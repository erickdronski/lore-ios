import CoreLocation
import SwiftUI
import UserNotifications

/// The first-run flow. A single full-screen cover, presented by the integrator
/// on first launch (gate: `OnboardingStore.shouldPresent`). Four moments plus a
/// send-off, on the brand dusk sky:
///
/// 1. **Arrival** — "Every place has a story." (ELEVATION §5.1)
/// 2. **Interests + persona** — the real curation signal (13 §4.1)
/// 3. **Location** — plain-English why (13 §4.2)
/// 4. **Notifications** — optional nudges (13 §4.3)
/// 5. **Finish** — the send-off, writes `user_prefs` (13 §4)
///
/// Skippable from any step → broad traveler default (13 §4.4). This view owns no
/// navigation of its own; `onFinished` fires exactly once when the flow is done
/// (whether completed or skipped) so the integrator can dismiss it.
struct OnboardingView: View {
    @State var store: OnboardingStore
    /// The injected prefs writer (real one is `OnboardingPrefsWriter`).
    let prefsWriter: PrefsWriting
    /// Called once when the flow completes or is skipped — dismiss here.
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            OnboardingBackground()

            content
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
                .id(store.step)
        }
        .preferredColorScheme(.dark) // the sky is Ink; keep system chrome dark
    }

    @ViewBuilder
    private var content: some View {
        switch store.step {
        case .arrival:
            ArrivalStep(store: store)
        case .interests:
            InterestsStep(store: store)
        case .location:
            LocationStep(store: store)
        case .notifications:
            NotificationsStep(store: store)
        case .finish:
            FinishStep(store: store, onDone: finish)
        }
    }

    private func skip() {
        store.skip(onComplete: onFinished, prefsWriter: prefsWriter)
    }

    private func finish() {
        store.finish(onComplete: onFinished, prefsWriter: prefsWriter)
    }
}

// MARK: - Step 1: Arrival (ELEVATION §5.1)

private struct ArrivalStep: View {
    let store: OnboardingStore
    @State private var appeared = false

    var body: some View {
        OnboardingScaffold(
            progress: store.progress,
            primaryTitle: "Begin",
            onBack: nil,
            onSkip: { store.advance() }, // arrival "skip" just enters — nothing set yet
            onPrimary: { store.advance() }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 40)

                // "Every place has a story." with the final full stop in Amber
                // (the ELEVATION "Chicago." — Amber full stop treatment).
                (
                    Text("Every place has a story")
                        .foregroundColor(LoreColor.bone)
                    + Text(".")
                        .foregroundColor(LoreColor.amber)
                )
                .font(LoreType.display(size: 40, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

                Text(OnboardingContent.arrivalSubhead)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 20)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(LoreMotion.unfurl, value: appeared)
            .onAppear { appeared = true }
        }
    }
}

// MARK: - Step 2: Interests + persona (13 §4.1)

private struct InterestsStep: View {
    @Bindable var store: OnboardingStore

    private var interests: [InterestMap.InterestMeta] {
        InterestMap.allInterests.map { InterestMap.meta(for: $0) }
    }

    var body: some View {
        OnboardingScaffold(
            progress: store.progress,
            primaryTitle: "Continue",
            primaryEnabled: store.canAdvanceInterests,
            onBack: { store.back() },
            onSkip: { store.advance() },
            onPrimary: { store.advance() }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text(OnboardingContent.interestsTitle)
                    .font(LoreType.displayL)
                    .foregroundStyle(LoreColor.bone)

                Text(OnboardingContent.interestsSubtitle)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                // Interest chips wrap across rows.
                WrapLayout(spacing: 8) {
                    ForEach(interests, id: \.slug) { meta in
                        InterestChip(
                            interest: meta,
                            isSelected: store.selectedInterests.contains(meta.slug)
                        ) {
                            store.toggleInterest(meta.slug)
                        }
                    }
                }
                .padding(.top, 4)

                // Preset row — "…or I'm here as a".
                Text(OnboardingContent.personaRowTitle)
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.bone)
                    .padding(.top, 12)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(OnboardingContent.presets) { preset in
                        PersonaChip(
                            preset: preset,
                            isSelected: store.selectedPersona == preset.persona
                        ) {
                            store.applyPreset(preset)
                        }
                    }
                }

