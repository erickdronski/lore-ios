import CryptoKit
import Foundation
import Observation
import SwiftUI

// MARK: - PackImageStore (durable image bytes)

/// Flat, durable image store for downloaded city packs, keyed by the SHA-256
/// of the remote URL. Lives in Application Support (never purged like Caches),
/// so a pack's hero images render with zero network. `BlurUpAsyncImage` checks
/// here before hitting the wire.
enum PackImageStore {
    static let directory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appending(path: "lore-packs/images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func key(for remote: URL) -> String {
        let marker = directory.appending(path: ".content-contract")
        let namespace = try? String(contentsOf: marker, encoding: .utf8)
        let identity = namespace.map { "\($0)\n\(remote.absoluteString)" }
            ?? remote.absoluteString
        return SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Switch generations before cleanup so interrupted deletion cannot make
    /// old URL-only media reachable under an enforced review epoch.
    static func activate(_ contract: ContentContract) {
        guard contract.usesVersionedCache else { return }
        let marker = directory.appending(path: ".content-contract")
        let namespace = contract.cacheNamespace
        guard (try? String(contentsOf: marker, encoding: .utf8)) != namespace else {
            return
        }
        try? Data(namespace.utf8).write(to: marker, options: .atomic)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent != marker.lastPathComponent {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The local file URL when the image was packed, else nil.
    static func localURL(for remote: URL) -> URL? {
        let file = directory.appending(path: key(for: remote))
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Store downloaded bytes; returns the key for the pack manifest.
    @discardableResult
    static func store(_ data: Data, for remote: URL) throws -> String {
        let k = key(for: remote)
        try data.write(to: directory.appending(path: k), options: .atomic)
        return k
    }

    static func remove(keys: some Sequence<String>) {
        for k in keys {
            try? FileManager.default.removeItem(at: directory.appending(path: k))
        }
    }

    static func byteCount(forKey key: String) -> Int64 {
        let file = directory.appending(path: key)
        let values = try? file.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}

// MARK: - CityPackStore

/// "Download this city": pins every JSON read the city needs (via AtlasCache's
/// durable pin store) and packs its hero images, so the map, dossiers, tours,
/// audio narration, and culture pages keep working in dead zones. A Lore+
/// feature; state is per-city and persisted in a manifest.
@MainActor
@Observable
final class CityPackStore {
    struct CityPack: Codable {
        var downloadedAt: Date
        var placeCount: Int
        var imageBytes: Int64
        var imageKeys: [String]
        var pinnedURLs: [String]
        var mediaCount: Int
        var missingMediaCount: Int
        var contractVersion: String?
        var reviewEpoch: String?

        var isComplete: Bool { missingMediaCount == 0 }

        init(
            downloadedAt: Date,
            placeCount: Int,
            imageBytes: Int64,
            imageKeys: [String],
            pinnedURLs: [String],
            mediaCount: Int = 0,
            missingMediaCount: Int = 0,
            contractVersion: String? = nil,
            reviewEpoch: String? = nil
        ) {
            self.downloadedAt = downloadedAt
            self.placeCount = placeCount
            self.imageBytes = imageBytes
            self.imageKeys = imageKeys
            self.pinnedURLs = pinnedURLs
            self.mediaCount = mediaCount
            self.missingMediaCount = missingMediaCount
            self.contractVersion = contractVersion
            self.reviewEpoch = reviewEpoch
        }

        private enum CodingKeys: String, CodingKey {
            case downloadedAt, placeCount, imageBytes, imageKeys, pinnedURLs
            case mediaCount, missingMediaCount
            case contractVersion, reviewEpoch
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            downloadedAt = try values.decode(Date.self, forKey: .downloadedAt)
            placeCount = try values.decode(Int.self, forKey: .placeCount)
            imageBytes = try values.decode(Int64.self, forKey: .imageBytes)
            imageKeys = try values.decode([String].self, forKey: .imageKeys)
            pinnedURLs = try values.decode([String].self, forKey: .pinnedURLs)
            mediaCount = try values.decodeIfPresent(Int.self, forKey: .mediaCount) ?? imageKeys.count
            missingMediaCount = try values.decodeIfPresent(Int.self, forKey: .missingMediaCount) ?? 0
            contractVersion = try values.decodeIfPresent(String.self, forKey: .contractVersion)
            reviewEpoch = try values.decodeIfPresent(String.self, forKey: .reviewEpoch)
        }

        func isCompatible(with contract: ContentContract, now: Date = Date()) -> Bool {
            guard contract.usesVersionedCache else { return contractVersion == nil && reviewEpoch == nil }
            guard contract.isValidForEnforcement,
                  contractVersion == contract.contractVersion,
                  reviewEpoch == contract.reviewEpoch
            else { return false }
            guard let maximumAge = contract.maximumOfflineAge else { return true }
            let age = now.timeIntervalSince(downloadedAt)
            return age >= -ContentContract.clockSkewTolerance && age <= maximumAge
        }

        mutating func reconcileStoredMedia(validKeys: Set<String>, bytes: Int64) {
            mediaCount = max(mediaCount, imageKeys.count)
            missingMediaCount = max(missingMediaCount, mediaCount - validKeys.count)
            imageBytes = bytes
        }
    }

    enum PackState: Equatable {
        case none
        case downloading(Double)   // 0...1
        case downloaded(CityPack)

        static func == (lhs: PackState, rhs: PackState) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none): return true
            case (.downloading(let a), .downloading(let b)): return a == b
            case (.downloaded(let a), .downloaded(let b)): return a.downloadedAt == b.downloadedAt
            default: return false
            }
        }
    }

    private(set) var packs: [String: CityPack] = [:]
    private(set) var downloading: [String: Double] = [:]
    private(set) var errorsByCity: [String: String] = [:]
    private var activeContentContract: ContentContract = .compatibility

    private let manifestFile: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appending(path: "lore-packs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "manifest.json")
    }()

    init() {
        activeContentContract = ContentContractStore.persistedSnapshot() ?? .compatibility
        PackImageStore.activate(activeContentContract)
        if let data = try? Data(contentsOf: manifestFile),
           let decoded = try? JSONDecoder().decode([String: CityPack].self, from: data) {
            packs = decoded.mapValues { stored in
                var pack = stored
                let validKeys = Set(pack.imageKeys.filter { PackImageStore.byteCount(forKey: $0) > 0 })
                let bytes = validKeys.reduce(Int64(0)) { $0 + PackImageStore.byteCount(forKey: $1) }
                pack.reconcileStoredMedia(validKeys: validKeys, bytes: bytes)
                return pack
            }
        }
        Task { [weak self] in
            guard let self else { return }
            let contract = await ContentContractStore.shared.current(
                session: .shared,
                forceRefresh: true
            )
            await self.apply(contract: contract)
        }
    }

    func state(for city: String) -> PackState {
        refreshPersistedContractIfNeeded()
        if let progress = downloading[city] { return .downloading(progress) }
        if let pack = packs[city], pack.isCompatible(with: activeContentContract) {
            return .downloaded(pack)
        }
        return .none
    }

    func error(for city: String) -> String? { errorsByCity[city] }
    func isDownloading(_ city: String) -> Bool { downloading[city] != nil }

    /// Download (or refresh) a city pack. JSON pinning is ~60% of the bar,
    /// images the rest. Concurrent downloads of different cities are fine;
    /// re-calling for an in-flight city is a no-op.
    func download(city: String) async {
        guard downloading[city] == nil else { return }
        downloading[city] = 0.01
        errorsByCity[city] = nil
        defer { downloading[city] = nil }
        do {
            // Phase 1: pin all JSON. Unit count = 7 endpoints + one per place
            // (dive+facts tick together via onUnit in pinCityPack).
            var jsonDone = 0.0
            var jsonTotal = 40.0   // refined after places resolve; safe floor
            let pin = try await LoreAPI.shared.pinCityPack(city: city) { [weak self] in
                jsonDone += 1
                self?.downloading[city] = min(0.6, (jsonDone / max(jsonTotal, jsonDone)) * 0.6)
            }
            guard !pin.contentContract.enforcementEnabled
                    || pin.contentContract.isValidForEnforcement
            else { throw LoreAPI.APIError.invalidResponse }
            await apply(
                contract: pin.contentContract,
                preservingPinnedURLs: Set(pin.pinnedURLs)
            )
            jsonTotal = Double(7 + pin.places.count)

            // Phase 2: resolve + pack hero images (skips titles with no
            // image), then the dives' studio narration files — same store,
            // same removal lifecycle, so a deleted pack cleans up its audio.
            try Task.checkCancellation()
            var mediaURLs = Set(pin.audioURLs)
            var titleMap: [String: URL] = [:]
            let titles = pin.wikipediaTitles
            for (index, title) in titles.enumerated() {
                try Task.checkCancellation()
                if let url = await WikipediaService.shared.portraitURL(for: title) {
                    titleMap[title] = url
                    mediaURLs.insert(url)
                }
                downloading[city] = 0.6 + (Double(index + 1) / Double(max(titles.count, 1))) * 0.1
            }
            await WikipediaService.shared.persistTitles(titleMap)

            var imageKeys = Set<String>()
            var imageBytes: Int64 = 0
            var missingMediaCount = 0
            let orderedMedia = mediaURLs.sorted { $0.absoluteString < $1.absoluteString }
            for (index, url) in orderedMedia.enumerated() {
                try Task.checkCancellation()
                if let packed = await packMedia(url) {
                    if imageKeys.insert(packed.key).inserted { imageBytes += packed.bytes }
                } else {
                    missingMediaCount += 1
                }
                downloading[city] = 0.7 + (Double(index + 1) / Double(max(orderedMedia.count, 1))) * 0.3
            }

            guard activeContentContract == pin.contentContract else { throw CancellationError() }
            let newPack = CityPack(
                downloadedAt: Date(),
                placeCount: pin.places.count,
                imageBytes: imageBytes,
                imageKeys: imageKeys.sorted(),
                pinnedURLs: pin.pinnedURLs,
                mediaCount: orderedMedia.count,
                missingMediaCount: missingMediaCount,
                contractVersion: pin.contentContract.usesVersionedCache
                    ? pin.contentContract.contractVersion
                    : nil,
                reviewEpoch: pin.contentContract.usesVersionedCache
                    ? pin.contentContract.reviewEpoch
                    : nil
            )
            let previous = packs[city]
            var updated = packs
            updated[city] = newPack
            try saveManifest(updated)
            packs = updated
            await removeSupersededFiles(previous: previous, replacement: newPack, city: city)
        } catch {
            if !(error is CancellationError) {
                errorsByCity[city] = "Couldn't finish \(Self.label(city)). Check your connection and try again."
            }
        }
    }

    /// Remove a pack: drop pinned JSON + images not shared with another pack.
    func remove(city: String) async {
        guard downloading[city] == nil else {
            errorsByCity[city] = "Wait for the current refresh to finish before removing this pack."
            return
        }
        guard let pack = packs[city] else { return }
        let otherKeys = Set(packs.filter { $0.key != city }.values.flatMap(\.imageKeys))
        let otherURLs = Set(packs.filter { $0.key != city }.values.flatMap(\.pinnedURLs))
        var updated = packs
        updated[city] = nil
        do {
            try saveManifest(updated)
            packs = updated
            PackImageStore.remove(keys: pack.imageKeys.filter { !otherKeys.contains($0) })
            await AtlasCache.shared.unpin(
                urlStrings: pack.pinnedURLs.filter { !otherURLs.contains($0) },
                contractVersion: pack.contractVersion,
                reviewEpoch: pack.reviewEpoch
            )
            errorsByCity[city] = nil
        } catch {
            errorsByCity[city] = "Couldn't update offline storage. Try removing the pack again."
        }
    }

    static func label(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func saveManifest(_ value: [String: CityPack]) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: manifestFile, options: .atomic)
    }

    private func packMedia(_ url: URL) async -> (key: String, bytes: Int64)? {
        let key = PackImageStore.key(for: url)
        if PackImageStore.localURL(for: url) != nil {
            return (key, PackImageStore.byteCount(forKey: key))
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              !data.isEmpty,
              key == PackImageStore.key(for: url),
              (try? PackImageStore.store(data, for: url)) != nil
        else { return nil }
        return (key, Int64(data.count))
    }

    private func refreshPersistedContractIfNeeded() {
        guard let persisted = ContentContractStore.persistedSnapshot(),
              persisted != activeContentContract
        else { return }
        activeContentContract = persisted
        Task { [weak self] in
            await self?.apply(contract: persisted)
        }
    }

    private func apply(
        contract: ContentContract,
        preservingPinnedURLs: Set<String> = []
    ) async {
        activeContentContract = contract
        guard contract.usesVersionedCache else { return }
        PackImageStore.activate(contract)

        let invalid = packs.filter { !$0.value.isCompatible(with: contract) }
        guard !invalid.isEmpty else { return }

        let invalidCities = Set(invalid.keys)
        let retained = packs.filter { !invalidCities.contains($0.key) }
        do {
            try saveManifest(retained)
            packs = retained
        } catch {
            // AtlasCache still rejects incompatible bytes. Leave the manifest
            // intact so a later launch can retry durable cleanup.
            return
        }

        let retainedImageKeys = Set(retained.values.flatMap(\.imageKeys))
        for pack in invalid.values {
            PackImageStore.remove(keys: pack.imageKeys.filter { !retainedImageKeys.contains($0) })
            let protectedURLs = pack.contractVersion == contract.contractVersion
                    && pack.reviewEpoch == contract.reviewEpoch
                ? preservingPinnedURLs
                : []
            await AtlasCache.shared.unpin(
                urlStrings: pack.pinnedURLs.filter { !protectedURLs.contains($0) },
                contractVersion: pack.contractVersion,
                reviewEpoch: pack.reviewEpoch
            )
        }
    }

    private func removeSupersededFiles(previous: CityPack?, replacement: CityPack, city: String) async {
        guard let previous else { return }
        let sharedKeys = Set(packs.filter { $0.key != city }.values.flatMap(\.imageKeys))
        let replacementKeys = Set(replacement.imageKeys)
        PackImageStore.remove(keys: previous.imageKeys.filter {
            !replacementKeys.contains($0) && !sharedKeys.contains($0)
        })

        let sharedURLs = Set(packs.filter { $0.key != city }.values.flatMap(\.pinnedURLs))
        let replacementURLs = Set(replacement.pinnedURLs)
        await AtlasCache.shared.unpin(
            urlStrings: previous.pinnedURLs.filter {
                !replacementURLs.contains($0) && !sharedURLs.contains($0)
            },
            contractVersion: previous.contractVersion,
            reviewEpoch: previous.reviewEpoch
        )
    }
}

// MARK: - CityPackButton (the "Download this city" affordance)

/// One-tap city download for Plus members; the locked state routes to the
/// paywall. Renders download / progress / downloaded states honestly.
struct CityPackButton: View {
    let city: String
    @Environment(CityPackStore.self) private var packStore
    @Environment(EntitlementStore.self) private var entitlements
    /// Present the paywall (owned by the host screen).
    var onNeedsPlus: () -> Void = {}

    var body: some View {
        Button {
            guard entitlements.isPlus else { onNeedsPlus(); return }
            Haptics.play(.chipTap)
            switch packStore.state(for: city) {
            case .none, .downloaded:
                Task { await packStore.download(city: city) }
            case .downloading:
                break
            }
        } label: {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink)
                    Text(subtitle)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
                Spacer()
                if !entitlements.isPlus {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(LoreColor.brass700.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(accessibilityText))
    }

    @ViewBuilder private var icon: some View {
        switch packStore.state(for: city) {
        case .downloading(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(LoreColor.brass700)
        case .downloaded(let pack):
            Image(systemName: pack.isComplete ? "checkmark.circle.fill" : "exclamationmark.arrow.circlepath")
                .font(.system(size: 18))
                .foregroundStyle(pack.isComplete ? LoreColor.brass700 : LoreColor.error)
        case .none:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 18))
                .foregroundStyle(LoreColor.ink)
        }
    }

    private var title: String {
        switch packStore.state(for: city) {
        case .downloading: return "Downloading \(CityPackStore.label(city))…"
        case .downloaded(let pack):
            return pack.isComplete
                ? "\(CityPackStore.label(city)) is saved offline"
                : "\(CityPackStore.label(city)) needs a refresh"
        case .none: return "Download \(CityPackStore.label(city))"
        }
    }

    private var subtitle: String {
        if let error = packStore.error(for: city) { return error }
        switch packStore.state(for: city) {
        case .downloading(let progress):
            return "\(Int(progress * 100))% — stories, tours, and photos"
        case .downloaded(let pack):
            if pack.missingMediaCount > 0 {
                return "Stories are saved; \(pack.missingMediaCount) audio or photo files still need a connection. Tap to retry."
            }
            return "\(pack.placeCount) places and \(pack.mediaCount) media files ready without signal. Tap to refresh."
        case .none:
            return "Every story, tour, and photo — works with no signal."
        }
    }

    private var accessibilityText: String {
        switch packStore.state(for: city) {
        case .downloading(let p): return "Downloading city pack, \(Int(p * 100)) percent"
        case .downloaded(let pack):
            return pack.isComplete
                ? "City pack saved offline. Tap to refresh."
                : "City stories are saved, but \(pack.missingMediaCount) media files need a refresh. Tap to retry."
        case .none:
            return entitlements.isPlus
                ? "Download \(CityPackStore.label(city)) for offline use"
                : "Download \(CityPackStore.label(city)) for offline use, a Lore Plus feature"
        }
    }
}

// MARK: - OfflinePacksSection (Settings management)

/// Settings block: every downloaded pack with size + date, swipe-free explicit
/// Remove buttons, and honest empty copy.
struct OfflinePacksSection: View {
    @Environment(CityPackStore.self) private var packStore

    var body: some View {
        Section("Offline city packs") {
            if packStore.packs.isEmpty {
                Text("No cities downloaded yet. Open Tours in a city and tap Download to keep its stories, tours, and photos with you offline.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            } else {
                ForEach(packStore.packs.sorted(by: { $0.key < $1.key }), id: \.key) { city, pack in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(CityPackStore.label(city))
                                .font(LoreType.body)
                                .foregroundStyle(LoreColor.ink)
                            Text("\(pack.placeCount) places · \(byteLabel(pack.imageBytes)) · \(pack.downloadedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(LoreType.caption)
                                .foregroundStyle(LoreColor.ink600)
                            if pack.missingMediaCount > 0 {
                                Text("\(pack.missingMediaCount) media files need refresh")
                                    .font(LoreType.caption)
                                    .foregroundStyle(LoreColor.error)
                            }
                            if let error = packStore.error(for: city) {
                                Text(error)
                                    .font(LoreType.caption)
                                    .foregroundStyle(LoreColor.error)
                            }
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            Task { await packStore.remove(city: city) }
                        }
                        .font(LoreType.caption)
                        .disabled(packStore.isDownloading(city))
                    }
                }
            }
        }
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
