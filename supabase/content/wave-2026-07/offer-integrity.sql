-- Lore offer integrity gate
-- Audited against production on 2026-07-26 02:07 UTC. This migration adds no
-- offers and changes no deal, price, discount, URL, validity, or source row.
-- It only makes the existing source approval flag part of feed eligibility.
--
-- Production snapshot before this change:
--   * 603 deal rows: 599 active, 583 visible through active sources.
--   * 16 deal sources: 15 active, but only `museum` is approved.
--   * 14 active sources were unapproved; 11 of them contributed 520
--     otherwise-current deals to the app feeds because the views checked
--     `active` but not `approved`.
--   * Current feeds exposed 230 city rows and 3,999 place-expanded rows.
--   * Approval-aware eligibility retains 1 city row and 63 place-expanded
--     rows (62 distinct place deals) from the approved source.
--
-- Integrity checks that passed:
--   * 0 expired-but-active deals.
--   * 0 validity timestamps at or before fetched_at; 0 future fetched_at rows.
--   * 0 blank required fields, non-HTTPS/unsafe URLs, invalid ratings, unknown
--     match kinds, non-live deal cities, place/city mismatches, deleted-place
--     matches, or feed rows the Swift Deal decoder cannot decode.
--   * 0 exact or normalized logical duplicates. Forty-three URLs are reused
--     across 167 rows for legitimate country-level eSIM/car-search pages or a
--     shared official free-day page. Four same-city URL pairs resolve to three
--     inactive superseded Airalo rows and two distinct Dublin attractions.
--   * There is no coupon, redemption-code, or promo-code column in the deal
--     schema or app model. Redemption is URL-only; all 603 URLs passed the
--     HTTPS, host, whitespace/control-character, user-info, localhost, and
--     private-network checks.
--   * `events` is the only source category outside the app's named category
--     set. Its source is unapproved and has 0 deal rows; if received, it would
--     still decode safely as the app's `local` fallback.
--
-- Verified-offer limitation:
-- Only 26 of 141 live cities currently have an offer from an active, approved
-- source. Lore must leave the other 115 cities empty rather than fabricate
-- commercial inventory:
--   Accra, Addis Ababa, Cairo, Cape Town, Dakar, Johannesburg, Lagos,
--   Marrakech, Nairobi, Stone Town, Tunis, Abu Dhabi, Agra, Bangkok, Beijing,
--   Bengaluru, Busan, Chengdu, Delhi, Doha, Dubai, Guangzhou, Hangzhou, Hanoi,
--   Hong Kong, Hyderabad, Istanbul, Jaipur, Jakarta, Kuala Lumpur, Kyoto,
--   Mecca, Mumbai, Osaka, Riyadh, Seoul, Shanghai, Shenzhen, Singapore,
--   Taipei, Tokyo, Amsterdam, Athens, Birmingham, Bruges, Brussels, Bucharest,
--   Budapest, Cologne, Copenhagen, Dusseldorf, Florence, Frankfurt, Hamburg,
--   Helsinki, Krakow, Lisbon, Lyon, Manchester, Milan, Moscow, Munich, Naples,
--   Oslo, Porto, Reykjavik, Rotterdam, Seville, Stockholm, Stuttgart,
--   Valencia, Venice, Vienna, Warsaw, Zurich, Asheville, Baltimore, Calgary,
--   Charleston, Dallas, Jersey City, Key West, Mexico City, Montreal,
--   Mount Laurel, Newport, Orlando, Ottawa, Quebec City, Salem, San Diego,
--   San Jose, Savannah, Seattle, Vancouver, Adelaide, Auckland, Brisbane,
--   Canberra, Christchurch, Darwin, Gold Coast, Hobart, Melbourne, Perth,
--   Wellington, Bogota, Buenos Aires, Cartagena, Cusco, Lima, Medellin,
--   Rio de Janeiro, Santiago, and Sao Paulo.

begin;

create or replace view public.city_deal_feed
with (security_invoker = true, security_barrier = true)
as
select
    d.id,
    d.source,
    s.category,
    d.city,
    d.title,
    d.merchant,
    d.url,
    d.price_original,
    d.price_deal,
    d.discount_label,
    d.rating,
    d.rating_count,
    d.match_kind,
    d.match_note,
    d.fetched_at,
    (((100 - s.priority) * 5)
      + case when coalesce(d.discount_label, '') <> '' then 0 else 3 end
      + case when coalesce(d.rating, 0) >= 4.5 then 0 else 1 end) as rank
from public.deal d
join public.deal_source s
  on s.key = d.source
 and s.active
 and s.approved
where d.active
  and d.match_kind = 'city'
  and (d.valid_through is null or d.valid_through > now());

create or replace view public.place_deal_feed
with (security_invoker = true, security_barrier = true)
as
select
    dp.place_id,
    d.id,
    d.source,
    s.category,
    d.city,
    d.title,
    d.merchant,
    d.url,
    d.price_original,
    d.price_deal,
    d.discount_label,
    d.rating,
    d.rating_count,
    d.match_kind,
    d.match_note,
    d.fetched_at,
    ((case d.match_kind
        when 'included' then 0
        when 'nearby' then 1
        else 2
      end * 1000)
      + ((100 - s.priority) * 5)
      + case when coalesce(d.discount_label, '') <> '' then 0 else 3 end
      + case when coalesce(d.rating, 0) >= 4.5 then 0 else 1 end) as rank
from public.deal d
join public.deal_place dp on dp.deal_id = d.id
join public.deal_source s
  on s.key = d.source
 and s.active
 and s.approved
where d.active
  and (d.valid_through is null or d.valid_through > now());

do $offer_integrity$
declare
    expected_city_rows bigint;
    expected_place_rows bigint;
    actual_city_rows bigint;
    actual_place_rows bigint;
begin
    if exists (
        select 1
        from public.city_deal_feed f
        join public.deal_source s on s.key = f.source
        where not s.active or not s.approved
    ) or exists (
        select 1
        from public.place_deal_feed f
        join public.deal_source s on s.key = f.source
        where not s.active or not s.approved
    ) then
        raise exception 'Offer integrity failed: an inactive or unapproved source remains visible';
    end if;

    select count(*)
      into expected_city_rows
      from public.deal d
      join public.deal_source s
        on s.key = d.source and s.active and s.approved
     where d.active
       and d.match_kind = 'city'
       and (d.valid_through is null or d.valid_through > now());

    select count(*)
      into expected_place_rows
      from public.deal d
      join public.deal_place dp on dp.deal_id = d.id
      join public.deal_source s
        on s.key = d.source and s.active and s.approved
     where d.active
       and (d.valid_through is null or d.valid_through > now());

    select count(*) into actual_city_rows from public.city_deal_feed;
    select count(*) into actual_place_rows from public.place_deal_feed;

    if actual_city_rows <> expected_city_rows
       or actual_place_rows <> expected_place_rows then
        raise exception
          'Offer integrity failed: feed counts do not match eligible inventory (city %/%, place %/%)',
          actual_city_rows, expected_city_rows,
          actual_place_rows, expected_place_rows;
    end if;

    if not coalesce((
        select c.reloptions @> array['security_invoker=true', 'security_barrier=true']
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relname = 'city_deal_feed'
    ), false) or not coalesce((
        select c.reloptions @> array['security_invoker=true', 'security_barrier=true']
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relname = 'place_deal_feed'
    ), false) then
        raise exception 'Offer integrity failed: feed view security options changed';
    end if;
end
$offer_integrity$;

commit;
