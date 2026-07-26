# Lore Content Experience Standard

**Status:** Required release gate for every destination with `city.status == "live"`

**Applies to:** Cities, towns, villages, neighborhoods presented as destinations, and future content waves

**Purpose:** Make every live destination feel complete, entertaining, educational, useful before a trip, and rewarding while exploring.

This standard is grounded in Lore's current `City`, `Place`, `Story`, `CitySection`, `Tour`, `TourStop`, `Dive`, narration, map relevance, and progress models. It defines what content must exist, how it should connect, and what must be validated before a destination or content wave is published.

## 1. The Experience Promise

Every live destination must let a traveler complete this loop without encountering an empty or misleading surface:

1. **Plan:** Understand why the destination is worth visiting, learn useful phrases, and choose a route for the available time, weather, and group.
2. **Orient:** See a legible map with a meaningful spread of places and stories, not a decorative cluster of duplicate pins.
3. **Discover:** Find a nearby moment, hidden detail, local ritual, food, sound, or person that rewards attention.
4. **Learn:** Move from a short hook to a sourced story, timeline, and optional narration without losing context.
5. **Do:** Follow a safe tour or complete a field prompt that connects the screen to the real place.
6. **Remember:** Mark visits, resume or complete tours, add private journal lore, and make honest progress toward achievements.

Lore content must be:

- **Place-true:** Specific enough that it could not be pasted onto another destination.
- **Fact-led:** Entertaining writing may shape verified facts, but may not invent facts, dialogue, motives, or certainty.
- **Human:** Center residents, makers, visitors, communities, and consequences, not only dates and structures.
- **Layered:** A quick traveler gets a useful hook; a curious traveler can continue into a full dossier.
- **Participatory:** Each destination asks the traveler to notice, listen, compare, try, or reflect.
- **Mode-flexible:** The experience remains worthwhile in rain, after dark, with children, with reduced mobility, without audio, and without a network connection.
- **Honest about capability:** Do not claim that a route, reward, translation, or accessibility feature exists unless the current app can present and support it.

## 2. Current Model Contract

The content pipeline must respect these existing behaviors.

| Surface | Current contract | Editorial consequence |
| --- | --- | --- |
| Destination | `City.slug` is the stable join key; only `status == "live"` publishes pins. | Every city-scoped row uses the exact live slug. Never use the display name as a join key. |
| Map place | `Place` requires an ID, slug, name, kind, coordinates, and city. `layer1.hook` powers the short card and scanner narration. | A map pin is not publishable until it has a truthful hook and resolves to its destination. |
| Nearby story | `Story` is a moment at real coordinates. Scanner discovery is limited to roughly 150 meters and four visible stories per frame. | Coordinates must represent where the moment happened, and story density must be tested at street scale. |
| City flavor | `CitySection.kind` is open-ended, but only `listen`, `field_note`, and a linked `experience` are currently interactive. | New kinds render as editorial cards, not new product behavior. Do not imply an unsupported action. |
| Tour | A `Tour` embeds ordered `TourStop` rows. Stops resolve through `place_id`; the client sorts them by `seq`. | Every route is a sequence of live places with continuous 1-based stop numbers. |
| Dive | A `Dive` belongs to one place. Its timeline is displayed in stored order; links and media are JSON objects. | Narratives, timeline order, media references, and fallback text must be curated before audio is attached. |
| Narration | A place hook uses on-device TTS. A dive prefers `audio_path`, then falls back to TTS of `narrative`. Playback never needs to fail silently. | Every audio-backed dive also needs readable narrative text. Studio audio is an enhancement, not the sole delivery mode. |
| Map curation | Interests and night mode weight pins; they generally do not hide them. Haunted stories and night places depend on exact tags. | Coverage must remain coherent with all filters cleared and must use registered tags consistently. |
| Tour progress | Resume state is keyed by traveler plus `Tour.slug`; completion is device-local. | A published tour slug is immutable. Reworking a route materially requires a new versioned slug. |
| Prompt progress | Interactive city-section completion is keyed by traveler plus `CitySection.id`; it is device-local. | A published interactive entry ID is immutable and may not be recycled for different content. |
| Achievements | Catalog rows are flexible, but real unlocks come from server-supported events such as visits and dive reads. | Tour and prompt completion must not promise a badge until a matching server event and criteria path exist. |

