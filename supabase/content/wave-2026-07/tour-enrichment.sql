begin;

-- Tour-stop notes have no source/attribution columns, so only text from dives
-- whose licenses permit reuse is copied here. Existing authored notes are never
-- changed. Timeline details are preferred; narrative text is the fallback.
with grounded_notes as (
    select
        ts.tour_id,
        ts.seq,
        regexp_replace(
            coalesce(
                nullif(btrim(d.timeline -> 0 ->> 'detail'), ''),
                nullif(btrim(d.narrative), '')
            ),
            '[[:space:]]+',
            ' ',
            'g'
        ) as grounded_text
    from public.tour_stop ts
    join public.tour t
      on t.id = ts.tour_id
    join public.city c
      on c.slug = t.city
     and c.status = 'live'
    join public.place p
      on p.id = ts.place_id
     and p.city = t.city
     and p.deleted_at is null
    join public.dive d
      on d.place_id = p.id
     and d.license in ('cc0', 'public_domain', 'user_cla', 'partner')
    where nullif(btrim(ts.note), '') is null
), prepared_notes as (
    select
        tour_id,
        seq,
        case
            when char_length(grounded_text) <= 280 then grounded_text
            else left(grounded_text, 277) || '...'
        end as note
    from grounded_notes
    where nullif(btrim(grounded_text), '') is not null
)
update public.tour_stop ts
set note = pn.note
from prepared_notes pn
where ts.tour_id = pn.tour_id
  and ts.seq = pn.seq
  and nullif(btrim(ts.note), '') is null;

-- Persist the deterministic choices while the existing sequences are shifted.
-- A candidate must be active, narrated, permissively licensed, in the same live
-- city, within 800 metres of the route, and strongly related to the route: it
-- either shares tags with at least two existing stops or shares at least two
-- non-generic editorial tags. This deliberately leaves weak matches unresolved.
create temporary table lore_tour_additions (
    tour_id uuid primary key,
    place_id uuid not null,
    insert_after integer not null,
    note text not null
) on commit drop;

with short_tours as (
    select
        t.id as tour_id,
        t.city,
        count(ts.*)::integer as stop_count
    from public.tour t
    join public.city c
      on c.slug = t.city
     and c.status = 'live'
    join public.tour_stop ts
      on ts.tour_id = t.id
    group by t.id
    having count(ts.*) = 3
), routes as (
    select
        st.tour_id,
        st.city,
        st.stop_count,
        st_makeline(p.geom::geometry order by ts.seq)::geography as path
    from short_tours st
    join public.tour_stop ts
      on ts.tour_id = st.tour_id
    join public.place p
      on p.id = ts.place_id
    group by st.tour_id, st.city, st.stop_count
), eligible_candidates as (
    select
        r.tour_id,
        r.stop_count,
        p.id as place_id,
        p.slug as place_slug,
        p.geom as candidate_geom,
        d.narrative,
        d.timeline,
        st_distance(p.geom, r.path) as route_metres,
        (
            select count(*)::integer
            from public.tour_stop existing_stop
            join public.place existing_place
              on existing_place.id = existing_stop.place_id
            where existing_stop.tour_id = r.tour_id
              and existing_place.tags && p.tags
        ) as matched_stops,
        cardinality(array(
            select distinct candidate_tag
            from unnest(p.tags) as candidate_tag
            where candidate_tag <> all(array[
                'architecture', 'beaux-arts', 'building', 'film-famous',
                'founding-era', 'gilded-age', 'heritage', 'historic',
                'landmark', 'modernist', 'museum', 'public-art',
                'record-holder', 'survivor'
            ]::text[])
              and exists (
                  select 1
                  from public.tour_stop existing_stop
                  join public.place existing_place
                    on existing_place.id = existing_stop.place_id
                  where existing_stop.tour_id = r.tour_id
                    and candidate_tag = any(existing_place.tags)
              )
        )) as signal_tags,
        cardinality(array(
            select distinct candidate_tag
            from unnest(p.tags) as candidate_tag
            where exists (
                select 1
                from public.tour_stop existing_stop
                join public.place existing_place
                  on existing_place.id = existing_stop.place_id
                where existing_stop.tour_id = r.tour_id
                  and candidate_tag = any(existing_place.tags)
            )
        )) as shared_tags
    from routes r
    join public.place p
      on p.city = r.city
     and p.deleted_at is null
    join public.dive d
      on d.place_id = p.id
     and d.license in ('cc0', 'public_domain', 'user_cla', 'partner')
     and nullif(btrim(d.narrative), '') is not null
    where st_dwithin(p.geom, r.path, 800)
      and not exists (
          select 1
          from public.tour_stop existing_stop
          where existing_stop.tour_id = r.tour_id
            and existing_stop.place_id = p.id
      )
), ranked_candidates as (
    select
        ec.*,
        row_number() over (
            partition by ec.tour_id
            order by
                ec.signal_tags desc,
                ec.matched_stops desc,
                ec.shared_tags desc,
                ec.route_metres,
                ec.place_slug,
                ec.place_id
        ) as candidate_rank
    from eligible_candidates ec
    where ec.matched_stops >= 2
       or ec.signal_tags >= 2
), chosen_candidates as (
    select *
    from ranked_candidates
    where candidate_rank = 1
), insertion_slots as (
    select
        cc.*,
        slot.insert_after,
        case
            when previous_place.geom is null then
                st_distance(cc.candidate_geom, next_place.geom)
            when next_place.geom is null then
                st_distance(previous_place.geom, cc.candidate_geom)
            else
                st_distance(previous_place.geom, cc.candidate_geom)
                + st_distance(cc.candidate_geom, next_place.geom)
                - st_distance(previous_place.geom, next_place.geom)
        end as insertion_cost
    from chosen_candidates cc
    cross join lateral generate_series(0, cc.stop_count) as slot(insert_after)
    left join public.tour_stop previous_stop
      on previous_stop.tour_id = cc.tour_id
     and previous_stop.seq = slot.insert_after
    left join public.place previous_place
      on previous_place.id = previous_stop.place_id
    left join public.tour_stop next_stop
      on next_stop.tour_id = cc.tour_id
     and next_stop.seq = slot.insert_after + 1
    left join public.place next_place
      on next_place.id = next_stop.place_id
), ranked_slots as (
    select
        insertion_slots.*,
        row_number() over (
            partition by tour_id
            order by insertion_cost, insert_after
        ) as slot_rank
    from insertion_slots
), prepared_additions as (
    select
        tour_id,
        place_id,
        insert_after,
        regexp_replace(
            coalesce(
                nullif(btrim(timeline -> 0 ->> 'detail'), ''),
                btrim(narrative)
            ),
            '[[:space:]]+',
            ' ',
            'g'
        ) as grounded_text
    from ranked_slots
    where slot_rank = 1
)
insert into lore_tour_additions (tour_id, place_id, insert_after, note)
select
    tour_id,
    place_id,
    insert_after,
    case
        when char_length(grounded_text) <= 280 then grounded_text
        else left(grounded_text, 277) || '...'
    end
