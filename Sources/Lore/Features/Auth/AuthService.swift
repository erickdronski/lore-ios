import Foundation
import Observation

/// Supabase GoTrue session, as returned by `POST /auth/v1/token`.
struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct AuthUser: Codable {
    let id: String
    let email: String?
}

/// Email/password auth against Supabase GoTrue REST, no SDK.
///
/// P0 scope: session lives in memory only (relaunch = signed out). P1 adds
/// Keychain persistence + refresh-token rotation, the **anonymous sign-in**
/// device identity for the dive meter (docs/03 §5), and native Sign in with
/// Apple (docs/11-AUTH-SETUP.md §B.2).
@Observable
@MainActor
final class AuthService {
    private(set) var session: AuthSession?
    private(set) var profile: UserProfile?
    private(set) var isBusy = false
    var lastError: String?

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

    /// Best-effort server-side revoke, then clear local state either way.
    func signOut() async {
        if let token = session?.accessToken {
            var request = URLRequest(url: Config.authURL.appending(path: "logout"))
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        session = nil
        profile = nil
    }

    /// Loads the signed-in user's `user_profile` row (trust tier, points).
    func refreshProfile() async {
        guard let token = session?.accessToken else { return }
        profile = try? await LoreAPI.shared.profile(accessToken: token)
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
