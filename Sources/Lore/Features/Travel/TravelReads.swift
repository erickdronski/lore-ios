import Foundation

/// Additive PostgREST helpers the Travel feature needs but the shared `LoreAPI`
/// doesn't yet expose, kept in this module so the feature lands without editing
/// any existing file. Same posture as `LoreAPI`: anon `apikey` on every request,
/// a user bearer token where RLS needs `auth.uid()` (`visit`, `user_prefs`).
///
/// Two calls live here:
/// - `visits(accessToken:)`, hydrate the "Been here" set (`GET /visit`).
/// - `updateHiddenKinds(_:accessToken:)`, persist the map filter chips'
///   category toggles to `user_prefs.hidden_kinds` (`PATCH /user_prefs`).
///
/// When the shared client grows these (a natural addition to `LoreAPI`), the
/// call sites here can be repointed and this file deleted.
enum TravelReads {

    enum TravelError: LocalizedError {
        case badURL
        case http(status: Int, body: String)
        case decoding(Error)
        case encoding(Error)

        var errorDescription: String? {
            switch self {
            case .badURL: return "Could not build the request URL."
            case .http(let status, let body): return "Server returned \(status): \(body)"
            case .decoding(let error): return "Could not read the response: \(error.localizedDescription)"
            case .encoding(let error): return "Could not build the request body: \(error.localizedDescription)"
            }
        }
    }

    /// The signed-in user's own `visit` rows (RLS scopes to `auth.uid()`).
    /// `GET /rest/v1/visit?select=place_id,visited_at,source&order=visited_at.desc`
    static func visits(
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> [Visit] {
        var components = URLComponents(
            url: Config.restURL.appending(path: "visit"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "user_id,place_id,visited_at,source"),
            URLQueryItem(name: "order", value: "visited_at.desc"),
        ]
        guard let url = components?.url else { throw TravelError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        apply(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
        do {
            return try JSONDecoder().decode([Visit].self, from: data)
        } catch {
            throw TravelError.decoding(error)
        }
    }

    /// Persist just the `hidden_kinds` array (the map filter chips' one hard
    /// filter, 13 §3). A targeted `PATCH` so the chips never clobber the
    /// persona/interests the onboarding flow owns.
    /// `PATCH /rest/v1/user_prefs?user_id=eq.{userID}` `{ "hidden_kinds": [...] }`
    static func updateHiddenKinds(
        _ hiddenKinds: [String],
        userID: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws {
        var components = URLComponents(
            url: Config.restURL.appending(path: "user_prefs"),
            resolvingAgainstBaseURL: false
        )
        // RLS already limits the row to the caller; the explicit filter keeps
        // the PATCH from being a no-target update if a row doesn't exist yet.
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
        ]
        guard let url = components?.url else { throw TravelError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        apply(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["hidden_kinds": hiddenKinds]
            )
        } catch {
            throw TravelError.encoding(error)
        }

        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
    }

    // MARK: - Plumbing

    private static func apply(_ request: inout URLRequest, accessToken: String) {
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    private static func ensureOK(_ response: URLResponse, data: Data) throws {
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw TravelError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}