from prepared_additions
where nullif(btrim(grounded_text), '') is not null;

-- Move current sequence values out of the primary-key range, then restore the
-- original order with one deterministic gap at the selected insertion point.
update public.tour_stop ts
set seq = ts.seq + 100
from lore_tour_additions addition
where ts.tour_id = addition.tour_id;

update public.tour_stop ts
set seq = (ts.seq - 100)
    + case when (ts.seq - 100) > addition.insert_after then 1 else 0 end
from lore_tour_additions addition
where ts.tour_id = addition.tour_id
  and ts.seq > 100;

insert into public.tour_stop (tour_id, seq, place_id, note)
select tour_id, insert_after + 1, place_id, note
from lore_tour_additions
on conflict (tour_id, seq) do nothing;

-- Fail closed if the live data changed between authoring and application.
do $$
begin
    if exists (
        select 1
        from public.tour_stop ts
        join public.tour t on t.id = ts.tour_id
        join public.city c on c.slug = t.city and c.status = 'live'
        where nullif(btrim(ts.note), '') is null
    ) then
        raise exception 'Tour enrichment left one or more live stop notes blank';
    end if;

    if exists (
        select 1
        from lore_tour_additions addition
        join public.tour t on t.id = addition.tour_id
        join public.place p on p.id = addition.place_id
        left join public.dive d on d.place_id = p.id
        where p.city <> t.city
           or p.deleted_at is not null
           or d.place_id is null
           or d.license not in ('cc0', 'public_domain', 'user_cla', 'partner')
           or nullif(btrim(addition.note), '') is null
    ) then
        raise exception 'Tour enrichment selected an unsafe stop';
    end if;

    if exists (
        select 1
        from lore_tour_additions addition
        left join lateral (
            select min(seq) as min_seq, max(seq) as max_seq, count(*) as stop_count
            from public.tour_stop ts
            where ts.tour_id = addition.tour_id
        ) counts on true
        where counts.min_seq <> 1
           or counts.max_seq <> counts.stop_count
           or counts.stop_count <> 4
    ) then
        raise exception 'Tour enrichment produced a non-contiguous route';
    end if;
end
$$;

commit;
