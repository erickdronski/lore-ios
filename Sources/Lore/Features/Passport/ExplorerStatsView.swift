import SwiftUI

/// The explorer's world dashboard at the top of the Passport: continents lit up
/// as you cross them, the headline tallies (places, cities, countries), a streak
/// flame, and the personal-exploration ledger. Every number is real, from the
/// `user_stats` RPC — nothing is estimated.
struct ExplorerStatsView: View {
    let stats: UserStats
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A representative emoji per continent, lit when the user has been there.
    private static let continentEmoji: [String: String] = [
        "North America": "🗽", "South America": "🏔️", "Europe": "🏰",
        "Africa": "🦁", "Asia": "🏯", "Oceania": "🦘",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            continents
            headline
            ledger
            if !stats.topCategories.isEmpty { categories }
            if let since = stats.exploringSince {
                Text("Exploring since \(since)")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
        }
        .padding(16)
        .background(LoreColor.ink900, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LoreColor.ink700, lineWidth: 1))
    }

    // MARK: The world — continents lit as you cross them

    private var continents: some View {
        VStack(alignment: .leading, spacing: 8) {
            continentHeader
            LazyVGrid(columns: continentColumns, spacing: 10) {
                ForEach(UserStats.allContinents, id: \.self) { name in
                    let visited = stats.continentsList.contains(name)
                    continentTile(name: name, visited: visited)
                }
            }
        }
    }

    @ViewBuilder
    private var continentHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                continentEyebrow
                continentCount
            }
        } else {
            HStack {
                continentEyebrow
                Spacer()
                continentCount
            }
        }
    }

    private var continentEyebrow: some View {
        Text("THE WORLD")
            .font(LoreType.label).tracking(0.6)
            .foregroundStyle(LoreColor.brass300)
    }

    private var continentCount: some View {
        Text("\(stats.continents) of 6 continents")
            .font(LoreType.caption)
            .foregroundStyle(LoreColor.ink600)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var continentColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 6
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private func continentTile(name: String, visited: Bool) -> some View {
        VStack(spacing: 4) {
            Text(Self.continentEmoji[name] ?? "🌍")
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(visited ? LoreColor.amber.opacity(0.9) : LoreColor.ink800)
                )
                .overlay(
                    Circle().strokeBorder(
                        visited ? LoreColor.brass : LoreColor.ink700,
                        lineWidth: visited ? 1.5 : 1
                    )
                )
                .saturation(visited ? 1 : 0)
                .opacity(visited ? 1 : 0.5)
            Text(dynamicTypeSize.isAccessibilitySize ? name : shortName(name))
                .font(LoreType.micro)
                .foregroundStyle(visited ? LoreColor.bone : LoreColor.ink600)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(Self.continentAccessibilityValue(visited: visited))
    }

    static func continentAccessibilityValue(visited: Bool) -> String {
        visited ? "Visited" : "Not visited"
    }

    private func shortName(_ name: String) -> String {
        switch name {
        case "North America": return "N. Am"
        case "South America": return "S. Am"
        default: return name
        }
    }

    // MARK: Headline tallies

    @ViewBuilder
    private var headline: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                bigStat(stats.places, "Places")
                Divider().overlay(LoreColor.ink700)
                bigStat(stats.cities, "Cities")
                Divider().overlay(LoreColor.ink700)
                bigStat(stats.countries, "Countries")
            }
        } else {
            HStack(spacing: 0) {
                bigStat(stats.places, "Places")
                divider
                bigStat(stats.cities, "Cities")
                divider
                bigStat(stats.countries, "Countries")
            }
        }
    }

    private func bigStat(_ value: Int, _ caption: String) -> some View {
        VStack(spacing: 3) {
            CountUpText.integer(value, font: LoreType.display(size: 30, weight: .bold))
                .foregroundStyle(LoreColor.bone)
            Text(caption.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.5)
                .foregroundStyle(LoreColor.ink600)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(caption)")
    }

    private var divider: some View {
        Rectangle()
            .fill(LoreColor.ink700)
            .frame(width: 1, height: 34)
            .accessibilityHidden(true)
    }

    // MARK: Personal ledger

    private var ledger: some View {
        let tiles: [(String, Int, String)] = [
            ("book.pages", stats.divesRead, "Deep dives"),
            ("square.and.pencil", stats.notes, "Your lore"),
            ("photo", stats.photos, "Photos"),
            ("camera.viewfinder", stats.scannerVisits, "Scans"),
            ("quote.bubble", stats.publicLores, "Shared"),
            ("flame.fill", stats.currentStreak, "Day streak"),
        ]
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount),
            spacing: 10
        ) {
            ForEach(tiles, id: \.2) { tile in
                smallStat(system: tile.0, value: tile.1, caption: tile.2,
                          hot: tile.2 == "Day streak" && tile.1 > 0)
            }
        }
    }

    private func smallStat(system: String, value: Int, caption: String, hot: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: system)
                .font(.system(size: 14))
                .foregroundStyle(hot ? LoreColor.amber : LoreColor.brass300)
            Text("\(value)")
                .font(LoreType.display(size: 18, weight: .semibold))
                .foregroundStyle(LoreColor.bone)
            Text(caption)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption), \(value)")
    }

    // MARK: Top categories

    private var categories: some View {
        let maxCount = max(stats.topCategories.map(\.count).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("WHAT YOU SEEK")
                .font(LoreType.label).tracking(0.6)
                .foregroundStyle(LoreColor.brass300)
            ForEach(stats.topCategories.prefix(5)) { cat in
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            categoryName(cat.kind)
                            Spacer()
                            categoryCount(cat.count)
                        }
                        categoryBar(count: cat.count, maxCount: maxCount)
                    }
                } else {
                    HStack(spacing: 10) {
                        categoryName(cat.kind)
                            .frame(width: 92, alignment: .leading)
                        categoryBar(count: cat.count, maxCount: maxCount)
                        categoryCount(cat.count)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func categoryName(_ kind: String) -> some View {
        Text(kind.capitalized)
            .font(LoreType.caption)
            .foregroundStyle(LoreColor.bone)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func categoryCount(_ count: Int) -> some View {
        Text("\(count)")
            .font(LoreType.caption.weight(.semibold))
            .foregroundStyle(LoreColor.ink600)
    }

    private func categoryBar(count: Int, maxCount: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LoreColor.ink800)
                Capsule().fill(LoreColor.amber)
                    .frame(width: max(8, geo.size.width * CGFloat(count) / CGFloat(maxCount)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
