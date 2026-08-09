import Foundation
import Observation

/// Lightweight Profile dashboard state. It reuses the server-computed
/// `user_stats` RPC that powers Passport, so Profile never estimates or
/// fabricates journey totals.
@Observable
@MainActor
final class ProfileJourneyModel {
    enum State: Equatable {
        case signedOut
        case loading
        case loaded(UserStats)
        case failed(String)
    }

    private(set) var state: State = .signedOut

    func reset() {
        state = .signedOut
    }

    func load(auth: AuthService) async {
        guard let userID = auth.session?.user.id else {
            state = .signedOut
            return
        }

        state = .loading
        guard let token = await auth.validAccessToken() else {
            state = .failed("Sign in again to refresh your field record.")
            return
        }

        do {
            state = .loaded(try await LoreAPI.shared.userStats(userID: userID, accessToken: token))
        } catch LoreAPI.APIError.http(let status, _) where status == 401 {
            guard let refreshed = await auth.validAccessToken(forceRefresh: true) else {
                state = .failed("Your session needs a fresh sign-in before Lore can sync journey totals.")
                return
            }
            do {
                state = .loaded(try await LoreAPI.shared.userStats(userID: userID, accessToken: refreshed))
            } catch {
                state = .failed("Lore couldn't refresh your journey totals. Pull down to try again.")
            }
        } catch {
            state = .failed("Lore couldn't refresh your journey totals. Pull down to try again.")
        }
    }
}

struct ProfileJourneySnapshot: Equatable {
    let stats: UserStats

    var headline: String {
        if stats.places == 0 { return "Your field record is ready" }
        if stats.cities > 1 { return "\(stats.cities) cities in your atlas" }
        return "\(stats.places) \(stats.places == 1 ? "place" : "places") logged"
    }

    var subhead: String {
        if let exploringSince = stats.exploringSince {
            return "Exploring since \(exploringSince)"
        }
        return "Visits, dives, notes, photos, and badges will collect here."
    }

    var primaryMetrics: [ProfileJourneyMetric] {
        [
            .init(id: "places", label: "Places", value: "\(stats.places)", symbol: "mappin.and.ellipse"),
            .init(id: "cities", label: "Cities", value: "\(stats.cities)", symbol: "building.2.fill"),
            .init(id: "dives", label: "Dives", value: "\(stats.divesRead)", symbol: "books.vertical.fill"),
            .init(id: "photos", label: "Photos", value: "\(stats.photos)", symbol: "photo.on.rectangle"),
        ]
    }

    var secondaryMetrics: [ProfileJourneyMetric] {
        [
            .init(id: "badges", label: "Badges", value: badgeValue, symbol: "seal.fill"),
            .init(id: "insight", label: "Insight", value: "\(stats.insightPoints)", symbol: "sparkles"),
            .init(id: "streak", label: "Streak", value: "\(stats.currentStreak)d", symbol: "flame.fill"),
        ]
    }

    private var badgeValue: String {
        guard stats.badgesTotal > 0 else { return "\(stats.badges)" }
        return "\(stats.badges)/\(stats.badgesTotal)"
    }
}

struct ProfileJourneyMetric: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let symbol: String
}