### Unsupported metadata rule

The current `Tour` model has no first-class fields for family suitability, weather, opening hours, step-free access, surface type, content warnings, or time of day. Until those fields and filters exist:

- Encode a verified variant plainly in the tour `title` and `blurb`.
- Use a linked `CitySection(kind: "experience")` to offer a rain, family, or evening starting point.
- Never describe an attribute as filterable.
- Never claim "accessible," "step-free," "open now," or "all weather" without a current route audit.
- Treat this encoding as editorial presentation, not structured metadata.

## 3. Destination Coverage Floors

Before authoring, assign one coverage band. The band reflects the destination's real scale, not the desired marketing tier. A small destination can be intimate; it cannot be thin.

| Minimum live coverage | Flagship city | City or town | Village or compact destination |
| --- | ---: | ---: | ---: |
| Distinct map places | 40 | 24 | 12 |
| Places with authored Layer-1 hooks | 40 | 24 | 12 |
| Coordinate-pinned stories | 28 | 18 | 10 |
| Curated tours | 5 | 4 | 3 |
| Free curated starter tours | 1 | 1 | 1 |
| Dives | 24 | 14 | 8 |
| Tour stops with dives | 100% | 100% | 100% |
| City-section entries | 42 | 36 | 34 |
| Studio-narrated dives | 12 | 7 | 4 |
| Story arcs | 5 | 4 | 3 |
| Interactive field/listen prompts | 8 | 6 | 6 |
| Weather, time, or family alternatives | 3 | 3 | 3 |

Additional floor rules:

- The generated "1 Hour In" route does not count as a curated tour.
- Every live place must have a non-empty Layer-1 hook. A pin with only a name is inventory, not Lore.
- At least 60% of map places must have a dive in a flagship city, 55% in a city or town, and 65% in a compact destination.
- Every tour stop must have a dive narrative so the stop-level Listen control is useful.
- At least half of all dives must have studio audio. The table above is the absolute floor when half would be lower.
- No more than 25% of places may share the same `kind`; parks, public art, civic spaces, food culture, sacred places, architecture, performance, industry, and everyday life should be represented where truthful.
- A destination that cannot meet its assigned floor remains `coming_soon` or is explicitly labeled as a preview. It does not silently ship as fully live.

## 4. The Reusable Destination Blueprint

Every destination packet must be designed as one connected experience rather than separate table-filling exercises.

### 4.1 Identity and orientation

Write a one-sentence editorial thesis before creating rows:

> `{Destination}` is a place where `{visible character}` reveals `{deeper tension or idea}` through `{three local lenses}`.

The thesis is an internal test, not necessarily app copy. Every arc, tour, and section should support or productively complicate it.

The packet must then define:

- One origin story, including the name and the people who used earlier names.
- Three to five signature lenses, such as water, migration, invention, faith, industry, music, food, resistance, landscape, or reinvention.
- Two common visitor misconceptions to correct gently.
- Two neighborhood or district contrasts when the destination has them.
- One local tension that prevents the content from becoming booster copy.
- One present-day continuity showing how history remains visible now.

### 4.2 Story arcs

A story arc is a sequence of related discoveries that accumulates meaning. Use a normalized `arc:<slug>` tag on every participating `Story` until a dedicated arc model exists.

Each arc must contain at least three stories in a flagship or city/town destination and at least two in a compact destination. Every destination must include these arc roles across its catalog:

1. **Origins:** Naming, first settlement, Indigenous context, founding, or the landscape before the current place.
2. **Change:** A fire, rebuilding, infrastructure shift, migration, economic turn, protest, or contested decision.
3. **People:** A resident, worker, artist, organizer, family, or community whose choices make the place personal.
4. **Everyday life:** Food, slang, recreation, transit, work, school, worship, or a ritual visitors can still observe.
5. **Wonder:** An overlooked detail, mystery, invention, record, cinematic moment, or beautiful surprise.

Small destinations may combine roles, but must still include origins, people, and wonder.

Every individual story must:

