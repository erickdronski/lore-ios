import SwiftUI

/// Email/password sign-in (live against Supabase GoTrue).
///
/// v1 ships email/password only. Native Sign in with Apple + Google OAuth are
/// implemented (`AuthService` / `AppleSignInCoordinator`) but their buttons are
/// held back until the App ID's Sign-in-with-Apple capability + the Supabase
/// Apple provider are provisioned — Guideline 4.8 requires a *working* Apple
/// button wherever Google is offered. Re-enable both in the 1.1 update.
struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Every place has a story.")
                        .font(LoreType.hook)
                        .foregroundStyle(LoreColor.ink600)

                    // v1 ships email/password only. Native Sign in with Apple +
                    // Google OAuth are wired in AuthService/AppleSignInCoordinator
                    // but their buttons are held back until the App ID's
                    // Sign-in-with-Apple capability + Supabase Apple provider are
                    // provisioned (Guideline 4.8: offering Google requires a
                    // working Apple button). Re-enable both in the 1.1 update.

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

}
