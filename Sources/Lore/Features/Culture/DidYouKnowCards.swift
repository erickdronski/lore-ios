import SwiftUI

// MARK: - Did You Know deck

/// A swipeable deck of the city's most surprising facts (the `city_fact` "Did
/// You Know" pillar). One arresting fact per card — a category chip, a big emoji,
/// the punchy line, an optional stat callout + expansion, and a source link —
/// paged horizontally like the quote card so it reads as a stack of cards you
/// flick through. Fixed height keeps every card uniform; long facts scale to fit.
///
/// This is the "wait, really?" surface: hometown pride, one brag at a time.
/// Ink-family tiles, grain-free, Reveal motion. A soft haptic marks each page so
/// the flick feels tactile (brand/ELEVATION.md §5b, LUXURY-MOTION §6).
struct DidYouKnowDeck: View {
    let facts: [CityFact]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $index) {
                ForEach(Array(facts.enumerated()), id: \.element.id) { i, fact in
                    DidYouKnowCard(fact: fact, position: i + 1, total: facts.count)
                        .padding(.horizontal, 2)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 268)

            if facts.count > 1 {
                dots
            }
        }
        .onChange(of: index) { _, _ in
            Haptics.play(.chipTap)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(facts.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? LoreColor.amber : LoreColor.ink600)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }
}

/// One "Did You Know" fact card face inside the deck.
struct DidYouKnowCard: View {
    let fact: CityFact
    let position: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                categoryChip
                Spacer(minLength: 8)
                Text(fact.displayEmoji)
                    .font(.system(size: 34))
                    .accessibilityHidden(true)
            }

            Text(fact.fact)
                .font(LoreType.display(size: 21, weight: .medium))
                .foregroundStyle(LoreColor.bone)
                .minimumScaleFactor(0.65)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)

            if fact.hasStat {
                statCallout
            } else if let detail = fact.detail, !detail.isEmpty {
                Text(detail)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.7))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LoreColor.ink800)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LoreColor.ink700, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var categoryChip: some View {
        Text(fact.category.label.uppercased())
            .loreLabelStyle()
            .foregroundStyle(LoreColor.brass300)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(LoreColor.ink900.opacity(0.6))
            )
            .overlay(
                Capsule().strokeBorder(LoreColor.ink700, lineWidth: 1)
            )
    }

    /// The headline number, set big in the display face, with its label beneath.
    private var statCallout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(fact.statValue ?? "")
                .font(LoreType.display(size: 26, weight: .semibold))
                .foregroundStyle(LoreColor.amber)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let label = fact.statLabel, !label.isEmpty {
                Text(label)
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.brass300)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Text("\(position) / \(total)")
                .font(LoreType.micro)
                .foregroundStyle(LoreColor.ink600)
                .monospacedDigit()
            Spacer()
            if let url = fact.sourceURL {
                Link(destination: url) {
                    Label("Source", systemImage: "link")
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.brass300)
                }
                .accessibilityLabel("Open the source for this fact")
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [fact.category.label, fact.fact]
        if fact.hasStat {
            let stat = [fact.statValue, fact.statLabel].compactMap { $0 }.joined(separator: " ")
            if !stat.isEmpty { parts.append(stat) }
        } else if let detail = fact.detail {
            parts.append(detail)
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - By the Numbers strip

/// A horizontal strip of the city's headline stats — each fact that carries a
/// number becomes a card whose figure counts up on appear (Strava/Peloton
/// energy, but for a place). Glanceable by design: the deck is where you read,
/// this is where the numbers land.
struct ByTheNumbersStrip: View {
    let stats: [CityFact]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(stats) { stat in
                    StatCard(fact: stat)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

/// One stat card: emoji, the big count-up figure, and its label.
struct StatCard: View {
    let fact: CityFact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fact.displayEmoji)
                .font(.system(size: 26))
                .accessibilityHidden(true)

            CountUpStat(raw: fact.statValue ?? "", reduceMotion: reduceMotion)
                .font(LoreType.display(size: 28, weight: .semibold))
                .foregroundStyle(LoreColor.amber)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if let label = fact.statLabel, !label.isEmpty {
                Text(label)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.75))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 158, height: 148, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LoreColor.ink800)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LoreColor.ink700, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [fact.statValue, fact.statLabel].compactMap { $0 }.joined(separator: " ")
        )
    }
}

