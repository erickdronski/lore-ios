# Lore content wave 2026-07

This directory is the reproducible source for Lore's traveler-utility content
wave. It complements the existing landmark, deep-dive, story, culture, fact,
tour, and flavor coverage with content a traveler can use in the moment.

## Coverage

- Regional JSON files add 6 practical phrases, 2 zero-proof drinks, 4 etiquette
  notes, and 1 market guide to every live destination: 1,833 sourced traveler
  cards across all 141 cities, towns, and villages in the roster.
- `missing-dives.json` and its generated SQL add 44 place dossiers totaling
  24,775 words, so every active place in the live city roster has a deep dive.
- `thin-destinations.sql` adds 12 culture profiles and 19 city facts, bringing
  every previously thin target to at least 10 culture rows or 8 facts.
- `derived-interactions.sql` turns each city's existing curated tour,
  soundmark, and material note into an interactive `experience`, `listen`, and
  `field_note` tile when that kind is missing.
- `derived-place-hooks.sql` turns safe-license dossier openings into concise
  scanner hooks without overwriting authored hooks or copying CC BY-SA text
  into an unattributed surface.
- `tour-enrichment.sql` grounds all 119 blank live stop notes in reusable dive
  text and adds 84 safe, same-city fourth stops. Thirteen routes remain short
  because no candidate passed the distance and editorial-relevance gates.
- `achievement-wave.sql` adds 8 earnable visit, map, story, journal, and photo
  milestones using only criteria evaluated by the current progress engine.
- `data-integrity.sql` normalizes London's country code and supplies the one
  missing live-city completion badge for Lagos.
- `offer-integrity.sql` gates both offer feeds on `deal_source.approved`. It
  does not add, edit, or fabricate commercial inventory.
- Every row is idempotent. Re-running the importer updates the same
  `(city, kind, title)` record instead of creating duplicates.

## Publication gates

1. Run `tools/content-audit` against production and save the before report.
2. Validate every regional JSON file and require the exact 6/2/4/1 traveler-kit
   mix per listed city, explicit zero-proof metadata, and clean traveler prose.
3. Review direct source links, local scripts, transliterations, sacred-place
   guidance, and Indigenous or contested naming against
   `docs/CONTENT-EDITORIAL-STANDARD.md`.
4. Import regional rows as `reference_only`; promote an item to `reviewed`
   only after its claims and language have passed editorial review.
5. Publish data in dependency order: `missing-dives.sql`,
   `derived-place-hooks.sql`, `regional-sections.sql`,
   `derived-interactions.sql`, `thin-destinations.sql`,
   `tour-enrichment.sql`, `achievement-wave.sql`, and `data-integrity.sql`.
6. Apply `offer-integrity.sql` as a reviewed Supabase migration because it
   replaces two feed views. Only approved sources may reach the app.
7. Re-run the content audit, feed queries, and app decoding tests before
   publishing.
8. Run `post-publish-verification.sql` and retain its single JSON evidence row
   with the release record.

Lore must leave a destination's offer section empty when no current approved
inventory exists. Empty is preferable to expired, unapproved, or fabricated
commercial content.
