import Foundation
import Observation

/// Supabase GoTrue session, as returned by `POST /auth/v1/token`.
struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let expiresAt: Int?
    let tokenType: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case tokenType = "token_type"
    }

    init(
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        expiresAt: Int? = nil,
        tokenType: String,
        user: AuthUser
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.user = user
    }

    func expires(within interval: TimeInterval) -> Bool {
        guard let expiresAt else {
            // Sessions saved before expiry tracking was added refresh once.
            return true
        }
        return Date(timeIntervalSince1970: TimeInterval(expiresAt))
            .timeIntervalSinceNow <= interval
    }

    func refreshDelay(leeway: TimeInterval) -> TimeInterval {
        guard let expiresAt else { return 0 }
        return max(
            0,
            Date(timeIntervalSince1970: TimeInterval(expiresAt))
                .timeIntervalSinceNow - leeway
        )
    }

    var isExpired: Bool { expires(within: 0) }
}

struct AuthUser: Codable {
    let id: String
    let email: String?
}

/// Email/password + OAuth auth against Supabase GoTrue REST, no SDK.
///
/// The session is **persisted to the Keychain** and restored on launch (with a
/// refresh-token exchange for a fresh access token), so relaunching keeps the
/// user signed in. Remaining P1: the **anonymous sign-in** device identity for
/// the dive meter (docs/03 §5).
@Observable
@MainActor
final class AuthService {
    private(set) var session: AuthSession? {
        didSet {
            if let session {
                SessionStore.save(session)
            } else {
                SessionStore.clear()
            }
            scheduleSessionRefresh()
        }
    }
    private(set) var profile: UserProfile?
    private(set) var isBusy = false
    /// True until the first launch restore attempt finishes, so signed-out UI
    /// doesn't flash before a persisted session is rehydrated.
    private(set) var isRestoring = true
    var lastError: String?
    var lastNotice: String?

    /// Access tokens normally last about an hour. Refresh two minutes early so
    /// stores that read the current token synchronously do not cross expiry.
    private static let refreshLeeway: TimeInterval = 2 * 60
    private static let initialRefreshRetry: TimeInterval = 5
    private static let maximumRefreshRetry: TimeInterval = 5 * 60
    @ObservationIgnored private var refreshTimerTask: Task<Void, Never>?
    @ObservationIgnored private var sessionRefreshTask: Task<Bool, Never>?

    /// Runs the `ASWebAuthenticationSession` for Supabase OAuth providers.
    private let webAuth = WebAuthCoordinator()
    /// The registered URL scheme (project.yml). `ASWebAuthenticationSession`
    /// intercepts this callback so Supabase's redirect lands back in the app.
    private static let oauthCallbackScheme = "lore"
    private static let oauthRedirect = "lore://auth-callback"

    var isSignedIn: Bool { session != nil }

