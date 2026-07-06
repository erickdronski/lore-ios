import SwiftUI

/// The Passport scrapbook (lore/docs/26-TRAVEL-PASSPORT.md §2, "the shoebox of
/// postcards made digital"). One `travel_stats` RPC feeds the whole surface:
///
/// - **The tally**: the big Fraunces numerals, places / cities / countries /
///   this-year, the ongoing-Wrapped headline, always live.
/// - **The stamp wall**: one stamp per city collected, slightly rotated in a
///   Brass ring, the passport-stamp metaphor.
/// - **The postcard feed**: reverse-chronological visits, each a postcard with
///   the place's lead photo (resolved via `WikipediaService.portraitURL`), name,
///   city, date, and the user's note; tapping routes back into the dossier.
/// - **The opt-in**: "Record my travels", the default-OFF switch that turns on
///   passive walk-and-collect (docs/26 §3).
/// - **A composed empty state** for the reader who hasn't collected anything yet.
///
/// This view is shown ABOVE the achievements wall inside `PassportView`, so the
/// Passport tab reads travel-first (the tally and postcards), then the badges.
struct TravelPassportView: View {
    /// Routes a tapped postcard to its place (the host installs `onRoute`).
    @Environment(AppRouter.self) private var router
    @Environment(AuthService.self) private var auth
    /// The Travel stores, the `tracker` inside drives the opt-in toggle. Read
    /// from the same `TravelSession` the map uses, so there's one owner and no
    /// extra environment key that could be missing.
    @Environment(TravelSession.self) private var travel

    @State private var model = TravelStatsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            switch model.state {
            case .loading:
                loadingBlock
            case .empty:
                TravelEmptyState(signedIn: auth.isSignedIn)
                recordTravelsToggle
            case .loaded(let stats):
                tally(stats.totals)
                if !stats.cityStamps.isEmpty {
                    stampWall(stats.cityStamps)
                }
                if !stats.recentVisits.isEmpty {
                    postcardFeed(stats.recentVisits)
                }
                recordTravelsToggle
            case .failed(let message):
                failureBlock(message)
            }
        }
        .task(id: auth.session?.accessToken) { await model.load(auth: auth) }
    }

    // MARK: - Tally (the Wrapped headline)

    private func tally(_ totals: TravelStats.Totals) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Everywhere you've been")
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)

            // Four big numerals, places lead (the count that matters most), the
            // rest read as the Wrapped supporting cast.
            HStack(alignment: .top, spacing: 0) {
                tallyStat(totals.places, "Places", tint: LoreColor.amber)
                tallyDivider
                tallyStat(totals.cities, "Cities", tint: LoreColor.brass300)
                tallyDivider
                tallyStat(totals.countries, "Countries", tint: LoreColor.brass300)
                tallyDivider
                tallyStat(totals.thisYear, "This year", tint: LoreColor.brass300)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24).fill(LoreColor.ink800))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(LoreColor.ink700, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func tallyStat(_ value: Int, _ caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CountUpText.integer(value, font: LoreType.display(size: 30, weight: .semibold))
                .foregroundStyle(tint)
            Text(caption.uppercased())
                .loreLabelStyle()
                .tracking(0.6)
                .foregroundStyle(LoreColor.ink600)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tallyDivider: some View {
        Rectangle().fill(LoreColor.ink700).frame(width: 1, height: 40)
    }

    // MARK: - The stamp wall

    private func stampWall(_ stamps: [TravelStats.CityStamp]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Passport stamps", symbol: "seal")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                ],
                spacing: 18
            ) {
                ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                    CityStampView(stamp: stamp, index: index)
                        .onTapGesture { router.route(.city(slug: stamp.slug)) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - The postcard feed

    private func postcardFeed(_ visits: [TravelStats.RecentVisit]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Recent postcards", symbol: "photo.on.rectangle.angled")
            VStack(spacing: 14) {
                ForEach(visits) { visit in
                    PostcardView(visit: visit)
                        .onTapGesture { route(to: visit) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func route(to visit: TravelStats.RecentVisit) {
        Haptics.play(.dossierOpen)
        router.route(.place(id: visit.placeID, city: visit.city))
    }

    // MARK: - The opt-in toggle

    private var recordTravelsToggle: some View {
        RecordTravelsToggle(tracker: travel.tracker, signedIn: auth.isSignedIn)
            .padding(.horizontal, 16)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LoreColor.brass300)
            Text(title)
                .font(LoreType.display(size: 20, weight: .medium))
                .foregroundStyle(LoreColor.bone)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Degraded states

    /// Content-shaped loading (no bare spinner): a dim tally block over a stamp
    /// grid, so the swap to the real scrapbook is a cross-fade with no jump.
    private var loadingBlock: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LoreColor.ink800)
                .frame(height: 116)
                .shimmer()
                .padding(.horizontal, 16)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                ],
                spacing: 18
            ) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(LoreColor.ink800).frame(width: 88, height: 88).shimmer()
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityLabel("Loading your travels")
    }

    private func failureBlock(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(LoreColor.amber)
            Text(message)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.75))
            Spacer()
            Button("Retry") { Task { await model.load(auth: auth) } }
                .font(LoreType.button)
                .tint(LoreColor.amber)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(LoreColor.ink800))
        .padding(.horizontal, 16)
    }
}

