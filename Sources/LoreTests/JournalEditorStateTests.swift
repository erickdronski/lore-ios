import XCTest
@testable import Lore

/// These exercise the same coordinator and operation closures used by the
/// editor, with deterministic suspension points instead of a live account.
@MainActor
final class JournalEditorStateTests: XCTestCase {
    func testSaveWaitsForPrivacyCleanupThenNoteAndRejectsDuplicateWork() async {
        let privacy = Suspended<Bool>()
        let note = Suspended<Bool>()
        var writes: [String] = []
        var otherWrites = 0
        let editor = makeEditor(
            legacy: true,
            saveNote: { writes.append($0); return await note.value() },
            makePrivate: { await privacy.value() },
            removePhoto: { _ in otherWrites += 1; return true }
        )
        editor.text = "  A new memory  "
        let save = Task { await editor.save() }
        await fulfillment(of: [privacy.started], timeout: 2)

        XCTAssertEqual(editor.operation, .save)
        XCTAssertFalse(editor.allowsInteractiveDismissal)
        XCTAssertTrue(writes.isEmpty)
        let duplicate = await editor.save()
        await editor.removePhoto(path: "photo")
        XCTAssertFalse(duplicate)
        XCTAssertEqual(otherWrites, 0)

        privacy.resume(true)
        await fulfillment(of: [note.started], timeout: 2)
        XCTAssertEqual(writes, ["A new memory"])
        XCTAssertFalse(editor.legacyShareWasPublic)
        XCTAssertEqual(editor.persistedText, "Original")
        XCTAssertTrue(editor.isBusy)
        note.resume(true)
        let mayDismiss = await save.value
        XCTAssertTrue(mayDismiss)
        XCTAssertEqual(editor.persistedText, "A new memory")
        XCTAssertFalse(editor.isBusy)
        XCTAssertTrue(editor.allowsInteractiveDismissal)
    }

    func testPrivacyFailurePreservesDraftAndRetryCompletesBothWrites() async {
        var privacyCalls = 0
        var notes: [String] = []
        let editor = makeEditor(
            legacy: true,
            saveNote: { notes.append($0); return true },
            makePrivate: { privacyCalls += 1; return privacyCalls > 1 },
            lastError: { "Privacy request failed" }
        )
        editor.text = "Keep this draft"
        let first = await editor.save()
        XCTAssertFalse(first)
        XCTAssertEqual(editor.text, "Keep this draft")
        XCTAssertEqual(editor.error, "Privacy request failed")
        XCTAssertTrue(editor.legacyShareWasPublic)
        XCTAssertTrue(notes.isEmpty)
        XCTAssertFalse(editor.isBusy)

        let retry = await editor.save()
        XCTAssertTrue(retry)
        XCTAssertEqual(privacyCalls, 2)
        XCTAssertEqual(notes, ["Keep this draft"])
        XCTAssertNil(editor.error)
    }

    func testNoteFailureRetainsDraftAndDoesNotRepeatSuccessfulPrivacyCleanup() async {
        var privacyCalls = 0
        var noteCalls = 0
        let editor = makeEditor(
            legacy: true,
            saveNote: { _ in noteCalls += 1; return noteCalls > 1 },
            makePrivate: { privacyCalls += 1; return true }
        )
        editor.text = "Changed"
        let first = await editor.save()
        XCTAssertFalse(first)
        XCTAssertEqual(editor.text, "Changed")
        XCTAssertEqual(editor.persistedText, "Original")
        XCTAssertEqual(editor.error, "Couldn't save your note.")
        XCTAssertFalse(editor.allowsInteractiveDismissal)
        let retry = await editor.save()
        XCTAssertTrue(retry)
        XCTAssertEqual(privacyCalls, 1)
        XCTAssertEqual(noteCalls, 2)
        XCTAssertNil(editor.error)
    }

