import XCTest
@testable import Lore

private enum JournalTestError: Error {
    case expected
}

private actor JournalShareProbe {
    private(set) var completions: [Bool] = []

    func update(_ isPublic: Bool) async throws {
        if isPublic {
            try await Task.sleep(nanoseconds: 120_000_000)
        } else {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        completions.append(isPublic)
    }
}

private actor JournalPhotoProbe {
    private(set) var requestCount = 0
    private(set) var maxConcurrent = 0
    private var active = 0

    func resolve(path: String) async throws -> URL {
        requestCount += 1
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        try await Task.sleep(nanoseconds: 40_000_000)
        active -= 1
        return URL(string: "https://example.com/\(path)")!
    }
}

@MainActor
final class JournalStoreTests: XCTestCase {
    func testHistoryLoadsBoundedPagesAtRawOffsets() async {
        var requests: [(limit: Int, offset: Int)] = []
        let firstPage = (0..<VisitStore.journalPageSize).map { entry(index: $0) }
        let secondPage = [entry(index: 100), entry(index: 101)]
        let client = makeClient(historyPage: { _, limit, offset in
            requests.append((limit, offset))
            return offset == 0 ? firstPage : secondPage
        })
        let store = makeStore(client: client)

        await store.loadHistory()

        XCTAssertEqual(store.visitHistory.count, VisitStore.journalPageSize)
        XCTAssertTrue(store.historyHasMore)
        XCTAssertEqual(requests.map(\.limit), [VisitStore.journalPageSize])
        XCTAssertEqual(requests.map(\.offset), [0])

        await store.loadMoreHistory()

        XCTAssertEqual(store.visitHistory.count, VisitStore.journalPageSize + 2)
        XCTAssertFalse(store.historyHasMore)
        XCTAssertEqual(requests.map(\.offset), [0, VisitStore.journalPageSize])
    }

    func testFailedNoteDoesNotMutateHistoryAndRetryDoes() async {
        var writeCount = 0
        let original = entry(index: 1, note: "Before")
        let client = makeClient(
            historyPage: { _, _, _ in [original] },
            updateNote: { _, _, _ in
                writeCount += 1
                if writeCount == 1 { throw JournalTestError.expected }
            }
        )
        let store = makeStore(client: client)
        await store.loadHistory()

        let failed = await store.saveNote(placeID: original.placeID, note: "After")

        guard case .failed = failed else { return XCTFail("Expected a failed write") }
        XCTAssertEqual(store.visitHistory.first?.note, "Before")

        let saved = await store.saveNote(placeID: original.placeID, note: "After")

        XCTAssertEqual(saved, .saved)
        XCTAssertEqual(store.visitHistory.first?.note, "After")
        XCTAssertNil(store.lastError)
    }

    func testRapidSharingWritesCompleteInToggleOrder() async throws {
        let probe = JournalShareProbe()
        let original = entry(index: 1, isPublic: false)
        let client = makeClient(
            historyPage: { _, _, _ in [original] },
            setShared: { _, isPublic, _ in try await probe.update(isPublic) }
        )
        let store = makeStore(client: client)
        await store.loadHistory()

        let first = Task { @MainActor in
            await store.setShared(placeID: original.placeID, isPublic: true)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        let second = Task { @MainActor in
            await store.setShared(placeID: original.placeID, isPublic: false)
        }

        let firstResult = await first.value
        let secondResult = await second.value
        let completions = await probe.completions
        XCTAssertEqual(firstResult, .saved)
        XCTAssertEqual(secondResult, .saved)
        XCTAssertEqual(completions, [true, false])
        XCTAssertFalse(store.visitHistory.first?.isShared ?? true)
    }

    func testPhotoRetryReusesUploadAndPreservesExistingPaths() async {
        var uploadCount = 0
        var patchCount = 0
        var patchedPaths: [[String]] = []
        let original = entry(index: 1, photos: ["user/place/existing.jpg"])
        let client = makeClient(
            historyPage: { _, _, _ in [original] },
            uploadPhoto: { _, _, _, _ in
                uploadCount += 1
                return "user/place/new.jpg"
            },
            updatePhotos: { _, paths, _ in
                patchCount += 1
                patchedPaths.append(paths)
                if patchCount == 1 { throw JournalTestError.expected }
            }
        )
        let store = makeStore(client: client)
        await store.loadHistory()

        guard case .failed = await store.addPhoto(placeID: original.placeID, imageData: Data([1])) else {
            return XCTFail("Expected the first metadata write to fail")
        }
        XCTAssertEqual(uploadCount, 1)

        let retryResult = await store.addPhoto(placeID: original.placeID, imageData: Data([1]))
        XCTAssertEqual(retryResult, .saved)
        XCTAssertEqual(uploadCount, 1)
        XCTAssertEqual(patchedPaths.last, ["user/place/existing.jpg", "user/place/new.jpg"])
        XCTAssertEqual(store.visitHistory.first?.photoPaths, patchedPaths.last)
    }

    func testDifferentPhotoAfterFailureGetsItsOwnUploadPath() async {
        var uploadCount = 0
        var patchCount = 0
        var patchedPaths: [[String]] = []
        let original = entry(index: 1, photos: ["user/place/existing.jpg"])
        let client = makeClient(
            historyPage: { _, _, _ in [original] },
            uploadPhoto: { _, _, _, _ in
                uploadCount += 1
                return "user/place/new-\(uploadCount).jpg"
            },
            updatePhotos: { _, paths, _ in
                patchCount += 1
                patchedPaths.append(paths)
                if patchCount == 1 { throw JournalTestError.expected }
            }
        )
        let store = makeStore(client: client)
        await store.loadHistory()

        guard case .failed = await store.addPhoto(placeID: original.placeID, imageData: Data([1])) else {
            return XCTFail("Expected the first metadata write to fail")
        }
        let result = await store.addPhoto(placeID: original.placeID, imageData: Data([2]))

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(uploadCount, 2)
        XCTAssertEqual(patchedPaths.last, ["user/place/existing.jpg", "user/place/new-2.jpg"])
    }

    func testSignedPhotoRequestsAreCoalescedAndCapped() async {
        let probe = JournalPhotoProbe()
        let client = makeClient(
            signedPhotoURL: { path, _ in try await probe.resolve(path: path) }
        )
        let store = makeStore(client: client)

        let duplicateTasks = (0..<8).map { _ in
            Task { @MainActor in await store.signedPhotoURL(path: "same.jpg") }
        }
        for task in duplicateTasks { _ = await task.value }
        let duplicateRequestCount = await probe.requestCount
        XCTAssertEqual(duplicateRequestCount, 1)

        let uniqueTasks = (0..<8).map { index in
            Task { @MainActor in await store.signedPhotoURL(path: "\(index).jpg") }
        }
        for task in uniqueTasks { _ = await task.value }

        let totalRequestCount = await probe.requestCount
        let maxConcurrent = await probe.maxConcurrent
        XCTAssertEqual(totalRequestCount, 9)
        XCTAssertLessThanOrEqual(maxConcurrent, 4)
    }

    private func makeStore(client: VisitStore.JournalClient) -> VisitStore {
        VisitStore(
            credentials: { (userID: "user", accessToken: "token") },
            journal: client
        )
    }

    private func makeClient(
        historyPage: @escaping (String, Int, Int) async throws -> [VisitLogEntry] = { _, _, _ in [] },
        historyEntry: @escaping (String, String) async throws -> VisitLogEntry? = { _, _ in nil },
        updateNote: @escaping (String, String, String) async throws -> Void = { _, _, _ in },
        uploadPhoto: @escaping (Data, String, String, String) async throws -> String = { _, _, _, _ in "new.jpg" },
        updatePhotos: @escaping (String, [String], String) async throws -> Void = { _, _, _ in },
        setShared: @escaping (String, Bool, String) async throws -> Void = { _, _, _ in },
        signedPhotoURL: @escaping (String, String) async throws -> URL = { path, _ in
            URL(string: "https://example.com/\(path)")!
        }
    ) -> VisitStore.JournalClient {
        VisitStore.JournalClient(
            historyPage: historyPage,
            historyEntry: historyEntry,
            updateNote: updateNote,
            uploadPhoto: uploadPhoto,
            updatePhotos: updatePhotos,
            setShared: setShared,
            signedPhotoURL: signedPhotoURL
        )
    }

    private func entry(
        index: Int,
        note: String? = nil,
        photos: [String]? = nil,
        isPublic: Bool = false
    ) -> VisitLogEntry {
        VisitLogEntry(
            placeID: "place-\(index)",
            visitedAt: "2026-07-21T12:00:00Z",
            note: note,
            photos: photos,
            visitID: "visit-\(index)",
            isPublic: isPublic,
            status: "visible",
            place: .init(name: "Place \(index)", emoji: nil, city: "chicago", kind: "building")
        )
    }
}
