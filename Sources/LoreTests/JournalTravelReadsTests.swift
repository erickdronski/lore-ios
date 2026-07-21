import XCTest
@testable import Lore

private final class JournalURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class JournalTravelReadsTests: XCTestCase {
    override func tearDown() {
        JournalURLProtocol.handler = nil
        super.tearDown()
    }

    func testVisitHistorySendsBoundedStablePageQuery() async throws {
        JournalURLProtocol.handler = { request in
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["limit"], "17")
            XCTAssertEqual(query["offset"], "34")
            XCTAssertEqual(query["order"], "visited_at.desc,place_id.asc")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let rows = try await TravelReads.visitHistory(
            accessToken: "token",
            limit: 17,
            offset: 34,
            session: makeSession()
        )

        XCTAssertTrue(rows.isEmpty)
    }

    func testVisitHistoryClampsInvalidBounds() async throws {
        JournalURLProtocol.handler = { request in
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["limit"], "1")
            XCTAssertEqual(query["offset"], "0")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        _ = try await TravelReads.visitHistory(
            accessToken: "token",
            limit: 0,
            offset: -1,
            session: makeSession()
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JournalURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