    func testUnchangedNoteOnlyClearsLegacyPrivacyFlag() async {
        var notes = 0
        var privacy = 0
        let editor = makeEditor(
            legacy: true,
            saveNote: { _ in notes += 1; return true },
            makePrivate: { privacy += 1; return true }
        )
        editor.text = "  Original\n"
        let mayDismiss = await editor.save()
        XCTAssertTrue(mayDismiss)
        XCTAssertEqual(privacy, 1)
        XCTAssertEqual(notes, 0)
    }

    func testInvalidDraftDoesNotStartWritesOrGetStuckBusy() async {
        var calls = 0
        let editor = makeEditor(saveNote: { _ in calls += 1; return true })
        editor.text = String(repeating: "x", count: JournalDraftPolicy.maximumCharacters + 1)
        let mayDismiss = await editor.save()
        XCTAssertFalse(mayDismiss)
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(editor.validationMessage)
        XCTAssertFalse(editor.isBusy)
    }

    func testUploadWaitsForPreparationAndDurablePathAndBlocksEveryOtherMutation() async {
        let preparation = Suspended<Data?>()
        let storage = Suspended<String?>()
        var uploadBytes: [Data] = []
        var competingWrites = 0
        let editor = makeEditor(
            saveNote: { _ in competingWrites += 1; return true },
            addPhoto: { uploadBytes.append($0); return await storage.value() },
            removePhoto: { _ in competingWrites += 1; return true },
            removeMemory: { _ in competingWrites += 1; return true }
        )
        let upload = Task { await editor.upload { await preparation.value() } }
        await fulfillment(of: [preparation.started], timeout: 2)
        XCTAssertEqual(editor.operation, .upload)
        XCTAssertFalse(editor.allowsInteractiveDismissal)
        XCTAssertNil(editor.pendingPhoto)
        editor.text = "Draft still here"
        let save = await editor.save()
        let delete = await editor.removeMemory(photoPaths: [])
        await editor.removePhoto(path: "old")
        await editor.upload { competingWrites += 1; return Data([8]) }
        XCTAssertFalse(save)
        XCTAssertFalse(delete)
        XCTAssertEqual(competingWrites, 0)

        preparation.resume(Data([1, 2, 3]))
        await fulfillment(of: [storage.started], timeout: 2)
        XCTAssertEqual(editor.pendingPhoto, Data([1, 2, 3]))
        XCTAssertEqual(uploadBytes, [Data([1, 2, 3])])
        XCTAssertTrue(editor.localPhotoPaths.isEmpty)
        XCTAssertTrue(editor.isBusy)
        storage.resume("owner/place/photo.jpg")
        await upload.value
        XCTAssertNil(editor.pendingPhoto)
        XCTAssertFalse(editor.isBusy)
        XCTAssertEqual(editor.text, "Draft still here")
        XCTAssertEqual(editor.visiblePhotos(stored: ["owner/place/photo.jpg"]), ["owner/place/photo.jpg"])
    }

    func testPreparationFailureResetsBusyAndCanRetry() async {
        var uploads = 0
        let editor = makeEditor(addPhoto: { _ in uploads += 1; return "photo" })
        await editor.upload { nil }
        XCTAssertEqual(editor.error, "That photo couldn't be prepared for upload.")
        XCTAssertFalse(editor.isBusy)
        XCTAssertEqual(uploads, 0)
        await editor.upload { Data([1]) }
        XCTAssertNil(editor.error)
        XCTAssertEqual(editor.localPhotoPaths, ["photo"])
        XCTAssertEqual(uploads, 1)
    }

    func testThrownPreparationFailurePreservesDraftAndAllowsRetry() async {
        let editor = makeEditor()
        editor.text = "Unsaved"
        await editor.upload { throw TestError.failed }
        XCTAssertEqual(editor.text, "Unsaved")
        XCTAssertEqual(editor.error, "That photo couldn't be prepared for upload.")
        XCTAssertNil(editor.pendingPhoto)
        XCTAssertFalse(editor.isBusy)
        await editor.upload { Data([1]) }
        XCTAssertNil(editor.error)
    }

