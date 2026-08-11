import SwiftUI
import UIKit

/// The shareable "Lore card" (docs: social-content-first). A designed, magazine
/// grade poster of a single place that a user can post straight to Instagram,
/// TikTok, or X, or save as an image. It is deliberately a *designed* card, not
/// a third-party photo, so it is always on brand and carries no image-licensing
/// or provenance-firewall risk (brand/DESIGN.md, docs/00-DECISIONS.md).
///
/// Rendered off-screen to a `UIImage` by `ShareCardRenderer` at a fixed logical
/// size so the export is pixel-exact regardless of the device it was shared
/// from. The `story` format is 9:16 for Instagram/TikTok stories; `square` is
/// 1:1 for feed posts.
struct LoreShareCard: View {
    let place: Place
    var format: Format = .story
    var heroImage: UIImage? = nil

    enum Format: Hashable, Sendable {
        case story   // 1080x1920 at scale 3 (logical 360x640)
        case square  // 1080x1080 at scale 3 (logical 360x360)

        /// Logical (point) size; the renderer multiplies by scale for pixels.
        var size: CGSize {
            switch self {
            case .story: return CGSize(width: 360, height: 640)
            case .square: return CGSize(width: 360, height: 360)
            }
        }

        var accessibilityName: String {
            switch self {
            case .story: return "story"
            case .square: return "square post"
            }
        }
    }

