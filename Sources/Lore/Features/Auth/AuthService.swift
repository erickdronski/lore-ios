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
