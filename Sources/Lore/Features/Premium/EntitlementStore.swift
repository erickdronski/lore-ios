import Foundation
import Observation

struct CachedEntitlementRecord: Codable, Equatable {
    let entitlement: Entitlement
    let verifiedAt: Date
}

enum EntitlementCachePolicy {
    /// A short resilience window prevents a transient backend outage from
    /// locking out a traveler while still bounding stale server grants. Native
    /// StoreKit transactions remain the longer-lived offline source of truth.
    static let maximumAge: TimeInterval = 72 * 60 * 60

    static func usable(
        _ record: CachedEntitlementRecord?,
        for userID: String?,
        now: Date
    ) -> Entitlement? {
        guard let record,
              let userID,
              record.entitlement.userID == userID,
              record.entitlement.isActive(asOf: now),
              now.timeIntervalSince(record.verifiedAt) >= 0,
              now.timeIntervalSince(record.verifiedAt) <= maximumAge
        else { return nil }
        return record.entitlement
    }

    /// Supabase access tokens are signed JWTs. Decoding the subject here does
    /// not establish trust; it only identity-binds an already local cache to
    /// the same authenticated session and prevents account crossover.
    static func userID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: data)
        else { return nil }
        return payload.sub
    }

    private struct JWTPayload: Decodable {
        let sub: String
    }
}

/// The single source of truth for "is this user Lore+?" across the app.
///
/// It reads the signed-in user's `entitlements` rows (RLS: own rows only) and
/// exposes `isPlus`, true when any grant's status is `active` or `trialing`
/// (docs/00-DECISIONS.md §7; the backend contract, `Entitlement.isActive`).
///
/// **Two paths, unioned (docs/16-APPLE-TOOLKITS.md §1).** RevenueCat remains the
/// planned server-side truth: its webhook writes the `entitlements` row this
/// store reads over the network. StoreKit 2 is the client path, a
/// `StoreKitService` reads `Transaction.currentEntitlements` on-device, which
/// works offline and survives an RC outage or a first-launch-before-network.
/// `isPlus` is the **union**: either source may *open* the gate, neither can
/// subtract from the other (docs/16 §1: "Read it locally, union it with the RC
/// answer, never subtract"). TODO(P3): when the RevenueCat SDK lands, RC becomes
/// the primary purchase driver and this union narrows to RC-truth + StoreKit's
/// offline belt-and-suspenders, the seam here does not change.
///
/// Doctrine (docs/00 §7): the app is generous by default. `isPlus == false`
/// gates only the four Lore+ surfaces, the 4th deep dive of a day, tours,
/// offline packs, audio narration. Scanning, Layer-1 cards, and the first three
/// dives are never gated (that generosity lives in `DiveMeter`, not here).
///
/// **Offline resilience.** Verified StoreKit transactions are the durable local
/// truth. A server grant is also cached for at most 72 hours and only reused by
/// a JWT whose subject matches that grant's user id. Signed-out, mismatched,
/// expired, unknown, or inactive cache entries fail closed.
///
/// Lifecycle mirrors `AuthService`: `@Observable @MainActor`, one instance,
/// handed down the environment. Views read `store.isPlus`; the paywall calls
/// `refresh(accessToken:)` after a purchase settles so the gate reopens without
/// a relaunch.
@Observable
@MainActor
final class EntitlementStore {
    private enum CacheKey {
        static let verifiedEntitlement = "lore.premium.cachedEntitlement.v1"
    }

    /// The grant currently on file, if we've loaded one. `nil` before the first
    /// load, or when the user has no entitlement row at all.
    private(set) var entitlement: Entitlement?

    /// The StoreKit 2 client path (`Transaction.currentEntitlements`). When set,
    /// its on-device answer is *unioned* into `isPlus`, it can open the gate the
    /// server hasn't confirmed yet (offline / RC-outage), never close one it has.
    /// Injected once from `LoreApp`. Weak-by-contract: both are `@MainActor`
    /// app-lifetime singletons, so a plain reference is fine.
    var storeKit: StoreKitService?

    /// True while a `refresh` is in flight (paywall/profile can show a spinner).
    private(set) var isRefreshing = false

    /// Set when the last refresh failed. Non-fatal, `isPlus` simply stays
    /// closed. Surfaced only where it helps (a quiet "couldn't verify" note),
    /// never as a blocking error.
    private(set) var lastError: String?

    /// True only while a fresh, identity-matched server snapshot is carrying
    /// access through a backend outage. Useful for transparent member UI.
    private(set) var isUsingCachedEntitlement = false

    private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    private var cachedRecord: CachedEntitlementRecord?
    private var activeCachedEntitlement: Entitlement?

