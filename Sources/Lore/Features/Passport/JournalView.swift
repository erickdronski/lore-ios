import PhotosUI
import SwiftUI
import UIKit

/// One visit row from the server, with the place details and the user's own
/// note ("their lore"). Decoded from
/// `GET /visit?select=place_id,visited_at,note,place(name,emoji,city,kind)`.
struct VisitLogEntry: Decodable, Identifiable {
    let placeID: String
    let visitedAt: String
    let note: String?
    let photos: [String]?
    /// The visit row's own id (reports reference it; nil on local stubs).
    let visitID: String?
    /// Whether the author shared this lore publicly (opt-in, default private).
    let isPublic: Bool?
    /// Server-owned moderation status: visible | auto_hidden | removed | approved.
    let status: String?
    let place: EmbeddedPlace?

    struct EmbeddedPlace: Decodable {
        let name: String
        let emoji: String?
        let city: String?
        let kind: String?
    }

    var id: String { placeID }
    var photoPaths: [String] { photos ?? [] }
    var isShared: Bool { isPublic ?? false }
    /// Author-facing: their shared lore was hidden by moderation.
    var isHiddenByModeration: Bool {
        status == "auto_hidden" || status == "removed"
    }

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case visitedAt = "visited_at"
        case visitID = "id"
        case isPublic = "is_public"
        case note, photos, place, status
    }

    var displayName: String { place?.name ?? "A place" }
    var displayEmoji: String { (place?.emoji?.isEmpty == false ? place?.emoji : nil) ?? "📍" }
    var displayCity: String? { place?.city?.replacingOccurrences(of: "-", with: " ").capitalized }
    var displayKind: String { place?.kind?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Place" }

    var kindSymbol: String {
        switch place?.kind?.lowercased() {
        case "architecture", "building", "landmark": return "building.columns.fill"
        case "art", "museum": return "paintpalette.fill"
        case "food", "restaurant", "cafe": return "fork.knife"
        case "music", "venue": return "music.note"
        case "nature", "park": return "leaf.fill"
        case "history", "historic": return "clock.fill"
        case "viewpoint": return "binoculars.fill"
        case "market", "shopping": return "basket.fill"
        default: return "mappin.and.ellipse"
        }
    }

    /// A friendly date from the ISO timestamp.
    var dateLabel: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: visitedAt)
            ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.date(from: visitedAt) }()
        guard let date else { return "" }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        return out.string(from: date)
    }
}

/// The Journal: every place the user has marked "I've been here", newest first,
/// with the date and their own notes ("their lore"). Tap a row to write or edit
/// the note. Reached from the Passport, the retention hook the beta fleet asked
/// for, so a visit becomes a memory, not just a greyed-out pin.
struct JournalView: View {
    @Environment(VisitStore.self) private var visits
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing: VisitLogEntry?
    @State private var appeared = false

    private var noteCount: Int {
        visits.visitHistory.filter { $0.note?.isEmpty == false }.count
    }

