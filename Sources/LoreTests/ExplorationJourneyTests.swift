import CoreLocation
import SwiftUI
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

    func testSavedPlaceStoreHydratesFromServerAndResetsForSignedOutState() async {
        var signedIn = true
        let store = SavedPlaceStore(
            credentials: { signedIn ? ("traveler", "token") : nil },
            savedPlacesLoader: { _ in [
                SavedPlace(
                    userID: "traveler",
                    placeID: "place-1",
                    savedAt: "2026-08-09T12:00:00Z",
                    place: SavedPlace.PlaceSummary(
                        id: "place-1",
                        slug: "old-library",
                        name: "Old Library",
                        kind: "building",
                        city: "dublin",
                        emoji: "📚"
                    )
                ),
            ] },
            saveWriter: { _, _ in },
            removeWriter: { _, _ in }
        )

        await store.load()
        XCTAssertTrue(store.hasSaved("place-1"))
        XCTAssertEqual(store.savedCount, 1)
        XCTAssertEqual(store.entries.first?.displayName, "Old Library")

        signedIn = false
        await store.load(force: true)
        XCTAssertFalse(store.hasSaved("place-1"))
        XCTAssertEqual(store.savedCount, 0)
        XCTAssertTrue(store.loaded)
    }

    func testSavedPlaceStoreDoesNotWriteWhenSignedOut() async {
        var writes = 0
        let store = SavedPlaceStore(
            credentials: { nil },
            savedPlacesLoader: { _ in [] },
            saveWriter: { _, _ in writes += 1 },
            removeWriter: { _, _ in writes += 1 }
        )

        let result = await store.save(placeID: "place-1")

        XCTAssertEqual(result, .signedOut)
        XCTAssertEqual(writes, 0)
        XCTAssertFalse(store.hasSaved("place-1"))
    }

    func testSavedPlaceStoreRollsBackFailedOptimisticSave() async {
        let store = SavedPlaceStore(
            credentials: { ("traveler", "token") },
            savedPlacesLoader: { _ in [] },
            saveWriter: { _, _ in
                throw TravelReads.TravelError.http(status: 500, body: "boom")
            },
            removeWriter: { _, _ in }
        )

        let result = await store.save(placeID: "place-1")

        XCTAssertFalse(store.hasSaved("place-1"))
        guard case .failed(let message) = result else {
            XCTFail("Expected a failed save")
            return
        }
        XCTAssertTrue(message.contains("500"))
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

    func testNearbyCardLayoutIsUniformForDiscoveryDeck() {
        XCTAssertEqual(NearMeCardLayout.cardWidth(isAccessibilitySize: false), 204)
        // Every tile shares one fixed height so the shelf reads as a uniform row,
        // bounded (not bloated) yet tall enough to fit the visit toggle.
        XCTAssertEqual(NearMeCardLayout.uniformHeight(isAccessibilitySize: false), 222)
        XCTAssertLessThanOrEqual(NearMeCardLayout.uniformHeight(isAccessibilitySize: false), 228)
        // The shelf frame must be >= the card height, or the toggle gets clipped.
        XCTAssertGreaterThanOrEqual(
            NearMeCardLayout.shelfMaxHeight(isAccessibilitySize: false),
            NearMeCardLayout.uniformHeight(isAccessibilitySize: false)
        )
        XCTAssertLessThanOrEqual(NearMeCardLayout.shelfMaxHeight(isAccessibilitySize: false), 238)
        XCTAssertEqual(NearMeCardLayout.teaserLineLimit(isAccessibilitySize: false), 0)

        // Accessibility sizes scale the tile up, and the shelf still contains it.
        XCTAssertGreaterThan(
            NearMeCardLayout.uniformHeight(isAccessibilitySize: true),
            NearMeCardLayout.uniformHeight(isAccessibilitySize: false)
        )
        XCTAssertGreaterThanOrEqual(
            NearMeCardLayout.shelfMaxHeight(isAccessibilitySize: true),
            NearMeCardLayout.uniformHeight(isAccessibilitySize: true)
        )
        XCTAssertLessThanOrEqual(NearMeCardLayout.shelfMaxHeight(isAccessibilitySize: true), 310)
        XCTAssertEqual(NearMeCardLayout.teaserLineLimit(isAccessibilitySize: true), 2)
    }

    func testExpandedDiscoveryDeckClearsFloatingTabDock() {
        XCTAssertEqual(TravelMapDeckLayout.collapsedBottomClearance, 16)
        XCTAssertEqual(TravelMapDeckLayout.expandedBottomClearance, 60)
        XCTAssertLessThan(
            TravelMapDeckLayout.bottomClearance(collapsed: true),
            TravelMapDeckLayout.bottomClearance(collapsed: false)
        )
        XCTAssertLessThanOrEqual(
            TravelMapDeckLayout.bottomClearance(collapsed: false),
            64
        )
    }

    func testMapPresentationResolvesOnlyLoadedPlaces() {
        let place = place(id: "found", kind: "building")

        let presented = MapPlacePresentationPolicy.presentablePlace(
            selectedID: "found",
            places: [place]
        )

        XCTAssertEqual(presented?.id, "found")
        XCTAssertTrue(MapPlacePresentationPolicy.shouldRecedeMap(presentedPlace: presented))
    }

    func testMapRecedeClearsForStaleSelectedPlaceID() {
        let presented = MapPlacePresentationPolicy.presentablePlace(
            selectedID: "stale",
            places: [place(id: "current", kind: "building")]
        )

        XCTAssertNil(presented)
        XCTAssertFalse(MapPlacePresentationPolicy.shouldRecedeMap(presentedPlace: presented))
    }

    func testPlaceTeaserPrefersServerDerivedHookText() {
        let place = place(
            id: "place",
            kind: "building",
            layer1: Layer1(
                hook: "A shorter legacy hook.",
                yearBuilt: nil,
                architect: nil,
                style: nil,
                nameMeaning: nil
            ),
            hookText: "  A richer first sentence from the published dossier.  "
        )

        XCTAssertEqual(place.teaser, "A richer first sentence from the published dossier.")
    }

    func testPlaceTeaserFallsBackToTrimmedLayerOneHook() {
        let place = place(
            id: "place",
            kind: "building",
            layer1: Layer1(
                hook: "  A legacy curated hook.  ",
                yearBuilt: nil,
                architect: nil,
                style: nil,
                nameMeaning: nil
            ),
            hookText: "   "
        )

        XCTAssertEqual(place.teaser, "A legacy curated hook.")
    }

    func testMapFallbackCameraIgnoresFarOutlierCoordinates() throws {
        let close = place(id: "close", kind: "building", lat: 41.882, lng: -87.629)
        let farther = place(id: "farther", kind: "park", lat: 41.89, lng: -87.629)
        let overseas = place(id: "overseas", kind: "building", lat: 48.8566, lng: 2.3522)

        let region = try XCTUnwrap(MapScreenModel.regionFitting([overseas, farther, close]))

        XCTAssertEqual(region.center.latitude, 41.886, accuracy: 0.01)
        XCTAssertEqual(region.center.longitude, -87.629, accuracy: 0.01)
        XCTAssertLessThanOrEqual(region.span.latitudeDelta, 0.18)
        XCTAssertLessThanOrEqual(region.span.longitudeDelta, 0.18)
    }

    func testOfflineCityPackDownloadsStayHiddenForCurrentRelease() {
        XCTAssertFalse(Config.offlineCityPacksEnabled)
    }

    func testTourBrowseLayoutContainsDecorativeArtworkInsideCards() {
        XCTAssertGreaterThan(TourBrowseLayout.sectionSpacing, 0)
        XCTAssertGreaterThan(TourBrowseLayout.tourRowArtworkWidth, 0)
        XCTAssertGreaterThan(TourBrowseLayout.tourRowArtworkHeight, 0)
        XCTAssertGreaterThanOrEqual(TourBrowseLayout.tourRowArtworkTrailingInset, 0)
        XCTAssertGreaterThanOrEqual(TourBrowseLayout.tourRowArtworkTopInset, 0)
        XCTAssertEqual(TourBrowseLayout.hiddenInterstitialHeight, 0)
        XCTAssertLessThanOrEqual(TourBrowseLayout.tourRowInsets.top, 4)
        XCTAssertLessThanOrEqual(TourBrowseLayout.tourRowInsets.bottom, 4)
    }

    func testGeneratedWalkStartsNearFreshTravelerOrigin() throws {
        let origin = CLLocationCoordinate2D(latitude: 41.8900, longitude: -87.6200)
        let nearOrigin = place(id: "near-origin", kind: "building", lat: 41.8970, lng: -87.6200)
        let nextNearOrigin = place(id: "next-near-origin", kind: "park", lat: 41.8980, lng: -87.6200)
        let cityCenter = place(id: "city-center", kind: "monument", lat: 41.8700, lng: -87.6500)
        let cityCenterNext = place(id: "city-center-next", kind: "building", lat: 41.8710, lng: -87.6500)

        let tour = try XCTUnwrap(OneHourTour.generate(
            city: "chicago",
            places: [cityCenter, cityCenterNext, nearOrigin, nextNearOrigin],
            from: origin,
            durationMin: 60
        ))

        XCTAssertEqual(tour.stops.first?.placeID, "near-origin")
        XCTAssertEqual(tour.stops.dropFirst().first?.placeID, "next-near-origin")
        XCTAssertGreaterThan(tour.distanceKm ?? 0, 0.7)
    }

    func testGeneratedWalkIgnoresRemoteBrowseOrigin() throws {
        let places = [
            place(id: "anchor", kind: "building", lat: 41.8800, lng: -87.6300),
            place(id: "second", kind: "park", lat: 41.8810, lng: -87.6300),
            place(id: "third", kind: "monument", lat: 41.8820, lng: -87.6300),
        ]
        let remoteOrigin = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)

        let cityWalk = try XCTUnwrap(OneHourTour.generate(
            city: "chicago",
            places: places,
            from: nil,
            durationMin: 60
        ))
        let remoteBrowseWalk = try XCTUnwrap(OneHourTour.generate(
            city: "chicago",
            places: places,
            from: remoteOrigin,
            durationMin: 60
        ))

        XCTAssertEqual(remoteBrowseWalk.stops.map(\.placeID), cityWalk.stops.map(\.placeID))
        XCTAssertEqual(remoteBrowseWalk.distanceKm ?? -1, cityWalk.distanceKm ?? -2, accuracy: 0.001)
    }

    func testGeneratedWalkIdentityIncludesOrderedRouteStops() throws {
        let northOrigin = CLLocationCoordinate2D(latitude: 41.8970, longitude: -87.6200)
        let southOrigin = CLLocationCoordinate2D(latitude: 41.8700, longitude: -87.6500)
        let places = [
            place(id: "south-anchor", kind: "building", lat: 41.8700, lng: -87.6500),
            place(id: "south-next", kind: "park", lat: 41.8710, lng: -87.6500),
            place(id: "north-anchor", kind: "museum", lat: 41.8970, lng: -87.6200),
            place(id: "north-next", kind: "monument", lat: 41.8980, lng: -87.6200),
        ]

        let northWalk = try XCTUnwrap(OneHourTour.generate(
            city: "chicago",
            places: places,
            from: northOrigin,
            durationMin: 60
        ))
        let southWalk = try XCTUnwrap(OneHourTour.generate(
            city: "chicago",
            places: places,
            from: southOrigin,
            durationMin: 60
        ))

        XCTAssertNotEqual(northWalk.stops.map(\.placeID), southWalk.stops.map(\.placeID))
        XCTAssertNotEqual(northWalk.slug, southWalk.slug)
        XCTAssertEqual(northWalk.title, "1 Hour In Chicago")
        XCTAssertEqual(southWalk.title, "1 Hour In Chicago")
        XCTAssertTrue(northWalk.stops.allSatisfy { $0.tourID == northWalk.id })
        XCTAssertTrue(southWalk.stops.allSatisfy { $0.tourID == southWalk.id })

        TourProgressStore.complete(
            tourSlug: northWalk.slug,
            userID: "traveler",
            defaults: defaults
        )

        XCTAssertTrue(TourProgressStore.progress(
            for: northWalk.slug,
            userID: "traveler",
            stopCount: northWalk.stops.count,
            defaults: defaults
        ).isCompleted)
        XCTAssertEqual(TourProgressStore.progress(
            for: southWalk.slug,
            userID: "traveler",
            stopCount: southWalk.stops.count,
            defaults: defaults
        ), .empty)
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
        lng: Double = -87.629,
        layer1: Layer1? = nil,
        hookText: String? = nil
    ) -> Place {
        Place(
            id: id,
            slug: id,
            name: id.capitalized,
            kind: kind,
            lat: lat,
            lng: lng,
            city: "chicago",
            layer1: layer1,
            hookText: hookText
        )
    }
}
