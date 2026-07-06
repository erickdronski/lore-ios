import SwiftUI

/// Lore color tokens, 1:1 with `lore/brand/tokens/tokens.json`.
/// Core four are locked in `docs/00-DECISIONS.md` §1; change there first,
/// then propagate here.
///
/// Rules (brand/DESIGN.md §4):
/// - Semantic colors never appear in the AR viewfinder, only Amber/Ink/Bone
///   exist over camera.
/// - Brass is decorative-only on light surfaces; Brass *text* on Bone uses
///   `brass700` (≈ 4.9:1, AA).
/// - Pins are always compound: Amber fill + 1.5 pt Ink stroke + Ink shadow.
enum LoreColor {
    // MARK: Core four

    /// #0F1626, primary dark, backgrounds, text on light.
    static let ink = Color(hex: 0x0F1626)
    /// #F6F1E6, light surfaces, cards, text on dark.
    static let bone = Color(hex: 0xF6F1E6)
    /// #B98A2F, premium/badges; decorative only on light.
    static let brass = Color(hex: 0xB98A2F)
    /// #FFB454, AR pins, outlines, beacon.
    static let amber = Color(hex: 0xFFB454)

    // MARK: Ink ramp

    /// #0A0F1B, deep-dive reader bg, OLED.
    static let ink950 = Color(hex: 0x0A0F1B)
    /// #0F1626, = ink; default dark bg.
    static let ink900 = Color(hex: 0x0F1626)
    /// #1A2336, raised dark surfaces.
    static let ink800 = Color(hex: 0x1A2336)
    /// #26314A, dark borders, dividers.
    static let ink700 = Color(hex: 0x26314A)
    /// #46506B, secondary text on Bone; disabled on dark.
    static let ink600 = Color(hex: 0x46506B)

    // MARK: Bone ramp

    /// #FCFAF4, elevated light surfaces.
    static let bone50 = Color(hex: 0xFCFAF4)
    /// #F6F1E6, = bone; default light surface.
    static let bone100 = Color(hex: 0xF6F1E6)
    /// #EAE2D0, recessed light, input fills.
    static let bone200 = Color(hex: 0xEAE2D0)
    /// #D8CDB4, hairlines on light.
    static let bone300 = Color(hex: 0xD8CDB4)

    // MARK: Brass / Amber ramp

    /// #85601D, Brass text on Bone (≈ 4.9:1, AA).
    static let brass700 = Color(hex: 0x85601D)
    /// #D9B36A, Brass accents on Ink.
    static let brass300 = Color(hex: 0xD9B36A)
    /// #D98A2B, warning text on Bone; pressed Amber.
    static let amber600 = Color(hex: 0xD98A2B)

    // MARK: Semantic (never in the viewfinder)

    /// #2E7D4F, verified, accepted (on Bone).
    static let success = Color(hex: 0x2E7D4F)
    /// #5BBE85, verified, accepted (on Ink).
    static let successDark = Color(hex: 0x5BBE85)
    /// #C0453E, rejected, localization failure (on Bone).
    static let error = Color(hex: 0xC0453E)
    /// #E97A6F, rejected, localization failure (on Ink).
    static let errorDark = Color(hex: 0xE97A6F)
    /// #4E7DA6, tips, onboarding (on Bone).
    static let info = Color(hex: 0x4E7DA6)
    /// #8FB8D9, tips, onboarding (on Ink).
    static let infoDark = Color(hex: 0x8FB8D9)

    // MARK: Scrims (label pills over camera)

    /// rgb(15 22 38 / 0.72), over bright camera (luma > 0.65).
    static let scrimSky = Color(hex: 0x0F1626).opacity(0.72)
    /// rgb(15 22 38 / 0.44), over dark camera (luma < 0.30).
    static let scrimFacade = Color(hex: 0x0F1626).opacity(0.44)
}

extension Color {
    /// `Color(hex: 0x0F1626)`, sRGB, full opacity.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}
