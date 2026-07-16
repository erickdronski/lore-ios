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
        SHA256.hash(data: Data(remote.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
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
    private(set) var lastError: String?

    private let manifestFile: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appending(path: "lore-packs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "manifest.json")
    }()

    init() {
        if let data = try? Data(contentsOf: manifestFile),
           let decoded = try? JSONDecoder().decode([String: CityPack].self, from: data) {
            packs = decoded
        }
    }

    func state(for city: String) -> PackState {
        if let progress = downloading[city] { return .downloading(progress) }
        if let pack = packs[city] { return .downloaded(pack) }
        return .none
    }

    /// Download (or refresh) a city pack. JSON pinning is ~60% of the bar,
    /// images the rest. Concurrent downloads of different cities are fine;
    /// re-calling for an in-flight city is a no-op.
    func download(city: String) async {
        guard downloading[city] == nil else { return }
        downloading[city] = 0.01
        lastError = nil
        do {
            // Phase 1: pin all JSON. Unit count = 7 endpoints + one per place
            // (dive+facts tick together via onUnit in pinCityPack).
            var jsonDone = 0.0
            var jsonTotal = 40.0   // refined after places resolve; safe floor
            let pin = try await LoreAPI.shared.pinCityPack(city: city) { [weak self] in
                jsonDone += 1
                self?.downloading[city] = min(0.6, (jsonDone / max(jsonTotal, jsonDone)) * 0.6)
            }
            jsonTotal = Double(7 + pin.places.count)

            // Phase 2: resolve + pack hero images (skips titles with no
            // image), then the dives' studio narration files — same store,
            // same removal lifecycle, so a deleted pack cleans up its audio.
            var imageKeys: [String] = []
            var imageBytes: Int64 = 0
            var titleMap: [String: URL] = [:]
            let titles = pin.wikipediaTitles
            let mediaTotal = titles.count + pin.audioURLs.count
            var mediaDone = 0
            for title in titles {
                if let url = await WikipediaService.shared.portraitURL(for: title) {
                    titleMap[title] = url
                    if PackImageStore.localURL(for: url) == nil,
                       let (data, response) = try? await URLSession.shared.data(from: url),
                       (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                       let key = try? PackImageStore.store(data, for: url) {
                        imageKeys.append(key)
                        imageBytes += Int64(data.count)
                    } else if let key = PackImageStore.localURL(for: url).map({ _ in PackImageStore.key(for: url) }) {
                        imageKeys.append(key)
                    }
                }
                mediaDone += 1
                downloading[city] = 0.6 + (Double(mediaDone) / Double(max(mediaTotal, 1))) * 0.4
            }
            await WikipediaService.shared.persistTitles(titleMap)

            for url in pin.audioURLs {
                if PackImageStore.localURL(for: url) == nil {
                    if let (data, response) = try? await URLSession.shared.data(from: url),
                       (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                       let key = try? PackImageStore.store(data, for: url) {
                        imageKeys.append(key)
                        imageBytes += Int64(data.count)
                    }
                } else {
                    imageKeys.append(PackImageStore.key(for: url))
                }
                mediaDone += 1
                downloading[city] = 0.6 + (Double(mediaDone) / Double(max(mediaTotal, 1))) * 0.4
            }

            packs[city] = CityPack(
                downloadedAt: Date(),
                placeCount: pin.places.count,
                imageBytes: imageBytes,
                imageKeys: imageKeys,
                pinnedURLs: pin.pinnedURLs
            )
            saveManifest()
        } catch {
            lastError = "Couldn't download \(Self.label(city)). Check your connection and try again."
        }
        downloading[city] = nil
    }

    /// Remove a pack: drop pinned JSON + images not shared with another pack.
    func remove(city: String) async {
        guard let pack = packs[city] else { return }
        let otherKeys = Set(packs.filter { $0.key != city }.values.flatMap(\.imageKeys))
        let otherURLs = Set(packs.filter { $0.key != city }.values.flatMap(\.pinnedURLs))
        PackImageStore.remove(keys: pack.imageKeys.filter { !otherKeys.contains($0) })
        await AtlasCache.shared.unpin(urlStrings: pack.pinnedURLs.filter { !otherURLs.contains($0) })
        packs[city] = nil
        saveManifest()
    }

    static func label(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func saveManifest() {
        if let data = try? JSONEncoder().encode(packs) {
            try? data.write(to: manifestFile, options: .atomic)
        }
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
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(LoreColor.brass700)
        case .none:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 18))
                .foregroundStyle(LoreColor.ink)
        }
    }

    private var title: String {
        switch packStore.state(for: city) {
        case .downloading: return "Downloading \(CityPackStore.label(city))…"
        case .downloaded: return "\(CityPackStore.label(city)) is saved offline"
        case .none: return "Download \(CityPackStore.label(city))"
        }
    }

    private var subtitle: String {
        switch packStore.state(for: city) {
        case .downloading(let progress):
            return "\(Int(progress * 100))% — stories, tours, and photos"
        case .downloaded(let pack):
            return "\(pack.placeCount) places ready without signal. Tap to refresh."
        case .none:
            return "Every story, tour, and photo — works with no signal."
        }
    }

    private var accessibilityText: String {
        switch packStore.state(for: city) {
        case .downloading(let p): return "Downloading city pack, \(Int(p * 100)) percent"
        case .downloaded: return "City pack saved offline. Tap to refresh."
        case .none: return "Download \(CityPackStore.label(city)) for offline use, a Lore Plus feature"
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
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            Task { await packStore.remove(city: city) }
                        }
                        .font(LoreType.caption)
                    }
                }
            }
        }
    }

    private func byteLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
