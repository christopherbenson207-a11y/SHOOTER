# FRONTLINE open world: the overhaul plan (7 Nov 2026)

This replaces `FRONTLINE-PLAN.md` (the 3-sector push) and `FRONTLINE-MAP-PLAN.md` (the trimmed valley). Both stay
as history; nothing in them is built on from here.

Owner, 7 Nov 2026: "Our war game competition is looking tuff. Our map in campaign is very weak and the gameplay.
Campaign map and system needs an overhaul and the games lighting, style, weather systems need to be planned."
Then: "Frontline needs to be changed completely to a huge map, replayable mode, fun open world." The research was
Galifran's "Top 10 best war games on Roblox 2026" (https://youtu.be/mOoORWarlxs), watched one frame per second for
the full 12 minutes, with the full caption track read line by line.

## 1. What the ten best war games do (from the video)

| # | Game | What it is | What makes it good (seen and said) |
|---|---|---|---|
| 10 | No Man's Land | WW1, third person | Mood above all: a night city on fire, rain and fog, planes overhead, suppression that blurs and tints the screen. The capture zone is a tinted column of colour you can see from far away, and a coloured smoke flare marks the cargo. "Cargo" mode: both teams fight over a drop in the middle. Bodies stay on the ground. |
| 9 | Dogs of War | WW2, first person | One art style everywhere: hand-painted, cartoon, outlined. Tight city maps where every door and corner can hide someone. Loadout of primary, secondary and specials, unlocked by playing. A row of flag icons at the top shows who owns what. Big painted "Allies / Axis" team pick. |
| 8 | Bleeding Blades | Medieval melee | Real battles, each map plays differently (sieges, field battles, river crossings). Siege towers, rams and ballistas that take several players to work. Crowds of 30+ in one fight. A tug-of-war bar at the top. Cavalry. |
| 7 | Steel Titans | WW2 tanks | 160 tanks, ammo types, X-ray of damaged modules. Engineers place walls with a green (valid) or red (invalid) ghost preview. Capture zones drawn as a red ring on the ground. Snow, desert, tropical and city maps. |
| 6 | Empire Clash | Persistent open world | One big island map with named places (Water Mill, Quarry, Fort, Military Academy, Palace). Factions hold them; the side panel lists what is "UNDER ATTACK" and "CAPTURING". Farming and crafting feed the war; you lose your kit when you die. Elected leaders and polls. |
| 5 | The Eastern War | Modern, realistic, open world | Huge open terrain (snow forests, frozen trenches, desert, grass fields), realistic PBR guns and uniforms, a compass strip at the top, lettered points A to D in the world, a "You are dying" downed state, and very little HUD. Hard: you are shot before you see anyone. 51M visits. |
| 4 | Centaura | Fictional early-1900s nations | Its own lore and nations. A sepia, desaturated grade with a vignette and lens distortion, ember particles, artillery that rains all match, and tinnitus (ringing ears) when a shell lands close. Back in the fight within seconds of dying. |
| 3 | Marque of War | Napoleonic, 128 players | Big river valleys with colourful villages, golden light, horses. The capture area is a glowing line on the ground. Classes earned by playing, from fusilier up to officer. |
| 2 | Entrenched | WW1, 22 maps, 9 classes | The phase system: every few minutes the sides switch between attack and defend, and defenders dig in (sandbags 60%, trench wall 86%). Sector rows (E1 E2 E3 C3 C2 C1) with percentages, a big "ATTACK / DEFEND" label and phase clock, "Killed X · 28 studs", "You were spotted", a mobile layout. No pay-to-win. |
| 1 | Airship Assault | Interwar, 58M visits | Three roles that each feel like a different game (raider on a glider, crewman repairing and manning guns, pilot). A second mode, Isle: beach landing from landing craft, palm island, tanks, artillery. Each faction has its own look. |

**What they share, and we lack:**
1. **Atmosphere is the product.** The narrator praises mood before guns in five of the ten: fire, rain, snow, fog,
   planes overhead, artillery, ringing ears, a strong colour grade. Ours is a flat grey afternoon with no weather.
2. **One art style, held everywhere.** Each game picks one family (painted cartoon, or grounded realistic, or sepia
   semi-real) and every model, texture and UI piece matches it.
