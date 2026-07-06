import Foundation
import Observation
import StoreKit

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
/// - and reports intro-offer eligibility for the 7-day trial framing.
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
    /// The two Lore+ subscription products, App Store Connect identifiers
    /// (docs/16 §1, and the ASC setup in docs/10 §6). These are the *real* IDs
    /// the `Configuration.storekit` file and ASC both define, not placeholders.
    enum ProductID {
        static let monthly = "lore_plus_monthly_4_99"
        static let annual = "lore_plus_annual_29_99"
        static let all: [String] = [monthly, annual]
    }

    /// The `entitlements` grant name these products confer. Matches the row
    /// `EntitlementStore` reads and the RevenueCat entitlement (`plus`/`lore_plus`).
    static let entitlementName = "lore_plus"

    /// Loaded `Product`s, keyed by identifier. Empty until `loadProducts` runs;
    /// the paywall renders localized prices from these when present, and falls
    /// back to the hardcoded USD lines (`PaywallModel.Plan.priceLine`) otherwise.
    private(set) var products: [String: Product] = [:]

    /// The set of product identifiers the user currently owns on this Apple ID,
    /// per `Transaction.currentEntitlements`. This is the offline signal
    /// `EntitlementStore` unions in. Recomputed on launch, on `Transaction.updates`,
    /// and after a purchase/restore.
    private(set) var ownedProductIDs: Set<String> = []

    /// True while a product load is in flight (paywall can show skeletons).
    private(set) var isLoadingProducts = false

    /// Non-fatal load/purchase error surfaced where it helps; never blocks.
    private(set) var lastError: String?

    /// The long-lived `Transaction.updates` listener. Cancelled on deinit.
    private var updatesTask: Task<Void, Never>?

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

    /// Load the Lore+ products from the App Store (or the `.storekit`
    /// configuration in the simulator). Best-effort: a failure leaves `products`
    /// empty and the paywall falls back to its hardcoded price lines.
    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        lastError = nil
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            lastError = "Couldn't load subscription options. You can still read everything free."
        }
    }

    /// The `Product` for a paywall plan, if loaded.
    func product(for id: String) -> Product? { products[id] }

    // MARK: - Entitlement read (the offline belt-and-suspenders)

    /// True when any current on-device entitlement is a Lore+ product and its
    /// verified transaction hasn't been revoked/expired. This is the union input
    /// `EntitlementStore` reads, it can only *open* the gate, never close one
    /// the server (RevenueCat/`entitlements`) has opened.
    var hasActiveEntitlement: Bool {
        !ownedProductIDs.isEmpty
    }

    /// Whether the current on-device entitlement is within an introductory
    /// (free-trial) period, lets the paywall/profile show "Trial" framing
    /// offline, distinct from a paid member. Determined from the latest verified
    /// transaction's `offer`/`offerType`.
    private(set) var isInIntroPeriod = false

    /// Recompute `ownedProductIDs` from `Transaction.currentEntitlements`. This
    /// is the on-device truth: it works offline and survives an RC outage.
    func refreshEntitlements() async {
        var owned: Set<String> = []
        var trialing = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProductID.all.contains(transaction.productID) else { continue }
            // Not revoked and (for subscriptions) not past expiry.
            if transaction.revocationDate != nil { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            owned.insert(transaction.productID)
            // `offer` (StoreKit 2, iOS 17.2+) or the legacy `offerType` tells us
            // this is an intro/free-trial period. Guard the newer API by version.
            if #available(iOS 17.2, *) {
                if transaction.offer?.type == .introductory { trialing = true }
            } else if transaction.offerType == .introductory {
                trialing = true
            }
        }
        ownedProductIDs = owned
        isInIntroPeriod = trialing
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
        lastError = nil
        guard let product = products[productID] else {
            // Try a just-in-time load so a cold paywall can still transact.
            await loadProducts()
            guard let loaded = products[productID] else {
                return .failed(message: "That option isn't available right now. Try again.")
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
                    return .failed(message: "That purchase couldn't be verified. No charge was made.")
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
                return .failed(message: "That didn't go through. No charge was made, try again.")
            }
        } catch {
            return .failed(message: "That didn't go through. No charge was made, try again.")
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

    /// Restore prior purchases. `AppStore.sync()` refreshes the receipt; then we
    /// recompute entitlements. Returns whether the user ends up with Lore+.
    ///
    /// TODO(P3): defer to `Purchases.shared.restorePurchases()` once RC is wired,
    /// so the restore also reconciles server-side.
    func restore() async -> Bool {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            // A cancelled/failed sync isn't fatal, currentEntitlements may still
            // reflect prior purchases. Fall through to the recompute.
        }
        await refreshEntitlements()
        return hasActiveEntitlement
    }

    // MARK: - Intro-offer eligibility (7-day trial framing)

    /// Whether the user is eligible for the introductory (7-day free trial)
    /// offer on a product's subscription group. Surface "Start 7-day free trial"
    /// only when `true`; fall back to "Subscribe" copy otherwise, or the paywall
    /// lies to a returning user (docs/16 §1).
    ///
    /// TODO(P3): RevenueCat exposes this per-offering too; unify on one source
    /// when RC is wired.
    func isEligibleForIntroOffer(productID: String) async -> Bool {
        guard
            let product = products[productID],
            let subscription = product.subscription
        else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    // MARK: - Manage subscriptions

    /// The App Store product identifier that best represents the active Lore+
    /// grant, for a "Manage subscription" deep link. `nil` when nothing owned.
    var activeProductID: String? {
        ownedProductIDs.first
    }

    // MARK: - Updates handler

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        // Finish any transaction we're told about so StoreKit stops replaying it.
        await transaction.finish()
        await refreshEntitlements()
    }
}