// MARK: - Count-up number

/// Renders a stat string with its leading number animating up from zero on
/// appear. Prefix (`$`, `€`, `~`) and suffix (` miles`, `M`, ` ft`) stay put;
/// only the figure counts. Falls back to the raw string, static, when the value
/// isn't a single clean number (ranges like "1889-1930", lists, "Track 61").
/// Under Reduce Motion the final value shows immediately.
struct CountUpStat: View {
    let raw: String
    let reduceMotion: Bool

    @State private var shown: Double = 0

    private var parsed: ParsedStat? { ParsedStat(raw) }

    var body: some View {
        Group {
            if let parsed {
                AnimatableNumberText(value: shown) { parsed.render($0) }
                    .onAppear {
                        guard shown == 0 else { return }
                        if reduceMotion {
                            shown = parsed.number
                        } else {
                            withAnimation(.easeOut(duration: 0.9)) { shown = parsed.number }
                        }
                    }
            } else {
                Text(raw)
            }
        }
    }
}

/// A `Text` whose numeric input is interpolated by SwiftUI during animation
/// (the classic count-up: `Animatable` drives `animatableData`, `body` re-renders
/// the formatted figure each frame).
private struct AnimatableNumberText: View, Animatable {
    var value: Double
    let render: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(render(value))
    }
}

/// A stat string decomposed into a static prefix, an animatable number (with a
/// fixed number of decimals), and a static suffix.
private struct ParsedStat {
    let prefix: String
    let number: Double
    let decimals: Int
    let suffix: String
    private let formatter: NumberFormatter

    /// Parses the first numeric run in `raw`. Returns nil (→ render static) when
    /// there is no number, or when a second digit appears after the run (a range
    /// or list like "1932, 1984" / "1889-1930"), which shouldn't count up.
    init?(_ raw: String) {
        let scalars = Array(raw)
        guard let start = scalars.firstIndex(where: { $0.isNumber }) else { return nil }

        var end = start
        var digits = ""
        var decimals = 0
        var seenDot = false
        var hadComma = false
        while end < scalars.count {
            let c = scalars[end]
            if c.isNumber {
                digits.append(c)
                if seenDot { decimals += 1 }
                end += 1
            } else if c == "," {
                // Thousands separator only when a digit follows; else stop.
                if end + 1 < scalars.count, scalars[end + 1].isNumber {
                    hadComma = true
                    end += 1
                } else { break }
            } else if c == ".", !seenDot,
                      end + 1 < scalars.count, scalars[end + 1].isNumber {
                seenDot = true
                digits.append(".")
                end += 1
            } else {
                break
            }
        }

        guard let value = Double(digits) else { return nil }

        let prefix = String(scalars[..<start])
        let suffix = String(scalars[end...])
        // A digit in the suffix means this was a range/list, not one figure.
        if suffix.contains(where: { $0.isNumber }) { return nil }

        let f = NumberFormatter()
        f.numberStyle = .decimal
        // Only group when the source string did — so quantities like "1,900"
        // keep their comma while years like "1920" stay bare.
        f.usesGroupingSeparator = hadComma
        f.groupingSeparator = ","
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals

        self.prefix = prefix
        self.number = value
        self.decimals = decimals
        self.suffix = suffix
        self.formatter = f
    }

    func render(_ current: Double) -> String {
        let n = formatter.string(from: NSNumber(value: current)) ?? "\(current)"
        return prefix + n + suffix
    }
}
