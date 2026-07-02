import SwiftUI

/// Considered-loading foundation (brand/LUXURY-MOTION.md §3: "delete every
/// spinner"). A shimmering placeholder: a muted Bone/Ink base with a slow
/// **Amber-tinted** gradient sweep (1.4s loop) traveling across it, so a
/// loading surface reads as "content is arriving here," shaped like the content
/// that will land.
///
/// Under Reduce Motion the sweep is dropped for a **static** muted block
/// (LUXURY-MOTION §3, §7) — still clearly a placeholder, just not animated.
///
/// Compose skeletons from `ShimmerBlock`s laid out like the real content, or
/// use the `SkeletonCard` / `SkeletonRow` presets.
struct Shimmer: ViewModifier {
    /// Length of one sweep, seconds (LUXURY-MOTION §3: 1.4s).
    var duration: Double = 1.4
    /// Tint of the traveling highlight — Amber, per doctrine.
    var highlight: Color = LoreColor.amber

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        if reduceMotion {
            // Static muted placeholder: no sweep, no motion.
            content
        } else {
            content
                .overlay(sweep.mask(content))
                .onAppear { startSweep() }
        }
    }

    /// The traveling Amber highlight band. A diagonal gradient whose bright
    /// stop rides `phase` from off-left (-1) to off-right (+1).
    private var sweep: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: highlight.opacity(0.35), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.6)
            .offset(x: phase * width)
        }
        .allowsHitTesting(false)
    }

    private func startSweep() {
        phase = -1
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

extension View {
    /// Sweep an Amber shimmer highlight across this view (Reduce-Motion static).
    /// Apply to a filled placeholder shape; the sweep is masked to the shape.
    func shimmer(duration: Double = 1.4) -> some View {
        modifier(Shimmer(duration: duration))
    }
}

/// A single skeleton primitive: a rounded, muted block that shimmers. The atom
/// every skeleton layout is built from (a name bar, a hook bar, a chip, a
/// thumbnail). Fill color sits on the recessed end of the surface stack so it
/// reads as "not-yet-content."
struct ShimmerBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 6
    /// Base fill — defaults to the recessed light surface (`bone200`). Pass an
    /// Ink-ramp value on dark surfaces.
    var fill: Color = LoreColor.bone200

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
            .shimmer()
            .accessibilityHidden(true)
    }
}

/// A content-shaped card skeleton (brand/LUXURY-MOTION.md §3): a card outline
/// with shimmer bars where the place name, hook, and chips will be, and a
/// leading medallion where the emoji disc lands. Mirrors the Layer-1 `Card`
/// anatomy (brand/DESIGN.md §7) so the swap from skeleton to real card is a
/// cross-fade with no layout shift.
struct SkeletonCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Emoji medallion placeholder.
            Circle()
                .fill(LoreColor.bone200)
                .frame(width: 44, height: 44)
                .shimmer()

            VStack(alignment: .leading, spacing: 8) {
                ShimmerBlock(width: 180, height: 20, cornerRadius: 6)   // name
                ShimmerBlock(width: 240, height: 14, cornerRadius: 5)   // hook
                HStack(spacing: 6) {                                    // chips
                    ShimmerBlock(width: 56, height: 20, cornerRadius: 8)
                    ShimmerBlock(width: 72, height: 20, cornerRadius: 8)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LoreColor.bone50)
        )
        .loreElevation(.elev1)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

/// A content-shaped row skeleton — a compact list item (near-you shelf, search
/// result, tour stop): a leading thumbnail/disc + two text bars. Use several
/// stacked (optionally via `StaggeredReveal`) for a loading list.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LoreColor.bone200)
                .frame(width: 40, height: 40)
                .shimmer()

            VStack(alignment: .leading, spacing: 6) {
                ShimmerBlock(width: 160, height: 15, cornerRadius: 5)
                ShimmerBlock(width: 100, height: 12, cornerRadius: 5)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}
