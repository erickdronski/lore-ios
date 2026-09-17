import XCTest
@testable import Lore

final class LoreAPITests: XCTestCase {
    func testPostgRESTEndpointsKeepVersionPath() {
        let rpc = Config.restURL
            .appending(path: "rpc")
            .appending(path: "search_lore")
        let table = Config.restURL.appending(path: "user_prefs")

        XCTAssertEqual(rpc.path, "/rest/v1/rpc/search_lore")
        XCTAssertEqual(table.path, "/rest/v1/user_prefs")
    }

    func testAuthSessionRefreshWindowUsesServerExpiry() {
        let user = AuthUser(id: "user", email: nil)
        let future = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 3_600,
            expiresAt: Int(Date().timeIntervalSince1970) + 3_600,
            tokenType: "bearer",
            user: user
        )
        let expired = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 3_600,
            expiresAt: Int(Date().timeIntervalSince1970) - 1,
            tokenType: "bearer",
            user: user
        )
        let legacy = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 3_600,
            tokenType: "bearer",
            user: user
        )

        XCTAssertFalse(future.expires(within: 120))
        XCTAssertFalse(future.isExpired)
        XCTAssertTrue(expired.expires(within: 120))
        XCTAssertTrue(expired.isExpired)
        XCTAssertTrue(legacy.expires(within: 120))
        XCTAssertTrue(legacy.isExpired)
    }

    func testCityFactSourceURLAcceptsOnlyWebLinks() {
        XCTAssertEqual(cityFact(source: "https://example.com/fact").sourceURL?.absoluteString,
                       "https://example.com/fact")
        XCTAssertEqual(cityFact(source: "http://example.com/fact").sourceURL?.absoluteString,
                       "http://example.com/fact")
        XCTAssertNil(cityFact(source: "seed:dev").sourceURL)
        XCTAssertNil(cityFact(source: "ftp://example.com/fact").sourceURL)
        XCTAssertNil(cityFact(source: "/relative-source").sourceURL)
        XCTAssertNil(cityFact(source: "").sourceURL)
        XCTAssertNil(cityFact(source: nil).sourceURL)
    }

    func testDiveLinksExposeOnlyHTTPSDossierSources() throws {
        let data = Data("""
        {
          "place_id": "place-1",
          "narrative": "A sourced dossier.",
          "timeline": [],
          "links": {
            "website": "https://example.org/place",
            "source_url": "https://archive.example.org/source-record",
            "wikipedia_title": "Example Place"
          },
          "media": {},
          "source": "seed:dev"
        }
        """.utf8)
        let dive = try JSONDecoder().decode(Dive.self, from: data)

        XCTAssertEqual(dive.links.websiteURL?.absoluteString, "https://example.org/place")
        XCTAssertEqual(dive.links.sourceRecordURL?.absoluteString, "https://archive.example.org/source-record")
        XCTAssertEqual(dive.links.wikipediaURL?.absoluteString, "https://en.wikipedia.org/wiki/Example_Place")
    }

    func testDiveMediaRefDecodesOrderedGalleryTitles() throws {
        let data = Data("""
        {
          "place_id": "place-1",
          "narrative": "A sourced dossier.",
          "timeline": [],
          "links": {},
          "media": {
            "wikipedia_title": "Bengaluru Palace",
            "wikipedia_titles": [
              "Bengaluru Palace",
              "Vidhana Soudha",
              "  "
            ],
            "gallery_wikipedia_titles": [
              "vidhana soudha",
              "Tipu Sultan's Summer Palace"
            ]
          },
          "source": "seed:dev"
        }
        """.utf8)

        let dive = try JSONDecoder().decode(Dive.self, from: data)

        XCTAssertEqual(dive.media.wikipediaTitle, "Bengaluru Palace")
        XCTAssertEqual(dive.media.wikipediaTitles, [
            "Bengaluru Palace",
            "Vidhana Soudha",
            "Tipu Sultan's Summer Palace",
        ])
    }

    func testDiveLinksRejectNonHTTPSSourceURLs() {
        let links = DiveLinks(
            website: "http://example.org/place",
            sourceURLString: "ftp://example.org/source",
            wikipediaTitle: nil
        )

        XCTAssertNil(links.websiteURL)
        XCTAssertNil(links.sourceRecordURL)
    }

    func testCatalogQueriesBoundCityPagesAndLookupByID() {
        let page = CatalogQuery.placesPage(city: "chicago", offset: 200, limit: LoreAPI.catalogPageSize)
        XCTAssertEqual(page.first { $0.name == "city" }?.value, "eq.chicago")
        XCTAssertEqual(page.first { $0.name == "limit" }?.value, "200")
        XCTAssertEqual(page.first { $0.name == "offset" }?.value, "200")

        let byID = CatalogQuery.placeByID("215607ca-aaaa-bbbb-cccc-ddddeeeeffff")
        XCTAssertEqual(byID.first { $0.name == "id" }?.value, "eq.215607ca-aaaa-bbbb-cccc-ddddeeeeffff")
        XCTAssertEqual(byID.first { $0.name == "limit" }?.value, "1")
        XCTAssertNil(byID.first { $0.name == "city" })

        let tour = CatalogQuery.tourBySlug("riverwalk")
        XCTAssertEqual(tour.first { $0.name == "slug" }?.value, "eq.riverwalk")
        XCTAssertEqual(tour.first { $0.name == "limit" }?.value, "1")

        let poisoned = CatalogQuery.eq("city", "chicago,or.other")
        XCTAssertEqual(poisoned.value, "eq.chicagoorother")
    }

    func testOnboardingInterestsOmitTrendingChip() {
        XCTAssertFalse(InterestMap.allInterests.contains("trending"))
        XCTAssertFalse(
            OnboardingContent.presets.flatMap(\.interests).contains("trending")
        )
        XCTAssertEqual(LoreAPI.catalogPageSize, 200)
        XCTAssertEqual(LoreAPI.catalogMaxRows, 4_000)
    }

    func testChromeLocalizationStaysEnglish() {
        let previous = L10n.shared.choice
        L10n.shared.choice = "es"
        XCTAssertEqual(L10n.t("tab.map"), "Map")
        L10n.shared.choice = previous
    }

    private func cityFact(source: String?) -> CityFact {
        CityFact(
            id: "fact",
            city: "chicago",
            category: .quirk,
            fact: "A sourced fact",
            detail: nil,
            statValue: nil,
            statLabel: nil,
            emoji: nil,
            source: source,
            sort: 1
        )
    }
}
