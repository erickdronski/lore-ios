import ActivityKit
import Foundation

/// The Live Activity contract for an **active walking tour** (docs/16 §8): a
/// "guide in your pocket" surface pinned to the Lock Screen and Dynamic Island
///, *Stop 3 of 7 · Wrigley Building · 200 m ahead*.
///
/// `ActivityAttributes` must be a type **shared** between the app (which
/// starts/updates the activity) and the widget extension (which renders it), so
/// it lives in `Sources/Shared`. The static `attributes` are the tour's fixed
/// identity; `ContentState` is the live, updatable payload the app mutates as
/// the walker progresses.
///
/// **Size discipline (docs/16 §8):** keep the combined attributes + state well
/// under ActivityKit's 4 KB limit. These are short strings and a couple of ints
///, comfortably within budget.
public struct TourActivityAttributes: ActivityAttributes {
    public typealias ContentState = TourProgress

    /// The tour's stable identity, set once at `Activity.request`, never
    /// changes for the life of the activity.
    public let tourID: String
    public let tourTitle: String
    /// Tour emoji (mirrors `Tour.displayEmoji`).
    public let emoji: String
    /// Total number of stops (denominator for "Stop 3 of 7").
    public let totalStops: Int

    public init(tourID: String, tourTitle: String, emoji: String, totalStops: Int) {
        self.tourID = tourID
        self.tourTitle = tourTitle
        self.emoji = emoji
        self.totalStops = totalStops
    }

    /// The live, updatable state, driven on-device from Core Location as the
    /// walker advances (docs/16 §8: no server, no push token for a self-guided
    /// walking tour; `Activity.update` on progress).
    public struct TourProgress: Codable, Hashable {
        /// 1-based index of the current stop.
        public var currentStopIndex: Int
        /// Name of the current stop.
        public var currentStopName: String
        /// Name of the next stop, if any (nil on the final stop).
        public var nextStopName: String?
        /// Straight-line distance to the next stop, in meters (nil if unknown /
        /// final stop). Rendered as "200 m ahead" / "1.2 km ahead".
        public var distanceToNextMeters: Double?

        public init(
            currentStopIndex: Int,
            currentStopName: String,
            nextStopName: String?,
            distanceToNextMeters: Double?
        ) {
            self.currentStopIndex = currentStopIndex
            self.currentStopName = currentStopName
            self.nextStopName = nextStopName
            self.distanceToNextMeters = distanceToNextMeters
        }

        /// "Stop 3", 1-based label for the current stop.
        public func stopLabel(of total: Int) -> String {
            "Stop \(currentStopIndex) of \(total)"
        }

        /// A human distance string: "200 m ahead" / "1.2 km ahead" / "".
        public var distanceLine: String {
            guard let meters = distanceToNextMeters else { return "" }
            if meters < 1000 {
                return "\(Int(meters.rounded())) m ahead"
            }
            return String(format: "%.1f km ahead", meters / 1000)
        }
    }
}
