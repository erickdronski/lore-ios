#!/usr/bin/env python3
"""Build source-seeded local-expert addon rows for live Lore cities.

The generator intentionally derives original cards from existing source-backed
city rows instead of inventing new unsourced facts. It creates the local-expert
add-on profile expected by build_sql.py.
"""

from __future__ import annotations

import argparse
import json
import re
import unicodedata
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path
from typing import Any, Iterable, Sequence
from urllib.parse import quote, urlsplit


EXPERT_COUNTS = {
    "watch": 2,
    "hashtag": 3,
    "local_legend": 2,
    "first_timer_mistake": 2,
    "neighborhood_decode": 2,
    "photo_prompt": 2,
    "seasonal": 1,
}
SORTS = {
    "watch": 160,
    "hashtag": 170,
    "local_legend": 180,
    "first_timer_mistake": 190,
    "neighborhood_decode": 200,
    "photo_prompt": 210,
    "seasonal": 220,
}
SOURCE_KIND_PRIORITY = {
    "story": 0,
    "fact": 1,
    "culture_person": 2,
    "culture_quote": 3,
    "culture_saying": 4,
    "culture_slang": 5,
    "market": 6,
    "etiquette": 7,
    "drink": 8,
    "phrase": 9,
}


class BuildError(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise BuildError(f"Could not read {path}: {error}") from error


def load_existing_rows(paths: Iterable[Path]) -> dict[str, list[dict[str, Any]]]:
    rows_by_city: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for path in paths:
        document = load_json(path)
        if not isinstance(document, list):
            raise BuildError(f"{path} must contain a top-level array")
        for row in document:
            if not isinstance(row, dict):
                continue
            city = row.get("city")
            source = row.get("source")
            if isinstance(city, str) and _https_url(source):
                rows_by_city[city].append(row)
    return rows_by_city


def load_rich_seed_rows(path: Path | None) -> dict[str, list[dict[str, Any]]]:
    if path is None:
        return {}
    document = load_json(path)
    if not isinstance(document, dict):
        raise BuildError(f"{path} must contain an object of table arrays")

    rows_by_city: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in document.get("story", []):
        source = row.get("source") if isinstance(row, dict) else None
        city = row.get("city") if isinstance(row, dict) else None
        title = row.get("title") if isinstance(row, dict) else None
        body = row.get("narrative") if isinstance(row, dict) else None
        if isinstance(city, str) and isinstance(title, str) and _https_url(source):
            rows_by_city[city].append(_seed(city, "story", title, body, source, row))

    for row in document.get("city_fact", []):
        source = row.get("source") if isinstance(row, dict) else None
        city = row.get("city") if isinstance(row, dict) else None
        title = row.get("fact") if isinstance(row, dict) else None
        detail = row.get("detail") if isinstance(row, dict) else None
        if isinstance(city, str) and isinstance(title, str) and _https_url(source):
            body = detail if isinstance(detail, str) and detail.strip() else title
            rows_by_city[city].append(_seed(city, "fact", title, body, source, row))

    for row in document.get("city_culture", []):
        source = row.get("source") if isinstance(row, dict) else None
        city = row.get("city") if isinstance(row, dict) else None
        title = row.get("headline") if isinstance(row, dict) else None
        body = row.get("body") if isinstance(row, dict) else None
        kind = row.get("kind") if isinstance(row, dict) else "saying"
        if isinstance(city, str) and isinstance(title, str) and _https_url(source):
            seed_kind = f"culture_{kind}" if isinstance(kind, str) else "culture_saying"
            rows_by_city[city].append(_seed(city, seed_kind, title, body, source, row))

    return rows_by_city


def _seed(
    city: str,
    kind: str,
    title: str,
    body: Any,
    source: str,
    raw: dict[str, Any],
) -> dict[str, Any]:
    return {
        "city": city,
        "kind": kind,
        "title": title,
        "body": body if isinstance(body, str) and body.strip() else title,
        "source": source,
        "raw": raw,
    }


def target_cities(audit_path: Path) -> list[dict[str, str]]:
    audit = load_json(audit_path)
    if not isinstance(audit, dict):
        raise BuildError("Audit JSON must be an object")
    targets: list[dict[str, str]] = []
    for city in audit.get("cities", []):
        if not isinstance(city, dict):
            continue
        checks = city.get("section_kind_checks")
        if not isinstance(checks, dict):
            continue
        needs_expert = any(
            isinstance(checks.get(kind), dict)
            and int(checks[kind].get("deficit", 0)) > 0
            for kind in EXPERT_COUNTS
        )
        if needs_expert:
            slug = city.get("slug")
            name = city.get("name") or slug
            country = city.get("country") or ""
            if isinstance(slug, str) and isinstance(name, str):
                targets.append({"slug": slug, "name": name, "country": str(country)})
    return sorted(targets, key=lambda item: item["slug"])


def source_rows_for_city(city: str, rows: Sequence[dict[str, Any]]) -> list[dict[str, Any]]:
    candidates = [row for row in rows if _https_url(row.get("source"))]
    candidates.sort(
        key=lambda row: (
            SOURCE_KIND_PRIORITY.get(str(row.get("kind")), 9),
            str(row.get("title") or "").casefold(),
        )
    )
    if not candidates:
        raise BuildError(f"No source-backed rows found for {city}")
    return candidates


def merge_seed_rows(
    base_rows: dict[str, list[dict[str, Any]]],
    rich_rows: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    merged: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for city, rows in base_rows.items():
        merged[city].extend(rows)
    for city, rows in rich_rows.items():
        merged[city].extend(rows)
    return merged


def build_rows(
    targets: Sequence[dict[str, str]],
    existing_rows: dict[str, list[dict[str, Any]]],
    accessed: str,
) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for target in targets:
        slug = target["slug"]
        name = target["name"]
        country = target["country"]
        sources = source_rows_for_city(slug, existing_rows.get(slug, []))
        primary = _pick_seed(sources, ("story", "fact", "culture_person", "culture_quote"))
        secondary = _pick_seed(sources, ("market", "etiquette", "culture_saying", "culture_slang"), 1)
        tertiary = _pick_seed(sources, ("story", "fact", "market", "etiquette"), 2)
        legend = _pick_seed(sources, ("story", "fact", "culture_quote", "culture_person"))
        legend_two = _pick_seed(sources, ("fact", "story", "culture_saying", "culture_slang"), 1)
        place = _pick_seed(sources, ("market", "story", "etiquette", "fact"))
        place_two = _pick_seed(sources, ("etiquette", "market", "culture_slang", "culture_saying"), 1)
        anchor = _anchor_label(primary, name)
        second_anchor = _anchor_label(secondary, name)
        legend_anchor = _anchor_label(legend, name)
        legend_two_anchor = _anchor_label(legend_two, name)
        place_anchor = _anchor_label(place, name)
        place_two_anchor = _anchor_label(place_two, name)
        output.extend(
            [
                _row(
                    slug,
                    "watch",
                    f"Watch {name} before you wander",
                    (
                        f"Start with a video search seeded by Lore's {anchor} source trail. "
                        "Look for current walking clips, museum explainers, and neighborhood cues, "
                        "then verify hours or access on official venue pages."
                    ),
                    f"Video discovery seeded from {anchor}",
                    "🎬",
                    {
                        "youtube_url": _youtube_search(
                            f"{name} official tourism history walking tour"
                        ),
                        "source": primary["source"],
                    },
                    _meta(accessed, "YouTube", "Public search", primary),
                    primary["source"],
                    160,
                ),
                _row(
                    slug,
                    "watch",
                    f"Scan short clips with a local lens",
                    (
                        f"Use short-form clips as a vibe check, not as proof. For {name}, "
                        f"compare what people film around {second_anchor} with the sourced "
                        "place cards in Lore before building a route."
                    ),
                    f"Short-form discovery seeded from {second_anchor}",
                    "📱",
                    {
                        "tiktok_url": _tiktok_search(f"{name} local history hidden guide"),
                        "source": secondary["source"],
                    },
                    _meta(accessed, "TikTok", "Public search", secondary),
                    secondary["source"],
                    161,
                ),
            ]
        )

        tags = _hashtags(name, slug, country)
        for index, tag in enumerate(tags):
            platform = "Instagram" if index != 1 else "TikTok"
            tag_url = (
                f"https://www.instagram.com/explore/tags/{tag[1:].lower()}/"
                if platform == "Instagram"
                else f"https://www.tiktok.com/tag/{tag[1:].lower()}"
            )
            output.append(
                _row(
                    slug,
                    "hashtag",
                    tag,
                    _hashtag_body(tag, name, index),
                    f"{name} public discovery tag",
                    "#️⃣",
                    {
                        "hashtag_url": tag_url,
                        "instagram_url": tag_url if platform == "Instagram" else None,
                        "tiktok_url": tag_url if platform == "TikTok" else None,
                        "source": primary["source"],
                    },
                    _meta(
                        accessed,
                        platform,
                        "Public search",
                        primary,
                        {"hashtag": tag, "rights": "external_search_only"},
                    ),
                    primary["source"],
                    170 + index,
                )
            )

        output.extend(
            [
                _row(
                    slug,
                    "local_legend",
                    _trim_title(f"{legend_anchor} has local layers"),
                    (
                        f"In {name}, {legend_anchor} is a useful lore thread. "
                        f"{_summary_sentence(legend)} Keep it as a sourced starting point, "
                        "then let the surrounding place make the story tangible."
                    ),
                    f"Lore source trail: {legend_anchor}",
                    "🗝️",
                    {"source": legend["source"]},
                    _meta(accessed, None, None, legend, {"confidence": "documented"}),
                    legend["source"],
                    180,
                ),
                _row(
                    slug,
                    "local_legend",
                    _trim_title(f"{legend_two_anchor} rewards a second look"),
                    (
                        f"A second layer appears through {legend_two_anchor}. "
                        f"{_summary_sentence(legend_two)} Use it as a prompt to ask what "
                        "locals notice that a quick itinerary misses."
                    ),
                    f"Lore source trail: {legend_two_anchor}",
                    "📜",
                    {"source": legend_two["source"]},
                    _meta(accessed, None, None, legend_two, {"confidence": "documented"}),
                    legend_two["source"],
                    181,
                ),
                _row(
                    slug,
                    "first_timer_mistake",
                    _trim_title(f"Treating {place_anchor} as a quick stop"),
                    (
                        f"The first-timer mistake is rushing {place_anchor} for one photo. "
                        f"{_summary_sentence(place)} Slow down, read the context, and keep "
                        "working paths clear."
                    ),
                    f"Visitor cue from {place_anchor}",
                    "⚠️",
                    {"source": place["source"]},
                    _meta(accessed, None, None, place, {"confidence": "documented"}),
                    place["source"],
                    190,
                ),
                _row(
                    slug,
                    "first_timer_mistake",
                    _trim_title("Ignoring the local pace cue"),
                    (
                        f"Do not force {name} into a generic checklist. "
                        f"{_summary_sentence(place_two)} Let greetings, queues, markets, "
                        "and quiet edges tell you how fast to move."
                    ),
                    f"Visitor cue from {place_two_anchor}",
                    "🧭",
                    {"source": place_two["source"]},
                    _meta(accessed, None, None, place_two, {"confidence": "documented"}),
                    place_two["source"],
                    191,
                ),
                _row(
                    slug,
                    "neighborhood_decode",
                    _trim_title(f"Start with {place_anchor}"),
                    (
                        f"Use {place_anchor} as your first neighborhood decoder in {name}. "
                        f"{_summary_sentence(place)} Then compare the side streets, transit "
                        "stops, and public edges around it."
                    ),
                    f"Neighborhood cue from {place_anchor}",
                    "🏘️",
                    {"source": place["source"]},
                    _meta(accessed, None, None, place, {"confidence": "documented"}),
                    place["source"],
                    200,
                ),
                _row(
                    slug,
                    "neighborhood_decode",
                    _trim_title(f"Follow {place_two_anchor} for the second read"),
                    (
                        f"{place_two_anchor} gives {name} a different rhythm. "
                        f"{_summary_sentence(place_two)} Put it beside the famous stops so "
                        "the city feels connected instead of scattered."
                    ),
                    f"Neighborhood cue from {place_two_anchor}",
                    "🧩",
                    {"source": place_two["source"]},
                    _meta(accessed, None, None, place_two, {"confidence": "documented"}),
                    place_two["source"],
                    201,
                ),
                _row(
                    slug,
                    "photo_prompt",
                    _trim_title(f"Frame {place_anchor} without making people the subject"),
                    (
                        f"Photograph {place_anchor} through signs, thresholds, materials, and public "
                        "space. Avoid close-ups of workers, worshippers, vendors, or children "
                        "unless you have clear consent."
                    ),
                    f"Photo cue from {place_anchor}",
                    "📷",
                    {"source": place["source"]},
                    _meta(
                        accessed,
                        None,
                        None,
                        place,
                        {"confidence": "documented", "prompt_type": "public_space"},
                    ),
                    place["source"],
                    210,
                ),
                _row(
                    slug,
                    "photo_prompt",
                    _trim_title(f"Catch the detail that explains {name}"),
                    (
                        f"Look for one small detail near {place_two_anchor}: a route sign, market "
                        "texture, transit cue, courtyard edge, or public inscription. The best "
                        "photo explains how the place works."
                    ),
                    f"Photo cue from {place_two_anchor}",
                    "🔎",
                    {"source": place_two["source"]},
                    _meta(
                        accessed,
                        None,
                        None,
                        place_two,
                        {"confidence": "documented", "prompt_type": "detail"},
                    ),
                    place_two["source"],
                    211,
                ),
                _row(
                    slug,
                    "seasonal",
                    _trim_title(f"Check {name}'s calendar before you commit"),
                    (
                        f"Use {name}'s current event rhythm before locking a walk. Weather, "
                        "festival days, religious observances, market schedules, and museum "
                        f"programs can change how {anchor} feels on the ground."
                    ),
                    f"Seasonal planning cue from {anchor}",
                    "📅",
                    {"source": tertiary["source"]},
                    _meta(
                        accessed,
                        None,
                        None,
                        tertiary,
                        {"confidence": "documented", "best_season": "Check current calendar"},
                    ),
                    tertiary["source"],
                    220,
                ),
            ]
        )
    _validate_counts(output, len(targets))
    return output


def _pick_seed(
    sources: Sequence[dict[str, Any]],
    kinds: Sequence[str],
    fallback_index: int = 0,
) -> dict[str, Any]:
    for kind in kinds:
        for row in sources:
            if row.get("kind") == kind:
                return row
    return sources[min(fallback_index, len(sources) - 1)]


def _row(
    city: str,
    kind: str,
    title: str,
    body: str,
    attribution: str,
    emoji: str,
    links: dict[str, Any],
    meta: dict[str, Any],
    source: str,
    sort: int,
) -> dict[str, Any]:
    return {
        "city": city,
        "kind": kind,
        "title": _trim_title(title),
        "body": _clean_text(body),
        "attribution": _clean_text(attribution),
        "emoji": emoji,
        "links": {key: value for key, value in links.items() if value},
        "meta": meta,
        "source": source,
        "license": "cc0",
        "sort": sort,
        "provenance_state": "reference_only",
    }


def _meta(
    accessed: str,
    platform: str | None,
    creator: str | None,
    source_row: dict[str, Any],
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    meta = {
        "wave": "2026-08",
        "profile": "local-expert-addons",
        "accessed": accessed,
        "rights": "original_lore_copy",
        "review_state": "source_checked",
        "rights_review": "link_only_ok",
        "confidence": "source-seeded",
        "seed_kind": source_row.get("kind"),
        "seed_title": source_row.get("title"),
    }
    if platform:
        meta["platform"] = platform
    if creator:
        meta["creator"] = creator
    if extra:
        meta.update(extra)
    return meta


def _validate_counts(rows: Sequence[dict[str, Any]], expected_cities: int) -> None:
    by_city: dict[str, Counter[str]] = defaultdict(Counter)
    for row in rows:
        by_city[row["city"]][row["kind"]] += 1
    if len(by_city) != expected_cities:
        raise BuildError(f"Generated {len(by_city)} cities; expected {expected_cities}")
    for city, counts in sorted(by_city.items()):
        for kind, expected in EXPERT_COUNTS.items():
            if counts[kind] != expected:
                raise BuildError(f"{city}: expected {expected} {kind}, got {counts[kind]}")


def _anchor_label(row: dict[str, Any], fallback: str) -> str:
    title = str(row.get("title") or "").strip()
    if not title:
        return fallback
    title = re.sub(r"^[#@]+", "", title)
    return _clean_text(title[:54])


def _summary_sentence(row: dict[str, Any]) -> str:
    body = _clean_text(str(row.get("body") or ""))
    sentences = re.split(r"(?<=[.!?])\s+", body)
    for sentence in sentences:
        sentence = _clean_text(sentence)
        if 25 <= len(sentence) <= 220:
            return sentence
    if body:
        return body[:220].rstrip(" ,;:") + "."
    return "The existing Lore source trail gives this place useful context."


def _hashtags(name: str, slug: str, country: str) -> list[str]:
    compact = _ascii_alnum(name)
    slug_compact = _ascii_alnum(slug)
    candidates = [
        f"#{compact}",
        f"#Visit{compact}",
        f"#{compact}{country.upper()}" if country else f"#{slug_compact}Guide",
    ]
    seen = set()
    tags = []
    for tag in candidates:
        if len(tag) < 2:
            continue
        if tag.lower() in seen:
            continue
        seen.add(tag.lower())
        tags.append(tag[:64])
    while len(tags) < 3:
        tags.append(f"#{slug_compact}Lore{len(tags) + 1}")
    return tags[:3]


def _hashtag_body(tag: str, name: str, index: int) -> str:
    if index == 0:
        return (
            f"Use {tag} as the broad public search trail for {name}. Treat it as a "
            "mood board, then return to source-backed Lore cards before acting on details."
        )
    if index == 1:
        return (
            f"Use {tag} when you want visitor-facing clips and trip-planning context. "
            "The useful move is comparing posts with official hours, routes, and local norms."
        )
    return (
        f"Use {tag} to narrow the feed when the city name is shared or noisy. Pair it "
        "with a neighborhood, venue, or date before trusting the signal."
    )


def _youtube_search(query: str) -> str:
    return f"https://www.youtube.com/results?search_query={quote(query)}"


def _tiktok_search(query: str) -> str:
    return f"https://www.tiktok.com/search?q={quote(query)}"


def _ascii_alnum(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_only = normalized.encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^A-Za-z0-9]", "", ascii_only) or "Lore"


def _trim_title(value: str) -> str:
    cleaned = _clean_text(value)
    if len(cleaned) <= 80:
        return cleaned
    return cleaned[:77].rstrip(" ,;:") + "..."


def _clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def _https_url(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    parsed = urlsplit(value.strip())
    if parsed.scheme == "https" and parsed.netloc:
        return value.strip()
    return None


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", type=Path, default=Path("/tmp/lore-content-audit.json"))
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--rich-seeds", type=Path)
    parser.add_argument("--accessed", default=date.today().isoformat())
    parser.add_argument("inputs", nargs="+", type=Path)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        targets = target_cities(args.audit)
        existing_rows = merge_seed_rows(
            load_existing_rows(args.inputs),
            load_rich_seed_rows(args.rich_seeds),
        )
        rows = build_rows(targets, existing_rows, args.accessed)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")
        print(
            json.dumps(
                {
                    "cities": len(targets),
                    "rows": len(rows),
                    "kinds": dict(sorted(Counter(row["kind"] for row in rows).items())),
                    "out": str(args.out),
                },
                sort_keys=True,
            )
        )
        return 0
    except BuildError as error:
        print(str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
