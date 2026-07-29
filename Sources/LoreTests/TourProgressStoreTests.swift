import XCTest
@testable import Lore

final class TourProgressStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TourProgressStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testProgressIsScopedToTravelerAndClampedToRoute() {
        TourProgressStore.advance(
            to: 8,
            for: "harbor-walk",
            userID: "traveler-a",
            defaults: defaults
        )

        XCTAssertEqual(
            TourProgressStore.progress(
                for: "harbor-walk",
                userID: "traveler-a",
                stopCount: 6,
                defaults: defaults
            ).stopIndex,
            5
        )
        XCTAssertEqual(
            TourProgressStore.progress(
                for: "harbor-walk",
                userID: "traveler-b",
                stopCount: 6,
                defaults: defaults
            ),
            .empty
        )
    }

    func testCompletionClearsResumePointAndRestartClearsCompletion() {
        TourProgressStore.advance(
            to: 3,
            for: "market-walk",
            userID: nil,
            defaults: defaults
        )
        TourProgressStore.complete(
            tourSlug: "market-walk",
            userID: nil,
            defaults: defaults
        )

        let completed = TourProgressStore.progress(
            for: "market-walk",
            userID: nil,
            stopCount: 5,
            defaults: defaults
        )
        XCTAssertNil(completed.stopIndex)
        XCTAssertTrue(completed.isCompleted)

        TourProgressStore.restart(
            tourSlug: "market-walk",
            userID: nil,
            defaults: defaults
        )
        XCTAssertEqual(
            TourProgressStore.progress(
                for: "market-walk",
                userID: nil,
                stopCount: 5,
                defaults: defaults
            ),
            .empty
        )
    }

    func testProgressOnlyMovesForwardUntilAnExplicitRestart() {
        TourProgressStore.advance(
            to: 4,
            for: "canal-walk",
            userID: "traveler",
            defaults: defaults
        )
        TourProgressStore.advance(
            to: 2,
            for: "canal-walk",
            userID: "traveler",
            defaults: defaults
        )

        XCTAssertEqual(
            TourProgressStore.progress(
                for: "canal-walk",
                userID: "traveler",
                stopCount: 8,
                defaults: defaults
            ).stopIndex,
            4
        )

        TourProgressStore.restart(
            tourSlug: "canal-walk",
            userID: "traveler",
            defaults: defaults
        )
        XCTAssertEqual(
            TourProgressStore.progress(
                for: "canal-walk",
                userID: "traveler",
                stopCount: 8,
                defaults: defaults
            ),
            .empty
        )
    }
}
