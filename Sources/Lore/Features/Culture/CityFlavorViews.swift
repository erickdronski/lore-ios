import SwiftUI

/// The city-theme header wash: a tall, quiet gradient in the city's signature
/// tinted inks, dissolving into the page background. Sits BEHIND the "Meet
/// {City}" header so the page reads as "this city's room" the moment it loads,
/// without ever competing with content — both stops are clamped into the
/// dark-ink family by `CityTheme`, so bone text always keeps its contrast.
struct CityThemeWash: View {
    let theme: CityTheme?

    var body: some View {
        if let theme {
            LinearGradient(
                stops: [
                    .init(color: theme.gradientTopColor, location: 0),
                    .init(color: theme.gradientBottomColor, location: 0.55),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 340)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }
}

/// One horizontal shelf of flavor cards for a single section kind ("dish",
/// "etiquette", …). Cards keep the DidYouKnow deck's editorial voice: emoji
/// glyph, serif title, two-line body, quiet attribution. The city accent
/// appears exactly twice — the header eyebrow (set by the caller) and a
/// hairline top rule on each card — flavor, not paint.
struct CityFlavorShelf: View {
    let entries: [CitySection]
    let accent: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(entries) { entry in
                    FlavorCard(entry: entry, accent: accent)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }
}

private struct FlavorCard: View {
    let entry: CitySection
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(accent.opacity(0.85))
                .frame(width: 28, height: 2)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let emoji = entry.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: 20))
                }
                Text(entry.title)
                    .font(LoreType.display(size: 19, weight: .semibold))
                    .foregroundStyle(LoreColor.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(entry.body)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.78))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let attribution = entry.attribution, !attribution.isEmpty {
                Text(attribution)
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.ink600)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 280, alignment: .topLeading)
        .frame(minHeight: 132)
        .background(LoreColor.ink900, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LoreColor.ink700, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
