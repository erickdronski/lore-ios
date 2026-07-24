import XCTest
@testable import Lore

final class CityExperienceProgressStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CityExperienceProgressStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCompletionIsScopedToTraveler() {
        CityExperienceProgressStore.complete(
            entryID: "listen-one",
            userID: "traveler-a",
            defaults: defaults
        )

        XCTAssertTrue(CityExperienceProgressStore.isCompleted(
            entryID: "listen-one", userID: "traveler-a", defaults: defaults
        ))
        XCTAssertFalse(CityExperienceProgressStore.isCompleted(
            entryID: "listen-one", userID: "traveler-b", defaults: defaults
        ))
        XCTAssertFalse(CityExperienceProgressStore.isCompleted(
            entryID: "listen-one", userID: nil, defaults: defaults
        ))
    }

    func testResetClearsOnlyRequestedExperience() {
        CityExperienceProgressStore.complete(
            entryID: "field-note-one", userID: nil, defaults: defaults
        )
        CityExperienceProgressStore.complete(
            entryID: "field-note-two", userID: nil, defaults: defaults
        )
        CityExperienceProgressStore.reset(
            entryID: "field-note-one", userID: nil, defaults: defaults
        )

        XCTAssertFalse(CityExperienceProgressStore.isCompleted(
            entryID: "field-note-one", userID: nil, defaults: defaults
        ))
        XCTAssertTrue(CityExperienceProgressStore.isCompleted(
            entryID: "field-note-two", userID: nil, defaults: defaults
        ))
    }
}
