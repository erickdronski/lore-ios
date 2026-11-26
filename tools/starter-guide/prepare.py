"""Prepare a release atlas from the public export. Run only at release time.

python3 tools/starter-guide/prepare.py public-export.json LoreStarterCatalog.json

The build checks the linked geographic article for each map pin. It keeps Lore's
licensed geometry, except for the individually identified Wikidata corrections
below. Article coordinates are compared in memory and never redistributed.
"""
import argparse
import json
import math
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote, unquote, urlencode, urlsplit
from urllib.request import Request, urlopen


# Manually matched CC0 coordinate items for misplaced pins or ambiguous articles.
# Fetch P625 at preparation time. Preserve each public Lore place's original ID.
GEOMETRY_ITEMS = {
    "asheville-basilica-of-st-lawrence": "Q4867387", "asheville-biltmore-estate": "Q585521",
    "asheville-grove-arcade": "Q17985580", "asheville-thomas-wolfe-house": "Q7795278",
    "charleston-fort-sumter": "Q737517", "charleston-magnolia-cemetery": "Q12061438",
    "charleston-gadsden-s-wharf": "Q85850644",
    "key-west-ernest-hemingway-home-and-museum": "Q280171",
    "key-west-fort-zachary-taylor-state-park": "Q1162281",
    "key-west-key-west-southernmost-point": "Q2304747",
    "key-west-mallory-square-sunset-celebration": "Q1887609",
    "newport-ri-cliff-walk": "Q16982763", "newport-ri-fort-adams": "Q5470704",
    "newport-ri-the-breakers": "Q1786400", "newport-ri-touro-synagogue": "Q1355822",
    "newport-ri-whitehorne-house-the-ghost-bride-legend": "Q7412924",
    "salem-chestnut-street": "Q5093998", "salem-house-of-the-seven-gables": "Q3297920",
    "salem-salem-maritime-national-historic-site-derby-whar": "Q2214191",
    "seattle-ballard-locks": "Q5769218", "boston-mount-auburn-cemetery": "Q1950363",
    "philadelphia-bartram-s-garden": "Q2313437", "savannah-wormsloe-historic-site": "Q8036892",
    "los-angeles-chateau-marmont": "Q741123", "nyc-lyceum-theatre": "Q1756846",
    "shedd-aquarium": "Q2166515", "st-regis-chicago": "Q19817578",
    "isabella-stewart-gardner-museum": "Q49135", "liberty-science-center": "Q6541946",
    "museum-of-pop-culture": "Q1384356", "neon-museum": "Q6993430",
    "paulsdale-alice-paul": "Q7155356", "rainier-tower": "Q7284914", "rubell-museum": "Q86757788",
    "miami-lowe-art-museum": "Q3837886",
}

# Updated display names. Stable slugs still resolve saved places and older links.
NAMES = {
    "stow-lake": ("Blue Heron Lake", "San Francisco Recreation and Park Department", "https://sfrecpark.org/1870/Golden-Gate-Park-Lakes"),
    "museum-of-science-and-industry": ("Griffin Museum of Science and Industry", "Griffin Museum of Science and Industry", "https://www.griffinmsi.org/about"),
    "guaranteed-rate-field": ("Rate Field", "Chicago White Sox", "https://www.mlb.com/whitesox/ballpark"),
    "los-angeles-the-hollywood-highland-center": ("Ovation Hollywood", "Ovation Hollywood", "https://www.ovationhollywood.com/visit"),
    "bo-railroad-museum": ("National Museum of Railroad History & Innovation", "National Museum of Railroad History & Innovation", "https://www.borail.org/about/"),
    "mccormick-field": ("HomeTrust Park", "Asheville Tourists", "https://www.milb.com/asheville/ballpark"),
    "perez-art-museum-miami": ("Pérez Art Museum Miami", "Pérez Art Museum Miami", "https://www.pamm.org/en/directions/"),
    "paulsdale-alice-paul": ("Paulsdale", "Alice Paul Center for Gender Justice", "https://www.alicepaul.org/visit/"),
}
LABELS = {
    "newport-ri-whitehorne-house-the-ghost-bride-legend": "Whitehorne House Museum",
    "salem-salem-maritime-national-historic-site-derby-whar": "Salem Maritime National Historical Park",
    "boston-the-haunted-granary-burying-ground": "Granary Burying Ground",
    "fishermans-wharf": "Fisherman’s Wharf",
    "key-west-mallory-square-sunset-celebration": "Mallory Square",
}
EXCLUDE = {
    "los-angeles-the-hollywood-roosevelt-hotel",  # duplicate with a misplaced pin
    "austin-congress-avenue-bridge-bat-emergence",  # duplicate bridge marker several blocks away
    "austin-hope-outdoor-gallery", "starbucks-reserve-roastery",  # former venues
    "tinker-field",  # source record identifies the demolished stadium
    "newport-ri-conanicut-point-wreck-treasure-and-mystery", "charleston-blackbeard-s-hideout-legend",
    "salem-the-bridget-bishop-legend-accusation-and-executi", "salem-the-gallows-hill-phantom-whispers-of-the-condemn",
    "los-angeles-the-playboy-mansion", "san-francisco-spreckels-mansion",
}
WIDE_FEATURES = {"park", "district", "nature", "infrastructure"}

