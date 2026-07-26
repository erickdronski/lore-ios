-- Lore content wave 2026-07: city-specific interactive experiences.
--
-- This script is intentionally derived only from existing curated Lore rows.
-- It fills missing interaction kinds without inventing places or claims and is
-- idempotent through city_section_city_kind_title_idx.

begin;

with ranked_tours as (
    select
        t.*,
        row_number() over (
            partition by t.city
            order by t.duration_min nulls last, t.title
        ) as city_rank
    from public.tour t
    join public.city c on c.slug = t.city and c.status = 'live'
),
tour_routes as (
    select
        t.city,
        t.slug,
        t.title,
        t.duration_min,
        t.distance_km,
        (array_agg(ts.place_id order by ts.seq))[1] as starting_place_id,
        array_agg(p.name order by ts.seq) filter (where p.name is not null) as stops
    from ranked_tours t
    join public.tour_stop ts on ts.tour_id = t.id
    join public.place p on p.id = ts.place_id and p.deleted_at is null
    where t.city_rank = 1
    group by t.city, t.slug, t.title, t.duration_min, t.distance_km
),
experience_rows as (
    select
        gen_random_uuid() as id,
        r.city,
        'experience'::text as kind,
        'Try: ' || r.title as title,
        concat(
            'Follow this ', coalesce(r.duration_min::text || '-minute ', ''),
            'route from ', r.stops[1],
            case when cardinality(r.stops) >= 2 then ' to ' || r.stops[2] else '' end,
            case when cardinality(r.stops) >= 3 then ' and ' || r.stops[3] else '' end,
            '. Treat each stop as a chapter: notice what changed, what survived, ',
            'and whose story the street tells.'
        ) as body,
        concat_ws(
            ' | ',
            'Lore route',
            case when r.duration_min is not null then r.duration_min::text || ' min' end,
            case when r.distance_km is not null then trim(to_char(r.distance_km, 'FM9990.0')) || ' km' end
        ) as attribution,
        '🧭'::text as emoji,
        r.starting_place_id as place_id,
        jsonb_build_object('tour_slug', r.slug, 'wave', '2026-07') as links,
        jsonb_build_object('derived_from', 'tour', 'tour_slug', r.slug) as meta,
        'editorial:derived-from-tour/' || r.slug as source,
        'cc0'::text as license,
        210 as sort,
        'reference_only'::text as provenance_state
    from tour_routes r
    where cardinality(r.stops) >= 2
      and not exists (
          select 1 from public.city_section x
          where x.city = r.city and x.kind = 'experience'
      )
)
insert into public.city_section (
    id, city, kind, title, body, attribution, emoji, place_id, links, meta,
    source, license, sort, provenance_state
)
select
    id, city, kind, title, body, attribution, emoji, place_id, links, meta,
    source, license, sort, provenance_state
from experience_rows
on conflict (city, kind, title) do update set
    body = excluded.body,
    attribution = excluded.attribution,
    emoji = excluded.emoji,
    place_id = excluded.place_id,
    links = excluded.links,
    meta = excluded.meta,
    source = excluded.source,
    license = excluded.license,
    sort = excluded.sort,
    provenance_state = excluded.provenance_state;

with first_soundmark as (
    select distinct on (s.city)
        s.city, s.title, s.body, s.source, s.place_id
    from public.city_section s
    join public.city c on c.slug = s.city and c.status = 'live'
    where s.kind = 'soundmark'
    order by s.city, s.sort nulls last, s.title
),
listen_rows as (
    select
        gen_random_uuid() as id,
        s.city,
        'listen'::text as kind,
        'Listen for: ' || s.title as title,
        concat(
            'Pause in a safe public spot and put the phone down for 30 seconds. ',
            s.body,
            ' Separate the closest sound from the farthest one, then notice what ',
            'the city is doing between them.'
        ) as body,
        'Lore sound quest'::text as attribution,
        '👂'::text as emoji,
        s.place_id,
        jsonb_build_object('wave', '2026-07') as links,
        jsonb_build_object('derived_from', 'soundmark', 'soundmark_title', s.title) as meta,
        coalesce(s.source, 'editorial:derived-from-soundmark') as source,
        'cc0'::text as license,
        220 as sort,
        'reference_only'::text as provenance_state
    from first_soundmark s
    where not exists (
        select 1 from public.city_section x
        where x.city = s.city and x.kind = 'listen'
    )
)
insert into public.city_section (
    id, city, kind, title, body, attribution, emoji, place_id, links, meta,
    source, license, sort, provenance_state
)
select
    id, city, kind, title, body, attribution, emoji, place_id, links, meta,
    source, license, sort, provenance_state
from listen_rows
on conflict (city, kind, title) do update set
    body = excluded.body,
    attribution = excluded.attribution,
    emoji = excluded.emoji,
    place_id = excluded.place_id,
    links = excluded.links,
    meta = excluded.meta,
    source = excluded.source,
    license = excluded.license,
    sort = excluded.sort,
    provenance_state = excluded.provenance_state;

with first_material as (
    select distinct on (s.city)
        s.city, s.title, s.body, s.source, s.place_id
    from public.city_section s
    join public.city c on c.slug = s.city and c.status = 'live'
    where s.kind = 'material'
    order by s.city, s.sort nulls last, s.title
),
field_note_rows as (
    select
        gen_random_uuid() as id,
        m.city,
        'field_note'::text as kind,
        'Trace: ' || m.title as title,
        concat(
            m.body,
            ' Find one example from a public, accessible position. Notice its ',
            'color, texture, age, and repair marks, then ask what it reveals ',
            'about how this city was built.'
        ) as body,
        'Lore explorer prompt'::text as attribution,
        '🔎'::text as emoji,
        m.place_id,
        jsonb_build_object('wave', '2026-07') as links,
        jsonb_build_object('derived_from', 'material', 'material_title', m.title) as meta,
        coalesce(m.source, 'editorial:derived-from-material') as source,
        'cc0'::text as license,
        230 as sort,
        'reference_only'::text as provenance_state
    from first_material m
    where not exists (
        select 1 from public.city_section x
        where x.city = m.city and x.kind = 'field_note'
    )
)
insert into public.city_section (
    id, city, kind, title, body, attribution, emoji, place_id, links, meta,
    source, license, sort, provenance_state
)
select
    id, city, kind, title, body, attribution, emoji, place_id, links, meta,
    source, license, sort, provenance_state
from field_note_rows
on conflict (city, kind, title) do update set
    body = excluded.body,
    attribution = excluded.attribution,
    emoji = excluded.emoji,
    place_id = excluded.place_id,
    links = excluded.links,
    meta = excluded.meta,
    source = excluded.source,
    license = excluded.license,
    sort = excluded.sort,
    provenance_state = excluded.provenance_state;

commit;
