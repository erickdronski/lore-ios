import SwiftUI

/// The global search sheet: a single field that queries the `search_lore` RPC
/// (debounced), grouping the ranked hits by kind (Cities / Places / People /
/// Stories / Tours). Tapping a row resolves a `LoreRoute` and hands it to the
/// injected router — the sheet dismisses itself and lets the host navigate.
///
/// Routing is *injected*, not hard-wired to `LoreApp.swift`: the host passes a
/// `handler` (or, in the app, the shared `AppRouter` via the initializer), so
/// this view never imports the tab structure it lives inside.
struct SearchView: View {
    /// Called with the resolved route when a result is tapped. The sheet
    /// dismisses first, then invokes this — the host decides what "open" means.
    let onSelect: (LoreRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = SearchModel()
    @FocusState private var searchFocused: Bool

    /// Hook the sheet to the shared router: taps drive `router.route(_:)`.
    init(router: AppRouter) {
        self.onSelect = { [weak router] route in router?.route(route) }
    }

    /// Hook the sheet to an arbitrary handler (previews / tests / a host that
    /// doesn't use `AppRouter`).
    init(onSelect: @escaping (LoreRoute) -> Void) {
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LoreColor.bone100.ignoresSafeArea()
                content
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .searchable(
            text: $model.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Cities, places, people, stories"
        )
        .onChange(of: model.query) { _, newValue in
            model.queryChanged(newValue)
        }
        .task { searchFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            ContentUnavailableView(
                "Search Lore",
                systemImage: "magnifyingglass",
                description: Text("Find a city to explore, a building's story, "
                    + "a local saying, or a curated walk.")
            )
        case .searching where model.groups.isEmpty:
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Search unavailable",
                systemImage: "wifi.exclamationmark",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView.search(text: model.query)
        case .searching, .loaded:
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            ForEach(model.groups, id: \.kind) { group in
                Section {
                    ForEach(group.results) { result in
                        Button {
                            select(result)
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(LoreColor.bone50)
                    }
                } header: {
                    Text(group.kind.sectionTitle)
                        .font(LoreType.label)
                        .tracking(0.6)
                        .foregroundStyle(LoreColor.ink600)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func select(_ result: SearchResult) {
        Haptics.play(.chipTap)
        let route = LoreRoute(result: result)
        dismiss()
        onSelect(route)
    }
}

// MARK: - Model

/// A kind-grouped bucket of results (Cities, Places, …) preserving the RPC's
/// intra-group rank order.
struct SearchGroup: Hashable {
    let kind: SearchResult.Kind
    let results: [SearchResult]
}

/// Drives the search sheet: holds the query, debounces RPC calls, and buckets
/// ranked results by kind. Debounce is a cancellable `Task.sleep` (no timers,
/// no Combine) — each keystroke cancels the last in-flight debounce.
@Observable
@MainActor
final class SearchModel {
    enum State: Equatable {
        /// No query yet — show the intro empty state.
        case idle
        /// A request is in flight (may already have stale `groups` to show).
        case searching
        /// Results present.
        case loaded
        /// Query ran, zero hits.
        case empty
        /// The RPC failed.
        case failed(String)
    }

    /// The live query text, bound to `.searchable`.
    var query: String = ""

    private(set) var state: State = .idle
    private(set) var groups: [SearchGroup] = []

    /// Debounce window — long enough to coalesce fast typing, short enough to
    /// feel live. `reveal.tap` is 120 ms; search debounce is a touch longer.
    private let debounce: Duration = .milliseconds(250)

    /// The in-flight debounce+search task, cancelled on every new keystroke.
    private var searchTask: Task<Void, Never>?

    /// Trailing-edge debounce: cancel the pending search, start a new one that
    /// waits `debounce` before hitting the network. An empty/blank query resets
    /// to idle immediately with no request.
    func queryChanged(_ raw: String) {
        searchTask?.cancel()

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            // Too short to be meaningful — clear results, go idle, no request.
            groups = []
            state = .idle
            return
        }

        state = .searching
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounce ?? .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.performSearch(trimmed)
        }
    }

    /// Fire the RPC and bucket the results. Guards against a stale response
    /// landing after the query moved on (compares against the current trimmed
    /// query) and against cancellation.
    private func performSearch(_ q: String) async {
        do {
            let results = try await LoreAPI.shared.search(q)
            guard !Task.isCancelled else { return }
            // Drop a late response whose query no longer matches the field.
            let current = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == q else { return }

            groups = Self.group(results)
            state = results.isEmpty ? .empty : .loaded
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed("Check your connection and try again.")
        }
    }

    /// Bucket ranked results by kind, preserving each group's internal rank
    /// order (results arrive highest-score-first) and ordering the groups by
    /// `Kind.sectionOrder` (Cities first).
    static func group(_ results: [SearchResult]) -> [SearchGroup] {
        let byKind = Dictionary(grouping: results, by: \.kind)
        return byKind
            .map { SearchGroup(kind: $0.key, results: $0.value) }
            .sorted { $0.kind.sectionOrder < $1.kind.sectionOrder }
    }
}
