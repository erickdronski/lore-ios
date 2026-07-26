#!/usr/bin/env python3
"""Self-contained tests for the Lore content audit tool."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
import urllib.parse
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("audit.py")
SPEC = importlib.util.spec_from_file_location("lore_content_audit", MODULE_PATH)
assert SPEC and SPEC.loader
audit = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = audit
SPEC.loader.exec_module(audit)


class FakeTransport:
    def __init__(self, rows: list[dict]) -> None:
        self.rows = rows
        self.requests: list[tuple[str, dict[str, str]]] = []

    def get(self, url: str, headers: dict[str, str]) -> audit.HTTPResponse:
        self.requests.append((url, headers))
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
        offset = int(query["offset"][0])
        limit = int(query["limit"][0])
        page = self.rows[offset : offset + limit]
        if page:
            content_range = f"{offset}-{offset + len(page) - 1}/{len(self.rows)}"
        else:
            content_range = f"*/{len(self.rows)}"
        return audit.HTTPResponse(
            status=200,
            headers={"content-range": content_range},
            body=json.dumps(page).encode(),
        )


class ContentAuditTests(unittest.TestCase):
    def test_reads_existing_swift_config_shape(self) -> None:
        source = '''
        enum Config {
            static let supabaseURL = URL(string: "https://example.supabase.co")!
            static let supabaseAnonKey = "public-anon-key"
        }
        '''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Config.swift"
            path.write_text(source)
            self.assertEqual(
                audit.read_supabase_config(path),
                ("https://example.supabase.co", "public-anon-key"),
            )

    def test_paginates_with_get_ranges_until_exact_total(self) -> None:
        transport = FakeTransport([{"id": str(index)} for index in range(5)])
        client = audit.SupabaseRESTClient(
            "https://example.supabase.co",
            "anon",
            transport,
            page_size=2,
        )

        rows = client.fetch_all("story", "id", "id.asc")

        self.assertEqual(len(rows), 5)
        self.assertEqual(len(transport.requests), 3)
        self.assertEqual(transport.requests[1][1]["Range"], "2-3")
        self.assertIn("offset=4", transport.requests[2][0])
        self.assertTrue(all("Authorization" in headers for _, headers in transport.requests))

    def test_builds_city_counts_and_dive_linkage(self) -> None:
        dataset = {
            "city": [
                {"slug": "alpha", "name": "Alpha", "country": "US", "status": "live"},
                {"slug": "beta", "name": "Beta", "country": "US", "status": "coming_soon"},
            ],
            "place_explore": [
                {"id": "p1", "city": "alpha"},
                {"id": "p2", "city": "alpha"},
                {"id": "p3", "city": "beta"},
            ],
            "dive": [{"place_id": "p1"}, {"place_id": "missing"}, {"place_id": "p3"}],
            "story": [{"id": "s1", "city": "alpha"}, {"id": "s2", "city": "unknown"}],
            "city_culture": [],
            "city_fact": [],
            "city_theme": [{"city": "alpha"}],
            "city_section": [],
            "tour": [],
        }
        minimums = {metric: 0 for metric in audit.METRICS}
        minimums.update({"city": 1, "place_explore": 2, "dive": 1, "story": 1})

        report = audit.build_report(
            dataset,
            minimums,
            source_url="https://example.supabase.co",
            generated_at="2026-07-25T00:00:00+00:00",
        )

        self.assertEqual(report["summary"]["cities_audited"], 1)
        alpha = report["cities"][0]
        self.assertEqual(alpha["counts"]["place_explore"], 2)
        self.assertEqual(alpha["counts"]["dive"], 1)
        self.assertEqual(alpha["dive_linkage"]["place_coverage_percent"], 50.0)
        self.assertEqual(report["linkage"]["orphan_dive_rows"], 1)
        self.assertEqual(report["linkage"]["out_of_scope_dive_rows"], 1)
        self.assertEqual(report["linkage"]["unknown_city_rows"]["story"], 1)
        self.assertTrue(report["summary"]["passed"])

    def test_unavailable_metric_fails_check_without_fabricating_a_zero(self) -> None:
        dataset = {metric: [] for metric in audit.METRICS}
        dataset["city"] = [{"slug": "alpha", "name": "Alpha", "status": "live"}]
        minimums = {metric: 0 for metric in audit.METRICS}

        report = audit.build_report(dataset, minimums, errors={"tour": "HTTP 403"})

        check = report["cities"][0]["checks"]["tour"]
        self.assertFalse(check["available"])
        self.assertIsNone(check["deficit"])
        self.assertFalse(report["summary"]["passed"])

    def test_requires_each_traveler_section_kind_not_only_total_rows(self) -> None:
        dataset = {metric: [] for metric in audit.METRICS}
        dataset["city"] = [{"slug": "alpha", "name": "Alpha", "status": "live"}]
        dataset["city_section"] = [
            {"id": str(index), "city": "alpha", "kind": "phrase"}
            for index in range(13)
        ]
        minimums = {metric: 0 for metric in audit.METRICS}
        minimums["city_section"] = 13

        report = audit.build_report(dataset, minimums)

        alpha = report["cities"][0]
        self.assertIn("city_section.drink", alpha["gaps"])
        self.assertEqual(alpha["section_kind_checks"]["phrase"]["count"], 13)
        self.assertFalse(alpha["passed"])

    def test_threshold_file_and_cli_override_are_validated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "thresholds.json"
            path.write_text('{"minimums":{"story":5,"tour":2}}')
            minimums = audit.load_minimums(path, ["story=7"])

        self.assertEqual(minimums["story"], 7)
        self.assertEqual(minimums["tour"], 2)
        with self.assertRaises(audit.AuditError):
            audit.load_minimums(None, ["unknown=3"])


if __name__ == "__main__":
    unittest.main()
