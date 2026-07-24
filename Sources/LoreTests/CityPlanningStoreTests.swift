import XCTest
@testable import Lore

final class CityPlanningStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CityPlanningStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPinsAreScopedToTraveler() {
        CityPlanningStore.toggle(city: "tokyo", userID: "traveler-a", defaults: defaults)

        XCTAssertEqual(
            CityPlanningStore.cities(userID: "traveler-a", defaults: defaults),
            Set(["tokyo"])
        )
        XCTAssertTrue(CityPlanningStore.cities(userID: "traveler-b", defaults: defaults).isEmpty)
        XCTAssertTrue(CityPlanningStore.cities(userID: nil, defaults: defaults).isEmpty)
    }

    func testTogglingAgainRemovesOnlyThatCity() {
        CityPlanningStore.toggle(city: "paris", userID: nil, defaults: defaults)
        CityPlanningStore.toggle(city: "rome", userID: nil, defaults: defaults)
        CityPlanningStore.toggle(city: "paris", userID: nil, defaults: defaults)

        XCTAssertEqual(CityPlanningStore.cities(userID: nil, defaults: defaults), Set(["rome"]))
    }
}
