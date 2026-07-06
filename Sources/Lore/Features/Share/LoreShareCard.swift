import SwiftUI

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

    enum Format {
        case story   // 1080x1920 at scale 3 (logical 360x640)
        case square  // 1080x1080 at scale 3 (logical 360x360)

        /// Logical (point) size; the renderer multiplies by scale for pixels.
        var size: CGSize {
            switch self {
            case .story: return CGSize(width: 360, height: 640)
            case .square: return CGSize(width: 360, height: 360)
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
                Spacer(minLength: 12)
                nameBlock
                if let hook = place.layer1?.hook, !hook.isEmpty {
                    Text(hook)
                        .font(LoreType.display(size: format == .story ? 20 : 17, weight: .medium).italic())
                        .foregroundStyle(LoreColor.bone.opacity(0.86))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
                factStrip
                    .padding(.top, 16)
                Spacer(minLength: 12)
                footer
            }
            .padding(format == .story ? 34 : 28)
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
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(LoreColor.amber)
                Text(cityLabel.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(LoreColor.bone.opacity(0.55))
            }
            Spacer()
            medallion
        }
    }

    private var medallion: some View {
        Text(place.displayEmoji)
            .font(.system(size: format == .story ? 40 : 34))
            .frame(width: format == .story ? 72 : 60, height: format == .story ? 72 : 60)
            .background(
                Circle().fill(LoreColor.amber.opacity(0.14))
            )
            .overlay(
                Circle().strokeBorder(LoreColor.brass300.opacity(0.55), lineWidth: 1.5)
            )
    }

    // MARK: Name + kind

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name)
                .font(LoreType.display(size: format == .story ? 46 : 34, weight: .semibold))
                .foregroundStyle(LoreColor.bone)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(place.kind.capitalized)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(LoreColor.amber)
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
                    .padding(.bottom, 14)
                HStack(alignment: .top, spacing: 22) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(fact.label.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.2)
                                .foregroundStyle(LoreColor.bone.opacity(0.5))
                            Text(fact.value)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
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
                    .font(LoreType.display(size: 13, weight: .medium).italic())
                    .foregroundStyle(LoreColor.bone.opacity(0.7))
                Text("Discovered with Lore")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(LoreColor.bone.opacity(0.4))
            }
            Spacer()
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(LoreColor.brass300.opacity(0.8))
        }
    }
}