// MARK: - City stamp

/// One passport stamp: the city medallion in a Brass ring, its name, count, and
/// stamp date, tilted a few degrees so the wall reads like an inked page rather
/// than a spreadsheet (docs/26 §2 "slight rotation, Brass ring"). The tilt is
/// deterministic per index so it never jitters across renders, and it flattens
/// under Reduce Motion.
struct CityStampView: View {
    let stamp: TravelStats.CityStamp
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A stable small tilt, alternating direction, so the grid looks hand-placed.
    private var rotation: Angle {
        guard !reduceMotion else { return .zero }
        let magnitudes: [Double] = [-6, 4, -3, 5, -5, 3]
        return .degrees(magnitudes[index % magnitudes.count])
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(LoreColor.brass, lineWidth: 2)
                    .background(Circle().fill(LoreColor.ink900))
                    .frame(width: 76, height: 76)
                VStack(spacing: 2) {
                    Text(stamp.displayEmoji)
                        .font(.system(size: 26))
                    if stamp.count > 1 {
                        Text("\(stamp.count)")
                            .font(LoreType.micro)
                            .foregroundStyle(LoreColor.brass300)
                    }
                }
            }
            .rotationEffect(rotation)

            Text(stamp.displayName)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let day = TravelStats.dayLabel(stamp.firstVisitedAt) {
                Text(day)
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.ink600)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(stamp.displayName), \(stamp.count) collected"))
    }
}

// MARK: - Postcard

/// One postcard in the feed: the lead photo (resolved from the place's
/// `wikipedia_title` via `WikipediaService`, the same best-effort path the
/// culture surface uses), the place name, city, date, and the user's note. A
/// GPS-collected visit wears a small "auto" tag so the magic is legible.
struct PostcardView: View {
    let visit: TravelStats.RecentVisit

    /// The resolved lead-photo URL, `nil` until the lookup lands (or a confirmed
    /// miss, in which case the emoji plate stays).
    @State private var photoURL: URL?
    @State private var didResolve = false

    var body: some View {
        HStack(spacing: 0) {
            leadPhoto
            details
        }
        .frame(height: 116)
        .background(RoundedRectangle(cornerRadius: 18).fill(LoreColor.ink800))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LoreColor.ink700, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .task { await resolvePhoto() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Photo

    @ViewBuilder
    private var leadPhoto: some View {
        ZStack {
            if let photoURL {
                BlurUpAsyncImage(url: photoURL, contentMode: .fill)
            } else {
                emojiPlate
            }
        }
        .frame(width: 116, height: 116)
        .clipped()
    }

    private var emojiPlate: some View {
        ZStack {
            LoreColor.ink900
            Text(visit.displayEmoji)
                .font(.system(size: 34))
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(visit.placeName)
                    .font(LoreType.display(size: 17, weight: .semibold))
                    .foregroundStyle(LoreColor.bone)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if visit.source == "gps" { autoTag }
            }

            if let city = visit.displayCity {
                Text(city)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.brass300)
                    .lineLimit(1)
            }

            if let note = visit.note, !note.isEmpty {
                Text(note)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.72))
                    .lineLimit(2)
            } else if let day = TravelStats.dayLabel(visit.visitedAt) {
                Text(day)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let note = visit.note, !note.isEmpty,
               let day = TravelStats.dayLabel(visit.visitedAt) {
                Text(day)
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.ink600)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The "auto" chip on a GPS-collected postcard, so the reader sees which
    /// visits the app collected for them.
    private var autoTag: some View {
        Text("AUTO")
            .font(LoreType.micro)
            .foregroundStyle(LoreColor.brass300)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(LoreColor.brass.opacity(0.16)))
            .overlay(Capsule().strokeBorder(LoreColor.brass.opacity(0.5), lineWidth: 1))
            .accessibilityLabel(Text("Auto-collected"))
    }

