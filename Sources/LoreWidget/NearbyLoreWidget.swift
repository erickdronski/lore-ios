import SwiftUI
import WidgetKit

/// The home-screen **"place near you / daily lore"** widget (docs/16 §7).
///
/// Data path: the app writes a `LoreWidgetSnapshot` to the shared App Group
/// after each near-me refresh; this widget's `TimelineProvider` reads it. The
/// widget itself does **no networking** — it renders the cached snapshot, or a
/// brand-correct sample when the App Group isn't provisioned yet / the app
/// hasn't written one (so the gallery preview and a fresh install still look
/// right, per docs/16 §7 "shows content, not a login wall").
///
/// Families: `.systemSmall` ("daily lore" — one place, hook, emoji pin) and
/// `.systemMedium` ("around you" — 2–3 nearest un-visited places). Every tap
/// deep-links through `lore://place/{id}` so `AppRouter` opens the matching card
/// (the router seam already exists in `LoreApp`).
struct NearbyLoreWidget: Widget {
    static let kind = "NearbyLoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NearbyLoreProvider()) { entry in
            NearbyLoreEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [LoreBrand.ink, LoreBrand.ink950],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Nearby Lore")
        .description("A place near you with a story worth knowing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

/// One rendered moment of the widget.
struct NearbyLoreEntry: TimelineEntry {
    let date: Date
    let snapshot: LoreWidgetSnapshot
}

/// Feeds the widget from the App-Group snapshot. Refreshes on a cadence; the app
/// also nudges `WidgetCenter.shared.reloadTimelines` after a near-me refresh so
/// the surface stays fresh without waiting for the next scheduled reload.
struct NearbyLoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> NearbyLoreEntry {
        NearbyLoreEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NearbyLoreEntry) -> Void) {
        completion(NearbyLoreEntry(date: Date(), snapshot: currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearbyLoreEntry>) -> Void) {
        let entry = NearbyLoreEntry(date: Date(), snapshot: currentSnapshot())
        // Re-poll the cache every 2 hours; the app's explicit reload covers the
        // "just walked somewhere new" case in between (docs/16 §7).
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// The app's cached snapshot, or the sample when there's nothing yet.
    private func currentSnapshot() -> LoreWidgetSnapshot {
        LoreWidgetStore.read() ?? .sample
    }
}

// MARK: - Views

struct NearbyLoreEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NearbyLoreEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumNearby(snapshot: entry.snapshot)
        default:
            SmallDailyLore(snapshot: entry.snapshot)
        }
    }
}

/// Small: the "daily lore" hero — one place, its emoji pin, hook, and year.
private struct SmallDailyLore: View {
    let snapshot: LoreWidgetSnapshot

    var body: some View {
        let place = snapshot.featured
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AmberPin(emoji: place?.emoji ?? "🏙️")
                Text("Daily Lore")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(LoreBrand.brass300)
                Spacer()
            }

            Spacer(minLength: 2)

            Text(place?.name ?? "Explore your city")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(LoreBrand.bone)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let hook = place?.hook {
                Text(hook)
                    .font(.system(size: 12))
                    .foregroundStyle(LoreBrand.bone.opacity(0.85))
                    .lineLimit(2)
            } else {
                Text("Point at a building to learn its story.")
                    .font(.system(size: 12))
                    .foregroundStyle(LoreBrand.ink600)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(place.map { URL(string: "lore://place/\($0.id)") } ?? URL(string: "lore://map"))
    }
}

/// Medium: "around you right now" — up to three nearest un-visited places.
private struct MediumNearby: View {
    let snapshot: LoreWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LoreBrand.amber)
                Text("Around you right now")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(LoreBrand.brass300)
                Spacer()
                Text(snapshot.city.capitalized)
                    .font(.system(size: 11))
                    .foregroundStyle(LoreBrand.ink600)
            }

            if snapshot.places.isEmpty {
                Text("Open Lore to load the stories around you.")
                    .font(.system(size: 13))
                    .foregroundStyle(LoreBrand.bone.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                ForEach(snapshot.places.prefix(3)) { place in
                    Link(destination: URL(string: "lore://place/\(place.id)")!) {
                        NearbyRow(place: place)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "lore://map"))
    }
}

private struct NearbyRow: View {
    let place: LoreWidgetSnapshot.Place

    var body: some View {
        HStack(spacing: 8) {
            AmberPin(emoji: place.emoji, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(LoreBrand.bone)
                    .lineLimit(1)
                if let hook = place.hook {
                    Text(hook)
                        .font(.system(size: 11))
                        .foregroundStyle(LoreBrand.ink600)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }
}

/// The compound Amber pin, widget-scaled: Amber disc + Ink stroke + emoji
/// (brand rule: pins are always Amber fill + Ink stroke, docs/00 §1 / DESIGN §4).
private struct AmberPin: View {
    let emoji: String
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle()
                .fill(LoreBrand.amber)
                .overlay(Circle().strokeBorder(LoreBrand.ink, lineWidth: 1.5))
            Text(emoji).font(.system(size: size * 0.5))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Sample

extension LoreWidgetSnapshot {
    /// Brand-correct sample so previews / a fresh install look right before the
    /// app writes a real snapshot (docs/16 §7: never an empty widget).
    static let sample = LoreWidgetSnapshot(
        updatedAt: Date(),
        city: "chicago",
        places: [
            .init(id: "sample-willis", name: "Willis Tower", emoji: "🏙️",
                  hook: "For 25 years, the tallest building on Earth.", year: 1973),
            .init(id: "sample-wrigley", name: "Wrigley Building", emoji: "🏛️",
                  hook: "Chicago's terra-cotta answer to a Sevillian tower.", year: 1924),
            .init(id: "sample-cloudgate", name: "Cloud Gate", emoji: "🗿",
                  hook: "\"The Bean\" — 168 seamless steel plates.", year: 2006),
        ]
    )
}
