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
        case missingVisit

        var errorDescription: String? {
            switch self {
            case .badURL: return "Could not build the request URL."
            case .http(let status, let body): return "Server returned \(status): \(body)"
            case .decoding(let error): return "Could not read the response: \(error.localizedDescription)"
            case .encoding(let error): return "Could not build the request body: \(error.localizedDescription)"
            case .missingVisit: return "The journal entry no longer exists."
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

    /// The signed-in user's complete visit history with place details and their
    /// own note ("your lore"), newest first, for the Journal surface.
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
            URLQueryItem(name: "select", value: "place_id,visited_at,note,photos,is_public,place(name,emoji,city,kind)"),
            URLQueryItem(name: "order", value: "visited_at.desc,place_id.asc"),
        ]
        guard let url = components?.url else { throw TravelError.badURL }

        let pageSize = 200
        var lowerBound = 0
        var history: [VisitLogEntry] = []

        while true {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            apply(&request, accessToken: accessToken)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("items", forHTTPHeaderField: "Range-Unit")
            request.setValue(
                "\(lowerBound)-\(lowerBound + pageSize - 1)",
                forHTTPHeaderField: "Range"
            )

            let (data, response) = try await session.data(for: request)
            try ensureOK(response, data: data)
            let page: [VisitLogEntry]
            do {
                page = try JSONDecoder().decode([VisitLogEntry].self, from: data)
            } catch {
                throw TravelError.decoding(error)
            }
            history.append(contentsOf: page)
            if page.count < pageSize { return history }
            lowerBound += pageSize
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
        components?.queryItems = [
            URLQueryItem(name: "place_id", value: "eq.\(placeID)"),
            URLQueryItem(name: "select", value: "place_id"),
        ]
        guard let url = components?.url else { throw TravelError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        apply(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["note": note])
        } catch {
            throw TravelError.encoding(error)
        }

        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
        struct UpdatedVisit: Decodable {
            let placeID: String
            enum CodingKeys: String, CodingKey { case placeID = "place_id" }
        }
        let rows: [UpdatedVisit]
        do {
            rows = try JSONDecoder().decode([UpdatedVisit].self, from: data)
        } catch {
            throw TravelError.decoding(error)
        }
        guard rows.count == 1, rows[0].placeID == placeID else {
            throw TravelError.missingVisit
        }
    }

    /// Append one private photo path atomically. The RPC validates that the
    /// path belongs to the caller and place before updating the owner-scoped
    /// visit, so concurrent uploads cannot replace one another's paths.
    /// `POST /rest/v1/rpc/append_visit_photo`
    static func appendVisitPhoto(
        placeID: String,
        path: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws {
        let url = Config.restURL.appending(path: "rpc/append_visit_photo")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        apply(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "p_place_id": placeID,
                "p_path": path,
            ])
        } catch {
            throw TravelError.encoding(error)
        }
        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
    }

    /// Clear a stale public flag left by a pre-launch client. This deliberately
    /// exposes no inverse operation: journals are private in the shipping app.
    static func makeVisitPrivate(
        placeID: String,
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
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["is_public": false])
        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
    }

    // MARK: - Journal photo storage (private `journal-photos` bucket)

    /// Persist a private journal photo across Storage and the visit row. Storage
    /// cannot participate in the Postgres transaction, so a failed append is
    /// compensated by deleting the just-uploaded object before the error escapes.
    @discardableResult
    static func storeJournalPhoto(
        data imageData: Data,
        userID: String,
        placeID: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> String {
        let path = try await uploadJournalPhoto(
            data: imageData,
            userID: userID,
            placeID: placeID,
            accessToken: accessToken,
            session: session
        )
        do {
            try await appendVisitPhoto(
                placeID: placeID,
                path: path,
                accessToken: accessToken,
                session: session
            )
            return path
        } catch {
            // An unstructured cleanup task is not cancelled with the failed
            // caller, which gives the compensation request a chance to finish.
            _ = await Task.detached(priority: .utility) {
                try? await removeJournalPhoto(
                    path: path,
                    accessToken: accessToken,
                    session: session
                )
            }.value
            throw error
        }
    }

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

    /// Remove an exact object path through the Storage API. The live bucket's
    /// DELETE policy limits this operation to the caller's own uid folder.
    /// `DELETE /storage/v1/object/journal-photos` `{ "prefixes": [path] }`
    static func removeJournalPhoto(
        path: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws {
        let url = Config.storageURL.appending(path: "object/journal-photos")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        apply(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "prefixes": [path],
            ])
        } catch {
            throw TravelError.encoding(error)
        }
        let (data, response) = try await session.data(for: request)
        try ensureOK(response, data: data)
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
