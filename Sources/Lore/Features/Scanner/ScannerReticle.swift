import SwiftUI

/// The viewfinder reticle, the two sanctioned ambient loops of the scanner
/// (brand/ELEVATION.md §3): the Amber **corner-frame** with a 1px **scanline**
/// sweep (3.2s, 12% opacity) and the **breathing** center that privileges
/// gaze. Everything is transform/opacity only and honors Reduce Motion (the
/// loops stop, the frame stays, information delivery is never removed,
/// brand/DESIGN.md §6).
///
/// This is chrome over the live camera, so it obeys the AR color rule: only
/// Amber/Ink/Bone in the viewfinder, no semantic colors (brand/DESIGN.md §4).
struct ScannerReticle: View {
    /// True while a Tier-A candidate is locked, the frame firms up (fuller
    /// Amber, one settle) so a lock *looks* different from a hunt (docs/12 §2).
    var isLocked: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanY: CGFloat = 0
    @State private var breathe = false

    /// Reticle box is a centered square, ~62% of the shorter side, big enough
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

    /// Four Amber L-brackets, the corner-frame, never a full box (a full box
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
            // The frame firms up on a settled spring when a lock lands, one
            // confident settle, no overshoot on chrome (LUXURY-MOTION §2, §7).
            .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: isLocked)
    }

    // MARK: Scanline

    /// The `scanline` loop (ELEVATION §3): a 1px Amber sweep at 12% opacity,
    /// 3.2s, top→bottom inside the frame. Held static (hidden) under Reduce
    /// Motion, an idle decoration, safe to drop.
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
        // compass.breathe, 1→1.04 sine, 2.4s (ELEVATION §3). Applied here to
        // the frame as the "acquiring" pulse; the compass ring reuses it below.
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }
}

/// The four corner L-brackets as a single `Shape`, cheaper than four views and
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

/// The scanner compass: a glassy heading dial in the top-right corner. A
/// rotating bezel (tick marks + cardinal letters) keeps its North mark aimed at
/// true north as you turn; a fixed amber arrow at the top marks the way you are
/// facing; the centre reads the live heading. A soft amber halo confirms the
/// heading is live. Passive; not interactive.
struct CompassRing: View {
    /// Device heading, degrees clockwise from true north; negative = unknown.
    var headingDegrees: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let diameter: CGFloat = 66
    private var known: Bool { headingDegrees >= 0 }
    /// The bezel counter-rotates so its North mark always points at true north.
    private var bezelRotation: Double { known ? -headingDegrees : 0 }

    var body: some View {
        ZStack {
            // Glassy base disc with a gradient amber rim.
            Circle()
                .fill(LoreColor.ink900.opacity(0.5))
                .background(.ultraThinMaterial, in: Circle())
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            LoreColor.amber.opacity(0.9),
                            LoreColor.amber.opacity(0.2),
                            LoreColor.amber.opacity(0.9)
                        ],
                        center: .center
                    ),
                    lineWidth: 1.2
                )

            bezel
                .rotationEffect(.degrees(bezelRotation))
                .animation(reduceMotion ? nil : LoreMotion.drift, value: bezelRotation)
                .opacity(known ? 1 : 0.45)

            facingArrow
            centreReadout
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: LoreColor.ink.opacity(0.45), radius: 6, x: 0, y: 2)
        .overlay(
            // Soft amber halo when the heading is live.
            Circle()
                .stroke(LoreColor.amber.opacity(known ? 0.28 : 0), lineWidth: 5)
                .blur(radius: 6)
                .allowsHitTesting(false)
        )
        .accessibilityLabel(Text("Compass"))
        .accessibilityValue(Text(known ? "\(Int(headingDegrees.rounded())) degrees" : "Heading unavailable"))
    }

    /// Tick marks + cardinal letters, printed on the ring so they turn with it.
    private var bezel: some View {
        ZStack {
            ForEach(0..<24, id: \.self) { i in
                let major = i % 6 == 0
                Capsule()
                    .fill(major ? LoreColor.amber : LoreColor.bone.opacity(0.35))
                    .frame(width: major ? 2 : 1, height: major ? 9 : 5)
                    .offset(y: -diameter / 2 + (major ? 6.5 : 4.5))
                    .rotationEffect(.degrees(Double(i) * 15))
            }
            ForEach(CompassRing.cardinals, id: \.angle) { cardinal in
                Text(cardinal.label)
                    .font(.system(size: cardinal.label == "N" ? 11 : 9,
                                  weight: cardinal.label == "N" ? .bold : .semibold,
                                  design: .rounded))
                    .foregroundStyle(cardinal.label == "N" ? LoreColor.amber : LoreColor.bone.opacity(0.7))
                    .offset(y: -diameter / 2 + 17)
                    .rotationEffect(.degrees(cardinal.angle))
            }
        }
    }

    /// Fixed at the very top, pointing down into the ring: the way you face.
    private var facingArrow: some View {
        CompassFacingArrow()
            .fill(LoreColor.amber)
            .frame(width: 10, height: 8)
            .offset(y: -diameter / 2 - 2)
            .shadow(color: LoreColor.amber.opacity(0.7), radius: 3)
    }

    private var centreReadout: some View {
        VStack(spacing: 0) {
            Text(known ? "\(Int(headingDegrees.rounded()))°" : "–")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(LoreColor.bone)
                .monospacedDigit()
            if known {
                Text(CompassRing.cardinalName(for: headingDegrees))
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(LoreColor.amber.opacity(0.9))
            }
        }
    }

    private static let cardinals: [(label: String, angle: Double)] =
        [("N", 0), ("E", 90), ("S", 180), ("W", 270)]

    private static func cardinalName(for deg: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (deg.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return names[Int((normalized / 45).rounded()) % 8]
    }
}

/// A small downward-pointing triangle — the compass's fixed "facing" mark.
private struct CompassFacingArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
