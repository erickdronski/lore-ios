"""Validate a public starter snapshot after exporting it with export.sql."""
import json
import sys
from collections import Counter
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID

catalog_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "Sources/Lore/Resources/LoreStarterCatalog.json"
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
assert catalog["schema_version"] == 1
cities = {city["slug"]: city for city in catalog["cities"]}
places = {place["id"]: place for place in catalog["places"]}
dives = {dive["place_id"]: dive for dive in catalog["dives"]}
assert len(cities) == len(catalog["cities"]) and "chicago" in cities
assert len(places) == len(catalog["places"]) == len({place["slug"] for place in places.values()})
assert len(dives) == len(catalog["dives"]) and dives.keys() == places.keys()
coverage = Counter(place["city"] for place in places.values())
assert coverage.keys() == cities.keys() and min(coverage.values()) >= 3
for city in cities.values():
    assert city["status"] == "live" and city["name"] and city["country"]
for place_id, place in places.items():
    UUID(place_id)
    assert -90 <= place["lat"] <= 90 and -180 <= place["lng"] <= 180
    assert place["slug"] and place["kind"] and place["name"] and place["hook_text"]
    dive = dives[place_id]
    assert dive["source"] and len(dive["narrative"].split()) >= 25
    url = urlsplit(dive["links"]["source_url"])
    assert url.scheme == "https" and url.hostname and not url.username and not url.password
    assert not dive["media"] and all(isinstance(event["year"], int) and event["title"] for event in dive["timeline"])
for tour in catalog["tours"]:
    stops = sorted(tour["tour_stop"], key=lambda stop: stop["seq"])
    assert len(stops) >= 2 and [stop["seq"] for stop in stops] == list(range(1, len(stops) + 1))
    assert all(places[stop["place_id"]]["city"] == tour["city"] and stop["tour_id"] == tour["id"] for stop in stops)
print(f"Verified {len(cities)} cities, {len(places)} unique places and linked dossiers, {len(catalog['tours'])} tours.")
