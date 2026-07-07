import SwiftUI

/// Profile tab.
///
/// Signed out, it carries the 5.1.1 posture in copy (reading never requires
/// an account, docs/10 §5 row 1) and offers sign-in. Signed in, it shows the
/// `user_profile` row: handle, trust tier (Scout → Curator ladder,
/// docs/06-CROWDSOURCING.md), Insight points. Contributions and Lore+ are
/// deliberate stubs, their rows state which phase ships them.
struct ProfileScreen: View {
    @Environment(AuthService.self) private var auth
    @State private var showSignIn = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = auth.profile {
                    signedInHeader(profile)
                } else if auth.isSignedIn {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading your profile…")
                                .font(LoreType.body)
                                .foregroundStyle(LoreColor.ink600)
                        }
                    }
                } else {
                    signedOutHeader
                }

                stubSection

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
            .task {
                if auth.isSignedIn { await auth.refreshProfile() }
            }
        }
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
                    + "contributions, Insight points, and Lore+."
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
                    Text("@\(profile.handle)")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
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

    // MARK: Stubs, honest about what phase ships them

    private var stubSection: some View {
        Section("Coming") {
            StubRow(
                icon: "plus.viewfinder",
                title: "Contributions",
                note: "P2, photo + 3 fields, CLA gate, peer verification"
            )
            StubRow(
                icon: "crown",
                title: "Lore+",
                note: "Unlimited dives · $5.99/mo · 7-day trial"
            )
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

struct StubRow: View {
    let icon: String
    let title: String
    let note: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(LoreColor.ink600)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
                Text(note)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
        }
        .opacity(0.75)
    }
}
