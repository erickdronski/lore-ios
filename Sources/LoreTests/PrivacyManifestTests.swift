import Foundation
import XCTest

final class PrivacyManifestTests: XCTestCase {
    private let appFunctionality = "NSPrivacyCollectedDataTypePurposeAppFunctionality"
    private let productPersonalization = "NSPrivacyCollectedDataTypePurposeProductPersonalization"

    func testFirstPartyCollectedDataDeclarationsMatchShippingFlows() throws {
        let manifest = try loadAppPrivacyManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)

        let declarations = try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        )
        let keyed = try Dictionary(uniqueKeysWithValues: declarations.map { declaration in
            (try XCTUnwrap(declaration["NSPrivacyCollectedDataType"] as? String), declaration)
        })

        let expectedTypes: Set<String> = [
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypePurchaseHistory",
            "NSPrivacyCollectedDataTypeOtherUserContent",
            "NSPrivacyCollectedDataTypePhotosorVideos",
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypeCoarseLocation",
        ]
        XCTAssertEqual(Set(keyed.keys), expectedTypes)

        for declaration in keyed.values {
            XCTAssertEqual(declaration["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
            XCTAssertEqual(declaration["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        }

        let personalizedTypes = [
            "NSPrivacyCollectedDataTypeOtherUserContent",
            "NSPrivacyCollectedDataTypeCoarseLocation",
        ]
        for type in personalizedTypes {
            XCTAssertEqual(
                try purposes(for: type, in: keyed),
                [appFunctionality, productPersonalization]
            )
        }

        for type in expectedTypes.subtracting(personalizedTypes) {
            XCTAssertEqual(try purposes(for: type, in: keyed), [appFunctionality])
        }
    }

    private func purposes(
        for type: String,
        in declarations: [String: [String: Any]]
    ) throws -> Set<String> {
        let declaration = try XCTUnwrap(declarations[type])
        return Set(try XCTUnwrap(declaration["NSPrivacyCollectedDataTypePurposes"] as? [String]))
    }

    private func loadAppPrivacyManifest() throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("Lore")
            .appendingPathComponent("PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }
}
