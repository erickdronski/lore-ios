import SwiftUI

/// Blur-up image loading (brand/LUXURY-MOTION.md §3): "No pop-in, no layout
/// shift." An async image that, while the sharp image loads, shows a shimmering
/// placeholder (optionally a tiny blurred low-res thumbnail), then **cross-fades
/// to sharp over ~400ms** once it arrives.
///
/// Two placeholder modes:
/// - Give a `thumbnail` (a tiny already-loaded low-res `Image`, e.g. a BlurHash
///   decode or a cached thumb): it is shown blurred and cross-fades under the
///   sharp image. This is the true "blur-up."
/// - Give nothing: a `Shimmer` placeholder fills the frame until load.
///
/// Under Reduce Motion the cross-fade collapses to an instant swap (the doctrine
/// allows a ≤160ms crossfade; here we simply drop the transform-free fade to be
/// safe and calm) and the shimmer is static.
///
/// Layout: the frame is fixed by the caller (`.frame`/aspect ratio) so nothing
/// shifts when the image lands — the sharp image fills the same box the
/// placeholder held.
struct BlurUpAsyncImage: View {
    let url: URL?
    /// Optional tiny low-res image shown blurred beneath the sharp one.
    var thumbnail: Image? = nil
    /// Cross-fade duration once the sharp image arrives (LUXURY-MOTION §3).
    var fadeDuration: Double = 0.40
    /// How the sharp image fills its frame.
    var contentMode: ContentMode = .fill

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: loadAnimation)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(fadeTransition)
            case .failure:
                // Failed load rests on the blurred thumb if we have one, else
                // a static muted block — never a broken-image glyph.
                placeholder
            case .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .clipped()
    }

    /// The pre-arrival state: a blurred low-res thumb if supplied, otherwise a
    /// shimmering muted fill.
    @ViewBuilder private var placeholder: some View {
        if let thumbnail {
            thumbnail
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .blur(radius: 12)
                .clipped()
                .overlay(LoreColor.ink950.opacity(0.06)) // gentle dusk tint
        } else {
            Rectangle()
                .fill(LoreColor.bone200)
                .shimmer()
        }
    }

    /// The transaction animation AsyncImage applies when the phase changes.
    private var loadAnimation: Animation? {
        reduceMotion ? LoreSpring.reducedCrossfade : .easeOut(duration: fadeDuration)
    }

    /// Sharp image entrance: an opacity cross-fade (no transform, 60fps-safe).
    private var fadeTransition: AnyTransition {
        .opacity
    }
}
