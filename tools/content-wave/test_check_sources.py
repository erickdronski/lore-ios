#!/usr/bin/env python3

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("check_sources.py")
SPEC = importlib.util.spec_from_file_location("lore_source_check", MODULE_PATH)
assert SPEC and SPEC.loader
sources = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = sources
SPEC.loader.exec_module(sources)


class SourceCheckTests(unittest.TestCase):
    def test_load_urls_deduplicates_sources(self) -> None:
        rows = [
            {"source": "https://example.org/a"},
            {"source": "https://example.org/a"},
            {"source": "https://example.org/b"},
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "content.json"
            path.write_text(json.dumps(rows))

            self.assertEqual(
                sources.load_urls([path]),
                ["https://example.org/a", "https://example.org/b"],
            )

    def test_classifies_statuses(self) -> None:
        self.assertEqual(sources.classify_status(200), "reachable")
        self.assertEqual(sources.classify_status(302), "reachable")
        self.assertEqual(sources.classify_status(403), "gated")
        self.assertEqual(sources.classify_status(404), "dead")
        self.assertEqual(sources.classify_status(500), "error")

    def test_encodes_international_url_paths(self) -> None:
        self.assertEqual(
            sources.encode_url("https://example.org/oraș?q=mulțumesc"),
            "https://example.org/ora%C8%99?q=mul%C8%9Bumesc",
        )

    def test_reads_final_status_from_redirect_headers(self) -> None:
        headers = "HTTP/1.1 301 Moved\n\nHTTP/2 200 OK\n"

        self.assertEqual(sources.status_from_headers(headers), 200)

    def test_rejects_non_https_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "content.json"
            path.write_text(json.dumps([{"source": "http://example.org"}]))

            with self.assertRaises(ValueError):
                sources.load_urls([path])


if __name__ == "__main__":
    unittest.main()
