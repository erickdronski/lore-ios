import Foundation
import XCTest
@testable import Lore

final class LoreNetworkResilienceTests: XCTestCase {
    override func tearDown() {
        NetworkStubProtocol.handler = nil
        super.tearDown()
    }

    func testApplePurchaseSyncPreservesVersionedEndpointAndOwnershipResponse() async throws {
        NetworkStubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/functions/v1/sync-apple-purchase")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"recorded":true,"original_transaction_id":"purchase-1","bound_user_id":"11111111-1111-4111-8111-111111111111","grants_access":true}"#.utf8))
        }
        let result = try await makeAPI().syncApplePurchase(signedTransaction: "test.signed.receipt", accessToken: "test-access")
        XCTAssertTrue(result.recorded)
        XCTAssertEqual(result.originalTransactionID, "purchase-1")
        XCTAssertEqual(result.grantsAccess, true)
    }

    func testDeletionContinuesPendingBatchesWithSameAccessToken() async throws {
        var requests = 0
        NetworkStubProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.path, "/functions/v1/delete-account")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer original-access")
            let code = requests < 3 ? 202 : 200
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: code, httpVersion: nil, headerFields: nil)!, Data())
        }
        let result = try await AccountDeletionClient.delete(accessToken: "original-access", session: makeSession(), retryDelay: .zero)
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(requests, 3)
    }

    func testDeletionRemainsPendingAfterBoundedAttempts() async throws {
        var requests = 0
        NetworkStubProtocol.handler = { request in
            requests += 1
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 202, httpVersion: nil, headerFields: nil)!, Data())
        }
        let result = try await AccountDeletionClient.delete(accessToken: "original-access", session: makeSession(), maximumAttempts: 2, retryDelay: .zero)
        XCTAssertEqual(result.statusCode, 202)
        XCTAssertEqual(requests, 2)
    }

    func testDeletionKeepsPendingStateWhenLaterCleanupRequestLosesNetwork() async throws {
        var requests = 0
        NetworkStubProtocol.handler = { request in
            requests += 1
            if requests > 1 { throw URLError(.notConnectedToInternet) }
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 202, httpVersion: nil, headerFields: nil)!, Data())
        }
        let result = try await AccountDeletionClient.delete(accessToken: "original-access", session: makeSession(), retryDelay: .zero)
        XCTAssertEqual(result.statusCode, 202)
        XCTAssertEqual(requests, 2)
    }

    func testDeletionStopsPollingAtTimeBudgetWithoutPretendingCompletion() async throws {
        var requests = 0
        NetworkStubProtocol.handler = { request in
            requests += 1
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 202, httpVersion: nil, headerFields: nil)!, Data())
        }
        let result = try await AccountDeletionClient.delete(accessToken: "original-access", session: makeSession(), retryDelay: .zero, maximumDuration: .zero)
        XCTAssertEqual(result.statusCode, 202)
        XCTAssertEqual(requests, 1)
    }

    func testSuccessfulResponseDecodes() async throws {
        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data("[{\"place_id\":\"one\"},{\"place_id\":\"two\"}]".utf8))
        }

        let result = try await makeAPI().placesWithOffers(placeIDs: ["one", "two"])

        XCTAssertEqual(result, Set(["one", "two"]))
    }

    func testHTTPFailureKeepsServerBodyOutOfUserFacingError() async throws {
        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("private backend diagnostic".utf8))
        }

        do {
            _ = try await makeAPI().placesWithOffers(placeIDs: ["one"])
            XCTFail("Expected an HTTP error")
        } catch let error as LoreAPI.APIError {
            XCTAssertEqual(
                error.localizedDescription,
                "Lore's service is having trouble. Please try again shortly."
            )
            XCTAssertFalse(error.localizedDescription.contains("private backend diagnostic"))
        }
    }

    func testMalformedJSONProducesSafeDecodingMessage() async throws {
        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("not-json".utf8))
        }

        do {
            _ = try await makeAPI().placesWithOffers(placeIDs: ["one"])
            XCTFail("Expected a decoding error")
        } catch let error as LoreAPI.APIError {
            XCTAssertEqual(error.localizedDescription, "Lore couldn't read that response. Please try again.")
        }
    }

    func testCancellationDoesNotReturnAStaleAtlasPayload() async throws {
        let cache = AtlasCache()
        let url = try XCTUnwrap(URL(string: "https://example.com/atlas/\(UUID().uuidString)"))
        let request = URLRequest(url: url)
        let session = makeSession()

        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("cached".utf8))
        }
        _ = try await cache.data(for: request, session: session, freshFor: -1)

        // Leaving the protocol unanswered makes the second request wait until
        // cancellation. Before the cancellation guard, AtlasCache returned the
        // stale bytes and allowed an obsolete screen task to keep running.
        NetworkStubProtocol.handler = nil
        let task = Task {
            try await cache.data(for: request, session: session, freshFor: -1)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled atlas request must not return stale data")
        } catch is CancellationError {
            // Expected on newer URLSession implementations.
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        }
    }

    func testDisabledContractPreservesLegacyStaleFallback() async throws {
        let provider = TestContentContractProvider(.compatibility)
        let clock = TestClock()
        let (cache, root) = try makeCache(provider: provider, clock: clock)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/legacy")))
        let session = makeSession()

        stubSuccess(body: "legacy")
        _ = try await cache.data(for: request, session: session, freshFor: -1)
        clock.advance(hours: 72)
        stubOfflineFailure()

        let fallback = try await cache.data(for: request, session: session, freshFor: -1)
        XCTAssertEqual(String(data: fallback, encoding: .utf8), "legacy")
    }

    func testEnforcementRejectsAndPurgesLegacyURLCacheBytes() async throws {
        let provider = TestContentContractProvider(.compatibility)
        let clock = TestClock()
        let (cache, root) = try makeCache(provider: provider, clock: clock)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/pre-gate")))
        let session = makeSession()

        stubSuccess(body: "unreviewed")
        _ = try await cache.data(for: request, session: session, freshFor: -1)
        await provider.set(enforcedContract())
        stubOfflineFailure()

        await XCTAssertThrowsAsyncError(
            try await cache.data(for: request, session: session, freshFor: -1)
        )
        let cacheFiles = try FileManager.default.contentsOfDirectory(
            at: root.appending(path: "cache"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(cacheFiles.map(\.lastPathComponent), [".content-contract"])
    }

    func testEnforcementRejectsMismatchedReviewEpoch() async throws {
        let provider = TestContentContractProvider(enforcedContract(epoch: "review-1"))
        let clock = TestClock()
        let (cache, root) = try makeCache(provider: provider, clock: clock)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/epoch")))
        let session = makeSession()

        stubSuccess(body: "review-1")
        _ = try await cache.data(for: request, session: session, freshFor: -1)
        await provider.set(enforcedContract(epoch: "review-2"))
        stubOfflineFailure()

        await XCTAssertThrowsAsyncError(
            try await cache.data(for: request, session: session, freshFor: -1)
        )
    }

    func testEnforcementRejectsExpiredContent() async throws {
        let provider = TestContentContractProvider(enforcedContract(maxAgeHours: 1))
        let clock = TestClock()
        let (cache, root) = try makeCache(provider: provider, clock: clock)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/expired")))
        let session = makeSession()

        stubSuccess(body: "current")
        _ = try await cache.data(for: request, session: session, freshFor: -1)
        clock.advance(hours: 2)
        stubOfflineFailure()

        await XCTAssertThrowsAsyncError(
            try await cache.data(for: request, session: session, freshFor: -1)
        )
    }

    func testEnforcementReturnsCurrentGenerationWithinOfflineAge() async throws {
        let provider = TestContentContractProvider(enforcedContract(maxAgeHours: 24))
        let clock = TestClock()
        let (cache, root) = try makeCache(provider: provider, clock: clock)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/current")))
        let session = makeSession()

        stubSuccess(body: "current")
        _ = try await cache.data(for: request, session: session, freshFor: -1)
        clock.advance(hours: 2)
        stubOfflineFailure()

        let fallback = try await cache.data(for: request, session: session, freshFor: -1)
        XCTAssertEqual(String(data: fallback, encoding: .utf8), "current")
    }

    func testContractEndpointUnavailableDefaultsToCompatibility() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "lore-contract-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentContractStore(persistedFile: root.appending(path: "contract.json"))

        NetworkStubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/v1/content_contract")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        let contract = await store.current(session: makeSession(), forceRefresh: true)
        XCTAssertEqual(contract, .compatibility)
    }

    func testContractEndpointOutageRetainsLastEnforcedSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "lore-contract-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentContractStore(persistedFile: root.appending(path: "contract.json"))
        let expected = enforcedContract()

        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, try JSONEncoder().encode([expected]))
        }
        let fetched = await store.current(session: makeSession(), forceRefresh: true)
        XCTAssertEqual(fetched, expected)

        stubOfflineFailure()
        let retained = await store.current(session: makeSession(), forceRefresh: true)
        XCTAssertEqual(retained, expected)
    }

    func testMalformedContractResponseFailsClosedWithoutPriorSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "lore-contract-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentContractStore(persistedFile: root.appending(path: "contract.json"))

        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("[{\"contract_version\":3}]".utf8))
        }

        let contract = await store.current(session: makeSession(), forceRefresh: true)
        XCTAssertEqual(contract, .cacheRejection)
        XCTAssertTrue(contract.enforcementEnabled)
        XCTAssertFalse(contract.isValidForEnforcement)

        let repeated = await store.current(session: makeSession(), forceRefresh: false)
        XCTAssertEqual(repeated, .cacheRejection)

        stubOfflineFailure()
        let restarted = ContentContractStore(persistedFile: root.appending(path: "contract.json"))
        let retained = await restarted.current(session: makeSession(), forceRefresh: true)
        XCTAssertEqual(retained, .cacheRejection)
    }

    func testConcurrentInitialContractReadsAwaitOneResolution() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "lore-contract-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentContractStore(persistedFile: root.appending(path: "contract.json"))
        let expected = enforcedContract()
        let requestCount = TestCounter()

        NetworkStubProtocol.handler = { request in
            requestCount.increment()
            Thread.sleep(forTimeInterval: 0.1)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, try JSONEncoder().encode([expected]))
        }

        async let first = store.current(session: makeSession(), forceRefresh: true)
        async let second = store.current(session: makeSession(), forceRefresh: false)
        let values = await [first, second]

        XCTAssertEqual(values, [expected, expected])
        XCTAssertEqual(requestCount.value, 1)
    }

    func testObservedEnforcementCannotDowngradeToDisabledContract() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "lore-contract-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentContractStore(persistedFile: root.appending(path: "contract.json"))
        let expected = enforcedContract()

        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, try JSONEncoder().encode([expected]))
        }
        let enforced = await store.current(session: makeSession(), forceRefresh: true)
        XCTAssertEqual(enforced, expected)

        let disabled = ContentContract.compatibility
        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, try JSONEncoder().encode([disabled]))
        }
        let retained = await store.current(session: makeSession(), forceRefresh: true)
        XCTAssertEqual(retained, expected)
    }

    func testClockRollbackForcesContractRefresh() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "lore-contract-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = TestClock()
        let store = ContentContractStore(
            persistedFile: root.appending(path: "contract.json"),
            now: { clock.current() }
        )

        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, try JSONEncoder().encode([ContentContract.compatibility]))
        }
        _ = await store.current(session: makeSession(), forceRefresh: true)

        let expected = enforcedContract()
        clock.advance(hours: -1)
        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, try JSONEncoder().encode([expected]))
        }

        let refreshed = await store.current(session: makeSession())
        XCTAssertEqual(refreshed, expected)
    }

    func testUnsupportedContractVersionRejectsCachedBytes() async throws {
        let provider = TestContentContractProvider(.compatibility)
        let clock = TestClock()
        let (cache, root) = try makeCache(provider: provider, clock: clock)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/version")))
        let session = makeSession()

        stubSuccess(body: "legacy")
        _ = try await cache.data(for: request, session: session, freshFor: -1)
        await provider.set(enforcedContract(version: "3"))
        stubOfflineFailure()

        await XCTAssertThrowsAsyncError(
            try await cache.data(for: request, session: session, freshFor: -1)
        )
    }

    private func makeAPI() -> LoreAPI {
        LoreAPI(session: makeSession())
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeCache(
        provider: TestContentContractProvider,
        clock: TestClock
    ) throws -> (AtlasCache, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "lore-atlas-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cacheDirectory = root.appending(path: "cache", directoryHint: .isDirectory)
        let pinDirectory = root.appending(path: "pins", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            AtlasCache(
                directory: cacheDirectory,
                pinDirectory: pinDirectory,
                contractProvider: provider,
                now: { clock.current() }
            ),
            root
        )
    }

    private func enforcedContract(
        version: String = "2",
        epoch: String = "review-1",
        maxAgeHours: Int = 24
    ) -> ContentContract {
        ContentContract(
            contractVersion: version,
            reviewEpoch: epoch,
            enforcementEnabled: true,
            offlineMaxAgeHours: maxAgeHours
        )
    }

    private func stubSuccess(body: String) {
        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(body.utf8))
        }
    }

    private func stubOfflineFailure() {
        NetworkStubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    }
}

private actor TestContentContractProvider: ContentContractProviding {
    private var contract: ContentContract

    init(_ contract: ContentContract) {
        self.contract = contract
    }

    func current(session: URLSession) async -> ContentContract {
        contract
    }

    func set(_ contract: ContentContract) {
        self.contract = contract
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()

    func current() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(hours: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(hours * 60 * 60)
        lock.unlock()
    }
}

private final class TestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private func XCTAssertThrowsAsyncError<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        // Expected.
    }
}

private final class NetworkStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
