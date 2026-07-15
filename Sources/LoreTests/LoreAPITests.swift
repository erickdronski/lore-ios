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
