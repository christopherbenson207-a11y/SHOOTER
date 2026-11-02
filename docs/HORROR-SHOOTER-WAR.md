# Last Light: WAR, Operation Last Light (1 Nov 2026 night: as built at the top, the first brief below)

## 2 Nov: the new map (all eight zones built)

**State (2 Nov, evening):** all eight zones are built in Studio from their scripts: CRASH (161 parts), FARM (371),
DEPOT (409), RAIL (345), TOWN (615), PLAZA (581), YARDS (448), BASIN (303). Each zone's audit is clean. The
whole-map check (`zones/CHECKS.lua`) passes: 164 of 164 soldier walks, 79 spots clear, 3,932 parts in Map
(trees, bounds, spots and dressing included), 68 lights (8 with shadows), 19 emitters. `zones/OPTIMIZE.lua` has
run on every zone. Battle reinforcement spots: all five `_Rear` groups have 4 each (`M3_LZ_Rear` behind the basin's
north outcrops and sheepfold), and all are in `map/Spots.lua`. Fixes made by hand after the zone builds (not in the
zone scripts): CRASH `FieldWallEast` and `FieldWallEastReturn` close the walk round the wall's east end to the
boundary; TOWN `BackWallWestEnd` and `BackWallEastEnd` carry the z 73 back walls out to the boundary at x ±85; and
two terrain scoops clear the drift by `M3_LZ_05` and the rock by `M3_LZ_08`. Known, left as is: three north-road
wave spawns can be seen straight up the road from the plaza corner. TOWN's lookout tower is at y 130, and its café
wing and H2 are lowered so the tower can see the plaza. No zone has had an independent review. Not Play-tested
and not saved: press Ctrl+S and publish.

**Next: the map as Blender meshes** (owner, 2 Nov: "u can make the entire maps in blender and ill import"). The
pipeline is `horror-shooter/war/map/BLENDER-PIPELINE.md`. FARM is the pilot; the hand-modelled kit is
`war/map/blender/build_kit.py`, and the import steps are in `war/map/blender/out/IMPORT-ME.md`.
**FARM is swapped (2 Nov night):** the owner imported `FARM.fbx` into `ServerStorage.MapAssets.Mesh.FARM`, and
`out/swap_FARM.luau` ran: the import turn was -180, 65 meshes were placed, 129 collision boxes hidden (`MeshProxy`)
and 113 decor parts deleted, leaving 191 visible parts out of 368. The whole-map check still passes (164 of 164
walks, 79 spots). Until the battle session's `CoverMap.solid()` accepts `MeshProxy`, FARM's hidden boxes don't
count as battle cover. Running `zones/FARM.lua` again restores the all-parts FARM.

The old toolbox battlefield (`Map.Battlefield`, 6,370 parts) is gone. The new valley is built zone by zone from
re-runnable scripts. The layout contract is `horror-shooter/war/map/MAP-PLAN.md`; the art direction, zone footprints,
budgets and briefs are in `horror-shooter/war/map/zones/BUILDER-GUIDE.md`; each zone's script is
`horror-shooter/war/map/zones/<ZONE>.lua` (CRASH, FARM, DEPOT, RAIL, TOWN, PLAZA, YARDS, BASIN), built into
`workspace.Map.Valley.<ZONE>`. `zones/CHECKS.lua` is the whole-map check (every objective walk, every spot, the budget).