- Use a title of 4 to 12 words that creates curiosity without clickbait.
- Use a narrative of 90 to 220 words, with the most surprising verified detail in the first two sentences.
- Answer what happened, why this coordinate matters, who was affected, and what remains visible or meaningful today.
- Use `year_label` when the date is approximate, disputed, a range, or better expressed as a decade.
- Include at least one source and license/provenance value.
- Carry useful interest tags and exactly one primary arc tag.
- Distinguish documented history from oral tradition, legend, rumor, or disputed interpretation in the text itself.
- Use `ghost`, `haunted`, or `haunted-lore` only for intentionally opt-in night content.
- Use `hidden-find` only when there is a real, observable detail a traveler can locate.

Geographic rules:

- At least 60% of stories must sit inside one or more walkable discovery clusters.
- A compact destination needs at least one cluster; a city/town needs two; a flagship needs four.
- Do not place more than four priority stories within the same 150-meter scanner view without testing which four the distance sort will surface.
- Do not pin a general city story to city hall, downtown center, or a tourism office unless the event occurred there.

### 4.3 Tour catalog

Every destination must publish these three experience roles:

1. **Signature walk:** The clearest first visit, 60 to 90 minutes, 5 to 8 stops.
2. **Family or gentle walk:** 35 to 60 minutes, 4 to 6 stops, 2.5 km maximum, frequent visual prompts, and no route-dependent alcohol or graphic material.
3. **Conditions alternative:** A rain-ready, heat-aware, cold-weather, sheltered, or daylight/evening alternative, 30 to 75 minutes and 4 to 7 stops.

Flagship and city/town catalogs add themed walks such as music, architecture, food, waterfront, hidden details, civil rights, inventions, or after dark. At least one curated tour is free and valuable enough to demonstrate the complete Lore loop.

#### Tour story shape

Each route must feel like a guided narrative rather than an ordered list:

1. **Invitation:** Explain why this route is worth the walk now.
2. **Orientation:** Give the traveler a visible landmark and the route's central question.
3. **Origin:** Establish what came before.
4. **Complication:** Introduce change, conflict, ambition, or an unexpected consequence.
5. **Human turn:** Center a person or lived experience.
6. **Payoff:** Deliver the route's strongest reveal at or near the final third.
7. **Return:** End with a present-day connection and one invitation to notice more.

A shorter route may combine adjacent beats, but may not omit invitation, human turn, payoff, or return.

#### Tour and stop requirements

- `Tour.id` and `Tour.slug` are unique, non-empty, stable, and never reused.
- `Tour.city` exactly matches the destination slug.
- `duration_min` and `distance_km` are present, positive, route-audited values.
- The stored distance is within 20% of a current walkable route estimate.
- Stops use contiguous, unique, 1-based `seq` values with no gaps.
- Every `TourStop.place_id` resolves to a live place in the same city.
- A place appears no more than once in a tour.
- A standard walking leg is 100 to 800 meters. Longer legs require an explicit transition note in the previous stop.
- The route does not require trespass, unsafe crossings, restricted access, unmarked trails, or entry into a paid venue unless the blurb states the requirement.
- Each stop note is 15 to 50 words and begins with something the traveler can do or see: "Look up," "Stand back," "Notice," "Compare," "Listen," or equivalent natural language.
- Stop notes add context or observation; they do not repeat the Layer-1 hook.
- The first note or blurb states any essential ticket, schedule, footwear, daylight, or transit dependency.
- Material route changes publish under a new versioned slug, such as `river-and-rail-v2`, so saved progress is not reassigned to a different walk.

### 4.4 City sections and traveler utility

Every destination must meet this universal `CitySection` mix. Add more entries for larger destinations.

| Kind | Minimum | Content rule |
| --- | ---: | --- |
| `name_origin` | 1 | Explain the current name and acknowledge earlier or Indigenous names where relevant. |
| `phrase` | 6 | Cover greeting, thanks, please, excuse/help, ordering, and navigation. |
| `dish` | 3 | Describe what it is, why it is local, and how a visitor encounters it. |
| `drink` | 2 | Include at least one non-alcoholic option. Never present alcohol as required participation. |
| `ritual` | 2 | A repeatable local habit, custom, celebration, or rhythm. |
| `soundmark` or `sound` | 2 | A specific sound and where or when it can be heard. |
| `material` | 1 | A material, craft, geological feature, or building texture visible locally. |
| `etiquette` | 4 | Transit, queuing, tipping/payment, dress or sacred-space behavior, and local courtesy as applicable. |
| `number` | 3 | Useful or surprising figures with enough context to avoid trivia without meaning. |
| `market` | 1 | A real public market, main street, gathering place, or honest equivalent. |
| `experience` | 3 | Signature start, conditions alternative, and family/gentle option. Link each to a same-city place. |
| `listen` | 2 | A safe 30-second sound quest that works without recording the user. |
| `field_note` | 4 | A specific, safe observation or reflection with a clear completion moment. |

