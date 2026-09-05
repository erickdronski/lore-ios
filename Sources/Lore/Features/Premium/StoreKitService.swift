import Foundation
import Observation
import StoreKit

/// A testable, StoreKit-independent projection of a verified transaction.
/// Keeping the policy pure makes revocation, expiration, upgrades, Family
/// Sharing, and trip-pass windows deterministic instead of simulator-only.
struct StoreEntitlementSnapshot: Equatable {
    enum Ownership: Equatable {
        case purchased
        case familyShared
    }

    let productID: String
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool
    let isIntroductory: Bool
    let ownership: Ownership
    let appAccountToken: UUID?
    var originalTransactionID: String? = nil
    var isSandbox: Bool = false
}

struct StoreEntitlementResolution: Equatable {
    let ownedProductIDs: Set<String>
    let tripPassExpiresAt: Date?
    let isInIntroPeriod: Bool
    let includesFamilySharedAccess: Bool
}

enum StoreEntitlementResolver {
    static func resolve(
        current: [StoreEntitlementSnapshot],
        history: [StoreEntitlementSnapshot],
        accountUUID: UUID?,
        serverBindings: [String: Bool] = [:],
        now: Date
    ) -> StoreEntitlementResolution {
        func belongsToCurrentAccount(_ snapshot: StoreEntitlementSnapshot) -> Bool {
            // Device purchases are usable without creating a Lore account.
            guard let accountUUID else { return true }
            if let originalID = snapshot.originalTransactionID,
               let confirmedAccess = serverBindings[originalID] {
                return confirmedAccess
            }
            // Account-bound receipts cannot unlock a different live Lore user.
            if let token = snapshot.appAccountToken { return token == accountUUID }
            // Sandbox cannot create a production server binding. Keep guest
            // testing usable on-device without granting any production cloud row.
            return snapshot.isSandbox
        }

        let active = current.filter { snapshot in
            guard belongsToCurrentAccount(snapshot) else { return false }
            guard StoreKitService.ProductID.subsAndLifetime.contains(snapshot.productID) else {
                return false
            }
            guard snapshot.revocationDate == nil, !snapshot.isUpgraded else { return false }
            guard let expiry = snapshot.expirationDate else { return true }
            return expiry > now
        }

        let passExpiry = history.compactMap { snapshot -> Date? in
            guard belongsToCurrentAccount(snapshot),
                  snapshot.revocationDate == nil,
                  let duration = StoreKitService.ProductID.passDuration(snapshot.productID)
            else { return nil }
            return snapshot.purchaseDate.addingTimeInterval(duration)
        }.max()

        return StoreEntitlementResolution(
            ownedProductIDs: Set(active.map(\.productID)),
            tripPassExpiresAt: passExpiry,
            isInIntroPeriod: active.contains(where: \.isIntroductory),
            includesFamilySharedAccess: active.contains { $0.ownership == .familyShared }
        )
    }
}

/// The **StoreKit 2** client path for Lore+, the on-device transaction engine.
///
/// StoreKit 2 is Lore's on-device purchase engine. Apple-signed transactions
/// are independently verified by Lore's first-party Edge Functions, which write
/// the server entitlement used by web and cloud-gated features. The local
/// transaction read keeps an account-scoped offline fallback without replacing
/// that server authority.
///
/// This service is that client path. It:
/// - loads the two products (`Product.products(for:)`),
/// - drives the native purchase sheet (`product.purchase()`),
/// - reads on-device entitlements (`Transaction.currentEntitlements`),
/// - listens for out-of-band changes (`Transaction.updates`),
/// - restores (`AppStore.sync()`),
/// - and reports StoreKit-authoritative free-trial eligibility and duration.
///
/// Lifecycle mirrors the other stores: `@Observable @MainActor`, one instance,
/// injected via the environment. `EntitlementStore` holds a reference and unions
/// `hasActiveEntitlement` into its `isPlus` answer.
@Observable
@MainActor
final class StoreKitService {
    /// The signed-in Lore account, set by the app whenever the session changes.
    ///
    /// Passed to `product.purchase()` as `appAccountToken`, so Apple echoes it
    /// in signed transactions and server notifications. Purchases made without
    /// a Lore account can later receive an authenticated initial server claim;
    /// an existing binding cannot be transferred to another live account.
    ///
    /// Nil leaves access with the verified Apple device account. Signed-in
    /// access remains scoped to its signed token or an authenticated server claim.
    var accountUUID: UUID? {
        didSet {
            guard oldValue != accountUUID else { return }
            refreshGeneration &+= 1
            serverBindings = [:]
            // Re-evaluate synchronously, before any old account request finishes.
            expirationRevision &+= 1
            scheduleExpiration()
        }
    }

