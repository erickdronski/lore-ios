import SwiftUI
import UIKit

/// The `grad.brass-sheen` token (brand/ELEVATION.md §2) as reusable SwiftUI
/// fills, plus the one-shot sweep animation that plays when a Lore+ surface
/// unlocks. Premium is the *only* place Brass gets to shine — everywhere else
/// Brass is decorative-on-light or `brass700` text (brand/DESIGN.md §4).
///
/// `grad.brass-sheen`:
/// `linear(105deg, #85601D 0%, #B98A2F 38%, #E3B65A 50%, #B98A2F 62%, #85601D 100%)`
enum BrassSheen {
    /// The five stops of the sheen ramp, dark→bright→dark.
    static let stops: [Color] = [
        Color(hex: 0x85601D),
        Color(hex: 0xB98A2F),
        Color(hex: 0xE3B65A),
        Color(hex: 0xB98A2F),
        Color(hex: 0x85601D),
    ]

    /// The static 105° linear gradient — the premium surface's resting fill.
    /// 105° measured from the x-axis; expressed as unit points on the diagonal.
    static var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: stops[0], location: 0.0),
                .init(color: stops[1], location: 0.38),
                .init(color: stops[2], location: 0.50),
                .init(color: stops[3], location: 0.62),
                .init(color: stops[4], location: 1.0),
            ],
            startPoint: UnitPoint(x: 0.0, y: 0.13),  // ≈105° sweep
            endPoint: UnitPoint(x: 1.0, y: -0.13)
        )
    }
}

/// A brass surface that, on appear (or when `unlocked` flips true), runs a
/// single 1.2 s sheen sweep — the light catching the Brass, once, never a
/// looping shimmer (brand/ELEVATION.md §2, §3: "sheen sweeps on unlock, 1.2s,
/// once"; anti-slop bans perpetual glassmorphism shimmer). Reduce Motion drops
/// the sweep and just shows the resting gradient.
struct BrassSheenSurface<S: Shape>: View {
    /// The shape to fill (a capsule for chips, a rounded rect for cards).
    let shape: S
    /// Flip to true to (re)trigger the sweep — e.g. the moment a feature
    /// unlocks. Defaults to sweeping once on first appear.
    var sweepOnAppear: Bool = true

    @State private var sweep: CGFloat = -1

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    var body: some View {
        shape
            .fill(BrassSheen.gradient)
            .overlay {
                if !reduceMotion {
                    // A soft bright band that travels across once.
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color(hex: 0xF4DDA0).opacity(0.55),
                                    .clear,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .mask(shape)
                        .offset(x: sweep * 260)
                        .blendMode(.screen)
                }
            }
            .onAppear {
                guard sweepOnAppear, !reduceMotion else { return }
                sweep = -1
                withAnimation(.easeInOut(duration: 1.2)) { sweep = 1 }
            }
    }
}
