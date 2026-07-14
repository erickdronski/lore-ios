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

/// A single-select "collection" lens above the kind chips: tap Family / Live
/// Music / Museums / Food / Free / Art / Nature / Nightlife to show only those
/// places. The active chip fills Amber (the pin-lens metaphor). Only collections
/// with real content in the current city appear, so no lens is ever empty.
struct CollectionChips: View {
    @Environment(MapFilterStore.self) private var store
    let places: [Place]

    private var collections: [PlaceCollection] { PlaceCollection.available(in: places) }

    var body: some View {
        if !collections.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(collections) { collection in
                        chip(collection)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .accessibilityLabel(Text("Show a collection of places"))
        }
    }

    private func chip(_ collection: PlaceCollection) -> some View {
        let active = store.activeCollection == collection
        return Button {
            store.setCollection(collection)
        } label: {
            HStack(spacing: 6) {
                Text(collection.emoji).font(.system(size: 13))
                Text(collection.label).font(LoreType.button)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(active ? LoreColor.amber : LoreColor.bone50))
            .overlay(Capsule().strokeBorder(active ? LoreColor.amber : LoreColor.bone300, lineWidth: active ? 1.5 : 1))
            .foregroundStyle(active ? LoreColor.ink : LoreColor.ink600)
            .contentShape(Capsule())
        }
        .buttonStyle(.pressableSilent)
        .accessibilityLabel(Text(collection.label))
        .accessibilityValue(Text(active ? "Showing only these" : "Off"))
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}
