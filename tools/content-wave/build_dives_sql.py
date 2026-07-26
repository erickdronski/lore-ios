#!/usr/bin/env python3
"""Validate missing Lore place dossiers and compile an idempotent SQL upsert."""

from __future__ import annotations

import argparse
import json
import re
import sys
import uuid
from pathlib import Path
from typing import Any, Sequence
from urllib.parse import urlsplit


REQUIRED_FIELDS = {
    "place_id",
    "narrative",
    "timeline",
    "links",
    "media",
    "source",
    "license",
}
TIMELINE_FIELDS = {"year", "title", "detail", "emoji"}
SOURCE_METADATA_FIELDS = {"title", "publisher", "url", "relationship"}


class DiveWaveError(RuntimeError):
    pass


def load_rows(path: Path) -> list[dict[str, Any]]:
    try:
        document = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise DiveWaveError(f"Could not read {path}: {error}") from error
    if not isinstance(document, list) or any(not isinstance(row, dict) for row in document):
        raise DiveWaveError(f"{path} must contain a top-level array of objects")
    return document


def _is_https(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlsplit(value)
    return parsed.scheme == "https" and bool(parsed.netloc)


def _word_count(value: str) -> int:
    return len(re.findall(r"\b[\w’'-]+\b", value, flags=re.UNICODE))


def validate_rows(rows: Sequence[dict[str, Any]], expected_count: int = 44) -> dict[str, Any]:
    errors: list[str] = []
    place_ids: set[str] = set()

    if len(rows) != expected_count:
        errors.append(f"wave contains {len(rows)} dives; expected {expected_count}")

    for index, row in enumerate(rows, 1):
        missing = REQUIRED_FIELDS - row.keys()
        extra = row.keys() - REQUIRED_FIELDS
        if missing:
            errors.append(f"row {index}: missing {', '.join(sorted(missing))}")
        if extra:
            errors.append(f"row {index}: unexpected {', '.join(sorted(extra))}")

        place_id = row.get("place_id")
        try:
            canonical_id = str(uuid.UUID(place_id)) if isinstance(place_id, str) else ""
        except ValueError:
            canonical_id = ""
        if not canonical_id or canonical_id != place_id:
            errors.append(f"row {index}: place_id must be a canonical UUID")
        elif place_id in place_ids:
            errors.append(f"row {index}: duplicate place_id {place_id}")
        else:
            place_ids.add(place_id)

        narrative = row.get("narrative")
        if not isinstance(narrative, str):
            errors.append(f"row {index}: narrative must be text")
        else:
            words = _word_count(narrative)
            if not 550 <= words <= 1_000:
                errors.append(
                    f"row {index} ({place_id}): narrative has {words} words; "
                    "expected 550-1000"
                )

        timeline = row.get("timeline")
        if not isinstance(timeline, list) or not 3 <= len(timeline) <= 7:
            errors.append(
                f"row {index} ({place_id}): timeline needs 3-7 events"
            )
        else:
            years: list[int] = []
            for event_index, event in enumerate(timeline, 1):
                if not isinstance(event, dict) or set(event) != TIMELINE_FIELDS:
                    errors.append(
                        f"row {index} ({place_id}) event {event_index}: invalid fields"
                    )
                    continue
                year = event.get("year")
                if not isinstance(year, int):
                    errors.append(
                        f"row {index} ({place_id}) event {event_index}: year must be integer"
                    )
                else:
                    years.append(year)
                if not isinstance(event.get("title"), str) or not event["title"].strip():
                    errors.append(
                        f"row {index} ({place_id}) event {event_index}: title is required"
                    )
                if not isinstance(event.get("detail"), str) or not event["detail"].strip():
                    errors.append(
                        f"row {index} ({place_id}) event {event_index}: detail is required"
                    )
            if years != sorted(years):
                errors.append(f"row {index} ({place_id}): timeline is not chronological")

        links = row.get("links")
        media = row.get("media")
        if not isinstance(links, dict) or not isinstance(media, dict):
            errors.append(f"row {index} ({place_id}): links and media must be objects")
        else:
            website = links.get("website")
            if website is not None and not _is_https(website):
                errors.append(f"row {index} ({place_id}): links.website must be HTTPS")
            sources = links.get("sources")
            if sources is not None:
                if not isinstance(sources, list) or not sources:
                    errors.append(
                        f"row {index} ({place_id}): links.sources must be a non-empty array"
                    )
                else:
                    for source_index, source in enumerate(sources, 1):
                        if not isinstance(source, dict) or set(source) != SOURCE_METADATA_FIELDS:
                            errors.append(
                                f"row {index} ({place_id}) source {source_index}: "
                                "invalid fields"
                            )
                            continue
                        for field in SOURCE_METADATA_FIELDS - {"url"}:
                            if not isinstance(source[field], str) or not source[field].strip():
                                errors.append(
                                    f"row {index} ({place_id}) source {source_index}: "
                                    f"{field} is required"
                                )
                        if not _is_https(source["url"]):
                            errors.append(
                                f"row {index} ({place_id}) source {source_index}: "
                                "url must be HTTPS"
                            )
            wikipedia_title = media.get("wikipedia_title")
            if wikipedia_title is not None and (
                not isinstance(wikipedia_title, str) or not wikipedia_title.strip()
            ):
                errors.append(f"row {index} ({place_id}): invalid media title")

        if not _is_https(row.get("source")):
            errors.append(f"row {index} ({place_id}): source must be HTTPS")
        if row.get("license") != "cc0":
            errors.append(f"row {index} ({place_id}): license must be cc0")

    if errors:
        preview = "\n".join(f"- {error}" for error in errors[:80])
        if len(errors) > 80:
            preview += f"\n- ... and {len(errors) - 80} more"
        raise DiveWaveError(f"Dive wave validation failed:\n{preview}")

    return {"dives": len(rows), "places": len(place_ids)}


def sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sql_json(value: Any) -> str:
    return sql_text(json.dumps(value, ensure_ascii=False, sort_keys=True)) + "::jsonb"


def compile_sql(rows: Sequence[dict[str, Any]]) -> str:
    ordered = sorted(rows, key=lambda row: row["place_id"])
    place_ids = ", ".join(sql_text(row["place_id"]) for row in ordered)
    values = []
    for row in ordered:
        values.append(
            "(" + ", ".join(
                (
                    sql_text(row["place_id"]),
                    sql_text(row["narrative"]),
                    sql_json(row["timeline"]),
                    sql_json(row["links"]),
                    sql_json(row["media"]),
                    sql_text(row["source"]),
                    sql_text(row["license"]),
                )
            ) + ")"
        )

    return f"""-- Generated by tools/content-wave/build_dives_sql.py. Do not edit by hand.
begin;

do $validate_places$
begin
    if exists (
        select requested.place_id
        from unnest(array[{place_ids}]::uuid[]) as requested(place_id)
        left join public.place p on p.id = requested.place_id
        where p.id is null or p.deleted_at is not null
    ) then
        raise exception 'Dive wave references a missing or deleted place';
    end if;
end
$validate_places$;

insert into public.dive (
    place_id, narrative, timeline, links, media, source, license
)
values
""" + ",\n".join(values) + """
on conflict (place_id) do update set
    narrative = excluded.narrative,
    timeline = excluded.timeline,
    links = excluded.links,
    media = excluded.media,
    source = excluded.source,
    license = excluded.license;

commit;
"""


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--expected-count", type=int, default=44)
    parser.add_argument("--sql-out", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        rows = load_rows(args.input)
        summary = validate_rows(rows, args.expected_count)
        args.sql_out.parent.mkdir(parents=True, exist_ok=True)
        args.sql_out.write_text(compile_sql(rows))
        print(json.dumps(summary, sort_keys=True))
        return 0
    except DiveWaveError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
