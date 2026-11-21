import XCTest
@testable import Lore

final class StarterCatalogTests: XCTestCase {
    func testShippedResourceOpensAndEveryListedPlaceHasAStoryAndSource() throws {
        let catalog = try XCTUnwrap(StarterCatalog.bundled)
        let cities = Set(catalog.cities.map(\.slug))
        XCTAssertTrue(cities.contains(Config.defaultCity))
        XCTAssertEqual(cities.count, catalog.cities.count)
        XCTAssertEqual(Set(catalog.places.map(\.city)), cities)
        let placeIDs = Set(catalog.places.map(\.id))
        XCTAssertEqual(placeIDs.count, catalog.places.count)
        XCTAssertEqual(placeIDs, Set(catalog.dives.map(\.placeID)))
        for dive in catalog.dives {
            XCTAssertFalse(dive.narrative?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            XCTAssertEqual(dive.links.sourceRecordURL?.scheme, "https")
        }
    }
}
