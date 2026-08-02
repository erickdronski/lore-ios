import XCTest
import UIKit

/// App Store screenshot capturer, driven by `fastlane screenshots`
/// (see fastlane/Snapfile + the screenshots.yml workflow).
///
/// It launches the app with the `LORE_SCREENSHOTS` argument, which
/// `ScreenshotSupport` reads to skip first-run onboarding, then walks the tab
/// bar capturing the non-camera surfaces at App Store sizes. Two "deep"
/// surfaces are presented state rather than a tab (the sourced deep-dive
/// dossier and Meet-the-City), so the capturer relaunches with a `LORE_SHOW`
/// stage that `LoreApp` opens deterministically. The AR scanner is deliberately
/// NOT shot here: the Simulator has no camera, so a real facade + pin hero image
/// can only come from a device.
///
/// These raw captures are composed into branded, headlined marketing frames by
/// the promo-frame generator before they reach the store listing.
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
        // screenshot is the app, not a system alert. The grant persists to the
        // relaunches below, so only the first launch needs it.
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

        // ── Launch 1: the tab surfaces ──────────────────────────────────────
        app.launch()
        dismissSystemPermissionAlertIfNeeded()

        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(
                app.tabBars.firstMatch.waitForExistence(timeout: 30),
                "the compact layout should expose Lore's tab bar"
            )
        } else {
            XCTAssertTrue(
                sidebarButton(app, "Map").waitForExistence(timeout: 30),
                "the regular-width iPad layout should expose Lore's sidebar"
            )
        }

        // MAP — the default surface. Tap the Map tab once (harmless, we're
        // already here) to trip the interruption monitor / dismiss any location
        // alert, then let pins + the near-me shelf settle over the network.
        tapTab(app, "Map")
        sleep(13)
        dismissSystemPermissionAlertIfNeeded()
        snapshot("01Map")

        // TOURS — curated walking tours.
        tapTab(app, "Tours")
        sleep(6)
        snapshot("02Tours")

        // PASSPORT — the collection / reward wall.
        tapTab(app, "Passport")
        sleep(5)
        snapshot("05Passport")

        // PROFILE — the no-account promise + membership.
        tapTab(app, "Profile")
        sleep(4)
        snapshot("06Profile")

        app.terminate()

        // ── Launch 2: the deep-dive dossier (the sourced story) ─────────────
        // Replaces the paywall as the "go deep" showcase.
        app.launchEnvironment["LORE_SHOW"] = "dive"
        app.launch()
        // Cold launch → fetch Chicago places → present the card → expand the
        // dossier → load the dive narrative + hero. Give the network room.
        sleep(15)
        dismissSystemPermissionAlertIfNeeded()
        snapshot("03Dive")
        app.terminate()

        // ── Launch 3: Meet-the-City (culture: facts, faces, local lingo) ────
        app.launchEnvironment["LORE_SHOW"] = "culture"
        app.launch()
        sleep(10)
        dismissSystemPermissionAlertIfNeeded()
        snapshot("04Culture")
    }

    /// Tap a tab bar button by its visible label, with a short wait so a slow
    /// first render doesn't miss it.
    @MainActor
    private func tapTab(_ app: XCUIApplication, _ label: String) {
        let button = app.tabBars.buttons[label]
        if button.waitForExistence(timeout: 15) {
            button.tap()
            return
        }

        let sidebar = sidebarButton(app, label)
        if sidebar.waitForExistence(timeout: 15) {
            sidebar.tap()
        }
    }

    /// Sidebar buttons combine the section title and its editorial subtitle
    /// into one accessibility label, so match the stable title prefix.
    private func sidebarButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(label),"))
            .firstMatch
    }

    @MainActor
    private func dismissSystemPermissionAlertIfNeeded(timeout: TimeInterval = 2) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return }

        for label in ["Allow While Using App", "Allow", "OK", "Allow Once"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }
}
