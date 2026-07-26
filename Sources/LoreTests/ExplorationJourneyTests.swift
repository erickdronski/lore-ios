import CoreLocation
import XCTest
@testable import Lore

@MainActor
final class ExplorationJourneyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ExplorationJourneyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCrossCityResultBecomesExplicitTravelerChoice() {
        let router = AppRouter(selectedCity: "chicago")

        router.route(.place(id: "place-1", city: "  PARIS "))
        router.autoSelectCity("tokyo")

        XCTAssertEqual(router.selectedCity, "paris")
        XCTAssertTrue(router.userDidChooseCity)
    }

    func testDeepLinkCarriesCityAndRejectsAmbiguousPaths() throws {
        let router = AppRouter(selectedCity: "chicago")

        XCTAssertTrue(router.handleDeepLink(try XCTUnwrap(URL(string: "lore://place/place-1?city=tokyo"))))
        XCTAssertEqual(router.selectedCity, "tokyo")
        XCTAssertEqual(router.lastRoute, .place(id: "place-1", city: "tokyo"))

        XCTAssertFalse(router.handleDeepLink(try XCTUnwrap(URL(string: "lore://place/place-1/extra"))))
        XCTAssertFalse(router.handleDeepLink(try XCTUnwrap(URL(string: "https://example.com/place/place-1"))))
    }

    func testWidgetDeepLinkContextOnlyRetainsCurrentSnapshot() {
        DeepLinkContextStore.remember(
            city: "paris",
            forPlaceIDs: ["a", "b"],
            defaults: defaults
        )
        XCTAssertEqual(DeepLinkContextStore.city(forPlaceID: "a", defaults: defaults), "paris")

        DeepLinkContextStore.remember(
            city: "tokyo",
            forPlaceIDs: ["c"],
            defaults: defaults
        )
        XCTAssertNil(DeepLinkContextStore.city(forPlaceID: "a", defaults: defaults))
        XCTAssertEqual(DeepLinkContextStore.city(forPlaceID: "c", defaults: defaults), "tokyo")
    }

    func testGuestPlansMoveIntoFirstSignedInJourney() {
        CityPlanningStore.toggle(city: " Paris ", userID: nil, defaults: defaults)
        CityPlanningStore.toggle(city: "TOKYO", userID: nil, defaults: defaults)

        XCTAssertEqual(
            CityPlanningStore.cities(userID: "traveler", defaults: defaults),
            Set(["paris", "tokyo"])
        )
        XCTAssertTrue(CityPlanningStore.cities(userID: nil, defaults: defaults).isEmpty)
    }

    func testMapFilterCatalogTracksOnlyCurrentCity() {
        let store = MapFilterStore(credentials: { nil })
        store.syncCategories(from: [place(id: "1", kind: "building")])
        XCTAssertEqual(store.categories.map(\.kind), ["building"])

        store.syncCategories(from: [place(id: "2", kind: "park")])
        XCTAssertEqual(store.categories.map(\.kind), ["park"])
    }

    func testRapidFilterTapsPersistOnlyTheSettledState() async throws {
        var writes: [[String]] = []
        let persisted = expectation(description: "Settled filter state persisted")
        let store = MapFilterStore(
            credentials: { ("traveler", "token") },
            writeHiddenKinds: { kinds, _, _ in
                writes.append(kinds)
                persisted.fulfill()
            }
        )
        store.syncCategories(from: [
            place(id: "1", kind: "building"),
            place(id: "2", kind: "park"),
        ])

        let building = try XCTUnwrap(store.categories.first { $0.kind == "building" })
        let park = try XCTUnwrap(store.categories.first { $0.kind == "park" })
        store.toggle(building)
        store.toggle(park)
        store.toggle(building)

        await fulfillment(of: [persisted], timeout: 2)
        XCTAssertEqual(writes, [["park"]])
        XCTAssertNil(store.lastError)
    }

    func testCollectionsOnlyAppearWithEnoughRealMatches() {
        let onePark = [place(id: "1", kind: "park")]
        XCTAssertFalse(PlaceCollection.available(in: onePark).contains(.nature))

        let twoParks = onePark + [place(id: "2", kind: "park")]
        XCTAssertTrue(PlaceCollection.available(in: twoParks).contains(.nature))
        XCTAssertTrue(PlaceCollection.available(in: twoParks).contains(.free))
    }

    func testNearbyShelfOrdersRealDistancesAndRejectsFarawayCity() {
        let user = CLLocation(latitude: 41.881, longitude: -87.629)
        let close = place(id: "close", kind: "building", lat: 41.882, lng: -87.629)
        let farther = place(id: "farther", kind: "park", lat: 41.89, lng: -87.629)
        let overseas = place(id: "overseas", kind: "building", lat: 48.8566, lng: 2.3522)
        let relevance = MapRelevance(prefs: nil, hasActiveFilter: false)

        let ranked = NearMe.nearest(
            to: user,
            among: [overseas, farther, close],
            relevance: relevance,
            limit: 8
        )

        XCTAssertEqual(ranked.map(\.id), ["close", "farther"])
        XCTAssertLessThan(ranked[0].meters, ranked[1].meters)
    }

    func testCityRegionHandlesHomeAndInternationalMarkets() {
        XCTAssertEqual(CityRegion.region(forCountry: "US"), .unitedStates)
        XCTAssertEqual(CityRegion.region(forCountry: "JP"), .asia)
        XCTAssertEqual(CityRegion.region(forCountry: "AE"), .middleEastAfrica)
        XCTAssertEqual(CityRegion.region(forCountry: "XX"), .international)
    }

    private func place(
        id: String,
        kind: String,
        lat: Double = 41.881,
        lng: Double = -87.629
    ) -> Place {
        Place(
            id: id,
            slug: id,
            name: id.capitalized,
            kind: kind,
            lat: lat,
            lng: lng,
            city: "chicago"
        )
    }
}
