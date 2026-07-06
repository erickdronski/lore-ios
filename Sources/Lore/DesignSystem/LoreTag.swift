import SwiftUI

/// The tag vocabulary, one place-tag slug → (color, SF Symbol, display label)
/// so every surface renders a tag identically (map filter chips, dossier tag
/// row, scanner context). Colors stay inside the brand ramp (brand/DESIGN.md
/// §4); tags are Bone-surface chrome, so text colors are AA on Bone.
///
/// Tags the DB emits that we don't recognize fall back to a neutral Ink style
/// via `LoreTagStyle.default(for:)`, an unknown tag is never a crash, just a
/// plain chip.
enum LoreTagStyle {
    /// A resolved tag style: the accent color, an SF Symbol glyph, and the
    /// human label.
    struct Style: Hashable {
        let color: Color
        let symbol: String
        let label: String
    }

    /// Registry, keyed by the raw tag slug from `place.tags` / `story.tags`.
    /// Grouped loosely by the interests in `InterestMap` so the palette reads
    /// coherently on a card.
    static let registry: [String: Style] = [
        // Architecture
        "art-deco": .init(color: LoreColor.brass700, symbol: "building.columns", label: "Art Deco"),
        "beaux-arts": .init(color: LoreColor.brass700, symbol: "building.columns", label: "Beaux-Arts"),
        "brutalist": .init(color: LoreColor.ink600, symbol: "square.stack.3d.up", label: "Brutalist"),
        "neo-gothic": .init(color: LoreColor.ink600, symbol: "building.2", label: "Neo-Gothic"),
        "gothic-revival": .init(color: LoreColor.ink600, symbol: "building.2", label: "Gothic Revival"),
        "modernist": .init(color: LoreColor.info, symbol: "square.grid.3x3", label: "Modernist"),
        "skyline-icon": .init(color: LoreColor.amber600, symbol: "building.2.crop.circle", label: "Skyline Icon"),
        "engineering-feat": .init(color: LoreColor.info, symbol: "gearshape.2", label: "Engineering Feat"),

        // History
        "founding-era": .init(color: LoreColor.brass700, symbol: "flag", label: "Founding Era"),
        "gilded-age": .init(color: LoreColor.brass700, symbol: "crown", label: "Gilded Age"),
        "survivor": .init(color: LoreColor.success, symbol: "shield.checkerboard", label: "Survivor"),
        "monument": .init(color: LoreColor.brass700, symbol: "building.columns.circle", label: "Monument"),

        // Parks & nature
        "green-space": .init(color: LoreColor.success, symbol: "leaf", label: "Green Space"),
        "forest": .init(color: LoreColor.success, symbol: "tree", label: "Forest"),
        "waterfront": .init(color: LoreColor.info, symbol: "water.waves", label: "Waterfront"),
        "riverfront": .init(color: LoreColor.info, symbol: "water.waves", label: "Riverfront"),

        // Nightlife
        "nightlife": .init(color: LoreColor.amber600, symbol: "moon.stars", label: "Nightlife"),
        "dive-bar": .init(color: LoreColor.amber600, symbol: "wineglass", label: "Dive Bar"),
        "jazz": .init(color: LoreColor.amber600, symbol: "music.note", label: "Jazz"),
        "speakeasy": .init(color: LoreColor.ink600, symbol: "key", label: "Speakeasy"),
        "comedy": .init(color: LoreColor.amber600, symbol: "theatermasks", label: "Comedy"),

        // Film & music
        "film-famous": .init(color: LoreColor.info, symbol: "film", label: "Film Famous"),
        "music-history": .init(color: LoreColor.info, symbol: "music.note.list", label: "Music History"),
        "music-venue": .init(color: LoreColor.info, symbol: "music.mic", label: "Music Venue"),
        "movie-palace": .init(color: LoreColor.brass700, symbol: "popcorn", label: "Movie Palace"),

        // Family
        "family-friendly": .init(color: LoreColor.success, symbol: "figure.2.and.child.holdinghands", label: "Family Friendly"),
        "observation-deck": .init(color: LoreColor.info, symbol: "binoculars", label: "Observation Deck"),

        // Sports
        "stadium": .init(color: LoreColor.info, symbol: "sportscourt", label: "Stadium"),
        "ballpark": .init(color: LoreColor.info, symbol: "baseball", label: "Ballpark"),
        "arena": .init(color: LoreColor.info, symbol: "sportscourt", label: "Arena"),
        "sports": .init(color: LoreColor.info, symbol: "figure.run", label: "Sports"),

        // Haunted
        "haunted-lore": .init(color: LoreColor.ink600, symbol: "moon.haze", label: "Haunted"),
        "ghost": .init(color: LoreColor.ink600, symbol: "moon.haze", label: "Ghost Story"),

        // Public art
        "public-art": .init(color: LoreColor.brass700, symbol: "paintpalette", label: "Public Art"),

        // Trending
        "trending": .init(color: LoreColor.error, symbol: "flame", label: "Trending"),
    ]

    /// The style for a tag; unknown tags get a neutral Ink chip whose label is
    /// the slug prettified ("civil-rights" → "Civil Rights").
    static func style(for tag: String) -> Style {
        if let known = registry[tag] { return known }
        let label = tag
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        return Style(color: LoreColor.ink600, symbol: "tag", label: label)
    }
}

/// A single tag chip: `radius.s`, glyph + label, tinted per `LoreTagStyle`.
/// Sized for a Bone surface; the tint is decorative-plus-AA-text, never a fill.
struct LoreTag: View {
    let tag: String
    /// When true, the chip fills with a faint tint of its accent (selected
    /// state on a filter row); otherwise it's outline-only.
    var selected: Bool = false

    private var style: LoreTagStyle.Style { LoreTagStyle.style(for: tag) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: style.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(style.label)
                .font(LoreType.label)
                .tracking(0.3)
        }
        .foregroundStyle(style.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? style.color.opacity(0.14) : LoreColor.bone50)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style.color.opacity(selected ? 0.5 : 0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
