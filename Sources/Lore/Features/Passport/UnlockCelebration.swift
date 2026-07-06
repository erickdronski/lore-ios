import SwiftUI
import UIKit

/// The unlock celebration, the reward moment when `recompute_achievements`
/// returns newly-earned badges. A dimmed Ink scrim, a confetti-ish burst in the
/// brand ramp (Amber/Brass/Bone, never rainbow slop, brand/ELEVATION.md §1),
/// and the freshly-earned medallion blooming in with `spring.bounce` and a
/// `Haptics.play(.badgeEarned)` success tap.
///
/// Multiple unlocks queue: the overlay steps through them one at a time (tap to
/// advance, or an 8-count "Continue"), so a session that unlocks three badges
/// is three beats, not a pile. Honors Reduce Motion, the confetti falls back
/// to a still Amber ring and the bounce to a crossfade.
struct UnlockCelebration: View {
    /// The queue of newly-unlocked achievements to celebrate, in order.
    let unlocked: [Achievement]
    /// Called when the user dismisses the last badge (clears the queue).
    let onDismiss: () -> Void

    @State private var index = 0
    @State private var bloom = false
    @State private var burst = false

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    private var current: Achievement? {
        unlocked.indices.contains(index) ? unlocked[index] : nil
    }

    private var tier: BadgeTier {
        BadgeTier(raw: current?.tier.rawValue)
    }

    var body: some View {
        ZStack {
            // Scrim, tap anywhere to advance.
            LoreColor.ink950.opacity(0.86)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            if !reduceMotion {
                ConfettiBurst(active: burst, tier: tier)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if let achievement = current {
                card(for: achievement)
                    .id(index) // re-run the bloom per badge in the queue
            }
        }
        .onAppear { beat() }
        .transition(.opacity)
    }

    // MARK: Card

    private func card(for achievement: Achievement) -> some View {
        VStack(spacing: 20) {
            Text("Achievement unlocked")
                .loreLabelStyle()
                .tracking(1.2)
                .foregroundStyle(tier.isPrestige ? tier.accent : LoreColor.brass300)

            // The medallion, blooming in. A synthetic "unlocked" row so the
            // shared badge renders in its earned finish.
            AchievementBadge(
                achievement: achievement,
                progress: unlockedRow(for: achievement),
                appeared: bloom
            )
            .scaleEffect(reduceMotion ? 1 : 1.15)

            VStack(spacing: 6) {
                Text(achievement.name)
                    .font(LoreType.displayL)
                    .foregroundStyle(LoreColor.bone)
                    .multilineTextAlignment(.center)

                if let description = achievement.description {
                    Text(description)
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.bone.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
            }

            if achievement.points > 0 {
                Label("+\(achievement.points) Insight", systemImage: "sparkles")
                    .font(LoreType.display(size: 16, weight: .semibold))
                    .foregroundStyle(LoreColor.amber)
            }

            continueButton
        }
        .padding(28)
        .frame(maxWidth: 340)
        .opacity(bloom ? 1 : 0)
    }

    private var continueButton: some View {
        Button(action: advance) {
            Text(isLast ? "Continue" : "Next")
                .font(LoreType.button)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .background(LoreColor.bone, in: Capsule())
        .foregroundStyle(LoreColor.ink)
        .overlay(alignment: .trailing) {
            if unlocked.count > 1 {
                Text("\(index + 1) / \(unlocked.count)")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
            }
        }
        .padding(.top, 4)
    }

    private var isLast: Bool { index >= unlocked.count - 1 }

    // MARK: Beats

    /// Play one badge: haptic, bloom, and confetti burst.
    private func beat() {
        Haptics.play(.badgeEarned)
        bloom = false
        burst = false
        // Bloom the medallion + copy in on `spring.bounce`, the reward arrival
        // (LUXURY-MOTION §6: unlock uses .bounce + Haptics.success).
        withAnimation(LoreSpring.bounce(reduceMotion: reduceMotion)) {
            bloom = true
        }
        // Kick the confetti a hair later so it reads as *from* the badge.
        if !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                burst = true
            }
        }
    }

    /// Advance to the next badge, or dismiss when the queue is exhausted.
    private func advance() {
        if isLast {
            onDismiss()
        } else {
            withAnimation(LoreMotion.tap) { index += 1 }
            // Next beat after the swap settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { beat() }
        }
    }

    /// A synthetic, fully-unlocked `UserAchievement` so the shared badge view
    /// renders the earned finish for this celebration.
    private func unlockedRow(for achievement: Achievement) -> UserAchievement {
        let target = achievement.criteriaTarget ?? 1
        return UserAchievement(
            userID: "",
            achievementSlug: achievement.slug,
            progress: target,
            target: target,
            unlockedAt: "now"
        )
    }
}

// MARK: - Confetti

/// A one-shot confetti burst kept inside the brand ramp, Amber, Brass, Bone
/// flecks that fall and fade. Deterministic-per-appearance, GPU-cheap (a fixed
/// set of `TimelineView`-free spring-animated rects), and silent under Reduce
/// Motion (the parent simply doesn't mount it).
struct ConfettiBurst: View {
    /// Flip true to launch. Launching re-seeds the flecks.
    let active: Bool
    let tier: BadgeTier

    private let count = 46

    /// Palette, the legend/gold tiers lean Amber; quieter tiers lean Brass.
    private var palette: [Color] {
        tier.isPrestige
            ? [LoreColor.amber, LoreColor.brass300, LoreColor.bone, LoreColor.amber600]
            : [LoreColor.brass300, LoreColor.brass700, LoreColor.bone, LoreColor.brass]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    Fleck(
                        index: i,
                        active: active,
                        color: palette[i % palette.count],
                        bounds: geo.size
                    )
                }
            }
        }
    }
}

/// A single confetti fleck: starts near the top-center, and on `active` springs
/// out to a seeded landing point while spinning and fading. Deterministic from
/// its index so no per-frame randomness is needed.
private struct Fleck: View {
    let index: Int
    let active: Bool
    let color: Color
    let bounds: CGSize

    // Seeded pseudo-randoms in 0…1 from the index (stable across renders).
    private func seed(_ salt: Int) -> Double {
        let x = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - floor(x)
    }

    private var size: CGFloat { 5 + CGFloat(seed(1)) * 6 }
    private var spread: CGFloat { CGFloat(seed(2) - 0.5) * bounds.width * 1.1 }
    private var fall: CGFloat { bounds.height * (0.55 + CGFloat(seed(3)) * 0.4) }
    private var spin: Double { (seed(4) - 0.5) * 720 }
    private var delay: Double { seed(5) * 0.18 }
    private var duration: Double { 1.3 + seed(6) * 0.7 }

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: size, height: size * 0.5)
            .position(
                x: bounds.width / 2 + (active ? spread : 0),
                y: bounds.height * 0.32 + (active ? fall : 0)
            )
            .rotationEffect(.degrees(active ? spin : 0))
            .opacity(active ? 0 : 1)
            .animation(
                .easeOut(duration: duration).delay(delay),
                value: active
            )
    }
}
