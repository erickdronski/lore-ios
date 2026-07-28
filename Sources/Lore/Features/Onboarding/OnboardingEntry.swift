import SwiftUI

/// The one clean seam the integrator wires, **no edit to `LoreApp.swift`
/// required** beyond attaching this modifier.
///
/// Usage in `LoreApp` (the integrator adds exactly this one line to the
/// existing `RootTabView()` in the `WindowGroup`):
///
/// ```swift
/// RootTabView()
///     .environment(auth)
///     .tint(LoreColor.brass700)
///     .loreOnboarding(auth: auth)   // ← the only new line
/// ```
///
/// It presents `OnboardingView` as a full-screen cover on first launch (gate:
/// local UserDefaults flag, folded with the server's `user_prefs.onboarded`
/// once a session exists), then never again. The gate + the single
/// `user_prefs` write are handled entirely inside the flow; the app just hosts
/// it.
extension View {
    /// Present the first-run onboarding flow over this view when it's due.
    ///
    /// - Parameters:
    ///   - auth: the app's `AuthService`, read for the current session so the
    ///     finish-write can upsert `user_prefs` (signed-out is handled: the
    ///     choice is stashed and the flow still completes, see
    ///     `OnboardingPrefsWriter`).
    ///   - forcePresent: bypass the gate and always show the flow (a "replay
    ///     onboarding" hook for Profile / debug). Default `false`.
    func loreOnboarding(
        auth: AuthService,
        prefs: PrefsCoordinator,
        forcePresent: Bool = false
    ) -> some View {
        modifier(OnboardingPresenter(auth: auth, prefsCoordinator: prefs, forcePresent: forcePresent))
    }
}

/// Hosts the onboarding cover and owns the `OnboardingStore`'s lifetime. Kept
/// private to the module surface; callers only ever touch `.loreOnboarding`.
struct OnboardingPresenter: ViewModifier {
    let auth: AuthService
    let forcePresent: Bool

    /// The shared prefs lens, passed in explicitly (NOT via @Environment): this
    /// modifier is applied outside `.environment(prefs)` in LoreApp, so it sits
    /// above that injection and could not read it from the environment. Adopting
    /// the just-chosen onboarding prefs here makes the map/scanner personalize
    /// immediately, including on the default signed-out path (audit docs/30).
    let prefsCoordinator: PrefsCoordinator

    @State private var store: OnboardingStore
    @State private var isPresented: Bool

    init(auth: AuthService, prefsCoordinator: PrefsCoordinator, forcePresent: Bool) {
        self.auth = auth
        self.prefsCoordinator = prefsCoordinator
        self.forcePresent = forcePresent
        let store = OnboardingStore(forcePresent: forcePresent)
        _store = State(initialValue: store)
        // Existing accounts must finish Keychain restoration + server-gate
        // resolution before presentation, otherwise onboarding flashes over a
        // returning user's app and can accept choices for the wrong identity.
        _isPresented = State(initialValue: forcePresent && store.shouldPresent)
    }

    /// The real prefs writer, reading the session lazily so it always sees the
    /// latest token (the user could sign in mid-flow).
    private var prefsWriter: PrefsWriting {
        OnboardingPrefsWriter {
            // Preserve the identity even if its access token just expired. The
            // immediate write may fail and retry after refresh, but the staged
            // choice must never be mislabeled as a guest choice.
            guard let session = auth.session else { return nil }
            return (userID: session.user.id, accessToken: session.accessToken)
        }
    }

    private var gateIdentity: String {
        if forcePresent { return "forced" }
        if auth.isRestoring { return "restoring" }
        return auth.session?.user.id ?? "guest"
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                OnboardingView(
                    store: store,
                    prefsWriter: prefsWriter,
                    onFinished: finishPresentation
                )
            }
            .task(id: gateIdentity) { await resolvePresentationGate() }
    }

    private func resolvePresentationGate() async {
        guard store.shouldPresent else {
            isPresented = false
            return
        }
        if forcePresent {
            isPresented = true
            return
        }
        // The task restarts when restoration changes this identity to a guest
        // or user id. Do not make a first-launch decision while it is unknown.
        guard !auth.isRestoring else { return }

        guard let token = await auth.validAccessToken() else {
            isPresented = store.shouldPresent
            return
        }

        // Signing in from the visible Finish sheet must commit the choices that
        // are already on screen before an existing account's server gate can
        // dismiss onboarding. The normal writer keeps its merge contract and
        // leaves hidden kinds untouched.
        if isPresented,
           store.finishAfterAuthenticationIfReady(
               onComplete: finishPresentation,
               prefsWriter: prefsWriter
           ) {
            return
        }

        let prefs = try? await LoreAPI.shared.userPrefs(accessToken: token)
        store.resolveGate(serverPrefs: prefs)
        isPresented = store.shouldPresent
    }

    private func finishPresentation() {
        isPresented = false
        // Adopt the just-staged lens so the map/scanner personalize this
        // session. A later server load reconciles for signed-in users.
        if let persona = store.resolvedPersona {
            prefsCoordinator.adopt(UserPrefs(
                userID: auth.session?.user.id ?? "local",
                persona: persona,
                interests: store.resolvedInterests,
                onboarded: true
            ))
        }
    }
}
