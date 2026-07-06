import SwiftUI
import UIKit

/// A two-sided card that flips on tap (3D Y-axis rotation), the paywall gate
/// (the 4th dive card flips to the gate, brand/ELEVATION.md §7) and any
/// "front → detail" reveal. Front and back are supplied as view builders; the
/// back is pre-mirrored so its content reads correctly after the flip.
///
/// Motion: `reveal.unfurl`-family spring (`spring.settle`, no overshoot, a
/// gate must never feel jaunty). Under Reduce Motion the rotation is dropped
/// for a 160 ms opacity crossfade between the two faces (no 3D transform).
struct FlipCard<Front: View, Back: View>: View {
    /// Bind to own the flip state (so a paywall can flip programmatically), or
    /// use the `@State` convenience init for tap-to-flip.
    @Binding var isFlipped: Bool
    /// When true, tapping the card toggles the flip. Off for programmatic-only
    /// (gate) flips.
    var flipOnTap: Bool
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    init(
        isFlipped: Binding<Bool>,
        flipOnTap: Bool = true,
        @ViewBuilder front: @escaping () -> Front,
        @ViewBuilder back: @escaping () -> Back
    ) {
        self._isFlipped = isFlipped
        self.flipOnTap = flipOnTap
        self.front = front
        self.back = back
    }

    var body: some View {
        ZStack {
            // Front, visible for angles < 90°.
            front()
                .opacity(frontOpacity)
                .accessibilityHidden(isFlipped)

            // Back, pre-mirrored so text isn't reversed after the flip.
            back()
                .scaleEffect(x: -1, y: 1)
                .opacity(backOpacity)
                .accessibilityHidden(!isFlipped)
        }
        .modifier(FlipRotation(isFlipped: isFlipped, enabled: !reduceMotion))
        .contentShape(Rectangle())
        .onTapGesture {
            guard flipOnTap else { return }
            Haptics.play(.chipTap)
            withAnimation(flipAnimation) { isFlipped.toggle() }
        }
        .accessibilityAddTraits(flipOnTap ? .isButton : [])
    }

    // Opacity gates which face shows. Under Reduce Motion this crossfade *is*
    // the transition (no rotation). With motion on, the same gate also keeps
    // the off-face from ghosting through as the card passes 90°.
    private var frontOpacity: Double { isFlipped ? 0 : 1 }

    private var backOpacity: Double { isFlipped ? 1 : 0 }

    private var flipAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: LoreMotion.reducedDuration)
            // spring.settle: stiffness 260, damping 30 (no overshoot).
            : .interpolatingSpring(stiffness: 260, damping: 30)
    }
}

/// The 3D rotation transform for the flip; disabled (identity) under Reduce
/// Motion so no perspective transform is applied.
private struct FlipRotation: ViewModifier {
    let isFlipped: Bool
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.rotation3DEffect(
                .degrees(isFlipped ? 180 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
        } else {
            content
        }
    }
}

/// Tap-to-flip convenience that owns its flip state, use when the caller has
/// no reason to hold the `isFlipped` binding itself. Wraps `FlipCard` with an
/// internal `@State` so tapping actually toggles (a `.constant` binding can't).
///
/// ```swift
/// StatefulFlipCard {
///     PlaceCardView(place: place)     // front
/// } back: {
///     DiveTeaserView(place: place)    // back
/// }
/// ```
struct StatefulFlipCard<Front: View, Back: View>: View {
    @State private var isFlipped = false
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back

    init(
        @ViewBuilder front: @escaping () -> Front,
        @ViewBuilder back: @escaping () -> Back
    ) {
        self.front = front
        self.back = back
    }

    var body: some View {
        FlipCard(isFlipped: $isFlipped, flipOnTap: true, front: front, back: back)
    }
}
