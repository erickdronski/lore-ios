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
                if !SessionStore.save(session) {
                    lastNotice = "You're signed in for now, but Lore couldn't securely remember this session."
                }
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
    @ObservationIgnored private var sessionRefreshID: UUID?
    @ObservationIgnored private let urlSession: URLSession

    /// Runs the `ASWebAuthenticationSession` for Supabase OAuth providers.
    @ObservationIgnored private let webAuth: WebAuthCoordinator
    /// The registered URL scheme (project.yml). `ASWebAuthenticationSession`
    /// intercepts this callback so Supabase's redirect lands back in the app.
    private static let oauthCallbackScheme = "lore"
    private static let oauthRedirect = "lore://auth-callback"
    private static let oauthCallbackHost = "auth-callback"
    private static let supportedOAuthProviders: Set<String> = ["google", "facebook"]
    private static let requestTimeout: TimeInterval = 30

    var isSignedIn: Bool { session != nil }

    init(
        urlSession: URLSession = .shared,
        webAuth: WebAuthCoordinator? = nil
    ) {
        self.urlSession = urlSession
        self.webAuth = webAuth ?? WebAuthCoordinator()
    }

    enum AuthError: LocalizedError {
        case http(status: Int, message: String)
        case invalidOAuthCallback(String)

        var errorDescription: String? {
            switch self {
            case .http(_, let message): return message
            case .invalidOAuthCallback(let message): return message
            }
        }
    }

    static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidEmail(_ value: String) -> Bool {
        let email = normalizedEmail(value)
        guard email.count <= 254,
              let at = email.lastIndex(of: "@"),
              at != email.startIndex else { return false }
        let domain = email[email.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    static func isValidNewPassword(_ value: String) -> Bool {
        value.count >= 8 && value.count <= 128
    }

    static func allowsAccountCreatingAuthentication(confirmedMinimumAge: Bool) -> Bool {
        confirmedMinimumAge
    }

    private func requireAccountCreationConsent(_ confirmedMinimumAge: Bool) -> Bool {
        guard Self.allowsAccountCreatingAuthentication(
            confirmedMinimumAge: confirmedMinimumAge
        ) else {
            lastError = "Confirm that you are 13 or older before continuing with social sign-in."
            return false
        }
        return true
    }

    /// `POST /auth/v1/token?grant_type=password` with the anon `apikey`.
    func signIn(email: String, password: String) async {
        lastError = nil
        lastNotice = nil
        let email = Self.normalizedEmail(email)
        guard Self.isValidEmail(email) else {
            lastError = "Enter a valid email address."
            return
        }
        guard !password.isEmpty else {
            lastError = "Enter your password."
            return
        }
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
            guard let url = components?.url else {
                throw AuthError.http(status: 0, message: "Lore couldn't create the secure sign-in request.")
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = Self.requestTimeout
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                ["email": email, "password": password]
            )

            let (data, response) = try await urlSession.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                let message = Self.errorMessage(from: data)
                    ?? "Sign-in failed (\(http.statusCode))."
                throw AuthError.http(status: http.statusCode, message: message)
            }
            let newSession = try JSONDecoder().decode(AuthSession.self, from: data)
            await completeAuthentication(with: newSession)
        } catch {
            recordFailure(error)
        }
    }

    /// Create a new account, `POST /auth/v1/signup` with the anon `apikey`.
    /// If email confirmation is off the response is a full session and we sign
    /// in immediately; if it's on there is no token yet, so we tell the user to
    /// confirm. Accounts are required to buy Lore+ or contribute.
    func signUp(email: String, password: String) async {
        lastError = nil
        lastNotice = nil
        let email = Self.normalizedEmail(email)
        guard Self.isValidEmail(email) else {
            lastError = "Enter a valid email address."
            return
        }
        guard Self.isValidNewPassword(password) else {
            lastError = "Create a password with 8 to 128 characters."
            return
        }
        isBusy = true
        lastError = nil
        lastNotice = nil
        defer { isBusy = false }
        do {
            var request = URLRequest(url: Config.authURL.appending(path: "signup"))
            request.timeoutInterval = Self.requestTimeout
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

            let (data, response) = try await urlSession.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                let message = Self.errorMessage(from: data)
                    ?? "Couldn't create your account (\(http.statusCode))."
                throw AuthError.http(status: http.statusCode, message: message)
            }
            if let newSession = try? JSONDecoder().decode(AuthSession.self, from: data),
               !newSession.accessToken.isEmpty {
                await completeAuthentication(with: newSession)
            } else {
                lastNotice = "Account created. Check your email to confirm, then sign in."
            }
        } catch {
            recordFailure(error)
        }
    }

    /// Send a password-reset email that finishes on Lore's secure web reset
    /// screen. This works from any mail client without relying on an app deep
    /// link or a locally stored PKCE verifier.
    func sendPasswordReset(email: String) async {
        lastError = nil
        lastNotice = nil
        let email = Self.normalizedEmail(email)
        guard Self.isValidEmail(email) else {
            lastError = "Enter the email address for your Lore account first."
            return
        }
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
            request.timeoutInterval = Self.requestTimeout
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["email": email])

            let (data, response) = try await urlSession.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw AuthError.http(
                    status: http.statusCode,
                    message: Self.errorMessage(from: data) ?? "Couldn't send the reset email."
                )
            }
            lastNotice = "If that email has an account, a reset link is on its way. Open it to choose a new password."
        } catch {
            recordFailure(error)
        }
    }

    /// Best-effort server-side revoke, then clear local state either way.
    func signOut() async {
        lastError = nil
        lastNotice = nil
        let token = session?.accessToken
        clearLocalSession()

        if let token {
            var request = URLRequest(url: Config.authURL.appending(path: "logout"))
            request.timeoutInterval = 10
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await urlSession.data(for: request)
        }
    }

    private func clearLocalSession() {
        refreshTimerTask?.cancel()
        refreshTimerTask = nil
        sessionRefreshTask?.cancel()
        sessionRefreshTask = nil
        sessionRefreshID = nil
        webAuth.cancel()
        session = nil
        profile = nil
        pendingAppleName = nil
        pendingAppleEmail = nil
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
            let deletedUserID = session?.user.id
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
            clearLocalSession()
            if let deletedUserID {
                AppleProfileSeedStore.clear(userID: deletedUserID)
            }
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    private func performDeleteAccount(accessToken: String) async throws -> HTTPURLResponse {
        var request = URLRequest(url: Config.functionsURL.appending(path: "delete-account"))
        request.timeoutInterval = Self.requestTimeout
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (_, response) = try await urlSession.data(for: request)
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
        let refreshed = await refreshSession()
        if refreshed || session?.isExpired == false {
            await completePostAuthenticationSetup()
        }
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
        let refreshID = UUID()
        sessionRefreshTask = task
        sessionRefreshID = refreshID
        let refreshed = await task.value
        if sessionRefreshID == refreshID {
            sessionRefreshTask = nil
            sessionRefreshID = nil
        }
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
            request.timeoutInterval = Self.requestTimeout
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

            let (data, response) = try await urlSession.data(for: request)
            guard session?.refreshToken == refreshToken else { return false }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // Only an auth verdict kills the session. A 5xx or transient
                // platform failure keeps it so foregrounding can retry.
                if [400, 401, 403].contains(http.statusCode) {
                    clearLocalSession()
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
        if session?.expires(within: Self.refreshLeeway) == true {
            _ = await refreshSession()
        }
        guard let current = session, !current.isExpired else { return }
        await synchronizePendingOnboarding(for: current)
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
    /// The one-time values are persisted immediately in
    /// `AppleProfileSeedStore`. The server profile writer remains an external
    /// dependency; until it exists, Lore does not risk losing them on relaunch.
    func signInWithApple(
        idToken: String,
        rawNonce: String,
        fullName: PersonNameComponents? = nil,
        email: String? = nil,
        confirmedMinimumAge: Bool
    ) async {
        lastError = nil
        lastNotice = nil
        guard requireAccountCreationConsent(confirmedMinimumAge) else { return }
        guard !idToken.isEmpty, !rawNonce.isEmpty else {
            lastError = "Apple sign-in returned incomplete credentials. Please try again."
            return
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            var components = URLComponents(
                url: Config.authURL.appending(path: "token"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
            guard let url = components?.url else {
                throw AuthError.http(status: 0, message: "Lore couldn't create the Apple sign-in request.")
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = Self.requestTimeout
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                ["provider": "apple", "id_token": idToken, "nonce": rawNonce]
            )

            let (data, response) = try await urlSession.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                let message = Self.errorMessage(from: data)
                    ?? "Sign in with Apple failed (\(http.statusCode))."
                throw AuthError.http(status: http.statusCode, message: message)
            }
            let newSession = try JSONDecoder().decode(AuthSession.self, from: data)
            pendingAppleName = fullName
            pendingAppleEmail = email
            if let seed = AppleProfileSeed.make(
                userID: newSession.user.id,
                fullName: fullName,
                email: email
            ), !AppleProfileSeedStore.save(seed) {
                lastNotice = "You're signed in, but Lore couldn't securely save Apple's one-time profile details."
            }
            await completeAuthentication(with: newSession)
        } catch {
            recordFailure(error)
        }
    }

    // MARK: - OAuth providers (Google, and later Facebook / Discord)

    /// Sign in with Google via Supabase GoTrue's OAuth web flow.
    func signInWithGoogle(confirmedMinimumAge: Bool) async {
        await signInWithOAuth(
            provider: "google",
            confirmedMinimumAge: confirmedMinimumAge
        )
    }

    /// Generic Supabase OAuth: open `/auth/v1/authorize?provider=…` in an
    /// `ASWebAuthenticationSession`, let Supabase run the provider handshake,
    /// then read the GoTrue tokens Supabase returns in the callback fragment and
    /// hydrate the session (docs/11-AUTH-SETUP.md §B, docs/16 §2).
    ///
    /// **Server prerequisite:** the provider must be enabled in the Supabase
    /// dashboard (client id + secret) and `lore://auth-callback` added to the
    /// Auth → URL Configuration redirect allowlist.
    func signInWithOAuth(provider: String, confirmedMinimumAge: Bool) async {
        lastError = nil
        lastNotice = nil
        guard requireAccountCreationConsent(confirmedMinimumAge) else { return }
        let provider = provider.lowercased()
        guard Self.supportedOAuthProviders.contains(provider) else {
            lastError = "That sign-in provider isn't available in Lore."
            return
        }
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
            guard let authorizeURL = components?.url else {
                throw AuthError.http(status: 0, message: "Lore couldn't create the secure provider request.")
            }

            let callback = try await webAuth.authenticate(
                url: authorizeURL,
                callbackScheme: Self.oauthCallbackScheme
            )
            let tokens = try Self.oauthTokens(from: callback)

            let user = try await fetchUser(accessToken: tokens.access)
            let newSession = AuthSession(
                accessToken: tokens.access,
                refreshToken: tokens.refresh,
                expiresIn: tokens.expiresIn,
                expiresAt: Int(Date().timeIntervalSince1970) + tokens.expiresIn,
                tokenType: tokens.tokenType,
                user: user
            )
            await completeAuthentication(with: newSession)
        } catch WebAuthCoordinator.WebAuthError.cancelled {
            // Backing out is a successful cancellation, not a failed sign-in.
        } catch {
            recordFailure(error)
        }
    }

    /// GET `/auth/v1/user` to resolve the account behind an OAuth access token
    /// (the OAuth callback carries only token strings, not the user object).
    private func fetchUser(accessToken: String) async throws -> AuthUser {
        var request = URLRequest(url: Config.authURL.appending(path: "user"))
        request.timeoutInterval = Self.requestTimeout
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
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
    struct OAuthTokens: Equatable {
        let access: String
        let refresh: String
        let expiresIn: Int
        let tokenType: String
    }

    static func oauthTokens(from url: URL) throws -> OAuthTokens {
        guard url.scheme?.lowercased() == oauthCallbackScheme,
              url.host?.lowercased() == oauthCallbackHost,
              url.user == nil,
              url.password == nil else {
            throw AuthError.invalidOAuthCallback(
                "The sign-in provider returned to an unexpected address. Please try again."
            )
        }
        if let callbackError = callbackError(from: url) {
            throw AuthError.invalidOAuthCallback(callbackError)
        }
        let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
            ?? url.fragment
        guard let fragment else {
            throw AuthError.invalidOAuthCallback("Sign-in didn't return a secure session. Please try again.")
        }
        var pairs: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, pairs[kv[0]] == nil else {
                throw AuthError.invalidOAuthCallback("Sign-in returned an invalid session. Please try again.")
            }
            pairs[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
        }
        guard let access = pairs["access_token"], !access.isEmpty,
              let refresh = pairs["refresh_token"], !refresh.isEmpty,
              let expiresIn = Int(pairs["expires_in"] ?? ""),
              (1...604_800).contains(expiresIn),
              let tokenType = pairs["token_type"],
              tokenType.caseInsensitiveCompare("bearer") == .orderedSame else {
            throw AuthError.invalidOAuthCallback("Sign-in returned an invalid session. Please try again.")
        }
        return OAuthTokens(access: access, refresh: refresh, expiresIn: expiresIn, tokenType: "bearer")
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

    private func completeAuthentication(with newSession: AuthSession) async {
        session = newSession
        await completePostAuthenticationSetup()
    }

    private func completePostAuthenticationSetup() async {
        guard let current = session, !current.isExpired else { return }
        await synchronizePendingOnboarding(for: current)
        await refreshProfile()
    }

    private func synchronizePendingOnboarding(for current: AuthSession) async {
        guard OnboardingPrefsWriter.pendingSelection() != nil else { return }
        do {
            try await OnboardingPrefsWriter.flushPending(
                userID: current.user.id,
                accessToken: current.accessToken
            )
        } catch {
            // Authentication succeeded. Keep the durable pending selection and
            // retry on the next restore/foreground rather than failing sign-in.
            lastNotice = "You're signed in. Your travel lens is saved here and will sync when the connection returns."
        }
    }

    private func recordFailure(_ error: Error) {
        guard let message = Self.userFacingMessage(for: error) else { return }
        lastError = message
    }

    static func userFacingMessage(for error: Error) -> String? {
        if error is CancellationError { return nil }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return nil
            case .notConnectedToInternet:
                return "You're offline. Reconnect and try again."
            case .timedOut, .networkConnectionLost:
                return "The connection was interrupted. Please try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Lore couldn't reach the sign-in service. Please try again shortly."
            default:
                return "Lore couldn't complete that secure sign-in. Please try again."
            }
        }
        if error is DecodingError {
            return "The sign-in service returned an unreadable response. Please try again."
        }
        return error.localizedDescription
    }

    /// First-authorization Apple values for immediate UI use. The durable copy
    /// lives in `AppleProfileSeedStore` until the profile endpoint consumes it.
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
