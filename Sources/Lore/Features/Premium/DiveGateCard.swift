import SwiftUI
import UIKit

/// The gate that lands on a free user's **4th deep dive of the day**
/// (brand/ELEVATION.md §7: "the 4th dive card flips to the gate with
/// spring.settle, warning haptic once, docent copy"). It stands in for the
/// dossier body when `DiveMeter.canOpenDive` returns false.
///
/// It is deliberately *not* a scolding wall. The tone: you've read three
/// today, that's the free daily gift, here's the door to unlimited. The place
/// name still shows above it (the caller keeps the dossier chrome), so the
/// wonder isn't yanked away, only the fourth read is deferred.
struct DiveGateCard: View {
    /// The place the user was about to dive into, named so the copy stays
    /// specific ("More on the Rookery is a tap away").
    let placeName: String
    /// Present the paywall.
    let onUnlock: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Brass medallion + "today's dives" framing.
            HStack(spacing: 12) {
                ZStack {
                    BrassSheenSurface(shape: Circle(), sweepOnAppear: true)
                        .frame(width: 48, height: 48)
                    Image(systemName: "book.pages")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("You've read three today")
                        .font(LoreType.displayM)
                        .foregroundStyle(LoreColor.bone)
                    Text("The free daily deep dives are on the house.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
            }

            Text("More on \(placeName) is one tap away. Lore+ opens every dossier, "
                 + "as many as the day holds, plus curated walking tours and audio.")
                .font(LoreType.body)
                .foregroundStyle(LoreColor.bone)
                .fixedSize(horizontal: false, vertical: true)

            UnlockButton(
                title: "Keep reading with Lore+",
                subtitle: "7 days free, then $5.99/mo",
                action: onUnlock
            )

            Text("Your free dives refresh tomorrow.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(LoreColor.brass.opacity(0.35), lineWidth: 1)
        )
        // spring.settle flip-in (brand/ELEVATION.md §7), no bounce on a gate.
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97)
        .animation(
            UIAccessibility.isReduceMotionEnabled
                ? .easeInOut(duration: LoreMotion.reducedDuration)
                : .interpolatingSpring(stiffness: 260, damping: 30),
            value: appeared
        )
        .onAppear {
            appeared = true
            // One warning haptic, once (brand/ELEVATION.md §4).
            Haptics.play(.meterGate)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "You've read your three free deep dives today. "
            + "More on \(placeName) is available with Lore plus. "
            + "Unlock for 7 days free, then $5.99 a month."
        )
    }
}

/// A tiny caption row showing the free user's remaining dives, for the top of
/// a dossier ("2 free dives left today"). Maps to the `Meter` component
/// (brand/DESIGN.md §7): shown n-of-3 for free users, hidden entirely for
/// Lore+. Never shown at the very first dive as a countdown pressure device —
/// callers pass `remaining` and hide it when the user still has the full
/// allowance if they prefer a quieter first read.
struct DiveMeterBadge: View {
    /// Dives remaining today (0…allowance).
    let remaining: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "book.closed")
                .font(.system(size: 11, weight: .semibold))
            Text(remaining == 1 ? "1 free dive left today"
                                : "\(remaining) free dives left today")
                .font(LoreType.caption)
        }
        .foregroundStyle(LoreColor.bone.opacity(0.72))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(LoreColor.ink800, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remaining) free deep dives left today")
    }
}
