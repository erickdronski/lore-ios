# Expansion Roadmap (founder vision, 2026-07-07)

Captured from the founder's overnight direction. Three big workstreams beyond the
items already shipped. Each needs a real design/build; two need a product call
before I build them wide (flagged 🟠). None should be blind-shipped overnight
against the founder's own "must be polished, no contrast/spacing/overlap issues"
bar — especially the visual effects, which I can't see from here.

---

## Already shipped in response to this vision

- **Current-location in the top header, gated to sign-in.** Header locate button;
  signed-out taps nudge sign-in, signed-in recenters on the live GPS fix. Server
  persistence of the location ping is TODO'd for the backend pass below.
- **Mount Laurel, NJ — the founding easter egg + first small-town coverage.**
  Seeded live: the city, plus 4 places — *Where Lore Was Founded* (founder lore,
  with a full deep-dive), *Laurel Acres Park*, *The Mount Laurel Doctrine*, and
  *Jacob's Chapel & Colemantown*. The founding pin sits at the town center
  (~39.9436, -74.8912); give me your exact coordinate (or drop a pin) and I'll
  move it to the precise spot.

---

## 1. Content depth + coverage (more cities, towns, neighborhoods, legends)

**Goal:** far more per city, more small towns/neighborhoods, and a
mystery/legends layer.

**Plan.** Run the content pipeline in verified batches (draft → fact-check →
seed), so we never ship a wrong fact into a live map:
- A **"Legends & Mysteries" register** per city (a new `tags` lens: `legend`,
  `mystery`, `unsolved`, `haunting`) surfaced as its own themed shelf, reusing the
  themed-lens chips already on the map rail.
- **Neighborhood + small-town coverage**: Mount Laurel is the template. Batch the
  next towns the same way (real places, careful coordinates, cited facts).
- **Density pass** on flagship cities: 2-3x the places, each with a dive.

🟠 **Need from you:** which towns/regions to prioritize next, and roughly how many
places per city to target. Then I run it as a verified authoring workflow.

## 2. Themed, per-story "living" tile effects  🟠

**Goal (founder's example):** the Ben Franklin kite tile gets a subtle lightning
motif behind it; each story's card carries a polished background that matches its
theme — never overlapping text, never hurting contrast.

**Plan — a theme engine, not one-off art:**
- A `StoryTheme` enum derived from a place's `tags` (e.g. `electricity` →
  lightning, `maritime` → slow tide, `aviation` → drifting clouds, `founding` →
  soft ember rise). One reusable, GPU-cheap effect per theme, all Reduce-Motion
  aware.
- Effects render **behind a legibility scrim** so text contrast is guaranteed by
  construction (the founder's hard constraint). The scrim + effect live below the
  content layer with fixed max opacity.
- Ship behind a flag, one theme at a time, each visually reviewed before the next.

🟠 **Need from you (or a screen share):** this is the one I explicitly should NOT
blind-ship — you were clear it must be reviewed for overlap/contrast/spacing, and
I can't see the simulator from here. Proposed path: I build the Ben Franklin
lightning as a single POC behind a flag, you eyeball it on TestFlight, we tune the
scrim/intensity, then I roll the pattern out theme by theme.

## 3. "Lists" — save, visit, and contribute your own lore

**Goal:** users favorite places into lists, check off visited, and add their own
lore (written story + optional photos/videos), kept private in-app or shared
publicly to premium users.

**What already exists to build on:** `VisitStore` / `VisitToggle` (visited
tracking) and the Passport reward wall. So "visited" is half-built; "save to a
list" + "my lore" + media are the new surfaces.

**Plan (phased):**
- **P1 — Saved lists (no media):** `list` + `list_item` tables (RLS: owner-only),
  a "Save" control on the place card, a "Lists" tab/section, visited check-off
  reusing VisitStore. Low risk, no uploads.
- **P2 — Personal lore:** a text note + rating per saved place (private).
- **P3 — Media + public:** photo/video upload to Supabase Storage, a
  `visibility` flag (private / public-to-premium), and a moderation gate before
  anything goes public. This is the heavy part (uploads, storage costs, safety).

🟠 **Need from you:** confirm the privacy model (default private; "public" = visible
to premium members only?) and whether P3 media is in-scope now or after launch.

## Backend pass (shared prerequisite)

Small Supabase additions these depend on: `user_location` (the gated locate
ping), `list` + `list_item`, and later `list_item_media` + Storage buckets with
RLS. I'll spec the DDL and apply it as versioned migrations, same as the Mount
Laurel seed.

## Save / Lists — build state (the next massive step)

**DONE — backend is live + verified.** `saved_place` table shipped via migration:
`id, user_id (default auth.uid()), place_id → place, saved_at, note, rating`,
`unique(user_id, place_id)`, owner-only RLS (read/insert/update/delete on
`user_id = auth.uid()`), mirroring the `visit` table. A `place_id`-only POST
satisfies RLS via the `auth.uid()` default (same shape as `logVisit`).

**READY — iOS build (staged, not blind-shipped onto the crashing/unshippable
build).** Each piece is a faithful mirror of the proven visit path:
1. `LoreAPI.savePlace(placeID:accessToken:)` → `write("saved_place", POST, {place_id}, prefer:"return=minimal")`; `unsavePlace(...)` → DELETE `saved_place?place_id=eq.{id}`; read via a `TravelReads.saved(accessToken:)` mirroring `visits(...)` (`select=place_id,saved_at&order=saved_at.desc`).
2. `SaveStore` — exact copy of `VisitStore` (savedPlaceIDs set, inFlight, load(force:), save/unsave optimistic + rollback, credentials closure, reset()).
3. `TravelSession` — add `let saves: SaveStore`, wire the same credentials closure; `bootstrap` calls `saves.load()`.
4. `LoreApp` — `.environment(travel.saves)`; `syncSession` resets saves on sign-out.
5. `SaveButton` (heart) — mirror `VisitToggle`; place on the PlaceCardView header **before** Share (roadmap: archive-first), and on NearMeCard + search rows.
6. `ProfileScreen` — a "Saved" section listing saved places grouped by city.

Ship this the moment CI billing is restored (and ideally after the city-switch
crash fix), verified together in one green build.
