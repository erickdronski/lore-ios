import CryptoKit
import Foundation

/// Additive backend contract that turns the publication boundary on without
/// making older app builds depend on the table existing first.
struct ContentContract: Codable, Equatable, Sendable {
    static let supportedVersion = "2"
    static let clockSkewTolerance: TimeInterval = 5

    let contractVersion: String
    let reviewEpoch: String
    let enforcementEnabled: Bool
    let offlineMaxAgeHours: Int

    static let compatibility = ContentContract(
        contractVersion: "legacy",
        reviewEpoch: "legacy",
        enforcementEnabled: false,
        offlineMaxAgeHours: 0
    )

    static let cacheRejection = ContentContract(
        contractVersion: "unsupported",
        reviewEpoch: "invalid",
        enforcementEnabled: true,
        offlineMaxAgeHours: 0
    )

    init(
        contractVersion: String,
        reviewEpoch: String,
        enforcementEnabled: Bool,
        offlineMaxAgeHours: Int
    ) {
        self.contractVersion = contractVersion
        self.reviewEpoch = reviewEpoch
        self.enforcementEnabled = enforcementEnabled
        self.offlineMaxAgeHours = offlineMaxAgeHours
    }

    private enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case reviewEpoch = "review_epoch"
        case enforcementEnabled = "enforcement_enabled"
        case offlineMaxAgeHours = "offline_max_age_hours"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try Self.decodeIdentifier(.contractVersion, from: values)
        reviewEpoch = try Self.decodeIdentifier(.reviewEpoch, from: values)
        enforcementEnabled = try values.decode(Bool.self, forKey: .enforcementEnabled)
        if let hours = try? values.decode(Int.self, forKey: .offlineMaxAgeHours) {
            offlineMaxAgeHours = hours
        } else {
            let raw = try values.decode(String.self, forKey: .offlineMaxAgeHours)
            guard let hours = Int(raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .offlineMaxAgeHours,
                    in: values,
                    debugDescription: "Expected an integer offline age."
                )
            }
            offlineMaxAgeHours = hours
        }
    }

    var isValidForEnforcement: Bool {
        contractVersion == Self.supportedVersion
            && !reviewEpoch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...720).contains(offlineMaxAgeHours)
    }

    var maximumOfflineAge: TimeInterval? {
        guard enforcementEnabled, isValidForEnforcement else {
            return enforcementEnabled ? 0 : nil
        }
        return TimeInterval(offlineMaxAgeHours) * 60 * 60
    }

    var cacheNamespace: String {
        "contract:\(contractVersion)|epoch:\(reviewEpoch)"
    }

    private static func decodeIdentifier(
        _ key: CodingKeys,
        from values: KeyedDecodingContainer<CodingKeys>
    ) throws -> String {
        if let value = try? values.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? values.decode(Int.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: values,
            debugDescription: "Expected a string or integer identifier."
        )
    }
}

protocol ContentContractProviding: Sendable {
    func current(session: URLSession) async -> ContentContract
}

