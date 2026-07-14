import SwiftUI

/// Sign in with email/password, Sign in with Apple (native id_token grant), and
/// Google / X / Facebook via Supabase OAuth. Apple is presented first among the
/// third-party options (Guideline 4.8: a working Apple button is required where
/// other social logins are offered). Prerequisites: the App ID's
/// Sign-in-with-Apple capability + the `applesignin` key in Lore.entitlements
/// (both wired), and each OAuth provider enabled in the Supabase dashboard with
/// `lore://auth-callback` in the redirect allowlist.
struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var apple = AppleSignInCoordinator()

    private enum Mode { case signIn, signUp }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Every place has a story.")
                        .font(LoreType.hook)
                        .foregroundStyle(LoreColor.ink600)

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
                            if mode == .signUp {
                                await auth.signUp(email: email, password: password)
                            } else {
                                await auth.signIn(email: email, password: password)
                            }
                            if auth.isSignedIn { dismiss() }
                        }
                    } label: {
                        Group {
                            if auth.isBusy {
                                ProgressView()
                            } else {
                                Text(mode == .signUp ? "Create account" : "Sign in")
                                    .font(LoreType.button)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .background(LoreColor.ink, in: Capsule())
                    .foregroundStyle(LoreColor.bone)
                    .disabled(email.isEmpty || password.isEmpty || auth.isBusy)

                    socialDivider
                    socialButtons

                    // Switch between sign in and account creation; reset link
                    // only in sign-in mode.
                    HStack {
                        Button(mode == .signUp ? "Have an account? Sign in" : "New here? Create an account") {
                            mode = (mode == .signUp) ? .signIn : .signUp
                            auth.lastError = nil
                        }
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.brass700)
                        Spacer()
                        if mode == .signIn {
                            Button("Forgot password?") {
                                Task { await auth.sendPasswordReset(email: email) }
                            }
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.ink600)
                            .disabled(email.isEmpty || auth.isBusy)
                        }
                    }

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
            .navigationTitle(mode == .signUp ? "Create account" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Social sign-in

    private var socialDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(LoreColor.ink.opacity(0.12)).frame(height: 1)
            Text("or").font(LoreType.caption).foregroundStyle(LoreColor.ink600)
            Rectangle().fill(LoreColor.ink.opacity(0.12)).frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    /// The OAuth providers currently enabled in Supabase (Google + Facebook).
    /// Apple (native id_token) and X are wired in AuthService/AppleSignInCoordinator
    /// and re-appear here the moment their Supabase providers + (for Apple) the
    /// App ID capability are provisioned, see the commented block below.
    @ViewBuilder private var socialButtons: some View {
        VStack(spacing: 10) {
            // appleButton   // enable once the App ID + Supabase Apple provider are set
            oauthButton("Continue with Google", provider: "google",
                        background: LoreColor.bone, foreground: LoreColor.ink, bordered: true)
            oauthButton("Continue with Facebook", provider: "facebook",
                        background: Color(red: 0.09, green: 0.47, blue: 0.95), foreground: .white)
            // oauthButton("Continue with X", provider: "twitter", background: .black, foreground: .white)
        }
    }

    /// Native Sign in with Apple (system sheet -> id_token grant). Ready; enable
    /// in `socialButtons` once the App ID Sign-in-with-Apple capability + the
    /// Supabase Apple provider exist (and re-add the entitlement in project.yml).
    @available(*, unavailable, message: "Enable when Apple provider + App ID capability are provisioned")
    private var appleButton: some View {
        Button {
            Task {
                do {
                    let cred = try await apple.signIn()
                    await auth.signInWithApple(
                        idToken: cred.identityToken, rawNonce: cred.rawNonce,
                        fullName: cred.fullName, email: cred.email
                    )
                    if auth.isSignedIn { dismiss() }
                } catch {
                    // .cancelled carries a nil message; real errors surface via
                    // auth.lastError from the exchange.
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                Text("Continue with Apple").font(LoreType.button)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.black, in: Capsule())
            .foregroundStyle(.white)
        }
        .disabled(auth.isBusy)
    }

    /// A Supabase OAuth provider button (web flow).
    private func oauthButton(
        _ title: String, provider: String,
        background: Color, foreground: Color, bordered: Bool = false
    ) -> some View {
        Button {
            Task {
                await auth.signInWithOAuth(provider: provider)
                if auth.isSignedIn { dismiss() }
            }
        } label: {
            Text(title)
                .font(LoreType.button)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(background, in: Capsule())
                .foregroundStyle(foreground)
                .overlay {
                    if bordered {
                        Capsule().strokeBorder(LoreColor.ink.opacity(0.15), lineWidth: 1)
                    }
                }
        }
        .disabled(auth.isBusy)
    }
}
