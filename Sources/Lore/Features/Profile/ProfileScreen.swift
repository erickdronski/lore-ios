import SwiftUI

/// Profile tab.
///
/// Signed out, it carries the 5.1.1 posture in copy (reading never requires
/// an account, docs/10 §5 row 1) and offers sign-in. Signed in, it shows the
/// `user_profile` row: handle, personal identity fields, Insight points, and a
/// live Lore+ membership row.
struct ProfileScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSignIn = false
    @State private var showPaywall = false
    @State private var editingProfile: UserProfile?
    @State private var showSignOutConfirmation = false
    @State private var signingOut = false
    /// True when a signed-in profile load failed, so the row offers a retry
    /// instead of spinning "Loading your profile…" forever.
    @State private var profileLoadFailed = false

    var body: some View {
        NavigationStack {
            List {
                Text("Profile")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(LoreColor.ink)
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 8, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityAddTraits(.isHeader)

                if auth.isRestoring {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Restoring your secure session…")
                                .font(LoreType.body)
                                .foregroundStyle(LoreColor.ink600)
                        }
                    }
                } else if let profile = auth.profile {
                    signedInHeader(profile)
                } else if auth.isSignedIn {
                    Section {
                        if profileLoadFailed {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(LoreColor.brass700)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Can't load your profile")
                                        .font(LoreType.body)
                                        .foregroundStyle(LoreColor.ink)
                                    Button("Try again") { Task { await loadProfile() } }
                                        .font(LoreType.caption)
                                        .foregroundStyle(LoreColor.brass700)
                                }
                            }
                        } else {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Loading your profile…")
                                    .font(LoreType.body)
                                    .foregroundStyle(LoreColor.ink600)
                            }
                        }
                    }
                } else {
                    signedOutHeader
                }

                membershipSection

                settingsSection

                aboutSection

                if auth.isSignedIn {
                    Section {
                        Button(role: .destructive) {
                            showSignOutConfirmation = true
                        } label: {
                            HStack {
                                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(LoreType.button)
                                Spacer()
                                if signingOut { ProgressView() }
                            }
                        }
                        .disabled(signingOut)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(LoreColor.bone100.ignoresSafeArea())
            .contentMargins(.horizontal, horizontalSizeClass == .regular ? 80 : 0, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
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
            .task { await loadProfile() }
            .refreshable {
                guard auth.isSignedIn else { return }
                profileLoadFailed = false
                await auth.refreshProfile()
                profileLoadFailed = auth.profile == nil
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                profileLoadFailed = false
                if signedIn { Task { await loadProfile() } }
            }
        }
        .background(LoreColor.bone100.ignoresSafeArea())
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
    private func signOut() async {
        guard !signingOut else { return }
        signingOut = true
        await auth.signOut()
        signingOut = false
    }

    // MARK: Signed out

    private var signedOutHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Every place has a story.")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.ink)

                // The 5.1.1 posture, stated to the user, not just the
                // reviewer: reading is never gated on an account.
                Text(
                    "You don't need an account to explore. The map, scanner, "
                    + "cards, and free dives all work signed out. An account adds "
                    + "synced visits, your private journal, Insight points, and Lore+."
                )
                .font(LoreType.body)
                .foregroundStyle(LoreColor.ink600)

                Button {
                    showSignIn = true
                } label: {
                    Text("Sign in")
                        .font(LoreType.button)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .background(LoreColor.ink, in: Capsule())
                .foregroundStyle(LoreColor.bone)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: Signed in

    private func signedInHeader(_ profile: UserProfile) -> some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                ProfileAvatarView(profile: profile)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayNameOrHandle)
                        .font(LoreType.display(size: 20, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)
                    if profile.displayName != nil, let handle = profile.handle {
                        Text("@\(handle)")
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.ink600)
                    }
                    if let email = auth.session?.user.email, !email.isEmpty {
                        Text(email)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.ink600)
                    }
                }
                Spacer()
                Button { editingProfile = profile } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LoreColor.brass700)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit profile")
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)

            if let bio = profile.bio {
                Text(bio)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if profile.completedIdentityFieldCount < 3 {
                Button {
                    editingProfile = profile
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Complete your traveler card", systemImage: "person.crop.circle.badge.plus")
                                .font(LoreType.caption.weight(.semibold))
                            Spacer()
                            Text("\(profile.completedIdentityFieldCount) of 3")
                                .font(LoreType.caption)
                        }
                        ProgressView(value: profile.identityCompletionFraction)
                            .tint(LoreColor.brass700)
                    }
                    .foregroundStyle(LoreColor.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Traveler card \(Int(profile.identityCompletionFraction * 100)) percent complete")
                .accessibilityHint("Opens profile editing")
            }

            HStack {
                Label("Insight", systemImage: "sparkles")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
                Spacer()
                Text("\(profile.insightPoints)")
                    .font(LoreType.display(size: 17, weight: .semibold))
                    .foregroundStyle(LoreColor.brass700)
            }
        }
    }

    // MARK: Membership (Lore+ is live, not a "coming" stub)

    /// Lore+ is a real, purchasable membership, so this opens the live paywall
    /// (TestFlight feedback: "Coming? Isn't this stuff live?"). Members see an
    /// active badge instead.
    @ViewBuilder
    private var membershipSection: some View {
        Section("Membership") {
            if entitlements.isPlus {
                NavigationLink {
                    SettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(LoreColor.brass700)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entitlements.isTrialing ? "Lore+ trial active" : "Lore+ member")
                                .font(LoreType.body)
                                .foregroundStyle(LoreColor.ink)
                            Text("Manage access, billing, and offline packs")
                                .font(LoreType.caption)
                                .foregroundStyle(LoreColor.ink600)
                        }
                    }
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(LoreColor.brass700)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unlock Lore+")
                                .font(LoreType.body)
                                .foregroundStyle(LoreColor.brass700)
                            Text("Unlimited dives, every tour, audio narration")
                                .font(LoreType.caption)
                                .foregroundStyle(LoreColor.ink600)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LoreColor.ink600)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Settings entry: preferences, permissions, subscription (TestFlight
    /// feedback #13). Available signed in or out, permissions + haptics apply
    /// to everyone.
    private var settingsSection: some View {
        Section {
            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version").font(LoreType.body)
                Spacer()
                Text(ProfileSupportLinks.versionLine)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
            HStack {
                Text("Coverage").font(LoreType.body)
                Spacer()
                Text("Cities around the world")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
        }
    }

}
