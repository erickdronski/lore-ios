import SwiftUI

/// Profile tab.
///
/// Signed out, it carries the 5.1.1 posture in copy (reading never requires
/// an account, docs/10 §5 row 1) and offers sign-in. Signed in, it becomes the
/// traveler's command center for identity, visits, Lore+, preferences, privacy,
/// support, legal, and account controls.
struct ProfileScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(VisitStore.self) private var visits
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSignIn = false
    @State private var showPaywall = false
    @State private var editingProfile: UserProfile?
    @State private var showSignOutConfirmation = false
    @State private var signingOut = false
    @State private var restoringPurchases = false
    @State private var restoreNote: String?
    @State private var loadedAccountID: String?
    /// True when a signed-in profile load failed, so the row offers a retry
    /// instead of spinning "Loading your profile…" forever.
    @State private var profileLoadFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Profile")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(LoreColor.ink)
                        .accessibilityAddTraits(.isHeader)

                    profileHero

                    dashboardMetrics

                    VStack(alignment: .leading, spacing: 14) {
                        ProfileSectionHeader(
                            eyebrow: "COMMAND CENTER",
                            title: "Everything you need",
                            detail: "Your traveler card, membership, privacy, purchases, and support in one place."
                        )
                        travelerSetupPanel
                        membershipPanel
                        privacySupportPanel
                        aboutPanel
                        accountPanel
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 26)
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(LoreColor.bone100.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: 86)
                    .allowsHitTesting(false)
            }
            .sheet(isPresented: $showSignIn) {
                SignInView()
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(entitlements: entitlements, store: store, auth: auth)
            }
            .sheet(item: $editingProfile) { profile in
                EditProfileView(profile: profile)
                    .presentationDetents([.large])
            }
            .alert("Sign out of Lore?", isPresented: $showSignOutConfirmation) {
                Button("Sign out", role: .destructive) {
                    Task { await signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your private account data stays safely synced. Any choices stored only on this device remain here until you remove Lore.")
            }
            .task(id: accountTaskID) { await loadDashboard(force: loadedAccountID != accountTaskID) }
            .refreshable {
                await refreshDashboard()
            }
        }
        .background(LoreColor.bone100.ignoresSafeArea())
    }

    private var accountTaskID: String {
        auth.session?.user.id ?? "signed-out"
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 40 : 20
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 760 : .infinity
    }

    private var accountEmail: String? {
        guard let email = auth.session?.user.email, !email.isEmpty else { return nil }
        return email
    }

    /// Load the signed-in user's profile, flagging a failure so the row can
    /// offer a retry instead of spinning forever (refreshProfile swallows the
    /// thrown error to nil, so "still nil after the attempt" is the signal).
    private func loadProfile() async {
        guard auth.isSignedIn, auth.profile == nil else { return }
        profileLoadFailed = false
        await auth.refreshProfile()
        if auth.profile == nil { profileLoadFailed = true }
    }

    @MainActor
    private func loadDashboard(force: Bool = false) async {
        let taskID = accountTaskID
        if force {
            loadedAccountID = taskID
            profileLoadFailed = false
        }
        await loadProfile()
        await visits.load(force: force)
        await visits.loadHistory(force: force)
    }

    @MainActor
    private func refreshDashboard() async {
        profileLoadFailed = false
        if auth.isSignedIn {
            await auth.refreshProfile()
            profileLoadFailed = auth.profile == nil
        }
        await visits.load(force: true)
        await visits.loadHistory(force: true)
        await entitlements.refresh(accessToken: await auth.validAccessToken())
        loadedAccountID = accountTaskID
    }

    @MainActor
    private func signOut() async {
        guard !signingOut else { return }
        signingOut = true
        await auth.signOut()
        signingOut = false
        restoreNote = nil
    }

    @MainActor
    private func restorePurchases() async {
        guard !restoringPurchases else { return }
        guard auth.isSignedIn else {
            restoreNote = "Sign in to restore purchases from your Apple Account."
            showSignIn = true
            return
        }
        restoringPurchases = true
        restoreNote = nil
        let outcome = await store.restore()
        await entitlements.refresh(accessToken: await auth.validAccessToken())
        restoringPurchases = false
        switch outcome {
        case .restored:
            restoreNote = "Purchases restored. Lore+ is active."
        case .nothingToRestore:
            restoreNote = "Nothing to restore on this Apple ID."
        case .userCancelled:
            break
        case .failed(let message):
            restoreNote = message
        }
    }

    // MARK: Hero

    @ViewBuilder
    private var profileHero: some View {
        if auth.isRestoring {
            ProfileLoadingPanel(
                title: "Restoring your secure session",
                detail: "Your profile, visits, and membership will appear here in a moment."
            )
        } else if let profile = auth.profile {
            signedInHero(profile)
        } else if auth.isSignedIn {
            signedInLoadingHero
        } else {
            signedOutHero
        }
    }

    private var signedOutHero: some View {
        ProfileHeroShell {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lore field record")
                    .loreLabelStyle()
                    .foregroundStyle(LoreColor.brass300)

                Text("Every place has a story.")
                    .font(LoreType.display(size: 34, weight: .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(LoreColor.bone)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Explore signed out, then create a private travel record when you want synced visits, notes, Insight points, and Lore+ access.")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    ProfileHeroChip(label: "Map", icon: "map")
                    ProfileHeroChip(label: "Scanner", icon: "camera.viewfinder")
                    ProfileHeroChip(label: "Free dives", icon: "book.pages")
                }

                Button {
                    showSignIn = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Sign in or create account")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.ink)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .background(LoreColor.amber, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func signedInHero(_ profile: UserProfile) -> some View {
        ProfileHeroShell {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    ProfileAvatarView(profile: profile, size: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.trustTierLabel)
                            .loreLabelStyle()
                            .foregroundStyle(LoreColor.brass300)
                        Text(profile.displayNameOrHandle)
                            .font(LoreType.display(size: 32, weight: .semibold, relativeTo: .largeTitle))
                            .foregroundStyle(LoreColor.bone)
                            .fixedSize(horizontal: false, vertical: true)
                        if profile.displayName != nil, let handle = profile.handle {
                            Text("@\(handle)")
                                .font(LoreType.caption)
                                .foregroundStyle(LoreColor.bone.opacity(0.76))
                        }
                        if let accountEmail {
                            Text(accountEmail)
                                .font(LoreType.caption)
                                .foregroundStyle(LoreColor.bone.opacity(0.76))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 8)
                    Button { editingProfile = profile } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(LoreColor.ink)
                            .frame(width: 46, height: 46)
                            .background(LoreColor.bone, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Edit profile")
                }

                if let bio = profile.bio {
                    Text(bio)
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.bone.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }

                ProfileCompletionBanner(profile: profile) {
                    editingProfile = profile
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var signedInLoadingHero: some View {
        ProfilePanel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: profileLoadFailed ? "exclamationmark.triangle.fill" : "person.crop.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(profileLoadFailed ? LoreColor.error : LoreColor.brass700)
                    .frame(width: 42, height: 42)
                    .background(LoreColor.bone200, in: Circle())
                VStack(alignment: .leading, spacing: 8) {
                    Text(profileLoadFailed ? "Can't load your profile" : "Loading your profile")
                        .font(LoreType.displayM)
                        .foregroundStyle(LoreColor.ink)
                    Text(profileLoadFailed ? "Your account is signed in, but Lore could not read the profile row yet." : "Your account hub is opening.")
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.ink600)
                    if profileLoadFailed {
                        Button("Try again") {
                            Task { await loadProfile() }
                        }
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.brass700)
                    } else {
                        ProgressView()
                            .tint(LoreColor.brass700)
                    }
                }
            }
        }
    }

    // MARK: Metrics

    private var dashboardMetrics: some View {
        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
            ProfileMetricCard(
                title: "Insight",
                value: auth.profile.map { "\($0.insightPoints)" } ?? (auth.isSignedIn ? "..." : "0"),
                detail: auth.profile?.trustTierLabel.capitalized ?? "sign in to sync",
                icon: "sparkles",
                tint: LoreColor.amber
            )
            ProfileMetricCard(
                title: "Visits",
                value: visits.loaded ? "\(visits.visitedPlaceIDs.count)" : "...",
                detail: visits.loaded ? "places recorded" : "loading visits",
                icon: "figure.walk.circle.fill",
                tint: LoreColor.successDark
            )
            ProfileMetricCard(
                title: "Journal",
                value: visits.historyLoaded ? "\(visits.visitHistory.count)" : "...",
                detail: visits.historyLoaded ? "private entries" : "loading notes",
                icon: "book.closed.fill",
                tint: LoreColor.infoDark
            )
            ProfileMetricCard(
                title: "Lore+",
                value: entitlements.isPlus ? "On" : "Off",
                detail: entitlements.isTrialing ? "trial active" : (entitlements.isPlus ? "member" : "free explorer"),
                icon: "crown.fill",
                tint: LoreColor.brass300
            )
        }
    }

    private var metricColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: count)
    }

    // MARK: Command center

    @ViewBuilder
    private var travelerSetupPanel: some View {
        ProfilePanel {
            VStack(spacing: 0) {
                ProfilePanelTitle(
                    icon: "person.text.rectangle",
                    title: "Traveler setup",
                    detail: "Shape how Lore introduces cities, routes, and nearby places."
                )

                if let profile = auth.profile, profile.completedIdentityFieldCount < 3 {
                    Button {
                        editingProfile = profile
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Complete your traveler card")
                                    .font(LoreType.button)
                                    .foregroundStyle(LoreColor.ink)
                                Spacer()
                                Text("\(profile.completedIdentityFieldCount) of 3")
                                    .font(LoreType.caption.weight(.semibold))
                                    .foregroundStyle(LoreColor.brass700)
                            }
                            ProgressView(value: profile.identityCompletionFraction)
                                .tint(LoreColor.brass700)
                        }
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    Divider().background(LoreColor.bone300)
                }

                if let profile = auth.profile {
                    Button { editingProfile = profile } label: {
                        ProfileActionRow(
                            title: "Edit profile",
                            detail: "Name, username, avatar, and travel bio",
                            icon: "pencil",
                            trailing: "Edit"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { showSignIn = true } label: {
                        ProfileActionRow(
                            title: "Create your traveler card",
                            detail: "Sync visits, notes, and membership across devices",
                            icon: "person.crop.circle.badge.plus",
                            trailing: "Sign in"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider().background(LoreColor.bone300)

                NavigationLink {
                    TravelPreferencesView()
                } label: {
                    ProfileActionRow(
                        title: "Travel preferences",
                        detail: "Tune your lens, interests, and city recommendations",
                        icon: "slider.horizontal.3",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)

                Divider().background(LoreColor.bone300)

                NavigationLink {
                    SettingsView()
                } label: {
                    ProfileActionRow(
                        title: "Settings and permissions",
                        detail: "Map filters, haptics, camera, location, language, and subscriptions",
                        icon: "gearshape.fill",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var membershipPanel: some View {
        ProfilePanel {
            VStack(spacing: 0) {
                ProfilePanelTitle(
                    icon: "crown.fill",
                    title: entitlements.isPlus ? (entitlements.isTrialing ? "Lore+ trial active" : "Lore+ member") : "Lore+ membership",
                    detail: entitlements.isPlus
                        ? "Your paid city tools are unlocked on this device."
                        : "Unlock unlimited dives, every tour, and high-quality narration when available."
                )

                if entitlements.isPlus {
                    ProfileStatusStrip(
                        title: entitlements.isTrialing ? "Trial access is active" : "Full access is active",
                        detail: entitlements.isUsingCachedEntitlement ? "Using a recent verified cache while the backend catches up." : "StoreKit and Lore entitlement checks can reopen access after refresh.",
                        icon: "checkmark.seal.fill"
                    )
                    .padding(.vertical, 14)
                    Divider().background(LoreColor.bone300)
                } else {
                    Button { showPaywall = true } label: {
                        ProfileActionRow(
                            title: "Unlock Lore+",
                            detail: "Apple In-App Purchase, managed through the App Store",
                            icon: "sparkles",
                            trailing: "View"
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().background(LoreColor.bone300)
                }

                Button {
                    openURL(ProfileSupportLinks.manageSubscriptions)
                } label: {
                    ProfileActionRow(
                        title: "Manage Apple subscription",
                        detail: "Billing, cancellation, refunds, and renewal are handled by Apple",
                        icon: "creditcard.fill",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)

                Divider().background(LoreColor.bone300)

                Button {
                    Task { await restorePurchases() }
                } label: {
                    ProfileActionRow(
                        title: auth.isSignedIn ? "Restore purchases" : "Sign in to restore purchases",
                        detail: auth.isSignedIn ? "Recheck this Apple Account for Lore+ access" : "Purchases are linked after a secure Lore sign-in",
                        icon: "arrow.clockwise",
                        trailing: restoringPurchases ? "Restoring" : nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(restoringPurchases)

                if let restoreNote {
                    Text(restoreNote)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
        }
    }

    private var privacySupportPanel: some View {
        ProfilePanel {
            VStack(spacing: 0) {
                ProfilePanelTitle(
                    icon: "hand.raised.fill",
                    title: "Privacy, support, and legal",
                    detail: "Understand the data model, get help, and reach the live policy pages."
                )

                NavigationLink {
                    PrivacyDataView()
                } label: {
                    ProfileActionRow(
                        title: "Privacy and your data",
                        detail: "Camera posture, location use, data access, and deletion notes",
                        icon: "lock.shield.fill",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)

                Divider().background(LoreColor.bone300)

                Button {
                    guard let url = ProfileSupportLinks.supportRequestURL(
                        accountEmail: accountEmail,
                        version: ProfileSupportLinks.versionLine
                    ) else { return }
                    openURL(url)
                } label: {
                    ProfileActionRow(
                        title: "Email Lore Support",
                        detail: "Prepared message includes account and app version fields",
                        icon: "envelope.fill",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)

                Divider().background(LoreColor.bone300)

                Button {
                    openURL(ProfileSupportLinks.support)
                } label: {
                    ProfileActionRow(
                        title: "Support center",
                        detail: "Published help route for Lore travelers",
                        icon: "questionmark.circle.fill",
                        trailing: nil
                    )
                }
                .buttonStyle(.plain)

                Divider().background(LoreColor.bone300)

                Button { openURL(ProfileSupportLinks.terms) } label: {
                    ProfileActionRow(title: "Terms of Use", detail: "Live web policy", icon: "doc.text.fill", trailing: nil)
                }
                .buttonStyle(.plain)

                Divider().background(LoreColor.bone300)

                Button { openURL(ProfileSupportLinks.privacy) } label: {
                    ProfileActionRow(title: "Privacy Policy", detail: "Live web policy", icon: "hand.raised.fill", trailing: nil)
                }
                .buttonStyle(.plain)

                Divider().background(LoreColor.bone300)

                Button { openURL(ProfileSupportLinks.appleEULA) } label: {
                    ProfileActionRow(title: "Apple Standard EULA", detail: "Required Apple license terms", icon: "checkmark.seal.fill", trailing: nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutPanel: some View {
        ProfilePanel {
            VStack(alignment: .leading, spacing: 14) {
                ProfilePanelTitle(
                    icon: "info.circle.fill",
                    title: "About Lore",
                    detail: "Version, coverage, data attribution, and source posture."
                )
                ProfileInfoRow(title: "Version", value: ProfileSupportLinks.versionLine)
                Divider().background(LoreColor.bone300)
                ProfileInfoRow(title: "Coverage", value: "Cities around the world")
                Divider().background(LoreColor.bone300)
                Text("Place data © OpenStreetMap contributors (ODbL). Stories draw on Wikipedia (CC BY-SA) and public-domain sources; map and imagery via Apple Maps. © 2026 Lore.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var accountPanel: some View {
        ProfilePanel {
            VStack(spacing: 0) {
                ProfilePanelTitle(
                    icon: "person.crop.circle.fill",
                    title: "Account",
                    detail: auth.isSignedIn ? "Secure session and account-level controls." : "Create an account only when you want synced private travel data."
                )

                if auth.isSignedIn {
                    if let accountEmail {
                        ProfileInfoRow(title: "Signed in as", value: accountEmail)
                            .padding(.vertical, 14)
                        Divider().background(LoreColor.bone300)
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        ProfileActionRow(
                            title: "Account deletion",
                            detail: "Typed confirmation and secure session required",
                            icon: "trash.fill",
                            trailing: nil,
                            tint: LoreColor.error
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(LoreColor.bone300)

                    Button(role: .destructive) {
                        showSignOutConfirmation = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(LoreColor.error)
                                .frame(width: 34, height: 34)
                                .background(LoreColor.error.opacity(0.1), in: Circle())
                            Text("Sign out")
                                .font(LoreType.button)
                                .foregroundStyle(LoreColor.error)
                            Spacer()
                            if signingOut { ProgressView() }
                        }
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(signingOut)
                } else {
                    Button { showSignIn = true } label: {
                        ProfileActionRow(
                            title: "Sign in to Lore",
                            detail: "Keep visits, journal notes, photos, and Lore+ access with you",
                            icon: "person.crop.circle.badge.plus",
                            trailing: "Sign in"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ProfileHeroShell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LoreColor.ink950, LoreColor.ink900, LoreColor.ink800],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(alignment: .topTrailing) {
                        ProfileRouteTrace()
                            .stroke(LoreColor.brass300.opacity(0.28), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 8]))
                            .frame(width: 190, height: 132)
                            .padding(.top, 42)
                            .padding(.trailing, -18)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .strokeBorder(LoreColor.brass300.opacity(0.34), lineWidth: 1)
                    )
            }
            .shadow(color: LoreColor.ink.opacity(0.22), radius: 18, y: 12)
    }
}

private struct ProfileRouteTrace: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY * 0.9))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY * 0.55),
            control1: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY * 0.1),
            control2: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY * 1.05)
        )
        return path
    }
}

private struct ProfileHeroChip: View {
    let label: String
    let icon: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(LoreType.caption.weight(.semibold))
            .foregroundStyle(LoreColor.bone)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(LoreColor.bone.opacity(0.12), in: Capsule())
    }
}

private struct ProfileCompletionBanner: View {
    let profile: UserProfile
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(LoreColor.bone.opacity(0.18), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: max(0.04, profile.identityCompletionFraction))
                        .stroke(LoreColor.amber, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(profile.completedIdentityFieldCount)/3")
                        .font(LoreType.caption.weight(.bold))
                        .foregroundStyle(LoreColor.bone)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.completedIdentityFieldCount < 3 ? "Complete your traveler card" : "Traveler card complete")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.bone)
                    Text(profile.completedIdentityFieldCount < 3 ? "A fuller card makes your private field record feel personal." : "Name, handle, and bio are ready.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LoreColor.bone.opacity(0.72))
            }
            .padding(14)
            .background(LoreColor.bone.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Traveler card \(Int(profile.identityCompletionFraction * 100)) percent complete")
        .accessibilityHint("Opens profile editing")
    }
}

private struct ProfileLoadingPanel: View {
    let title: String
    let detail: String

    var body: some View {
        ProfilePanel {
            HStack(alignment: .top, spacing: 14) {
                ProgressView()
                    .tint(LoreColor.brass700)
                    .frame(width: 42, height: 42)
                    .background(LoreColor.bone200, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(LoreType.displayM)
                        .foregroundStyle(LoreColor.ink)
                    Text(detail)
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ProfileSectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .loreLabelStyle()
                .foregroundStyle(LoreColor.brass700)
            Text(title)
                .font(LoreType.displayL)
                .foregroundStyle(LoreColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(LoreType.body)
                .foregroundStyle(LoreColor.ink600)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ProfilePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(LoreColor.bone300.opacity(0.75), lineWidth: 1)
            )
            .shadow(color: LoreColor.ink.opacity(0.08), radius: 12, y: 6)
    }
}

private struct ProfilePanelTitle: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LoreColor.brass700)
                .frame(width: 38, height: 38)
                .background(LoreColor.brass.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LoreType.display(size: 20, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(LoreColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 12)
    }
}

private struct ProfileMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(LoreType.display(size: 26, weight: .semibold, relativeTo: .title2))
                    .foregroundStyle(LoreColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(LoreType.caption.weight(.semibold))
                    .foregroundStyle(LoreColor.ink)
                Text(detail)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(LoreColor.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LoreColor.bone300.opacity(0.65), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileActionRow: View {
    let title: String
    let detail: String
    let icon: String
    let trailing: String?
    var tint: Color = LoreColor.brass700

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LoreType.body.weight(.semibold))
                    .foregroundStyle(LoreColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            if let trailing {
                Text(trailing)
                    .font(LoreType.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LoreColor.ink600.opacity(0.72))
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileStatusStrip: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(LoreColor.success)
                .frame(width: 34, height: 34)
                .background(LoreColor.success.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LoreType.body.weight(.semibold))
                    .foregroundStyle(LoreColor.ink)
                Text(detail)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ProfileInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(LoreType.body)
                .foregroundStyle(LoreColor.ink)
            Spacer(minLength: 12)
            Text(value)
                .font(LoreType.caption.weight(.semibold))
                .foregroundStyle(LoreColor.ink600)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .accessibilityElement(children: .combine)
    }
}
