import XCTest
@testable import Lore

final class StarterCatalogTests: XCTestCase {
    func testEveryMapPinHasACityValidCoordinatesAndASource() throws {
        let catalog = try XCTUnwrap(StarterCatalog.bundled)
        let cities = Set(catalog.cities.map(\.slug))
        XCTAssertTrue(cities.contains(Config.defaultCity))
        XCTAssertEqual(cities.count, catalog.cities.count)
        XCTAssertEqual(Set(catalog.places.map(\.city)), cities)
        XCTAssertEqual(catalog.placesByID.count, catalog.places.count)
        for place in catalog.places {
            XCTAssertTrue((-90...90).contains(place.lat), place.name)
            XCTAssertTrue((-180...180).contains(place.lng), place.name)
            let source = try XCTUnwrap(catalog.sources[place.id]?.source_url, place.name)
            XCTAssertEqual(source.scheme, "https", place.name)
            XCTAssertNotNil(source.host, place.name)
        }
    }

    func testNarrativesAndWalksResolveToMapPins() throws {
        let catalog = try XCTUnwrap(StarterCatalog.bundled)
        let storyPlaces = catalog.places.filter { $0.hookText != nil }
        XCTAssertEqual(Set(storyPlaces.map(\.id)), Set(catalog.divesByID.keys))
        XCTAssertEqual(Set(storyPlaces.map(\.city)), Set(catalog.cities.map(\.slug)))
        XCTAssertEqual(catalog.divesByID.count, catalog.dives.count)
        for dive in catalog.dives {
            XCTAssertNotNil(catalog.placesByID[dive.placeID])
            XCTAssertFalse(dive.narrative?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            XCTAssertEqual(dive.links.sourceRecordURL?.scheme, "https")
        }
        XCTAssertFalse(catalog.tours.isEmpty)
        for tour in catalog.tours {
            let walk = try XCTUnwrap(OfflineWalk(tour: tour, places: catalog.placesByID, dives: catalog.divesByID), tour.slug)
            XCTAssertEqual(walk.stops.map(\.entry.seq), Array(1...walk.stops.count), tour.slug)
        }
    }
}
