import ActivityKit
import SwiftUI
import WidgetKit

/// The **active-tour Live Activity** (docs/16-APPLE-TOOLKITS.md §8): a walking
/// tour pinned to the Lock Screen and Dynamic Island, *Stop 3 of 7 · Wrigley
/// Building · 200 m ahead*.
///
/// Renders `TourActivityAttributes` (shared with the app, which starts/updates
/// the activity). Three presentations: the Lock-Screen/banner view, the expanded
/// Dynamic Island, and the compact + minimal Island. Updates are driven
/// on-device from Core Location by the app (docs/16 §8, no push token for a
/// self-guided walk).
struct TourLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TourActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            TourLockScreenView(context: context)
                .activityBackgroundTint(LoreBrand.ink.opacity(0.92))
                .activitySystemActionForegroundColor(LoreBrand.amber)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded, the rich, pulled-open state.
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.emoji)
                        .font(.system(size: 28))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.stopLabel(of: context.attributes.totalStops))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LoreBrand.brass300)
                        if !context.state.distanceLine.isEmpty {
                            Text(context.state.distanceLine)
                                .font(.system(size: 12))
                                .foregroundStyle(LoreBrand.bone.opacity(0.85))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.currentStopName)
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(LoreBrand.bone)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let next = context.state.nextStopName {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LoreBrand.amber)
                            Text("Next: \(next)")
                                .font(.system(size: 13))
                                .foregroundStyle(LoreBrand.bone.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                Text(context.attributes.emoji).font(.system(size: 15))
            } compactTrailing: {
                // "3/7", where we are along the walk, at a glance.
                Text("\(context.state.currentStopIndex)/\(context.attributes.totalStops)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LoreBrand.amber)
            } minimal: {
                Text(context.attributes.emoji).font(.system(size: 14))
            }
            .widgetURL(URL(string: "lore://tour/\(context.attributes.tourID)"))
            .keylineTint(LoreBrand.amber)
        }
    }
}

/// The Lock-Screen / banner presentation of the tour Live Activity.
private struct TourLockScreenView: View {
    let context: ActivityViewContext<TourActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Emoji pin in the Amber compound style.
            ZStack {
                Circle()
                    .fill(LoreBrand.amber)
                    .overlay(Circle().strokeBorder(LoreBrand.ink, lineWidth: 1.5))
                Text(context.attributes.emoji).font(.system(size: 20))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.stopLabel(of: context.attributes.totalStops))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(LoreBrand.brass300)
                Text(context.state.currentStopName)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(LoreBrand.bone)
                    .lineLimit(1)
                if let next = context.state.nextStopName {
                    Text("Next: \(next)")
                        .font(.system(size: 12))
                        .foregroundStyle(LoreBrand.ink600)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !context.state.distanceLine.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LoreBrand.amber)
                    Text(context.state.distanceLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LoreBrand.bone.opacity(0.85))
                }
            }
        }
        .padding(14)
    }
}
