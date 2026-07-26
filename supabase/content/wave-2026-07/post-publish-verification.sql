-- Read-only release evidence for Lore's 2026-07 content wave.
with live_cities as (
    select slug
    from public.city
    where status = 'live'
), live_places as (
    select p.id, p.city
    from public.place p
    join live_cities c on c.slug = p.city
    where p.deleted_at is null
), section_coverage as (
    select
        c.slug,
        count(*) filter (where s.kind = 'phrase') as phrases,
        count(*) filter (where s.kind = 'drink') as drinks,
        count(*) filter (where s.kind = 'etiquette') as etiquette,
        count(*) filter (where s.kind = 'market') as markets,
        count(*) filter (where s.kind = 'experience') as experiences,
        count(*) filter (where s.kind = 'listen') as listens,
        count(*) filter (where s.kind = 'field_note') as field_notes
    from live_cities c
    left join public.city_section s on s.city = c.slug
    group by c.slug
), tour_coverage as (
    select t.id, count(ts.*) as stop_count
    from public.tour t
    join live_cities c on c.slug = t.city
    left join public.tour_stop ts on ts.tour_id = t.id
    group by t.id
), visible_unapproved as (
    select f.id
    from public.city_deal_feed f
    join public.deal_source s on s.key = f.source
    where not s.active or not s.approved
    union all
    select f.id
    from public.place_deal_feed f
    join public.deal_source s on s.key = f.source
    where not s.active or not s.approved
)
select jsonb_build_object(
    'live_cities', (select count(*) from live_cities),
    'active_live_places', (select count(*) from live_places),
    'places_without_dive', (
        select count(*)
        from live_places p
        left join public.dive d on d.place_id = p.id
        where d.place_id is null
    ),
    'places_without_hook', (
        select count(*)
        from live_places p
        join public.place place_row on place_row.id = p.id
        where nullif(btrim(place_row.layer1 ->> 'hook'), '') is null
    ),
    'cities_below_traveler_kit_floor', (
        select count(*)
        from section_coverage
        where phrases < 6 or drinks < 2 or etiquette < 4 or markets < 1
    ),
    'cities_missing_interactive_kinds', (
        select count(*)
        from section_coverage
        where experiences < 1 or listens < 1 or field_notes < 1
    ),
    'blank_live_tour_notes', (
        select count(*)
        from public.tour_stop ts
        join public.tour t on t.id = ts.tour_id
        join live_cities c on c.slug = t.city
        where nullif(btrim(ts.note), '') is null
    ),
    'live_tours_under_four_stops', (
        select count(*) from tour_coverage where stop_count < 4
    ),
    'wave_achievements', (
        select count(*)
        from public.achievement
        where slug = any(array[
            'story-sampler', 'five-footprints', 'map-reader',
            'map-constellation', 'travel-notebook', 'travel-memoir',
            'postcard-set', 'world-in-frames'
        ])
    ),
    'unapproved_visible_offers', (select count(*) from visible_unapproved),
    'visible_city_offers', (select count(*) from public.city_deal_feed),
    'visible_place_offers', (select count(*) from public.place_deal_feed)
) as release_evidence;