    /// Called with a transaction's **JWS representation** so the app can post it
    /// to the server for entitlement recording. Set by the app before `start()`.
    ///
    /// It must be the JWS, not `Transaction.jsonRepresentation`: the server
    /// re-verifies Apple's signature over this exact string and trusts nothing
    /// the client asserts. Handing it unsigned JSON would let any caller mint
    /// itself a paid entitlement.
    var onVerifiedTransaction: ((String) async -> VerifiedTransactionSyncOutcome)?

    /// The Lore+ products, App Store Connect identifiers (docs/16 §1). IDs are
    /// price-agnostic on purpose: storefront pricing and offers may change
    /// without requiring new identifiers. `lifetime` is a non-consumable
    /// unlock; the subscriptions auto-renew.
    /// Any owned product confers Lore+ (see `isPlus`).
    enum ProductID {
        static let monthly = "lore_plus_monthly"
        static let annual = "lore_plus_annual"
        static let lifetime = "lore_plus_lifetime"
        /// Non-renewing Trip Passes for one-trip visitors (no recurring charge).
        /// Each grants Lore+ for a fixed window from its purchase date. Create
        /// these as **non-renewing subscription** products in App Store Connect.
        static let pass72h = "lore_pass_72h"
        static let pass7d = "lore_pass_7d"
        /// Subs + lifetime unlock (these appear in `currentEntitlements`).
        static let subsAndLifetime: [String] = [monthly, annual, lifetime]
        /// The non-renewing passes (tracked by purchase date + window).
        static let passes: [String] = [pass72h, pass7d]
        static let all: [String] = subsAndLifetime + passes
        /// The recurring plans are the minimum viable catalog. Lifetime and
        /// trip passes are optional and appear only when App Store Connect
        /// returns them.
        static let requiredSubscriptions: [String] = [monthly, annual]

        /// The access window a Trip Pass grants from its purchase date.
        static func passDuration(_ id: String) -> TimeInterval? {
            switch id {
            case pass72h: return 72 * 3600
            case pass7d: return 7 * 24 * 3600
            default: return nil
            }
        }
    }

    /// The `entitlements` grant name these products confer. Product ids are
    /// `lore_plus_*`; the grant itself is the cross-platform `plus` row.
    static let entitlementName = Entitlement.plusName

    enum VerifiedTransactionSyncOutcome: Equatable {
        /// Lore durably recorded a production Plus entitlement row.
        case recorded
        /// Lore verified/handled the transaction but intentionally did not grant
        /// a production row, for example a TestFlight/Sandbox purchase.
        case acceptedWithoutServerGrant
        /// An authenticated server verdict binds this purchase to one Lore user.
        case accountVerified(originalTransactionID: String, userID: UUID, grantsAccess: Bool)
        /// The app could not post or verify the transaction with Lore.
        case failed

        init(response: LoreAPI.ApplePurchaseSyncResponse) {
            if response.recorded,
               let originalID = response.originalTransactionID,
               let userID = response.boundUserID,
               let grantsAccess = response.grantsAccess {
                self = .accountVerified(originalTransactionID: originalID, userID: userID, grantsAccess: grantsAccess)
            } else {
                self = response.recorded ? .recorded : .acceptedWithoutServerGrant
            }
        }