    private var photoCount: Int {
        visits.visitHistory.reduce(0) { $0 + $1.photoPaths.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                journalMasthead
                    .padding(.top, 8)

                if !visits.canLogVisits {
                    hint(
                        title: "Your memories belong together",
                        text: "Sign in to keep a private journal of everywhere you've been and the notes you write.",
                        symbol: "person.crop.circle.badge.plus"
                    )
                } else if !visits.historyLoaded {
                    journalLoading
                } else if visits.visitHistory.isEmpty {
                    hint(
                        title: "Your first page is waiting",
                        text: "Mark a place \"I've been here\" and it lands here. Add the detail you never want to forget.",
                        symbol: "book.pages.fill"
                    )
                } else {
                    journeySummary
                    ForEach(Array(visits.visitHistory.enumerated()), id: \.element.id) { index, entry in
                        memoryRow(entry, index: index, isLast: index == visits.visitHistory.count - 1)
                            .revealBounce(
                                isActive: appeared,
                                delay: reduceMotion ? 0 : LoreMotion.staggerDelay(index: index),
                                fromScale: 0.94
                            )
                    }
                }
            }
            .padding(16)
        }
        .background(LoreColor.ink950.ignoresSafeArea())
        .task { await visits.loadHistory() }
        .refreshable { await visits.loadHistory(force: true) }
        .onAppear { appeared = true }
        .sheet(item: $editing) { entry in
            NoteEditorSheet(entry: entry) { note in
                await visits.saveNote(placeID: entry.placeID, note: note)
            }
        }
    }

    private var journalMasthead: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PRIVATE FIELD NOTES")
                    .font(LoreType.label)
                    .tracking(1)
                    .foregroundStyle(LoreColor.brass300)
                Text("Journal")
                    .font(LoreType.display(size: 34, weight: .bold))
                    .foregroundStyle(LoreColor.bone)
                Text("The world, as you remember it.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.68))
            }
            Spacer(minLength: 8)
            ZStack {
                Circle().fill(LoreColor.amber.opacity(0.13))
                Circle().strokeBorder(
                    LoreColor.brass300.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.2, dash: [2, 3])
                )
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(LoreColor.amber)
            }
            .frame(width: 58, height: 58)
            .rotationEffect(.degrees(-6))
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var journeySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("MEMORY LEDGER", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(LoreType.label)
                    .tracking(0.7)
                    .foregroundStyle(LoreColor.brass300)
                Spacer()
                Text("Newest first")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.55))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                journalStat(visits.visitHistory.count, "Places", "mappin.circle.fill")
                journalStat(noteCount, "Stories", "text.quote")
                journalStat(photoCount, "Photos", "photo.stack.fill")
            }
        }
        .padding(14)
        .background(LoreColor.ink900, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LoreColor.brass300.opacity(0.18), lineWidth: 1)
        )
    }

    private func journalStat(_ value: Int, _ label: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LoreColor.amber)
            Text("\(value)")
                .font(LoreType.display(size: 17, weight: .semibold))
                .foregroundStyle(LoreColor.bone)
            Text(label)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(LoreColor.ink800, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private func hint(title: String, text: String, symbol: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(LoreColor.amber.opacity(0.12))
                Circle().strokeBorder(
                    LoreColor.brass300.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(LoreColor.amber)
            }
            .frame(width: 64, height: 64)
            Text(title)
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)
                .multilineTextAlignment(.center)
            Text(text)
                .font(LoreType.body)
                .foregroundStyle(LoreColor.bone.opacity(0.68))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [LoreColor.ink800, LoreColor.ink900], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LoreColor.brass300.opacity(0.2), lineWidth: 1)
        )
    }

    private var journalLoading: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LoreColor.ink800)
                    .frame(height: 180)
                    .shimmer()
            }
        }
        .accessibilityLabel("Loading your journal")
    }

    private func memoryRow(_ entry: VisitLogEntry, index: Int, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            journeyThread(index: index, isLast: isLast)
            memoryCard(entry)
        }
    }

    private func journeyThread(index: Int, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(index == 0 ? LoreColor.amber : LoreColor.ink800)
                Circle().strokeBorder(LoreColor.brass300.opacity(0.7), lineWidth: 1)
                Image(systemName: index == 0 ? "location.fill" : "smallcircle.filled.circle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(index == 0 ? LoreColor.ink900 : LoreColor.brass300)
            }
            .frame(width: 28, height: 28)

            if !isLast {
                Rectangle()
                    .fill(LoreColor.brass300.opacity(0.24))
                    .frame(width: 1)
                    .frame(minHeight: 170)
            }
        }
        .accessibilityHidden(true)
    }

    private func memoryCard(_ entry: VisitLogEntry) -> some View {
        Button { editing = entry } label: {
            VStack(alignment: .leading, spacing: 10) {
                if entry.photoPaths.isEmpty {
                    JournalMemoryArtwork(entry: entry)
                } else {
                    photoStrip(entry)
                }

                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LoreColor.ink.opacity(0.07))
                        Text(entry.displayEmoji).font(.system(size: 23))
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName)
                            .font(LoreType.display(size: 17, weight: .semibold))
                            .foregroundStyle(LoreColor.ink)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            if let city = entry.displayCity {
                                Text(city).font(LoreType.caption).foregroundStyle(LoreColor.ink600)
                                Text("·").foregroundStyle(LoreColor.bone300)
                            }
                            Text(entry.dateLabel).font(LoreType.caption).foregroundStyle(LoreColor.ink600)
                        }
                    }
                    Spacer()
                    Image(systemName: (entry.note?.isEmpty == false) ? "square.and.pencil" : "plus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(LoreColor.brass700)
                }
                if let note = entry.note, !note.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LoreColor.brass700)
                        Text(note)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(LoreColor.ink.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LoreColor.bone200.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Label("Add what made this place memorable", systemImage: "plus")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.brass700)
                }

                HStack(spacing: 8) {
                    Label(entry.displayKind, systemImage: entry.kindSymbol)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                    Spacer()
                    if entry.isShared {
                        Label("Shared", systemImage: "person.2.fill")
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.success)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LoreColor.bone50))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LoreColor.bone300, lineWidth: 1)
            )
            .loreElevation(.elev1)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(memoryAccessibilityLabel(entry))
        .accessibilityHint("Opens this memory for editing")
    }

    private func photoStrip(_ entry: VisitLogEntry) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(entry.photoPaths.prefix(4).enumerated()), id: \.element) { index, path in
                    JournalPhotoThumb(path: path, size: index == 0 ? 104 : 88)
                        .rotationEffect(.degrees(reduceMotion ? 0 : (index.isMultiple(of: 2) ? -1.5 : 1.5)))
                }
                if entry.photoPaths.count > 4 {
                    Text("+\(entry.photoPaths.count - 4)")
                        .font(LoreType.display(size: 17, weight: .semibold))
                        .foregroundStyle(LoreColor.brass700)
                        .frame(width: 56, height: 88)
                        .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
        }
        .accessibilityLabel("\(entry.photoPaths.count) private photos")
    }

    private func memoryAccessibilityLabel(_ entry: VisitLogEntry) -> String {
        var parts = [entry.displayName]
        if let city = entry.displayCity { parts.append(city) }
        if !entry.dateLabel.isEmpty { parts.append(entry.dateLabel) }
        if let note = entry.note, !note.isEmpty { parts.append(note) }
        parts.append("\(entry.photoPaths.count) photos")
        if entry.isShared { parts.append("shared with travelers") }
        return parts.joined(separator: ", ")
    }
}

