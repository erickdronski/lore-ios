#if DEBUG
import Foundation

/// Launch hooks used only by the App Store screenshot pipeline
/// (`fastlane screenshots` → the `LoreUITests` capturer). The whole file is
/// wrapped in `#if DEBUG`, so it is compiled out of the Release/TestFlight
/// binary entirely and can never touch a shipping user.
///
/// The capturer passes the `LORE_SCREENSHOTS` launch argument; when present we
/// fast-forward past first-run onboarding so the capture lands on the Map
/// immediately (the gate reads `OnboardingStore.didOnboardDefaultsKey`, which we
/// set here before the presenter's `init` reads it). Call `applyIfNeeded()` as
/// the very first thing in `LoreApp.init`.
enum ScreenshotSupport {
    /// True when the process was launched by the screenshot capturer.
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("LORE_SCREENSHOTS")
    }

    /// Optional "deep" surface the capturer wants staged on launch, read from
    /// the `LORE_SHOW` launch environment. The Simulator can walk the tab bar on
    /// its own, but the dossier and the culture sheet are presented state, not a
    /// tab, so the capturer relaunches with a stage and `LoreApp` opens it
    /// deterministically (no fragile map-pin taps). Values: `"dive"` (open a
    /// known landmark's deep-dive) and `"culture"` (open Meet-the-City).
    static var stage: String? {
        let value = ProcessInfo.processInfo.environment["LORE_SHOW"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// The landmark whose dossier the `"dive"` stage opens: Willis Tower, the
    /// most recognizable thing in the pilot city, with a deep sourced narrative
    /// and a Wikipedia hero photo. Matched by slug in the live Chicago set.
    static let diveSlug = "willis-tower"

    /// The `"card"` stage's target, overridable so any city/place can be staged
    /// (verification + future screenshots of the community layer). Defaults to
    /// the pilot-city dive landmark.
    static var cardCity: String {
        ProcessInfo.processInfo.environment["LORE_CARD_CITY"] ?? "chicago"
    }
    static var cardSlug: String {
        ProcessInfo.processInfo.environment["LORE_CARD_SLUG"] ?? diveSlug
    }

    /// Idempotent. Prepares a clean, first-run-skipped state for the capturer.
    static func applyIfNeeded() {
        guard isActive else { return }
        // Mark onboarding complete so the full-screen cover never presents.
        UserDefaults.standard.set(true, forKey: OnboardingStore.didOnboardDefaultsKey)
    }
}
#endif
