import Foundation
import Observation

/// Server-backed "want to go" store. Visits are past-tense ("I was here");
/// saved places are future-tense intent, the lightweight list that gets a
/// traveler to reopen Lore when planning the next walk.
@Observable
@MainActor
final class SavedPlaceStore {
    typealias SavedPlacesLoader = (String) async throws -> [SavedPlace]
    typealias SaveWriter = (String, String) async throws -> Void
    typealias RemoveWriter = (String, String) async throws -> Void

    private(set) var savedPlaceIDs: Set<String> = []
    private(set) var entries: [SavedPlace] = []
    private(set) var inFlightPlaceIDs: Set<String> = []
    private(set) var loaded = false
    var lastError: String?

    private let credentials: () -> (userID: String, accessToken: String)?
    private let savedPlacesLoader: SavedPlacesLoader
    private let saveWriter: SaveWriter
    private let removeWriter: RemoveWriter

    init(
        credentials: @escaping () -> (userID: String, accessToken: String)?,
        savedPlacesLoader: @escaping SavedPlacesLoader = { accessToken in
            try await TravelReads.savedPlaces(accessToken: accessToken)
        },
        saveWriter: @escaping SaveWriter = { placeID, accessToken in
            try await TravelReads.savePlace(placeID: placeID, accessToken: accessToken)
        },
        removeWriter: @escaping RemoveWriter = { placeID, accessToken in
            try await TravelReads.removeSavedPlace(placeID: placeID, accessToken: accessToken)
        }
    ) {
        self.credentials = credentials
        self.savedPlacesLoader = savedPlacesLoader
        self.saveWriter = saveWriter
        self.removeWriter = removeWriter
    }

    var canSavePlaces: Bool { credentials() != nil }
    var savedCount: Int { savedPlaceIDs.count }

    func hasSaved(_ placeID: String) -> Bool {
        savedPlaceIDs.contains(placeID)
    }

    func isInFlight(_ placeID: String) -> Bool {
        inFlightPlaceIDs.contains(placeID)
    }

    func load(force: Bool = false) async {
        guard force || !loaded else { return }
        guard let creds = credentials() else {
            entries = []
            savedPlaceIDs = []
            loaded = true
            lastError = nil
            return
        }
        do {
            let rows = try await savedPlacesLoader(creds.accessToken)
            guard credentials()?.userID == creds.userID else { return }
            entries = rows
            savedPlaceIDs = Set(rows.map(\.placeID))
            loaded = true
            lastError = nil
        } catch {
            guard credentials()?.userID == creds.userID else { return }
            loaded = true
            lastError = "Couldn't load your saved places."
        }
    }

    enum SaveResult: Equatable {
        case saved
        case alreadySaved
        case signedOut
        case failed(String)
    }

    @discardableResult
    func save(placeID: String) async -> SaveResult {
        guard !savedPlaceIDs.contains(placeID) else { return .alreadySaved }
        guard let creds = credentials() else { return .signedOut }
        guard !inFlightPlaceIDs.contains(placeID) else { return .alreadySaved }

        savedPlaceIDs.insert(placeID)
        inFlightPlaceIDs.insert(placeID)
        defer { inFlightPlaceIDs.remove(placeID) }

        do {
            try await saveWriter(placeID, creds.accessToken)
            guard credentials()?.userID == creds.userID else { return .saved }
            lastError = nil
            await load(force: true)
            return .saved
        } catch {
            guard credentials()?.userID == creds.userID else {
                return .failed("The account changed before the save finished.")
            }
            savedPlaceIDs.remove(placeID)
            let message = errorMessage(error, fallback: "Couldn't save that place.")
            lastError = message
            return .failed(message)
        }
    }

    enum RemoveResult: Equatable {
        case removed
        case notSaved
        case signedOut
        case failed(String)
    }

    @discardableResult
    func remove(placeID: String) async -> RemoveResult {
        guard savedPlaceIDs.contains(placeID) else { return .notSaved }
        guard let creds = credentials() else { return .signedOut }
        guard !inFlightPlaceIDs.contains(placeID) else { return .notSaved }

        let priorIDs = savedPlaceIDs
        let priorEntries = entries
        savedPlaceIDs.remove(placeID)
        entries.removeAll { $0.placeID == placeID }
        inFlightPlaceIDs.insert(placeID)
        defer { inFlightPlaceIDs.remove(placeID) }

        do {
            try await removeWriter(placeID, creds.accessToken)
            guard credentials()?.userID == creds.userID else { return .removed }
            lastError = nil
            return .removed
        } catch {
            guard credentials()?.userID == creds.userID else {
                return .failed("The account changed before the save finished.")
            }
            savedPlaceIDs = priorIDs
            entries = priorEntries
            let message = errorMessage(error, fallback: "Couldn't remove that place.")
            lastError = message
            return .failed(message)
        }
    }

    func reset() {
        savedPlaceIDs = []
        entries = []
        inFlightPlaceIDs = []
        loaded = false
        lastError = nil
    }

    private func errorMessage(_ error: Error, fallback: String) -> String {
        (error as? LoreAPI.APIError)?.errorDescription
            ?? (error as? TravelReads.TravelError)?.errorDescription
            ?? fallback
    }
}
