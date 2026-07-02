import SwiftUI

/// The deep-dive dossier (brand/DESIGN.md §7 `DiveSheet`): Ink background,
/// narrative in the `reader` face, a HORIZONTAL snap-scrolling timeline with
/// Amber nodes and display-face years, then links (the attribution surface —
/// CC-BY-SA prose may only render where these source links do, docs/04 §2.2).
struct DiveView: View {
    let place: Place
    @State private var model = DiveModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(place.name)
                    .font(LoreType.displayXL)
                    .foregroundStyle(LoreColor.bone)
                    .fixedSize(horizontal: false, vertical: true)

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
        }
        .background(LoreColor.ink950)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await model.load(placeID: place.id) }
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

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(LoreColor.ink800)
                    .frame(height: 14)
            }
        }
        .redacted(reason: .placeholder)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(events) { event in
                        TimelineNode(event: event)
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
        }
    }
}

struct TimelineNode: View {
    let event: TimelineEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Node dot on the rail — compound Amber per the pin rules.
            HStack(spacing: 8) {
                Circle()
                    .fill(LoreColor.amber)
                    .strokeBorder(LoreColor.ink, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                Rectangle()
                    .fill(LoreColor.ink700)
                    .frame(height: 2)
            }

            HStack(spacing: 6) {
                if let emoji = event.emoji {
                    Text(emoji)
                }
                Text(String(event.year))
                    .font(LoreType.display(size: 22, weight: .semibold))
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
