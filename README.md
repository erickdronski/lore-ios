# Lore for iPhone

This repository is the only native shipping and TestFlight lane for Lore. It is
a SwiftUI iPhone app generated from `project.yml` with XcodeGen.

Lore is a curated city guide. A user can browse a living map, point the
camera at chronicled places, open historical stories, follow walks, listen to
narration, and keep a private visit journal. Coverage is curated city by city;
the app does not claim to recognize every building or object or to have a
source link for every catalog record.

## Release State

- Marketing version: `1.0`
- Bundle ID: `com.erickdronski.lore`
- Widget bundle ID: `com.erickdronski.lore.LoreWidget`
- Minimum platform: iOS 17, iPhone only
- App Store Connect app ID: `6788171860`
- Last uploaded baseline: build 56 from commit `bb73031` on July 14, 2026
- Current working tree: release-hardening candidate; it must pass CI and be
  uploaded as a new build before review

The app and widget version must remain identical. Build numbers are assigned by
Fastlane from the selected App Store version train.

## What Ships

- First-run onboarding with optional location permission
- Map, city switcher, search, place cards, deep dives, and culture content
- Live camera scanner using camera, location, heading, motion, and Apple
  frameworks to rank known nearby places
- Optional, explicit `Identify with Google` action that sends one confirmed
  frame to the authenticated Supabase Edge Function and Google Cloud Vision
- Curated walking tours and an on-device tour Live Activity
- Passport, visits, private notes/photos, and achievements
- Email/password authentication with Keychain-backed session restoration
- Password recovery that finishes on Lore's secure web reset screen
- In-app account deletion through the authenticated `delete-account` function
- StoreKit 2 Lore+ purchase, eligibility-aware trial copy, and restoration
- Share links through the live web `/p/[slug]` redirect route

## What Does Not Ship

- Public contributions or media submissions
- Offline city-pack sales
- Apple, Google, Facebook, or X sign-in in Release builds
- ARCore Geospatial or Streetscape Geometry
- RevenueCat, PostHog, Sentry, advertising, or cross-app tracking
- Background location or notification permission during onboarding

Do not add these items to App Store metadata or legal copy until the complete
feature, consent, moderation, security, and review path is implemented.

## Scanner Data Flow

Normal scanning stays on-device. Lore does not store continuous camera video or
continuous location history. The separate Google identification action:

1. Requires a signed-in user.
2. Shows a disclosure and confirmation before upload.
3. Sends one current JPEG to the `landmark-id` Edge Function.
4. Enforces payload and per-user quotas server-side.
5. Relays the request to Google Cloud Vision without storing the frame in Lore
   Storage.

The camera purpose string, privacy manifest, App Store privacy answers, and
Privacy Policy must continue to describe this same flow.

## Lore+

| Product ID | Type | U.S. reference price |
|---|---|---:|
| `lore_plus_monthly` | Monthly auto-renewable | $5.99 |
| `lore_plus_annual` | Annual auto-renewable | $34.99 |
| `lore_plus_lifetime` | Non-consumable | $99.99 |

Monthly and annual may show a seven-day introductory trial only when StoreKit
reports the user as eligible. Optional Trip Pass code remains hidden unless the
matching App Store products exist.

Lore+ unlocks unlimited deep dives, curated walking tours, and full-story
narration. Scanning, maps, place cards, three deep dives per day, visits,
journal features, and badges remain free.

## Build And Test

The project file is generated; do not edit or commit it manually.

```sh
xcodegen generate
bundle install
bundle exec fastlane tests
```

The GitHub workflow in `.github/workflows/ios-testflight.yml` is the release
gate. Pushes and pull requests run tests. TestFlight upload is manual and
requires the `upload_to_testflight` workflow-dispatch input.

The workflow uses App Store Connect API-key and Match secrets stored in GitHub.
No signing key, service-role key, reviewer password, or Google server key belongs
in this repository.

Local machines without the full Xcode iOS SDK can still run:

```sh
swiftc -parse $(git diff --name-only -- '*.swift')
plutil -lint Sources/Lore/PrivacyInfo.xcprivacy \
  Sources/LoreWidget/PrivacyInfo.xcprivacy
```

The final authority is a clean simulator test run plus a signed Release archive
on the same commit that is uploaded.

## Release Sources Of Truth

- App Store copy and reviewer path:
  `/Users/dron/Projects/lore/legal/APP-STORE-LISTING.md`
- Privacy and Terms: `/Users/dron/Projects/lore/legal/`
- Backend migrations and functions: `/Users/dron/Projects/lore/supabase/`
- Web, legal hosting, support, and share routes: `/Users/dron/Projects/lore-web`

Never mix Lore release work with another product repository.
