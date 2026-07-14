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

    /// The signed-in user's visit history with the place details + their own
    /// note ("your lore"), newest first, for the Journal surface.
    /// `GET /rest/v1/visit?select=place_id,visited_at,note,place(name,emoji,city,kind)&order=visited_at.desc`
    static func visitHistory(
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> [VisitLogEntry] {
        var components = URLComponents(
            url: Config.restURL.appending(path: "visit"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "place_id,visited_at,note,photos,place(name,emoji,city,kind)"),
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
            return try JSONDecoder().decode([VisitLogEntry].self, from: data)
        } catch {
            throw TravelError.decoding(error)
        }
    }

    /// Save the user's own note ("lore") on a visited place. RLS scopes the rows
    /// to the caller, so a filter on `place_id` updates only their own visit(s).
    /// `PATCH /rest/v1/visit?place_id=eq.{placeID}` `{ "note": "..." }`
    static func updateVisitNote(
        placeID: String,
        note: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws {
        var components = URLComponents(
            url: Config.restURL.appending(path: "visit"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "place_id", value: "eq.\(placeID)")]
        guard let url = components?.url else { throw TravelError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        apply(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["note": note])

        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
    }

    /// Save the user's photo object-paths on a visited place.
    /// `PATCH /rest/v1/visit?place_id=eq.{placeID}` `{ "photos": [...] }`
    static func updateVisitPhotos(
        placeID: String,
        photos: [String],
        accessToken: String,
        session: URLSession = .shared
    ) async throws {
        var components = URLComponents(url: Config.restURL.appending(path: "visit"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "place_id", value: "eq.\(placeID)")]
        guard let url = components?.url else { throw TravelError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        apply(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["photos": photos])
        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
    }

    // MARK: - Journal photo storage (private `journal-photos` bucket)

    /// Upload image bytes to the user's own folder and return the object PATH
    /// (`{userID}/{placeID}/{uuid}.jpg`). RLS lets a user write only under their
    /// own uid folder. `POST /storage/v1/object/journal-photos/{path}`
    static func uploadJournalPhoto(
        data imageData: Data,
        userID: String,
        placeID: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> String {
        let path = "\(userID)/\(placeID)/\(UUID().uuidString).jpg"
        let url = Config.storageURL.appending(path: "object/journal-photos/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        apply(&request, accessToken: accessToken)
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("3600", forHTTPHeaderField: "Cache-Control")
        request.httpBody = imageData
        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
        return path
    }

    /// A short-lived signed URL to display a private journal photo.
    /// `POST /storage/v1/object/sign/journal-photos/{path}` `{ "expiresIn": 3600 }`
    static func signedJournalPhotoURL(
        path: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> URL {
        let url = Config.storageURL.appending(path: "object/sign/journal-photos/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        apply(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["expiresIn": 3600])
        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
        struct Signed: Decodable { let signedURL: String }
        let signed = try JSONDecoder().decode(Signed.self, from: data)
        // The response is a path relative to the storage base ("/object/sign/...").
        let relative = signed.signedURL.hasPrefix("/") ? String(signed.signedURL.dropFirst()) : signed.signedURL
        guard let full = URL(string: Config.storageURL.absoluteString + "/" + relative) else { throw TravelError.badURL }
        return full
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
