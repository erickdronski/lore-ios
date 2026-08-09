import SwiftUI

/// Profile's future-tense travel list: places the traveler saved to revisit,
/// plan around, or share into a route later.
struct SavedPlacesView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SavedPlaceStore.self) private var savedPlaces

    @State private var selectedPlace: Place?
    @State private var openingPlaceID: String?
    @State private var showSignIn = false
    @State private var openError: String?

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !auth.isSignedIn {
                signedOutState
            } else if !savedPlaces.loaded {
                loadingState
            } else if savedPlaces.entries.isEmpty {
                emptyState
            } else {
                Section {
                    ForEach(savedPlaces.entries) { entry in
                        SavedPlaceRow(
                            entry: entry,
                            isOpening: openingPlaceID == entry.placeID,
                            open: { Task { await open(entry) } },
                            remove: { Task { await savedPlaces.remove(placeID: entry.placeID) } }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LoreColor.bone100.ignoresSafeArea())
        .navigationTitle("Saved places")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: auth.session?.user.id) {
            await savedPlaces.load(force: true)
        }
        .refreshable {
            guard auth.isSignedIn else { return }
            await savedPlaces.load(force: true)
        }
        .loreDossierPresentation(item: $selectedPlace) { place in
            PlaceCardView(place: place)
        }
        .sheet(isPresented: $showSignIn) {
            SignInView()
                .presentationDetents([.large])
        }
        .alert("Couldn't open that place", isPresented: openErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openError ?? "Try again in a moment.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LoreColor.amber.opacity(0.16))
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(LoreColor.brass700)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Want-to-go list")
                        .font(LoreType.displayM)
                        .foregroundStyle(LoreColor.ink)
                    Text(headerSubtitle)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LoreColor.bone, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LoreColor.bone300))
    }

    private var headerSubtitle: String {
        guard auth.isSignedIn else {
            return "Sign in to keep the places you want to revisit on every device."
        }
        let count = savedPlaces.savedCount
        if count == 0 { return "Save places from any dossier and build tomorrow's walk." }
        return "\(count) saved \(count == 1 ? "place" : "places") ready for your next walk."
    }

    private var signedOutState: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save the next place before you arrive.")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.ink)
                Text("Browsing stays free. An account lets Lore sync the places you want to come back to.")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showSignIn = true
                } label: {
                    Text("Sign in")
                        .font(LoreType.button)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .foregroundStyle(LoreColor.bone)
                .background(LoreColor.ink, in: Capsule())
                .buttonStyle(.pressable)
            }
            .padding(.vertical, 6)
        }
    }

    private var loadingState: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading your saved places...")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink600)
            }
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(LoreColor.brass700)
                Text("No saved places yet")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.ink)
                Text("Open any place card and tap the bookmark. Lore will keep it here as your planning list.")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
        }
    }

    private func open(_ entry: SavedPlace) async {
        guard openingPlaceID == nil else { return }
        openingPlaceID = entry.placeID
        defer { openingPlaceID = nil }
        do {
            if let place = try await LoreAPI.shared.place(id: entry.placeID) {
                selectedPlace = place
            } else {
                openError = "That saved place is no longer published."
            }
        } catch {
            openError = error.localizedDescription
        }
    }

    private var openErrorBinding: Binding<Bool> {
        Binding(
            get: { openError != nil },
            set: { if !$0 { openError = nil } }
        )
    }
}

private struct SavedPlaceRow: View {
    let entry: SavedPlace
    let isOpening: Bool
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 12) {
                Text(entry.displayEmoji)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(LoreColor.bone200, in: Circle())
                    .overlay(Circle().strokeBorder(LoreColor.brass700.opacity(0.2)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.displayName)
                        .font(LoreType.body.weight(.semibold))
                        .foregroundStyle(LoreColor.ink)
                        .lineLimit(2)
                    Text(detail)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if isOpening {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LoreColor.ink600)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: remove) {
                Label("Remove", systemImage: "bookmark.slash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.displayName), \(detail)")
    }

    private var detail: String {
        let bits = [entry.displayKind, entry.displayCity, savedLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return bits.joined(separator: " · ")
    }

    private var savedLabel: String? {
        guard let date = entry.savedDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Saved \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
