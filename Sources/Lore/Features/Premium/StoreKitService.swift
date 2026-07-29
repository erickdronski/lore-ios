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
        now: Date
    ) -> StoreEntitlementResolution {
        guard let accountUUID else {
            return StoreEntitlementResolution(
                ownedProductIDs: [],
                tripPassExpiresAt: nil,
                isInIntroPeriod: false,
                includesFamilySharedAccess: false
            )
        }

        let active = current.filter { snapshot in
            guard snapshot.appAccountToken == accountUUID else { return false }
            guard StoreKitService.ProductID.subsAndLifetime.contains(snapshot.productID) else {
                return false
            }
            guard snapshot.revocationDate == nil, !snapshot.isUpgraded else { return false }
            guard let expiry = snapshot.expirationDate else { return true }
            return expiry > now
        }

        let passExpiry = history.compactMap { snapshot -> Date? in
            guard snapshot.appAccountToken == accountUUID,
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
    /// This is the ONLY link between an App Store transaction and a Lore
    /// account. It is passed to `product.purchase()` as `appAccountToken`, so
    /// Apple echoes it back in the signed transaction and in every App Store
    /// Server Notification — which is what lets the server write an
    /// `entitlements` row for the right user. Without it a purchase is
    /// cryptographically valid but unattributable, and the only proof of
    /// payment lives on one device.
    ///
    /// Purchases fail closed while this is nil. New transactions must be
    /// attributable to a Lore account before StoreKit opens.
    var accountUUID: UUID?

    /// Called with a transaction's **JWS representation** so the app can post it
    /// to the server for entitlement recording. Set by the app; no-op until it
    /// is.
    ///
    /// It must be the JWS, not `Transaction.jsonRepresentation`: the server
    /// re-verifies Apple's signature over this exact string and trusts nothing
    /// the client asserts. Handing it unsigned JSON would let any caller mint
    /// itself a paid entitlement.
    var onVerifiedTransaction: ((String) async -> Bool)?

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

    /// The `entitlements` grant name these products confer. Matches the row
    /// `EntitlementStore` reads from Lore's server row.
    static let entitlementName = "lore_plus"

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
    private(set) var ownedProductIDs: Set<String> = []

    /// True while a product load is in flight (paywall can show skeletons).
    private(set) var isLoadingProducts = false

    /// Non-fatal load/purchase error surfaced where it helps; never blocks.
    private(set) var lastError: String?

    /// A verified transaction may be shared by the purchaser's family. Lore
    /// grants it exactly like a directly purchased transaction when the product
    /// is configured as Family Shareable in App Store Connect.
    private(set) var hasFamilySharedAccess = false

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

    init() {}

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
    private(set) var tripPassExpiresAt: Date?

    /// True while an unexpired Trip Pass grants Lore+.
    var tripPassActive: Bool {
        guard let expiry = tripPassExpiresAt else { return false }
        return expiry > Date()
    }

    /// Whether the current on-device entitlement is within an introductory
    /// (free-trial) period, lets the paywall/profile show "Trial" framing
    /// offline, distinct from a paid member. Determined from the latest verified
    /// transaction's `offer`/`offerType`.
    private(set) var isInIntroPeriod = false

    /// Recompute access from verified StoreKit transactions. Unverified rows
    /// fail closed and are remembered so restore can explain the integrity
    /// failure instead of incorrectly reporting an empty purchase history.
    @discardableResult
    func refreshEntitlements() async -> Bool {
        var current: [StoreEntitlementSnapshot] = []
        var history: [StoreEntitlementSnapshot] = []
        var verificationIssue = false
        var verifiedJWS: [String] = []
        var seenJWS = Set<String>()

        func queueForServer(_ jws: String) {
            if seenJWS.insert(jws).inserted { verifiedJWS.append(jws) }
        }

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard ProductID.all.contains(transaction.productID) else { continue }
                queueForServer(result.jwsRepresentation)
                if transaction.appAccountToken == accountUUID {
                    current.append(snapshot(for: transaction))
                }
            case .unverified:
                verificationIssue = true
            }
        }

        for await result in Transaction.all {
            switch result {
            case .verified(let transaction):
                guard ProductID.passDuration(transaction.productID) != nil else { continue }
                queueForServer(result.jwsRepresentation)
                if transaction.appAccountToken == accountUUID {
                    history.append(snapshot(for: transaction))
                }
            case .unverified(let transaction, _):
                if ProductID.all.contains(transaction.productID) {
                    verificationIssue = true
                }
            }
        }

        // Re-assert verified ownership server-side after collecting current
        // products and Trip Pass history. A token mismatch never grants local
        // access, but the server may safely reclaim an orphaned binding after
        // account deletion by matching Apple's original transaction id.
        var serverRecorded = false
        if let sync = onVerifiedTransaction {
            for jws in verifiedJWS {
                if await sync(jws) { serverRecorded = true }
            }
        }

        let resolution = StoreEntitlementResolver.resolve(
            current: current,
            history: history,
            accountUUID: accountUUID,
            now: Date()
        )
        ownedProductIDs = resolution.ownedProductIDs
        tripPassExpiresAt = resolution.tripPassExpiresAt
        isInIntroPeriod = resolution.isInIntroPeriod
        hasFamilySharedAccess = resolution.includesFamilySharedAccess
        hasVerificationIssue = verificationIssue
        if verificationIssue {
            lastError = "Apple returned a purchase Lore couldn't verify. Restore purchases to try again."
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
            appAccountToken: transaction.appAccountToken
        )
    }

    // MARK: - Purchase

    /// Outcome of a purchase attempt the paywall branches on.
    enum PurchaseOutcome: Equatable {
        /// Purchase succeeded and the transaction verified + finished. `trialing`
        /// reflects whether it started in the introductory free-trial period.
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
        guard accountUUID != nil else {
            return .failed(message: "Sign in to Lore before purchasing so Apple can link access to your account.")
        }
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
            // Bind the transaction to the Lore account so Apple echoes the id
            // back in the signed transaction and in every server notification.
            // This is what makes the purchase attributable server-side.
            guard let accountUUID else {
                return .failed(message: "Sign in to Lore before purchasing so Apple can link access to your account.")
            }
            let options: Set<Product.PurchaseOption> = [.appAccountToken(accountUUID)]
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
                // Record it server-side BEFORE finishing, so a crash between
                // the two still leaves the transaction unfinished and therefore
                // replayable on next launch. `verification.jwsRepresentation`
                // is the Apple-signed form the server re-verifies.
                _ = await onVerifiedTransaction?(verification.jwsRepresentation)
                await transaction.finish()
                await refreshEntitlements()
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
        guard accountUUID != nil else {
            return .failed(message: "Sign in to Lore before restoring so Apple can link access to your account.")
        }
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
        // Finish any transaction we're told about so StoreKit stops replaying it.
        await transaction.finish()
        await refreshEntitlements()
    }
}
