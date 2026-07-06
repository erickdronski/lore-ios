import Foundation

/// Thin async PostgREST client over `URLSession`, no external dependencies
/// (docs/03 §2 names the Supabase Swift client for ContentKit at P1; at P0 the
/// read surface is anonymous GETs + a handful of RPCs and a hand-rolled client
/// keeps the scaffold dependency-free).
///
/// Every request carries the anon key as `apikey`. Reads authorize with the
/// anon key by default; authed methods take a user access token so RLS
/// resolves `auth.uid()` (required for `user_prefs`, `visit`, `entitlements`,
/// `user_achievement`, and `user_profile`).
struct LoreAPI {
    static let shared = LoreAPI()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    enum APIError: LocalizedError {
        case badURL
        case http(status: Int, body: String)
        case decoding(Error)
        case encoding(Error)

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "Could not build the request URL."
            case .http(let status, let body):
                return "Server returned \(status): \(body)"
            case .decoding(let error):
                return "Could not read the server response: \(error.localizedDescription)"
            case .encoding(let error):
                return "Could not build the request body: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Public read surface

    /// All live cities, in curated order.
    /// `GET /rest/v1/city?status=eq.live&order=sort`
    func cities() async throws -> [City] {
        try await get(
            "city",
            query: [
                URLQueryItem(name: "status", value: "eq.live"),
                URLQueryItem(name: "order", value: "sort.asc"),
            ]
        )
    }

    /// All published places for a city, from the `place_explore` view.
    /// `GET /rest/v1/place_explore?city=eq.{city}&order=name.asc`
    func places(city: String = Config.defaultCity) async throws -> [Place] {
        try await get(
            "place_explore",
            query: [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "order", value: "name.asc"),
            ]
        )
    }

    /// The cached deep-dive dossier for one place, if synthesized.
    /// `GET /rest/v1/dive?place_id=eq.{id}&limit=1`
    func dive(placeID: String) async throws -> Dive? {
        let rows: [Dive] = try await get(
            "dive",
            query: [
                URLQueryItem(name: "place_id", value: "eq.\(placeID)"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first
    }

    /// The "meanwhile-nearby" story rows for a city. Distance filtering is done
    /// client-side against the user's pose (12 §3.1).
    /// `GET /rest/v1/story?city=eq.{city}&order=year.asc`
    func stories(city: String = Config.defaultCity) async throws -> [Story] {
        try await get(
            "story",
            query: [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "order", value: "year.asc"),
            ]
        )
    }

    /// The culture shelf (slang, sayings, quotes, people) for a city.
    /// `GET /rest/v1/city_culture?city=eq.{city}&order=sort`
    func culture(city: String = Config.defaultCity) async throws -> [CityCulture] {
        try await get(
            "city_culture",
            query: [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "order", value: "sort.asc"),
            ]
        )
    }

    /// Published tours for a city, stops embedded and ordered by `seq`.
    /// `GET /rest/v1/tour?city=eq.{city}&select=*,tour_stop(*)&order=title.asc`
    func tours(city: String = Config.defaultCity) async throws -> [Tour] {
        try await get(
            "tour",
            query: [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "select", value: "*,tour_stop(*)"),
                URLQueryItem(name: "order", value: "title.asc"),
            ]
        )
    }

    /// The catalog of earnable achievements (definitions only), in sort order.
    /// `GET /rest/v1/achievement?order=sort.asc`
    func achievements() async throws -> [Achievement] {
        try await get(
            "achievement",
            query: [URLQueryItem(name: "order", value: "sort.asc")]
        )
    }

    /// The raw provenance rows behind a dossier (verified facts only surface
    /// in UI provenance chips; the narrative itself comes from `dive`).
    /// `GET /rest/v1/fact?place_id=eq.{id}&order=key.asc`
    func facts(placeID: String) async throws -> [Fact] {
        try await get(
            "fact",
            query: [
                URLQueryItem(name: "place_id", value: "eq.\(placeID)"),
                URLQueryItem(name: "order", value: "key.asc"),
            ]
        )
    }

    /// Unified search across places, stories, tours, culture, and cities.
    /// `POST /rest/v1/rpc/search_lore { "q": q, "max_results": maxResults }`
    /// Results arrive ranked, highest `score` first.
    func search(_ q: String, maxResults: Int = 20) async throws -> [SearchResult] {
        try await rpc(
            "search_lore",
            body: ["q": q, "max_results": maxResults]
        )
    }

    // MARK: - Authenticated reads

    /// The signed-in user's own `user_profile` row (RLS: `auth.uid() = id`).
    func profile(accessToken: String) async throws -> UserProfile? {
        let rows: [UserProfile] = try await get(
            "user_profile",
            query: [URLQueryItem(name: "limit", value: "1")],
            accessToken: accessToken
        )
        return rows.first
    }

