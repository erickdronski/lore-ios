import UIKit

/// The haptic vocabulary — brand/ELEVATION.md §4: "the app should be *felt*."
///
/// One enum-driven API (`Haptics.play(.pinTap)`) wrapping UIKit's feedback
/// generators so no view ever instantiates a generator ad hoc — the doctrine
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
        /// A pin on the living map was tapped — `.light` impact.
        case pinTap
        /// A bearing chip (scanner) or filter chip was tapped — `.light` impact.
        case chipTap
        /// The dive dossier unfurled — `.medium` impact.
        case dossierOpen
        /// The scanner locked onto the nearest place — `.rigid` impact.
        /// (The selection ticks as chips pass center are `.scannerChipPass`.)
        case scannerLock
        /// A chip crossed the scanner's center line — selection tick.
        case scannerChipPass
        /// A contribution badge landed — notification `.success`.
        case badgeEarned
        /// "First to Chronicle" claimed — notification `.success`.
        case firstToChronicle
        /// The free-dive meter hit its gate — notification `.warning`.
        /// Doctrine: fire ONCE per gate encounter, never repeated; the
        /// caller owns that once-ness (the gate view plays it on appear).
        case meterGate
        /// The dossier timeline snapped to a decade — selection tick per snap.
        case timelineSnap
    }

    /// Play the haptic for a doctrine event. Safe to call from any view;
    /// on devices without a Taptic Engine the generators quietly no-op.
    static func play(_ event: Event) {
        switch event {
        case .pinTap, .chipTap:
            impact(.light)
        case .dossierOpen:
            impact(.medium)
        case .scannerLock:
            impact(.rigid)
        case .scannerChipPass, .timelineSnap:
            selection()
        case .badgeEarned, .firstToChronicle:
            notify(.success)
        case .meterGate:
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
