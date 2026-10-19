import XCTest
@testable import Lore

@MainActor
final class PhotoURLLoaderTests: XCTestCase {
    func testSamePathSharesOneSigningRequestAndCachesResult() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer)
        let first = request(loader, "a")
        let second = request(loader, "a")
        await waitUntil { loader.pendingWaiterCount == 2 && signer.calls.count == 1 }
        signer.succeed(0)
        let firstURL = await first.value
        let secondURL = await second.value
        let cachedURL = await loader.url(path: "a", accessToken: "token")
        XCTAssertEqual(firstURL, signer.url(0))
        XCTAssertEqual(secondURL, firstURL)
        XCTAssertEqual(cachedURL, firstURL)
        XCTAssertEqual(signer.calls.count, 1)
    }

    func testDifferentPathsRespectConcurrencyLimitAndFIFOQueue() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer, concurrent: 2)
        let first = request(loader, "a")
        await waitUntil { signer.calls.count == 1 }
        let second = request(loader, "b")
        await waitUntil { signer.calls.count == 2 }
        let third = request(loader, "c")
        await waitUntil { loader.pendingRequestCount == 3 }
        let fourth = request(loader, "d")
        await waitUntil { loader.pendingRequestCount == 4 }
        XCTAssertEqual(signer.calls.count, 2)
        signer.succeed(0)
        await waitUntil { signer.calls.count == 3 }
        XCTAssertEqual(signer.calls[2].path, "c")
        signer.succeed(1)
        await waitUntil { signer.calls.count == 4 }
        XCTAssertEqual(signer.calls[3].path, "d")
        signer.succeed(2)
        signer.succeed(3)
        for task in [first, second, third, fourth] { _ = await task.value }
        XCTAssertEqual(signer.maximumActive, 2)
        XCTAssertEqual(loader.activeRequestCount, 0)
    }

    func testCacheExpiryUsesSigningStartAndLRUEvictsLeastRecentlyRead() async {
        let signer = ControlledPhotoSigner()
        var now = Date(timeIntervalSince1970: 100)
        let loader = PhotoURLLoader(signer: signer.sign, now: { now }, limits: .init(concurrentRequests: 2, cachedURLs: 2, cacheLifetime: 10))
        for (index, path) in ["a", "b"].enumerated() {
            let task = request(loader, path)
            await waitUntil { signer.calls.count == index + 1 }
            signer.succeed(index)
            _ = await task.value
        }
        _ = await loader.url(path: "a", accessToken: "token") // a is now most recent.
        let third = request(loader, "c")
        await waitUntil { signer.calls.count == 3 }
        signer.succeed(2)
        _ = await third.value
        XCTAssertEqual(loader.cachedURLCount, 2)
        let cachedA = await loader.url(path: "a", accessToken: "token")
        XCTAssertEqual(cachedA, signer.url(0))
        let evictedB = request(loader, "b")
        await waitUntil { signer.calls.count == 4 }
        signer.succeed(3)
        _ = await evictedB.value
        now.addTimeInterval(10)
        let expiredA = request(loader, "a")
        await waitUntil { signer.calls.count == 5 }
        signer.succeed(4)
        let refreshedA = await expiredA.value
        XCTAssertEqual(refreshedA, signer.url(4))
        XCTAssertEqual(loader.cachedURLCount, 1)
    }

    func testSlowSigningDoesNotExtendCacheLifetime() async {
        let signer = ControlledPhotoSigner()
        var now = Date(timeIntervalSince1970: 100)
        let loader = PhotoURLLoader(signer: signer.sign, now: { now }, limits: .init(cacheLifetime: 10))
        let first = request(loader, "a")
        await waitUntil { signer.calls.count == 1 }
        now.addTimeInterval(11)
        signer.succeed(0)
        _ = await first.value
        XCTAssertEqual(loader.cachedURLCount, 0)
    }

    func testFailureIsSharedAndNextAttemptRetries() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer)
        let first = request(loader, "a")
        let second = request(loader, "a")
        await waitUntil { loader.pendingWaiterCount == 2 && signer.calls.count == 1 }
        signer.fail(0)
        let firstURL = await first.value
        let secondURL = await second.value
        XCTAssertNil(firstURL)
        XCTAssertNil(secondURL)
        XCTAssertEqual(loader.cachedURLCount, 0)
        let retry = request(loader, "a")
        await waitUntil { signer.calls.count == 2 }
        signer.succeed(1)
        let retryURL = await retry.value
        XCTAssertEqual(retryURL, signer.url(1))
    }

    func testForceRefreshBypassesCompletedCacheAndConcurrentRefreshesCoalesce() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer)
        let first = request(loader, "a")
        await waitUntil { signer.calls.count == 1 }
        signer.succeed(0)
        _ = await first.value
        let refresh = request(loader, "a", forceRefresh: true)
        let duplicateRefresh = request(loader, "a", forceRefresh: true)
        let normal = request(loader, "a")
        await waitUntil { loader.pendingWaiterCount == 3 && signer.calls.count == 2 }
        signer.succeed(1)
        for task in [refresh, duplicateRefresh, normal] {
            let url = await task.value
            XCTAssertEqual(url, signer.url(1))
        }
        XCTAssertEqual(signer.calls.count, 2)
    }

    func testForceRefreshJoinsExistingUncachedRequest() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer)
        let original = request(loader, "a")
        await waitUntil { signer.calls.count == 1 }
        let refresh = request(loader, "a", forceRefresh: true)
        await waitUntil { loader.pendingWaiterCount == 2 }
        signer.succeed(0)
        let originalURL = await original.value
        let refreshURL = await refresh.value
        XCTAssertEqual(originalURL, refreshURL)
        XCTAssertEqual(signer.calls.count, 1)
    }

    func testCancellingOneConsumerDoesNotCancelSharedSigner() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer)
        let cancelled = request(loader, "a")
        let remaining = request(loader, "a")
        await waitUntil { loader.pendingWaiterCount == 2 && signer.calls.count == 1 }
        cancelled.cancel()
        let cancelledURL = await cancelled.value
        XCTAssertNil(cancelledURL)
        XCTAssertEqual(loader.pendingWaiterCount, 1)
        signer.succeed(0)
        let remainingURL = await remaining.value
        XCTAssertEqual(remainingURL, signer.url(0))
        XCTAssertEqual(signer.cancelledAtCompletion, [false])
    }

    func testLastWaiterCancellationCannotFreeSlotBeforeUnderlyingSignerEnds() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer, concurrent: 1)
        let cancelled = request(loader, "a")
        await waitUntil { signer.calls.count == 1 }
        cancelled.cancel()
        let cancelledURL = await cancelled.value
        XCTAssertNil(cancelledURL)
        let replacement = request(loader, "a")
        await waitUntil { loader.pendingWaiterCount == 1 }
        XCTAssertEqual(signer.calls.count, 1)
        signer.succeed(0) // Deliberately ignores cancellation until completion.
        await waitUntil { signer.calls.count == 2 }
        XCTAssertEqual(loader.cachedURLCount, 0)
        signer.succeed(1)
        let replacementURL = await replacement.value
        XCTAssertEqual(replacementURL, signer.url(1))
        XCTAssertEqual(signer.maximumActive, 1)
        XCTAssertEqual(signer.cancelledAtCompletion, [true, false])
    }

    func testCancelledQueuedRequestNeverStartsAndSurvivingQueueAdvances() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer, concurrent: 1)
        let active = request(loader, "a")
        await waitUntil { signer.calls.count == 1 }
        let cancelled = request(loader, "b")
        await waitUntil { loader.pendingRequestCount == 2 }
        cancelled.cancel()
        _ = await cancelled.value
        let surviving = request(loader, "c")
        await waitUntil { loader.pendingRequestCount == 2 }
        signer.succeed(0)
        await waitUntil { signer.calls.count == 2 }
        XCTAssertEqual(signer.calls.map(\.path), ["a", "c"])
        signer.succeed(1)
        _ = await active.value
        _ = await surviving.value
    }

    func testAlreadyCancelledConsumerDoesNotSignOrUseCachedCapability() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer)
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await loader.url(path: "a", accessToken: "token")
        }
        let result = await cancelled.value
        XCTAssertNil(result)
        XCTAssertTrue(signer.calls.isEmpty)
    }

    func testResetDrainsActiveAndQueuedWaitersAndRejectsLateCompletion() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer, concurrent: 1)
        let old = request(loader, "a")
        await waitUntil { signer.calls.count == 1 }
        let queued = request(loader, "b")
        await waitUntil { loader.pendingRequestCount == 2 }
        loader.reset()
        let oldURL = await old.value
        let queuedURL = await queued.value
        XCTAssertNil(oldURL)
        XCTAssertNil(queuedURL)
        let current = request(loader, "a")
        await waitUntil { loader.pendingRequestCount == 1 }
        signer.succeed(0)
        await waitUntil { signer.calls.count == 2 }
        XCTAssertEqual(signer.calls.map(\.path), ["a", "a"])
        XCTAssertEqual(loader.cachedURLCount, 0)
        signer.succeed(1)
        let currentURL = await current.value
        XCTAssertEqual(currentURL, signer.url(1))
    }

    func testInvalidationPreventsLateRequestFromRepopulatingOrFinishingReplacement() async {
        let signer = ControlledPhotoSigner()
        let loader = makeLoader(signer, concurrent: 2)
        let old = request(loader, "a")
        await waitUntil { signer.calls.count == 1 }
        loader.invalidate(path: "a")
        let oldURL = await old.value
        XCTAssertNil(oldURL)
        let current = request(loader, "a")
        await waitUntil { signer.calls.count == 2 }
        signer.succeed(0)
        await waitUntil { loader.activeRequestCount == 1 }
        XCTAssertEqual(loader.pendingWaiterCount, 1)
        XCTAssertEqual(loader.cachedURLCount, 0)
        signer.succeed(1)
        _ = await current.value
        loader.invalidate(path: "a")
        XCTAssertEqual(loader.cachedURLCount, 0)
    }

    func testZeroCacheLimitAndNonpositiveConcurrencyStillCompleteWithoutCaching() async {
        let signer = ControlledPhotoSigner()
        let loader = PhotoURLLoader(signer: signer.sign, limits: .init(concurrentRequests: 0, cachedURLs: 0))
        let task = request(loader, "a")
        await waitUntil { signer.calls.count == 1 }
        signer.succeed(0)
        let url = await task.value
        XCTAssertNotNil(url)
        XCTAssertEqual(loader.cachedURLCount, 0)
    }

    func testStoreAccountSwitchDoesNotReuseCachedURLOrAcceptLateOldResult() async {
        let signer = ControlledPhotoSigner()
        var account: String? = "a"
        let store = VisitStore(credentials: { account.map { ($0, "token-\($0)") } }, photoURLSigner: signer.sign)
        let first = Task { await store.signedPhotoURL(path: "photo") }
        await waitUntil { signer.calls.count == 1 }
        account = "b"
        let second = Task { await store.signedPhotoURL(path: "photo") }
        await waitUntil { signer.calls.count == 2 }
        signer.succeed(0)
        let firstURL = await first.value
        XCTAssertNil(firstURL)
        signer.succeed(1)
        let secondURL = await second.value
        XCTAssertEqual(secondURL, signer.url(1))
        XCTAssertEqual(signer.calls.map(\.token), ["token-a", "token-b"])
        account = nil
        let signedOutURL = await store.signedPhotoURL(path: "photo")
        XCTAssertNil(signedOutURL)
        account = "b"
        let returning = Task { await store.signedPhotoURL(path: "photo") }
        await waitUntil { signer.calls.count == 3 }
        signer.succeed(2)
        _ = await returning.value
    }

    func testStoreResetProtectsSameAccountAndAToBToAFromLateCompletion() async {
        let signer = ControlledPhotoSigner()
        var account = "a"
        let store = VisitStore(credentials: { (account, "token-\(account)") }, photoURLSigner: signer.sign)
        let old = Task { await store.signedPhotoURL(path: "photo") }
        await waitUntil { signer.calls.count == 1 }
        let generation = store.photoSessionGeneration
        account = "b"
        store.reset()
        account = "a"
        store.reset()
        XCTAssertNotEqual(generation, store.photoSessionGeneration)
        let current = Task { await store.signedPhotoURL(path: "photo") }
        await waitUntil { signer.calls.count == 2 }
        signer.succeed(0)
        let oldURL = await old.value
        XCTAssertNil(oldURL)
        signer.succeed(1)
        let currentURL = await current.value
        XCTAssertEqual(currentURL, signer.url(1))
        store.reset() // A same-account reauthentication must also discard cache.
        let reauthenticated = Task { await store.signedPhotoURL(path: "photo") }
        await waitUntil { signer.calls.count == 3 }
        signer.succeed(2)
        _ = await reauthenticated.value
    }

    func testStoreRejectsResultWhenAccountChangesWithoutAnotherPhotoRequest() async {
        let signer = ControlledPhotoSigner()
        var account: String? = "a"
        let store = VisitStore(credentials: { account.map { ($0, "token") } }, photoURLSigner: signer.sign)
        let task = Task { await store.signedPhotoURL(path: "photo") }
        await waitUntil { signer.calls.count == 1 }
        account = nil
        signer.succeed(0)
        let result = await task.value
        XCTAssertNil(result)
    }

    func testPreviewCacheEnforcesByteAndEntryLRULimitsAndReplacementAccounting() {
        var cache = PhotoPreviewCache(maximumCount: 2, maximumBytes: 6)
        cache.insert(Data([1, 1]), for: "a")
        cache.insert(Data([2, 2]), for: "b")
        XCTAssertNotNil(cache.data(for: "a"))
        cache.insert(Data([3, 3]), for: "c")
        XCTAssertNil(cache.data(for: "b"))
        XCTAssertEqual(cache.byteCount, 4)
        cache.insert(Data([4, 4, 4, 4, 4]), for: "a")
        XCTAssertNil(cache.data(for: "c"))
        XCTAssertEqual(cache.byteCount, 5)
        XCTAssertEqual(cache.count, 1)
        cache.insert(Data(repeating: 0, count: 7), for: "a")
        XCTAssertNil(cache.data(for: "a"))
        XCTAssertEqual(cache.byteCount, 0)
        cache.insert(Data([1]), for: "a")
        cache.remove("a")
        cache.insert(Data([2]), for: "b")
        cache.removeAll()
        XCTAssertEqual(cache.byteCount, 0)
        XCTAssertEqual(cache.count, 0)
        var disabled = PhotoPreviewCache(maximumCount: 0, maximumBytes: 0)
        disabled.insert(Data(), for: "a")
        XCTAssertNil(disabled.data(for: "a"))
    }

    private func makeLoader(_ signer: ControlledPhotoSigner, concurrent: Int = 4) -> PhotoURLLoader {
        PhotoURLLoader(signer: signer.sign, limits: .init(concurrentRequests: concurrent))
    }

    private func request(_ loader: PhotoURLLoader, _ path: String, forceRefresh: Bool = false) -> Task<URL?, Never> {
        Task { await loader.url(path: path, accessToken: "token", forceRefresh: forceRefresh) }
    }

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !predicate(), Date() < deadline { await Task.yield() }
        XCTAssertTrue(predicate(), "Expected async work to reach the controlled checkpoint", file: file, line: line)
    }
}

/// Intentionally ignores cancellation while suspended, exercising the bounds
/// and stale-result guards even when a transport does not stop immediately.
@MainActor
private final class ControlledPhotoSigner {
    struct Call { let path: String; let token: String }
    private(set) var calls: [Call] = []
    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var active = 0
    private(set) var maximumActive = 0
    private(set) var cancelledAtCompletion: [Bool] = []

    func sign(path: String, token: String) async throws -> URL {
        let index = calls.count
        calls.append(Call(path: path, token: token))
        active += 1
        maximumActive = max(maximumActive, active)
        defer {
            active -= 1
            cancelledAtCompletion.append(Task.isCancelled)
        }
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }

    func url(_ index: Int) -> URL { URL(string: "https://photos.example.test/signed/\(index)")! }
    func succeed(_ index: Int) { continuations.removeValue(forKey: index)?.resume(returning: url(index)) }
    func fail(_ index: Int) { continuations.removeValue(forKey: index)?.resume(throwing: URLError(.notConnectedToInternet)) }
}
