#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("build_dives_sql.py")
SPEC = importlib.util.spec_from_file_location("lore_dive_wave", MODULE_PATH)
assert SPEC and SPEC.loader
dives = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = dives
SPEC.loader.exec_module(dives)


def row(place_id: str = "47a58aec-c35a-4473-8581-eb36096956a1") -> dict:
    narrative = " ".join(["story"] * 600)
    return {
        "place_id": place_id,
        "narrative": narrative,
        "timeline": [
            {"year": 1900, "title": "Begins", "detail": "Work starts.", "emoji": "one"},
            {"year": 1920, "title": "Opens", "detail": "Doors open.", "emoji": "two"},
            {"year": 1940, "title": "Changes", "detail": "Use changes.", "emoji": "three"},
        ],
        "links": {
            "website": "https://example.org/place",
            "sources": [
                {
                    "title": "Place history",
                    "publisher": "Example archive",
                    "url": "https://example.org/archive/place",
                    "relationship": "archive",
                }
            ],
        },
        "media": {"wikipedia_title": "Example Place"},
        "source": "https://example.org/place",
        "license": "cc0",
    }


class DiveWaveTests(unittest.TestCase):
    def test_validates_and_compiles_dive(self) -> None:
        rows = [row()]

        self.assertEqual(dives.validate_rows(rows, expected_count=1)["dives"], 1)
        sql = dives.compile_sql(rows)

        self.assertIn("on conflict (place_id) do update", sql)
        self.assertNotIn("audio_path =", sql)

    def test_rejects_short_narrative(self) -> None:
        value = row()
        value["narrative"] = "Too short."

        with self.assertRaises(dives.DiveWaveError):
            dives.validate_rows([value], expected_count=1)

    def test_rejects_long_narrative(self) -> None:
        value = row()
        value["narrative"] = " ".join(["story"] * 1_001)

        with self.assertRaises(dives.DiveWaveError):
            dives.validate_rows([value], expected_count=1)

    def test_rejects_too_few_timeline_events(self) -> None:
        value = row()
        value["timeline"] = value["timeline"][:2]

        with self.assertRaises(dives.DiveWaveError):
            dives.validate_rows([value], expected_count=1)

    def test_rejects_too_many_timeline_events(self) -> None:
        value = row()
        value["timeline"] = [
            {"year": year, "title": str(year), "detail": "Event.", "emoji": "dot"}
            for year in range(1900, 1980, 10)
        ]

        with self.assertRaises(dives.DiveWaveError):
            dives.validate_rows([value], expected_count=1)

    def test_rejects_non_https_secondary_source(self) -> None:
        value = row()
        value["links"]["sources"][0]["url"] = "http://example.org/archive/place"

        with self.assertRaises(dives.DiveWaveError):
            dives.validate_rows([value], expected_count=1)

    def test_rejects_out_of_order_timeline(self) -> None:
        value = row()
        value["timeline"].reverse()

        with self.assertRaises(dives.DiveWaveError):
            dives.validate_rows([value], expected_count=1)


if __name__ == "__main__":
    unittest.main()
