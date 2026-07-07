import SwiftUI

/// Choreographed entrance for the dossier deep-dive (brand LUXURY-MOTION §3, §6):
/// the content stack reveals in three brief waves — narrative, then gallery, then
/// timeline — so the dossier *unfolds* rather than flashing in.
///
/// Pure opacity + a 14pt rise (no background effect, no scrim), so text contrast
/// is untouched. Under Reduce Motion every section appears together in one
/// ~160ms crossfade with no transforms (LUXURY-MOTION §7). GPU-cheap: opacity +
/// offset only, all state local.
struct DiveEntranceEffect: ViewModifier {
    /// Section index (0 = narrative, 1 = gallery, 2 = timeline). Drives the
    /// cascade delay at `step` per wave.
    let index: Int
    var step: TimeInterval = 0.10
    var rise: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (appeared ? 0 : rise))
            .onAppear {
                guard !appeared else { return }
                if reduceMotion {
                    withAnimation(LoreSpring.reducedCrossfade) { appeared = true }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * step) {
                        withAnimation(LoreSpring.smooth) { appeared = true }
                    }
                }
            }
    }
}

extension View {
    /// Apply the dossier entrance cascade; lower indices reveal first.
    func diveEntrance(index: Int, step: TimeInterval = 0.10) -> some View {
        modifier(DiveEntranceEffect(index: index, step: step))
    }
}
