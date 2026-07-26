import Foundation
import XCTest
@testable import Lore

final class LoreNetworkResilienceTests: XCTestCase {
    override func tearDown() {
        NetworkStubProtocol.handler = nil
        super.tearDown()
    }

    func testSuccessfulResponseDecodes() async throws {
        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data("[{\"place_id\":\"one\"},{\"place_id\":\"two\"}]".utf8))
        }

        let result = try await makeAPI().placesWithOffers(placeIDs: ["one", "two"])

        XCTAssertEqual(result, Set(["one", "two"]))
    }

    func testHTTPFailureKeepsServerBodyOutOfUserFacingError() async throws {
        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("private backend diagnostic".utf8))
        }

        do {
            _ = try await makeAPI().placesWithOffers(placeIDs: ["one"])
            XCTFail("Expected an HTTP error")
        } catch let error as LoreAPI.APIError {
            XCTAssertEqual(
                error.localizedDescription,
                "Lore's service is having trouble. Please try again shortly."
            )
            XCTAssertFalse(error.localizedDescription.contains("private backend diagnostic"))
        }
    }

    func testMalformedJSONProducesSafeDecodingMessage() async throws {
        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("not-json".utf8))
        }

        do {
            _ = try await makeAPI().placesWithOffers(placeIDs: ["one"])
            XCTFail("Expected a decoding error")
        } catch let error as LoreAPI.APIError {
            XCTAssertEqual(error.localizedDescription, "Lore couldn't read that response. Please try again.")
        }
    }

    func testCancellationDoesNotReturnAStaleAtlasPayload() async throws {
        let cache = AtlasCache()
        let url = try XCTUnwrap(URL(string: "https://example.com/atlas/\(UUID().uuidString)"))
        let request = URLRequest(url: url)
        let session = makeSession()

        NetworkStubProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("cached".utf8))
        }
        _ = try await cache.data(for: request, session: session, freshFor: -1)

        // Leaving the protocol unanswered makes the second request wait until
        // cancellation. Before the cancellation guard, AtlasCache returned the
        // stale bytes and allowed an obsolete screen task to keep running.
        NetworkStubProtocol.handler = nil
        let task = Task {
            try await cache.data(for: request, session: session, freshFor: -1)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled atlas request must not return stale data")
        } catch is CancellationError {
            // Expected on newer URLSession implementations.
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        }
    }

    private func makeAPI() -> LoreAPI {
        LoreAPI(session: makeSession())
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetworkStubProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class NetworkStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        do {
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
