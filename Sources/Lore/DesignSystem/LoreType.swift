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

    /// A Dynamic Type-aware display font: Fraunces when bundled, New York
    /// otherwise. `UIFontMetrics` preserves the token's intended default size
    /// while allowing every display use to follow the user's text-size choice.
    static func display(
        size: CGFloat,
        weight: Font.Weight = .semibold,
        relativeTo textStyle: UIFont.TextStyle? = nil
    ) -> Font {
        let style = textStyle ?? displayTextStyle(for: size)
        let baseFont: UIFont

        if let fraunces = UIFont(name: frauncesFamily, size: size) {
            baseFont = fraunces
        } else {
            let system = UIFont.systemFont(ofSize: size)
            let descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
            baseFont = UIFont(descriptor: descriptor, size: size)
        }

        let scaled = UIFontMetrics(forTextStyle: style).scaledFont(for: baseFont)
        return Font(scaled).weight(weight)
    }

    /// Semantic scaling bucket for an arbitrary display token.
    static func displayTextStyle(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case 34...: return .largeTitle
        case 28..<34: return .title1
        case 22..<28: return .title2
        case 20..<22: return .title3
        case 17..<20: return .body
        case 14..<17: return .callout
        case 13..<14: return .footnote
        default: return .caption2
        }
    }

    /// Deterministic scaling hook used by focused accessibility tests.
    static func scaledDisplayPointSize(
        _ size: CGFloat,
        relativeTo textStyle: UIFont.TextStyle? = nil,
        category: UIContentSizeCategory
    ) -> CGFloat {
        let style = textStyle ?? displayTextStyle(for: size)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        return UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits)
    }

    // MARK: Scale

    /// 40/44 semibold, deep-dive place name.
    static var displayXL: Font { display(size: 40, weight: .semibold, relativeTo: .largeTitle) }
    /// 28/34 semibold, Layer-1 card place name.
    static var displayL: Font { display(size: 28, weight: .semibold, relativeTo: .title1) }
    /// 22/28 medium, section heads, tour titles.
    static var displayM: Font { display(size: 22, weight: .medium, relativeTo: .title2) }
    /// 17/24 medium italic, the Layer-1 hook line.
    static var hook: Font { display(size: 17, weight: .medium, relativeTo: .body).italic() }
    /// 17/24 regular SF Pro, UI copy, forms, settings.
    static var body: Font { .body }
    /// 13/18 regular SF Pro, provenance, timestamps, distances, meters.
    static var caption: Font { .caption }
    /// 12/16 semibold SF Pro, tracked, badges (SCOUT, CURATOR), chips.
    /// Apply `.tracking(0.6)` at the call site (tracking is a Text modifier).
    static var label: Font { .caption.weight(.semibold) }
    /// 17–21 New York, Dynamic Type, deep-dive long-form body only.
    static var reader: Font { .system(.body, design: .serif) }
    /// 15 semibold SF Pro, buttons, chips (`type.label`, 02-PRODUCT §6.1).
    static var button: Font { .callout.weight(.semibold) }
    /// 11 SF Pro, pin labels in-world only (`type.micro`).
    static var micro: Font { .caption2.weight(.medium) }
}

extension Text {
    /// Badge/chip style: `label` token with its +0.6 tracking baked in.
    func loreLabelStyle() -> Text {
        self.font(LoreType.label).tracking(0.6)
    }
}
