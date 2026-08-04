#!/usr/bin/env python3

import importlib.util
import json
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("build_local_expert_addons.py")
SPEC = importlib.util.spec_from_file_location("lore_local_expert_addons", MODULE_PATH)
assert SPEC and SPEC.loader
addons = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = addons
SPEC.loader.exec_module(addons)

SQL_MODULE_PATH = Path(__file__).with_name("build_sql.py")
SQL_SPEC = importlib.util.spec_from_file_location("lore_content_wave", SQL_MODULE_PATH)
assert SQL_SPEC and SQL_SPEC.loader
wave = importlib.util.module_from_spec(SQL_SPEC)
sys.modules[SQL_SPEC.name] = wave
SQL_SPEC.loader.exec_module(wave)


def seed_row(city: str, kind: str, title: str, body: str, source: str) -> dict:
    return {
        "city": city,
        "kind": kind,
        "title": title,
        "body": body,
        "attribution": None,
        "emoji": "note",
        "links": {"source": source},
        "meta": {"review_state": "source_checked"},
        "source": source,
        "license": "cc0",
        "sort": 150,
        "provenance_state": "reference_only",
    }


class LocalExpertAddonTests(unittest.TestCase):
    def test_generates_complete_addon_pack_from_source_seed_rows(self) -> None:
        audit = {
            "cities": [
                {
                    "slug": "alpha-city",
                    "name": "Alpha City",
                    "country": "US",
                    "section_kind_checks": {
                        kind: {"deficit": required}
                        for kind, required in addons.EXPERT_COUNTS.items()
                    },
                }
            ]
        }
        rows = [
            seed_row(
                "alpha-city",
                "market",
                "River Market",
                "River Market is the working public anchor for food, crafts, and daily movement.",
                "https://example.org/river-market",
            ),
            seed_row(
                "alpha-city",
                "etiquette",
                "Share the space",
                "Move slowly, keep public walkways open, and ask before taking close-up photos.",
                "https://example.org/share-space",
            ),
        ]
        with tempfile.TemporaryDirectory() as directory:
            audit_path = Path(directory) / "audit.json"
            rows_path = Path(directory) / "rows.json"
            audit_path.write_text(json.dumps(audit))
            rows_path.write_text(json.dumps(rows))

            targets = addons.target_cities(audit_path)
            existing = addons.load_existing_rows([rows_path])
            output = addons.build_rows(targets, existing, "2026-08-02")

        counts = Counter(row["kind"] for row in output)
        self.assertEqual(len(output), 14)
        self.assertEqual(counts, addons.EXPERT_COUNTS)
        self.assertTrue(all(row["city"] == "alpha-city" for row in output))
        self.assertTrue(all(row["source"].startswith("https://") for row in output))
        self.assertTrue(all(row["provenance_state"] == "reference_only" for row in output))
        self.assertTrue(all(row["meta"]["review_state"] == "source_checked" for row in output))
        wave.validate_rows(
            output,
            expected_city_count=1,
            profile="local-expert-addons",
        )

    def test_rejects_target_without_source_seed_rows(self) -> None:
        with self.assertRaises(addons.BuildError):
            addons.build_rows(
                [{"slug": "empty", "name": "Empty", "country": "US"}],
                {},
                "2026-08-02",
            )

    def test_rich_seeds_take_priority_for_legend_cards(self) -> None:
        base = seed_row(
            "alpha-city",
            "market",
            "River Market",
            "River Market is the working public anchor for food, crafts, and daily movement.",
            "https://example.org/river-market",
        )
        rich = {
            "alpha-city": [
                addons._seed(
                    "alpha-city",
                    "fact",
                    "Founded on the bluff",
                    "Alpha City grew from a bluff-side settlement into a river crossing.",
                    "https://example.org/bluff",
                    {},
                )
            ]
        }

        output = addons.build_rows(
            [{"slug": "alpha-city", "name": "Alpha City", "country": "US"}],
            addons.merge_seed_rows({"alpha-city": [base]}, rich),
            "2026-08-02",
        )

        legends = [row for row in output if row["kind"] == "local_legend"]
        self.assertTrue(any("Founded on the bluff" in row["title"] for row in legends))
        self.assertTrue(any(row["source"] == "https://example.org/bluff" for row in legends))


if __name__ == "__main__":
    unittest.main()
