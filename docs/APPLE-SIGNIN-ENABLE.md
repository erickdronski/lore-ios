# Enabling Sign in with Apple (Guideline 4.8)

Lore ships Google + Facebook sign-in, so Apple **requires** Sign in with Apple too
(Guideline 4.8). The app code is already written (`AppleSignInCoordinator` +
`AuthService.signInWithApple`); it's disabled only until the two provider steps
below are done. **Do the OWNER steps first, then the CODE flip** — flipping the
entitlement before the App ID capability exists breaks CI code-signing.

## Owner steps (do these first, ~15 min)

1. **Apple Developer portal** → Certificates, Identifiers & Profiles → Identifiers →
   **`com.erickdronski.lore`** → tick **Sign In with Apple** → Save.
   (If it asks about the primary App ID, keep the default "Enable as a primary App ID".)

2. **Supabase** (project `uiuwzymvyrgfyiugqlkp`) → Authentication → Providers →
   **Apple** → toggle **Enable**. Lore uses the **native id_token** flow, so:
   - In **"Client IDs"** (a.k.a. Authorized Client IDs / for iOS), add
     **`com.erickdronski.lore`**.
   - The Services ID + Secret Key (`.p8`) fields are only needed for the *web* OAuth
     flow, which Lore does not use for Apple — leave them blank unless you also want
     Apple sign-in on the web. Save.

3. Tell Claude "Apple sign-in is set up" and it does the code flip below + pushes a build.

## Code flip (Claude does this once the owner confirms)

1. `project.yml` → under the `Lore` target's `settings`, un-comment:
   `CODE_SIGN_ENTITLEMENTS: Sources/Lore/Lore.entitlements`
   (the `Lore.entitlements` file with `com.apple.developer.applesignin` already exists).
2. `Sources/Lore/Features/Auth/SignInView.swift`:
   - remove `@available(*, unavailable, ...)` from `appleButton`.
   - un-comment `appleButton` in `socialButtons` (it goes **first**, above Google —
     4.8 wants Apple presented at least as prominently as the others).
3. `xcodegen generate` → build → push. CI (fastlane) signs with the now-matching
   entitlement + provisioning profile.

## Verify before submitting
- The login screen shows **Apple, Google, Facebook** (Apple first).
- Tapping "Continue with Apple" completes the native sheet and signs in.
