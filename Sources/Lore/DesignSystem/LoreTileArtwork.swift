import SwiftUI

/// A small visual vocabulary for Lore's text-led cards. Each content family
/// gets a recognizable field-guide mark so a phrase, memory, route, or offer
/// can be understood before the first line is read.
enum LoreArtworkKind: Hashable {
    case story
    case quote
    case fact
    case number
    case phrase
    case food
    case drink
    case sound
    case etiquette
    case material
    case market
    case route
    case memory
    case offer
    case discovery
    case achievement

    init(contentKind: String) {
        switch contentKind.lowercased() {
        case "quote": self = .quote
        case "fact", "fun_fact", "name_origin": self = .fact
        case "number", "stat": self = .number
        case "phrase", "language": self = .phrase
        case "dish", "food": self = .food
        case "drink": self = .drink
        case "sound", "soundmark", "listen": self = .sound
        case "etiquette", "ritual": self = .etiquette
        case "material": self = .material
        case "market": self = .market
        case "experience", "tour", "route": self = .route
        case "journal", "field_note", "memory": self = .memory
        case "deal", "offer": self = .offer
        case "achievement", "badge": self = .achievement
        case "discovery", "place": self = .discovery
        default: self = .story
        }
    }

    var symbol: String {
        switch self {
        case .story: return "book.pages.fill"
        case .quote: return "quote.opening"
        case .fact: return "sparkle.magnifyingglass"
        case .number: return "chart.line.uptrend.xyaxis"
        case .phrase: return "character.bubble.fill"
        case .food: return "fork.knife"
        case .drink: return "mug.fill"
        case .sound: return "waveform"
        case .etiquette: return "hand.wave.fill"
        case .material: return "square.3.layers.3d"
        case .market: return "storefront.fill"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        case .memory: return "camera.macro"
        case .offer: return "ticket.fill"
        case .discovery: return "binoculars.fill"
        case .achievement: return "seal.fill"
        }
    }

    fileprivate var companionSymbol: String {
        switch self {
        case .story, .fact: return "text.book.closed.fill"
        case .quote, .phrase: return "waveform"
        case .number: return "number"
        case .food: return "leaf.fill"
        case .drink: return "drop.fill"
        case .sound: return "ear.fill"
        case .etiquette: return "person.2.fill"
        case .material: return "cube.fill"
        case .market, .offer: return "sparkles"
        case .route, .discovery: return "location.fill"
        case .memory: return "bookmark.fill"
        case .achievement: return "star.fill"
        }
    }
}

/// Quiet background artwork for a card. It uses only transform/opacity motion,
/// and becomes completely still when Reduce Motion is enabled.
struct LoreTileArtwork: View {
    let kind: LoreArtworkKind
    var accent: Color = LoreColor.amber
    var intensity: Double = 0.22
    var animates = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                contourLines(in: size)

                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: min(size.width, size.height) * 0.78)
                    .blur(radius: 1)
                    .offset(x: size.width * 0.34, y: -size.height * 0.23)

                Image(systemName: kind.symbol)
                    .font(.system(size: max(42, min(size.width, size.height) * 0.34), weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
                    .rotationEffect(.degrees(drifting && !reduceMotion ? 3 : -2))
                    .offset(
                        x: size.width * 0.31,
                        y: drifting && !reduceMotion ? -size.height * 0.08 : -size.height * 0.04
                    )

                Image(systemName: kind.companionSymbol)
                    .font(.system(size: max(15, min(size.width, size.height) * 0.10), weight: .bold))
                    .foregroundStyle(accent)
                    .padding(9)
                    .background(.thinMaterial, in: Circle())
                    .offset(x: size.width * 0.20, y: size.height * 0.27)

                fieldDots(in: size)
            }
            .opacity(intensity)
            .clipped()
            .onAppear {
                guard animates, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true)) {
                    drifting = true
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func contourLines(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            for index in 0..<4 {
                var path = Path()
                let y = canvasSize.height * (0.16 + CGFloat(index) * 0.21)
                path.move(to: CGPoint(x: -12, y: y))
                path.addCurve(
                    to: CGPoint(x: canvasSize.width + 16, y: y + CGFloat(index.isMultiple(of: 2) ? 8 : -6)),
                    control1: CGPoint(x: canvasSize.width * 0.28, y: y - 22),
                    control2: CGPoint(x: canvasSize.width * 0.68, y: y + 24)
                )
                context.stroke(path, with: .color(accent.opacity(0.45)), lineWidth: index == 1 ? 1.4 : 0.8)
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(x: drifting && !reduceMotion ? 5 : 0)
    }

    private func fieldDots(in size: CGSize) -> some View {
        ZStack {
            Circle().frame(width: 5, height: 5).offset(x: -size.width * 0.35, y: -size.height * 0.25)
            Circle().frame(width: 8, height: 8).offset(x: -size.width * 0.26, y: size.height * 0.18)
            Circle().frame(width: 4, height: 4).offset(x: size.width * 0.02, y: size.height * 0.32)
        }
        .foregroundStyle(accent)
    }
}

/// A compact content marker for headers and rows. It intentionally avoids
/// emoji-only meaning: the SF Symbol remains legible in grayscale and VoiceOver
/// receives meaning from the surrounding label.
struct LoreArtworkMedallion: View {
    let kind: LoreArtworkKind
    var symbol: String? = nil
    var accent: Color = LoreColor.brass700
    var diameter: CGFloat = 38
    var isDark = false

    var body: some View {
        Image(systemName: symbol ?? kind.symbol)
            .font(.system(size: diameter * 0.38, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isDark ? LoreColor.ink900 : accent)
            .frame(width: diameter, height: diameter)
            .background(
                LinearGradient(
                    colors: [accent.opacity(isDark ? 0.95 : 0.18), accent.opacity(isDark ? 0.72 : 0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(accent.opacity(0.42), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
