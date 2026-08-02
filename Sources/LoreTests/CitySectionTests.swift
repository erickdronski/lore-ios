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

    @Test("Watch rows expose a single curated external action")
    func watchActionUsesVideoLinkWithoutRepeatingSource() throws {
        let section = try decode(
            kind: "watch",
            title: "Ten minutes in the city",
            links: """
            {
              "youtube_url": "https://www.youtube.com/watch?v=abc123"
            }
            """,
            meta: """
            {
              "platform": "YouTube",
              "duration": "8 min",
              "creator": "Local historian"
            }
            """,
            source: "https://www.youtube.com/watch?v=abc123"
        )

        #expect(section.primaryExternalURL?.absoluteString == "https://www.youtube.com/watch?v=abc123")
        #expect(section.primaryExternalAction?.label == "Watch YouTube")
        #expect(section.contextChips == ["YouTube", "8 min", "Local historian"])
        #expect(section.sourceDisclosureURL == nil)
    }

    @Test("Hashtag rows prefer the hashtag link but retain a separate source")
    func hashtagActionKeepsSeparateCitation() throws {
        let section = try decode(
            kind: "hashtag",
            title: "#HiddenRome",
            links: """
            {
              "hashtag_url": "https://www.tiktok.com/tag/hiddenrome"
            }
            """,
            meta: """
            {
              "hashtag": "#HiddenRome"
            }
            """,
            source: "https://www.rome.net"
        )

        #expect(section.primaryExternalURL?.absoluteString == "https://www.tiktok.com/tag/hiddenrome")
        #expect(section.primaryExternalAction?.label == "Open hashtag")
        #expect(section.sourceDisclosureURL?.absoluteString == "https://www.rome.net")
    }

    @Test("Non-HTTPS city section links are ignored")
    func rejectsNonHTTPSExternalLinks() throws {
        let section = try decode(
            kind: "watch",
            links: """
            {
              "video_url": "http://example.org/video"
            }
            """,
            source: "http://example.org/source"
        )

        #expect(section.primaryExternalURL == nil)
        #expect(section.sourceURL == nil)
    }

    @Test("Rich city section kinds have stable editorial ordering")
    func richSectionOrdering() {
        #expect(SectionKindMeta.order(for: "watch") < SectionKindMeta.order(for: "dish"))
        #expect(SectionKindMeta.order(for: "hashtag") < SectionKindMeta.order(for: "dish"))
        #expect(SectionKindMeta.order(for: "local_legend") < SectionKindMeta.order(for: "number"))
        #expect(SectionKindMeta.header(for: "photo_prompt").title == "Photo Field Prompts")
    }

    private func decode(source: String) throws -> CitySection {
        try decode(kind: "phrase", title: "Bonjour", links: "{}", meta: """
        {
          "language": "French",
          "original_script": "Bonjour"
        }
        """, source: source)
    }

    private func decode(
        kind: String,
        title: String = "Bonjour",
        links: String = "{}",
        meta: String = "{}",
        source: String
    ) throws -> CitySection {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "city": "paris",
          "kind": "\(kind)",
          "title": "\(title)",
          "body": "Hello. A polite greeting for most everyday encounters.",
          "attribution": "bohn-ZHOOR",
          "emoji": "wave",
          "place_id": null,
          "source": "\(source)",
          "provenance_state": "reviewed",
          "sort": 120,
          "links": \(links),
          "meta": \(meta)
        }
        """
        return try JSONDecoder().decode(CitySection.self, from: Data(json.utf8))
    }
}
