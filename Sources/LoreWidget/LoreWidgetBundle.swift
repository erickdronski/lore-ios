import SwiftUI
import WidgetKit

/// The widget extension's entry point (`@main`). A `WidgetBundle` groups every
/// widget + Live Activity the extension vends (docs/16-APPLE-TOOLKITS.md §7/§8):
///
/// - `TourLiveActivityWidget`, the active-tour Live Activity + Dynamic Island,
///   started/updated by the app's Tours flow.
///
/// The Live Activity `ActivityConfiguration` **must** ship inside a widget
/// extension bundle (docs/16 §8). The Nearby widget stays out of Release until
/// its App Group is provisioned; otherwise it can only show sample content.
@main
struct LoreWidgetBundle: WidgetBundle {
    var body: some Widget {
        TourLiveActivityWidget()
    }
}
