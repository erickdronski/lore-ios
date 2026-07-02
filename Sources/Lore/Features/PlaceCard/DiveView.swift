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
    /// dossier is presented standalone (scanner, tours) — the medallion then just
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
                    Text("This dossier hasn't been written yet — dives are synthesized once and cached, never generated on the spot.")
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.ink600)
                case .failed(let message):
                    Text(message)
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.errorDark)
                case .loaded(let dive):
                    diveBody(dive)
                }

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

    /// The dossier header: the emoji medallion (the morph *target* — it grows
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
            Text(narrative)
                .font(LoreType.reader)
                .lineSpacing(7)
                .foregroundStyle(LoreColor.bone)
                .fixedSize(horizontal: false, vertical: true)
        }

        let photos = dive.media.filter { ($0.kind ?? "image") != "audio" }
        if !photos.isEmpty {
            DiveGallery(media: photos)
        }

        if !dive.timeline.isEmpty {
            TimelineStrip(events: dive.timeline)
        }
    }

    // MARK: Links

    @ViewBuilder
    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources & links")
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)

            // Maps deep-link — always available, built from place coordinates.
            if let mapsURL = appleMapsURL {
                Link(destination: mapsURL) {
                    LinkRow(icon: "map", title: "Open in Maps", subtitle: "Walk there")
                }
                .buttonStyle(.pressable)
            }

            if case .loaded(let dive) = model.state {
                ForEach(dive.links) { link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            LinkRow(
                                icon: "link",
                                title: link.displayTitle,
                                subtitle: URL(string: link.url)?.host()
                            )
                        }
                        .buttonStyle(.pressable)
                    }
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
    /// like the narrative paragraph, then a row of timeline-node tiles — so the
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
            state = .failed("Couldn't load this dossier — check your connection.")
        }
    }
}

// MARK: - Horizontal timeline

/// The horizontal timeline: `ScrollView(.horizontal)` with view-aligned snap
/// targets, Amber node dots on an Ink-700 rail, years set in the display
/// (Fraunces-ready) face.
struct TimelineStrip: View {
    let events: [TimelineEvent]
    /// The event currently snapped into view — drives the selection tick.
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
                // Decade snap — one selection tick per snap
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
    /// True when this node is the one snapped into view — it pops forward.
    var isSnapped: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Node dot on the rail — compound Amber per the pin rules.
            HStack(spacing: 8) {
                Circle()
                    .fill(LoreColor.amber)
                    .strokeBorder(LoreColor.ink, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    // The snapped dot swells a touch — the "pop" landing.
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

/// The dossier photo gallery: a horizontal shelf of blur-up tiles. Each image
/// loads through `BlurUpAsyncImage` (shimmer placeholder → cross-fade to sharp,
/// no pop-in, LUXURY-MOTION §3) and the tiles cascade in with the shared 40 ms
/// fade+rise. Photographs breathe, so the lead tile gets a slow Ken-Burns drift.
struct DiveGallery: View {
    let media: [DiveMedia]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gallery")
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                        BlurUpAsyncImage(url: URL(string: item.url))
                            .frame(width: 240, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .loreElevation(.elev1)
                            .modifier(StaggerChild(
                                index: index,
                                appeared: appeared,
                                reduceMotion: reduceMotion
                            ))
                            .accessibilityLabel(Text(item.caption ?? "Photo"))
                    }
                }
            }
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation { appeared = true }
            }
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
