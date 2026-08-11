#!/usr/bin/env python3
"""Read-only coverage audit for Lore's public Supabase content surfaces."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import urllib.parse
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, Sequence, TextIO


METRICS = (
    "city",
    "place_explore",
    "dive",
    "story",
    "city_culture",
    "city_fact",
    "city_theme",
    "city_section",
    "tour",
)

SECTION_KIND_MINIMUMS = {
    "name_origin": 1,
    "phrase": 6,
    "screen": 2,
    "drink": 2,
    "etiquette": 4,
    "market": 1,
    "watch": 2,
    "hashtag": 3,
    "local_legend": 2,
    "first_timer_mistake": 2,
    "neighborhood_decode": 2,
    "photo_prompt": 2,
    "seasonal": 1,
}
CULTURE_KIND_MINIMUMS = {
    "slang": 3,
    "saying": 2,
}
LOCAL_EXPERT_KINDS = frozenset(
    {
        "name_origin",
        "screen",
        "watch",
        "hashtag",
        "local_legend",
        "first_timer_mistake",
        "neighborhood_decode",
        "photo_prompt",
        "seasonal",
    }
)
PUBLIC_PROVENANCE_STATES = frozenset({"reference_only", "reviewed"})
UNSAFE_PHOTO_PROMPT_MARKERS = (
    "trespass",
    "sneak into",
    "private property",
    "restricted area",
    "climb over",
    "jump the fence",
)
REVIEW_STATE_KEYS = (
    "review_state",
    "review_status",
    "fact_review",
    "cultural_safety_review",
    "rights_review",
    "recheck_state",
    "recheck_status",
)
UNFINISHED_REVIEW_MARKERS = ("pending", "not_reviewed", "unreviewed")

# These defaults describe a useful city experience, not merely a non-empty DB.
DEFAULT_MINIMUMS = {
    "city": 1,
    "place_explore": 12,
    "dive": 8,
    "story": 3,
    "city_culture": 8,
    "city_fact": 8,
    "city_theme": 1,
    "city_section": sum(SECTION_KIND_MINIMUMS.values()),
    "tour": 1,
}

ENDPOINTS = {
    "city": {"select": "slug,name,country,status,sort", "order": "slug.asc"},
    "place_explore": {"select": "id,city", "order": "id.asc"},
    "dive": {"select": "place_id", "order": "place_id.asc"},
    "story": {"select": "id,city", "order": "id.asc"},
    "city_culture": {"select": "id,city,kind", "order": "id.asc"},
    "city_fact": {"select": "id,city", "order": "id.asc"},
    "city_theme": {"select": "city", "order": "city.asc"},
    "city_section": {
        "select": "id,city,kind,title,body,links,meta,source,provenance_state",
        "order": "id.asc",
    },
    "tour": {"select": "id,city", "order": "id.asc"},
}

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = REPO_ROOT / "Sources/Lore/Networking/Config.swift"


class AuditError(RuntimeError):
    """A safe, user-facing audit failure."""


@dataclass(frozen=True)
class HTTPResponse:
    status: int
    headers: Mapping[str, str]
    body: bytes


class CurlTransport:
    """Small GET-only transport that works with the macOS system trust store."""

    def __init__(self, timeout: int = 30) -> None:
        self.timeout = timeout

    def get(self, url: str, headers: Mapping[str, str]) -> HTTPResponse:
        if urllib.parse.urlsplit(url).scheme != "https":
            raise AuditError("Refusing a non-HTTPS Supabase URL")

        with tempfile.TemporaryDirectory(prefix="lore-content-audit-") as temp_dir:
            header_path = Path(temp_dir) / "headers"
            body_path = Path(temp_dir) / "body"
            command = [
                "curl",
                "--silent",
                "--show-error",
                "--request",
                "GET",
                "--proto",
                "=https",
                "--max-time",
                str(self.timeout),
                "--dump-header",
                str(header_path),
                "--output",
                str(body_path),
                "--write-out",
                "%{http_code}",
                url,
            ]
            for name, value in headers.items():
                command.extend(("--header", f"{name}: {value}"))

            try:
                completed = subprocess.run(
                    command,
                    check=False,
                    capture_output=True,
                    text=True,
                )
            except FileNotFoundError as error:
                raise AuditError("curl is required but was not found") from error

            if completed.returncode != 0:
                detail = completed.stderr.strip() or f"curl exit {completed.returncode}"
                raise AuditError(f"GET request failed: {detail}")

            try:
                status = int(completed.stdout.strip())
            except ValueError as error:
                raise AuditError("GET request returned an invalid HTTP status") from error

            response_headers = _parse_headers(header_path.read_text(errors="replace"))
            body = body_path.read_bytes()
            if not 200 <= status < 300:
                detail = body.decode("utf-8", errors="replace")[:500]
                raise AuditError(f"GET returned HTTP {status}: {detail}")
            return HTTPResponse(status=status, headers=response_headers, body=body)


class SupabaseRESTClient:
    """Read-only PostgREST client with bounded, progress-checked pagination."""

    def __init__(
        self,
        base_url: str,
        anon_key: str,
        transport: Any,
        page_size: int = 500,
        max_pages: int = 10_000,
    ) -> None:
        if not 1 <= page_size <= 1_000:
            raise AuditError("page size must be between 1 and 1000")
        self.rest_url = f"{base_url.rstrip('/')}/rest/v1"
        self.anon_key = anon_key
        self.transport = transport
        self.page_size = page_size
        self.max_pages = max_pages

    def fetch_all(self, resource: str, select: str, order: str) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        previous_page_digest: str | None = None

        for page_index in range(self.max_pages):
            offset = page_index * self.page_size
            query = urllib.parse.urlencode(
                {
                    "select": select,
                    "order": order,
                    "limit": self.page_size,
                    "offset": offset,
                }
            )
            url = f"{self.rest_url}/{urllib.parse.quote(resource, safe='')}?{query}"
            headers = {
                "Accept": "application/json",
                "apikey": self.anon_key,
                "Authorization": f"Bearer {self.anon_key}",
                "Prefer": "count=exact",
                "Range-Unit": "items",
                "Range": f"{offset}-{offset + self.page_size - 1}",
                "User-Agent": "LoreContentAudit/1.0",
            }
            response = self.transport.get(url, headers)
            try:
                page = json.loads(response.body)
            except json.JSONDecodeError as error:
                raise AuditError(f"{resource} returned invalid JSON") from error
            if not isinstance(page, list) or any(not isinstance(row, dict) for row in page):
                raise AuditError(f"{resource} did not return a JSON row array")

            content_range = _parse_content_range(response.headers.get("content-range"))
            if content_range and page:
                range_start, range_end, _ = content_range
                if range_start != offset or range_end < range_start:
                    raise AuditError(
                        f"{resource} pagination mismatch: requested {offset}, "
                        f"received {range_start}-{range_end}"
                    )

            digest = hashlib.sha256(
                json.dumps(page, sort_keys=True, separators=(",", ":")).encode()
            ).hexdigest()
            if page and digest == previous_page_digest:
                raise AuditError(f"{resource} pagination did not advance at offset {offset}")
            previous_page_digest = digest
            rows.extend(page)

            total = content_range[2] if content_range else None
            if total is not None and len(rows) >= total:
                return rows
            if len(page) < self.page_size:
                return rows

        raise AuditError(f"{resource} exceeded the {self.max_pages}-page safety limit")


def _parse_headers(raw_headers: str) -> dict[str, str]:
    """Return the final HTTP header block, normalized to lowercase keys."""
    blocks = re.split(r"\r?\n\r?\n", raw_headers.strip())
    for block in reversed(blocks):
        lines = block.splitlines()
        if lines and lines[0].startswith("HTTP/"):
            parsed: dict[str, str] = {}
            for line in lines[1:]:
                if ":" in line:
                    name, value = line.split(":", 1)
                    parsed[name.strip().lower()] = value.strip()
            return parsed
    return {}


def _parse_content_range(value: str | None) -> tuple[int, int, int | None] | None:
    if not value:
        return None
    match = re.fullmatch(r"(?:(\d+)-(\d+)|\*)/(\d+|\*)", value.strip())
    if not match:
        raise AuditError(f"Invalid Content-Range header: {value}")
    if match.group(1) is None:
        return (0, -1, None if match.group(3) == "*" else int(match.group(3)))
    return (
        int(match.group(1)),
        int(match.group(2)),
        None if match.group(3) == "*" else int(match.group(3)),
    )


def read_supabase_config(path: Path) -> tuple[str, str]:
    try:
        source = path.read_text()
    except OSError as error:
        raise AuditError(f"Could not read Config.swift at {path}: {error}") from error

    url_match = re.search(
        r'static\s+let\s+supabaseURL\s*=\s*URL\(string:\s*"([^"]+)"\)', source
    )
    key_match = re.search(r'static\s+let\s+supabaseAnonKey\s*=\s*"([^"]+)"', source)
    if not url_match or not key_match:
        raise AuditError("Config.swift does not contain the expected Supabase URL and anon key")
    return url_match.group(1), key_match.group(1)


def load_minimums(path: Path | None, overrides: Sequence[str]) -> dict[str, int]:
    minimums = dict(DEFAULT_MINIMUMS)
    if path:
        try:
            document = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as error:
            raise AuditError(f"Could not read thresholds from {path}: {error}") from error
        if isinstance(document, dict) and "minimums" in document:
            document = document["minimums"]
        if not isinstance(document, dict):
            raise AuditError("Threshold file must be an object or contain a minimums object")
        minimums.update(_validate_minimums(document))

    parsed_overrides: dict[str, Any] = {}
    for override in overrides:
        metric, separator, raw_value = override.partition("=")
        if not separator:
            raise AuditError(f"Invalid --min value {override!r}; expected METRIC=COUNT")
        try:
            parsed_overrides[metric] = int(raw_value)
        except ValueError as error:
            raise AuditError(f"Invalid minimum count in {override!r}") from error
    minimums.update(_validate_minimums(parsed_overrides))
    return minimums


def _validate_minimums(values: Mapping[str, Any]) -> dict[str, int]:
    validated: dict[str, int] = {}
    for metric, value in values.items():
        if metric not in METRICS:
            raise AuditError(f"Unknown threshold metric {metric!r}")
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise AuditError(f"Minimum for {metric} must be a non-negative integer")
        validated[metric] = value
    return validated


def fetch_content(client: SupabaseRESTClient) -> tuple[dict[str, list[dict[str, Any]]], dict[str, str]]:
    dataset: dict[str, list[dict[str, Any]]] = {}
    errors: dict[str, str] = {}
    for metric in METRICS:
        spec = ENDPOINTS[metric]
        try:
            dataset[metric] = client.fetch_all(metric, spec["select"], spec["order"])
        except AuditError as error:
            dataset[metric] = []
            errors[metric] = str(error)
    return dataset, errors


def build_report(
    dataset: Mapping[str, Sequence[Mapping[str, Any]]],
    minimums: Mapping[str, int],
    *,
    include_non_live: bool = False,
    errors: Mapping[str, str] | None = None,
    source_url: str = "",
    page_size: int = 500,
    generated_at: str | None = None,
) -> dict[str, Any]:
    errors = dict(errors or {})
    city_rows = dataset.get("city", [])
    all_cities = {
        str(row.get("slug")): row
        for row in city_rows
        if isinstance(row.get("slug"), str) and row.get("slug")
    }
    scoped_cities = {
        slug: row
        for slug, row in all_cities.items()
        if include_non_live or row.get("status") == "live"
    }
    availability = {metric: metric not in errors for metric in METRICS}
    counts = {slug: {metric: 0 for metric in METRICS} for slug in scoped_cities}
    culture_kind_counts = {
        slug: {kind: 0 for kind in CULTURE_KIND_MINIMUMS} for slug in scoped_cities
    }
    section_kind_counts = {
        slug: {kind: 0 for kind in SECTION_KIND_MINIMUMS} for slug in scoped_cities
    }
    section_quality_issues = {slug: [] for slug in scoped_cities}
    for slug in counts:
        counts[slug]["city"] = 1

    unknown_city_rows = {metric: 0 for metric in METRICS if metric not in ("city", "dive")}
    out_of_scope_rows = {metric: 0 for metric in METRICS if metric not in ("city", "dive")}
    place_to_city: dict[str, str] = {}
    places_by_city: dict[str, set[str]] = {slug: set() for slug in scoped_cities}

    for row in dataset.get("place_explore", []):
        place_id = row.get("id")
        city = row.get("city")
        if isinstance(place_id, str) and isinstance(city, str):
            place_to_city[place_id] = city
        if city in scoped_cities:
            counts[city]["place_explore"] += 1
            if isinstance(place_id, str):
                places_by_city[city].add(place_id)
        elif city in all_cities:
            out_of_scope_rows["place_explore"] += 1
        else:
            unknown_city_rows["place_explore"] += 1

    for metric in METRICS:
        if metric in ("city", "place_explore", "dive"):
            continue
        for row in dataset.get(metric, []):
            city = row.get("city")
            if city in scoped_cities:
                counts[city][metric] += 1
                if metric == "city_culture":
                    kind = row.get("kind")
                    if kind in CULTURE_KIND_MINIMUMS:
                        culture_kind_counts[city][str(kind)] += 1
                if metric == "city_section":
                    kind = row.get("kind")
                    if kind in SECTION_KIND_MINIMUMS:
                        section_kind_counts[city][str(kind)] += 1
                    section_quality_issues[city].extend(_city_section_quality_issues(row))
            elif city in all_cities:
                out_of_scope_rows[metric] += 1
            else:
                unknown_city_rows[metric] += 1

    places_with_dive: dict[str, set[str]] = {slug: set() for slug in scoped_cities}
    orphan_dive_rows = 0
    out_of_scope_dive_rows = 0
    for row in dataset.get("dive", []):
        place_id = row.get("place_id")
        city = place_to_city.get(place_id) if isinstance(place_id, str) else None
        if city in scoped_cities:
            counts[city]["dive"] += 1
            places_with_dive[city].add(place_id)
        elif city in all_cities:
            out_of_scope_dive_rows += 1
        else:
            orphan_dive_rows += 1

    city_reports: list[dict[str, Any]] = []
    total_counts = {metric: 0 for metric in METRICS}
    for slug, metadata in scoped_cities.items():
        city_counts = counts[slug]
        for metric in METRICS:
            total_counts[metric] += city_counts[metric]
        checks = {}
        gaps = []
        for metric in METRICS:
            count = city_counts[metric]
            minimum = minimums[metric]
            available = availability[metric]
            passed = available and count >= minimum
            checks[metric] = {
                "count": count,
                "minimum": minimum,
                "available": available,
                "passed": passed,
                "deficit": max(0, minimum - count) if available else None,
            }
            if not passed:
                gaps.append(metric)

        culture_kind_checks = {}
        if minimums["city_culture"] > 0 and availability["city_culture"]:
            for kind, required in CULTURE_KIND_MINIMUMS.items():
                count = culture_kind_counts[slug][kind]
                passed = count >= required
                culture_kind_checks[kind] = {
                    "count": count,
                    "minimum": required,
                    "passed": passed,
                    "deficit": max(0, required - count),
                }
                if not passed:
                    gaps.append(f"city_culture.{kind}")

        section_kind_checks = {}
        section_quality_checks = []
        if minimums["city_section"] > 0 and availability["city_section"]:
            for kind, required in SECTION_KIND_MINIMUMS.items():
                count = section_kind_counts[slug][kind]
                passed = count >= required
                section_kind_checks[kind] = {
                    "count": count,
                    "minimum": required,
                    "passed": passed,
                    "deficit": max(0, required - count),
                }
                if not passed:
                    gaps.append(f"city_section.{kind}")
            for issue in section_quality_issues[slug]:
                section_quality_checks.append(issue)
                gaps.append(f"city_section.quality.{issue['kind']}")

        place_count = len(places_by_city[slug])
        covered_place_count = len(places_with_dive[slug])
        coverage = round(100 * covered_place_count / place_count, 1) if place_count else 0.0
        city_reports.append(
            {
                "slug": slug,
                "name": metadata.get("name") or slug,
                "country": metadata.get("country"),
                "status": metadata.get("status"),
                "counts": city_counts,
                "checks": checks,
                "culture_kind_checks": culture_kind_checks,
                "section_kind_checks": section_kind_checks,
                "section_quality_checks": section_quality_checks,
                "dive_linkage": {
                    "places_with_dive": covered_place_count,
                    "places_total": place_count,
                    "place_coverage_percent": coverage,
                },
                "gaps": gaps,
                "passed": not gaps,
            }
        )

    city_reports.sort(key=lambda city: (city["passed"], str(city["name"]).casefold()))
    cities_passing = sum(1 for city in city_reports if city["passed"])
    raw_rows = {metric: len(dataset.get(metric, [])) for metric in METRICS}
    generated_at = generated_at or datetime.now(timezone.utc).isoformat()
    return {
        "schema_version": 1,
        "generated_at": generated_at,
        "source": {
            "supabase_url": source_url,
            "api": "/rest/v1",
            "city_scope": "all" if include_non_live else "live",
            "page_size": page_size,
            "read_only": True,
        },
        "minimums": dict(minimums),
        "availability": availability,
        "errors": errors,
        "summary": {
            "passed": not errors and cities_passing == len(city_reports) and bool(city_reports),
            "cities_audited": len(city_reports),
            "cities_passing": cities_passing,
            "cities_failing": len(city_reports) - cities_passing,
            "total_counts": total_counts,
            "raw_rows": raw_rows,
        },
        "linkage": {
            "orphan_dive_rows": orphan_dive_rows,
            "out_of_scope_dive_rows": out_of_scope_dive_rows,
            "unknown_city_rows": unknown_city_rows,
            "out_of_scope_rows": out_of_scope_rows,
        },
        "cities": city_reports,
    }


def _city_section_quality_issues(row: Mapping[str, Any]) -> list[dict[str, str]]:
    kind = row.get("kind")
    if kind not in LOCAL_EXPERT_KINDS:
        return []

    city = str(row.get("city") or "")
    title = str(row.get("title") or row.get("id") or "")
    links = row.get("links") if isinstance(row.get("links"), dict) else {}
    meta = row.get("meta") if isinstance(row.get("meta"), dict) else {}
    issues: list[dict[str, str]] = []

    def add(reason: str) -> None:
        issues.append({"city": city, "kind": str(kind), "title": title, "reason": reason})

    if _https_url(row.get("source")) is None:
        add("missing_https_source")
    provenance_state = row.get("provenance_state")
    if provenance_state not in PUBLIC_PROVENANCE_STATES:
        add("unpublished_provenance")
    if _has_unfinished_review_marker(meta):
        add("unfinished_review_state")

    if kind == "watch":
        if _first_https_link(links, "video_url", "youtube_url", "tiktok_url", "website") is None:
            add("missing_https_video_link")
        if not _nonempty(meta.get("platform")):
            add("missing_platform")
    elif kind == "hashtag":
        hashtag = str(meta.get("hashtag") or title).strip()
        if not hashtag.startswith("#") or len(hashtag) < 2:
            add("missing_literal_hashtag")
        if _first_https_link(
            links, "hashtag_url", "tiktok_url", "instagram_url", "website"
        ) is None:
            add("missing_https_hashtag_link")
    elif kind == "local_legend":
        confidence = str(meta.get("confidence") or "").strip().casefold()
        if confidence not in {"legend", "oral tradition", "disputed", "documented"}:
            add("missing_legend_confidence_label")
    elif kind == "screen":
        if not _nonempty(meta.get("platform")):
            add("missing_screen_medium")
    elif kind == "photo_prompt":
        body = str(row.get("body") or "").casefold()
        if any(marker in body for marker in UNSAFE_PHOTO_PROMPT_MARKERS):
            add("unsafe_photo_prompt_language")

    return issues


def _has_unfinished_review_marker(meta: Mapping[str, Any]) -> bool:
    for key in REVIEW_STATE_KEYS:
        value = meta.get(key)
        if not isinstance(value, str):
            continue
        folded = value.casefold()
        if any(marker in folded for marker in UNFINISHED_REVIEW_MARKERS):
            return True
    return False


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _https_url(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    parsed = urllib.parse.urlsplit(value.strip())
    if parsed.scheme == "https" and parsed.netloc:
        return value.strip()
    return None


def _first_https_link(links: Mapping[str, Any], *keys: str) -> str | None:
    for key in keys:
        url = _https_url(links.get(key))
        if url:
            return url
    return None


def human_summary(report: Mapping[str, Any]) -> str:
    summary = report["summary"]
    result = "PASS" if summary["passed"] else "GAPS FOUND"
    lines = [
        "Lore content coverage audit",
        f"Result: {result}",
        (
            f"Cities: {summary['cities_audited']} audited, "
            f"{summary['cities_passing']} passing, {summary['cities_failing']} below minimums"
        ),
        "",
        "City                         Places Dives Stories Culture Facts Theme Sections Tours  Result",
        "---------------------------  ------ ----- ------- ------- ----- ----- -------- -----  ------",
    ]
    for city in report["cities"]:
        counts = city["counts"]
        name = f"{city['name']} ({city['slug']})"
        lines.append(
            f"{name[:27]:27}  {counts['place_explore']:6} {counts['dive']:5} "
            f"{counts['story']:7} {counts['city_culture']:7} {counts['city_fact']:5} "
            f"{counts['city_theme']:5} {counts['city_section']:8} {counts['tour']:5}  "
            f"{'PASS' if city['passed'] else 'GAPS'}"
        )

    failing = [city for city in report["cities"] if not city["passed"]]
    if failing:
        lines.extend(("", "Threshold gaps:"))
        for city in failing:
            details = []
            for metric in city["gaps"]:
                if metric.startswith("city_section.quality."):
                    kind = metric.rsplit(".", 1)[1]
                    quality_issues = [
                        issue
                        for issue in city.get("section_quality_checks", [])
                        if issue.get("kind") == kind
                    ]
                    reason = quality_issues[0]["reason"] if quality_issues else "invalid"
                    details.append(f"{metric} {reason}")
                    continue
                if metric.startswith("city_culture."):
                    kind = metric.split(".", 1)[1]
                    check = city["culture_kind_checks"][kind]
                    details.append(
                        f"{metric} {check['count']}/{check['minimum']}"
                    )
                    continue
                if metric.startswith("city_section."):
                    kind = metric.split(".", 1)[1]
                    check = city["section_kind_checks"][kind]
                    details.append(
                        f"{metric} {check['count']}/{check['minimum']}"
                    )
                    continue
                check = city["checks"][metric]
                if check["available"]:
                    details.append(f"{metric} {check['count']}/{check['minimum']}")
                else:
                    details.append(f"{metric} unavailable")
            lines.append(f"- {city['name']}: {', '.join(details)}")

    linkage = report["linkage"]
    lines.extend(
        (
            "",
            (
                "Dive linkage: "
                f"{linkage['orphan_dive_rows']} orphan rows, "
                f"{linkage['out_of_scope_dive_rows']} linked outside the selected city scope"
            ),
        )
    )
    if report["errors"]:
        lines.append("Endpoint errors:")
        for metric, error in sorted(report["errors"].items()):
            lines.append(f"- {metric}: {error}")
    return "\n".join(lines) + "\n"


def write_output(path: str, content: str, default_stream: TextIO) -> None:
    if path == "-":
        default_stream.write(content)
        default_stream.flush()
        return
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--thresholds", type=Path, help="JSON threshold overrides")
    parser.add_argument(
        "--min",
        action="append",
        default=[],
        metavar="METRIC=COUNT",
        help="override one minimum; repeat as needed",
    )
    parser.add_argument("--page-size", type=int, default=500)
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--include-non-live", action="store_true")
    parser.add_argument("--json-out", default="-", metavar="PATH", help="default: stdout")
    parser.add_argument(
        "--summary-out",
        default="-",
        metavar="PATH",
        help="default: stderr; '-' means stderr",
    )
    parser.add_argument(
        "--fail-on-gaps",
        action="store_true",
        help="exit 1 when any city is below a minimum",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if args.timeout < 1:
            raise AuditError("timeout must be at least one second")
        minimums = load_minimums(args.thresholds, args.min)
        supabase_url, anon_key = read_supabase_config(args.config)
        client = SupabaseRESTClient(
            supabase_url,
            anon_key,
            CurlTransport(timeout=args.timeout),
            page_size=args.page_size,
        )
        dataset, errors = fetch_content(client)
        report = build_report(
            dataset,
            minimums,
            include_non_live=args.include_non_live,
            errors=errors,
            source_url=supabase_url,
            page_size=args.page_size,
        )
        json_document = json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        write_output(args.json_out, json_document, sys.stdout)
        write_output(args.summary_out, human_summary(report), sys.stderr)
    except AuditError as error:
        print(f"content audit error: {error}", file=sys.stderr)
        return 2

    if errors:
        return 2
    if args.fail_on_gaps and not report["summary"]["passed"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
