import XCTest
@testable import Lore

@MainActor
final class PremiumEntitlementTests: XCTestCase {
    func testServerStatusesPreserveGraceButFailClosedAfterCancellationOrExpiration() {
        XCTAssertTrue(entitlement(.active).isActive)
        XCTAssertTrue(entitlement(.trialing).isActive)
        XCTAssertTrue(entitlement(.gracePeriod).isActive)
        XCTAssertFalse(entitlement(.canceled).isActive)
        XCTAssertFalse(entitlement(.expired).isActive)
        XCTAssertFalse(entitlement(.unknown).isActive)
    }

    func testResolverAcceptsVerifiedFamilySharingAndIntroductoryAccess() {
        let now = Date(timeIntervalSince1970: 10_000)
        let shared = snapshot(
            id: StoreKitService.ProductID.annual,
            expiry: now.addingTimeInterval(3_600),
            introductory: true,
            ownership: .familyShared
        )

        let resolution = StoreEntitlementResolver.resolve(
            current: [shared],
            history: [],
            now: now
        )

        XCTAssertEqual(resolution.ownedProductIDs, [StoreKitService.ProductID.annual])
        XCTAssertTrue(resolution.isInIntroPeriod)
        XCTAssertTrue(resolution.includesFamilySharedAccess)
    }

    func testResolverRejectsExpiredRevokedAndUpgradedTransactions() {
        let now = Date(timeIntervalSince1970: 10_000)
        let expired = snapshot(
            id: StoreKitService.ProductID.monthly,
            expiry: now
        )
        let revoked = snapshot(
            id: StoreKitService.ProductID.annual,
            expiry: now.addingTimeInterval(3_600),
            revoked: now.addingTimeInterval(-60)
        )
        let upgraded = snapshot(
            id: StoreKitService.ProductID.monthly,
            expiry: now.addingTimeInterval(3_600),
            upgraded: true
        )

        let resolution = StoreEntitlementResolver.resolve(
            current: [expired, revoked, upgraded],
            history: [],
            now: now
        )

        XCTAssertTrue(resolution.ownedProductIDs.isEmpty)
        XCTAssertFalse(resolution.isInIntroPeriod)
        XCTAssertFalse(resolution.includesFamilySharedAccess)
    }

    func testResolverKeepsLifetimeAndUsesLatestTripPassWindow() {
        let now = Date(timeIntervalSince1970: 10_000)
        let lifetime = snapshot(id: StoreKitService.ProductID.lifetime)
        let shortPass = snapshot(
            id: StoreKitService.ProductID.pass72h,
            purchase: now.addingTimeInterval(-3_600)
        )
        let longPass = snapshot(
            id: StoreKitService.ProductID.pass7d,
            purchase: now.addingTimeInterval(-7_200)
        )

        let resolution = StoreEntitlementResolver.resolve(
            current: [lifetime],
            history: [shortPass, longPass],
            now: now
        )

        XCTAssertEqual(resolution.ownedProductIDs, [StoreKitService.ProductID.lifetime])
        XCTAssertEqual(
            resolution.tripPassExpiresAt,
            longPass.purchaseDate.addingTimeInterval(7 * 24 * 3_600)
        )
    }

    func testOfflineCacheIsIdentityBoundActiveAndTimeLimited() {
        let verifiedAt = Date(timeIntervalSince1970: 100_000)
        let record = CachedEntitlementRecord(
            entitlement: entitlement(.active, userID: "traveler-a"),
            verifiedAt: verifiedAt
        )

        XCTAssertNotNil(EntitlementCachePolicy.usable(
            record,
            for: "traveler-a",
            now: verifiedAt.addingTimeInterval(EntitlementCachePolicy.maximumAge)
        ))
        XCTAssertNil(EntitlementCachePolicy.usable(
            record,
            for: "traveler-b",
            now: verifiedAt.addingTimeInterval(60)
        ))
        XCTAssertNil(EntitlementCachePolicy.usable(
            record,
            for: "traveler-a",
            now: verifiedAt.addingTimeInterval(EntitlementCachePolicy.maximumAge + 1)
        ))
        XCTAssertNil(EntitlementCachePolicy.usable(
            record,
            for: "traveler-a",
            now: verifiedAt.addingTimeInterval(-1)
        ))
    }