If a kind would be false or forced, document the exception and substitute an equal number of more truthful entries. Required traveler phrases, etiquette, three linked experiences, and five total interactive prompts may not be waived.

#### Phrase invariant

The phrase card UI gives each field a specific meaning:

- `title`: The local-language phrase as a traveler should see it.
- `body`: A concise English meaning and, when useful, when to use it.
- `attribution`: A traveler-friendly pronunciation or transliteration, not a source citation.
- `emoji`: Optional context, never the only explanation.

For destinations where English is not the primary local language, add at least four more phrases covering dietary needs, numbers/payment, emergency help, and a polite request to switch languages. Use the locally relevant language rather than assuming one national language serves every region.

#### Interactive section invariant

- `listen` asks for a sound that can usually be heard from a safe public position for 30 seconds.
- `field_note` is completable in one to three minutes and makes sense with the button text "I tried this."
- `experience` includes a non-null `place_id` that resolves to the intended same-city starting point.
- Interactive row IDs remain stable forever because completion is stored against `entry.id`.
- Completion language celebrates attention, not physical ability, speed, spending, photography, or sharing.

### 4.5 Field-prompt library

Each destination uses at least four different prompt modes:

- **Notice:** Find a symbol, seam, material, inscription, skyline break, or repeated shape.
- **Compare:** Contrast two facades, street widths, eras, languages, sounds, or public uses.
- **Listen:** Stay still for 30 seconds and name the nearest and farthest sounds.
- **Imagine:** Reconstruct a documented earlier view using visible anchors, without inventing people or dialogue.
- **Participate:** Try a greeting, public ritual, market custom, or local food ordering convention respectfully.
- **Reflect:** Consider who built, used, benefited from, or was displaced by what is visible.
- **Remember:** Add one observation to a private journal after marking a visit.

Every prompt must have a non-visual alternative when the primary action depends on sight, and a non-audio alternative when it depends on hearing. Prompts may never require trespass, touching protected objects, blocking circulation, photographing people, buying something, consuming alcohol, or disclosing personal information.

### 4.6 Dives and long-form learning

A dive is the sourced dossier behind a place, not a longer version of the same hook.

Each published dive must include:

- A narrative of 550 to 1,000 words, usually four to seven spoken minutes.
- A first paragraph that resolves the Layer-1 hook while opening a deeper question.
- At least three of these lenses: origin, design, people, conflict, use, change over time, local meaning, preservation, or present day.
- A timeline of 3 to 7 events in oldest-first order.
- A source/provenance value and at least one usable read-more link when a trustworthy public link exists.
- A narrative that stands alone when the hero image, audio, or network is unavailable.
- A final paragraph that returns attention to something the traveler can observe now.

Dive data rules:

- There is at most one live dive per `place_id`.
- `timeline` is an array; `links` and `media` are JSON objects, never arrays.
- Timeline IDs are effectively `year-title`; do not duplicate that pair.
- Timeline years are chronological. Use the detail field for approximate or multi-year context instead of false precision.
- `media.wikipedia_title` names an article whose lead image depicts the place or an editorially relevant subject, not merely the city.
- `links.website` uses HTTPS when available; `links.wikipedia_title` is an article title, not a URL.
- A studio-narrated dive always keeps its full `narrative` as TTS and reading fallback.

### 4.7 Narration beats

Lore has two narration scales and each needs different writing.

#### Scanner hook

- Target 35 to 55 words or roughly 15 to 25 seconds.
- Start by naming the place so audio orientation works with the phone lowered.
- Deliver one arresting, verified fact and one cue to look or listen.
- Avoid citations, parentheticals, abbreviations, symbol-heavy dates, and long lists in spoken copy.
- Never auto-play. The existing interaction offers narration and lets the traveler choose.

