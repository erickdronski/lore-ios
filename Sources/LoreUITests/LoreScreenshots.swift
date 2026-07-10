import XCTest

/// App Store screenshot capturer, driven by `fastlane screenshots`
/// (see fastlane/Snapfile + the screenshots.yml workflow).
///
/// It launches the app with the `LORE_SCREENSHOTS` argument, which
/// `ScreenshotSupport` reads to skip first-run onboarding, then walks the tab
/// bar capturing the non-camera surfaces at App Store sizes. The AR scanner is
/// deliberately NOT shot here: the Simulator has no camera, so a real facade +
/// pin hero image can only come from a device.
final class LoreScreenshots: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["LORE_SCREENSHOTS"]

        // Auto-dismiss the location permission dialog if it appears, so the Map
        // screenshot is the app, not a system alert. Fires on the next
        // interaction after the alert shows (hence the tab tap below).
        addUIInterruptionMonitor(withDescription: "Permission dialog") { alert in
            for label in ["Allow While Using App", "Allow", "OK", "Allow Once"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()

        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 30)

        // 1. MAP — the default surface. Tap the Map tab once (harmless, we're
        //    already here) to trip the interruption monitor / dismiss any
        //    location alert, then let pins load over the network.
        tapTab(app, "Map")
        sleep(10)
        snapshot("01Map")

        // 2. TOURS — curated walking tours.
        tapTab(app, "Tours")
        sleep(6)
        snapshot("02Tours")

        // 3. PASSPORT — the collection / reward wall.
        tapTab(app, "Passport")
        sleep(5)
        snapshot("03Passport")

        // 4. PROFILE — membership + settings.
        tapTab(app, "Profile")
        sleep(4)
        snapshot("04Profile")

        // 5. PAYWALL — open the live Lore+ paywall from the membership row.
        let unlock = app.staticTexts["Unlock Lore+"]
        if unlock.waitForExistence(timeout: 6) {
            unlock.tap()
            sleep(4)
            snapshot("05Paywall")
        }
    }

    /// Tap a tab bar button by its visible label, with a short wait so a slow
    /// first render doesn't miss it.
    @MainActor
    private func tapTab(_ app: XCUIApplication, _ label: String) {
        let button = app.tabBars.buttons[label]
        if button.waitForExistence(timeout: 15) {
            button.tap()
        }
    }
}
