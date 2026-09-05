import Foundation
import XCTest
@testable import Lore

@MainActor
final class PremiumLifecycleRegressionTests: XCTestCase {
    private let userA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let userB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "PremiumLifecycleRegressionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testExpiringCacheRoundTripsAndSupportsLegacyNumericDates() throws {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000.25)
        let record = CachedEntitlementRecord(entitlement: grant(expiry: expiry), verifiedAt: expiry.addingTimeInterval(-60))
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(CachedEntitlementRecord.self, from: data), record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entitlement = try XCTUnwrap(object["entitlement"] as? [String: Any])
        XCTAssertTrue(entitlement["expires_at"] is String)
        entitlement["expires_at"] = expiry.timeIntervalSinceReferenceDate
        object["entitlement"] = entitlement
        let legacy = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(CachedEntitlementRecord.self, from: legacy), record)
        entitlement["expires_at"] = "invalid-expiration"
        object["entitlement"] = entitlement
        XCTAssertThrowsError(try JSONDecoder().decode(CachedEntitlementRecord.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testFiniteMembershipCacheSurvivesRelaunchOfflineAndExpires() async throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let membership = grant(expiry: now.addingTimeInterval(3_600))
        let first = EntitlementStore(defaults: defaults, now: { now }, entitlementLoader: { _ in membership })
        await first.refresh(accessToken: token(userA))
        let restarted = EntitlementStore(defaults: defaults, now: { now }, entitlementLoader: { _ in throw URLError(.notConnectedToInternet) })
        await restarted.refresh(accessToken: token(userA))
        XCTAssertTrue(restarted.isPlus)
        XCTAssertTrue(restarted.isUsingCachedEntitlement)
        now = now.addingTimeInterval(3_600)
        XCTAssertFalse(restarted.isPlus)
        XCTAssertFalse(restarted.isUsingCachedEntitlement)
    }

    func testCachedAccessClosesAfter72HoursWithoutAnotherRefresh() async throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let membership = grant()
        var offline = false
        let store = EntitlementStore(defaults: defaults, now: { now }, entitlementLoader: { _ in
            if offline { throw URLError(.notConnectedToInternet) }
            return membership
        })
        await store.refresh(accessToken: token(userA))
        offline = true
        await store.refresh(accessToken: token(userA))
        XCTAssertTrue(store.isUsingCachedEntitlement)
        now = now.addingTimeInterval(EntitlementCachePolicy.maximumAge + 1)
        XCTAssertFalse(store.isPlus)
        XCTAssertFalse(store.isUsingCachedEntitlement)
        XCTAssertFalse(store.isTrialing)
    }

    func testCancelledOldAccountRequestCannotReopenCacheAfterSignOut() async throws {
        let membership = grant()
        var response: CheckedContinuation<Entitlement?, Error>?
        var delay = false
        let started = expectation(description: "old account request suspended")
        let store = EntitlementStore(defaults: defaults, entitlementLoader: { _ in
            if !delay { return membership }
            return try await withCheckedThrowingContinuation {
                response = $0
                started.fulfill()
            }
        })
        await store.refresh(accessToken: token(userA))
        delay = true
        let pending = Task { await store.refresh(accessToken: token(userA)) }
        await fulfillment(of: [started], timeout: 2)
        store.clear()
        await store.refresh(accessToken: nil)
        pending.cancel()
        response?.resume(throwing: URLError(.cancelled))
        await pending.value
        XCTAssertFalse(store.isPlus)
        XCTAssertFalse(store.isUsingCachedEntitlement)
        XCTAssertNil(store.entitlement)
        XCTAssertNil(store.lastError)
    }

    func testOldSuccessfulRequestCannotReplaceNewAccount() async throws {
        let membership = grant()
        let oldToken = token(userA)
        var response: CheckedContinuation<Entitlement?, Error>?
        let started = expectation(description: "old request suspended")
        let store = EntitlementStore(defaults: defaults, entitlementLoader: { accessToken in
            if accessToken != oldToken { return nil }
            return try await withCheckedThrowingContinuation {
                response = $0
                started.fulfill()
            }
        })
        let pending = Task { await store.refresh(accessToken: oldToken) }
        await fulfillment(of: [started], timeout: 2)
        await store.refresh(accessToken: token(userB))
        response?.resume(returning: membership)
        await pending.value
        XCTAssertFalse(store.isPlus)
        XCTAssertNil(store.entitlement)
    }

    func testExplicitAuthRejectionDoesNotReuseCachedMembership() async throws {
        let membership = grant()
        var reject = false
        let store = EntitlementStore(defaults: defaults, entitlementLoader: { _ in
            if reject { throw LoreAPI.APIError.http(status: 401, body: "") }
            return membership
        })
        await store.refresh(accessToken: token(userA))
        reject = true
        await store.refresh(accessToken: token(userA))
        XCTAssertFalse(store.isPlus)
        XCTAssertFalse(store.isUsingCachedEntitlement)
    }

    func testAlreadyCancelledRefreshCannotClearTheCurrentAccount() async {
        var requests = 0
        let membership = grant()
        let store = EntitlementStore(entitlement: membership, defaults: defaults, entitlementLoader: { _ in
            requests += 1
            return nil
        })
        let staleTask = Task { await store.refresh(accessToken: token(userB)) }
        staleTask.cancel()
        await staleTask.value
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(store.entitlement, membership)
        XCTAssertTrue(store.isPlus)
    }

    func testGuestReceiptRequiresConfirmedClaimAfterSignInAndHonorsServerDenial() {
        let now = Date()
        let guest = StoreEntitlementSnapshot(
            productID: StoreKitService.ProductID.monthly, purchaseDate: now,
            expirationDate: now.addingTimeInterval(3_600), revocationDate: nil,
            isUpgraded: false, isIntroductory: false, ownership: .purchased,
            appAccountToken: nil, originalTransactionID: "original-1"
        )
        func resolve(_ account: UUID?, bindings: [String: Bool] = [:]) -> StoreEntitlementResolution {
            StoreEntitlementResolver.resolve(current: [guest], history: [], accountUUID: account, serverBindings: bindings, now: now)
        }
        XCTAssertEqual(resolve(nil).ownedProductIDs, [StoreKitService.ProductID.monthly])
        XCTAssertTrue(resolve(userA).ownedProductIDs.isEmpty)
        XCTAssertEqual(resolve(userA, bindings: ["original-1": true]).ownedProductIDs, [StoreKitService.ProductID.monthly])
        XCTAssertTrue(resolve(userA, bindings: ["wrong-original": true]).ownedProductIDs.isEmpty)
        XCTAssertTrue(resolve(userA, bindings: ["original-1": false]).ownedProductIDs.isEmpty)
        XCTAssertTrue(resolve(userB).ownedProductIDs.isEmpty)
    }

    func testServerDenialSuppressesAnOtherwiseMatchingAccountReceipt() {
        let now = Date()
        let receipt = StoreEntitlementSnapshot(
            productID: StoreKitService.ProductID.lifetime, purchaseDate: now,
            expirationDate: nil, revocationDate: nil, isUpgraded: false,
            isIntroductory: false, ownership: .purchased, appAccountToken: userA,
            originalTransactionID: "refunded-purchase"
        )
        let denied = StoreEntitlementResolver.resolve(current: [receipt], history: [], accountUUID: userA,
            serverBindings: ["refunded-purchase": false], now: now)
        XCTAssertTrue(denied.ownedProductIDs.isEmpty)
    }

    func testRecordedRefundDoesNotClaimActiveServerEntitlement() throws {
        let body = Data("""
        {"recorded":true,"original_transaction_id":"original-1","bound_user_id":"\(userA.uuidString)","grants_access":false}
        """.utf8)
        let response = try JSONDecoder().decode(LoreAPI.ApplePurchaseSyncResponse.self, from: body)
        let outcome = StoreKitService.VerifiedTransactionSyncOutcome(response: response)
        XCTAssertTrue(outcome.canFinishTransaction)
        XCTAssertFalse(outcome.recordedServerEntitlement)
        XCTAssertEqual(outcome, .accountVerified(originalTransactionID: "original-1", userID: userA, grantsAccess: false))
    }

    private func grant(expiry: Date? = nil) -> Entitlement {
        Entitlement(userID: userA.uuidString, entitlement: "plus", status: .active, expiresAt: expiry, environment: .production)
    }

    private func token(_ userID: UUID) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["sub": userID.uuidString])
        return "e30." + data.base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") + ".test"
    }
}