# Check the original CC0 museum pin against the city map for the current
# building. Its Wikidata item still locates the museum at its previous site.
# https://www.miami.gov/Notices/Events-Activities/State-of-the-City-Address-2020
CHECKED_PINS = {"perez-art-museum-miami": (25.7860641, -80.186286)}


def api(host, **params):
    params.update(format="json", formatversion="2")
    request = Request(f"https://{host}/w/api.php?" + urlencode(params),
                      headers={"User-Agent": "Lore catalog preparation (https://lore-web-liart.vercel.app)"})
    with urlopen(request, timeout=40) as response:
        result = json.load(response)
    if "error" in result:
        raise ValueError(result["error"])
    if "continue" in result:
        raise ValueError("Incomplete reference batch")
    return result


def distance_km(lat, lng, other_lat, other_lng):
    phi, other_phi = map(math.radians, (lat, other_lat))
    dy, dx = other_phi - phi, math.radians(other_lng - lng)
    chord = math.sin(dy / 2)**2 + math.cos(phi)*math.cos(other_phi)*math.sin(dx / 2)**2
    return 12742 * math.asin(math.sqrt(min(chord, 1)))


def reference_pages(titles):
    pages = {}
    names = sorted(set(titles))
    for start in range(0, len(names), 40):
        batch = names[start:start+40]
        data = api("en.wikipedia.org", action="query", prop="coordinates|pageprops",
                   ppprop="disambiguation", colimit="max", redirects=1, titles="|".join(batch))["query"]
        redirects = {row["from"]: row["to"] for field in ("normalized", "redirects")
                     for row in data.get(field, [])}
        keyed = {row["title"]: row for row in data["pages"]}
        for original in batch:
            title = original
            seen = set()
            while title in redirects and title not in seen:
                seen.add(title)
                title = redirects[title]
            pages[original] = keyed[title]
    return pages


def corrected_geometry(slugs):
    ids = [GEOMETRY_ITEMS[s] for s in slugs if s in GEOMETRY_ITEMS]
    result = {}
    if not ids:
        return result
    for start in range(0, len(ids), 40):
        entities = api("www.wikidata.org", action="wbgetentities", ids="|".join(ids[start:start+40]),
                       props="claims|sitelinks", sitefilter="enwiki")["entities"]
        for item, entity in entities.items():
            claims = [c for c in entity.get("claims", {}).get("P625", []) if c.get("rank") != "deprecated"]
            for claim in sorted(claims, key=lambda c: c["rank"] != "preferred"):
                geo = claim["mainsnak"].get("datavalue", {}).get("value", {})
                title = entity.get("sitelinks", {}).get("enwiki", {}).get("title")
                if title and geo.get("globe", "").endswith("/Q2") and "latitude" in geo:
                    result[item] = (round(geo["latitude"], 6), round(geo["longitude"], 6), title)
                    break
    return result


