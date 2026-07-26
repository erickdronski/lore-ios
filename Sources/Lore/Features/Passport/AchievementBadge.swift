import SwiftUI

/// The visual grammar of a single achievement badge, the medallion, its tier
/// finish, and (when in progress) a progress ring drawn around it. Shared by
/// the Passport wall and the unlock celebration so a badge looks identical the
/// moment it lands and forever after on the wall.
///
/// Tiers map to the brand ramp (brand/DESIGN.md §4): bronze/silver in the Ink
/// family (quiet), gold in Brass ("reserved for money and mastery"), and the
/// top "legend" tier gets the Amber beacon. The `Achievement.Tier` enum only
/// models bronze/silver/gold/platinum and falls back to bronze for anything
/// unknown, so we resolve the *display* tier from a raw string here, a DB
/// "legend" row renders as Legend without touching the shared model.

// MARK: - Tier finish

/// The presentation-layer tier: adds `legend` on top of the model's four and
/// carries the colors/label each tier renders with. Resolved from a raw tier
/// string so new tiers are additive and never a decode break.
enum BadgeTier: String, CaseIterable {
    case bronze, silver, gold, legend, platinum

    /// Resolve from any raw tier string (case-insensitive). Platinum is the
    /// icy-diamond apex above legend (world-spanning capstones); unknowns fall
    /// to bronze.
    init(raw: String?) {
        switch raw?.lowercased() {
        case "silver": self = .silver
        case "gold": self = .gold
        case "legend": self = .legend
        case "platinum": self = .platinum
        default: self = .bronze
        }
    }

    var label: String { rawValue.capitalized }

    /// The apex tier's icy tones — a cool diamond-white to set it visibly apart
    /// from legend's warm Amber.
    private static let platinumBright = Color(red: 0.93, green: 0.97, blue: 1.0)
    private static let platinumCool = Color(red: 0.70, green: 0.82, blue: 0.94)
    private static let platinumDeep = Color(red: 0.55, green: 0.66, blue: 0.82)

    /// The medallion's inner fill color when unlocked.
    var accent: Color {
        switch self {
        case .bronze: return LoreColor.brass700
        case .silver: return LoreColor.ink600
        case .gold: return LoreColor.brass
        case .legend: return LoreColor.amber
        case .platinum: return Self.platinumBright
        }
    }

    /// The ring / stroke color for the tier.
    var ring: Color {
        switch self {
        case .bronze: return LoreColor.brass700
        case .silver: return LoreColor.ink700
        case .gold: return LoreColor.brass
        case .legend: return LoreColor.amber600
        case .platinum: return Self.platinumCool
        }
    }

    /// A soft tinted disc behind the emoji on the unlocked medallion.
    var disc: Color {
        switch self {
        case .bronze: return LoreColor.brass.opacity(0.14)
        case .silver: return LoreColor.ink600.opacity(0.12)
        case .gold: return LoreColor.brass.opacity(0.20)
        case .legend: return LoreColor.amber.opacity(0.22)
        case .platinum: return Self.platinumBright.opacity(0.24)
        }
    }

    /// Gold, legend, and platinum earn the prestige glow treatment. Bronze/
    /// silver stay quiet — the finish is earned, not default.
    var isPrestige: Bool { self == .gold || self == .legend || self == .platinum }

    /// The metal color stops for this tier, brightest → base, used to build a
    /// brushed-metal angular sheen on the medallion ring.
    private var metalStops: [Color] {
        switch self {
        case .bronze: return [LoreColor.brass, LoreColor.brass700, Color(red: 0.42, green: 0.28, blue: 0.14)]
        case .silver: return [LoreColor.bone, LoreColor.ink600, LoreColor.ink700]
        case .gold:   return [LoreColor.amber, LoreColor.brass, LoreColor.brass700]
        case .legend: return [LoreColor.amber, LoreColor.amber600, LoreColor.brass]
        case .platinum: return [Self.platinumBright, Self.platinumCool, Self.platinumDeep]
        }
    }

