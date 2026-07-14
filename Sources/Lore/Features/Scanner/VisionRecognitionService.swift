import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Observation
import QuartzCore
import Vision

/// One honest on-device read of a single camera frame.
///
/// HONESTY CONTRACT: `topCategory` is a *kind of thing* ("skyscraper",
/// "fountain", "clock tower"), never a specific landmark identity, and
/// `readableText` is only text the camera can literally see (signage, building
/// names, plaques). Naming a specific landmark ("Empire State Building") from
/// pixels alone requires a cloud recognizer — never claim it here.
struct VisionRead: Equatable, Sendable {
    /// Cleaned top scene/object category, or nil if nothing cleared the floor.
    var topCategory: String?
    /// Confidence 0…1 for `topCategory`.
    var confidence: Float
    /// Text actually read in-frame, most-confident first, de-duplicated.
    var readableText: [String]

    /// True when this read carries anything worth surfacing to the user.
    var hasSignal: Bool { topCategory != nil || !readableText.isEmpty }

    /// A short, honest human phrase for the read, or nil when there is nothing
    /// worth claiming. Always hedged ("Looks like…", "I can read…") so a guess
    /// is never presented as fact.
    var phrase: String? {
        if let text = readableText.first {
            return "I can read “\(text)”"
        }
        if let category = topCategory {
            return "Looks like \(article(for: category)) \(category)"
        }
        return nil
    }

    private func article(for word: String) -> String {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        return vowels.contains(word.lowercased().first ?? "x") ? "an" : "a"
    }

    static let empty = VisionRead(topCategory: nil, confidence: 0, readableText: [])
}

/// Throttled, on-device Apple Vision recognizer that turns raw camera frames
/// into an honest `VisionRead`. Drives the scanner's always-alive feedback
/// ("Looks like a skyscraper…", "I can read 'FLATIRON'…") and fuses with the
/// existing geospatial ranking (a known nearby place always wins).
///
/// Not `@MainActor`: `recognize(...)` is called from the camera's background
/// video queue, does all Vision work off the main thread on its own serial
/// queue, and only hops to the main thread to publish `latest` (so SwiftUI
/// observation stays main-thread-consistent). No external dependencies. The
/// camera path is device-only (the Simulator has no camera), but the still
/// path (`recognize(cgImage:)`) runs anywhere — including tests.
@Observable
final class VisionRecognitionService {

    /// The most recent read. Observed by the scanner view; mutated on main only.
    private(set) var latest: VisionRead = .empty

    // MARK: - Tuning

    /// Minimum time between completed recognitions (~2 Hz), keeping CPU/thermals
    /// sane while still feeling responsive.
    @ObservationIgnored private static let minimumInterval: CFTimeInterval = 0.45
    /// Minimum classification confidence we will surface as a category.
    @ObservationIgnored private static let categoryFloor: Float = 0.10
    /// Minimum per-line text confidence we will trust as readable signage.
    @ObservationIgnored private static let textFloor: Float = 0.30
    /// Cap on text tokens returned per frame.
    @ObservationIgnored private static let maxTextTokens = 4

    /// Categories too generic to be worth saying out loud — we want
    /// "skyscraper", not "outdoor".
    @ObservationIgnored private static let genericLabels: Set<String> = [
        "outdoor", "indoor", "sky", "structure", "material", "people",
        "person", "no_person", "nature", "landscape", "plant", "art",
    ]

    // MARK: - Internals

    @ObservationIgnored
    private let queue = DispatchQueue(label: "app.lore.vision.recognition", qos: .userInitiated)
    /// Touched only on `queue`: guards single-in-flight + the interval throttle.
    @ObservationIgnored private var lastCompleted: CFTimeInterval = 0
    /// Touched only on `queue`: when false, live frames are dropped without any
    /// Vision work. The scanner only consumes the read in the nothing-recognized
    /// state, so it enables recognition only then — the whole pipeline idles
    /// (no classification, no OCR) in the common "found a place" case.
    @ObservationIgnored private var enabled = false

    // MARK: - Entry points

