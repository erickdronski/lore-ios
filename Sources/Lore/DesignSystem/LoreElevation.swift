import SwiftUI

/// Depth tokens (brand/LUXURY-MOTION.md §4) — the elevation scale that lets
/// surfaces sit *in space* rather than lying flat. Shadows are **Ink-tinted,
/// never pure black** (the doctrine's hard rule): a shadow of `#000` reads as a
/// cheap drop-shadow; a shadow tinted toward Ink #0F1626 reads as the room's
/// own dusk light falling behind the surface.
///
/// | Level  | Surface            | Web reference (LUXURY-MOTION §4) |
/// |--------|--------------------|----------------------------------|
/// | `elev1`| cards              | `0 2px 8px  rgba(10,15,27,.28)`  |
/// | `elev2`| sheets, panels     | `0 12px 40px rgba(10,15,27,.45)` |
/// | `elev3`| modals, lightbox   | `0 24px 80px rgba(10,15,27,.60)` |
///
/// The web spec's `rgba(10,15,27,…)` is Ink-950 (`#0A0F1B`); we tint against
/// `LoreColor.ink950` so the whole app shares one shadow hue. Apply via the
/// `.loreElevation(_:)` modifier; never hand-roll a `.shadow` in a view.
enum LoreElevation {
    /// A resolved shadow: the (Ink-tinted) color, blur radius, and vertical
    /// offset. SwiftUI's `.shadow` takes radius as the blur; `y` is the drop.
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    /// The shadow-tint base — Ink-950, never `#000` (LUXURY-MOTION §4).
    static let tint = LoreColor.ink950

    /// `elev.1` — cards. `0 2px 8px rgba(ink, .28)` (SwiftUI blur ≈ web/2).
    static let elev1 = Shadow(color: tint.opacity(0.28), radius: 4, y: 2)
    /// `elev.2` — sheets / floating panels. `0 12px 40px rgba(ink, .45)`.
    static let elev2 = Shadow(color: tint.opacity(0.45), radius: 20, y: 12)
    /// `elev.3` — modals / lightbox. `0 24px 80px rgba(ink, .60)`.
    static let elev3 = Shadow(color: tint.opacity(0.60), radius: 40, y: 24)
}

/// Applies a `LoreElevation` shadow. Elevation is depth, not motion, so it is
/// **not** gated on Reduce Motion — a still shadow is always safe and always
/// wanted.
struct LoreElevationModifier: ViewModifier {
    let shadow: LoreElevation.Shadow

    func body(content: Content) -> some View {
        content.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }
}

extension View {
    /// Cast a `LoreElevation` shadow (Ink-tinted, never black).
    ///
    /// ```swift
    /// card.loreElevation(.elev1)   // resting card
    /// sheet.loreElevation(.elev2)  // floating panel
    /// ```
    func loreElevation(_ shadow: LoreElevation.Shadow) -> some View {
        modifier(LoreElevationModifier(shadow: shadow))
    }
}

extension LoreElevation.Shadow {
    /// `.elev1` — card resting shadow.
    static var elev1: LoreElevation.Shadow { LoreElevation.elev1 }
    /// `.elev2` — sheet / panel shadow.
    static var elev2: LoreElevation.Shadow { LoreElevation.elev2 }
    /// `.elev3` — modal / lightbox shadow.
    static var elev3: LoreElevation.Shadow { LoreElevation.elev3 }
}
