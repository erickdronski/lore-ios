import UIKit

/// The haptic vocabulary, brand/ELEVATION.md §4: "the app should be *felt*."
///
/// One enum-driven API (`Haptics.play(.pinTap)`) wrapping UIKit's feedback
/// generators so no view ever instantiates a generator ad hoc, the doctrine
/// table lives here, in exactly one place:
///
/// | Doctrine event                          | Case                | Generator |
/// |-----------------------------------------|---------------------|-----------|
/// | Pin tap / chip tap                      | `.pinTap`/`.chipTap`| `UIImpactFeedbackGenerator(.light)` |
/// | Dossier opens                           | `.dossierOpen`      | `UIImpactFeedbackGenerator(.medium)` |
/// | Scanner locks onto a place              | `.scannerLock`      | `UIImpactFeedbackGenerator(.rigid)` |
/// | Chips pass the scanner's center         | `.scannerChipPass`  | `UISelectionFeedbackGenerator` |
/// | Badge earned / First to Chronicle       | `.badgeEarned` / `.firstToChronicle` | `UINotificationFeedbackGenerator(.success)` |
/// | Meter exhausted / gate (once, never repeated) | `.meterGate`  | `UINotificationFeedbackGenerator(.warning)` |
/// | Timeline decade snap (per snap)         | `.timelineSnap`     | `UISelectionFeedbackGenerator` |
///
/// Haptics are seasoning, not structure: every call is fire-and-forget and
/// nothing in the app gates on whether the Taptic Engine answered.
@MainActor
enum Haptics {
    /// Every haptic-worthy moment in Lore, named for the doctrine table.
    enum Event {
        /// A pin on the living map was tapped, `.light` impact.
        case pinTap
        /// A bearing chip (scanner) or filter chip was tapped, `.light` impact.
        case chipTap
        /// The dive dossier unfurled, `.medium` impact.
        case dossierOpen
        /// The scanner locked onto the nearest place, `.rigid` impact.
        /// (The selection ticks as chips pass center are `.scannerChipPass`.)
        case scannerLock
        /// A chip crossed the scanner's center line, selection tick.
        case scannerChipPass
        /// The scanner became active / the camera was raised, `.light` impact.
        /// A single "I'm awake and looking" pulse so pointing the phone always
        /// *feels* like something started (never a dead viewfinder).
        case scanAttempt
        /// A new on-device read appeared ("Looks like a skyscraper"), selection
        /// tick, so the user feels the scanner respond to what they aim at.
        case scanRecognizing
        /// The honest "nothing here" thunk, notification `.warning`, fired ONCE
        /// on entering the nothing-recognized state (never a per-frame buzz).
        case scanNothing
        /// A contribution badge landed, notification `.success`.
        case badgeEarned
        /// "First to Chronicle" claimed, notification `.success`.
        case firstToChronicle
        /// The free-dive meter hit its gate, notification `.warning`.
        /// Doctrine: fire ONCE per gate encounter, never repeated; the
        /// caller owns that once-ness (the gate view plays it on appear).
        case meterGate
        /// The dossier timeline snapped to a decade, selection tick per snap.
        case timelineSnap
    }

    /// The UserDefaults key behind the Settings → "Haptic feedback" toggle.
    /// Absent means on (haptics default to seasoning-on).
    static let enabledDefaultsKey = "lore.haptics.enabled"

    /// The user's master haptics switch. On unless they turned it off in
    /// Settings; read fresh per call so the toggle takes effect immediately.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

    /// Play the haptic for a doctrine event. Safe to call from any view;
    /// on devices without a Taptic Engine the generators quietly no-op, and
    /// the whole vocabulary is gated by the user's Settings toggle.
    static func play(_ event: Event) {
        guard isEnabled else { return }
        switch event {
        case .pinTap, .chipTap:
            impact(.light)
        case .dossierOpen:
            impact(.medium)
        case .scannerLock:
            impact(.rigid)
        case .scannerChipPass, .timelineSnap, .scanRecognizing:
            selection()
        case .scanAttempt:
            impact(.light)
        case .badgeEarned, .firstToChronicle:
            notify(.success)
        case .meterGate, .scanNothing:
            notify(.warning)
        }
    }

    // MARK: - Generators

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
