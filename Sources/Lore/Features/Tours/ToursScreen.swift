import SwiftUI

/// Curated walking tours, listed by city, each opening a stop-by-stop
/// stepper detail.
struct ToursScreen: View {
    var onMeetCity: (String) -> Void = { _ in }
    /// The shared active city (same source the map reads). Switching it here
    /// re-scopes the whole Tours surface, the 1-Hour hero and the curated list.
    @Environment(AppRouter.self) private var router
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var model = ToursModel()
    /// The paywall raised by the offline-pack button's locked state.
    @State private var showPackPaywall = false
    /// The generated "1 Hour In" walk, presented in a sheet once routed.
    @State private var generatedTour: Tour?
    /// Chosen length for the generated walk (30 / 60 / 90 minutes).
    @State private var oneHourMinutes = 60
    /// Surfaced when the 1-hour walk can't be built (too few stops, or offline).
    @State private var oneHourError: String?
    /// The city whose walk is currently being routed (drives the hero spinner).
    @State private var generatingCity: String?
    /// The city switcher sheet (TestFlight feedback: "how does a user change
    /// the city here?").
    @State private var showCitySwitcher = false
    /// Pushes tour detail without using a visible `NavigationLink` row accessory,
    /// so the card remains the full visual tap target.
    @State private var tourPath: [Tour] = []
    /// City-wide deals, loaded here rather than inside `CityDealsSection` so the
    /// section is emitted into the `List` only when it has real offers. A
    /// self-hiding row still formed a phantom inset-grouped section, doubling
    /// the gap under the hero for every city with no deals.
    @State private var cityDeals: [Deal] = []

