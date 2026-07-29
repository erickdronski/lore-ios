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
    @State private var operation: Operation?
    @State private var actionTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    private enum Mode { case signIn, signUp }
    private enum Field { case email, password }
    private enum Operation: Equatable {
        case credentials
        case passwordReset
        case apple
        case oauth(String)
    }

    private var isWorking: Bool { operation != nil || auth.isBusy }
    private var canSubmitCredentials: Bool {
        AuthService.isValidEmail(email)
            && !password.isEmpty
            && (mode == .signIn || (confirmedMinimumAge && AuthService.isValidNewPassword(password)))
            && !isWorking
    }
    private var canStartSocialAuthentication: Bool {
        AuthService.allowsAccountCreatingAuthentication(
            confirmedMinimumAge: confirmedMinimumAge
        ) && !isWorking
    }

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
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .padding(12)
                            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))

                        SecureField("Password", text: $password)
                            .textContentType(mode == .signUp ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submitCredentials)
                            .padding(12)
                            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if mode == .signUp {
                        Text("Use 8 to 128 characters.")
                            .font(LoreType.micro)
                            .foregroundStyle(LoreColor.ink600)
                    }

                    if mode == .signUp { accountCreationConsent }

                    if let lastError = auth.lastError {
                        statusMessage(lastError, symbol: "exclamationmark.triangle.fill", color: LoreColor.error)
                            .accessibilityIdentifier("auth.error")
                    }
                    if let lastNotice = auth.lastNotice {
                        statusMessage(lastNotice, symbol: "checkmark.circle.fill", color: LoreColor.success)
                            .accessibilityIdentifier("auth.notice")
                    }

                    Button(action: submitCredentials) {
                        Group {
                            if operation == .credentials {
                                ProgressView()
                            } else {
                                Text(mode == .signUp ? "Create account" : "Sign in")
                                    .font(LoreType.button)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                    }
                    .background(LoreColor.ink, in: Capsule())
                    .foregroundStyle(LoreColor.bone)
                    .disabled(!canSubmitCredentials)

                    // Third-party sign-in ships in Release as of 2026-07-16:
                    // Sign in with Apple is provisioned end to end (App ID
                    // capability + entitlement + live Supabase Apple provider),
                    // which satisfies Guideline 4.8 for the Google/Facebook
                    // options offered alongside it.
                    socialDivider
                    if mode == .signIn { accountCreationConsent }
                    socialButtons

                    // Switch between sign in and account creation; reset link
                    // only in sign-in mode.
                    VStack(alignment: .leading, spacing: 12) {
                        Button(mode == .signUp ? "Have an account? Sign in" : "New here? Create an account") {
                            mode = (mode == .signUp) ? .signIn : .signUp
                            confirmedMinimumAge = false
                            auth.lastError = nil
                            auth.lastNotice = nil
                            focusedField = .email
                        }
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.brass700)
                        .disabled(isWorking)
                        if mode == .signIn {
                            Button("Forgot password?") {
                                run(.passwordReset) {
                                    await auth.sendPasswordReset(email: email)
                                }
                            }
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.ink600)
                            .disabled(!AuthService.isValidEmail(email) || isWorking)
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
                    Button("Close", action: cancelAndDismiss)
                }
            }
        }
        // The sheet is painted with fixed light brand colors (bone/ink); pin the
        // scheme so the nav chrome + sheet grabber don't render dark on a
        // dark-mode device (matches ProfileScreen/SettingsView).
        .preferredColorScheme(.light)
        .onDisappear {
            actionTask?.cancel()
            apple.cancel()
        }
    }

    @ViewBuilder
    private var policyLinks: some View {
        Link("Terms of Use", destination: URL(string: "https://lore-web-liart.vercel.app/terms")!)
        Link("Privacy Policy", destination: URL(string: "https://lore-web-liart.vercel.app/privacy")!)
    }

    private var accountCreationConsent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("I am 13 or older", isOn: $confirmedMinimumAge)
                .font(LoreType.caption)
                .tint(LoreColor.brass700)

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    mode == .signUp
                        ? "By creating an account, you agree to:"
                        : "Social sign-in may create an account. By continuing, you agree to:"
                )
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { policyLinks }
                    VStack(alignment: .leading, spacing: 6) { policyLinks }
                }
            }
            .font(LoreType.micro)
            .foregroundStyle(LoreColor.ink600)
            .tint(LoreColor.brass700)
        }
    }

    private func statusMessage(_ message: String, symbol: String, color: Color) -> some View {
        Label(message, systemImage: symbol)
            .font(LoreType.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
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
            run(.apple) {
                do {
                    let cred = try await apple.signIn()
                    await auth.signInWithApple(
                        idToken: cred.identityToken, rawNonce: cred.rawNonce,
                        fullName: cred.fullName, email: cred.email,
                        confirmedMinimumAge: confirmedMinimumAge
                    )
                } catch AppleSignInCoordinator.AppleSignInError.cancelled {
                    // User backed out of the Apple sheet — nothing to show.
                } catch {
                    // Everything else (missing token, network, keychain) must
                    // surface — an empty catch here left the button feeling dead.
                    // Shown via auth.lastError (SignInView renders it).
                    auth.lastError = AuthService.userFacingMessage(for: error)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if operation == .apple {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "apple.logo")
                    Text("Continue with Apple").font(LoreType.button)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(Color.black, in: Capsule())
            .foregroundStyle(.white)
        }
        .disabled(!canStartSocialAuthentication)
        .accessibilityHint(
            confirmedMinimumAge
                ? "Uses your Apple account to continue"
                : "Confirm that you are 13 or older before continuing"
        )
    }

    /// A Supabase OAuth provider button (web flow).
    private func oauthButton(
        _ title: String, provider: String,
        background: Color, foreground: Color, bordered: Bool = false
    ) -> some View {
        Button {
            run(.oauth(provider)) {
                await auth.signInWithOAuth(
                    provider: provider,
                    confirmedMinimumAge: confirmedMinimumAge
                )
            }
        } label: {
            Group {
                if operation == .oauth(provider) {
                    ProgressView().tint(foreground)
                } else {
                    Text(title).font(LoreType.button)
                }
            }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(background, in: Capsule())
                .foregroundStyle(foreground)
                .overlay {
                    if bordered {
                        Capsule().strokeBorder(LoreColor.ink.opacity(0.15), lineWidth: 1)
                    }
                }
        }
        .disabled(!canStartSocialAuthentication)
        .accessibilityHint(
            confirmedMinimumAge
                ? "Opens the provider's secure sign-in flow"
                : "Confirm that you are 13 or older before continuing"
        )
    }

    private func submitCredentials() {
        guard canSubmitCredentials else { return }
        focusedField = nil
        run(.credentials) {
            if mode == .signUp {
                await auth.signUp(email: email, password: password)
            } else {
                await auth.signIn(email: email, password: password)
            }
        }
    }

    private func run(_ nextOperation: Operation, action: @escaping @MainActor () async -> Void) {
        guard operation == nil, !auth.isBusy else { return }
        operation = nextOperation
        auth.lastError = nil
        auth.lastNotice = nil
        actionTask = Task { @MainActor in
            defer {
                operation = nil
                actionTask = nil
            }
            await action()
            guard !Task.isCancelled else { return }
            if auth.isSignedIn { dismiss() }
        }
    }

    private func cancelAndDismiss() {
        actionTask?.cancel()
        apple.cancel()
        dismiss()
    }
}
