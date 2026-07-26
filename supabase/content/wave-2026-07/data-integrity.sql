-- Lore content wave 2026-07: small roster and Passport integrity repairs.

begin;

update public.city
set country = 'GB'
where slug = 'london' and country = 'UK';

insert into public.achievement (
    slug, name, description, emoji, category, tier, criteria, points, secret, sort
)
values (
    'lagos-lagoon-navigator',
    'Lagos Lagoon Navigator',
    'Visit 80% of Lagos''s places',
    '🌊',
    'city',
    'gold',
    '{"type":"city_complete","city":"lagos","pct":80}'::jsonb,
    150,
    false,
    20
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

commit;
