import SwiftUI

/// One row in the global search list: emoji (or the kind's SF Symbol as a
/// fallback), the primary `label`, and a `sublabel` second line. Sized and
/// tinted for a Bone list surface (brand/DESIGN.md §7, the app's words in
/// SF Pro; Fraunces only for the world's words, so the label stays SF Pro-ish
/// display, sublabel is plain caption).
///
/// Purely presentational, the enclosing `List`/`Button` owns the tap.
struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: 12) {
            leadingGlyph
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.label)
                    .font(LoreType.display(size: 17, weight: .medium))
                    .foregroundStyle(LoreColor.ink)
                    .lineLimit(1)

                if let sub = result.sublabel, !sub.isEmpty {
                    Text(sub)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LoreColor.bone300)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// The emoji when the row has one, else the kind's SF Symbol on a faint
    /// Bone chip so every row has a stable leading anchor.
    @ViewBuilder
    private var leadingGlyph: some View {
        if !result.displayEmoji.isEmpty {
            Text(result.displayEmoji)
                .font(.system(size: 24))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LoreColor.bone200)
                Image(systemName: result.kind.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LoreColor.ink600)
            }
        }
    }

    private var accessibilityLabel: String {
        if let sub = result.sublabel, !sub.isEmpty {
            return "\(result.label), \(sub)"
        }
        return result.label
    }
}

/// Human section header for a group of results, keyed by `SearchResult.Kind`.
/// Cities / Places / People / Stories / Tours, plural, title-cased, matching
/// the switcher's and culture shelf's copy.
extension SearchResult.Kind {
    /// Plural section title used to group results in the search list.
    var sectionTitle: String {
        switch self {
        case .city: return "Cities"
        case .place: return "Places"
        case .story: return "Stories"
        case .culture: return "People & Culture"
        case .tour: return "Tours"
        }
    }

    /// Curated order the groups appear in the results list, Cities first (the
    /// switch that reframes everything), then Places, People, Stories, Tours.
    var sectionOrder: Int {
        switch self {
        case .city: return 0
        case .place: return 1
        case .culture: return 2
        case .story: return 3
        case .tour: return 4
        }
    }
}
