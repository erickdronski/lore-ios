-- Public release export. Run read-only in the project SQL editor as shown.
-- The standalone atlas uses public-domain/CC0 coordinates, selected factual fields,
-- original editorial text, and references. Never export source prose or media.
-- With a new contract epoch or active withdrawal policy a new review is required.
begin read only;
set local role anon;
with editorial(slug, publisher, source_url, hook, narrative, year, event_title) as (
 values
  ('cloud-gate', 'Choose Chicago', 'https://www.choosechicago.com/articles/tours-and-attractions/the-bean-chicago/', 'Look for a seam in the skyline reflected on Cloud Gate.', 'Anish Kapoor’s sculpture looks like one piece of metal. Its skin actually took 168 stainless steel plates, welded and polished until their joints disappeared. Walk toward the hollow beneath the arch and watch how the curved surface rearranges the surrounding buildings.', null, null),
  ('willis-tower', 'Skidmore, Owings & Merrill', 'https://www.som.com/projects/willis-tower-formerly-sears-tower/', 'The setbacks mark where individual tubes end.', 'Look up the face of the former Sears headquarters. At its base, nine square structural tubes stand together, each 75 feet wide. They end at different heights. The steps you see in the skyline trace the building’s frame.', null, null),
  ('robie-house', 'Frank Lloyd Wright Trust', 'https://flwright.org/explore/frederick-c-robie-house', 'Even the brickwork draws your eye sideways.', 'Frank Lloyd Wright designed this Hyde Park home for Frederick Robie. It was finished in 1910. Follow the line of a projecting roof back to the wall, then look at the bands of windows and long runs of brick below. The horizontal pattern repeats at each scale.', 1910, 'Robie House is completed'),
  ('wrigley-building', 'Chicago Architecture Center', 'https://www.architecture.org/online-resources/buildings-of-chicago/wrigley-building', 'A tower from Seville helped shape a Chicago headquarters.', 'William Wrigley Jr. chose the north bank of the river for his chewing gum company’s headquarters. Two buildings make up the complex, both faced in white terra cotta. Look at the tower above them. Its design draws on the Giralda in Seville, Spain.', null, null),
  ('brooklyn-bridge', 'New York City Department of Transportation', 'https://www.nyc.gov/html/dot/html/infrastructure/brooklyn-bridge.shtml', 'The walk to the river is part of the engineering.', 'The bridge had to clear the East River while meeting low ground on either bank. That explains why the approaches reach so far into Brooklyn and Manhattan. Its stone towers carry a suspension span completed in 1883 after work began in 1869.', 1883, 'The bridge is completed'),
  ('empire-state-building', 'Empire State Building', 'https://www.esbnyc.com/about/history', 'The tower’s opening ceremony reached all the way to Washington.', 'The Empire State Building opened on May 1, 1931. A button pressed by President Herbert Hoover in Washington switched on the lights. The 102-story tower had gone up in a year and 45 days, with workers adding about four and a half stories of steel framing a week.', 1931, 'The Empire State Building opens'),
  ('statue-of-liberty', 'National Park Service', 'https://www.nps.gov/stli/learn/statue-of-liberty-facts.htm', 'The harbor was the statue’s second assembly site.', 'Workers built the statue in France and took it apart for the Atlantic crossing. It arrived in New York in 1885 and was reassembled on its pedestal for the dedication in October 1886. From the harbor, compare the figure with the pedestal beneath it. The pedestal is slightly taller.', 1886, 'The statue is dedicated'),
  ('independence-hall', 'National Park Service', 'https://www.nps.gov/articles/000/assembly-room-furnishings.htm', 'One chair in the Assembly Room links two legislatures.', 'The Declaration of Independence was approved in this room in 1776. The carved chair at its front came later. John Folwell made it for Pennsylvania’s legislative speaker in 1779, and George Washington used it while presiding over the Constitutional Convention in 1787.', 1787, 'The Constitutional Convention meets here'),
  ('liberty-bell-center', 'National Park Service', 'https://www.nps.gov/inde/learn/historyculture/stories-libertybell.htm', 'Look above the crack for the inscription that gave the bell its public life.', 'This was the bell of the Pennsylvania State House. Its inscription called for liberty throughout the land. Abolitionists took up that language, and advocates for women’s voting rights and civil rights later found their own cause in the same words.', null, null),
  ('reading-terminal-market', 'Reading Terminal Market', 'https://readingterminalmarket.org/about-the-market/history/', 'A railroad and a market shared this block vertically.', 'When the railroad bought the block for a terminal, the merchants wanted to stay. Their new market opened beneath the train shed in 1893. Stalls occupied the street level while refrigerated rooms below held food at different temperatures. Shoppers once heard trains move overhead.', 1893, 'The market opens below the tracks'),
  ('golden-gate-bridge', 'Golden Gate Bridge, Highway and Transportation District', 'https://www.goldengate.org/bridge/history-research/bridge-features/color-art-deco-styling/', 'The color of unfinished steel helped determine the finished bridge.', 'The fabricated steel arrived with a reddish protective primer. Seeing the towers go up, consulting architect Irving Morrow investigated how that warm color looked from the bay. His studies led to International Orange, chosen to stand out against water and sky while fitting the hills.', null, null),
  ('alcatraz-island', 'National Park Service', 'https://www.nps.gov/alca/learn/historyculture/us-penitentiary-alcatraz.htm', 'The island was already a prison before the federal penitentiary opened.', 'The Bureau of Prisons took over a former Army prison on the island. Its distance from shore suited officials who wanted to limit contact with the outside world. Alcatraz operated as a federal penitentiary from 1934 to 1963.', 1934, 'The federal penitentiary era begins'),
  ('coit-tower', 'San Francisco Recreation and Park Department', 'https://sfrecpark.org/facilities/facility/details/Coit-Tower-290/', 'The tower and the paintings inside it belong to two different years.', 'Coit Tower rose on Telegraph Hill in 1933. The next year, artists working for the federal Public Works of Art Project painted its base with scenes of California during the Depression. Look at the building from both distances. The column marks the skyline, while the murals tell stories at eye level.', 1934, 'Artists paint the tower murals'),
  ('space-needle', 'Space Needle', 'https://www.spaceneedle.com/history', 'The shape grew out of two very different ideas.', 'The tower was conceived for Seattle’s 1962 World’s Fair. Architect John Graham Jr. developed the flying-saucer form at the top. Victor Steinbrueck drew on a sculpture of a dancer for the narrow waist of the supporting structure. Trace the two shapes separately from the ground.', 1962, 'Seattle hosts the World’s Fair'),
  ('pike-place-market', 'Pike Place Market', 'https://www.pikeplacemarket.org/market-history/', 'The first market here gave farmers a way to sell directly.', 'Seattle created a public farmers market on Pike Place in 1907. Decades later its future was in doubt. Voters approved a historic district around the market, protecting a place where producers and shoppers could still meet in the middle of the city.', 1907, 'A public farmers market begins'),
  ('smith-tower', 'Smith Tower', 'https://www.smithtower.com/history/', 'The first plans called for just fourteen stories.', 'Lyman Cornelius Smith bought the lot at Second and Yesler in 1899. Plans for a modest tower grew more ambitious before construction began. When Smith Tower opened on July 4, 1914, thousands of visitors rode the elevator to an observatory on the 35th floor.', 1914, 'The observatory welcomes its first visitors'),
  ('marina-city', 'Chicago Architecture Center', 'https://www.architecture.org/online-resources/buildings-of-chicago/marina-city', 'What looks like a flower from below is a floor plan.', 'Look up from the river at the round towers of Marina City. Cars occupy the open lower floors. Higher up, wedge-shaped apartments meet the air at curved balconies. Architect Bertrand Goldberg gathered homes and parking around the same central cores so people could live downtown.', null, null),
  ('art-institute', 'Art Institute of Chicago', 'https://www.artic.edu/pdf/static/download-my-museum-tour.pdf-layout-42.pdf', 'The two bronze lions strike different poses.', 'The pair at the Michigan Avenue entrance arrived in 1894. Sculptor Edward Kemeys gave each animal a character of its own. Compare their heads, tails and front paws from the sidewalk. The lion north of the steps is on the prowl. Its southern partner stands its ground.', 1894, 'Bronze lions take their places at the entrance'),
  ('buckingham-fountain', 'Chicago Park District', 'https://www.chicagoparkdistrict.com/parks-facilities/clarence-f-buckingham-memorial-fountain', 'Four groups of sea horses turn this basin into a map.', 'Kate Buckingham gave Chicago the fountain in memory of her brother Clarence. The great basin stands for Lake Michigan. Look for the groups of sculpted sea horses around it. Each marks one of the four states along the lake’s shore.', 1927, 'Buckingham Fountain opens'),
  ('seattle-great-wheel', 'Seattle Great Wheel', 'https://seattlegreatwheel.com/faq', 'The wheel grew out of one pier owner’s long-running idea.', 'Hal Griffith wanted to bring a Ferris wheel to Seattle for nearly thirty years. He eventually built one on his own pier. From the waterfront, trace the circle of 42 enclosed gondolas and look for the point where the deck beneath them gives way to Elliott Bay.', null, null),
  ('rainier-tower', 'Society of Architectural Historians', 'https://sah-archipedia.org/buildings/WA-01-033-0077', 'The office block grows narrower as it meets the ground.', 'Stand where you can see the base of Rainier Tower in profile. Minoru Yamasaki’s design places 29 office floors above an eleven-story concrete pedestal. The pedestal curves inward as it descends, leaving an open space where the edges of a conventional office tower would meet the block.', null, null),
  ('washington-monument', 'National Park Service', 'https://www.nps.gov/wamo/faqs.htm', 'A change in the stone records an interruption in construction.', 'Look for the horizontal change in color on the monument’s shaft. Work stopped in 1854 when money ran out. The stone for the later part came from another quarry, and those blocks weathered differently. The pale bands on an apparently uniform obelisk mark two periods of work.', 1854, 'Construction halts for lack of funding'),
  ('united-states-capitol', 'Architect of the Capitol', 'https://www.aoc.gov/explore-capitol-campus/buildings-grounds/capitol-building', 'What material would you guess supports the white dome?', 'Viewed from the Mall, the Capitol’s dome seems to grow from the masonry below. Architect Thomas U. Walter designed it in cast iron. Follow its silhouette from the wide base to the statue at the top and imagine how workers assembled the many pieces over the Rotunda.', null, null),
  ('vietnam-veterans-memorial', 'National Park Service', 'https://www.nps.gov/places/000/vietnam-veterans-memorial.htm', 'The order of the names follows time.', 'Maya Lin set the memorial’s polished black granite walls into the ground. As the path descends, the panels rise beside it. The names follow the dates of the service members’ deaths or disappearances, making the progression of the war part of the walk.', null, null),
  ('lincoln-memorial', 'National Park Service', 'https://www.nps.gov/linc/learn/historyculture/exterior-features.htm', 'The columns count states rather than presidents.', 'From the plaza, look beyond the front row of columns to the sides of the memorial. Thirty-six columns surround the building, one for each state in the Union at Lincoln’s death. Above them, the state names appear in the frieze.', null, null)
), routes(slug, blurb) as (
 values
  ('millennium-moments', 'From the river to Grant Park, see how architects and artists put a parking garage, a skyline, two lions and a lake into four very different forms.'),
  ('emerald-city-sampler', 'Start at the Space Needle and finish at Rainier Tower. In between, descend to the market and waterfront to see what Seattle built around the edge of Elliott Bay.'),
  ('national-mall-postcards', 'Go east to the Capitol before crossing back toward the Lincoln Memorial. Stone, iron and polished granite tell four different stories along this long Mall walk.')
), notes(tour_slug, seq, place_slug, note) as (
 values
  ('millennium-moments', 1, 'marina-city', 'Start on the river side with both towers in view. Find the floor where the open spiral of parked cars changes into rings of balconies.'),
  ('millennium-moments', 2, 'cloud-gate', 'Before approaching the arch, pick a building in the reflected skyline. Take a few steps to one side and see whether you can keep track of it.'),
  ('millennium-moments', 3, 'art-institute', 'At the Michigan Avenue steps, compare the two lions from the sidewalk. Which one looks ready to move? Look at the forepaws before you decide.'),
  ('millennium-moments', 4, 'buckingham-fountain', 'Finish at the basin in Grant Park. Walk part of its rim to spot the separate groups of sea horses that stand for the states around Lake Michigan.'),
  ('emerald-city-sampler', 1, 'space-needle', 'Begin at Seattle Center. Trace the legs as they narrow at the waist and widen again to support the saucer.'),
  ('emerald-city-sampler', 2, 'pike-place-market', 'At the market, look at how the stalls meet the street. Imagine a farmer bringing produce here in 1907 to sell directly to neighbors.'),
  ('emerald-city-sampler', 3, 'seattle-great-wheel', 'Down on the waterfront, stand back far enough to see both the wheel and its pier. Look for the point on the rim that extends over the water.'),
  ('emerald-city-sampler', 4, 'rainier-tower', 'Head inland for the final stop. Look up from across the street and trace the outline of the tower down to its narrow concrete base.'),
  ('national-mall-postcards', 1, 'washington-monument', 'Begin near the obelisk. Shade your eyes and scan the stone for the line where the marble changes shade.'),
  ('national-mall-postcards', 2, 'united-states-capitol', 'Head east along the Mall. As the dome grows larger, look for the change from the straight lines of the building to the curves of the cast-iron dome.'),
  ('national-mall-postcards', 3, 'vietnam-veterans-memorial', 'Return west to the memorial. Follow the path quietly as the ground slopes down and the walls fill more of your field of view.'),
  ('national-mall-postcards', 4, 'lincoln-memorial', 'Finish at the Lincoln Memorial. From the plaza, pick out the rows of columns on the sides before looking back along the Mall.')
), available as (
 select e.id, e.slug, e.name, e.kind, e.lat, e.lng, e.city, e.emoji, p.geom_license,
        t.hook, t.publisher, t.narrative, t.year, t.event_title,
        coalesce(t.source_url, d.links->>'wikipedia_url') as source_url,
        case when p.layer1_licenses::text = '{cc0}' then
          nullif(jsonb_strip_nulls(jsonb_build_object(
            'architect', case when jsonb_typeof(e.layer1->'architect') = 'string'
               and length(trim(e.layer1->>'architect')) between 1 and 160 then trim(e.layer1->>'architect') end,
            'style', case when jsonb_typeof(e.layer1->'style') = 'string'
               and length(trim(e.layer1->>'style')) between 1 and 100 then trim(e.layer1->>'style') end,
            'year_built', case when jsonb_typeof(e.layer1->'year_built') = 'number'
               and e.layer1->>'year_built' ~ '^[1-2][0-9]{3}$' then e.layer1->'year_built' end
          )), '{}'::jsonb)
        end as facts
 from public.place_explore e
 join public.place p on p.id=e.id and p.geom_license in ('cc0','public_domain') and p.deleted_at is null
 join public.city c on c.slug=e.city and c.status='live' and c.country='US'
 join public.dive d on d.place_id=e.id
 left join editorial t on t.slug=e.slug
 where (t.source_url is not null or d.links->>'wikipedia_url' ~ '^https://en[.]wikipedia[.]org/wiki/[^?#[:cntrl:] ]+$')
   and abs(e.lat-c.lat) < 0.7 and abs(e.lng-c.lng) < 1
), published_walks as (
 select t.id, t.slug, t.city, t.title, r.blurb, t.emoji, t.duration_min, t.distance_km,
        t.travel_mode, t.distance_kind, t.route_source, t.route_checked_at, t.route_note, t.is_premium,
        (select jsonb_agg(jsonb_build_object('tour_id',s.tour_id,'place_id',s.place_id,'seq',s.seq,'note',n.note)
                          order by s.seq)
         from public.tour_stop s
         join available a on a.id=s.place_id and a.city=t.city and a.narrative is not null
         join notes n on n.tour_slug=t.slug and n.seq=s.seq and n.place_slug=a.slug
         where s.tour_id=t.id) as tour_stop
 from routes r join public.tour t on t.slug=r.slug
 where not t.is_premium and t.travel_mode='walking' and t.distance_kind='walking_route'
   and t.route_checked_at is not null
), catalog as (
 select jsonb_build_object(
   'schema_version', 2, 'review_epoch', contract.review_epoch,
   'cities', (select jsonb_agg(to_jsonb(c) order by c.sort,c.slug)
     from (select slug,name,country,emoji,lat,lng,zoom,status,sort from public.city
           where slug in (select city from available) and status='live') c),
   'places', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
     'id',id,'slug',slug,'name',name,'kind',kind,'lat',lat,'lng',lng,'city',city,'emoji',emoji,
     'hook_text',hook,'tags','[]'::jsonb,'source_name',coalesce(publisher,'Wikipedia'),
     'source_url',source_url,'geom_license',geom_license,'layer1',facts)) order by city,name,id)
     from available),
   'dives', (select jsonb_agg(jsonb_build_object('place_id',id,'narrative',narrative,'source',publisher,
     'links',jsonb_build_object('source_url',source_url),'media','{}'::jsonb,
     'timeline',case when year is null then '[]'::jsonb else jsonb_build_array(
       jsonb_build_object('year',year,'title',event_title)) end) order by city,name,id)
     from available where narrative is not null),
   'tours', (select jsonb_agg(to_jsonb(w) order by city,slug) from published_walks w
     where jsonb_array_length(w.tour_stop)=(select count(*) from public.tour_stop s where s.tour_id=w.id)
       and jsonb_array_length(w.tour_stop)=(select count(*) from notes n where n.tour_slug=w.slug))
 ) as catalog
 from public.content_contract contract where contract.contract_version=2
   and contract.review_epoch=2026090501 and not contract.enforcement_enabled
)
select catalog from catalog;
rollback;
