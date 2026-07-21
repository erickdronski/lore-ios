import UIKit
import XCTest
@testable import Lore

final class AccessibilitySemanticsTests: XCTestCase {
    func testDisplayFontScaleGrowsForAccessibilityCategories() {
        let standard = LoreType.scaledDisplayPointSize(22, category: .large)
        let accessible = LoreType.scaledDisplayPointSize(
            22,
            category: .accessibilityExtraExtraExtraLarge
        )

        XCTAssertGreaterThan(accessible, standard)
        XCTAssertEqual(LoreType.displayTextStyle(for: 40), .largeTitle)
        XCTAssertEqual(LoreType.displayTextStyle(for: 28), .title1)
        XCTAssertEqual(LoreType.displayTextStyle(for: 22), .title2)
        XCTAssertEqual(LoreType.displayTextStyle(for: 17), .body)
    }

    func testPaywallCellsNameTierAndAvailability() {
        XCTAssertEqual(
            FeatureComparison.Cell.yes.accessibilityLabel(for: .free),
            "Free: Included"
        )
        XCTAssertEqual(
            FeatureComparison.Cell.no.accessibilityLabel(for: .lorePlus),
            "Lore Plus: Not included"
        )
        XCTAssertEqual(
            FeatureComparison.Cell.text("3/day").accessibilityLabel(for: .free),
            "Free: 3 per day"
        )
    }

    func testDealLabelIncludesEveryVisibleDecisionDetail() {
        let label = DealAccessibility.label(
            title: "Architecture river cruise",
            sourceLabel: "via Example",
            originalPrice: "$80",
            currentPrice: "$60",
            discount: "25% off",
            matchNote: "Includes admission to this place",
            checkedLabel: "checked Jul 21, 2026"
        )

        XCTAssertTrue(label.contains("Original price $80"))
        XCTAssertTrue(label.contains("Current price $60"))
        XCTAssertTrue(label.contains("Discount 25% off"))
        XCTAssertTrue(label.contains("Why it matches: Includes admission to this place"))
        XCTAssertTrue(label.contains("checked Jul 21, 2026"))
        XCTAssertTrue(label.contains("Opens in browser"))
        XCTAssertTrue(DealAccessibility.commissionDisclosure.contains("commission"))
        XCTAssertTrue(DealAccessibility.commissionDisclosure.contains("no extra cost"))
    }

    func testFlavorOnlyCultureCountsAsContent() {
        XCTAssertTrue(
            CultureModel.hasContent(cultureCount: 0, factCount: 0, flavorCount: 1)
        )
        XCTAssertFalse(
            CultureModel.hasContent(cultureCount: 0, factCount: 0, flavorCount: 0)
        )
    }

    func testContinentStateIsExpressedWithoutColor() {
        XCTAssertEqual(
            ExplorerStatsView.continentAccessibilityValue(visited: true),
            "Visited"
        )
        XCTAssertEqual(
            ExplorerStatsView.continentAccessibilityValue(visited: false),
            "Not visited"
        )
    }
}
