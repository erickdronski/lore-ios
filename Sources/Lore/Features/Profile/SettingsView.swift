import AVFoundation
import CoreLocation
import StoreKit
import SwiftUI
import UserNotifications

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
    @Environment(PushService.self) private var push
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showDeleteFlow = false
    @State private var locationStatus: CLAuthorizationStatus = .notDetermined
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    @State private var requestingPermission: PermissionKind?
    @State private var locationManager = CLLocationManager()

    /// The master haptics switch, read by `Haptics.play` via the same key.
    @AppStorage(Haptics.enabledDefaultsKey) private var hapticsEnabled = true

    #if DEBUG
    /// Debug-only Lore+ override, read by `EntitlementStore.isPlus`.
    @AppStorage("lore.dev.forcePlus") private var devForcePlus = false
    #endif

    @State private var restoring = false
    @State private var restoreNote: String?

    var body: some View {
        List {
            whatYouSeeSection
            preferencesSection
            languageSection
            if Config.offlineCityPacksEnabled {
                OfflinePacksSection()
            }
            permissionsSection
            subscriptionSection
            privacyDataSection
            aboutLegalSection
            if auth.isSignedIn { accountSection }
            #if DEBUG
            developerSection
            #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LoreColor.bone100)
        .contentMargins(.horizontal, horizontalSizeClass == .regular ? 80 : 0, for: .scrollContent)
        .navigationTitle(L10n.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showDeleteFlow) {
            DeleteAccountView {
                showDeleteFlow = false
                dismiss()
            }
            .presentationDetents([.large])
        }
        .task { await refreshPermissionStatuses() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshPermissionStatuses() }
        }
    }

    // MARK: Account (App Store 5.1.1(v): in-app account deletion)

    private var accountSection: some View {
        Section {
            if let email = auth.session?.user.email {
                LabeledContent("Signed in as") {
                    Text(email)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                        .multilineTextAlignment(.trailing)
                }
                .font(LoreType.body)
                .accessibilityElement(children: .combine)
            }

            Button(role: .destructive) {
                showDeleteFlow = true
            } label: {
                settingsRow("Delete account", icon: "trash", tint: LoreColor.error)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Deletion requires a typed confirmation and a freshly verified secure session. Apple subscriptions must be cancelled separately.")
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

            if let error = filters.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.error)
                    .accessibilityLabel("Preference save error. \(error)")
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
        Section {
            NavigationLink {
                TravelPreferencesView()
            } label: {
                Label("Travel preferences", systemImage: "slider.horizontal.3")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
            }

            Toggle(isOn: $hapticsEnabled) {
                Label("Haptic feedback", systemImage: "hand.tap")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
            }
            .tint(LoreColor.brass700)
        } header: {
            Text("Preferences")
        } footer: {
            Text("Your travel lens and interests shape ranking across the map, scanner, and nearby stories. Haptics are stored on this device.")
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        Section {
            if Config.pushNotificationsEnabled {
                permissionRow(
                    "Notifications",
                    icon: "bell.badge.fill",
                    status: notificationStatusLabel,
                    isEnabled: push.isAuthorized,
                    kind: .notifications
                )
            }

            permissionRow(
                "Location",
                icon: "location.fill",
                status: locationStatusLabel,
                isEnabled: locationIsAuthorized,
                kind: .location
            )
            permissionRow(
                "Camera",
                icon: "camera.fill",
                status: cameraStatusLabel,
                isEnabled: cameraStatus == .authorized,
                kind: .camera
            )

            Button {
                openSystemSettings()
            } label: {
                settingsRow("Open all iOS permissions", icon: "gearshape.fill", tint: LoreColor.ink)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Permissions")
        } footer: {
            Text("Permissions are optional. The map works without Camera, and city browsing works without Location. Lore does not store a continuous camera feed or location history.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }

    private func permissionRow(
        _ label: String,
        icon: String,
        status: String,
        isEnabled: Bool,
        kind: PermissionKind
    ) -> some View {
        Button {
            Task { await handlePermission(kind) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(isEnabled ? LoreColor.brass700 : LoreColor.ink600)
                    .frame(width: 24)
                Text(label)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
                Spacer()
                if requestingPermission == kind {
                    ProgressView()
                } else {
                    Text(status)
                        .font(LoreType.caption.weight(.semibold))
                        .foregroundStyle(isEnabled ? LoreColor.brass700 : LoreColor.ink600)
                    Image(systemName: kind.isUndetermined(
                        notification: push.authorizationStatus,
                        location: locationStatus,
                        camera: cameraStatus
                    ) ? "chevron.right" : "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LoreColor.ink600)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(requestingPermission != nil)
        .accessibilityLabel("\(label), \(status)")
        .accessibilityHint(kind.isUndetermined(
            notification: push.authorizationStatus,
            location: locationStatus,
            camera: cameraStatus
        ) ? "Requests permission" : "Opens iOS Settings")
    }

    // MARK: Subscription

    private var subscriptionSection: some View {
        Section {
            LabeledContent("Lore+ status") {
                Text(entitlements.isPlus ? (entitlements.isTrialing ? "Trial active" : "Active") : "No active access found")
                    .font(LoreType.caption.weight(.semibold))
                    .foregroundStyle(entitlements.isPlus ? LoreColor.brass700 : LoreColor.ink600)
            }
            .font(LoreType.body)

            Button {
                openURL(ProfileSupportLinks.manageSubscriptions)
            } label: {
                settingsRow("Manage Apple subscription", icon: "creditcard.fill", tint: LoreColor.brass700)
            }
            .buttonStyle(.plain)

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
        } header: {
            Text("Lore+")
        } footer: {
            Text("Apple manages payment, cancellation, refunds, and billing details. Lore never receives your card number. Restore uses the Apple Account that made the purchase.")
        }
    }

    private func restorePurchases() async {
        restoring = true
        restoreNote = nil
        let outcome = await store.restore()
        let token = await auth.validAccessToken()
        await entitlements.refresh(accessToken: token)
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

    // MARK: Privacy + data

    private var privacyDataSection: some View {
        Section {
            NavigationLink {
                PrivacyDataView()
            } label: {
                Label("Privacy & your data", systemImage: "hand.raised.fill")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
            }

            Button {
                guard let url = ProfileSupportLinks.supportRequestURL(
                    accountEmail: auth.session?.user.email,
                    version: ProfileSupportLinks.versionLine
                ) else { return }
                openURL(url)
            } label: {
                settingsRow("Email Lore Support", icon: "envelope.fill", tint: LoreColor.ink)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Privacy & support")
        } footer: {
            Text("See what Lore processes, request access to account data, or get help with an account or purchase.")
        }
    }

    // MARK: About + legal

    /// Policies, support, a rate prompt, and the data attribution the licenses
    /// require (OpenStreetMap ODbL + Wikipedia CC BY-SA). The links open the
    /// live lore-web legal pages, the same ones the paywall points to.
    private var aboutLegalSection: some View {
        Section {
            linkRow("Terms of Use", icon: "doc.text", url: ProfileSupportLinks.terms)
            linkRow("Privacy Policy", icon: "hand.raised", url: ProfileSupportLinks.privacy)
            linkRow("Apple Standard EULA", icon: "checkmark.seal", url: ProfileSupportLinks.appleEULA)
            linkRow("Support Center", icon: "questionmark.circle", url: ProfileSupportLinks.support)
            Button {
                requestReview()
            } label: {
                settingsRow("Rate Lore", icon: "star", tint: LoreColor.ink)
            }
            .buttonStyle(.plain)
        } header: {
            Text("About Lore")
        } footer: {
            Text("Lore \(ProfileSupportLinks.versionLine). Place data © OpenStreetMap contributors (ODbL). Stories draw on Wikipedia (CC BY-SA) and public-domain sources; map and imagery via Apple Maps. © 2026 Lore.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }

    private func linkRow(_ label: String, icon: String, url: URL) -> some View {
        Button {
            openURL(url)
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

    // MARK: Permission state

    private enum PermissionKind: Equatable {
        case notifications, location, camera

        func isUndetermined(
            notification: UNAuthorizationStatus,
            location: CLAuthorizationStatus,
            camera: AVAuthorizationStatus
        ) -> Bool {
            switch self {
            case .notifications: return notification == .notDetermined
            case .location: return location == .notDetermined
            case .camera: return camera == .notDetermined
            }
        }
    }

    private var notificationStatusLabel: String {
        switch push.authorizationStatus {
        case .authorized: return "On"
        case .provisional, .ephemeral: return "Quietly on"
        case .denied: return "Off"
        case .notDetermined: return "Not set"
        @unknown default: return "Review"
        }
    }

    private var locationIsAuthorized: Bool {
        locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
    }

    private var locationStatusLabel: String {
        switch locationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While using"
        case .denied: return "Off"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not set"
        @unknown default: return "Review"
        }
    }

    private var cameraStatusLabel: String {
        switch cameraStatus {
        case .authorized: return "On"
        case .denied: return "Off"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not set"
        @unknown default: return "Review"
        }
    }

    @MainActor
    private func refreshPermissionStatuses() async {
        if Config.pushNotificationsEnabled {
            await push.refreshAuthorizationStatus()
        }
        locationStatus = locationManager.authorizationStatus
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    @MainActor
    private func handlePermission(_ kind: PermissionKind) async {
        guard requestingPermission == nil else { return }
        guard kind.isUndetermined(
            notification: push.authorizationStatus,
            location: locationStatus,
            camera: cameraStatus
        ) else {
            openSystemSettings()
            return
        }

        requestingPermission = kind
        defer { requestingPermission = nil }
        switch kind {
        case .notifications:
            guard Config.pushNotificationsEnabled else { return }
            await push.requestAuthorizationAndRegister()
        case .location:
            locationManager.requestWhenInUseAuthorization()
            try? await Task.sleep(for: .milliseconds(450))
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        await refreshPermissionStatuses()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