    /// The user's curation prefs (persona, interests, hidden kinds). `nil`
    /// before onboarding writes the row.
    /// `GET /rest/v1/user_prefs?limit=1`
    func userPrefs(accessToken: String) async throws -> UserPrefs? {
        let rows: [UserPrefs] = try await get(
            "user_prefs",
            query: [URLQueryItem(name: "limit", value: "1")],
            accessToken: accessToken
        )
        return rows.first
    }

    /// The user's progress across every achievement.
    /// `GET /rest/v1/user_achievement`
    func userAchievements(accessToken: String) async throws -> [UserAchievement] {
        try await get(
            "user_achievement",
            query: [],
            accessToken: accessToken
        )
    }

    /// The user's Lore+ entitlement, if any. Returns the first row whose status
    /// currently confers access, else the first row, else `nil`.
    /// `GET /rest/v1/entitlements`
    func entitlement(accessToken: String) async throws -> Entitlement? {
        let rows: [Entitlement] = try await get(
            "entitlements",
            query: [],
            accessToken: accessToken
        )
        return rows.first(where: \.isActive) ?? rows.first
    }

    // MARK: - Authenticated writes / RPCs

    /// Upsert the user's curation prefs (onboarding + Profile edits). RLS
    /// derives `user_id` from the JWT, so the payload never carries it.
    /// `POST /rest/v1/user_prefs` with `Prefer: resolution=merge-duplicates`.
    @discardableResult
    func upsertPrefs(_ prefs: UserPrefs, accessToken: String) async throws -> UserPrefs? {
        let rows: [UserPrefs] = try await write(
            "user_prefs",
            method: "POST",
            jsonBody: prefs.upsertPayload,
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=representation"
        )
        return rows.first
    }

    /// Log an "I was here" visit. RLS derives `user_id`; the server defaults
    /// `visited_at`. Call `recomputeAchievements` afterward to settle badges.
    /// `POST /rest/v1/visit`
    func logVisit(
        placeID: String,
        source: Visit.Source = .scanner,
        accessToken: String
    ) async throws {
        let _: EmptyResponse = try await write(
            "visit",
            method: "POST",
            jsonBody: ["place_id": placeID, "source": source.rawValue],
            accessToken: accessToken,
            prefer: "return=minimal"
        )
    }

    /// Recompute achievements for the signed-in user and return any newly
    /// unlocked badges. RLS-scoped RPC; pass the user's own id as `p_user`.
    /// `POST /rest/v1/rpc/recompute_achievements { "p_user": userID }`
    @discardableResult
    func recomputeAchievements(userID: String, accessToken: String) async throws -> [Achievement] {
        try await rpc(
            "recompute_achievements",
            body: ["p_user": userID],
            accessToken: accessToken
        )
    }

    // MARK: - Plumbing

    /// A GET against a table/view, decoding the JSON array into `T`.
    private func get<T: Decodable>(
        _ table: String,
        query: [URLQueryItem],
        accessToken: String? = nil
    ) async throws -> T {
        var components = URLComponents(
            url: Config.restURL.appending(path: table),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await send(request)
    }

    /// A POST to `/rpc/{name}` with a JSON object body, decoding the result.
    private func rpc<T: Decodable>(
        _ name: String,
        body: [String: Any],
        accessToken: String? = nil
    ) async throws -> T {
        guard let url = URL(string: "rpc/\(name)", relativeTo: Config.restURL) else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAuth(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encodeJSON(body)

        return try await send(request)
    }

    /// A write (POST/PATCH) to a table with a JSON object body. `T` is either a
    /// decodable row array (with `return=representation`) or `EmptyResponse`
    /// (with `return=minimal`).
    private func write<T: Decodable>(
        _ table: String,
        method: String,
        jsonBody: [String: Any],
        accessToken: String,
        prefer: String
    ) async throws -> T {
        guard let url = URL(string: table, relativeTo: Config.restURL) else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        applyAuth(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        request.httpBody = try encodeJSON(jsonBody)

        return try await send(request)
    }

    /// Attach the `apikey` + `Authorization` headers Supabase requires. Reads
    /// with no user token authorize as `anon`.
    private func applyAuth(_ request: inout URLRequest, accessToken: String?) {
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(accessToken ?? Config.supabaseAnonKey)",
            forHTTPHeaderField: "Authorization"
        )
    }

    /// Execute a request, map non-2xx to `APIError.http`, decode the body into
    /// `T`. An empty body (204 / `return=minimal`) decodes into `EmptyResponse`.
    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func encodeJSON(_ object: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object)
        } catch {
            throw APIError.encoding(error)
        }
    }
}

/// Sentinel for endpoints that return no body (`Prefer: return=minimal`).
struct EmptyResponse: Decodable {}
