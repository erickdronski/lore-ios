import Foundation
import XCTest
@testable import Lore

final class TravelReadsTests: XCTestCase {
    override func tearDown() {
        TravelReadsURLProtocol.handler = nil
        super.tearDown()
    }

    func testAppendVisitPhotoUsesAtomicRPCContract() async throws {
        let placeID = "7c26d345-a8c0-43b9-b56b-f7c58b6da972"
        let path = "user-123/\(placeID)/photo.jpg"

        TravelReadsURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/append_visit_photo")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "return=minimal")

            let body = try self.requestBody(request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            XCTAssertEqual(json, ["p_place_id": placeID, "p_path": path])

            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data("[]".utf8))
        }

        try await TravelReads.appendVisitPhoto(
            placeID: placeID,
            path: path,
            accessToken: "token-123",
            session: makeSession()
        )
    }

    func testVisitHistoryPagesUntilTheServerReturnsAShortPage() async throws {
        let lock = NSLock()
        var requestedRanges: [String] = []

        TravelReadsURLProtocol.handler = { request in
            let range = try XCTUnwrap(request.value(forHTTPHeaderField: "Range"))
            lock.lock()
            requestedRanges.append(range)
            lock.unlock()

            let rows: [[String: Any]]
            switch range {
            case "0-199": rows = (0..<200).map(Self.historyRow)
            case "200-399": rows = [Self.historyRow(200)]
            default: XCTFail("Unexpected page \(range)"); rows = []
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, try JSONSerialization.data(withJSONObject: rows))
        }

        let rows = try await TravelReads.visitHistory(
            accessToken: "token-123",
            session: makeSession()
        )

        XCTAssertEqual(rows.count, 201)
        XCTAssertEqual(rows.first?.placeID, "place-0")
        XCTAssertEqual(rows.last?.placeID, "place-200")
        XCTAssertEqual(requestedRanges, ["0-199", "200-399"])
    }

    func testUpdateVisitNoteRequiresOneReturnedOwnerRow() async throws {
        let placeID = "7c26d345-a8c0-43b9-b56b-f7c58b6da972"
        TravelReadsURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "return=representation")
            XCTAssertTrue(request.url?.query?.contains("select=place_id") == true)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data("[{\"place_id\":\"\(placeID)\"}]".utf8))
        }

        try await TravelReads.updateVisitNote(
            placeID: placeID,
            note: "A private field note",
            accessToken: "token-123",
            session: makeSession()
        )
    }

    func testUpdateVisitNoteRejectsAZeroRowSuccess() async throws {
        TravelReadsURLProtocol.handler = { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data("[]".utf8))
        }

        do {
            try await TravelReads.updateVisitNote(
                placeID: "7c26d345-a8c0-43b9-b56b-f7c58b6da972",
                note: "A private field note",
                accessToken: "token-123",
                session: makeSession()
            )
            XCTFail("A zero-row update must not look successful")
        } catch TravelReads.TravelError.missingVisit {
            // Expected: the editor remains open and shows its save error.
        }
    }

    private static func historyRow(_ index: Int) -> [String: Any] {
        [
            "place_id": "place-\(index)",
            "visited_at": "2026-07-29T05:00:00Z",
            "photos": [],
            "is_public": false,
            "place": NSNull(),
        ]
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TravelReadsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw try XCTUnwrap(stream.streamError) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class TravelReadsURLProtocol: URLProtocol {
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