    /// A brushed-metal angular gradient for the medallion ring. Locked badges
    /// use a flat Ink so only earned badges shine.
    func metalGradient(unlocked: Bool) -> AngularGradient {
        let base = unlocked
            ? metalStops
            : [LoreColor.ink700, LoreColor.ink800, LoreColor.ink700]
        // Repeat the sequence so the sheen sweeps twice around for a richer
        // metallic reflection, and close the loop back to the first stop.
        let sweep = base + base.reversed() + [base[0]]
        return AngularGradient(gradient: Gradient(colors: sweep), center: .center)
    }

    /// The icon tint on the Ink enamel disc, a light/warm tone that reads on dark.
    var iconColor: Color {
        switch self {
        case .bronze: return LoreColor.bone
        case .silver: return LoreColor.bone
        case .gold:   return LoreColor.amber
        case .legend: return LoreColor.amber
        case .platinum: return Self.platinumBright
        }
    }
}

// MARK: - Progress ring

/// A circular progress ring for an in-progress badge: an Ink track with the
/// tier-colored arc sweeping clockwise from 12 o'clock. Draws itself on with a
/// Reveal-timed animation when `animates` is set.
struct ProgressRing: View {
    /// 0…1 fraction complete.
    let fraction: Double
    let tier: BadgeTier
    var lineWidth: CGFloat = 4
    var animates: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var target: Double { min(1, max(0, fraction)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(LoreColor.ink700.opacity(0.35), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    tier.ring,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(checkpointColor(at: index))
                    .frame(width: lineWidth + 1, height: lineWidth + 1)
                    .offset(y: -38)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .onAppear {
            guard animates, !reduceMotion else { shown = target; return }
            withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) { shown = target }
        }
        .onChange(of: fraction) { _, _ in
            withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) { shown = target }
        }
    }

    private func checkpointColor(at index: Int) -> Color {
        let checkpoint = Double(index) / 4
        return target >= checkpoint && target > 0
            ? tier.ring
            : LoreColor.ink700.opacity(0.55)
    }
}

// MARK: - Badge tile

/// One badge on the Passport wall. Four visual states:
/// - **unlocked**: full-color medallion, tier ring, name + tier label.
/// - **inProgress**: dimmed medallion inside a progress ring, "n / target".
/// - **locked**: greyed medallion outline, name shown, no progress.
/// - **secret** (locked + `secret`): a mystery tile, "?" glyph, "Secret",
///   the name and emoji withheld until earned (brand voice: intrigue, not
///   spoilers).
struct AchievementBadge: View {
    let achievement: Achievement
    /// The user's row for this badge, if any (nil ⇒ never started).
    let progress: UserAchievement?
    /// Set true to bloom the medallion in on appear (wall entrance / unlock).
    var appeared: Bool = true
    /// Stagger delay for cascade entrances on the wall.
    var revealDelay: TimeInterval = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tier: BadgeTier { BadgeTier(raw: achievement.tier.rawValue) }

    private var isUnlocked: Bool { progress?.isUnlocked ?? false }

    /// A secret badge stays a mystery tile until it's actually earned.
    private var isMystery: Bool { achievement.secret && !isUnlocked }

    /// Fraction complete, preferring the user row, falling back to 0.
    private var fraction: Double { progress?.fraction ?? 0 }

    /// In progress = started, not done, and not a mystery.
    private var isInProgress: Bool {
        !isUnlocked && !isMystery && (progress?.progress ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 8) {
            medallion
                .revealBounce(isActive: appeared, delay: revealDelay)
            label
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 132, alignment: .top)
        .background(tileBackground)
        .overlay(alignment: .topTrailing) {
            if isUnlocked {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tier.iconColor, tier.ring)
                    .padding(7)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        isUnlocked ? tier.disc.opacity(0.52) : LoreColor.ink800.opacity(0.72),
                        LoreColor.ink900.opacity(0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isUnlocked ? tier.ring.opacity(0.32) : LoreColor.ink700.opacity(0.72),
                        lineWidth: 1
                    )
            )
    }

    // MARK: Medallion