    func testOfflineCacheNeverReopensAnInactiveGrant() {
        let now = Date(timeIntervalSince1970: 100_000)
        for status in [Entitlement.Status.canceled, .expired, .unknown] {
            let record = CachedEntitlementRecord(
                entitlement: entitlement(status, userID: "traveler"),
                verifiedAt: now
            )
            XCTAssertNil(EntitlementCachePolicy.usable(record, for: "traveler", now: now))
        }
    }

    func testJWTSubjectBindsCacheToAuthenticatedTraveler() throws {
        let header = try base64URL(["alg": "none"])
        let payload = try base64URL(["sub": "traveler-42"])

        XCTAssertEqual(
            EntitlementCachePolicy.userID(fromJWT: "\(header).\(payload).signature"),
            "traveler-42"
        )
        XCTAssertNil(EntitlementCachePolicy.userID(fromJWT: "not-a-jwt"))
    }

    func testColdPaywallNeverInventsPriceOrTrialEligibility() {
        let model = PaywallModel()

        XCTAssertNil(model.displayPriceLine(for: .annual))
        XCTAssertNil(model.trialDurationDescription)
        XCTAssertFalse(model.isEligibleForTrial)
        XCTAssertFalse(model.hasCheckedEligibility)
        XCTAssertFalse(model.canPurchaseSelectedPlan)
        XCTAssertEqual(model.ctaTitle, "Continue with Apple")
        XCTAssertTrue(model.finePrintText.contains("No purchase can begin"))
    }

    func testStoreKitConfigurationMatchesRuntimeCoreProducts() throws {
        let bundle = Bundle(for: Self.self)
        let configurationURL = try XCTUnwrap(
            bundle.url(forResource: "Lore", withExtension: "storekit")
        )
        let data = try Data(contentsOf: configurationURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        let groups = try XCTUnwrap(json["subscriptionGroups"] as? [[String: Any]])
        let group = try XCTUnwrap(groups.first)
        let subscriptions = try XCTUnwrap(group["subscriptions"] as? [[String: Any]])

        let recurringIDs = Set(subscriptions.compactMap { $0["productID"] as? String })
        XCTAssertEqual(recurringIDs, Set(StoreKitService.ProductID.requiredSubscriptions))
        XCTAssertEqual(products.first?["productID"] as? String, StoreKitService.ProductID.lifetime)
        XCTAssertEqual(products.first?["type"] as? String, "NonConsumable")

        for subscription in subscriptions {
            let offer = try XCTUnwrap(subscription["introductoryOffer"] as? [String: Any])
            XCTAssertEqual(offer["paymentMode"] as? String, "free")
            XCTAssertEqual(offer["subscriptionPeriod"] as? String, "P1W")
            XCTAssertNotNil(subscription["familyShareable"] as? Bool)
        }
    }

    private func entitlement(
        _ status: Entitlement.Status,
        userID: String = "traveler"
    ) -> Entitlement {
        Entitlement(userID: userID, entitlement: StoreKitService.entitlementName, status: status)
    }

    private func snapshot(
        id: String,
        purchase: Date = Date(timeIntervalSince1970: 9_000),
        expiry: Date? = nil,
        revoked: Date? = nil,
        upgraded: Bool = false,
        introductory: Bool = false,
        ownership: StoreEntitlementSnapshot.Ownership = .purchased
    ) -> StoreEntitlementSnapshot {
        StoreEntitlementSnapshot(
            productID: id,
            purchaseDate: purchase,
            expirationDate: expiry,
            revocationDate: revoked,
            isUpgraded: upgraded,
            isIntroductory: introductory,
            ownership: ownership
        )
    }

    private func base64URL(_ object: [String: String]) throws -> String {
        try JSONSerialization.data(withJSONObject: object)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
