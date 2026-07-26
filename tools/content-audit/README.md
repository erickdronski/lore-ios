# Lore content audit

`audit.py` performs a read-only coverage audit of Lore's public Supabase REST
surfaces. It reads the existing project URL and publishable anon key from
`Sources/Lore/Networking/Config.swift`; credentials are not duplicated here.

The tool paginates every surface with stable ordering, `limit`/`offset`, and
HTTP item ranges. It counts live-city rows for `city`, `place_explore`, `dive`,
`story`, `city_culture`, `city_fact`, `city_theme`, `city_section`, and `tour`.
Because dives carry `place_id` rather than `city`, they are linked through the
public `place_explore` view. Orphan and out-of-scope dive rows are reported.
When city sections are part of the requested minimums, the audit also enforces
the traveler-kit mix independently: 6 phrases, 2 zero-proof drinks, 4 etiquette
notes, and 1 market guide per live destination. A pile of one section kind can
therefore never satisfy the total by accident.

## Run

```sh
python3 tools/content-audit/audit.py \
  --json-out /tmp/lore-content-audit.json \
  --summary-out /tmp/lore-content-audit.txt
```

JSON is written to stdout and the readable summary to stderr when output paths
are omitted. Content gaps do not fail the command unless `--fail-on-gaps` is
set; endpoint/network failures always exit `2`.

Override minimums inline:

```sh
python3 tools/content-audit/audit.py --fail-on-gaps \
  --min place_explore=20 --min dive=15 --min tour=2
```

Or supply JSON. Values replace the built-in richness minimum for that metric:

```json
{
  "minimums": {
    "story": 5,
    "city_culture": 10,
    "city_section": 10
  }
}
```

Pass `--include-non-live` to audit every city row rather than the app's live
city roster. The transport is deliberately GET-only and refuses non-HTTPS
Supabase URLs; there is no write code path.

## Test

```sh
python3 -m unittest discover -s tools/content-audit -p 'test_*.py' -v
```
