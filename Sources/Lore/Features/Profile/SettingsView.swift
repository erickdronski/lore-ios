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
    @Environment(\.openURL) private var openURL

    /// The master haptics switch, read by `Haptics.play` via the same key.
    @AppStorage(Haptics.enabledDefaultsKey) private var hapticsEnabled = true

    @State private var restoring = false
    @State private var restoreNote: String?

    /// Apple's universal manage-subscriptions surface (no app id needed).
    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")

    var body: some View {
        List {
            preferencesSection
            permissionsSection
            subscriptionSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LoreColor.bone100)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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
