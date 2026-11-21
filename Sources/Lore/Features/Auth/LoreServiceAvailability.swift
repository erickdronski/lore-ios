import Foundation
import Observation

@MainActor
@Observable
final class LoreServiceAvailability {
    static let shared = LoreServiceAvailability()
    nonisolated static let signInUnavailable = "Lore account services are temporarily unavailable. Try again later."
    nonisolated static let purchasesUnavailable = "New purchases are paused while Lore’s online services are unavailable. You can still restore a previous purchase."

    private(set) var isRestricted = false
    private(set) var isUnavailable = false
    @ObservationIgnored private var pending: Task<Bool, Never>?
    @ObservationIgnored private let session: URLSession

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 4
        config.urlCache = nil
        self.session = session ?? URLSession(configuration: config)
    }

    func observeHTTPStatus(_ status: Int) {
        if status == 402 {
            isRestricted = true
            isUnavailable = true
        }
    }

    @discardableResult
    func check() async -> Bool {
        if let pending { return await pending.value }
        let task = Task { await checkServices() }
        pending = task
        defer { pending = nil }
        return await task.value
    }

    private struct Settings: Decodable {
        let external: [String: Bool]
        let disable_signup: Bool
    }

    private struct City: Decodable { let slug: String }
    private enum Result: Equatable { case available, restricted, unavailable }

    private func checkServices() async -> Bool {
        let city = Config.restURL.appending(path: "city").appending(queryItems: [
            URLQueryItem(name: "select", value: "slug"), URLQueryItem(name: "status", value: "eq.live"),
            URLQueryItem(name: "limit", value: "1")
        ])
        async let auth = probe(Config.authURL.appending(path: "settings")) { data in
            (try? JSONDecoder().decode(Settings.self, from: data)) != nil
        }
        async let catalog = probe(city) { data in
            guard let first = try? JSONDecoder().decode([City].self, from: data).first else { return false }
            return !first.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let results = await (auth, catalog)
        let available = results == (.available, .available)
        if available { isRestricted = false }
        if results.0 == .restricted || results.1 == .restricted { isRestricted = true }
        isUnavailable = !available
        return available
    }

    private func probe(_ url: URL, validate: (Data) -> Bool) async -> Result {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 4
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer " + Config.supabaseAnonKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            if http.statusCode == 402 { return .restricted }
            guard (200..<300).contains(http.statusCode), validate(data) else { return .unavailable }
            return .available
        } catch {
            return .unavailable
        }
    }
}
