-- Lore content wave 2026-07: close thin culture and city-fact coverage gaps.
--
-- The production schema does not expose provenance_state on either target table,
-- and city_fact has no license column. Culture rows are released as CC0; every
-- row retains a direct institutional source for editorial review.

begin;

with incoming (
    row_key, city, kind, headline, body, attribution, emoji, year, source, sort
) as (
    values
        (
            'baltimore-frederick-douglass',
            'baltimore',
            'person',
            'Frederick Douglass',
            'Sent to Baltimore at eight while enslaved, Douglass taught himself to read and write in the city''s streets. He later worked as a ship caulker, met Anna Murray, and escaped by train from Baltimore in 1838 before becoming a leading abolitionist, writer, and statesman.',
            '1818 to 1895, abolitionist and writer',
            '📚',
            1818,
            'https://www.nps.gov/frdo/learn/historyculture/frederickdouglass.htm',
            70
        ),
        (
            'baltimore-thurgood-marshall',
            'baltimore',
            'person',
            'Thurgood Marshall',
            'Born in Baltimore, Marshall opened a law practice in the city before becoming the NAACP''s lead counsel. He helped win Brown v. Board of Education and, in 1967, became the first African American justice of the United States Supreme Court.',
            '1908 to 1993, lawyer and Supreme Court justice',
            '⚖️',
            1908,
            'https://www.nps.gov/people/thurgood-marshall.htm',
            80
        ),
        (
            'baltimore-ta-nehisi-coates',
            'baltimore',
            'person',
            'Ta-Nehisi Coates',
            'A journalist, essayist, and novelist whose Baltimore upbringing anchors The Beautiful Struggle. His work combines personal reflection with historical research to examine race, place, policy, and memory in American life.',
            'Baltimore-raised writer and journalist',
            '✍️',
            null,
            'https://www.macfound.org/fellows/class-of-2015/ta-nehisi-coates',
            90
        ),
        (
            'baltimore-h-l-mencken',
            'baltimore',
            'person',
            'H. L. Mencken',
            'Born in Baltimore in 1880, Mencken lived in his Hollins Street rowhouse for nearly all his life. He wrote many of the newspaper columns and books that made him a nationally influential, if often contentious, critic from its second-floor study.',
            '1880 to 1956, journalist and critic',
            '📰',
            1880,
            'https://explore.baltimoreheritage.org/items/show/12',
            100
        ),
        (
            'brussels-toots-thielemans',
            'brussels',
            'person',
            'Toots Thielemans',
            'Born above his parents'' cafe in Brussels'' Marolles district, Thielemans taught himself accordion, guitar, and harmonica. His 1962 composition Bluesette and his unmistakable harmonica sound made this lifelong Brussels ambassador a global jazz figure.',
            '1922 to 2016, jazz musician and composer',
            '🎵',
            1922,
            'https://www.visit.brussels/en/visitors/what-to-do/toots-thielemans',
            60
        ),
        (
            'brussels-victor-horta',
            'brussels',
            'person',
            'Victor Horta',
            'After moving to Brussels to study architecture, Horta helped give Art Nouveau its architectural language. His 1893 Tassel House is treated as a seminal work of the movement, and four of his Brussels townhouses are UNESCO World Heritage sites.',
            '1861 to 1947, architect and Art Nouveau pioneer',
            '📐',
            1861,
            'https://www.visit.brussels/en/visitors/agenda/brussels-capital-of-art-nouveau',
            70
        ),
        (
            'hobart-william-charles-piguenit',
            'hobart',
            'person',
            'William Charles Piguenit',
            'Born in Hobart Town in 1836, Piguenit began as a draftsman in Tasmania''s Survey Office. He left government work in 1872 to paint full time, later traveling on foot to portray the Gordon River, Arthur Range, Lake Pedder, and western highlands.',
            '1836 to 1914, landscape artist and lithographer',
            '🎨',
            1836,
            'https://adb.anu.edu.au/biography/piguenit-william-charles-4400',
            80
        ),
        (
            'manchester-anthony-burgess',
            'manchester',
            'person',
            'Anthony Burgess',
            'Born John Burgess Wilson in Harpurhey, Burgess was educated in Manchester and grew into a novelist, composer, poet, playwright, and broadcaster. The city''s music halls, pubs, libraries, and industrial character continued to shape his work after he left.',
            '1917 to 1993, writer and composer',
            '📖',
            1917,
            'https://www.anthonyburgess.org/about-anthony-burgess/',
            70
        ),
        (
            'savannah-susie-king-taylor',
            'savannah',
            'person',
            'Susie King Taylor',
            'Born into slavery near Savannah, Taylor learned in secret schools, then served as a teacher and nurse with the First South Carolina Volunteers. After the Civil War she opened a school for freed children in Savannah and later published a singular memoir of her wartime experience.',
            '1848 to 1912, teacher, nurse, and memoirist',
            '📚',
            1848,
            'https://www.nps.gov/people/susie-king-taylor.htm',
            70
        ),
        (
            'savannah-james-alan-mcpherson',
            'savannah',
            'person',
            'James Alan McPherson',
            'The Savannah-born essayist and short-story writer became the first African American recipient of the Pulitzer Prize for fiction, winning in 1978 for Elbow Room. As a child he sometimes skipped school to read at the city''s segregated Carnegie library branch.',
            '1943 to 2016, writer and critic',
            '🏆',
            1943,
            'https://www.georgiaencyclopedia.org/articles/arts-culture/james-alan-mcpherson-1943-2016/',
            80
        ),
        (
            'savannah-mary-musgrove',
            'savannah',
            'person',
            'Mary Musgrove',
            'Known as Coosaponakeesa and recognized within the Muscogee Wind Clan, Musgrove was a trader, interpreter, and diplomat. She used her command of Muscogee and English to advocate for Muscogee interests and mediate negotiations during Savannah''s colonial founding.',
            'ca. 1700 to ca. 1763, Muscogee cultural liaison and trader',
            '🗣️',
            null,
            'https://www.georgiaencyclopedia.org/articles/history-archaeology/mary-musgrove-ca-1700-ca-1763/',
            90
        ),
        (
            'savannah-tomochichi',
            'savannah',
            'person',
            'Tomochichi',
            'A leader of the Yamacraw community, Tomochichi settled with about two hundred people on the Savannah River bluff, a place believed to hold ancestral remains. He became a consequential diplomatic broker between Muscogee communities and British colonists while pressing for fair trade and education.',
            'ca. 1644 to 1739, Yamacraw leader and diplomat',
            '🤝',
            null,
            'https://www.georgiaencyclopedia.org/articles/history-archaeology/tomochichi-ca-1644-1739/',
            100
        )
), prepared as (
    select
        md5('lore:wave-2026-07:culture:' || row_key)::uuid as id,
        city,
        kind::public.culture_kind as kind,
        headline,
        body,
        attribution,
        emoji,
        year,
        jsonb_build_object('website', source) as links,
        source,
        'cc0'::public.license_kind as license,
        sort
    from incoming
)
insert into public.city_culture (
    id, city, kind, headline, body, attribution, emoji, year, links, source, license, sort
)
select
    p.id, p.city, p.kind, p.headline, p.body, p.attribution, p.emoji, p.year,
    p.links, p.source, p.license, p.sort
