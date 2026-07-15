import SwiftUI

/// The deep-dive dossier (brand/DESIGN.md §7 `DiveSheet`): Ink background,
/// narrative in the `reader` face, a HORIZONTAL snap-scrolling timeline with
/// Amber nodes and display-face years, then links (the attribution surface —
/// CC-BY-SA prose may only render where these source links do, docs/04 §2.2).
struct DiveView: View {
    let place: Place
    /// The shared-element morph namespace (LUXURY-MOTION §6): when the dossier is
    /// grown from a Layer-1 card, the pin/emoji medallion morphs from the card
    /// header into this header via `matchedGeometryEffect`. `nil` when the
    /// dossier is presented standalone (scanner, tours), the medallion then just
    /// appears, no morph, which is correct: nothing to morph *from*.
    var morphNamespace: Namespace.ID? = nil
    /// The shared id the medallion morphs across (unique per place).
    var medallionID: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(DiveMeter.self) private var diveMeter
    @Environment(StoreKitService.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var model = DiveModel()
    /// On-device narration of the full dossier (the Lore+ audio pillar). One per
    /// dossier; stopped on disappear so it never keeps talking off-screen.
    @State private var narration = NarrationService()
    /// True once the free daily dive allowance is spent: the dossier body defers
    /// to the gate card (docs/00 §7). Lore+ members are never gated.
    @State private var gated = false
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                tagRow

                if gated {
                    // The place name (header) stays above the gate, so the
                    // wonder isn't yanked away, only the extra read is deferred.
                    DiveGateCard(placeName: place.name, onUnlock: { showPaywall = true })
                } else {
                    switch model.state {
                    case .loading:
                        loadingSkeleton
                    case .empty:
                        Text("This dossier hasn't been written yet. Dives are synthesized once and cached, never generated on the spot.")
                            .font(LoreType.body)
                            .foregroundStyle(LoreColor.ink600)
                    case .failed(let message):
                        Text(message)
                            .font(LoreType.body)
                            .foregroundStyle(LoreColor.errorDark)
                    case .loaded(let dive):
                        diveBody(dive)
                    }

                    // Apple street-level view, shown only where Apple has coverage.
                    LookAroundSection(place: place)

                    linksSection
                }
            }
            .padding(16)
            // Clear the dismiss chevron the host overlays top-left.
            .padding(.top, 44)
        }
        .background(LoreColor.ink950.ignoresSafeArea())
        .onDisappear { narration.stop() }
        .task {
            // Dive-open gate (docs/00 §7): members and free users with dives left
            // open normally. Spend a free dive only after real dossier content
            // loads; an empty or failed request must not consume the allowance.
            if diveMeter.canOpenDive(isPlus: entitlements.isPlus) {
                if await model.load(placeID: place.id) {
                    diveMeter.recordDiveOpened(isPlus: entitlements.isPlus)
                }
            } else {
                gated = true
            }
        }
        // A completed purchase lifts the gate in place and loads the dossier.
        .onChange(of: entitlements.isPlus) { _, isPlus in
            if isPlus && gated {
                gated = false
                Task { _ = await model.load(placeID: place.id) }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(entitlements: entitlements, store: store, auth: auth, context: .fourthDive)
        }
    }

    // MARK: Header (morph target)

    /// The dossier header: the emoji medallion (the morph *target*, it grows
    /// from the Layer-1 card's medallion) beside the place name in display XL.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                medallion
                Text(place.name)
                    .font(LoreType.displayXL)
                    .foregroundStyle(LoreColor.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Free users see their remaining daily dives up front, so the 4th-dive
            // gate is anticipated rather than a surprise mid-read.
            if !entitlements.isPlus && !gated {
                DiveMeterBadge(remaining: diveMeter.remainingToday)
            }
        }
    }

    /// The emoji disc that participates in the shared-element morph. When a
    /// namespace is supplied it carries the same `matchedGeometryEffect` id the
    /// Layer-1 card's medallion did, so it *is* that disc, grown to dossier size.
    @ViewBuilder
    private var medallion: some View {
        let disc = Text(place.displayEmoji)
            .font(.system(size: 32))
            .frame(width: 60, height: 60)
            .background(Circle().fill(LoreColor.ink800))
            .overlay(Circle().strokeBorder(LoreColor.amber.opacity(0.4), lineWidth: 1))
        if let morphNamespace {
            // Non-source: the Layer-1 card header medallion is the geometry
            // source; this disc *receives* that geometry, so the emoji appears to
            // grow from the card into the dossier rather than two discs fighting.
            disc.matchedGeometryEffect(id: medallionID, in: morphNamespace, isSource: false)
        } else {
            disc
        }
    }

    /// The place's tags as branded chips (LoreTag), the registry-styled subset so
    /// internal slugs don't clutter the row. Was a fully-built system that
    /// rendered nowhere; now it gives the dossier a glanceable identity strip.
    @ViewBuilder
    private var tagRow: some View {
        let shown = place.tags.filter { LoreTagStyle.registry[$0] != nil }.prefix(6)
        if !shown.isEmpty {
            WrapLayout(spacing: 6) {
                ForEach(Array(shown), id: \.self) { LoreTag(tag: $0) }
            }
        }
    }

    // MARK: Dossier body

    @ViewBuilder
    private func diveBody(_ dive: Dive) -> some View {
        if let narrative = dive.narrative {
            // Compact by default with a Read more toggle, so the gallery and
            // timeline sit close instead of below a wall of text (TestFlight
            // feedback: "go deeper exposes all the text; keep it compact with a
            // read more button so everything below is pushed up and visible").
            // On-device translated into the reader's language (LocalizedContent),
            // badged honestly, falling back to the English original.
            LocalizedContent(source: narrative) { text, translated in
                VStack(alignment: .leading, spacing: 8) {
                    ExpandableNarrative(text: text)
                    if translated { TranslatedBadge() }
                }
            }
            .diveEntrance(index: 0)

            listenControl(narrative)
                .diveEntrance(index: 0)
        }

        if let wikipediaTitle = dive.media.wikipediaTitle {
            DiveGallery(wikipediaTitle: wikipediaTitle)
                .diveEntrance(index: 1)
        }

        // A real across-the-street Google Street View, proxied so the key stays
        // server-side. Hides itself where Google has no outdoor coverage.
        StreetViewSection(coordinate: place.coordinate)
            .diveEntrance(index: 2)

        if !dive.timeline.isEmpty {
            TimelineStrip(events: dive.timeline)
                .diveEntrance(index: 3)
        }
    }

    /// The Lore+ "Listen to the full story" control: on-device narration of the
    /// whole dossier (the real audio pillar, not just the scanner hook). Free
    /// users get a locked affordance that opens the paywall; members hear it.
    @ViewBuilder
    private func listenControl(_ narrative: String) -> some View {
        Button {
            if entitlements.isPlus {
                Haptics.play(.chipTap)
                if narration.isSpeaking { narration.stop() } else { narration.speakDossier(narrative) }
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: narration.isSpeaking ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(LoreColor.amber)
                Text(narration.isSpeaking ? "Stop" : "Listen to the full story")
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone)
                Spacer()
                if !entitlements.isPlus {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LoreColor.amber)
                }
            }
            .padding(14)
            .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LoreColor.amber.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entitlements.isPlus
            ? (narration.isSpeaking ? "Stop narration" : "Listen to the full story")
            : "Listen to the full story, a Lore Plus feature")
    }

    // MARK: Narrative

    /// The dossier narrative, collapsed to a few lines with a Read more toggle
    /// when it's long, so the gallery + timeline stay near the top.
    private struct ExpandableNarrative: View {
        let text: String
        @State private var expanded = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// Roughly longer than the collapsed window; only then do we truncate +
        /// offer Read more.
        private var isLong: Bool { text.count > 300 }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(LoreType.reader)
                    .lineSpacing(7)
                    .foregroundStyle(LoreColor.bone)
                    .lineLimit(expanded || !isLong ? nil : 6)
                    .fixedSize(horizontal: false, vertical: true)

                if isLong {
                    Button {
                        withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) {
                            expanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(expanded ? L10n.t("dossier.readLess") : L10n.t("dossier.readMore"))
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.amber)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Links

    @ViewBuilder
    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("dossier.sources"))
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)

            // Maps deep-link, always available, built from place coordinates.
            if let mapsURL = appleMapsURL {
                Link(destination: mapsURL) {
                    LinkRow(icon: "map", title: "Open in Maps", subtitle: "Walk there")
                }
                .buttonStyle(.pressable)
            }

            if case .loaded(let dive) = model.state {
                if let website = dive.links.website, let url = URL(string: website) {
                    Link(destination: url) {
                        LinkRow(icon: "link", title: "Official site", subtitle: url.host())
                    }
                    .buttonStyle(.pressable)
                }
                if let url = dive.links.wikipediaURL {
                    Link(destination: url) {
                        LinkRow(icon: "book", title: "Wikipedia", subtitle: "en.wikipedia.org")
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(.top, 8)
    }

    /// `maps://` deep-link into Apple Maps, centered and labeled.
    private var appleMapsURL: URL? {
        var components = URLComponents(string: "maps://")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(place.lat),\(place.lng)"),
            URLQueryItem(name: "q", value: place.name),
        ]
        return components?.url
    }

    /// Content-shaped dossier skeleton (LUXURY-MOTION §3): shimmer bars sized
    /// like the narrative paragraph, then a row of timeline-node tiles, so the
    /// swap to the real dossier is a cross-fade with no layout jump. Bars sit on
    /// the Ink ramp (this surface is dark), not the default Bone.
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<5, id: \.self) { i in
                    ShimmerBlock(
                        width: i == 4 ? 220 : nil,
                        height: 14,
                        cornerRadius: 5,
                        fill: LoreColor.ink800
                    )
                }
            }
            HStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LoreColor.ink800)
                        .frame(width: 200, height: 120)
                        .shimmer()
                }
            }
        }
        .accessibilityLabel("Loading the dossier")
    }
}

