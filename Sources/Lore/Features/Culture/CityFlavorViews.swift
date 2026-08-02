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
    @State private var narration = NarrationService()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(entries) { entry in
                    FlavorCard(entry: entry, accent: accent, narration: narration)
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
    let narration: NarrationService

    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 20
    @State private var completed = false
    @State private var isListening = false
    @State private var secondsRemaining = 30
    @State private var pulse = false

    private var isInteractive: Bool {
        entry.kind == "listen" || entry.kind == "field_note" ||
            entry.primaryExternalAction != nil ||
            (entry.kind == "experience" && entry.placeID != nil)
    }

    private var isPhrase: Bool { entry.kind == "phrase" }
    private var isPhraseSpeaking: Bool {
        narration.isSpeaking && narration.activeSpeechID == entry.id
    }

    private var cardWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 332 : 286
    }

    private var minimumHeight: CGFloat {
        let base = isInteractive ? 282.0 : (isPhrase ? 252.0 : 222.0)
        return dynamicTypeSize.isAccessibilitySize ? base + 126 : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CityFlavorArtwork(entry: entry, accent: accent)

            Text(entry.title)
                .font(LoreType.display(size: titleSize, weight: .semibold))
                .foregroundStyle(LoreColor.bone)
                .fixedSize(horizontal: false, vertical: true)

            if !entry.contextChips.isEmpty {
                chipRow
            }

            if isPhrase {
                phraseTranslation
            } else {
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
            }
            Spacer(minLength: 0)
            action
            if let sourceURL = entry.sourceDisclosureURL {
                Link(destination: sourceURL) {
                    Label("Editorial source", systemImage: "link")
                        .font(LoreType.micro)
                        .foregroundStyle(accent)
                }
                .accessibilityHint("Opens the source for this traveler note")
            }
        }
        .padding(16)
        .frame(width: cardWidth, alignment: .topLeading)
        .frame(minHeight: minimumHeight, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    completed ? LoreColor.ink700 : LoreColor.ink800,
                    LoreColor.ink900,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(completed ? accent : LoreColor.ink700, lineWidth: completed ? 1.5 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if completed {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(pulse && !reduceMotion ? 1.035 : 1)
        .animation(LoreSpring.bounce(reduceMotion: reduceMotion), value: completed)
        .task(id: auth.session?.user.id) {
            completed = CityExperienceProgressStore.isCompleted(
                entryID: entry.id,
                userID: auth.session?.user.id
            )
        }
        .task(id: isListening) {
            guard isListening else { return }
            while secondsRemaining > 0 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard isListening else { return }
                secondsRemaining -= 1
            }
            guard isListening else { return }
            isListening = false
            completeExperience()
        }
        .accessibilityElement(children: isInteractive ? .contain : .combine)
    }

    private var phraseTranslation: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pronunciation = entry.attribution, !pronunciation.isEmpty {
                Label(pronunciation, systemImage: "waveform")
                    .font(LoreType.micro)
                    .foregroundStyle(accent)
            }

            Rectangle()
                .fill(LoreColor.bone.opacity(0.12))
                .frame(height: 1)

            Text("ENGLISH")
                .font(LoreType.micro)
                .tracking(0.8)
                .foregroundStyle(LoreColor.ink600)
            Text(entry.body)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(entry.contextChips, id: \.self) { chip in
                Text(chip)
                    .font(LoreType.micro)
                    .lineLimit(1)
                    .foregroundStyle(LoreColor.bone.opacity(0.82))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(LoreColor.ink700.opacity(0.86), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var action: some View {
        switch entry.kind {
        case "phrase":
            Button {
                if isPhraseSpeaking {
                    narration.stop()
                } else {
                    narration.speakPhrase(
                        entry.spokenPhrase,
                        languageName: entry.meta?.language,
                        id: entry.id
                    )
                }
            } label: {
                Label(
                    isPhraseSpeaking ? "Stop" : "Hear it",
                    systemImage: isPhraseSpeaking ? "stop.fill" : "speaker.wave.2.fill"
                )
                .font(LoreType.button)
                .foregroundStyle(LoreColor.bone)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(LoreColor.ink700, in: Capsule())
            }
            .buttonStyle(.pressable)

        case "listen":
            Button(action: toggleListening) {
                HStack(spacing: 8) {
                    Image(systemName: completed ? "ear.badge.checkmark" : (isListening ? "waveform" : "ear"))
                    Text(listenLabel)
                    Spacer(minLength: 0)
                    if isListening {
                        Text("\(secondsRemaining)s")
                            .monospacedDigit()
                    }
                }
                .font(LoreType.button)
                .foregroundStyle(completed ? LoreColor.ink900 : LoreColor.bone)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(completed ? accent : LoreColor.ink700, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(completed)

        case "field_note":
            Button {
                completeExperience()
            } label: {
                Label(completed ? "Explorer moment captured" : "I tried this", systemImage: completed ? "checkmark" : "sparkles")
                    .font(LoreType.button)
                    .foregroundStyle(completed ? LoreColor.ink900 : LoreColor.bone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(completed ? accent : LoreColor.ink700, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(completed)

        case "watch", "hashtag":
            if let url = entry.primaryExternalURL,
               let action = entry.primaryExternalAction {
                Link(destination: url) {
                    Label(action.label, systemImage: action.systemImage)
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink900)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(accent, in: Capsule())
                }
                .accessibilityHint("Opens an external source curated for this city")
            }

        case "experience":
            if let placeID = entry.placeID {
                Button {
                    Haptics.play(.dossierOpen)
                    router.route(.place(id: placeID, city: entry.city))
                } label: {
                    Label("Open the starting point", systemImage: "location.fill")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.bone)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(LoreColor.ink700, in: Capsule())
                }
                .buttonStyle(.pressable)
            }

        default:
            EmptyView()
        }
    }

    private var listenLabel: String {
        if completed { return "Sound quest complete" }
        return isListening ? "Listening now" : "Start a 30-second sound quest"
    }

    private func toggleListening() {
        if completed { return }
        Haptics.play(.chipTap)
        if isListening {
            isListening = false
            secondsRemaining = 30
        } else {
            secondsRemaining = 30
            isListening = true
        }
    }

    private func completeExperience() {
        guard !completed else { return }
        CityExperienceProgressStore.complete(
            entryID: entry.id,
            userID: auth.session?.user.id
        )
        Haptics.play(.badgeEarned)
        withAnimation(LoreSpring.bounce(reduceMotion: reduceMotion)) {
            completed = true
            pulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(LoreMotion.tap) { pulse = false }
        }
    }
}

// MARK: - Flavor artwork

/// A compact visual index for each flavor kind. The icon answers "what sort of
/// knowledge is this?" before the reader reaches the title; the moving field
/// mark gives sound, route, language, and ritual cards distinct silhouettes.
private struct CityFlavorArtwork: View {
    let entry: CitySection
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false

    private var identity: FlavorVisualIdentity {
        FlavorVisualIdentity(kind: entry.kind, language: entry.meta?.language)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.2), LoreColor.ink900.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            flavorFieldMark
                .opacity(0.44)
                .offset(x: isDrifting && !reduceMotion ? 4 : -3)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LoreColor.ink900.opacity(0.84))
                    Circle()
                        .strokeBorder(accent.opacity(0.78), lineWidth: 1)
                    Image(systemName: identity.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(identity.eyebrow.uppercased())
                        .loreLabelStyle()
                        .foregroundStyle(accent)
                    if let emoji = entry.emoji, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 20))
                    } else {
                        Text(identity.prompt)
                            .font(LoreType.micro)
                            .foregroundStyle(LoreColor.bone.opacity(0.65))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 72)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(0.72))
                .frame(height: 1)
                .padding(.horizontal, 12)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(LoreSpring.slow.repeatForever(autoreverses: true)) {
                isDrifting = true
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var flavorFieldMark: some View {
        switch identity.motif {
        case .wave:
            HStack(alignment: .center, spacing: 4) {
                ForEach([12.0, 28.0, 18.0, 38.0, 22.0, 14.0], id: \.self) { height in
                    Capsule()
                        .fill(accent)
                        .frame(width: 3, height: height)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 18)

        case .route:
            HStack(spacing: 0) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Rectangle().fill(accent).frame(width: 62, height: 1)
                Circle().strokeBorder(accent, lineWidth: 2).frame(width: 12, height: 12)
            }
            .rotationEffect(.degrees(-12))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 14)

        case .rays:
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(accent)
                        .frame(width: 42, height: 2)
                        .offset(x: 20)
                        .rotationEffect(.degrees(Double(index) * 28 - 56))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 22)

        case .grid:
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { column in
                    VStack(spacing: 5) {
                        ForEach(0..<2, id: \.self) { row in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accent.opacity((column + row).isMultiple(of: 2) ? 1 : 0.42))
                                .frame(width: 15, height: 15)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
        }
    }
}

private struct FlavorVisualIdentity {
    enum Motif { case wave, route, rays, grid }

    let symbol: String
    let eyebrow: String
    let prompt: String
    let motif: Motif

    private init(symbol: String, eyebrow: String, prompt: String, motif: Motif) {
        self.symbol = symbol
        self.eyebrow = eyebrow
        self.prompt = prompt
        self.motif = motif
    }

    init(kind: String, language: String?) {
        switch kind {
        case "name_origin":
            self = .init(symbol: "textformat.abc", eyebrow: "Origin", prompt: "Read the name", motif: .rays)
        case "phrase":
            self = .init(symbol: "quote.bubble.fill", eyebrow: language ?? "Local voice", prompt: "Say it aloud", motif: .wave)
        case "watch":
            self = .init(symbol: "play.rectangle.fill", eyebrow: "Watch list", prompt: "See the city", motif: .grid)
        case "hashtag":
            self = .init(symbol: "number", eyebrow: "Search trail", prompt: "Follow the tag", motif: .route)
        case "dish":
            self = .init(symbol: "fork.knife", eyebrow: "Local table", prompt: "Taste the city", motif: .rays)
        case "drink":
            self = .init(symbol: "wineglass.fill", eyebrow: "Local pour", prompt: "Know the order", motif: .rays)
        case "ritual":
            self = .init(symbol: "sparkles", eyebrow: "Ritual", prompt: "Join the rhythm", motif: .rays)
        case "local_legend":
            self = .init(symbol: "book.closed.fill", eyebrow: "Legend", prompt: "Ask around", motif: .rays)
        case "first_timer_mistake":
            self = .init(symbol: "exclamationmark.triangle.fill", eyebrow: "Avoid this", prompt: "Move smarter", motif: .route)
        case "neighborhood_decode":
            self = .init(symbol: "map.fill", eyebrow: "Neighborhood", prompt: "Read the map", motif: .grid)
        case "photo_prompt":
            self = .init(symbol: "camera.viewfinder", eyebrow: "Photo prompt", prompt: "Frame the detail", motif: .route)
        case "seasonal":
            self = .init(symbol: "calendar.badge.clock", eyebrow: "Seasonal", prompt: "Time it right", motif: .rays)
        case "soundmark", "sound":
            self = .init(symbol: "waveform", eyebrow: "Sound field", prompt: "Hear the place", motif: .wave)
        case "material":
            self = .init(symbol: "building.columns.fill", eyebrow: "Material study", prompt: "Read the details", motif: .grid)
        case "screen":
            self = .init(symbol: "film.fill", eyebrow: "On screen", prompt: "Spot the scene", motif: .grid)
        case "etiquette":
            self = .init(symbol: "hand.raised.fill", eyebrow: "Local code", prompt: "Move like a local", motif: .route)
        case "number":
            self = .init(symbol: "number", eyebrow: "Field measure", prompt: "Size it up", motif: .grid)
        case "market":
            self = .init(symbol: "storefront.fill", eyebrow: "Street life", prompt: "Follow the crowd", motif: .grid)
        case "experience":
            self = .init(symbol: "map.fill", eyebrow: "Mini route", prompt: "Start exploring", motif: .route)
        case "listen":
            self = .init(symbol: "ear.fill", eyebrow: "Sound quest", prompt: "Phone down", motif: .wave)
        case "field_note":
            self = .init(symbol: "pencil.and.outline", eyebrow: "Your field note", prompt: "Try it yourself", motif: .route)
        default:
            self = .init(symbol: "sparkles", eyebrow: "City detail", prompt: "Look closer", motif: .rays)
        }
    }
}
