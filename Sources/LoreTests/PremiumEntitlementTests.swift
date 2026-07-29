import XCTest
@testable import Lore

@MainActor
final class PremiumEntitlementTests: XCTestCase {
    func testEntitlementDecodesAppleEnvironmentAndFractionalExpiry() throws {
        let production = try decodeEntitlement(
            environment: "Production",
            expiresAt: "2026-07-28T15:00:00.250Z"
        )
        let sandbox = try decodeEntitlement(environment: "sandbox")
        let legacy = try decodeEntitlement(environment: nil)
        let unknown = try decodeEntitlement(environment: "Preview")

        XCTAssertEqual(production.environment, .production)
        XCTAssertNotNil(production.expiresAt)
        XCTAssertEqual(sandbox.environment, .sandbox)
        XCTAssertNil(legacy.environment)
        XCTAssertEqual(unknown.environment, .unknown)
    }

    func testProductionPolicyRejectsSandboxButPreservesProductionAndLegacyRows() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(EntitlementEnvironmentPolicy.production.grantsAccess(
            entitlement(.active, environment: .production),
            asOf: now
        ))
        XCTAssertTrue(EntitlementEnvironmentPolicy.production.grantsAccess(
            entitlement(.active),
            asOf: now
        ))
        XCTAssertFalse(EntitlementEnvironmentPolicy.production.grantsAccess(
            entitlement(.active, environment: .sandbox),
            asOf: now
        ))
        XCTAssertFalse(EntitlementEnvironmentPolicy.production.grantsAccess(
            entitlement(.active, environment: .unknown),
            asOf: now
        ))
    }

    func testSandboxPolicyAcceptsProductionSandboxAndLegacyRows() {
        let now = Date(timeIntervalSince1970: 10_000)

        for environment in [
            Entitlement.Environment.production,
            .sandbox,
            nil
        ] {
            XCTAssertTrue(EntitlementEnvironmentPolicy.sandbox.grantsAccess(
                entitlement(.active, environment: environment),
                asOf: now
            ))
        }
    }

    func testRuntimePolicyUsesDebugOrSandboxReceipt() {
        let sandboxReceipt = URL(fileURLWithPath: "/receipt/sandboxReceipt")
        let productionReceipt = URL(fileURLWithPath: "/receipt/receipt")

        XCTAssertEqual(
            EntitlementEnvironmentPolicy.resolved(
                receiptURL: sandboxReceipt,
                isDebugBuild: false
            ),
            .sandbox
        )
        XCTAssertEqual(
            EntitlementEnvironmentPolicy.resolved(
                receiptURL: productionReceipt,
                isDebugBuild: false
            ),
            .production
        )
        XCTAssertEqual(
            EntitlementEnvironmentPolicy.resolved(
                receiptURL: nil,
                isDebugBuild: true
            ),
            .sandbox
        )
        XCTAssertEqual(
            EntitlementEnvironmentPolicy.resolved(
                receiptURL: nil,
                isDebugBuild: false
            ),
            .production
        )
    }

    func testEntitlementExpiryBoundaryFailsClosed() {
        let expiry = Date(timeIntervalSince1970: 10_000)
        let grant = entitlement(
            .active,
            expiresAt: expiry,
            environment: .production
        )

        XCTAssertTrue(grant.isActive(asOf: expiry.addingTimeInterval(-0.001)))
        XCTAssertFalse(grant.isActive(asOf: expiry))
        XCTAssertFalse(grant.isActive(asOf: expiry.addingTimeInterval(0.001)))
    }

    func testEntitlementStoreAppliesEnvironmentPolicyToServerRows() {
        let now = Date(timeIntervalSince1970: 10_000)
        let sandboxGrant = entitlement(.active, environment: .sandbox)
        let productionStore = EntitlementStore(
            entitlement: sandboxGrant,
            now: { now },
            environmentPolicy: .production
        )
        let sandboxStore = EntitlementStore(
            entitlement: sandboxGrant,
            now: { now },
            environmentPolicy: .sandbox
        )

        XCTAssertFalse(productionStore.isPlus)
        XCTAssertTrue(sandboxStore.isPlus)
    }

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
            accountUUID: testAccountUUID,
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
            accountUUID: testAccountUUID,
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
            accountUUID: testAccountUUID,
            now: now
        )

        XCTAssertEqual(resolution.ownedProductIDs, [StoreKitService.ProductID.lifetime])
        XCTAssertEqual(
            resolution.tripPassExpiresAt,
            longPass.purchaseDate.addingTimeInterval(7 * 24 * 3_600)
        )
    }

    func testResolverRejectsAnotherLoreAccountsTransactions() {
        let now = Date(timeIntervalSince1970: 10_000)
        let otherAccount = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let lifetime = snapshot(id: StoreKitService.ProductID.lifetime)
        let pass = snapshot(id: StoreKitService.ProductID.pass72h, purchase: now)

        let switchedAccount = StoreEntitlementResolver.resolve(
            current: [lifetime],
            history: [pass],
            accountUUID: otherAccount,
            now: now
        )
        let signedOut = StoreEntitlementResolver.resolve(
            current: [lifetime],
            history: [pass],
            accountUUID: nil,
            now: now
        )

        XCTAssertTrue(switchedAccount.ownedProductIDs.isEmpty)
        XCTAssertNil(switchedAccount.tripPassExpiresAt)
        XCTAssertTrue(signedOut.ownedProductIDs.isEmpty)
        XCTAssertNil(signedOut.tripPassExpiresAt)
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
            now: verifiedAt.addingTimeInterval(EntitlementCachePolicy.maximumAge),
            environmentPolicy: .production
        ))
        XCTAssertNil(EntitlementCachePolicy.usable(
            record,
            for: "traveler-b",
            now: verifiedAt.addingTimeInterval(60),
            environmentPolicy: .production
        ))
        XCTAssertNil(EntitlementCachePolicy.usable(
            record,
            for: "traveler-a",
            now: verifiedAt.addingTimeInterval(EntitlementCachePolicy.maximumAge + 1),
            environmentPolicy: .production
        ))
        XCTAssertNil(EntitlementCachePolicy.usable(
            record,
            for: "traveler-a",
            now: verifiedAt.addingTimeInterval(-1),
            environmentPolicy: .production
        ))
    }

    func testOfflineCacheNeverReopensAnInactiveGrant() {
        let now = Date(timeIntervalSince1970: 100_000)
        for status in [Entitlement.Status.canceled, .expired, .unknown] {
            let record = CachedEntitlementRecord(
                entitlement: entitlement(status, userID: "traveler"),
                verifiedAt: now
            )
            XCTAssertNil(EntitlementCachePolicy.usable(
                record,
                for: "traveler",
                now: now,
                environmentPolicy: .production
            ))
        }
    }

    func testOfflineCacheHonorsEnvironmentPolicy() {
        let now = Date(timeIntervalSince1970: 100_000)
        let record = CachedEntitlementRecord(
            entitlement: entitlement(.active, environment: .sandbox),
            verifiedAt: now
        )

        XCTAssertNil(EntitlementCachePolicy.usable(
            record,
            for: "traveler",
            now: now,
            environmentPolicy: .production
        ))
        XCTAssertNotNil(EntitlementCachePolicy.usable(
            record,
            for: "traveler",
            now: now,
            environmentPolicy: .sandbox
        ))
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
        userID: String = "traveler",
        expiresAt: Date? = nil,
        environment: Entitlement.Environment? = nil
    ) -> Entitlement {
        Entitlement(
            userID: userID,
            entitlement: StoreKitService.entitlementName,
            status: status,
            expiresAt: expiresAt,
            environment: environment
        )
    }

    private func decodeEntitlement(
        environment: String?,
        expiresAt: String? = nil
    ) throws -> Entitlement {
        var json: [String: Any] = [
            "user_id": "traveler",
            "entitlement": StoreKitService.entitlementName,
            "status": "active"
        ]
        if let environment { json["environment"] = environment }
        if let expiresAt { json["expires_at"] = expiresAt }
        return try JSONDecoder().decode(
            Entitlement.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
    }

    private func snapshot(
        id: String,
        purchase: Date = Date(timeIntervalSince1970: 9_000),
        expiry: Date? = nil,
        revoked: Date? = nil,
        upgraded: Bool = false,
        introductory: Bool = false,
        ownership: StoreEntitlementSnapshot.Ownership = .purchased,
        appAccountToken: UUID? = UUID(uuidString: "11111111-1111-1111-1111-111111111111")
    ) -> StoreEntitlementSnapshot {
        StoreEntitlementSnapshot(
            productID: id,
            purchaseDate: purchase,
            expirationDate: expiry,
            revocationDate: revoked,
            isUpgraded: upgraded,
            isIntroductory: introductory,
            ownership: ownership,
            appAccountToken: appAccountToken
        )
    }

    private var testAccountUUID: UUID {
        UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    }

    private func base64URL(_ object: [String: String]) throws -> String {
        try JSONSerialization.data(withJSONObject: object)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
