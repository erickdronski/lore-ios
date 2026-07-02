import SwiftUI

/// The map filter chips (task requirement 3): a horizontally-scrolling row of
/// kind-category toggles the user taps to hard-filter the map. Each chip maps
/// 1:1 onto a `place.kind`; toggling it off drops that kind from the map and
/// persists to `user_prefs.hidden_kinds` via `MapFilterStore`.
///
/// Additive surface: the integrator overlays this on the map (bottom strip,
/// above the near-you shelf) without editing `MapScreen`. Chips are `on` by
/// default (Amber-forward, the "in view" state); toggled `off` they go quiet
/// (Bone outline, dimmed) so the row reads as "what's showing." A leading
/// "All" chip appears once anything is filtered, to restore the full map in one
/// tap (§3: show everything is always one tap).
///
/// Brand: chips are the app's words, so Ink/Brass/Bone, never Amber-as-chrome —
/// except the *active pin lens* metaphor, where an on-chip's dot borrows Amber
/// to echo the pins it's showing. Tap = `.chipTap` light haptic; toggles settle
/// with `reveal.tap`.
struct MapFilterChips: View {
    @Environment(MapFilterStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if store.hasActiveFilter {
                    allChip
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                ForEach(store.categories) { category in
                    chip(for: category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .animation(LoreMotion.tap, value: store.hasActiveFilter)
        }
        .accessibilityLabel(Text("Filter the map by kind of place"))
    }

    // MARK: Chips

    private func chip(for category: KindCategory) -> some View {
        let on = store.isOn(category)
        return Button {
            store.toggle(category)
        } label: {
            HStack(spacing: 6) {
                Text(category.emoji)
                    .font(.system(size: 13))
                Text(category.label)
                    .font(LoreType.button)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(chipBackground(on: on))
            .overlay(chipBorder(on: on))
            .foregroundStyle(on ? LoreColor.ink : LoreColor.ink600)
            .opacity(on ? 1 : 0.7)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressableSilent)
        .accessibilityLabel(Text(category.label))
        .accessibilityValue(Text(on ? "Showing" : "Hidden"))
        .accessibilityHint(Text(on ? "Tap to hide from the map." : "Tap to show on the map."))
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    private var allChip: some View {
        Button {
            store.clear()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("All")
                    .font(LoreType.button)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(LoreColor.ink))
            .foregroundStyle(LoreColor.bone)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressableSilent)
        .accessibilityLabel(Text("Show all places"))
        .accessibilityHint(Text("Clears every filter and restores the full map."))
    }

    @ViewBuilder
    private func chipBackground(on: Bool) -> some View {
        if on {
            Capsule().fill(LoreColor.bone50)
        } else {
            Capsule().fill(LoreColor.bone200)
        }
    }

    @ViewBuilder
    private func chipBorder(on: Bool) -> some View {
        Capsule()
            .strokeBorder(
                on ? LoreColor.brass700.opacity(0.55) : LoreColor.bone300,
                lineWidth: on ? 1.5 : 1
            )
    }
}
