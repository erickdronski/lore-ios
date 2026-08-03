# App Store Submission Log — 2026-08-03

Firsthand record of the session that submitted **Lore 1.1 (build 27)** to Apple App Review.
Companion to the end-to-end story in [`lore/docs/JOURNEY.md`](../../lore/docs/JOURNEY.md) and the
durable DB record in `lore_ops.release_log` (Supabase project `uiuwzymvyrgfyiugqlkp`).

## Outcome

**Lore 1.1 (build 27) is SUBMITTED — status "Waiting for Review"** (up to 48h; Apple emails on decision).
Submitted via the App Store Connect **web UI** (not the CI submit lane, so the `APP_REVIEW_HOLD=true`
CI guard did not apply), under explicit owner authorization.

## Build

- **1.1 (27)** — CI run [`30837170447`](https://github.com/erickdronski/lore-ios/actions/runs/30837170447),
  HEAD commit `afac440` ("Fix near-me cards clipped by the tab bar (Discovery Deck)").
- Dispatched with `gh workflow run ios-testflight.yml --ref main -f upload_to_testflight=true`.
  The work GitHub account (`Erick-Dronski_ivanti`) was active and 403'd ("Must have admin rights");
  fixed with `gh auth switch --user erickdronski`.
- Carries the tab-bar clipping fix + all of the day's server-side content elevation (hooks, building
  facts, tours, city themes, flagship narration) which renders regardless of build.

## Pre-submission adversarial audit — ✅ GO, 0 blockers

A 6-lens multi-agent audit read the whole codebase and adversarially verified every finding.
All candidate blockers were refuted or downgraded to non-blocking:

| Lens | Result |
|---|---|
| Guideline 3.1.2 (EULA/Privacy links for auto-renew subs) | Description carries the Apple Standard EULA URL + `lore-web-liart.vercel.app/privacy`; verifier confirmed the host is the live **production** alias (not a dead preview) and `/terms` + `/privacy` resolve |
| App Privacy labels vs code reality | See reconciliation below |
| StoreKit / paywall (2.1 / 3.1.1) | No purchase control renders without a backing product (trip-pass section hidden when products nil); Restore lives on the paywall |
| Sign in with Apple (4.8) + account deletion (5.1.1v) | The `#if DEBUG` social-container trap is fixed — Apple renders first/prominent in Release; deletion re-verifies the session and shows an honest failure card |
| Honesty / fabrication | No mock/placeholder data on user surfaces; empty offer sections hide gracefully |
| Build / version integrity | MARKETING_VERSION 1.1, bundle id `com.erickdronski.lore`, SIWA entitlement applied to Release |

## App Privacy labels reconciled to the binary manifest

The ASC labels were stale relative to build 27's `PrivacyInfo.xcprivacy`. Corrected (code-verified):

- **Removed Precise Location** — the app requests precise accuracy **on-device only** (AR placement,
  near-me ranking, tour geofencing) and never transmits coordinates (`logVisit` sends `{place_id, source}`).
- **Added Name** (display name PATCHed to the profile; SIWA fullName) — App Functionality / Linked / not tracking.
- **Added Coarse Location** (visit rows persist `place_id` = neighborhood-level history) — App Functionality / Linked / not tracking.
- **Added Product Interaction** (visit + achievement + preference events) — App Functionality / Linked / not tracking.

Result: **8 data types** — Photos/Videos, Other User Content, User ID, Purchase History, Email Address, Name, Coarse Location, Product Interaction.

## Submission steps (ASC web UI)

1. Confirmed build 27 finished processing → "Ready to Submit".
2. On the 1.1 version (was **Developer Rejected**): removed the attached build 7, **Add Build → 27**, Save → status became "Prepare for Submission".
3. Verified metadata: Description (EULA + Privacy links), What's New (1.1 corrective notes), 10/10 screenshots.
4. Verified App Review Information: contact set; notes cover camera, the Google-identify confirmation disclosure, location/privacy, auth, the Lore+ paywall + Restore, and account deletion.
5. **Add for Review** → Draft Submission (iOS App 1.1 (27)) → **Submit for Review** → *1 Item Submitted*.
   IAPs were already Approved, so only the app version was in the submission.

## Monetization — fully live (verified in ASC)

- Paid Apps Agreement: **Active** (through Jun 11 2027).
- Bank account: **TD Bank …6507 (USD) — Active**.
- Tax: **U.S. Form W-9 — Active**.
- IAPs **Approved**: `lore_plus_monthly`, `lore_plus_annual`, `lore_plus_lifetime`.

## Free ($0) narration

Studio narration uses open-source **Chatterbox TTS** locally on Apple-Silicon MPS — no key, no per-run
cost. A detached, resumable background batch narrates the top ~23 tourist cities in priority order;
on-device TTS remains the free fallback everywhere else, so nothing is ever silent.

## Sign-in model (confirmed with owner)

The app loads and is fully usable **with no account** — browse the map, run the AR scanner, open place
cards, read the daily free deep dives, follow tours. Sign-in only gates **journaling/logging your lore**
and **premium (Lore+)**. This matches the App Review notes and is how 1.0 passed.

## Known non-blocking follow-ups (owner)

1. **Demo credentials** — the review notes reference "the demo account" but no login is in the notes or the
   (unchecked) Sign-In fields. Core app is account-free and Sign in with Apple works, so it's reviewable —
   but adding a real demo login would make purchase/deletion testing bulletproof. (Not fabricated here.)
2. **DSA EU trader-status** — still unattested (Business tab); the app stays EU-excluded until the owner
   completes it. A legal declaration only the owner can make.
3. No physical-device StoreKit purchase test was possible from this environment; Apple reviews IAP on-device.

## Backup / provenance

- Code + docs: GitHub `erickdronski/lore-ios` + `erickdronski/lore` (both clean, on `main`).
- DB record: `lore_ops.release_log` (5 milestones incl. this submission). Supabase project on PRO tier →
  automatic daily backups + 7-day PITR.
