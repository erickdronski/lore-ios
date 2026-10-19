import Foundation
import Observation

/// The production editor's operation boundary. All mutations are exclusive and
/// every suspension must still belong to the identity that opened the sheet.
@MainActor @Observable
final class JournalEditorState {
    enum Operation: Equatable {
        case save, upload, removePhoto, removeMemory
    }

    struct Dependencies {
        var currentUserID: () -> String?
        var saveNote: (String) async -> Bool
        var makePrivate: () async -> Bool
        var addPhoto: (Data) async -> String?
        var removePhoto: (String) async -> Bool
        var removeMemory: ([String]) async -> Bool
        var lastError: () -> String?
    }

    var text: String
    private(set) var persistedText: String
    private(set) var legacyShareWasPublic: Bool
    private(set) var operation: Operation?
    private(set) var error: String?
    private(set) var localPhotoPaths: [String] = []
    private(set) var pendingPhoto: Data?
    private(set) var removedPhotoPaths: Set<String> = []
    @ObservationIgnored private var dependencies: Dependencies?
    @ObservationIgnored private var editingUserID: String?
    @ObservationIgnored private var invalidated = false

    init(text: String, legacyShareWasPublic: Bool) {
        self.text = text
        self.persistedText = JournalDraftPolicy.normalized(text)
        self.legacyShareWasPublic = legacyShareWasPublic
    }

    var normalizedText: String { JournalDraftPolicy.normalized(text) }
    var hasUnsavedChanges: Bool { normalizedText != persistedText }
    var validationMessage: String? { JournalDraftPolicy.validationMessage(text: text) }
    var isBusy: Bool { operation != nil }
    var allowsInteractiveDismissal: Bool { !isBusy && !hasUnsavedChanges }
    var isCurrentIdentity: Bool {
        !invalidated && editingUserID != nil && dependencies?.currentUserID() == editingUserID
    }

    /// Connect once, when SwiftUI's environment is available. An invalidated
    /// editor can never attach its old draft to a new account.
    func connect(_ dependencies: Dependencies) {
        guard self.dependencies == nil, !invalidated else { return }
        self.dependencies = dependencies
        editingUserID = dependencies.currentUserID()
    }

    func invalidate() {
        invalidated = true
        dependencies = nil
        pendingPhoto = nil
        localPhotoPaths = []
    }

    func visiblePhotos(stored: [String]) -> [String] {
        var seen = Set<String>()
        return (stored + localPhotoPaths).filter {
            !removedPhotoPaths.contains($0) && seen.insert($0).inserted
        }
    }

    /// True means the current editor may dismiss. Failure leaves its draft and
    /// successful privacy cleanup intact, so retry only repeats unfinished work.
    func save() async -> Bool {
        guard validationMessage == nil, let dependencies = begin(.save) else { return false }
        defer { operation = nil }
        let desiredText = normalizedText
        if legacyShareWasPublic {
            let succeeded = await dependencies.makePrivate()
            guard canContinue else { return false }
            guard succeeded else {
                error = dependencies.lastError() ?? "Couldn't make that note private."
                return false
            }
            legacyShareWasPublic = false
        }
        if desiredText != persistedText {
            let succeeded = await dependencies.saveNote(desiredText)
            guard canContinue else { return false }
            guard succeeded else {
                error = dependencies.lastError() ?? "Couldn't save your note."
                return false
            }
            persistedText = desiredText
        }
        return canContinue
    }

    func upload(loadPreparedPhoto: () async throws -> Data?) async {
        guard let dependencies = begin(.upload) else { return }
        defer {
            operation = nil
            pendingPhoto = nil
        }
        do {
            let data = try await loadPreparedPhoto()
            guard canContinue else { return }
            guard let data else {
                error = "That photo couldn't be prepared for upload."
                return
            }
            pendingPhoto = data
            let path = await dependencies.addPhoto(data)
            guard canContinue else { return }
            guard let path else {
                error = dependencies.lastError() ?? "Couldn't add that photo."
                return
            }
            if !localPhotoPaths.contains(path) { localPhotoPaths.append(path) }
        } catch is CancellationError {
            return
        } catch {
            guard canContinue else { return }
            self.error = "That photo couldn't be prepared for upload."
        }
    }

    func removePhoto(path: String) async {
        guard let dependencies = begin(.removePhoto) else { return }
        defer { operation = nil }
        let succeeded = await dependencies.removePhoto(path)
        guard canContinue else { return }
        if succeeded {
            localPhotoPaths.removeAll { $0 == path }
            // Hide it even if a failed history refresh falls back to the entry
            // that originally opened the editor.
            removedPhotoPaths.insert(path)
        } else {
            error = dependencies.lastError() ?? "Couldn't remove that photo."
        }
    }

    func removeMemory(photoPaths: [String]) async -> Bool {
        guard let dependencies = begin(.removeMemory) else { return false }
        defer { operation = nil }
        let succeeded = await dependencies.removeMemory(photoPaths)
        guard canContinue else { return false }
        if !succeeded { error = dependencies.lastError() ?? "Couldn't remove that memory." }
        return succeeded
    }

    private var canContinue: Bool { isCurrentIdentity && !Task.isCancelled }

    private func begin(_ operation: Operation) -> Dependencies? {
        guard !isBusy, canContinue, let dependencies else { return nil }
        self.operation = operation
        error = nil
        return dependencies
    }
}

enum JournalDraftPolicy {
    static let maximumCharacters = 2_000

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validationMessage(text: String) -> String? {
        if text.count > maximumCharacters {
            return "Shorten this field note to \(maximumCharacters) characters before saving."
        }
        return nil
    }
}

