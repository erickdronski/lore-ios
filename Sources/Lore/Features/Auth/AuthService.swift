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

/// Email/password auth against Supabase GoTrue REST — no SDK.
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

    // TODO(P1): Sign in with Apple — docs/11-AUTH-SETUP.md §B.2. Present
    // ASAuthorizationController with a hashed nonce, take the returned
    // identityToken, and exchange it at POST /auth/v1/token?grant_type=id_token
    // (provider=apple, nonce=rawNonce). Dashboard prerequisite: bundle id
    // app.lore.lore in the Apple provider's Client IDs list (§B.1 step 4).
    // Anonymous-session users upgrade in place — same auth.uid().

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
