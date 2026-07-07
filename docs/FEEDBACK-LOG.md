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

## Scoped features — real work, need a proper build + your review (not shipped blind)

| # | Note | Plan |
|---|------|------|
| 1 | "SO much more areas to explore in Philadelphia / all our cities" | Content depth, not code. Philadelphia is sparse vs. our flagship cities. Queued against the seed pipeline. |
| 5 | "How does a user change the city here? (Tours) so they see city-specific tours" | Tours is locked to the default city for the "1 Hour In" hero. Wire the shared city selection (we already have `CitySwitcherView`) into the Tours screen + hero. |
| 6 | "Allow a user to click on these and open the place tile/card" | Map pins, near-me cards, and famous faces are already tappable — need your screenshot to see which list isn't. Likely the Meet-the-City places or search results. |
| 7 | "Swipe down on 'Around you right now' to give the map more space — draggable, hideable" | Convert the fixed bottom near-me shelf into a draggable/collapsible sheet with detents. Nice ask; it's a real interaction change to the map's bottom layout, so I want to build + test it, not guess. |
| 8 | "Filters should be here for USA, Asia, Europe, etc." | Add a region field to the city model + region filter UI on the explore/cities list. |
| 11 | "Dropdown icon is overlapping the emoji/icon on the tile" | Couldn't find the exact tile in code (the map header's chevron sits next to text, no emoji). Need the screenshot to pinpoint which tile. |
| 12 | "Photo of the place should be in the first tile when clicked" | Place data has no photo field today; we resolve Wikipedia imagery for the deep dive and famous faces. Add an async hero image to the place card using the same Wikipedia service. |
| 13 | "Profile needs preferences, permissions, dark/white mode, manage portal (Stripe) policies, haptics…" | Biggest item — a real Settings build-out. Includes a proper **dark-mode toggle** (right now we force light to dodge the contrast bug; the correct fix is to make dark mode readable and let the user choose). Manage-subscription links to the App Store / RevenueCat portal, not Stripe, on iOS. |
| 15 | "More text on these slang tiles that I can't click into / read further" | Lingo flip cards cap the back at 6 lines. Add tap-to-expand to a full definition sheet. |
| 4 / 16 | "You need to be able to swipe here" / "Make this swippable" | Ambiguous without the screenshots — need to see which surfaces. |

## Needs you (I can't do these from here)

| # | Note | Why |
|---|------|-----|
| 18 | "Sign in with Apple doesn't work" | Needs the App ID **Sign in with Apple** capability enabled in the Developer portal + the Apple provider configured in Supabase (Services ID + key). Google sign-in is already live; Apple needs these two switches. This is queued as task #32. |
| 13 (Stripe) | "manage portal (Stripe) policies" | Subscriptions on iOS go through Apple IAP / RevenueCat, which needs the Paid Apps agreement + banking accepted in App Store Connect, then a RevenueCat account. |

---

*Sweep also checked Crashes: no crash feedback. Session stayed authenticated.*
