import Foundation
import Observation

/// The free-tier deep-dive allowance: **3 dives per day** (docs/00-DECISIONS.md
/// §7). Lore+ members bypass this entirely, the meter is only consulted when
/// `EntitlementStore.isPlus == false`.
///
/// ## Doctrine: never gate mid-wonder
///
/// The gate lands on the **4th** dive of a day, never the 1st, 2nd, or 3rd. A
/// visitor's first taps in a new city must always open, the paywall shows up
/// only after they've felt the value three times. `canOpenDive` is the free
/// user's remaining-count check; `recordDiveOpened` is called *after* a dive
/// actually opens, so the count reflects consumed wonder, not intent.
///
/// ## Persistence
///
/// Count + day are persisted in `UserDefaults` so the allowance survives
/// relaunch but resets at local midnight. This is the P0 client-side meter.
///
/// **Server is the real source of truth (P1).** The backend will track
/// `dive_reads` per user per day (an authenticated, tamper-proof counter that a
/// reinstall or a second device can't reset). At that point this meter becomes
/// an *optimistic local mirror*: it still gives instant, offline-correct
/// answers, but reconciles against the server count on refresh, and the server
/// has final say on whether the gate is up. Until then, a determined free user
/// can reset by clearing app data, an acceptable P0 leak, called out here so
/// nobody mistakes the client meter for enforcement.
/// TODO(P1): wire `reconcile(serverCount:day:)` to `GET /rpc/dive_reads_today`
/// (or the `dive_reads` table) and let the server value win on conflict.
@Observable
@MainActor
final class DiveMeter {
    /// Free-tier daily allowance (docs/00 §7). Change here changes everywhere.
    static let dailyFreeAllowance = 3

    /// Dives opened *today* (local day). Resets when the calendar day rolls.
    private(set) var usedToday: Int = 0

    private let defaults: UserDefaults
    private let calendar: Calendar

    /// `UserDefaults` keys, namespaced so they never collide with other
    /// feature state.
    private enum Key {
        static let count = "lore.diveMeter.usedToday"
        /// Stored as a day ordinal (`Date` → start-of-day epoch days) so a
        /// simple integer compare tells us whether to reset.
        static let day = "lore.diveMeter.dayOrdinal"
    }

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        rolloverIfNeeded()
        usedToday = defaults.integer(forKey: Key.count)
    }

    // MARK: Reads

    /// Dives left today for a free user (0…allowance). Clamped, never negative.
    var remainingToday: Int {
        max(0, Self.dailyFreeAllowance - usedToday)
    }

    /// Whether a free user may open one more dive right now. Lore+ callers
    /// should short-circuit on `isPlus` and never ask this, but if they do,
    /// this only answers for the free allowance.
    var canOpenFreeDive: Bool {
        remainingToday > 0
    }

    /// The single decision the dive-opening code makes. Lore+ always passes;
    /// free users pass until they've spent the day's allowance.
    ///
    /// - Parameter isPlus: `EntitlementStore.isPlus` at the call site.
    /// - Returns: `true` if the dive should open, `false` if the paywall gate
    ///   should show instead.
    func canOpenDive(isPlus: Bool) -> Bool {
        if isPlus { return true }
        rolloverIfNeeded()
        return canOpenFreeDive
    }

    // MARK: Writes

    /// Record that a dive was actually opened. No-op for Lore+ members (their
    /// dives don't count against a free allowance). Call this **after** the
    /// dive presents, not before, the count tracks consumed wonder.
    ///
    /// - Parameter isPlus: `EntitlementStore.isPlus` at the call site. When
    ///   true, nothing is recorded.
    func recordDiveOpened(isPlus: Bool) {
        guard !isPlus else { return }
        rolloverIfNeeded()
        // Cap the stored count at the allowance so a race can't run it away;
        // the gate is already up once we're here at the limit.
        usedToday = min(usedToday + 1, Self.dailyFreeAllowance)
        persist()
    }

    /// Test / debug hook: force the meter back to a fresh day.
    func resetForNewDay() {
        usedToday = 0
        defaults.set(0, forKey: Key.count)
        defaults.set(todayOrdinal, forKey: Key.day)
    }

    // MARK: Day rollover

    /// Reset the count if the stored day is not today (local midnight boundary).
    private func rolloverIfNeeded() {
        let storedDay = defaults.integer(forKey: Key.day)
        let today = todayOrdinal
        guard storedDay != today else { return }
        usedToday = 0
        defaults.set(0, forKey: Key.count)
        defaults.set(today, forKey: Key.day)
    }

    /// Days since the reference date at *local* start-of-day, a stable integer
    /// that increments exactly once per calendar day in the user's time zone.
    private var todayOrdinal: Int {
        let startOfToday = calendar.startOfDay(for: Date())
        return Int(startOfToday.timeIntervalSinceReferenceDate / 86_400)
    }

    private func persist() {
        defaults.set(usedToday, forKey: Key.count)
        defaults.set(todayOrdinal, forKey: Key.day)
    }
}
