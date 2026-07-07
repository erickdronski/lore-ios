# TestFlight Feedback Log

Founder review pass captured from App Store Connect → TestFlight → Screenshot
Feedback. **All 18 notes below were left on build `1.0 (1)` — the very first
build.** Roughly a dozen builds have shipped since, so several items are already
fixed in the latest TestFlight build and only need a device update to disappear.

Legend: ✅ shipped · 🟡 already fixed in a later build (update to verify) ·
🔨 scoped feature (needs a real build + your eyes) · 🙋 needs you (portal/config)

---

## Shipped this pass (build with commit `ce6f011`, CI green)

| # | Note | What shipped |
|---|------|--------------|
| 3 | "Don't we need directions wired up here? Total distance? Total time? Significance?" | Directions button shipped earlier (`07836af`). Now added a **facts strip** to the tour header: total walking distance, estimated time, and stop count. "Significance" already lives in the tour blurb/summary line above it. |
| 10 | "There should be a 'current location' icon here in the header" | Added a **center-on-my-location** control to the map's floating controls (top-right, with 3D/Satellite). Follows the live GPS fix; falls back to the city frame if location isn't granted yet. Put it with the other map controls rather than the header, which already holds city/Meet/Search — say the word if you want it moved into the header row. |

## Shipped — second pass (scoped backlog, after "keep going")

| # | Note | What shipped |
|---|------|--------------|
| 5 | "How does a user change the city here? So they can see city-specific tours?" | Tours now follows the **shared active city**. A Brass city chip in the "Made for you" header opens the city switcher; picking a city re-scopes both the "1 Hour In {city}" hero and the curated tour list. (Previously Tours was locked to Chicago.) |
| 12 | "Photo of the place should be in the first tile when clicked on" | Place cards now show a **Wikipedia lead photo** at the top (same curated source the deep-dive gallery uses), with a shimmer while it loads and a clean self-hide when a place has no image. |
| 15 | "There's more text on these slang tiles that I can't click into or read further" | **Touch-and-hold** a Local Lingo / Sayings card to open the full definition + example in a sheet (no line cap). Tap-to-flip still works as before. |
| 8 | "Filters should be here for USA, Asia, Europe, etc." | The city switcher now groups cities by **region — United States, Europe, Asia, Americas, Middle East & Africa, Oceania** — from each city's country code (was just US / International). |
| 13 (partial) | "Profile needs preferences, permissions, manage subscription, haptics…" | New **Settings** screen off Profile: a working **haptics on/off** toggle (gates every haptic app-wide), **Permissions** deep-links (Location / Camera / Notifications → iOS Settings), **Manage subscription** (Apple's subscriptions page) and **Restore purchases**. |

> **Not shipped — dark/light toggle (part of #13, and #17):** deliberately held.
> The app pins light mode because the fixed Ink/Bone/Brass palette isn't yet an
> adaptive dark theme — flipping to dark re-creates the exact "can't read the
> tiles" contrast bug you reported. A real dark mode is a separate design-system
> pass (making every surface adaptive), not a one-line toggle. Tracked for that
> pass rather than shipped broken.

## Already fixed in a later build — update your TestFlight app to confirm

| # | Note | Status |
|---|------|--------|
| 2 | "Hard to read text here, make sure this works and is wired up correctly" (search) | 🟡 Fixed by the forced-light-mode build (`ec6c900`). This was the dark-mode contrast bug. |
| 9 | "Contrast is pretty harsh here and hard to read text" | 🟡 Same dark-mode fix. |
| 14 | "Contrast here is really bad and tough to read all the text" | 🟡 Same. |
| 17 | "Can't read 'Profile' or the text in each tile, really strong contrast" | 🟡 Same dark-mode fix (Profile tiles). Verify after update; if still harsh in light mode, it's a genuine tune we'll do under the Profile work (#13). |

> **The single most useful thing you can do: delete the app and reinstall the
> latest TestFlight build.** You're on 1.0(1); the current build is ~a dozen
> ahead and already carries the dark-mode fix, the directions button, the app
> icon with the globe, Google sign-in, tour totals, and the locate control.

## Scoped features — still open (need your screenshot or a bigger build)

| # | Note | Plan |
|---|------|------|
| 1 | "SO much more areas to explore in Philadelphia / all our cities" | Content depth, not code. Philadelphia is sparse vs. our flagship cities. Queued against the seed pipeline. |
| 7 | "Swipe down on 'Around you right now' to give the map more space — draggable, hideable" | Convert the fixed bottom near-me shelf into a drag-to-collapse panel. Fully spec'd and buildable, but it changes the map's bottom layout, so I want to build + eyeball it rather than ship it blind overnight. Next build. |
| 6 | "Allow a user to click on these and open the place tile/card" | Map pins, near-me cards, and famous faces are already tappable — need your screenshot to see which list isn't. Likely the Meet-the-City places or search results. |
| 11 | "Dropdown icon is overlapping the emoji/icon on the tile" | The prime suspect (map-header chevron) sits next to text, not an emoji, so the guess is weak. Need the screenshot to pinpoint the exact tile. |
| 4 / 16 | "You need to be able to swipe here" / "Make this swippable" | Ambiguous without the screenshots — need to see which surfaces. Likely resolved by the #7 draggable panel if they point at the near-me shelf. |

## Needs you (I can't do these from here)

| # | Note | Why |
|---|------|-----|
| 18 | "Sign in with Apple doesn't work" | Needs the App ID **Sign in with Apple** capability enabled in the Developer portal + the Apple provider configured in Supabase (Services ID + key). Google sign-in is already live; Apple needs these two switches. This is queued as task #32. |
| 13 (Stripe) | "manage portal (Stripe) policies" | Subscriptions on iOS go through Apple IAP / RevenueCat, which needs the Paid Apps agreement + banking accepted in App Store Connect, then a RevenueCat account. |

---

*Sweep also checked Crashes: no crash feedback. Session stayed authenticated.*
