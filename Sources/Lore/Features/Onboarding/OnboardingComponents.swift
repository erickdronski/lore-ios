import SwiftUI

// MARK: - Dusk background (ELEVATION §2 grad.dusk + grad.horizon)

/// The full-bleed brand sky behind the whole flow: `grad.dusk` (vertical Ink
/// duskscape with an Amber horizon glow) plus a soft bottom `grad.horizon`
/// city-glow. Every gradient stop is inside the brand family (ELEVATION §2:
/// "all gradients stay inside the brand family").
///
/// The cinematic layer (LUXURY-MOTION §6, §7 "the arrival gets the slow
/// treatment, grain + Amber horizon glow rising"): a fine film grain sits over
/// the sky, and the Amber horizon glow *rises* once, slowly, on first appear
/// (`spring.slow`). Reduce Motion holds the glow at its risen rest, no rise, no
/// shimmer, so the still image is identical, just without the motion.
struct OnboardingBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowRisen = false

    var body: some View {
        ZStack {
            // grad.dusk, linear(180°, #0A0F1D → #0F1626 → #1B2A4A → amber 16%)
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x0A0F1D), location: 0.0),
                    .init(color: LoreColor.ink900, location: 0.45),
                    .init(color: Color(hex: 0x1B2A4A), location: 0.78),
                    .init(color: LoreColor.amber.opacity(0.16), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // grad.horizon, radial Amber city-glow rising from the bottom edge.
            // On first appear it swells up from a low ember to full glow over a
            // slow spring, so arrival reads cinematic (the "wow" beat, §6).
            RadialGradient(
                colors: [LoreColor.amber.opacity(0.22), .clear],
                center: .init(x: 0.5, y: 1.0),
                startRadius: 0,
                endRadius: glowRisen ? 420 : 240
            )
            .opacity(glowRisen ? 1 : 0.55)
            .blendMode(.screen)
            .allowsHitTesting(false)

            // Film grain, a fine, static Ink/Bone speckle at low opacity so the
            // sky has photographic texture, not a flat digital fill. Static by
            // design (grain that moves is noise); safe under Reduce Motion.
            FilmGrain()
                .opacity(0.05)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onAppear {
            if reduceMotion {
                glowRisen = true
            } else {
                withAnimation(LoreSpring.slow) { glowRisen = true }
            }
        }
    }
}

/// A cheap, deterministic film-grain texture: a Canvas of many tiny Bone specks
/// at fixed pseudo-random positions. Drawn once (no per-frame work), it gives
/// the dusk sky a subtle photographic tooth. Kept in the Bone family so it never
/// tints the sky, only textures it.
struct FilmGrain: View {
    /// Speck count, dense enough to read as grain, sparse enough to stay cheap.
    var count: Int = 900

