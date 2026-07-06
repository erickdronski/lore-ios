import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Runs the native **Sign in with Apple** flow: builds an
/// `ASAuthorizationAppleIDRequest` with a hashed nonce, presents the system
/// `ASAuthorizationController`, and hands back the Apple credential.
///
/// Doctrine (docs/16-APPLE-TOOLKITS.md §2, docs/11-AUTH-SETUP.md §B.2): use the
/// native `AuthenticationServices` path, not a web redirect. Take the returned
/// `identityToken` (a JWT) and exchange it with Supabase via
/// `signInWithIdToken(provider: .apple, idToken:, nonce:)`, which is
/// `AuthService.signInWithApple`. The nonce protects the exchange from replay:
/// we send the SHA-256 hash to Apple in the request, and the raw nonce to
/// Supabase, which verifies the hash inside the signed token matches.
///
/// **Name/email caveat (docs/16 §2):** Apple returns `fullName`/`email` only on
/// the *very first* authorization for a given Apple ID. Persist them immediately
/// (to `user_profile`) or they're gone, `AppleCredential` carries them up so
/// the caller can. Honor the private-relay email as a real address; never block
/// `@privaterelay.appleid.com`.
///
/// This is a `UIKit` `NSObject` coordinator (SwiftUI has no first-class hook for
/// the `presentationAnchor` + delegate pair). It retains itself for the duration
/// of the request via the continuation, then releases.
@MainActor
final class AppleSignInCoordinator: NSObject {
    /// The credential the flow yields on success, everything the token exchange
    /// and first-run profile write need.
    struct AppleCredential {
        /// The Apple identity token (JWT) to exchange with Supabase.
        let identityToken: String
        /// The raw (un-hashed) nonce Supabase verifies against the token's hash.
        let rawNonce: String
        /// Apple's stable user identifier for this app.
        let userID: String
        /// First-authorization-only: the user's name, if granted.
        let fullName: PersonNameComponents?
        /// First-authorization-only: the (possibly relay) email, if granted.
        let email: String?
    }

    enum AppleSignInError: LocalizedError {
        case cancelled
        case missingIdentityToken
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return nil  // user backed out, not an error to surface
            case .missingIdentityToken:
                return "Apple didn't return a sign-in token. Try again."
            case .failed(let message):
                return message
            }
        }
    }

    private var continuation: CheckedContinuation<AppleCredential, Error>?
    /// The raw nonce for the in-flight request (returned in the credential).
    private var currentRawNonce: String?
    /// Self-retain across the async request so the delegate stays alive.
    private var strongSelf: AppleSignInCoordinator?

    /// Begin the flow. Suspends until the user completes or cancels the system
    /// sheet. Throws `AppleSignInError` (`.cancelled` carries a nil message).
    func signIn() async throws -> AppleCredential {
        let rawNonce = Self.randomNonceString()
        currentRawNonce = rawNonce
        strongSelf = self

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedContinuation { (cont: CheckedContinuation<AppleCredential, Error>) -> Void in
            self.continuation = cont
            controller.performRequests()
        }
        // NB: the resume happens in the delegate callbacks below.
    }

    private func finish(_ result: Result<AppleCredential, Error>) {
        let cont = continuation
        continuation = nil
        currentRawNonce = nil
        strongSelf = nil
        switch result {
        case .success(let credential): cont?.resume(returning: credential)
        case .failure(let error): cont?.resume(throwing: error)
        }
    }

    // MARK: - Nonce

    /// A cryptographically-random nonce string (Apple's recommended generator).
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                // Fallback that still yields a usable nonce if SecRandom fails.
                randoms = (0..<16).map { _ in UInt8.random(in: 0...255) }
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// SHA-256 of the nonce, hex-encoded, what goes in the Apple request.
    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        else {
            finish(.failure(AppleSignInError.failed("Unexpected Apple credential type.")))
            return
        }
        guard
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            finish(.failure(AppleSignInError.missingIdentityToken))
            return
        }
        guard let rawNonce = currentRawNonce else {
            finish(.failure(AppleSignInError.failed("Missing sign-in nonce. Try again.")))
            return
        }
        finish(.success(AppleCredential(
            identityToken: idToken,
            rawNonce: rawNonce,
            userID: credential.user,
            fullName: credential.fullName,
            email: credential.email
        )))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            finish(.failure(AppleSignInError.cancelled))
        } else {
            finish(.failure(AppleSignInError.failed(error.localizedDescription)))
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Find the app's key window to anchor the system sheet. iOS 15+ scene API.
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        let keyWindow = windowScene?.windows.first(where: \.isKeyWindow)
            ?? windowScene?.windows.first
        return keyWindow ?? ASPresentationAnchor()
    }
}