// MARK: - Model

@Observable
@MainActor
final class DiveModel {
    enum State {
        case loading
        case empty
        case failed(String)
        case loaded(Dive)
    }

    private(set) var state: State = .loading

    /// Returns true only when a real dossier loaded, used by DiveMeter so empty
    /// and failed requests never consume a free daily dive.
    func load(placeID: String) async -> Bool {
        do {
            if let dive = try await LoreAPI.shared.dive(placeID: placeID) {
                state = .loaded(dive)
                return true
            } else {
                state = .empty
                return false
            }
        } catch {
            state = .failed("Couldn't load this dossier, check your connection.")
            return false
        }
    }
}

// MARK: - Horizontal timeline

/// The horizontal timeline: `ScrollView(.horizontal)` with view-aligned snap
/// targets, Amber node dots on an Ink-700 rail, years set in the display
/// (Fraunces-ready) face.
struct TimelineStrip: View {
    let events: [TimelineEvent]
    /// The event currently snapped into view, drives the selection tick.
    @State private var snappedEventID: TimelineEvent.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("dossier.timeline"))
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(events) { event in
                        TimelineNode(event: event, isSnapped: snappedEventID == event.id)
                            .containerRelativeFrame(
                                .horizontal,
                                count: 5,
                                span: 4,
                                spacing: 12
                            )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $snappedEventID)
            .onChange(of: snappedEventID) { oldValue, newValue in
                // Decade snap, one selection tick per snap
                // (brand/ELEVATION.md §4); silent on first settle.
                if oldValue != nil, newValue != nil, oldValue != newValue {
                    Haptics.play(.timelineSnap)
                }
            }
            // The snapped node pops with `spring.bounce` (LUXURY-MOTION §6:
            // "timeline nodes pop with .bounce on snap"); Reduce Motion crossfades.
            .animation(LoreSpring.bounce(reduceMotion: reduceMotion), value: snappedEventID)
        }
    }
}

