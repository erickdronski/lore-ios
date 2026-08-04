# Local Expert Addons Production Evidence - 2026-08-02

This wave filled the 139 live Lore cities that were missing the local-expert
addon profile. Rome and Mount Laurel already had the pilot rows, so production
now covers all 141 live cities.

## Production write

- Project: `lore` Supabase project `uiuwzymvyrgfyiugqlkp`
- Applied: `2026-08-02`
- Rows added for the 139-city expansion: `1,946`
- Total `2026-08` `local-expert-addons` rows including pilot cities: `1,974`
- Target categories per expansion city:
  - `watch`: 2
  - `hashtag`: 3
  - `local_legend`: 2
  - `first_timer_mistake`: 2
  - `neighborhood_decode`: 2
  - `photo_prompt`: 2
  - `seasonal`: 1

The first compact production pass was replaced after sampling because it chose
raw fact and phrase rows too early. The final live pass is tagged:

`meta.generated_by = "lore-production-sql-2026-08-02-v3"`

The v3 pass prioritizes existing source-backed Lore cards in this order:

1. `city_section.market`
2. `city_section.etiquette`
3. `city_section.drink`
4. existing source-backed sections and stories
5. `city_culture`
6. `city_fact`
7. `city_section.phrase` as fallback only

## Verification

Final direct Supabase readback:

- Live cities: `141`
- Wave cities: `141`
- Wave rows: `1,974`
- v3 expansion rows: `1,946`
- Stale generated rows from earlier passes: `0`
- Kind failures: `0`

Final content audit:

- Result: `PASS`
- Cities audited: `141`
- Cities passing: `141`
- Cities failing: `0`

Final source check for the committed agent-reviewed merged artifact:

- Sources: `911`
- Reachable: `899`
- Gated: `12`
- Dead: `0`
- Error: `0`
