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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var deckHeight: CGFloat {
        if dynamicTypeSize >= .accessibility4 { return 620 }
        if dynamicTypeSize >= .accessibility2 { return 530 }
        if dynamicTypeSize.isAccessibilitySize { return 452 }
        if dynamicTypeSize > .large { return 344 }
        return 318
    }

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
            .frame(height: deckHeight)

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var headlineSize: CGFloat = 21
    @ScaledMetric(relativeTo: .title2) private var calloutSize: CGFloat = 26
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FactFieldMark(fact: fact)

            Text(fact.fact)
                .font(LoreType.display(size: headlineSize, weight: .medium))
                .foregroundStyle(LoreColor.bone)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.76)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 8 : 5)
                .fixedSize(horizontal: false, vertical: true)

            if fact.hasStat {
                statCallout
            } else if let detail = fact.detail, !detail.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.7))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Read the full story") { showDetail = true }
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.amber)
                }
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [LoreColor.ink800, LoreColor.ink900],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LoreColor.ink700, lineWidth: 1)
        )
        .loreElevation(.elev1)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showDetail) {
            FactDetailSheet(fact: fact)
        }
    }

    /// The headline number, set big in the display face, with its label beneath.
    private var statCallout: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(LoreColor.amber)
                .frame(width: 3)
                .clipShape(Capsule())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                CountUpStat(raw: fact.statValue ?? "", reduceMotion: reduceMotion)
                .font(LoreType.display(size: calloutSize, weight: .semibold))
                .foregroundStyle(LoreColor.amber)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                if let label = fact.statLabel, !label.isEmpty {
                    Text(label)
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.brass300)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "ruler.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LoreColor.brass300.opacity(0.72))
                .accessibilityHidden(true)
        }
        .padding(10)
        .background(LoreColor.ink950.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(position), total: Double(max(total, 1)))
                .tint(LoreColor.amber)
                .scaleEffect(y: 0.65)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Text("FIELD NOTE \(position) OF \(total)")
                    .font(LoreType.micro)
                    .tracking(0.5)
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
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.brass300)
                }
                .padding(.leading, 12)
                .accessibilityLabel("Share this fact")
            }
        }
    }

    private var shareText: String {
        ([fact.fact, fact.detail] as [String?])
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n") + "\n\nDiscovered with Lore."
    }

}

private struct FactDetailSheet: View {
    let fact: CityFact
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FactFieldMark(fact: fact)

                    Text(fact.fact)
                        .font(LoreType.display(size: 26, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    if let detail = fact.detail, !detail.isEmpty {
                        Text(detail)
                            .font(LoreType.body)
                            .foregroundStyle(LoreColor.bone.opacity(0.84))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if fact.hasStat {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(fact.statValue ?? "")
                                .font(LoreType.display(size: 30, weight: .bold))
                                .foregroundStyle(LoreColor.amber)
                            Text(fact.statLabel ?? "")
                                .font(LoreType.caption)
                                .foregroundStyle(LoreColor.brass300)
                        }
                    }

                    HStack(spacing: 14) {
                        if let source = fact.sourceURL {
                            Link(destination: source) {
                                Label("Source", systemImage: "link")
                            }
                        }
                        ShareLink(item: shareText) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.amber)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(LoreColor.ink900.ignoresSafeArea())
            .navigationTitle("Field note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var shareText: String {
        ([fact.fact, fact.detail] as [String?])
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n") + "\n\nDiscovered with Lore."
    }
}

/// Category is useful metadata, so the visual treatment encodes it consistently
/// instead of relying on a decorative emoji alone.
private struct FactFieldMark: View {
    let fact: CityFact

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAlive = false

    private var identity: FactVisualIdentity { .init(category: fact.category) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LoreColor.ink950.opacity(0.5))

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LoreColor.brass300.opacity(0.12))
                    Circle()
                        .strokeBorder(LoreColor.brass300.opacity(0.64), lineWidth: 1)
                    Image(systemName: identity.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(LoreColor.brass300)
                        .scaleEffect(isAlive && !reduceMotion ? 1.07 : 0.96)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.category.label.uppercased())
                        .loreLabelStyle()
                        .foregroundStyle(LoreColor.brass300)
                    Text(identity.prompt)
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.bone.opacity(0.58))
                }

                Spacer(minLength: 4)

                categoryMotif

                Text(fact.displayEmoji)
                    .font(.system(size: 26))
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 70)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(LoreSpring.slow.repeatForever(autoreverses: true)) {
                isAlive = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fact.category.label)
    }

    private var categoryMotif: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(identity.bars.indices, id: \.self) { index in
                Capsule()
                    .fill(index == identity.bars.indices.last ? LoreColor.amber : LoreColor.brass300.opacity(0.45))
                    .frame(width: 3, height: identity.bars[index])
            }
        }
        .frame(height: 28, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private struct FactVisualIdentity {
    let symbol: String
    let prompt: String
    let bars: [CGFloat]

    init(category: CityFact.Category) {
        switch category {
        case .superlative:
            self = .init(symbol: "trophy.fill", prompt: "The city at full scale", bars: [8, 13, 19, 27])
        case .first:
            self = .init(symbol: "flag.checkered", prompt: "Where something began", bars: [27, 9, 9, 9])
        case .record:
            self = .init(symbol: "chart.line.uptrend.xyaxis", prompt: "A mark worth measuring", bars: [7, 12, 18, 26])
        case .quirk:
            self = .init(symbol: "sparkle.magnifyingglass", prompt: "Look twice", bars: [10, 24, 13, 20])
        case .etymology:
            self = .init(symbol: "text.book.closed.fill", prompt: "Hidden in the name", bars: [24, 20, 15, 10])
        case .stat:
            self = .init(symbol: "number.square.fill", prompt: "A city in figures", bars: [8, 18, 12, 25])
        case .claimToFame:
            self = .init(symbol: "star.fill", prompt: "Why locals tell the story", bars: [12, 18, 26, 18])
        case .funFact:
            self = .init(symbol: "lightbulb.fill", prompt: "A detail to carry with you", bars: [8, 16, 24, 14])
        }
    }

    private init(symbol: String, prompt: String, bars: [CGFloat]) {
        self.symbol = symbol
        self.prompt = prompt
        self.bars = bars
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var figureSize: CGFloat = 28

    private var identity: FactVisualIdentity { .init(category: fact.category) }
    private var cardWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 238 : 178 }
    private var minimumHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 246 : 178 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LoreColor.brass300.opacity(0.12))
                    Image(systemName: identity.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LoreColor.brass300)
                }
                .frame(width: 30, height: 30)

                Text(fact.category.label.uppercased())
                    .font(LoreType.micro)
                    .tracking(0.5)
                    .foregroundStyle(LoreColor.brass300)
                    .lineLimit(2)

                Spacer(minLength: 0)

                Text(fact.displayEmoji)
                    .font(.system(size: 20))
            }
            .accessibilityHidden(true)

            CountUpStat(raw: fact.statValue ?? "", reduceMotion: reduceMotion)
                .font(LoreType.display(size: figureSize, weight: .semibold))
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

            if let sourceURL = fact.sourceURL {
                Link(destination: sourceURL) {
                    Label("Source", systemImage: "link")
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.brass300)
                }
                .accessibilityLabel("Open the source for this statistic")
            }
        }
        .padding(16)
        .frame(width: cardWidth, alignment: .topLeading)
        .frame(minHeight: minimumHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [LoreColor.ink800, LoreColor.ink900],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LoreColor.ink700, lineWidth: 1)
        )
        .loreElevation(.elev1)
        .accessibilityElement(children: .contain)
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