    /// The one question the rest of the app asks. `active` or `trialing` on any
    /// grant opens every Lore+ surface; everything else (including no grant, a
    /// signed-out user, or an unconfirmed read) leaves it closed.
    ///
    /// **Union of the two paths** (docs/16 §1): the server row (RevenueCat →
    /// `entitlements`) *or* the on-device StoreKit 2 entitlement. Either opens
    /// the gate; neither subtracts. StoreKit's read is the offline
    /// belt-and-suspenders so a returning subscriber isn't gated during an RC
    /// outage or before the first network round-trip.
    var isPlus: Bool {
        #if DEBUG
        // Developer override: unlock every Lore+ surface for testing without a
        // purchase. Set by the LORE_DEV_PLUS launch env or the DEBUG-only
        // Settings toggle. Compiled out of Release entirely, never ships.
        if EntitlementStore.devForcePlus { return true }
        #endif
        let server = entitlement?.isActive ?? false
        let cached = activeCachedEntitlement?.isActive ?? false
        let onDevice = storeKit?.hasActiveEntitlement ?? false
        return server || cached || onDevice
    }

    #if DEBUG
    /// Debug-only Lore+ override (env `LORE_DEV_PLUS=1` or UserDefaults toggle).
    static var devForcePlus: Bool {
        ProcessInfo.processInfo.environment["LORE_DEV_PLUS"] == "1"
            || UserDefaults.standard.bool(forKey: "lore.dev.forcePlus")
    }
    #endif

    /// True specifically during the 7-day free trial, lets surfaces show
    /// "Trial · 4 days left" style affordances distinct from a paid member.
    /// (The day-count itself isn't in the `entitlements` contract yet; this is
    /// just the status distinction. TODO(P1): expose `trial_ends_at`.)
    ///
    /// Unions the server status with StoreKit's introductory-period read so the
    /// trial framing shows even when only the on-device path knows about it.
    var isTrialing: Bool {
        (entitlement?.status == .trialing)
            || (activeCachedEntitlement?.status == .trialing)
            || (storeKit?.isInIntroPeriod ?? false)
    }

    init(
        entitlement: Entitlement? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.entitlement = entitlement
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: CacheKey.verifiedEntitlement) {
            cachedRecord = try? JSONDecoder().decode(CachedEntitlementRecord.self, from: data)
        }
    }

    /// Load the user's entitlement. Pass the current access token (from
    /// `AuthService.validAccessToken()`); a `nil` token means signed-out, so
    /// we clear to free without hitting the network.
    ///
    /// Call this: on sign-in, on app foreground, and after a purchase settles.
    func refresh(accessToken: String?) async {
        // Always re-read the on-device StoreKit path, it's valid even when
        // signed out of Supabase (the purchase lives on the Apple ID, not the
        // account) and needs no token.
        await storeKit?.refreshEntitlements()

        guard let accessToken else {
            entitlement = nil
            activeCachedEntitlement = nil
            isUsingCachedEntitlement = false
            lastError = nil
            return
        }
        let currentUserID = EntitlementCachePolicy.userID(fromJWT: accessToken)
        activeCachedEntitlement = nil
        isUsingCachedEntitlement = false
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }
        do {
            entitlement = try await LoreAPI.shared.entitlement(accessToken: accessToken)
            activeCachedEntitlement = nil
            if let entitlement {
                persist(entitlement, verifiedAt: now())
            } else if cachedRecord?.entitlement.userID == currentUserID {
                removeCachedRecord()
            }
        } catch {
            entitlement = nil
            activeCachedEntitlement = EntitlementCachePolicy.usable(
                cachedRecord,
                for: currentUserID,
                now: now()
            )
            isUsingCachedEntitlement = activeCachedEntitlement != nil
            lastError = isUsingCachedEntitlement
                ? "You're offline. Lore+ is using your recently verified membership for up to 72 hours."
                : "Couldn't verify your membership. Free Lore remains available while you reconnect."
        }
    }

    /// Clear the *server* grant on sign-out, the next Supabase user starts from
    /// free. The StoreKit path is deliberately **not** cleared: the purchase
    /// belongs to the Apple ID, not the account, so `isPlus` can still resolve
    /// from `Transaction.currentEntitlements` for a signed-out purchaser
    /// (docs/16 §1 offline belt-and-suspenders).
    func clear() {
        entitlement = nil
        activeCachedEntitlement = nil
        isUsingCachedEntitlement = false
        lastError = nil
        isRefreshing = false
    }

    /// Optimistically mark the user as Lore+ the instant a purchase completes,
    /// before the server-side webhook has written the `entitlements` row. The
    /// next `refresh` reconciles with the backend truth.
    ///
    /// Called by the paywall's purchase handler once RevenueCat reports a
    /// successful transaction (see `PaywallView` purchase stub). `userID` lets
    /// us build a plausible local row; `trialing` picks the status so the
    /// 7-day-trial framing shows immediately.
    func applyLocalPurchase(userID: String, trialing: Bool) {
        entitlement = Entitlement(
            userID: userID,
            entitlement: "lore_plus",
            status: trialing ? .trialing : .active
        )
    }

    private func persist(_ entitlement: Entitlement, verifiedAt: Date) {
        let record = CachedEntitlementRecord(entitlement: entitlement, verifiedAt: verifiedAt)
        cachedRecord = record
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: CacheKey.verifiedEntitlement)
        }
    }

    private func removeCachedRecord() {
        cachedRecord = nil
        activeCachedEntitlement = nil
        isUsingCachedEntitlement = false
        defaults.removeObject(forKey: CacheKey.verifiedEntitlement)
    }
}
