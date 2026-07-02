import SwiftUI

/// The viewfinder reticle — the two sanctioned ambient loops of the scanner
/// (brand/ELEVATION.md §3): the Amber **corner-frame** with a 1px **scanline**
/// sweep (3.2s, 12% opacity) and the **breathing** center that privileges
/// gaze. Everything is transform/opacity only and honors Reduce Motion (the
/// loops stop, the frame stays — information delivery is never removed,
/// brand/DESIGN.md §6).
///
/// This is chrome over the live camera, so it obeys the AR color rule: only
/// Amber/Ink/Bone in the viewfinder, no semantic colors (brand/DESIGN.md §4).
struct ScannerReticle: View {
    /// True while a Tier-A candidate is locked — the frame firms up (fuller
    /// Amber, one settle) so a lock *looks* different from a hunt (docs/12 §2).
    var isLocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanY: CGFloat = 0
    @State private var breathe = false

    /// Reticle box is a centered square, ~62% of the shorter side — big enough
    /// to frame a façade, small enough to keep gaze meaningful.
    private let sideFraction: CGFloat = 0.62
    private let cornerLength: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * sideFraction
            let origin = CGPoint(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2
            )
            let rect = CGRect(origin: origin, size: CGSize(width: side, height: side))

            ZStack {
                cornerFrame(in: rect)
                scanline(in: rect)
            }
            .onAppear { startLoops(height: side, top: origin.y) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Corner frame

    /// Four Amber L-brackets — the corner-frame, never a full box (a full box
    /// reads as a QR scanner, not a lens). Firms brighter when locked.
    private func cornerFrame(in rect: CGRect) -> some View {
        ReticleCorners(cornerLength: cornerLength)
            .stroke(
                LoreColor.amber.opacity(isLocked ? 0.95 : 0.7),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .scaleEffect(breathe && !reduceMotion ? 1.02 : 1.0)
            .shadow(color: LoreColor.ink.opacity(0.35), radius: 3, x: 0, y: 1)
            .animation(LoreMotion.unfurl, value: isLocked)
    }

    // MARK: Scanline

    /// The `scanline` loop (ELEVATION §3): a 1px Amber sweep at 12% opacity,
    /// 3.2s, top→bottom inside the frame. Held static (hidden) under Reduce
    /// Motion — an idle decoration, safe to drop.
    @ViewBuilder
    private func scanline(in rect: CGRect) -> some View {
        if !reduceMotion {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            LoreColor.amber.opacity(0),
                            LoreColor.amber.opacity(0.12),
                            LoreColor.amber.opacity(0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: rect.width, height: 1)
                .position(x: rect.midX, y: scanY)
        }
    }

    // MARK: Loops

    private func startLoops(height: CGFloat, top: CGFloat) {
        guard !reduceMotion else { return }
        scanY = top
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
            scanY = top + height
        }
        // compass.breathe — 1→1.04 sine, 2.4s (ELEVATION §3). Applied here to
        // the frame as the "acquiring" pulse; the compass ring reuses it below.
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }
}

/// The four corner L-brackets as a single `Shape` — cheaper than four views and
/// it strokes as one path so the Amber weight is uniform.
private struct ReticleCorners: Shape {
    let cornerLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = cornerLength

        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))

        return path
    }
}

/// The bottom compass ring — the second sanctioned ambient loop
/// (`compass.breathe`, ELEVATION §3): a thin Amber heading ring that scales
/// 1→1.04 on a 2.4s sine, with a north tick that rotates opposite the device
/// heading so it always points at true north. Passive; not interactive.
struct CompassRing: View {
    /// Device heading, degrees clockwise from true north; negative = unknown.
    var headingDegrees: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private let diameter: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(LoreColor.amber.opacity(0.6), lineWidth: 1.5)
                .frame(width: diameter, height: diameter)

            // North tick: rotates to keep pointing at true north as we turn.
            Capsule()
                .fill(LoreColor.amber)
                .frame(width: 2, height: 10)
                .offset(y: -diameter / 2 + 6)
                .rotationEffect(.degrees(headingDegrees >= 0 ? -headingDegrees : 0))
                .animation(LoreMotion.drift, value: headingDegrees)

            Text("N")
                .font(LoreType.micro)
                .foregroundStyle(LoreColor.bone)
        }
        .scaleEffect(breathe && !reduceMotion ? 1.04 : 1.0)
        .shadow(color: LoreColor.ink.opacity(0.35), radius: 3, x: 0, y: 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityLabel(Text("Compass"))
    }
}
