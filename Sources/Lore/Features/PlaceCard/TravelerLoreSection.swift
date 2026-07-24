import SwiftUI

/// The community layer on a place: other travelers' opt-in shared lore, from
/// the moderated `lore_public` view. Shows the three newest on the card with a
/// "See all" sheet, so a heavily-loved place never buries the place itself.
///
/// Guideline 1.2 pairing: every entry that isn't the reader's own carries
/// Report (reasoned, three distinct reports auto-hide server-side) and Block
/// (that author's lore never returns for this reader). Both need an account;
/// signed-out readers are routed to sign-in via `onNeedsSignIn`.
struct TravelerLoreSection: View {
    let placeID: String
    /// Raise the host's sign-in sheet (report/block need an account).
    var onNeedsSignIn: () -> Void = {}

    @Environment(AuthService.self) private var auth

    @State private var entries: [PublicLore] = []
    @State private var loaded = false
    @State private var showAll = false
    /// Entries reported this session, hidden optimistically with a thank-you.
    @State private var reportedIDs: Set<String> = []
    /// The entry a report dialog is open for.
    @State private var reporting: PublicLore?

    /// How many entries render inline on the card before "See all".
    private static let inlineCount = 3

    var body: some View {
        Group {
            if !visibleEntries.isEmpty {
                section
            } else {
                // A zero-size anchor, NOT an absent view: `.task` only fires on
                // a view that appears, and an empty Group never appears — which
                // would mean the fetch below never runs and the section could
                // never learn it has entries to show.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .task(id: placeID) { await load() }
        .sheet(isPresented: $showAll) { allSheet }
        .confirmationDialog(
            "Report this lore?",
            isPresented: reportDialogBinding,
            titleVisibility: .visible
        ) {
            reportButtons
        } message: {
            Text("Reported lore is hidden while we review it.")
        }
    }

    // MARK: Data

    /// Everyone else's visible entries: the reader's own lore already renders
    /// as YOUR LORE above, and optimistically-reported rows drop immediately.
    private var visibleEntries: [PublicLore] {
        entries.filter { entry in
            entry.authorID != auth.session?.user.id && !reportedIDs.contains(entry.id)
        }
    }

    private func load() async {
        let token = await auth.validAccessToken()
        do {
            entries = try await LoreAPI.shared.publicLore(placeID: placeID, accessToken: token)
        } catch {
            // Quiet in production (the section just self-hides); loud in DEBUG
            // so a contract drift with `lore_public` can never fail silently.
            #if DEBUG
            print("TravelerLore load failed for \(placeID): \(error)")
            #endif
            entries = []
        }
        loaded = true
    }

    // MARK: Card section

    private var section: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TRAVELER LORE")
                    .loreLabelStyle()
                    .foregroundStyle(LoreColor.brass700)
                Spacer()
                if visibleEntries.count > Self.inlineCount {
                    Button {
                        Haptics.play(.chipTap)
                        showAll = true
                    } label: {
                        Text("See all \(visibleEntries.count)")
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.brass700)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(visibleEntries.prefix(Self.inlineCount)) { entry in
                row(entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
    }

    /// The full list, for places with more lore than the card should carry.
    private var allSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleEntries) { entry in
                        row(entry)
                            .padding(12)
                            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
            }
            .background(LoreColor.bone100)
            .navigationTitle("Traveler lore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { showAll = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Rows

    private func row(_ entry: PublicLore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.displayName)
                    .font(LoreType.display(size: 14, weight: .semibold))
                    .foregroundStyle(LoreColor.ink)
                if !entry.dateLabel.isEmpty {
                    Text("· \(entry.dateLabel)")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
                Spacer()
                rowMenu(entry)
            }
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Report / block, the 1.2 pair. Needs an account so reports are
    /// attributable and rate-limitable; signed-out taps route to sign-in.
    private func rowMenu(_ entry: PublicLore) -> some View {
        Menu {
            Button(role: .destructive) {
                if auth.isSignedIn { reporting = entry } else { onNeedsSignIn() }
            } label: {
                Label("Report this lore", systemImage: "flag")
            }
            Button(role: .destructive) {
                if auth.isSignedIn {
                    Task { await block(entry) }
                } else {
                    onNeedsSignIn()
                }
            } label: {
                Label("Block this traveler", systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LoreColor.ink600)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Report or block")
    }

    // MARK: Report / block actions

    private var reportDialogBinding: Binding<Bool> {
        Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })
    }

    @ViewBuilder
    private var reportButtons: some View {
        ForEach(["Inappropriate content", "Spam", "False information", "Harassment"], id: \.self) { reason in
            Button(reason, role: .destructive) {
                if let entry = reporting { Task { await report(entry, reason: reason) } }
            }
        }
        Button("Cancel", role: .cancel) { reporting = nil }
    }

    private func report(_ entry: PublicLore, reason: String) async {
        reporting = nil
        guard let token = await auth.validAccessToken(),
              let reporterID = auth.session?.user.id else { return }
        do {
            try await TravelReads.reportLore(
                visitID: entry.id, reason: reason, reporterID: reporterID, accessToken: token
            )
            Haptics.play(.chipTap)
            reportedIDs.insert(entry.id)
        } catch {
            // Leave the row visible; the reader can retry from the menu.
        }
    }

    private func block(_ entry: PublicLore) async {
        guard let token = await auth.validAccessToken(),
              let blockerID = auth.session?.user.id else { return }
        do {
            try await TravelReads.blockAuthor(
                blockerID: blockerID, blockedID: entry.authorID, accessToken: token
            )
            Haptics.play(.chipTap)
            // The server's view filters this author from now on; refetch so
            // every entry of theirs drops, not just this row.
            await load()
        } catch {
            // Non-fatal; the row stays until a retry succeeds.
        }
    }
}
