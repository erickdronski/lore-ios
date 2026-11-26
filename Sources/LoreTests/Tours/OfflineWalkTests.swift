import XCTest
@testable import Lore

final class OfflineWalkTests: XCTestCase {
    private func route(premium: Bool = false, mode: Tour.TravelMode = .walking) -> Tour {
        Tour(id: "walk-id", slug: "lake-walk", title: "Lake Walk", city: "chicago",
             emoji: nil, blurb: nil, durationMin: nil, distanceKm: nil, isPremium: premium,
             stops: [TourStop(tourID: "walk-id", placeID: "b", seq: 2, note: "See the second stop."),
                     TourStop(tourID: "walk-id", placeID: "a", seq: 1, note: "See the first stop.")],
             travelMode: mode)
    }

    private let places = ["a", "b"].reduce(into: [String: Place]()) { result, id in
        result[id] = Place(id: id, slug: id, name: id, kind: "park", lat: 41, lng: -87, city: "chicago")
    }

    func testOnlyCompleteFreeWalksAreOfferedAndUseCuratedOrder() throws {
        let walk = try XCTUnwrap(OfflineWalk(tour: route(), places: places, dives: [:]))
        XCTAssertEqual(walk.stops.map(\.place.id), ["a", "b"])
        XCTAssertEqual(walk.stops.first?.paragraphs, ["See the first stop."])
        XCTAssertNil(OfflineWalk(tour: route(), places: [:], dives: [:]))
        XCTAssertNil(OfflineWalk(tour: route(premium: true), places: places, dives: [:]))
        XCTAssertNil(OfflineWalk(tour: route(mode: .mixed), places: places, dives: [:]))
    }

    func testResumeCompletionAndRestartSurviveRecreationAndRespectTraveler() throws {
        let walk = try XCTUnwrap(OfflineWalk(tour: route(), places: places, dives: [:]))
        let suite = "offline-walk-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func reopen(owner: String? = nil) -> OfflineWalkSession {
            OfflineWalkSession(walk: walk, owner: owner, defaults: defaults)
        }
        var walking = reopen()
        XCTAssertEqual(walking.index, 0)
        walking.next()
        walking.previous()
        XCTAssertEqual(walking.index, 0)
        var resumed = reopen()
        XCTAssertEqual(resumed.index, 1)
        XCTAssertEqual(reopen(owner: "different-traveler").index, 0)
        resumed.next()
        var finished = reopen()
        XCTAssertTrue(finished.complete)
        finished.restart()
        XCTAssertEqual(reopen().index, 0)
        XCTAssertFalse(reopen().complete)
    }
}
