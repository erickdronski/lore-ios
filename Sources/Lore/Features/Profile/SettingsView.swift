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
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

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
            #if DEBUG
            developerSection
            #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LoreColor.bone100)
        .navigationTitle(L10n.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Language (scanner-lab port: nine interface languages + Auto)

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(
                get: { L10n.shared.choice },
                set: { L10n.shared.choice = $0 }
            )) {
                Text(L10n.t("settings.languageAuto")).tag("auto")
                ForEach(AppLanguage.allCases) { language in
                    Text(language.label).tag(language.rawValue)
                }
            } label: {
                Label(L10n.t("settings.language"), systemImage: "globe")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
            }
            .tint(LoreColor.brass700)
        } header: {
            Text(L10n.t("settings.language"))
        } footer: {
            Text(L10n.t("settings.languageNote"))
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
            permissionRow("Notifications", icon: "bell.fill")
        } header: {
            Text("Permissions")
        } footer: {
            Text("Opens the iOS Settings app, where Lore's location, camera, and notification access live.")
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
        let ok = await store.restore()
        restoring = false
        restoreNote = ok
            ? "Purchases restored."
            : "Nothing to restore on this Apple ID."
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
