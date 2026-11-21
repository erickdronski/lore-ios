-- Run once per release in the project's authorized SQL editor or connector.
-- Look up only publicly visible dossiers and CC0 coordinates. No runtime API.
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
  ('smith-tower', 'Smith Tower', 'https://www.smithtower.com/history/', 'The first plans called for just fourteen stories.', 'Lyman Cornelius Smith bought the lot at Second and Yesler in 1899. Plans for a modest tower grew more ambitious before construction began. When Smith Tower opened on July 4, 1914, thousands of visitors rode the elevator to an observatory on the 35th floor.', 1914, 'The observatory welcomes its first visitors')
), available as (
 select e.id, e.slug, e.name, e.kind, e.lat, e.lng, e.city, e.emoji,
        t.publisher, t.source_url, t.hook, t.narrative, t.year, t.event_title
 from editorial t
 join public.place_explore e using (slug)
 join public.place p on p.id=e.id and p.geom_license='cc0' and p.deleted_at is null
 join public.dive d on d.place_id=e.id
 join public.city c on c.slug=e.city and c.status='live'
)
select jsonb_build_object(
 'schema_version', 1,
 'cities', (select jsonb_agg(to_jsonb(c) order by c.sort,c.slug)
   from (select slug,name,country,emoji,lat,lng,zoom,status,sort from public.city
         where slug in (select city from available) and status='live') c),
 'places', (select jsonb_agg(jsonb_build_object('id',id,'slug',slug,'name',name,'kind',kind,
           'lat',lat,'lng',lng,'city',city,'emoji',emoji,'hook_text',hook,'tags','[]'::jsonb)
           order by city,name) from available),
 'dives', (select jsonb_agg(jsonb_build_object('place_id',id,'narrative',narrative,'source',publisher,
          'links',jsonb_build_object('source_url',source_url),'media','{}'::jsonb,
          'timeline',case when year is null then '[]'::jsonb else jsonb_build_array(
              jsonb_build_object('year',year,'title',event_title)) end)
          order by city,name) from available),
 'tours', '[]'::jsonb
) as catalog;
rollback;
