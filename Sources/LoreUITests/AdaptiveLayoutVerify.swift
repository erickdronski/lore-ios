import UIKit
import XCTest

/// Guards the universal shell itself. Screenshot coverage exercises the rich
/// surfaces; this test makes the compact/regular navigation contract explicit.
final class AdaptiveLayoutVerify: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNavigationMatchesTheDeviceCanvas() throws {
        let app = launchApp(stage: "passport")

        if UIDevice.current.userInterfaceIdiom == .pad {
            let mapSidebarButton = sidebarButton(app, "Map")
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
            XCTAssertTrue(app.staticTexts["Begin your field record"].waitForExistence(timeout: 20))
            attachPassportScreenshot(named: "passport-signed-out-ipad")
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
            XCTAssertTrue(app.tabBars.buttons["Map"].exists)
            XCTAssertTrue(app.tabBars.buttons["Passport"].exists)
            XCTAssertTrue(app.staticTexts["Begin your field record"].waitForExistence(timeout: 20))
            attachPassportScreenshot(named: "passport-signed-out-iphone")
        }
    }

    private func attachPassportScreenshot(named name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        shot.name = name
        add(shot)
    }

    /// Exercises Lore as a traveler rather than treating launch as success:
    /// browse the primary surfaces, open the journal, filter the city roster,
    /// and persist then remove a planned trip.
    @MainActor
    func testPrimaryTravelerJourneyRemainsReachable() throws {
        let app = launchApp()

        XCTAssertTrue(currentCityButton(app).waitForExistence(timeout: 35))

        selectDestination(app, "Tours")
        XCTAssertTrue(app.staticTexts["Build a city walk"].waitForExistence(timeout: 25))
        XCTAssertTrue(currentCityButton(app).exists)

        selectDestination(app, "Passport")
        XCTAssertTrue(app.staticTexts["Begin your field record"].waitForExistence(timeout: 25))

        let journal = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Your Journal"))
            .firstMatch
        XCTAssertTrue(journal.waitForExistence(timeout: 10))
        if !journal.isHittable {
            app.swipeUp()
        }
        journal.tap()
        XCTAssertTrue(app.staticTexts["Journal"].waitForExistence(timeout: 10))

        selectDestination(app, "Profile")
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Every place has a story."].exists)

        selectDestination(app, "Map")
        let cityButton = currentCityButton(app)
        XCTAssertTrue(cityButton.waitForExistence(timeout: 20))
        cityButton.tap()

        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 20))
        for filter in ["All", "Planning", "US", "Europe", "Asia"] {
            XCTAssertTrue(app.buttons[filter].exists, "\(filter) city filter should be reachable")
        }

        app.buttons["Europe"].tap()
        let pinButton = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Pin ", " for trip planning"))
            .firstMatch
        XCTAssertTrue(pinButton.waitForExistence(timeout: 20))

        let cityName = pinButton.label
            .replacingOccurrences(of: "Pin ", with: "")
            .replacingOccurrences(of: " for trip planning", with: "")
        pinButton.tap()

        let removeButton = app.buttons["Remove \(cityName) from trip planning"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5))
        app.buttons["Planning"].tap()
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5))

        // Leave the simulator clean so fleet order never changes the result.
        removeButton.tap()
        XCTAssertTrue(app.staticTexts["No trips pinned yet"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(currentCityButton(app).waitForExistence(timeout: 10))
    }

    @MainActor
    func testAccessibilityTextSizeKeepsPrimaryNavigationReachable() throws {
        let app = launchApp(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )

        if UIDevice.current.userInterfaceIdiom == .pad {
            for destination in ["Map", "Scanner", "Tours", "Passport", "Profile"] {
                let button = sidebarButton(app, destination)
                XCTAssertTrue(button.waitForExistence(timeout: 30))
                XCTAssertTrue(button.isHittable, "\(destination) should remain tappable at accessibility text sizes")
            }
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
            for destination in ["Map", "Scanner", "Tours", "Passport", "Profile"] {
                let button = app.tabBars.buttons[destination]
                XCTAssertTrue(button.exists)
                XCTAssertTrue(button.isHittable, "\(destination) should remain tappable at accessibility text sizes")
            }
        }

        selectDestination(app, "Profile")
        XCTAssertTrue(app.staticTexts["Profile"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testIPadLandscapeKeepsSidebarAndPlanningReachable() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPhone is intentionally portrait-only")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp()
        XCTAssertTrue(sidebarButton(app, "Map").waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Hide sidebar"].isHittable)

        let cityButton = currentCityButton(app)
        XCTAssertTrue(cityButton.waitForExistence(timeout: 20))
        cityButton.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Planning"].isHittable)
        XCTAssertTrue(app.buttons["Europe"].isHittable)
        XCTAssertTrue(app.buttons["Asia"].isHittable)
        app.buttons["Close"].tap()

        app.buttons["Hide sidebar"].tap()
        XCTAssertTrue(app.buttons["Show sidebar"].waitForExistence(timeout: 5))
        app.buttons["Show sidebar"].tap()
        XCTAssertTrue(sidebarButton(app, "Map").waitForExistence(timeout: 5))
    }

    /// The Simulator cannot prove live camera or AR alignment, but it can prove
    /// every recoverable scanner entry state remains readable and actionable
    /// on the iPad landscape canvas where orientation regressions occurred.
    @MainActor
    func testIPadLandscapeScannerFallbackRemainsActionable() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad landscape scanner coverage")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchApp()
        selectDestination(app, "Scanner")

        let stateTitles = app.staticTexts.matching(NSPredicate(
            format: "label IN %@",
            [
                "Reveal the stories around you",
                "The scanner needs camera access",
                "The scanner needs your location",
                "Turn on Precise Location",
                "Live scanner unavailable",
            ]
        ))
        XCTAssertTrue(
            stateTitles.firstMatch.waitForExistence(timeout: 30),
            "Scanner should expose a truthful permission or hardware state"
        )

        let recoveryActions = app.buttons.matching(NSPredicate(
            format: "label IN %@",
            ["Continue", "Open Settings", "Use Precise Location", "Try camera again"]
        ))
        XCTAssertTrue(recoveryActions.firstMatch.exists)
        XCTAssertTrue(recoveryActions.firstMatch.isHittable)
    }

    @MainActor
    private func launchApp(
        contentSizeCategory: String = "UICTContentSizeCategoryLarge",
        stage: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // The preferred category is a persistent app default. Set it on every
        // launch so an accessibility run cannot contaminate later fleet tests.
        app.launchArguments += [
            "LORE_SCREENSHOTS",
            "-UIPreferredContentSizeCategoryName",
            contentSizeCategory,
        ]
        if let stage { app.launchEnvironment["LORE_SHOW"] = stage }
        app.launch()
        return app
    }

    @MainActor
    private func selectDestination(_ app: XCUIApplication, _ label: String) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let button = sidebarButton(app, label)
            XCTAssertTrue(button.waitForExistence(timeout: 20))
            button.tap()
        } else {
            let button = app.tabBars.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 20))
            button.tap()
        }
    }

    private func sidebarButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(label),"))
            .firstMatch
    }

    private func currentCityButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Current city, "))
            .firstMatch
    }
}
