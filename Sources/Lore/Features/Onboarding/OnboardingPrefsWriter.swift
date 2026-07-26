import Foundation

/// The real `PrefsWriting` implementation: builds a `UserPrefs` and upserts it
/// through `LoreAPI` with the signed-in user's token.
///
/// Signed-out is a first-class path. Onboarding runs before any account exists
/// (browsing never requires sign-in, see `SignInView`'s copy), so when there's
/// no session this writer **succeeds silently**: the flow's selections are
/// still applied to the local flag, and the persona/interests are remembered in
/// UserDefaults so a later sign-in (or the integrator) can replay the write.
/// The store's contract is "best effort", and no-signed-in-user is not an error.
@MainActor
struct OnboardingPrefsWriter: PrefsWriting {
    /// UserDefaults keys for the pending (signed-out) selection, so a later
    /// sign-in can flush it to `user_prefs`.
    static let pendingPersonaKey = "lore.onboarding.pendingPersona.v1"
    static let pendingInterestsKey = "lore.onboarding.pendingInterests.v1"
    static let pendingOwnerKey = "lore.onboarding.pendingOwner.v1"
    private static let guestOwner = "guest"

    /// The current user's access token + id, or `nil` when signed out. A closure
    /// (rather than a stored `AuthService`) keeps this decoupled from the auth
    /// type and lets the integrator wire whatever session source it has.
    let credentials: () -> (userID: String, accessToken: String)?
    let api: LoreAPI
    let defaults: UserDefaults

    init(
        api: LoreAPI = .shared,
        defaults: UserDefaults = .standard,
        credentials: @escaping () -> (userID: String, accessToken: String)?
    ) {
        self.api = api
        self.defaults = defaults
        self.credentials = credentials
    }

    func writeOnboardingPrefs(persona: UserPrefs.Persona, interests: [String]) async throws {
        // Stage before touching the network. If the app is interrupted or an
        // authenticated write fails offline, the exact choice remains flushable.
        stageOnboardingPrefs(persona: persona, interests: interests)
        guard let creds = credentials() else {
            // Signed out is a valid guest path; post-sign-in setup flushes it.
            return
        }

        let prefs = UserPrefs(
            userID: creds.userID,
            persona: persona,
            interests: interests,
            hiddenKinds: [],
            affinity: nil,
            onboarded: true
        )
        try await api.upsertPrefs(prefs, accessToken: creds.accessToken)
        clearPending()
    }

    // MARK: - Pending (signed-out) selection

    func stageOnboardingPrefs(persona: UserPrefs.Persona, interests: [String]) {
        stashPending(persona: persona, interests: interests)
    }

    private func stashPending(persona: UserPrefs.Persona, interests: [String]) {
        defaults.set(persona.rawValue, forKey: Self.pendingPersonaKey)
        defaults.set(Array(Set(interests)).sorted(), forKey: Self.pendingInterestsKey)
        defaults.set(credentials()?.userID ?? Self.guestOwner, forKey: Self.pendingOwnerKey)
    }

    private func clearPending() {
        defaults.removeObject(forKey: Self.pendingPersonaKey)
        defaults.removeObject(forKey: Self.pendingInterestsKey)
        defaults.removeObject(forKey: Self.pendingOwnerKey)
    }

    /// The onboarding selection captured while signed out, if any. The
    /// integrator can call this right after a successful sign-in and, if
    /// non-nil, upsert it so the account inherits the first-run choice.
    static func pendingSelection(
        defaults: UserDefaults = .standard
    ) -> (persona: UserPrefs.Persona, interests: [String])? {
        guard let raw = defaults.string(forKey: pendingPersonaKey) else { return nil }
        let persona = UserPrefs.Persona(rawValue: raw) ?? .traveler
        let interests = Array(Set(defaults.stringArray(forKey: pendingInterestsKey) ?? [])).sorted()
        return (persona, interests)
    }

    /// Flush a stashed signed-out selection to `user_prefs` after sign-in.
    /// No-op when there's nothing pending. Clears the stash on success.
    static func flushPending(
        userID: String,
        accessToken: String,
        api: LoreAPI = .shared,
        defaults: UserDefaults = .standard
    ) async throws {
        guard let pending = pendingSelection(defaults: defaults) else { return }
        let owner = defaults.string(forKey: pendingOwnerKey) ?? guestOwner
        guard owner == guestOwner || owner == userID else { return }
        let prefs = UserPrefs(
            userID: userID,
            persona: pending.persona,
            interests: pending.interests,
            hiddenKinds: [],
            affinity: nil,
            onboarded: true
        )
        try await api.upsertPrefs(prefs, accessToken: accessToken)
        defaults.removeObject(forKey: pendingPersonaKey)
        defaults.removeObject(forKey: pendingInterestsKey)
        defaults.removeObject(forKey: pendingOwnerKey)
    }
}
