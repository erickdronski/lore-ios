import SwiftUI
import XCTest
@testable import Lore

final class LoreSpecialistLaneTests: XCTestCase {
    @MainActor
    func testJournalImageProcessorDownscalesByPixelDimension() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        let png = try XCTUnwrap(source.pngData())

        let processed = await JournalImageProcessor.preparedJPEG(
            png,
            maxDimension: 100,
            quality: 0.75
        )
        let jpeg = try XCTUnwrap(processed)
        let result = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)

        XCTAssertEqual(result.width, 100)
        XCTAssertEqual(result.height, 50)
        XCTAssertLessThan(jpeg.count, png.count)
    }

    func testJournalDraftNormalizesWhitespace() {
        XCTAssertEqual(JournalDraftPolicy.normalized("  A quiet courtyard.\n"), "A quiet courtyard.")
    }

    func testJournalDraftAllowsClearingAPrivateNote() {
        XCTAssertNil(JournalDraftPolicy.validationMessage(text: "  \n"))
    }

    func testJournalDraftEnforcesBoundedNotes() {
        let accepted = String(repeating: "a", count: JournalDraftPolicy.maximumCharacters)
        let rejected = accepted + "b"

        XCTAssertNil(JournalDraftPolicy.validationMessage(text: accepted))
        XCTAssertNotNil(JournalDraftPolicy.validationMessage(text: rejected))
    }

    func testUserStatsIgnoresLegacyPublicLoreCount() throws {
        let payload = """
        {
          "places": 2,
          "cities": 1,
          "countries": 1,
          "continents": 1,
          "continents_list": ["Europe"],
          "dives_read": 3,
          "notes": 1,
          "photos": 2,
          "public_lores": 99,
          "scanner_visits": 1,
          "badges": 1,
          "badges_total": 12,
          "insight_points": 8,
          "current_streak": 2,
          "longest_streak": 4,
          "top_categories": [],
          "first_visit": null
        }
        """

        let stats = try JSONDecoder().decode(UserStats.self, from: Data(payload.utf8))

        XCTAssertEqual(stats.places, 2)
        XCTAssertEqual(stats.scannerVisits, 1)
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

    func testSignedOutPassportDoesNotExposePersonalProgress() {
        XCTAssertFalse(PassportProgressState.signedOut.showsPersonalProgress)
        XCTAssertEqual(PassportProgressState.signedOut.badgeTrackingMode, .catalog)
        XCTAssertTrue(PassportProgressState.available.showsPersonalProgress)
        XCTAssertEqual(PassportProgressState.available.badgeTrackingMode, .personal)
        XCTAssertFalse(PassportProgressState.unavailable.showsPersonalProgress)
        XCTAssertEqual(PassportProgressState.unavailable.badgeTrackingMode, .syncUnavailable)
    }

    func testPassportSectionsCollapseLargeCatalogsWithoutDroppingBadges() throws {
        let badges = try (0..<8).map { index in
            PassportBadge(
                achievement: try achievement(slug: "badge-\(index)", sort: index),
                progress: nil
            )
        }
        let section = PassportSection(category: "knowledge", badges: badges)

        XCTAssertEqual(section.visibleBadges(isExpanded: false).count, PassportSection.collapsedBadgeLimit)
        XCTAssertEqual(section.visibleBadges(isExpanded: true).count, badges.count)
        XCTAssertEqual(section.visibleBadges(isExpanded: true).map(\.id), badges.map(\.id))
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
