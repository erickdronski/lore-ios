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

    /// Idempotent. Prepares a clean, first-run-skipped state for the capturer.
    static func applyIfNeeded() {
        guard isActive else { return }
        // Mark onboarding complete so the full-screen cover never presents.
        UserDefaults.standard.set(true, forKey: OnboardingStore.didOnboardDefaultsKey)
    }
}
#endif
