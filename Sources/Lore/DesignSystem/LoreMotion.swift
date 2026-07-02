import SwiftUI
import UIKit

/// "Reveal" motion tokens — 1:1 with `lore/brand/tokens/tokens.json` §motion.
/// Nothing pops in — things *bloom*, *unfurl*, *settle*. No ad-hoc curves in
/// views: every animation in the app goes through this enum
/// (brand/DESIGN.md §6).
enum LoreMotion {
    // MARK: Durations (seconds)

    /// 120 ms — touch feedback, chip toggles, pill mode switches.
    static let tapDuration: TimeInterval = 0.120
    /// 320 ms — pin entrance: scale 0.6→1.0 + opacity 0→1.
    static let bloomDuration: TimeInterval = 0.320
    /// 420 ms — Layer-1 card rising from the pin; sheet presentations.
    static let unfurlDuration: TimeInterval = 0.420
    /// 800 ms — ambient settles: map recenters, cluster expand.
    static let driftDuration: TimeInterval = 0.800
    /// 40 ms per pin, max 6 staggered then simultaneous.
    static let staggerPerPin: TimeInterval = 0.040
    static let staggerMaxCount = 6
    /// Reduced-motion replacement: every spring becomes a 160 ms crossfade.
    static let reducedDuration: TimeInterval = 0.160

    // MARK: Animations

    /// `reveal.tap` — easeOut cubic-bezier(0.2, 0, 0, 1), 120 ms.
    static var tap: Animation {
        reduced(.timingCurve(0.2, 0, 0, 1, duration: tapDuration))
    }

    /// `reveal.bloom` — spring(response 0.38, damping 0.78), ~320 ms.
    static var bloom: Animation {
        reduced(.spring(response: 0.38, dampingFraction: 0.78))
    }

    /// `reveal.unfurl` — spring(response 0.50, damping 0.86), ~420 ms.
    static var unfurl: Animation {
        reduced(.spring(response: 0.50, dampingFraction: 0.86))
    }

    /// `reveal.drift` — easeInOut, 800 ms.
    static var drift: Animation {
        reduced(.easeInOut(duration: driftDuration))
    }

    /// Stagger delay for the nth pin in a cascade (near → far order); pins
    /// past `staggerMaxCount` land simultaneously with the last staggered one.
    static func staggerDelay(index: Int) -> TimeInterval {
        guard !UIAccessibility.isReduceMotionEnabled else { return 0 }
        return TimeInterval(min(index, staggerMaxCount)) * staggerPerPin
    }

    /// Reduced Motion contract (brand/DESIGN.md §6): springs become a 160 ms
    /// crossfade; changes *how*, never *whether*, information arrives.
    private static func reduced(_ animation: Animation) -> Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .easeInOut(duration: reducedDuration)
            : animation
    }
}

/// Luxury-motion spring tokens (brand/LUXURY-MOTION.md §2) as SwiftUI
/// `Animation`s. Where "Reveal" (`LoreMotion`) is the base entrance grammar,
/// `LoreSpring` is the finer-grained physics vocabulary the polish pass rides
/// on: one confident spring per moment, with mass and momentum.
///
/// Four springs, mapped from the doctrine's stiffness/damping pairs onto
/// SwiftUI's `response`/`dampingFraction` model (which is easier to reason
/// about and interruptible):
///
/// | Token   | Feel                          | response · damping |
/// |---------|-------------------------------|--------------------|
/// | `snappy`| buttons, chips, taps          | .28 · .82 (no overshoot) |
/// | `bounce`| arrivals: pins, cards, badges | .50 · .68 (visible overshoot) |
/// | `smooth`| sheets, panels, transitions   | .45 · .90 (settled) |
/// | `slow`  | hero / ambient / arrival      | .80 · .86 (cinematic) |
///
/// Every token has three forms:
/// - `LoreSpring.snappy` — the plain `.spring`.
/// - `LoreSpring.snappyInteractive` — the `.interactiveSpring`, for
///   gesture-tracked / interruptible motion (drag, press-and-hold).
/// - `LoreSpring.snappy(reduceMotion:)` — Reduce-Motion-aware: returns a
///   160 ms crossfade when the flag is set. Prefer this in views, driving it
///   from `@Environment(\.accessibilityReduceMotion)`.
enum LoreSpring {
    // MARK: Response / damping tokens (LUXURY-MOTION §2)

    /// Buttons, chips, taps — quick, no overshoot.
    static let snappyResponse: Double = 0.28
    static let snappyDamping: Double = 0.82
    /// Arrivals — pins landing, card open, badge pop; visible overshoot.
    static let bounceResponse: Double = 0.50
    static let bounceDamping: Double = 0.68
    /// Sheets, panels, page transitions — settled, no overshoot.
    static let smoothResponse: Double = 0.45
    static let smoothDamping: Double = 0.90
    /// Hero / ambient / the arrival — slow and cinematic.
    static let slowResponse: Double = 0.80
    static let slowDamping: Double = 0.86

    // MARK: Plain springs

    /// `spring.snappy` — response .28, damping .82. Buttons, chips, taps.
    static var snappy: Animation {
        .spring(response: snappyResponse, dampingFraction: snappyDamping)
    }
    /// `spring.bounce` — response .5, damping .68. Arrivals; visible overshoot.
    static var bounce: Animation {
        .spring(response: bounceResponse, dampingFraction: bounceDamping)
    }
    /// `spring.smooth` — response .45, damping .9. Sheets, panels, transitions.
    static var smooth: Animation {
        .spring(response: smoothResponse, dampingFraction: smoothDamping)
    }
    /// `spring.slow` — response .8, damping .86. Hero / ambient / arrival.
    static var slow: Animation {
        .spring(response: slowResponse, dampingFraction: slowDamping)
    }

    // MARK: Interactive springs (gesture-tracked, interruptible)

    /// Interruptible `snappy` — for press-and-hold and gesture tracking.
    static var snappyInteractive: Animation {
        .interactiveSpring(response: snappyResponse, dampingFraction: snappyDamping)
    }
    /// Interruptible `bounce`.
    static var bounceInteractive: Animation {
        .interactiveSpring(response: bounceResponse, dampingFraction: bounceDamping)
    }
    /// Interruptible `smooth` — sheet drags, panel drags.
    static var smoothInteractive: Animation {
        .interactiveSpring(response: smoothResponse, dampingFraction: smoothDamping)
    }
    /// Interruptible `slow`.
    static var slowInteractive: Animation {
        .interactiveSpring(response: slowResponse, dampingFraction: slowDamping)
    }

    // MARK: Reduce-Motion-aware forms

    /// `snappy`, or a 160 ms crossfade under Reduce Motion. Drive `reduceMotion`
    /// from `@Environment(\.accessibilityReduceMotion)`.
    static func snappy(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedCrossfade : snappy
    }
    /// `bounce`, or a 160 ms crossfade under Reduce Motion.
    static func bounce(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedCrossfade : bounce
    }
    /// `smooth`, or a 160 ms crossfade under Reduce Motion.
    static func smooth(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedCrossfade : smooth
    }
    /// `slow`, or a 160 ms crossfade under Reduce Motion.
    static func slow(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedCrossfade : slow
    }

    /// The single Reduce-Motion fallback (brand/DESIGN.md §6, LUXURY-MOTION §7):
    /// a ≤160 ms crossfade, no transform, no overshoot.
    static var reducedCrossfade: Animation {
        .easeInOut(duration: LoreMotion.reducedDuration)
    }
}
