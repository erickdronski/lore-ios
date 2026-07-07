# Lore — Persona Research Roadmap (2026-07-07)

Synthesized from **42 persona agents / 532 findings** (tourists, first-timers,
engineers, architects, teachers, parents, accessibility users, the high-density
explorer, the journaler, the ASO marketer, the elite-app benchmarker, and more),
clustered across 4 domains, then merged into positioning + waves. Raw JSON:
`scratchpad/roadmap_raw.txt`.

## Positioning

**"Lore — the living history and memory layer over your world."**
Promise (App Store + onboarding): *"Point your camera at anything around you and
its story appears — then save the places that move you and add your own."*
The same surfaces read as **fun + quick** for a commuter, **fun + educational**
for a historian, **fun + expansive** for a local building lists — no mode switch.

## The single next massive step

Ship the **"See it → Save it → Make it yours" memory loop** as the app's second
pillar, with the **scanner as the front door**. The codebase is ~80% wired for
it (VisitStore already does optimistic "been here" + achievements) but has **zero
save/list UI**. Three connected pieces:
1. **Save + Lists** — the missing half of the product. Heart control on every
   place surface, a "Saved" section in Profile, named private lists.
2. **Scanner as front door** — the hero the App Store sells is currently Tab 2
   with no discoverable entry. Add a Finish-step teaser + a first-7-days nudge.
3. **Celebratory lock** — a 2-second "Locked!" moment with inline Save + Capture.

## The journaling loop (full circle)

See → **Save** → Mark visited → **Note** (private text + rating) → **Collect**
(named lists) → Earn (Passport/streak) → Share → Revisit. Save sits *before*
Share in the visual order — archive first, share second.

## Vetted UGC-density design ("a curated few, not a flood")

User lore is **never a peer** of editorial lore. Three visibility lanes on the
Scout→Curator trust ladder:
- **Pending (hidden)** — every submission enters `pending_review`; author-only.
  The moderation floor that MUST exist before any public/media.
- **Community (below the fold)** — approved Scout-tier lore renders **inside the
  dossier only**, a distinct "From explorers" section (Bone card, not the Ink
  editorial voice), with handle + read-count. Never a pin, never a scanner claim.
- **Curated (featured)** — Curator/editor-picked gets **one** "Editor's pick"
  slot on the Layer-1 card, Brass-accented, capped at one per place.
Density caps per place + per viewport keep a 200-submission block calm.

## Delivery waves

**Wave 1 — blind-shippable quick wins (copy + clarity, no backend):**
rewrite onboarding arrival + finish copy to lead with action + memory; **Save
(heart) on the place card, before Share**; consistent price copy; editable share
caption + auto hashtags; city-chip "tap to change" affordance; skeleton near-me
shelf on first load.

**Wave 2 — the memory pillar (small backend: list/list_item):** Saved section +
named lists in Profile; private note + rating on saved places; streak model +
Passport counter + closest-to-unlock; broaden onboarding personas (foodie,
memory-keeper, sacred-site).

**Wave 3 — scanner as front door + wow moment:** celebratory lock with inline
Save + Capture; post-onboarding scanner nudge + finish teaser; audio narration
as a primary lock affordance.

**Wave 4 — trust + premium framing:** provenance footer + report-error on every
dive; confidence/depth signals ("3 min read", "Timeline 1850–1920"); reframe the
paywall as a **membership** (a club, not a gate); server push + daily widget
refresh.

**Wave 5 — vetted public UGC + media (heaviest, behind flags, ship last):**
moderation queue + pending/community/curated lanes; media uploads with age-gate +
content warnings; contributor teaching + Scout→Curator progression.

## What this session already shipped against the roadmap

- **Default-Chicago fix** (W1-adjacent) → nearest-city auto-select. ✅ shipped
- **Session persistence** (relaunch keeps you signed in). ✅ shipped
- **Place-card story teaser** (fills free-user space). ✅ shipped
- **Collapsible near-me + swipeable quotes + uniform tiles**. ✅ (last one pending CI billing)
- **Live Lore+ paywall** off Profile (was a dead "Coming" stub). ✅ shipped
- Mount Laurel expanded to 7 places incl. Paulsdale/Alice Paul. ✅ live in DB

Next up per waves: **Wave 1 Save button + onboarding copy**, then **Wave 2 Lists**
(the next massive step). Blocked on CI billing to ship (see below).