#### Dossier and tour-stop narration

- Target 120 to 155 spoken words per minute.
- Open with place name and physical orientation.
- Use a beat every 30 to 60 seconds: reveal, person, contrast, sensory cue, or reflective question.
- Put essential route or safety guidance in visible tour copy as well as audio.
- End before giving directions to the next stop; navigation and story should not compete.
- Write names, dates, measurements, and foreign words so TTS remains understandable.
- Maintain a pronunciation QA list for local names; if TTS cannot render a critical name clearly, prioritize that dive for studio audio.

Studio-audio invariants:

- `audio_path` is a relative storage path in the public `narration` bucket, not a full URL.
- `audio_seconds` is a positive integer within 5% of the encoded file duration.
- An audio row must have both `audio_path` and `audio_seconds`; neither field ships alone.
- The file exists, plays from a clean install, and is included by the offline city-pack flow.
- Loudness, silence, clipping, pronunciation, and chapter ending are reviewed with headphones and a phone speaker.
- The narrative text matches the recording in substance. Editorial corrections update both.

### 4.8 Weather, time, and family alternatives

Every destination publishes three honest alternatives, even when its main identity is outdoors.

#### Conditions alternative

- A rain, heat, cold, smoke, or high-wind plan appropriate to local conditions.
- Prefer covered streets, short outdoor legs, transit, public interiors, or a compact route.
- Never call a route indoor when any required stop depends on outdoor viewing.
- State ticket or opening-hour dependencies in the tour blurb.
- Include one no-route city-section option for a traveler who chooses to remain indoors.

#### Time alternative

- Provide a 30-to-45-minute quick route or an evening/daylight variant.
- Night routes use well-trafficked public areas and avoid content that invites a traveler into isolated locations.
- Haunted content is opt-in, clearly framed as folklore or documented belief, and never used to sensationalize real harm.
- A route dependent on illumination, a market day, tide, ceremony, or opening hours says so explicitly.

#### Family or gentle alternative

- Four to six stops, 2.5 km maximum, with a meaningful payoff in the first two stops.
- At least one find-it prompt, one movement-free prompt, and one choice question that supports conversation.
- Avoid graphic harm, adult nightlife, alcohol-dependent activities, and long uninterrupted narration.
- Do not market a route as stroller-friendly, wheelchair-accessible, sensory-friendly, or step-free until it has been audited for that claim.
- Family copy speaks to the whole group; it does not talk down to children or assign one adult as the default user.

## 5. Map and Discovery Quality

Content is only as good as its placement.

- All latitude values are between -90 and 90; longitude values are between -180 and 180.
- Destination coordinates and default camera center must frame the actual coverage area.
- Every place and story coordinate is checked against an authoritative map and satellite/street imagery when available.
- Two records may share a coordinate only when they represent genuinely distinct things at the same site.
- Avoid stacks of same-kind pins. Where a complex contains several records, choose the entries with distinct traveler value.
- Place tags use the app's recognized interest vocabulary where applicable. Unknown tags may enrich data but do not create a visible filter.
- Night places use the exact supported tags such as `nightlife`, `jazz`, `speakeasy`, `comedy`, `live-music`, `night-market`, `haunted`, `ghost`, `theater`, or `music-venue` when truthful.
- Map filters with everything cleared must still reveal a balanced destination.
- A 150-meter scanner test is performed in each story cluster so the four-story budget surfaces the strongest nearby moments.
- Tour pins and story pins are checked at minimum and maximum supported map zooms for overlap and legibility.
- A downloaded city pack is opened offline and must retain places, stories, tours, dives, media, and referenced narration.

## 6. Accessibility Standard

Accessibility is part of content authorship, not a final copy edit.