from prepared p
where not exists (
    select 1
    from public.city_culture existing
    where existing.city = p.city
      and lower(btrim(existing.headline)) = lower(btrim(p.headline))
      and existing.id <> p.id
)
on conflict (id) do update set
    city = excluded.city,
    kind = excluded.kind,
    headline = excluded.headline,
    body = excluded.body,
    attribution = excluded.attribution,
    emoji = excluded.emoji,
    year = excluded.year,
    links = excluded.links,
    source = excluded.source,
    license = excluded.license,
    sort = excluded.sort;

with incoming (
    row_key, city, category, fact, detail, stat_value, stat_label, emoji, source, sort
) as (
    values
        (
            'kyoto-gion-matsuri-origin',
            'kyoto',
            'fun-fact',
            'The Gion Matsuri traces its origin to a sacred rite held in 869 during a devastating epidemic.',
            'Tradition records that 66 halberds, one for each province of the time, were raised as prayers for relief; the observance became annual in 970 and developed into Kyoto''s month-long festival.',
            '869',
            'Traditional origin of Gion Matsuri',
            '🏮',
            'https://kyoto.travel/en/travel-inspiration/gion-matsuri-festival/',
            50
        ),
        (
            'kyoto-nintendo-hanafuda',
            'kyoto',
            'first',
            'Nintendo began in Kyoto in 1889 as a maker and seller of hanafuda playing cards.',
            'Founder Fusajiro Yamauchi started the business in Kyoto''s Shimogyo ward, almost a century before the company released the Famicom and became a global video-game name.',
            '1889',
            'Nintendo began making cards',
            '🎴',
            'https://www.nintendo.co.jp/corporate/en/history/index.html',
            60
        ),
        (
            'kyoto-seventeen-world-heritage-components',
            'kyoto',
            'stat',
            'Ancient Kyoto''s UNESCO World Heritage property has 17 component sites containing 198 buildings and 12 gardens.',
            'Most of those buildings and gardens date from the 10th through 17th centuries, together charting the development of Japanese architecture and garden design.',
            '17',
            'World Heritage components',
            '🏯',
            'https://whc.unesco.org/en/list/688/',
            70
        ),
        (
            'kyoto-philosophers-path',
            'kyoto',
            'quirk',
            'The Philosopher''s Path takes its name from Kyoto thinker Nishida Kitaro''s regular contemplative walks.',
            'After joining Kyoto Imperial University, Nishida began walking the canal-side route around 1910; the practice continued until his 1928 retirement and gave Tetsugaku no Michi its enduring identity.',
            '1910',
            'Nishida began the walking habit',
            '🚶',
            'https://kyoto.travel/en/travel-inspiration/the-philosophers-path-nishida-kitaros-contemplative-route/',
            80
        ),
        (
            'marrakech-medina-world-heritage',
            'marrakech',
            'stat',
            'UNESCO inscribed the 1,107-hectare Medina of Marrakesh on the World Heritage List in 1985.',
            'The inscription recognizes an urban ensemble of ramparts, gates, gardens, religious buildings, palaces, residences, and living public spaces.',
            '1985',
            'Medina inscribed by UNESCO',
            '🌍',
            'https://whc.unesco.org/en/list/331',
            50
        ),
        (
            'marrakech-almohad-capital',
            'marrakech',
            'claim-to-fame',
            'Marrakesh served as the Almohad capital from 1147 to 1269, with influence reaching across North Africa and into Andalusia.',
            'UNESCO identifies the city as a long-standing political, economic, and cultural center of the western Muslim world, visible in its kasbah, gates, gardens, and monumental architecture.',
            '1147-1269',
            'Almohad capital',
            '🕌',
            'https://whc.unesco.org/en/list/331',
            60
        ),
        (
            'marrakech-jardin-majorelle-rescue',
            'marrakech',
            'quirk',
            'The Jardin Majorelle began taking botanical form in 1922 and was rescued from a proposed hotel development in 1980.',
            'Painter Jacques Majorelle planted specimens gathered from around the world; Yves Saint Laurent and Pierre Berge later bought and restored the garden rather than see it demolished.',
            '1980',
            'Garden rescued from development',
            '🌵',
            'https://www.jardinmajorelle.com/en/thegarden/',
            70
        ),
        (
            'marrakech-bahia-palace',
            'marrakech',
            'stat',
            'Marrakesh''s Bahia Palace was built in two phases across eight hectares during the second half of the 19th century.',
            'Its first phase included a large riad, northern courtyard, and annexes; later work expanded the complex into one of the medina''s major historic residences.',
            '8 ha',
            'Historic palace complex',
            '🏛️',
            'https://e-services.minculture.gov.ma/en/tickets/palais-bahia',
            80
        ),
        (
            'mount-laurel-paulsdale',
            'mount-laurel',
            'claim-to-fame',
            'Paulsdale in Mount Laurel was the birthplace and childhood home of suffrage leader Alice Paul.',
            'Paul was born on the family''s Quaker farm in 1885. The property entered the National Register of Historic Places in 1989 and became a National Historic Landmark in 1991.',
            '1991',
            'Paulsdale became a National Historic Landmark',
            '🗳️',
            'https://www.nps.gov/articles/000/places-of-alice-paul.htm',
            20
        ),
        (
            'mount-laurel-evesham-friends',
            'mount-laurel',
            'fun-fact',
            'The Historic American Buildings Survey dates Mount Laurel''s Evesham Friends Meeting House to 1760.',
            'The Library of Congress record also documents a later 1798 building campaign, preserving measured drawings and photographs of the Quaker meeting house.',
            '1760',
            'Initial construction',
            '🏠',
            'https://www.loc.gov/pictures/item/nj0362/',
            30
        ),
        (
            'rio-carioca-landscapes-world-heritage',
            'rio-de-janeiro',
            'claim-to-fame',
            'Rio''s Carioca Landscapes between the Mountain and the Sea became a UNESCO World Heritage cultural landscape in 2012.',
            'The 7,248.78-hectare property recognizes the city''s exceptional relationship between dramatic terrain, designed landscapes, forests, parks, and urban life.',
            '2012',
            'Carioca landscape inscribed by UNESCO',
            '⛰️',
            'https://whc.unesco.org/en/list/1100',
            50
        ),
        (
            'rio-maracana-world-cup-record',
            'rio-de-janeiro',
            'record',
            'The 1950 World Cup decider at Rio''s Maracana still holds the tournament''s official attendance record.',
            'FIFA records 173,850 spectators for Uruguay''s 2-1 victory over Brazil, a match remembered in football history as the Maracanazo.',
            '173,850',
            'Official World Cup attendance record',
            '⚽',
            'https://www.fifa.com/en/tournaments/mens/worldcup/articles/uruguay-brazil-1950-maracanazo',
            60
        ),
        (
            'rio-royal-library',
            'rio-de-janeiro',
            'stat',
            'The Portuguese royal court brought roughly 60,000 books, maps, and engravings to Rio in 1808, seeding Brazil''s National Library.',
            'The Royal Library was formally established in 1810 and opened to the public in 1814, turning a court collection into a lasting civic institution.',
            '60,000',
            'Works carried across the Atlantic',
            '📚',
            'https://antigo.bn.gov.br/en/explore/curiosidades/personagem-frei-camilo-montserrat',
            70
        ),
        (
            'rio-sitio-burle-marx',
            'rio-de-janeiro',
            'claim-to-fame',
            'Sítio Roberto Burle Marx in western Rio is a UNESCO-listed landscape laboratory where gardens became living modernist artworks.',
            'Across more than forty years, landscape architect Roberto Burle Marx combined abstract artistic ideas with native tropical plants among mangroves and Atlantic forest.',
            '40+ years',
            'Burle Marx landscape experiments',
            '🌿',
            'https://whc.unesco.org/en/decisions/7946',
            80
        ),
        (
            'sao-paulo-masp-modern-museum',
            'sao-paulo',
            'claim-to-fame',
            'MASP, founded in São Paulo in 1947, was Brazil''s first modern museum.',
            'The museum moved to Avenida Paulista in 1968, into Lina Bo Bardi''s suspended glass-and-concrete building, now a landmark of 20th-century architecture and public life.',
            '1947',
            'MASP founded',
            '🖼️',
            'https://masp.org.br/en/about',
            20
        ),
        (
            'venice-first-jewish-ghetto',
            'venice',
            'first',
            'In 1516 the Venetian Senate forced the city''s Jewish residents into Europe''s first state-established ghetto.',
            'The gates of the segregated enclosure were locked from sunset to sunrise. The site remains essential for understanding both the endurance of Venetian Jewish life and the history of a word later used worldwide.',
            '1516',
            'Venetian ghetto established',
            '✡️',
            'https://jvenice.org/en/jews-venice-the-origins/',
            50
        ),
        (
            'venice-biennale-origin',
            'venice',
            'first',
            'Venice staged its first International Art Exhibition in 1895, beginning the institution now known as La Biennale.',
            'The idea began with an 1893 City Council resolution and became an international exhibition in the Giardini two years later.',
            '1895',
            'First international art exhibition',
            '🎨',
            'https://www.labiennale.org/en/history-biennale-arte',
            60
        ),
        (
            'venice-murano-glass-furnaces',
            'venice',
            'quirk',
            'In 1291 Venice ordered glass furnaces moved to Murano to reduce the fire risk they posed to the city.',
            'The safety decree concentrated furnaces and specialist knowledge on the lagoon island, helping shape Murano''s centuries-long identity with glassmaking.',
            '1291',
            'Furnaces ordered to Murano',
            '🔥',
            'https://www.cmog.org/sites/default/files/collections/75/759CAC48-8465-4D33-A9B4-BCEB2E6705CF.pdf',
            70
        ),
        (
            'venice-san-cassiano-public-opera',
            'venice',
            'first',
            'Venice''s Teatro San Cassiano opened in 1637 as the world''s first public opera house.',
            'By selling access beyond a courtly audience, the theater helped turn opera into public entertainment and ignited a boom that made Venice a center of the new art form.',
            '1637',
            'Public opera begins',
            '🎭',
            'https://www.teatrosancassiano.it/en/teatro-san-cassiano',
            80
        )
), prepared as (
    select
        md5('lore:wave-2026-07:fact:' || row_key)::uuid as id,
        city,
        category,
        fact,
        detail,
        stat_value,
        stat_label,
        emoji,
        source,
        sort
    from incoming
)
insert into public.city_fact (
    id, city, category, fact, detail, stat_value, stat_label, emoji, source, sort
)
select
    p.id, p.city, p.category, p.fact, p.detail, p.stat_value, p.stat_label,
    p.emoji, p.source, p.sort
