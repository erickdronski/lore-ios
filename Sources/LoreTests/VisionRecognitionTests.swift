import CoreGraphics
import UIKit
import Vision
import XCTest
@testable import Lore

/// Proves the on-device recognizer actually *reads* — the scanner's headline
/// fix. Apple Vision runs fine in the Simulator on a still image (only the live
/// camera is device-only), so we render real signage into a `CGImage` and
/// confirm the service reads it back, plus lock in the honest phrasing that must
/// never claim a specific landmark identity.
final class VisionRecognitionTests: XCTestCase {

    // MARK: - Real OCR end to end

    /// Rendered signage is read back — the "I can read 'FLATIRON'" path really
    /// resolves pixels to text (not a mock).
    func testReadsRenderedSignageText() {
        let service = VisionRecognitionService()
        let image = renderText("FLATIRON")
        let read = service.read(cgImage: image, orientation: .up)
        let joined = read.readableText.joined(separator: " ").uppercased()
        XCTAssertTrue(
            joined.contains("FLAT"),
            "OCR should read the rendered signage; got \(read.readableText)"
        )
    }

    /// A blank frame is honestly empty — never an invented read.
    func testBlankFrameReadsNoText() {
        let service = VisionRecognitionService()
        let blank = renderText("", size: CGSize(width: 120, height: 120))
        let read = service.read(cgImage: blank, orientation: .up)
        XCTAssertTrue(read.readableText.isEmpty, "A blank frame must read no text")
    }

    // MARK: - Honest phrasing (never a specific landmark)

    func testPhraseHedgesReadText() {
        var read = VisionRead.empty
        read.readableText = ["FLATIRON"]
        XCTAssertEqual(read.phrase, "I can read “FLATIRON”")
    }

    func testPhraseHedgesCategoryWithArticle() {
        var read = VisionRead.empty
        read.topCategory = "skyscraper"
        XCTAssertEqual(read.phrase, "Looks like a skyscraper")
        read.topCategory = "obelisk"
        XCTAssertEqual(read.phrase, "Looks like an obelisk")
    }

    func testEmptyReadHasNoSignalAndNoPhrase() {
        XCTAssertFalse(VisionRead.empty.hasSignal)
        XCTAssertNil(VisionRead.empty.phrase)
    }

    func testReadTextIsPreferredOverCategoryInPhrase() {
        // When both are present, the literal read wins — it's the more honest,
        // more specific thing the camera can actually show the user.
        var read = VisionRead.empty
        read.topCategory = "skyscraper"
        read.readableText = ["EMPIRE STATE"]
        XCTAssertEqual(read.phrase, "I can read “EMPIRE STATE”")
    }

    // MARK: - Helpers

    private func renderText(_ text: String, size: CGSize = CGSize(width: 640, height: 200)) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            guard !text.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 96),
                .foregroundColor: UIColor.black,
            ]
            let string = NSAttributedString(string: text, attributes: attrs)
            let textSize = string.size()
            let rect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            string.draw(in: rect)
        }
        return image.cgImage!
    }
}
