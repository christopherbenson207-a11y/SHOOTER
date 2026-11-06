# FRONTLINE map plan: smaller, cleaner, readable (6 Nov 2026)

The owner's verdict on the campaign valley for FRONTLINE: too big for its new use, too cluttered, and the
buildings are confusing. This plan says what the map becomes. Nothing has been deleted yet; the owner reads this
first.

## What is wrong now (measured in Studio, 6 Nov)

- **Too long and too wide.** The valley runs about 650 studs north to south and up to 300 across. It was built
  for a squad walking forward through six story beats, not for two teams fighting over one flag.
- **Spawns are far from the flags.** Attackers walk this far from their spawn to the flag:

  | Sector | Attacker spawn to flag |
  |---|---|
  | The Road | 94 studs |
  | The Depot | 173 studs |
  | The Plaza | 117 studs |
  | The Yards | 163 studs |
  | The Basin | 113 studs |

  Anything past about 100 studs is a long, empty jog on a 12 v 12 map.
- **Lone props in the open.** Within 90 studs of each flag:

  | Sector | Small props | Mostly |
  |---|---|---|
  | Road | 61 | crates 8, fuel drums 6, hay bales 6, gateposts 8, sandbag walls 6, plane skin 6 |
  | Depot | 52 | crates 10, fuel drums 5, sack pallets 4, sandbag walls 6, lanterns and lamps 7 |
  | Plaza | 32 | plane skin 5, sandbags 4, market stalls 3, fuel drums 3 |
  | Yards | 21 | lamps 4, crates 4, sleepers 4, fuel drums 3 |
  | Basin | 12 | rubble 3, crates 3 |

  They sit alone on open snow, so they are neither cover nor scenery. They are noise you have to read past.
- **Buildings that all look the same.** The town is about 14 cream plaster houses packed together, with 10 more
  "lane houses" behind them. From the ground every street looks alike, and nothing says which way the flag is.
- **Trees in the play space.** 101 pines, several standing inside fights, blocking sightlines at random.

## The target

| Thing | Target |
|---|---|
| A sector's fight space | about 150 x 120 studs |
| Attacker spawn to flag | 80 to 100 studs, 5 to 6 seconds of sprinting |
| Defender spawn behind the flag | 60 to 70 studs |
| Lanes per sector | 3: one main lane and two flanks, each clearly a lane |
| Hero landmark per sector | 1, visible from the attacker spawn, at the flag |
| Playable buildings per sector | at most 2 |
| Small props per sector | at most 15, all against a wall or building, never in a lane |

## Decisions

1. **Four sectors, not five.** FRONTLINE plays the FARM ROAD, the DEPOT, the PLAZA and the YARDS. A match is three in
   a row, starting at sector 1 or 2. The crash field (empty meadow south of the road) and the basin and frozen lake
   (huge and open, north of the yards) leave the play space. Walls close them off. Basin cover and spawns are
   deleted. The far hills stay as backdrop.
2. **Spawns chain flag to flag.** Each sector's attackers come in at the last flag they took, so the walk is always
   80 to 100 studs:

   | Sector | Attackers come in at | Distance |
   |---|---|---|
   | Farm Road (2, 198) | the south edge, about (-4, 280) | 82 |
   | Depot (52, 128) | the Road flag area | 86 |
   | Plaza (-5, -12) | the rail crossing, about (10, 82) | 95 |
   | Yards (-60, -112) | the plaza's north edge, about (-5, -40) | 91 |

   Defenders come in 60 to 70 studs behind their flag, out of the attackers' sight.
3. **The edges move with the fight (Battlefield Rush style).** Each sector has a play box. Outside it the screen
   warns RETURN TO THE FIGHT, and after 6 seconds it starts to hurt. Players never wander into the next sector or
   the empty valley. Bots already stay on their lanes.
4. **Physical walls move in.** The invisible `Bounds` walls move in to the new valley edges, about x -110 to 120 by
   the farm and depot, and x -130 to 80 through the town and yards, from z 285 in the south to z -165 in the north.
