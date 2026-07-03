import ActivityKit
import CoreLocation
import Foundation
import Observation

/// Starts, updates, and ends the **active-tour Live Activity** (docs/16 §8) from
/// the Tours flow. The rendering lives in the widget extension
/// (`TourLiveActivityWidget`); this is the app-side driver.
///
/// Update model (docs/16 §8): for a self-guided walking tour we drive updates
/// **on-device** — every time the walker advances a stop (or Core Location
/// reports a new distance to the next stop) the app calls `updateProgress`. No
/// push token, no server. `Activity.update` mutates the `ContentState` and the
/// Lock-Screen / Dynamic Island re-render.
///
/// Lifecycle: `@Observable @MainActor`, held by the tour detail screen (or a
/// tour session store) for the life of the walk. `start` is a no-op when the
/// user has Live Activities disabled (`ActivityAuthorizationInfo`), so the Tours
/// UI stays functional either way.
@Observable
@MainActor
final class TourLiveActivityController {
    /// The running activity, if one is live. `nil` before `start` / after `end`.
    private var activity: Activity<TourActivityAttributes>?

    /// True when a tour Live Activity is currently running.
    var isRunning: Bool { activity != nil }

    /// Whether the system allows Live Activities right now (user setting).
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Begin a Live Activity for a tour. Safe to call when already running (it
    /// ends the prior one first) or when Live Activities are disabled (no-op).
    ///
    /// - Parameters:
    ///   - tour: the tour identity (title, emoji, stop count).
    ///   - initialStopIndex: 1-based index of the starting stop.
    ///   - currentStopName / nextStopName / distanceToNextMeters: the first state.
    func start(
        tour: Tour,
        initialStopIndex: Int,
        currentStopName: String,
        nextStopName: String?,
        distanceToNextMeters: Double?
    ) {
        guard areActivitiesEnabled else { return }
        // One tour Live Activity at a time.
        if activity != nil {
            end()
        }

        let attributes = TourActivityAttributes(
            tourID: tour.id,
            tourTitle: tour.title,
            emoji: tour.displayEmoji,
            totalStops: max(tour.stops.count, 1)
        )
        let state = TourActivityAttributes.TourProgress(
            currentStopIndex: initialStopIndex,
            currentStopName: currentStopName,
            nextStopName: nextStopName,
            distanceToNextMeters: distanceToNextMeters
        )

        do {
            // iOS 16.2+ uses `ActivityContent`; min target is 17, so this is safe.
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil // on-device driven — no push token (docs/16 §8)
            )
        } catch {
            // Starting can fail (budget, disabled mid-flight). Non-fatal — the
            // tour stepper works without the Live Activity.
            activity = nil
        }
    }

    /// Push a new progress state as the walker advances. No-op if not running.
    ///
    /// TODO(P1): wire the live distance from Core Location — a `CLLocationManager`
    /// in the tour session recomputes `distanceToNextMeters` on each fix and
    /// calls this (docs/16 §8: "drive updates on-device from Core Location").
    func updateProgress(
        currentStopIndex: Int,
        currentStopName: String,
        nextStopName: String?,
        distanceToNextMeters: Double?
    ) {
        guard let activity else { return }
        let state = TourActivityAttributes.TourProgress(
            currentStopIndex: currentStopIndex,
            currentStopName: currentStopName,
            nextStopName: nextStopName,
            distanceToNextMeters: distanceToNextMeters
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// End the Live Activity (tour finished or the user left the walk). No-op if
    /// nothing is running.
    func end() {
        guard let activity else { return }
        let final = activity
        self.activity = nil
        Task {
            await final.end(nil, dismissalPolicy: .immediate)
        }
    }
}
