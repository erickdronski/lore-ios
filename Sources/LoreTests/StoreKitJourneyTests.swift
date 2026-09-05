import Foundation
import StoreKit
import StoreKitTest
import XCTest
@testable import Lore

/// Real local StoreKit engine, real service entry points, and an isolated HTTP
/// stub for Lore's verifier. No App Store payment or production request occurs.
/// SKTestSession has one shared environment, so this target runs serially.
@MainActor
final class StoreKitJourneyTests: XCTestCase {
    private var engine: SKTestSession!
    private var service: StoreKitService!
    private let userA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    override func setUpWithError() throws {
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Lore", withExtension: "storekit"))
        engine = try SKTestSession(contentsOf: configuration)
        engine.resetToDefaultState()
        engine.disableDialogs = true
        guard engine.disableDialogs else {
            throw NSError(domain: "StoreKitJourneyTests.LocalEngineUnavailable", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "StoreKitTest could not activate its local environment; refusing any Sandbox purchase."])
        }
        engine.timeRate = .realTime
        engine.clearTransactions()
        service = StoreKitService()
    }

    override func tearDownWithError() throws {
        service = nil
        StoreKitVerifierProtocol.handler = nil
        engine?.clearTransactions()
        engine?.resetToDefaultState()
        engine = nil
    }

    func testGuestPurchaseUnlocksAndFinishesWithoutLoreRegistration() async throws {
        service.onVerifiedTransaction = { _ in .acceptedWithoutServerGrant }
        await service.loadProducts()
        XCTAssertNotNil(service.product(for: StoreKitService.ProductID.lifetime))

        let outcome = await service.purchase(productID: StoreKitService.ProductID.lifetime)

        XCTAssertEqual(outcome, .success(trialing: false))
        XCTAssertTrue(service.hasActiveEntitlement)
        let membership = EntitlementStore()
        membership.storeKit = service
        XCTAssertTrue(membership.isPlus)
        let receipt = try await currentTransaction(productID: StoreKitService.ProductID.lifetime)
        XCTAssertNil(receipt.appAccountToken)
        XCTAssertEqual(receipt.environment, .xcode)
        let unfinished = await unfinishedIDs()
        XCTAssertFalse(unfinished.contains(receipt.id))
    }

    func testSignedInPurchasePostsRealJWSOnVersionedEndpointBeforeFinishing() async throws {
        service.accountUUID = userA
        let api = mockedAPI()
        var postedOriginalID: String?
        let userID = userA
        StoreKitVerifierProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/functions/v1/sync-apple-purchase")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer integration-access")
            let body = try Self.requestBody(request)
            let requestJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            let jws = try XCTUnwrap(requestJSON["signed_transaction"])
            let claims = try Self.claims(jws)
            XCTAssertEqual((claims["appAccountToken"] as? String)?.lowercased(), userID.uuidString.lowercased())
            let originalID = try XCTUnwrap(claims["originalTransactionId"] as? String)
            postedOriginalID = originalID
            return try Self.response(request, body: [
                "recorded": true, "original_transaction_id": originalID,
                "bound_user_id": userID.uuidString, "grants_access": true
            ])
        }
        service.onVerifiedTransaction = { jws in
            do {
                return .init(response: try await api.syncApplePurchase(signedTransaction: jws, accessToken: "integration-access"))
            } catch {
                XCTFail("Mocked verifier request failed: \(error)")
                return .failed
            }
        }
        await service.loadProducts()

        let outcome = await service.purchase(productID: StoreKitService.ProductID.lifetime)

        XCTAssertEqual(outcome, .success(trialing: false))
        XCTAssertTrue(service.hasActiveEntitlement)
        let receipt = try await currentTransaction(productID: StoreKitService.ProductID.lifetime)
        XCTAssertEqual(receipt.appAccountToken, userA)
        XCTAssertEqual(postedOriginalID, String(receipt.originalID))
        let unfinished = await unfinishedIDs()
        XCTAssertFalse(unfinished.contains(receipt.id))
        service.accountUUID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        XCTAssertFalse(service.hasActiveEntitlement, "The signed Apple account token must not unlock a different Lore user")
        service.accountUUID = userA
        XCTAssertTrue(service.hasActiveEntitlement)
    }

    func testRestoreAndNewServiceRecoverGuestPurchaseFromAppleHistory() async throws {
        _ = try await engine.buyProduct(identifier: StoreKitService.ProductID.lifetime)
        service.onVerifiedTransaction = { _ in .acceptedWithoutServerGrant }

        let restored = await service.restore()

        XCTAssertEqual(restored, .restored)
        XCTAssertTrue(service.hasActiveEntitlement)
        let relaunched = StoreKitService()
        await relaunched.refreshEntitlements(syncWithServer: false)
        XCTAssertTrue(relaunched.hasActiveEntitlement)
        XCTAssertEqual(relaunched.accessKind, .lifetime)
    }

    func testRefundUpdateClosesLocalAccessEvenWhenServerIsOffline() async throws {
        service.onVerifiedTransaction = { _ in .acceptedWithoutServerGrant }
        await service.loadProducts()
        let purchase = await service.purchase(productID: StoreKitService.ProductID.lifetime)
        XCTAssertEqual(purchase, .success(trialing: false))
        let transaction = try XCTUnwrap(engine.allTransactions().first)
        service.onVerifiedTransaction = { _ in .failed }
        service.start()
        await service.refreshEntitlements(syncWithServer: false)
        XCTAssertTrue(service.hasActiveEntitlement)

        try engine.refundTransaction(identifier: transaction.identifier)

        try await eventually { !self.service.hasActiveEntitlement }
        XCTAssertFalse(service.hasActiveEntitlement)
        let membership = EntitlementStore()
        membership.storeKit = service
        XCTAssertFalse(membership.isPlus)
    }

    func testPaidGuestKeepsAccessWhileFailedVerifierLeavesReceiptUnfinished() async throws {
        service.onVerifiedTransaction = { _ in .failed }
        await service.loadProducts()

        let outcome = await service.purchase(productID: StoreKitService.ProductID.lifetime)

        XCTAssertEqual(outcome, .success(trialing: false))
        XCTAssertTrue(service.hasActiveEntitlement)
        XCTAssertNotNil(service.lastError)
        let receipt = try await currentTransaction(productID: StoreKitService.ProductID.lifetime)
        let unfinished = await unfinishedIDs()
        XCTAssertTrue(unfinished.contains(receipt.id), "A failed server post must remain replayable")
    }

    func testSubscriptionExpirationClosesAccessAfterEngineRefresh() async throws {
        _ = try await engine.buyProduct(identifier: StoreKitService.ProductID.monthly, options: [.appAccountToken(userA)])
        service.accountUUID = userA
        await service.refreshEntitlements(syncWithServer: false)
        XCTAssertTrue(service.hasActiveEntitlement)

        try engine.expireSubscription(productIdentifier: StoreKitService.ProductID.monthly)
        await service.refreshEntitlements(syncWithServer: false)

        XCTAssertFalse(service.hasActiveEntitlement)
        XCTAssertNil(service.activeProductID)
    }

    private func currentTransaction(productID: String) async throws -> StoreKit.Transaction {
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == productID { return transaction }
        }
        XCTFail("No verified current transaction for \(productID)")
        throw NSError(domain: "StoreKitJourneyTests", code: 1)
    }

    private func unfinishedIDs() async -> Set<UInt64> {
        var ids = Set<UInt64>()
        for await result in StoreKit.Transaction.unfinished {
            if case .verified(let transaction) = result { ids.insert(transaction.id) }
        }
        return ids
    }

    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(condition(), "Expected StoreKit's update to arrive within five seconds")
    }

    private func mockedAPI() -> LoreAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StoreKitVerifierProtocol.self]
        return LoreAPI(session: URLSession(configuration: config))
    }

    nonisolated private static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }

    /// The mock examines the engine's JWS to build its response. Production
    /// verification remains server-side; this is never an unsigned access path.
    nonisolated private static func claims(_ jws: String) throws -> [String: Any] {
        let components = jws.split(separator: ".")
        XCTAssertEqual(components.count, 3)
        var payload = String(components[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    nonisolated private static func response(_ request: URLRequest, body: [String: Any]) throws -> (HTTPURLResponse, Data) {
        let http = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
        return (http, try JSONSerialization.data(withJSONObject: body))
    }
}

private final class StoreKitVerifierProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.notConnectedToInternet) }
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