    private var accessibilityLabel: String {
        var parts = [visit.placeName]
        if let city = visit.displayCity { parts.append(city) }
        if let day = TravelStats.dayLabel(visit.visitedAt) { parts.append(day) }
        return parts.joined(separator: ", ")
    }

    // MARK: Photo resolution

    private func resolvePhoto() async {
        guard !didResolve else { return }
        didResolve = true
        guard let title = visit.wikipediaTitle, !title.isEmpty else { return }
        let url = await WikipediaService.shared.portraitURL(for: title)
        if let url { photoURL = url }
    }
}

// MARK: - Empty state

/// The composed empty scrapbook (docs/26 §3 "A composed empty state"): an
/// inviting blank page, not a spinner or a dead end. Signed-out reads honestly
/// (reading is never gated); signed-in nudges the first collection.
struct TravelEmptyState: View {
    let signedIn: Bool

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(LoreColor.brass.opacity(0.5), lineWidth: 2)
                    .frame(width: 88, height: 88)
                Image(systemName: "map")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(LoreColor.brass300)
            }
            .rotationEffect(.degrees(-5))

            Text("Your scrapbook starts here")
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)
                .multilineTextAlignment(.center)

            Text(signedIn
                 ? "Walk up to a place, or tap \"I've been here\", and it lands here as a postcard. Every city you collect earns a stamp."
                 : "Sign in and the places you visit become postcards and passport stamps, a living record of everywhere you've been.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).fill(LoreColor.ink800))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(LoreColor.ink700, lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

// MARK: - Record-my-travels toggle

/// The "Record my travels" opt-in (docs/26 §3): default OFF, one honest line of
/// copy, and a clear note that it wants Always location. Turning it on flips the
/// preference and asks Core Location for the passive (Always) grant, turning it
/// off tears monitoring down. When off, only manual + foreground near-approach
/// visits happen, exactly today's behavior.
struct RecordTravelsToggle: View {
    /// The tracker to drive; may be absent in previews.
    var tracker: VisitTracker?
    let signedIn: Bool

    @State private var isOn = RecordTravelsPreference.isOn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 10) {
                    Image(systemName: "location.viewfinder")
                        .foregroundStyle(LoreColor.amber)
                    Text("Record my travels")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.bone)
                }
            }
            .tint(LoreColor.brass700)
            .disabled(!signedIn)

            Text("Off by default. Turn it on and Lore quietly records the places you walk through for your Passport, using your location in the background. Nothing is shared, and this is never ad tracking. Turn it off anytime.")
                .font(LoreType.micro)
                .foregroundStyle(LoreColor.bone.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            if !signedIn {
                Text("Sign in to record your travels.")
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.brass300)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(LoreColor.ink800))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LoreColor.ink700, lineWidth: 1))
        .onChange(of: isOn) { _, newValue in
            RecordTravelsPreference.isOn = newValue
            if newValue {
                // Opting in: ask for the passive Always grant.
                tracker?.requestAlwaysAuthorizationForPassive()
            } else {
                tracker?.stop()
            }
        }
    }
}

// MARK: - Model

/// Fetches the `travel_stats` payload and holds it for the scrapbook. `nil`
/// session ⇒ the empty state (no visits to read). A fetch failure surfaces a
/// gentle retry, never a blank tab.
@Observable
@MainActor
final class TravelStatsModel {
    enum State {
        case loading
        case empty
        case loaded(TravelStats)
        case failed(String)
    }

    private(set) var state: State = .loading

    func load(auth: AuthService) async {
        // Signed out: nothing to read, show the composed empty state.
        guard let token = auth.session?.accessToken,
              let userID = auth.session?.user.id else {
            state = .empty
            return
        }
        state = .loading
        do {
            let stats = try await LoreAPI.shared.travelStats(
                userID: userID,
                accessToken: token
            )
            state = stats.isEmpty ? .empty : .loaded(stats)
        } catch {
            state = .failed("Couldn't load your travels. Check your connection and try again.")
        }
    }
}
