import Observation
import SwiftUI

/// Compact city context for a place card. It is derived from `CityFieldBrief`,
/// so the card never invents facts or shows thin cities as complete.
struct PlaceCityFieldKit: Equatable {
    let items: [CityFieldBrief.Item]
    let action: CityFieldBrief.ExternalAction?

    init?(brief: CityFieldBrief) {
        let compactItems = Array(brief.items.prefix(3))
        guard compactItems.count == 3 else { return nil }
        items = compactItems
        action = brief.action
    }
}

@Observable
@MainActor
final class PlaceCityFieldKitModel {
    private enum CacheEntry {
        case ready(PlaceCityFieldKit)
        case missing
    }

    private(set) var kit: PlaceCityFieldKit?

    private static var cache: [String: CacheEntry] = [:]
    private var loadedCity: String?
    private var activeLoadID = UUID()

    func load(city: String) async {
        let cacheKey = city.lowercased()
        if loadedCity == city { return }
        if let cached = Self.cache[cacheKey] {
            loadedCity = city
            switch cached {
            case .ready(let cachedKit):
                kit = cachedKit
            case .missing:
                kit = nil
            }
            return
        }

        let loadID = UUID()
        activeLoadID = loadID
        loadedCity = nil
        kit = nil

        do {
            let sections = try await LoreAPI.shared.citySections(city: city)
            guard activeLoadID == loadID, !Task.isCancelled else { return }

            if let brief = CityFieldBrief(sections: sections),
               let builtKit = PlaceCityFieldKit(brief: brief) {
                Self.cache[cacheKey] = .ready(builtKit)
                kit = builtKit
            } else {
                Self.cache[cacheKey] = .missing
                kit = nil
            }
            loadedCity = city
        } catch {
            guard activeLoadID == loadID, !Task.isCancelled else { return }
            kit = nil
            loadedCity = nil
        }
    }
}

struct PlaceCityFieldKitCard: View {
    let city: String
    let kit: PlaceCityFieldKit
    let accent: Color
    let onMeetCity: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var cityName: String {
        city
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.15))
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CITY FIELD KIT")
                        .loreLabelStyle()
                        .foregroundStyle(accent)
                    Text("Before you wander \(cityName)")
                        .font(LoreType.display(size: 20, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(LoreColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(kit.items) { item in
                    PlaceCityFieldKitRow(item: item, accent: accent)
                }
            }

            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LoreColor.bone50)
                LoreTileArtwork(kind: .discovery, accent: accent, intensity: 0.06)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.20), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var footer: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                actionLink
                meetCityButton
            }
        } else {
            HStack(spacing: 10) {
                actionLink
                meetCityButton
            }
        }
    }

    @ViewBuilder
    private var actionLink: some View {
        if let action = kit.action {
            Link(destination: action.url) {
                Label(action.label, systemImage: action.systemImage)
                    .font(LoreType.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(LoreColor.ink900)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(accent.opacity(0.94), in: Capsule())
            }
            .accessibilityHint("Opens a curated city source")
        }
    }

    private var meetCityButton: some View {
        Button {
            Haptics.play(.chipTap)
            onMeetCity(city)
        } label: {
            Label("Meet city", systemImage: "quote.bubble")
                .font(LoreType.button)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .foregroundStyle(LoreColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .overlay(Capsule().strokeBorder(LoreColor.ink.opacity(0.62), lineWidth: 1.2))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Meet \(cityName)")
    }
}

struct DossierCityFieldKitCard: View {
    let city: String
    let kit: PlaceCityFieldKit
    let onMeetCity: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var cityName: String {
        city
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LoreColor.amber.opacity(0.16))
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LoreColor.amber)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CITY FIELD KIT")
                        .loreLabelStyle()
                        .foregroundStyle(LoreColor.amber)
                    Text("Carry this into \(cityName)")
                        .font(LoreType.display(size: 22, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(LoreColor.bone)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 11) {
                ForEach(kit.items) { item in
                    DossierCityFieldKitRow(item: item)
                }
            }

            footer
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LoreColor.ink800)
                LoreTileArtwork(kind: .discovery, accent: LoreColor.amber, intensity: 0.09)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LoreColor.amber.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var footer: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                actionLink
                meetCityButton
            }
        } else {
            HStack(spacing: 10) {
                actionLink
                meetCityButton
            }
        }
    }

    @ViewBuilder
    private var actionLink: some View {
        if let action = kit.action {
            Link(destination: action.url) {
                Label(action.label, systemImage: action.systemImage)
                    .font(LoreType.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(LoreColor.ink900)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(LoreColor.amber, in: Capsule())
            }
            .accessibilityHint("Opens a curated city source")
        }
    }

    private var meetCityButton: some View {
        Button {
            Haptics.play(.chipTap)
            onMeetCity(city)
        } label: {
            Label("Meet city", systemImage: "quote.bubble")
                .font(LoreType.button)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .foregroundStyle(LoreColor.bone)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .overlay(Capsule().strokeBorder(LoreColor.bone.opacity(0.34), lineWidth: 1.2))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Meet \(cityName)")
    }
}

private struct DossierCityFieldKitRow: View {
    let item: CityFieldBrief.Item

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LoreColor.amber)
                .frame(width: 20, height: 20)
                .background(LoreColor.amber.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Text(item.title)
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.bone.opacity(0.66))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PlaceCityFieldKitRow: View {
    let item: CityFieldBrief.Item
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 20, height: 20)
                .background(accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(LoreType.micro)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Text(item.title)
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.ink600)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
