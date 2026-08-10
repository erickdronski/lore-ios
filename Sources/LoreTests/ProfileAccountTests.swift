import XCTest
@testable import Lore

final class ProfileAccountTests: XCTestCase {
    override func tearDown() {
        ProfileURLProtocol.handler = nil
        super.tearDown()
    }

    func testProfileDecodingToleratesMissingOptionalServerFields() throws {
        let data = Data(#"{"id":"traveler-1","display_name":"  Ada  ","insight_points":-5}"#.utf8)

        let profile = try JSONDecoder().decode(UserProfile.self, from: data)

        XCTAssertEqual(profile.displayName, "Ada")
        XCTAssertEqual(profile.trustTier, "scout")
        XCTAssertEqual(profile.insightPoints, 0)
        XCTAssertEqual(profile.initials, "A")
        XCTAssertEqual(profile.completedIdentityFieldCount, 1)
    }

    func testProfileEditNormalizesAndEncodesClearedFields() throws {
        let edit = try UserProfile.Edit(
            displayName: "  Ada Lovelace ",
            handle: " @ADA_1843 ",
            bio: "   "
        )

        XCTAssertEqual(edit.displayName, "Ada Lovelace")
        XCTAssertEqual(edit.handle, "ada_1843")
        XCTAssertNil(edit.bio)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: Any]
        )
        XCTAssertEqual(object["display_name"] as? String, "Ada Lovelace")
        XCTAssertEqual(object["handle"] as? String, "ada_1843")
        XCTAssertTrue(object["bio"] is NSNull)
    }

    func testProfileEditRejectsUnsafeUsername() {
        XCTAssertThrowsError(
            try UserProfile.Edit(displayName: "Ada", handle: "Not valid!", bio: "")
        ) { error in
            XCTAssertEqual(error as? UserProfile.ValidationError, .invalidHandle)
        }
    }

    func testAvatarRequiresHTTPS() {
        let secure = UserProfile(id: "1", avatarURL: "https://images.example/avatar.jpg")
        let insecure = UserProfile(id: "2", avatarURL: "http://images.example/avatar.jpg")

        XCTAssertNotNil(secure.secureAvatarURL)
        XCTAssertNil(insecure.secureAvatarURL)
    }

    func testProfileJourneySnapshotUsesServerStats() {
        let stats = UserStats(
            places: 14,
            cities: 3,
            countries: 2,
            continents: 1,
            continentsList: ["North America"],
            divesRead: 9,
            notes: 4,
            photos: 6,
            scannerVisits: 5,
            badges: 7,
            badgesTotal: 425,
            insightPoints: 140,
            currentStreak: 2,
            longestStreak: 5,
            topCategories: [],
            firstVisit: nil
        )

        let snapshot = ProfileJourneySnapshot(stats: stats)

        XCTAssertEqual(snapshot.headline, "3 cities in your atlas")
        XCTAssertEqual(snapshot.primaryMetrics.map(\.value), ["14", "3", "9", "6"])
        XCTAssertEqual(snapshot.secondaryMetrics.map(\.value), ["7/425", "140", "2d"])
    }

    func testProfileJourneySnapshotHasHonestZeroState() {
        let snapshot = ProfileJourneySnapshot(stats: .zero)

        XCTAssertEqual(snapshot.headline, "Your field record is ready")
        XCTAssertTrue(snapshot.subhead.contains("Visits, dives, notes, photos, and badges"))
        XCTAssertEqual(snapshot.secondaryMetrics.first?.value, "0")
    }

    func testGuideCompanionSignedOutStartsWithAccountAndLens() {
        let snapshot = ProfileGuideCompanionSnapshot(
            isSignedIn: false,
            isPlus: false,
            profile: nil,
            journeyState: .signedOut,
            savedCount: 0
        )

        XCTAssertEqual(snapshot.title, "Start your field record")
        XCTAssertEqual(snapshot.cues.map(\.id), ["sign-in", "travel-lens"])
        XCTAssertEqual(snapshot.cues.first?.destination, .signIn)
    }

    func testGuideCompanionUsesZeroJourneyStateForFirstMoves() {
        let profile = UserProfile(id: "u1", displayName: "Ada")
        let snapshot = ProfileGuideCompanionSnapshot(
            isSignedIn: true,
            isPlus: false,
            profile: profile,
            journeyState: .loaded(.zero),
            savedCount: 0
        )

        XCTAssertEqual(snapshot.title, "Your guide is ready")
        XCTAssertEqual(
            snapshot.cues.map(\.id),
            ["traveler-card", "first-visit", "save-route-seed"]
        )
        XCTAssertEqual(snapshot.cues.map(\.destination), [.editProfile, .journal, .savedPlaces])
    }

    func testGuideCompanionPicksSpecificNextMovesFromSyncedStats() {
        let stats = UserStats(
            places: 8,
            cities: 2,
            countries: 1,
            continents: 1,
            continentsList: ["North America"],
            divesRead: 12,
            notes: 2,
            photos: 0,
            scannerVisits: 3,
            badges: 4,
            badgesTotal: 425,
            insightPoints: 90,
            currentStreak: 3,
            longestStreak: 5,
            topCategories: [],
            firstVisit: nil
        )
        let profile = UserProfile(
            id: "u1",
            handle: "ada",
            displayName: "Ada",
            bio: "Architecture walks"
        )

        let snapshot = ProfileGuideCompanionSnapshot(
            isSignedIn: true,
            isPlus: true,
            profile: profile,
            journeyState: .loaded(stats),
            savedCount: 2
        )

        XCTAssertEqual(snapshot.title, "Your next field moves")
        XCTAssertEqual(snapshot.cues.map(\.id), ["first-photo", "saved-walk", "next-badge"])
        XCTAssertEqual(snapshot.cues.map(\.destination), [.journal, .savedPlaces, .passport])
    }

    func testPreferencesDecodeForwardCompatiblyAndDeduplicate() throws {
        let data = Data(#"{"user_id":"u1","persona":"future_lens","interests":["history","history",""],"hidden_kinds":["museum","museum"],"onboarded":true}"#.utf8)

        let prefs = try JSONDecoder().decode(UserPrefs.self, from: data)

        XCTAssertEqual(prefs.persona, .traveler)
        XCTAssertEqual(prefs.interests, ["history"])
        XCTAssertEqual(prefs.hiddenKinds, ["museum"])
        XCTAssertTrue(prefs.onboarded)
    }

    func testPreferenceUpdatePreservesFiltersAndAffinity() {
        let affinity = JSONValue.object(["art-deco": .number(0.8)])
        let original = UserPrefs(
            userID: "u1",
            persona: .traveler,
            interests: ["history"],
            hiddenKinds: ["bar"],
            affinity: affinity,
            onboarded: true
        )

        let updated = original.updating(persona: .architect, interests: ["architecture"])

        XCTAssertEqual(updated.persona, .architect)
        XCTAssertEqual(updated.interests, ["architecture"])
        XCTAssertEqual(updated.hiddenKinds, ["bar"])
        XCTAssertEqual(updated.affinity, affinity)
        XCTAssertEqual(updated.affinityWeight(for: "art-deco"), 0.8)
    }

    func testDeletionConfirmationIsDeliberate() {
        XCTAssertTrue(AccountDeletionConfirmation.isConfirmed(" DELETE\n"))
        XCTAssertFalse(AccountDeletionConfirmation.isConfirmed("delete"))
        XCTAssertFalse(AccountDeletionConfirmation.isConfirmed("DELETE ACCOUNT"))
    }

    func testPushNotificationSettingStaysHiddenUntilDeliveryIsConfigured() {
        XCTAssertFalse(Config.pushNotificationsEnabled)
    }

    func testDataAccessRequestIncludesAccountContext() throws {
        let url = try XCTUnwrap(
            ProfileSupportLinks.dataAccessRequestURL(accountEmail: "traveler@example.com")
        )
        let decoded = url.absoluteString.removingPercentEncoding ?? url.absoluteString

        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(decoded.contains(ProfileSupportLinks.supportEmail))
        XCTAssertTrue(decoded.contains("traveler@example.com"))
        XCTAssertTrue(decoded.contains("data access request"))
    }

    func testProfileUpdateUsesScopedAuthenticatedPatch() async throws {
        let session = stubSession { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "return=representation")
            XCTAssertTrue(request.url?.query?.contains("id=eq.traveler-1") == true)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"[{"id":"traveler-1","display_name":"Ada","handle":"ada_1843"}]"#.utf8))
        }
        let edit = try UserProfile.Edit(displayName: "Ada", handle: "ada_1843", bio: "")

        let profile = try await ProfileAccountClient.updateProfile(
            edit,
            userID: "traveler-1",
            accessToken: "access-token",
            session: session
        )

        XCTAssertEqual(profile.handle, "ada_1843")
    }

    func testProfileUpdateMapsConflictToFriendlyUsernameError() async throws {
        let session = stubSession { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 409,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let edit = try UserProfile.Edit(displayName: "Ada", handle: "ada_1843", bio: "")

        do {
            _ = try await ProfileAccountClient.updateProfile(
                edit,
                userID: "traveler-1",
                accessToken: "access-token",
                session: session
            )
            XCTFail("Expected username conflict")
        } catch {
            XCTAssertEqual(error as? ProfileAccountClient.ClientError, .usernameTaken)
        }
    }

    private func stubSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        ProfileURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class ProfileURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