    var body: some View {
        Canvas { context, size in
            for i in 0..<count {
                let x = Double(pseudo(i, 1)) * size.width
                let y = Double(pseudo(i, 2)) * size.height
                let s = 0.5 + Double(pseudo(i, 3)) * 1.0
                let rect = CGRect(x: x, y: y, width: s, height: s)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(LoreColor.bone.opacity(0.6))
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// Deterministic 0…1 hash from an index + salt (stable across renders).
    private func pseudo(_ i: Int, _ salt: Int) -> Float {
        let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return Float(x - floor(x))
    }
}

// MARK: - Page scaffold

/// The chrome shared by every step: a top row (back + progress rail + skip), a
/// scrollable content column, and a pinned bottom primary CTA, honoring the
/// HIG one-handed rule (primary actions in the bottom 60%, brand/DESIGN.md §8).
///
/// Content is Bone on the Ink sky, so text colors here are the on-Ink variants.
struct OnboardingScaffold<Content: View>: View {
    let progress: Double
    /// Shown as the pinned bottom button label. `nil` hides the CTA (e.g. steps
    /// whose action lives inline).
    let primaryTitle: String?
    /// Whether the primary CTA is tappable.
    var primaryEnabled: Bool = true
    /// Whether the primary CTA shows a spinner instead of its title.
    var primaryBusy: Bool = false
    /// Back affordance; `nil` on the first step.
    var onBack: (() -> Void)?
    /// Skip affordance; `nil` to hide (e.g. the finish step).
    var onSkip: (() -> Void)?
    let onPrimary: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            if let primaryTitle {
                primaryButton(primaryTitle)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LoreColor.bone.opacity(0.7))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
            } else {
                Spacer().frame(width: 44, height: 44)
            }

            ProgressRail(progress: progress)

            if let onSkip {
                Button("Skip", action: onSkip)
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone.opacity(0.7))
                    .frame(height: 44)
                    .padding(.horizontal, 4)
            } else {
                Spacer().frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func primaryButton(_ title: String) -> some View {
        Button(action: {
            Haptics.play(.chipTap)
            onPrimary()
        }) {
            Group {
                if primaryBusy {
                    ProgressView().tint(LoreColor.ink)
                } else {
                    Text(title).font(LoreType.button)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .background(primaryEnabled ? LoreColor.amber : LoreColor.amber.opacity(0.3), in: Capsule())
        .foregroundStyle(LoreColor.ink)
        .overlay(
            Capsule().strokeBorder(LoreColor.ink.opacity(0.12), lineWidth: 1)
        )
        .disabled(!primaryEnabled || primaryBusy)
        .animation(LoreMotion.tap, value: primaryEnabled)
    }
}

/// The slim top progress rail, a Bone track with an Amber fill that eases as
/// steps advance.
struct ProgressRail: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LoreColor.bone.opacity(0.18))
                Capsule()
                    .fill(LoreColor.amber)
                    .frame(width: max(6, geo.size.width * progress))
                    .animation(LoreMotion.drift, value: progress)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Setup progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

// MARK: - Interest chip

/// A single multi-select interest chip on the Ink sky. Selected = Amber-tinted
/// fill + Amber border; unselected = faint Bone outline. Emoji + label from
/// `InterestMap`. Meets the 44 pt touch-target minimum (brand/DESIGN.md §8).
struct InterestChip: View {
    let interest: InterestMap.InterestMeta
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(interest.emoji)
                    .font(.system(size: 16))
                Text(interest.label)
                    .font(LoreType.button)
                    .foregroundStyle(isSelected ? LoreColor.ink : LoreColor.bone)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                Capsule().fill(isSelected ? LoreColor.amber : LoreColor.bone.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? LoreColor.amber : LoreColor.bone.opacity(0.28),
                    lineWidth: 1.5
                )
            )
        }
        .buttonStyle(.pressable)
        .animation(LoreSpring.snappy, value: isSelected)
        .accessibilityLabel(interest.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Persona preset chip

/// A "here as a…" preset chip: symbol + label, with the persona tagline shown
/// under it when active. Tapping seeds interests + sets the lens.
struct PersonaChip: View {
    let preset: OnboardingContent.Preset
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? LoreColor.ink : LoreColor.amber)
                Text(preset.label)
                    .font(LoreType.button)
                    .foregroundStyle(isSelected ? LoreColor.ink : LoreColor.bone)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? LoreColor.amber : LoreColor.bone.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? LoreColor.amber : LoreColor.bone.opacity(0.22),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.pressable)
        .animation(LoreSpring.bounce(reduceMotion: reduceMotion), value: isSelected)
        .accessibilityLabel("\(preset.label). \(preset.tagline)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Flow-layout wrap (chips wrap to multiple rows)

/// A minimal flow layout so interest chips wrap naturally without a fixed grid
/// (chips are variable width). iOS 17's `Layout` protocol, no dependencies.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var x: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                totalHeight += rowHeight + spacing
                rows.append([])
                x = 0
                rowHeight = 0
            }
            rows[rows.count - 1].append(subview)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        let width = proposal.width ?? x
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
