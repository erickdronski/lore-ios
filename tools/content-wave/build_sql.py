#!/usr/bin/env python3
"""Validate Lore regional content JSON and compile an idempotent SQL wave."""

from __future__ import annotations

import argparse
import copy
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable, Sequence
from urllib.parse import urlsplit


REQUIRED_KINDS = ("phrase", "drink", "etiquette", "market")
REQUIRED_KIND_COUNTS = {"phrase": 6, "drink": 2, "etiquette": 4, "market": 1}
REQUIRED_FIELDS = {
    "city",
    "kind",
    "title",
    "body",
    "attribution",
    "emoji",
    "links",
    "meta",
    "source",
    "license",
    "sort",
    "provenance_state",
}
EXPECTED_SORTS = {"phrase": 120, "drink": 130, "etiquette": 140, "market": 150}
FORBIDDEN_BODY_MARKERS = (
    "Traveler context:",
    "Travel context:",
    "Drink context:",
    "Place context:",
    "Route context:",
    "Market context:",
    "System context:",
)


class WaveError(RuntimeError):
    pass


def _first_text(mapping: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = mapping.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def normalize_row(row: dict[str, Any]) -> dict[str, Any]:
    """Canonicalize harmless agent schema variations before strict validation."""
    normalized = copy.deepcopy(row)
    if normalized.get("kind") != "phrase":
        return normalized

    meta = normalized.get("meta")
    if not isinstance(meta, dict):
        return normalized

    pronunciation = _first_text(
        meta, "pronunciation", "transliteration", "romanization"
    )
    english = _first_text(meta, "english", "English", "translation", "meaning")
    usage = _first_text(
        meta, "usage", "when_to_use", "usage_context", "context"
    )
    existing_attribution = normalized.get("attribution")

    if pronunciation:
        meta["pronunciation"] = pronunciation
        if (
            isinstance(existing_attribution, str)
            and existing_attribution.strip()
            and "pronunciation" not in existing_attribution.casefold()
        ):
            meta.setdefault("editorial_attribution", existing_attribution.strip())
        if not (
            isinstance(existing_attribution, str)
            and "pronunciation" in existing_attribution.casefold()
        ):
            normalized["attribution"] = f"Pronunciation: {pronunciation}"
    elif "english" in str(meta.get("language", "")).casefold():
        spoken_guidance = _first_text(meta, "pronunciation", "spoken_guidance")
        if not spoken_guidance and isinstance(normalized.get("title"), str):
            spoken_guidance = normalized["title"].strip()
        meta["pronunciation"] = spoken_guidance or "as written"
        normalized["attribution"] = f"Pronunciation: {meta['pronunciation']}"
    if english:
        meta["english"] = english
    if usage:
        meta["usage"] = usage
    elif isinstance(normalized.get("body"), str) and normalized["body"].strip():
        # The card body already contains the agent's traveler usage guidance.
        meta["usage"] = normalized["body"].strip()

    normalized["meta"] = meta
    return normalized


def normalize_rows(rows: Sequence[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized = [normalize_row(row) for row in rows]
    sequences: Counter[tuple[str, str]] = Counter()
    for row in normalized:
        city = row.get("city")
        kind = row.get("kind")
        if isinstance(city, str) and kind in EXPECTED_SORTS:
            key = (city, kind)
            row["sort"] = EXPECTED_SORTS[kind] + sequences[key]
            sequences[key] += 1
    return normalized


def load_rows(paths: Iterable[Path]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in paths:
        try:
            document = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as error:
            raise WaveError(f"Could not read {path}: {error}") from error
        if not isinstance(document, list) or any(not isinstance(row, dict) for row in document):
            raise WaveError(f"{path} must contain a top-level array of objects")
        rows.extend(document)
    return rows


def validate_rows(rows: Sequence[dict[str, Any]], expected_city_count: int) -> dict[str, Any]:
    if not rows:
        raise WaveError("The content wave is empty")

    errors: list[str] = []
    city_kinds: dict[str, Counter[str]] = defaultdict(Counter)
    identities: set[tuple[str, str, str]] = set()

    for index, row in enumerate(rows, 1):
        missing = REQUIRED_FIELDS - row.keys()
        extra = row.keys() - REQUIRED_FIELDS
        if missing:
            errors.append(f"row {index}: missing {', '.join(sorted(missing))}")
        if extra:
            errors.append(f"row {index}: unexpected {', '.join(sorted(extra))}")

        city = row.get("city")
        kind = row.get("kind")
        title = row.get("title")
        body = row.get("body")
        if not isinstance(city, str) or not city.strip():
            errors.append(f"row {index}: city must be a non-empty string")
            continue
        if kind not in REQUIRED_KINDS:
            errors.append(f"row {index} ({city}): unsupported kind {kind!r}")
            continue
        city_kinds[city][kind] += 1

        if not isinstance(title, str) or not 2 <= len(title.strip()) <= 80:
            errors.append(f"row {index} ({city}/{kind}): title must be 2-80 characters")
        if not isinstance(body, str) or not 15 <= len(body.strip()) <= 500:
            errors.append(f"row {index} ({city}/{kind}): body must be 15-500 characters")
        elif any(marker in body for marker in FORBIDDEN_BODY_MARKERS):
            errors.append(
                f"row {index} ({city}/{kind}): body contains internal editorial scaffolding"
            )
        elif "?.”" in body or "!.”" in body:
            errors.append(f"row {index} ({city}/{kind}): body has malformed quoted punctuation")
        if isinstance(title, str):
            identity = (city, kind, title.strip().casefold())
            if identity in identities:
                errors.append(f"row {index}: duplicate city/kind/title {identity}")
            identities.add(identity)

        source = row.get("source")
        parsed = urlsplit(source) if isinstance(source, str) else None
        if parsed is None or parsed.scheme != "https" or not parsed.netloc:
            errors.append(f"row {index} ({city}/{kind}): source must be an HTTPS URL")
        if row.get("license") != "cc0":
            errors.append(f"row {index} ({city}/{kind}): license must be cc0")
        if row.get("provenance_state") != "reference_only":
            errors.append(f"row {index} ({city}/{kind}): provenance must be reference_only")
        expected_sort_range = range(
            EXPECTED_SORTS[kind],
            EXPECTED_SORTS[kind] + REQUIRED_KIND_COUNTS[kind],
        )
        if row.get("sort") not in expected_sort_range:
            errors.append(
                f"row {index} ({city}/{kind}): sort must be in "
                f"{expected_sort_range.start}-{expected_sort_range.stop - 1}"
            )
        if not isinstance(row.get("links"), dict) or not isinstance(row.get("meta"), dict):
            errors.append(f"row {index} ({city}/{kind}): links and meta must be objects")
        if kind == "drink" and isinstance(row.get("meta"), dict):
            if row["meta"].get("nonalcoholic") is not True:
                errors.append(
                    f"row {index} ({city}/drink): meta.nonalcoholic must be true"
                )
        if kind == "phrase":
            attribution = row.get("attribution")
            if not isinstance(attribution, str) or not attribution.strip():
                errors.append(
                    f"row {index} ({city}/phrase): attribution must contain pronunciation"
                )
            meta = row.get("meta")
            if isinstance(meta, dict):
                for key in ("language", "english", "usage"):
                    if not isinstance(meta.get(key), str) or not meta[key].strip():
                        errors.append(f"row {index} ({city}/phrase): meta.{key} is required")
                language = str(meta.get("language", "")).casefold()
                if "english" not in language and (
                    not isinstance(meta.get("pronunciation"), str)
                    or not meta["pronunciation"].strip()
                ):
                    errors.append(
                        f"row {index} ({city}/phrase): non-English phrases require pronunciation"
                    )

    if len(city_kinds) != expected_city_count:
        errors.append(
            f"wave covers {len(city_kinds)} cities; expected {expected_city_count}"
        )
    for city, kinds in sorted(city_kinds.items()):
        for kind in REQUIRED_KINDS:
            expected = REQUIRED_KIND_COUNTS[kind]
            if kinds[kind] != expected:
                errors.append(
                    f"{city}: expected {expected} {kind} rows, found {kinds[kind]}"
                )

    if errors:
        preview = "\n".join(f"- {error}" for error in errors[:80])
        if len(errors) > 80:
            preview += f"\n- ... and {len(errors) - 80} more"
        raise WaveError(f"Content wave validation failed:\n{preview}")

    return {
        "cities": len(city_kinds),
        "rows": len(rows),
        "kinds": dict(sorted(Counter(row["kind"] for row in rows).items())),
    }


def sql_text(value: str | None) -> str:
    if value is None:
        return "null"
    return "'" + value.replace("'", "''") + "'"


def sql_json(value: dict[str, Any]) -> str:
    return sql_text(json.dumps(value, ensure_ascii=False, sort_keys=True)) + "::jsonb"


def compile_sql(rows: Sequence[dict[str, Any]]) -> str:
    values = []
    for row in sorted(
        rows,
        key=lambda item: (item["city"], item["sort"], item["title"].casefold()),
    ):
        values.append(
            "(" + ", ".join(
                (
                    "gen_random_uuid()",
                    sql_text(row["city"]),
                    sql_text(row["kind"]),
                    sql_text(row["title"]),
                    sql_text(row["body"]),
                    sql_text(row["attribution"]),
                    sql_text(row["emoji"]),
                    "null",
                    sql_json(row["links"]),
                    sql_json(row["meta"]),
                    sql_text(row["source"]),
                    sql_text(row["license"]),
                    str(row["sort"]),
                    sql_text(row["provenance_state"]),
                )
            ) + ")"
        )

    return """-- Generated by tools/content-wave/build_sql.py. Do not edit by hand.
begin;

insert into public.city_section (
    id, city, kind, title, body, attribution, emoji, place_id, links, meta,
    source, license, sort, provenance_state
)
values
""" + ",\n".join(values) + """
on conflict (city, kind, title) do update set
    body = excluded.body,
    attribution = excluded.attribution,
    emoji = excluded.emoji,
    links = excluded.links,
    meta = excluded.meta,
    source = excluded.source,
    license = excluded.license,
    sort = excluded.sort,
    provenance_state = excluded.provenance_state;

commit;
"""


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--expected-city-count", type=int, default=141)
    parser.add_argument("--sql-out", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows = normalize_rows(load_rows(args.inputs))
        summary = validate_rows(rows, args.expected_city_count)
        sql = compile_sql(rows)
        if args.sql_out:
            args.sql_out.parent.mkdir(parents=True, exist_ok=True)
            args.sql_out.write_text(sql)
        else:
            sys.stdout.write(sql)
        print(json.dumps(summary, sort_keys=True), file=sys.stderr)
        return 0
    except WaveError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
