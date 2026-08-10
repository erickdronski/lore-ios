import SwiftUI

/// A pocket-guide layer for the place card: three practical moves a traveler
/// can do while standing at the spot. Facts come from the place/dossier/city kit;
/// generic fallback moves are framed as prompts, not claims.
enum PlaceFieldGuide {
    struct Move: Identifiable, Equatable {
        let id: String
        let label: String
        let title: String
        let detail: String
        let systemImage: String
    }

    static func moves(
        place: Place,
        dive: Dive?,
        cityKit: PlaceCityFieldKit?
    ) -> [Move] {
        var result: [Move] = []
        var usedIDs = Set<String>()

        func append(_ move: Move) {
            guard !usedIDs.contains(move.id) else { return }
            usedIDs.insert(move.id)
            result.append(move)
        }

        if let style = clean(place.layer1?.style) {
            append(Move(
                id: "style-\(normalized(style))",
                label: "Look for",
                title: style,
                detail: "Use the facade, roofline, materials, and entrances as your first read before you open the full story.",
                systemImage: "eye.fill"
            ))
        } else {
            append(kindMove(for: place.kind))
        }

        if let event = dive?.timeline.first {
            append(Move(
                id: "timeline-\(event.id)",
                label: "Timeline",
                title: "\(event.year): \(event.title)",
                detail: clean(event.detail) ?? "Start the dossier timeline here, then scan forward for what changed around this place.",
                systemImage: "clock.arrow.circlepath"
            ))
        } else if let year = place.layer1?.yearBuilt {
            append(Move(
                id: "year-\(year)",
                label: "Anchor year",
                title: "Built \(year)",
                detail: "Hold that date in your head while you compare this stop with the block around it.",
                systemImage: "calendar"
            ))
        }

        if let architect = clean(place.layer1?.architect) {
            append(Move(
                id: "architect-\(normalized(architect))",
                label: "Name to know",
                title: architect,
                detail: "Keep the designer's name in mind; Lore can turn one stop into a pattern across the city.",
                systemImage: "person.text.rectangle"
            ))
        }

        if let cityMove = cityKit?.items.first {
            append(Move(
                id: "city-\(cityMove.id)",
                label: "City lens",
                title: cityMove.title,
                detail: cityMove.detail,
                systemImage: cityMove.systemImage
            ))
        }

        if !place.tags.isEmpty {
            let tags = place.tags
                .prefix(3)
                .map { "#\($0.replacingOccurrences(of: " ", with: ""))" }
                .joined(separator: " ")
            append(Move(
                id: "tags-\(normalized(tags))",
                label: "Search trail",
                title: tags,
                detail: "Use these as your lens when nearby places start to repeat a theme.",
                systemImage: "number"
            ))
        }

        append(photoMove(for: place.kind))
        append(Move(
            id: "compare-nearby",
            label: "Next move",
            title: "Compare one nearby stop",
            detail: "Open the next closest card and look for what repeats: materials, dates, names, or street behavior.",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up"
        ))

        return Array(result.prefix(3))
    }

    private static func kindMove(for kind: String) -> Move {
        switch normalized(kind) {
        case "park", "nature":
            return Move(
                id: "kind-park",
                label: "Read the edge",
                title: "Where the city softens",
                detail: "Notice where street noise gives way to paths, trees, water, or open ground.",
                systemImage: "leaf.fill"
            )
        case "statue", "sculpture", "monument", "memorial":
            return Move(
                id: "kind-monument",
                label: "Circle once",
                title: "Check the base and back",
                detail: "The smallest clue is often an inscription, date, maker mark, or dedication.",
                systemImage: "arrow.triangle.2.circlepath"
            )
        case "bridge":
            return Move(
                id: "kind-bridge",
                label: "Watch the crossings",
                title: "Read movement first",
                detail: "Stand aside for a minute and see how people, traffic, and sightlines use the span.",
                systemImage: "water.waves"
            )
        case "church", "temple":
            return Move(
                id: "kind-sacred",
                label: "Slow down",
                title: "Look for thresholds",
                detail: "Doors, steps, towers, bells, and interior light usually tell the first story.",
                systemImage: "building.columns.fill"
            )
        default:
            return Move(
                id: "kind-\(normalized(kind))",
                label: "Read the block",
                title: "How this \(displayKind(kind)) sits here",
                detail: "Step back once, then look at scale, entrances, materials, and what the street does around it.",
                systemImage: "map.fill"
            )
        }
    }

    private static func photoMove(for kind: String) -> Move {
        Move(
            id: "photo-\(normalized(kind))",
            label: "Frame",
            title: "One wide, one detail",
            detail: "Take the context shot first, then move close for the texture, sign, carving, view, or corner most people miss.",
            systemImage: "camera.viewfinder"
        )
    }

    private static func displayKind(_ kind: String) -> String {
        let cleaned = kind.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "place" : cleaned
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }
}

struct PlaceFieldGuideCard: View {
    let place: Place
    let dive: Dive?
    let cityKit: PlaceCityFieldKit?
    let accent: Color

    @State private var completedIDs: Set<String> = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var moves: [PlaceFieldGuide.Move] {
        PlaceFieldGuide.moves(place: place, dive: dive, cityKit: cityKit)
    }

    var body: some View {
        if !moves.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                header

                VStack(spacing: 9) {
                    ForEach(moves) { move in
                        moveRow(move)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LoreColor.bone50)
                    LoreTileArtwork(kind: .discovery, accent: accent, intensity: 0.07)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accent.opacity(0.22), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("FIELD MOVES")
                    .loreLabelStyle()
                    .foregroundStyle(accent)
                Text("Try this before you leave")
                    .font(LoreType.display(size: dynamicTypeSize.isAccessibilitySize ? 21 : 20, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(LoreColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func moveRow(_ move: PlaceFieldGuide.Move) -> some View {
        let completed = completedIDs.contains(move.id)

        return Button {
            if completed {
                completedIDs.remove(move.id)
                Haptics.play(.chipTap)
            } else {
                completedIDs.insert(move.id)
                Haptics.play(.chipTap)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: move.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(completed ? LoreColor.ink900 : accent)
                    .frame(width: 24, height: 24)
                    .background(completed ? accent : accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(move.label.uppercased())
                        .font(LoreType.micro)
                        .tracking(0.7)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                    Text(move.title)
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(move.detail)
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.ink600)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(completed ? accent : LoreColor.ink600.opacity(0.42))
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                completed ? accent.opacity(0.10) : LoreColor.bone100.opacity(0.74),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.pressableSilent)
        .accessibilityLabel("\(move.label), \(move.title)")
        .accessibilityHint(completed ? "Marked as noticed. Tap to clear." : "Tap to mark this field move as noticed.")
    }
}
