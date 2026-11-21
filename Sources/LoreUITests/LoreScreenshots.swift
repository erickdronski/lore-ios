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
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments += ["-lore-starter-guide"]
        app.launch()

        let atlas = element("atlas.directory", in: app)
        XCTAssertTrue(atlas.waitForExistence(timeout: 15))
        capture("01Atlas")
        app.buttons["atlas.search"].tap()
        let home = element("starter.home", in: app)
        let chicago = element("starter.city.chicago", in: app)
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        XCTAssertTrue(chicago.waitForExistence(timeout: 5))
        capture("02FieldGuide")

        reveal(chicago, in: app)
        chicago.tap()
        let cloudGate = element("starter.place.cloud-gate", in: app)
        XCTAssertTrue(cloudGate.waitForExistence(timeout: 5))

        reveal(cloudGate, in: app)
        cloudGate.tap()
        let source = element("starter.sources", in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        capture("03CloudGate")
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
        let search = app.buttons["atlas.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        let chicago = element("starter.city.chicago", in: app)
        XCTAssertTrue(chicago.waitForExistence(timeout: 15))
        reveal(chicago, in: app)
        chicago.tap()
        let cloudGate = element("starter.place.cloud-gate", in: app)
        reveal(cloudGate, in: app)
        cloudGate.tap()
        let save = app.buttons["Save place on this device"]
        let saved = app.buttons["Saved on this device"]
        if saved.exists { reveal(saved, in: app); saved.tap() }
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        let saves = app.buttons["atlas.saved"]
        XCTAssertTrue(saves.waitForExistence(timeout: 15))
        saves.tap()
        XCTAssertTrue(cloudGate.waitForExistence(timeout: 5), "The saved place should survive relaunch")
        cloudGate.tap()
        reveal(saved, in: app)
        saved.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        goBack(in: app)
        XCTAssertFalse(cloudGate.exists, "Removing the saved place should remove it from Saved")
    }

    @MainActor
    private func capture(_ name: String) {
        snapshot(name, timeWaitingForIdle: 0)
        let frame = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        frame.name = name
        frame.lifetime = .keepAlways
        add(frame)
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