3. **Maps with a name, a place and a story** ("Amiens City 1918", "Kirmanov", "Tannenberg 1914").
4. **Objectives you read from anywhere:** coloured columns, ground rings, lettered markers, a flag row with %.
5. **Systems that make chaos on their own:** phases, artillery, cargo drops, building, vehicles, crewed weapons, roles.
6. **Earn everything by playing**, and get back into the fight fast.

## 2. Where we stand (checked in the campaign Studio, 7 Nov)

- **Lighting:** ClockTime 15.6, Brightness 1.9, Atmosphere density 0.36 with haze 1.8, a mild grade (NightGrade:
  contrast 0.12, saturation -0.22). From the ground it reads as a flat grey afternoon. There is no falling snow, no
  wind, no fire or smoke in the sky, and the sky has no stars or clouds of note.
- **Map:** 2,628 parts in `Map.Valley` after the 6 Nov cuts. From above it is a small cluster of buildings in a huge
  empty white bowl, with blotchy rock and snow terrain around it. At eye level the road sector is a flat snow field
  with stone field walls and a town of pastel boxes far off.
- **Style:** cream and pastel plaster houses, a teal Toolbox van, a rust-textured car, realistic pines and a
  wrecked plane. Each one comes from a different source, so nothing belongs together.
- **Gameplay:** a 12 v 12 three-sector push through a corridor, bots on both sides, three killstreaks. It is locked
  in the lobby since b020cb6 (the MULTIPLAYER card is the 1v1 duel).
- **What is strong and stays:** the battle AI on both sides (Battle, Soldier v2, CoverMap, tactics), tanks,
  emplacements, explosive drums, gun feel (GunFeel, MuzzleFx, ViewMode third person), the ElevenLabs sound set, the
  end card, progression, per-gun challenges, the store and boosters.

## 3. The decision

**FRONTLINE becomes Conquest on one huge open map, "Varsk Valley". 20 v 20, bots fill every empty slot. Seven named
points; hold more than the enemy and their tickets bleed. Free spawn on any point you own, your base or your squad.
Vehicles to cross the map. Every match rolls its own weather and time of day, and the fight moves to a different
part of the valley each time.**

Why Conquest: it is the proven open-world loop (Battlefield; Eastern War, Entrenched and Marque of War all use
lettered points), it works on a phone (go to the letter, stay in the ring), and the battle AI already does "attack
a spot group" and "hold posts". Domination on a small arena and the push corridor both fight an open map.

