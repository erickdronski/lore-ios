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

    func testSavedPlacesReadUsesOwnerScopedJoinAndPagingHeaders() async throws {
        TravelReadsURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/rest/v1/saved_place")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range-Unit"), "items")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "0-199")

            let query = request.url?.query?.removingPercentEncoding ?? ""
            XCTAssertTrue(query.contains("select=user_id,place_id,saved_at,note,rating,place(id,slug,name,kind,city,emoji)"))
            XCTAssertTrue(query.contains("order=saved_at.desc"))

            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data(#"[{"user_id":"u1","place_id":"p1","saved_at":"2026-08-09T12:00:00Z","place":{"id":"p1","slug":"library","name":"Old Library","kind":"building","city":"dublin","emoji":"📚"}}]"#.utf8))
        }

        let rows = try await TravelReads.savedPlaces(
            accessToken: "token-123",
            session: makeSession()
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.placeID, "p1")
        XCTAssertEqual(rows.first?.displayName, "Old Library")
        XCTAssertEqual(rows.first?.displayCity, "Dublin")
    }

    func testSavePlacePostsPlaceOnlyWithDuplicateSafeContract() async throws {
        let placeID = "7c26d345-a8c0-43b9-b56b-f7c58b6da972"

        TravelReadsURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/rest/v1/saved_place")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "resolution=ignore-duplicates,return=minimal")

            let query = request.url?.query?.removingPercentEncoding ?? ""
            XCTAssertTrue(query.contains("on_conflict=user_id,place_id"))

            let body = try self.requestBody(request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            XCTAssertEqual(json, ["place_id": placeID])

            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data())
        }

        try await TravelReads.savePlace(
            placeID: placeID,
            accessToken: "token-123",
            session: makeSession()
        )
    }

    func testRemoveSavedPlaceDeletesOnlyTheSelectedPlace() async throws {
        let placeID = "7c26d345-a8c0-43b9-b56b-f7c58b6da972"

        TravelReadsURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/rest/v1/saved_place")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "return=minimal")
            XCTAssertEqual(request.url?.query?.removingPercentEncoding, "place_id=eq.\(placeID)")

            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 204,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        try await TravelReads.removeSavedPlace(
            placeID: placeID,
            accessToken: "token-123",
            session: makeSession()
        )
    }

    func testStoreJournalPhotoDeletesUploadWhenDatabaseAppendFails() async throws {
        let placeID = "7c26d345-a8c0-43b9-b56b-f7c58b6da972"
        let lock = NSLock()
        var uploadedPath: String?
        var calls: [String] = []

        TravelReadsURLProtocol.handler = { request in
            let method = try XCTUnwrap(request.httpMethod)
            let requestPath = try XCTUnwrap(request.url?.path)
            lock.lock()
            calls.append("\(method) \(requestPath)")
            lock.unlock()

            let status: Int
            let responseData: Data
            if method == "POST", requestPath.hasPrefix("/storage/v1/object/journal-photos/") {
                uploadedPath = String(requestPath.dropFirst("/storage/v1/object/journal-photos/".count))
                status = 200
                responseData = Data("{}".utf8)
            } else if method == "POST", requestPath == "/rest/v1/rpc/append_visit_photo" {
                status = 500
                responseData = Data(#"{"message":"append failed"}"#.utf8)
            } else if method == "DELETE", requestPath == "/storage/v1/object/journal-photos" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
                let body = try self.requestBody(request)
                let json = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: body) as? [String: [String]]
                )
                XCTAssertEqual(json["prefixes"], [try XCTUnwrap(uploadedPath)])
                status = 200
                responseData = Data("[]".utf8)
            } else {
                XCTFail("Unexpected request: \(method) \(requestPath)")
                status = 404
                responseData = Data()
            }

            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, responseData)
        }

        do {
            _ = try await TravelReads.storeJournalPhoto(
                data: Data("jpeg".utf8),
                userID: "user-123",
                placeID: placeID,
                accessToken: "token-123",
                session: makeSession()
            )
            XCTFail("A failed database append must remain a failed photo save")
        } catch TravelReads.TravelError.http(let status, _) {
            XCTAssertEqual(status, 500)
        }

        XCTAssertEqual(calls.count, 3)
        XCTAssertTrue(calls[0].hasPrefix("POST /storage/v1/object/journal-photos/user-123/\(placeID)/"))
        XCTAssertEqual(calls[1], "POST /rest/v1/rpc/append_visit_photo")
        XCTAssertEqual(calls[2], "DELETE /storage/v1/object/journal-photos")
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
