import SwiftUI

/// "Meet {City}" — the culture surface. A warm, playful introduction to how a
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

    @State private var model = CultureModel()

    init(city: String = Config.defaultCity) {
        self.city = city
    }

    var body: some View {
        ZStack {
            LoreColor.ink900.ignoresSafeArea()

            switch model.state {
            case .loading:
                ProgressView("Meeting the city\u{2026}")
                    .tint(LoreColor.amber)
                    .foregroundStyle(LoreColor.bone)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .navigationTitle("Meet \(model.cityDisplayName(for: city))")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(LoreColor.ink900, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await model.load(city: city) }
        .sheet(item: $model.selectedPerson) { person in
            PersonBioSheet(person: person)
        }
    }

    // MARK: - Loaded content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header

                if !model.quotes.isEmpty {
                    CultureQuoteCard(quotes: model.quotes)
                        .padding(.horizontal, 16)
                }

                if !model.people.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        CultureSectionHeader(eyebrow: "The Locals", title: "Famous Faces")
                            .padding(.horizontal, 16)
                        FamousFacesRow(people: model.people) { person in
                            model.selectedPerson = person
                        }
                    }
                }

                if !model.lingo.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        CultureSectionHeader(eyebrow: "Talk Like a Local", title: "Local Lingo")
                            .padding(.horizontal, 16)
                        lingoGrid
                    }
                }

                if !model.sayings.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        CultureSectionHeader(eyebrow: "How We Say It", title: "Sayings")
                            .padding(.horizontal, 16)
                        sayingsRow
                    }
                }

                Color.clear.frame(height: 24)
            }
            .padding(.top, 8)
        }
    }

    private var header: some View {
        Text("A quick introduction to how this city talks, thinks, and remembers itself.")
            .font(LoreType.body)
            .foregroundStyle(LoreColor.bone.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
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
    /// Slang words — the "Local Lingo" flip cards.
    private(set) var lingo: [CityCulture] = []
    /// Sayings — turns of phrase, also shown as flip cards.
    private(set) var sayings: [CityCulture] = []

    /// The person whose bio sheet is presented, if any.
    var selectedPerson: CityCulture?

    /// Human-friendly city name. Falls back to a title-cased slug when the
    /// `city` table hasn't been consulted (this surface only needs the slug).
    func cityDisplayName(for slug: String) -> String {
        cityNames[slug] ?? slug.capitalized
    }

    private var cityNames: [String: String] = [:]

    func load(city: String) async {
        guard case .loading = state else { return }
        do {
            // Best-effort proper city name (non-fatal if it fails).
            async let citiesTask = try? LoreAPI.shared.cities()
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

            state = rows.isEmpty ? .empty : .loaded
        } catch {
            state = .failed("Check your connection and try again.")
        }
    }
}
