import SwiftUI

/// The arrival-screen hero: a scanner viewfinder framing a small city skyline
/// with an Amber story pin dropped on the tallest tower. Drawn entirely in
/// SwiftUI (no asset, scales crisply on any device), it is a literal preview of
/// the core gesture, point your phone at a building and its story surfaces, so
/// the very first screen shows the product instead of only describing it.
///
/// A slow ambient breathe on the pin's halo gives it life; it holds still when
/// Reduce Motion is on. Purely decorative, the headline carries the meaning, so
/// it is hidden from VoiceOver.
struct ArrivalHeroMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    /// Overall square size. Comfortably fills the arrival dead-space on large
    /// phones and compresses gracefully inside the step's flexible Spacers.
    var side: CGFloat = 224

    var body: some View {
        ZStack {
            reticle
            cityscape
        }
        .frame(width: side, height: side)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Viewfinder

    /// Four camera-style corner brackets, quiet Bone so the pin stays the hero.
    private var reticle: some View {
        ViewfinderCorners(bracket: 30, radius: 22)
            .stroke(
                LoreColor.bone.opacity(0.38),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: side - 20, height: side - 20)
    }

    // MARK: Skyline + pin

    /// The towers sit on a faint horizon inside the reticle; the tallest carries
    /// the story pin so the alignment is anchored, never pixel-guessed.
    private var cityscape: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(LoreColor.bone.opacity(0.16))
                    .frame(height: 1)
                HStack(alignment: .bottom, spacing: 9) {
                    tower(height: 60, lit: false, pinned: false)
                    tower(height: 104, lit: true, pinned: false)
                    tower(height: 80, lit: false, pinned: false)
                    tower(height: 126, lit: true, pinned: true) // tallest → pin
                    tower(height: 54, lit: false, pinned: false)
                }
            }
        }
        .frame(width: side - 52, height: side - 56, alignment: .bottom)
        .padding(.bottom, 8)
    }

    private func tower(height: CGFloat, lit: Bool, pinned: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [LoreColor.ink700, LoreColor.ink800],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 26, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(LoreColor.ink600.opacity(0.55), lineWidth: 0.5)
            )
            .overlay(alignment: .top) {
                if lit { litWindows.padding(.top, 12) }
            }
            .overlay(alignment: .top) {
                if pinned { storyPin.offset(y: -30) }
            }
    }

    /// A few warm windows on the lit towers, the city is awake.
    private var litWindows: some View {
        VStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 6) {
                    Circle().fill(LoreColor.amber.opacity(0.85)).frame(width: 3, height: 3)
                    Circle().fill(LoreColor.amber.opacity(0.45)).frame(width: 3, height: 3)
                }
            }
        }
    }

    /// The Amber story pin with a breathing halo, the moment a story is found.
    private var storyPin: some View {
        ZStack {
            Circle()
                .fill(LoreColor.amber.opacity(0.30))
                .frame(width: 84, height: 84)
                .blur(radius: 20)
                .scaleEffect(breathe ? 1.06 : 0.9)
                .opacity(breathe ? 0.95 : 0.55)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 32, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(LoreColor.ink, LoreColor.amber)
                .shadow(color: LoreColor.amber.opacity(0.55), radius: 7)
        }
    }
}

/// Four camera-style corner brackets (an L with a rounded elbow at each corner),
/// a viewfinder rather than a closed frame.
private struct ViewfinderCorners: Shape {
    var bracket: CGFloat = 28
    var radius: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect
        // top-left
        p.move(to: CGPoint(x: r.minX, y: r.minY + radius + bracket))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY),
                       control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + radius + bracket, y: r.minY))
        // top-right
        p.move(to: CGPoint(x: r.maxX - radius - bracket, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius),
                       control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + radius + bracket))
        // bottom-right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - radius - bracket))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY),
                       control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - radius - bracket, y: r.maxY))
        // bottom-left
        p.move(to: CGPoint(x: r.minX + radius + bracket, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius),
                       control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius - bracket))
        return p
    }
}
