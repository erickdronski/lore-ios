import SwiftUI

/// Choreographed entrances (brand/LUXURY-MOTION.md §3, §6 · ELEVATION.md §3
/// `fade.rise`). A container that reveals its children in a **40ms cascade** —
/// each item fades in (opacity 0→1) and rises (translateY 14pt→0), ordered, so
/// a list/shelf/panel assembles itself rather than snapping in all at once.
///
/// Used for: near-you shelf cards, filter chips, passport badges, search
/// results, gallery tiles, timeline nodes.
///
/// Under Reduce Motion the cascade and the rise are dropped: every child appears
/// together with a single ≤160ms opacity crossfade (no stagger, no transform) —
/// information still arrives, just without the choreography (LUXURY-MOTION §7).
///
/// Two ways to use it:
/// - `StaggeredReveal { A(); B(); C() }`, wrap a fixed set of children in a
///   `VStack`-style cascade.
/// - `StaggeredReveal(data) { item in Row(item) }`, cascade over a collection.
struct StaggeredReveal<Content: View>: View {
    /// Per-item stagger (ELEVATION §3 `fade.rise`: 40ms).
    var step: TimeInterval = LoreMotion.staggerPerPin
    /// Cap the cascade so a long list doesn't take forever; items past the cap
    /// land with the last staggered one (mirrors `reveal.stagger` max).
    var maxStaggered: Int = 8
    /// Distance the child rises from (LUXURY-MOTION / ELEVATION `fade.rise`: 14pt).
    var rise: CGFloat = 14
    /// Spacing between the stacked children.
    var spacing: CGFloat = 12
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    init(
        step: TimeInterval = LoreMotion.staggerPerPin,
        maxStaggered: Int = 8,
        rise: CGFloat = 14,
        spacing: CGFloat = 12,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: () -> Content
    ) {
        self.step = step
        self.maxStaggered = maxStaggered
        self.rise = rise
        self.spacing = spacing
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            // `_VariadicView` isn't public, so we walk the children via a Group
            // subview index provided by `.staggeredRevealChild`. Simpler: apply
            // the cascade per-child through the environment-free index modifier.
            content
        }
        // The container flips `appeared`; children read it through the modifier
        // applied by the caller (`.staggerChild(index:)`), see below.
        .environment(\.staggerAppeared, appeared)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation { appeared = true }
            }
        }
    }
}

/// Convenience for cascading over a `RandomAccessCollection`: this variant owns
/// the indexing, so children need no `.staggerChild` call.
struct StaggeredForEach<Data: RandomAccessCollection, ID: Hashable, RowContent: View>: View
where Data.Element: Identifiable, Data.Element.ID == ID {
    let data: Data
    var step: TimeInterval = LoreMotion.staggerPerPin
    var maxStaggered: Int = 8
    var rise: CGFloat = 14
    var spacing: CGFloat = 12
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder let row: (Data.Element) -> RowContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                row(element)
                    .modifier(StaggerChild(
                        index: index,
                        appeared: appeared,
                        step: step,
                        maxStaggered: maxStaggered,
                        rise: rise,
                        reduceMotion: reduceMotion
                    ))
            }
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation { appeared = true }
            }
        }
    }
}

/// The per-child fade+rise. Fades opacity 0→1 and translates from `rise`pt below
/// to 0, on `LoreSpring.smooth`, delayed by `index * step` (capped). Reduce
/// Motion: no rise, no per-item delay, a single crossfade.
struct StaggerChild: ViewModifier {
    let index: Int
    let appeared: Bool
    var step: TimeInterval = LoreMotion.staggerPerPin
    var maxStaggered: Int = 8
    var rise: CGFloat = 14
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: yOffset)
            .animation(animation, value: appeared)
    }

    private var yOffset: CGFloat {
        if reduceMotion { return 0 }        // no transform under Reduce Motion
        return appeared ? 0 : rise
    }

    private var delay: TimeInterval {
        guard !reduceMotion else { return 0 }
        return TimeInterval(min(index, maxStaggered)) * step
    }

    private var animation: Animation {
        reduceMotion
            ? LoreSpring.reducedCrossfade
            : LoreSpring.smooth.delay(delay)
    }
}

extension View {
    /// Mark this view as the `index`-th child of a `StaggeredReveal`, giving it
    /// the fade+rise cascade. Read the container's appearance from the
    /// `\.staggerAppeared` environment value.
    ///
    /// ```swift
    /// StaggeredReveal {
    ///     ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
    ///         CardView(card).staggerChild(index: i)
    ///     }
    /// }
    /// ```
    func staggerChild(
        index: Int,
        step: TimeInterval = LoreMotion.staggerPerPin,
        maxStaggered: Int = 8,
        rise: CGFloat = 14
    ) -> some View {
        modifier(StaggerChildEnvironment(
            index: index, step: step, maxStaggered: maxStaggered, rise: rise
        ))
    }
}

/// Bridges the container's `\.staggerAppeared` environment flag and the device's
/// Reduce-Motion setting into a `StaggerChild`, so callers pass only an index.
private struct StaggerChildEnvironment: ViewModifier {
    let index: Int
    let step: TimeInterval
    let maxStaggered: Int
    let rise: CGFloat

    @Environment(\.staggerAppeared) private var appeared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.modifier(StaggerChild(
            index: index,
            appeared: appeared,
            step: step,
            maxStaggered: maxStaggered,
            rise: rise,
            reduceMotion: reduceMotion
        ))
    }
}

// MARK: - Environment key

private struct StaggerAppearedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True once the enclosing `StaggeredReveal` has begun its cascade.
    var staggerAppeared: Bool {
        get { self[StaggerAppearedKey.self] }
        set { self[StaggerAppearedKey.self] = newValue }
    }
}