/// A local, content-aware memory illustration used when a traveler has not
/// attached a photo yet. The map route and kind glyph keep the card visual
/// without pretending we have imagery for the place.
private struct JournalMemoryArtwork: View {
    let entry: VisitLogEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [LoreColor.ink800, LoreColor.ink900],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                var route = Path()
                route.move(to: CGPoint(x: size.width * 0.05, y: size.height * 0.72))
                route.addCurve(
                    to: CGPoint(x: size.width * 0.92, y: size.height * 0.28),
                    control1: CGPoint(x: size.width * 0.32, y: size.height * 0.18),
                    control2: CGPoint(x: size.width * 0.62, y: size.height * 0.88)
                )
                context.stroke(
                    route,
                    with: .color(LoreColor.brass300.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 5])
                )
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayKind.uppercased())
                        .font(LoreType.label)
                        .tracking(0.8)
                        .foregroundStyle(LoreColor.brass300)
                    Text(entry.displayCity ?? "A place remembered")
                        .font(LoreType.display(size: 18, weight: .medium))
                        .foregroundStyle(LoreColor.bone)
                }
                Spacer()
                ZStack {
                    Circle().fill(LoreColor.amber.opacity(0.16))
                    Circle().strokeBorder(LoreColor.amber.opacity(0.7), lineWidth: 1)
                    Image(systemName: entry.kindSymbol)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(LoreColor.amber)
                }
                .frame(width: 58, height: 58)
            }
            .padding(14)
        }
        .frame(minHeight: 104)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// The note + photo editor: write "your lore" for a place and attach photos,
/// saved back to the visit (note via the closure, photos straight to Storage).
/// Internal (not private): the PlaceCard raises the same editor so a reader can
/// add their lore right where the place's story lives, not only from Passport.
struct NoteEditorSheet: View {
    let entry: VisitLogEntry
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(VisitStore.self) private var visits
    @State private var text: String
    @State private var picked: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false
    @State private var sheetError: String?
    @State private var suppressShareChange = false
    /// Opt-in public sharing; writes immediately (like photos), server-owned
    /// moderation status.
    @State private var isShared: Bool

    init(entry: VisitLogEntry, onSave: @escaping (String) async -> Bool) {
        self.entry = entry
        self.onSave = onSave
        _text = State(initialValue: entry.note ?? "")
        _isShared = State(initialValue: entry.isShared)
    }

