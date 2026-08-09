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
    @State private var journey = ProfileJourneyModel()
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

                journeySection

                membershipSection

                fieldKitSection

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
            .task(id: auth.session?.user.id) { await reloadProfileSurface() }
            .refreshable {
                guard auth.isSignedIn else { return }
                await reloadProfileSurface(force: true)
            }
            .onChange(of: auth.isSignedIn) { _, signedIn in
                profileLoadFailed = false
                if signedIn {
                    Task { await reloadProfileSurface(force: true) }
                } else {
                    journey.reset()
                }
            }
        }
        .background(LoreColor.bone100.ignoresSafeArea())
    }

    private func reloadProfileSurface(force: Bool = false) async {
        if auth.isSignedIn {
            if force {
                profileLoadFailed = false
                await auth.refreshProfile()
                profileLoadFailed = auth.profile == nil
            } else {
                await loadProfile()
            }
        } else {
            profileLoadFailed = false
        }
        await journey.load(auth: auth)
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

    // MARK: Journey

    private var journeySection: some View {
        Section {
            ProfileJourneyCard(
                state: journey.state,
                isPlus: entitlements.isPlus,
                onRetry: { Task { await journey.load(auth: auth) } }
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
                            Text("Manage access, billing, and purchases")
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

    /// One-stop-shop entries: Profile should be more than an account page.
    /// These are real in-app surfaces, not placeholders.
    private var fieldKitSection: some View {
        Section("Field kit") {
            NavigationLink {
                JournalView()
            } label: {
                profileActionRow(
                    "Journal",
                    detail: auth.isSignedIn ? "Visits, notes, and private photos" : "Sign in to keep private memories",
                    icon: "book.closed.fill"
                )
            }

            NavigationLink {
                PassportView()
            } label: {
                profileActionRow(
                    "Passport",
                    detail: "Badges, milestones, and explorer stats",
                    icon: "seal.fill"
                )
            }

            NavigationLink {
                TravelPreferencesView()
            } label: {
                profileActionRow(
                    "Travel preferences",
                    detail: "Tune your lens, interests, and discovery mix",
                    icon: "slider.horizontal.3"
                )
            }

            NavigationLink {
                PrivacyDataView()
            } label: {
                profileActionRow(
                    "Privacy & data",
                    detail: "Camera, location, journal, and account controls",
                    icon: "hand.raised.fill"
                )
            }

            NavigationLink {
                SettingsView()
            } label: {
                profileActionRow(
                    "Settings",
                    detail: "Permissions, haptics, subscriptions, and legal",
                    icon: "gearshape.fill"
                )
            }
        }
    }

    private func profileActionRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(LoreColor.brass700)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
                Text(detail)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
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

// MARK: - Journey card

private struct ProfileJourneyCard: View {
    let state: ProfileJourneyModel.State
    let isPlus: Bool
    let onRetry: () -> Void

    var body: some View {
        Group {
            switch state {
            case .signedOut:
                signedOutCard
            case .loading:
                loadingCard
            case .loaded(let stats):
                loadedCard(ProfileJourneySnapshot(stats: stats))
            case .failed(let message):
                failedCard(message)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func loadedCard(_ snapshot: ProfileJourneySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            cardHeader(
                eyebrow: isPlus ? "LORE+ FIELD RECORD" : "FIELD RECORD",
                title: snapshot.headline,
                subtitle: snapshot.subhead,
                symbol: "map.circle.fill"
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 92), spacing: 10),
                    GridItem(.flexible(minimum: 92), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(snapshot.primaryMetrics) { metric in
                    ProfileMetricTile(metric: metric, prominence: .primary)
                }
            }

            HStack(spacing: 10) {
                ForEach(snapshot.secondaryMetrics) { metric in
                    ProfileMetricTile(metric: metric, prominence: .compact)
                }
            }
        }
        .padding(18)
        .profileJourneySurface()
    }

    private var signedOutCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(
                eyebrow: "PRIVATE FIELD RECORD",
                title: "Make Lore yours",
                subtitle: "Save visits, notes, photos, badges, preferences, and Lore+ access in one account.",
                symbol: "person.crop.circle.badge.plus"
            )

            HStack(spacing: 10) {
                ProfileValuePill(symbol: "lock.shield.fill", text: "Private journal")
                ProfileValuePill(symbol: "seal.fill", text: "Earned badges")
            }
        }
        .padding(18)
        .profileJourneySurface()
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(LoreColor.ink800)
                    .frame(width: 48, height: 48)
                    .shimmer()
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerBlock(width: 120, height: 12, cornerRadius: 5, fill: LoreColor.ink800)
                    ShimmerBlock(width: 210, height: 24, cornerRadius: 7, fill: LoreColor.ink800)
                    ShimmerBlock(width: 250, height: 14, cornerRadius: 5, fill: LoreColor.ink800)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 92), spacing: 10),
                    GridItem(.flexible(minimum: 92), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LoreColor.ink800)
                        .frame(height: 78)
                        .shimmer()
                }
            }
        }
        .padding(18)
        .profileJourneySurface()
        .accessibilityLabel("Loading your field record")
    }

    private func failedCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                eyebrow: "SYNC NEEDED",
                title: "Field record unavailable",
                subtitle: message,
                symbol: "icloud.slash.fill"
            )

            Button(action: onRetry) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.ink900)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                    .background(LoreColor.amber, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(18)
        .profileJourneySurface()
    }

    private func cardHeader(
        eyebrow: String,
        title: String,
        subtitle: String,
        symbol: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(LoreColor.amber.opacity(0.14))
                Circle()
                    .strokeBorder(LoreColor.brass300.opacity(0.5), lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LoreColor.amber)
            }
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(LoreType.label)
                    .tracking(1)
                    .foregroundStyle(LoreColor.brass300)
                Text(title)
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ProfileMetricTile: View {
    enum Prominence {
        case primary
        case compact
    }

    let metric: ProfileJourneyMetric
    let prominence: Prominence

    var body: some View {
        VStack(alignment: .leading, spacing: prominence == .primary ? 8 : 5) {
            HStack {
                Image(systemName: metric.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LoreColor.amber)
                Spacer(minLength: 0)
            }
            Text(metric.value)
                .font(LoreType.display(size: prominence == .primary ? 25 : 19, weight: .semibold))
                .foregroundStyle(prominence == .primary ? LoreColor.bone : LoreColor.brass300)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(metric.label.uppercased())
                .font(LoreType.label)
                .tracking(0.8)
                .foregroundStyle(LoreColor.bone.opacity(0.64))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: prominence == .primary ? 78 : 70, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LoreColor.ink800.opacity(prominence == .primary ? 0.95 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LoreColor.brass300.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.label): \(metric.value)")
    }
}

private struct ProfileValuePill: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(LoreType.caption.weight(.semibold))
            .foregroundStyle(LoreColor.bone)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(LoreColor.ink800, in: Capsule())
            .overlay(Capsule().strokeBorder(LoreColor.brass300.opacity(0.18), lineWidth: 1))
    }
}

private extension View {
    func profileJourneySurface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LoreColor.ink900, LoreColor.ink950],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LoreColor.brass300.opacity(0.25), lineWidth: 1)
            )
            .loreElevation(.elev1)
    }
}
