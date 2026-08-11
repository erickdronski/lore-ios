import Foundation

/// Fetches portrait thumbnails for famous faces from the Wikipedia REST
/// summary API, no external dependencies, no API key.
///
/// `GET https://en.wikipedia.org/api/rest_v1/page/summary/{title}` returns a
/// JSON object whose `thumbnail.source` is a reasonably sized portrait crop and
/// whose `originalimage.source` is the full asset. We prefer the thumbnail (it
/// is already scaled for a small avatar and lighter to load) and fall back to
/// the original.
///
/// Doctrine fit: this is the *only* network image path in the culture surface.
/// It is best-effort, a missing portrait is never an error, the face just
/// keeps its emoji medallion placeholder. Results are memoized per title for
/// the lifetime of the process (the same person never re-fetches), and misses
/// are cached too so a person without a photo isn't retried on every scroll.
actor WikipediaService {
    static let shared = WikipediaService()

    private enum CacheEntry {
        case portrait(URL)
        case confirmedMissing
    }

    private enum Resolution {
        case portrait(URL)
        case confirmedMissing
        case transientFailure
    }

    /// Successful portraits and confirmed no-image responses are memoized.
    /// Network/server failures are deliberately not cached so scrolling back or
    /// retrying later can recover without restarting the app.
    private var cache: [String: CacheEntry] = [:]
    private let session: URLSession

    /// Durable `title → image URL` map written by city-pack downloads, so a
    /// downloaded city resolves its hero images with zero network. Loaded once.
    private var persistent: [String: String]?
    private let persistentFile: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appending(path: "lore-packs", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "wiki-titles.json")
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The portrait URL for a Wikipedia article title, or `nil` if the article
    /// has no image (or the lookup failed). Cached after the first call.
    ///
    /// - Parameter title: the raw `links.wikipedia_title` (e.g. "Oprah Winfrey");
    ///   spaces and punctuation are percent-encoded for the path segment.
    func portraitURL(for title: String) async -> URL? {
        let key = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] {
            switch cached {
            case .portrait(let url): return url
            case .confirmedMissing: return nil
            }
        }

        // A pack-persisted resolution answers offline (and skips the network).
        if let packed = loadPersistent()[key], let url = URL(string: packed) {
            cache[key] = .portrait(url)
            return url
        }

        let resolved = await fetchPortraitURL(for: key)
        switch resolved {
        case .portrait(let url):
            cache[key] = .portrait(url)
            return url
        case .confirmedMissing:
            cache[key] = .confirmedMissing
            return nil
        case .transientFailure:
            return nil
        }
    }

    /// Resolve several titles in order, skipping blanks, duplicate titles, and
    /// duplicate image URLs. Used by place galleries where a content row can
    /// now expose more than one Wikipedia-backed image candidate.
    func portraitURLs(for titles: [String]) async -> [URL] {
        var seenTitles: Set<String> = []
        var seenURLs: Set<String> = []
        var urls: [URL] = []

        for title in titles {
            let key = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            let titleKey = key.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seenTitles.insert(titleKey).inserted else { continue }
            guard let url = await portraitURL(for: key) else { continue }
            if seenURLs.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }

        return urls
    }

    /// Merge pack-resolved titles into the durable map (city-pack downloads).
    func persistTitles(_ map: [String: URL]) {
        var current = loadPersistent()
        for (title, url) in map { current[title] = url.absoluteString }
        persistent = current
        if let data = try? JSONEncoder().encode(current) {
            try? data.write(to: persistentFile, options: .atomic)
        }
    }

    private func loadPersistent() -> [String: String] {
        if let persistent { return persistent }
        let loaded = (try? Data(contentsOf: persistentFile))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        persistent = loaded
        return loaded
    }

    // MARK: - Network

    private func fetchPortraitURL(for title: String) async -> Resolution {
        guard let url = Self.summaryURL(for: title) else { return .confirmedMissing }

        var request = URLRequest(url: url)
        // Wikipedia asks REST clients to identify themselves; a descriptive UA
        // avoids the default-agent throttle.
        request.setValue("LoreApp/1.0 (https://lore.app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return http.statusCode == 404 ? .confirmedMissing : .transientFailure
            }
            let summary = try JSONDecoder().decode(WikiSummary.self, from: data)
            if let url = summary.portraitURL { return .portrait(url) }
            return .confirmedMissing
        } catch {
            return .transientFailure
        }
    }

    /// Build the REST summary URL, percent-encoding the title as one path
    /// segment (Wikipedia accepts spaces encoded as `%20`; `_` also works).
    static func summaryURL(for title: String) -> URL? {
        let base = "https://en.wikipedia.org/api/rest_v1/page/summary/"
        guard let encoded = title.addingPercentEncoding(
            withAllowedCharacters: .wikipediaPathSegment
        ) else { return nil }
        return URL(string: base + encoded)
    }
}

/// The slice of the Wikipedia summary payload we read. Everything is optional —
/// many articles have no image, and we never treat that as a failure.
private struct WikiSummary: Decodable {
    let thumbnail: Image?
    let originalimage: Image?

    struct Image: Decodable {
        let source: String
    }

    /// Prefer the pre-scaled thumbnail; fall back to the full-size original.
    var portraitURL: URL? {
        if let thumb = thumbnail?.source, let url = URL(string: thumb) { return url }
        if let orig = originalimage?.source, let url = URL(string: orig) { return url }
        return nil
    }
}

private extension CharacterSet {
    /// URL-path-segment-safe set: alphanumerics plus the sub-delims Wikipedia
    /// titles can legitimately contain, minus `/` (which would split the path).
    static let wikipediaPathSegment: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove("/")
        return set
    }()
}
