import SwiftUI

/// Authentication: email/password plus Sign in with Apple, Google, and
/// Facebook (Supabase OAuth). Apple is presented first and given equal-or-
/// greater prominence, which satisfies Guideline 4.8 for the other social
/// options. All three social providers ship in Release as of 2026-07-16, once
/// the App ID gained the Sign-in-with-Apple capability and the Supabase Apple
/// provider went live with the bundle id in its Client IDs.
struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var apple = AppleSignInCoordinator()
    @State private var confirmedMinimumAge = false

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

                    if mode == .signUp {
                        Toggle("I am 13 or older", isOn: $confirmedMinimumAge)
                            .font(LoreType.caption)
                            .tint(LoreColor.brass700)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("By creating an account, you agree to:")
                            HStack(spacing: 8) {
                                Link("Terms of Use", destination: URL(string: "https://lore-web-liart.vercel.app/terms")!)
                                Link("Privacy Policy", destination: URL(string: "https://lore-web-liart.vercel.app/privacy")!)
                            }
                        }
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.ink600)
                        .tint(LoreColor.brass700)
                    }

                    if let lastError = auth.lastError {
                        Text(lastError)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.error)
                    }
                    if let lastNotice = auth.lastNotice {
                        Text(lastNotice)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.success)
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
                    .disabled(
                        email.isEmpty || password.isEmpty || auth.isBusy
                        || (mode == .signUp && !confirmedMinimumAge)
                    )

                    // Third-party sign-in ships in Release as of 2026-07-16:
                    // Sign in with Apple is provisioned end to end (App ID
                    // capability + entitlement + live Supabase Apple provider),
                    // which satisfies Guideline 4.8 for the Google/Facebook
                    // options offered alongside it.
                    socialDivider
                    socialButtons

                    // Switch between sign in and account creation; reset link
                    // only in sign-in mode.
                    HStack {
                        Button(mode == .signUp ? "Have an account? Sign in" : "New here? Create an account") {
                            mode = (mode == .signUp) ? .signIn : .signUp
                            confirmedMinimumAge = false
                            auth.lastError = nil
                            auth.lastNotice = nil
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
                        + "visits, your journal, Insight sync, and Lore+."
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
        // The sheet is painted with fixed light brand colors (bone/ink); pin the
        // scheme so the nav chrome + sheet grabber don't render dark on a
        // dark-mode device (matches ProfileScreen/SettingsView).
        .preferredColorScheme(.light)
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

    /// The third-party sign-in options. Apple is FIRST and given equal-or-greater
    /// prominence (Guideline 4.8 + HIG): where Google/Facebook are offered, a
    /// working Sign in with Apple must be too. Live in Supabase as of 2026-07-16.
    /// X stays commented until its Supabase provider is configured.
    @ViewBuilder private var socialButtons: some View {
        VStack(spacing: 10) {
            appleButton
            oauthButton("Continue with Google", provider: "google",
                        background: LoreColor.bone, foreground: LoreColor.ink, bordered: true)
            oauthButton("Continue with Facebook", provider: "facebook",
                        background: Color(red: 0.09, green: 0.47, blue: 0.95), foreground: .white)
            // oauthButton("Continue with X", provider: "twitter", background: .black, foreground: .white)
        }
    }

    /// Native Sign in with Apple (system sheet -> id_token grant). Live: the App
    /// ID has the Sign-in-with-Apple capability, the entitlement is on in
    /// project.yml, and the Supabase Apple provider carries the bundle id.
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
