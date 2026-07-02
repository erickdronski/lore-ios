import Foundation
import Observation

/// The single source of truth for "is this user Lore+?" across the app.
///
/// It reads the signed-in user's `entitlements` rows (RLS: own rows only) and
/// exposes `isPlus` — true when any grant's status is `active` or `trialing`
/// (docs/00-DECISIONS.md §7; the backend contract, `Entitlement.isActive`).
///
/// Doctrine (docs/00 §7): the app is generous by default. `isPlus == false`
/// gates only the four Lore+ surfaces — the 4th deep dive of a day, tours,
/// offline packs, audio narration. Scanning, Layer-1 cards, and the first three
/// dives are never gated (that generosity lives in `DiveMeter`, not here).
///
/// **Failing open vs. closed.** Reads fail *closed*: a network error or a
/// signed-out user leaves `isPlus == false`, so we never hand out Lore+ we
/// can't confirm. But the app stays fully usable without it — a free user is a
/// first-class citizen, not a locked-out one.
///
/// Lifecycle mirrors `AuthService`: `@Observable @MainActor`, one instance,
/// handed down the environment. Views read `store.isPlus`; the paywall calls
/// `refresh(accessToken:)` after a purchase settles so the gate reopens without
/// a relaunch.
@Observable
@MainActor
final class EntitlementStore {
    /// The grant currently on file, if we've loaded one. `nil` before the first
    /// load, or when the user has no entitlement row at all.
    private(set) var entitlement: Entitlement?

    /// True while a `refresh` is in flight (paywall/profile can show a spinner).
    private(set) var isRefreshing = false

    /// Set when the last refresh failed. Non-fatal — `isPlus` simply stays
    /// closed. Surfaced only where it helps (a quiet "couldn't verify" note),
    /// never as a blocking error.
    private(set) var lastError: String?

    /// The one question the rest of the app asks. `active` or `trialing` on any
    /// grant opens every Lore+ surface; everything else (including no grant, a
    /// signed-out user, or an unconfirmed read) leaves it closed.
    var isPlus: Bool {
        entitlement?.isActive ?? false
    }

    /// True specifically during the 7-day free trial — lets surfaces show
    /// "Trial · 4 days left" style affordances distinct from a paid member.
    /// (The day-count itself isn't in the `entitlements` contract yet; this is
    /// just the status distinction. TODO(P1): expose `trial_ends_at`.)
    var isTrialing: Bool {
        entitlement?.status == .trialing
    }

    init(entitlement: Entitlement? = nil) {
        self.entitlement = entitlement
    }

    /// Load the user's entitlement. Pass the current access token (from
    /// `AuthService.session?.accessToken`); a `nil` token means signed-out, so
    /// we clear to free without hitting the network.
    ///
    /// Call this: on sign-in, on app foreground, and after a purchase settles.
    func refresh(accessToken: String?) async {
        guard let accessToken else {
            entitlement = nil
            lastError = nil
            return
        }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }
        do {
            entitlement = try await LoreAPI.shared.entitlement(accessToken: accessToken)
        } catch {
            // Fail closed: keep whatever we last knew is NOT correct here —
            // if we can't confirm, we must not keep a stale "plus". Drop to
            // free; the surfaces stay usable, the paywall stays honest.
            entitlement = nil
            lastError = "Couldn't verify your membership. You can still use everything free."
        }
    }

    /// Clear on sign-out — the next user starts from free.
    func clear() {
        entitlement = nil
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
}
