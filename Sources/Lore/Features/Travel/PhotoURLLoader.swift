import Foundation

/// Session-local signing work. A path has one request and independent waiters,
/// so disappearing thumbnails can cancel without cancelling another consumer.
@MainActor
final class PhotoURLLoader {
    typealias Signer = (String, String) async throws -> URL

    struct Limits {
        var concurrentRequests = 4
        var cachedURLs = 128
        // Storage signs for one hour. Leave ten minutes of expiry headroom.
        var cacheLifetime: TimeInterval = 50 * 60
    }

    private struct CachedURL {
        let url: URL
        let expiresAt: Date
        var lastAccess: UInt64
    }

    private final class Request {
        let id = UUID()
        let path: String
        let accessToken: String
        var waiters: [UUID: CheckedContinuation<URL?, Never>] = [:]

        init(path: String, accessToken: String) {
            self.path = path
            self.accessToken = accessToken
        }
    }

    private let signer: Signer
    private let now: () -> Date
    private let limits: Limits
    private var cache: [String: CachedURL] = [:]
    private var accessCounter: UInt64 = 0
    private var requests: [String: Request] = [:]
    private var queue: [Request] = []
    private var active: [UUID: Task<Void, Never>] = [:]

    // Internal diagnostics also let tests wait for admission without sleeps.
    var pendingRequestCount: Int { requests.count }
    var pendingWaiterCount: Int { requests.values.reduce(0) { $0 + $1.waiters.count } }
    var activeRequestCount: Int { active.count }
    var cachedURLCount: Int { cache.count }

    init(signer: @escaping Signer, now: @escaping () -> Date = Date.init, limits: Limits = .init()) {
        self.signer = signer
        self.now = now
        self.limits = limits
    }

    /// Refresh bypasses a completed cache entry, but joins an existing signing
    /// request. Concurrent retries therefore cannot create competing results.
    func url(path: String, accessToken: String, forceRefresh: Bool = false) async -> URL? {
        guard !Task.isCancelled else { return nil }
        cache = cache.filter { $0.value.expiresAt > now() }
        if forceRefresh {
            cache.removeValue(forKey: path)
        } else if var cached = cache[path] {
            cached.lastAccess = nextAccess()
            cache[path] = cached
            return cached.url
        }

        let waiterID = UUID()
        let url: URL? = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                let request: Request
                if let existing = requests[path] {
                    request = existing
                } else {
                    request = Request(path: path, accessToken: accessToken)
                    requests[path] = request
                    queue.append(request)
                }
                request.waiters[waiterID] = continuation
                startQueuedRequests()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(path: path, id: waiterID)
            }
        }
        return Task.isCancelled ? nil : url
    }

    /// Discard both cached capabilities and in-flight results for this object.
    func invalidate(path: String) {
        cache.removeValue(forKey: path)
        guard let request = requests.removeValue(forKey: path) else { return }
        queue.removeAll { $0.id == request.id }
        active[request.id]?.cancel()
        finishWaiters(request, url: nil)
        startQueuedRequests()
    }

    /// Called on every session reset, even when the next account has the same ID.
    func reset() {
        cache.removeAll()
        let abandoned = Array(requests.values)
        requests.removeAll()
        queue.removeAll()
        for task in active.values { task.cancel() }
        for request in abandoned { finishWaiters(request, url: nil) }
        // Cancelled operations still occupy their slots until they finish. An
        // uncooperative signer must not allow a reset/cancel storm to exceed
        // the network concurrency limit or write back into the new session.
    }

    private func cancelWaiter(path: String, id: UUID) {
        guard let request = requests[path],
              let waiter = request.waiters.removeValue(forKey: id) else { return }
        waiter.resume(returning: nil)
        if request.waiters.isEmpty { invalidate(path: path) }
    }

    private func startQueuedRequests() {
        while active.count < max(1, limits.concurrentRequests), !queue.isEmpty {
            let request = queue.removeFirst()
            let startedAt = now()
            let signer = signer
            active[request.id] = Task { [weak self] in
                let url: URL?
                do {
                    try Task.checkCancellation()
                    url = try await signer(request.path, request.accessToken)
                } catch {
                    url = nil
                }
                self?.complete(request, url: url, startedAt: startedAt)
            }
        }
    }

    private func complete(_ request: Request, url: URL?, startedAt: Date) {
        active.removeValue(forKey: request.id)
        defer { startQueuedRequests() }
        guard requests[request.path]?.id == request.id else { return }
        requests.removeValue(forKey: request.path)
        if let url, limits.cachedURLs > 0 {
            let expiry = startedAt.addingTimeInterval(limits.cacheLifetime)
            if expiry > now() {
                cache[request.path] = CachedURL(url: url, expiresAt: expiry, lastAccess: nextAccess())
                while cache.count > limits.cachedURLs,
                      let oldest = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
                    cache.removeValue(forKey: oldest)
                }
            }
        }
        finishWaiters(request, url: url)
    }

    private func finishWaiters(_ request: Request, url: URL?) {
        let waiters = request.waiters.values
        request.waiters = [:]
        for waiter in waiters { waiter.resume(returning: url) }
    }

    private func nextAccess() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }
}

/// Uploaded JPEG bytes provide instant previews, with a strict memory budget.
/// This cache is owned and cleared by the same VisitStore session as URL signing.
struct PhotoPreviewCache {
    private struct Entry {
        let data: Data
        var lastAccess: UInt64
    }
    private let maximumCount: Int
    private let maximumBytes: Int
    private var entries: [String: Entry] = [:]
    private var accessCounter: UInt64 = 0
    private(set) var byteCount = 0
    var count: Int { entries.count }

    init(maximumCount: Int = 8, maximumBytes: Int = 8 * 1024 * 1024) {
        self.maximumCount = maximumCount
        self.maximumBytes = maximumBytes
    }

    mutating func data(for path: String) -> Data? {
        guard var entry = entries[path] else { return nil }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        entries[path] = entry
        return entry.data
    }

    mutating func insert(_ data: Data, for path: String) {
        remove(path)
        guard maximumCount > 0, data.count <= maximumBytes else { return }
        accessCounter &+= 1
        entries[path] = Entry(data: data, lastAccess: accessCounter)
        byteCount += data.count
        while entries.count > maximumCount || byteCount > maximumBytes {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            remove(oldest)
        }
    }

    mutating func remove(_ path: String) {
        if let removed = entries.removeValue(forKey: path) { byteCount -= removed.data.count }
    }

    mutating func removeAll() {
        entries.removeAll()
        byteCount = 0
    }
}
