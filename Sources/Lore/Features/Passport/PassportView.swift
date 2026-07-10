import SwiftUI

/// The Passport, the exploration reward wall. It fetches the achievement
/// catalog (anonymous read) joined against the signed-in user's
/// `user_achievement` rows, groups badges by category (milestone, collector,
/// city, knowledge, streak, special), and renders each as a tier medallion:
/// unlocked in full color, in-progress with a progress ring, locked as a grey
/// outline, and secret-locked as a mystery tile. A header tallies unlocked
/// count and total Insight points. When `recompute_achievements` returns new
/// unlocks (e.g. after a visit lands), the `UnlockCelebration` overlay fires.
///
/// Signed-out is a first-class state: the wall still shows the catalog (so a
/// reader sees what's earnable) with a gentle "sign in to start earning" note,
/// honoring the 5.1.1 posture that reading is never gated (docs/10 §5).
struct PassportView: View {
    @Environment(AuthService.self) private var auth
    @State private var model = PassportModel()

    var body: some View {
        NavigationStack {
            ZStack {
                LoreColor.ink900.ignoresSafeArea()

                switch model.state {
                case .loading:
                    loadingWall
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Can't load the passport", systemImage: "seal")
                    } description: {
                        Text(message).foregroundStyle(LoreColor.bone.opacity(0.7))
                    } actions: {
                        Button("Try again") { Task { await reload() } }
                            .tint(LoreColor.amber)
                    }
                case .loaded, .empty:
                    wall
                }

                // The unlock reward moment, above everything.
                if !model.celebrating.isEmpty {
                    UnlockCelebration(unlocked: model.celebrating) {
                        withAnimation(LoreMotion.tap) { model.dismissCelebration() }
                    }
                    .zIndex(10)
                    .transition(.opacity)
                }
            }
            .navigationTitle("Passport")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // The wall sits on a dark Ink ground, so run the screen in dark mode:
            // this recolors the *system* chrome (the large nav title + the status
            // bar) to light so both are legible. Content uses explicit LoreColors,
            // which are fixed values and do not shift with the scheme.
            .preferredColorScheme(.dark)
            .task { await model.loadIfNeeded(auth: auth) }
        }
    }

    private func reload() async {
        await model.load(auth: auth)
    }

    // MARK: Wall

    private var wall: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PassportSummary(
                    unlockedCount: model.unlockedCount,
                    totalCount: model.totalCount,
                    insightPoints: model.insightPoints,
                    signedIn: auth.isSignedIn
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)

                if !auth.isSignedIn {
                    signedOutNote
                        .padding(.horizontal, 16)
                }

                ForEach(model.sections) { section in
                    CategorySection(section: section)
                }
            }
            .padding(.bottom, 40)
        }
        .scrollContentBackground(.hidden)
    }

    /// Content-shaped loading wall (LUXURY-MOTION §3, "delete every spinner"): a
    /// dim summary block over a grid of shimmering medallion discs, so the swap
    /// to the real wall is a cross-fade with no layout jump.
    private var loadingWall: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LoreColor.ink800)
                    .frame(height: 116)
                    .shimmer()
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 14) {
                        ShimmerBlock(width: 140, height: 20, cornerRadius: 6, fill: LoreColor.ink800)
                            .padding(.horizontal, 16)
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                            ],
                            spacing: 20
                        ) {
                            ForEach(0..<6, id: \.self) { _ in
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(LoreColor.ink800)
                                        .frame(width: 72, height: 72)
                                        .shimmer()
                                    ShimmerBlock(width: 60, height: 12, cornerRadius: 5, fill: LoreColor.ink800)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .scrollContentBackground(.hidden)
        .accessibilityLabel("Loading your passport")
    }

    private var signedOutNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .foregroundStyle(LoreColor.amber)
            Text("Sign in to start earning. Reading is always free, badges track the places you visit.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.75))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LoreColor.ink800)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LoreColor.ink700, lineWidth: 1)
        )
    }
}

// MARK: - Summary header

