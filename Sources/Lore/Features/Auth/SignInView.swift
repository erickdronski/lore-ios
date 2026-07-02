import AuthenticationServices
import SwiftUI

/// Email/password sign-in (live against Supabase GoTrue) plus a Sign in with
/// Apple button that is present-but-stubbed until P1.
///
/// Guideline 4.8 posture (docs/10 §5 row 3): Sign in with Apple renders
/// **above** every other provider in every sign-in UI. Keep that order.
struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var appleStubMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Every place has a story.")
                        .font(LoreType.hook)
                        .foregroundStyle(LoreColor.ink600)

                    // Sign in with Apple — FIRST, always (guideline 4.8).
                    //
                    // TODO(P1): native flow per docs/11-AUTH-SETUP.md §B.2 —
                    // add the Sign in with Apple entitlement (capability is
                    // already on app.lore.lore), generate a hashed nonce for
                    // the request, then exchange credential.identityToken at
                    // /auth/v1/token?grant_type=id_token (provider=apple,
                    // nonce=rawNonce). Only dashboard prerequisite: bundle id
                    // in the Apple provider's Client IDs list (§B.1 step 4).
                    SignInWithAppleButton(.signIn) { _ in
                        // Intentionally not configuring scopes yet — the
                        // exchange path doesn't exist until P1.
                    } onCompletion: { _ in
                        appleStubMessage =
                            "Sign in with Apple lands at P1 — the native "
                            + "token exchange is specced in docs/11-AUTH-SETUP.md §B.2. "
                            + "Use email sign-in for now."
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    if let appleStubMessage {
                        Text(appleStubMessage)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.info)
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
                        "Reading never requires an account — browsing, the map, "
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
}
