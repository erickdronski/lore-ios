import CoreLocation
import XCTest

final class OfflineExploreUITests: XCTestCase {
    @MainActor
    func testDeniedLocationStillOpensCityMapAndLocalPlace() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments += ["-lore-starter-guide"]
        app.launch()

        let landmarkFinder = app.buttons["guide.finder"]
        XCTAssertTrue(landmarkFinder.waitForExistence(timeout: 15))
        landmarkFinder.tap()
        let start = app.buttons["atlas.finder.enable"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = system.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 12))
        deny.tap()
        XCTAssertTrue(app.staticTexts["Location access is off"].waitForExistence(timeout: 10))
        app.buttons["Browse the city map"].tap()
        let directory = app.buttons["atlas.directory"]
        XCTAssertTrue(directory.waitForExistence(timeout: 10))
        directory.tap()
        let place = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "atlas.place.")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 8))
        place.tap()
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save place on this device", "Saved on this device"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
    }

    @MainActor
    func testCurrentLocationRecentersOnLaunchAndSupportsUncoveredAreas() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments += ["-lore-starter-guide"]
        let device = XCUIDevice.shared
        let chicago = CLLocation(latitude: 41.8827, longitude: -87.6233)
        device.location = XCUILocation(location: chicago)
        defer { device.location = nil }
        app.launch()
        let locate = app.buttons["atlas.locate"]
        XCTAssertTrue(locate.waitForExistence(timeout: 15))
        locate.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = system.alerts.buttons["Allow While Using App"]
        XCTAssertTrue(allow.waitForExistence(timeout: 12))
        allow.tap()
        let area = app.buttons["atlas.directory"]
        let nearby = NSPredicate(format: "label CONTAINS %@", "Around you")
        expectation(for: nearby, evaluatedWith: area)
        waitForExpectations(timeout: 20)
        area.tap()
        let cloud = app.buttons["atlas.place.cloud-gate"]
        XCTAssertTrue(cloud.waitForExistence(timeout: 8))
        app.buttons["Done"].tap()

        app.terminate()
        device.location = XCUILocation(location: CLLocation(latitude: 64.1466, longitude: -21.9426))
        app.launch()
        let apple = app.buttons["Search Apple Maps nearby"]
        XCTAssertTrue(apple.waitForExistence(timeout: 20))
        XCTAssertTrue(nearby.evaluate(with: app.buttons["atlas.directory"]))
        XCTAssertTrue(apple.isEnabled)
        apple.tap()
        let result = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
            "places from Apple Maps", "Apple Maps found no places", "Apple Maps search is unavailable"
        )).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30))
    }

    @MainActor
    func testVisibleMapPinOpensBundledDetail() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments += ["-lore-starter-guide"]
        app.launch()
        XCTAssertTrue(app.buttons["atlas.directory"].waitForExistence(timeout: 15))
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        let pin = map.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Tribune Tower")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10), map.debugDescription)
        pin.tap()
        let selected = app.buttons["atlas.selectedPlace"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        selected.tap()
        let directions = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@", "Walking directions in Maps")).firstMatch
        XCTAssertTrue(directions.waitForExistence(timeout: 8))
    }

    @MainActor
    func testWalkResumesAtCloudGateAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-lore-starter-guide"]
        app.launch()
        let walks = app.buttons["atlas.walks"]
        let route = app.buttons["walks.route.millennium-moments"]
        func openWalk() {
            XCTAssertTrue(walks.waitForExistence(timeout: 15))
            walks.tap()
            for _ in 0..<3 where !route.isHittable { app.swipeUp() }
            XCTAssertTrue(route.isHittable)
            route.tap()
        }
        openWalk()
        let current = app.staticTexts["walks.stopTitle"]
        let previous = app.buttons["Previous stop"]
        for _ in 0..<3 where current.exists && current.label != "Marina City" {
            for _ in 0..<3 where !previous.isHittable { app.swipeUp() }
            previous.tap()
        }
        XCTAssertEqual(current.label, "Marina City")
        let next = app.buttons["walks.next"]
        for _ in 0..<3 where !next.isHittable { app.swipeUp() }
        next.tap()
        XCTAssertEqual(current.label, "Cloud Gate")
        app.terminate()
        app.launch()
        openWalk()
        XCTAssertTrue(current.waitForExistence(timeout: 8))
        XCTAssertEqual(current.label, "Cloud Gate")
    }
}
