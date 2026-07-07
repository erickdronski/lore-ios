import AuthenticationServices
import UIKit

/// Runs an `ASWebAuthenticationSession` for a Supabase OAuth provider (Google,
/// Facebook, Discord …) and returns the callback URL, which carries the GoTrue
/// session tokens in its fragment. `ASWebAuthenticationSession` intercepts the
/// `lore://` callback itself, so no Info.plist / `onOpenURL` juggling is needed.
@MainActor
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum WebAuthError: Error { case cancelled, failedToStart }

    /// Retained for the life of the sheet so the system doesn't tear it down.
    private var session: ASWebAuthenticationSession?

    /// Present the provider's web flow and resolve the redirect URL. Throws
    /// `WebAuthError.cancelled` when the user dismisses the sheet.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else if let error, (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    cont.resume(throwing: WebAuthError.cancelled)
                } else {
                    cont.resume(throwing: error ?? WebAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            // Keep the user's Google cookie so a return sign-in is one tap.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                cont.resume(throwing: WebAuthError.failedToStart)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
