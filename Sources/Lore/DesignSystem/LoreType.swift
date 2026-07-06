import SwiftUI
import UIKit

/// Lore type scale, 1:1 with `lore/brand/tokens/tokens.json` §type.
///
/// Doctrine (brand/DESIGN.md §5): **Fraunces = the world's words; SF Pro = the
/// app's words; never UI chrome in Fraunces.** The Fraunces variable font is
/// not bundled at P0 (brand/fonts/README.md), every display style is
/// *Fraunces-ready*: it uses the custom face when the family is registered in
/// the bundle, and falls back to the system serif design (New York) so the
/// hierarchy reads correctly today. Drop `Fraunces[SOFT,WONK,opsz,wght].ttf`
/// into a bundled fonts group + `UIAppFonts` and these helpers pick it up.
enum LoreType {
    /// PostScript family name the bundled Fraunces registers as.
    static let frauncesFamily = "Fraunces"

    /// True when the Fraunces face is available at runtime.
    static var frauncesAvailable: Bool {
        UIFont(name: frauncesFamily, size: 17) != nil
    }

    /// A display (serif) font: Fraunces when bundled, New York otherwise.
    static func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if frauncesAvailable {
            return .custom(frauncesFamily, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    // MARK: Scale

    /// 40/44 semibold, deep-dive place name.
    static var displayXL: Font { display(size: 40, weight: .semibold) }
    /// 28/34 semibold, Layer-1 card place name.
    static var displayL: Font { display(size: 28, weight: .semibold) }
    /// 22/28 medium, section heads, tour titles.
    static var displayM: Font { display(size: 22, weight: .medium) }
    /// 17/24 medium italic, the Layer-1 hook line.
    static var hook: Font { display(size: 17, weight: .medium).italic() }
    /// 17/24 regular SF Pro, UI copy, forms, settings.
    static var body: Font { .system(size: 17, weight: .regular) }
    /// 13/18 regular SF Pro, provenance, timestamps, distances, meters.
    static var caption: Font { .system(size: 13, weight: .regular) }
    /// 12/16 semibold SF Pro, tracked, badges (SCOUT, CURATOR), chips.
    /// Apply `.tracking(0.6)` at the call site (tracking is a Text modifier).
    static var label: Font { .system(size: 12, weight: .semibold) }
    /// 17–21 New York, Dynamic Type, deep-dive long-form body only.
    static var reader: Font { .system(size: 19, weight: .regular, design: .serif) }
    /// 15 semibold SF Pro, buttons, chips (`type.label`, 02-PRODUCT §6.1).
    static var button: Font { .system(size: 15, weight: .semibold) }
    /// 11 SF Pro, pin labels in-world only (`type.micro`).
    static var micro: Font { .system(size: 11, weight: .medium) }
}

extension Text {
    /// Badge/chip style: `label` token with its +0.6 tracking baked in.
    func loreLabelStyle() -> Text {
        self.font(LoreType.label).tracking(0.6)
    }
}