/// The Insight ledger at the top of the wall: unlocked-of-total and the running
/// Insight points, set in Fraunces display. Brass is reserved for the points
/// total (money and mastery, brand/DESIGN.md §7).
struct PassportSummary: View {
    let unlockedCount: Int
    let totalCount: Int
    let insightPoints: Int
    let signedIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your exploration, earned")
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)

            HStack(spacing: 12) {
                stat(caption: "Badges") {
                    // "n / total", n counts up on first view; the total is fixed.
                    HStack(spacing: 0) {
                        CountUpText.integer(
                            unlockedCount,
                            font: LoreType.display(size: 26, weight: .semibold)
                        )
                        Text("/\(totalCount)")
                            .font(LoreType.display(size: 26, weight: .semibold))
                    }
                    .foregroundStyle(LoreColor.amber)
                }
                divider
                stat(caption: "Insight") {
                    // Insight points roll up, the ledger tallying (LUXURY-MOTION §5).
                    CountUpText.integer(
                        insightPoints,
                        font: LoreType.display(size: 26, weight: .semibold)
                    )
                    .foregroundStyle(LoreColor.brass300)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(LoreColor.ink800)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(LoreColor.ink700, lineWidth: 1)
        )
    }

    private func stat<Value: View>(
        caption: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value()
            Text(caption.uppercased())
                .loreLabelStyle()
                .tracking(0.8)
                // Bone, not ink600: the Passport card is dark (ink800), so the
                // caption needs a light tone to be readable (TestFlight feedback:
                // "contrast here, I can't read all the text").
                .foregroundStyle(LoreColor.bone.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(LoreColor.ink700)
            .frame(width: 1, height: 36)
    }
}

// MARK: - Category section

/// One category's worth of badges in a lazy grid. The category header carries a
/// glyph + human title; the grid flows three-up and never dumps text.
struct CategorySection: View {
    let section: PassportSection

    /// Flips on appear so the badges bloom in a stagger rather than being born
    /// already-landed (LUXURY-MOTION §6 "badges StaggeredReveal in").
    @State private var appeared = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LoreColor.brass300)
                Text(section.title)
                    .font(LoreType.display(size: 20, weight: .medium))
                    .foregroundStyle(LoreColor.bone)
                Spacer()
                Text("\(section.unlockedCount)/\(section.badges.count)")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.6))
            }
            .padding(.horizontal, 16)

            LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                ForEach(Array(section.badges.enumerated()), id: \.element.achievement.id) { pair in
                    AchievementBadge(
                        achievement: pair.element.achievement,
                        progress: pair.element.progress,
                        appeared: appeared,
                        revealDelay: LoreMotion.staggerDelay(index: pair.offset)
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        // Flip on appear so RevealBounce runs its entrance (a stagger under
        // motion, a crossfade under Reduce Motion, handled inside RevealBounce).
        .onAppear { appeared = true }
    }
}

// MARK: - View data

/// A badge paired with the user's progress row (nil ⇒ never started).
struct PassportBadge: Identifiable, Hashable {
    let achievement: Achievement
    let progress: UserAchievement?

    var id: String { achievement.slug }
    var isUnlocked: Bool { progress?.isUnlocked ?? false }
}

/// A resolved category section for the wall: title, glyph, and its badges in
/// catalog order.
struct PassportSection: Identifiable {
    let category: String
    let badges: [PassportBadge]

    var id: String { category }

    var unlockedCount: Int { badges.filter(\.isUnlocked).count }

