import SwiftUI
import UIKit

// MARK: - Rotating quote

/// A single famous quote about the city, set large in the display (Fraunces-
/// ready) face, that gently rotates through the city's `quote` rows. Tapping it
/// (or waiting ~9s) reveals the next one with a `reveal.unfurl` crossfade.
///
/// This is the emotional top of the "Meet {City}" surface: one arresting line
/// in the world's words, its author in the app's words beneath. Under Reduce
/// Motion the auto-rotation still advances (information isn't removed), the
/// transition just becomes the standard 160 ms crossfade via `LoreMotion`.
struct CultureQuoteCard: View {
    let quotes: [CityCulture]
    @State private var index = 0
    @State private var autoAdvance = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var quoteSize: CGFloat = 24

    /// ~9s per quote, long enough to read a sentence, short enough to feel
    /// alive. One sanctioned ambient beat, not decoration for its own sake.
    private let rotation = Timer.publish(every: 9, on: .main, in: .common).autoconnect()

    private var cardHeight: CGFloat {
        if dynamicTypeSize >= .accessibility4 { return 610 }
        if dynamicTypeSize >= .accessibility2 { return 500 }
        if dynamicTypeSize.isAccessibilitySize { return 420 }
        if dynamicTypeSize > .large { return 288 }
        return 246
    }

    var body: some View {
        VStack(spacing: 12) {
            // A swipeable pager (TestFlight feedback: "these quote tiles are
            // still not scrollable"). Fixed height keeps every card uniform;
            // long quotes scale to fit rather than clipping.
            TabView(selection: $index) {
                ForEach(Array(quotes.enumerated()), id: \.element.id) { i, quote in
                    quoteFace(quote)
                        .padding(.horizontal, 2)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: cardHeight)

            if quotes.count > 1 {
                quoteDots
            }
        }
        .onReceive(rotation) { _ in
            guard autoAdvance, !voiceOverEnabled, quotes.count > 1 else { return }
            advance()
        }
    }

    /// One quote card face inside the pager.
    private func quoteFace(_ quote: CityCulture) -> some View {
        ZStack {
            QuoteFieldArtwork()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(LoreColor.amber)
                    Text("A VOICE OF \(quote.city.replacingOccurrences(of: "-", with: " ").uppercased())")
                        .font(LoreType.micro)
                        .tracking(0.65)
                        .foregroundStyle(LoreColor.brass300)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let year = quote.year {
                        Text(String(year))
                            .font(LoreType.micro)
                            .foregroundStyle(LoreColor.bone.opacity(0.6))
                            .monospacedDigit()
                    }
                }

                Text(quote.headline)
                    .font(LoreType.display(size: quoteSize, weight: .medium))
                    .foregroundStyle(LoreColor.bone)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 8 : 5)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                authorSignature(for: quote)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        .loreElevation(.elev1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: quote))
    }

    @ViewBuilder
    private func authorSignature(for quote: CityCulture) -> some View {
        let attribution = quote.attribution ?? quote.body

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                QuoteAuthorPortrait(quote: quote)
                if let attribution {
                    attributionText(attribution)
                }
            }
        } else {
            HStack(alignment: .bottom, spacing: 12) {
                if let attribution {
                    attributionText(attribution)
                }
                Spacer(minLength: 0)
                QuoteAuthorPortrait(quote: quote)
            }
        }
    }

    private func attributionText(_ attribution: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("IN THEIR WORDS")
                .font(LoreType.micro)
                .tracking(0.55)
                .foregroundStyle(LoreColor.bone.opacity(0.46))
            Text(attribution)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.brass300)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quoteDots: some View {
        HStack(spacing: 6) {
            ForEach(quotes.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? LoreColor.amber : LoreColor.ink600)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private func accessibilityLabel(for quote: CityCulture) -> String {
        let attribution = quote.attribution.map { ", \($0)" } ?? ""
        return "\(quote.headline)\(attribution)"
    }

    /// Auto-advance to the next quote (the ambient beat); manual paging is the
    /// user's swipe on the pager.
    private func advance() {
        guard quotes.count > 1 else { return }
        withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) {
            index = (index + 1) % quotes.count
        }
    }
}

