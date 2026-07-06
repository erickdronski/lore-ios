import SwiftUI

/// The Lore brand palette, **duplicated deliberately** for the widget/Live-Activity
/// extension. The app's full `LoreColor` (in the `Lore` target's DesignSystem)
/// pulls in the whole design system; a widget extension wants only the four core
/// tokens, so `LoreBrand` is a minimal, self-contained copy compiled into both
/// the app and the extension via the shared `Sources/Shared` group.
///
/// Core four are locked in `docs/00-DECISIONS.md` §1, keep these hexes in lock-
/// step with `LoreColor`/`tokens.json` (change the decision doc first).
///
/// Widget rule (docs/16-APPLE-TOOLKITS.md §7): the widget reuses the Amber pin +
/// Ink surface language of the app so it reads as Lore at a glance.
public enum LoreBrand {
    /// #0F1626, primary dark, widget backgrounds.
    public static let ink = Color(loreHex: 0x0F1626)
    /// #0A0F1B, deep OLED ink for widget gradients.
    public static let ink950 = Color(loreHex: 0x0A0F1B)
    /// #1A2336, raised dark surface.
    public static let ink800 = Color(loreHex: 0x1A2336)
    /// #46506B, secondary text on ink.
    public static let ink600 = Color(loreHex: 0x46506B)
    /// #F6F1E6, light text on dark / bone surfaces.
    public static let bone = Color(loreHex: 0xF6F1E6)
    /// #FFB454, AR pins, outlines, beacon, the world's accent.
    public static let amber = Color(loreHex: 0xFFB454)
    /// #D9B36A, brass accent on ink (badges/labels).
    public static let brass300 = Color(loreHex: 0xD9B36A)
}

extension Color {
    /// `Color(loreHex: 0x0F1626)`, sRGB, full opacity. Named to avoid clashing
    /// with the app target's `Color(hex:)` when both compile the shared file.
    public init(loreHex: UInt32) {
        let red = Double((loreHex >> 16) & 0xFF) / 255.0
        let green = Double((loreHex >> 8) & 0xFF) / 255.0
        let blue = Double(loreHex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}