        var canFinishTransaction: Bool { self != .failed }

        var recordedServerEntitlement: Bool {
            switch self {
            case .recorded: return true
            case .accountVerified(_, _, let grantsAccess): return grantsAccess
            case .acceptedWithoutServerGrant, .failed: return false
            }
        }
    }

    enum ProductLoadState: Equatable {
        case idle
        case loading
        case ready
        case partial
        case unavailable
        case failed
    }

    /// Loaded `Product`s, keyed by identifier. Empty until `loadProducts` runs;
    /// the paywall renders only these localized storefront prices and disables
    /// purchase when they are unavailable.
    private(set) var products: [String: Product] = [:]

    /// Distinguishes a cold load, a partial App Store catalog, and a real
    /// failure so the paywall never substitutes a potentially wrong USD price.
    private(set) var productLoadState: ProductLoadState = .idle

    /// The set of product identifiers the user currently owns on this Apple ID,
    /// per `Transaction.currentEntitlements`. This is the offline signal
    /// `EntitlementStore` unions in. Recomputed on launch, on `Transaction.updates`,
    /// and after a purchase/restore.
    var ownedProductIDs: Set<String> { resolution.ownedProductIDs }

    /// True while a product load is in flight (paywall can show skeletons).
    private(set) var isLoadingProducts = false

    /// Non-fatal load/purchase error surfaced where it helps; never blocks.
    private(set) var lastError: String?

    /// A verified transaction may be shared by the purchaser's family. Lore
    /// grants it exactly like a directly purchased transaction when the product
    /// is configured as Family Shareable in App Store Connect.
    var hasFamilySharedAccess: Bool { resolution.includesFamilySharedAccess }

    /// True when StoreKit returned a transaction whose signature could not be
    /// verified. The transaction never unlocks access, and restore reports a
    /// verification problem rather than claiming there was nothing to restore.
    private(set) var hasVerificationIssue = false

    /// Service-wide guards prevent two sheets or surfaces from launching
    /// overlapping App Store operations.
    private(set) var isPurchaseInProgress = false
    private(set) var isRestoreInProgress = false

    /// The long-lived `Transaction.updates` listener. Observation ignores this
    /// implementation detail, which also lets nonisolated deinit cancel it.
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var productLoadTask: Task<[Product], Error>?
    @ObservationIgnored private var expirationTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    private var currentSnapshots: [StoreEntitlementSnapshot] = []
    private var historySnapshots: [StoreEntitlementSnapshot] = []
    private var serverBindings: [String: Bool] = [:]
    private var refreshGeneration: UInt64 = 0
    private var expirationRevision = 0

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    private var resolution: StoreEntitlementResolution {
        _ = expirationRevision
        return StoreEntitlementResolver.resolve(
            current: currentSnapshots, history: historySnapshots,
            accountUUID: accountUUID, serverBindings: serverBindings, now: now()
        )
    }

    /// Only a server response for the still-current account and this verified
    /// original transaction can establish or deny recovered local ownership.
    func applyServerVerification(_ outcome: VerifiedTransactionSyncOutcome, originalTransactionID: String) {
        guard case .accountVerified(let verifiedID, let userID, let grantsAccess) = outcome,
              verifiedID == originalTransactionID, userID == accountUUID else { return }
        serverBindings[verifiedID] = grantsAccess
    }

