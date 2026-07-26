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
        now: Date
    ) -> StoreEntitlementResolution {
        let active = current.filter { snapshot in
            guard StoreKitService.ProductID.subsAndLifetime.contains(snapshot.productID) else {
                return false
            }
            guard snapshot.revocationDate == nil, !snapshot.isUpgraded else { return false }
            guard let expiry = snapshot.expirationDate else { return true }
            return expiry > now
        }

        let passExpiry = history.compactMap { snapshot -> Date? in
            guard snapshot.revocationDate == nil,
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
/// Doctrine (docs/16-APPLE-TOOLKITS.md §1): StoreKit 2 and RevenueCat are
/// *layers, not alternatives*. RevenueCat remains the planned **server-side
/// truth**, its webhook writes the `entitlements` row `EntitlementStore` reads,
/// and it owns the paywall/offering config. StoreKit 2 is the on-device engine
/// underneath: the actual purchase sheet, restore, intro-offer eligibility, and
///, critically, `Transaction.currentEntitlements` as a **belt-and-suspenders
/// offline check** so a returning subscriber isn't gated during an RC outage or
/// a first-launch-before-network.
///
/// This service is that client path. It:
/// - loads the two products (`Product.products(for:)`),
/// - drives the native purchase sheet (`product.purchase()`),
/// - reads on-device entitlements (`Transaction.currentEntitlements`),
/// - listens for out-of-band changes (`Transaction.updates`),
/// - restores (`AppStore.sync()`),
/// - and reports StoreKit-authoritative free-trial eligibility and duration.
///
/// **Reconciliation TODO (docs/16 §1 + docs/00 §2):** when the RevenueCat SDK
/// lands at P3, `Purchases.shared` becomes the primary purchase driver (it runs
/// on StoreKit 2 under the hood) and its webhook the entitlement writer. At that
/// point this service's `purchase`/`restore` should defer to RC, and its role
/// narrows to the *offline union* read (`hasActiveEntitlement`) that
/// `EntitlementStore` unions with, **never subtracts from**, the RC/`entitlements`
/// answer. Do not run a second raw purchase path in parallel with RC once it
/// exists; that is the double-bookkeeping trap the doc warns against. Until RC
/// is wired, this is the real, working purchase path.
///
/// Lifecycle mirrors the other stores: `@Observable @MainActor`, one instance,
/// injected via the environment. `EntitlementStore` holds a reference and unions
/// `hasActiveEntitlement` into its `isPlus` answer.
@Observable
@MainActor
final class StoreKitService {
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
    /// `EntitlementStore` reads and the RevenueCat entitlement (`plus`/`lore_plus`).
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
    /// the server (RevenueCat/`entitlements`) has opened.
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
    func refreshEntitlements() async {
        var current: [StoreEntitlementSnapshot] = []
        var history: [StoreEntitlementSnapshot] = []
        var verificationIssue = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                current.append(snapshot(for: transaction))
            case .unverified:
                verificationIssue = true
            }
        }

        for await result in Transaction.all {
            switch result {
            case .verified(let transaction):
                guard ProductID.passDuration(transaction.productID) != nil else { continue }
                history.append(snapshot(for: transaction))
            case .unverified(let transaction, _):
                if ProductID.all.contains(transaction.productID) {
                    verificationIssue = true
                }
            }
        }

        let resolution = StoreEntitlementResolver.resolve(
            current: current,
            history: history,
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
    }

    private func snapshot(for transaction: Transaction) -> StoreEntitlementSnapshot {
        StoreEntitlementSnapshot(
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            isIntroductory: introductory(in: transaction),
            ownership: transaction.ownershipType == .familyShared ? .familyShared : .purchased
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
    ///
    /// **RevenueCat reconciliation TODO (docs/16 §1):** at P3 this becomes a
    /// `Purchases.shared.purchase(package:)` call so RC records the transaction
    /// server-side and its webhook writes the `entitlements` row. The return
    /// contract (a `PurchaseOutcome`) stays, so the paywall wiring is untouched
    /// by that swap.
    func purchase(productID: String) async -> PurchaseOutcome {
        guard !isPurchaseInProgress, !isRestoreInProgress else { return .inProgress }
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
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    hasVerificationIssue = true
                    let message = "Apple completed the purchase, but Lore couldn't verify it. Try Restore Purchases; if access still doesn't appear, contact support."
                    lastError = message
                    return .failed(message: message)
                }
                let trialing = introductory(in: transaction)
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
    /// TODO(P3): defer to `Purchases.shared.restorePurchases()` once RC is wired,
    /// so the restore also reconciles server-side.
    func restore() async -> RestoreOutcome {
        guard !isRestoreInProgress, !isPurchaseInProgress else {
            return .failed(message: "Another App Store request is already in progress.")
        }
        isRestoreInProgress = true
        defer { isRestoreInProgress = false }
        lastError = nil
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            await refreshEntitlements()
            return hasActiveEntitlement ? .restored : .userCancelled
        } catch {
            // The existing receipt may still prove access even if the explicit
            // sync prompt failed, so preserve that verified entitlement.
            await refreshEntitlements()
            if hasActiveEntitlement { return .restored }
            let message = "Couldn't connect to the App Store. Check your connection and try again."
            lastError = message
            return .failed(message: message)
        }
        await refreshEntitlements()
        if hasVerificationIssue, !hasActiveEntitlement {
            let message = "A purchase was found but couldn't be verified. Confirm your Apple Account, then try Restore Purchases again."
            lastError = message
            return .failed(message: message)
        }
        return hasActiveEntitlement ? .restored : .nothingToRestore
    }

    // MARK: - Intro-offer eligibility

    /// Returns the actual free-trial duration only when this product currently
    /// has a free-trial offer and the Apple Account is eligible for it. This
    /// prevents stale local copy from promising an offer App Store Connect no
    /// longer provides.
    ///
    /// TODO(P3): RevenueCat exposes this per-offering too; unify on one source
    /// when RC is wired.
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
