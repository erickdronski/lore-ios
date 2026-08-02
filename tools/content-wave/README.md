# Lore content-wave compiler

`build_sql.py` validates regional content files and compiles them into one
idempotent `city_section` upsert. It does not connect to Supabase or contain a
write path.

```sh
python3 tools/content-wave/build_sql.py \
  supabase/content/wave-2026-07/africa-oceania-south-america.json \
  supabase/content/wave-2026-07/asia.json \
  supabase/content/wave-2026-07/europe.json \
  supabase/content/wave-2026-07/north-america.json \
  --expected-city-count 141 \
  --sql-out supabase/content/wave-2026-07/regional-sections.sql
```

The compiler requires exactly 6 practical phrases, 2 explicitly zero-proof
drinks, 4 context-specific etiquette notes, and 1 market guide per city. It
assigns stable display order, requires HTTPS sources, `cc0` text, and
`reference_only` provenance, and rejects internal editorial scaffolding or
malformed traveler-facing punctuation. Database publication remains a
separate, authenticated review step.

For the richer city pages, compile the same shape with the stricter
`local-expert-kit` profile. It keeps the traveler kit and additionally requires
2 watch/video links, 3 hashtags, 2 local legends, 2 first-timer mistakes,
2 neighborhood decoders, 2 photo prompts, and 1 seasonal hook per city:

```sh
python3 tools/content-wave/build_sql.py \
  supabase/content/wave-2026-07/africa-oceania-south-america.json \
  supabase/content/wave-2026-07/asia.json \
  supabase/content/wave-2026-07/europe.json \
  supabase/content/wave-2026-07/north-america.json \
  --profile local-expert-kit \
  --expected-city-count 141 \
  --sql-out supabase/content/wave-2026-07/regional-sections.sql
```

When a city already has the traveler kit, use `local-expert-addons` for a
14-row append-only wave containing only the richer local-expert kinds.

Compile the missing place dossiers without touching existing audio fields:

```sh
python3 tools/content-wave/build_dives_sql.py \
  supabase/content/wave-2026-07/missing-dives.json \
  --sql-out supabase/content/wave-2026-07/missing-dives.sql
```

Check deduplicated source URLs before publishing:

```sh
python3 tools/content-wave/check_sources.py \
  supabase/content/wave-2026-07/africa-oceania-south-america.json \
  supabase/content/wave-2026-07/asia.json \
  supabase/content/wave-2026-07/europe.json \
  supabase/content/wave-2026-07/north-america.json \
  supabase/content/wave-2026-07/missing-dives.json \
  --json-out /tmp/lore-source-health.json
```

Bot-gated sources are reported separately from confirmed dead links. Dead links
and network errors fail the command so they cannot silently pass release review.

Run its self-contained tests with:

```sh
python3 -m unittest discover -s tools/content-wave -p 'test_*.py' -v
```