Done and tested before the zones:
- **Explosive drums** (`ServerScriptService.ExplosivesServer`, `GameConfig.Explosives`): any model tagged `Explosive`
  (MapKit's `Kit.fuelDrum`: a signal-red drum with a pale band). Shots soak 60 damage, then it blows: 220 damage to
  enemies within 16 studs (falling to 30% at the edge) through MobReactions, so kills and gore count as the shooter's;
  allies and players in reach get hurt too (players 70); drums within 12 studs chain 0.2 s later. Fire, smoke, sparks
  and a flash, the `World/Explosion` sound, and the drum's pieces fly and fade after 20 s. Tested in Play.
- **Soldiers and doors:** soldiers can't open doors, so `Soldier`'s path costs treat door slabs as walls
  (`Costs = { Door = math.huge }`); doors never hang on a doorway soldiers need.
- **Hard cover by default:** MapKit's `Kit.part` marks SmoothPlastic and Plastic parts `Indestructible` (marks only),
  unless built with `Soft = true`; wood, planks and crates stay breakable.
- **The downed bird** sat floating; it is re-posed upright, nose 5° down, belly 1.3 studs in the snow (pivot about
  (-19.5, 113.2, 289.5); its old pose is the attribute `PoseBefore`), with terrain snow berms and drifts round it.
- **Supply crates** moved off enemy spots: the plaza's to (0, 10), the yards' to (-100, -160).

## As built (1 Nov night): the campaign is its own place

The brief below was the first version, set in the desert town. What was built instead is a separate place on a winter
war map, retextured and rebuilt. The day's full notes, the tests and the owner's to-do list are in
HORROR-SHOOTER-HANDOFF.md's top section. Local mirrors of the scripts are in `horror-shooter/war/`.

- **Place:** Operation Last Light, placeId 78870312741411, in the lobby's universe. The lobby menu's CAMPAIGN row
  teleports the party there (`GameConfig.War.Campaign.PlaceId`), and the end of the run teleports everyone back
  (`LobbyPlaceId`). WarServer sets the workspace attribute Campaign, so the place's menu deploys players straight in.
- **Map:** `Map.Battlefield` under snow, with `Map.WarDressing` on top: the RelayMast in the plaza, the LZPad and its
  CallStation, the burning DownedBird at the start, SupplyCrates (ammo, at most once per player every `AmmoGap` 20 s),
  sandbags, cars, wrecks, street lamps and fire barrels. The spots are the parts in `Map.War`.
- **Missions (ServerScriptService.WarServer):**
  - HOT DROP: up from the downed bird, a contact on the road, then clear the depot.
  - SIGNAL: take the plaza, patch into the mast (hold E for 3 s), then stay within 40 studs while it transmits for
    90 s. Squads of four come from `M2_Road` at 4, 25, 50 and 70 s, and the heavy at 40 s.
  - LAST LIGHT: push through the yards, clear the LZ, call the bird (hold E for 1.5 s), hold the pad for the 45 s it
    is inbound (squads at 3, 16 and 30 s, the heavy at 22 s), then GRAB the ladder.
  - Each mission is steps with checkpoints. If every player is down at once, the step restarts from its checkpoint.
    The dead respawn near the squad after `War.RespawnTime` (10 s).
  - Pay: 150, 200 and 300 Scrip for the three missions, plus 250 for getting out. It goes through `Profile.Earn`, so
    VIP players get +20%.
- **Squad HOUND:** the NPC soldiers REYES, OKAFOR and HASKINS (`War.Squad`) fill the slots no player holds. A player
  joining mid-run takes the last NPC's place where it stands, and a player leaving gives it back.
- **Enemies:** Lamplighters (rigs HostileA and HostileB, with AKs) and the Heavy (HeavyA, 1.15 scale, 650 health, an
  80-round gun). All soldiers run on `ServerStorage.Modules.Soldier`. The rigs are retextured Toolbox models in
  `ServerStorage.SoldierRigs`.
- **HUD:** WarServer sets workspace attributes: WarMission (the mission's name), WarObjective (its one small line),
  Objective (the point WarClient marks) and WarProgress (how far the mast has transmitted).
- **Kit:** the AK in hand, plus the Pistol and a Bandage, from this place's `GameConfig.Loadout` order and
  `Inventory.Start`.
- **Changed from the brief below:** there's no police station and no tower codes (mission 1 ends at the depot), the
  relay mast replaces the tower and transmits for 90 s, and there's no Beacon and no dog in this place (BeaconServer
  and DogServer are off), so mission 3 is a straight LZ hold. The radio is still RadioVoice text-to-speech, because
  the ElevenLabs MCP still fails to connect.
- **Not tested yet:** two or more players (the slot takeover), the live teleports both ways, and real purchases.

## The first brief (the town version, before the campaign got its own place)

The owner's ask: make Last Light play and feel like Call of Duty Modern Warfare 3 / Black Ops 2. That means a
story-like war mode, NPC enemy soldiers, an NPC squad whose slots joining players take over, and an MW3/BO2-style
menu, built on the systems the game already has. This file is both the prompt for the session that builds it and the
plan. Start here, then HORROR-SHOOTER-HANDOFF.md's top section.

## 0. Rules that still hold (owner, memory)

- UI is authored PNG art or authored Studio UI; never frames or labels built by script. Scripts only change text,
  visibility and images.
- One HUD Notice line, no overlay text, no damage counters, no objective lists. Objectives are carried by the radio
  voice, a world marker (one PNG diamond in a BillboardGui) and world glows.
- Game-specific models are made in Blender (the owner imports them, or use computer use: Home > Import 3D). Toolbox
  assets are stripped of scripts and retextured.
- Zombie blood stays green. Human enemies bleed dark, not red-bright: a new Gore colour set.
- Delete, don't archive. Back up scripts to `ServerStorage._Backups.<Name>_<date>_beforeWar` before editing.
- Never stop the owner's Play. Remind them to press Ctrl+S.

## 1. What already exists and gets reused (checked 1 Nov)

| Need | Existing system | Seam |
|---|---|---|
| Shooting human enemies | GunServer hits anything tagged `Enemy` and calls `MobReactions.Hit` | Tag soldiers `Enemy`, give them `MobType = "Lamplighter"` |
| Hit reactions, ragdoll death, corpse fade | MobReactions, driven by `GameConfig.Mobs[MobType]` | Add `GameConfig.Mobs.Lamplighter`: limbs that never tear (`Dangles = false`, high limb health), Head `Kills`, dark Gore colours, own Sounds folder |
| Points for kills | `EnemyHit` event to Points and GlowDrops | Works as is |
| Damage to players | `PlayerHealth.Damage(player, amount, fromPos)` | Soldier bullets call it |
| Zombies | MatchServer `addZombie`, `spawnZombie`, `wake`, MobAI.Hunt | MobAI `nearestPlayer` only sees players: extend it to models tagged `Ally`; `MobAttack.Swing` takes a player: add a branch that damages an ally humanoid |
| Voice | RadioVoice speaks any `Remotes.Match "Radio", text, key` through Roblox text-to-speech with a radio filter | The commander's lines need no new code. Squad chatter: a positional TTS chain per ally (AudioTextToSpeech, AudioEmitter on the head) |
| Helicopter out | Outbreak `callBird(pad)`, `heliTick`, `escapeOutbreak`, pads tagged LandingPad, the new CallStation model | Mission 3 reuses all of it |
| Insertion | Outbreak `outbreakDrop`, insertions with wrecks and crates | Mission 1's hot drop |
| The Beacon | BeaconServer, `workspace.Breakout`, `RevealUntil` | Mission 3's wake |
| Menu | StarterGui.Menu (authored): a 3D night road, logo, left list of heavy words, amber bar on hover. Already the MW3 shape | Restructure, don't rebuild |
| Joining mid-match | MenuServer: a run going keeps its mode, you join it | War adds the slot takeover |

## 2. The mode: WAR, "Operation Last Light"

Co-op campaign for 1 to 4. A squad of four always: you plus NPC allies until players fill the slots. 15 to 20 minutes,
three missions played back to back in the town, a checkpoint between each.

**The squad, callsign HOUND:** Sgt. Reyes (leader, says the orders), Cpl. Okafor (rifle), Pvt. Haskins (shotgun,
the talker), and the police dog. Players take slots from the back: Haskins first, then Okafor, then Reyes. A player
who leaves gives their slot back to the NPC, who spawns where they stood.

**The enemy, the Lamplighters:** a militia that follows the Beacon. Gas masks, dark coats, a caged lamp on the chest
(the lamp is a weak spot: shoot it and they burn). Zombies ignore them because they carry the Beacon's light. Rifles,
some shotguns; from mission 2, a heavy with a big lamp and a drum gun.

**Mission 1: HOT DROP (5 min).** The helicopter drops HOUND on Main Street (Outbreak's insertion). Zombies on the wreck,
then Lamplighters fire from the Police Station windows. Push up the street, clear the station (10 to 12 Lamplighters),
hold E on the dispatch desk for the tower codes. Radio: "Codes are in the station. Get them."

**Mission 2: SIGNAL (6 min).** Up the hill to the radio tower. Fit the codes (hold E on the cabinet; the four lamps
light as the parts already do), then hold the tower 120 s while it transmits: zombie waves up the slope, two
Lamplighter squads from the road, the heavy at 60 s.

**Mission 3: LAST LIGHT (5 to 7 min).** The broadcast wakes the Beacon (reveal for everyone). Get to a CallStation,
call the bird, hold the pad 60 s against everything, GRAB the ladder. Escape = the existing rescue cutscene and menu.

**Fail and checkpoints:** a downed player is revived by an ally NPC or a player. Allies never die: at 0 they kneel
for 15 s, then get up. The whole human squad down = restart the current mission from its checkpoint (not the op).

## 3. Systems to build, in order (each tested before the next)

1. **`ServerStorage.Modules.Soldier`**: one NPC soldier, ally or enemy.
   - Rig: `Players:CreateHumanoidModelFromDescription` R15. Allies wear the SWAT uniform (`GameConfig.Match.Uniform`);
     Lamplighters wear their own shirt and pants, plus the Blender gas mask and chest lamp (to model: `build_lamplighter.py`).
     Set `Limb` attributes on the parts so MobReactions reads them.
   - Gun: clone the matching gun model from the existing guns, welded to the right hand. Arms aimed by Motor6D C0
     each step (procedural, like MobPose), default Animate for walking.
   - Firing: server raycast from the muzzle with spread by range and movement, bursts, reloads. Effects through the
     existing `Remotes.ShotFx` path so CombatFx draws tracers, flash and sound. Damage: `PlayerHealth.Damage` on
     players, `MobReactions.Hit` on zombies and enemies, never on its own side.
   - Brain (0.2 s tick): pick the nearest visible foe; move to the assigned spot (allies: a formation slot around the
     squad leader or the objective; enemies: their defend spot); take cover at the nearest `Cover` tagged part when
     hit or reloading; peek and burst. Pathfinding with MobAI's costs.
2. **MobAI and MobAttack:** zombies hunt `Ally` tagged models as well as players.
3. **`GameConfig.Mobs.Lamplighter`, `GameConfig.War`** (squad names, missions, counts, times, lines) and
   `GameConfig.Modes.War = { War = true, NoBreakout = true }`, `Menu.Modes` gets War.
4. **`ServerStorage.Modules.War`**: the mission script. `War.Run(ctx)`, where ctx is MatchServer's helpers (addZombie,
   spawnZombie, wake, radio, callBird, heliTick, outbreakDrop, inMatch, isAlive). MatchServer gets
   `elseif mode.War then playWar()` next to Outbreak.
5. **Slots:** PlayerAdded or Play during War: the player spawns on an ally NPC, which is removed. PlayerRemoving: the
   NPC comes back. Squad names on `workspace` attributes (`Squad1..4`) for the menu.
6. **Objective marker:** one Blender-rendered diamond PNG (upload with `upload_image`) on a BillboardGui at
   `workspace.Objective` (a Vector3 attribute), and the Notice line once per objective.
7. **Menu (MW3/BO2):** in Edit, clone the authored buttons. Main becomes CAMPAIGN / ZOMBIES / SHOP / SETTINGS. ZOMBIES
   opens the existing Modes page (Defend, Outbreak, Nightmare, Endless). CAMPAIGN opens a new page: the operation's
   name, the three missions as rows, the four squad slots (NPC callsign or player name), DEPLOY. The backdrop camera
   moves to the squad standing by the burning wreck on Main Street.
8. **Voice:** commander lines through RadioVoice now. Squad chatter (Contact! Reloading! Man down!) through positional
   TTS per ally. The ElevenLabs MCP failed to connect on 1 Nov; when it works, `horror-shooter/voice/gen_voices.py`
   records real lines and VoiceManifest replaces the TTS.
9. **Models (Blender, then Import 3D):** Lamplighter gas mask + chest lamp, the heavy's drum gun, the dispatch desk,
   cover pieces (sandbags, jersey barriers) for the station yard and the hill.

## 4. Not in this pass

- A new place: not needed. The town has every location the three missions use. A second operation (the Dam, the
  Hospital) would be its own place in the experience, teleported to from the CAMPAIGN page.
- Killstreaks, perks, a rank system: MW3 multiplayer features, not campaign. Later, if the owner wants them.
