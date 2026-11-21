import XCTest

/// Exercises the guide shipped inside the app. Fastlane uses three points
/// along this same journey for the iPhone and iPad storefront screenshots.
final class LoreScreenshots: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOfflineStarterGuideJourney() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-lore-starter-guide"]
        app.launch()

        let home = element("starter.home", in: app)
        let chicago = element("starter.city.chicago", in: app)
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        XCTAssertTrue(chicago.waitForExistence(timeout: 5))
        snapshot("01StarterGuide", timeWaitingForIdle: 0)

        reveal(chicago, in: app)
        chicago.tap()
        let cloudGate = element("starter.place.cloud-gate", in: app)
        XCTAssertTrue(cloudGate.waitForExistence(timeout: 5))
        snapshot("02Chicago", timeWaitingForIdle: 0)

        reveal(cloudGate, in: app)
        cloudGate.tap()
        let source = element("starter.sources", in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        snapshot("03CloudGate", timeWaitingForIdle: 0)
        reveal(source, in: app)
        XCTAssertTrue(source.isEnabled)

        goBack(in: app)
        XCTAssertTrue(cloudGate.waitForExistence(timeout: 5))
        goBack(in: app)
        XCTAssertTrue(home.waitForExistence(timeout: 5))

        let search = app.textFields["starter.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Seattle")
        let seattle = element("starter.city.seattle", in: app)
        XCTAssertTrue(seattle.waitForExistence(timeout: 5))
        XCTAssertFalse(chicago.exists, "City search should exclude unrelated cities")
        seattle.tap()
        let places = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "starter.place."))
        XCTAssertTrue(places.firstMatch.waitForExistence(timeout: 5))
        goBack(in: app)

        let account = element("starter.account", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        let restore = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Restore purchases")).firstMatch
        reveal(restore, in: app)
        XCTAssertTrue(restore.isEnabled)
    }

    @MainActor
    func testSavedStarterPlaceSurvivesRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lore-starter-guide"]
        app.launch()
        let chicago = element("starter.city.chicago", in: app)
        XCTAssertTrue(chicago.waitForExistence(timeout: 15))
        reveal(chicago, in: app)
        chicago.tap()
        let cloudGate = element("starter.place.cloud-gate", in: app)
        reveal(cloudGate, in: app)
        cloudGate.tap()
        let save = app.buttons["Save place on this device"]
        reveal(save, in: app)
        save.tap()
        let saved = app.buttons["Saved on this device"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(element("starter.home", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(cloudGate.waitForExistence(timeout: 5), "A saved place should be on the home screen after relaunch")
        cloudGate.tap()
        reveal(saved, in: app)
        saved.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        goBack(in: app)
        XCTAssertTrue(chicago.waitForExistence(timeout: 5))
        XCTAssertFalse(cloudGate.exists, "Removing the saved place should remove its home shortcut")
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Small screens can place the source link or restore control below the fold.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func goBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.isHittable)
        back.tap()
    }
}
