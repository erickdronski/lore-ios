-- Lore content wave 2026-07: fill scanner hooks from existing safe-license dives.
--
-- Layer-1 hooks are spoken without attribution, so attribution-required dives
-- are deliberately excluded. Existing hooks are never overwritten.

begin;

with hook_candidates as (
    select
        p.id,
        d.license as hook_license,
        case
            when d.narrative ~ '^.{1,220}?[.!?](\s|$)'
                then (regexp_match(d.narrative, '^(.{1,220}?[.!?])(?:\s|$)'))[1]
            else left(trim(d.narrative), 220)
        end as hook
    from public.place p
    join public.city c on c.slug = p.city and c.status = 'live'
    join public.dive d on d.place_id = p.id
    where p.deleted_at is null
      and coalesce(nullif(trim(p.layer1 ->> 'hook'), ''), '') = ''
      and nullif(trim(d.narrative), '') is not null
      and d.license::text in ('cc0', 'public_domain', 'user_cla')
)
update public.place p
set
    layer1 = jsonb_set(
        coalesce(p.layer1, '{}'::jsonb),
        '{hook}',
        to_jsonb(h.hook),
        true
    ),
    layer1_licenses = case
        when p.layer1_licenses is null then array[h.hook_license]::license_kind[]
        when not (h.hook_license = any(p.layer1_licenses))
            then array_append(p.layer1_licenses, h.hook_license)
        else p.layer1_licenses
    end,
    layer1_updated_at = now(),
    updated_at = now()
from hook_candidates h
where p.id = h.id;

commit;
