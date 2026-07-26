import Foundation
import Testing
@testable import Lore

@Suite("City section provenance")
struct CitySectionTests {
    @Test("HTTP sources become source links")
    func validSourceURL() throws {
        let section = try decode(source: "https://example.org/city-guide")

        #expect(section.sourceURL?.absoluteString == "https://example.org/city-guide")
        #expect(section.provenanceState == "reviewed")
        #expect(section.spokenPhrase == "Bonjour")
        #expect(section.meta?.language == "French")
    }

    @Test("Internal editorial markers stay hidden")
    func internalSourceMarker() throws {
        let section = try decode(source: "editorial:lore-wave-21")

        #expect(section.sourceURL == nil)
    }

    private func decode(source: String) throws -> CitySection {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "city": "paris",
          "kind": "phrase",
          "title": "Bonjour",
          "body": "Hello. A polite greeting for most everyday encounters.",
          "attribution": "bohn-ZHOOR",
          "emoji": "wave",
          "place_id": null,
          "source": "\(source)",
          "provenance_state": "reviewed",
          "sort": 120,
          "meta": {
            "language": "French",
            "original_script": "Bonjour"
          }
        }
        """
        return try JSONDecoder().decode(CitySection.self, from: Data(json.utf8))
    }
}
