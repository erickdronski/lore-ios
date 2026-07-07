import AuthenticationServices
import SwiftUI

/// Email/password sign-in (live against Supabase GoTrue) plus a **native Sign in
/// with Apple** flow (docs/16-APPLE-TOOLKITS.md §2, docs/11 §B.2).
///
/// Guideline 4.8 posture (docs/10 §5 row 3): Sign in with Apple renders
/// **above** every other provider in every sign-in UI. Keep that order.
///
/// The Apple button runs `AppleSignInCoordinator` (nonce + system sheet) and
/// hands the identity token to `AuthService.signInWithApple`, which exchanges it
/// with Supabase. Server prerequisites (bundle id in the Apple provider's Client
/// IDs, shared `.p8`/Services ID) are documented in `AuthService`; the web OAuth
/// path already stood them up, so no new console work is needed (docs/16 §2).
struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    /// Non-fatal Apple sign-in error (nil when the user simply cancelled).
    @State private var appleError: String?
    /// The coordinator is created lazily per sign-in attempt.
    @State private var isAppleSigningIn = false
    /// Non-fatal Google sign-in error (nil when the user simply cancelled).
    @State private var googleError: String?
    @State private var isGoogleSigningIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Every place has a story.")
                        .font(LoreType.hook)
                        .foregroundStyle(LoreColor.ink600)

                    // Sign in with Apple, FIRST, always (guideline 4.8).
                    // Native flow: `AppleSignInCoordinator` runs the system
                    // sheet with a hashed nonce; `AuthService.signInWithApple`
                    // exchanges the identity token at
                    // /auth/v1/token?grant_type=id_token (docs/16 §2).
                    //
                    // We use `ASAuthorizationAppleIDButton` (the required native
                    // button) rather than SwiftUI's `SignInWithAppleButton` so we
                    // own the controller/nonce lifecycle end-to-end.
                    AppleIDButton { Task { await signInWithApple() } }
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .allowsHitTesting(!isAppleSigningIn && !auth.isBusy)
                        .opacity(isAppleSigningIn ? 0.6 : 1)
                        .overlay {
                            if isAppleSigningIn {
                                ProgressView().tint(LoreColor.bone)
                            }
                        }
                        .accessibilityLabel("Sign in with Apple")

                    if let appleError {
                        Text(appleError)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.error)
                    }

                    // Continue with Google (Supabase OAuth via ASWebAuthSession).
                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Continue with Google")
                                .font(LoreType.button)
                            if isGoogleSigningIn {
                                Spacer(minLength: 8)
                                ProgressView().tint(LoreColor.ink)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(LoreColor.ink)
                        .background(LoreColor.bone, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(LoreColor.ink.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isGoogleSigningIn || auth.isBusy)
                    .accessibilityLabel("Continue with Google")

                    if let googleError {
                        Text(googleError)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.error)
                    }

                    divider

                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding(12)
                            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if let lastError = auth.lastError {
                        Text(lastError)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.error)
                    }

                    Button {
                        Task {
                            await auth.signIn(email: email, password: password)
                            if auth.isSignedIn { dismiss() }
                        }
                    } label: {
                        Group {
                            if auth.isBusy {
                                ProgressView()
                            } else {
                                Text("Sign in")
                                    .font(LoreType.button)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .background(LoreColor.ink, in: Capsule())
                    .foregroundStyle(LoreColor.bone)
                    .disabled(email.isEmpty || password.isEmpty || auth.isBusy)

                    Text(
                        "Reading never requires an account, browsing, the map, "
                        + "and deep dives all work signed out. Accounts unlock "
                        + "contributions, Insight sync, and Lore+."
                    )
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                }
                .padding(16)
            }
            .background(LoreColor.bone100)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var divider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(LoreColor.bone300).frame(height: 1)
            Text("or")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
            Rectangle().fill(LoreColor.bone300).frame(height: 1)
        }
    }

    // MARK: - Actions

    /// Run the native Apple flow, then exchange the token with Supabase.
    @MainActor
    private func signInWithApple() async {
        appleError = nil
        isAppleSigningIn = true
        defer { isAppleSigningIn = false }
        let coordinator = AppleSignInCoordinator()
        do {
            let credential = try await coordinator.signIn()
            await auth.signInWithApple(
                idToken: credential.identityToken,
                rawNonce: credential.rawNonce,
                fullName: credential.fullName,
                email: credential.email
            )
            if auth.isSignedIn {
                dismiss()
            } else if let authError = auth.lastError {
                appleError = authError
            }
        } catch let error as AppleSignInCoordinator.AppleSignInError {
            // `.cancelled` has a nil description, stay silent on a user cancel.
            appleError = error.errorDescription
        } catch {
            appleError = error.localizedDescription
        }
    }

    /// Run the Supabase Google OAuth flow, then dismiss on success.
    @MainActor
    private func signInWithGoogle() async {
        googleError = nil
        isGoogleSigningIn = true
        defer { isGoogleSigningIn = false }
        await auth.signInWithGoogle()
        if auth.isSignedIn {
            dismiss()
        } else if let authError = auth.lastError {
            googleError = authError
        }
    }
}

/// The required native **Sign in with Apple** button, wrapped for SwiftUI.
/// Using `ASAuthorizationAppleIDButton` (not the SwiftUI `SignInWithAppleButton`)
/// keeps the button's look Apple-managed while the flow is driven by our
/// `AppleSignInCoordinator`. Renders black to sit above the Ink email CTA.
private struct AppleIDButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.cornerRadius = 14
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.tapped),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