- Every essential audio fact also exists as readable text.
- No instruction depends only on color, emoji, animation, sound, compass direction, or a visual landmark.
- Emoji supplements a title; it never replaces a meaningful label.
- Use short paragraphs, concrete verbs, and plain language without flattening the history.
- Define specialized architecture, religious, political, and local terms on first use.
- Give measurements in locally familiar units and include a useful comparison when scale matters.
- Describe where to direct attention without assuming height, perfect vision, or the ability to stand in one exact location.
- Provide seated or stationary alternatives to movement prompts.
- Provide visual alternatives to listening prompts and non-visual alternatives to observation prompts.
- Avoid countdown pressure. The 30-second listen is an invitation; completing it is not required to access other content.
- Respect Reduce Motion by ensuring no editorial meaning exists only in an animated effect.
- Do not label a route accessible based only on map data. Verify curb cuts, grades, surfaces, stairs, doorways, rest points, crossings, and temporary closures.
- Content warnings precede graphic violence, death, persecution, or distressing legend material. If the current surface cannot show a warning before exposure, exclude that material from family routes and short hooks.
- Pronunciation guidance is written for comprehension, not as a judgment about accents.
- Translations are reviewed by a fluent local speaker before publication; machine output may be a draft, never the final authority.

## 7. Progress and Achievement Hooks

Every destination should create momentum without misrepresenting what the app records.

### Current completion events

- A tour stores current stop and completion locally, scoped to the guest or signed-in traveler.
- A `listen` or `field_note` city section stores local completion by row ID.
- A visit can trigger server achievement recomputation.
- Opening a dive can record a server-side dive read and support knowledge achievements.
- Tour completion and city-section completion do not currently create a server achievement event.

### Required hooks per destination

Design at least these five honest reward opportunities:

1. **First discovery:** A strong starter place that invites the traveler to log a visit.
2. **Knowledge:** A set of dives worth reading or listening to, connected to supported dive-read progress.
3. **Route completion:** A satisfying local completion beat at the end of every curated tour.
4. **Attention:** At least five locally completable `listen` or `field_note` entries.
5. **Memory:** At least one prompt inviting a private journal note after a visit.

Achievement catalog rules:

- Only promise a named badge when its `Achievement.slug`, criteria, target, and server event are live.
- `criteria.n` and `UserAchievement.target` are positive for count-based badges.
- Progress never exceeds the target in authored or migrated rows.
- Points are non-negative and proportional across comparable tiers.
- Secret badges do not reveal the hidden action in locked copy.
- A destination-specific badge must have enough qualifying live places that a traveler can complete it without unsafe, paid-only, or private access.
- Editorial phrases such as "quest complete" may celebrate local completion, but must not imply that Insight points or a Passport badge were awarded.

### Identifier stability

- Never change a live `Tour.slug` to fix typography. Change only the display title.
- Never reuse a retired tour slug for a new route.
- Never change the meaning of a live interactive `CitySection.id`.
- Do not reorder a live tour in place when travelers may have saved progress. Publish a versioned tour and retire the old one deliberately.
- IDs are globally unique; slugs are unique within their model and stable across environments.

## 8. Data Invariants

These checks block publication.

### Referential integrity

- Every city-scoped row references an existing live `City.slug`.
- Every tour stop and linked city experience resolves to an existing live `Place.id` in the same destination.
- Every dive resolves to exactly one live place.
- Every stored audio path resolves to a readable object.
- No live tour has zero stops or an unresolved stop.

### Required content

- Required strings are trimmed, non-empty, and free of placeholder copy.
- Titles are unique within a destination and surface unless repetition is editorially necessary.
- Every place has a Layer-1 hook.
- Every story has a narrative, coordinate, source, license/provenance value, and at least one useful tag.
- Every tour has a blurb, duration, distance, emoji, and stop notes at every stop.
- Every tour stop has a dive narrative.
- Every dive has a narrative, three or more timeline events, and provenance.
- Every city section has a deterministic `sort`; sort values are unique within each city and kind.

### Accuracy and provenance

- Layer-1 hooks use only content safe for unattributed display under the project's CC0, public-domain, or contributor-license policy.
- Quotes preserve exact wording only when the source and rights permit it; otherwise paraphrase and do not use quotation marks.
- Dates, superlatives, records, contested histories, and current practical claims have a source that directly supports them.
- Current names, opening requirements, route access, and business-dependent advice are rechecked within 30 days of publication.
- Cultural practices are described by reliable local or community sources, not generalized from national stereotypes.
- Indigenous names, sacred traditions, conflict, displacement, and living communities receive context and appropriate naming.
- A single source does not support an entire multi-claim dossier unless it directly substantiates every claim.
- AI-assisted drafts receive human fact-checking against the cited source before becoming live data.