    private func scheduleExpiration() {
        expirationTask?.cancel()
        expirationTask = nil
        let deadlines = currentSnapshots.compactMap(\.expirationDate)
            + historySnapshots.compactMap { snapshot -> Date? in
                StoreKitService.ProductID.passDuration(snapshot.productID).map {
                    snapshot.purchaseDate.addingTimeInterval($0)
                }
            }
        guard let next = deadlines.filter({ $0 > now() }).min() else { return }
        let delay = max(0.01, next.timeIntervalSince(now()))
        expirationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.expirationRevision &+= 1
            self.scheduleExpiration()
        }
    }

    /// Start the transaction listener. Call once, early (from `LoreApp`), so a
    /// renewal or a Family-Sharing grant that arrives while the app is running
    /// updates `ownedProductIDs` without a relaunch. Also does the initial
    /// `refreshEntitlements` read.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await refreshEntitlements() }
    }

    deinit {
        updatesTask?.cancel()
        expirationTask?.cancel()
    }

    // MARK: - Products

    /// Load localized products from the App Store (or the local StoreKit
    /// configuration). Prices never fall back to hardcoded USD because doing so
    /// can misstate the active storefront. `force` supports an explicit retry
    /// after a network or App Store catalog failure.
    func loadProducts(force: Bool = false) async {
        if !force, productLoadState == .ready { return }

        if let inFlight = productLoadTask {
            do {
                applyLoadedProducts(try await inFlight.value)
            } catch {
                applyProductLoadFailure()
            }
            return
        }

        isLoadingProducts = true
        productLoadState = .loading
        lastError = nil
        let task = Task { try await Product.products(for: ProductID.all) }
        productLoadTask = task
        defer {
            productLoadTask = nil
            isLoadingProducts = false
        }

        do {
            applyLoadedProducts(try await task.value)
        } catch {
            applyProductLoadFailure()
        }
    }

    private func applyLoadedProducts(_ loaded: [Product]) {
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        let recurringCount = ProductID.requiredSubscriptions.filter { products[$0] != nil }.count
        switch recurringCount {
        case ProductID.requiredSubscriptions.count:
            productLoadState = .ready
        case 1:
            productLoadState = .partial
            lastError = "One membership option is temporarily unavailable. The available App Store option is safe to use."
        default:
            productLoadState = .unavailable
            lastError = "Membership options aren't available from the App Store right now."
        }
    }

    private func applyProductLoadFailure() {
        products = [:]
        productLoadState = .failed
        lastError = "Couldn't load membership options from the App Store. Check your connection and try again."
    }

    /// The `Product` for a paywall plan, if loaded.
    func product(for id: String) -> Product? { products[id] }

    var availableCoreProductIDs: [String] {
        ProductID.subsAndLifetime.filter { products[$0] != nil }
    }

    // MARK: - Entitlement read (the offline belt-and-suspenders)

    /// True when any current on-device entitlement is a Lore+ product and its
    /// verified transaction hasn't been revoked/expired. This is the union input
    /// `EntitlementStore` reads, it can only *open* the gate, never close one
    /// the server `entitlements` row has opened.
    var hasActiveEntitlement: Bool {
        !ownedProductIDs.isEmpty || tripPassActive
    }

    /// The expiry of the most recent Trip Pass, if any. A non-renewing pass does
    /// NOT appear in `currentEntitlements`, so it's tracked from its purchase
    /// date plus the pass window (recomputed in `refreshEntitlements`).
    var tripPassExpiresAt: Date? { resolution.tripPassExpiresAt }

    /// True while an unexpired Trip Pass grants Lore+.
    var tripPassActive: Bool {
        guard let expiry = tripPassExpiresAt else { return false }
        return expiry > now()
    }

    /// Whether the current on-device entitlement is within an introductory
    /// (free-trial) period, lets the paywall/profile show "Trial" framing
    /// offline, distinct from a paid member. Determined from the latest verified
    /// transaction's `offer`/`offerType`.
    var isInIntroPeriod: Bool { resolution.isInIntroPeriod }

    /// Recompute access from verified StoreKit transactions. Unverified rows
    /// fail closed and are remembered so restore can explain the integrity
    /// failure instead of incorrectly reporting an empty purchase history.
    @discardableResult
    func refreshEntitlements(syncWithServer: Bool = true) async -> Bool {
        guard !Task.isCancelled else { return false }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        var current: [StoreEntitlementSnapshot] = []
        var history: [StoreEntitlementSnapshot] = []
        var verificationIssue = false
        var verifiedJWS: [(String, String)] = []
        var seenJWS = Set<String>()

        func queueForServer(_ jws: String, originalID: String) {
            if seenJWS.insert(jws).inserted { verifiedJWS.append((jws, originalID)) }
        }

        for await result in Transaction.currentEntitlements {
            guard generation == refreshGeneration, !Task.isCancelled else { return false }
            switch result {
            case .verified(let transaction):
                guard ProductID.all.contains(transaction.productID) else { continue }
                queueForServer(result.jwsRepresentation, originalID: String(transaction.originalID))
                current.append(snapshot(for: transaction))
            case .unverified(let transaction, _):
                if ProductID.all.contains(transaction.productID) { verificationIssue = true }
            }
        }
        for await result in Transaction.all {
            guard generation == refreshGeneration, !Task.isCancelled else { return false }
            switch result {
            case .verified(let transaction):
                guard ProductID.passDuration(transaction.productID) != nil else { continue }
                queueForServer(result.jwsRepresentation, originalID: String(transaction.originalID))
                history.append(snapshot(for: transaction))
            case .unverified(let transaction, _):
                if ProductID.all.contains(transaction.productID) { verificationIssue = true }
            }
        }
        guard generation == refreshGeneration, !Task.isCancelled else { return false }
        // Publish Apple's current truth before waiting on Lore. A failed sync
        // must not suppress a new device purchase or defer a refund/revocation.
        currentSnapshots = current
        historySnapshots = history
        hasVerificationIssue = verificationIssue
        scheduleExpiration()
        if verificationIssue {
            lastError = "Apple returned a purchase Lore couldn't verify. Restore purchases to try again."
        }
        guard syncWithServer, let sync = onVerifiedTransaction else { return false }
        var serverRecorded = false
        for (jws, originalID) in verifiedJWS {
            let outcome = await sync(jws)
            guard generation == refreshGeneration, !Task.isCancelled else { return false }
            applyServerVerification(outcome, originalTransactionID: originalID)
            if outcome.recordedServerEntitlement { serverRecorded = true }
            if outcome == .failed { lastError = Self.transactionSyncFailureMessage }
        }
        return serverRecorded
    }

    private func snapshot(for transaction: Transaction) -> StoreEntitlementSnapshot {
        StoreEntitlementSnapshot(
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            isIntroductory: introductory(in: transaction),
            ownership: transaction.ownershipType == .familyShared ? .familyShared : .purchased,
            appAccountToken: transaction.appAccountToken,
            originalTransactionID: String(transaction.originalID),
            isSandbox: transaction.environment == .sandbox || transaction.environment == .xcode
        )
    }

    // MARK: - Purchase

    /// Outcome of a purchase attempt the paywall branches on.
    enum PurchaseOutcome: Equatable {
        /// Apple verified the purchase and access is available. A temporarily
        /// failed server sync remains unfinished for retry. `trialing` reflects
        /// whether it started in the introductory free-trial period.
        case success(trialing: Bool)
        /// The user tapped Cancel in the sheet, not an error, no message.
        case userCancelled
        /// Apple needs a further step (Ask to Buy / SCA), the transaction will
        /// arrive later via `Transaction.updates`.
        case pending
        /// Another purchase task already owns the StoreKit sheet.
        case inProgress
        /// Something failed. `message` is a user-safe line.
        case failed(message: String)
    }

    /// Buy a product by identifier via the native StoreKit 2 purchase sheet.
    func purchase(productID: String) async -> PurchaseOutcome {
        guard !isPurchaseInProgress, !isRestoreInProgress else { return .inProgress }
        // No account requirement. Lore+ is not account-based content: StoreKit
        // grants it to the Apple ID and `EntitlementStore.isPlus` unions the
        // on-device `currentEntitlements` read. This guard used to reject the
        // purchase outright with "Sign in to Lore before purchasing", which is
        // the forced registration App Review rejected under 5.1.1(v) — twice.
        // The paywall UI was fixed first; this service-layer guard was the one
        // the reviewer actually hit, because it refuses before StoreKit opens.
        guard AppStore.canMakePayments else {
            return .failed(message: "Purchases are disabled on this device. Check Screen Time or Apple Account settings.")
        }
        guard ProductID.all.contains(productID) else {
            return .failed(message: "That membership option isn't recognized. No purchase was started.")
        }

        isPurchaseInProgress = true
        defer { isPurchaseInProgress = false }
        lastError = nil
        guard let product = products[productID] else {
            // Try a just-in-time load so a cold paywall can still transact.
            await loadProducts(force: true)
            guard let loaded = products[productID] else {
                return .failed(message: "That option isn't available from the App Store right now. No purchase was started.")
            }
            return await purchase(product: loaded)
        }
        return await purchase(product: product)
    }

    private func purchase(product: Product) async -> PurchaseOutcome {
        do {
            // Bind the transaction to the Lore account when there is one, so
            // Apple echoes the id back in the signed transaction and in every
            // server notification — that is what makes a purchase attributable
            // server-side. It is an optimisation, never a requirement: a
            // signed-out buyer must be able to complete the purchase (5.1.1(v)).
            // When they sign in later, LoreApp rebinds accountUUID and calls
            // refreshEntitlements(), which re-posts the verified transaction and
            // reclaims attribution.
            var options: Set<Product.PurchaseOption> = []
            if let accountUUID {
                options.insert(.appAccountToken(accountUUID))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    hasVerificationIssue = true
                    let message = "Apple completed the purchase, but Lore couldn't verify it. Try Restore Purchases; if access still doesn't appear, contact support."
                    lastError = message
                    return .failed(message: message)
                }
                let trialing = introductory(in: transaction)
                await refreshEntitlements(syncWithServer: false)
                // Record/accept it server-side BEFORE finishing, so a crash or
                // transport failure leaves the transaction unfinished and
                // replayable. Sandbox/TestFlight may be accepted without a
                // production entitlement row, but failed posts are not finished.
                let syncOutcome = await syncVerifiedTransaction(verification.jwsRepresentation)
                applyServerVerification(syncOutcome, originalTransactionID: String(transaction.originalID))
                if syncOutcome.canFinishTransaction {
                    await transaction.finish()
                } else {
                    // Keep unfinished for retry, but acknowledge usable verified
                    // on-device access when Apple has already completed payment.
                    lastError = Self.transactionSyncFailureMessage
                }
                guard hasActiveEntitlement || syncOutcome.recordedServerEntitlement else {
                    return .failed(message: Self.transactionSyncFailureMessage)
                }
                return .success(trialing: trialing)
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed(message: "The App Store returned an unexpected result. Check Purchase History before trying again.")
            }
        } catch {
            let message = "The App Store couldn't complete that request. Check your connection and Purchase History before trying again."
            lastError = message
            return .failed(message: message)
        }
    }

    private func introductory(in transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return transaction.offer?.type == .introductory
        } else {
            return transaction.offerType == .introductory
        }
    }

    // MARK: - Restore

    enum RestoreOutcome: Equatable {
        case restored
        case nothingToRestore
        case userCancelled
        case failed(message: String)
    }

    /// Restore prior purchases. `AppStore.sync()` refreshes the receipt; then we
    /// recompute entitlements. Sync failures are distinct from a valid receipt
    /// with no Lore+ purchase, so the UI never reports a network/auth failure as
    /// "nothing to restore."
    ///
    func restore() async -> RestoreOutcome {
        guard !isRestoreInProgress, !isPurchaseInProgress else {
            return .failed(message: "Another App Store request is already in progress.")
        }
        // Restore must work signed out. It is an Apple-ID operation, and a buyer
        // who reinstalls has to recover access without first creating an account
        // (5.1.1(v)). This guard previously refused with "Sign in to Lore before
        // restoring", stranding exactly the person the guideline protects.
        isRestoreInProgress = true
        defer { isRestoreInProgress = false }
        lastError = nil
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            let serverRecorded = await refreshEntitlements()
            return hasActiveEntitlement || serverRecorded ? .restored : .userCancelled
        } catch {
            // The existing receipt may still prove access even if the explicit
            // sync prompt failed, so preserve that verified entitlement.
            let serverRecorded = await refreshEntitlements()
            if hasActiveEntitlement || serverRecorded { return .restored }
            let message = "Couldn't connect to the App Store. Check your connection and try again."
            lastError = message
            return .failed(message: message)
        }
        let serverRecorded = await refreshEntitlements()
        if hasVerificationIssue, !hasActiveEntitlement {
            let message = "A purchase was found but couldn't be verified. Confirm your Apple Account, then try Restore Purchases again."
            lastError = message
            return .failed(message: message)
        }
        return hasActiveEntitlement || serverRecorded ? .restored : .nothingToRestore
    }

    // MARK: - Intro-offer eligibility

    /// Returns the actual free-trial duration only when this product currently
    /// has a free-trial offer and the Apple Account is eligible for it. This
    /// prevents stale local copy from promising an offer App Store Connect no
    /// longer provides.
    func eligibleFreeTrialDescription(productID: String) async -> String? {
        guard
            let product = products[productID],
            let subscription = product.subscription,
            let offer = subscription.introductoryOffer,
            offer.paymentMode == .freeTrial,
            await subscription.isEligibleForIntroOffer
        else { return nil }
        return Self.trialPeriodDescription(offer.period)
    }

    private static func trialPeriodDescription(_ period: Product.SubscriptionPeriod) -> String? {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: return nil
        }
        return "\(period.value) \(unit)\(period.value == 1 ? "" : "s")"
    }

    // MARK: - Manage subscriptions

    /// The App Store product identifier that best represents the active Lore+
    /// grant, for a "Manage subscription" deep link. `nil` when nothing owned.
    var activeProductID: String? {
        [ProductID.annual, ProductID.monthly].first { ownedProductIDs.contains($0) }
    }

    enum AccessKind: Equatable {
        case subscription
        case lifetime
        case tripPass
        case none
    }

    var accessKind: AccessKind {
        if activeProductID != nil { return .subscription }
        if ownedProductIDs.contains(ProductID.lifetime) { return .lifetime }
        if tripPassActive { return .tripPass }
        return .none
    }

    // MARK: - Updates handler

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            hasVerificationIssue = true
            lastError = "A purchase update arrived but couldn't be verified. Restore purchases to retry."
            return
        }
        guard ProductID.all.contains(transaction.productID) else {
            await transaction.finish()
            return
        }
        await refreshEntitlements(syncWithServer: false)
        let syncOutcome = await syncVerifiedTransaction(result.jwsRepresentation)
        applyServerVerification(syncOutcome, originalTransactionID: String(transaction.originalID))
        guard syncOutcome.canFinishTransaction else {
            lastError = Self.transactionSyncFailureMessage
            return
        }
        // Finish only after Lore has handled the signed transaction, so StoreKit
        // can replay it if the durable server sync is temporarily unavailable.
        await transaction.finish()
    }

    private static let transactionSyncFailureMessage =
        "Apple recorded the purchase, but Lore couldn't link it to your account yet. Check your connection, then use Restore Purchases."

    private func syncVerifiedTransaction(_ jws: String) async -> VerifiedTransactionSyncOutcome {
        guard let sync = onVerifiedTransaction else { return .failed }
        let generation = refreshGeneration
        let outcome = await sync(jws)
        guard generation == refreshGeneration, !Task.isCancelled else { return .failed }
        return outcome
    }
}
