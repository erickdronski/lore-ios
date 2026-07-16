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
    let place: EmbeddedPlace?

    struct EmbeddedPlace: Decodable {
        let name: String
        let emoji: String?
        let city: String?
        let kind: String?
    }

    var id: String { placeID }
    var photoPaths: [String] { photos ?? [] }

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case visitedAt = "visited_at"
        case note, photos, place
    }

    var displayName: String { place?.name ?? "A place" }
    var displayEmoji: String { (place?.emoji?.isEmpty == false ? place?.emoji : nil) ?? "📍" }
    var displayCity: String? { place?.city?.replacingOccurrences(of: "-", with: " ").capitalized }

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
    @State private var editing: VisitLogEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Journal")
                    .font(LoreType.display(size: 32, weight: .bold))
                    .foregroundStyle(LoreColor.bone)
                    .padding(.top, 8)

                if !visits.canLogVisits {
                    hint("Sign in to keep a journal of everywhere you've been and the notes you write.")
                } else if !visits.historyLoaded {
                    ProgressView().tint(LoreColor.brass).frame(maxWidth: .infinity).padding(.top, 40)
                } else if visits.visitHistory.isEmpty {
                    hint("Mark places \"I've been here\" and they land here. Add your own notes and memories to each one.")
                } else {
                    Text("\(visits.visitHistory.count) place\(visits.visitHistory.count == 1 ? "" : "s") logged")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                    ForEach(visits.visitHistory) { entry in
                        row(entry)
                    }
                }
            }
            .padding(16)
        }
        .background(LoreColor.ink950.ignoresSafeArea())
        .task { await visits.loadHistory() }
        .sheet(item: $editing) { entry in
            NoteEditorSheet(entry: entry) { note in
                Task { await visits.saveNote(placeID: entry.placeID, note: note) }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(LoreType.body)
            .foregroundStyle(LoreColor.ink600)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 24)
    }

    private func row(_ entry: VisitLogEntry) -> some View {
        Button { editing = entry } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(entry.displayEmoji)
                        .font(.system(size: 24))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LoreColor.ink800))
                        .overlay(Circle().strokeBorder(LoreColor.brass300.opacity(0.4), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName)
                            .font(LoreType.display(size: 17, weight: .semibold))
                            .foregroundStyle(LoreColor.bone)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let city = entry.displayCity {
                                Text(city).font(LoreType.caption).foregroundStyle(LoreColor.ink600)
                                Text("·").foregroundStyle(LoreColor.ink700)
                            }
                            Text(entry.dateLabel).font(LoreType.caption).foregroundStyle(LoreColor.ink600)
                        }
                    }
                    Spacer()
                    Image(systemName: (entry.note?.isEmpty == false) ? "square.and.pencil" : "plus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(LoreColor.amber)
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.bone.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text("Add your notes and photos")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
                if !entry.photoPaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(entry.photoPaths, id: \.self) { path in
                                JournalPhotoThumb(path: path, size: 72)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(LoreColor.ink900))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LoreColor.ink700, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// The note + photo editor: write "your lore" for a place and attach photos,
/// saved back to the visit (note via the closure, photos straight to Storage).
/// Internal (not private): the PlaceCard raises the same editor so a reader can
/// add their lore right where the place's story lives, not only from Passport.
struct NoteEditorSheet: View {
    let entry: VisitLogEntry
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(VisitStore.self) private var visits
    @State private var text: String
    @State private var picked: PhotosPickerItem?
    @State private var uploading = false

    init(entry: VisitLogEntry, onSave: @escaping (String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _text = State(initialValue: entry.note ?? "")
    }

    /// Live photos for this place from the store, so an upload shows immediately.
    private var photos: [String] {
        visits.visitHistory.first(where: { $0.placeID == entry.placeID })?.photoPaths ?? entry.photoPaths
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Text(entry.displayEmoji).font(.system(size: 26))
                        Text(entry.displayName)
                            .font(LoreType.display(size: 20, weight: .semibold))
                            .foregroundStyle(LoreColor.ink)
                    }
                    Text("Your lore, what you saw, who you were with, what it meant.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                    TextEditor(text: $text)
                        .font(LoreType.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 150)
                        .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))

                    HStack {
                        Text("PHOTOS").font(LoreType.label).tracking(0.6).foregroundStyle(LoreColor.ink600)
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
                        Text("Add photos of this spot to remember it.")
                            .font(LoreType.caption).foregroundStyle(LoreColor.ink600)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos, id: \.self) { path in
                                    JournalPhotoThumb(path: path, size: 96)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .background(LoreColor.bone100)
            .navigationTitle("Your lore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    uploading = true
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let jpeg = Self.downscaledJPEG(data) {
                        await visits.addPhoto(placeID: entry.placeID, imageData: jpeg)
                    }
                    picked = nil
                    uploading = false
                }
            }
        }
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
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        LoreColor.ink800
                    }
                }
            } else {
                LoreColor.ink800
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: path) { url = await visits.signedPhotoURL(path: path) }
    }
}
