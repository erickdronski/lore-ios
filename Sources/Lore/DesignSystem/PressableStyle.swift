import SwiftUI

/// The universal press feedback (brand/LUXURY-MOTION.md §5: "every element
/// earns its tap"). A `ButtonStyle` so any `Button` gets it for free:
/// - press → scale to 0.96 + a light `Haptics.play(.chipTap)`,
/// - release → springs back on `LoreSpring.snappy`.
///
/// Under Reduce Motion the scale transform is dropped entirely (no press-lift,
/// no spring); the haptic still fires (haptics are not motion) and the button
/// stays fully functional. Optionally dims slightly on press for a second,
/// non-transform affordance that survives Reduce Motion.
///
/// ```swift
/// Button("Go deeper") { … }.buttonStyle(PressableStyle())
/// ```
struct PressableStyle: ButtonStyle {
    /// The scale the button rests at while pressed (LUXURY-MOTION §5: 0.96).
    var pressedScale: CGFloat = 0.96
    /// Opacity while pressed — a subtle dim that also reads under Reduce Motion.
    var pressedOpacity: Double = 0.92
    /// Fire a light haptic on press-down. On by default (taps should be felt);
    /// turn off for dense/rapid controls where a tick per press would nag.
    var haptics: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? pressedScale : 1))
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(pressAnimation, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed, haptics { Haptics.play(.chipTap) }
            }
    }

    private var pressAnimation: Animation {
        reduceMotion ? LoreSpring.reducedCrossfade : LoreSpring.snappy
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// The default press feedback (scale 0.96 + light haptic, spring back).
    static var pressable: PressableStyle { PressableStyle() }

    /// Press feedback with no haptic — for dense or rapidly-tapped controls.
    static var pressableSilent: PressableStyle { PressableStyle(haptics: false) }
}

/// A press modifier for surfaces that are tappable but not `Button`s (a card,
/// a pin, a row with its own gesture). Wraps the same scale-0.96 + haptic +
/// spring-back behaviour around an arbitrary `isPressed` you drive from a
/// `DragGesture(minimumDistance: 0)` or a `.onLongPressGesture` press closure.
///
/// Prefer `PressableStyle` (the `ButtonStyle`) whenever the element is a real
/// button; reach for this only when it can't be.
struct PressableSurface: ViewModifier {
    /// Drive from your own gesture's press state.
    let isPressed: Bool
    var pressedScale: CGFloat = 0.96
    var pressedOpacity: Double = 0.92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (isPressed ? pressedScale : 1))
            .opacity(isPressed ? pressedOpacity : 1)
            .animation(reduceMotion ? LoreSpring.reducedCrossfade : LoreSpring.snappy, value: isPressed)
            .onChange(of: isPressed) { _, pressed in
                if pressed { Haptics.play(.chipTap) }
            }
    }
}

extension View {
    /// Give a non-button surface the standard press-lift (scale 0.96 + light
    /// haptic, spring back). Drive `isPressed` from your own gesture.
    func pressableSurface(isPressed: Bool) -> some View {
        modifier(PressableSurface(isPressed: isPressed))
    }
}