/// Fetches the contract directly from PostgREST. Its small local snapshot is
/// separate from AtlasCache so content bytes can never answer this request.
actor ContentContractStore: ContentContractProviding {
    static let shared = ContentContractStore()

    private static let refreshInterval: TimeInterval = 5 * 60

    private let persistedFile: URL
    private let now: @Sendable () -> Date
    private var lastKnown: ContentContract?
    private var lastRefresh: Date?
    private var refreshTask: Task<ContentContract, Never>?

    private enum FetchResult: Sendable {
        case contract(ContentContract)
        case absent
        case unavailable
        case invalid
    }

    init(
        persistedFile: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.persistedFile = persistedFile ?? Self.defaultPersistedFile()
        self.now = now
        if let data = try? Data(contentsOf: self.persistedFile) {
            self.lastKnown = try? JSONDecoder().decode(ContentContract.self, from: data)
        } else {
            self.lastKnown = nil
        }
    }

    static func persistedSnapshot() -> ContentContract? {
        guard let data = try? Data(contentsOf: defaultPersistedFile()) else { return nil }
        return try? JSONDecoder().decode(ContentContract.self, from: data)
    }

    func current(session: URLSession) async -> ContentContract {
        await current(session: session, forceRefresh: false)
    }

    func current(session: URLSession, forceRefresh: Bool) async -> ContentContract {
        let checkedAt = now()
        if let refreshTask {
            return await refreshTask.value
        }

        if !forceRefresh,
           let lastRefresh,
           checkedAt.timeIntervalSince(lastRefresh) >= 0,
           checkedAt.timeIntervalSince(lastRefresh) < Self.refreshInterval {
            return lastKnown ?? .compatibility
        }

        lastRefresh = checkedAt
        let task = Task {
            let result = await self.fetchDirect(session: session)
            return self.finishRefresh(result)
        }
        refreshTask = task
        return await task.value
    }

    private func finishRefresh(_ result: FetchResult) -> ContentContract {
        refreshTask = nil
        return apply(result)
    }

    private func apply(_ result: FetchResult) -> ContentContract {
        let previous = lastKnown
        switch result {
        case .absent, .unavailable:
            return previous ?? .compatibility
        case .invalid:
            let rejection = ContentContract.cacheRejection
            lastKnown = rejection
            if let data = try? JSONEncoder().encode(rejection) {
                try? data.write(to: persistedFile, options: .atomic)
            }
            return rejection
        case .contract(let fetched):
            if previous?.enforcementEnabled == true, !fetched.enforcementEnabled {
                return previous ?? .cacheRejection
            }
            lastKnown = fetched
            if let data = try? JSONEncoder().encode(fetched) {
                try? data.write(to: persistedFile, options: .atomic)
            }
            return fetched
        }
    }

    private func fetchDirect(session: URLSession) async -> FetchResult {
        var components = URLComponents(
            url: Config.restURL.appending(path: "content_contract"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(
                name: "select",
                value: "contract_version,review_epoch,enforcement_enabled,offline_max_age_hours"
            ),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else { return .invalid }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            if http.statusCode == 404 { return .absent }
            guard (200..<300).contains(http.statusCode) else { return .unavailable }
            do {
                guard let contract = try JSONDecoder()
                    .decode([ContentContract].self, from: data)
                    .first
                else { return .invalid }
                return .contract(contract)
            } catch {
                return .invalid
            }
        } catch {
            return .unavailable
        }
    }

    private static func defaultPersistedFile() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = support.appending(path: "lore-contract", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "current.json")
    }
}

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
/// - network failure            → compatible cached bytes beat a spinner; once
///   contract enforcement is active, generation and maximum age are strict.
///
/// User-scoped rows (anything with an access token) must NEVER pass through
/// here; `LoreAPI.get` only routes anonymous requests in.
actor AtlasCache {
    static let shared = AtlasCache()

    /// Six hours: city content changes on editorial cadence, not per-minute.
    static let defaultFreshFor: TimeInterval = 6 * 60 * 60

    private let directory: URL
    /// Durable copies for downloaded city packs. Lives in Application Support
    /// (NOT Caches) so iOS storage-pressure purges can't break a pack the user
    /// explicitly downloaded. Read as the last resort after cache + network.
    private let pinDirectory: URL
    private let contractProvider: any ContentContractProviding
    private let now: @Sendable () -> Date
    private var refreshing: Set<String> = []

    init(
        directory: URL? = nil,
        pinDirectory: URL? = nil,
        contractProvider: any ContentContractProviding = ContentContractStore.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = directory
            ?? caches.appending(path: "lore-atlas", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.pinDirectory = pinDirectory
            ?? support.appending(path: "lore-packs/atlas", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.pinDirectory, withIntermediateDirectories: true)
        self.contractProvider = contractProvider
        self.now = now
    }

    /// Fetch `request` through the cache. See the type comment for semantics.
    func data(
        for request: URLRequest,
        session: URLSession,
        freshFor: TimeInterval = AtlasCache.defaultFreshFor
    ) async throws -> Data {
        let contract = await contentContract(session: session)
        prepareStorage(for: contract)
        guard let key = cacheKey(for: request, contract: contract) else {
            return try await fetchValid(request, session: session)
        }
        let file = directory.appending(path: key)
        let maximumAge = contract.maximumOfflineAge
        let effectiveFreshFor = maximumAge.map { min(freshFor, $0) } ?? freshFor

        if let cached = read(file, maximumAge: maximumAge), cached.age < effectiveFreshFor {
            refreshInBackground(key: key, request: request, session: session, file: file)
            return cached.data
        }

        do {
            let data = try await fetchValid(request, session: session)
            if !contract.enforcementEnabled || contract.isValidForEnforcement {
                try? data.write(to: file, options: .atomic)
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // A superseded city/search task must stay cancelled. Returning a
            // stale payload here would let an old selection overwrite the new
            // one after the traveler has already moved on.
            throw error
        } catch {
            if let stale = read(file, maximumAge: maximumAge) { return stale.data }
            // Cache purged + no network: a downloaded city pack still answers.
            // Re-seed the cache copy so subsequent reads skip this branch.
            if let pinned = read(pinDirectory.appending(path: key), maximumAge: maximumAge) {
                try? pinned.data.write(to: file, options: .atomic)
                return pinned.data
            }
            throw error
        }
    }

    // MARK: - City packs (durable pins)

    /// Fetch fresh bytes for `request` and store them in BOTH the cache and the
    /// durable pin store. Returns the bytes. Used by "Download this city".
    func pinData(for request: URLRequest, session: URLSession) async throws -> Data {
        let contract = await contentContract(session: session)
        return try await pinData(for: request, session: session, contract: contract)
    }

    func pinData(
        for request: URLRequest,
        session: URLSession,
        contract: ContentContract
    ) async throws -> Data {
        prepareStorage(for: contract)
        let data = try await fetchValid(request, session: session)
        if (!contract.enforcementEnabled || contract.isValidForEnforcement),
           let key = cacheKey(for: request, contract: contract) {
            try? data.write(to: directory.appending(path: key), options: .atomic)
            try? data.write(to: pinDirectory.appending(path: key), options: .atomic)
        }
        return data
    }

    func contentContract(session: URLSession) async -> ContentContract {
        await contractProvider.current(session: session)
    }

    /// Remove the durable copies for the given request URLs (pack removal).
    func unpin(
        urlStrings: [String],
        contractVersion: String? = nil,
        reviewEpoch: String? = nil
    ) {
        for urlString in urlStrings {
            let identity: String
            if let contractVersion, let reviewEpoch {
                identity = "contract:\(contractVersion)|epoch:\(reviewEpoch)\n\(urlString)"
            } else {
                identity = urlString
            }
            let key = Self.digest(identity)
            try? FileManager.default.removeItem(at: pinDirectory.appending(path: key))
        }
    }

    // MARK: - Internals

    private func cacheKey(for request: URLRequest, contract: ContentContract) -> String? {
        guard let url = request.url?.absoluteString else { return nil }
        let identity = contract.enforcementEnabled
            ? "\(contract.cacheNamespace)\n\(url)"
            : url
        return Self.digest(identity)
    }

    private func read(
        _ file: URL,
        maximumAge: TimeInterval?
    ) -> (data: Data, age: TimeInterval)? {
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? nil
        let age = modified.map { now().timeIntervalSince($0) } ?? .infinity
        if let maximumAge {
            guard age >= -ContentContract.clockSkewTolerance, age <= maximumAge else {
                return nil
            }
            return (data, max(0, age))
        }
        return (data, max(0, age))
    }

    /// An enforcement transition removes all prior URL-only bytes. Subsequent
    /// generations are isolated by the same marker and key namespace.
    private func prepareStorage(for contract: ContentContract) {
        guard contract.enforcementEnabled else { return }
        let namespace = contract.cacheNamespace
        for storageDirectory in [directory, pinDirectory] {
            let marker = storageDirectory.appending(path: ".content-contract")
            let stored = try? String(contentsOf: marker, encoding: .utf8)
            guard stored != namespace else { continue }
            if let files = try? FileManager.default.contentsOfDirectory(
                at: storageDirectory,
                includingPropertiesForKeys: nil
            ) {
                for file in files { try? FileManager.default.removeItem(at: file) }
            }
            try? Data(namespace.utf8).write(to: marker, options: .atomic)
        }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Network fetch that only accepts 2xx bodies, so an error payload can
    /// never poison the cache.
    private func fetchValid(_ request: URLRequest, session: URLSession) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw LoreAPI.APIError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
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