    enum AuthError: LocalizedError {
        case http(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .http(_, let message): return message
            }
        }
    }

    /// `POST /auth/v1/token?grant_type=password` with the anon `apikey`.
    func signIn(email: String, password: String) async {
        isBusy = true
        lastError = nil
        lastNotice = nil
        defer { isBusy = false }
        do {
            var components = URLComponents(
                url: Config.authURL.appending(path: "token"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
            guard let url = components?.url else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                ["email": email, "password": password]
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                let message = Self.errorMessage(from: data)
                    ?? "Sign-in failed (\(http.statusCode))."
                throw AuthError.http(status: http.statusCode, message: message)
            }
            let newSession = try JSONDecoder().decode(AuthSession.self, from: data)
            session = newSession
            await refreshProfile()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Create a new account, `POST /auth/v1/signup` with the anon `apikey`.
    /// If email confirmation is off the response is a full session and we sign
    /// in immediately; if it's on there is no token yet, so we tell the user to
    /// confirm. Accounts are required to buy Lore+ or contribute.
    func signUp(email: String, password: String) async {
        isBusy = true
        lastError = nil
        lastNotice = nil
        defer { isBusy = false }
        do {
            var request = URLRequest(url: Config.authURL.appending(path: "signup"))
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                let message = Self.errorMessage(from: data)
                    ?? "Couldn't create your account (\(http.statusCode))."
                throw AuthError.http(status: http.statusCode, message: message)
            }
            if let newSession = try? JSONDecoder().decode(AuthSession.self, from: data),
               !newSession.accessToken.isEmpty {
                session = newSession
                await refreshProfile()
            } else {
                lastNotice = "Account created. Check your email to confirm, then sign in."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Send a password-reset email that finishes on Lore's secure web reset
    /// screen. This works from any mail client without relying on an app deep
    /// link or a locally stored PKCE verifier.
    func sendPasswordReset(email: String) async {
        isBusy = true
        lastError = nil
        lastNotice = nil
        defer { isBusy = false }
        do {
            var resetComponents = URLComponents(
                url: Config.webURL.appending(path: "auth"),
                resolvingAgainstBaseURL: false
            )
            resetComponents?.queryItems = [URLQueryItem(name: "mode", value: "reset")]
            guard let resetURL = resetComponents?.url else {
                throw AuthError.http(status: 0, message: "Couldn't create the reset link.")
            }

            var recoverComponents = URLComponents(
                url: Config.authURL.appending(path: "recover"),
                resolvingAgainstBaseURL: false
            )
            recoverComponents?.queryItems = [
                URLQueryItem(name: "redirect_to", value: resetURL.absoluteString)
            ]
            guard let recoverURL = recoverComponents?.url else {
                throw AuthError.http(status: 0, message: "Couldn't create the reset request.")
            }

            var request = URLRequest(url: recoverURL)
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["email": email])

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw AuthError.http(
                    status: http.statusCode,
                    message: Self.errorMessage(from: data) ?? "Couldn't send the reset email."
                )
            }
            lastNotice = "If that email has an account, a reset link is on its way. Open it to choose a new password."
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Best-effort server-side revoke, then clear local state either way.
    func signOut() async {
        if let token = await validAccessToken() {
            var request = URLRequest(url: Config.authURL.appending(path: "logout"))
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        session = nil
        profile = nil
    }

    /// Permanently delete the account and all its data (App Store Guideline
    /// 5.1.1(v)). Calls the service-role `delete-account` edge function with the
    /// user's OWN token; the function verifies it and deletes only that uid's
    /// auth user, rows, and journal photos. On success we clear the local
    /// session so the app returns to signed-out. Returns true on success.
    func deleteAccount() async -> Bool {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            guard let token = await validAccessToken() else {
                lastError = "Your session has expired. Sign in and try again."
                return false
            }

            var response = try await performDeleteAccount(accessToken: token)
            if response.statusCode == 401,
               let refreshedToken = await validAccessToken(forceRefresh: true) {
                response = try await performDeleteAccount(accessToken: refreshedToken)
            }

            guard response.statusCode == 200 else {
                lastError = "Couldn't delete your account. Please try again."
                return false
            }
            session = nil
            profile = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func performDeleteAccount(accessToken: String) async throws -> HTTPURLResponse {
        var request = URLRequest(url: Config.functionsURL.appending(path: "delete-account"))
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.http(status: 0, message: "The server returned an invalid response.")
        }
        return http
    }

    /// Restore a persisted session on launch: load it from the Keychain, show
    /// signed-in immediately, then exchange the refresh token for a fresh access
    /// token and hydrate the profile. If nothing is stored (or the refresh
    /// token is dead), we end up signed out cleanly. Idempotent, no-ops if
    /// already signed in.
    func restore() async {
        defer { isRestoring = false }
        guard session == nil, let saved = SessionStore.load() else { return }
        session = saved
        _ = await refreshSession()
        await refreshProfile()
    }

    /// Exchange the current refresh token for a fresh GoTrue session
    /// (`grant_type=refresh_token`). On an invalid/expired refresh token we sign
    /// out; on a network blip we keep the restored session so a later call can
    /// retry rather than bouncing the user to sign-in.
    private func refreshSession() async -> Bool {
        if let sessionRefreshTask {
            return await sessionRefreshTask.value
        }
        guard let refreshToken = session?.refreshToken else { return false }

        let task = Task { [weak self] in
            guard let self else { return false }
            return await self.performSessionRefresh(refreshToken: refreshToken)
        }
        sessionRefreshTask = task
        let refreshed = await task.value
        sessionRefreshTask = nil
        return refreshed
    }

    private func performSessionRefresh(refreshToken: String) async -> Bool {
        do {
            var components = URLComponents(
                url: Config.authURL.appending(path: "token"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
            guard let url = components?.url else { return false }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // Only an auth verdict kills the session. A 5xx or transient
                // platform failure keeps it so foregrounding can retry.
                if [400, 401, 403].contains(http.statusCode) {
                    session = nil
                }
                return false
            }
            session = try JSONDecoder().decode(AuthSession.self, from: data)
            return true
        } catch {
            // Transient failure: keep the session and retry on foreground/401.
            return false
        }
    }

    /// Return a token that is not near expiry. `forceRefresh` is used for the
    /// single retry after an authenticated endpoint returns 401.
    func validAccessToken(forceRefresh: Bool = false) async -> String? {
        guard let current = session else { return nil }
        if forceRefresh || current.expires(within: Self.refreshLeeway) {
            let refreshed = await refreshSession()
            // A forced refresh follows a server auth rejection. Reusing the
            // same token after that refresh failed would only repeat the 401.
            if forceRefresh && !refreshed { return nil }
        }
        guard let candidate = session, !candidate.isExpired else { return nil }
        return candidate.accessToken
    }

    /// Called when the app becomes active; a suspended refresh timer may have
    /// missed its deadline while iOS froze the process.
    func refreshIfNeeded() async {
        guard session?.expires(within: Self.refreshLeeway) == true else { return }
        _ = await refreshSession()
    }

    private func scheduleSessionRefresh() {
        refreshTimerTask?.cancel()
        refreshTimerTask = nil
        guard let session else { return }

        let delay = session.refreshDelay(leeway: Self.refreshLeeway)
        refreshTimerTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            var retryDelay = Self.initialRefreshRetry
            while !Task.isCancelled {
                guard let self else { return }
                let refreshed = await self.refreshSession()
                if refreshed || self.session == nil { return }

                // A transient network/platform failure must not strand the
                // session after this one timer fires. Retry quietly with a
                // bounded backoff; foreground calls still coalesce into the
                // same refresh task.
                do {
                    try await Task.sleep(for: .seconds(retryDelay))
                } catch {
                    return
                }
                retryDelay = min(retryDelay * 2, Self.maximumRefreshRetry)
            }
        }
    }

    /// Loads the signed-in user's `user_profile` row (trust tier, points).
    func refreshProfile() async {
        guard let token = await validAccessToken() else { return }
        do {
            profile = try await LoreAPI.shared.profile(accessToken: token)
        } catch LoreAPI.APIError.http(let status, _) where status == 401 {
            guard let refreshedToken = await validAccessToken(forceRefresh: true) else { return }
            profile = try? await LoreAPI.shared.profile(accessToken: refreshedToken)
        } catch {
            // Profile is supplemental; keep the rest of the signed-in app live.
        }
    }

    /// Native **Sign in with Apple**, exchange the Apple identity token for a
    /// Supabase session (docs/11-AUTH-SETUP.md §B.2, docs/16 §2).
    ///
    /// This is the REST counterpart of the SDK's `signInWithIdToken`:
    /// `POST /auth/v1/token?grant_type=id_token` with
    /// `{ provider: "apple", id_token: <JWT>, nonce: <rawNonce> }`. Supabase
    /// verifies the token signature and that its embedded nonce hash matches the
    /// raw nonce we pass, then mints a GoTrue session.
    ///
    /// The caller (`SignInView`) obtains the credential from
    /// `AppleSignInCoordinator`. Apple returns name/email only on the *first*
    /// authorization, so `fullName`/`email` are passed here to seed the profile.
    ///
    /// **Server prerequisites (docs/11 §B.1, not wired in this repo):** the
    /// bundle id `com.erickdronski.lore` must be in the Supabase Apple provider's Client
    /// IDs list, and the shared `.p8` key + Services ID configured. Because the
    /// web OAuth path already stood those up, the native path needs **no new
    /// Supabase console work** (docs/16 §2).
    ///
    /// TODO(P1/server): on first authorization, upsert `fullName` + `email` to
    /// `user_profile` immediately, Apple never sends them again (docs/16 §2).
    /// This wants a `user_profile` write path (currently profile is read-only in
    /// `LoreAPI`); scaffolded here as the seed values are carried through.
    func signInWithApple(
        idToken: String,
        rawNonce: String,
        fullName: PersonNameComponents? = nil,
        email: String? = nil
    ) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            var components = URLComponents(
                url: Config.authURL.appending(path: "token"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
            guard let url = components?.url else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                ["provider": "apple", "id_token": idToken, "nonce": rawNonce]
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                let message = Self.errorMessage(from: data)
                    ?? "Sign in with Apple failed (\(http.statusCode))."
                throw AuthError.http(status: http.statusCode, message: message)
            }
            let newSession = try JSONDecoder().decode(AuthSession.self, from: data)
            session = newSession
            // Seed the name/email Apple only ever sends once. TODO(P1/server):
            // persist to `user_profile` here once a write path exists, carried
            // through so the wiring is ready.
            pendingAppleName = fullName
            pendingAppleEmail = email
            await refreshProfile()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - OAuth providers (Google, and later Facebook / Discord)

    /// Sign in with Google via Supabase GoTrue's OAuth web flow.
    func signInWithGoogle() async { await signInWithOAuth(provider: "google") }

    /// Generic Supabase OAuth: open `/auth/v1/authorize?provider=…` in an
    /// `ASWebAuthenticationSession`, let Supabase run the provider handshake,
    /// then read the GoTrue tokens Supabase returns in the callback fragment and
    /// hydrate the session (docs/11-AUTH-SETUP.md §B, docs/16 §2).
    ///
    /// **Server prerequisite:** the provider must be enabled in the Supabase
    /// dashboard (client id + secret) and `lore://auth-callback` added to the
    /// Auth → URL Configuration redirect allowlist.
    func signInWithOAuth(provider: String) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            var components = URLComponents(
                url: Config.authURL.appending(path: "authorize"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "provider", value: provider),
                URLQueryItem(name: "redirect_to", value: Self.oauthRedirect),
            ]
            guard let authorizeURL = components?.url else { return }

            let callback = try await webAuth.authenticate(
                url: authorizeURL,
                callbackScheme: Self.oauthCallbackScheme
            )

            guard let tokens = Self.tokens(from: callback) else {
                // Supabase can bounce an error back in the fragment instead.
                lastError = Self.callbackError(from: callback)
                    ?? "\(provider.capitalized) sign-in didn't complete. Please try again."
                return
            }

            let user = try await fetchUser(accessToken: tokens.access)
            session = AuthSession(
                accessToken: tokens.access,
                refreshToken: tokens.refresh,
                expiresIn: tokens.expiresIn,
                expiresAt: Int(Date().timeIntervalSince1970) + tokens.expiresIn,
                tokenType: tokens.tokenType,
                user: user
            )
            await refreshProfile()
        } catch is WebAuthCoordinator.WebAuthError {
            // User dismissed the sheet, silent (not an error to surface).
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// GET `/auth/v1/user` to resolve the account behind an OAuth access token
    /// (the OAuth callback carries only token strings, not the user object).
    private func fetchUser(accessToken: String) async throws -> AuthUser {
        var request = URLRequest(url: Config.authURL.appending(path: "user"))
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AuthError.http(
                status: http.statusCode,
                message: Self.errorMessage(from: data) ?? "Couldn't load your account."
            )
        }
        return try JSONDecoder().decode(AuthUser.self, from: data)
    }

    /// Parse the GoTrue tokens Supabase returns in the callback URL fragment
    /// (`…#access_token=…&refresh_token=…&expires_in=…&token_type=bearer`).
    private static func tokens(
        from url: URL
    ) -> (access: String, refresh: String, expiresIn: Int, tokenType: String)? {
        let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
            ?? url.fragment
        guard let fragment else { return nil }
        let pairs = fragment.split(separator: "&").reduce(into: [String: String]()) { dict, pair in
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { dict[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
        }
        guard let access = pairs["access_token"], let refresh = pairs["refresh_token"] else {
            return nil
        }
        return (access, refresh, Int(pairs["expires_in"] ?? "3600") ?? 3600, pairs["token_type"] ?? "bearer")
    }

    /// A human error Supabase may put in the callback fragment/query instead of tokens.
    private static func callbackError(from url: URL) -> String? {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let haystack = (comps?.fragment ?? "") + "&" + (comps?.query ?? "")
        for pair in haystack.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == "error_description" {
                return kv[1].removingPercentEncoding?.replacingOccurrences(of: "+", with: " ")
            }
        }
        return nil
    }

    /// First-authorization Apple name, stashed until a `user_profile` write path
    /// exists to persist it (docs/16 §2, Apple sends it only once).
    /// TODO(P1/server): flush to `user_profile` and clear.
    private(set) var pendingAppleName: PersonNameComponents?
    /// First-authorization Apple email (possibly private-relay), same lifecycle.
    private(set) var pendingAppleEmail: String?

    private static func errorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dict = object as? [String: Any]
        else { return nil }
        return (dict["error_description"] as? String)
            ?? (dict["msg"] as? String)
            ?? (dict["message"] as? String)
    }
}