                // Show the active persona's tagline as a docent line.
                if let persona = store.selectedPersona,
                   let preset = OnboardingContent.preset(for: persona) {
                    Text("“\(preset.tagline)”")
                        .font(LoreType.hook)
                        .foregroundStyle(LoreColor.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .transition(.opacity)
                }

                if !store.canAdvanceInterests {
                    Text("Pick at least \(OnboardingContent.minInterests) to continue — or Skip for the classic city view.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.6))
                        .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Step 3: Location (13 §4.2)

private struct LocationStep: View {
    let store: OnboardingStore

    /// The bottom CTA reads differently once we know the outcome.
    private var isResolved: Bool {
        store.locationStatus != .notDetermined
    }

    var body: some View {
        OnboardingScaffold(
            progress: store.progress,
            primaryTitle: isResolved ? "Continue" : OnboardingContent.locationAllow,
            primaryBusy: store.isRequestingPermission,
            onBack: { store.back() },
            onSkip: { store.advance() },
            onPrimary: {
                if isResolved {
                    store.advance()
                } else {
                    store.requestLocation()
                }
            }
        ) {
            PermissionCard(
                symbol: "location.fill",
                title: OnboardingContent.locationTitle,
                body: OnboardingContent.locationBody,
                footnote: locationFootnote,
                footnoteColor: footnoteColor
            )
            .padding(.top, 24)

            if isResolved {
                Button(OnboardingContent.locationSkip) { store.advance() }
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .padding(.top, 8)
            }
        }
    }

    private var locationFootnote: String? {
        switch store.locationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Located. The map will center on you."
        case .denied, .restricted:
            return "No problem — the map still works, just without the “around me” view. You can enable location later in Settings."
        default:
            return nil
        }
    }

    private var footnoteColor: Color {
        switch store.locationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return LoreColor.successDark
        case .denied, .restricted: return LoreColor.bone.opacity(0.6)
        default: return LoreColor.bone.opacity(0.6)
        }
    }
}

// MARK: - Step 4: Notifications (13 §4.3, optional)

private struct NotificationsStep: View {
    let store: OnboardingStore

    private var isResolved: Bool {
        store.notificationStatus != .notDetermined
    }

    var body: some View {
        OnboardingScaffold(
            progress: store.progress,
            primaryTitle: isResolved ? "Continue" : OnboardingContent.notificationsAllow,
            primaryBusy: store.isRequestingPermission,
            onBack: { store.back() },
            onSkip: { store.advance() },
            onPrimary: {
                if isResolved {
                    store.advance()
                } else {
                    Task {
                        await store.requestNotifications()
                    }
                }
            }
        ) {
            PermissionCard(
                symbol: "bell.badge.fill",
                title: OnboardingContent.notificationsTitle,
                body: OnboardingContent.notificationsBody,
                footnote: notificationFootnote,
                footnoteColor: footnoteColor
            )
            .padding(.top, 24)

            Button(OnboardingContent.notificationsSkip) { store.advance() }
                .font(LoreType.button)
                .foregroundStyle(LoreColor.bone.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.top, 8)
        }
    }

    private var notificationFootnote: String? {
        switch store.notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "You'll get the occasional great-story nudge."
        case .denied:
            return "All good — Lore stays quiet. Turn nudges on anytime in Settings."
        default:
            return nil
        }
    }

    private var footnoteColor: Color {
        switch store.notificationStatus {
        case .authorized, .provisional, .ephemeral: return LoreColor.successDark
        default: return LoreColor.bone.opacity(0.6)
        }
    }
}

// MARK: - Step 5: Finish

private struct FinishStep: View {
    let store: OnboardingStore
    let onDone: () -> Void
    @State private var appeared = false

    var body: some View {
        OnboardingScaffold(
            progress: 1.0,
            primaryTitle: OnboardingContent.finishCTA,
            primaryBusy: store.isFinishing,
            onBack: { store.back() },
            onSkip: nil,
            onPrimary: onDone
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 40)

                Text("🧭")
                    .font(.system(size: 56))
                    .revealBounce(isActive: appeared)

                Text(OnboardingContent.finishTitle)
                    .font(LoreType.displayXL)
                    .foregroundStyle(LoreColor.bone)

                Text(OnboardingContent.finishBody)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.8))

                // A quiet recap of what the flow captured.
                selectionRecap

                if let error = store.finishError {
                    Text("Saved on this device. We'll sync your prefs when the connection's back. (\(error))")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                Spacer(minLength: 20)
            }
            .onAppear { appeared = true }
        }
    }

    @ViewBuilder
    private var selectionRecap: some View {
        let persona = store.selectedPersona ?? OnboardingContent.skipPersona
        let interests = store.selectedInterests.isEmpty
            ? Set(OnboardingContent.skipInterests)
            : store.selectedInterests

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill.viewfinder")
                    .foregroundStyle(LoreColor.amber)
                Text("Your lens: \(persona.label)")
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone)
            }
            WrapLayout(spacing: 6) {
                ForEach(Array(interests).sorted(), id: \.self) { slug in
                    let meta = InterestMap.meta(for: slug)
                    Text("\(meta.emoji) \(meta.label)")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Capsule().fill(LoreColor.bone.opacity(0.08)))
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Shared permission card

/// The Ink-sky card used by both permission steps: a glyph medallion, a title,
/// the plain-English body, and a reactive footnote after the choice is made.
private struct PermissionCard: View {
    let symbol: String
    let title: String
    let body: String
    let footnote: String?
    var footnoteColor: Color = LoreColor.bone.opacity(0.6)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Circle()
                    .fill(LoreColor.amber.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(LoreColor.amber)
            }

            Text(title)
                .font(LoreType.displayL)
                .foregroundStyle(LoreColor.bone)

            Text(body)
                .font(LoreType.body)
                .foregroundStyle(LoreColor.bone.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            if let footnote {
                Text(footnote)
                    .font(LoreType.caption)
                    .foregroundStyle(footnoteColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LoreColor.bone.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(LoreColor.bone.opacity(0.14), lineWidth: 1)
        )
    }
}