    func testUploadFailureDropsOnlyPendingPreviewAndRetrySucceeds() async {
        var calls = 0
        let editor = makeEditor(addPhoto: { _ in calls += 1; return calls > 1 ? "photo" : nil })
        editor.text = "Unsaved"
        await editor.upload { Data([1]) }
        XCTAssertEqual(editor.text, "Unsaved")
        XCTAssertEqual(editor.error, "Couldn't add that photo.")
        XCTAssertNil(editor.pendingPhoto)
        XCTAssertTrue(editor.localPhotoPaths.isEmpty)
        XCTAssertFalse(editor.isBusy)
        await editor.upload { Data([1]) }
        XCTAssertEqual(editor.localPhotoPaths, ["photo"])
        XCTAssertNil(editor.error)
    }

    func testPhotoRemovalBlocksDismissalAndDoesNotReappearFromStaleEntry() async {
        let removal = Suspended<Bool>()
        var saves = 0
        let editor = makeEditor(
            saveNote: { _ in saves += 1; return true },
            removePhoto: { _ in await removal.value() }
        )
        let task = Task { await editor.removePhoto(path: "photo") }
        await fulfillment(of: [removal.started], timeout: 2)
        XCTAssertEqual(editor.operation, .removePhoto)
        XCTAssertFalse(editor.allowsInteractiveDismissal)
        XCTAssertEqual(editor.visiblePhotos(stored: ["photo", "other"]), ["photo", "other"])
        let save = await editor.save()
        XCTAssertFalse(save)
        XCTAssertEqual(saves, 0)
        removal.resume(true)
        await task.value
        XCTAssertEqual(editor.visiblePhotos(stored: ["photo", "other"]), ["other"])
        XCTAssertTrue(editor.allowsInteractiveDismissal)
    }

    func testPhotoRemovalFailureRetainsPhotoAndRetryRemovesIt() async {
        var calls = 0
        let editor = makeEditor(removePhoto: { _ in calls += 1; return calls > 1 })
        await editor.removePhoto(path: "photo")
        XCTAssertEqual(editor.visiblePhotos(stored: ["photo"]), ["photo"])
        XCTAssertEqual(editor.error, "Couldn't remove that photo.")
        XCTAssertFalse(editor.isBusy)
        await editor.removePhoto(path: "photo")
        XCTAssertTrue(editor.visiblePhotos(stored: ["photo"]).isEmpty)
        XCTAssertNil(editor.error)
    }

    func testMemoryRemovalWaitsBeforeAllowingDismissal() async {
        let removal = Suspended<Bool>()
        var received: [String] = []
        let editor = makeEditor(removeMemory: { received = $0; return await removal.value() })
        let task = Task { await editor.removeMemory(photoPaths: ["one", "two"]) }
        await fulfillment(of: [removal.started], timeout: 2)
        XCTAssertEqual(received, ["one", "two"])
        XCTAssertEqual(editor.operation, .removeMemory)
        XCTAssertFalse(editor.allowsInteractiveDismissal)
        let duplicate = await editor.removeMemory(photoPaths: [])
        let save = await editor.save()
        XCTAssertFalse(duplicate)
        XCTAssertFalse(save)
        removal.resume(true)
        let mayDismiss = await task.value
        XCTAssertTrue(mayDismiss)
        XCTAssertFalse(editor.isBusy)
    }

    func testMemoryRemovalFailurePreservesDraftAndCanRetry() async {
        var calls = 0
        let editor = makeEditor(removeMemory: { _ in calls += 1; return calls > 1 })
        editor.text = "Unsaved"
        let first = await editor.removeMemory(photoPaths: ["photo"])
        XCTAssertFalse(first)
        XCTAssertEqual(editor.text, "Unsaved")
        XCTAssertEqual(editor.error, "Couldn't remove that memory.")
        XCTAssertFalse(editor.isBusy)
        let retry = await editor.removeMemory(photoPaths: ["photo"])
        XCTAssertTrue(retry)
        XCTAssertNil(editor.error)
    }