### Consistency

- Place names, diacritics, people, dates, and transliterations match across hooks, stories, dives, tours, and sections.
- `year_label` and timeline wording do not contradict numeric year fields.
- Tour duration, distance, stop count, and blurb agree.
- Studio narration and narrative text agree in facts, names, and ending.
- Tags use lowercase normalized slugs and do not differ only by punctuation or pluralization.
- The same generic paragraph is not reused across destinations.

### Safety and dignity

- Content does not direct a traveler onto private property, into restricted areas, or into unsafe traffic positions.
- Living people are not assigned private motives or sensitive personal details without reliable public sourcing and relevance.
- Tragedy is not framed as a scavenger hunt, joke, or collectible spectacle.
- Folklore and mysteries are labeled honestly; uncertainty is part of the story, not hidden from it.
- Recommendations do not imply guaranteed discounts, availability, safety, or access.

## 9. End-to-End Editorial QA

Every content wave passes these gates in order.

### Gate 1: Inventory

- Produce a per-destination count against the coverage table.
- List missing required kinds, alternatives, story arcs, dives, audio, and interactive entries.
- Detect duplicate IDs, slugs, titles, coordinates, and text.

### Gate 2: Structural validation

- Decode representative API responses through the current Swift models.
- Validate join keys, stop sequences, JSON object/array shapes, coordinate ranges, sorts, and audio pairs.
- Confirm every tour stop, experience link, dive, and audio object resolves.

### Gate 3: Editorial and source review

- Check every claim against its cited source.
- Review voice, specificity, dignity, pronunciation, translation, and uncertainty.
- Read each destination as a whole to remove repetition and fill missing perspectives.

### Gate 4: Route and field review

- Inspect every route in walking directions and current imagery.
- Verify distance, estimated time, crossings, access, paid dependencies, closure risk, and each stop's viewing position.
- Complete every field prompt from the intended public location.
- Physically audit routes before making accessibility claims.

### Gate 5: App experience review

- Complete the plan-to-memory loop on a compact iPhone and an iPad.
- Test Dynamic Type, VoiceOver reading order, Reduce Motion, dark city themes, and long translated strings.
- Clear filters, apply each interest lens, inspect night mode, and test scanner story density.
- Resume a tour, finish it, restart it, and verify guest/account progress separation.
- Complete, reset, and repeat interactive city-section entries.

### Gate 6: Audio and offline review

- Play every new recording on a phone speaker and headphones.
- Test TTS fallback by removing network access or using a dive without studio audio.
- Download the destination, go offline, and open each core surface plus one full narrated tour.

### Gate 7: Release score

Score each destination out of 100:

| Area | Points |
| --- | ---: |
| Coverage and variety | 20 |
| Accuracy, provenance, and cultural care | 20 |
| Story and tour craft | 20 |
| Traveler utility and alternatives | 15 |
| Map, route, and safety quality | 10 |
| Accessibility and language quality | 10 |
| Progress, audio, and offline continuity | 5 |

A destination needs at least 90 points, no missing invariant, and no safety, attribution, translation, or broken-reference defect to publish. A content wave cannot average away a failed destination; every destination passes independently.

## 10. Definition of Done for a Content Wave

A content wave is complete only when:

- Every targeted live destination meets its assigned coverage floor.
- Every required story arc, tour role, city-section group, alternative, dive, and prompt is present.
- All references, sorts, coordinates, durations, distances, sources, licenses, media, and audio pairs validate.
- Every tour stop has a readable and narratable dive.
- Phrases and pronunciation guidance have fluent-speaker review.
- Route, accessibility, family, weather, and time claims have documented evidence.
- The end-to-end loop has been tested in the app, including offline and assistive settings.
- Progress identifiers are stable and no existing traveler state is silently repurposed.
- Achievement copy promises only events the backend currently records.
- The per-destination release score is 90 or higher with zero critical defects.

The standard is intentionally demanding. Lore should cover fewer destinations well rather than publish a large atlas of shallow pins. A village with twelve vivid, connected places and three excellent experiences is complete; a major city with forty disconnected cards is not.
