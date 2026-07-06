import SwiftUI

/// The Ken-Burns drift (brand/LUXURY-MOTION.md §4 depth/parallax family ·
/// ELEVATION.md §7: the arrival + dossier headers get "the slow, cinematic
/// treatment"). A hero image slowly, continuously scales and pans so a still
/// photograph breathes, the signature "this is premium" ambient motion on
/// arrival heroes and dossier header medallions.
///
/// It is the one sanctioned *ambient* image loop (alongside scanline/compass in
/// ELEVATION §3); keep it to hero surfaces only, never behind reading copy
/// (LUXURY-MOTION §7: "No motion on body text or during reading").
///
/// Motion is transform-only (scale + offset) so it stays 60fps. The drift eases
/// in-out and auto-reverses on a long loop (default ~18s each way) so it never
/// snaps back. Under Reduce Motion the modifier is inert: the image rests at a
/// gentle fixed zoom (so a `.fill` crop still covers) with no movement at all.
struct KenBurns: ViewModifier {
    /// Seconds for one drift leg (there and back auto-reverses).
    var duration: Double = 18
    /// Peak zoom the image drifts toward (1.0 = no zoom). A small value keeps it
    /// tasteful; 1.12 is a slow, expensive-feeling push-in.
    var maxScale: CGFloat = 1.12
    /// Peak pan, points, along each axis at full drift.
    var pan: CGSize = CGSize(width: 14, height: 10)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(currentScale, anchor: .center)
            .offset(currentOffset)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(loop) { drifting = true }
            }
            // The drift lives inside the frame; clip so the pan never reveals an
            // edge. Callers still set their own `.frame`.
            .clipped()
    }

    /// Even at rest we hold a slight zoom so a `.fill` image keeps full coverage
    /// as it pans; under Reduce Motion this fixed value is the whole story.
    private var restScale: CGFloat { reduceMotion ? 1.04 : 1.0 }

    private var currentScale: CGFloat {
        reduceMotion ? restScale : (drifting ? maxScale : 1.0)
    }

    private var currentOffset: CGSize {
        guard !reduceMotion else { return .zero }
        return drifting ? pan : .zero
    }

    private var loop: Animation {
        .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }
}

extension View {
    /// Apply a slow Ken-Burns drift (scale + pan) to a hero image. Ambient and
    /// hero-only; Reduce-Motion static.
    ///
    /// ```swift
    /// BlurUpAsyncImage(url: heroURL)
    ///     .kenBurns()                 // arrival / dossier header
    ///     .frame(height: 280).clipped()
    /// ```
    func kenBurns(
        duration: Double = 18,
        maxScale: CGFloat = 1.12,
        pan: CGSize = CGSize(width: 14, height: 10)
    ) -> some View {
        modifier(KenBurns(duration: duration, maxScale: maxScale, pan: pan))
    }
}