/// A quiet editorial field behind the quote: quotation marks and measured lines
/// make the card read like a collected voice rather than an undifferentiated
/// block of copy. Its drift is subtle and completely absent under Reduce Motion.
private struct QuoteFieldArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Text("\u{201C}")
                    .font(LoreType.display(size: min(proxy.size.width * 0.46, 150), weight: .semibold))
                    .foregroundStyle(LoreColor.brass300.opacity(0.055))
                    .offset(x: isDrifting && !reduceMotion ? 5 : 0, y: -34)

                VStack(alignment: .trailing, spacing: 7) {
                    ForEach([0.48, 0.34, 0.21], id: \.self) { fraction in
                        Capsule()
                            .fill(LoreColor.brass300.opacity(0.09))
                            .frame(width: proxy.size.width * fraction, height: 1)
                    }
                }
                .padding(.top, 64)
                .padding(.trailing, 6)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(LoreSpring.slow.repeatForever(autoreverses: true)) {
                isDrifting = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// A compact portrait signature for a quote. Named speakers resolve through
/// the same Wikipedia image path as Famous Faces; the curated emoji remains a
/// useful offline and non-person fallback.
private struct QuoteAuthorPortrait: View {
    let quote: CityCulture
    @State private var portraitURL: URL?
    @State private var didResolve = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var diameter: CGFloat { dynamicTypeSize.isAccessibilitySize ? 74 : 60 }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(LoreColor.brass300.opacity(0.2), lineWidth: 1)
                .padding(-6)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [LoreColor.ink700, LoreColor.ink900],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                        Text(quote.displayEmoji)
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 28 : 23))
                )

            if let portraitURL {
                AsyncImage(
                    url: portraitURL,
                    transaction: Transaction(animation: LoreMotion.bloom)
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .empty, .failure:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(
            Circle()
                .strokeBorder(LoreColor.brass300, lineWidth: 1.5)
        )
        .loreElevation(.elev1)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: portraitURL == nil ? "person.fill" : "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(LoreColor.ink900)
                .frame(width: 18, height: 18)
                .background(LoreColor.amber, in: Circle())
                .overlay(Circle().strokeBorder(LoreColor.ink900, lineWidth: 2))
                .accessibilityHidden(true)
        }
        .task(id: portraitTitle) {
            guard !didResolve else { return }
            didResolve = true
            guard let portraitTitle else {
                portraitURL = nil
                return
            }
            portraitURL = await WikipediaService.shared.portraitURL(for: portraitTitle)
        }
        .accessibilityHidden(true)
    }

    private var portraitTitle: String? {
        if let title = quote.wikipediaTitle { return title }
        guard let attribution = quote.attribution?.trimmingCharacters(in: .whitespacesAndNewlines),
              !attribution.isEmpty else { return nil }

        // Most curated attributions are "Name, role/context". A few use
        // "Name in Work"; both reduce cleanly to Wikipedia's article title.
        let beforeContext = attribution.split(separator: ",", maxSplits: 1).first.map(String.init)
            ?? attribution
        let lowercased = beforeContext.lowercased()
        if let range = lowercased.range(of: " in ") {
            return String(beforeContext[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return beforeContext.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Famous faces

/// A horizontal shelf of the city's notable people, each a circular portrait
/// (loaded async from Wikipedia) over its name. Compact by doctrine: media is
/// horizontal, never a vertical wall (brand/ELEVATION.md §5b).
struct FamousFacesRow: View {
    let people: [CityCulture]
    /// Called when a face is tapped, so the parent can present a bio detail.
    var onSelect: (CityCulture) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(people) { person in
                    Button {
                        Haptics.play(.chipTap)
                        onSelect(person)
                    } label: {
                        FamousFaceView(person: person)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

/// One famous face: a circular Wikipedia portrait (async, with an emoji
/// medallion placeholder while it loads or if there's no photo) and the
/// person's name beneath.
struct FamousFaceView: View {
    let person: CityCulture
    @State private var portraitURL: URL?
    @State private var didResolve = false

    private let diameter: CGFloat = 76

    var body: some View {
        VStack(spacing: 8) {
            portrait
            Text(person.headline)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone)
                .lineLimit(1)
                .frame(width: diameter + 12)
                .minimumScaleFactor(0.85)
        }
        .task { await resolvePortrait() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(person.headline)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var portrait: some View {
        ZStack {
            // Placeholder medallion, always drawn; the photo fades in over it.
            Circle()
                .fill(LoreColor.ink800)
                .overlay(
                    Text(person.displayEmoji)
                        .font(.system(size: 30))
                )
                .overlay(
                    Circle().strokeBorder(LoreColor.brass300.opacity(0.5), lineWidth: 1.5)
                )

            if let url = portraitURL {
                AsyncImage(url: url, transaction: Transaction(animation: LoreMotion.bloom)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .empty, .failure:
                        // Keep the medallion; nothing to overlay.
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(LoreColor.brass300, lineWidth: 1.5)
                )
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func resolvePortrait() async {
        guard !didResolve else { return }
        didResolve = true
        guard let title = person.wikipediaTitle else { return }
        let url = await WikipediaService.shared.portraitURL(for: title)
        // Back on the main actor (task inherits it from the SwiftUI view).
        portraitURL = url
    }
}

// MARK: - Local lingo flip card

/// A local-slang flip card built on the foundation `FlipCard`: the front is the
/// word (big, in the display face); tap to flip to its meaning + example on the
/// back. Grouped under "Local Lingo" on the culture surface.
///
/// Front and back are the same Ink-800 tile so the flip reads as one object
/// turning over. The back's copy is the row's `body` (definition, then the
/// "used in a sentence" example the seed writes inline).
struct LingoFlipCard: View {
    let entry: CityCulture
    /// Long-press opens the full definition (TestFlight feedback: "more text
    /// here I can't click into or read further"). The compact card caps the
    /// back at a few lines; this reads the whole entry.
    @State private var showExpanded = false

    var body: some View {
        StatefulFlipCard {
            face(alignment: .center) {
                VStack(spacing: 8) {
                    Text(entry.displayEmoji)
                        .font(.system(size: 30))
                    Text(entry.headline)
                        .font(LoreType.display(size: 22, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                    Text("tap to flip")
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.bone.opacity(0.52))
                }
            }
        } back: {
            face(alignment: .leading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.headline)
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.amber)
                    if let body = entry.body {
                        // A teaser that always clears the "More" chip in the
                        // bottom corner; the full meaning lives in the sheet.
                        Text(body)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.bone)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(4)
                    }
                }
            }
        }
        .frame(width: 180, height: 150)
        // An unmistakable "More" chip (long-press also works) so it's obvious
        // the full entry is a tap away, the old expand glyph read as decoration
        // (owner: "when I flip these I can't read all the text"). It sits above
        // the flip so tapping it opens the detail instead of flipping the card.
        .overlay(alignment: .bottomTrailing) {
            Button {
                Haptics.play(.chipTap)
                showExpanded = true
            } label: {
                HStack(spacing: 3) {
                    Text("More")
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                }
                .font(LoreType.micro)
                .foregroundStyle(LoreColor.ink900)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(LoreColor.amber, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Read the full meaning")
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            Haptics.play(.chipTap)
            showExpanded = true
        }
        .sheet(isPresented: $showExpanded) {
            LingoDetailSheet(entry: entry)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to flip. Touch and hold to read the full meaning.")
    }

    /// The shared tile chrome for both faces so the flip looks like one card.
    private func face<Content: View>(
        alignment: Alignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(width: 180, height: 150, alignment: alignment)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LoreColor.ink800)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(LoreColor.ink700, lineWidth: 1)
            )
    }

    private var accessibilityLabel: String {
        if let body = entry.body {
            return "\(entry.headline). \(body)"
        }
        return entry.headline
    }
}

// MARK: - Lingo detail sheet

/// The full read of a lingo / saying entry, opened by a long-press on its flip
/// card: the word big in the display face, then the complete meaning + example
/// with no line cap. Ink surface, matching `PersonBioSheet`.
struct LingoDetailSheet: View {
    let entry: CityCulture
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Text(entry.displayEmoji)
                        .font(.system(size: 44))
                    Text(entry.headline)
                        .font(LoreType.display(size: 26, weight: .semibold))
                        .foregroundStyle(LoreColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 24)

                if let body = entry.body {
                    Text(body)
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.bone)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
        }
        .background(LoreColor.ink900.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(entry.body.map { "\(entry.headline). \($0)" } ?? entry.headline))
    }
}

// MARK: - Section header

/// A culture-surface section header: an eyebrow label (tracked, Brass) over a
/// display-face title. Used above each register (Quotes, People, Lingo).
struct CultureSectionHeader: View {
    let eyebrow: String
    let title: String
    /// City-theme accent for the eyebrow; nil keeps the house brass.
    var accent: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .loreLabelStyle()
                .foregroundStyle(accent ?? LoreColor.brass300)
            Text(title)
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}
