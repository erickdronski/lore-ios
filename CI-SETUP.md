# Cloud build to TestFlight (GitHub Actions + Fastlane)

The Nalee/EAS experience for the native app: push to `main` and a macOS cloud
runner builds Lore and uploads it to TestFlight. No local Xcode, no certs
repo. You do a one-time setup (~15 min) that replaces EAS's Apple-account
link with an App Store Connect API key.

## Why this instead of EAS
EAS builds Expo/React Native apps. Lore's mobile app is native SwiftUI (for
the ARKit AR scanner), which EAS can't build. This pipeline is the native
equivalent: GitHub's macOS runner runs `xcodegen` + `fastlane`, and Xcode's
cloud-managed signing (`-allowProvisioningUpdates`) creates the certificate
and profiles for you, so there is nothing to store or rotate by hand.

## One-time setup

### 1. Create an App Store Connect API key
1. appstoreconnect.apple.com → Users and Access → Integrations → App Store
   Connect API → Team Keys → "+".
2. Name it `lore-ci`, Access role **App Manager** (needed so it can manage
   signing), Generate.
3. Download the `.p8` file (you only get one download). Note the **Key ID**
   and the **Issuer ID** shown on that page.

### 2. Add three repo secrets
In the `erickdronski/lore-ios` repo → Settings → Secrets and variables →
Actions → New repository secret. Add:

| Secret name | Value |
|---|---|
| `ASC_KEY_ID` | the Key ID (e.g. `A1B2C3D4E5`) |
| `ASC_ISSUER_ID` | the Issuer ID (a UUID) |
| `ASC_KEY_CONTENT` | the `.p8` file contents, **base64-encoded** |

To base64 the key on your Mac (no Xcode needed, just Terminal):
```
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```
then paste as the `ASC_KEY_CONTENT` value.

### 3. Make sure the app record exists in App Store Connect
The bundle id `com.erickdronski.lore` needs an app record. If you have not made it:
My Apps → "+" → New App → iOS → name **Lore** → bundle `com.erickdronski.lore` →
SKU `lore-ios`. (Listing copy can come later; TestFlight does not need it.)

## Run it
- Automatic: push to `main` (any change under `Sources/`, `project.yml`,
  `StoreKit/`, `fastlane/`).
- Manual: Actions tab → "iOS · TestFlight" → Run workflow.

The build takes ~10-15 min, then appears in App Store Connect → TestFlight a
few minutes later. Add yourself as an internal tester and install via the
TestFlight app. Answer the export-compliance prompt with "no / exempt"
(`ITSAppUsesNonExemptEncryption` is already false in the app).

## What runs (no action needed, just so you know)
`.github/workflows/ios-testflight.yml` → checkout → latest Xcode → install
XcodeGen → `xcodegen generate` → `bundle exec fastlane beta`, which
(`fastlane/Fastfile`) sets a per-run build number, `build_app` archives with
cloud-managed signing, and `upload_to_testflight` ships it.

## Troubleshooting
- "No profiles / signing" on the first run: confirm the API key role is App
  Manager (not Developer) and the app record exists (step 3).
- Duplicate build number: the pipeline uses the CI run number, so this should
  not happen; if it does, re-run the workflow (the number increments).
- Want a faster path for the very first build only: `lore-ios/TESTFLIGHT.md`
  is the manual Xcode route. After that, this pipeline is hands-off.
