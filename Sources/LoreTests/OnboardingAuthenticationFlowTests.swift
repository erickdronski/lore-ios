import CoreLocation
import XCTest
@testable import Lore

@MainActor
final class OnboardingAuthenticationFlowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingAuthenticationFlowTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testInterruptedOnboardingRestoresDraftStepAndSelections() {
        let first = OnboardingStore(defaults: defaults)
        first.step = .location
        first.selectedPersona = .explorer
        first.selectedInterests = ["history", "hidden_gems"]

        let resumed = OnboardingStore(defaults: defaults)

        XCTAssertTrue(resumed.shouldPresent)
        XCTAssertEqual(resumed.step, .location)
        XCTAssertEqual(resumed.selectedPersona, .explorer)
        XCTAssertEqual(resumed.selectedInterests, ["history", "hidden_gems"])
    }

    func testUnavailableNotificationStepIsSkippedByEveryNavigationPath() async {
        XCTAssertFalse(Config.pushNotificationsEnabled)
        XCTAssertFalse(OnboardingStore.activeSteps.contains(.notifications))
        XCTAssertNil(OnboardingStore.Step.named("notifications"))

        let store = OnboardingStore(defaults: defaults)
        store.advance()
        store.advance()
        XCTAssertEqual(store.step, .location)

        store.advance()
        XCTAssertEqual(store.step, .finish)
        store.back()
        XCTAssertEqual(store.step, .location)

        await store.requestNotifications()
        XCTAssertFalse(store.isRequestingPermission)
    }

    func testNotificationDraftRestoresAtFinishWithoutLosingSelections() {
        let first = OnboardingStore(defaults: defaults)
        first.selectedPersona = .historian
        first.selectedInterests = ["architecture", "history"]
        first.step = .notifications

        let resumed = OnboardingStore(defaults: defaults)

        XCTAssertEqual(resumed.step, .finish)
        XCTAssertEqual(resumed.selectedPersona, .historian)
        XCTAssertEqual(resumed.selectedInterests, ["architecture", "history"])
    }

    func testCompletedServerGateClearsLocalDraftAndNeverPresentsAgain() {
        let store = OnboardingStore(defaults: defaults)
        store.step = .finish
        store.selectedInterests = ["architecture", "history"]
        store.resolveGate(serverPrefs: userPrefs(onboarded: true))

        XCTAssertFalse(store.shouldPresent)
        XCTAssertTrue(defaults.bool(forKey: OnboardingStore.didOnboardDefaultsKey))
        XCTAssertNil(defaults.data(forKey: OnboardingStore.draftDefaultsKey))
        XCTAssertFalse(OnboardingStore(defaults: defaults).shouldPresent)
    }

    func testFinishStagesSynchronouslyCompletesExactlyOnceAndWritesInBackground() async {
        let writeFinished = expectation(description: "prefs write")
        let writer = RecordingPrefsWriter(writeFinished: writeFinished)
        let store = OnboardingStore(defaults: defaults)
        store.selectedPersona = .historian
        store.selectedInterests = ["history", "architecture"]
        var completionCount = 0

        store.finish(onComplete: { completionCount += 1 }, prefsWriter: writer)
        store.finish(onComplete: { completionCount += 1 }, prefsWriter: writer)

        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(writer.stagedPersona, .historian)
        XCTAssertEqual(Set(writer.stagedInterests), ["history", "architecture"])
        XCTAssertFalse(store.shouldPresent)
        XCTAssertTrue(defaults.bool(forKey: OnboardingStore.didOnboardDefaultsKey))
        await fulfillment(of: [writeFinished], timeout: 1)
        XCTAssertEqual(writer.writeCount, 1)
    }

    func testSkipIsOneStepAndUsesDocumentedBroadTravelerDefaults() async {
        let writeFinished = expectation(description: "skip prefs write")
        let writer = RecordingPrefsWriter(writeFinished: writeFinished)
        let store = OnboardingStore(defaults: defaults)
        store.selectedPersona = .nightlife
        store.selectedInterests = ["nightlife"]
        var completionCount = 0

        store.skip(onComplete: { completionCount += 1 }, prefsWriter: writer)

        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(writer.stagedPersona, OnboardingContent.skipPersona)
        XCTAssertEqual(Set(writer.stagedInterests), Set(OnboardingContent.skipInterests))
        XCTAssertFalse(store.shouldPresent)
        await fulfillment(of: [writeFinished], timeout: 1)
    }

    func testGuestPreferencesRemainDurableAndDeterministicUntilSignIn() async throws {
        let writer = OnboardingPrefsWriter(defaults: defaults, credentials: { nil })

        try await writer.writeOnboardingPrefs(
            persona: .traveler,
            interests: ["history", "architecture", "history"]
        )
        let pending = OnboardingPrefsWriter.pendingSelection(defaults: defaults)

        XCTAssertEqual(pending?.persona, .traveler)
        XCTAssertEqual(pending?.interests, ["architecture", "history"])
    }

    func testFailedAccountPreferenceCannotLeakIntoAnotherAccount() async throws {
        let writer = OnboardingPrefsWriter(defaults: defaults) {
            (userID: "account-a", accessToken: "expired-token")
        }
        writer.stageOnboardingPrefs(persona: .historian, interests: ["history"])

        // A mismatched owner returns before attempting any API request.
        try await OnboardingPrefsWriter.flushPending(
            userID: "account-b",
            accessToken: "token-b",
            defaults: defaults
        )

        XCTAssertEqual(OnboardingPrefsWriter.pendingSelection(defaults: defaults)?.persona, .historian)
        XCTAssertEqual(defaults.string(forKey: OnboardingPrefsWriter.pendingOwnerKey), "account-a")
    }

    func testCredentialValidationNormalizesEmailAndEnforcesNewPasswordBounds() {
        XCTAssertEqual(AuthService.normalizedEmail("  Traveler@Example.COM \n"), "traveler@example.com")
        XCTAssertTrue(AuthService.isValidEmail("Traveler@example.com"))
        XCTAssertFalse(AuthService.isValidEmail("traveler@example"))
        XCTAssertFalse(AuthService.isValidEmail("@example.com"))
        XCTAssertTrue(AuthService.isValidNewPassword("eight888"))
        XCTAssertFalse(AuthService.isValidNewPassword("short"))
        XCTAssertFalse(AuthService.isValidNewPassword(String(repeating: "x", count: 129)))
    }

    func testOAuthCallbackAcceptsOnlyLoreHostAndCompleteBearerTokens() throws {
        let valid = URL(string: "lore://auth-callback#access_token=access&refresh_token=refresh&expires_in=3600&token_type=bearer")!
        let tokens = try AuthService.oauthTokens(from: valid)

        XCTAssertEqual(tokens.access, "access")
        XCTAssertEqual(tokens.refresh, "refresh")
        XCTAssertEqual(tokens.expiresIn, 3_600)
        XCTAssertEqual(tokens.tokenType, "bearer")

        XCTAssertThrowsError(try AuthService.oauthTokens(from: URL(string:
            "lore://unexpected#access_token=a&refresh_token=r&expires_in=3600&token_type=bearer")!))
        XCTAssertThrowsError(try AuthService.oauthTokens(from: URL(string:
            "lore://auth-callback#access_token=a&access_token=b&refresh_token=r&expires_in=3600&token_type=bearer")!))
        XCTAssertThrowsError(try AuthService.oauthTokens(from: URL(string:
            "lore://auth-callback#access_token=a&refresh_token=r&expires_in=forever&token_type=bearer")!))
    }

    func testOAuthProviderErrorIsDecodedForAUsefulRetryMessage() {
        let callback = URL(string: "lore://auth-callback?error=access_denied&error_description=Access+was+denied")!

        XCTAssertThrowsError(try AuthService.oauthTokens(from: callback)) { error in
            XCTAssertEqual(error.localizedDescription, "Access was denied")
        }
    }

    func testAppleNonceUsesExpectedLengthAlphabetAndHash() throws {
        let first = try AppleSignInCoordinator.randomNonceString()
        let second = try AppleSignInCoordinator.randomNonceString()
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

        XCTAssertEqual(first.count, 32)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.unicodeScalars.allSatisfy(allowed.contains))
        XCTAssertEqual(
            AppleSignInCoordinator.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testAppleOneTimeProfileSeedKeepsNameAndPrivateRelayEmail() {
        var name = PersonNameComponents()
        name.givenName = "Ada"
        name.familyName = "Lovelace"

        let seed = AppleProfileSeed.make(
            userID: "apple-user",
            fullName: name,
            email: " relay@privaterelay.appleid.com "
        )

        XCTAssertEqual(seed?.userID, "apple-user")
        XCTAssertEqual(seed?.displayName, "Ada Lovelace")
        XCTAssertEqual(seed?.email, "relay@privaterelay.appleid.com")
    }

    func testOfflineAndCancellationErrorsHaveCorrectUserSemantics() {
        XCTAssertEqual(
            AuthService.userFacingMessage(for: URLError(.notConnectedToInternet)),
            "You're offline. Reconnect and try again."
        )
        XCTAssertNil(AuthService.userFacingMessage(for: CancellationError()))
        XCTAssertNil(AuthService.userFacingMessage(for: URLError(.cancelled)))
    }

    private func userPrefs(onboarded: Bool) -> UserPrefs {
        UserPrefs(
            userID: "traveler",
            persona: .traveler,
            interests: ["history"],
            hiddenKinds: [],
            affinity: nil,
            onboarded: onboarded
        )
    }
}

@MainActor
private final class RecordingPrefsWriter: PrefsWriting {
    private let writeFinished: XCTestExpectation
    private(set) var stagedPersona: UserPrefs.Persona?
    private(set) var stagedInterests: [String] = []
    private(set) var writeCount = 0

    init(writeFinished: XCTestExpectation) {
        self.writeFinished = writeFinished
    }

    func stageOnboardingPrefs(persona: UserPrefs.Persona, interests: [String]) {
        stagedPersona = persona
        stagedInterests = interests
    }

    func writeOnboardingPrefs(persona: UserPrefs.Persona, interests: [String]) async throws {
        writeCount += 1
        writeFinished.fulfill()
    }
}
