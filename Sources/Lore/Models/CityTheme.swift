import SwiftUI

/// Row shape of the `city_theme` table: each city's signature hue system,
/// applied as a whisper over the shared Lore ink/bone/brass design system.
/// `GET /rest/v1/city_theme?city=eq.{city}&limit=1`
///
/// The accent is anchored to something REAL about the city (Kyoto: the
/// vermilion of Fushimi Inari's torii; Paris: warm Haussmann limestone) —
/// `rationale` names the anchor. The client never trusts the data blindly:
/// every color passes through a taste clamp so a bad row cannot produce a
/// garish or unreadable page.
struct CityTheme: Decodable, Equatable {
    let city: String
    let accent: String
    let accentSoft: String
    let glow: String
    let gradientTop: String
    let gradientBottom: String
    let rationale: String

    enum CodingKeys: String, CodingKey {
        case city, accent, glow, rationale
        case accentSoft = "accent_soft"
        case gradientTop = "gradient_top"
        case gradientBottom = "gradient_bottom"
    }

    // MARK: Colors (clamped)

    /// The city's signature hue, for eyebrows, small rules, and chips.
    var accentColor: Color { Self.clampedAccent(hex: accent) ?? LoreColor.brass300 }
    /// Lower-voltage companion for fills and soft borders.
    var accentSoftColor: Color { Self.clampedAccent(hex: accentSoft) ?? LoreColor.brass700 }
    /// Night-map halo tint.
    var glowColor: Color { Self.clampedAccent(hex: glow) ?? LoreColor.amber }
    /// Header wash start — forced into the dark-ink family regardless of data.
    var gradientTopColor: Color { Self.clampedInk(hex: gradientTop) ?? LoreColor.ink900 }
    /// Header wash end.
    var gradientBottomColor: Color { Self.clampedInk(hex: gradientBottom) ?? LoreColor.ink }

    // MARK: Taste clamp

    /// Parses `#RRGGBB`; returns nil on malformed input.
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// Accents must sit comfortably on near-black ink: bright enough to read,
    /// never neon. Luminance is nudged into [0.35, 0.75] and saturation is
    /// tempered by blending toward its own gray when the channel spread is
    /// extreme.
    static func clampedAccent(hex: String) -> Color? {
        guard var c = rgb(hex) else { return nil }
        let spread = max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
        if spread > 0.85 { // neon: pull 25% toward gray of same luminance
            let gray = (c.r + c.g + c.b) / 3
            c = (c.r * 0.75 + gray * 0.25, c.g * 0.75 + gray * 0.25, c.b * 0.75 + gray * 0.25)
        }
        let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        if lum < 0.35, lum > 0 { let k = 0.35 / lum; c = (min(c.r * k, 1), min(c.g * k, 1), min(c.b * k, 1)) }
        if lum > 0.75 { let k = 0.75 / lum; c = (c.r * k, c.g * k, c.b * k) }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// Header-wash colors must remain tinted INKS — near-black with a hue
    /// whisper — so bone text always passes contrast. Anything brighter is
    /// scaled down into the ink family, keeping its hue.
    static func clampedInk(hex: String) -> Color? {
        guard var c = rgb(hex) else { return nil }
        let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        let ceiling = 0.16
        if lum > ceiling, lum > 0 {
            let k = ceiling / lum
            c = (c.r * k, c.g * k, c.b * k)
        }
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}