    /// Human title for a category slug (falls back to a prettified slug).
    var title: String {
        switch category.lowercased() {
        case "milestone": return "Milestones"
        case "collector": return "Collector"
        case "city": return "Cities"
        case "knowledge": return "Knowledge"
        case "streak": return "Streaks"
        case "special": return "Special"
        default:
            return category
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    /// SF Symbol glyph per category.
    var symbol: String {
        switch category.lowercased() {
        case "milestone": return "flag.checkered"
        case "collector": return "square.grid.2x2"
        case "city": return "building.2"
        case "knowledge": return "book"
        case "streak": return "flame"
        case "special": return "sparkles"
        default: return "seal"
        }
    }
}

// MARK: - Model

/// Fetches the catalog + the user's rows, stitches them into sections, tracks
/// the celebration queue, and drives `recompute_achievements`. `@Observable`
/// + `@MainActor` matches the app's other feature models (ToursModel).
@Observable
@MainActor
final class PassportModel {
    enum State {
        case loading
        case empty
        case failed(String)
        case loaded
    }

    private(set) var state: State = .loading
    private(set) var sections: [PassportSection] = []
    /// Newly-unlocked badges waiting to be celebrated.
    private(set) var celebrating: [Achievement] = []

    /// The full catalog, cached for celebration lookups.
    private var catalog: [Achievement] = []
    private var loaded = false

    // MARK: Derived

    var totalCount: Int { catalog.count }
    var unlockedCount: Int { sections.reduce(0) { $0 + $1.unlockedCount } }

    /// Insight = sum of the points on every unlocked badge.
    private(set) var insightPoints: Int = 0

    /// The category display order (task spec order); anything unknown lands
    /// after, alphabetically, so a new DB category is never dropped.
    private static let categoryOrder = [
        "milestone", "collector", "city", "knowledge", "streak", "special",
    ]

    // MARK: Loading

    func loadIfNeeded(auth: AuthService) async {
        guard !loaded else { return }
        await load(auth: auth)
    }

    func load(auth: AuthService) async {
        state = .loading
        do {
            // Catalog is an anonymous read; the user's rows need a token.
            async let catalogTask = LoreAPI.shared.achievements()
            let userRows: [UserAchievement]
            if let token = auth.session?.accessToken {
                userRows = (try? await LoreAPI.shared.userAchievements(accessToken: token)) ?? []
            } else {
                userRows = []
            }
            let catalog = try await catalogTask

            self.catalog = catalog
            rebuild(catalog: catalog, userRows: userRows)
            loaded = true
            state = catalog.isEmpty ? .empty : .loaded
        } catch {
            state = .failed("Check your connection and try again.")
        }
    }

    /// Stitch catalog + user rows into grouped sections and re-tally Insight.
    private func rebuild(catalog: [Achievement], userRows: [UserAchievement]) {
        let byslug = Dictionary(
            userRows.map { ($0.achievementSlug, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let badges = catalog.map {
            PassportBadge(achievement: $0, progress: byslug[$0.slug])
        }

        // Insight = points of every unlocked badge.
        insightPoints = badges
            .filter(\.isUnlocked)
            .reduce(0) { $0 + $1.achievement.points }

        // Group by category, preserving catalog order within a section.
        let grouped = Dictionary(grouping: badges) {
            ($0.achievement.category ?? "special").lowercased()
        }

        let orderedKeys = grouped.keys.sorted { lhs, rhs in
            let li = Self.categoryOrder.firstIndex(of: lhs) ?? Int.max
            let ri = Self.categoryOrder.firstIndex(of: rhs) ?? Int.max
            if li != ri { return li < ri }
            return lhs < rhs
        }

        sections = orderedKeys.map { key in
            PassportSection(category: key, badges: grouped[key] ?? [])
        }
    }

    // MARK: Recompute + celebrate

    /// Recompute achievements after an activity (e.g. a logged visit), refresh
    /// the wall, and queue any newly-unlocked badges for the celebration
    /// overlay. No-op when signed out (no user to recompute for).
    func recomputeAndCelebrate(auth: AuthService) async {
        guard let token = auth.session?.accessToken,
              let userID = auth.session?.user.id else { return }
        do {
            let newlyUnlocked = try await LoreAPI.shared.recomputeAchievements(
                userID: userID,
                accessToken: token
            )
            // Pull fresh user rows so the wall reflects the new state.
            let userRows = (try? await LoreAPI.shared.userAchievements(accessToken: token)) ?? []
            rebuild(catalog: catalog, userRows: userRows)
            state = catalog.isEmpty ? .empty : .loaded

            if !newlyUnlocked.isEmpty {
                withAnimation(LoreMotion.unfurl) {
                    celebrating = newlyUnlocked
                }
            }
        } catch {
            // A recompute failure is silent, the wall stays as it was.
        }
    }

    /// Clear the celebration queue once the user dismisses the overlay.
    func dismissCelebration() {
        celebrating = []
    }
}