    var body: some View {
        NavigationStack(path: $tourPath) {
            List {
                madeForYouSection

                if Config.offlineCityPacksEnabled {
                    // Take this city with you: pins every story, tour, and photo
                    // so the walk survives subways and roaming dead zones (Lore+).
                    Section {
                        CityPackButton(city: router.selectedCity) {
                            showPackPaywall = true
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                // City passes & standing deals (Lore+): the day-planner's
                // money section. Emitted only when the city has real offers, so
                // cities with none show no empty band under the hero.
                if !cityDeals.isEmpty {
                    CityDealsSection(city: router.selectedCity, deals: cityDeals)
                }

                switch model.state {
                case .loading:
                    ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 10) {
                        Text(message)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.ink600)
                        Button("Try loading tours again") {
                            Task { await model.load(city: router.selectedCity, force: true) }
                        }
                        .font(LoreType.button)
                    }
                case .empty:
                    Text("Curated walks are landing city by city. Your 1-hour walk above already works wherever we have stories.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                case .loaded:
                    ForEach(model.cities, id: \.self) { city in
                        Section {
                            ForEach(model.toursByCity[city] ?? []) { tour in
                                Button {
                                    Haptics.play(.chipTap)
                                    tourPath.append(tour)
                                } label: {
                                    TourRow(
                                        tour: tour,
                                        isPlus: entitlements.isPlus,
                                        userID: auth.session?.user.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(TourBrowseLayout.tourRowInsets)
                            }
                        } header: {
                            Text(city.replacingOccurrences(of: "-", with: " ").capitalized)
                                .font(LoreType.displayM)
                                .foregroundStyle(LoreColor.ink)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(TourBrowseLayout.sectionSpacing)
            .scrollContentBackground(.hidden)
            .background(LoreColor.bone100)
            .navigationTitle("Tours")
            .navigationDestination(for: Tour.self) { tour in
                TourDetailView(tour: tour, onMeetCity: onMeetCity)
            }
            .sheet(item: $generatedTour) { tour in
                TourSheet(tour: tour, onMeetCity: onMeetCity)
            }
            .sheet(isPresented: $showCitySwitcher) {
                CitySwitcherView(router: router)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showPackPaywall) {
                PaywallView(entitlements: entitlements, store: store, auth: auth, context: .tours)
            }
            // Load (and reload) the selected city's tours; switching cities in
            // the sheet re-scopes the list without leaving Tours.
            .task(id: router.selectedCity) { await model.load(city: router.selectedCity) }
            .task(id: router.selectedCity) {
                cityDeals = (try? await LoreAPI.shared.cityDeals(city: router.selectedCity)) ?? []
            }
            .alert("Walk unavailable", isPresented: oneHourErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(oneHourError ?? "")
            }
        }
    }

    private var oneHourErrorBinding: Binding<Bool> {
        Binding(get: { oneHourError != nil }, set: { if !$0 { oneHourError = nil } })
    }

    /// City slug → display name, e.g. "san-francisco" → "San Francisco".
    private func cityLabel(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// The always-available generated walk (strategy Phase 2). Works in every
    /// seeded city even before curated tours land, so the feature is never empty.
    private var madeForYouSection: some View {
        Section {
            OneHourHero(
                city: router.selectedCity,
                minutes: oneHourMinutes,
                isGenerating: generatingCity == router.selectedCity
            ) {
                let city = router.selectedCity
                let minutes = oneHourMinutes
                generatingCity = city
                Task {
                    do {
                        if let tour = try await model.oneHourTour(city: city, durationMin: minutes) {
                            if router.selectedCity == city { generatedTour = tour }
                        } else {
                            if router.selectedCity == city {
                                oneHourError = "There aren't enough stops in \(cityLabel(city)) yet for a full walk. Try another city."
                            }
                        }
                    } catch {
                        if router.selectedCity == city {
                            oneHourError = "Couldn't build your walk. Check your connection and try again."
                        }
                    }
                    if generatingCity == city { generatingCity = nil }
                }
            }

            Picker("Walk length", selection: $oneHourMinutes) {
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
                Text("90 min").tag(90)
            }
            .pickerStyle(.segmented)
        } header: {
            HStack(spacing: 10) {
                Text("Build a city walk")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.ink)
                    .textCase(nil)
                Spacer(minLength: 8)
                citySwitcherChip
            }
        }
    }

    /// The Brass city chip in the section header: shows the active city and
    /// opens the switcher so Tours can be re-scoped to any city.
    private var citySwitcherChip: some View {
        Button {
            Haptics.play(.chipTap)
            showCitySwitcher = true
        } label: {
            HStack(spacing: 6) {
                Text(cityLabel(router.selectedCity))
                    .font(LoreType.display(size: 14, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(LoreColor.brass700)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(LoreColor.bone200, in: Capsule())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel(Text("Current city, \(cityLabel(router.selectedCity))"))
        .accessibilityHint(Text("Switch cities to see their tours."))
    }
}

enum TourBrowseLayout {
    static let sectionSpacing: CGFloat = 14
    static let tourRowCornerRadius: CGFloat = 18
    static let tourRowArtworkWidth: CGFloat = 118
    static let tourRowArtworkHeight: CGFloat = 76
    static let tourRowArtworkTopInset: CGFloat = 8
    static let tourRowArtworkTrailingInset: CGFloat = 10
    static let hiddenInterstitialHeight: CGFloat = 0
    static let tourRowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    static let interstitialRowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
}

/// The featured "1 Hour In {city}" entry: a dark field-guide cover with a
/// route signature and one Amber call to action. Taps generate the walk on the
/// fly (a brief routing state), then push the standard tour stepper.
struct OneHourHero: View {
    let city: String
    var minutes: Int = 60
    var isGenerating: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cityLabel: String {
        city.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var titleText: String {
        switch minutes {
        case 30: return "30 Minutes In \(cityLabel)"
        case 90: return "90 Minutes In \(cityLabel)"
        default: return "1 Hour In \(cityLabel)"
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LoreColor.ink800, LoreColor.ink950],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                TourRouteArtwork(
                    nodeCount: minutes == 30 ? 3 : (minutes == 90 ? 5 : 4),
                    color: LoreColor.amber,
                    activeFraction: isGenerating ? 0.45 : 1
                )
                .frame(width: 170, height: 104)
                .opacity(0.45)
                .padding(.top, 22)
                .padding(.trailing, -18)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("MADE FOR YOU", systemImage: "wand.and.stars")
                            .font(LoreType.micro)
                            .tracking(1.2)
                            .foregroundStyle(LoreColor.brass300)
                        Spacer()
                        Text(minutes == 60 ? "1 HOUR" : "\(minutes) MIN")
                            .font(LoreType.micro)
                            .tracking(0.8)
                            .foregroundStyle(LoreColor.bone)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(LoreColor.bone.opacity(0.11), in: Capsule())
                    }

                    Text(titleText)
                        .font(LoreType.display(size: 24, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(isGenerating ? "Threading nearby stories into one walk…" : "A fresh route through published Lore, built around your time.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 9) {
                        Image(systemName: isGenerating ? "point.3.connected.trianglepath.dotted" : "figure.walk.motion")
                            .symbolEffect(.pulse, options: .repeating, isActive: isGenerating && !reduceMotion)
                        Text(isGenerating ? "ROUTING" : "BUILD MY WALK")
                            .font(LoreType.micro)
                            .tracking(1)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(LoreColor.ink)
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .background(LoreColor.amber, in: Capsule())
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Clip the route artwork (it uses a negative trailing padding to sit
            // at the edge) to the card's rounded rect so it can't bleed past the
            // corner.
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(isGenerating)
        .accessibilityLabel(Text(titleText))
        .accessibilityHint(Text(isGenerating ? "Your route is being built." : "Builds a city walk from published Lore stops."))
    }
}

struct TourRow: View {
    let tour: Tour
    /// Whether the viewer is a Lore+ member (drives the premium lock marker).
    var isPlus: Bool = false
    var userID: String?
    @State private var progress = TourProgressStore.Progress.empty

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TourBrowseLayout.tourRowCornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardShape
                .fill(LoreColor.bone50)

            TourRouteArtwork(
                nodeCount: min(max(tour.stops.count, 3), 6),
                color: LoreColor.brass,
                activeFraction: progressFraction
            )
            .frame(width: TourBrowseLayout.tourRowArtworkWidth, height: TourBrowseLayout.tourRowArtworkHeight)
            .opacity(0.18)
            .padding(.top, TourBrowseLayout.tourRowArtworkTopInset)
            .padding(.trailing, TourBrowseLayout.tourRowArtworkTrailingInset)
            .accessibilityHidden(true)
            .allowsHitTesting(false)

            HStack(alignment: .top, spacing: 13) {
                ZStack {
                    Circle()
                        .fill(LoreColor.ink)
                    Circle()
                        .strokeBorder(LoreColor.amber.opacity(0.8), lineWidth: 1)
                        .padding(3)
                    Text(tour.displayEmoji)
                        .font(.system(size: 25))
                }
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(progress.isCompleted ? "TRAIL COMPLETE" : "CURATED FIELD WALK")
                            .font(LoreType.micro)
                            .tracking(1)
                            .foregroundStyle(progress.isCompleted ? LoreColor.success : LoreColor.brass700)
                        if tour.isPremium && !isPlus {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(LoreColor.brass700)
                        }
                    }

                    Text(tour.title)
                        .font(LoreType.display(size: 20, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)

                    if let blurb = tour.blurb {
                        Text(blurb)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.ink600)
                            .lineLimit(2)
                    }

                    tourFacts

                    if let stopIndex = progress.stopIndex, !progress.isCompleted {
                        TourRowProgress(current: stopIndex + 1, total: tour.stops.count)
                    } else if progress.isCompleted {
                        Label("Saved to your Lore trail", systemImage: "checkmark.seal.fill")
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.success)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(15)
        }
        .clipShape(cardShape)
        .overlay {
            cardShape
                .strokeBorder(LoreColor.bone300.opacity(0.8), lineWidth: 1)
        }
        .loreElevation(.elev1)
        .accessibilityElement(children: .combine)
        .onAppear {
            progress = TourProgressStore.progress(
                for: tour.slug,
                userID: userID,
                stopCount: tour.stops.count
            )
        }
    }

    private var progressFraction: Double {
        if progress.isCompleted { return 1 }
        guard let stopIndex = progress.stopIndex, !tour.stops.isEmpty else { return 0 }
        return Double(stopIndex + 1) / Double(tour.stops.count)
    }

    @ViewBuilder
    private var tourFacts: some View {
        HStack(spacing: 10) {
            if let duration = tour.durationMin {
                Label("\(duration) min", systemImage: "clock")
            }
            if let distance = tour.distanceKm {
                Label(String(format: "%.1f km", distance), systemImage: "figure.walk")
            }
            if !tour.stops.isEmpty {
                Label("\(tour.stops.count)", systemImage: "mappin.and.ellipse")
            }
        }
        .font(LoreType.micro)
        .foregroundStyle(LoreColor.ink600)
        .labelStyle(.titleAndIcon)
    }
}

/// A compact route signature used across the browse surface. It is decorative;
/// the adjacent text remains the complete accessible description of the tour.
private struct TourRouteArtwork: View {
    let nodeCount: Int
    let color: Color
    let activeFraction: Double

    var body: some View {
        GeometryReader { proxy in
            let points = routePoints(in: proxy.size)
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [3, 7]))

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(nodeIsActive(index) ? color : LoreColor.bone300)
                        .frame(width: index == points.count - 1 ? 10 : 7, height: index == points.count - 1 ? 10 : 7)
                        .overlay(Circle().strokeBorder(LoreColor.ink.opacity(0.7), lineWidth: 1))
                        .position(point)
                }
            }
        }
    }

    private func nodeIsActive(_ index: Int) -> Bool {
        let count = max(nodeCount, 1)
        return Double(index + 1) / Double(count) <= max(activeFraction, 0.01)
    }

    private func routePoints(in size: CGSize) -> [CGPoint] {
        let count = max(nodeCount, 2)
        return (0..<count).map { index in
            let fraction = CGFloat(index) / CGFloat(count - 1)
            let x = 8 + fraction * max(size.width - 16, 0)
            let wave = index.isMultiple(of: 2) ? 0.28 : 0.72
            return CGPoint(x: x, y: size.height * wave)
        }
    }
}

private struct TourRowProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LoreColor.bone200)
                    Capsule()
                        .fill(LoreColor.amber)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)

            Text("Resume at checkpoint \(current) of \(total)")
                .font(LoreType.micro)
                .foregroundStyle(LoreColor.brass700)
        }
        .accessibilityElement(children: .combine)
    }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(current) / Double(total), 0), 1)
    }
}

// MARK: - Model

@Observable
@MainActor
final class ToursModel {
    enum State {
        case loading
        case empty
        case failed(String)
        case loaded
    }

    private(set) var state: State = .loading
    private(set) var toursByCity: [String: [Tour]] = [:]
    /// The city the current `toursByCity` was loaded for, so a re-scope reloads
    /// and the same city doesn't refetch.
    private var loadedCity: String?
    private var loadRequestID = UUID()

    var cities: [String] { toursByCity.keys.sorted() }

    /// Load the curated tours for `city`. Reloads when the city changes;
    /// re-selecting the same city is a no-op.
    func load(city: String, force: Bool = false) async {
        guard force || city != loadedCity else { return }
        let requestID = UUID()
        loadRequestID = requestID
        state = .loading
        do {
            let tours = try await LoreAPI.shared.tours(city: city)
            guard loadRequestID == requestID else { return }
            toursByCity = Dictionary(grouping: tours, by: \.city)
            loadedCity = city
            state = tours.isEmpty ? .empty : .loaded
        } catch {
            guard loadRequestID == requestID else { return }
            loadedCity = city
            toursByCity = [:]
            state = .failed("Check your connection and try again.")
        }
    }

    /// Build the "1 Hour In {city}" walk on demand (strategy Phase 2). Fetches
    /// the city's places and routes them. Throws on a network failure (so the
    /// caller can distinguish "offline" from "too few stops"); returns nil when
    /// the fetch succeeds but there aren't enough stops to route a walk.
    func oneHourTour(city: String, durationMin: Int = 60) async throws -> Tour? {
        let places = try await LoreAPI.shared.places(city: city)
        return OneHourTour.generate(city: city, places: places, from: nil, durationMin: durationMin)
    }
}