from prepared p
where not exists (
    select 1
    from public.city_fact existing
    where existing.city = p.city
      and lower(btrim(existing.fact)) = lower(btrim(p.fact))
      and existing.id <> p.id
)
on conflict (id) do update set
    city = excluded.city,
    category = excluded.category,
    fact = excluded.fact,
    detail = excluded.detail,
    stat_value = excluded.stat_value,
    stat_label = excluded.stat_label,
    emoji = excluded.emoji,
    source = excluded.source,
    sort = excluded.sort;

do $coverage$
declare
    gap text;
begin
    select string_agg(target.city || '=' || target.actual, ', ' order by target.city)
    into gap
    from (
        select wanted.city, count(culture.id) as actual
        from (
            values ('baltimore'), ('brussels'), ('hobart'), ('manchester'), ('savannah')
        ) as wanted(city)
        left join public.city_culture culture on culture.city = wanted.city
        group by wanted.city
        having count(culture.id) < 10
    ) target;

    if gap is not null then
        raise exception 'city_culture coverage remains below 10: %', gap;
    end if;

    select string_agg(target.city || '=' || target.actual, ', ' order by target.city)
    into gap
    from (
        select wanted.city, count(fact.id) as actual
        from (
            values
                ('kyoto'), ('marrakech'), ('mount-laurel'),
                ('rio-de-janeiro'), ('sao-paulo'), ('venice')
        ) as wanted(city)
        left join public.city_fact fact on fact.city = wanted.city
        group by wanted.city
        having count(fact.id) < 8
    ) target;

    if gap is not null then
        raise exception 'city_fact coverage remains below 8: %', gap;
    end if;
end
$coverage$;

select 'city_culture' as content_type, city, count(*) as total
from public.city_culture
where city in ('baltimore', 'brussels', 'hobart', 'manchester', 'savannah')
group by city
union all
select 'city_fact' as content_type, city, count(*) as total
from public.city_fact
where city in (
    'kyoto', 'marrakech', 'mount-laurel', 'rio-de-janeiro', 'sao-paulo', 'venice'
)
group by city
order by content_type, city;

commit;
