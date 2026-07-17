import SwiftUI

/// The explorer's world dashboard at the top of the Passport: continents lit up
/// as you cross them, the headline tallies (places, cities, countries), a streak
/// flame, and the personal-exploration ledger. Every number is real, from the
/// `user_stats` RPC — nothing is estimated.
struct ExplorerStatsView: View {
    let stats: UserStats

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
            HStack {
                Text("THE WORLD")
                    .font(LoreType.label).tracking(0.6)
                    .foregroundStyle(LoreColor.brass300)
                Spacer()
                Text("\(stats.continents) of 6 continents")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
            HStack(spacing: 8) {
                ForEach(UserStats.allContinents, id: \.self) { name in
                    let visited = stats.continentsList.contains(name)
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
                        Text(shortName(name))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(visited ? LoreColor.bone : LoreColor.ink600)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func shortName(_ name: String) -> String {
        switch name {
        case "North America": return "N. Am"
        case "South America": return "S. Am"
        default: return name
        }
    }

    // MARK: Headline tallies

    private var headline: some View {
        HStack(spacing: 0) {
            bigStat(stats.places, "Places")
            divider
            bigStat(stats.cities, "Cities")
            divider
            bigStat(stats.countries, "Countries")
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
    }

    private var divider: some View {
        Rectangle().fill(LoreColor.ink700).frame(width: 1, height: 34)
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
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
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
                .font(.system(size: 10))
                .foregroundStyle(LoreColor.ink600)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Top categories

    private var categories: some View {
        let maxCount = max(stats.topCategories.map(\.count).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("WHAT YOU SEEK")
                .font(LoreType.label).tracking(0.6)
                .foregroundStyle(LoreColor.brass300)
            ForEach(stats.topCategories.prefix(5)) { cat in
                HStack(spacing: 10) {
                    Text(cat.kind.capitalized)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone)
                        .frame(width: 92, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(LoreColor.ink800)
                            Capsule().fill(LoreColor.amber)
                                .frame(width: max(8, geo.size.width * CGFloat(cat.count) / CGFloat(maxCount)))
                        }
                    }
                    .frame(height: 8)
                    Text("\(cat.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LoreColor.ink600)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }
}
