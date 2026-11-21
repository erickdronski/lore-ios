import Foundation

/// A public walking route is usable offline only when the entire itinerary is bundled.
struct OfflineWalk: Identifiable {
    struct Stop: Identifiable {
        let entry: TourStop
        let place: Place
        let dive: Dive?
        var id: String { entry.id }

        var paragraphs: [String] {
            let parts = [entry.note, dive?.narrative ?? place.teaser]
            return parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .reduce(into: []) { if !$1.isEmpty && !$0.contains($1) { $0.append($1) } }
        }
    }

    let tour: Tour
    let stops: [Stop]
    var id: String { tour.id }

    init?(tour: Tour, places: [String: Place], dives: [String: Dive]) {
        guard !tour.isPremium, !tour.requiresTransport, tour.stops.count >= 2 else { return nil }
        var itinerary: [Stop] = []
        let ordered = tour.stops.sorted { $0.seq < $1.seq }
        guard Set(ordered.map(\.seq)).count == ordered.count else { return nil }
        for entry in ordered {
            guard entry.tourID == tour.id,
                  let place = places[entry.placeID], place.city == tour.city,
                  (-90...90).contains(place.lat), (-180...180).contains(place.lng)
            else { return nil }
            itinerary.append(Stop(entry: entry, place: place, dive: dives[place.id]))
        }
        self.tour = tour
        stops = itinerary
    }
}

/// Keep browsing previous stops separate from the furthest saved checkpoint.
/// Shares the online tour's resume state when the same traveler opens it again.
struct OfflineWalkSession {
    private(set) var index: Int
    private(set) var complete: Bool
    private let slug: String
    private let count: Int
    private let owner: String?
    private let defaults: UserDefaults

    init(walk: OfflineWalk, owner: String?, defaults: UserDefaults = .standard) {
        slug = walk.tour.slug
        count = walk.stops.count
        self.owner = owner
        self.defaults = defaults
        let saved = TourProgressStore.progress(for: slug, userID: owner, stopCount: count, defaults: defaults)
        index = saved.stopIndex ?? 0
        complete = saved.isCompleted
    }

    mutating func next() {
        guard !complete else { return }
        if index + 1 == count {
            TourProgressStore.complete(tourSlug: slug, userID: owner, defaults: defaults)
            complete = true
        } else {
            index += 1
            TourProgressStore.advance(to: index, for: slug, userID: owner, defaults: defaults)
        }
    }

    mutating func previous() { index = max(0, index - 1) }

    mutating func restart() {
        TourProgressStore.restart(tourSlug: slug, userID: owner, defaults: defaults)
        index = 0
        complete = false
    }
}
