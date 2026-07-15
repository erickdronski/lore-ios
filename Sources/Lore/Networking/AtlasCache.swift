import CryptoKit
import Foundation

/// Disk-backed stale-while-revalidate cache for the anonymous atlas reads
/// (cities, places, stories, culture, facts, tours, dives). Ported from the
/// scanner lab (lore-expo docs/SCANNER-FUSION.md §4) to deliver the
/// blueprint's zero-network loop in the native app: the scanner and city
/// folios resolve instantly on relaunch and keep working through dead spots.
///
/// Semantics per read:
/// - fresh cache (< `freshFor`)  → return it now, refresh silently in the
///   background so the next read is current;
/// - stale / missing            → network first, cache on success;
/// - network failure            → any cached copy, however old, beats a spinner.
///
/// User-scoped rows (anything with an access token) must NEVER pass through
/// here; `LoreAPI.get` only routes anonymous requests in.
actor AtlasCache {
    static let shared = AtlasCache()

    /// Six hours: city content changes on editorial cadence, not per-minute.
    static let defaultFreshFor: TimeInterval = 6 * 60 * 60

    private let directory: URL
    private var refreshing: Set<String> = []

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: "lore-atlas", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Fetch `request` through the cache. See the type comment for semantics.
    func data(
        for request: URLRequest,
        session: URLSession,
        freshFor: TimeInterval = AtlasCache.defaultFreshFor
    ) async throws -> Data {
        guard let key = cacheKey(for: request) else {
            let (data, _) = try await session.data(for: request)
            return data
        }
        let file = directory.appending(path: key)

        if let cached = read(file), cached.age < freshFor {
            refreshInBackground(key: key, request: request, session: session, file: file)
            return cached.data
        }

        do {
            let data = try await fetchValid(request, session: session)
            try? data.write(to: file, options: .atomic)
            return data
        } catch {
            if let stale = read(file) { return stale.data }
            throw error
        }
    }

    // MARK: - Internals

    private func cacheKey(for request: URLRequest) -> String? {
        guard let url = request.url?.absoluteString else { return nil }
        let digest = SHA256.hash(data: Data(url.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func read(_ file: URL) -> (data: Data, age: TimeInterval)? {
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? nil
        let age = modified.map { Date().timeIntervalSince($0) } ?? .infinity
        return (data, age)
    }

    /// Network fetch that only accepts 2xx bodies, so an error payload can
    /// never poison the cache.
    private func fetchValid(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LoreAPI.APIError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    private func refreshInBackground(key: String, request: URLRequest, session: URLSession, file: URL) {
        guard !refreshing.contains(key) else { return }
        refreshing.insert(key)
        Task {
            defer { self.endRefresh(key) }
            if let data = try? await self.fetchValid(request, session: session) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    private func endRefresh(_ key: String) {
        refreshing.remove(key)
    }
}
