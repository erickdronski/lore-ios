import Foundation
import WidgetKit

/// Bridges the app's near-me ranking to the **home-screen widget** (docs/16 §7).
///
/// The widget can't hit the network, so the app writes a small
/// `LoreWidgetSnapshot` to the shared App Group after each near-me refresh, then
/// asks WidgetKit to reload. `LoreWidgetSnapshot` + `LoreWidgetStore` are the
/// shared types in `Sources/Shared`, compiled into both targets.
///
/// **App Group is portal-gated** (docs/16 §7 / project.yml): until
/// `group.app.lore.lore` exists in the Developer portal and is on both targets'
/// entitlements, `LoreWidgetStore.sharedDefaults` is nil and every write is a
/// silent no-op — the widget just shows its brand sample. Nothing here crashes
/// on the un-provisioned path.
enum WidgetPublisher {
    /// Publish the current nearest places for the widget's "around you" surface.
    ///
    /// Call after the near-me shelf re-ranks (it already has the `RankedPlace`
    /// list). Debounced by content-equality so we don't thrash the timeline: a
    /// reload only fires when the projected snapshot actually changed.
    @MainActor
    static func publishNearby(_ ranked: [RankedPlace], city: String) {
        let places = ranked.prefix(3).map { r in
            LoreWidgetSnapshot.Place(
                id: r.place.id,
                name: r.place.name,
                emoji: r.place.displayEmoji,
                hook: r.place.layer1?.hook,
                year: r.place.layer1?.yearBuilt
            )
        }
        let snapshot = LoreWidgetSnapshot(
            updatedAt: Date(),
            city: city,
            places: Array(places)
        )
        // Skip if nothing meaningful changed (ignore the timestamp).
        if let existing = LoreWidgetStore.read(),
           existing.city == snapshot.city,
           existing.places == snapshot.places {
            return
        }
        LoreWidgetStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: NearbyLoreWidgetKind.kind)
    }
}

/// The widget kind string, mirrored here so the app can reload it without
/// importing the extension target. Must equal `NearbyLoreWidget.kind`.
enum NearbyLoreWidgetKind {
    static let kind = "NearbyLoreWidget"
}