struct TimelineNode: View {
    let event: TimelineEvent
    /// True when this node is the one snapped into view, it pops forward.
    var isSnapped: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Node dot on the rail, compound Amber per the pin rules.
            HStack(spacing: 8) {
                Circle()
                    .fill(LoreColor.amber)
                    .strokeBorder(LoreColor.ink, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    // The snapped dot swells a touch, the "pop" landing.
                    .scaleEffect(isSnapped && !reduceMotion ? 1.25 : 1.0)
                Rectangle()
                    .fill(LoreColor.ink700)
                    .frame(height: 2)
            }

            HStack(spacing: 6) {
                if let emoji = event.emoji {
                    Text(emoji)
                }
                // The year rolls up on first view (LUXURY-MOTION §5 tickers).
                CountUpText.integer(
                    event.year,
                    font: LoreType.display(size: 22, weight: .semibold)
                )
                .foregroundStyle(LoreColor.amber)
            }

            Text(event.title)
                .font(LoreType.button)
                .foregroundStyle(LoreColor.bone)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = event.detail {
                Text(detail)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 14))
        // The whole snapped node lifts (scale + elevation) so the focused decade
        // reads forward of its neighbors (LUXURY-MOTION §6 pop on snap).
        .scaleEffect(isSnapped && !reduceMotion ? 1.03 : 1.0)
        .loreElevation(isSnapped ? .elev2 : .elev1)
    }
}

// MARK: - Gallery

/// The dossier's lead photo: resolved from `dive.media.wikipedia_title` through
/// the same Wikipedia summary API the culture portraits use (no dependency, no
/// key), then shown through `BlurUpAsyncImage` (shimmer placeholder →
/// cross-fade to sharp, no pop-in, LUXURY-MOTION §3). Self-hides on a confirmed
/// miss so a title without an image leaves no empty frame.
struct DiveGallery: View {
    let wikipediaTitle: String

    @State private var imageURL: URL?
    @State private var resolved = false

    var body: some View {
        Group {
            if !resolved || imageURL != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("dossier.gallery"))
                        .font(LoreType.displayM)
                        .foregroundStyle(LoreColor.bone)

                    BlurUpAsyncImage(url: imageURL)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        // A light backing so a dark or transparent Wikipedia
                        // image (some pages return a dark logo, not a photo)
                        // stays legible on the Ink dossier instead of vanishing.
                        // Full-bleed photos cover it; only letterboxed/logo art
                        // shows the frame.
                        .background(LoreColor.bone)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .loreElevation(.elev1)
                        .accessibilityLabel(Text("Photo of \(wikipediaTitle)"))
                }
            }
        }
        .task(id: wikipediaTitle) {
            imageURL = await WikipediaService.shared.portraitURL(for: wikipediaTitle)
            resolved = true
        }
    }
}

struct LinkRow: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(LoreColor.amber)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone)
                if let subtitle {
                    Text(subtitle)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13))
                .foregroundStyle(LoreColor.ink600)
        }
        .padding(12)
        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 14))
    }
}
