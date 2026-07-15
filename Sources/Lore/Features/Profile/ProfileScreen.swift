import SwiftUI

/// Profile tab.
///
/// Signed out, it carries the 5.1.1 posture in copy (reading never requires
/// an account, docs/10 §5 row 1) and offers sign-in. Signed in, it shows the
/// `user_profile` row: handle, trust tier (Scout → Curator ladder,
/// docs/06-CROWDSOURCING.md), Insight points, and a live Lore+ membership row.
struct ProfileScreen: View {
    @Environment(AuthService.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @State private var showSignIn = false
    @State private var showPaywall = false
    /// True when a signed-in profile load failed, so the row offers a retry
    /// instead of spinning "Loading your profile…" forever.
    @State private var profileLoadFailed = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = auth.profile {
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
                            Task { await auth.signOut() }
                        } label: {
                            Text("Sign out")
                                .font(LoreType.button)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(LoreColor.bone100)
            .navigationTitle("Profile")
            .sheet(isPresented: $showSignIn) {
                SignInView()
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(entitlements: entitlements, store: store, auth: auth)
            }
            .task { await loadProfile() }
        }
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
                    "You don't need an account to read, the map, scanner, "
                    + "cards, and dives all work signed out. An account adds "
                    + "visits, your journal, Insight points, and Lore+."
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
            HStack(spacing: 14) {
                initialsBadge(profile)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayNameOrHandle)
                        .font(LoreType.display(size: 20, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)
                    if let handle = profile.handle, !handle.isEmpty {
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
                TrustBadge(tier: profile.trustTier)
            }
            .padding(.vertical, 4)

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

    private func initialsBadge(_ profile: UserProfile) -> some View {
        ZStack {
            Circle().fill(LoreColor.ink)
            Text(String(profile.displayNameOrHandle.prefix(1)).uppercased())
                .font(LoreType.display(size: 20, weight: .semibold))
                .foregroundStyle(LoreColor.bone)
        }
        .frame(width: 48, height: 48)
    }

    // MARK: Membership (Lore+ is live, not a "coming" stub)

    /// Lore+ is a real, purchasable membership, so this opens the live paywall
    /// (TestFlight feedback: "Coming? Isn't this stuff live?"). Members see an
    /// active badge instead.
    @ViewBuilder
    private var membershipSection: some View {
        Section("Membership") {
            if entitlements.isPlus {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(LoreColor.brass700)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entitlements.isTrialing ? "Lore+ (trial)" : "Lore+ member")
                            .font(LoreType.body)
                            .foregroundStyle(LoreColor.ink)
                        Text("Unlimited dives, every tour, audio narration")
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.ink600)
                    }
                    Spacer()
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
                Text(Self.versionLine)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
            HStack {
                Text("Pilot city").font(LoreType.body)
                Spacer()
                Text("Chicago, Loop · Riverwalk · Museum Campus")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
        }
    }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Trust-tier chip (brand/DESIGN.md §7 `TrustBadge`): Curator earns Brass —
/// "Brass is reserved for money and mastery"; everyone else gets the Bone
/// outline treatment.
struct TrustBadge: View {
    let tier: String

    private var isCurator: Bool { tier.lowercased() == "curator" }

    var body: some View {
        Text(tier.uppercased())
            .loreLabelStyle()
            .foregroundStyle(isCurator ? LoreColor.brass700 : LoreColor.ink600)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurator ? LoreColor.brass.opacity(0.16) : LoreColor.bone200)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isCurator ? LoreColor.brass : LoreColor.bone300,
                        lineWidth: 1
                    )
            )
    }
}
