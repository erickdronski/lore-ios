import SwiftUI

/// Future-tense companion to `VisitToggle`: save a place to the traveler's
/// want-to-go list. The write is real (`saved_place`), optimistic, and honest
/// about signed-out state.
struct SavePlaceButton: View {
    enum Style {
        case icon
        case pill
    }

    let place: Place
    var style: Style = .icon
    var onNeedsSignIn: () -> Void = {}

    @Environment(SavedPlaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse = false
    @State private var errorMessage: String?

    private var saved: Bool { store.hasSaved(place.id) }
    private var inFlight: Bool { store.isInFlight(place.id) }

    var body: some View {
        Button(action: tap) {
            label
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(inFlight)
        .scaleEffect(pulse && !reduceMotion ? 1.05 : 1)
        .animation(LoreMotion.bloom, value: saved)
        .accessibilityLabel(Text(saved ? "Remove \(place.name) from saved places" : "Save \(place.name)"))
        .accessibilityValue(Text(inFlight ? "Saving" : (saved ? "Saved" : "Not saved")))
        .accessibilityAddTraits(saved ? [.isSelected, .isButton] : .isButton)
        .alert("Couldn't update saved places", isPresented: errorBinding) {
            Button("Try again") { tap() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Check your connection and try again.")
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .icon:
            ZStack {
                Circle()
                    .fill(saved ? LoreColor.amber.opacity(0.95) : LoreColor.bone200)
                Circle()
                    .strokeBorder(saved ? LoreColor.brass.opacity(0.35) : LoreColor.brass700.opacity(0.22), lineWidth: 1)
                icon
            }
            .frame(width: 44, height: 44)
        case .pill:
            HStack(spacing: 8) {
                icon
                Text(inFlight ? "Saving..." : (saved ? "Saved" : "Save"))
                    .font(LoreType.button)
            }
            .foregroundStyle(LoreColor.ink)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(saved ? LoreColor.amber.opacity(0.95) : LoreColor.bone50, in: Capsule())
            .overlay(Capsule().strokeBorder(saved ? LoreColor.brass.opacity(0.35) : LoreColor.bone300, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var icon: some View {
        if inFlight {
            ProgressView()
                .controlSize(.small)
                .tint(LoreColor.ink)
        } else {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(saved ? LoreColor.ink : LoreColor.brass700)
        }
    }

    private func tap() {
        guard !inFlight else { return }
        guard store.canSavePlaces else {
            Haptics.play(.meterGate)
            onNeedsSignIn()
            return
        }
        Task {
            if saved {
                let result = await store.remove(placeID: place.id)
                switch result {
                case .removed, .notSaved:
                    Haptics.play(.chipTap)
                case .signedOut:
                    Haptics.play(.meterGate)
                    onNeedsSignIn()
                case .failed(let message):
                    Haptics.play(.meterGate)
                    errorMessage = message
                }
            } else {
                let result = await store.save(placeID: place.id)
                switch result {
                case .saved, .alreadySaved:
                    Haptics.play(.chipTap)
                    firePulse()
                case .signedOut:
                    Haptics.play(.meterGate)
                    onNeedsSignIn()
                case .failed(let message):
                    Haptics.play(.meterGate)
                    errorMessage = message
                }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func firePulse() {
        guard !reduceMotion else { return }
        withAnimation(.interpolatingSpring(stiffness: 360, damping: 22)) {
            pulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(LoreMotion.tap) { pulse = false }
        }
    }
}
