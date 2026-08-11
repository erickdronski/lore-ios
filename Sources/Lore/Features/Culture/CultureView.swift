import SwiftUI

/// Sheet host for the full-bleed culture surface. CultureView intentionally
/// hides navigation chrome, so its sheet dismissal must live above that view.
struct CultureSheet: View {
    let city: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CultureView(city: city)
                .overlay(alignment: .topTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LoreColor.bone)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Close city guide")
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                }
        }
    }
}

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
                } actions: {
                    Button("Try again") {
                        Task { await model.load(city: city, force: true) }
                    }
                    .tint(LoreColor.amber)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                emptyState
            case .loaded:
                content
            }
        }
        // The title is drawn in-content. Hide the otherwise-empty navigation
        // bar so the cinematic sky flows through the status area without a
        // horizontal seam above "Meet {City}."
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task(id: city) { await model.load(city: city) }
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

                if let warning = model.loadWarning {
                    partialDataNotice(warning)
                        .padding(.horizontal, 16)
                        .staggerChild(index: 1)
                }

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

                if let fieldBrief = model.fieldBrief {
                    CityFieldBriefCard(brief: fieldBrief, accent: accent ?? LoreColor.brass300)
                        .padding(.horizontal, 16)
                        .staggerChild(index: 7)
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
                    .staggerChild(index: 8)
                }

                Color.clear.frame(height: 24)
            }
            .padding(.top, 8)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
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

    private func partialDataNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(LoreColor.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("Some stories are still arriving")
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone)
                Text(message)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.7))
            }
            Spacer(minLength: 8)
            Button("Retry") {
                Task { await model.load(city: city, force: true) }
            }
            .font(LoreType.button)
            .foregroundStyle(LoreColor.amber)
        }
        .padding(14)
        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LoreColor.amber.opacity(0.24), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
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
        } actions: {
            Button("Check again") {
                Task { await model.load(city: city, force: true) }
            }
            .tint(LoreColor.amber)
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    portrait
                        .padding(.top, 24)

                    Text(person.headline)
                        .font(LoreType.display(size: 28, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

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

                    HStack(spacing: 10) {
                        if let source = person.cultureSourceURL ?? wikipediaURL {
                            Link(destination: source) {
                                Label("Source", systemImage: "link")
                            }
                        }

                        ShareLink(item: shareText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.ink900)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(LoreColor.amber))
                    .padding(.top, 8)

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
            .background(LoreColor.ink900.ignoresSafeArea())
            .navigationTitle("City profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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

    private var shareText: String {
        ([person.headline, person.attribution, person.body] as [String?])
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n") + "\n\nDiscovered with Lore."
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
    private(set) var loadWarning: String?

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
    /// The traveler brief, synthesized from the richest loaded section kinds
    /// when enough of them exist.
    private(set) var fieldBrief: CityFieldBrief?

    /// Human-friendly city name. Falls back to a title-cased slug when the
    /// `city` table hasn't been consulted (this surface only needs the slug).
    func cityDisplayName(for slug: String) -> String {
        cityNames[slug] ?? Self.prettyCitySlug(slug)
    }

    private var cityNames: [String: String] = [:]
    private var loadedCity: String?
    private var activeLoadID = UUID()

    private static func prettyCitySlug(_ slug: String) -> String {
        slug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    func load(city: String, force: Bool = false) async {
        guard force || loadedCity != city else { return }

        let loadID = UUID()
        activeLoadID = loadID
        state = .loading
        loadWarning = nil
        quotes = []
        people = []
        lingo = []
        sayings = []
        facts = []
        stats = []
        theme = nil
        flavor = []
        fieldBrief = nil

        async let citiesTask = try? LoreAPI.shared.cities()
        async let cultureTask = try? LoreAPI.shared.culture(city: city)
        async let factsTask = try? LoreAPI.shared.cityFacts(city: city)
        async let themeTask = try? LoreAPI.shared.cityTheme(city: city)
        async let sectionsTask = try? LoreAPI.shared.citySections(city: city)

        let (cities, rows, loadedFacts, loadedTheme, sections) = await (
            citiesTask, cultureTask, factsTask, themeTask, sectionsTask
        )
        guard activeLoadID == loadID else { return }

        guard rows != nil || loadedFacts != nil || sections != nil else {
            state = .failed("Check your connection and try again.")
            return
        }

        if let cities {
            cityNames = Dictionary(
                cities.map { ($0.slug, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        let cultureRows = rows ?? []
        quotes = cultureRows.filter { $0.kind == .quote }
        people = cultureRows.filter { $0.kind == .person }
        lingo = cultureRows.filter { $0.kind == .slang }
        sayings = cultureRows.filter { $0.kind == .saying }

        facts = loadedFacts ?? []
        stats = facts.filter(\.hasStat)
        theme = loadedTheme

        let loadedSections = sections ?? []
        fieldBrief = CityFieldBrief(sections: loadedSections)

        flavor = Dictionary(grouping: loadedSections, by: \.kind)
            .map {
                (kind: $0.key, entries: $0.value.sorted {
                    let leftSort = $0.sort ?? 100
                    let rightSort = $1.sort ?? 100
                    return leftSort == rightSort
                        ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                        : leftSort < rightSort
                })
            }
            .sorted {
                let (a, b) = (SectionKindMeta.order(for: $0.kind), SectionKindMeta.order(for: $1.kind))
                return a == b ? $0.kind < $1.kind : a < b
            }

        let unavailable = [rows == nil, loadedFacts == nil, sections == nil].filter { $0 }.count
        if unavailable > 0 {
            loadWarning = "Lore is showing everything available now. Retry when your connection improves to complete this city guide."
        }

        loadedCity = city
        state = (cultureRows.isEmpty && facts.isEmpty && (sections ?? []).isEmpty) ? .empty : .loaded
    }
}

extension CityCulture {
    var cultureSourceURL: URL? {
        for raw in [links.website, source] {
            guard let raw, let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), url.host != nil else { continue }
            return url
        }
        return nil
    }
}
