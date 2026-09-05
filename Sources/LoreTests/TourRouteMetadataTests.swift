import Foundation
import XCTest
@testable import Lore

final class TourRouteMetadataTests: XCTestCase {
    func testExistingCatalogAndGeneratedToursKeepEstimatedWalkingDefaults() throws {
        let tour = try decode([:])
        XCTAssertEqual(tour.travelMode, .walking)
        XCTAssertEqual(tour.distanceKind, .estimated)
        XCTAssertEqual(tour.distanceLabel, "About 2.2 km")
        XCTAssertEqual(tour.durationLabel, "About 70 min")
        XCTAssertNil(tour.transportLabel)
        let generated = Tour(id: "local", slug: "one-hour", title: "One Hour", city: "la",
                             emoji: nil, blurb: nil, durationMin: 60, distanceKm: 1.5, stops: [])
        XCTAssertEqual(generated.travelMode, .walking)
        XCTAssertEqual(generated.distanceKind, .estimated)
    }

    func testMixedMinimumDistanceNeverPromisesWalkingDuration() throws {
        let tour = try decode(["travel_mode": "mixed", "distance_kind": "minimum"])
        XCTAssertEqual(tour.transportLabel, "Transport needed")
        XCTAssertEqual(tour.distanceLabel, "At least 2.2 km")
        XCTAssertNil(tour.durationLabel, "Even a legacy duration must not masquerade as a transport itinerary")
        XCTAssertEqual(tour.summaryLine, "Transport needed · At least 2.2 km")
        XCTAssertEqual(tour.routeTypeLabel, "CITY EXCURSION")
        XCTAssertFalse(tour.summaryLine.contains("minimum"))
        XCTAssertFalse(tour.summaryLine.contains("mixed"))
    }

    func testWalkingMinimumAlsoSuppressesUnverifiedTime() throws {
        let tour = try decode(["distance_kind": "minimum"])
        XCTAssertNil(tour.durationLabel)
        XCTAssertEqual(tour.distanceLabel, "At least 2.2 km")
    }

    func testMeasuredWalkingRouteKeepsApproximateDistanceAndDuration() throws {
        let tour = try decode([
            "travel_mode": "walking", "distance_kind": "walking_route",
            "route_note": "Allow time at each stop.",
            "route_source": "https://www.openstreetmap.org/copyright",
            "route_checked_at": "2026-09-05T16:00:00Z"
        ])
        XCTAssertEqual(tour.distanceLabel, "About 2.2 km")
        XCTAssertEqual(tour.durationLabel, "About 70 min")
        XCTAssertEqual(tour.routeNote, "Allow time at each stop.")
        XCTAssertEqual(tour.routeSourceURL?.host, "www.openstreetmap.org")
        XCTAssertEqual(try JSONDecoder().decode(Tour.self, from: JSONEncoder().encode(tour)), tour)
    }

    func testNullDurationAndMissingDistanceNeverInventEstimates() throws {
        let tour = try decode(["duration_min": NSNull(), "distance_km": NSNull()])
        XCTAssertNil(tour.durationLabel)
        XCTAssertNil(tour.distanceLabel)
        XCTAssertTrue(tour.summaryLine.isEmpty)
        let invalid = try decode(["duration_min": -10, "distance_km": -2])
        XCTAssertNil(invalid.durationLabel)
        XCTAssertNil(invalid.distanceLabel)
    }

    func testFutureMetadataFallsBackToConservativeTransportAndMinimumLabels() throws {
        let tour = try decode(["travel_mode": "ferry", "distance_kind": "future_kind"])
        XCTAssertEqual(tour.transportLabel, "Transport needed")
        XCTAssertEqual(tour.distanceLabel, "At least 2.2 km")
        XCTAssertNil(tour.durationLabel)
    }

    func testRouteSourceOnlyAcceptsHTTPSWithoutCredentials() throws {
        for source in ["http://example.com", "file:///private/report", "javascript:alert(1)",
                       "https://", "https://user:password@example.com", "/relative/path"] {
            XCTAssertNil(try decode(["route_source": source]).routeSourceURL, source)
        }
        XCTAssertNotNil(try decode(["route_source": "https://www.openstreetmap.org/copyright"]).routeSourceURL)
    }

    private func decode(_ fields: [String: Any]) throws -> Tour {
        var row: [String: Any] = [
            "id": "route-1", "slug": "downtown", "title": "Downtown", "city": "la",
            "distance_km": 2.2, "duration_min": 70
        ]
        row.merge(fields) { _, new in new }
        return try JSONDecoder().decode(Tour.self, from: JSONSerialization.data(withJSONObject: row))
    }
}
