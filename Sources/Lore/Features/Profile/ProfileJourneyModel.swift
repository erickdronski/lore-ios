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

struct ProfileGuideCue: Identifiable, Equatable {
    enum Destination: Equatable {
        case signIn
        case editProfile
        case journal
        case savedPlaces
        case passport
        case travelPreferences
        case paywall
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let destination: Destination
}

struct ProfileGuideCompanionSnapshot: Equatable {
    let title: String
    let subtitle: String
    let cues: [ProfileGuideCue]

    init(
        isSignedIn: Bool,
        isPlus: Bool,
        profile: UserProfile?,
        journeyState: ProfileJourneyModel.State,
        savedCount: Int
    ) {
        guard isSignedIn else {
            title = "Start your field record"
            subtitle = "Explore freely now. Sign in when you want Lore to remember the route."
            cues = [
                .init(
                    id: "sign-in",
                    title: "Keep your discoveries",
                    detail: "Sync visits, notes, saved places, and Lore+ access.",
                    symbol: "person.crop.circle.badge.plus",
                    destination: .signIn
                ),
                .init(
                    id: "travel-lens",
                    title: "Tune your travel lens",
                    detail: "Set the themes Lore should favor while you wander.",
                    symbol: "slider.horizontal.3",
                    destination: .travelPreferences
                ),
            ]
            return
        }

        switch journeyState {
        case .loading:
            title = "Syncing your guide"
            subtitle = "Lore is checking your visits, saved places, and badges before choosing the next move."
            cues = [
                .init(
                    id: "syncing",
                    title: "Refreshing field record",
                    detail: "Your next cue will appear when the sync finishes.",
                    symbol: "arrow.triangle.2.circlepath",
                    destination: .passport
                ),
            ]
        case .failed:
            title = "Reconnect your guide"
            subtitle = "Your saved route is protected; Lore just needs a clean sync before advising the next step."
            cues = [
                .init(
                    id: "sync-passport",
                    title: "Review your Passport",
                    detail: "Check what synced and retry from the field record.",
                    symbol: "icloud.slash.fill",
                    destination: .passport
                ),
            ]
        case .signedOut:
            title = "Start your field record"
            subtitle = "Explore freely now. Sign in when you want Lore to remember the route."
            cues = [
                .init(
                    id: "sign-in",
                    title: "Keep your discoveries",
                    detail: "Sync visits, notes, saved places, and Lore+ access.",
                    symbol: "person.crop.circle.badge.plus",
                    destination: .signIn
                ),
            ]
        case .loaded(let stats):
            let selected = Self.loadedCues(
                stats: stats,
                isPlus: isPlus,
                profile: profile,
                savedCount: savedCount
            )
            cues = Array(selected.prefix(3))
            title = stats.places == 0 ? "Your guide is ready" : "Your next field moves"
            subtitle = stats.places == 0
                ? "Start with one logged place, then Lore can shape the companion plan around real travel."
                : "Based on the field record Lore has actually synced."
        }
    }

    private static func loadedCues(
        stats: UserStats,
        isPlus: Bool,
        profile: UserProfile?,
        savedCount: Int
    ) -> [ProfileGuideCue] {
        var cues: [ProfileGuideCue] = []

        if let profile, profile.completedIdentityFieldCount < 3 {
            cues.append(.init(
                id: "traveler-card",
                title: "Finish your traveler card",
                detail: "\(profile.completedIdentityFieldCount) of 3 fields complete.",
                symbol: "person.text.rectangle.fill",
                destination: .editProfile
            ))
        }

        if stats.places == 0 {
            cues.append(.init(
                id: "first-visit",
                title: "Log the first place",
                detail: "One visit unlocks a real field record, streaks, and Passport progress.",
                symbol: "mappin.and.ellipse",
                destination: .journal
            ))
        } else if stats.notes == 0 {
            cues.append(.init(
                id: "first-note",
                title: "Write the first field note",
                detail: "Turn a visit into something you can remember later.",
                symbol: "book.closed.fill",
                destination: .journal
            ))
        } else if stats.photos == 0 {
            cues.append(.init(
                id: "first-photo",
                title: "Add a private photo",
                detail: "Give one logged place a visual memory.",
                symbol: "photo.on.rectangle.angled",
                destination: .journal
            ))
        }

        if savedCount == 0 {
            cues.append(.init(
                id: "save-route-seed",
                title: "Seed tomorrow's walk",
                detail: "Save a place from any dossier to build a want-to-go list.",
                symbol: "bookmark.fill",
                destination: .savedPlaces
            ))
        } else {
            cues.append(.init(
                id: "saved-walk",
                title: "Turn saved places into a walk",
                detail: "\(savedCount) saved \(savedCount == 1 ? "place" : "places") waiting.",
                symbol: "figure.walk",
                destination: .savedPlaces
            ))
        }

        if stats.badgesTotal > 0 && stats.badges < stats.badgesTotal {
            cues.append(.init(
                id: "next-badge",
                title: "Chase the next seal",
                detail: "\(stats.badges) of \(stats.badgesTotal) badges earned.",
                symbol: "seal.fill",
                destination: .passport
            ))
        } else if stats.currentStreak == 0 && stats.places > 0 {
            cues.append(.init(
                id: "start-streak",
                title: "Start a new streak",
                detail: "Read or log one place today to begin a run.",
                symbol: "flame.fill",
                destination: .passport
            ))
        }

        if !isPlus {
            cues.append(.init(
                id: "unlock-audio",
                title: "Unlock the narrated guide",
                detail: "Unlimited dives, every tour, and studio audio as coverage rolls out.",
                symbol: "waveform",
                destination: .paywall
            ))
        }

        if cues.isEmpty {
            cues.append(.init(
                id: "refine-lens",
                title: "Refine your discovery lens",
                detail: "Keep recommendations sharp for the cities you explore next.",
                symbol: "slider.horizontal.3",
                destination: .travelPreferences
            ))
        }

        return cues
    }
}
