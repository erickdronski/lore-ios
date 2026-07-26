import SwiftUI

struct TravelPreferencesView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PrefsCoordinator.self) private var coordinator
    @Environment(MapFilterStore.self) private var filters
    @Environment(\.dismiss) private var dismiss

    @State private var persona: UserPrefs.Persona = .traveler
    @State private var interests = Set<String>()
    @State private var loaded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("Your travel lens", selection: personaBinding) {
                    ForEach(UserPrefs.Persona.allCases, id: \.self) { option in
                        Label(option.label, systemImage: option.symbolName)
                            .tag(option)
                    }
                }
                .pickerStyle(.navigationLink)

                Label(persona.tagline, systemImage: persona.symbolName)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)

                Button("Use \(persona.label) recommendations") {
                    interests = Set(persona.defaultInterestIDs)
                }
                .font(LoreType.caption.weight(.semibold))
                .foregroundStyle(LoreColor.brass700)
            } header: {
                Text("Travel lens")
            } footer: {
                Text("Your lens changes what Lore brings forward, never what you are allowed to explore.")
            }

            Section {
                ForEach(UserPrefs.interestCatalog) { option in
                    Button {
                        toggle(option.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.symbolName)
                                .foregroundStyle(interests.contains(option.id) ? LoreColor.brass700 : LoreColor.ink600)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(LoreType.body)
                                    .foregroundStyle(LoreColor.ink)
                                Text(option.detail)
                                    .font(LoreType.caption)
                                    .foregroundStyle(LoreColor.ink600)
                            }
                            Spacer()
                            Image(systemName: interests.contains(option.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(interests.contains(option.id) ? LoreColor.brass700 : LoreColor.ink600)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.label), \(interests.contains(option.id) ? "selected" : "not selected")")
                    .accessibilityHint(option.detail)
                    .accessibilityAddTraits(interests.contains(option.id) ? .isSelected : [])
                }
            } header: {
                Text("Bring forward")
            } footer: {
                Text("Choose at least one. Lore uses these interests to rank nearby stories, scanner results, and recommendations.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.error)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LoreColor.bone100)
        .navigationTitle("Travel preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(isSaving || interests.isEmpty || !loaded)
            }
        }
        .task { loadDraft() }
    }

    private var personaBinding: Binding<UserPrefs.Persona> {
        Binding(
            get: { persona },
            set: { newPersona in
                let wasUsingDefaults = interests.isEmpty || interests == Set(persona.defaultInterestIDs)
                persona = newPersona
                if wasUsingDefaults { interests = Set(newPersona.defaultInterestIDs) }
            }
        )
    }

    private func loadDraft() {
        guard !loaded else { return }
        if let prefs = coordinator.prefs {
            persona = prefs.persona
            interests = Set(prefs.interests)
        } else if let pending = OnboardingPrefsWriter.pendingSelection() {
            persona = pending.persona
            interests = Set(pending.interests)
        } else {
            persona = .traveler
            interests = Set(UserPrefs.Persona.traveler.defaultInterestIDs)
        }
        if interests.isEmpty { interests = Set(persona.defaultInterestIDs) }
        loaded = true
    }

    private func toggle(_ id: String) {
        if interests.contains(id) {
            interests.remove(id)
        } else {
            interests.insert(id)
        }
        Haptics.play(.chipTap)
    }

    @MainActor
    private func save() async {
        guard !isSaving, !interests.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let orderedKnown = UserPrefs.interestCatalog.map(\.id).filter(interests.contains)
        let unknown = interests.subtracting(UserPrefs.knownInterestIDs).sorted()
        let orderedInterests = orderedKnown + unknown
        let hiddenKinds = coordinator.prefs?.hiddenKinds ?? Array(filters.hiddenKinds).sorted()
        let affinity = coordinator.prefs?.affinity

        do {
            if let userID = auth.session?.user.id {
                guard let token = await auth.validAccessToken() else {
                    throw ProfileAccountClient.ClientError.signedOut
                }
                let draft = UserPrefs(
                    userID: userID,
                    persona: persona,
                    interests: orderedInterests,
                    hiddenKinds: hiddenKinds,
                    affinity: affinity,
                    onboarded: true
                )
                let saved = try await LoreAPI.shared.upsertPrefs(draft, accessToken: token)
                coordinator.adopt(saved ?? draft)
            } else {
                let writer = OnboardingPrefsWriter(credentials: { nil })
                try await writer.writeOnboardingPrefs(persona: persona, interests: orderedInterests)
                coordinator.adopt(UserPrefs(
                    userID: "local",
                    persona: persona,
                    interests: orderedInterests,
                    hiddenKinds: hiddenKinds,
                    onboarded: true
                ))
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