**Art direction (decided): grounded semi-real, late Cold War, Eastern Europe.** This is the owner's "Cold War on
Roblox" ask and the Eastern War's look (realistic PBR, the most-praised modern game in the list), held with one rule:
every surface is a PBR MaterialVariant or a Blender model textured the same way, and nothing cartoon or pastel goes
on the map. Characters stay Roblox avatars in uniform. The menu keeps its own kid-friendly navy and yellow; the
in-match HUD stays flat and minimal (the owner's realistic-flat-UI rule).

## 4. Varsk Valley (the map)

**World brief**

- **Fantasy:** a frozen river valley on the border in the last winter of the Cold War; two armies fight over the
  dam, the rail junction and the radar on the hill while the town burns.
- **Play pattern:** spawn at a base or an owned point, drive or run to the nearest contested letter, take it, hold
  it, move on. Matches last 15 to 20 minutes. 1 to 40 players, bots to 20 a side.
- **Target:** phone first, PC strong. StreamingEnabled on.
- **Scale:** R15 at default size, WalkSpeed 16, sprint 24.
- **Style:** grounded semi-real PBR (see 3).
- **Palette:** snow 232,236,240 | concrete 150,150,145 | rust brick 128,72,56 | pine 52,70,58 | asphalt 60,62,66.
- **Accents:** HOUND blue 70,140,230 and LAMPLIGHTER amber 240,150,40, used only on point markers, flags, smoke
  flares and the HUD. Nothing else on the map uses them.
- **Hero landmark:** the radar station on Radar Hill in the middle of the map. The mast is 110 studs tall on a hill
  60 studs high, with red aircraft lights that blink at night. It is visible from both bases and every point.
  Second landmark: the dam's wall across the north end.
- **Not this:** no pastel houses, no cartoon props, no lone props on open snow, no Toolbox model left in its original
  texture, no trees standing in the middle of a fight, no long empty walks without cover or a vehicle.

**Size and layout.** The play area is about 1,800 x 1,400 studs, some 13 times the area of today's valley. The ground
is Terrain; the edges are mountains and a frozen lake that you cannot cross (soft boundary: "RETURN TO THE FIGHT"
for 6 seconds, then damage, as built on 6 Nov). Neighbouring points are 250 to 350 studs apart, which is 12 to 15
seconds of sprinting or 6 seconds in a jeep (the guide: a fight every 150 to 300 studs).

| Point | Name | What it is | Kind of fight |
|---|---|---|---|
| Base S | HOUND base | Forward operating base with a helipad, vehicle depot and field tents | Safe spawn, vehicles |
| A | Kolkhoz | A collective farm: two barns, a grain silo, a tractor yard | Open fields, long sightlines, barns to clear |
| B | Rail Junction | Marshalling yard, goods shed, signal box, rows of wagons | Lanes between wagons, close and medium range |
| C | Old Town | The town square with a church, hotel and town hall, streets on fire at night | Close quarters, rooftops, doorways (Dogs of War) |
| D | Radar Hill | The radar station and its bunkers on top of the central hill | King of the hill: everyone sees it, everyone wants it |
| E | The Bridge | A steel road bridge over the river and the riverside houses | A chokepoint; vehicles must cross here or at the dam |
| F | Hydro Dam | The dam wall, the turbine hall, the spillway | Vertical fight on and inside the wall |
| G | Forest Line | Trench lines and log bunkers in the pine forest (Eastern War) | Trench fighting, prone in the snow |
| Base N | LAMPLIGHTER base | Requisitioned factory with smokestacks, rail spur and trucks | Safe spawn, vehicles |

The river runs west to east through the middle, so the valley has two halves joined by the Bridge, the Dam and one
ford. The main road snakes from base to base through A, C and E; a dirt track through G and F is the flank.

**The front moves (replay).** A match does not use all seven points at once. It draws a "front" of five neighbouring
points (for example A-B-C-D-E or C-D-E-F-G), so the fight happens in a different part of the valley each match, the
points stay close enough for 20 a side, and the rest of the map is still there to drive through and flank across.

**How it gets built** (each phase ends with screenshots from the spawns, a walk test and a phone budget check):
1. **Blockout:** Terrain sculpted at full size (hills, river, cliffs), grey boxes for every building, every point's
   ring, both bases, the roads. Time the runs and drives. Bots walk every lane (the `CHECKS.lua` method).
2. **Primary forms:** one Blender building kit in the chosen style (concrete panel blocks, brick sheds, timber barns,
   the church), the radar station and the dam as hero models, all imported by the owner (`BLENDER-PIPELINE.md`).
3. **Composition pass** from the player camera at 10, 50 and 300 studs, on a phone aspect too.
4. **Cover and story groups:** cover in lines (walls, wagons, sandbag runs, trench lines), story groups at nodes
   (a convoy hit on the road, an abandoned checkpoint). No lone props on open snow.
5. **Ground and foliage:** real pine and birch models (owner rule), bare winter trees, snow drifts, tyre tracks.
6. **Delete the old valley** once Varsk plays (owner rule: delete, don't archive).

**Budget (phone):** StreamingEnabled with Opportunistic stream-out, landmarks (radar mast, dam, church tower) set
`Persistent` so they always show, everything else streams. 300k to 600k visible triangles on a phone, at most 12
lights on screen and 3 with shadows. Static scenery anchored; decor with CanCollide, CanTouch and CanQuery off.

## 5. Systems (what gets built, in the order players feel it)

| System | What the player gets | From | Builds on |
|---|---|---|---|
| **Stances** | Tap crouch, hold for prone, move in both, crouch again to stand; no sprint while low | Every shooter | Evade, CrouchPose (being built now, see 8) |
| **Conquest** | Seven lettered points, tickets bleed while the enemy holds more, a match ends at 0 tickets or 20 minutes | Battlefield, Eastern War, Entrenched | FrontServer's capture code |
| **Point readability** | A coloured ring on the ground plus a column of smoke in the owner's colour, a world letter that shows through walls, a flag row with % at the top, "B IS CONTESTED" | No Man's Land, Steel Titans, Entrenched | ObjectiveMarker, the flag poles |
| **Deploy screen** | A map of the valley; pick your base, any point you hold that is not contested, or your squad leader | Battlefield | Authored PNG map art (UI rule) |
| **Vehicles** | Jeep (4 seats), transport truck (8), tank at the base on a long cooldown | Steel Titans, Airship Isle | `Modules.Tank`; jeep and truck are new |
| **Classes** | Rifleman, Assault, Support (MG, ammo box), Medic (revive), Engineer (build, launcher), Recon (sniper, spot). All earned by playing, none sold | Marque of War, Entrenched | Gear, Classes, Progression |
| **Building** | Engineers place sandbags, wire and an MG nest with a green or red ghost preview, at a supply cost | Steel Titans, Entrenched | Emplacements |
| **Suppression and shell shock** | Near misses blur and darken the screen edges and shake the view; a shell close by rings your ears and muffles sound for 3 seconds | No Man's Land, Centaura | PlayerHealthClient, sound groups |
| **Battle ambience** | Distant artillery flashes and thumps, tracers in the sky, planes flying over, smoke columns over burning points, all client-side and far away | No Man's Land, Centaura | MuzzleFx pooling, the sound overhaul |
| **Match events** | Every 4 to 6 minutes one of: a supply drop on a random point (marked by smoke), an artillery barrage on the most contested point, a convoy across the map | No Man's Land cargo, Centaura | Mortars killstreak, explosions |
| **Spotting and compass** | A compass strip at the top with point letters and marked enemies; spot with Q | Eastern War, Entrenched | SPOTTER killstreak |
| **Squads** | Parties stay in one squad of 4, spawn on each other, a squad order marker | Battlefield | Party code in MenuServer |
| **Lobby card** | FRONTLINE back in the lobby next to the duel | | `Common.Multiplayer` |

Kept as is: the killstreaks (SPOTTER, MORTARS, ARMOUR), the bots' AI, guns and attachments, the gun feel, third
person, the AAR and end card, pay through `Profile.Earn`, the weekly Front counter.

Owner rules that still hold: no damage numbers, one notice line at a time (kill and capture lines share it), UI is
authored PNG art, the PC gets no aim assist, enemy blood stays dark and limited on faces.

## 6. Lighting, style and weather

**One system, `WeatherService` (server) plus `WeatherClient`.** The server picks a preset at the start of each match
and may move to a second one partway through (snow starts falling, fog rolls in at dusk). It writes the preset name
and a blend time to workspace attributes; every client tweens Lighting, Atmosphere, Clouds and the grade, and turns
its own weather on around its camera. Nothing per-frame runs on the server.

**Base settings for all presets:** `LightingStyle` Realistic with `PrioritizeLightingQuality` on; Atmosphere is the
fog (Fog properties are ignored while one exists); one ColorCorrection named `Grade`, one Bloom, SunRays, a light
DepthOfField only in menus. The existing `HurtColor` grade stays for damage.

| Preset | ClockTime | Sky and light | Atmosphere (density / haze) | Grade (contrast / saturation / tint) | Weather on the camera | Gameplay |
|---|---|---|---|---|---|---|
| Clear Morning | 8.5 | low sun, long blue shadows | 0.28 / 0.6 | 0.10 / -0.05 / cool white | light snow dust off roofs | full sight |
| Overcast | 13 | flat, soft | 0.38 / 1.4 | 0.08 / -0.18 / grey blue | none | full sight |
| Snowfall | 15 | dim, cloudy | 0.45 / 1.8 | 0.10 / -0.20 / cold | snowfall, wind sound | bots see 260 studs |
| Blizzard | 16 | dark, white-out | 0.62 / 2.6 | 0.06 / -0.30 / white | heavy driving snow, gusts | bots see 140 studs, sound carries less |
| Freezing Fog | 7 | sun a pale disc | 0.70 / 0.8 | 0.05 / -0.35 / blue grey | ice motes | bots see 160 studs |
| Golden Dusk | 17.4 | warm low sun, pink sky | 0.33 / 1.2 | 0.12 / 0.05 / warm | none | full sight |
| Night Battle | 22.5 | moon, stars, flares | 0.40 / 0.6 | 0.12 / -0.10 / blue | flares drift down over contested points | street lamps, fires and flares light the fights (owner: night with lights, never forced day) |

Rules: Ambient never brighter than OutdoorAmbient; night is tinted blue, never black; phones below graphics quality
4 have no shadows, so value and colour must carry each preset (check every preset with shadows off and in
greyscale). Local lights only at focal points, as in the budget above. The weather particles are a few emitters
parented to a part that follows the camera, so the cost does not grow with map size.

**Style rules for every new asset:**
1. Blender model or retextured Toolbox model (owner rules), PBR textures at the same texel density, no plastic.
2. One MaterialVariant library for the whole game (about 20: snowy concrete, wet asphalt, rusted metal, brick,
   timber, frozen mud, trench planks), named `<Base><Surface><Variant>`.
3. Weathering on everything: snow on top faces, grime at the bottom, rust on metal.
4. Colour comes from the light and the grade, not from paint. The two team accents are the only saturated colours.

## 7. Build order

| Phase | What | Done looks like |
|---|---|---|
| 0 | Stances (crouch, prone, move, stand) in the campaign and duel places | In Play: tap, hold, crawl, stand, no sprint while low, others see the pose (being built 7 Nov) |
| 1 | WeatherService and the seven presets, suppression and shell shock, battle ambience, on the current valley | Screenshots of each preset from the same spot; phone check with shadows off |
| 2 | Varsk Valley blockout plus Conquest on it, bots on both sides | Bots play a full match alone; run and drive times measured |
| 3 | Deploy screen, point readability, jeep and truck, the lobby card | A player can spawn, drive to a point, take it and win |
| 4 | Art: Blender building kit and hero models, terrain paint, real trees, MaterialVariants | Composition pass from the spawns and every point |
| 5 | Classes, engineer building, match events, compass and spotting, squads | Each system tested in Play |
| 6 | Phone budget pass, then a live test with 2+ players | Two matches with real players, deaths per minute measured |

Each phase ends with a sync back to `last-light-game`, a commit, and the owner saving and publishing the campaign
place.

## 8. Phase 0: stances (owner, 7 Nov: "this is basics")

- **Tap crouch** (C or Left Ctrl, gamepad B, the touch Crouch button): standing goes to crouched; crouched or prone
  goes back to standing.
- **Hold crouch** (0.35 s) from standing or crouched: lie down flat on your front, rifle held out in front, head up.
- **Move** while crouched (CrouchSpeed) and while prone (a slow crawl). Turning while prone turns the whole body.
- **Sprint** works only while standing. Holding sprint while crouched or prone does nothing; it no longer stands you up.
- **Jump** from crouched or prone stands you up instead of jumping (as crouch does today).
- **Everyone sees it:** the server poses the body from the character's `Stance` attribute, so other players, the
  server's hit checks and third person all match the camera.
- A sprint slide (tap crouch while sprinting) stays as it is.

## 9. Engine facts the build must respect (fwjelaa vault, checked 7 Nov 2026)

- **Streaming:** StreamingEnabled cannot be switched from a script; set it in Studio. Keep the default radii (min 64,
  target 1024), set ModelStreamingBehavior to Improved and StreamOutBehavior to Opportunistic. Buildings and
  anything players interact with are Atomic models. Only the three far landmarks are Persistent (Persistent on many
  models is a known mistake). Call `Player:RequestStreamAroundAsync` before every deploy-screen spawn and keep a
  streamed-in road collider ahead of fast vehicles. A streamed-out part has its parent set to nil, so scripts must
  not hold on to map parts across stream-out.
- **Meshes:** draw calls cost a phone more than triangles: reuse a few kit meshes and textures so they batch. Check in
  Studio whether `Workspace.MeshStreamingAndImprovedLoDs` is available (April 2026); when it is on, RenderFidelity
  is ignored.
- **Lighting:** `Lighting.Technology` is deprecated and errors from scripts; use LightingStyle Realistic with
  PrioritizeLightingQuality on (the old Future). Light.Range tops out at 120. Shadows only on hero lights.
- **Weather:** the server picks the state and writes attributes; clients blend Lighting and Atmosphere, with the
  blend computed from `workspace:GetServerTimeNow()` so every client fades at the same moment. Never tween Lighting
  on the server. Falling snow is a camera-local slab of emitters (LockedToPart off) moved to the camera every frame.
  Gameplay (bot sight, sound range) reads the server's weather state, never the client's, so removing the snow
  locally gives no edge. Atmosphere density hides distance but does not save any drawing cost.
- **Discovery (June and October 2026 changes):** the algorithm now counts 28 days of retention (Day 1, 2 to 7, 8 to
  28) and first-play bounce under 60 seconds and 61 to 180 seconds, from organic joins only. So the first match
  must be fun inside a minute: a phone player must be in a fight within 30 seconds of joining. Home needs a custom
  16:9 thumbnail since 19 October.

## 10. Open questions for the owner (only taste, everything else is decided above)

- The map name "Varsk Valley" and the point names can change freely.
- Server size: 40 (20 v 20) is the plan. Roblox allows more, but 40 bodies is the tested AI budget.
