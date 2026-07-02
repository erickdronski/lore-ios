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
