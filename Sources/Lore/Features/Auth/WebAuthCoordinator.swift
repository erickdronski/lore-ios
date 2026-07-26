import AuthenticationServices
import UIKit

/// Runs an `ASWebAuthenticationSession` for a Supabase OAuth provider (Google,
/// Facebook, Discord …) and returns the callback URL, which carries the GoTrue
/// session tokens in its fragment. `ASWebAuthenticationSession` intercepts the
/// `lore://` callback itself, so no Info.plist / `onOpenURL` juggling is needed.
@MainActor
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum WebAuthError: LocalizedError, Equatable {
        case cancelled
        case failedToStart
        case alreadyInProgress

        var errorDescription: String? {
            switch self {
            case .cancelled: return nil
            case .failedToStart: return "The secure sign-in window couldn't open. Please try again."
            case .alreadyInProgress: return "A secure sign-in is already in progress."
            }
        }
    }

    /// Retained for the life of the sheet so the system doesn't tear it down.
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var attemptID: UUID?

    /// Present the provider's web flow and resolve the redirect URL. Throws
    /// `WebAuthError.cancelled` when the user dismisses the sheet.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        guard session == nil, continuation == nil else {
            throw WebAuthError.alreadyInProgress
        }
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                self.continuation = cont
                let attemptID = UUID()
                self.attemptID = attemptID
                if Task.isCancelled {
                    self.finish(.failure(WebAuthError.cancelled), for: attemptID)
                    return
                }
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme
                ) { [weak self] callbackURL, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let callbackURL {
                            self.finish(.success(callbackURL), for: attemptID)
                        } else if let error,
                                  (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self.finish(.failure(WebAuthError.cancelled), for: attemptID)
                        } else {
                            self.finish(.failure(error ?? WebAuthError.cancelled), for: attemptID)
                        }
                    }
                }
                session.presentationContextProvider = self
                // Keep the user's provider cookie so a return sign-in is one tap.
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                if !session.start() {
                    finish(.failure(WebAuthError.failedToStart), for: attemptID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() {
        session?.cancel()
        guard let attemptID else { return }
        finish(.failure(WebAuthError.cancelled), for: attemptID)
    }

    private func finish(_ result: Result<URL, Error>, for attemptID: UUID) {
        guard self.attemptID == attemptID else { return }
        let continuation = continuation
        self.continuation = nil
        self.attemptID = nil
        session = nil
        switch result {
        case .success(let url): continuation?.resume(returning: url)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.windows.first(where: \.isKeyWindow)
            ?? active?.windows.first
            ?? ASPresentationAnchor()
    }
}