    private var medallion: some View {
        ZStack {
            if isUnlocked {
                sealTeeth
            }

            // In-progress badges keep the tier progress ring, sized just outside
            // the metal medallion.
            if isInProgress {
                ProgressRing(fraction: fraction, tier: tier, animates: appeared)
                    .frame(width: 80, height: 80)
            }

            // The metal medallion: a brushed-metal angular sheen with a beveled
            // rim highlight, and a prestige glow for gold/legend.
            Circle()
                .fill(tier.metalGradient(unlocked: isUnlocked))
                .frame(width: 68, height: 68)
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(isUnlocked ? 0.55 : 0.12), .clear, .black.opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                )
                .shadow(
                    color: (isUnlocked && tier.isPrestige)
                        ? tier.ring.opacity(0.5)
                        : LoreElevation.tint.opacity(0.38),
                    radius: (isUnlocked && tier.isPrestige) ? 10 : 4,
                    x: 0, y: 2
                )

            // The Ink enamel center, with a little radial depth and a tier rim.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [LoreColor.ink900, LoreColor.ink800],
                        center: .init(x: 0.5, y: 0.42), startRadius: 2, endRadius: 30
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Circle().strokeBorder(tier.ring.opacity(isUnlocked ? 0.6 : 0.2), lineWidth: 1)
                )

            glyph

            // Glossy top-left sheen so the medallion catches light. Unlocked only.
            if isUnlocked {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.38), .clear],
                            center: .init(x: 0.3, y: 0.24), startRadius: 1, endRadius: 26
                        )
                    )
                    .frame(width: 66, height: 66)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        }
        // Locked/mystery medallions read quieter (desaturated + dimmed).
        .saturation(isUnlocked ? 1 : 0.25)
        .opacity(isUnlocked ? 1 : 0.82)
    }

    /// A restrained perforated edge makes earned badges read like physical
    /// passport seals without adding image assets or obscuring the tier metal.
    private var sealTeeth: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                Capsule()
                    .fill(tier.ring.opacity(tier.isPrestige ? 0.72 : 0.48))
                    .frame(width: 4, height: 10)
                    .offset(y: -38)
                    .rotationEffect(.degrees(Double(index) * 22.5))
            }
        }
        .rotationEffect(.degrees(reduceMotion ? 0 : -3))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if isMystery {
            Image(systemName: "questionmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(LoreColor.ink600)
        } else {
            Image(systemName: achievement.symbolName)
                .font(.system(size: 25, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isUnlocked ? tier.iconColor : LoreColor.bone.opacity(0.5))
                .shadow(color: LoreElevation.tint.opacity(isUnlocked ? 0.35 : 0), radius: 1, y: 1)
        }
    }

    // MARK: Label

    @ViewBuilder
    private var label: some View {
        VStack(spacing: 3) {
            Text(isMystery ? "Secret" : achievement.name)
                .font(LoreType.display(size: 14, weight: .medium))
                .foregroundStyle(isUnlocked ? LoreColor.bone : LoreColor.bone.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            sublabel
        }
    }

    @ViewBuilder
    private var sublabel: some View {
        if isMystery {
            Text("Keep exploring")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        } else if isUnlocked {
            Text(tier.label.uppercased())
                .loreLabelStyle()
                .tracking(0.6)
                .foregroundStyle(tier.isPrestige ? tier.accent : LoreColor.ink600)
        } else if isInProgress, let p = progress {
            VStack(spacing: 4) {
                Text("\(p.progress) of \(p.target)")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.76))
                Capsule()
                    .fill(LoreColor.ink700)
                    .frame(width: 42, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tier.ring)
                            .frame(width: 42 * fraction, height: 3)
                    }
            }
        } else {
            Text("Locked")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }

    // MARK: Accessibility

    private var accessibilityText: String {
        if isMystery {
            return "Secret achievement, not yet unlocked. Keep exploring."
        }
        var parts = [achievement.name, "\(tier.label) tier"]
        if isUnlocked {
            parts.append("unlocked")
        } else if isInProgress, let p = progress {
            parts.append("\(p.progress) of \(p.target)")
        } else {
            parts.append("locked")
        }
        if let d = achievement.description { parts.append(d) }
        return parts.joined(separator: ", ")
    }
}
