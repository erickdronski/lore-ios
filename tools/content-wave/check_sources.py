#!/usr/bin/env python3
"""Check the health of source URLs referenced by Lore content-wave JSON."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Iterable, Sequence
from urllib.parse import quote, urlsplit, urlunsplit


GATED_STATUSES = {401, 403, 405, 406, 429}
DEAD_STATUSES = {404, 410}


def load_urls(paths: Iterable[Path]) -> list[str]:
    urls: set[str] = set()
    for path in paths:
        document = json.loads(path.read_text())
        if not isinstance(document, list):
            raise ValueError(f"{path} must contain a top-level array")
        for index, row in enumerate(document, 1):
            source = row.get("source") if isinstance(row, dict) else None
            if not isinstance(source, str) or not source.startswith("https://"):
                raise ValueError(f"{path} row {index} has no HTTPS source")
            urls.add(source)
    return sorted(urls)


def classify_status(status: int) -> str:
    if 200 <= status < 400:
        return "reachable"
    if status in GATED_STATUSES:
        return "gated"
    if status in DEAD_STATUSES:
        return "dead"
    return "error"


def encode_url(url: str) -> str:
    parts = urlsplit(url)
    hostname = parts.hostname.encode("idna").decode("ascii") if parts.hostname else ""
    if parts.port:
        hostname = f"{hostname}:{parts.port}"
    if parts.username:
        credentials = quote(parts.username, safe="")
        if parts.password:
            credentials += ":" + quote(parts.password, safe="")
        hostname = f"{credentials}@{hostname}"
    return urlunsplit(
        (
            parts.scheme,
            hostname,
            quote(parts.path, safe="/%:@"),
            quote(parts.query, safe="=&%:@/?+"),
            quote(parts.fragment, safe=""),
        )
    )


def status_from_headers(raw_headers: str) -> int | None:
    statuses = re.findall(r"^HTTP/\S+\s+(\d{3})\b", raw_headers, flags=re.MULTILINE)
    return int(statuses[-1]) if statuses else None


def check_url(url: str, timeout: float) -> dict[str, Any]:
    try:
        with tempfile.TemporaryDirectory(prefix="lore-source-check-") as directory:
            headers_path = Path(directory) / "headers"
            completed = subprocess.run(
                [
                    "curl",
                    "--location",
                    "--silent",
                    "--show-error",
                    "--http1.1",
                    "--output",
                    "/dev/null",
                    "--dump-header",
                    str(headers_path),
                    "--range",
                    "0-1023",
                    "--max-time",
                    str(timeout),
                    "--retry",
                    "2",
                    "--retry-all-errors",
                    "--retry-delay",
                    "1",
                    "--user-agent",
                    "LoreContentAudit/1.0 (+https://github.com/erickdronski)",
                    "--write-out",
                    "%{http_code}\t%{url_effective}",
                    encode_url(url),
                ],
                capture_output=True,
                check=False,
                text=True,
                timeout=(timeout * 3) + 5,
            )
            received_status = status_from_headers(
                headers_path.read_text(errors="replace") if headers_path.exists() else ""
            )
    except (OSError, subprocess.TimeoutExpired) as error:
        return {
            "url": url,
            "status": None,
            "result": "error",
            "error": str(error),
        }

    if completed.returncode != 0:
        if received_status is not None:
            return {
                "url": url,
                "status": received_status,
                "result": classify_status(received_status),
                "final_url": url,
                "note": completed.stderr.strip() or f"curl exited {completed.returncode}",
            }
        return {
            "url": url,
            "status": None,
            "result": "error",
            "error": completed.stderr.strip() or f"curl exited {completed.returncode}",
        }

    status_text, _, final_url = completed.stdout.partition("\t")
    try:
        status = int(status_text)
    except ValueError:
        return {
            "url": url,
            "status": None,
            "result": "error",
            "error": f"unexpected curl status: {status_text!r}",
        }
    return {
        "url": url,
        "status": status,
        "result": classify_status(status),
        "final_url": final_url,
    }


def check_urls(urls: Sequence[str], timeout: float, workers: int) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {executor.submit(check_url, url, timeout): url for url in urls}
        for future in as_completed(futures):
            results.append(future.result())
    return sorted(results, key=lambda result: result["url"])


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        urls = load_urls(args.inputs)
        results = check_urls(urls, args.timeout, args.workers)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1

    summary = {
        "sources": len(results),
        "reachable": sum(result["result"] == "reachable" for result in results),
        "gated": sum(result["result"] == "gated" for result in results),
        "dead": sum(result["result"] == "dead" for result in results),
        "error": sum(result["result"] == "error" for result in results),
    }
    payload = {"summary": summary, "results": results}
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, sort_keys=True))

    for result in results:
        if result["result"] in {"dead", "error"}:
            print(json.dumps(result, sort_keys=True), file=sys.stderr)
    return 1 if summary["dead"] or summary["error"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
