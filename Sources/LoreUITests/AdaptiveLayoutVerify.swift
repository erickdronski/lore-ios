import UIKit
import XCTest

/// Guards the universal shell itself. Screenshot coverage exercises the rich
/// surfaces; this test makes the compact/regular navigation contract explicit.
final class AdaptiveLayoutVerify: XCTestCase {
    @MainActor
    func testNavigationMatchesTheDeviceCanvas() throws {
        let app = XCUIApplication()
        app.launchArguments += ["LORE_SCREENSHOTS"]
        app.launch()

        if UIDevice.current.userInterfaceIdiom == .pad {
            let mapSidebarButton = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Map,"))
                .firstMatch
            XCTAssertTrue(mapSidebarButton.waitForExistence(timeout: 30))
            XCTAssertFalse(app.tabBars.firstMatch.exists)

            let hideSidebar = app.buttons["Hide sidebar"]
            XCTAssertTrue(hideSidebar.exists)
            hideSidebar.tap()

            let showSidebar = app.buttons["Show sidebar"]
            XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
            XCTAssertFalse(mapSidebarButton.exists)
            showSidebar.tap()
            XCTAssertTrue(mapSidebarButton.waitForExistence(timeout: 5))

            let passport = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Passport,"))
                .firstMatch
            XCTAssertTrue(passport.exists)
            passport.tap()
            XCTAssertTrue(app.staticTexts["Your exploration, earned"].waitForExistence(timeout: 20))
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
            XCTAssertTrue(app.tabBars.buttons["Map"].exists)
            XCTAssertTrue(app.tabBars.buttons["Passport"].exists)
        }
    }
}
