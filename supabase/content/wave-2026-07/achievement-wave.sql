-- Lore content wave 2026-07: earnable traveler progression.
--
-- `achievement.slug` is the catalog's primary identity; these stable slugs are
-- the deterministic IDs used by `user_achievement.achievement_slug`.
--
-- Earnability limits intentionally respected by this wave:
-- * Tour completion is device-local in TourProgressStore. The current tour UI
--   does not write `visit.source = 'tour'`, so no new tour badges are added.
-- * Planned-city pins are device-local in CityPlanningStore and are not visible
--   to `private.recompute_achievements_internal`.
-- * Phrase and culture opens have no per-user read table or evaluated criterion.
-- * Multi-region travel is evaluated through `continent_count`, but the live
--   catalog already contains every distinct target from 1 through 6.
--
-- The rows below only use criteria evaluated by the current achievement engine:
-- `visit_count`, `source_count`, `dive_read`, `note_count`, and `photo_count`.

begin;

-- Refuse to shadow another badge's human-facing name or exact criterion. This
-- still permits a clean rerun because a row may match its own stable slug.
do $validation$
declare
    collision text;
begin
    with wanted(slug, name, criteria) as (
        values
            ('story-sampler', 'Story Sampler', '{"type":"dive_read","n":3}'::jsonb),
            ('five-footprints', 'Five Footprints', '{"type":"visit_count","n":5}'::jsonb),
            ('map-reader', 'Map Reader', '{"type":"source_count","source":"map","n":10}'::jsonb),
            ('map-constellation', 'Map Constellation', '{"type":"source_count","source":"map","n":40}'::jsonb),
            ('travel-notebook', 'Travel Notebook', '{"type":"note_count","n":15}'::jsonb),
            ('travel-memoir', 'Travel Memoir', '{"type":"note_count","n":75}'::jsonb),
            ('postcard-set', 'Postcard Set', '{"type":"photo_count","n":15}'::jsonb),
            ('world-in-frames', 'World in Frames', '{"type":"photo_count","n":75}'::jsonb)
    )
    select format('%s conflicts with %s', wanted.slug, existing.slug)
    into collision
    from wanted
    join public.achievement existing
      on existing.slug <> wanted.slug
     and (
         lower(existing.name) = lower(wanted.name)
         or existing.criteria = wanted.criteria
     )
    limit 1;

    if collision is not null then
        raise exception 'achievement wave collision: %', collision;
    end if;
end
$validation$;

insert into public.achievement (
    slug,
    name,
    description,
    emoji,
    category,
    tier,
    criteria,
    points,
    secret,
    sort
)
values
    (
        'story-sampler',
        'Story Sampler',
        'Open deep-dive stories for 3 different places',
        '📖',
        'knowledge',
        'bronze',
        '{"type":"dive_read","n":3}'::jsonb,
        10,
        false,
        230
    ),
    (
        'five-footprints',
        'Five Footprints',
        'Log visits at 5 different places',
        '👣',
        'milestone',
        'bronze',
        '{"type":"visit_count","n":5}'::jsonb,
        15,
        false,
        231
    ),
    (
        'map-reader',
        'Map Reader',
        'Log visits at 10 different places from the living map',
        '🗺️',
        'special',
        'bronze',
        '{"type":"source_count","source":"map","n":10}'::jsonb,
        30,
        false,
        232
    ),
    (
        'travel-notebook',
        'Travel Notebook',
        'Write journal notes for 15 different places',
        '📓',
        'knowledge',
        'silver',
        '{"type":"note_count","n":15}'::jsonb,
        85,
        false,
        233
    ),
    (
        'postcard-set',
        'Postcard Set',
        'Add a journal photo at 15 different places',
        '🎞️',
        'special',
        'silver',
        '{"type":"photo_count","n":15}'::jsonb,
        85,
        false,
        234
    ),
    (
        'map-constellation',
        'Map Constellation',
        'Log visits at 40 different places from the living map',
        '🌌',
        'special',
        'gold',
        '{"type":"source_count","source":"map","n":40}'::jsonb,
        100,
        false,
        235
    ),
    (
        'travel-memoir',
        'Travel Memoir',
        'Write journal notes for 75 different places',
        '✍️',
        'knowledge',
        'legend',
        '{"type":"note_count","n":75}'::jsonb,
        500,
        false,
        236
    ),
    (
        'world-in-frames',
        'World in Frames',
        'Add a journal photo at 75 different places',
        '📷',
        'special',
        'legend',
        '{"type":"photo_count","n":75}'::jsonb,
        450,
        false,
        237
    )
on conflict (slug) do update set
    name = excluded.name,
    description = excluded.description,
    emoji = excluded.emoji,
    category = excluded.category,
    tier = excluded.tier,
    criteria = excluded.criteria,
    points = excluded.points,
    secret = excluded.secret,
    sort = excluded.sort;

-- Fail the transaction if a future edit introduces an unsupported criterion,
-- a non-positive target, or a map milestone that is not tied to map visits.
do $verification$
declare
    invalid_row text;
begin
    select achievement.slug
    into invalid_row
    from public.achievement achievement
    where achievement.slug in (
        'story-sampler',
        'five-footprints',
        'map-reader',
        'map-constellation',
        'travel-notebook',
        'travel-memoir',
        'postcard-set',
        'world-in-frames'
    )
      and (
          achievement.criteria->>'type' not in (
              'visit_count', 'source_count', 'dive_read', 'note_count', 'photo_count'
          )
          or coalesce((achievement.criteria->>'n')::integer, 0) <= 0
          or (
              achievement.criteria->>'type' = 'source_count'
              and achievement.criteria->>'source' <> 'map'
          )
      )
    limit 1;

    if invalid_row is not null then
        raise exception 'achievement wave contains an unevaluable row: %', invalid_row;
    end if;

    if (
        select count(*)
        from public.achievement
        where slug in (
            'story-sampler',
            'five-footprints',
            'map-reader',
            'map-constellation',
            'travel-notebook',
            'travel-memoir',
            'postcard-set',
            'world-in-frames'
        )
    ) <> 8 then
        raise exception 'achievement wave did not settle all 8 rows';
    end if;
end
$verification$;

commit;
