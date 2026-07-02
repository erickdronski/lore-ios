import SwiftUI

/// The reusable premium gate. Wrap any Lore+ surface (a tour route, an audio
/// player, an offline-pack download) and `PlusGate` shows the real content to
/// members and a tasteful locked state to everyone else — with an
/// `UnlockButton` that presents the paywall.
///
/// Doctrine (docs/00 §7 + brand/ELEVATION.md §7): the gate never modal-slams.
/// It's the *content itself* that resolves to a lock, with docent copy naming
/// what's behind it — "Curated walks, turn by turn" — not a generic wall. One
/// warning haptic fires the first time a locked gate appears, never repeated.
///
/// Two presentation styles:
/// - `.inline` (default): a locked panel that stands in for the content
///   (blurred teaser + reason + unlock CTA). Use where the gated thing is the
///   whole screen region (audio player, offline pack).
/// - `.overlay`: renders the content dimmed underneath with a lock veil and
///   CTA on top — use when a *taste* of the content should still be visible
///   (a tour's map with the route locked).
///
/// Usage:
/// ```swift
/// PlusGate(
///     isPlus: entitlements.isPlus,
///     feature: .audio,
///     onUnlock: { showPaywall = true }
/// ) {
///     AudioNarrationPlayer(dive: dive)   // members see the real player
/// }
/// ```
struct PlusGate<Content: View>: View {
    /// `EntitlementStore.isPlus` at the call site.
    let isPlus: Bool
    /// Which Lore+ surface this is — drives the icon + docent copy.
    let feature: PlusFeature
    /// Present the paywall.
    let onUnlock: () -> Void
    /// How to render the locked state.
    var style: Style = .inline
    /// The real, members-only content.
    @ViewBuilder let content: () -> Content

    enum Style { case inline, overlay }

    var body: some View {
        if isPlus {
            content()
        } else {
            switch style {
            case .inline:
                LockedPanel(feature: feature, onUnlock: onUnlock)
            case .overlay:
                content()
                    .disabled(true)
                    .overlay {
                        LockedVeil(feature: feature, onUnlock: onUnlock)
                    }
                    .accessibilityElement(children: .contain)
            }
        }
    }
}

/// The catalog of gate-able Lore+ surfaces, each carrying its own icon and
/// docent copy so every gate in the app reads consistently (docs/00 §7 lists
/// the four: tours, offline, audio, early cities — plus the dive-meter gate,
/// which has its own richer surface in `DiveGateCard`).
enum PlusFeature {
    case tours
    case audio
    case offline
    case earlyCities
    /// Generic fallback for a one-off premium affordance.
    case general

    var icon: String {
        switch self {
        case .tours: return "figure.walk"
        case .audio: return "headphones"
        case .offline: return "arrow.down.circle"
        case .earlyCities: return "sparkles"
        case .general: return "lock.fill"
        }
    }

    /// The headline on the locked panel — a noun, not a pitch.
    var title: String {
        switch self {
        case .tours: return "Curated walks"
        case .audio: return "Audio narration"
        case .offline: return "Offline city packs"
        case .earlyCities: return "Early-access cities"
        case .general: return "A Lore+ feature"
        }
    }

    /// The line under it — specific, warm, docent voice (brand/ELEVATION.md §1).
    /// No em dashes anywhere in displayed copy (§1 hard rule).
    var blurb: String {
        switch self {
        case .tours:
            return "Turn-by-turn walks a local curator built, story waiting at every stop."
        case .audio:
            return "Let the docent read. Pocket your phone and just listen as you walk."
        case .offline:
            return "Download a city before you land. Every story, no signal needed."
        case .earlyCities:
            return "Walk the newest cities the week they open, before anyone else."
        case .general:
            return "This one's part of Lore+."
        }
    }

    /// Short CTA subtitle.
    var unlockSubtitle: String {
        "7 days free, then $4.99/mo"
    }
}

/// The inline locked panel: brass-ringed icon, feature title + blurb, and the
/// unlock CTA. Plays one `.meterGate` warning haptic on first appear.
private struct LockedPanel: View {
    let feature: PlusFeature
    let onUnlock: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                BrassSheenSurface(shape: Circle(), sweepOnAppear: true)
                    .frame(width: 56, height: 56)
                Image(systemName: feature.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LoreColor.ink)
            }

            VStack(spacing: 6) {
                Text(feature.title)
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.ink)
                    .multilineTextAlignment(.center)
                Text(feature.blurb)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink600)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            UnlockButton(subtitle: feature.unlockSubtitle, action: onUnlock)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(LoreColor.brass.opacity(0.35), lineWidth: 1)
        )
        .revealBounce(isActive: appeared, fromScale: 0.94)
        .onAppear {
            appeared = true
            // Doctrine: one warning haptic on the gate, never repeated
            // (brand/ELEVATION.md §4). The panel owns that once-ness.
            Haptics.play(.meterGate)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title). \(feature.blurb) Unlock with Lore plus.")
    }
}

/// The overlay veil: an ink scrim + centered lock + compact CTA, laid over a
/// dimmed taste of the real content.
private struct LockedVeil: View {
    let feature: PlusFeature
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            LoreColor.ink.opacity(0.55)
            VStack(spacing: 12) {
                LockChip(label: feature.title, showsLock: true)
                Text(feature.blurb)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    Haptics.play(.chipTap)
                    onUnlock()
                } label: {
                    Text("Unlock with Lore+")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(BrassSheenSurface(shape: Capsule(), sweepOnAppear: false))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title), locked. Unlock with Lore plus.")
    }
}