5. **Clutter rule: everything is cover, a landmark, or gone.**
   - Cover comes in lines or clusters at least 8 studs long (walls, containers, wagons, sandbag runs), set along
     lanes with room to strafe behind.
   - Small props (crates, drums, hay, pallets, lanterns, bins) stay only when they are pushed against a building or
     wall, and at most 15 a sector. The rest are deleted.
   - Lone gateposts, single sandbags, scattered plane skin and loose rubble are deleted.
   - Pines inside a play box are deleted unless one is deliberate cover. The slopes keep theirs.
6. **Buildings: playable or backdrop, never in between.**
   - A playable building has two or more doors, an empty readable inside and one window lane. Each sector gets at
     most two: Farm = the barn; Depot = the warehouse and the office; Plaza = the town hall and the hotel; Yards =
     the goods shed and the signal box.
   - Every other building is backdrop: no open doors, at the edge of the play box, and simple.
   - The 10 lane houses inside the town block are deleted. That opens three clear lanes through town: Main Street in
     the middle and a back lane on each side.
7. **Each sector reads differently.** One colour and one silhouette per sector, so a player always knows where they
   are:

   | Sector | Landmark | Colour |
   |---|---|---|
   | Farm Road | the red barn, plus a roadblock across the road | red and timber |
   | Depot | the white fuel tanks and the loading canopy | white and yellow |
   | Plaza | the town hall clock tower and the relay mast | cream and blue |
   | Yards | the long brick goods shed and the signal box | brick and black |

## Order of work

1. **Scripts (reversible):** four sectors in `Shared.Front`, the new spawn spots in `Map.War`, and the moving play box
   with its warning. Tested in Play.
2. **Map clean-up in Studio (after the owner OKs this plan):** delete per the rules above, sector by sector, with a
   top-down and a ground screenshot of each one before and after. Move the `Bounds` walls. The owner saves and
   publishes. Per "delete, don't archive", removed parts are deleted, not parked in ServerStorage.
3. **Landmarks:** the four hero buildings get Blender passes per `BLENDER-PIPELINE.md`, and the owner imports them.

## What this changes elsewhere

- The old story campaign (workspace `PlayCampaign`) uses the same map. It is retired, so it is not kept working.
- Map edits live in the place, not the repo. The owner must save and publish the campaign place after step 2.

## Done on 6 Nov (steps 1 and 2, in Studio; the owner must save and publish the campaign place)

- **Four sectors** in `Shared.Front`: the Road, the Depot, the Plaza and the Yards. A match starts at sector 1 or 2.
- **New spawn spots** in `Map.War`: `FL_<Sector>_Attack` and `FL_<Sector>_Rear`, 4 parts each, placed on open
  ground by a clearance search. The old `Start`, `Checkpoint` and `_Rear` groups are left for the retired campaign.
- **Play boxes:** computed from each sector's flag, posts and both spawns, with a 30-stud margin. They come out about
  150 to 210 studs wide and 210 to 245 long. Outside one, the HUD says RETURN TO THE FIGHT and counts down from 6,
  then it hurts 20 a second. Tested in Play.
- **Walls:** new invisible walls `FrontSouth` at z 300 and `FrontNorth` at z -185. Six old walls beyond them were
  deleted.
- **Clutter:** 59 lone props were deleted. They were fuel drums, crates, hay bales and ricks, sack pallets,
  gateposts, scattered plane skin, market stalls, a tractor, cargo spills, a cable drum and similar. Kept on
  purpose: lights (the fights are at night), fire barrels, snow poles (they mark the road edges), every cover line
  (walls, sandbags, barriers, vehicles in the road lane), and anything against a building or by a post.
- **Pines:** 5 pines on the valley floor were deleted. The two town cover pines were kept.
- **Correction to decision 6:** the "lane houses" (H1 to H4) are not inside the town block. They form the outer
  walls of the two back lanes. Deleting them would turn the flanks into open fields, so they stay.
- **Not done yet:** the building colour and landmark pass (decision 7 and step 3). That is visual design work for
  Blender and the owner's eye. The Road field still has short wall pieces that read as scattered; re-laying them
  into clear lines is part of that pass.
