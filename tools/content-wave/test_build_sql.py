#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("build_sql.py")
SPEC = importlib.util.spec_from_file_location("lore_content_wave", MODULE_PATH)
assert SPEC and SPEC.loader
wave = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = wave
SPEC.loader.exec_module(wave)


def row(city: str, kind: str, sequence: int = 0) -> dict:
    return {
        "city": city,
        "kind": kind,
        "title": f"{city} {kind} {sequence}",
        "body": "A specific and useful traveler note with enough detail.",
        "attribution": "traveler pronunciation" if kind == "phrase" else None,
        "emoji": "note",
        "links": {},
        "meta": {
            "language": "English",
            "pronunciation": "traveler pronunciation",
            "english": "Thank you",
            "usage": "A polite everyday phrase",
        } if kind == "phrase" else ({"nonalcoholic": True} if kind == "drink" else {}),
        "source": "https://example.org/travel",
        "license": "cc0",
        "sort": wave.EXPECTED_SORTS[kind] + sequence,
        "provenance_state": "reference_only",
    }


class ContentWaveTests(unittest.TestCase):
    @staticmethod
    def city_rows(city: str) -> list[dict]:
        return [
            row(city, kind, sequence)
            for kind in wave.REQUIRED_KINDS
            for sequence in range(wave.REQUIRED_KIND_COUNTS[kind])
        ]

    def test_validates_complete_city_sets(self) -> None:
        rows = self.city_rows("alpha") + self.city_rows("beta")

        summary = wave.validate_rows(rows, expected_city_count=2)

        self.assertEqual(summary["rows"], 26)
        self.assertEqual(summary["cities"], 2)

    def test_rejects_missing_kind(self) -> None:
        rows = [item for item in self.city_rows("alpha") if item["kind"] != "market"]

        with self.assertRaises(wave.WaveError):
            wave.validate_rows(rows, expected_city_count=1)

    def test_rejects_non_https_source(self) -> None:
        rows = self.city_rows("alpha")
        rows[0]["source"] = "editorial:generated"

        with self.assertRaises(wave.WaveError):
            wave.validate_rows(rows, expected_city_count=1)

    def test_rejects_internal_context_scaffolding(self) -> None:
        rows = self.city_rows("alpha")
        rows[0]["body"] = "Ask one clear question. Travel context: copied source fragment."

        with self.assertRaises(wave.WaveError):
            wave.validate_rows(rows, expected_city_count=1)

    def test_normalizes_phrase_schema_variants(self) -> None:
        phrase = row("alpha", "phrase")
        phrase["attribution"] = "Language authority"
        phrase["meta"] = {
            "language": "Dutch",
            "transliteration": "dahnk oo vel",
            "English": "Thank you",
            "usage_context": "Use it politely with a host.",
        }

        normalized = wave.normalize_row(phrase)

        self.assertEqual(normalized["attribution"], "Pronunciation: dahnk oo vel")
        self.assertEqual(normalized["meta"]["pronunciation"], "dahnk oo vel")
        self.assertEqual(normalized["meta"]["english"], "Thank you")
        self.assertEqual(normalized["meta"]["usage"], "Use it politely with a host.")
        self.assertEqual(
            normalized["meta"]["editorial_attribution"], "Language authority"
        )

    def test_uses_phrase_body_as_usage_fallback(self) -> None:
        phrase = row("alpha", "phrase")
        phrase["attribution"] = None
        phrase["meta"] = {
            "language": "Twi",
            "transliteration": "meh-DAH-see",
            "english": "Thank you",
        }

        normalized = wave.normalize_row(phrase)

        self.assertEqual(normalized["meta"]["usage"], phrase["body"])
        wave.validate_rows(
            [normalized]
            + [row("alpha", "phrase", sequence) for sequence in range(1, 6)]
            + [item for item in self.city_rows("alpha") if item["kind"] != "phrase"],
            expected_city_count=1,
        )

    def test_allows_english_local_shorthand_without_transliteration(self) -> None:
        phrase = row("alpha", "phrase")
        phrase["attribution"] = None
        phrase["meta"] = {
            "language": "English",
            "English": "The local transit system",
            "usage": "Use the term when asking for directions.",
        }

        normalized = wave.normalize_row(phrase)

        self.assertEqual(normalized["attribution"], "Pronunciation: alpha phrase 0")
        wave.validate_rows(
            [normalized]
            + [row("alpha", "phrase", sequence) for sequence in range(1, 6)]
            + [item for item in self.city_rows("alpha") if item["kind"] != "phrase"],
            expected_city_count=1,
        )

    def test_compiles_idempotent_upsert(self) -> None:
        rows = self.city_rows("alpha")
        wave.validate_rows(rows, expected_city_count=1)

        sql = wave.compile_sql(rows)

        self.assertIn("on conflict (city, kind, title) do update", sql)
        self.assertIn("https://example.org/travel", sql)

    def test_normalization_assigns_stable_kind_sequence(self) -> None:
        rows = [row("alpha", "phrase", sequence) for sequence in range(6)]
        for item in rows:
            item["sort"] = 120

        normalized = wave.normalize_rows(rows)

        self.assertEqual([item["sort"] for item in normalized], list(range(120, 126)))


if __name__ == "__main__":
    unittest.main()
