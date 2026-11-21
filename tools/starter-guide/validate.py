"""Check the integrity, sources, license scope and footprint of a release atlas."""
import json
import re
import sys
from collections import Counter
from math import asin, cos, radians, sin, sqrt
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID


def secure_url(raw):
    url = urlsplit(raw)
    return url.scheme == "https" and url.hostname and not url.username and not url.password


def km(a, b):
    lat1, lat2 = radians(a["lat"]), radians(b["lat"])
    dz = radians(b["lng"] - a["lng"])
    h = sin((lat2-lat1)/2)**2 + cos(lat1)*cos(lat2)*sin(dz/2)**2
    return 12742 * asin(sqrt(min(h, 1)))


catalog_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "Sources/Lore/Resources/LoreStarterCatalog.json"
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
assert catalog_path.stat().st_size < 1024 * 1024, "Unexpected resource growth"
assert catalog["schema_version"] == 2 and catalog["review_epoch"] == 2026090501
cities = {city["slug"]: city for city in catalog["cities"]}
places = {place["id"]: place for place in catalog["places"]}
dives = {dive["place_id"]: dive for dive in catalog["dives"]}
tours = {tour["slug"]: tour for tour in catalog["tours"]}
assert len(cities) == len(catalog["cities"]) and "chicago" in cities
assert len(places) == len(catalog["places"]) == len({place["slug"] for place in places.values()})
assert len(dives) == len(catalog["dives"]) and dives.keys() <= places.keys()
coverage = Counter(place["city"] for place in places.values())
assert coverage.keys() == cities.keys() and min(coverage.values()) >= 3, coverage
assert len(cities) >= 25 and len(places) >= 500 and len(dives) >= 25, "Unexpected release coverage change"
for city in cities.values():
    assert city["status"] == "live" and city["name"] and city["country"] == "US"
for place_id, place in places.items():
    UUID(place_id)
    assert -90 <= place["lat"] <= 90 and -180 <= place["lng"] <= 180
    assert km(place, cities[place["city"]]) < 85, place["slug"]
    assert re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", place["slug"]) and place["kind"] and place["name"]
    assert place["geom_license"] in {"cc0", "public_domain"} and place["source_name"] and secure_url(place["source_url"])
    if "geom_source_url" in place:
        assert re.fullmatch(r"https://www\.wikidata\.org/wiki/Q[0-9]+", place["geom_source_url"])
    assert bool(place.get("hook_text")) == (place_id in dives)
    facts = place.get("layer1", {})
    assert facts.keys() <= {"architect", "style", "year_built"}
    assert isinstance(facts.get("year_built", 0), int)
for place_id, dive in dives.items():
    assert dive["source"] and len(dive["narrative"].split()) >= 25
    assert secure_url(dive["links"]["source_url"]) and dive["links"]["source_url"] == places[place_id]["source_url"]
    assert not dive["media"] and all(isinstance(e["year"], int) and e["title"] for e in dive["timeline"])
walks = {
    "millennium-moments": ["marina-city", "cloud-gate", "art-institute", "buckingham-fountain"],
    "emerald-city-sampler": ["space-needle", "pike-place-market", "seattle-great-wheel", "rainier-tower"],
    "national-mall-postcards": ["washington-monument", "united-states-capitol", "vietnam-veterans-memorial", "lincoln-memorial"],
}
assert tours.keys() == walks.keys() and len(tours) == len(catalog["tours"])
for slug, tour in tours.items():
    UUID(tour["id"])
    assert tour["is_premium"] is False and tour["travel_mode"] == "walking" and tour["distance_kind"] == "walking_route"
    assert tour["route_note"] and tour["route_checked_at"] and secure_url(tour["route_source"]) and tour["duration_min"] > 0
    stops = tour["tour_stop"]
    assert [stop["seq"] for stop in stops] == list(range(1, len(stops) + 1))
    assert all(stop["tour_id"] == tour["id"] and stop["place_id"] in dives and stop["note"] for stop in stops)
    points = [places[stop["place_id"]] for stop in stops]
    assert [p["slug"] for p in points] == walks[slug] and all(p["city"] == tour["city"] for p in points)
    assert tour["distance_km"] + 0.1 >= sum(km(a, b) for a, b in zip(points, points[1:])), slug
print(f"Verified {len(cities)} US cities, {len(places)} sourced places, {len(dives)} stories and {len(tours)} walking routes ({catalog_path.stat().st_size:,} bytes).")
