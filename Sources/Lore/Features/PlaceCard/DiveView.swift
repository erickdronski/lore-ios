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
    @State private var model = DiveModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

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
            .padding(16)
            // Clear the dismiss chevron the host overlays top-left.
            .padding(.top, 44)
        }
        .background(LoreColor.ink950.ignoresSafeArea())
        .task { await model.load(placeID: place.id) }
    }

    // MARK: Header (morph target)

    /// The dossier header: the emoji medallion (the morph *target*, it grows
    /// from the Layer-1 card's medallion) beside the place name in display XL.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            medallion
            Text(place.name)
                .font(LoreType.displayXL)
                .foregroundStyle(LoreColor.bone)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Dossier body

    @ViewBuilder
    private func diveBody(_ dive: Dive) -> some View {
        if let narrative = dive.narrative {
            // Compact by default with a Read more toggle, so the gallery and
            // timeline sit close instead of below a wall of text (TestFlight
            // feedback: "go deeper exposes all the text; keep it compact with a
            // read more button so everything below is pushed up and visible").
            ExpandableNarrative(text: narrative)
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
                            Text(expanded ? "Read less" : "Read more")
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
            Text("Sources & links")
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

    func load(placeID: String) async {
        do {
            if let dive = try await LoreAPI.shared.dive(placeID: placeID) {
                state = .loaded(dive)
            } else {
                state = .empty
            }
        } catch {
            state = .failed("Couldn't load this dossier, check your connection.")
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
            Text("Timeline")
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
                    Text("Gallery")
                        .font(LoreType.displayM)
                        .foregroundStyle(LoreColor.bone)

                    BlurUpAsyncImage(url: imageURL)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
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