    /// Live photos for this place from the store, so an upload shows immediately.
    private var photos: [String] {
        visits.visitHistory.first(where: { $0.placeID == entry.placeID })?.photoPaths ?? entry.photoPaths
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    editorMasthead

                    Label("YOUR FIELD NOTE", systemImage: "pencil.and.scribble")
                        .font(LoreType.label)
                        .tracking(0.7)
                        .foregroundStyle(LoreColor.brass700)
                    TextEditor(text: $text)
                        .font(LoreType.body)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 170)
                        .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(LoreColor.bone300, lineWidth: 1)
                        )
                        .accessibilityLabel("Field note")

                    HStack {
                        Label("PRIVATE PHOTOS", systemImage: "lock.fill")
                            .font(LoreType.label)
                            .tracking(0.6)
                            .foregroundStyle(LoreColor.ink600)
                        Spacer()
                        PhotosPicker(selection: $picked, matching: .images) {
                            HStack(spacing: 6) {
                                if uploading { ProgressView() } else { Image(systemName: "plus") }
                                Text("Add photo").font(LoreType.button)
                            }
                            .foregroundStyle(LoreColor.brass700)
                        }
                        .disabled(uploading)
                    }
                    if photos.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(LoreColor.brass700)
                            Text("Add a photo of the detail you want to remember. It stays private to you.")
                                .font(LoreType.caption)
                                .foregroundStyle(LoreColor.ink600)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LoreColor.bone200.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos, id: \.self) { path in
                                    JournalPhotoThumb(path: path, size: 96)
                                }
                            }
                        }
                    }

                    shareSection

                    if let sheetError {
                        Label(sheetError, systemImage: "exclamationmark.triangle.fill")
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .background(LoreColor.bone100)
            .navigationTitle("Your lore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            saving = true
                            sheetError = nil
                            let saved = await onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                            saving = false
                            if saved {
                                dismiss()
                            } else {
                                sheetError = visits.lastError ?? "Couldn't save your note."
                            }
                        }
                    }
                    .disabled(saving || uploading)
                }
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    uploading = true
                    sheetError = nil
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let jpeg = Self.downscaledJPEG(data) {
                        let added = await visits.addPhoto(placeID: entry.placeID, imageData: jpeg)
                        if !added { sheetError = visits.lastError ?? "Couldn't add that photo." }
                    } else {
                        sheetError = "That photo couldn't be prepared for upload."
                    }
                    picked = nil
                    uploading = false
                }
            }
        }
    }

    private var editorMasthead: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LoreColor.ink.opacity(0.07))
                Text(entry.displayEmoji).font(.system(size: 28))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(LoreType.display(size: 21, weight: .semibold))
                    .foregroundStyle(LoreColor.ink)
                HStack(spacing: 5) {
                    if let city = entry.displayCity { Text(city) }
                    if entry.displayCity != nil, !entry.dateLabel.isEmpty { Text("·") }
                    Text(entry.dateLabel)
                }
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
                Text("What you saw, who you were with, what it meant.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [LoreColor.bone50, LoreColor.bone200.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LoreColor.bone300, lineWidth: 1)
        )
    }

    /// The live history row for this place (fresher than the captured entry).
    private var liveEntry: VisitLogEntry {
        visits.visitHistory.first(where: { $0.placeID == entry.placeID }) ?? entry
    }

    /// Opt-in community sharing (Guideline 1.2 pairs this with report + block
    /// on the reading side). Default private; writes immediately like photos.
    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isShared) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share with all travelers")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink)
                    // v1 shares the NOTE only: journal photos live in a private
                    // bucket other readers can't load, so promising them here
                    // would be a lie until the public-photo path ships.
                    Text("Your note appears on this place for every traveler, under your display name. Photos stay private to you.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
            }
            .tint(LoreColor.brass700)
            .onChange(of: isShared) { _, newValue in
                if suppressShareChange {
                    suppressShareChange = false
                    return
                }
                Task {
                    sheetError = nil
                    let shared = await visits.setShared(placeID: entry.placeID, isPublic: newValue)
                    if !shared {
                        sheetError = visits.lastError ?? "Couldn't change sharing for that place."
                        suppressShareChange = true
                        isShared = !newValue
                    }
                }
            }
            if isShared {
                Text("Keep it kind and true. Lore that other travelers report is hidden while we review it; abusive content is removed.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
            if liveEntry.isHiddenByModeration {
                Label(
                    "This entry was reported and is hidden from other travelers while it's reviewed. You still see it here.",
                    systemImage: "eye.slash"
                )
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.error)
            }
        }
        .padding(12)
        .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Downscale + JPEG-encode the picked image so uploads stay small.
    static func downscaledJPEG(_ data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}

/// A private journal photo: resolves a short-lived signed URL for its storage
/// path (RLS-guarded to the owner) and loads it, with a quiet placeholder.
struct JournalPhotoThumb: View {
    @Environment(VisitStore.self) private var visits
    let path: String
    var size: CGFloat = 72
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(systemName: "exclamationmark.triangle")
                    case .empty:
                        placeholder(systemName: "photo")
                    @unknown default:
                        placeholder(systemName: "photo")
                    }
                }
            } else {
                placeholder(systemName: "photo")
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LoreColor.bone50, lineWidth: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LoreColor.bone300.opacity(0.8), lineWidth: 1)
        )
        .loreElevation(.elev1)
        .task(id: path) { url = await visits.signedPhotoURL(path: path) }
        .accessibilityLabel("Private journal photo")
    }

    private func placeholder(systemName: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [LoreColor.ink800, LoreColor.ink900],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LoreColor.brass300.opacity(0.75))
        }
    }
}
