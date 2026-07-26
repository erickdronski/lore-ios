import SwiftUI
import XCTest
@testable import Lore

final class LoreSpecialistLaneTests: XCTestCase {
    func testJournalDraftNormalizesWhitespace() {
        XCTAssertEqual(JournalDraftPolicy.normalized("  A quiet courtyard.\n"), "A quiet courtyard.")
    }

    func testJournalDraftRequiresTextBeforePublicSharing() {
        XCTAssertNotNil(JournalDraftPolicy.validationMessage(text: "  \n", wantsToShare: true))
        XCTAssertNil(JournalDraftPolicy.validationMessage(text: "  \n", wantsToShare: false))
    }

    func testJournalDraftEnforcesBoundedNotes() {
        let accepted = String(repeating: "a", count: JournalDraftPolicy.maximumCharacters)
        let rejected = accepted + "b"

        XCTAssertNil(JournalDraftPolicy.validationMessage(text: accepted, wantsToShare: false))
        XCTAssertNotNil(JournalDraftPolicy.validationMessage(text: rejected, wantsToShare: false))
    }

    func testMilestoneSelectorPrefersMeaningfulInProgressBadge() throws {
        let untouched = try achievement(slug: "untouched", sort: 1)
        let progressing = try achievement(slug: "progressing", sort: 3)
        let secret = try achievement(slug: "secret", secret: true, sort: 2)
        let unlocked = try achievement(slug: "unlocked", sort: 0)

        let section = PassportSection(category: "milestone", badges: [
            PassportBadge(achievement: untouched, progress: nil),
            PassportBadge(
                achievement: progressing,
                progress: UserAchievement(
                    userID: "traveler",
                    achievementSlug: progressing.slug,
                    progress: 4,
                    target: 10
                )
            ),
            PassportBadge(
                achievement: secret,
                progress: UserAchievement(
                    userID: "traveler",
                    achievementSlug: secret.slug,
                    progress: 9,
                    target: 10
                )
            ),
            PassportBadge(
                achievement: unlocked,
                progress: UserAchievement(
                    userID: "traveler",
                    achievementSlug: unlocked.slug,
                    progress: 1,
                    target: 1,
                    unlockedAt: "2026-07-26T12:00:00Z"
                )
            ),
        ])

        XCTAssertEqual(PassportMilestoneSelector.next(from: [section])?.id, "progressing")
    }

    func testMilestoneSelectorUsesEditorialOrderWhenNothingStarted() throws {
        let later = try achievement(slug: "later", sort: 20)
        let first = try achievement(slug: "first", sort: 10)
        let section = PassportSection(category: "knowledge", badges: [
            PassportBadge(achievement: later, progress: nil),
            PassportBadge(achievement: first, progress: nil),
        ])

        XCTAssertEqual(PassportMilestoneSelector.next(from: [section])?.id, "first")
    }

    func testWikipediaSummaryURLTreatsTitleAsOnePathSegment() {
        let url = WikipediaService.summaryURL(for: "Jean/Luc Picard")

        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("Jean%2FLuc%20Picard") == true)
    }

    @MainActor
    func testShareRendererRejectsUnsafeDimensionsAndScale() {
        XCTAssertNil(ShareCardRenderer.image(Color.red, size: .zero))
        XCTAssertNil(ShareCardRenderer.image(Color.red, size: CGSize(width: 10, height: 10), scale: 5))
        XCTAssertNotNil(ShareCardRenderer.image(Color.red, size: CGSize(width: 10, height: 10), scale: 1))
    }

    private func achievement(
        slug: String,
        secret: Bool = false,
        sort: Int
    ) throws -> Achievement {
        let object: [String: Any] = [
            "slug": slug,
            "name": slug.capitalized,
            "description": "Complete the requirement",
            "tier": "bronze",
            "criteria": ["type": "visit_count", "n": 10],
            "points": 10,
            "secret": secret,
            "sort": sort,
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Achievement.self, from: data)
    }
}
