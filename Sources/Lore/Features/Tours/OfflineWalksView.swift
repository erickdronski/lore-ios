import SwiftUI

struct OfflineWalksView: View {
    private let walks: [OfflineWalk]
    private let cityNames: [String: String]
    private let citiesWithWalks: [String]
    @State private var selectedCity: String?
    @Environment(AuthService.self) private var auth

    init(tours: [Tour], places: [Place], dives: [Dive], initialCity: String? = nil, cities: [City] = []) {
        let byPlace = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byDive = Dictionary(dives.map { ($0.placeID, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(cities.map { ($0.slug, $0.name) }, uniquingKeysWith: { first, _ in first })
        let available = tours.compactMap { OfflineWalk(tour: $0, places: byPlace, dives: byDive) }
        walks = available.sorted { $0.tour.title.localizedStandardCompare($1.tour.title) == .orderedAscending }
        cityNames = names
        citiesWithWalks = Set(available.map { $0.tour.city }).sorted {
            (names[$0] ?? $0).localizedStandardCompare(names[$1] ?? $1) == .orderedAscending
        }
        _selectedCity = State(initialValue: initialCity.flatMap { city in
            available.contains { $0.tour.city == city } ? city : nil
        })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if citiesWithWalks.count > 1 {
                    Picker("City", selection: $selectedCity) {
                        Text("All cities").tag(String?.none)
                        ForEach(citiesWithWalks, id: \.self) { city in
                            Text(cityName(city)).tag(Optional(city))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("walks.cityFilter")
                }
                if walks.isEmpty {
                    ContentUnavailableView("No walks available", systemImage: "figure.walk",
                                           description: Text("Browse the places in this guide."))
                }
                ForEach(walks.filter { selectedCity == nil || $0.tour.city == selectedCity }) { walk in
                    NavigationLink {
                        OfflineWalkReader(walk: walk, owner: auth.session?.user.id)
                            .id(auth.session?.user.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(cityName(walk.tour.city)).font(LoreType.label).foregroundStyle(LoreColor.brass300)
                            Text(walk.tour.title).font(LoreType.displayL)
                            if let blurb = walk.tour.blurb { Text(blurb).font(LoreType.body) }
                            Label(walk.tour.summaryLine, systemImage: "figure.walk").font(.subheadline)
                            if let first = walk.stops.first {
                                Label("Start at " + first.place.name, systemImage: "mappin")
                                    .font(.subheadline).foregroundStyle(LoreColor.bone200)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(alignment: .topTrailing) {
                            LoreTileArtwork(kind: .route, accent: LoreColor.brass, intensity: 0.12, animates: false)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        .background(LoreColor.ink900)
                        .foregroundStyle(LoreColor.bone50)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("walks.route." + walk.tour.slug)
                }
            }
            .frame(maxWidth: 680)
            .padding(18)
            .frame(maxWidth: .infinity)
        }
        .background(LoreColor.bone)
        .navigationTitle("Field walks")
        .preferredColorScheme(.light)
    }

    private func cityName(_ slug: String) -> String {
        cityNames[slug] ?? slug.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private struct OfflineWalkReader: View {
    let walk: OfflineWalk
    @State private var session: OfflineWalkSession
    @State private var narration = NarrationService()
    @Environment(\.scenePhase) private var scenePhase

    init(walk: OfflineWalk, owner: String?) {
        self.walk = walk
        _session = State(initialValue: OfflineWalkSession(walk: walk, owner: owner))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(walk.tour.title).font(LoreType.displayL)
                        .accessibilityAddTraits(.isHeader).id("walk.top")
                    if session.complete {
                        completion
                    } else {
                        stopReader
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: session.index) { _, _ in proxy.scrollTo("walk.top", anchor: .top) }
            .onChange(of: session.complete) { _, _ in proxy.scrollTo("walk.top", anchor: .top) }
        }
        .background(LoreColor.bone)
        .foregroundStyle(LoreColor.ink)
        .tint(LoreColor.brass700)
        .navigationTitle("Field walk")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { if narration.isActive { narration.stop() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, narration.isActive { narration.stop() }
        }
    }

    @ViewBuilder private var stopReader: some View {
        let stop = walk.stops[session.index]
        VStack(alignment: .leading, spacing: 10) {
            Text("Stop \(session.index + 1) of \(walk.stops.count)").font(LoreType.label)
                .foregroundStyle(LoreColor.amber)
            Text("Stop order").font(.caption2).foregroundStyle(LoreColor.bone200)
            OfflineStopDiagram(stops: walk.stops, current: session.index)
                .frame(height: 74)
                .accessibilityHidden(true)
            Text(stop.place.name).font(LoreType.displayL)
                .accessibilityIdentifier("walks.stopTitle")
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(LoreColor.bone50)
        .background(LoreColor.ink900, in: RoundedRectangle(cornerRadius: 16))

        ForEach(stop.paragraphs, id: \.self) { paragraph in
            Text(paragraph).font(LoreType.reader).lineSpacing(4)
        }
        if !stop.paragraphs.isEmpty {
            Button {
                if narration.isActive { narration.stop() }
                else { narration.speakDossier(([stop.place.name] + stop.paragraphs).joined(separator: ". ")) }
            } label: {
                Label(narration.isActive ? "Stop narration" : "Listen to this stop",
                      systemImage: narration.isActive ? "stop.circle" : "speaker.wave.2")
            }.accessibilityIdentifier("walks.listen")
            if let error = narration.playbackError { Text(error).font(.footnote) }
        }
        if let dive = stop.dive, let source = dive.links.sourceRecordURL ?? dive.links.websiteURL {
            Link(destination: source) { Label(dive.source ?? "Place source", systemImage: "book") }
        }

        if let url = URL(string: "https://maps.apple.com/?daddr=\(stop.place.lat),\(stop.place.lng)&dirflg=w") {
            Link(destination: url) { Label("Walking directions in Maps", systemImage: "arrow.triangle.turn.up.right.diamond") }
        }
        Button {
            if narration.isActive { narration.stop() }
            session.next()
        } label: {
            Label(session.index + 1 == walk.stops.count ? "Finish walk" : "Next stop",
                  systemImage: session.index + 1 == walk.stops.count ? "checkmark" : "arrow.right")
                .font(LoreType.button).frame(maxWidth: .infinity).padding(5)
        }
        .buttonStyle(.borderedProminent).tint(LoreColor.ink).accessibilityIdentifier("walks.next")
        if session.index > 0 {
            Button("Previous stop") {
                if narration.isActive { narration.stop() }
                session.previous()
            }
        }
        Divider()
        DisclosureGroup("Itinerary") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(walk.stops.enumerated()), id: \.element.id) { index, row in
                    Text("\(index + 1). \(row.place.name)").font(.subheadline)
                }
                if let note = walk.tour.routeNote { Text(note).font(.footnote) }
                if let url = walk.tour.routeSourceURL { Link("Route source", destination: url) }
            }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Walk complete", systemImage: "checkmark.seal.fill")
                .font(LoreType.displayM).foregroundStyle(LoreColor.brass700)
                .accessibilityIdentifier("walks.complete")
            ForEach(walk.stops) { stop in
                Label(stop.place.name, systemImage: "checkmark")
            }
            Button("Walk again") { session.restart() }
                .buttonStyle(.borderedProminent).tint(LoreColor.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A north-up schematic of the stop locations. The dotted line indicates reading
/// order; walking directions are available separately from each stop.
private struct OfflineStopDiagram: View {
    let stops: [OfflineWalk.Stop]
    let current: Int

    var body: some View {
        Canvas { context, size in
            guard let anchor = stops.first?.place else { return }
            let longitudeScale = cos(anchor.lat * .pi / 180)
            let offsets = stops.map { stop in
                CGPoint(x: (stop.place.lng - anchor.lng) * longitudeScale,
                        y: anchor.lat - stop.place.lat)
            }
            let xs = offsets.map(\.x), ys = offsets.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return }
            let scale = min(max(1, size.width - 28) / max(maxX - minX, 0.000001),
                            max(1, size.height - 24) / max(maxY - minY, 0.000001))
            let points = offsets.map { point in
                CGPoint(x: size.width / 2 + (point.x - (maxX + minX) / 2) * scale,
                        y: size.height / 2 + (point.y - (maxY + minY) / 2) * scale)
            }
            var line = Path()
            line.addLines(points)
            context.stroke(line, with: .color(LoreColor.bone300),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
            for point in points {
                let dot = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dot), with: .color(LoreColor.bone50))
            }
            let point = points[current]
            let marker = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
            context.fill(Path(ellipseIn: marker), with: .color(LoreColor.amber))
            context.draw(Text(String(current + 1)).font(.caption2.bold()).foregroundColor(LoreColor.ink),
                         at: point)
        }
    }
}
