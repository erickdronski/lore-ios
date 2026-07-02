import Foundation

/// Thin async PostgREST client over `URLSession` — no external dependencies
/// (docs/03 §2 names the Supabase Swift client for ContentKit at P1; at P0 the
/// read surface is three anonymous GETs and a hand-rolled client keeps the
/// scaffold dependency-free).
///
/// Every request carries the anon key as both `apikey` and
/// `Authorization: Bearer` (Supabase convention). When a user session exists,
/// pass its access token so RLS resolves `auth.uid()` — required for
/// `user_profile`.
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

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "Could not build the request URL."
            case .http(let status, let body):
                return "Server returned \(status): \(body)"
            case .decoding(let error):
                return "Could not read the server response: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Public read surface

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

    // MARK: - Plumbing

    private func get<T: Decodable>(
        _ table: String,
        query: [URLQueryItem],
        accessToken: String? = nil
    ) async throws -> T {
        var components = URLComponents(
            url: Config.restURL.appending(path: table),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
        guard let url = components?.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(accessToken ?? Config.supabaseAnonKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