def refresh_routes(catalog):
    places = {p["id"]: p for p in catalog["places"]}
    for index, tour in enumerate(catalog["tours"]):
        if index:
            time.sleep(1.1)
        points = [places[s["place_id"]] for s in tour["tour_stop"]]
        coords = ";".join(f"{p['lng']},{p['lat']}" for p in points)
        endpoint = "https://routing.openstreetmap.de/routed-foot/route/v1/driving/"
        request = Request(endpoint + coords + "?overview=false&steps=false",
                          headers={"User-Agent": "Lore release route check (https://lore-web-liart.vercel.app)"})
        with urlopen(request, timeout=35) as response:
            data = json.load(response)
        route = data["routes"][0]
        if data["code"] != "Ok" or len(route["legs"]) != len(points) - 1 or any(leg["distance"] <= 0 for leg in route["legs"]):
            raise ValueError(f"Unresolved walk: {tour['slug']}")
        if len(data["waypoints"]) != len(points) or any(w["distance"] > 180 for w in data["waypoints"]):
            raise ValueError(f"Review sidewalk access for {tour['slug']}")
        tour["distance_km"] = round(route["distance"] / 1000, 1)
        tour["duration_min"] = 5 * math.ceil((route["duration"] / 60 + 10 * len(points)) / 5)
        tour["route_checked_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        tour["route_note"] = ("Distance follows mapped pedestrian paths. Allow about ten minutes at each stop, "
                              "plus time for any indoor visits or queues. Check local access before setting out. "
                              "Route data © OpenStreetMap contributors.")


def prepare(catalog):
    if catalog.get("schema_version") != 2 or catalog.get("review_epoch") != 2026090501:
        raise ValueError("Review the updated publication contract before preparing a new release")
    edited = {d["place_id"] for d in catalog["dives"]}
    places = [p for p in catalog["places"] if p["slug"] not in EXCLUDE]
    geometry = corrected_geometry([p["slug"] for p in places])
    titles = {}
    for p in places:
        item = GEOMETRY_ITEMS.get(p["slug"])
        if item:
            lat, lng, title = geometry[item]
            if distance_km(p["lat"], p["lng"], lat, lng) > 20:
                raise ValueError(f"Recheck Wikidata match for {p['slug']}")
            p.update(lat=lat, lng=lng, geom_license="cc0", geom_source_url="https://www.wikidata.org/wiki/"+item)
            if p["id"] not in edited:
                p.update(source_name="Wikipedia", source_url="https://en.wikipedia.org/wiki/"+quote(title.replace(" ", "_"),safe="()"))
        if p["id"] not in edited:
            titles[p["slug"]] = unquote(urlsplit(p["source_url"]).path.removeprefix("/wiki/")).replace("_", " ")
    pages = reference_pages(titles.values())
    retained = []
    for p in places:
        slug = p["slug"]
        if slug in titles:
            page = pages[titles[slug]]
            if page.get("missing") or "disambiguation" in page.get("pageprops", {}):
                continue
            if slug in CHECKED_PINS:
                if distance_km(p["lat"], p["lng"], *CHECKED_PINS[slug]) > 0.05:
                    raise ValueError(f"Recheck the public location for {slug}")
            elif slug not in GEOMETRY_ITEMS:
                coords = next(iter(page.get("coordinates", [])), None)
                if not coords or coords.get("globe") != "earth":
                    continue
                limit = 0.75 if p["kind"] in WIDE_FEATURES else 0.3
                if distance_km(p["lat"], p["lng"], coords["lat"], coords["lon"]) > limit:
                    continue
        if slug in NAMES:
            name, publisher, url = NAMES[slug]
            p["name"] = name
            if p["id"] not in edited:
                p.update(source_name=publisher, source_url=url)
        elif slug in LABELS:
            p["name"] = LABELS[slug]
        retained.append(p)
    catalog["places"] = sorted(retained, key=lambda p: (p["city"], p["name"], p["id"]))
    cities = {p["city"] for p in retained}
    catalog["cities"] = [c for c in catalog["cities"] if c["slug"] in cities]
    refresh_routes(catalog)
    return catalog


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    catalog = prepare(json.loads(args.candidate.read_text()))
    # One record per line keeps release diffs small.
    arrays = ("cities", "places", "dives", "tours")
    fields = ['  "'+k+'": '+str(catalog[k]) for k in ("schema_version", "review_epoch")]
    for key in arrays:
        rows = [json.dumps(r, ensure_ascii=False, sort_keys=True, separators=(",", ":")) for r in catalog[key]]
        fields.append('  "'+key+'": [\n    '+',\n    '.join(rows)+'\n  ]')
    output = "{\n" + ",\n".join(fields) + "\n}\n"
    with tempfile.NamedTemporaryFile("w", dir=args.destination.parent, delete=False, encoding="utf-8") as handle:
        handle.write(output)
        temporary = Path(handle.name)
    try:
        subprocess.run([sys.executable, str(Path(__file__).with_name("validate.py")), str(temporary)], check=True)
        temporary.chmod(0o644)
        temporary.replace(args.destination)
    finally:
        temporary.unlink(missing_ok=True)