    func testIdentityChangeDuringPreparationNeverUploadsIntoNewAccount() async {
        let preparation = Suspended<Data?>()
        var identity: String? = "A"
        var uploads = 0
        let editor = makeEditor(currentUserID: { identity }, addPhoto: { _ in uploads += 1; return "photo" })
        let task = Task { await editor.upload { await preparation.value() } }
        await fulfillment(of: [preparation.started], timeout: 2)
        identity = "B"
        preparation.resume(Data([1]))
        await task.value
        XCTAssertEqual(uploads, 0)
        XCTAssertTrue(editor.localPhotoPaths.isEmpty)
        XCTAssertNil(editor.error)
        XCTAssertNil(editor.pendingPhoto)
    }

    func testIdentityChangeDuringUploadIgnoresLatePath() async {
        let storage = Suspended<String?>()
        var identity: String? = "A"
        let editor = makeEditor(currentUserID: { identity }, addPhoto: { _ in await storage.value() })
        let task = Task { await editor.upload { Data([1]) } }
        await fulfillment(of: [storage.started], timeout: 2)
        identity = nil
        editor.invalidate()
        XCTAssertNil(editor.pendingPhoto)
        storage.resume("A/private/photo")
        await task.value
        XCTAssertTrue(editor.localPhotoPaths.isEmpty)
        XCTAssertNil(editor.error)
    }

    func testIdentityChangeDuringPrivacyCleanupDoesNotSaveNoteOrDismiss() async {
        let privacy = Suspended<Bool>()
        var identity: String? = "A"
        var notes = 0
        let editor = makeEditor(
            legacy: true, currentUserID: { identity },
            saveNote: { _ in notes += 1; return true },
            makePrivate: { await privacy.value() }
        )
        editor.text = "Unsaved"
        let task = Task { await editor.save() }
        await fulfillment(of: [privacy.started], timeout: 2)
        identity = "B"
        privacy.resume(true)
        let mayDismiss = await task.value
        XCTAssertFalse(mayDismiss)
        XCTAssertEqual(notes, 0)
        XCTAssertTrue(editor.legacyShareWasPublic)
        XCTAssertEqual(editor.persistedText, "Original")
        XCTAssertNil(editor.error)
    }

    func testIdentityChangeDuringNoteWriteDoesNotCommitDraftOrDismiss() async {
        let note = Suspended<Bool>()
        var identity: String? = "A"
        let editor = makeEditor(currentUserID: { identity }, saveNote: { _ in await note.value() })
        editor.text = "Unsaved"
        let task = Task { await editor.save() }
        await fulfillment(of: [note.started], timeout: 2)
        identity = "B"
        note.resume(true)
        let mayDismiss = await task.value
        XCTAssertFalse(mayDismiss)
        XCTAssertEqual(editor.persistedText, "Original")
        XCTAssertEqual(editor.text, "Unsaved")
        XCTAssertNil(editor.error)
    }

    func testInvalidatedEditorCannotResumeEvenIfSameAccountReturns() async {
        let removal = Suspended<Bool>()
        var identity: String? = "A"
        let editor = makeEditor(currentUserID: { identity }, removeMemory: { _ in await removal.value() })
        let task = Task { await editor.removeMemory(photoPaths: []) }
        await fulfillment(of: [removal.started], timeout: 2)
        identity = "B"
        editor.invalidate()
        identity = "A"
        removal.resume(true)
        let mayDismiss = await task.value
        let save = await editor.save()
        XCTAssertFalse(mayDismiss)
        XCTAssertFalse(save)
        XCTAssertFalse(editor.isCurrentIdentity)
        XCTAssertNil(editor.error)
    }

