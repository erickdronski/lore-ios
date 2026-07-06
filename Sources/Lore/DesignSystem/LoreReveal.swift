import SwiftUI
import UIKit

/// The "Reveal" bounce entrance (brand/ELEVATION.md §3 `spring.bounce`,
/// stiffness 380 / damping 22, ~8% overshoot) as a reusable modifier: pins
/// landing, chips arriving, badge pops. Nothing pops in, things *bloom* into
/// place, then settle.
///
/// Honors Reduce Motion (§3): the bounce becomes a 160 ms opacity crossfade
/// with no scale transform. Information *arrival* is preserved; only the
/// *physics* is dropped.
struct RevealBounce: ViewModifier {
    /// Flip to true to trigger the entrance (e.g. `.onAppear`, or when a pin
    /// enters the frustum). Driving it with a bool lets callers re-run it.
    let isActive: Bool
    /// Optional stagger delay (near→far pin cascades). Ignored under Reduce
    /// Motion.
    var delay: TimeInterval = 0
    /// The scale a non-active view rests at before blooming (0.6 matches the
    /// pin-entrance spec, brand/DESIGN.md §6 `reveal.bloom`).
    var fromScale: CGFloat = 0.6

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(isActive ? 1 : 0)
            .animation(animation, value: isActive)
    }

    private var scale: CGFloat {
        if reduceMotion { return 1 }        // no scale transform under Reduce Motion
        return isActive ? 1 : fromScale
    }

    private var animation: Animation {
        if reduceMotion {
            return .easeInOut(duration: LoreMotion.reducedDuration).delay(0)
        }
        // spring.bounce: stiffness 380, damping 22, a visible overshoot.
        return .interpolatingSpring(stiffness: 380, damping: 22).delay(delay)
    }
}

/// A one-shot "verified"/"badge earned" pop: a 1.2× overshoot pulse, the only
/// celebratory scale in the app (brand/DESIGN.md §6 verified moment). Drive
/// `trigger` (e.g. an incrementing counter or a Bool) to fire it; pairs with
/// `Haptics.play(.badgeEarned)` at the call site.
struct RevealPulse: ViewModifier {
    /// Any `Equatable` whose change fires one pulse.
    var trigger: Bool
    @State private var pulsing = false

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing && !reduceMotion ? 1.2 : 1.0)
            .animation(
                reduceMotion
                    ? .easeInOut(duration: LoreMotion.reducedDuration)
                    : .interpolatingSpring(stiffness: 320, damping: 14),
                value: pulsing
            )
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                pulsing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    pulsing = false
                }
            }
    }
}

extension View {
    /// Reveal-bounce this view into place when `isActive` becomes true
    /// (brand/ELEVATION.md §3 `spring.bounce`). Reduce-Motion-safe.
    ///
    /// ```swift
    /// PinView().revealBounce(isActive: appeared, delay: LoreMotion.staggerDelay(index: i))
    /// ```
    func revealBounce(
        isActive: Bool,
        delay: TimeInterval = 0,
        fromScale: CGFloat = 0.6
    ) -> some View {
        modifier(RevealBounce(isActive: isActive, delay: delay, fromScale: fromScale))
    }

    /// Fire a single celebratory 1.2× pulse whenever `trigger` flips
    /// (the verified / badge-earned moment). Reduce-Motion-safe.
    func revealPulse(trigger: Bool) -> some View {
        modifier(RevealPulse(trigger: trigger))
    }
}
