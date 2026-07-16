import XCTest

/// Regression check for the PlaceCard's "your lore" wiring: the layer-1 card
/// must carry the visit toggle (the entry point to logging a visit + writing
/// your own lore on the place). Signed out, the toggle reads "I've been here"
/// and the YOUR LORE box stays hidden — the signed-in visited state renders the
/// note + photos (store-conditioned, exercised by unit-level state).
final class CardLoreVerify: XCTestCase {

    @MainActor
    func testPlaceCardShowsVisitToggle() throws {
        let app = XCUIApplication()
        app.launchArguments += ["LORE_SCREENSHOTS"]
        app.launchEnvironment["LORE_SHOW"] = "card"
        app.launch()

        // The card stage routes a Chicago place once the network returns.
        let card = app.staticTexts["Willis Tower"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "place card should open")

        // The visit toggle now lives on the card itself (matched by its
        // accessibility label — VisitToggle overrides the visible text).
        // Swipe until it scrolls into the hittable area: the first swipe grows
        // the sheet to .large, the rest scroll the card content.
        let toggle = app.buttons["Mark Willis Tower as visited"]
        var found = false
        for _ in 0..<5 {
            if toggle.exists && toggle.isHittable { found = true; break }
            app.swipeUp()
        }
        XCTAssertTrue(found || toggle.waitForExistence(timeout: 5),
                      "the card must offer 'I've been here' (visit + your-lore entry point)")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        shot.name = "card-visit-toggle"
        add(shot)
    }
}