    func testIdentityChangeDuringPhotoRemovalDoesNotChangeNewIdentityState() async {
        let removal = Suspended<Bool>()
        var identity: String? = "A"
        let editor = makeEditor(currentUserID: { identity }, removePhoto: { _ in await removal.value() })
        let task = Task { await editor.removePhoto(path: "photo") }
        await fulfillment(of: [removal.started], timeout: 2)
        identity = "B"
        removal.resume(false)
        await task.value
        XCTAssertTrue(editor.removedPhotoPaths.isEmpty)
        XCTAssertNil(editor.error)
    }

    func testCancellationDuringPreparationNeverUploadsAndDoesNotShowAnError() async {
        let preparation = Suspended<Data?>()
        var uploads = 0
        let editor = makeEditor(addPhoto: { _ in uploads += 1; return "photo" })
        let task = Task { await editor.upload { await preparation.value() } }
        await fulfillment(of: [preparation.started], timeout: 2)
        task.cancel()
        preparation.resume(Data([1]))
        await task.value
        XCTAssertEqual(uploads, 0)
        XCTAssertNil(editor.error)
        XCTAssertNil(editor.pendingPhoto)
        XCTAssertFalse(editor.isBusy)
    }

    func testSignedOutEditorCannotStartMutations() async {
        var calls = 0
        let editor = makeEditor(currentUserID: { nil }, addPhoto: { _ in calls += 1; return "photo" })
        await editor.upload { calls += 1; return Data([1]) }
        let save = await editor.save()
        XCTAssertFalse(save)
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(editor.isBusy)
    }

    func testInvalidationReleasesStoredOperationDependencies() async {
        final class LifetimeProbe {}
        weak var retainedProbe: LifetimeProbe?
        let editor = JournalEditorState(text: "Original", legacyShareWasPublic: false)
        do {
            let probe = LifetimeProbe()
            retainedProbe = probe
            editor.connect(.init(
                currentUserID: { "owner" },
                saveNote: { [probe] _ in _ = probe; return true },
                makePrivate: { true }, addPhoto: { _ in nil },
                removePhoto: { _ in true }, removeMemory: { _ in true },
                lastError: { nil }
            ))
        }
        XCTAssertNotNil(retainedProbe)
        editor.invalidate()
        XCTAssertNil(retainedProbe)
        let mayDismiss = await editor.save()
        XCTAssertFalse(mayDismiss)
    }

    private func makeEditor(
        legacy: Bool = false,
        currentUserID: @escaping () -> String? = { "owner" },
        saveNote: @escaping (String) async -> Bool = { _ in true },
        makePrivate: @escaping () async -> Bool = { true },
        addPhoto: @escaping (Data) async -> String? = { _ in "photo" },
        removePhoto: @escaping (String) async -> Bool = { _ in true },
        removeMemory: @escaping ([String]) async -> Bool = { _ in true },
        lastError: @escaping () -> String? = { nil }
    ) -> JournalEditorState {
        let editor = JournalEditorState(text: "Original", legacyShareWasPublic: legacy)
        editor.connect(.init(
            currentUserID: currentUserID, saveNote: saveNote, makePrivate: makePrivate,
            addPhoto: addPhoto, removePhoto: removePhoto, removeMemory: removeMemory,
            lastError: lastError
        ))
        return editor
    }

    private enum TestError: Error { case failed }

    @MainActor
    private final class Suspended<Value> {
        let started = XCTestExpectation(description: "Operation reached suspension")
        private var continuation: CheckedContinuation<Value, Never>?

        func value() async -> Value {
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        }

        func resume(_ value: Value) {
            guard let continuation else {
                XCTFail("Operation must suspend before its result is supplied")
                return
            }
            self.continuation = nil
            continuation.resume(returning: value)
        }
    }
}
