import SwiftUI

/// "Meet {City}", the culture surface. A warm, playful introduction to how a
/// city *talks and thinks*, built entirely from the `city_culture` table:
///
/// - a rotating famous **quote** at the top (the world's words),
/// - a horizontal shelf of **famous faces** (portraits pulled from Wikipedia),
/// - **Local Lingo** flip cards (slang word on the front, meaning + example on
///   the back), and any **sayings** as flip cards too.
///
/// Ink-family surface throughout (this is app chrome, not over-camera), grain-
/// free tiles, Reveal motion, and progressive disclosure by doctrine
/// (brand/ELEVATION.md §5b): compact tiles, depth on tap. Every section is
/// independently optional, so a city with only slang still renders gracefully,
/// and a city with nothing at all shows a friendly empty state.
struct CultureView: View {
    let city: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = CultureModel()
    /// Rises once on load so the Amber horizon glow swells, the meet-the-city
    /// cinematic beat (LUXURY-MOTION §6, §7).
    @State private var glowRisen = false

    init(city: String = Config.defaultCity) {
        self.city = city
    }

    var body: some View {
        ZStack {
            cinematicSky

            switch model.state {
            case .loading:
                loadingSkeleton
            case .failed(let message):
                ContentUnavailableView {
                    Label("Can't load the culture", systemImage: "quote.bubble")
                        .foregroundStyle(LoreColor.bone)
                } description: {
                    Text(message).foregroundStyle(LoreColor.ink600)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                emptyState
            case .loaded:
                content
            }
        }
        // App is pinned to light scheme at the root, so a system large title
        // renders near-black on this dark ground. Title is drawn in-content as
        // bone (see `header`); keep the bar an opaque dark strip for a light
        // status bar.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(LoreColor.ink900, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await model.load(city: city) }
        .onAppear {
            if reduceMotion {
                glowRisen = true
            } else {
                withAnimation(LoreSpring.slow) { glowRisen = true }
            }
        }
        .sheet(item: $model.selectedPerson) { person in
            PersonBioSheet(person: person)
        }
    }

    // MARK: - Cinematic sky

    /// The Ink surface with an Amber horizon glow that rises on load, the same
    /// cinematic "meet-the-city" treatment as the arrival (LUXURY-MOTION §6).
    private var cinematicSky: some View {
        ZStack {
            LoreColor.ink900
            RadialGradient(
                colors: [LoreColor.amber.opacity(0.14), .clear],
                center: .init(x: 0.5, y: 1.0),
                startRadius: 0,
                endRadius: glowRisen ? 380 : 200
            )
            .opacity(glowRisen ? 1 : 0.4)
            .blendMode(.screen)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Loading

    /// Content-shaped skeleton (LUXURY-MOTION §3): a quote-card block over a row
    /// of portrait discs, no spinner.
    private var loadingSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LoreColor.ink800)
                    .frame(height: 150)
                    .shimmer()
                    .padding(.horizontal, 16)

                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(LoreColor.ink800)
                                .frame(width: 76, height: 76)
                                .shimmer()
                            ShimmerBlock(width: 60, height: 12, cornerRadius: 5, fill: LoreColor.ink800)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 12)
        }
        .accessibilityLabel("Meeting the city")
    }

    // MARK: - Loaded content

    private var content: some View {
        ScrollView {
            // The sections cascade in with the shared 40 ms fade+rise so the
            // surface assembles itself (LUXURY-MOTION §6). Conditional sections
            // make static indices awkward, so we cascade the ones that exist.
            StaggeredReveal(spacing: 32) {
                header.staggerChild(index: 0)

                if !model.quotes.isEmpty {
                    CultureQuoteCard(quotes: model.quotes)
                        .padding(.horizontal, 16)
                        .staggerChild(index: 1)
                }

                if !model.facts.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        CultureSectionHeader(eyebrow: "Wait, Really?", title: "Did You Know", accent: accent)
                            .padding(.horizontal, 16)
                        DidYouKnowDeck(facts: model.facts)
                    }
                    .staggerChild(index: 2)
                }

                if !model.stats.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        CultureSectionHeader(eyebrow: "The Big Figures", title: "By the Numbers", accent: accent)
                            .padding(.horizontal, 16)
                        ByTheNumbersStrip(stats: model.stats)
                    }
                    .staggerChild(index: 3)
                }

                if !model.people.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        CultureSectionHeader(eyebrow: "The Locals", title: "Famous Faces", accent: accent)
                            .padding(.horizontal, 16)
                        FamousFacesRow(people: model.people) { person in
                            model.selectedPerson = person
                        }
                    }
                    .staggerChild(index: 4)
                }

                if !model.lingo.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        CultureSectionHeader(eyebrow: "Talk Like a Local", title: "Local Lingo", accent: accent)
                            .padding(.horizontal, 16)
                        lingoGrid
                    }
                    .staggerChild(index: 5)
                }

                if !model.sayings.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        CultureSectionHeader(eyebrow: "How We Say It", title: "Sayings", accent: accent)
                            .padding(.horizontal, 16)
                        sayingsRow
                    }
                    .staggerChild(index: 6)
                }

                if !model.flavor.isEmpty {
                    // The flavor layer: dish/sound/etiquette/… shelves, any kind
                    // the server sends. One block in the cascade so indices of
                    // the culture sections above stay stable.
                    VStack(alignment: .leading, spacing: 32) {
                        ForEach(model.flavor, id: \.kind) { group in
                            let meta = SectionKindMeta.header(for: group.kind)
                            VStack(alignment: .leading, spacing: 14) {
                                CultureSectionHeader(eyebrow: meta.eyebrow, title: meta.title, accent: accent)
                                    .padding(.horizontal, 16)
                                CityFlavorShelf(entries: group.entries, accent: accent ?? LoreColor.brass300)
                            }
                        }
                    }
                    .staggerChild(index: 7)
                }

                Color.clear.frame(height: 24)
            }
            .padding(.top, 8)
            .background(alignment: .top) {
                // The city's signature wash, scrolling away with the header.
                CityThemeWash(theme: model.theme)
            }
        }
    }

    /// The city accent for section eyebrows and card rules; nil = house brass.
    private var accent: Color? { model.theme?.accentColor }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meet \(model.cityDisplayName(for: city))")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LoreColor.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("A quick introduction to how this city talks, thinks, and remembers itself.")
                .font(LoreType.body)
                .foregroundStyle(LoreColor.bone.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }

    /// Lingo as a two-row horizontal shelf of flip cards (compact, horizontal
    /// media per §5b). A `LazyHGrid` with two rows lets many words scroll
    /// sideways without a vertical wall.
    private var lingoGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(150), spacing: 12), GridItem(.fixed(150), spacing: 12)], spacing: 12) {
                ForEach(model.lingo) { entry in
                    LingoFlipCard(entry: entry)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var sayingsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(model.sayings) { entry in
                    LingoFlipCard(entry: entry)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No culture notes yet", systemImage: "quote.bubble")
                .foregroundStyle(LoreColor.bone)
        } description: {
            Text(
                "The slang, sayings, and famous faces for "
                + "\(model.cityDisplayName(for: city)) land with the seed."
            )
            .foregroundStyle(LoreColor.ink600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Person bio sheet

/// A tap on a famous face opens their bio: a big portrait, name, the one-line
/// life span/role (`attribution`), the seed bio (`body`), and a link out to
/// Wikipedia when we have a title.
struct PersonBioSheet: View {
    let person: CityCulture
    @Environment(\.dismiss) private var dismiss
    @State private var portraitURL: URL?

    private let diameter: CGFloat = 132

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                portrait
                    .padding(.top, 24)

                Text(person.headline)
                    .font(LoreType.display(size: 28, weight: .semibold))
                    .foregroundStyle(LoreColor.bone)
                    .multilineTextAlignment(.center)

                if let attribution = person.attribution {
                    Text(attribution)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.brass300)
                        .multilineTextAlignment(.center)
                }

                if let body = person.body {
                    Text(body)
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.bone.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                if let wiki = wikipediaURL {
                    Link(destination: wiki) {
                        Label("Read on Wikipedia", systemImage: "safari")
                            .font(LoreType.button)
                            .foregroundStyle(LoreColor.ink900)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(LoreColor.amber))
                    }
                    .padding(.top, 8)
                }

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .background(LoreColor.ink900.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard let title = person.wikipediaTitle else { return }
            portraitURL = await WikipediaService.shared.portraitURL(for: title)
        }
    }

    @ViewBuilder
    private var portrait: some View {
        ZStack {
            Circle()
                .fill(LoreColor.ink800)
                .overlay(Text(person.displayEmoji).font(.system(size: 52)))

            if let url = portraitURL {
                AsyncImage(url: url, transaction: Transaction(animation: LoreMotion.bloom)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill().transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().strokeBorder(LoreColor.brass300, lineWidth: 2))
    }

    private var wikipediaURL: URL? {
        guard let title = person.wikipediaTitle,
              let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://en.wikipedia.org/wiki/\(encoded)")
    }
}

// MARK: - Model

@Observable
@MainActor
final class CultureModel {
    enum State {
        case loading
        case empty
        case failed(String)
        case loaded
    }

    private(set) var state: State = .loading

    /// The full culture set for the city, split by register once on load.
    private(set) var quotes: [CityCulture] = []
    private(set) var people: [CityCulture] = []
    /// Slang words, the "Local Lingo" flip cards.
    private(set) var lingo: [CityCulture] = []
    /// Sayings, turns of phrase, also shown as flip cards.
    private(set) var sayings: [CityCulture] = []

    /// The "Did You Know" facts for the city (superlatives, firsts, quirks, …),
    /// shown as a swipeable deck. Loaded best-effort; a city with none simply
    /// hides the deck.
    private(set) var facts: [CityFact] = []
    /// The subset of `facts` that carry a headline number, shown as the "By the
    /// Numbers" stat strip.
    private(set) var stats: [CityFact] = []

    /// The person whose bio sheet is presented, if any.
    var selectedPerson: CityCulture?

    /// The city's signature hue system, if curated (nil = house palette).
    private(set) var theme: CityTheme?
    /// Flavor sections grouped by kind, in `SectionKindMeta` order. Any kind
    /// the server sends renders; old kinds never break.
    private(set) var flavor: [(kind: String, entries: [CitySection])] = []

    /// Human-friendly city name. Falls back to a title-cased slug when the
    /// `city` table hasn't been consulted (this surface only needs the slug).
    func cityDisplayName(for slug: String) -> String {
        cityNames[slug] ?? Self.prettyCitySlug(slug)
    }

    private var cityNames: [String: String] = [:]

    private static func prettyCitySlug(_ slug: String) -> String {
        slug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    func load(city: String) async {
        guard case .loading = state else { return }
        do {
            // Best-effort proper city name + facts + theme + flavor sections
            // (all non-fatal if they fail).
            async let citiesTask = try? LoreAPI.shared.cities()
            async let factsTask = try? LoreAPI.shared.cityFacts(city: city)
            async let themeTask = try? LoreAPI.shared.cityTheme(city: city)
            async let sectionsTask = try? LoreAPI.shared.citySections(city: city)
            let rows = try await LoreAPI.shared.culture(city: city)
            if let cities = await citiesTask {
                cityNames = Dictionary(
                    cities.map { ($0.slug, $0.name) },
                    uniquingKeysWith: { first, _ in first }
                )
            }

            quotes = rows.filter { $0.kind == .quote }
            people = rows.filter { $0.kind == .person }
            lingo = rows.filter { $0.kind == .slang }
            sayings = rows.filter { $0.kind == .saying }

            facts = await factsTask ?? []
            stats = facts.filter(\.hasStat)

            theme = (await themeTask) ?? nil
            let sections = (await sectionsTask) ?? []
            flavor = Dictionary(grouping: sections, by: \.kind)
                .map { (kind: $0.key, entries: $0.value.sorted { ($0.sort ?? 100) < ($1.sort ?? 100) }) }
                .sorted {
                    let (a, b) = (SectionKindMeta.order(for: $0.kind), SectionKindMeta.order(for: $1.kind))
                    return a == b ? $0.kind < $1.kind : a < b
                }

            state = (rows.isEmpty && facts.isEmpty && sections.isEmpty) ? .empty : .loaded
        } catch {
            state = .failed("Check your connection and try again.")
        }
    }
}