    /// Turn live-frame recognition on/off. Cheap; safe from any thread. The
    /// scanner calls this as its state changes so Vision never burns battery
    /// producing a read nothing will show.
    func setEnabled(_ on: Bool) {
        queue.async { [weak self] in self?.enabled = on }
    }

    /// Recognize a live camera frame. No-ops unless enabled; throttled + serial;
    /// extra frames inside the interval are dropped. Safe from a background queue.
    func recognize(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) {
        queue.async { [weak self] in
            guard let self, self.enabled, self.shouldRun() else { return }
            let read = Self.perform(cgImage: nil, pixelBuffer: pixelBuffer, orientation: orientation)
            self.lastCompleted = CACurrentMediaTime()
            self.publish(read)
        }
    }

    /// Recognize a still image asynchronously (a captured frame). Not throttled.
    func recognize(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) {
        queue.async { [weak self] in
            guard let self else { return }
            let read = Self.perform(cgImage: cgImage, pixelBuffer: nil, orientation: orientation)
            self.lastCompleted = CACurrentMediaTime()
            self.publish(read)
        }
    }

    /// Synchronous still recognition for tests: returns the read directly.
    func read(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) -> VisionRead {
        Self.perform(cgImage: cgImage, pixelBuffer: nil, orientation: orientation)
    }

    /// Clear state when the scanner disappears.
    func reset() {
        publish(.empty)
        queue.async { [weak self] in
            self?.lastCompleted = 0
            self?.enabled = false
        }
    }

    // MARK: - Throttle plumbing (all on `queue`)

    private func shouldRun() -> Bool {
        CACurrentMediaTime() - lastCompleted >= Self.minimumInterval
    }

    private func publish(_ read: VisionRead) {
        DispatchQueue.main.async { [weak self] in self?.latest = read }
    }

    // MARK: - Recognition (pure, off the main actor)

    /// Runs classification + text reads, each with its own handler so one
    /// failing can never wipe out the other. `.fast` OCR (no language
    /// correction) is right for a live viewfinder reading large signage /
    /// building names — dramatically cheaper than `.accurate` at ~2 Hz. Nothing
    /// is claimed that wasn't actually read.
    private static func perform(
        cgImage: CGImage?,
        pixelBuffer: CVPixelBuffer?,
        orientation: CGImagePropertyOrientation
    ) -> VisionRead {
        func makeHandler() -> VNImageRequestHandler? {
            if let cgImage {
                return VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            }
            if let pixelBuffer {
                return VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            }
            return nil
        }

        let classify = VNClassifyImageRequest()
        let category: (name: String?, confidence: Float)
        if let handler = makeHandler(), (try? handler.perform([classify])) != nil {
            category = topCategory(from: classify)
        } else {
            category = (nil, 0)
        }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        let text: [String]
        if let handler = makeHandler(), (try? handler.perform([textRequest])) != nil {
            text = readableText(from: textRequest)
        } else {
            text = []
        }

        return VisionRead(
            topCategory: category.name,
            confidence: category.confidence,
            readableText: text
        )
    }

    private static func topCategory(
        from request: VNClassifyImageRequest
    ) -> (name: String?, confidence: Float) {
        guard let best = request.results?
            .filter({ $0.confidence >= categoryFloor && !genericLabels.contains($0.identifier) })
            .max(by: { $0.confidence < $1.confidence })
        else { return (nil, 0) }
        return (friendly(best.identifier), best.confidence)
    }

    private static func readableText(
        from request: VNRecognizeTextRequest
    ) -> [String] {
        guard let lines = request.results else { return [] }
        var out: [String] = []
        for line in lines {
            guard let candidate = line.topCandidates(1).first,
                  candidate.confidence >= textFloor else { continue }
            let cleaned = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            // Real words only: at least two chars and containing a letter, so a
            // stray "12" or "•" never becomes a claimed "read".
            guard cleaned.count >= 2,
                  cleaned.rangeOfCharacter(from: .letters) != nil,
                  !out.contains(cleaned) else { continue }
            out.append(cleaned)
            if out.count >= maxTextTokens { break }
        }
        return out
    }

    /// Cleans a Vision identifier into human-readable copy. Stays a *category*,
    /// never upgraded to a specific name.
    private static func friendly(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
