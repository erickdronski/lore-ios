import SwiftUI
import WidgetKit

/// The widget extension's entry point (`@main`). A `WidgetBundle` groups every
/// widget + Live Activity the extension vends (docs/16-APPLE-TOOLKITS.md §7/§8):
///
/// - `NearbyLoreWidget`, the home-screen "place near you / daily lore" card
///   (small + medium families), fed by the App-Group snapshot the app writes.
/// - `TourLiveActivityWidget`, the active-tour Live Activity + Dynamic Island,
///   started/updated by the app's Tours flow.
///
/// The Live Activity `ActivityConfiguration` **must** ship inside a widget
/// extension bundle (docs/16 §8), hence both live here, in one target.
@main
struct LoreWidgetBundle: WidgetBundle {
    var body: some Widget {
        NearbyLoreWidget()
        TourLiveActivityWidget()
    }
}
