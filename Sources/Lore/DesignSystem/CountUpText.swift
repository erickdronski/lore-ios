import SwiftUI

/// Count-up numerals (brand/ELEVATION.md §3 `ticker.count` · LUXURY-MOTION.md §5:
/// "Numbers count up with a ticker on first view"). A number that rolls from a
/// start value up to its target over ~800ms with an ease-out, on first appear —
/// used for the year built, height, distance, Insight points, achievement
/// counts.
///
/// Driven by SwiftUI's `Animatable` via a private `AnimatableModifier`, so the
/// interpolation runs on the render thread and every intermediate frame is
/// formatted through the caller's `format` closure (no manual timers).
///
/// Under Reduce Motion the value is shown at its target immediately — no roll
/// (LUXURY-MOTION §7: no motion where it isn't needed; the number still arrives).
struct CountUpText: View {
    /// The destination value.
    let value: Double
    /// Where the roll starts (usually 0; pass the previous value to animate a
    /// delta instead of from zero).
    var from: Double = 0
    /// Roll duration (ELEVATION §3: ~800ms).
    var duration: Double = 0.8
    /// Formats each intermediate value into display text (e.g. `"\(Int($0))"`,
    /// `"\(Int($0)) ft"`, a distance string). Called every animation frame.
    var format: (Double) -> String
    /// Font applied to the rendered text.
    var font: Font = LoreType.displayM

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedValue: Double

    init(
        value: Double,
        from: Double = 0,
        duration: Double = 0.8,
        font: Font = LoreType.displayM,
        format: @escaping (Double) -> String
    ) {
        self.value = value
        self.from = from
        self.duration = duration
        self.font = font
        self.format = format
        // Start at `from`; the roll to `value` runs in `.onAppear`.
        _animatedValue = State(initialValue: from)
    }

    var body: some View {
        // A zero-size anchor carries the AnimatableModifier that re-renders the
        // formatted text every interpolated frame — one Text, driven on the
        // render thread.
        Color.clear
            .frame(width: 0, height: 0)
            .modifier(CountUpAnimator(value: animatedValue, format: format, font: font))
            .fixedSize()
            .onAppear {
                if reduceMotion {
                    animatedValue = value    // straight to target, no roll
                } else {
                    animatedValue = from
                    withAnimation(.easeOut(duration: duration)) {
                        animatedValue = value
                    }
                }
            }
            // A VoiceOver reader announces the final value, never the roll.
            .accessibilityLabel(format(value))
    }
}

/// Interpolates the numeric value on the render thread so every in-between frame
/// is formatted, giving a true rolling ticker rather than a single jump. The
/// rendered `Text` replaces the modified content, so the host view can be a
/// zero-size anchor. Conforms to `Animatable` + `ViewModifier` directly (the
/// modern replacement for the deprecated `AnimatableModifier`).
private struct CountUpAnimator: ViewModifier, Animatable {
    var value: Double
    let format: (Double) -> String
    let font: Font

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(format(value))
            .font(font)
            .monospacedDigit()               // digits don't jitter as they roll
    }
}

extension CountUpText {
    /// Integer convenience — rolls to `Int(value)` and formats with a rounded
    /// integer (optionally a suffix like " ft", " yrs"). The most common case:
    /// years, heights, points.
    static func integer(
        _ value: Int,
        suffix: String = "",
        from: Int = 0,
        duration: Double = 0.8,
        font: Font = LoreType.displayM
    ) -> CountUpText {
        CountUpText(
            value: Double(value),
            from: Double(from),
            duration: duration,
            font: font
        ) { current in
            "\(Int(current.rounded()))\(suffix)"
        }
    }
}
