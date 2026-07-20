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

    /// The "Did You Know" facts (superlatives, firsts, records, quirks, stats)
    /// for a city. Powers the fact deck + "By the Numbers" strip on Meet {City}.
    /// `GET /rest/v1/city_fact?city=eq.{city}&order=sort`
    func cityFacts(city: String = Config.defaultCity) async throws -> [CityFact] {
        try await get(
            "city_fact",
            query: [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "order", value: "sort.asc"),
            ]
        )
    }

    /// The city's signature hue system, if curated. One row or none.
    /// `GET /rest/v1/city_theme?city=eq.{city}&limit=1`
    func cityTheme(city: String = Config.defaultCity) async throws -> CityTheme? {
        let rows: [CityTheme] = try await get(
            "city_theme",
            query: [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return rows.first
    }

    /// The city's flavor sections (dish, sound, etiquette, …), any kind.
    /// `GET /rest/v1/city_section?city=eq.{city}&order=sort`
    func citySections(city: String = Config.defaultCity) async throws -> [CitySection] {
        try await get(
            "city_section",
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

    // MARK: - Public traveler lore (community layer)

    /// The shared traveler lore on one place, newest first, via the moderated
    /// `lore_public` view (opt-in rows, visible/approved only; signed-in
    /// callers get their blocks applied server-side). DELIBERATELY bypasses
    /// AtlasCache even for anonymous reads: moderation (report -> hide) must
    /// take effect on next open, never after a six-hour cache window.
    /// `GET /rest/v1/lore_public?place_id=eq.{id}&order=shared_at.desc`
    func publicLore(
        placeID: String,
        accessToken: String? = nil,
        limit: Int = 20
    ) async throws -> [PublicLore] {
        let request = try atlasRequest(
            "lore_public",
            query: [
                URLQueryItem(name: "place_id", value: "eq.\(placeID)"),
                URLQueryItem(name: "order", value: "shared_at.desc"),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            accessToken: accessToken
        )
        return try await send(request)
    }

    // MARK: - Deals & discounts

    /// Live offers matched to one place, via `place_deal_feed` (real, curated
    /// deals only; `match_kind` says how the deal relates to the place). Never
    /// cached or pinned: a price snapshot must not outlive the marketplace.
    /// `GET /rest/v1/place_deal_feed?place_id=eq.{id}`
    func deals(placeID: String) async throws -> [Deal] {
        let request = try atlasRequest(
            "place_deal_feed",
            query: [
                URLQueryItem(name: "place_id", value: "eq.\(placeID)"),
                // Best first: the server's `rank` folds match tier, source
                // priority (relevance × trust × payout), discount, and rating.
                URLQueryItem(name: "order", value: "rank.asc"),
                URLQueryItem(name: "limit", value: "12"),
            ]
        )
        return try await send(request)
    }

    /// City-wide offers (passes, always-on bundles) for the city rail, best
    /// first. Same freshness rule as place deals: never served from cache, so
    /// a deactivated deal disappears on next open.
    /// `GET /rest/v1/city_deal_feed?city=eq.{city}&order=rank.asc`
    func cityDeals(city: String) async throws -> [Deal] {
        let request = try atlasRequest(
            "city_deal_feed",
            query: [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "order", value: "rank.asc"),
                URLQueryItem(name: "limit", value: "6"),
            ]
        )
        return try await send(request)
    }

    /// Which of the given places have at least one live offer. One lightweight
    /// query (`select=place_id`) so shelves and lists can render a quiet
    /// "offers here" mark without an N-per-tile fan-out. Empty in → empty out.
    /// `GET /rest/v1/place_deal_feed?select=place_id&place_id=in.(a,b,c)`
    func placesWithOffers(placeIDs: [String]) async throws -> Set<String> {
        guard !placeIDs.isEmpty else { return [] }
        struct Row: Decodable { let place_id: String }
        let request = try atlasRequest(
            "place_deal_feed",
            query: [
                URLQueryItem(name: "select", value: "place_id"),
                URLQueryItem(name: "place_id", value: "in.(\(placeIDs.joined(separator: ",")))"),
            ]
        )
        let rows: [Row] = try await send(request)
        return Set(rows.map(\.place_id))
    }

    // MARK: - Offline city packs

    /// Everything `pinCityPack` learned while pinning, for the image pass.
    struct CityPinResult {
        var places: [Place] = []
        /// Distinct `media.wikipedia_title`s across the city's dives.
        var wikipediaTitles: [String] = []
        /// Every request URL pinned, recorded so a pack can be removed.
        var pinnedURLs: [String] = []
        /// Studio narration files referenced by this city's dives; the pack
        /// downloads them like hero images so audio survives offline.
        var audioURLs: [URL] = []
    }

    /// Fetch + durably pin every anonymous read a city needs to work offline:
    /// the city list, this city's places/stories/culture/facts/tours, the
    /// achievement catalog, and every place's dive + provenance facts. Requests
    /// are built by the same builder as live reads, so the pinned bytes answer
    /// the exact URLs the app asks for later. `onUnit` ticks once per finished
    /// request (drive a progress bar with it).
    func pinCityPack(
        city: String,
        onUnit: @escaping @MainActor () -> Void
    ) async throws -> CityPinResult {
        var result = CityPinResult()

        // City-scoped + global endpoints, in the exact live-read shapes.
        let endpoints: [(table: String, query: [URLQueryItem])] = [
            ("city", [
                URLQueryItem(name: "status", value: "eq.live"),
                URLQueryItem(name: "order", value: "sort.asc"),
            ]),
            ("place_explore", [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "order", value: "name.asc"),
            ]),
            ("story", [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "order", value: "year.asc"),
            ]),
            ("city_culture", [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "order", value: "sort.asc"),
            ]),
            ("city_fact", [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "order", value: "sort.asc"),
            ]),
            ("tour", [
                URLQueryItem(name: "city", value: "eq.\(city)"),
                URLQueryItem(name: "select", value: "*,tour_stop(*)"),
                URLQueryItem(name: "order", value: "title.asc"),
            ]),
            ("achievement", [
                URLQueryItem(name: "order", value: "sort.asc"),
            ]),
        ]

        for endpoint in endpoints {
            let request = try atlasRequest(endpoint.table, query: endpoint.query)
            let data = try await AtlasCache.shared.pinData(for: request, session: session)
            result.pinnedURLs.append(request.url?.absoluteString ?? "")
            if endpoint.table == "place_explore" {
                result.places = try decodeBody(data)
            }
            await onUnit()
        }

        // Per-place dive + facts, four at a time. A single failed place skips
        // (its live read still works online); the pack keeps going.
        var titles: Set<String> = []
        var audioURLs: Set<URL> = []
        try await withThrowingTaskGroup(of: (urls: [String], title: String?, audio: URL?).self) { group in
            var iterator = result.places.makeIterator()
            var inFlight = 0

            func addNext() {
                guard let place = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    var urls: [String] = []
                    var title: String?
                    var audio: URL?
                    if let diveRequest = try? self.atlasRequest("dive", query: [
                        URLQueryItem(name: "place_id", value: "eq.\(place.id)"),
                        URLQueryItem(name: "limit", value: "1"),
                    ]) {
                        if let data = try? await AtlasCache.shared.pinData(for: diveRequest, session: self.session) {
                            urls.append(diveRequest.url?.absoluteString ?? "")
                            let dives: [Dive]? = try? self.decodeBody(data)
                            title = dives?.first?.media.wikipediaTitle
                            audio = dives?.first?.audioURL
                        }
                    }
                    if let factsRequest = try? self.atlasRequest("fact", query: [
                        URLQueryItem(name: "place_id", value: "eq.\(place.id)"),
                        URLQueryItem(name: "order", value: "key.asc"),
                    ]) {
                        if (try? await AtlasCache.shared.pinData(for: factsRequest, session: self.session)) != nil {
                            urls.append(factsRequest.url?.absoluteString ?? "")
                        }
                    }
                    return (urls, title, audio)
                }
            }

            for _ in 0..<4 { addNext() }
            while inFlight > 0 {
                guard let outcome = try await group.next() else { break }
                inFlight -= 1
                result.pinnedURLs.append(contentsOf: outcome.urls)
                if let title = outcome.title, !title.isEmpty { titles.insert(title) }
                if let audio = outcome.audio { audioURLs.insert(audio) }
                await onUnit()
                addNext()
            }
        }

        result.wikipediaTitles = titles.sorted()
        result.audioURLs = audioURLs.sorted { $0.absoluteString < $1.absoluteString }
        return result
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
    /// The signed-in user's world-exploration stats (`user_stats` RPC, a single
    /// jsonb object). RLS-guarded to the caller; the dashboard reads it.
    func userStats(userID: String, accessToken: String) async throws -> UserStats {
        try await rpc("user_stats", body: ["p_user": userID], accessToken: accessToken)
    }

    func recomputeAchievements(userID: String, accessToken: String) async throws -> [Achievement] {
        try await rpc(
            "recompute_achievements",
            body: ["p_user": userID],
            accessToken: accessToken
        )
    }

    /// Record that the signed-in user opened this place's deep dive today, so the
    /// "Deep dives" stat counts it and the dive-read badges can unlock. Idempotent
    /// per day (the RPC's `on conflict do nothing`), and it recomputes achievements
    /// server-side. Returns the user's all-time distinct dive-read count.
    /// `POST /rest/v1/rpc/record_dive_read { "p_place": "…" }`
    @discardableResult
    func recordDiveRead(placeID: String, accessToken: String) async throws -> Int {
        try await rpc("record_dive_read", body: ["p_place": placeID], accessToken: accessToken)
    }

    // MARK: - Plumbing

    /// A GET against a table/view, decoding the JSON array into `T`.
    /// Anonymous reads flow through `AtlasCache` (stale-while-revalidate, the
    /// zero-network loop); user-token reads always hit the network so RLS rows
    /// are never persisted or stale.
    private func get<T: Decodable>(
        _ table: String,
        query: [URLQueryItem],
        accessToken: String? = nil
    ) async throws -> T {
        let request = try atlasRequest(table, query: query, accessToken: accessToken)
        guard accessToken == nil else { return try await send(request) }
        let data = try await AtlasCache.shared.data(for: request, session: session)
        return try decodeBody(data)
    }

    /// The one place atlas GET requests are built. Live reads, cache keys, and
    /// pack pins all flow through here, so a pinned entry always answers the
    /// exact URL the app requests later.
    private func atlasRequest(
        _ table: String,
        query: [URLQueryItem],
        accessToken: String? = nil
    ) throws -> URLRequest {
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
        return request
    }

    /// A POST to `/rpc/{name}` with a JSON object body, decoding the result.
    private func rpc<T: Decodable>(
        _ name: String,
        body: [String: Any],
        accessToken: String? = nil
    ) async throws -> T {
        let url = Config.restURL
            .appending(path: "rpc")
            .appending(path: name)
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
        let url = Config.restURL.appending(path: table)
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
        return try decodeBody(data)
    }

    /// Shared body decoding for network and cache paths. An empty body
    /// (204 / `return=minimal`) decodes into `EmptyResponse`.
    private func decodeBody<T: Decodable>(_ data: Data) throws -> T {
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
