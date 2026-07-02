import SwiftUI

/// The "I've been here" visit toggle (task requirement 1). Drop it into a place
/// card, dossier header, or a shelf row: it reads the `VisitStore` for its state
/// and, on tap for an unvisited place, logs the visit (`POST /visit` →
/// `recompute_achievements`) and lets the store surface any unlocks to the
/// Passport celebration.
///
/// Three visual states, all inside the brand ramp:
/// - **unvisited** → Bone-outline pill, "I've been here", a hollow marker.
/// - **in flight** → a quiet progress tick while the write lands.
/// - **visited** → the verified finish: Amber fill, filled seal, "Been here",
///   the single celebratory pulse doctrine reserves for a claimed moment
///   (brand/DESIGN.md §6 "Verified moment"). Fires `Haptics.play(.badgeEarned)`.
///
/// Signed-out is honest: the pill still shows and, on tap, calls `onNeedsSignIn`
/// (a warning haptic + the integrator's sign-in nudge) rather than silently
/// failing — reading/marking intent is never a dead end.
struct VisitToggle: View {
    let place: Place
    /// How this visit should be attributed if logged from here.
    var source: Visit.Source = .map
    /// Called when a tap can't proceed because there's no signed-in user.
    var onNeedsSignIn: () -> Void = {}

    @Environment(VisitStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse = false

    private var visited: Bool { store.hasVisited(place.id) }
    private var inFlight: Bool { store.isInFlight(place.id) }

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                marker
                Text(label)
                    .font(LoreType.button)
            }
            .padding(.horizontal, 16)
            .frame(height: 44) // HIG min target (brand/DESIGN.md §8)
            .frame(minWidth: 44)
            .background(background)
            .overlay(border)
            .foregroundStyle(visited ? LoreColor.ink : LoreColor.ink)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(inFlight)
        .scaleEffect(pulse && !reduceMotion ? 1.06 : 1.0)
        .animation(LoreMotion.bloom, value: visited)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(visited ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(Text(visited ? "" : "Marks this place as visited and earns badges."))
    }

    // MARK: Pieces

    @ViewBuilder
    private var marker: some View {
        if inFlight {
            ProgressView()
                .controlSize(.small)
                .tint(LoreColor.ink)
        } else {
            Image(systemName: visited ? "checkmark.seal.fill" : "mappin.and.ellipse")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(visited ? LoreColor.ink : LoreColor.brass700)
        }
    }

    private var label: String {
        if inFlight { return "Logging…" }
        return visited ? "Been here" : "I've been here"
    }

    @ViewBuilder
    private var background: some View {
        if visited {
            Capsule().fill(LoreColor.amber)
        } else {
            Capsule().fill(LoreColor.bone50)
        }
    }

    @ViewBuilder
    private var border: some View {
        if visited {
            // The expanding Brass ring of the verified moment, once.
            Capsule()
                .strokeBorder(LoreColor.brass, lineWidth: pulse && !reduceMotion ? 2 : 0)
                .opacity(pulse && !reduceMotion ? 0 : 1)
        } else {
            Capsule().strokeBorder(LoreColor.bone300, lineWidth: 1)
        }
    }

    private var accessibilityLabel: String {
        if visited { return "Visited \(place.name)" }
        return "Mark \(place.name) as visited"
    }

    // MARK: Action

    private func tap() {
        guard !visited, !inFlight else { return }
        guard store.canLogVisits else {
            Haptics.play(.meterGate) // one warning tap — a gentle "sign in" cue
            onNeedsSignIn()
            return
        }
        Task {
            let result = await store.logVisit(placeID: place.id, source: source)
            switch result {
            case .logged:
                // The verified moment: success haptic + one pulse (§6).
                Haptics.play(.badgeEarned)
                firePulse()
            case .alreadyVisited:
                break
            case .signedOut:
                Haptics.play(.meterGate)
                onNeedsSignIn()
            case .failed:
                break // store.lastError carries the message if the caller shows it
            }
        }
    }

    /// The single 1.2× celebratory pulse + Brass ring, then settle (§6).
    private func firePulse() {
        guard !reduceMotion else { return }
        withAnimation(.interpolatingSpring(stiffness: 380, damping: 22)) {
            pulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(LoreMotion.tap) { pulse = false }
        }
    }
}
