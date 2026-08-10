import SwiftUI
import UIKit

/// Renders a SwiftUI view off-screen to a `UIImage` at a fixed pixel size, so a
/// share export is identical regardless of the device it came from. Uses
/// `ImageRenderer` (iOS 16+); `scale` maps logical points to export pixels
/// (a 360x640 card at scale 3 exports 1080x1920, Instagram-Story native).
@MainActor
enum ShareCardRenderer {
    /// Render `content` sized to `size` points at `scale`x. Returns nil only if
    /// the renderer cannot produce an image (never expected for a laid-out view).
    static func image(_ content: some View, size: CGSize, scale: CGFloat = 3) -> UIImage? {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite,
              size.width > 0, size.height > 0, scale > 0, scale <= 4 else { return nil }
        let renderer = ImageRenderer(
            content: content
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Convenience for a `LoreShareCard` in a given format.
    static func loreCard(
        _ place: Place,
        format: LoreShareCard.Format = .story,
        heroImage: UIImage? = nil
    ) -> UIImage? {
        image(LoreShareCard(place: place, format: format, heroImage: heroImage), size: format.size)
    }
}
