import SwiftUI

/// The explorer's world dashboard at the top of the Passport: continents lit up
/// as you cross them, the headline tallies (places, cities, countries), a streak
/// flame, and the personal-exploration ledger. Every number is real, from the
/// `user_stats` RPC — nothing is estimated.
struct ExplorerStatsView: View {
    let stats: UserStats

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealsProgress = false

    /// A field-guide glyph per continent, stamped when the user has been there.
    private static let continentSymbol: [String: String] = [
        "North America": "building.columns.fill",
        "South America": "mountain.2.fill",
        "Europe": "building.2.crop.circle.fill",
        "Africa": "sun.horizon.fill",
        "Asia": "torii.gate",
        "Oceania": "water.waves",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            journeyHeading
            continents
            headline
            ledger
            if !stats.topCategories.isEmpty { categories }
            journeyFooter
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [LoreColor.ink800, LoreColor.ink900],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) { atlasLines }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LoreColor.brass300.opacity(0.2), lineWidth: 1)
        )
        .loreElevation(.elev1)
        .onAppear {
            guard !revealsProgress else { return }
            if reduceMotion {
                revealsProgress = true
            } else {
                withAnimation(LoreSpring.slow(reduceMotion: false).delay(0.12)) {
                    revealsProgress = true
                }
            }
        }
    }

    private var journeyHeading: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LoreColor.amber.opacity(0.15))
                Circle()
                    .strokeBorder(LoreColor.brass300.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                Image(systemName: "map.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LoreColor.amber)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("EXPLORER'S LEDGER")
                    .font(LoreType.label)
                    .tracking(0.8)
                    .foregroundStyle(LoreColor.brass300)
                Text(stats.places == 0 ? "Your world starts here" : "A world shaped by your footsteps")
                    .font(LoreType.display(size: 17, weight: .medium))
                    .foregroundStyle(LoreColor.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var atlasLines: some View {
        Canvas { context, size in
            var route = Path()
            route.move(to: CGPoint(x: size.width * 0.1, y: size.height * 0.72))
            route.addCurve(
                to: CGPoint(x: size.width * 0.92, y: size.height * 0.16),
                control1: CGPoint(x: size.width * 0.36, y: size.height * 0.34),
                control2: CGPoint(x: size.width * 0.58, y: size.height * 0.78)
            )
            context.stroke(
                route,
                with: .color(LoreColor.brass300.opacity(0.09)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 7])
            )
        }
        .frame(width: 190, height: 110)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                    .foregroundStyle(LoreColor.bone.opacity(0.65))
            }

            ProgressView(value: Double(stats.continents), total: 6)
                .tint(LoreColor.amber)
                .accessibilityLabel("Continents explored")
                .accessibilityValue("\(stats.continents) of 6")

            GeometryReader { proxy in
                let spacing: CGFloat = 6
                let stampSize = min(44, (proxy.size.width - spacing * 5) / 6)

                HStack(spacing: spacing) {
                    ForEach(UserStats.allContinents, id: \.self) { name in
                        let visited = stats.continentsList.contains(name)
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(visited ? LoreColor.amber.opacity(0.92) : LoreColor.ink900)
                                Circle()
                                    .strokeBorder(
                                        visited ? LoreColor.brass300 : LoreColor.ink700,
                                        style: StrokeStyle(lineWidth: visited ? 1.5 : 1, dash: visited ? [2, 2] : [])
                                    )
                                Image(systemName: Self.continentSymbol[name] ?? "globe.americas.fill")
                                    .font(.system(size: min(17, stampSize * 0.42), weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(visited ? LoreColor.ink900 : LoreColor.bone.opacity(0.45))
                            }
                            .frame(width: stampSize, height: stampSize)
                            .opacity(visited ? 1 : 0.5)
                            Text(shortName(name))
                                .font(LoreType.micro)
                                .foregroundStyle(visited ? LoreColor.bone : LoreColor.bone.opacity(0.45))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: stampSize)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(name)
                        .accessibilityValue(visited ? "Visited" : "Not visited")
                    }
                }
            }
            .frame(height: 62)
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
                .foregroundStyle(LoreColor.bone.opacity(0.58))
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
            ZStack {
                Circle()
                    .fill((hot ? LoreColor.amber : LoreColor.brass300).opacity(0.12))
                Image(systemName: system)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hot ? LoreColor.amber : LoreColor.brass300)
            }
            .frame(width: 28, height: 28)
            Text("\(value)")
                .font(LoreType.display(size: 18, weight: .semibold))
                .foregroundStyle(LoreColor.bone)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(LoreColor.bone.opacity(0.58))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(LoreColor.ink900.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LoreColor.ink700.opacity(0.7), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
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
                            Capsule().fill(LoreColor.ink900)
                            Capsule().fill(LoreColor.amber)
                                .frame(
                                    width: revealsProgress
                                        ? max(8, geo.size.width * CGFloat(cat.count) / CGFloat(maxCount))
                                        : 0
                                )
                        }
                    }
                    .frame(height: 8)
                    Text("\(cat.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LoreColor.bone.opacity(0.62))
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }

    private var journeyFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { journeyFooterItems }
            VStack(alignment: .leading, spacing: 8) { journeyFooterItems }
        }
        .padding(12)
        .background(LoreColor.ink900.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var journeyFooterItems: some View {
        Label(
            stats.currentStreak > 0 ? "\(stats.currentStreak)-day trail" : "Begin a trail",
            systemImage: stats.currentStreak > 0 ? "flame.fill" : "figure.walk"
        )
        .foregroundStyle(stats.currentStreak > 0 ? LoreColor.amber : LoreColor.bone.opacity(0.72))

        Spacer(minLength: 4)

        if let since = stats.exploringSince {
            Label("Since \(since)", systemImage: "calendar")
                .foregroundStyle(LoreColor.bone.opacity(0.68))
        } else {
            Label("First memory awaits", systemImage: "bookmark")
                .foregroundStyle(LoreColor.bone.opacity(0.68))
        }
    }
}
