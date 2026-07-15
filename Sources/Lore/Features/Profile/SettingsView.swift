import StoreKit
import SwiftUI

/// Settings, pushed from Profile (TestFlight feedback #13: "Profile needs
/// preferences, permissions, manage subscription, haptics").
///
/// Scope note: appearance (light/dark) is deliberately **not** a toggle here.
/// Lore pins `.light` because the fixed Ink/Bone/Brass palette isn't yet an
/// adaptive dark theme (system list/nav chrome goes dark while the fixed-Ink
/// text stays dark, the "can't read the tiles" bug). A real dark mode is a
/// separate design-system pass; shipping a toggle now would re-break contrast.
///
/// Pushed inside Profile's `NavigationStack`, so this view carries no stack of
/// its own, just the `List` and its title.
struct SettingsView: View {
    @Environment(StoreKitService.self) private var store
    @Environment(EntitlementStore.self) private var entitlements
    /// The same store the map's filter chips use, so a toggle here persists to
    /// `user_prefs.hidden_kinds` and re-filters the map + nearby lists live.
    @Environment(MapFilterStore.self) private var filters
    @Environment(AuthService.self) private var auth
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dismiss) private var dismiss

    /// Account-deletion confirmation (App Store 5.1.1(v)).
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var deleteFailure: String?

    /// The master haptics switch, read by `Haptics.play` via the same key.
    @AppStorage(Haptics.enabledDefaultsKey) private var hapticsEnabled = true

    #if DEBUG
    /// Debug-only Lore+ override, read by `EntitlementStore.isPlus`.
    @AppStorage("lore.dev.forcePlus") private var devForcePlus = false
    #endif

    @State private var restoring = false
    @State private var restoreNote: String?

    /// Apple's universal manage-subscriptions surface (no app id needed).
    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")

    var body: some View {
        List {
            whatYouSeeSection
            preferencesSection
            languageSection
            permissionsSection
            subscriptionSection
            aboutLegalSection
            if auth.isSignedIn { accountSection }
            #if DEBUG
            developerSection
            #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LoreColor.bone100)
        .navigationTitle(L10n.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            if let manageSubscriptionsURL {
                Button("Manage Apple subscription") {
                    openURL(manageSubscriptionsURL)
                }
            }
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Lore account and private data, including visits, notes, journal photos, badges, and your Lore+ record. Published factual contributions may be retained without account attribution. Deleting your Lore account does not cancel an Apple subscription; manage it separately in your Apple ID subscription settings. This cannot be undone.")
        }
        .alert("Account not deleted", isPresented: Binding(
            get: { deleteFailure != nil },
            set: { if !$0 { deleteFailure = nil } }
        )) {
            Button("Try again") { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteFailure ?? "Please try again.")
        }
    }

    // MARK: Account (App Store 5.1.1(v): in-app account deletion)

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Label("Delete account", systemImage: "trash")
                        .foregroundStyle(LoreColor.error)
                    Spacer()
                    if deleting { ProgressView() }
                }
            }
            .disabled(deleting)
        } header: {
            Text("Account")
        } footer: {
            Text("Deletes your Lore account and private data. Apple subscriptions must be cancelled separately.")
        }
    }

    private func deleteAccount() async {
        guard !deleting else { return }
        deleting = true
        deleteFailure = nil
        let deleted = await auth.deleteAccount()
        deleting = false
        if deleted {
            dismiss() // Session cleared, return to the signed-out profile.
        } else {
            deleteFailure = auth.lastError ?? "Couldn't delete your account. Please try again."
        }
    }

    // MARK: Story translation

    private var languageSection: some View {
        Section {
            if #available(iOS 18.0, *) {
                Picker(selection: Binding(
                    get: { L10n.shared.choice },
                    set: { L10n.shared.choice = $0 }
                )) {
                    Text("Auto (device)").tag("auto")
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                } label: {
                    Label("Story translation", systemImage: "character.bubble")
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.ink)
                }
                .tint(LoreColor.brass700)
            } else {
                Label("Story translation requires iOS 18 or later", systemImage: "character.bubble")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink600)
            }
        } header: {
            Text("Story translation")
        } footer: {
            Text("Long-form stories can translate privately on your device. App controls remain in English for this release; the original English is shown when translation is unavailable.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }

    // MARK: What you see (category preferences → user_prefs.hidden_kinds)

    /// The standard catalog plus any extra kinds the current city surfaced,
    /// de-duplicated in a stable order.
    private var allCategories: [KindCategory] {
        var seen = Set<String>()
        var out: [KindCategory] = []
        for category in KindCategory.catalog + filters.categories {
            if seen.insert(category.kind).inserted { out.append(category) }
        }
        return out
    }

    /// Founder steer: let users control what they see so the map isn't
    /// information overload. Onboarding sets these; this is where they change
    /// them anytime. Toggling a category off hides that kind of place on the
    /// map and in nearby lists (persists to `user_prefs.hidden_kinds`).
    private var whatYouSeeSection: some View {
        Section {
            ForEach(allCategories) { category in
                Toggle(isOn: Binding(
                    get: { filters.isOn(category) },
                    set: { newOn in
                        if newOn != filters.isOn(category) { filters.toggle(category) }
                    }
                )) {
                    Label {
                        Text(category.label)
                            .font(LoreType.body)
                            .foregroundStyle(LoreColor.ink)
                    } icon: {
                        Text(category.emoji)
                    }
                }
                .tint(LoreColor.brass700)
            }

            if filters.hasActiveFilter {
                Button {
                    filters.clear()
                } label: {
                    Label("Show everything", systemImage: "eye")
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.brass700)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("What you see")
        } footer: {
            Text("Turn off the kinds of places you're not interested in. Hidden ones won't clutter your map or nearby lists. You picked these in onboarding; change them here anytime.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }

    // MARK: Preferences

    private var preferencesSection: some View {
        Section("Preferences") {
            Toggle(isOn: $hapticsEnabled) {
                Label("Haptic feedback", systemImage: "hand.tap")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
            }
            .tint(LoreColor.brass700)
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        Section {
            permissionRow("Location", icon: "location.fill")
            permissionRow("Camera", icon: "camera.fill")
        } header: {
            Text("Permissions")
        } footer: {
            Text("Opens the iOS Settings app, where Lore's location and camera access live.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }

    private func permissionRow(_ label: String, icon: String) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            settingsRow(label, icon: icon, tint: LoreColor.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: Subscription

    private var subscriptionSection: some View {
        Section("Lore+") {
            if entitlements.isPlus, let url = manageSubscriptionsURL {
                Button {
                    openURL(url)
                } label: {
                    settingsRow("Manage subscription", icon: "creditcard.fill", tint: LoreColor.brass700)
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await restorePurchases() }
            } label: {
                HStack {
                    Label("Restore purchases", systemImage: "arrow.clockwise")
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.ink)
                    Spacer()
                    if restoring {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(restoring)

            if let restoreNote {
                Text(restoreNote)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
        }
    }

    private func restorePurchases() async {
        restoring = true
        restoreNote = nil
        let outcome = await store.restore()
        restoring = false
        switch outcome {
        case .restored:
            restoreNote = "Purchases restored."
        case .nothingToRestore:
            restoreNote = "Nothing to restore on this Apple ID."
        case .userCancelled:
            break
        case .failed(let message):
            restoreNote = message
        }
    }

    // MARK: About + legal

    /// Policies, support, a rate prompt, and the data attribution the licenses
    /// require (OpenStreetMap ODbL + Wikipedia CC BY-SA). The links open the
    /// live lore-web legal pages, the same ones the paywall points to.
    private var aboutLegalSection: some View {
        Section {
            linkRow("Terms of Use", icon: "doc.text", urlString: "https://lore-web-liart.vercel.app/terms")
            linkRow("Privacy Policy", icon: "hand.raised", urlString: "https://lore-web-liart.vercel.app/privacy")
            linkRow("Support", icon: "questionmark.circle", urlString: "https://lore-web-liart.vercel.app/support")
            Button {
                requestReview()
            } label: {
                settingsRow("Rate Lore", icon: "star", tint: LoreColor.ink)
            }
            .buttonStyle(.plain)
        } header: {
            Text("About Lore")
        } footer: {
            Text("Place data © OpenStreetMap contributors (ODbL). Stories draw on Wikipedia (CC BY-SA) and public-domain sources; map and imagery via Apple Maps. © 2026 Lore.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }

    private func linkRow(_ label: String, icon: String, urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) { openURL(url) }
        } label: {
            settingsRow(label, icon: icon, tint: LoreColor.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: Developer (DEBUG only)

    #if DEBUG
    private var developerSection: some View {
        Section {
            Toggle(isOn: $devForcePlus) {
                Label("Force Lore+ (dev)", systemImage: "hammer")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
            }
            .tint(LoreColor.brass700)
        } header: {
            Text("Developer")
        } footer: {
            Text("Debug builds only. Unlocks every Lore+ surface for testing without a purchase (re-enter a screen to see it apply).")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }
    #endif

    // MARK: Row

    private func settingsRow(_ label: String, icon: String, tint: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(LoreType.body)
                .foregroundStyle(tint)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LoreColor.ink600)
        }
    }
}
