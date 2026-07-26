# Lore Content Wave 2026-07: Final Independent QA

**Review date:** 2026-07-25
**Scope:** Final read-only release-gate review of the four regional JSON files,
`missing-dives.json` and generated SQL, content compilers and tests, wave README,
editorial and experience standards, and the relevant Swift models, API, rendering,
source-link, phrase-TTS, dossier, timeline, and narration paths.
**Repository changes from this review:** This report only. No content, SQL, Swift,
test, or configuration file was edited, and no commit was created.

## Release verdict

**PASS FOR `reference_only`; BLOCKED FROM PROMOTION TO `reviewed`.**

The completed July 2026 wave is safe to publish in the repository's explicitly
limited `reference_only` state. Its source artifacts are complete and reproducible,
the required traveler-kit and dossier floors pass automated validation, generated
SQL matches the checked-in SQL, source health has no unresolved dead or server-error
result, and the current Swift integration compiles with the new content shapes.

This verdict does **not** certify the material as human-reviewed editorial content.
The regional records deliberately retain `reference_only` provenance and pending
review metadata. They must not be relabeled, represented, or promoted as `reviewed`
until the human gates below are completed and documented item by item.

## Verified release evidence

| Artifact | Final result |
| --- | ---: |
| Covered destination slugs | **141** |
| Regional rows | **1,833** |
| `phrase` rows | **846** (6 per destination) |
| `drink` rows | **282** (2 per destination; all explicitly zero-proof) |
| `etiquette` rows | **564** (4 per destination) |
| `market` rows | **141** (1 per destination) |
| Regional publication state | **1,833 `reference_only`; 0 other states** |
| Missing-place dossiers | **44** unique place IDs |
| Dossier narrative words | **24,775** total; 551-606 per dossier |
| Timeline events | **151** total; 3-4 per dossier, oldest first |

- Both content compilers pass. Regeneration under `/tmp` matched
  `regional-sections.sql` and `missing-dives.sql` byte for byte.
- The regional compiler enforces exact 6/2/4/1 coverage, 141 unique destinations,
  required fields, HTTPS sources, CC0 text, zero-proof drink metadata, phrase
  fields, stable sort ranges, and `reference_only` provenance.
- The dossier compiler enforces 44 canonical unique place IDs, 550-1,000-word
  narratives, 3-7 chronological events, JSON object shapes, HTTPS sources, and
  CC0 text. Its SQL validates that every dossier resolves to a live place before
  applying the idempotent upsert and leaves existing audio fields untouched.
- All **21** content-wave tests and all **6** read-only content-audit tests pass.
  The iOS test run passed **27 of 27** tests with zero failures on an iPhone 17 Pro
  simulator. The resulting app installed and launched successfully on that device
  and on a 13-inch iPad Pro simulator, with no launch crash or visible clipping.
- Swift integration is compatible: city sections decode provenance and source URLs,
  group and render the new kinds in stable order, and use phrase language/original
  script for TTS. Dossiers decode narrative, timeline, links, and media, retain text
  when offline, and fall back to on-device TTS when studio audio is absent.

## Source health

The combined deduplicated sweep covered **766 unique primary sources**. It classified
**737 reachable**, **28 bot-gated**, and **0 dead**; the remaining official JNTO
source transiently returned HTTP 502 and returned HTTP 200 on an immediate targeted
retry. There are therefore no unresolved dead or error sources in the release gate.

Bot-gated means automated retrieval was refused or rate-limited, not that the source
is dead. Those 28 sources still require manual claim-level inspection before the
affected items can become `reviewed`.

## What automation does and does not prove

Automated validation proves artifact shape, counts, required coverage, deterministic
compilation, SQL reproducibility, URL transport status, basic provenance fields,
decoder compatibility, and test-covered rejection paths. It does not prove that a
claim is correct, a source directly supports every displayed claim, wording is
culturally accountable, pronunciation and register are natural, or traveler advice
is safe and current in the field.

All 1,833 regional rows identify automated editorial research and retain pending
human review state. The automated pass is therefore sufficient for the deliberately
limited `reference_only` lane, but it cannot satisfy the standards' fact, language,
cultural-safety, accessibility, route/field, or final editorial approval gates.

## Blocks on promotion to `reviewed`

Promotion remains blocked until all applicable work is completed and recorded:

1. A human editor/fact reviewer must open the claim-level sources, verify every
   material claim, resolve bot-gated evidence manually, narrow unsupported claims,
   and record reviewer and review date.
2. Qualified speakers must review local script, language/variety, natural meaning,
   pronunciation or transliteration, register, and real use context for every
   applicable phrase. Automated or machine-assisted language work is not approval.
3. Community-preferred sources and documented community or specialist review are
   required where content concerns Indigenous names and relationships, living
   communities, sacred or memorial settings, contested history, colonization,
   displacement, enslavement, conflict, trauma, or other sensitive identity claims.
4. Human traveler, accessibility, copy, and technical QA must confirm mutable
   guidance, source affordances, long-text rendering, Dynamic Type, VoiceOver,
   offline/TTS behavior, and any relevant route or field conditions on device.
5. Promotion must occur item by item only after the applicable provenance record is
   complete. A passing batch compiler or healthy URL must never bulk-promote this
   wave from `reference_only` to `reviewed`.

**Final gate:** Publish the wave as `reference_only` is approved. Promotion of any
item to `reviewed` remains blocked until its required human, qualified-speaker, and,
where applicable, community/specialist reviews are complete and documented.
