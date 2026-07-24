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
            HStack(alignment: .top, spacing: 12) {
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

    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completed = false
    @State private var isListening = false
    @State private var secondsRemaining = 30
    @State private var pulse = false

    private var isInteractive: Bool {
        entry.kind == "listen" || entry.kind == "field_note" ||
            (entry.kind == "experience" && entry.placeID != nil)
    }

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
            action
        }
        .padding(14)
        .frame(width: 280, alignment: .topLeading)
        .frame(minHeight: isInteractive ? 218 : 132)
        .background(
            completed ? LoreColor.ink800 : LoreColor.ink900,
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

    @ViewBuilder
    private var action: some View {
        switch entry.kind {
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
                .frame(height: 40)
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
                    .frame(height: 40)
                    .background(completed ? accent : LoreColor.ink700, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(completed)

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
                        .frame(height: 40)
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
