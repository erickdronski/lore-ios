# Lore iOS → TestFlight runbook

State as of 2026-07-06: the native SwiftUI app (94 files, iPhone-first, iOS 17+)
parses clean on Swift 6.3.2. Everything that can be prepared without your Apple
account IS prepared; what remains is ~45 minutes of founder clicking, because
Apple requires the account holder for signing and upload. This machine has only
Command Line Tools (no full Xcode), so the archive must happen on your Mac with
Xcode installed.

## What is already done (no action needed)
- App target + LoreWidget extension speced in `project.yml` (XcodeGen), bundle
  `com.erickdronski.lore`, team `J9DMDH4S58`, iOS 17.0, iPhone-only (deliberate, see
  docs/10 §1 in the lore repo).
- StoreKit 2 service + local `StoreKit/Lore.storekit` config (Lore+ products),
  Sign in with Apple coordinator, WidgetKit widget, tour Live Activity +
  Dynamic Island, push scaffold, deep links (`lore://`), purpose strings locked
  from the legal docs.
- Portal-gated entitlements are deliberately COMMENTED in `project.yml`
  (Sign in with Apple, aps-environment, App Groups) so the first build signs
  without portal work; uncomment as you enable each capability later.

## The founder path (in order)

1. **Install Xcode** from the App Store (or `xcodes`), open once, accept the
   license, let it install iOS platform support.
2. **Generate the project**: `brew install xcodegen` then, in this repo,
   `xcodegen generate` → produces `Lore.xcodeproj`.
3. **Open `Lore.xcodeproj`**, select the `Lore` scheme, run once in the
   Simulator (sanity: app boots to the map shell).
4. **Signing**: project → targets `Lore` and `LoreWidget` → Signing &
   Capabilities → check "Automatically manage signing", team `J9DMDH4S58`.
   Xcode will create the App ID `com.erickdronski.lore` + profiles on the portal.
5. **App Store Connect** (appstoreconnect.apple.com): My Apps → "+" → New App →
   platform iOS, name **Lore**, bundle `com.erickdronski.lore`, SKU `lore-ios`.
   (Listing copy, keywords, and screenshot plan live in lore repo
   `docs/10-APPSTORE.md`; screenshots can come later, TestFlight does not
   need them.)
6. **Archive + upload**: in Xcode, destination "Any iOS Device (arm64)" →
   Product → Archive → Distribute App → TestFlight & App Store → Upload.
7. **TestFlight tab** in App Store Connect: the build appears after
   processing (~10-30 min). Answer the export-compliance question (the app
   uses only standard HTTPS: answer "standard encryption, exempt";
   `ITSAppUsesNonExemptEncryption` is already false in the Info.plist).
   Add yourself as an internal tester → install via the TestFlight app.

## Gotchas we already routed around
- Do NOT enable the commented `UIRequiredDeviceCapabilities` (arkit/gps) yet;
  they are irreversible once shipped and the scaffold runs on any iOS 17
  device (docs/10 §1).
- The widget shows sample content until App Groups are provisioned; that is
  by design (no crash), enable the group later with the other entitlements.
- If Xcode complains the CLT is selected: `sudo xcode-select -s
  /Applications/Xcode.app/Contents/Developer`.

## After the first TestFlight build
- P1 wiring: MapLibre Native for the 3D map (same style doctrine as web),
  live Supabase data on device, the AR scanner spike (docs/05), then real
  screenshots for the listing from the device.