    /// Human city label from the slug ("new-york" -> "New York").
    private var cityLabel: String {
        place.city.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: format == .story ? 12 : 18)
                nameBlock
                if let hook = place.teaser, !hook.isEmpty {
                    Text(hook)
                        .font(LoreType.display(size: format == .story ? 20 : 15, weight: .medium).italic())
                        .foregroundStyle(LoreColor.bone.opacity(0.86))
                        .lineSpacing(format == .story ? 3 : 2)
                        .lineLimit(format == .story ? 5 : 2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, format == .story ? 14 : 12)
                }
                factStrip
                    .padding(.top, format == .story ? 16 : 14)
                Spacer(minLength: format == .story ? 12 : 20)
                footer
            }
            .padding(format == .story ? 34 : 30)
        }
        .frame(width: format.size.width, height: format.size.height)
        .clipShape(RoundedRectangle(cornerRadius: format == .story ? 0 : 28, style: .continuous))
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [LoreColor.ink950, LoreColor.ink900, Color(hex: 0x141D31)],
                startPoint: .top, endPoint: .bottom
            )
            // A warm amber aura in the upper third, the signature Lore glow.
            RadialGradient(
                colors: [LoreColor.amber.opacity(0.22), .clear],
                center: .init(x: 0.5, y: 0.16), startRadius: 0, endRadius: format.size.width * 0.95
            )
            // A soft vignette so the poster reads as a lit object.
            RadialGradient(
                colors: [.clear, LoreColor.ink950.opacity(0.55)],
                center: .center, startRadius: format.size.width * 0.35, endRadius: format.size.width * 0.85
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Header (kicker + medallion)

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                // The non-negotiable recognition anchor: the Amber-beacon "LORE."
                // signature, fixed top-left on every share card (strategy synth).
                Text("LORE.")
                    .font(.system(size: format == .story ? 16 : 15, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(LoreColor.amber)
                Text(cityLabel.uppercased())
                    .font(.system(size: format == .story ? 11 : 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(LoreColor.bone.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            medallion
        }
    }

    private var medallion: some View {
        ZStack(alignment: .bottomTrailing) {
            assetPlate
            emojiCluster
                .offset(x: format == .story ? 8 : 7, y: format == .story ? 7 : 6)
        }
    }

    @ViewBuilder
    private var assetPlate: some View {
        let width: CGFloat = format == .story ? 82 : 58
        let height: CGFloat = format == .story ? 94 : 66
        let radius: CGFloat = format == .story ? 25 : 21
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LoreColor.amber.opacity(0.13))
            if let heroImage {
                Image(uiImage: heroImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .overlay(
                        LinearGradient(
                            colors: [
                                LoreColor.ink950.opacity(0.04),
                                LoreColor.ink950.opacity(0.38),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                LoreTileArtwork(kind: .story, accent: LoreColor.brass300, intensity: 0.18)
                Text(place.displayEmoji)
                    .font(.system(size: format == .story ? 34 : 28))
                    .shadow(color: LoreColor.ink950.opacity(0.35), radius: 8, x: 0, y: 4)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LoreColor.brass300.opacity(heroImage == nil ? 0.55 : 0.72), lineWidth: 1.4)
        )
        .shadow(color: LoreColor.ink950.opacity(0.34), radius: 16, x: 0, y: 10)
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(LoreColor.bone.opacity(0.42))
                .frame(width: 9, height: 9)
                .padding(9)
                .blendMode(.screen)
                .accessibilityHidden(true)
        }
    }

    private var emojiCluster: some View {
        HStack(spacing: 3) {
            ForEach(Array(shareEmojis.prefix(2).enumerated()), id: \.offset) { _, emoji in
                Text(emoji)
                    .font(.system(size: format == .story ? 12 : 10))
                    .frame(width: format == .story ? 23 : 20, height: format == .story ? 23 : 20)
                    .background(Circle().fill(LoreColor.bone.opacity(0.94)))
                    .overlay(Circle().strokeBorder(LoreColor.brass300.opacity(0.5), lineWidth: 0.8))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(Capsule().fill(LoreColor.ink950.opacity(0.52)))
        .accessibilityHidden(true)
    }

    private var shareEmojis: [String] {
        var values: [String] = []
        func append(_ value: String) {
            guard !value.isEmpty, !values.contains(value) else { return }
            values.append(value)
        }
        append(place.displayEmoji)
        let normalized = ([place.kind] + place.tags).map {
            $0.lowercased().replacingOccurrences(of: "_", with: " ")
        }
        if normalized.contains(where: { $0.contains("beer") || $0.contains("bar") || $0.contains("pub") || $0.contains("venue") || $0.contains("nightlife") }) {
            append("🍻")
        }
        if normalized.contains(where: { $0.contains("bridge") }) {
            append("🌉")
        }
        if normalized.contains(where: { $0.contains("park") || $0.contains("garden") || $0.contains("nature") }) {
            append("🌿")
        }
        if normalized.contains(where: { $0.contains("museum") || $0.contains("gallery") || $0.contains("art") }) {
            append("🖼️")
        }
        if normalized.contains(where: { $0.contains("church") || $0.contains("temple") }) {
            append("⛪️")
        }
        if normalized.contains(where: { $0.contains("monument") || $0.contains("memorial") || $0.contains("statue") || $0.contains("sculpture") }) {
            append("🏛️")
        }
        append("📍")
        return values
    }

    // MARK: Name + kind

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name)
                .font(LoreType.display(size: format == .story ? 46 : 31, weight: .semibold))
                .foregroundStyle(LoreColor.bone)
                .lineLimit(format == .story ? 4 : 3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(place.kind.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.system(size: format == .story ? 12 : 10, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(LoreColor.amber)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // MARK: Fact strip (year / architect / height)

    @ViewBuilder
    private var factStrip: some View {
        let facts = shareFacts
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(LoreColor.brass300.opacity(0.35))
                    .frame(height: 1)
                    .padding(.bottom, format == .story ? 14 : 10)
                HStack(alignment: .top, spacing: format == .story ? 22 : 18) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.label.uppercased())
                                .font(.system(size: format == .story ? 9 : 8, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(LoreColor.bone.opacity(0.5))
                            Text(fact.value)
                                .font(.system(size: format == .story ? 14 : 12, weight: .medium, design: .rounded))
                                .foregroundStyle(LoreColor.bone.opacity(0.92))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private struct ShareFact { let label: String; let value: String }

    private var shareFacts: [ShareFact] {
        var out: [ShareFact] = []
        if let year = place.layer1?.yearBuilt { out.append(.init(label: "Since", value: String(year))) }
        if let style = place.layer1?.style { out.append(.init(label: "Style", value: style)) }
        if let h = place.heightM, h > 0 { out.append(.init(label: "Height", value: "\(Int(h)) m")) }
        return Array(out.prefix(3))
    }

    // MARK: Footer wordmark

    private var footer: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Every place has a story.")
                    .font(LoreType.display(size: format == .story ? 13 : 11, weight: .medium).italic())
                    .foregroundStyle(LoreColor.bone.opacity(0.7))
                Text("Discovered with Lore")
                    .font(.system(size: format == .story ? 10 : 8.5, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(LoreColor.bone.opacity(0.4))
            }
            Spacer()
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: format == .story ? 22 : 18))
                .foregroundStyle(LoreColor.brass300.opacity(0.8))
        }
    }
}
