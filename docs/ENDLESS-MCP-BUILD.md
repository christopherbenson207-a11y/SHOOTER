# Endless reference: build it in Studio with MCP

This file is everything a local Claude session needs to build the Endless reference place in Roblox
Studio through MCP, without Rojo: what it is, how to set the place up, every script with its exact
place in the Explorer, its type and its full code, and what to check when you press Play.
It is generated from `src/endless/` by `python tools/endless_guide.py`, so the code below is exactly
the code in the repo. The design write-up is `docs/ENDLESS-REFERENCE.md`; a browser version you can
play straight away is `docs/endless/endless-test.html`.

**Nothing in Studio has been playtested yet.** The scripts were written in a cloud session with no
Studio. They passed a layout checker, a syntax and name checker and three code reviews (about twenty
bugs found and fixed), but the first Play in Studio is the real test.

## What it is

A standalone place that plays an Endless mode from start to finish, as reference code for building
Endless into the zombie mode. It follows the owner's brief: the Mortuus video (roguelike Call of Duty
Zombies) with a weapon randomizer, in a huge house. Everything is built by the scripts (the house,
the zombies and the guns are plain parts), so it runs in an empty place.

- **Rounds** use Call of Duty's numbers (6, 8, 13, 18, 24 zombies for the first five rounds alone;
  health 150, +100 a round to round 9, then x1.1). Brutes from round 8, crawlers from round 12, runners
  from round 4. At most 24 zombies up at once.
- **Zombies** rise in the yard outside a boarded window, tear the boards off and climb in (upper windows:
  they climb the wall first), or claw up through a floor hatch. Only rooms the squad has opened send
  zombies. They lose arms and legs to gunfire (heads never), and their blood is green.
- **Points:** 10 a hit, 50 a kill, 100 a headshot kill, 130 a knife kill, 10 a board nailed back.
- **Spending:** doors and stair gates (750 to 1500, prices move each run), chalk guns on the walls (buy
  again for ammo), the weapon randomizer (950: a random gun you don't carry; after four spins the skull
  can move it), five perk machines behind a power switch in the cellar, and the gun ascension altar
  (pick one of three boosts, up to eight times a gun).
- **Relics** after every round (three on the floor, take one), **power-ups** from kills, **going down**
  and being revived, and a new draw of the box, perks, wall guns, altar, switch and prices every run.

## Set the place up (once)

1. Make a new place in the Last Light universe (Creator Hub, or Studio: File > New > Baseplate, then
   File > Publish to Roblox As, Last Light, new place). Any empty place works for a test.
2. Recommended: set `Workspace.StreamingEnabled` to false (new places have it on).
3. Optional: set `Lighting.Technology` to Future (lamps throw shadows).
4. Optional but strongly recommended: copy these two from the lobby place into this place:
   - `StarterGui.HUD` (the authored HUD: round, points, ammo). Without it there is no HUD.
   - `ReplicatedStorage.Assets.Sounds` (the zombie mode's sounds). Without it the place is silent.
5. The Baseplate and SpawnLocation can stay: the server deletes them when it starts.

## How to build it with MCP

Give the local session this file and ask it to build every script below. For each script:

1. Make any missing folders on the way (both `Endless` folders are plain `Folder`s).
2. Create an instance of the listed class (ModuleScript, Script or LocalScript) with the listed Name
   at the listed path.
3. Set its `Source` to the code block, exactly as written (for long sources, the MCP tool that edits
   script source, or `ScriptEditorService:UpdateSourceAsync`, both work).

Build in the order of the table (modules before the scripts that require them). `Health` is meant to
be empty apart from its comment. Nothing else is needed: no models, no assets, no Rojo.

A Luau snippet for the folders (run it in the Command Bar or with the MCP run-code tool):

```lua
local function folder(parent, name)
	local f = parent:FindFirstChild(name) or Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
folder(game:GetService("ReplicatedStorage"), "Endless")
folder(game:GetService("ServerStorage"), "Endless")
```

## The scripts

| # | Explorer path | Class | What it does |
|---|---|---|---|
| 1 | `ReplicatedStorage.Endless.Config` | ModuleScript | Every number: rounds, zombies, players, points, guns, perks, altar, relics, power-ups, the house. |
| 2 | `ReplicatedStorage.Endless.Net` | ModuleScript | Makes and finds the three RemoteEvents (Weapon, Fx, Hud) in ReplicatedStorage.Endless.Remotes. |
| 3 | `ReplicatedStorage.Endless.Sfx` | ModuleScript | Plays sound cues from ReplicatedStorage.Assets.Sounds (the lobby's folder); silent without it. |
| 4 | `ReplicatedStorage.Endless.Weapons` | ModuleScript | A gun's numbers for one player: base stats plus altar boosts, perks and relics. |
| 5 | `ReplicatedStorage.Endless.GunModel` | ModuleScript | Builds every gun's look from parts (no assets). |
| 6 | `ServerStorage.Endless.Util` | ModuleScript | Signal, Maid (cleanup), ProximityPrompt maker, shuffle, weighted pick. |
| 7 | `ServerStorage.Endless.HouseLayout` | ModuleScript | The map as data: four levels of ASCII plans, doors, arches, windows, hatches, stairs, spots. |
| 8 | `ServerStorage.Endless.HouseBuilder` | ModuleScript | Builds the house from HouseLayout out of parts, every run, and returns the House table. |
| 9 | `ServerStorage.Endless.Economy` | ModuleScript | Points (player attribute Points), Double Pay and Scavenger multipliers, run stats. |
| 10 | `ServerStorage.Endless.Survivors` | ModuleScript | Player lives: spawning, regen, going down, revives, bleed-out, self-revive. |
| 11 | `ServerStorage.Endless.Arsenal` | ModuleScript | Guns as Tools, slots, ammo, the server's checks on every shot, the knife. |
| 12 | `ServerStorage.Endless.Windows` | ModuleScript | Boarded windows: zombies tear boards off, players hold Repair to nail them back. |
| 13 | `ServerStorage.Endless.Horde` | ModuleScript | The zombies: R6 rig from blocks, rising, windows, hunting, the swipe, limbs, ragdoll. |
| 14 | `ServerStorage.Endless.Doors` | ModuleScript | Doors and stair gates bought with points; opening one opens its zones. |
| 15 | `ServerStorage.Endless.Randomizer` | ModuleScript | The weapon randomizer (mystery box): spin, take, the skull that moves it. |
| 16 | `ServerStorage.Endless.WallBuys` | ModuleScript | Chalk guns on the walls: buy the gun, or its ammo. |
| 17 | `ServerStorage.Endless.Perks` | ModuleScript | The five perk machines and the power switch. |
| 18 | `ServerStorage.Endless.Choices` | ModuleScript | Pick-one sigils on the floor (relics and altar boosts). |
| 19 | `ServerStorage.Endless.Relics` | ModuleScript | The relic draft after every round and what each relic does. |
| 20 | `ServerStorage.Endless.Altar` | ModuleScript | Gun ascension: pay, the gun is taken, pick one of three boosts, it comes back stronger. |
| 21 | `ServerStorage.Endless.PowerUps` | ModuleScript | Drops: Resupply, Reaper, Double Pay, Purge, Hammer and Nails. |
| 22 | `ServerStorage.Endless.Director` | ModuleScript | The rounds: how many zombies, how tough, how fast, from where; intermissions. |
| 23 | `StarterPlayer.StarterCharacterScripts.Health` | Script | Empty on purpose: replaces Roblox's default health regen script. |
| 24 | `StarterPlayer.StarterPlayerScripts.EndlessFx` | LocalScript | Client: zombie poses, green blood, power-up spin, lamp flicker, prompt wording, spectating. |
| 25 | `StarterPlayer.StarterPlayerScripts.EndlessHud` | LocalScript | Client: drives the lobby's authored HUD by name (builds no UI). |
| 26 | `StarterPlayer.StarterPlayerScripts.EndlessClient` | LocalScript | Client: first-person guns, PC/gamepad/touch input, recoil, aim assist on touch and gamepad. |
| 27 | `ServerScriptService.EndlessServer` | Script | Boot (lighting, collision groups, remotes) and the run loop; wires the systems together. |

## What to check when you press Play (solo)

Studio test switches (workspace attributes, read when a run starts): `EndlessStartRound` (number),
`EndlessStartPoints` (number), `EndlessPower` (bool), `EndlessGod` (bool), `EndlessOpenAll` (bool).

1. The Output shows no red errors. The baseplate is gone and Blackwood Manor stands with a walled yard.
2. You spawn in the foyer, first person, with the Service Pistol, 8/80 ammo and 500 points.
3. 15 seconds later round 1 starts (HUD: ROUND 1, zombies left). About six zombies rise outside the
   foyer windows, tear the boards off one by one and climb in. Shoot them: each hit pays 10, a kill 50.
4. Hold E at a torn window: the boards go back and pay 10 each.
5. Doors show "Open Door (price)". Buy the living room door (about 750): it swings open and zombies now
   also come through the living room windows.
6. Wall guns: the Carbine and Bolt Rifle chalk drawings in the foyer sell the gun; buying again sells ammo.
7. Find the chest with the pale beam (the weapon randomizer, 950): guns flick past, one settles, hold E
   to take it. You never get a gun you already carry.
8. Go down to the cellar (pantry gate) and turn on the power: the lamps change from dim red to warm, the
   perk machines light up and the altar rune glows.
9. Buy a perk (Bulwark Brew: health 250). Go down: every perk is lost.
10. At the altar, hold a gun and pay: it is taken, three candles rise; take one and the gun comes back
    with a star on the HUD and a tint.
11. After each round three relic candles stand in your room: take one; HUD line names it.
12. Kills sometimes drop a glowing power-up: walk over it (RESUPPLY, REAPER, DOUBLE PAY, PURGE, HAMMER AND NAILS).
13. Let the zombies get you: you go down (grey screen). Alone with no Lazarus Draught or Second Wind,
    the run ends: the end screen shows the round reached, and 12 seconds later a new run starts in a
    freshly built house (the box, perks and prices have moved).

If something goes wrong, the useful things to report back are the first red error in the Output and
which step it was.

## Full source (27 scripts, 6975 lines)

### 1. `ReplicatedStorage.Endless.Config` (ModuleScript)

Every number: rounds, zombies, players, points, guns, perks, altar, relics, power-ups, the house.

```lua
-- Every number of the Endless reference, read by the server and the clients
-- (docs/ENDLESS-REFERENCE.md). The loop is Call of Duty Zombies' rounds with Mortuus' roguelike
-- layer: survive a round, spend points on doors, guns, perks and the weapon randomizer, pick a relic
-- after every round, feed guns to the ascension altar, and keep going until everyone is down.

local Config = {}

-- Studio only (RunService:IsStudio()). Workspace attributes, read when a run starts:
--   EndlessStartRound (number)   start at this round
--   EndlessStartPoints (number)  everyone starts with this many points
--   EndlessPower (bool)          the power is on from the start
--   EndlessGod (bool)            nothing hurts players
--   EndlessOpenAll (bool)        every door starts open
Config.Debug = {}

-- The run -----------------------------------------------------------------------------------------
-- A run starts when the first player joins: everyone spawns in the start room with StartPoints and
-- the Start gun, round 1 begins FirstDelay seconds later. Between rounds there are Intermission
-- seconds (long enough to take this round's relic). When every player in the run is down or dead
-- the run is over: GameOverTime seconds on the end screen, then the house is built again (a new
-- draw of every spot) and a new run starts. Players who join mid-run, and the dead, come back at
-- the next intermission.
Config.Run = {
	FirstDelay = 15,
	Intermission = 18,
	GameOverTime = 12,
	StartPoints = 500,
	-- After the house is rebuilt, players spawn this long before the first-round timer starts.
	SpawnSettle = 1.5,
}

-- Rounds (Call of Duty Zombies' numbers) ------------------------------------------------------------
-- How many zombies a round sends:
--   mult = max(1, round / 5), and from round 10 on mult x (round x 0.15)
--   total = Base + per-player part, where the per-player part is PerPlayer x mult x (players - 1),
--   or PerPlayer x 0.5 x mult playing alone.
--   Rounds 1 to 5 take Early[round] of that (6, 8, 13, 18, 24 alone).
-- Zombie health: Base, PerRound more each round up to LinearTo, then x Late a round.
-- Spawns: SpawnGap seconds apart on round 1, x GapMult every round, never under GapMin. At most
-- MaxAlive stand at once (the rest wait their turn).
-- Speed: from Runners.From on, a share of each round runs: Step more every round, up to Max.
Config.Rounds = {
	Count = { Base = 24, PerPlayer = 6, Early = { 0.25, 0.3, 0.5, 0.7, 0.9 } },
	Health = { Base = 150, PerRound = 100, LinearTo = 9, Late = 1.1 },
	MaxAlive = 24,
	SpawnGap = 2,
	GapMult = 0.95,
	GapMin = 0.15,
	WalkSpeed = NumberRange.new(5.5, 7.5),
	RunSpeed = NumberRange.new(12.5, 14.5),
	Runners = { From = 4, Step = 0.12, Max = 0.9 },
}

-- Specials (Mortuus brings its Juggernaut, Lope and Skitter in late rounds; these are ours):
--   Brute: from round From, Count of them a round (one more every Per rounds, at most Max). A big,
--     slow zombie with Health x the round's health; worth Points on the kill.
--   Crawler: from round From, Share of the spawns come in already on their arms (legs gone):
--     low, quick and hard to hit. Any zombie that loses both legs crawls too.
Config.Specials = {
	Brute = { From = 8, Per = 8, Max = 3, Health = 6, Speed = 6, Damage = 70, Scale = 1.35, Points = 300 },
	Crawler = { From = 12, Share = 0.12, Speed = 10, Health = 0.6 },
}

-- Zombies ---------------------------------------------------------------------------------------
-- Melee is Call of Duty's swipe: stop inside Attack.Range, wind up, swing; it lands if you are still
-- within Reach and inside Arc degrees in front of it. Damage per swing (players have MaxHealth 100,
-- so three swipes put you down; Bulwark Brew makes it six). An arm torn off takes ArmLost off the
-- damage. Limbs: an arm tears off after ArmShare of the zombie's max health has gone into it, a leg
-- after LegShare; heads never tear (owner: less gore on faces). Both legs gone and it crawls at
-- CrawlSpeed x its speed. Blood is green (owner rule).
-- Navigation: close and in plain sight it walks straight at you; otherwise it follows a path,
-- recomputed every Repath seconds. A zombie that makes under StuckDistance of headway in
-- StuckTime shuffles aside; one that makes none for LostTime is put back in the round's queue.
-- Windows: it tears a board off every BreakDelay, one zombie climbs a window at a time, the climb
-- over the sill takes ClimbTime (plus ClimbPerStud for every stud it climbs a wall to an upper
-- window). Spawning, it rises out of the ground (or the hatch) over Emerge seconds.
Config.Zombie = {
	Attack = { Range = 4, Reach = 5.5, Arc = 100, Windup = 0.5, Swing = 0.15, Cooldown = 0.8, Damage = 45, ArmLost = 0.6 },
	ArmShare = 0.4,
	LegShare = 0.45,
	CrawlSpeed = 0.55,
	Navigation = {
		Tick = 0.15,
		DirectRange = 30,
		Repath = 1,
		StuckTime = 1.4,
		StuckDistance = 0.8,
		LostTime = 25,
	},
	Window = { BreakDelay = NumberRange.new(0.9, 1.5), ClimbTime = 0.9, ClimbPerStud = 0.06, Distract = 12 },
	Emerge = 1.1,
	-- Where it waits outside before walking up to its window (studs out from the wall).
	SpawnOut = 26,
	CorpseTime = 6,
	-- The look: skin, shirt and trousers are picked from these.
	Skin = { Color3.fromRGB(122, 140, 104), Color3.fromRGB(104, 118, 96), Color3.fromRGB(136, 132, 112), Color3.fromRGB(94, 110, 92) },
	Shirt = { Color3.fromRGB(70, 62, 58), Color3.fromRGB(88, 78, 60), Color3.fromRGB(58, 66, 78), Color3.fromRGB(96, 52, 48), Color3.fromRGB(110, 106, 96) },
	Pants = { Color3.fromRGB(46, 44, 50), Color3.fromRGB(60, 52, 44), Color3.fromRGB(40, 48, 60), Color3.fromRGB(70, 66, 58) },
	Eyes = Color3.fromRGB(255, 196, 90),
	RunnerEyes = Color3.fromRGB(255, 70, 50),
	Blood = Color3.fromRGB(96, 168, 54),
	-- Sound cues (Sfx paths, the lobby's ReplicatedStorage.Assets.Sounds layout).
	Sounds = "Mobs/TestZombie",
}

-- Players ---------------------------------------------------------------------------------------
-- Health comes back RegenDelay seconds after the last hit, at RegenRate a second. Hits closer
-- together than HitGrace count once. Nothing hurts you for SpawnGrace after spawning.
-- Down (Call of Duty's last stand): at no health you go down instead of dying. You crawl at
-- Downed.Speed, can't shoot, lose your perks and PointsLost of your points. A teammate holds the
-- interact key for ReviveTime next to you to get you up with ReviveHealth of your health. After
-- BleedOut seconds you die and come back at the next intermission with the Start gun. Playing
-- alone with a self-revive (Lazarus Draught, Second Wind) you get up by yourself after SelfReviveTime.
Config.Player = {
	MaxHealth = 100,
	RegenDelay = 4,
	RegenRate = 45,
	HitGrace = 0.35,
	SpawnGrace = 3,
	WalkSpeed = 16,
	Downed = {
		BleedOut = 30,
		ReviveTime = 4,
		ReviveRange = 8,
		ReviveHealth = 0.5,
		Speed = 3,
		PointsLost = 0.05,
		SelfReviveTime = 4,
	},
	Fov = 72,
}

-- Points (Call of Duty Zombies) -------------------------------------------------------------------
-- A hit that doesn't kill pays Hit; a kill pays Kill, a headshot kill HeadKill, a melee kill
-- MeleeKill. Every board you nail back pays Repair, up to RepairCap boards a round.
Config.Points = { Hit = 10, Kill = 50, HeadKill = 100, MeleeKill = 130, Repair = 10, RepairCap = 40 }

-- Doors: the layout's Cost, moved by up to Jitter (in steps of Step) each run so prices are learnt
-- every run. Hold the interact key HoldTime to buy.
Config.Doors = { Jitter = 250, Step = 50, HoldTime = 0.35, OpenTime = 0.6 }

-- Windows: boards per window; hold the interact key HoldTime per board to nail them back on.
Config.Windows = { Boards = 6, HoldTime = 0.45, Range = 9 }

-- Guns ------------------------------------------------------------------------------------------
-- Fire: "Semi" (a click a shot), "Auto" (hold), "Pump"/"Bolt" (a click a shot, slow). Rpm caps the
-- rate. Damage per pellet (Pellets for shotguns), Head is the headshot multiplier. Spread in degrees
-- from the hip and aimed. Pierce: how many zombies one bullet goes through. Range in studs. Price
-- on a wall (ammo is AmmoShare of it). Box: weight in the weapon randomizer (0 = never). Sounds: the
-- lobby's gun sound folder (Crack, Body, Tail, MagOut, MagIn...). Look: the shape GunModel builds.
Config.Weapons = {
	Pistol = { Name = "Service Pistol", Fire = "Semi", Damage = 45, Head = 2.5, Rpm = 400, Mag = 8, Reserve = 80, Reload = 1.6, Spread = { Hip = 1.4, Aim = 0.5 }, Range = 300, Pierce = 1, Box = 0, Sounds = "Guns/Pistol", Look = "Pistol" },
	Revolver = { Name = "Hand Cannon", Fire = "Semi", Damage = 200, Head = 2.5, Rpm = 150, Mag = 6, Reserve = 42, Reload = 2.6, Spread = { Hip = 1.6, Aim = 0.4 }, Range = 400, Pierce = 2, Box = 3, Sounds = "Guns/HandCannon", Look = "Revolver" },
	Carbine = { Name = "Carbine", Fire = "Semi", Damage = 90, Head = 2, Rpm = 450, Mag = 15, Reserve = 120, Reload = 2, Spread = { Hip = 1.4, Aim = 0.25 }, Range = 500, Pierce = 1, Price = 600, Box = 2, Sounds = "Guns/M4", Look = "Carbine" },
	BoltRifle = { Name = "Bolt Rifle", Fire = "Bolt", Damage = 240, Head = 2.5, Rpm = 55, Mag = 5, Reserve = 50, Reload = 2.8, Spread = { Hip = 2, Aim = 0 }, Range = 700, Pierce = 2, Price = 500, Box = 1, Sounds = "Guns/Sniper", Look = "BoltRifle" },
	SMG = { Name = "MP5", Fire = "Auto", Damage = 48, Head = 1.8, Rpm = 800, Mag = 30, Reserve = 180, Reload = 2.2, Spread = { Hip = 2.2, Aim = 0.9 }, Range = 250, Pierce = 1, Price = 1000, Box = 3, Sounds = "Guns/MP5", Look = "SMG" },
	Shotgun = { Name = "Trench Gun", Fire = "Pump", Damage = 40, Pellets = 8, Head = 1.5, Rpm = 75, Mag = 6, Reserve = 54, Reload = 3, Spread = { Hip = 5, Aim = 3.5 }, Range = 90, Pierce = 1, Price = 1200, Box = 3, Sounds = "Guns/Shotgun", Look = "Shotgun" },
	AK = { Name = "AK", Fire = "Auto", Damage = 80, Head = 2, Rpm = 600, Mag = 30, Reserve = 210, Reload = 2.5, Spread = { Hip = 2.4, Aim = 0.4 }, Range = 500, Pierce = 1, Box = 3, Sounds = "Guns/AK", Look = "AK" },
	M4 = { Name = "M4", Fire = "Auto", Damage = 65, Head = 2, Rpm = 750, Mag = 30, Reserve = 240, Reload = 2.2, Spread = { Hip = 2, Aim = 0.3 }, Range = 500, Pierce = 1, Price = 1500, Box = 3, Sounds = "Guns/M4", Look = "M4" },
	BattleRifle = { Name = "SR-25", Fire = "Semi", Damage = 160, Head = 2.2, Rpm = 320, Mag = 20, Reserve = 140, Reload = 2.6, Spread = { Hip = 1.8, Aim = 0.2 }, Range = 650, Pierce = 2, Price = 1800, Box = 3, Sounds = "Guns/SR25", Look = "BattleRifle" },
	Sniper = { Name = "Sniper", Fire = "Bolt", Damage = 700, Head = 3, Rpm = 45, Mag = 5, Reserve = 40, Reload = 3.2, Spread = { Hip = 6, Aim = 0 }, Range = 1000, Pierce = 4, Box = 2, Sounds = "Guns/Sniper", Look = "Sniper", AimFov = 26 },
	LMG = { Name = "M60", Fire = "Auto", Damage = 90, Head = 1.6, Rpm = 550, Mag = 100, Reserve = 400, Reload = 5, Spread = { Hip = 3, Aim = 1.2 }, Range = 500, Pierce = 2, Box = 2, Sounds = "Guns/M60", Look = "LMG" },
	CoachGun = { Name = "Coach Gun", Fire = "Semi", Damage = 50, Pellets = 10, Head = 1.4, Rpm = 300, Mag = 2, Reserve = 40, Reload = 2.4, Spread = { Hip = 6, Aim = 4.5 }, Range = 70, Pierce = 1, Box = 2, Sounds = "Guns/Shotgun", Look = "CoachGun" },
	-- The wonder weapon: rare in the randomizer, one bolt of light through a whole line of them.
	Lumen = { Name = "Lumen Rifle", Fire = "Semi", Damage = 2500, Head = 1, Rpm = 150, Mag = 8, Reserve = 48, Reload = 3, Spread = { Hip = 0.6, Aim = 0 }, Range = 600, Pierce = 12, Box = 1, Sounds = "Guns/Sniper", Look = "Lumen", Beam = Color3.fromRGB(150, 230, 255) },
}

-- The kit and the rules every gun shares.
-- Slots: guns you carry (Packmule Tonic adds one). Taking a new gun with full hands swaps out the
-- one you hold. Melee (Call of Duty's knife): Damage within Range in front of you, Cooldown apart.
-- AimFov: the zoom while aiming (a gun's own AimFov wins). Validation: the server's checks on what a
-- client says it shot (loose enough for 250 ms of ping).
Config.Arsenal = {
	Start = "Pistol",
	Slots = 2,
	AmmoShare = 0.5,
	AscendedAmmo = 2500,
	Melee = { Damage = 150, Range = 6, Arc = 80, Cooldown = 0.7 },
	AimFov = 52,
	Recoil = { Kick = 0.9, Recover = 10 },
	Validation = { MaxOriginOffset = 8, ClaimSlack = 4, RateSlack = 0.7, ConeSlack = 3 },
}

-- Aim assist: none on PC, help on touch and gamepad (owner rule), picked by PreferredInput.
-- Magnet: a shot leaving within MagnetAngle degrees of a zombie bends Strength of the way onto it.
Config.AimAssist = {
	KeyboardAndMouse = { Enabled = false },
	Touch = { Enabled = true, MagnetAngle = 7, Strength = 0.7, Range = 160 },
	Gamepad = { Enabled = true, MagnetAngle = 5, Strength = 0.45, Range = 160 },
}

-- The weapon randomizer (Call of Duty's mystery box) ---------------------------------------------
-- Cost points a spin. The lid opens and guns flick past for RollTime seconds, then it settles on one
-- (weighted by Config.Weapons Box, never a gun you already carry) and holds it OfferTime seconds for
-- you to take. After MinUses spins at one spot, each spin has MoveChance of turning up the skull
-- instead: your points come back, the box shakes, flies off, and after MoveTime it lands on another
-- Box spot of the house, its light beam showing where.
Config.Randomizer = {
	Cost = 950,
	RollTime = 4,
	OfferTime = 12,
	MinUses = 4,
	MoveChance = 0.2,
	MoveTime = 8,
	HoldTime = 0.4,
}

-- Guns on the walls: layout Wall spots with a Weapon keep it; the rest draw from Pool each run.
Config.WallBuys = { Pool = { "SMG", "Shotgun", "M4", "BattleRifle", "Carbine", "BoltRifle" }, HoldTime = 0.4 }

-- Perks (Call of Duty's perk machines, our tonics). They need the power on. At most Limit at once,
-- all lost when you go down. Lazarus Draught costs SoloCost playing alone, where it is a self-revive
-- (SoloUses buys a run); with a team it halves the time you take to revive someone.
Config.Perks = {
	Limit = 4,
	HoldTime = 0.5,
	Order = { "Bulwark", "Quickhand", "TwinFang", "Lazarus", "Packmule" },
	List = {
		Bulwark = { Name = "Bulwark Brew", Text = "250 HEALTH", Cost = 2500, Color = Color3.fromRGB(196, 40, 40), Health = 250 },
		Quickhand = { Name = "Quickhand Tonic", Text = "RELOAD TWICE AS FAST", Cost = 3000, Color = Color3.fromRGB(70, 200, 90), Reload = 0.5 },
		TwinFang = { Name = "Twin Fang Tonic", Text = "FIRE A THIRD FASTER", Cost = 2000, Color = Color3.fromRGB(240, 196, 40), FireRate = 1.33 },
		Lazarus = { Name = "Lazarus Draught", Text = "REVIVE FASTER / GET UP ALONE", Cost = 1500, SoloCost = 500, SoloUses = 3, Color = Color3.fromRGB(70, 140, 240), Revive = 0.5 },
		Packmule = { Name = "Packmule Tonic", Text = "CARRY A THIRD GUN", Cost = 4000, Color = Color3.fromRGB(60, 120, 60), Slots = 3 },
	},
}

-- The power switch: hold HoldTime on it and the house lights come on, the perk machines wake and the
-- ascension altar lights.
Config.Power = { HoldTime = 1.5 }

-- Gun ascension (Mortuus' altar, Call of Duty's Pack-a-Punch): hold your gun to the altar and pay
-- Cost x Growth ^ (times it has ascended). It takes the gun and offers three boosts; pick one (in
-- ChoiceTime, or the first is taken for you) and the gun comes back with it and a full load. At most
-- MaxLevel times a gun. Each level tints the gun (TierColors).
Config.Altar = {
	Cost = 3000,
	Growth = 1.5,
	MaxLevel = 8,
	ChoiceTime = 20,
	HoldTime = 0.6,
	Boosts = {
		Damage = { Name = "Hollow Points", Text = "+35% DAMAGE", Damage = 0.35, Color = Color3.fromRGB(255, 120, 60) },
		Mag = { Name = "Drum Mag", Text = "+50% MAGAZINE", Mag = 0.5, Color = Color3.fromRGB(240, 220, 90) },
		Reserve = { Name = "Bandolier", Text = "+60% RESERVE", Reserve = 0.6, Color = Color3.fromRGB(200, 170, 110) },
		FireRate = { Name = "Hair Trigger", Text = "+25% FIRE RATE", Rpm = 0.25, Color = Color3.fromRGB(255, 80, 160) },
		Reload = { Name = "Slick Hands", Text = "RELOAD 30% FASTER", Reload = 0.3, Color = Color3.fromRGB(90, 220, 140) },
		Pierce = { Name = "Penetrator", Text = "+2 PIERCE", Pierce = 2, Color = Color3.fromRGB(120, 180, 255) },
		Head = { Name = "Executioner", Text = "+50% HEADSHOT", Head = 0.5, Color = Color3.fromRGB(230, 60, 60) },
	},
	TierColors = {
		Color3.fromRGB(120, 200, 255),
		Color3.fromRGB(150, 120, 255),
		Color3.fromRGB(255, 110, 200),
		Color3.fromRGB(255, 170, 60),
		Color3.fromRGB(255, 80, 60),
	},
}

-- Relics (Mortuus' draft after every round; the lobby Endless pool plus four) ------------------------
-- When a round is cleared Offer relics stand on floor sigils in the room most of the squad is in;
-- everyone may take one of them before the next round starts. They stack and last the run, and land
-- as player attributes the systems read (Relic<Stat>; Add per pick, never over Cap).
Config.Relics = {
	Offer = 3,
	HoldTime = 0.6,
	Pool = {
		IronRounds = { Name = "Iron Rounds", Text = "+15% DAMAGE", Stat = "Damage", Add = 0.15, Color = Color3.fromRGB(255, 140, 50) },
		Headhunter = { Name = "Headhunter", Text = "+50% HEADSHOT", Stat = "Head", Add = 0.5, Color = Color3.fromRGB(230, 60, 60) },
		ThickSkin = { Name = "Thick Skin", Text = "+25 HEALTH", Stat = "Health", Add = 25, Color = Color3.fromRGB(90, 200, 120) },
		LeadBelly = { Name = "Lead Belly", Text = "-15% DAMAGE TAKEN", Stat = "Armor", Add = 0.15, Cap = 0.6, Color = Color3.fromRGB(120, 150, 210) },
		FastMend = { Name = "Fast Mend", Text = "HEAL 30% SOONER", Stat = "Regen", Add = 0.3, Cap = 0.75, Color = Color3.fromRGB(200, 240, 150) },
		Scavenger = { Name = "Scavenger", Text = "+30% POINTS", Stat = "Points", Add = 0.3, Color = Color3.fromRGB(255, 200, 80) },
		SecondWind = { Name = "Second Wind", Text = "+1 SELF-REVIVE", Stat = "SelfRevives", Add = 1, Color = Color3.fromRGB(240, 240, 250) },
		DeepPockets = { Name = "Deep Pockets", Text = "+25% RESERVE AMMO", Stat = "Reserve", Add = 0.25, Color = Color3.fromRGB(190, 160, 100) },
		QuickHands = { Name = "Quick Hands", Text = "RELOAD 15% FASTER", Stat = "Reload", Add = 0.15, Cap = 0.5, Color = Color3.fromRGB(110, 230, 200) },
		Fleet = { Name = "Fleet", Text = "+1.5 SPEED", Stat = "Speed", Add = 1.5, Cap = 4.5, Color = Color3.fromRGB(160, 200, 255) },
		Bloodthirst = { Name = "Bloodthirst", Text = "KILLS HEAL 4", Stat = "Leech", Add = 4, Color = Color3.fromRGB(200, 40, 70) },
	},
}

-- Power-ups (Call of Duty's drops, our names) ------------------------------------------------------
-- A kill drops one with Chance, at most PerRound a round; kinds come out of a shuffled bag so each
-- shows up once before any repeats. A drop lasts Life seconds (blinking for the last Blink) and is
-- picked up by walking within Reach. Timed ones last Duration.
Config.PowerUps = {
	Chance = 0.025,
	PerRound = 4,
	Life = 26,
	Blink = 6,
	Reach = 4.5,
	Duration = 30,
	Kinds = {
		Resupply = { Name = "RESUPPLY", Color = Color3.fromRGB(255, 205, 70) },
		Reaper = { Name = "REAPER", Color = Color3.fromRGB(235, 235, 245) },
		DoublePay = { Name = "DOUBLE PAY", Color = Color3.fromRGB(110, 230, 110) },
		Purge = { Name = "PURGE", Color = Color3.fromRGB(255, 110, 40), Points = 400 },
		Nails = { Name = "HAMMER AND NAILS", Color = Color3.fromRGB(190, 140, 90), Points = 200 },
	},
}

-- The house (ServerStorage.Endless.HouseLayout is the plan) ----------------------------------------
-- Cell: studs per plan cell. Story: floor to floor; Slab: floor thickness; Wall: wall thickness.
-- Openings are cut Door/Arch/Window wide and tall (Window.Sill above the floor). Yard: open ground
-- this far round the house, walled in by a stone wall Fence tall.
Config.House = {
	Origin = Vector3.new(0, 0, 0),
	Cell = 10,
	Story = 16,
	Slab = 1,
	Wall = 1,
	Door = { Width = 7, Height = 11, Color = Color3.fromRGB(60, 40, 28) },
	Arch = { Width = 8, Height = 12 },
	Window = { Width = 6, Height = 6, Sill = 3.5 },
	Railing = 3.6,
	Yard = 70,
	Fence = 12,
	Exterior = { Material = Enum.Material.Brick, Color = Color3.fromRGB(78, 54, 46) },
	Trim = { Material = Enum.Material.Slate, Color = Color3.fromRGB(58, 56, 58) },
	Roof = { Material = Enum.Material.Slate, Color = Color3.fromRGB(38, 38, 44) },
	Ground = { Material = Enum.Material.Mud, Color = Color3.fromRGB(46, 50, 38) },
	-- Room styles: wall and floor finish, and the furniture set (HouseBuilder's PROPS).
	Styles = {
		Foyer = { Wall = Color3.fromRGB(104, 34, 38), Floor = Enum.Material.Marble, FloorColor = Color3.fromRGB(176, 170, 160), Props = "Foyer" },
		Hall = { Wall = Color3.fromRGB(70, 72, 52), Floor = Enum.Material.WoodPlanks, FloorColor = Color3.fromRGB(92, 64, 44), Props = "Hall" },
		Living = { Wall = Color3.fromRGB(44, 70, 56), Floor = Enum.Material.WoodPlanks, FloorColor = Color3.fromRGB(100, 72, 50), Props = "Living" },
		Dining = { Wall = Color3.fromRGB(96, 40, 48), Floor = Enum.Material.WoodPlanks, FloorColor = Color3.fromRGB(84, 58, 40), Props = "Dining" },
		Library = { Wall = Color3.fromRGB(70, 50, 36), WallMaterial = Enum.Material.WoodPlanks, Floor = Enum.Material.Fabric, FloorColor = Color3.fromRGB(40, 44, 70), Props = "Library" },
		GreatHall = { Wall = Color3.fromRGB(120, 96, 60), Floor = Enum.Material.WoodPlanks, FloorColor = Color3.fromRGB(110, 78, 50), Props = "GreatHall" },
		Kitchen = { Wall = Color3.fromRGB(176, 170, 156), Floor = Enum.Material.Slate, FloorColor = Color3.fromRGB(70, 70, 74), Props = "Kitchen" },
		Pantry = { Wall = Color3.fromRGB(150, 140, 120), Floor = Enum.Material.Cobblestone, FloorColor = Color3.fromRGB(100, 96, 90), Props = "Pantry" },
		Conservatory = { Wall = Color3.fromRGB(150, 200, 190), WallMaterial = Enum.Material.Glass, WallTransparency = 0.55, Floor = Enum.Material.Slate, FloorColor = Color3.fromRGB(86, 104, 92), Props = "Conservatory" },
		Cellar = { Wall = Color3.fromRGB(96, 66, 52), WallMaterial = Enum.Material.Brick, Floor = Enum.Material.Cobblestone, FloorColor = Color3.fromRGB(80, 78, 74), Props = "Cellar" },
		Boiler = { Wall = Color3.fromRGB(96, 96, 92), WallMaterial = Enum.Material.Concrete, Floor = Enum.Material.DiamondPlate, FloorColor = Color3.fromRGB(80, 80, 82), Props = "Boiler" },
		Bedroom = { Wall = Color3.fromRGB(52, 54, 86), Floor = Enum.Material.Fabric, FloorColor = Color3.fromRGB(96, 40, 44), Props = "Bedroom" },
		Study = { Wall = Color3.fromRGB(40, 64, 48), Floor = Enum.Material.WoodPlanks, FloorColor = Color3.fromRGB(78, 56, 40), Props = "Study" },
		Nursery = { Wall = Color3.fromRGB(150, 112, 116), Floor = Enum.Material.WoodPlanks, FloorColor = Color3.fromRGB(120, 96, 72), Props = "Nursery" },
		Trophy = { Wall = Color3.fromRGB(86, 30, 30), Floor = Enum.Material.WoodPlanks, FloorColor = Color3.fromRGB(70, 48, 34), Props = "Trophy" },
		Attic = { Wall = Color3.fromRGB(96, 74, 54), WallMaterial = Enum.Material.WoodPlanks, Floor = Enum.Material.WoodPlanks, FloorColor = Color3.fromRGB(88, 66, 46), Props = "Attic" },
	},
	-- Lamps: one per LampCells cells of a room. Before the power: Off (dim, red, flickering); after: On.
	LampCells = 12,
	Lamps = {
		Off = { Color = Color3.fromRGB(255, 120, 80), Brightness = 0.5, Range = 22 },
		On = { Color = Color3.fromRGB(255, 214, 160), Brightness = 1.4, Range = 34 },
	},
}

-- The night outside (EndlessServer sets Lighting at boot).
Config.Lighting = {
	ClockTime = 0.2,
	Brightness = 1.2,
	Ambient = Color3.fromRGB(26, 26, 34),
	OutdoorAmbient = Color3.fromRGB(58, 60, 78),
	Atmosphere = { Density = 0.42, Offset = 0.1, Color = Color3.fromRGB(70, 76, 96), Decay = Color3.fromRGB(40, 40, 52), Glare = 0, Haze = 2.2 },
}

-- What the HUD (StarterGui.HUD, the lobby's authored HUD) shows, and its colours.
Config.Hud = {
	Amber = Color3.fromRGB(255, 176, 60),
	White = Color3.fromRGB(240, 238, 232),
	Red = Color3.fromRGB(230, 70, 60),
	NoticeTime = 3.5,
}

return Config
```

### 2. `ReplicatedStorage.Endless.Net` (ModuleScript)

Makes and finds the three RemoteEvents (Weapon, Fx, Hud) in ReplicatedStorage.Endless.Remotes.

```lua
-- The Endless remotes, in ReplicatedStorage.Endless.Remotes. The server makes them at boot
-- (Net.Get creates what is missing); clients wait for them.
--   Weapon (client -> server): "Fire" (tool, origin, directions, claims), "Reload" (tool),
--     "Melee" ().
--   Fx (server -> clients): world effects: "Shot" (userId, weaponId, origin, ends), "Blood"
--     (position, normal, amount), "Gib" (position), "Swing" (zombie), "Box" (state...).
--   Hud (server -> clients): screen cues: "Notice" (text), "Broke", "Round" (n), "RoundOver" (n),
--     "GameOver" (round), "Hit" (head, killed), "Hurt", "PowerUp" (kind), "Down" (name).

local RunService = game:GetService("RunService")

local Net = {}

local root = script.Parent
local NAMES = { "Weapon", "Fx", "Hud" }

local function container()
	local f = root:FindFirstChild("Remotes")
	if not f and RunService:IsServer() then
		f = Instance.new("Folder")
		f.Name = "Remotes"
		f.Parent = root
	end
	return f or root:WaitForChild("Remotes")
end

function Net.Get(name: string): RemoteEvent
	local f = container()
	local r = f:FindFirstChild(name)
	if not r then
		if RunService:IsServer() then
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = f
		else
			r = f:WaitForChild(name)
		end
	end
	return r
end

-- Server: make every remote before any client asks.
function Net.Make()
	for _, name in NAMES do
		Net.Get(name)
	end
end

return Net
```

### 3. `ReplicatedStorage.Endless.Sfx` (ModuleScript)

Plays sound cues from ReplicatedStorage.Assets.Sounds (the lobby's folder); silent without it.

```lua
-- Sound cues for the Endless reference, on the server or a client. A cue is a path like
-- "Guns/AK/Crack" under ReplicatedStorage.Assets.Sounds: the lobby's SoundKit layout, so copying
-- that folder from the lobby place gives this place the zombie mode's sounds. A cue that names a
-- Folder plays one of its Sounds. With no Assets.Sounds (a bare place) every cue is silent.
--   Sfx.Play(cue, { Position = Vector3 | Parent = Instance, Volume = n, Speed = n })

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Sfx = {}

local missing = {}

local function root()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Sounds")
end

local function resolve(cue: string)
	local node = root()
	if not node then
		return nil
	end
	for name in string.gmatch(cue, "[^/]+") do
		node = node:FindFirstChild(name)
		if not node then
			return nil
		end
	end
	if node:IsA("Folder") then
		local list = {}
		for _, s in node:GetChildren() do
			if s:IsA("Sound") then
				table.insert(list, s)
			end
		end
		return if #list > 0 then list[math.random(#list)] else nil
	end
	return if node:IsA("Sound") then node else nil
end

function Sfx.Play(cue: string, opts: { [string]: any }?)
	local template = resolve(cue)
	if not template then
		missing[cue] = true
		return nil
	end
	opts = opts or {}
	local sound = template:Clone()
	if opts.Volume then
		sound.Volume *= opts.Volume
	end
	if opts.Speed then
		sound.PlaybackSpeed *= opts.Speed
	end
	local holder
	if opts.Position then
		holder = Instance.new("Attachment")
		holder.WorldPosition = opts.Position
		holder.Parent = workspace.Terrain
		sound.Parent = holder
	else
		sound.Parent = opts.Parent or SoundService
	end
	sound:Play()
	local life = sound.TimeLength / math.max(0.05, sound.PlaybackSpeed) + 0.5
	Debris:AddItem(holder or sound, if life > 0.6 then life else 6)
	return sound
end

-- Cues asked for that this place has no sound for (for a check in the Command Bar).
function Sfx.Missing()
	return missing
end

return Sfx
```

### 4. `ReplicatedStorage.Endless.Weapons` (ModuleScript)

A gun's numbers for one player: base stats plus altar boosts, perks and relics.

```lua
-- A gun's numbers as they stand for one player: the gun's own (Config.Weapons), what the ascension
-- altar added to this copy (the tool's Boosts attribute, a comma list of Config.Altar.Boosts ids),
-- and the player's perks and relics. Server and clients use the same sums, so the client's fire
-- rate, magazine and reload match what the server allows.
--
-- Tool attributes (set by the server's Arsenal): Weapon (id), Mag, Reserve, Boosts, Level,
-- Reloading (bool), ReloadEnd (server time).

local Config = require(script.Parent.Config)

local Weapons = {}

function Weapons.Get(id: string)
	return Config.Weapons[id]
end

function Weapons.ParseBoosts(text: string?): { string }
	local list = {}
	if text and text ~= "" then
		for id in string.gmatch(text, "[^,]+") do
			if Config.Altar.Boosts[id] then
				table.insert(list, id)
			end
		end
	end
	return list
end

local function attr(player: Player?, name: string): number
	return if player then (player:GetAttribute(name) or 0) else 0
end

-- The numbers for gun `id` with these boosts, carried by player (nil: the bare gun).
function Weapons.Stats(id: string, boostText: string?, player: Player?)
	local base = Config.Weapons[id]
	if not base then
		return nil
	end
	local boosts = Weapons.ParseBoosts(boostText)
	local damage, mag, reserve, rpm, reload, pierce, head = 1, 1, 1, 1, 1, base.Pierce or 1, base.Head or 1
	for _, b in boosts do
		local boost = Config.Altar.Boosts[b]
		damage += boost.Damage or 0
		mag += boost.Mag or 0
		reserve += boost.Reserve or 0
		rpm += boost.Rpm or 0
		reload *= 1 - (boost.Reload or 0)
		pierce += boost.Pierce or 0
		head += boost.Head or 0
	end
	local perks = Config.Perks.List
	if player then
		damage *= 1 + attr(player, "RelicDamage")
		head = 1 + (head - 1) * (1 + attr(player, "RelicHead"))
		reserve += attr(player, "RelicReserve")
		reload *= 1 - attr(player, "RelicReload")
		if player:GetAttribute("Perk_TwinFang") then
			rpm *= perks.TwinFang.FireRate
		end
		if player:GetAttribute("Perk_Quickhand") then
			reload *= perks.Quickhand.Reload
		end
	end
	return {
		Id = id,
		Name = base.Name,
		Fire = base.Fire,
		Damage = base.Damage * damage,
		Pellets = base.Pellets or 1,
		Head = head,
		Rpm = base.Rpm * rpm,
		Mag = math.max(1, math.floor(base.Mag * mag + 0.5)),
		Reserve = math.floor(base.Reserve * reserve + 0.5),
		Reload = base.Reload * reload,
		Spread = base.Spread,
		Range = base.Range,
		Pierce = pierce,
		AimFov = base.AimFov,
		Sounds = base.Sounds,
		Beam = base.Beam,
		Level = #boosts,
	}
end

-- The same, read off a tool.
function Weapons.ForTool(tool: Instance, player: Player?)
	local id = tool:GetAttribute("Weapon")
	return id and Weapons.Stats(id, tool:GetAttribute("Boosts"), player) or nil
end

-- What the altar charges to ascend a gun that has ascended `level` times.
function Weapons.AscendCost(level: number): number
	return math.floor(Config.Altar.Cost * Config.Altar.Growth ^ level / 50 + 0.5) * 50
end

return Weapons
```

### 5. `ReplicatedStorage.Endless.GunModel` (ModuleScript)

Builds every gun's look from parts (no assets).

```lua
-- Gun looks built from plain parts (no assets), one per Config.Weapons Look. The grip is the
-- origin: barrel along -Z, up is +Y, and the invisible "Handle" part sits where the hand holds it,
-- so a Tool made from it points forward with the default Grip. A "Muzzle" attachment in the Handle
-- marks the barrel's tip.
--   GunModel.Build(id, opts) -> Model
--     opts.Level: ascension level (tints the accent parts, Config.Altar.TierColors)
--     opts.Anchored: for display (the randomizer, a wall); otherwise parts are welded to Handle
--     opts.Chalk: drawn on a wall (one chalk colour)
--     opts.CFrame: where the grip goes (default: the origin)

local Config = require(script.Parent.Config)

local GunModel = {}

local METAL = Color3.fromRGB(46, 46, 50)
local DARK = Color3.fromRGB(30, 30, 34)
local WOOD = Color3.fromRGB(104, 70, 42)
local CHALK = Color3.fromRGB(232, 232, 222)

local LOOKS = {
	Pistol = { Body = Vector3.new(0.3, 0.42, 1.25), Barrel = 0.15, Bore = 0.16 },
	Revolver = { Body = Vector3.new(0.34, 0.5, 0.9), Barrel = 0.9, Bore = 0.22, Cylinder = true },
	Carbine = { Body = Vector3.new(0.32, 0.45, 1.9), Barrel = 1.3, Stock = 1.5, Mag = Vector3.new(0.24, 0.5, 0.35), Wood = true },
	BoltRifle = { Body = Vector3.new(0.3, 0.42, 2), Barrel = 2, Stock = 1.7, Wood = true, Bolt = true },
	SMG = { Body = Vector3.new(0.34, 0.55, 1.5), Barrel = 0.5, Stock = 0.8, Mag = Vector3.new(0.24, 0.85, 0.32) },
	Shotgun = { Body = Vector3.new(0.34, 0.45, 1.6), Barrel = 2, Bore = 0.26, Stock = 1.6, Pump = true, Wood = true },
	AK = { Body = Vector3.new(0.34, 0.55, 1.9), Barrel = 1.3, Stock = 1.5, Mag = Vector3.new(0.28, 0.85, 0.42), MagTilt = 18, Wood = true },
	M4 = { Body = Vector3.new(0.34, 0.6, 1.8), Barrel = 1.2, Stock = 1.3, Mag = Vector3.new(0.26, 0.75, 0.38), Rail = true },
	BattleRifle = { Body = Vector3.new(0.36, 0.6, 2.1), Barrel = 1.5, Stock = 1.5, Mag = Vector3.new(0.28, 0.6, 0.45), Scope = 1.3 },
	Sniper = { Body = Vector3.new(0.34, 0.5, 2.1), Barrel = 2.3, Stock = 1.7, Scope = 1.8, Wood = true },
	LMG = { Body = Vector3.new(0.5, 0.7, 2.1), Barrel = 1.7, Bore = 0.28, Stock = 1.5, Box = Vector3.new(0.6, 0.6, 0.7) },
	CoachGun = { Body = Vector3.new(0.34, 0.45, 1.1), Barrel = 2.1, Bore = 0.22, Double = true, Stock = 1.6, Wood = true },
	Lumen = { Body = Vector3.new(0.5, 0.6, 1.8), Barrel = 1.1, Bore = 0.3, Glow = Color3.fromRGB(150, 230, 255), Coils = 3 },
}

function GunModel.Look(id: string)
	local w = Config.Weapons[id]
	return LOOKS[w and w.Look or "Pistol"] or LOOKS.Pistol
end

function GunModel.Build(id: string, opts: { [string]: any }?): Model
	opts = opts or {}
	local look = GunModel.Look(id)
	local at = opts.CFrame or CFrame.new()
	local level = opts.Level or 0
	local tier = if level > 0 then Config.Altar.TierColors[math.min(level, #Config.Altar.TierColors)] else nil

	local model = Instance.new("Model")
	model.Name = id

	local function part(name, size, cf, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = at * cf
		p.Color = if opts.Chalk then CHALK else color
		p.Material = if opts.Chalk then Enum.Material.SmoothPlastic elseif material then material else Enum.Material.Metal
		p.Transparency = if opts.Chalk then 0.15 else 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = not opts.Chalk
		p.Anchored = opts.Anchored == true
		p.Parent = model
		return p
	end

	local handle = part("Handle", Vector3.new(0.4, 0.4, 0.4), CFrame.new(), METAL)
	handle.Transparency = 1

	local body = look.Body
	local front = 0.55 - body.Z
	local wood = if look.Wood then WOOD else METAL
	local accent = if tier then tier else METAL
	local accentMat = if tier then Enum.Material.Neon else Enum.Material.Metal

	part("Grip", Vector3.new(0.28, 0.85, 0.42), CFrame.new(0, -0.3, 0.12) * CFrame.Angles(math.rad(-18), 0, 0), wood, if look.Wood then Enum.Material.Wood else Enum.Material.SmoothPlastic)
	part("Body", body, CFrame.new(0, 0.3, 0.55 - body.Z / 2), METAL)
	part("Accent", Vector3.new(body.X + 0.04, 0.08, body.Z * 0.75), CFrame.new(0, 0.32, 0.55 - body.Z / 2), accent, accentMat)

	local bore = look.Bore or 0.18
	local barrelY = 0.36
	local function barrel(x)
		part("Barrel", Vector3.new(look.Barrel, bore, bore), CFrame.new(x, barrelY, front - look.Barrel / 2) * CFrame.Angles(0, math.rad(90), 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	if look.Double then
		barrel(-0.1)
		barrel(0.1)
	else
		barrel(0)
	end
	if look.Wood and look.Stock then
		part("Handguard", Vector3.new(body.X + 0.06, 0.3, math.min(look.Barrel * 0.6, 1.4)), CFrame.new(0, 0.2, front - math.min(look.Barrel * 0.6, 1.4) / 2), WOOD, Enum.Material.Wood)
	end
	if look.Stock then
		part("Stock", Vector3.new(0.28, 0.5, look.Stock), CFrame.new(0, 0.15, 0.55 + look.Stock / 2) * CFrame.Angles(math.rad(-6), 0, 0), wood, if look.Wood then Enum.Material.Wood else Enum.Material.SmoothPlastic)
	end
	if look.Mag then
		local m = look.Mag
		local cf = CFrame.new(0, 0.3 - body.Y / 2 - m.Y / 2 + 0.12, front + 0.45 + m.Z / 2) * CFrame.Angles(math.rad(look.MagTilt or 0), 0, 0)
		part("Mag", m, cf, DARK)
	end
	if look.Box then
		part("Box", look.Box, CFrame.new(0.05, 0.3 - body.Y / 2 - look.Box.Y / 2 + 0.1, front + 0.8), Color3.fromRGB(70, 74, 54))
	end
	if look.Pump then
		part("Pump", Vector3.new(0.34, 0.28, 0.8), CFrame.new(0, barrelY - 0.24, front - 0.6), WOOD, Enum.Material.Wood)
	end
	if look.Cylinder then
		part("Cylinder", Vector3.new(0.5, 0.46, 0.46), CFrame.new(0, 0.32, front + 0.3) * CFrame.Angles(0, math.rad(90), 0), METAL, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	if look.Scope then
		part("Scope", Vector3.new(look.Scope, 0.32, 0.32), CFrame.new(0, 0.3 + body.Y / 2 + 0.24, 0.55 - body.Z / 2) * CFrame.Angles(0, math.rad(90), 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	if look.Rail then
		part("Rail", Vector3.new(0.2, 0.1, body.Z * 0.8), CFrame.new(0, 0.3 + body.Y / 2 + 0.05, 0.55 - body.Z / 2), DARK)
	end
	if look.Bolt then
		part("Bolt", Vector3.new(0.3, 0.1, 0.1), CFrame.new(0.22, 0.42, 0.25), METAL)
	end
	if look.Glow then
		for i = 1, look.Coils or 2 do
			part("Coil", Vector3.new(0.12, bore + 0.25, bore + 0.25), CFrame.new(0, barrelY, front - i * look.Barrel / ((look.Coils or 2) + 1)) * CFrame.Angles(0, math.rad(90), 0), look.Glow, Enum.Material.Neon, Enum.PartType.Cylinder)
		end
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, barrelY, front - look.Barrel - 0.05)
	muzzle.Parent = handle

	if not opts.Anchored then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	model.PrimaryPart = handle
	return model
end

return GunModel
```

### 6. `ServerStorage.Endless.Util` (ModuleScript)

Signal, Maid (cleanup), ProximityPrompt maker, shuffle, weighted pick.

```lua
-- Small helpers the Endless server modules share.
--   Util.Signal(): Connect(fn) -> {Disconnect}, Fire(...), Clear()
--   Util.Maid(): Add(thing) (connection, thread, instance, function, or anything with Destroy/Disconnect),
--     Clean() (undoes everything added, newest first)
--   Util.Prompt(parent, action, object, hold, range): a ProximityPrompt set up the house way
--   Util.Shuffle(list), Util.Weighted(weights, skip), Util.Flat(v), Util.Now()

local Util = {}

function Util.Signal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local h = { Fn = fn }
		table.insert(handlers, h)
		return {
			Disconnect = function()
				local i = table.find(handlers, h)
				if i then
					table.remove(handlers, i)
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, h in table.clone(handlers) do
			task.spawn(h.Fn, ...)
		end
	end
	function signal:Clear()
		table.clear(handlers)
	end
	return signal
end

function Util.Maid()
	local items = {}
	local maid = {}
	function maid:Add(thing)
		table.insert(items, thing)
		return thing
	end
	function maid:Clean()
		for i = #items, 1, -1 do
			local thing = items[i]
			items[i] = nil
			local kind = typeof(thing)
			if kind == "RBXScriptConnection" then
				thing:Disconnect()
			elseif kind == "thread" then
				pcall(task.cancel, thing)
			elseif kind == "Instance" then
				thing:Destroy()
			elseif kind == "function" then
				local ok, err = pcall(thing)
				if not ok then
					warn("Endless cleanup:", err)
				end
			elseif kind == "table" then
				if thing.Destroy then
					thing:Destroy()
				elseif thing.Disconnect then
					thing:Disconnect()
				end
			end
		end
	end
	return maid
end

function Util.Prompt(parent: Instance, action: string, object: string, hold: number, range: number?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = range or 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = parent
	return prompt
end

function Util.Shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- A key from {key = weight}, leaving out keys for which skip(key) is true. Nil if none is left.
function Util.Weighted(weights, skip)
	local total = 0
	for k, wgt in weights do
		if wgt > 0 and not (skip and skip(k)) then
			total += wgt
		end
	end
	if total <= 0 then
		return nil
	end
	local r = math.random() * total
	local last
	for k, wgt in weights do
		if wgt > 0 and not (skip and skip(k)) then
			r -= wgt
			last = k
			if r <= 0 then
				return k
			end
		end
	end
	return last
end

function Util.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.Now(): number
	return workspace:GetServerTimeNow()
end

return Util
```

### 7. `ServerStorage.Endless.HouseLayout` (ModuleScript)

The map as data: four levels of ASCII plans, doors, arches, windows, hatches, stairs, spots.

```lua
-- The huge house the Endless reference is played in: Blackwood Manor, four levels (cellar, ground,
-- upper, attic), nineteen rooms in fifteen zones. HouseBuilder turns this table into parts at the start of every
-- run. Check a change with `python tools/endless_house.py` (it validates the layout and draws each
-- level to docs/endless/house-*.png) before you sync.
--
-- Plans: one string per row, north (z = 0) at the top, west (x = 0) on the left. Each character is a
-- cell House.Cell studs square (Config.House). A letter or digit is the room on that cell; "." is no
-- room. Every level uses the same grid, so a cell is the same spot of ground on every level.
-- Walls come by themselves: wherever two neighbouring cells are different rooms (or a room and
-- nothing), there is a wall. Openings are cut into those walls:
--   Doors   {Level, At = {x, z}, Side, Cost}: bought with points; opening one joins its two zones.
--   Arches  {Level, At, Side}: always open; rooms joined by arches are one zone.
--   Windows {Level, At, Side}: boarded windows on outside walls, where zombies come in. Windows on
--           an upper level need open ground under them on every level below (zombies climb the
--           wall).
--   Hatches {Level, At}: a broken hole in the floor of that cell; zombies claw up through it.
-- Side is the side of cell At the opening is on: "N" (toward z - 1), "S", "W" (toward x - 1) or "E".
-- Stairs {Level, At, Rise, Length, Gate, Cost}: a ramp on Level from cell At (its low end) running
--   Length cells toward Rise and climbing one level. The cells above it on Level + 1 have no floor
--   (railings round the hole) and the next cell past the top is where you step off. Gate = "Bottom"
--   or "Top" puts a door you buy across that end; no Gate means the stair is always open.
-- Spots {Kind, Level, At, Side}: places for the run's furniture, standing in cell At against the wall
--   on Side. Every run draws where things go from these, so the house plays different each time:
--   Box (the weapon randomizer: one spot is used, it moves between them), Perk (one per perk),
--   Wall (a gun drawn on the wall; Weapon = fixed gun, else drawn from Config.WallBuys.Pool),
--   Altar (gun ascension; one is used), Power (the power switch; one is used).
-- Rooms {Name, Style, Start}: Style picks colours and furniture (Config.House.Styles). Players
-- spawn in the Start room, whose zone is open from the start.

return {
	Name = "Blackwood Manor",
	Width = 16,
	Depth = 14,
	Levels = {
		[-1] = {
			"................",
			"................",
			"...........XXXXX",
			"...........XXXXX",
			"...........XXXXX",
			"...........WWWWW",
			"...........WWWWW",
			"...........WWWWW",
			"...........WWWWW",
			"...........WWWWW",
			"................",
			"................",
			"................",
			"................",
		},
		[0] = {
			"..CCCCCCCCCCCC..",
			"..CCCCCCCCCCCC..",
			"BBBBBGGGGGGKKKKK",
			"BBBBBGGGGGGKKKKK",
			"BBBBBGGGGGGKKKKK",
			"BBBBBGGGGGGKKKKK",
			"BBBBBGGGGGGPPPPP",
			"LLLLLhhhhhhPPPPP",
			"LLLLLFFFFFFDDDDD",
			"LLLLLFFFFFFDDDDD",
			"LLLLLFFFFFFDDDDD",
			"LLLLLFFFFFFDDDDD",
			".....FFFFFF.....",
			"................",
		},
		[1] = {
			"................",
			"................",
			"MMMMMSSSSSSNNNNN",
			"MMMMMSSSSSSNNNNN",
			"MMMMMSSSSSSNNNNN",
			"MMMMMSSSSSSNNNNN",
			"MMMMMuuuuuuNNNNN",
			"RRRRRuuuuuuTTTTT",
			"RRRRRUUUUUUTTTTT",
			"RRRRRUUUUUUTTTTT",
			"RRRRRUUUUUUTTTTT",
			"RRRRRUUUUUUTTTTT",
			"................",
			"................",
		},
		[2] = {
			"................",
			"................",
			".....AAAAAA.....",
			".....AAAAAA.....",
			".....AAAAAA.....",
			".....AAAAAA.....",
			".....AAAAAA.....",
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
			"................",
		},
	},

	Rooms = {
		F = { Name = "Foyer", Style = "Foyer", Start = true },
		h = { Name = "Back Hall", Style = "Hall" },
		L = { Name = "Living Room", Style = "Living" },
		D = { Name = "Dining Room", Style = "Dining" },
		B = { Name = "Library", Style = "Library" },
		G = { Name = "Great Hall", Style = "GreatHall" },
		K = { Name = "Kitchen", Style = "Kitchen" },
		P = { Name = "Pantry", Style = "Pantry" },
		C = { Name = "Conservatory", Style = "Conservatory" },
		W = { Name = "Wine Cellar", Style = "Cellar" },
		X = { Name = "Boiler Room", Style = "Boiler" },
		U = { Name = "Gallery", Style = "Foyer" },
		u = { Name = "Upper Hall", Style = "Hall" },
		R = { Name = "Guest Room", Style = "Bedroom" },
		T = { Name = "Trophy Room", Style = "Trophy" },
		M = { Name = "Master Bedroom", Style = "Bedroom" },
		N = { Name = "Nursery", Style = "Nursery" },
		S = { Name = "Study", Style = "Study" },
		A = { Name = "Attic", Style = "Attic" },
	},

	Stairs = {
		-- The grand stair, up the east side of the foyer to the gallery.
		{ Level = 0, At = { 10, 11 }, Rise = "N", Length = 3, Gate = "Bottom", Cost = 1000 },
		-- Down from the pantry into the wine cellar; the gate is at the top, in the pantry.
		{ Level = -1, At = { 12, 6 }, Rise = "E", Length = 3, Gate = "Top", Cost = 1250 },
		-- Up from the upper hall into the attic.
		{ Level = 1, At = { 6, 6 }, Rise = "E", Length = 3, Gate = "Bottom", Cost = 1500 },
	},

	Doors = {
		{ Level = 0, At = { 5, 9 }, Side = "W", Cost = 750 }, -- foyer -> living room
		{ Level = 0, At = { 10, 8 }, Side = "E", Cost = 750 }, -- foyer -> dining room
		{ Level = 0, At = { 7, 7 }, Side = "N", Cost = 1250 }, -- back hall -> great hall
		{ Level = 0, At = { 2, 7 }, Side = "N", Cost = 1000 }, -- living room -> library
		{ Level = 0, At = { 13, 8 }, Side = "N", Cost = 1000 }, -- dining room -> pantry
		{ Level = 0, At = { 4, 4 }, Side = "E", Cost = 1250 }, -- library -> great hall
		{ Level = 0, At = { 11, 4 }, Side = "W", Cost = 1250 }, -- kitchen -> great hall
		{ Level = 0, At = { 7, 2 }, Side = "N", Cost = 1500 }, -- great hall -> conservatory
		{ Level = 0, At = { 3, 2 }, Side = "N", Cost = 1250 }, -- library -> conservatory
		{ Level = 0, At = { 12, 2 }, Side = "N", Cost = 1250 }, -- kitchen -> conservatory
		{ Level = 1, At = { 5, 10 }, Side = "W", Cost = 1000 }, -- gallery -> guest room
		{ Level = 1, At = { 10, 8 }, Side = "E", Cost = 1000 }, -- gallery -> trophy room
		{ Level = 1, At = { 5, 6 }, Side = "W", Cost = 1250 }, -- upper hall -> master bedroom
		{ Level = 1, At = { 10, 6 }, Side = "E", Cost = 1250 }, -- upper hall -> nursery
		{ Level = 1, At = { 9, 6 }, Side = "N", Cost = 1000 }, -- upper hall -> study
		{ Level = 1, At = { 2, 7 }, Side = "N", Cost = 750 }, -- guest room -> master bedroom
		{ Level = 1, At = { 13, 7 }, Side = "N", Cost = 750 }, -- trophy room -> nursery
	},

	Arches = {
		{ Level = 0, At = { 6, 8 }, Side = "N" }, -- foyer <-> back hall
		{ Level = 0, At = { 9, 8 }, Side = "N" }, -- foyer <-> back hall
		{ Level = 0, At = { 11, 6 }, Side = "N" }, -- pantry <-> kitchen
		{ Level = -1, At = { 13, 5 }, Side = "N" }, -- wine cellar <-> boiler room
		{ Level = 1, At = { 6, 8 }, Side = "N" }, -- gallery <-> upper hall
		{ Level = 1, At = { 8, 8 }, Side = "N" }, -- gallery <-> upper hall
	},

	Windows = {
		{ Level = 0, At = { 6, 12 }, Side = "S" }, -- foyer
		{ Level = 0, At = { 9, 12 }, Side = "S" }, -- foyer
		{ Level = 0, At = { 5, 12 }, Side = "W" }, -- foyer
		{ Level = 0, At = { 0, 8 }, Side = "W" }, -- living room
		{ Level = 0, At = { 0, 10 }, Side = "W" }, -- living room
		{ Level = 0, At = { 2, 11 }, Side = "S" }, -- living room
		{ Level = 0, At = { 15, 9 }, Side = "E" }, -- dining room
		{ Level = 0, At = { 15, 11 }, Side = "E" }, -- dining room
		{ Level = 0, At = { 13, 11 }, Side = "S" }, -- dining room
		{ Level = 0, At = { 0, 3 }, Side = "W" }, -- library
		{ Level = 0, At = { 0, 5 }, Side = "W" }, -- library
		{ Level = 0, At = { 15, 3 }, Side = "E" }, -- kitchen
		{ Level = 0, At = { 15, 5 }, Side = "E" }, -- kitchen
		{ Level = 0, At = { 15, 7 }, Side = "E" }, -- pantry
		{ Level = 0, At = { 4, 0 }, Side = "N" }, -- conservatory
		{ Level = 0, At = { 7, 0 }, Side = "N" }, -- conservatory
		{ Level = 0, At = { 10, 0 }, Side = "N" }, -- conservatory
		{ Level = 0, At = { 2, 1 }, Side = "W" }, -- conservatory
		{ Level = 0, At = { 13, 1 }, Side = "E" }, -- conservatory
		{ Level = 1, At = { 0, 4 }, Side = "W" }, -- master bedroom
		{ Level = 1, At = { 0, 9 }, Side = "W" }, -- guest room
		{ Level = 1, At = { 3, 11 }, Side = "S" }, -- guest room
		{ Level = 1, At = { 15, 8 }, Side = "E" }, -- trophy room
		{ Level = 1, At = { 12, 11 }, Side = "S" }, -- trophy room
		{ Level = 1, At = { 15, 4 }, Side = "E" }, -- nursery
	},

	Hatches = {
		{ Level = 0, At = { 7, 4 } }, -- great hall
		{ Level = 0, At = { 9, 3 } }, -- great hall
		{ Level = -1, At = { 14, 8 } }, -- wine cellar
		{ Level = -1, At = { 12, 3 } }, -- boiler room
		{ Level = 1, At = { 7, 3 } }, -- study
		{ Level = 1, At = { 7, 10 } }, -- gallery
		{ Level = 2, At = { 7, 3 } }, -- attic
	},

	Spots = {
		{ Kind = "Box", Level = 0, At = { 1, 7 }, Side = "N" }, -- living room
		{ Kind = "Box", Level = 0, At = { 8, 2 }, Side = "N" }, -- great hall
		{ Kind = "Box", Level = 0, At = { 9, 1 }, Side = "S" }, -- conservatory
		{ Kind = "Box", Level = 1, At = { 1, 2 }, Side = "N" }, -- master bedroom
		{ Kind = "Box", Level = -1, At = { 11, 9 }, Side = "W" }, -- wine cellar
		{ Kind = "Box", Level = 1, At = { 15, 10 }, Side = "E" }, -- trophy room

		{ Kind = "Perk", Level = 0, At = { 0, 2 }, Side = "W" }, -- library
		{ Kind = "Perk", Level = 0, At = { 15, 2 }, Side = "E" }, -- kitchen
		{ Kind = "Perk", Level = 0, At = { 11, 11 }, Side = "W" }, -- dining room
		{ Kind = "Perk", Level = 0, At = { 10, 6 }, Side = "E" }, -- great hall
		{ Kind = "Perk", Level = 1, At = { 5, 11 }, Side = "W" }, -- gallery
		{ Kind = "Perk", Level = 1, At = { 15, 6 }, Side = "E" }, -- nursery
		{ Kind = "Perk", Level = 1, At = { 0, 11 }, Side = "W" }, -- guest room
		{ Kind = "Perk", Level = -1, At = { 15, 2 }, Side = "E" }, -- boiler room

		{ Kind = "Wall", Level = 0, At = { 5, 10 }, Side = "W", Weapon = "Carbine" }, -- foyer
		{ Kind = "Wall", Level = 0, At = { 7, 12 }, Side = "S", Weapon = "BoltRifle" }, -- foyer
		{ Kind = "Wall", Level = 0, At = { 0, 9 }, Side = "W" }, -- living room
		{ Kind = "Wall", Level = 0, At = { 15, 10 }, Side = "E" }, -- dining room
		{ Kind = "Wall", Level = 0, At = { 4, 6 }, Side = "E" }, -- library
		{ Kind = "Wall", Level = 0, At = { 11, 3 }, Side = "W" }, -- kitchen
		{ Kind = "Wall", Level = 0, At = { 5, 3 }, Side = "W" }, -- great hall
		{ Kind = "Wall", Level = 0, At = { 13, 0 }, Side = "N" }, -- conservatory
		{ Kind = "Wall", Level = 1, At = { 8, 11 }, Side = "S" }, -- gallery
		{ Kind = "Wall", Level = 1, At = { 4, 3 }, Side = "E" }, -- master bedroom
		{ Kind = "Wall", Level = 1, At = { 10, 3 }, Side = "E" }, -- study
		{ Kind = "Wall", Level = -1, At = { 15, 8 }, Side = "E" }, -- wine cellar

		{ Kind = "Altar", Level = 2, At = { 10, 4 }, Side = "E" }, -- attic
		{ Kind = "Altar", Level = 0, At = { 2, 0 }, Side = "N" }, -- conservatory
		{ Kind = "Altar", Level = -1, At = { 11, 2 }, Side = "W" }, -- boiler room

		{ Kind = "Power", Level = -1, At = { 13, 2 }, Side = "N" }, -- boiler room
		{ Kind = "Power", Level = -1, At = { 15, 5 }, Side = "E" }, -- wine cellar
	},
}
```

### 8. `ServerStorage.Endless.HouseBuilder` (ModuleScript)

Builds the house from HouseLayout out of parts, every run, and returns the House table.

```lua
-- Builds the Endless house from HouseLayout (plans, openings, stairs, spots) out of plain parts, and
-- returns the House the rest of the mode works from. Called at the start of every run: the old house
-- is destroyed and a new one stands, so every run starts with doors shut, boards up and fresh props.
--
-- Geometry (Config.House): cell (x, z) of a plan covers Cell x Cell studs, the grid centred on
-- Origin. Level L's floor top is Origin.Y + 1 + L x Story (the yard is at Origin.Y). A wall stands on
-- every cell edge between two different rooms (or a room and nothing): two half-thickness skins, one
-- in each room's finish (outside: Exterior). Doors, arches and windows are cut out of those walls.
-- A stair is a ramp on its level with the cells above it left open (railings round the hole).
--
-- The House (a table) holds what the systems need:
--   Model; Rooms[id] = {Id, Name, Style, Level, Cells, Zone, Floor}; Zones[id] = {Id, Rooms, Open}
--   StartRoom, StartZone; Doors = list of {Id, Kind ("Door"/"Gate"), Zones = {a, b}, Cost, Leaf
--   (Model), Center, Normal, Width, Height, Open}; Windows = list of {Id, Room, Zone, Level, Center,
--   SillTop, Normal (out of the room), Inside, Outside, Perch (upper floors), Spawn, Boards,
--   RepairAt}; Hatches = list of {Id, Room, Zone, Position}; Spots[kind] = list of {Kind, Room,
--   Zone, Level, CFrame (on the wall's inner face at floor height, facing into the room), Weapon};
--   Lamps = list of {Part, Light, Room}; YardMin/YardMax (Vector3).
--   House:RoomAt(position), House:FloorTop(level), House:StartPoints(count),
--   House:FloorPoints(room, count, near)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Endless.Config)

local HOUSE = Config.House
local CELL, STORY, SLAB, WALL = HOUSE.Cell, HOUSE.Story, HOUSE.Slab, HOUSE.Wall

local STEP = { N = { 0, -1 }, S = { 0, 1 }, W = { -1, 0 }, E = { 1, 0 } }
local DIR = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	W = Vector3.new(-1, 0, 0),
	E = Vector3.new(1, 0, 0),
}
local OPPOSITE = { N = "S", S = "N", W = "E", E = "W" }

local TRIM_INSIDE = Color3.fromRGB(58, 40, 30)
local WOOD = Color3.fromRGB(92, 66, 44)
local DARK_WOOD = Color3.fromRGB(56, 38, 28)
local IRON = Color3.fromRGB(40, 40, 44)

local HouseBuilder = {}

-- Parts -------------------------------------------------------------------------------------------

local function newPart(parent, name, cf, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- A part nobody walks into or shoots (trim, decals, glow).
local function ghost(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Greedy rectangles over a grid of keys (grid[z][x] = key or nil): fewer, bigger parts.
local function rectangles(grid, w, d)
	local used = {}
	local out = {}
	for z = 0, d - 1 do
		for x = 0, w - 1 do
			local k = grid[z] and grid[z][x]
			if k and not (used[z] and used[z][x]) then
				local x1 = x
				while x1 + 1 < w and grid[z][x1 + 1] == k and not (used[z] and used[z][x1 + 1]) do
					x1 += 1
				end
				local z1 = z
				while z1 + 1 < d do
					local ok = true
					for xx = x, x1 do
						if not (grid[z1 + 1] and grid[z1 + 1][xx] == k) or (used[z1 + 1] and used[z1 + 1][xx]) then
							ok = false
							break
						end
					end
					if not ok then
						break
					end
					z1 += 1
				end
				for zz = z, z1 do
					used[zz] = used[zz] or {}
					for xx = x, x1 do
						used[zz][xx] = true
					end
				end
				table.insert(out, { X0 = x, Z0 = z, X1 = x1, Z1 = z1, Key = k })
			end
		end
	end
	return out
end

-- Furniture ---------------------------------------------------------------------------------------
-- Each piece is built against a wall: cf is on the wall's inner face at floor height, looking into the
-- room (forward = into the room), so CFrame.new(0, up, -depth / 2) is a piece's centre.

local function piece(parent, cf, name, offset, size, color, material, shape)
	return newPart(parent, name, cf * CFrame.new(offset), size, color, material, shape)
end

local PROPS = {}

function PROPS.Bookshelf(parent, cf)
	piece(parent, cf, "Bookshelf", Vector3.new(0, 5, -1.2), Vector3.new(7, 10, 2.4), DARK_WOOD, Enum.Material.Wood)
	for i = 0, 3 do
		local books = piece(parent, cf, "Books", Vector3.new(0, 1.6 + i * 2.3, -2.25), Vector3.new(6.4, 1.6, 0.2), Color3.fromHSV(math.random(), 0.45, 0.35), Enum.Material.Fabric)
		ghost(books)
	end
end

function PROPS.Cabinet(parent, cf)
	piece(parent, cf, "Cabinet", Vector3.new(0, 2, -1.1), Vector3.new(5, 4, 2.2), DARK_WOOD, Enum.Material.Wood)
	ghost(piece(parent, cf, "Top", Vector3.new(0, 4.05, -1.1), Vector3.new(5.2, 0.1, 2.4), Color3.fromRGB(120, 112, 100), Enum.Material.Marble))
end

function PROPS.Sofa(parent, cf)
	piece(parent, cf, "Sofa", Vector3.new(0, 1, -1.5), Vector3.new(7, 2, 3), Color3.fromRGB(90, 40, 40), Enum.Material.Fabric)
	piece(parent, cf, "Back", Vector3.new(0, 2.5, -0.5), Vector3.new(7, 2, 1), Color3.fromRGB(80, 34, 34), Enum.Material.Fabric)
end

function PROPS.Counter(parent, cf)
	piece(parent, cf, "Counter", Vector3.new(0, 1.75, -1.25), Vector3.new(8, 3.5, 2.5), Color3.fromRGB(150, 146, 136), Enum.Material.SmoothPlastic)
	ghost(piece(parent, cf, "Top", Vector3.new(0, 3.55, -1.3), Vector3.new(8.2, 0.15, 2.7), Color3.fromRGB(60, 60, 64), Enum.Material.Granite))
end

function PROPS.Barrels(parent, cf)
	for i = -1, 1, 2 do
		piece(parent, cf, "Barrel", Vector3.new(i * 1.7, 2, -1.6), Vector3.new(4, 3, 3), Color3.fromRGB(96, 64, 40), Enum.Material.Wood, Enum.PartType.Cylinder).CFrame =
			cf * CFrame.new(i * 1.7, 2, -1.6) * CFrame.Angles(0, 0, math.rad(90))
	end
end

function PROPS.Crates(parent, cf)
	piece(parent, cf, "Crate", Vector3.new(-1.2, 1.5, -1.6), Vector3.new(3, 3, 3), Color3.fromRGB(120, 92, 60), Enum.Material.WoodPlanks)
	piece(parent, cf, "Crate", Vector3.new(1.6, 1.2, -1.3), Vector3.new(2.4, 2.4, 2.4), Color3.fromRGB(110, 84, 54), Enum.Material.WoodPlanks)
	piece(parent, cf, "Crate", Vector3.new(-0.9, 3.9, -1.5), Vector3.new(2.2, 1.8, 2.2), Color3.fromRGB(128, 98, 64), Enum.Material.WoodPlanks).CFrame =
		cf * CFrame.new(-0.9, 3.9, -1.5) * CFrame.Angles(0, math.rad(math.random(-20, 20)), 0)
end

function PROPS.Bed(parent, cf)
	piece(parent, cf, "Bed", Vector3.new(0, 1.2, -3.5), Vector3.new(5, 2.4, 7), Color3.fromRGB(200, 196, 186), Enum.Material.Fabric)
	piece(parent, cf, "Headboard", Vector3.new(0, 2.6, -0.4), Vector3.new(5.4, 5.2, 0.6), DARK_WOOD, Enum.Material.Wood)
	ghost(piece(parent, cf, "Blanket", Vector3.new(0, 2.45, -4.4), Vector3.new(5.1, 0.1, 5), Color3.fromRGB(110, 36, 40), Enum.Material.Fabric))
end

function PROPS.Desk(parent, cf)
	piece(parent, cf, "Desk", Vector3.new(0, 1.6, -1.5), Vector3.new(6, 3.2, 3), DARK_WOOD, Enum.Material.Wood)
	ghost(piece(parent, cf, "Lamp", Vector3.new(1.8, 3.6, -1.2), Vector3.new(0.8, 0.8, 0.8), Color3.fromRGB(255, 220, 150), Enum.Material.Neon, Enum.PartType.Ball))
end

function PROPS.Planter(parent, cf)
	piece(parent, cf, "Planter", Vector3.new(0, 1.2, -1.4), Vector3.new(6, 2.4, 2.4), Color3.fromRGB(120, 104, 90), Enum.Material.Concrete)
	for i = -2, 2, 2 do
		ghost(piece(parent, cf, "Plant", Vector3.new(i, 3.2, -1.4), Vector3.new(2, 2.4, 2), Color3.fromRGB(46, 80, 40), Enum.Material.Grass, Enum.PartType.Ball))
	end
end

function PROPS.Crib(parent, cf)
	piece(parent, cf, "Crib", Vector3.new(0, 1.6, -1.6), Vector3.new(5, 3.2, 3.2), Color3.fromRGB(196, 186, 170), Enum.Material.Wood)
	ghost(piece(parent, cf, "Doll", Vector3.new(0.8, 3.6, -1.6), Vector3.new(0.9, 0.9, 0.9), Color3.fromRGB(220, 200, 190), Enum.Material.SmoothPlastic, Enum.PartType.Ball))
end

function PROPS.Plaque(parent, cf)
	ghost(piece(parent, cf, "Plaque", Vector3.new(0, 8, -0.15), Vector3.new(2.4, 3, 0.3), DARK_WOOD, Enum.Material.Wood))
	ghost(piece(parent, cf, "Skull", Vector3.new(0, 8.2, -0.9), Vector3.new(1.4, 1.4, 1.4), Color3.fromRGB(214, 206, 186), Enum.Material.SmoothPlastic, Enum.PartType.Ball))
	piece(parent, cf, "Chest", Vector3.new(0, 1.5, -1.3), Vector3.new(4, 3, 2.6), Color3.fromRGB(70, 46, 30), Enum.Material.Wood)
end

function PROPS.Statue(parent, cf)
	piece(parent, cf, "Plinth", Vector3.new(0, 1.5, -1.5), Vector3.new(3, 3, 3), Color3.fromRGB(150, 146, 140), Enum.Material.Marble)
	piece(parent, cf, "Bust", Vector3.new(0, 4.4, -1.5), Vector3.new(2, 2.8, 1.6), Color3.fromRGB(170, 166, 160), Enum.Material.Marble)
end

function PROPS.Piano(parent, cf)
	piece(parent, cf, "Piano", Vector3.new(0, 2.2, -1.6), Vector3.new(7, 4.4, 3.2), Color3.fromRGB(20, 18, 20), Enum.Material.SmoothPlastic)
	ghost(piece(parent, cf, "Keys", Vector3.new(0, 2.6, -3.3), Vector3.new(6, 0.3, 0.6), Color3.fromRGB(235, 232, 220), Enum.Material.SmoothPlastic))
end

function PROPS.Boiler(parent, cf)
	piece(parent, cf, "Tank", Vector3.new(0, 3, -1.8), Vector3.new(6, 3.6, 3.6), Color3.fromRGB(90, 70, 60), Enum.Material.CorrodedMetal, Enum.PartType.Cylinder).CFrame =
		cf * CFrame.new(0, 3, -1.8) * CFrame.Angles(0, 0, math.rad(90))
	ghost(piece(parent, cf, "Pipe", Vector3.new(1.5, 9, -0.8), Vector3.new(0.8, 9, 0.8), Color3.fromRGB(80, 74, 70), Enum.Material.CorrodedMetal))
end

-- Which furniture a room style gets along its walls.
local STYLE_PROPS = {
	Foyer = { "Statue", "Cabinet" },
	Hall = { "Cabinet" },
	Living = { "Sofa", "Cabinet", "Bookshelf" },
	Dining = { "Cabinet", "Cabinet" },
	Library = { "Bookshelf", "Bookshelf", "Bookshelf", "Desk" },
	GreatHall = { "Piano", "Statue", "Cabinet" },
	Kitchen = { "Counter", "Counter", "Cabinet" },
	Pantry = { "Crates", "Barrels" },
	Conservatory = { "Planter", "Planter" },
	Cellar = { "Barrels", "Barrels", "Crates" },
	Boiler = { "Boiler", "Crates" },
	Bedroom = { "Bed", "Cabinet", "Desk" },
	Study = { "Bookshelf", "Desk" },
	Nursery = { "Crib", "Cabinet" },
	Trophy = { "Plaque", "Plaque", "Cabinet" },
	Attic = { "Crates", "Crates", "Barrels" },
}

-- The build --------------------------------------------------------------------------------------

function HouseBuilder.Build(layout, parent)
	local w, d = layout.Width, layout.Depth
	local origin = HOUSE.Origin
	local ox, oz = origin.X - w * CELL / 2, origin.Z - d * CELL / 2
	local groundY = origin.Y

	local model = Instance.new("Model")
	model.Name = "House"
	local fGround = folder(model, "Ground")
	local fFloors = folder(model, "Floors")
	local fWalls = folder(model, "Walls")
	local fOpenings = folder(model, "Openings")
	local fStairs = folder(model, "Stairs")
	local fLamps = folder(model, "Lamps")
	local fProps = folder(model, "Props")
	local fYard = folder(model, "Yard")

	local levels = {}
	for level in layout.Levels do
		table.insert(levels, level)
	end
	table.sort(levels)
	local minLevel, maxLevel = levels[1], levels[#levels]

	local function floorTop(level)
		return groundY + 1 + level * STORY
	end

	local function roomAt(level, x, z)
		local rows = layout.Levels[level]
		if not rows or x < 0 or z < 0 or x >= w or z >= d then
			return nil
		end
		local c = string.sub(rows[z + 1], x + 1, x + 1)
		return if c == "." then nil else c
	end

	local function cellKey(level, x, z)
		return level .. ":" .. x .. ":" .. z
	end

	-- Every edge is stored once, as the E or S side of the cell west or north of it.
	local function edgeKey(level, x, z, side)
		if side == "W" then
			return cellKey(level, x - 1, z) .. ":E"
		elseif side == "N" then
			return cellKey(level, x, z - 1) .. ":S"
		end
		return cellKey(level, x, z) .. ":" .. side
	end

	local function cellCenter(x, z, y)
		return Vector3.new(ox + (x + 0.5) * CELL, y or groundY, oz + (z + 0.5) * CELL)
	end

	-- The middle of a cell's edge at height y.
	local function edgeMid(x, z, side, y)
		return cellCenter(x, z, y) + DIR[side] * (CELL / 2)
	end

	-- Rooms.
	local rooms = {}
	for _, level in levels do
		for z = 0, d - 1 do
			for x = 0, w - 1 do
				local id = roomAt(level, x, z)
				if id then
					local info = layout.Rooms[id]
					assert(info, "HouseLayout: room " .. id .. " is not in Rooms")
					local room = rooms[id]
					if not room then
						room = { Id = id, Name = info.Name, Style = info.Style, Start = info.Start, Level = level, Cells = {}, Floor = floorTop(level) }
						rooms[id] = room
					end
					table.insert(room.Cells, { x, z })
				end
			end
		end
	end

	-- Stairs: the ramp cells, the open cells above them, and their gates.
	local ramp, hole, nearStair = {}, {}, {}
	local gates = {}
	local joins = {}
	for _, s in layout.Stairs or {} do
		local dx, dz = STEP[s.Rise][1], STEP[s.Rise][2]
		local x, z = s.At[1], s.At[2]
		local stair = { Level = s.Level, Rise = s.Rise, Length = s.Length, X = x, Z = z, Cost = s.Cost, Gate = s.Gate }
		stair.Low = roomAt(s.Level, x, z)
		stair.High = roomAt(s.Level + 1, x, z)
		for k = 0, s.Length - 1 do
			ramp[cellKey(s.Level, x + dx * k, z + dz * k)] = stair
			hole[cellKey(s.Level + 1, x + dx * k, z + dz * k)] = stair
		end
		nearStair[cellKey(s.Level, x - dx, z - dz)] = true
		nearStair[cellKey(s.Level + 1, x + dx * s.Length, z + dz * s.Length)] = true
		if s.Gate == "Bottom" then
			gates[edgeKey(s.Level, x, z, OPPOSITE[s.Rise])] = stair
		elseif s.Gate == "Top" then
			gates[edgeKey(s.Level + 1, x + dx * (s.Length - 1), z + dz * (s.Length - 1), s.Rise)] = stair
		else
			table.insert(joins, { stair.Low, stair.High })
		end
	end

	-- Openings on edges.
	local openings = {}
	local function addOpening(kind, o)
		local x, z = o.At[1], o.At[2]
		local there = roomAt(o.Level, x + STEP[o.Side][1], z + STEP[o.Side][2])
		local entry = { Kind = kind, Level = o.Level, X = x, Z = z, Side = o.Side, Here = roomAt(o.Level, x, z), There = there, Cost = o.Cost }
		openings[edgeKey(o.Level, x, z, o.Side)] = entry
		return entry
	end
	for _, o in layout.Doors or {} do
		addOpening("Door", o)
	end
	for _, o in layout.Arches or {} do
		local e = addOpening("Arch", o)
		table.insert(joins, { e.Here, e.There })
	end
	for _, o in layout.Windows or {} do
		addOpening("Window", o)
	end

	-- Zones: rooms joined by arches and open stairs.
	local parentOf = {}
	for id in rooms do
		parentOf[id] = id
	end
	local function find(id)
		while parentOf[id] ~= id do
			parentOf[id] = parentOf[parentOf[id]]
			id = parentOf[id]
		end
		return id
	end
	for _, pair in joins do
		parentOf[find(pair[1])] = find(pair[2])
	end
	local zones = {}
	for id, room in rooms do
		local zid = find(id)
		room.Zone = zid
		zones[zid] = zones[zid] or { Id = zid, Rooms = {}, Open = false }
		table.insert(zones[zid].Rooms, id)
	end
	local startRoom
	for id, room in rooms do
		if room.Start then
			startRoom = id
		end
	end
	assert(startRoom, "HouseLayout: no room has Start = true")
	zones[rooms[startRoom].Zone].Open = true

	-- Finishes.
	local function styleOf(id)
		return id and HOUSE.Styles[rooms[id].Style] or nil
	end
	local function isGlass(id)
		local st = styleOf(id)
		return st ~= nil and st.WallMaterial == Enum.Material.Glass
	end
	-- The finish of the skin facing room id (nil: outside, facing room other).
	local function skin(id, other)
		if id == nil then
			if isGlass(other) then
				local st = styleOf(other)
				return st.WallMaterial, st.Wall, st.WallTransparency or 0
			end
			return HOUSE.Exterior.Material, HOUSE.Exterior.Color, 0
		end
		local st = styleOf(id)
		return st.WallMaterial or Enum.Material.SmoothPlastic, st.Wall, st.WallTransparency or 0
	end

	-- Ground ---------------------------------------------------------------------------------------
	local yard = HOUSE.Yard
	local yardMin = Vector3.new(ox - yard, groundY, oz - yard)
	local yardMax = Vector3.new(ox + w * CELL + yard, groundY, oz + d * CELL + yard)
	local groundDepth = 4
	local function groundSlab(x0, z0, x1, z1)
		local size = Vector3.new(x1 - x0, groundDepth, z1 - z0)
		local p = newPart(fGround, "Ground", CFrame.new((x0 + x1) / 2, groundY - groundDepth / 2, (z0 + z1) / 2), size, HOUSE.Ground.Color, HOUSE.Ground.Material)
		return p
	end
	groundSlab(yardMin.X, yardMin.Z, yardMax.X, oz)
	groundSlab(yardMin.X, oz + d * CELL, yardMax.X, yardMax.Z)
	groundSlab(yardMin.X, oz, ox, oz + d * CELL)
	groundSlab(ox + w * CELL, oz, yardMax.X, oz + d * CELL)
	do
		local grid = {}
		for z = 0, d - 1 do
			grid[z] = {}
			for x = 0, w - 1 do
				local under = false
				for level = minLevel, -1 do
					if roomAt(level, x, z) then
						under = true
					end
				end
				if not under then
					grid[z][x] = "g"
				end
			end
		end
		for _, r in rectangles(grid, w, d) do
			groundSlab(ox + r.X0 * CELL, oz + r.Z0 * CELL, ox + (r.X1 + 1) * CELL, oz + (r.Z1 + 1) * CELL)
		end
	end

	-- Floors and roofs -------------------------------------------------------------------------------
	for k = minLevel, maxLevel + 1 do
		local grid = {}
		for z = 0, d - 1 do
			grid[z] = {}
			for x = 0, w - 1 do
				local up, down = roomAt(k, x, z), roomAt(k - 1, x, z)
				if (up or down) and not hole[cellKey(k, x, z)] then
					grid[z][x] = if up then up elseif isGlass(down) then "glass" else "roof"
				end
			end
		end
		local y = floorTop(k) - SLAB / 2
		for _, r in rectangles(grid, w, d) do
			local size = Vector3.new((r.X1 - r.X0 + 1) * CELL, SLAB, (r.Z1 - r.Z0 + 1) * CELL)
			local cf = CFrame.new(ox + (r.X0 + r.X1 + 1) / 2 * CELL, y, oz + (r.Z0 + r.Z1 + 1) / 2 * CELL)
			if r.Key == "roof" then
				newPart(fFloors, "Roof", cf, size, HOUSE.Roof.Color, HOUSE.Roof.Material)
			elseif r.Key == "glass" then
				local p = newPart(fFloors, "GlassRoof", cf, size, Color3.fromRGB(150, 200, 190), Enum.Material.Glass)
				p.Transparency = 0.6
			else
				local st = styleOf(r.Key)
				newPart(fFloors, "Floor_" .. r.Key, cf, size, st.FloorColor, st.Floor)
			end
		end
	end

	-- Walls ----------------------------------------------------------------------------------------
	local wallHeight = STORY - SLAB
	-- One skin of wall on an edge line. vertical: the line runs north-south at x = fixed.
	local function skins(vertical, fixed, a0, a1, y0, h0, h1, roomA, roomB)
		if a1 - a0 < 0.05 or h1 - h0 < 0.05 then
			return
		end
		for i = 1, 2 do
			-- (Indexing, not a table walk: roomA is nil on an outside edge.)
			local id = if i == 1 then roomA else roomB
			local other = if i == 1 then roomB else roomA
			local mat, color, transparency = skin(id, other)
			local offset = (if i == 1 then -1 else 1) * WALL / 4
			local size, pos
			if vertical then
				size = Vector3.new(WALL / 2, h1 - h0, a1 - a0)
				pos = Vector3.new(fixed + offset, y0 + (h0 + h1) / 2, (a0 + a1) / 2)
			else
				size = Vector3.new(a1 - a0, h1 - h0, WALL / 2)
				pos = Vector3.new((a0 + a1) / 2, y0 + (h0 + h1) / 2, fixed + offset)
			end
			local p = newPart(fWalls, "Wall", CFrame.new(pos), size, color, mat)
			p.Transparency = transparency
		end
	end

	local doors, windows, hatches = {}, {}, {}

	local function frameTrim(vertical, fixed, a0, a1, y0, top, bottom, color)
		-- Posts and a head round an opening, a little proud of both skins.
		local t = WALL + 0.3
		local function trim(b0, b1, h0, h1)
			local size = if vertical then Vector3.new(t, h1 - h0, b1 - b0) else Vector3.new(b1 - b0, h1 - h0, t)
			local pos = if vertical
				then Vector3.new(fixed, y0 + (h0 + h1) / 2, (b0 + b1) / 2)
				else Vector3.new((b0 + b1) / 2, y0 + (h0 + h1) / 2, fixed)
			ghost(newPart(fOpenings, "Trim", CFrame.new(pos), size, color, Enum.Material.Wood))
		end
		trim(a0 - 0.4, a0, bottom, top)
		trim(a1, a1 + 0.4, bottom, top)
		trim(a0 - 0.4, a1 + 0.4, top, top + 0.4)
	end

	-- A door leaf (or a stair's iron gate) filling an opening, with the prompt's anchor.
	local function makeDoor(kind, vertical, fixed, mid, y0, width, height, zoneA, zoneB, cost, normal)
		local leafModel = Instance.new("Model")
		leafModel.Name = kind
		local center = if vertical then Vector3.new(fixed, y0 + height / 2, mid) else Vector3.new(mid, y0 + height / 2, fixed)
		local along = if vertical then Vector3.zAxis else Vector3.xAxis
		local leafCf = CFrame.lookAt(center, center + normal)
		local leaf
		if kind == "Gate" then
			leaf = newPart(leafModel, "Leaf", leafCf, Vector3.new(width - 0.2, height, 0.3), IRON, Enum.Material.Metal)
			leaf.Transparency = 1
			local barHeight = math.min(height, 9)
			local barMid = -height / 2 + barHeight / 2
			for i = -3, 3 do
				local bar = newPart(leafModel, "Bar", leafCf * CFrame.new(i * (width - 0.6) / 6, barMid, 0), Vector3.new(0.3, barHeight, 0.3), IRON, Enum.Material.Metal)
				bar.CanCollide = false
				bar.CanQuery = false
			end
			for _, hgt in { 0.6, barHeight / 2, barHeight - 0.4 } do
				local rail = newPart(leafModel, "Rail", leafCf * CFrame.new(0, -height / 2 + hgt, 0), Vector3.new(width - 0.2, 0.35, 0.4), IRON, Enum.Material.Metal)
				rail.CanCollide = false
				rail.CanQuery = false
			end
		else
			leaf = newPart(leafModel, "Leaf", leafCf, Vector3.new(width - 0.2, height - 0.1, 0.5), HOUSE.Door.Color, Enum.Material.Wood)
			for _, hgt in { -height / 3, height / 3 } do
				ghost(newPart(leafModel, "Strap", leafCf * CFrame.new(0, hgt, 0), Vector3.new(width - 0.3, 0.4, 0.6), IRON, Enum.Material.Metal))
			end
			ghost(newPart(leafModel, "Knob", leafCf * CFrame.new(width / 2 - 1, -0.6, 0), Vector3.new(0.5, 0.5, 0.8), Color3.fromRGB(150, 120, 60), Enum.Material.Metal, Enum.PartType.Ball))
		end
		leafModel.PrimaryPart = leaf
		leafModel.Parent = fOpenings
		local door = {
			Id = #doors + 1,
			Kind = kind,
			Zones = { zoneA, zoneB },
			BaseCost = cost or 0,
			Cost = cost or 0,
			Leaf = leafModel,
			Center = center,
			Normal = normal,
			Along = along,
			Width = width,
			Height = height,
			Open = false,
		}
		table.insert(doors, door)
		return door
	end

	-- An edge with an opening cut into it.
	local function openingWall(level, vertical, fixed, start, x, z, roomA, roomB, opening)
		local y0 = floorTop(level)
		local kind = opening.Kind
		local spec = if kind == "Window" then HOUSE.Window elseif kind == "Door" then HOUSE.Door else HOUSE.Arch
		local half = spec.Width / 2
		local mid = start + CELL / 2
		local bottom = if kind == "Window" then spec.Sill else 0
		local top = bottom + spec.Height
		skins(vertical, fixed, start, mid - half, y0, 0, wallHeight, roomA, roomB)
		skins(vertical, fixed, mid + half, start + CELL, y0, 0, wallHeight, roomA, roomB)
		skins(vertical, fixed, mid - half, mid + half, y0, top, wallHeight, roomA, roomB)
		if bottom > 0 then
			skins(vertical, fixed, mid - half, mid + half, y0, 0, bottom, roomA, roomB)
		end
		frameTrim(vertical, fixed, mid - half, mid + half, y0, top, bottom, if kind == "Window" then DARK_WOOD else TRIM_INSIDE)

		local here = opening.Here
		local hx, hz = opening.X, opening.Z
		local out = DIR[opening.Side]
		if kind == "Door" then
			local normal = out
			makeDoor("Door", vertical, fixed, mid, y0, spec.Width, spec.Height, rooms[here].Zone, rooms[opening.There].Zone, opening.Cost, normal)
		elseif kind == "Window" then
			local center = edgeMid(hx, hz, opening.Side, y0 + bottom + spec.Height / 2)
			local window = {
				Id = #windows + 1,
				Room = here,
				Zone = rooms[here].Zone,
				Level = level,
				Center = center,
				SillTop = y0 + bottom,
				Normal = out,
				Inside = edgeMid(hx, hz, opening.Side, y0) - out * 3.2,
				Boards = {},
			}
			local base = edgeMid(hx, hz, opening.Side, groundY)
			if level == 0 then
				window.Outside = base + out * 3.2
			else
				window.Outside = base + out * 2.6
				window.Perch = base + out * 1.7 + Vector3.new(0, window.SillTop - groundY - 1.2, 0)
			end
			local spawn = base + out * Config.Zombie.SpawnOut
			window.Spawn = Vector3.new(
				math.clamp(spawn.X, yardMin.X + 6, yardMax.X - 6),
				groundY,
				math.clamp(spawn.Z, yardMin.Z + 6, yardMax.Z - 6)
			)
			window.RepairAt = window.Inside + Vector3.new(0, 3, 0)
			-- Boards nailed across the outside, a little crooked.
			local faceCf = CFrame.lookAt(center + out * (WALL / 2 + 0.2), center + out * 5)
			for i = 1, Config.Windows.Boards do
				local hgt = -spec.Height / 2 + (i - 0.5) * spec.Height / Config.Windows.Boards
				local tilt = math.rad(math.random(-9, 9))
				local board = newPart(fOpenings, "Board", faceCf * CFrame.new(0, hgt, -0.1 * (i % 2)) * CFrame.Angles(0, 0, tilt), Vector3.new(spec.Width + 1.2, 0.8, 0.25), Color3.fromRGB(118, 90, 60), Enum.Material.WoodPlanks)
				-- Shots go through a barricade (Call of Duty): boards only show how far in they are.
				board.CanCollide = false
				board.CanQuery = false
				board:SetAttribute("Home", board.CFrame)
				table.insert(window.Boards, board)
			end
			-- Players never climb out; zombies are carried through by their climb.
			local block = newPart(fOpenings, "PlayerBlock", CFrame.lookAt(center, center + out), Vector3.new(spec.Width, spec.Height, WALL), Color3.new(), Enum.Material.SmoothPlastic)
			block.Transparency = 1
			block.CanQuery = false
			block.CanTouch = false
			block.CollisionGroup = "PlayerBlock"
			-- Glass splinters in the frame.
			ghost(newPart(fOpenings, "Sill", CFrame.lookAt(edgeMid(hx, hz, opening.Side, y0 + bottom), edgeMid(hx, hz, opening.Side, y0 + bottom) + out) * CFrame.new(0, -0.15, 0), Vector3.new(spec.Width + 0.8, 0.3, WALL + 0.8), DARK_WOOD, Enum.Material.Wood))
			table.insert(windows, window)
		end
	end

	for _, level in levels do
		local y0 = floorTop(level)
		-- North-south lines, then east-west lines; runs of plain wall are merged.
		for pass = 1, 2 do
			local vertical = pass == 1
			local outerMax = if vertical then w - 1 else d - 1
			local innerMax = if vertical then d - 1 else w - 1
			for line = -1, outerMax do
				local runStart, runA, runB = nil, nil, nil
				local function flush(lastIndex)
					if runStart then
						local fixed = if vertical then ox + (line + 1) * CELL else oz + (line + 1) * CELL
						local base = if vertical then oz else ox
						skins(vertical, fixed, base + runStart * CELL, base + (lastIndex + 1) * CELL, y0, 0, wallHeight, runA, runB)
						runStart = nil
					end
				end
				for i = 0, innerMax + 1 do
					local x, z = (if vertical then line else i), (if vertical then i else line)
					local a, b, opening
					if i <= innerMax then
						a = roomAt(level, x, z)
						b = if vertical then roomAt(level, x + 1, z) else roomAt(level, x, z + 1)
						opening = openings[edgeKey(level, x, z, if vertical then "E" else "S")]
					end
					local isWall = i <= innerMax and a ~= b
					if isWall and not opening and runStart and runA == a and runB == b then
						continue
					end
					flush(i - 1)
					if isWall then
						if opening then
							local fixed = if vertical then ox + (line + 1) * CELL else oz + (line + 1) * CELL
							local start = if vertical then oz + z * CELL else ox + x * CELL
							openingWall(level, vertical, fixed, start, x, z, a, b, opening)
						else
							runStart, runA, runB = i, a, b
						end
					end
				end
			end
		end
		-- Posts where walls meet or end, so corners close.
		for vz = 0, d do
			for vx = 0, w do
				local function differs(ax, az, bx, bz)
					return roomAt(level, ax, az) ~= roomAt(level, bx, bz)
				end
				local north = differs(vx - 1, vz - 1, vx, vz - 1)
				local south = differs(vx - 1, vz, vx, vz)
				local west = differs(vx - 1, vz - 1, vx - 1, vz)
				local east = differs(vx, vz - 1, vx, vz)
				local count = (if north then 1 else 0) + (if south then 1 else 0) + (if west then 1 else 0) + (if east then 1 else 0)
				local straight = count == 2 and ((north and south) or (west and east))
				if count > 0 and not straight then
					local outside = not (roomAt(level, vx - 1, vz - 1) and roomAt(level, vx, vz - 1) and roomAt(level, vx - 1, vz) and roomAt(level, vx, vz))
					local pos = Vector3.new(ox + vx * CELL, y0 + wallHeight / 2, oz + vz * CELL)
					newPart(fWalls, "Post", CFrame.new(pos), Vector3.new(WALL + 0.2, wallHeight, WALL + 0.2), if outside then HOUSE.Trim.Color else TRIM_INSIDE, if outside then HOUSE.Trim.Material else Enum.Material.Wood)
				end
			end
		end
	end

	-- Stairs ---------------------------------------------------------------------------------------
	for _, s in layout.Stairs or {} do
		local dir = DIR[s.Rise]
		local x, z = s.At[1], s.At[2]
		local y0, y1 = floorTop(s.Level), floorTop(s.Level + 1)
		local run = s.Length * CELL
		local lowEdge = edgeMid(x, z, OPPOSITE[s.Rise], y0)
		local highEdge = lowEdge + dir * run + Vector3.new(0, y1 - y0, 0)
		local across = Vector3.new(dir.Z, 0, -dir.X)
		local width = CELL - 0.4
		-- The walking surface: one tilted slab, its top face running from edge to edge.
		local mid = (lowEdge + highEdge) / 2
		local slope = (highEdge - lowEdge).Magnitude
		local slabCf = CFrame.lookAt(mid, highEdge) * CFrame.new(0, -0.5, 0.5)
		local slab = newPart(fStairs, "Ramp", slabCf, Vector3.new(width, 1, slope + 1), WOOD, Enum.Material.WoodPlanks)
		slab:SetAttribute("Stair", true)
		ghost(newPart(fStairs, "Runner", CFrame.lookAt(mid, highEdge) * CFrame.new(0, 0.03, 0), Vector3.new(width * 0.55, 0.05, slope), Color3.fromRGB(110, 30, 36), Enum.Material.Fabric))
		local steps = math.floor((y1 - y0) / 1.25)
		for i = 1, steps - 1 do
			-- Thin dark lines across the slab, so the ramp reads as steps.
			local at = lowEdge:Lerp(highEdge, i / steps) + Vector3.new(0, 0.04, 0)
			ghost(newPart(fStairs, "Tread", CFrame.lookAt(at, at + dir), Vector3.new(width * 0.98, 0.08, 0.18), DARK_WOOD, Enum.Material.Wood))
		end
		-- Under it, solid blocks stepping up (below the slab), so nothing walks under the ramp.
		local blocks = 6
		for i = 1, blocks - 1 do
			local h = (y1 - y0) * i / blocks - 0.6
			local from = (i / blocks) * run
			local to = ((i + 1) / blocks) * run
			local center = lowEdge + dir * ((from + to) / 2) + Vector3.new(0, h / 2, 0)
			local size = if math.abs(dir.X) > 0.5 then Vector3.new(to - from, h, width) else Vector3.new(width, h, to - from)
			newPart(fStairs, "Under", CFrame.new(center), size, DARK_WOOD, Enum.Material.Wood)
		end
		-- Where a ramp side is open floor of its own room, a full-height wall closes it off, so the
		-- only way onto the ramp is past its foot (and its gate): nobody hops the side to skip it.
		local low = roomAt(s.Level, x, z)
		for k = 0, s.Length - 1 do
			local cx, cz = x + STEP[s.Rise][1] * k, z + STEP[s.Rise][2] * k
			for _, side in { "N", "S", "W", "E" } do
				if side ~= s.Rise and side ~= OPPOSITE[s.Rise] then
					local nx, nz = cx + STEP[side][1], cz + STEP[side][2]
					if roomAt(s.Level, nx, nz) == low and not ramp[cellKey(s.Level, nx, nz)] then
						local vertical = side == "E" or side == "W"
						local fixed = if vertical then ox + (cx + (if side == "E" then 1 else 0)) * CELL else oz + (cz + (if side == "S" then 1 else 0)) * CELL
						local start = if vertical then oz + cz * CELL else ox + cx * CELL
						skins(vertical, fixed, start, start + CELL, y0, 0, STORY, low, low)
					end
				end
			end
		end
		-- Round the hole upstairs: railings, except where you step off. With the gate at the top the
		-- ramp can be walked from below, so the hole gets full walls instead of railings.
		local dx, dz = STEP[s.Rise][1], STEP[s.Rise][2]
		local high = roomAt(s.Level + 1, x, z)
		local guard = if s.Gate == "Top" then STORY - SLAB else HOUSE.Railing
		for k = 0, s.Length - 1 do
			local cx, cz = x + dx * k, z + dz * k
			for side, step in STEP do
				local nx, nz = cx + step[1], cz + step[2]
				local isLanding = k == s.Length - 1 and side == s.Rise
				if not hole[cellKey(s.Level + 1, nx, nz)] and roomAt(s.Level + 1, nx, nz) == high and not isLanding then
					local m = edgeMid(cx, cz, side, y1 + guard / 2)
					local size = if side == "N" or side == "S" then Vector3.new(CELL, guard, 0.6) else Vector3.new(0.6, guard, CELL)
					newPart(fStairs, "Railing", CFrame.new(m), size, DARK_WOOD, Enum.Material.Wood)
				end
			end
		end
	end
	-- Gates across a stair end.
	for key, stair in gates do
		local parts = string.split(key, ":")
		local level, x, z, side = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3]), parts[4]
		local vertical = side == "E"
		local fixed = if vertical then ox + (x + 1) * CELL else oz + (z + 1) * CELL
		local mid = if vertical then oz + (z + 0.5) * CELL else ox + (x + 0.5) * CELL
		local y0 = floorTop(level)
		local normal = DIR[side]
		local zoneLow, zoneHigh = rooms[stair.Low].Zone, rooms[stair.High].Zone
		-- The bars are 9 studs tall; the invisible leaf behind them fills the edge to the ceiling.
		makeDoor("Gate", vertical, fixed, mid, y0, CELL - 0.6, STORY - SLAB - 0.2, zoneLow, zoneHigh, stair.Cost, normal)
	end

	-- Hatches ----------------------------------------------------------------------------------------
	for _, hch in layout.Hatches or {} do
		local x, z = hch.At[1], hch.At[2]
		local id = roomAt(hch.Level, x, z)
		local pos = cellCenter(x, z, floorTop(hch.Level))
		local holePart = ghost(newPart(fOpenings, "Hatch", CFrame.new(pos + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.06, 5, 5), Color3.fromRGB(10, 8, 8), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder))
		holePart.CanQuery = false
		for i = 1, 3 do
			local a = math.rad(i * 120 + math.random(-20, 20))
			local at = pos + Vector3.new(math.cos(a) * 2.6, 0.15, math.sin(a) * 2.6)
			ghost(newPart(fOpenings, "Splinter", CFrame.new(at) * CFrame.Angles(0, a, math.rad(math.random(-15, 15))), Vector3.new(0.5, 0.25, 2.2), Color3.fromRGB(90, 66, 44), Enum.Material.WoodPlanks))
		end
		table.insert(hatches, { Id = #hatches + 1, Room = id, Zone = rooms[id].Zone, Position = pos })
	end

	-- Spots -----------------------------------------------------------------------------------------
	local spots = { Box = {}, Perk = {}, Wall = {}, Altar = {}, Power = {} }
	local spotEdges = {}
	for _, s in layout.Spots or {} do
		local x, z = s.At[1], s.At[2]
		local id = roomAt(s.Level, x, z)
		local face = edgeMid(x, z, s.Side, floorTop(s.Level)) - DIR[s.Side] * (WALL / 2)
		table.insert(spots[s.Kind], {
			Kind = s.Kind,
			Room = id,
			Zone = rooms[id].Zone,
			Level = s.Level,
			Weapon = s.Weapon,
			CFrame = CFrame.lookAt(face, face - DIR[s.Side]),
		})
		spotEdges[cellKey(s.Level, x, z)] = true
	end

	-- Lamps -----------------------------------------------------------------------------------------
	local lamps = {}
	local off = HOUSE.Lamps.Off
	for id, room in rooms do
		local cells = {}
		for _, c in room.Cells do
			if not ramp[cellKey(room.Level, c[1], c[2])] then
				table.insert(cells, c)
			end
		end
		local count = if #cells > 0 then math.max(1, math.ceil(#room.Cells / HOUSE.LampCells)) else 0
		for i = 1, count do
			local c = cells[math.clamp(math.floor((i - 0.5) / count * #cells) + 1, 1, #cells)]
			if c then
				local pos = cellCenter(c[1], c[2], floorTop(room.Level + 1) - SLAB - 1.6)
				ghost(newPart(fLamps, "Chain", CFrame.new(pos + Vector3.new(0, 0.9, 0)), Vector3.new(0.15, 1.4, 0.15), IRON, Enum.Material.Metal))
				local bulb = ghost(newPart(fLamps, "Lamp", CFrame.new(pos), Vector3.new(1.3, 1.3, 1.3), off.Color, Enum.Material.Neon, Enum.PartType.Ball))
				local light = Instance.new("PointLight")
				light.Color = off.Color
				light.Brightness = off.Brightness
				light.Range = off.Range
				light.Shadows = true
				light.Parent = bulb
				table.insert(lamps, { Part = bulb, Light = light, Room = id })
			end
		end
	end

	-- Furniture against quiet walls (no opening, spot, stair or hatch in the cell) ---------------------
	local busy = {}
	local furnished = {}
	for key in ramp do
		busy[key] = true
	end
	for key in hole do
		busy[key] = true
	end
	for key in nearStair do
		busy[key] = true
	end
	for key in spotEdges do
		busy[key] = true
	end
	for _, hch in layout.Hatches or {} do
		busy[cellKey(hch.Level, hch.At[1], hch.At[2])] = true
	end
	for _, o in openings do
		busy[cellKey(o.Level, o.X, o.Z)] = true
		local nx, nz = o.X + STEP[o.Side][1], o.Z + STEP[o.Side][2]
		busy[cellKey(o.Level, nx, nz)] = true
	end
	for key in gates do
		local parts = string.split(key, ":")
		busy[cellKey(tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3]))] = true
	end
	for id, room in rooms do
		local kinds = STYLE_PROPS[styleOf(id).Props or room.Style]
		if kinds then
			local slots = {}
			for _, c in room.Cells do
				if not busy[cellKey(room.Level, c[1], c[2])] then
					for _, side in { "N", "E", "S", "W" } do
						local nx, nz = c[1] + STEP[side][1], c[2] + STEP[side][2]
						if roomAt(room.Level, nx, nz) ~= id then
							table.insert(slots, { c[1], c[2], side })
						end
					end
				end
			end
			-- One piece per cell, about one cell in two.
			local usedCells = {}
			local n = 0
			for i = #slots, 2, -1 do
				local j = math.random(i)
				slots[i], slots[j] = slots[j], slots[i]
			end
			for _, slot in slots do
				local key = slot[1] .. ":" .. slot[2]
				if not usedCells[key] and math.random() < 0.55 then
					usedCells[key] = true
					n += 1
					local kind = kinds[(n - 1) % #kinds + 1]
					local face = edgeMid(slot[1], slot[2], slot[3], floorTop(room.Level)) - DIR[slot[3]] * (WALL / 2)
					PROPS[kind](fProps, CFrame.lookAt(face, face - DIR[slot[3]]))
					-- A bed reaches past the cell's middle: floor points avoid furnished cells.
					furnished[cellKey(room.Level, slot[1], slot[2])] = true
				end
			end
		end
	end

	-- The yard: a stone wall all round, dead trees and graves out past where zombies gather ------------
	do
		local fh = HOUSE.Fence
		local stone = Color3.fromRGB(84, 82, 80)
		local function fence(x0, z0, x1, z1)
			local size = Vector3.new(math.max(2, x1 - x0), fh, math.max(2, z1 - z0))
			newPart(fYard, "Fence", CFrame.new((x0 + x1) / 2, groundY + fh / 2, (z0 + z1) / 2), size, stone, Enum.Material.Cobblestone)
			local barrier = newPart(fYard, "Barrier", CFrame.new((x0 + x1) / 2, groundY + 40, (z0 + z1) / 2), Vector3.new(size.X, 80, size.Z), stone, Enum.Material.SmoothPlastic)
			barrier.Transparency = 1
			barrier.CanQuery = false
		end
		fence(yardMin.X, yardMin.Z - 1, yardMax.X, yardMin.Z + 1)
		fence(yardMin.X, yardMax.Z - 1, yardMax.X, yardMax.Z + 1)
		fence(yardMin.X - 1, yardMin.Z, yardMin.X + 1, yardMax.Z)
		fence(yardMax.X - 1, yardMin.Z, yardMax.X + 1, yardMax.Z)
		local inner = Config.Zombie.SpawnOut + 9
		local function clearOf(pos)
			local gx = math.clamp(pos.X, ox, ox + w * CELL)
			local gz = math.clamp(pos.Z, oz, oz + d * CELL)
			local fromHouse = Vector3.new(pos.X - gx, 0, pos.Z - gz).Magnitude
			return fromHouse > inner and fromHouse < yard - 6
		end
		local placed = 0
		for _ = 1, 400 do
			if placed >= 34 then
				break
			end
			local pos = Vector3.new(yardMin.X + math.random() * (yardMax.X - yardMin.X), groundY, yardMin.Z + math.random() * (yardMax.Z - yardMin.Z))
			if clearOf(pos) then
				placed += 1
				if placed % 2 == 0 then
					local h = 14 + math.random() * 10
					local trunkCf = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(math.rad(math.random(-6, 6)), math.random() * 6.28, 0)
					newPart(fYard, "Tree", trunkCf, Vector3.new(1.8, h, 1.8), Color3.fromRGB(46, 38, 32), Enum.Material.Wood)
					for b = 1, 3 do
						local bcf = trunkCf * CFrame.new(0, h * (0.1 + b * 0.12), 0) * CFrame.Angles(0, b * 2.1, math.rad(40 + math.random(0, 25))) * CFrame.new(0, 3, 0)
						newPart(fYard, "Branch", bcf, Vector3.new(0.7, 6 + math.random() * 3, 0.7), Color3.fromRGB(46, 38, 32), Enum.Material.Wood)
					end
				else
					local cf = CFrame.new(pos + Vector3.new(0, 1.8, 0)) * CFrame.Angles(math.rad(math.random(-8, 8)), math.random() * 6.28, math.rad(math.random(-6, 6)))
					newPart(fYard, "Grave", cf, Vector3.new(3, 4, 0.8), Color3.fromRGB(96, 96, 100), Enum.Material.Slate)
				end
			end
		end
	end

	model.Parent = parent

	-- The House -------------------------------------------------------------------------------------
	local house = {
		Model = model,
		Layout = layout,
		Rooms = rooms,
		Zones = zones,
		StartRoom = startRoom,
		StartZone = rooms[startRoom].Zone,
		Doors = doors,
		Windows = windows,
		Hatches = hatches,
		Spots = spots,
		Lamps = lamps,
		YardMin = yardMin,
		YardMax = yardMax,
	}

	function house:FloorTop(level)
		return floorTop(level)
	end

	-- The room a point is in (a character's root counts for the floor it stands on), or nil.
	function house:RoomAt(pos)
		local level = math.floor((pos.Y - floorTop(0) + 2) / STORY)
		local x = math.floor((pos.X - ox) / CELL)
		local z = math.floor((pos.Z - oz) / CELL)
		local id = roomAt(level, x, z)
		return id and rooms[id] or nil
	end

	-- A room's cell middles to stand things on: never a stair, hatch, opening or spot cell; cells
	-- with furniture only when the bare ones run out.
	local function floorCells(room)
		local bare, furnishedList = {}, {}
		for _, c in room.Cells do
			local key = cellKey(room.Level, c[1], c[2])
			if not ramp[key] and not hole[key] and not busy[key] then
				table.insert(if furnished[key] then furnishedList else bare, cellCenter(c[1], c[2], room.Floor))
			end
		end
		return bare, furnishedList
	end

	-- count spots to stand on in the start room (cell middles, shuffled; they repeat if few).
	function house:StartPoints(count)
		local bare, furnishedList = floorCells(rooms[startRoom])
		for i = #bare, 2, -1 do
			local j = math.random(i)
			bare[i], bare[j] = bare[j], bare[i]
		end
		for _, p in furnishedList do
			table.insert(bare, p)
		end
		local out = {}
		for i = 1, count do
			table.insert(out, bare[(i - 1) % math.max(1, #bare) + 1])
		end
		return out
	end

	-- Up to count floor points in a room (cell middles), bare cells first, each group nearest `near` first.
	function house:FloorPoints(room, count, near)
		local bare, furnishedList = floorCells(room)
		local function byDistance(list)
			if near then
				table.sort(list, function(a, b)
					return (a - near).Magnitude < (b - near).Magnitude
				end)
			end
		end
		byDistance(bare)
		byDistance(furnishedList)
		local out = {}
		for _, list in { bare, furnishedList } do
			for _, p in list do
				if #out >= count then
					return out
				end
				table.insert(out, p)
			end
		end
		return out
	end

	return house
end

return HouseBuilder
```

### 9. `ServerStorage.Endless.Economy` (ModuleScript)

Points (player attribute Points), Double Pay and Scavenger multipliers, run stats.

```lua
-- Points (Call of Duty Zombies' economy). A player's points are the player attribute Points; the
-- HUD reads it. Add pays with this moment's multipliers: DOUBLE PAY (workspace DoublePayUntil)
-- and the Scavenger relic (player RelicPoints). Bonus pays a flat amount (power-ups). Spend takes
-- points if there are enough and tells the player's HUD when there aren't ("Broke").
-- Run stats are player attributes too: Kills, Headshots, Downs, Revives, Earned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)

local Economy = {}

local STATS = { "Kills", "Headshots", "Downs", "Revives", "Earned" }

function Economy.Get(player: Player): number
	return player:GetAttribute("Points") or 0
end

function Economy.Reset(player: Player, points: number?)
	player:SetAttribute("Points", points or Config.Run.StartPoints)
	for _, stat in STATS do
		player:SetAttribute(stat, 0)
	end
end

function Economy.Count(player: Player, stat: string, by: number?)
	player:SetAttribute(stat, (player:GetAttribute(stat) or 0) + (by or 1))
end

function Economy.Multiplier(player: Player): number
	local mult = 1 + (player:GetAttribute("RelicPoints") or 0)
	if (workspace:GetAttribute("DoublePayUntil") or 0) > workspace:GetServerTimeNow() then
		mult *= 2
	end
	return mult
end

function Economy.Add(player: Player, amount: number): number
	local paid = math.floor(amount * Economy.Multiplier(player) + 0.5)
	player:SetAttribute("Points", Economy.Get(player) + paid)
	Economy.Count(player, "Earned", paid)
	return paid
end

function Economy.Bonus(player: Player, amount: number)
	player:SetAttribute("Points", Economy.Get(player) + amount)
	Economy.Count(player, "Earned", amount)
end

function Economy.Spend(player: Player, amount: number): boolean
	local have = Economy.Get(player)
	if have < amount then
		Net.Get("Hud"):FireClient(player, "Broke")
		return false
	end
	player:SetAttribute("Points", have - amount)
	return true
end

-- Going down costs a share of what you have (Config.Player.Downed.PointsLost).
function Economy.Lose(player: Player, share: number)
	local have = Economy.Get(player)
	player:SetAttribute("Points", have - math.floor(have * share / 10 + 0.5) * 10)
end

return Economy
```

### 10. `ServerStorage.Endless.Survivors` (ModuleScript)

Player lives: spawning, regen, going down, revives, bleed-out, self-revive.

```lua
-- Players' lives in an Endless run (Call of Duty Zombies' rules; numbers: Config.Player).
-- Characters only load when the run says so (Players.CharacterAutoLoads is off): Spawn puts a
-- player in the house. Zombie swipes come through Damage; at no health you go down instead of
-- dying (character attribute Downed): you crawl, can't shoot, lose your perks (Survivors.Downed
-- fires, Perks clears them) and a share of your points. A teammate holds the Revive prompt on you
-- for ReviveTime (half with Lazarus Draught, set on their own client) to get you up. After BleedOut
-- you die and wait for the next intermission. Playing alone, Lazarus Draught (or a Second Wind
-- relic) gets you up by yourself after SelfReviveTime.
-- Health comes back RegenDelay seconds after the last hit (sooner with Fast Mend).
-- Player attribute InRun: this player is part of the run (set when they first spawn into it).
-- Character attributes: Downed, BleedOutAt (server time), SelfRevive (getting up alone).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)

local PLAYER = Config.Player
local DOWNED = PLAYER.Downed

local Survivors = {}
Survivors.Downed = Util.Signal() -- (player)
Survivors.Revived = Util.Signal() -- (player)
Survivors.Died = Util.Signal() -- (player)

local state = {} -- [player] = { LastHit, SpawnedAt, Prompt, Highlight, Loading, DownId }

local function get(player)
	local st = state[player]
	if not st then
		st = { LastHit = 0, SpawnedAt = 0 }
		state[player] = st
	end
	return st
end

function Survivors.Parts(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, root
end

function Survivors.IsAlive(player: Player): boolean
	local _, humanoid, root = Survivors.Parts(player)
	return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

function Survivors.IsDowned(player: Player): boolean
	return Survivors.IsAlive(player) and player.Character:GetAttribute("Downed") == true
end

function Survivors.IsStanding(player: Player): boolean
	return Survivors.IsAlive(player) and not player.Character:GetAttribute("Downed")
end

function Survivors.InRun(player: Player): boolean
	return player:GetAttribute("InRun") == true
end

function Survivors.RunPlayers(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if Survivors.InRun(p) then
			table.insert(list, p)
		end
	end
	return list
end

function Survivors.StandingPlayers(): { Player }
	local list = {}
	for _, p in Survivors.RunPlayers() do
		if Survivors.IsStanding(p) then
			table.insert(list, p)
		end
	end
	return list
end

-- Whether the run goes on: someone is standing, down but sure to get up alone, or still loading in
-- (Spawn yields in LoadCharacter; a run must not end before its players have arrived).
function Survivors.AnyoneUp(): boolean
	for _, p in Survivors.RunPlayers() do
		local st = state[p]
		if (st and st.Loading) or Survivors.IsStanding(p) or (Survivors.IsDowned(p) and p.Character:GetAttribute("SelfRevive")) then
			return true
		end
	end
	return false
end

local function studioFlag(name)
	return RunService:IsStudio() and workspace:GetAttribute(name) == true
end

function Survivors.MaxHealthFor(player: Player): number
	local base = if player:GetAttribute("Perk_Bulwark") then Config.Perks.List.Bulwark.Health else PLAYER.MaxHealth
	return base + (player:GetAttribute("RelicHealth") or 0)
end

function Survivors.RefreshMaxHealth(player: Player)
	local _, humanoid = Survivors.Parts(player)
	if humanoid and humanoid.Health > 0 then
		local max = Survivors.MaxHealthFor(player)
		local gained = max - humanoid.MaxHealth
		humanoid.MaxHealth = max
		if gained > 0 and not player.Character:GetAttribute("Downed") then
			humanoid.Health = math.min(max, humanoid.Health + gained)
		end
	end
end

function Survivors.WalkSpeed(player: Player): number
	return PLAYER.WalkSpeed + (player:GetAttribute("RelicSpeed") or 0)
end

-- Loads a character for player standing at `at` (a floor point). Yields until it stands there.
function Survivors.Spawn(player: Player, at: Vector3)
	local st = get(player)
	player:SetAttribute("InRun", true)
	st.Loading = true
	-- With streaming on (a new place's default), get the house round the spot to the client first.
	if workspace.StreamingEnabled then
		pcall(player.RequestStreamAroundAsync, player, at, 10)
	end
	local loaded = pcall(player.LoadCharacter, player)
	local character = player.Character
	local humanoid = loaded and character and character:WaitForChild("Humanoid", 10)
	local root = loaded and character and character:WaitForChild("HumanoidRootPart", 10)
	st.Loading = nil
	if not humanoid or not root then
		return nil
	end
	character:PivotTo(CFrame.new(at + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	humanoid.MaxHealth = Survivors.MaxHealthFor(player)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = Survivors.WalkSpeed(player)
	humanoid.BreakJointsOnDeath = false
	st.SpawnedAt = os.clock()
	st.LastHit = 0
	humanoid.Died:Once(function()
		if st.Prompt then
			st.Prompt:Destroy()
			st.Prompt = nil
		end
		if st.Highlight then
			st.Highlight:Destroy()
			st.Highlight = nil
		end
		character:SetAttribute("Downed", nil)
		Survivors.Died:Fire(player)
	end)
	return character
end

function Survivors.Heal(player: Player, amount: number)
	local _, humanoid = Survivors.Parts(player)
	if humanoid and Survivors.IsStanding(player) then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

-- A zombie's swipe (or anything else that hurts a player).
function Survivors.Damage(player: Player, amount: number)
	if studioFlag("EndlessGod") or not Survivors.IsStanding(player) then
		return
	end
	local st = get(player)
	local now = os.clock()
	if now - st.SpawnedAt < PLAYER.SpawnGrace or now - st.LastHit < PLAYER.HitGrace then
		return
	end
	st.LastHit = now
	local armor = math.min(player:GetAttribute("RelicArmor") or 0, Config.Relics.Pool.LeadBelly.Cap)
	amount *= 1 - armor
	local _, humanoid, root = Survivors.Parts(player)
	Sfx.Play("Player/Hurt", { Position = root.Position })
	Net.Get("Hud"):FireClient(player, "Hurt")
	if humanoid.Health - amount <= 0.5 then
		Survivors.Down(player)
	else
		humanoid.Health -= amount
	end
end

function Survivors.Down(player: Player)
	local character, humanoid, root = Survivors.Parts(player)
	if not Survivors.IsStanding(player) then
		return
	end
	local st = get(player)
	-- This fall's number: the timers below only act on the fall that started them.
	st.DownId = (st.DownId or 0) + 1
	local downId = st.DownId
	-- Getting up alone: Lazarus Draught when alone, else a Second Wind relic.
	local selfRevive = false
	if #Survivors.RunPlayers() == 1 and player:GetAttribute("Perk_Lazarus") then
		selfRevive = true
	elseif (player:GetAttribute("RelicSelfRevives") or 0) > 0 then
		player:SetAttribute("RelicSelfRevives", player:GetAttribute("RelicSelfRevives") - 1)
		selfRevive = true
	end

	character:SetAttribute("Downed", true)
	character:SetAttribute("SelfRevive", selfRevive)
	character:SetAttribute("BleedOutAt", workspace:GetServerTimeNow() + DOWNED.BleedOut)
	humanoid.Health = 1
	humanoid.WalkSpeed = DOWNED.Speed
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:UnequipTools()
	Economy.Lose(player, DOWNED.PointsLost)
	Economy.Count(player, "Downs")
	Sfx.Play("Player/Down", { Position = root.Position })
	Net.Get("Hud"):FireAllClients("Down", player.DisplayName)
	Survivors.Downed:Fire(player)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(200, 30, 30)
	highlight.OutlineColor = Color3.fromRGB(255, 80, 70)
	highlight.FillTransparency = 0.75
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
	st.Highlight = highlight

	local prompt = Util.Prompt(root, "Revive", player.DisplayName, DOWNED.ReviveTime, DOWNED.ReviveRange)
	prompt.Name = "RevivePrompt"
	prompt:SetAttribute("For", player.UserId)
	prompt.Triggered:Connect(function(by)
		if by ~= player and Survivors.IsStanding(by) and Survivors.IsDowned(player) then
			Economy.Count(by, "Revives")
			Survivors.Revive(player)
		end
	end)
	st.Prompt = prompt

	if selfRevive then
		task.delay(DOWNED.SelfReviveTime, function()
			if st.DownId == downId and character.Parent and Survivors.IsDowned(player) then
				Survivors.Revive(player)
			end
		end)
	else
		task.delay(DOWNED.BleedOut, function()
			if st.DownId == downId and character.Parent and Survivors.IsDowned(player) then
				humanoid.Health = 0
			end
		end)
	end
end

function Survivors.Revive(player: Player)
	local character, humanoid, root = Survivors.Parts(player)
	if not Survivors.IsDowned(player) then
		return
	end
	local st = get(player)
	if st.Prompt then
		st.Prompt:Destroy()
		st.Prompt = nil
	end
	if st.Highlight then
		st.Highlight:Destroy()
		st.Highlight = nil
	end
	character:SetAttribute("Downed", nil)
	character:SetAttribute("SelfRevive", nil)
	character:SetAttribute("BleedOutAt", nil)
	humanoid.MaxHealth = Survivors.MaxHealthFor(player)
	humanoid.Health = humanoid.MaxHealth * DOWNED.ReviveHealth
	humanoid.WalkSpeed = Survivors.WalkSpeed(player)
	humanoid.JumpPower = 50
	humanoid.JumpHeight = 7.2
	st.SpawnedAt = os.clock() - PLAYER.SpawnGrace + 1.5 -- a breath before the next hit
	Sfx.Play("Player/GetUp", { Position = root.Position })
	Survivors.Revived:Fire(player)
end

-- Run start: forget last run's state (attributes from perks and relics are cleared by their owners).
function Survivors.Reset(player: Player)
	local st = get(player)
	st.LastHit, st.SpawnedAt = 0, 0
	player:SetAttribute("InRun", nil)
end

function Survivors.Start()
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, st in state do
			local _, humanoid = Survivors.Parts(player)
			if humanoid and Survivors.IsStanding(player) and humanoid.Health < humanoid.MaxHealth then
				local delay = PLAYER.RegenDelay * (1 - math.min(player:GetAttribute("RelicRegen") or 0, Config.Relics.Pool.FastMend.Cap))
				if now - st.LastHit >= delay then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + PLAYER.RegenRate * dt)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)
	-- Every character part in the Players collision group (window blockers stop players only).
	local function setGroup(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
	local function onCharacter(character)
		for _, d in character:GetDescendants() do
			setGroup(d)
		end
		character.DescendantAdded:Connect(setGroup)
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

return Survivors
```

### 11. `ServerStorage.Endless.Arsenal` (ModuleScript)

Guns as Tools, slots, ammo, the server's checks on every shot, the knife.

```lua
-- Guns on the server: what each player carries, their ammo, and whether a shot a client reports
-- counts. A gun is a Tool built from GunModel (attributes: Weapon, Mag, Reserve, Boosts, Level,
-- Reloading, ReloadEnd; Shared Weapons does the sums). You carry Config.Arsenal.Slots guns (three
-- with Packmule Tonic); taking another with full hands swaps out the one you hold.
--
-- The client shoots (StarterPlayerScripts.EndlessClient) and sends Weapon "Fire" with where from,
-- the direction of each pellet and the zombie part it saw each one hit (or false). The server checks
-- the ammo, the rate (a token bucket: the gun's rate on average, a couple of shots of slack for
-- bunched-up packets), that nothing solid stands between the head and the origin, and that the
-- pellets keep to the gun's cone; it casts every pellet again, and takes the client's word for a hit
-- its own cast missed only if the part is close to the ray and no wall is in between (lag). Hits go
-- to Arsenal.DamageZombie (EndlessServer wires it to Horde.Damage and the points).
-- Melee is Call of Duty's knife (Config.Arsenal.Melee).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Weapons = require(ReplicatedStorage.Endless.Weapons)
local GunModel = require(ReplicatedStorage.Endless.GunModel)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Survivors = require(ServerStorage.Endless.Survivors)

local ARSENAL = Config.Arsenal
local CHECK = ARSENAL.Validation

local Arsenal = {}
-- (player, zombie model, part, damage, head, melee, direction, paysHit): set by EndlessServer.
Arsenal.DamageZombie = nil

local budget = {} -- [player] = {Credit, At}: shots the player may fire right now
local lastMelee = {} -- [player] = os.clock()
local BURST = 2

-- Tools ------------------------------------------------------------------------------------------

function Arsenal.MakeTool(id: string, boosts: string?): Tool
	local cfg = Config.Weapons[id]
	local tool = Instance.new("Tool")
	tool.Name = cfg.Name
	tool.ToolTip = cfg.Name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	local level = #Weapons.ParseBoosts(boosts)
	local model = GunModel.Build(id, { Level = level })
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()
	local stats = Weapons.Stats(id, boosts, nil)
	tool:SetAttribute("Weapon", id)
	tool:SetAttribute("Boosts", boosts or "")
	tool:SetAttribute("Level", level)
	tool:SetAttribute("Mag", stats.Mag)
	tool:SetAttribute("Reserve", stats.Reserve)
	return tool
end

-- Every gun the player carries, in slot order (backpack and hand).
function Arsenal.Tools(player: Player): { Tool }
	local list = {}
	local function scan(container)
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("Weapon") then
					table.insert(list, t)
				end
			end
		end
	end
	scan(player.Character)
	scan(player:FindFirstChildOfClass("Backpack"))
	table.sort(list, function(a, b)
		return (a:GetAttribute("Slot") or 0) < (b:GetAttribute("Slot") or 0)
	end)
	return list
end

function Arsenal.Held(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return if tool and tool:GetAttribute("Weapon") then tool else nil
end

function Arsenal.Find(player: Player, id: string): Tool?
	for _, t in Arsenal.Tools(player) do
		if t:GetAttribute("Weapon") == id then
			return t
		end
	end
	return nil
end

function Arsenal.SlotCount(player: Player): number
	return if player:GetAttribute("Perk_Packmule") then Config.Perks.List.Packmule.Slots else ARSENAL.Slots
end

-- Fills a tool's magazine and reserve to this player's sizes.
function Arsenal.Fill(player: Player, tool: Tool)
	local stats = Weapons.ForTool(tool, player)
	if stats then
		tool:SetAttribute("Mag", stats.Mag)
		tool:SetAttribute("Reserve", stats.Reserve)
	end
end

-- Puts a gun in the player's hands. With every slot full, the gun in hand (or the last) goes.
-- slot: keep this slot number (a gun coming back from the altar).
function Arsenal.Give(player: Player, id: string, boosts: string?, slot: number?): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or not Config.Weapons[id] then
		return nil
	end
	local tools = Arsenal.Tools(player)
	slot = slot or #tools + 1
	if #tools >= Arsenal.SlotCount(player) then
		local out = Arsenal.Held(player) or tools[#tools]
		slot = out:GetAttribute("Slot") or #tools
		out:Destroy()
	end
	local tool = Arsenal.MakeTool(id, boosts)
	tool:SetAttribute("Slot", slot)
	Arsenal.Fill(player, tool)
	tool.Parent = backpack
	local _, humanoid = Survivors.Parts(player)
	if humanoid and Survivors.IsStanding(player) then
		humanoid:EquipTool(tool)
	end
	return tool
end

-- A fresh life: just the starting gun.
function Arsenal.GiveStart(player: Player)
	for _, t in Arsenal.Tools(player) do
		t:Destroy()
	end
	Arsenal.Give(player, ARSENAL.Start)
end

-- Going down without Packmule any more: the gun past the second slot is lost (Call of Duty).
function Arsenal.Trim(player: Player)
	local tools = Arsenal.Tools(player)
	for i = Arsenal.SlotCount(player) + 1, #tools do
		tools[i]:Destroy()
	end
end

-- RESUPPLY: every gun of every player in the run gets a full reserve.
function Arsenal.ResupplyAll()
	for _, p in Survivors.RunPlayers() do
		for _, t in Arsenal.Tools(p) do
			local stats = Weapons.ForTool(t, p)
			if stats then
				t:SetAttribute("Reserve", stats.Reserve)
			end
		end
	end
end

-- Relic or perk changes the sizes: top up so nothing reads over its new maximum.
function Arsenal.Refresh(player: Player)
	for _, t in Arsenal.Tools(player) do
		local stats = Weapons.ForTool(t, player)
		if stats then
			t:SetAttribute("Mag", math.min(t:GetAttribute("Mag") or 0, stats.Mag))
			t:SetAttribute("Reserve", math.min(t:GetAttribute("Reserve") or 0, stats.Reserve))
		end
	end
end

-- Shots -----------------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function ignoreList(extra)
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local fx = workspace:FindFirstChild("Fx")
	if fx then
		table.insert(list, fx)
	end
	local drops = workspace:FindFirstChild("Drops")
	if drops then
		table.insert(list, drops)
	end
	for _, m in extra do
		table.insert(list, m)
	end
	return list
end

local function zombieOf(part: Instance?)
	local zombies = workspace:FindFirstChild("Zombies")
	local node = part
	while node and node.Parent and node.Parent ~= zombies do
		node = node.Parent
	end
	if node and node.Parent == zombies and node:IsA("Model") then
		local hum = node:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return node
		end
	end
	return nil
end

-- One pellet: up to `pierce` zombies along the ray. Returns {zombie, part, position} and the end point.
local function castPellet(origin, dir, range, pierce, claim)
	local hits = {}
	local skip = {}
	local from = origin
	local left = range
	local stop = origin + dir * range
	while left > 0 and #hits < pierce do
		rayParams.FilterDescendantsInstances = ignoreList(skip)
		local result = workspace:Raycast(from, dir * left, rayParams)
		if not result then
			break
		end
		local zombie = zombieOf(result.Instance)
		if not zombie then
			stop = result.Position
			break
		end
		table.insert(hits, { Zombie = zombie, Part = result.Instance, Position = result.Position })
		table.insert(skip, zombie)
		left -= (result.Position - from).Magnitude
		from = result.Position
	end
	-- Lag: the client saw this zombie part on the ray; the server's copy has moved a little.
	if #hits == 0 and typeof(claim) == "Instance" and claim:IsA("BasePart") then
		local zombie = zombieOf(claim)
		if zombie then
			local to = claim.Position - origin
			local along = to:Dot(dir)
			local off = (to - dir * along).Magnitude
			local wallAt = (stop - origin).Magnitude
			if along > 0 and along <= range and along <= wallAt + 2 and off <= claim.Size.Magnitude / 2 + CHECK.ClaimSlack then
				table.insert(hits, { Zombie = zombie, Part = claim, Position = origin + dir * along })
				stop = origin + dir * along
			end
		end
	end
	if #hits > 0 then
		stop = hits[#hits].Position
	end
	return hits, stop
end

local function onFire(player, tool, origin, directions, claims)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or tool.Parent ~= player.Character then
		return
	end
	if typeof(origin) ~= "Vector3" or type(directions) ~= "table" or not Survivors.IsStanding(player) then
		return
	end
	local stats = Weapons.ForTool(tool, player)
	if not stats or tool:GetAttribute("Reloading") then
		return
	end
	-- The rate: credit fills at the gun's rate, up to BURST shots banked; a shot needs RateSlack of one.
	local now = os.clock()
	local b = budget[player]
	if not b then
		b = { Credit = BURST, At = now }
		budget[player] = b
	end
	b.Credit = math.min(BURST, b.Credit + (now - b.At) * stats.Rpm / 60)
	b.At = now
	if b.Credit < CHECK.RateSlack then
		return
	end
	local mag = tool:GetAttribute("Mag") or 0
	if mag <= 0 then
		return
	end
	local head = player.Character:FindFirstChild("Head")
	if not head or (origin - head.Position).Magnitude > CHECK.MaxOriginOffset then
		return
	end
	-- Not from the far side of a wall or a shut door.
	rayParams.FilterDescendantsInstances = ignoreList({})
	if workspace:Raycast(head.Position, origin - head.Position, rayParams) then
		return
	end
	b.Credit -= 1
	tool:SetAttribute("Mag", mag - 1)
	player.Character:SetAttribute("FiredAt", workspace:GetServerTimeNow())

	local ends = {}
	local dealt = {} -- [zombie] = true: one points payout per zombie per shot
	local first = nil
	local cone = math.rad(2 * stats.Spread.Hip + CHECK.ConeSlack)
	for i = 1, math.min(#directions, stats.Pellets) do
		local dir = directions[i]
		if typeof(dir) == "Vector3" and dir.Magnitude > 0.5 then
			dir = dir.Unit
			-- Every pellet keeps to the gun's cone round the first one.
			first = first or dir
			if math.acos(math.clamp(dir:Dot(first), -1, 1)) > cone then
				continue
			end
			local claim = type(claims) == "table" and claims[i] or nil
			local hits, stop = castPellet(origin, dir, stats.Range, stats.Pierce, claim)
			table.insert(ends, stop)
			for _, h in hits do
				local isHead = h.Part.Name == "Head"
				local amount = stats.Damage * (if isHead then stats.Head else 1)
				if Arsenal.DamageZombie then
					Arsenal.DamageZombie(player, h.Zombie, h.Part, amount, isHead, false, dir, not dealt[h.Zombie])
				end
				dealt[h.Zombie] = true
			end
		end
	end
	-- The shooter hears and sees their own shot at once (EndlessClient); everyone else from this.
	Net.Get("Fx"):FireAllClients("Shot", player.UserId, stats.Id, origin, ends)
end

local function onReload(player, tool)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or tool.Parent ~= player.Character or not Survivors.IsStanding(player) then
		return
	end
	local stats = Weapons.ForTool(tool, player)
	if not stats or tool:GetAttribute("Reloading") then
		return
	end
	local mag, reserve = tool:GetAttribute("Mag") or 0, tool:GetAttribute("Reserve") or 0
	if mag >= stats.Mag or reserve <= 0 then
		return
	end
	tool:SetAttribute("Reloading", true)
	tool:SetAttribute("ReloadEnd", workspace:GetServerTimeNow() + stats.Reload)
	local character = player.Character
	task.delay(stats.Reload, function()
		if not tool.Parent then
			return
		end
		tool:SetAttribute("Reloading", nil)
		-- Put away, or the player went down, mid-reload: nothing goes in (Call of Duty).
		if tool.Parent ~= character or not Survivors.IsStanding(player) then
			return
		end
		local now = Weapons.ForTool(tool, player)
		local m, r = tool:GetAttribute("Mag") or 0, tool:GetAttribute("Reserve") or 0
		local take = math.min(now.Mag - m, r)
		tool:SetAttribute("Mag", m + take)
		tool:SetAttribute("Reserve", r - take)
	end)
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

local function onMelee(player)
	if not Survivors.IsStanding(player) then
		return
	end
	local now = os.clock()
	if now - (lastMelee[player] or 0) < ARSENAL.Melee.Cooldown * CHECK.RateSlack then
		return
	end
	lastMelee[player] = now
	local _, _, root = Survivors.Parts(player)
	local zombies = workspace:FindFirstChild("Zombies")
	if not root or not zombies then
		return
	end
	local look = Util.Flat(root.CFrame.LookVector).Unit
	local best, bestD = nil, ARSENAL.Melee.Range
	for _, z in zombies:GetChildren() do
		local zr = z:FindFirstChild("HumanoidRootPart")
		local hum = z:FindFirstChildOfClass("Humanoid")
		if zr and hum and hum.Health > 0 then
			local to = zr.Position - root.Position
			local d = to.Magnitude
			local flat = Util.Flat(to)
			local inArc = flat.Magnitude < 0.5 or look:Dot(flat.Unit) >= math.cos(math.rad(ARSENAL.Melee.Arc / 2))
			if d < bestD and inArc and math.abs(to.Y) < 5 then
				best, bestD = z, d
			end
		end
	end
	Sfx.Play("Common/Whiz", { Position = root.Position, Speed = 0.8 })
	if best and Arsenal.DamageZombie then
		local torso = best:FindFirstChild("Torso") or best.PrimaryPart
		local damage = ARSENAL.Melee.Damage * (1 + (player:GetAttribute("RelicDamage") or 0))
		Arsenal.DamageZombie(player, best, torso, damage, false, true, look, true)
	end
end

function Arsenal.Start()
	local remote = Net.Get("Weapon")
	remote.OnServerEvent:Connect(function(player, action, ...)
		if action == "Fire" then
			onFire(player, ...)
		elseif action == "Reload" then
			onReload(player, ...)
		elseif action == "Melee" then
			onMelee(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		budget[player] = nil
		lastMelee[player] = nil
	end)
end

return Arsenal
```

### 12. `ServerStorage.Endless.Windows` (ModuleScript)

Boarded windows: zombies tear boards off, players hold Repair to nail them back.

```lua
-- Boarded windows (Call of Duty Zombies' barriers). Each window of the House has Config.Windows.Boards
-- boards on the outside; zombies tear them off one at a time (Rip) and climb in once none is left.
-- Inside, a player holds the Repair prompt: one hold nails every missing board back, a board at a
-- time, paying Config.Points.Repair a board up to RepairCap boards a round (Call of Duty's cap).
-- HAMMER AND NAILS (RepairAll) puts every board in the house back at once.
-- Window fields used here: Boards (parts with a Home attribute), RepairAt, Load (zombies on their
-- way to it), ClimbFreeAt (os.clock() when the next zombie may climb through).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Endless.Config)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)

local Windows = {}

local house
local repairs = {} -- [player] = boards paid for this round

local function fx()
	return workspace:FindFirstChild("Fx") or workspace
end

function Windows.Torn(window): number
	local n = 0
	for _, b in window.Boards do
		if b:GetAttribute("Torn") then
			n += 1
		end
	end
	return n
end

function Windows.Broken(window): boolean
	return Windows.Torn(window) >= #window.Boards
end

-- One board off, thrown toward the zombie. False if there was none left.
function Windows.Rip(window, fromPos: Vector3): boolean
	for i = #window.Boards, 1, -1 do
		local board = window.Boards[i]
		if not board:GetAttribute("Torn") then
			board:SetAttribute("Torn", true)
			local loose = board:Clone()
			loose:SetAttribute("Torn", nil)
			loose.Anchored = false
			loose.CanCollide = true
			loose.CollisionGroup = "Corpses"
			loose.Parent = fx()
			local away = Util.Flat(fromPos - board.Position)
			away = if away.Magnitude > 0.1 then away.Unit else window.Normal
			loose.AssemblyLinearVelocity = away * (10 + math.random() * 8) + Vector3.new(0, 8, 0)
			loose.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12
			Debris:AddItem(loose, 8)
			board.Transparency = 1
			Sfx.Play("World/WoodBreak", { Position = board.Position, Volume = 0.7 })
			return true
		end
	end
	return false
end

local function nail(board)
	board:SetAttribute("Torn", nil)
	local home = board:GetAttribute("Home")
	board.CFrame = home * CFrame.new(0, 0, -0.6)
	board.Transparency = 0
	TweenService:Create(board, TweenInfo.new(0.1), { CFrame = home }):Play()
	Sfx.Play("World/PlankDrop", { Position = board.Position })
end

function Windows.RepairAll()
	for _, window in house.Windows do
		for _, b in window.Boards do
			if b:GetAttribute("Torn") then
				nail(b)
			end
		end
	end
end

function Windows.NewRound()
	table.clear(repairs)
end

function Windows.Setup(run, maid)
	house = run.House
	table.clear(repairs)
	for _, window in house.Windows do
		window.Load = 0
		window.ClimbFreeAt = 0
		local anchor = Instance.new("Part")
		anchor.Name = "RepairPoint"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Position = window.RepairAt
		anchor.Parent = house.Model
		local prompt = Util.Prompt(anchor, "Repair", "Window", Config.Windows.HoldTime, Config.Windows.Range)
		prompt.Enabled = false
		window.Prompt = prompt
		local repairing = false
		prompt.Triggered:Connect(function(player)
			if repairing or not Survivors.IsStanding(player) then
				return
			end
			repairing = true
			prompt.Enabled = false
			for _, b in window.Boards do
				if not Survivors.IsStanding(player) then
					break
				end
				if b:GetAttribute("Torn") then
					nail(b)
					local done = repairs[player] or 0
					if run.State == "Wave" and done < Config.Points.RepairCap then
						repairs[player] = done + 1
						Economy.Add(player, Config.Points.Repair)
					end
					task.wait(0.12)
				end
			end
			repairing = false
		end)
		maid:Add(task.spawn(function()
			while anchor.Parent do
				local torn = Windows.Torn(window)
				prompt.Enabled = torn > 0 and not repairing
				prompt.HoldDuration = Config.Windows.HoldTime + 0.15 * torn
				task.wait(0.25)
			end
		end))
	end
end

return Windows
```

### 13. `ServerStorage.Endless.Horde` (ModuleScript)

The zombies: R6 rig from blocks, rising, windows, hunting, the swipe, limbs, ragdoll.

```lua
-- The zombies (numbers: Config.Zombie, Config.Rounds, Config.Specials). A zombie is a classic R6
-- rig built from blocks (no assets), so the reference runs in an empty place; clients pose it
-- (StarterPlayerScripts.EndlessFx: arms out, legs walking, the swipe, the crawl).
-- Spawn(entry, kind, health, speed) brings one up out of the ground outside a window (entry.Window)
-- or out of a floor hatch (entry.Hatch). Through a window it walks up to the boards, tears them off
-- one by one (Windows.Rip), swipes at anyone holding the window from inside, and climbs in over the
-- sill; for an upper window it first climbs the wall to hang outside it. Inside it hunts the nearest
-- standing player (straight at them when close and in sight, else along a PathfindingService path)
-- and swipes: a windup the client sees (model attribute SwingAt), then it lands if you are still in
-- reach and in front of it.
-- Damage(model, amount, part, player, opts) hurts one; an arm or leg that has taken its share tears
-- off (heads never do; owner: less gore on faces), and a zombie with no legs crawls. Blood is green.
-- Kinds: "Walker", "Runner", "Brute" (big and slow), "Crawler" (on its arms from the start).
-- Model attributes for clients: Kind, SwingAt (server time), Crawling, Dead.
-- Signals: Killed (model, killer or nil, info {Head, Melee, Kind, Position}); Lost (a stuck zombie was
-- taken away; the round owes one more).

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Windows = require(ServerStorage.Endless.Windows)
local Survivors = require(ServerStorage.Endless.Survivors)

local ZOMBIE = Config.Zombie
local ATTACK = ZOMBIE.Attack
local NAV = ZOMBIE.Navigation
local BRUTE = Config.Specials.Brute
local SOUNDS = ZOMBIE.Sounds

local Horde = {}
Horde.Killed = Util.Signal()
Horde.Lost = Util.Signal()

local folder
local alive = {} -- [model] = z
local count = 0
local templates = {} -- [scale] = Model

local LIMBS = { ["Left Arm"] = "Arm", ["Right Arm"] = "Arm", ["Left Leg"] = "Leg", ["Right Leg"] = "Leg" }

-- The rig --------------------------------------------------------------------------------------

local R6 = {
	-- name, part0, part1, C0, C1 (the classic R6 joints)
	{ "RootJoint", "HumanoidRootPart", "Torso", CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	{ "Neck", "Torso", "Head", CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	{ "Right Shoulder", "Torso", "Right Arm", CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	{ "Left Shoulder", "Torso", "Left Arm", CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	{ "Right Hip", "Torso", "Right Leg", CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	{ "Left Hip", "Torso", "Left Leg", CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
}

local function buildRig(scale: number): Model
	local model = Instance.new("Model")
	model.Name = "Zombie"
	local parts = {}
	local function limb(name, size)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * scale
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CollisionGroup = "Zombies"
		p.Parent = model
		parts[name] = p
		return p
	end
	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1))
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = false
	limb("Torso", Vector3.new(2, 2, 1))
	local head = limb("Head", Vector3.new(2, 1, 1))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	limb("Left Arm", Vector3.new(1, 2, 1))
	limb("Right Arm", Vector3.new(1, 2, 1))
	limb("Left Leg", Vector3.new(1, 2, 1))
	limb("Right Leg", Vector3.new(1, 2, 1))
	root.CFrame = CFrame.new()
	for _, j in R6 do
		local c0 = CFrame.new(j[4].Position * scale) * j[4].Rotation
		local c1 = CFrame.new(j[5].Position * scale) * j[5].Rotation
		local p0, p1 = parts[j[2]], parts[j[3]]
		p1.CFrame = p0.CFrame * c0 * c1:Inverse()
		local m = Instance.new("Motor6D")
		m.Name = j[1]
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = c0
		m.C1 = c1
		m.Parent = p0
	end
	for side = -1, 1, 2 do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.22, 0.22, 0.22) * scale
		eye.Material = Enum.Material.Neon
		eye.Color = ZOMBIE.Eyes
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.Massless = true
		eye.CFrame = head.CFrame * CFrame.new(side * 0.24 * scale, 0.12 * scale, -0.55 * scale)
		eye.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = eye
		weld.Parent = eye
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function template(scale)
	local t = templates[scale]
	if not t then
		t = buildRig(scale)
		templates[scale] = t
	end
	return t
end

local function pick(list)
	return list[math.random(#list)]
end

-- Flat on the floor on its arms. Clients draw the same pose (EndlessFx); setting it here too moves
-- the server's parts, so a crawler's torso and head are hit where they are seen, not standing up.
-- (Motor6D.Transform does not replicate; each side sets its own.)
local CRAWL = CFrame.new(0, 0, -1.9) * CFrame.Angles(math.rad(78), 0, 0)
local function crawlPose(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local joint = root and root:FindFirstChild("RootJoint")
	if joint then
		joint.Transform = CRAWL
	end
end

local function dress(model, kind)
	local skin = if kind == "Brute" then Color3.fromRGB(86, 96, 78) else pick(ZOMBIE.Skin)
	local shirt, pants = pick(ZOMBIE.Shirt), pick(ZOMBIE.Pants)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name == "Torso" then
				p.Color = shirt
				p.Material = Enum.Material.Fabric
			elseif p.Name == "Left Leg" or p.Name == "Right Leg" then
				p.Color = pants
				p.Material = Enum.Material.Fabric
			elseif p.Name == "Eye" then
				p.Color = if kind == "Runner" or kind == "Brute" then ZOMBIE.RunnerEyes else ZOMBIE.Eyes
			elseif p.Name ~= "HumanoidRootPart" then
				p.Color = skin
			end
		end
	end
end

-- Helpers ---------------------------------------------------------------------------------------

local function isAlive(z)
	return z.Model.Parent ~= nil and z.Humanoid.Health > 0 and alive[z.Model] == z
end

local function hold(z, time)
	local t = 0
	while t < time do
		t += task.wait(math.min(NAV.Tick, time - t + 0.01))
		if not isAlive(z) then
			return false
		end
	end
	return true
end

-- Humanoid:MoveTo gives up after 8 s, and the very same point again doesn't restart it.
local function walkTo(z, pos)
	local h = z.Humanoid
	if (h.WalkToPoint - pos).Magnitude < 0.05 then
		pos += Vector3.new(0.1, 0, 0)
	end
	h:MoveTo(pos)
end

local function stand(z)
	z.Humanoid:MoveTo(z.Root.Position)
end

local function face(z, pos)
	local to = Util.Flat(pos - z.Root.Position)
	if to.Magnitude > 0.1 and not z.Root.Anchored then
		z.Root.CFrame = CFrame.lookAt(z.Root.Position, z.Root.Position + to)
	end
end

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude

local function sees(z, target: BasePart)
	local ignore = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local fx = workspace:FindFirstChild("Fx")
	if fx then
		table.insert(ignore, fx)
	end
	sightParams.FilterDescendantsInstances = ignore
	local from = z.Root.Position + Vector3.new(0, 1.2 * z.Scale, 0)
	return workspace:Raycast(from, target.Position - from, sightParams) == nil
end

-- The nearest standing player.
local function nearest(from: Vector3)
	local best, bestRoot, bestD = nil, nil, math.huge
	for _, p in Survivors.StandingPlayers() do
		local _, _, root = Survivors.Parts(p)
		if root then
			local d = (root.Position - from).Magnitude
			if d < bestD then
				best, bestRoot, bestD = p, root, d
			end
		end
	end
	return best, bestRoot, bestD
end

local function rootHeight(z)
	return 3 * z.Scale
end

-- Anchored carry along a curve (rising, climbing walls and sills). Returns false if it died.
local function carry(z, to: Vector3, time: number, over: Vector3?)
	local root = z.Root
	local from = root.Position
	local control = if over then over * 2 - (from + to) / 2 else (from + to) / 2
	local facing = Util.Flat(to - from)
	local rot = if facing.Magnitude > 0.1 then CFrame.lookAt(Vector3.zero, facing.Unit) else root.CFrame.Rotation
	root.Anchored = true
	local t = 0
	while t < 1 do
		t = math.min(t + RunService.Heartbeat:Wait() / time, 1)
		if not isAlive(z) then
			return false
		end
		local a = from:Lerp(control, t)
		local b = control:Lerp(to, t)
		root.CFrame = CFrame.new(a:Lerp(b, t)) * rot
	end
	return true
end

local function release(z)
	z.Root.Anchored = false
	pcall(z.Root.SetNetworkOwner, z.Root, nil)
end

-- The swipe.
local function swing(z, player)
	local _, _, target = Survivors.Parts(player)
	if not target then
		return
	end
	if not z.Root.Anchored then
		stand(z)
		face(z, target.Position)
	end
	z.Model:SetAttribute("SwingAt", workspace:GetServerTimeNow())
	if not hold(z, ATTACK.Windup) then
		return
	end
	Sfx.Play(SOUNDS .. "/Swing", { Position = z.Root.Position })
	if not hold(z, ATTACK.Swing) then
		return
	end
	z.ReadyAt = os.clock() + ATTACK.Cooldown
	local to = target.Position - z.Root.Position
	local flat = Util.Flat(to)
	local look = Util.Flat(z.Root.CFrame.LookVector)
	local inArc = flat.Magnitude < 0.5 or look.Magnitude < 0.1 or look.Unit:Dot(flat.Unit) >= math.cos(math.rad(ATTACK.Arc / 2))
	local reach = ATTACK.Reach * z.Scale + (if z.Window then 2 else 0)
	if to.Magnitude <= reach and inArc and target.Parent then
		Survivors.Damage(player, z.Damage)
	end
end

local function ready(z)
	return os.clock() >= (z.ReadyAt or 0)
end

-- Phases ----------------------------------------------------------------------------------------

-- Up out of the yard (from depth studs down) or a floor hatch. A hatch is a hole in a 1-stud floor
-- with a room under it, so it starts only waist-deep: the legs must not hang out of the ceiling below.
local function rise(z, at: Vector3, depth: number)
	local h = rootHeight(z)
	z.Root.CFrame = CFrame.new(at + Vector3.new(0, h - depth * z.Scale, 0)) * z.Root.CFrame.Rotation
	z.Root.Anchored = true
	Sfx.Play(SOUNDS .. "/Idle", { Position = at })
	local ok = carry(z, at + Vector3.new(0, h, 0), ZOMBIE.Emerge)
	if ok then
		release(z)
	end
	return ok
end

-- A standing player holding this window from inside, close enough to swipe.
local function defender(window)
	for _, p in Survivors.StandingPlayers() do
		local _, _, root = Survivors.Parts(p)
		if root and (root.Position - (window.Inside + Vector3.new(0, 3, 0))).Magnitude < 7 then
			return p
		end
	end
	return nil
end

local function approach(z)
	local window = z.Window
	local side = Vector3.new(-window.Normal.Z, 0, window.Normal.X)
	local spot = window.Outside + side * (math.random() * 3 - 1.5) + Vector3.new(0, rootHeight(z), 0)
	local checkPos, checkAt = z.Root.Position, os.clock()
	local started = os.clock()
	while isAlive(z) do
		if Util.Flat(spot - z.Root.Position).Magnitude < 1.8 then
			return true
		end
		walkTo(z, spot)
		if Util.Flat(z.Root.Position - checkPos).Magnitude > NAV.StuckDistance then
			checkPos, checkAt = z.Root.Position, os.clock()
		elseif os.clock() - checkAt > NAV.StuckTime * 3 then
			-- Something in the way outside: step to the window regardless.
			z.Root.CFrame = CFrame.new(spot) * z.Root.CFrame.Rotation
			checkPos, checkAt = z.Root.Position, os.clock()
		end
		if os.clock() - started > NAV.LostTime then
			return false
		end
		task.wait(NAV.Tick)
	end
	return false
end

local function breach(z)
	local window = z.Window
	local inward = -window.Normal
	if window.Perch then
		-- Up the wall to hang outside an upper window.
		local height = window.Perch.Y - z.Root.Position.Y
		if not carry(z, window.Perch, 0.5 + ZOMBIE.Window.ClimbPerStud * math.abs(height)) then
			return false
		end
		z.Root.CFrame = CFrame.lookAt(window.Perch, window.Perch + inward)
	else
		stand(z)
	end
	while isAlive(z) do
		local broken = Windows.Broken(window)
		if broken and os.clock() >= (window.ClimbFreeAt or 0) then
			return true
		end
		if not z.Root.Anchored then
			z.Root.CFrame = CFrame.lookAt(z.Root.Position, z.Root.Position + inward)
		end
		local player = defender(window)
		if player and ready(z) then
			swing(z, player)
		elseif not broken then
			z.Model:SetAttribute("SwingAt", workspace:GetServerTimeNow())
			if not hold(z, 0.35) then
				return false
			end
			Windows.Rip(window, z.Root.Position)
			local delay = ZOMBIE.Window.BreakDelay
			if not hold(z, delay.Min + math.random() * (delay.Max - delay.Min)) then
				return false
			end
		elseif not hold(z, 0.3) then
			return false
		end
	end
	return false
end

local function climbIn(z)
	local window = z.Window
	local h = rootHeight(z)
	local time = ZOMBIE.Window.ClimbTime
	window.ClimbFreeAt = os.clock() + time + 0.25
	local over = Vector3.new(window.Center.X, window.SillTop + h * 0.6, window.Center.Z)
	if not carry(z, window.Inside + Vector3.new(0, h, 0), time, over) then
		return false
	end
	release(z)
	window.Load = math.max(0, window.Load - 1)
	z.Window = nil
	return true
end

local function hunt(z)
	local scale = z.Scale
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.5 * scale,
		AgentHeight = 5 * scale,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})
	local waypoints, index, pathAt, pathGoal = nil, 0, 0, nil
	local checkPos, checkAt = z.Root.Position, os.clock()
	local lastProgress = os.clock()
	local aggro = false
	while isAlive(z) do
		local root = z.Root
		local player, target, dist = nearest(root.Position)
		local moving = false
		if target then
			if not aggro then
				aggro = true
				Sfx.Play(SOUNDS .. "/Aggro", { Position = root.Position })
			end
			local dy = math.abs(target.Position.Y - root.Position.Y)
			local range = ATTACK.Range * scale
			local inSight = dist <= NAV.DirectRange and dy < 5 and sees(z, target)
			if dist <= range and inSight then
				if ready(z) then
					swing(z, player)
				else
					stand(z)
				end
				lastProgress = os.clock()
			else
				local goal = target.Position
				if not inSight then
					-- A new path at most every Repath seconds (a failed one too, or a stuck zombie
					-- would ask for one every tick).
					if os.clock() - pathAt > NAV.Repath and (not waypoints or (target.Position - pathGoal).Magnitude > 4) then
						pathAt, pathGoal = os.clock(), target.Position
						local ok = pcall(path.ComputeAsync, path, root.Position, target.Position)
						if ok and path.Status == Enum.PathStatus.Success then
							waypoints, index = path:GetWaypoints(), 2
						else
							waypoints = nil
						end
					end
					if waypoints then
						while waypoints[index + 1] and Util.Flat(waypoints[index].Position - root.Position).Magnitude < 2.5 do
							index += 1
						end
						if waypoints[index] then
							goal = waypoints[index].Position
						end
					end
				else
					waypoints = nil
				end
				walkTo(z, goal)
				moving = true
			end
		else
			stand(z)
			lastProgress = os.clock()
		end
		-- Stuck: shuffle aside and repath; no headway at all for LostTime and it's taken away.
		if moving then
			if Util.Flat(root.Position - checkPos).Magnitude > NAV.StuckDistance then
				checkPos, checkAt = root.Position, os.clock()
				lastProgress = os.clock()
			elseif os.clock() - checkAt > NAV.StuckTime then
				local look = Util.Flat(root.CFrame.LookVector)
				local aside = Vector3.new(-look.Z, 0, look.X) * (if math.random() < 0.5 then -1 else 1)
				walkTo(z, root.Position + aside * 3 - look)
				hold(z, 0.5)
				waypoints = nil
				checkPos, checkAt = root.Position, os.clock()
			end
			if os.clock() - lastProgress > NAV.LostTime then
				Horde.Remove(z.Model, true)
				return
			end
		end
		task.wait(NAV.Tick)
	end
end

local function brain(z)
	local entry = z.Entry
	if entry.Window then
		if not rise(z, entry.Window.Spawn, 4.5) then
			return
		end
		if not approach(z) then
			if isAlive(z) then
				Horde.Remove(z.Model, true)
			end
			return
		end
		if not breach(z) or not climbIn(z) then
			return
		end
	elseif not rise(z, entry.Hatch.Position, 2) then
		return
	end
	hunt(z)
end

-- Spawning ---------------------------------------------------------------------------------------

function Horde.Count(): number
	return count
end

-- entry: {Window = window} or {Hatch = hatch}. kind: Walker, Runner, Brute, Crawler.
function Horde.Spawn(entry, kind: string, health: number, speed: number)
	local scale = if kind == "Brute" then BRUTE.Scale else 1
	local model = template(scale):Clone()
	dress(model, kind)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = speed
	model:SetAttribute("Kind", kind)
	local z = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Kind = kind,
		Scale = scale,
		MaxHealth = health,
		Damage = if kind == "Brute" then BRUTE.Damage else ATTACK.Damage,
		Limb = {},
		ArmsLost = 0,
		LegsLost = 0,
		Entry = entry,
		Window = entry.Window,
	}
	if kind == "Crawler" then
		z.LegsLost = 2
		z.Damage *= 0.7
		model:SetAttribute("Crawling", true)
		for _, name in { "Left Leg", "Right Leg" } do
			local leg = model:FindFirstChild(name)
			leg.Transparency = 1
			leg.CanQuery = false
		end
		crawlPose(model)
	end
	if entry.Window then
		entry.Window.Load += 1
	end
	alive[model] = z
	count += 1
	local at = if entry.Window then entry.Window.Spawn else entry.Hatch.Position
	root.CFrame = CFrame.new(at - Vector3.new(0, 6, 0))
	root.Anchored = true -- held until it has risen (brain)
	model.Parent = folder
	humanoid.Died:Once(function()
		if alive[model] == z then
			Horde.Remove(model, false)
		end
	end)
	task.spawn(brain, z)
	return model
end

-- Takes a zombie out of the count. lost: it was stuck, not killed (the round owes one more).
function Horde.Remove(model: Model, lost: boolean)
	local z = alive[model]
	if not z then
		return
	end
	alive[model] = nil
	count -= 1
	if z.Window then
		z.Window.Load = math.max(0, z.Window.Load - 1)
	end
	if lost then
		model:Destroy()
		Horde.Lost:Fire()
	end
end

-- Damage and death -------------------------------------------------------------------------------

local function fxFolder()
	return workspace:FindFirstChild("Fx") or workspace
end

local function tear(z, part, dir)
	if part.Transparency >= 1 then
		return
	end
	local loose = part:Clone()
	loose:ClearAllChildren()
	loose.Anchored = false
	loose.CanCollide = true
	loose.CanQuery = false
	loose.CollisionGroup = "Corpses"
	loose.Parent = fxFolder()
	loose.AssemblyLinearVelocity = (dir or Vector3.zero) * 18 + Vector3.new(0, 10, 0)
	loose.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 16
	Debris:AddItem(loose, 8)
	part.Transparency = 1
	part.CanQuery = false
	Net.Get("Fx"):FireAllClients("Gib", part.Position)
	if LIMBS[part.Name] == "Arm" then
		z.ArmsLost += 1
		z.Damage *= ATTACK.ArmLost
	else
		z.LegsLost += 1
		if z.LegsLost >= 2 and not z.Model:GetAttribute("Crawling") then
			z.Model:SetAttribute("Crawling", true)
			z.Humanoid.WalkSpeed *= ZOMBIE.CrawlSpeed
			z.Damage *= 0.7
			crawlPose(z.Model)
		end
	end
end

local function ragdoll(model, push)
	for _, m in model:GetDescendants() do
		if m:IsA("Motor6D") then
			local a0 = Instance.new("Attachment")
			a0.CFrame = m.C0
			a0.Parent = m.Part0
			local a1 = Instance.new("Attachment")
			a1.CFrame = m.C1
			a1.Parent = m.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 70
			socket.Parent = m.Part0
			m:Destroy()
		end
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Corpses"
			p.CanCollide = p.Name ~= "HumanoidRootPart" and p.Name ~= "Eye" and p.Transparency < 1
			p.CanQuery = false
			p.Anchored = false
		end
	end
	local root = model.PrimaryPart
	if root then
		pcall(root.SetNetworkOwner, root, nil)
		root.AssemblyLinearVelocity = push * 14 + Vector3.new(0, 6, 0)
	end
end

local function die(z, killer, info)
	local model = z.Model
	Horde.Remove(model, false)
	model:SetAttribute("Dead", true)
	info.Kind = z.Kind
	info.Position = z.Root.Position
	Sfx.Play(SOUNDS .. "/Death", { Position = z.Root.Position })
	ragdoll(model, info.Direction or Vector3.zero)
	Horde.Killed:Fire(model, killer, info)
	task.delay(ZOMBIE.CorpseTime, function()
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				TweenService:Create(p, TweenInfo.new(1), { Transparency = 1 }):Play()
			end
		end
		task.wait(1.1)
		model:Destroy()
	end)
end

-- Hurts a zombie. opts: {Head, Melee, Direction}. Returns killed, damage dealt.
function Horde.Damage(model: Model, amount: number, part: BasePart?, killer: Player?, opts)
	local z = alive[model]
	if not z or z.Humanoid.Health <= 0 then
		return false, 0
	end
	opts = opts or {}
	if (workspace:GetAttribute("ReaperUntil") or 0) > workspace:GetServerTimeNow() then
		-- REAPER: anything dies in one hit, a brute takes four times the damage.
		amount = if z.Kind == "Brute" then amount * 4 else z.Humanoid.Health
	end
	local dealt = math.min(amount, z.Humanoid.Health)
	z.Humanoid.Health -= dealt
	local at = if part then part.Position else z.Root.Position
	-- Less on faces (owner rule): a headshot sprays half as much.
	Net.Get("Fx"):FireAllClients("Blood", at, opts.Direction or Vector3.zero, if opts.Head then 0.5 else 1)
	if part and LIMBS[part.Name] and z.Humanoid.Health > 0 then
		z.Limb[part.Name] = (z.Limb[part.Name] or 0) + amount
		local share = if LIMBS[part.Name] == "Arm" then ZOMBIE.ArmShare else ZOMBIE.LegShare
		if z.Limb[part.Name] >= share * z.MaxHealth then
			tear(z, part, opts.Direction)
		end
	end
	if z.Humanoid.Health <= 0 then
		die(z, killer, { Head = opts.Head == true, Melee = opts.Melee == true, Direction = opts.Direction })
		return true, dealt
	end
	if math.random() < 0.3 then
		Sfx.Play(SOUNDS .. "/Hurt", { Position = z.Root.Position, Volume = 0.8 })
	end
	return false, dealt
end

-- PURGE: every zombie standing dies (no points each, Call of Duty's nuke).
function Horde.KillAll()
	for model, z in alive do
		if z.Humanoid.Health > 0 then
			z.Humanoid.Health = 0
			die(z, nil, { Purge = true })
		end
	end
end

-- Run over: every zombie and corpse goes.
function Horde.Clear()
	for model in alive do
		model:Destroy()
	end
	table.clear(alive)
	count = 0
	folder:ClearAllChildren()
end

-- Zombies that fell out of the world go back in the queue.
local function sweep()
	while true do
		task.wait(2)
		for model, z in alive do
			if z.Root.Position.Y < -80 then
				Horde.Remove(model, true)
			end
		end
	end
end

function Horde.Start()
	folder = workspace:FindFirstChild("Zombies") or Instance.new("Folder")
	folder.Name = "Zombies"
	folder.Parent = workspace
	template(1)
	template(BRUTE.Scale)
	task.spawn(sweep)
end

return Horde
```

### 14. `ServerStorage.Endless.Doors` (ModuleScript)

Doors and stair gates bought with points; opening one opens its zones.

```lua
-- Doors and stair gates you buy (Call of Duty Zombies). Every run each price moves by up to
-- Config.Doors.Jitter from the layout's, in Step steps, so prices are learnt again each run. Hold
-- the prompt and pay: a door swings away from you, a gate sinks into the floor, and the zones on
-- both sides are open (their windows and hatches start sending zombies, see Director).
-- Opened fires (door, player).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Endless.Config)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)

local DOORS = Config.Doors

local Doors = {}
Doors.Opened = Util.Signal()

local house

local function jitter(cost: number): number
	if cost <= 0 then
		return 0
	end
	local steps = math.floor(DOORS.Jitter / DOORS.Step)
	return math.max(DOORS.Step, cost + math.random(-steps, steps) * DOORS.Step)
end

local function partsOf(door)
	local list = {}
	for _, p in door.Leaf:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(list, p)
		end
	end
	return list
end

-- The leaf swings 100 degrees on its hinge, away from `from`.
local function swing(door, from: Vector3?)
	local parts = partsOf(door)
	local start = {}
	for _, p in parts do
		start[p] = p.CFrame
		p.CanCollide = false
	end
	local hinge = CFrame.new(door.Center - door.Along * (door.Width / 2))
	local away = if from and (from - door.Center):Dot(door.Normal) > 0 then -door.Normal else door.Normal
	local function freeEnd(angle)
		return (CFrame.Angles(0, angle, 0) * door.Along) * door.Width
	end
	local angle = math.rad(100)
	if freeEnd(angle):Dot(away) < freeEnd(-angle):Dot(away) then
		angle = -angle
	end
	local t = 0
	while t < 1 do
		t = math.min(1, t + RunService.Heartbeat:Wait() / DOORS.OpenTime)
		local eased = 1 - (1 - t) ^ 3
		local turn = hinge * CFrame.Angles(0, angle * eased, 0) * hinge:Inverse()
		for _, p in parts do
			if p.Parent then
				p.CFrame = turn * start[p]
			end
		end
	end
end

-- A gate drops a little and fades, then is gone (sinking all the way would push the bars through the
-- floor into the room below, and its invisible leaf would go on stopping bullets there).
local function sink(door)
	for _, p in partsOf(door) do
		p.CanCollide = false
		p.CanQuery = false
		TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = p.CFrame - Vector3.new(0, 2.5, 0), Transparency = 1 }):Play()
	end
	task.delay(1, function()
		door.Leaf:Destroy()
	end)
end

function Doors.Open(door, player: Player?)
	if door.Open then
		return
	end
	door.Open = true
	if door.Prompt then
		door.Prompt:Destroy()
		door.Prompt = nil
	end
	for _, zid in door.Zones do
		house.Zones[zid].Open = true
	end
	Sfx.Play("World/DoorCreak", { Position = door.Center })
	if door.Kind == "Gate" then
		sink(door)
	else
		Sfx.Play("World/WoodBreak", { Position = door.Center, Volume = 0.6 })
		local from = player and player.Character and player.Character:GetPivot().Position
		task.spawn(swing, door, from)
	end
	Doors.Opened:Fire(door, player)
end

function Doors.Setup(run, maid)
	house = run.House
	for _, door in house.Doors do
		door.Cost = jitter(door.BaseCost)
		local leaf = door.Leaf.PrimaryPart
		local action = if door.Kind == "Gate" then "Open Gate" else "Open Door"
		local prompt = Util.Prompt(leaf, action .. "  (" .. door.Cost .. ")", "", DOORS.HoldTime, 9)
		prompt:SetAttribute("Price", door.Cost)
		door.Prompt = prompt
		prompt.Triggered:Connect(function(player)
			if door.Open or not Survivors.IsStanding(player) then
				return
			end
			if Economy.Spend(player, door.Cost) then
				Doors.Open(door, player)
			end
		end)
	end
	if RunService:IsStudio() and workspace:GetAttribute("EndlessOpenAll") then
		for _, door in house.Doors do
			Doors.Open(door, nil)
		end
	end
end

return Doors
```

### 15. `ServerStorage.Endless.Randomizer` (ModuleScript)

The weapon randomizer (mystery box): spin, take, the skull that moves it.

```lua
-- The weapon randomizer (Call of Duty Zombies' mystery box; Config.Randomizer). A chest on one of
-- the House's Box spots, drawn every run, a pale beam of light over it. Hold the prompt and pay
-- Cost: the lid opens and guns flick past for RollTime seconds, slowing down, then it settles on
-- one (weighted by Config.Weapons Box, never a gun you already carry) and holds it OfferTime seconds
-- for you to take (prompt attribute For: only you). Take it and it's in your hands; with full hands
-- the gun you hold is swapped out.
-- After MinUses spins at one spot, every spin has MoveChance of turning up the skull instead: your
-- points come back, the chest shakes and rises away, and MoveTime later it stands on another Box
-- spot (HUD line: THE RANDOMIZER HAS MOVED).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Endless.Config)
local GunModel = require(ReplicatedStorage.Endless.GunModel)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)

local BOX = Config.Randomizer

local Randomizer = {}

local GLOW = Color3.fromRGB(150, 210, 255)

local function part(parent, name, cf, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ghost(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- The chest at a spot: body, lid (hinged at the back), inner glow, beam, and a display of every gun
-- it can give (all hidden; show() lets one be seen).
local function buildChest(spot, parent)
	local model = Instance.new("Model")
	model.Name = "Randomizer"
	local base = spot.CFrame * CFrame.new(0, 0, -1.6)
	local body = part(model, "Body", base * CFrame.new(0, 1.2, 0), Vector3.new(5.4, 2.4, 2.8), Color3.fromRGB(70, 46, 30), Enum.Material.Wood)
	for _, x in { -2.5, 2.5 } do
		ghost(part(model, "Band", base * CFrame.new(x, 1.2, 0), Vector3.new(0.25, 2.5, 2.9), Color3.fromRGB(150, 120, 60), Enum.Material.Metal))
	end
	local glow = ghost(part(model, "Glow", base * CFrame.new(0, 2.3, 0), Vector3.new(4.8, 0.2, 2.2), GLOW, Enum.Material.Neon))
	local hingeCf = base * CFrame.new(0, 2.4, 1.4)
	local lid = part(model, "Lid", hingeCf * CFrame.new(0, 0.2, -1.4), Vector3.new(5.4, 0.4, 2.8), Color3.fromRGB(80, 54, 34), Enum.Material.Wood)
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Brightness = 1.2
	light.Range = 16
	light.Parent = glow
	-- The beam: a column of light up from the chest.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.2, 0)
	a0.Parent = glow
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 9, 0)
	a1.Parent = glow
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 2.6
	beam.Width1 = 0.6
	beam.Color = ColorSequence.new(GLOW)
	beam.Transparency = NumberSequence.new(0.35, 1)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = glow

	local prompt = Util.Prompt(body, "Spin  (" .. BOX.Cost .. ")", "Weapon Randomizer", BOX.HoldTime, 8)
	prompt:SetAttribute("Price", BOX.Cost)

	-- Where a gun floats while it rolls and waits.
	local showAt = base * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, math.rad(90), 0)
	local displays = {}
	for id, w in Config.Weapons do
		if (w.Box or 0) > 0 then
			local m = GunModel.Build(id, { Anchored = true, CFrame = showAt })
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") then
					p:SetAttribute("Shown", p.Transparency)
					p.Transparency = 1
				end
			end
			m.Parent = model
			displays[id] = m
		end
	end
	-- The skull looks out into the room (the guns are shown side on, the skull face on).
	local skullAt = base * CFrame.new(0, 3.2, 0)
	local skull = Instance.new("Model")
	skull.Name = "Skull"
	local bone = Color3.fromRGB(222, 214, 196)
	local cranium = ghost(part(skull, "Cranium", skullAt, Vector3.new(1.3, 1.3, 1.3), bone, Enum.Material.SmoothPlastic, Enum.PartType.Ball))
	ghost(part(skull, "Jaw", skullAt * CFrame.new(0, -0.6, -0.15), Vector3.new(0.9, 0.4, 0.8), bone))
	for _, x in { -0.28, 0.28 } do
		ghost(part(skull, "Socket", skullAt * CFrame.new(x, 0.05, -0.55), Vector3.new(0.38, 0.38, 0.38), Color3.new(), Enum.Material.SmoothPlastic, Enum.PartType.Ball))
	end
	for _, p in skull:GetChildren() do
		p:SetAttribute("Shown", 0)
		p.Transparency = 1
	end
	skull.PrimaryPart = cranium
	skull.Parent = model
	displays.Skull = skull

	local takeAnchor = ghost(part(model, "TakePoint", showAt, Vector3.new(0.4, 0.4, 0.4), GLOW))
	takeAnchor.Transparency = 1
	local take = Util.Prompt(takeAnchor, "Take", "", 0.25, 8)
	take.Enabled = false

	model.Parent = parent
	return {
		Model = model,
		Body = body,
		Lid = lid,
		LidHome = lid.CFrame,
		Hinge = hingeCf,
		Glow = glow,
		Light = light,
		Prompt = prompt,
		Take = take,
		ShowAt = showAt,
		SkullAt = skullAt,
		Displays = displays,
	}
end

local function show(chest, id, at: CFrame?)
	for key, m in chest.Displays do
		local on = key == id
		if at and on then
			m:PivotTo(at)
		end
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = if on then p:GetAttribute("Shown") or 0 else 1
			end
		end
	end
end

-- The lid turns about its hinge (+105 degrees about the hinge's X: the front edge, at -Z from the
-- hinge, swings up and back). Turned step by step so its back edge stays on the hinge.
local function lid(chest, open: boolean)
	local from = chest.LidAngle or 0
	local to = if open then math.rad(105) else 0
	chest.LidAngle = to
	task.spawn(function()
		local t = 0
		while t < 1 and chest.Lid.Parent do
			t = math.min(1, t + RunService.Heartbeat:Wait() / 0.4)
			local eased = 1 - (1 - t) ^ 3
			local angle = from + (to - from) * eased
			chest.Lid.CFrame = chest.Hinge * CFrame.Angles(angle, 0, 0) * chest.Hinge:Inverse() * chest.LidHome
		end
	end)
end

local function roll(player)
	return Util.Weighted(
		(function()
			local weights = {}
			for id, w in Config.Weapons do
				weights[id] = w.Box or 0
			end
			return weights
		end)(),
		function(id)
			return Arsenal.Find(player, id) ~= nil
		end
	)
end

function Randomizer.Setup(run, maid)
	local house = run.House
	local spots = house.Spots.Box
	if #spots == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "RandomizerSpot"
	folder.Parent = house.Model
	maid:Add(folder)

	local current = math.random(#spots)
	local uses = 0
	local busy = false
	local chest

	local function place(index)
		if chest then
			chest.Model:Destroy()
		end
		current = index
		uses = 0
		local my = buildChest(spots[index], folder)
		chest = my
		-- Everything below works on `my`, this chest: when the run ends mid-spin the chest is gone and
		-- the spin stops quietly at its next step.
		local function gone()
			return my.Model.Parent == nil
		end
		my.Prompt.Triggered:Connect(function(player)
			if busy or gone() or not Survivors.IsStanding(player) then
				return
			end
			if not Economy.Spend(player, BOX.Cost) then
				return
			end
			busy = true
			my.Prompt.Enabled = false
			uses += 1
			local result = if uses > BOX.MinUses and math.random() < BOX.MoveChance then "Skull" else roll(player)
			if not result then
				-- They carry every gun there is.
				Economy.Bonus(player, BOX.Cost)
				my.Prompt.Enabled = true
				busy = false
				return
			end
			lid(my, true)
			Sfx.Play("Night/Stinger", { Position = my.Body.Position, Volume = 0.6 })
			my.Light.Brightness = 3
			-- Guns flick past, slowing, rising out of the chest.
			local t, gap = 0, 0.08
			local pool = {}
			for id in my.Displays do
				if id ~= "Skull" then
					table.insert(pool, id)
				end
			end
			while t < BOX.RollTime do
				local rise = math.min(t / BOX.RollTime, 1) * 1.8
				show(my, pool[math.random(#pool)], my.ShowAt * CFrame.new(0, rise, 0))
				task.wait(gap)
				if gone() then
					return
				end
				t += gap
				gap = math.min(0.35, gap * 1.09)
			end
			if result == "Skull" then
				show(my, "Skull", my.SkullAt * CFrame.new(0, 1.8, 0))
				Sfx.Play(Config.Zombie.Sounds .. "/Aggro", { Position = my.Body.Position })
				task.wait(1.6)
				if gone() then
					return
				end
				show(my, nil)
				Economy.Bonus(player, BOX.Cost)
				-- Shake, rise, gone; then it lands somewhere else.
				for _, p in my.Model:GetDescendants() do
					if p:IsA("BasePart") then
						TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = p.CFrame + Vector3.new(0, 10, 0), Transparency = 1 }):Play()
					end
				end
				task.wait(1.7)
				if gone() then
					return
				end
				my.Model:Destroy()
				chest = nil
				task.wait(BOX.MoveTime)
				if not folder.Parent then
					return
				end
				local others = {}
				for i = 1, #spots do
					if i ~= current then
						table.insert(others, i)
					end
				end
				place(if #others > 0 then others[math.random(#others)] else current)
				Net.Get("Hud"):FireAllClients("Notice", "THE RANDOMIZER HAS MOVED")
				busy = false
				return
			end
			-- Offer it to the buyer.
			local at = my.ShowAt * CFrame.new(0, 1.8, 0)
			show(my, result, at)
			my.Take.ActionText = "Take " .. Config.Weapons[result].Name
			my.Take:SetAttribute("For", player.UserId)
			my.Take.Enabled = true
			local taken = false
			local conn = my.Take.Triggered:Connect(function(who)
				if who == player and not taken and Survivors.IsStanding(who) then
					taken = true
					-- Bought the same gun on a wall meanwhile: this one only fills it.
					local have = Arsenal.Find(who, result)
					if have then
						Arsenal.Fill(who, have)
					else
						Arsenal.Give(who, result)
					end
					Sfx.Play("Pickup/Ammo", { Position = my.Body.Position })
				end
			end)
			local waited = 0
			while waited < BOX.OfferTime and not taken and not gone() do
				waited += task.wait(0.1)
				-- The gun sinks back as its time runs out.
				show(my, result, at * CFrame.new(0, -1.6 * waited / BOX.OfferTime, 0))
			end
			conn:Disconnect()
			if gone() then
				return
			end
			my.Take.Enabled = false
			my.Take:SetAttribute("For", nil)
			show(my, nil)
			lid(my, false)
			my.Light.Brightness = 1.2
			task.wait(0.5)
			if gone() then
				return
			end
			my.Prompt.Enabled = true
			busy = false
		end)
	end
	place(current)
	maid:Add(function()
		if chest then
			chest.Model:Destroy()
			chest = nil
		end
	end)
end

return Randomizer
```

### 16. `ServerStorage.Endless.WallBuys` (ModuleScript)

Chalk guns on the walls: buy the gun, or its ammo.

```lua
-- Guns drawn on the walls (Call of Duty Zombies' wall buys). Each Wall spot of the House shows a gun
-- in chalk: the layout's Weapon, or one drawn from Config.WallBuys.Pool each run. Hold the prompt
-- to buy the gun for its Price, or, carrying it already, its ammo for AmmoShare of the price
-- (Config.Arsenal.AscendedAmmo once it has been through the altar). Prompt attributes Weapon,
-- Price and AmmoPrice let each client word the prompt for its own player (EndlessFx).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Weapons = require(ReplicatedStorage.Endless.Weapons)
local GunModel = require(ReplicatedStorage.Endless.GunModel)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)

local WallBuys = {}

function WallBuys.Setup(run, maid)
	local house = run.House
	local folder = Instance.new("Folder")
	folder.Name = "WallBuys"
	folder.Parent = house.Model
	maid:Add(folder)
	local pool = Util.Shuffle(table.clone(Config.WallBuys.Pool))
	local nextFromPool = 0
	for _, spot in house.Spots.Wall do
		local id = spot.Weapon
		if not id or not Config.Weapons[id] then
			nextFromPool = nextFromPool % #pool + 1
			id = pool[nextFromPool]
		end
		local cfg = Config.Weapons[id]
		local price = cfg.Price or 1000
		local ammoPrice = math.floor(price * Config.Arsenal.AmmoShare / 10 + 0.5) * 10
		-- The chalk drawing, flat on the wall, on a dark board.
		local wallCf = spot.CFrame * CFrame.new(0, 5.2, 0)
		local board = Instance.new("Part")
		board.Name = "ChalkBoard"
		board.Anchored = true
		board.CanCollide = false
		board.CanQuery = false
		board.Size = Vector3.new(5.6, 2.6, 0.1)
		board.CFrame = wallCf * CFrame.new(0, 0, -0.06)
		board.Color = Color3.fromRGB(30, 32, 30)
		board.Material = Enum.Material.Slate
		board.Parent = folder
		local drawing = GunModel.Build(id, { Anchored = true, Chalk = true, CFrame = wallCf * CFrame.new(0.8, -0.1, -0.4) * CFrame.Angles(0, math.rad(90), 0) })
		drawing.Parent = folder
		local prompt = Util.Prompt(board, "Buy " .. cfg.Name .. "  (" .. price .. ")", "", Config.WallBuys.HoldTime, 7)
		prompt:SetAttribute("Weapon", id)
		prompt:SetAttribute("Price", price)
		prompt:SetAttribute("AmmoPrice", ammoPrice)
		prompt:SetAttribute("AscendedAmmo", Config.Arsenal.AscendedAmmo)
		prompt.Triggered:Connect(function(player)
			if not Survivors.IsStanding(player) then
				return
			end
			local tool = Arsenal.Find(player, id)
			if tool then
				local stats = Weapons.ForTool(tool, player)
				local full = (tool:GetAttribute("Reserve") or 0) >= stats.Reserve and (tool:GetAttribute("Mag") or 0) >= stats.Mag
				if full then
					return
				end
				local cost = if (tool:GetAttribute("Level") or 0) > 0 then Config.Arsenal.AscendedAmmo else ammoPrice
				if Economy.Spend(player, cost) then
					Arsenal.Fill(player, tool)
					Sfx.Play("Pickup/Ammo", { Position = board.Position })
				end
			elseif Economy.Spend(player, price) then
				Arsenal.Give(player, id)
				Sfx.Play("Pickup/Ammo", { Position = board.Position })
			end
		end)
	end
end

return WallBuys
```

### 17. `ServerStorage.Endless.Perks` (ModuleScript)

The five perk machines and the power switch.

```lua
-- Perk machines and the power switch (Call of Duty Zombies; our tonics, Config.Perks).
-- Every run the perks are dealt out to the House's Perk spots at random and the switch stands on one
-- of its Power spots. Until someone holds the switch, the machines are dark and the house is lit
-- only by dim red lamps; then the lamps come up, the machines light and the altar wakes (workspace
-- attribute Power, Perks.PowerOn signal).
-- Buying a perk sets the player attribute Perk_<Id>; the systems read it (Survivors: Bulwark,
-- Lazarus; Weapons: Quickhand, TwinFang; Arsenal: Packmule). At most Limit at once, all lost when
-- you go down. Lazarus Draught alone is SoloCost and a self-revive, SoloUses times a run (player
-- attribute LazarusBuys).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)

local PERKS = Config.Perks

local Perks = {}
Perks.PowerOn = Util.Signal()

local machines = {} -- list of {Id, Panel, Light, Prompt}
local lamps = {}

function Perks.Has(player: Player, id: string): boolean
	return player:GetAttribute("Perk_" .. id) == true
end

function Perks.Count(player: Player): number
	local n = 0
	for id in PERKS.List do
		if Perks.Has(player, id) then
			n += 1
		end
	end
	return n
end

function Perks.Price(player: Player, id: string): number
	local perk = PERKS.List[id]
	if perk.SoloCost and #Survivors.RunPlayers() <= 1 then
		return perk.SoloCost
	end
	return perk.Cost
end

function Perks.LoseAll(player: Player)
	for id in PERKS.List do
		player:SetAttribute("Perk_" .. id, nil)
	end
	Survivors.RefreshMaxHealth(player)
	Arsenal.Trim(player)
	Arsenal.Refresh(player)
end

-- Run start.
function Perks.Reset(player: Player)
	for id in PERKS.List do
		player:SetAttribute("Perk_" .. id, nil)
	end
	player:SetAttribute("LazarusBuys", nil)
end

local function notice(player, text)
	Net.Get("Hud"):FireClient(player, "Notice", text)
end

local function buy(player, id)
	local perk = PERKS.List[id]
	if not Survivors.IsStanding(player) then
		return
	end
	if workspace:GetAttribute("Power") ~= true then
		notice(player, "THE POWER IS OFF")
		return
	end
	if Perks.Has(player, id) then
		return
	end
	if Perks.Count(player) >= PERKS.Limit then
		notice(player, "YOU CAN'T HOLD ANOTHER PERK")
		return
	end
	local solo = #Survivors.RunPlayers() <= 1
	if id == "Lazarus" and solo and (player:GetAttribute("LazarusBuys") or 0) >= perk.SoloUses then
		notice(player, "THE MACHINE IS EMPTY")
		return
	end
	if not Economy.Spend(player, Perks.Price(player, id)) then
		return
	end
	if id == "Lazarus" and solo then
		player:SetAttribute("LazarusBuys", (player:GetAttribute("LazarusBuys") or 0) + 1)
	end
	player:SetAttribute("Perk_" .. id, true)
	if id == "Bulwark" then
		Survivors.RefreshMaxHealth(player)
	end
	Sfx.Play("Pickup/Bandage", { Parent = player.Character and player.Character:FindFirstChild("HumanoidRootPart") })
	notice(player, string.upper(perk.Name) .. "  \u{00B7}  " .. perk.Text)
end

local function buildMachine(spot, id, parent)
	local perk = PERKS.List[id]
	local model = Instance.new("Model")
	model.Name = "Perk_" .. id
	local base = spot.CFrame * CFrame.new(0, 0, -1.7)
	local function part(name, cf, size, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local dark = perk.Color:Lerp(Color3.new(0, 0, 0), 0.55)
	local body = part("Body", base * CFrame.new(0, 3.6, 0), Vector3.new(3.8, 7.2, 3), dark, Enum.Material.Metal)
	local panel = part("Panel", base * CFrame.new(0, 4.4, -1.52), Vector3.new(3, 3.2, 0.1), perk.Color:Lerp(Color3.new(), 0.7), Enum.Material.Neon)
	panel.CanCollide = false
	local sign = part("Sign", base * CFrame.new(0, 6.7, -1.52), Vector3.new(3.4, 0.6, 0.12), perk.Color:Lerp(Color3.new(), 0.7), Enum.Material.Neon)
	sign.CanCollide = false
	local slot = part("Slot", base * CFrame.new(0, 1.6, -1.52), Vector3.new(1.4, 0.9, 0.1), Color3.fromRGB(16, 16, 18))
	slot.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = perk.Color
	light.Brightness = 0
	light.Range = 14
	light.Parent = panel
	local prompt = Util.Prompt(body, "Needs Power", perk.Name, PERKS.HoldTime, 7)
	prompt:SetAttribute("Perk", id)
	prompt:SetAttribute("Price", perk.Cost)
	prompt:SetAttribute("SoloPrice", perk.SoloCost)
	prompt.Triggered:Connect(function(player)
		buy(player, id)
	end)
	model.Parent = parent
	return { Id = id, Panel = panel, Sign = sign, Light = light, Prompt = prompt, Color = perk.Color }
end

local function setLamps(on: boolean)
	local s = if on then Config.House.Lamps.On else Config.House.Lamps.Off
	for _, lamp in lamps do
		lamp.Light.Color = s.Color
		lamp.Light.Brightness = s.Brightness
		lamp.Light.Range = s.Range
		lamp.Part.Color = s.Color
	end
end

function Perks.TurnOnPower()
	if workspace:GetAttribute("Power") then
		return
	end
	workspace:SetAttribute("Power", true)
	setLamps(true)
	for _, m in machines do
		m.Panel.Color = m.Color
		m.Sign.Color = m.Color
		TweenService:Create(m.Light, TweenInfo.new(1.5), { Brightness = 1.3 }):Play()
		m.Prompt.ActionText = "Buy  (" .. PERKS.List[m.Id].Cost .. ")"
	end
	Net.Get("Hud"):FireAllClients("Notice", "THE POWER IS ON")
	Perks.PowerOn:Fire()
end

function Perks.Setup(run, maid)
	local house = run.House
	machines = {}
	lamps = house.Lamps
	workspace:SetAttribute("Power", false)
	setLamps(false)
	local folder = Instance.new("Folder")
	folder.Name = "Perks"
	folder.Parent = house.Model
	maid:Add(folder)
	local spots = Util.Shuffle(table.clone(house.Spots.Perk))
	for i, id in PERKS.Order do
		if spots[i] then
			table.insert(machines, buildMachine(spots[i], id, folder))
		else
			warn("Endless: no Perk spot left for", id)
		end
	end
	-- The switch: a lever box on the wall.
	local powerSpots = house.Spots.Power
	if #powerSpots > 0 then
		local spot = powerSpots[math.random(#powerSpots)]
		local box = Instance.new("Part")
		box.Name = "PowerSwitch"
		box.Anchored = true
		box.Size = Vector3.new(2.4, 3.2, 0.8)
		box.CFrame = spot.CFrame * CFrame.new(0, 5, -0.45)
		box.Color = Color3.fromRGB(70, 74, 64)
		box.Material = Enum.Material.CorrodedMetal
		box.Parent = folder
		local lever = Instance.new("Part")
		lever.Name = "Lever"
		lever.Anchored = true
		lever.CanCollide = false
		lever.Size = Vector3.new(0.3, 1.6, 0.3)
		lever.CFrame = box.CFrame * CFrame.new(0, 0.3, -0.6) * CFrame.Angles(math.rad(-35), 0, 0)
		lever.Color = Color3.fromRGB(160, 40, 30)
		lever.Material = Enum.Material.Metal
		lever.Parent = folder
		local prompt = Util.Prompt(box, "Turn On", "Power", Config.Power.HoldTime, 7)
		prompt.Triggered:Connect(function(player)
			if Survivors.IsStanding(player) then
				prompt:Destroy()
				TweenService:Create(lever, TweenInfo.new(0.3), { CFrame = box.CFrame * CFrame.new(0, -0.3, -0.6) * CFrame.Angles(math.rad(35), 0, 0) }):Play()
				Sfx.Play("World/DoorCreak", { Position = box.Position, Speed = 0.6 })
				Perks.TurnOnPower()
			end
		end)
	end
	if RunService:IsStudio() and workspace:GetAttribute("EndlessPower") then
		Perks.TurnOnPower()
	end
	-- Going down costs every perk (Call of Duty).
	maid:Add(Survivors.Downed:Connect(function(player)
		Perks.LoseAll(player)
	end))
end

return Perks
```

### 18. `ServerStorage.Endless.Choices` (ModuleScript)

Pick-one sigils on the floor (relics and altar boosts).

```lua
-- "Pick one" on the floor: a candle on a glowing ring per option, in the option's colour (the lobby
-- Endless relic sigils). Hold the prompt on one to take it. Relics after a round and the ascension
-- altar's boosts both use it. Everything is world parts and ProximityPrompts; no screen UI.
--   Choices.Offer(spec) -> handle with :Clear()
--     spec.Points   floor positions, one per option
--     spec.Options  list of {Id, Name, Text, Color}
--     spec.For      a Player: only they may take one (the offer closes on their pick); nil: anyone
--     spec.Group, spec.Round  read by clients to darken what you can't take (EndlessFx)
--     spec.Hold     prompt hold time
--     spec.OnPick(player, option) -> true to close the whole offer
--     spec.Expires, spec.OnExpire  seconds until the offer closes by itself, and what happens then
-- Model attributes: Choice (option id), For (UserId or 0), Group, Round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)

local Choices = {}

local function folder()
	local f = workspace:FindFirstChild("Choices")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Choices"
		f.Parent = workspace
	end
	return f
end

local function sigil(at: Vector3, option, spec)
	local model = Instance.new("Model")
	model.Name = option.Id
	model:SetAttribute("Choice", option.Id)
	model:SetAttribute("For", if spec.For then spec.For.UserId else 0)
	model:SetAttribute("Group", spec.Group or "")
	model:SetAttribute("Round", spec.Round or 0)

	local function part(name, shape, size, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.Color = color
		p.Material = material
		p.Parent = model
		return p
	end
	local ring = part("Ring", Enum.PartType.Cylinder, Vector3.new(0.08, 3.6, 3.6), CFrame.new(at + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), option.Color, Enum.Material.Neon)
	ring.Transparency = 0.55
	ring.CanQuery = false
	ring.CastShadow = false
	local candle = part("Candle", Enum.PartType.Cylinder, Vector3.new(1.1, 0.6, 0.6), CFrame.new(at + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(226, 214, 190), Enum.Material.SmoothPlastic)
	local flame = part("Flame", Enum.PartType.Ball, Vector3.new(0.35, 0.35, 0.35), CFrame.new(at + Vector3.new(0, 1.3, 0)), option.Color, Enum.Material.Neon)
	flame.CanQuery = false
	flame.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = option.Color
	light.Range = 9
	light.Brightness = 1.6
	light.Shadows = true
	light.Parent = flame
	local prompt = Util.Prompt(candle, option.Name, option.Text, spec.Hold or 0.6, 8)
	prompt.Name = "TakePrompt"
	model.PrimaryPart = candle
	model.Parent = folder()
	return model, prompt
end

function Choices.Offer(spec)
	local handle = { Models = {}, Closed = false }
	function handle:Clear()
		if self.Closed then
			return
		end
		self.Closed = true
		for _, m in self.Models do
			m:Destroy()
		end
		table.clear(self.Models)
	end
	for i, option in spec.Options do
		local at = spec.Points[i]
		if at then
			local model, prompt = sigil(at, option, spec)
			table.insert(handle.Models, model)
			prompt.Triggered:Connect(function(player)
				if handle.Closed or (spec.For and player ~= spec.For) then
					return
				end
				Sfx.Play("Pickup/Bandage", { Position = at, Speed = 0.75 })
				if spec.OnPick(player, option) then
					handle:Clear()
				end
			end)
		end
	end
	if spec.Expires then
		task.delay(spec.Expires, function()
			if not handle.Closed then
				handle:Clear()
				if spec.OnExpire then
					spec.OnExpire()
				end
			end
		end)
	end
	return handle
end

-- Everything on the floor goes (run over).
function Choices.ClearAll()
	folder():ClearAllChildren()
end

return Choices
```

### 19. `ServerStorage.Endless.Relics` (ModuleScript)

The relic draft after every round and what each relic does.

```lua
-- Relics: Mortuus' upgrade draft after every round (the lobby Endless pool plus four; numbers:
-- Config.Relics). When a round is cleared, Offer relics stand on sigils in the room most of the
-- standing squad is in. Everyone may take one before the next round starts (player attribute
-- RelicRound marks this round's pick; clients darken the sigils for whoever has picked). They
-- stack and last the run, as player attributes the systems read: RelicDamage, RelicHead (Weapons),
-- RelicHealth (Survivors), RelicArmor, RelicRegen, RelicSelfRevives, RelicReserve, RelicReload,
-- RelicSpeed, RelicLeech (EndlessServer heals on kills), RelicPoints (Economy); Relic_<id> counts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Util = require(ServerStorage.Endless.Util)
local Choices = require(ServerStorage.Endless.Choices)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)

local RELICS = Config.Relics

local Relics = {}

local offer = nil

function Relics.Reset(player: Player)
	for _, relic in RELICS.Pool do
		player:SetAttribute("Relic" .. relic.Stat, nil)
	end
	for id in RELICS.Pool do
		player:SetAttribute("Relic_" .. id, nil)
	end
	player:SetAttribute("RelicRound", nil)
end

function Relics.Apply(player: Player, id: string)
	local relic = RELICS.Pool[id]
	if not relic then
		return
	end
	player:SetAttribute("Relic_" .. id, (player:GetAttribute("Relic_" .. id) or 0) + 1)
	local key = "Relic" .. relic.Stat
	local value = (player:GetAttribute(key) or 0) + relic.Add
	if relic.Cap then
		value = math.min(value, relic.Cap)
	end
	player:SetAttribute(key, value)
	if relic.Stat == "Health" then
		Survivors.RefreshMaxHealth(player)
	elseif relic.Stat == "Speed" then
		local _, humanoid = Survivors.Parts(player)
		if humanoid and Survivors.IsStanding(player) then
			humanoid.WalkSpeed = Survivors.WalkSpeed(player)
		end
	elseif relic.Stat == "Reserve" then
		-- The bigger pouch comes filled.
		for _, tool in Arsenal.Tools(player) do
			Arsenal.Fill(player, tool)
		end
	end
end

function Relics.Clear()
	if offer then
		offer:Clear()
		offer = nil
	end
end

-- Up to n floor points in the room most standing players are in, near the middle of them.
local function spots(house, n)
	local rooms, best, bestCount = {}, nil, 0
	local sum, count = Vector3.zero, 0
	for _, p in Survivors.StandingPlayers() do
		local _, _, root = Survivors.Parts(p)
		local room = root and house:RoomAt(root.Position)
		if room then
			rooms[room] = (rooms[room] or 0) + 1
			if rooms[room] > bestCount then
				best, bestCount = room, rooms[room]
			end
			sum += root.Position
			count += 1
		end
	end
	best = best or house.Rooms[house.StartRoom]
	local near = if count > 0 then sum / count else nil
	local points = house:FloorPoints(best, n + 2, near)
	-- A small room (a hall full of doorways) may not have enough: the rest of its zone helps out.
	if #points < n then
		for _, id in house.Zones[best.Zone].Rooms do
			if id ~= best.Id then
				for _, p in house:FloorPoints(house.Rooms[id], n - #points, near) do
					table.insert(points, p)
				end
			end
		end
	end
	-- Not right under someone's feet: skip the nearest if there are spare points.
	while #points > n do
		table.remove(points, 1)
	end
	return points
end

function Relics.Offer(run, round: number)
	Relics.Clear()
	local ids = {}
	for id in RELICS.Pool do
		table.insert(ids, id)
	end
	table.sort(ids)
	Util.Shuffle(ids)
	local options = {}
	for i = 1, math.min(RELICS.Offer, #ids) do
		local relic = RELICS.Pool[ids[i]]
		table.insert(options, { Id = ids[i], Name = relic.Name, Text = relic.Text, Color = relic.Color })
	end
	local points = spots(run.House, #options)
	if #points == 0 then
		return
	end
	offer = Choices.Offer({
		Points = points,
		Options = options,
		Group = "Relic",
		Round = round,
		Hold = RELICS.HoldTime,
		OnPick = function(player, option)
			if not Survivors.IsStanding(player) or player:GetAttribute("RelicRound") == round then
				return false
			end
			player:SetAttribute("RelicRound", round)
			Relics.Apply(player, option.Id)
			Net.Get("Hud"):FireClient(player, "Notice", string.upper(option.Name) .. "  \u{00B7}  " .. option.Text)
			return false
		end,
	})
	Net.Get("Hud"):FireAllClients("Notice", "CHOOSE A RELIC")
end

return Relics
```

### 20. `ServerStorage.Endless.Altar` (ModuleScript)

Gun ascension: pay, the gun is taken, pick one of three boosts, it comes back stronger.

```lua
-- Gun ascension (Mortuus' altar, Call of Duty's Pack-a-Punch; Config.Altar). A stone altar on one
-- of the House's Altar spots, drawn every run, dark until the power is on. Hold the gun you want to
-- ascend and hold the prompt: you pay Cost x Growth ^ (times it has ascended), the altar takes the
-- gun, and three boosts rise round it for you alone (Choices, For = you). Take one (within
-- ChoiceTime, or the first is taken for you) and the gun comes back into the same slot with that
-- boost added (the tool's Boosts), a full load and a brighter tint. One gun on the altar at a time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Endless.Config)
local Weapons = require(ReplicatedStorage.Endless.Weapons)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)
local Choices = require(ServerStorage.Endless.Choices)
local Perks = require(ServerStorage.Endless.Perks)

local ALTAR = Config.Altar

local Altar = {}

local function notice(player, text)
	Net.Get("Hud"):FireClient(player, "Notice", text)
end

function Altar.Setup(run, maid)
	local house = run.House
	local spots = house.Spots.Altar
	if #spots == 0 then
		return
	end
	local spot = spots[math.random(#spots)]
	local model = Instance.new("Model")
	model.Name = "Altar"
	local base = spot.CFrame * CFrame.new(0, 0, -2.2)
	local function part(name, cf, size, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local stone = Color3.fromRGB(92, 90, 88)
	part("Base", base * CFrame.new(0, 0.6, 0), Vector3.new(6, 1.2, 4), stone, Enum.Material.Slate)
	local block = part("Block", base * CFrame.new(0, 2.2, 0), Vector3.new(4.6, 2, 3), stone, Enum.Material.Slate)
	part("Top", base * CFrame.new(0, 3.35, 0), Vector3.new(5.2, 0.3, 3.4), Color3.fromRGB(70, 68, 66), Enum.Material.Slate)
	local rune = part("Rune", base * CFrame.new(0, 2.2, -1.52), Vector3.new(3, 1.2, 0.08), Color3.fromRGB(40, 30, 50), Enum.Material.Neon)
	rune.CanCollide = false
	local circle = part("Circle", base * CFrame.new(0, 0.04, -3.2) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.06, 7, 7), Color3.fromRGB(40, 30, 50), Enum.Material.Neon, Enum.PartType.Cylinder)
	circle.CanCollide = false
	circle.CanQuery = false
	circle.Transparency = 0.6
	for _, x in { -2.2, 2.2 } do
		part("Candle", base * CFrame.new(x, 3.9, 0.8), Vector3.new(0.4, 0.9, 0.4), Color3.fromRGB(220, 210, 186))
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(180, 120, 255)
	light.Brightness = 0
	light.Range = 18
	light.Parent = rune
	local prompt = Util.Prompt(block, "Ascend", "Gun Ascension", ALTAR.HoldTime, 8)
	prompt:SetAttribute("Altar", true)
	model.Parent = house.Model
	maid:Add(model)

	local function wake()
		rune.Color = Color3.fromRGB(180, 120, 255)
		circle.Color = Color3.fromRGB(180, 120, 255)
		TweenService:Create(light, TweenInfo.new(1.5), { Brightness = 1.6 }):Play()
	end
	if workspace:GetAttribute("Power") then
		wake()
	end
	maid:Add(Perks.PowerOn:Connect(wake))

	local busy = false
	local offer = nil
	maid:Add(function()
		if offer then
			offer:Clear()
		end
	end)

	prompt.Triggered:Connect(function(player)
		if busy or not Survivors.IsStanding(player) then
			return
		end
		if workspace:GetAttribute("Power") ~= true then
			notice(player, "THE ALTAR NEEDS POWER")
			return
		end
		local tool = Arsenal.Held(player)
		if not tool then
			notice(player, "HOLD THE GUN YOU WANT TO ASCEND")
			return
		end
		local level = tool:GetAttribute("Level") or 0
		if level >= ALTAR.MaxLevel then
			notice(player, "IT CAN'T GROW ANY STRONGER")
			return
		end
		if not Economy.Spend(player, Weapons.AscendCost(level)) then
			return
		end
		busy = true
		local id, boosts, slot = tool:GetAttribute("Weapon"), tool:GetAttribute("Boosts") or "", tool:GetAttribute("Slot")
		tool:Destroy()
		Sfx.Play("Night/Stinger", { Position = block.Position })
		-- Three different boosts, round the front of the altar.
		local ids = {}
		for b in ALTAR.Boosts do
			table.insert(ids, b)
		end
		table.sort(ids)
		Util.Shuffle(ids)
		local options = {}
		for i = 1, 3 do
			local boost = ALTAR.Boosts[ids[i]]
			table.insert(options, { Id = ids[i], Name = boost.Name, Text = boost.Text, Color = boost.Color })
		end
		local front = base * CFrame.new(0, 0, -4.2)
		local points = {
			(front * CFrame.new(-3.2, 0, 0.6)).Position,
			front.Position,
			(front * CFrame.new(3.2, 0, 0.6)).Position,
		}
		local done = false
		local function finish(option)
			if done then
				return
			end
			done = true
			offer = nil
			local newBoosts = if boosts == "" then option.Id else boosts .. "," .. option.Id
			if player.Parent and Survivors.InRun(player) then
				-- Bought the same gun again while this one was on the altar: the ascended one replaces it.
				local dup = Arsenal.Find(player, id)
				if dup then
					slot = dup:GetAttribute("Slot") or slot
					dup:Destroy()
				end
				local given = Arsenal.Give(player, id, newBoosts, slot)
				if given then
					notice(player, string.upper(Config.Weapons[id].Name) .. "  \u{2726}" .. (level + 1) .. "  \u{00B7}  " .. option.Text)
				end
			end
			busy = false
		end
		offer = Choices.Offer({
			Points = points,
			Options = options,
			For = player,
			Group = "Altar",
			Hold = 0.4,
			OnPick = function(_, option)
				finish(option)
				return true
			end,
			Expires = ALTAR.ChoiceTime,
			OnExpire = function()
				finish(options[1])
			end,
		})
		notice(player, "CHOOSE HOW IT GROWS")
	end)
end

return Altar
```

### 21. `ServerStorage.Endless.PowerUps` (ModuleScript)

Drops: Resupply, Reaper, Double Pay, Purge, Hammer and Nails.

```lua
-- Power-ups (Call of Duty Zombies' drops, our names; Config.PowerUps). A kill drops one with Chance,
-- at most PerRound a round, the kinds coming out of a shuffled bag so each turns up once before any
-- repeats. A drop floats where the zombie fell for Life seconds (blinking the last Blink seconds,
-- EndlessFx) and anyone standing who walks within Reach takes it for the whole squad:
--   RESUPPLY      every gun's reserve full
--   REAPER        Duration seconds of one-hit kills (workspace ReaperUntil; Horde.Damage)
--   DOUBLE PAY    Duration seconds of double points (workspace DoublePayUntil; Economy)
--   PURGE         every zombie standing dies, Points each for everyone
--   HAMMER AND NAILS  every board back up, Points each for everyone
-- Drop attributes for clients: Kind, ExpiresAt (server time).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)
local Windows = require(ServerStorage.Endless.Windows)

local POWER = Config.PowerUps

local PowerUps = {}
-- Set by EndlessServer: kills every zombie (Horde.KillAll), kept out of here to avoid a loop.
PowerUps.Purge = nil

local folder
local bag = {}
local dropped = 0
local drops = {} -- [model] = {Kind, At, ExpiresAt}

local function draw()
	if #bag == 0 then
		for kind in POWER.Kinds do
			table.insert(bag, kind)
		end
		table.sort(bag)
		Util.Shuffle(bag)
	end
	return table.remove(bag)
end

local function shape(kind, at: Vector3)
	local info = POWER.Kinds[kind]
	local model = Instance.new("Model")
	model.Name = kind
	local function part(name, size, offset, partShape, color)
		local p = Instance.new("Part")
		p.Name = name
		if partShape then
			p.Shape = partShape
		end
		p.Size = size
		p.CFrame = CFrame.new(at + offset)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Neon
		p.Color = color or info.Color
		p.Parent = model
		return p
	end
	local core
	if kind == "Resupply" then
		core = part("Crate", Vector3.new(1.6, 1.1, 1.1), Vector3.zero)
		part("Lid", Vector3.new(1.7, 0.2, 1.2), Vector3.new(0, 0.6, 0), nil, Color3.fromRGB(120, 100, 40))
	elseif kind == "Reaper" then
		core = part("Skull", Vector3.new(1.4, 1.4, 1.4), Vector3.zero, Enum.PartType.Ball)
		part("Jaw", Vector3.new(0.9, 0.4, 0.8), Vector3.new(0, -0.65, 0))
	elseif kind == "DoublePay" then
		core = part("Coin", Vector3.new(0.25, 1.5, 1.5), Vector3.new(-0.3, 0, 0), Enum.PartType.Cylinder)
		part("Coin2", Vector3.new(0.25, 1.5, 1.5), Vector3.new(0.3, 0, 0), Enum.PartType.Cylinder)
	elseif kind == "Purge" then
		core = part("Bomb", Vector3.new(1.5, 1.5, 1.5), Vector3.zero, Enum.PartType.Ball)
		part("Fuse", Vector3.new(0.2, 0.6, 0.2), Vector3.new(0, 0.95, 0), nil, Color3.fromRGB(255, 240, 200))
	else
		core = part("Head", Vector3.new(1.5, 0.6, 0.6), Vector3.new(0, 0.5, 0))
		part("Handle", Vector3.new(0.3, 1.6, 0.3), Vector3.new(0, -0.4, 0), nil, Color3.fromRGB(120, 86, 50))
	end
	local light = Instance.new("PointLight")
	light.Color = info.Color
	light.Brightness = 2
	light.Range = 12
	light.Parent = core
	model.PrimaryPart = core
	model:SetAttribute("Kind", kind)
	model:SetAttribute("ExpiresAt", workspace:GetServerTimeNow() + POWER.Life)
	model.Parent = folder
	return model
end

local function apply(kind, run)
	local info = POWER.Kinds[kind]
	local now = workspace:GetServerTimeNow()
	if kind == "Resupply" then
		Arsenal.ResupplyAll()
	elseif kind == "Reaper" then
		workspace:SetAttribute("ReaperUntil", now + POWER.Duration)
	elseif kind == "DoublePay" then
		workspace:SetAttribute("DoublePayUntil", now + POWER.Duration)
	elseif kind == "Purge" then
		if PowerUps.Purge then
			PowerUps.Purge()
		end
		for _, p in Survivors.RunPlayers() do
			Economy.Bonus(p, info.Points)
		end
	elseif kind == "Nails" then
		Windows.RepairAll()
		for _, p in Survivors.RunPlayers() do
			Economy.Bonus(p, info.Points)
		end
	end
	Net.Get("Hud"):FireAllClients("PowerUp", kind, info.Name)
end

-- A kill at `at` (the zombie's root): maybe a drop, on the floor under it.
function PowerUps.OnKill(at: Vector3)
	if dropped >= POWER.PerRound or math.random() >= POWER.Chance then
		return
	end
	dropped += 1
	local kind = draw()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local house = workspace:FindFirstChild("House")
	params.FilterDescendantsInstances = if house then { house } else {}
	local hit = workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	local floor = if hit then hit.Position else at - Vector3.new(0, 3, 0)
	local model = shape(kind, floor + Vector3.new(0, 2.2, 0))
	drops[model] = { Kind = kind, At = floor + Vector3.new(0, 2.2, 0) }
end

function PowerUps.NewRound()
	dropped = 0
end

function PowerUps.Setup(run, maid)
	folder = workspace:FindFirstChild("Drops")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Drops"
		folder.Parent = workspace
	end
	folder:ClearAllChildren()
	table.clear(drops)
	table.clear(bag)
	dropped = 0
	workspace:SetAttribute("ReaperUntil", nil)
	workspace:SetAttribute("DoublePayUntil", nil)
	maid:Add(task.spawn(function()
		while true do
			task.wait(0.1)
			local now = workspace:GetServerTimeNow()
			for model, d in drops do
				if not model.Parent or now >= model:GetAttribute("ExpiresAt") then
					drops[model] = nil
					model:Destroy()
				else
					for _, p in Survivors.StandingPlayers() do
						local _, _, root = Survivors.Parts(p)
						if root and (root.Position - d.At).Magnitude <= POWER.Reach + 2 then
							drops[model] = nil
							model:Destroy()
							Sfx.Play("Pickup/Ammo", { Position = d.At })
							apply(d.Kind, run)
							break
						end
					end
				end
			end
		end
	end))
	maid:Add(function()
		folder:ClearAllChildren()
		table.clear(drops)
	end)
end

return PowerUps
```

### 22. `ServerStorage.Endless.Director` (ModuleScript)

The rounds: how many zombies, how tough, how fast, from where; intermissions.

```lua
-- The rounds of a run (Call of Duty Zombies' numbers; Config.Rounds, Config.Specials).
-- Director.Run(run) plays round after round until nobody in the run is standing (Survivors.AnyoneUp)
-- and returns the round reached. A round sends Count(round, players) zombies, SpawnGap(round) apart,
-- at most MaxAlive standing at once, each from an open window or hatch near the squad (PickEntry).
-- When the last one dies the round is over: the dead and anyone who joined come back
-- (run.RespawnDead), three relics stand on the floor (Relics.Offer) and the next round starts
-- Intermission seconds later.
-- Workspace attributes for the HUD: WaveState ("Intermission", "Wave"), Wave, ZombiesLeft,
-- NextWaveAt (server time).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Survivors = require(ServerStorage.Endless.Survivors)
local Horde = require(ServerStorage.Endless.Horde)
local Windows = require(ServerStorage.Endless.Windows)
local Relics = require(ServerStorage.Endless.Relics)
local PowerUps = require(ServerStorage.Endless.PowerUps)

local ROUNDS = Config.Rounds
local SPECIALS = Config.Specials

local Director = {}

-- How many zombies round n sends with this many players (Call of Duty's formula).
function Director.Count(round: number, players: number): number
	local c = ROUNDS.Count
	local mult = math.max(1, round / 5)
	if round >= 10 then
		mult *= round * 0.15
	end
	local extra = if players <= 1 then c.PerPlayer * 0.5 * mult else c.PerPlayer * (players - 1) * mult
	local total = c.Base + math.floor(extra)
	local early = c.Early[round]
	if early then
		total = math.floor(total * early)
	end
	return math.max(1, total)
end

function Director.Health(round: number): number
	local h = ROUNDS.Health
	if round <= h.LinearTo then
		return h.Base + h.PerRound * (round - 1)
	end
	return math.floor((h.Base + h.PerRound * (h.LinearTo - 1)) * h.Late ^ (round - h.LinearTo))
end

function Director.SpawnGap(round: number): number
	return math.max(ROUNDS.GapMin, ROUNDS.SpawnGap * ROUNDS.GapMult ^ (round - 1))
end

function Director.RunnerShare(round: number): number
	local r = ROUNDS.Runners
	if round < r.From then
		return 0
	end
	return math.min(r.Max, r.Step * (round - r.From + 1))
end

function Director.Brutes(round: number): number
	local b = SPECIALS.Brute
	if round < b.From then
		return 0
	end
	return math.min(b.Max, 1 + (round - b.From) // b.Per)
end

local function between(range: NumberRange): number
	return range.Min + math.random() * (range.Max - range.Min)
end

-- An open window or hatch to send the next zombie from: one of the nearest few to a standing player
-- (the fight comes to the squad), the least crowded window first, never a hatch right beside someone.
function Director.PickEntry(house)
	local standing = {}
	for _, p in Survivors.StandingPlayers() do
		local _, _, root = Survivors.Parts(p)
		if root then
			table.insert(standing, root.Position)
		end
	end
	local function nearestPlayer(pos)
		local best = math.huge
		for _, at in standing do
			best = math.min(best, (at - pos).Magnitude)
		end
		return best
	end
	local list = {}
	for _, w in house.Windows do
		if house.Zones[w.Zone].Open and w.Load < 4 then
			table.insert(list, { Entry = { Window = w }, D = nearestPlayer(w.Inside) + w.Load * 12 })
		end
	end
	for _, h in house.Hatches do
		if house.Zones[h.Zone].Open then
			local d = nearestPlayer(h.Position)
			if d > 14 then
				table.insert(list, { Entry = { Hatch = h }, D = d + 20 })
			end
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		return a.D < b.D
	end)
	return list[math.random(math.min(4, #list))].Entry
end

local function setState(run, state)
	run.State = state
	workspace:SetAttribute("WaveState", state)
end

-- Waits up to `time` seconds; false if everyone went down meanwhile.
local function waitUp(time: number): boolean
	local t = 0
	while t < time do
		t += task.wait(0.2)
		if not Survivors.AnyoneUp() then
			return false
		end
	end
	return true
end

function Director.Run(run): number
	local round = 0
	if RunService:IsStudio() and type(workspace:GetAttribute("EndlessStartRound")) == "number" then
		round = math.max(0, workspace:GetAttribute("EndlessStartRound") - 1)
	end
	setState(run, "Intermission")
	workspace:SetAttribute("Wave", round)
	workspace:SetAttribute("ZombiesLeft", 0)
	workspace:SetAttribute("NextWaveAt", workspace:GetServerTimeNow() + Config.Run.FirstDelay)
	if not waitUp(Config.Run.FirstDelay) then
		return round
	end

	while true do
		round += 1
		run.Round = round
		workspace:SetAttribute("Wave", round)
		Relics.Clear()
		Windows.NewRound()
		PowerUps.NewRound()
		setState(run, "Wave")
		Net.Get("Hud"):FireAllClients("Round", round)
		Sfx.Play("Night/Stinger")

		local players = #Survivors.RunPlayers()
		local total = Director.Count(round, players)
		local health = Director.Health(round)
		local gap = Director.SpawnGap(round)
		local runners = Director.RunnerShare(round)
		local queue = total
		-- Brutes come at even points through the round.
		local bruteAt = {}
		local brutes = Director.Brutes(round)
		for i = 1, brutes do
			bruteAt[math.max(1, math.floor(total * (1 - i / (brutes + 1))))] = true
		end
		local lost = Horde.Lost:Connect(function()
			queue += 1
		end)
		local nextSpawn = os.clock() + 1.5
		while queue > 0 or Horde.Count() > 0 do
			if not Survivors.AnyoneUp() then
				lost:Disconnect()
				return round
			end
			if queue > 0 and Horde.Count() < ROUNDS.MaxAlive and os.clock() >= nextSpawn then
				local entry = Director.PickEntry(run.House)
				if entry then
					local kind, hp, speed
					local crawler = SPECIALS.Crawler
					if bruteAt[queue] then
						bruteAt[queue] = nil
						kind, hp, speed = "Brute", health * SPECIALS.Brute.Health, SPECIALS.Brute.Speed
					elseif round >= crawler.From and math.random() < crawler.Share then
						kind, hp, speed = "Crawler", health * crawler.Health, crawler.Speed
					elseif math.random() < runners then
						kind, hp, speed = "Runner", health, between(ROUNDS.RunSpeed)
					else
						kind, hp, speed = "Walker", health, between(ROUNDS.WalkSpeed)
					end
					Horde.Spawn(entry, kind, hp, speed)
					queue -= 1
					nextSpawn = os.clock() + gap * (0.7 + math.random() * 0.6)
				else
					nextSpawn = os.clock() + 1
				end
			end
			workspace:SetAttribute("ZombiesLeft", queue + Horde.Count())
			task.wait(0.1)
		end
		lost:Disconnect()
		workspace:SetAttribute("ZombiesLeft", 0)

		-- The round is over.
		setState(run, "Intermission")
		Net.Get("Hud"):FireAllClients("RoundOver", round)
		Sfx.Play("Common/WaveClear")
		workspace:SetAttribute("NextWaveAt", workspace:GetServerTimeNow() + Config.Run.Intermission)
		if run.RespawnDead then
			run.RespawnDead()
		end
		Relics.Offer(run, round)
		if not waitUp(Config.Run.Intermission) then
			return round
		end
	end
end

return Director
```

### 23. `StarterPlayer.StarterCharacterScripts.Health` (Script)

Empty on purpose: replaces Roblox's default health regen script.

```lua
-- Empty on purpose: a script named Health here replaces Roblox's default one, which would heal
-- characters slowly on its own. Endless heals players itself (ServerStorage.Endless.Survivors).
```

### 24. `StarterPlayer.StarterPlayerScripts.EndlessFx` (LocalScript)

Client: zombie poses, green blood, power-up spin, lamp flicker, prompt wording, spectating.

```lua
-- What each client does to the Endless world for its own player:
--   Zombies: the server's R6 blocks are posed here (no animation assets): arms reaching out, legs
--     walking with their speed, the swipe (model attribute SwingAt), the crawl (Crawling).
--   Blood is green (owner rule): drops on every hit (Fx "Blood"), a burst when a limb tears ("Gib").
--   Power-ups spin, bob and blink out; house lamps flicker until the power is on.
--   Prompts are worded for you: a wall gun you carry offers ammo, a perk shows your price (alone,
--     Lazarus Draught is cheaper), the altar names the gun in your hands and its cost, you never see
--     your own Revive prompt and Lazarus Draught halves the hold on others', sigils you can't take
--     (another player's altar boosts, a relic once you've picked this round's) go dark.
--   Screen: a red flash when hit, grey and red while down. Dead, you watch a standing teammate.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Endless = ReplicatedStorage:WaitForChild("Endless")
local Config = require(Endless:WaitForChild("Config"))
local Weapons = require(Endless:WaitForChild("Weapons"))
local Net = require(Endless:WaitForChild("Net"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local fxFolder = workspace:WaitForChild("Fx")
local ATTACK = Config.Zombie.Attack
local BLOOD = Config.Zombie.Blood

-- Zombies ---------------------------------------------------------------------------------------

local rigs = setmetatable({}, { __mode = "k" }) -- [model] = {joints, last, phase, speed}

local function rigOf(model)
	local r = rigs[model]
	if r then
		return r
	end
	local torso = model:FindFirstChild("Torso")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not torso or not root then
		return nil
	end
	r = {
		RS = torso:FindFirstChild("Right Shoulder"),
		LS = torso:FindFirstChild("Left Shoulder"),
		RH = torso:FindFirstChild("Right Hip"),
		LH = torso:FindFirstChild("Left Hip"),
		Neck = torso:FindFirstChild("Neck"),
		Root = root:FindFirstChild("RootJoint"),
		RootPart = root,
		Last = root.Position,
		Phase = math.random() * 6,
		Speed = 0,
		Offset = math.random() * 10,
	}
	rigs[model] = r
	return r
end

local function set(joint, cf)
	if joint and joint.Parent then
		joint.Transform = cf
	end
end

local function poseZombie(model, dt, now, serverNow)
	local r = rigOf(model)
	if not r then
		return
	end
	local pos = r.RootPart.Position
	local moved = Vector3.new(pos.X - r.Last.X, 0, pos.Z - r.Last.Z).Magnitude
	r.Last = pos
	r.Speed += (moved / math.max(dt, 1e-3) - r.Speed) * math.min(1, dt * 8)
	r.Phase += dt * (1.5 + r.Speed * 0.55)
	local crawling = model:GetAttribute("Crawling") == true
	local runner = model:GetAttribute("Kind") == "Runner"
	local stride = math.clamp(r.Speed / 12, 0, 1)

	-- Arms reach out, and the swipe: up through the windup, down hard on the swing.
	local arm = 1.45 + 0.08 * math.sin(now * 2 + r.Offset)
	local swingAt = model:GetAttribute("SwingAt")
	if swingAt then
		local t = serverNow - swingAt
		if t >= 0 and t < ATTACK.Windup then
			arm = 1.45 + 0.95 * (t / ATTACK.Windup)
		elseif t >= ATTACK.Windup and t < ATTACK.Windup + ATTACK.Swing then
			arm = 2.4 - 1.9 * ((t - ATTACK.Windup) / ATTACK.Swing)
		elseif t >= ATTACK.Windup + ATTACK.Swing and t < ATTACK.Windup + ATTACK.Swing + 0.35 then
			arm = 0.5 + 0.95 * ((t - ATTACK.Windup - ATTACK.Swing) / 0.35)
		end
	end
	if crawling then
		-- Dragging itself on its arms, the body flat to the floor.
		local pull = 0.5 * math.sin(r.Phase * 1.3)
		set(r.RS, CFrame.Angles(0, 0, arm + pull))
		set(r.LS, CFrame.Angles(0, 0, -(arm - pull)))
		set(r.RH, CFrame.Angles(0, 0, -0.2))
		set(r.LH, CFrame.Angles(0, 0, 0.2))
		set(r.Root, CFrame.new(0, 0, -1.9) * CFrame.Angles(math.rad(78), 0, 0))
		set(r.Neck, CFrame.Angles(math.rad(-50), 0, 0.1 * math.sin(now + r.Offset)))
		return
	end
	local swing = 0.7 * stride * math.sin(r.Phase)
	set(r.RS, CFrame.Angles(0, 0, arm + 0.12 * swing))
	set(r.LS, CFrame.Angles(0, 0, -arm + 0.12 * swing))
	set(r.RH, CFrame.Angles(0, 0, -swing))
	set(r.LH, CFrame.Angles(0, 0, -swing))
	set(r.Root, CFrame.Angles(math.rad(if runner then 16 else 7), 0, 0.06 * math.sin(r.Phase * 0.5)))
	set(r.Neck, CFrame.Angles(0.12 * math.sin(now * 0.8 + r.Offset), 0, 0.25 + 0.1 * math.sin(now * 0.5 + r.Offset)))
end

-- Blood (green) ---------------------------------------------------------------------------------

local function drops(at: Vector3, dir: Vector3, n: number, size: number)
	for _ = 1, n do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * size * (0.6 + math.random() * 0.8)
		p.Color = BLOOD:Lerp(Color3.new(0, 0, 0), math.random() * 0.35)
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Position = at
		p.Parent = fxFolder
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 16
		p.AssemblyLinearVelocity = dir * 10 + spread
		Debris:AddItem(p, 0.6)
	end
end

-- Power-ups ----------------------------------------------------------------------------------------

local dropBase = setmetatable({}, { __mode = "k" }) -- [model] = {center, {part = cframe}}

local function animateDrop(model, now, serverNow)
	local d = dropBase[model]
	if not d then
		local parts = {}
		local sum, n = Vector3.zero, 0
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				parts[p] = p.CFrame
				sum += p.Position
				n += 1
			end
		end
		if n == 0 then
			return
		end
		d = { Center = sum / n, Parts = parts }
		dropBase[model] = d
	end
	local turn = CFrame.new(d.Center + Vector3.new(0, 0.35 * math.sin(now * 3), 0)) * CFrame.Angles(0, now * 2, 0) * CFrame.new(-d.Center)
	local left = (model:GetAttribute("ExpiresAt") or math.huge) - serverNow
	local hidden = left < Config.PowerUps.Blink and math.floor(left * 4) % 2 == 0
	for p, base in d.Parts do
		if p.Parent then
			p.CFrame = turn * base
			p.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- Lamps flicker until the power is on ---------------------------------------------------------------

local function flickerLamps(now)
	if workspace:GetAttribute("Power") == true then
		return
	end
	local house = workspace:FindFirstChild("House")
	local lamps = house and house:FindFirstChild("Lamps")
	if not lamps then
		return
	end
	local off = Config.House.Lamps.Off
	for i, lamp in lamps:GetChildren() do
		local light = lamp:FindFirstChildOfClass("PointLight")
		if light then
			local n = math.noise(now * 3, i * 1.7)
			light.Brightness = if n < -0.35 then 0.05 else off.Brightness * (0.75 + n * 0.5)
		end
	end
end

-- Prompts worded for this player -------------------------------------------------------------------

local function myTools()
	local list = {}
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("Weapon") then
					list[t:GetAttribute("Weapon")] = t
				end
			end
		end
	end
	return list
end

local function inRunCount()
	local n = 0
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InRun") then
			n += 1
		end
	end
	return n
end

local function wordPrompt(prompt: ProximityPrompt, owned)
	local weapon = prompt:GetAttribute("Weapon")
	if weapon then
		local tool = owned[weapon]
		local name = Config.Weapons[weapon] and Config.Weapons[weapon].Name or weapon
		if tool then
			local price = if (tool:GetAttribute("Level") or 0) > 0 then prompt:GetAttribute("AscendedAmmo") else prompt:GetAttribute("AmmoPrice")
			prompt.ActionText = "Buy Ammo  (" .. tostring(price) .. ")"
		else
			prompt.ActionText = "Buy " .. name .. "  (" .. tostring(prompt:GetAttribute("Price")) .. ")"
		end
		return
	end
	local perk = prompt:GetAttribute("Perk")
	if perk then
		if player:GetAttribute("Perk_" .. perk) then
			prompt.ActionText = "Owned"
		elseif workspace:GetAttribute("Power") ~= true then
			prompt.ActionText = "Needs Power"
		else
			local price = if prompt:GetAttribute("SoloPrice") and inRunCount() <= 1 then prompt:GetAttribute("SoloPrice") else prompt:GetAttribute("Price")
			prompt.ActionText = "Buy  (" .. tostring(price) .. ")"
		end
		return
	end
	if prompt:GetAttribute("Altar") then
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		if workspace:GetAttribute("Power") ~= true then
			prompt.ActionText = "Needs Power"
		elseif not tool or not tool:GetAttribute("Weapon") then
			prompt.ActionText = "Hold a gun"
		elseif (tool:GetAttribute("Level") or 0) >= Config.Altar.MaxLevel then
			prompt.ActionText = "Can't grow"
		else
			prompt.ActionText = "Ascend " .. tool.Name .. "  (" .. Weapons.AscendCost(tool:GetAttribute("Level") or 0) .. ")"
		end
		return
	end
	if prompt.Name == "RevivePrompt" then
		if prompt:GetAttribute("For") == player.UserId then
			prompt.Enabled = false
		else
			prompt.HoldDuration = Config.Player.Downed.ReviveTime * (if player:GetAttribute("Perk_Lazarus") then Config.Perks.List.Lazarus.Revive else 1)
		end
		return
	end
	local forId = prompt:GetAttribute("For")
	if forId and forId ~= player.UserId and prompt.Enabled then
		prompt.Enabled = false
	end
end

local function shadeChoices()
	local folder = workspace:FindFirstChild("Choices")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		local forId = model:GetAttribute("For") or 0
		local dark = (forId ~= 0 and forId ~= player.UserId)
			or (model:GetAttribute("Group") == "Relic" and player:GetAttribute("RelicRound") == model:GetAttribute("Round"))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if dark then 1 else 0
			elseif d:IsA("PointLight") then
				d.Enabled = not dark
			elseif d:IsA("ProximityPrompt") then
				d.Enabled = not dark
			end
		end
	end
end

-- Every prompt in the house and on the floor sigils, kept as they come (the house is big).
local prompts = {}
local function track(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			prompts[d] = true
		end
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			prompts[d] = true
		end
	end)
end
for _, name in { "House", "Choices" } do
	local root = workspace:FindFirstChild(name)
	if root then
		track(root)
	end
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "House" or child.Name == "Choices" then
		track(child)
	end
end)

local function wordAll()
	local owned = myTools()
	for prompt in prompts do
		if prompt.Parent then
			wordPrompt(prompt, owned)
		else
			prompts[prompt] = nil
		end
	end
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local prompt = root and root:FindFirstChild("RevivePrompt")
		if prompt then
			wordPrompt(prompt, owned)
		end
	end
	shadeChoices()
end

-- Screen ---------------------------------------------------------------------------------------

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "EndlessGrade"
grade.Parent = Lighting
local hurtAt = 0

-- Spectating -----------------------------------------------------------------------------------

local function spectate()
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		if camera.CameraSubject ~= hum then
			camera.CameraSubject = hum
		end
		return
	end
	local state = workspace:GetAttribute("WaveState")
	if state ~= "Wave" and state ~= "Intermission" then
		return
	end
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if p ~= player and h and h.Health > 0 and not c:GetAttribute("Downed") then
			if camera.CameraSubject ~= h then
				camera.CameraSubject = h
			end
			return
		end
	end
end

-- Loop -------------------------------------------------------------------------------------------

local slow = 0
RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local zombies = workspace:FindFirstChild("Zombies")
	if zombies then
		local eye = camera.CFrame.Position
		for _, model in zombies:GetChildren() do
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and not model:GetAttribute("Dead") and (root.Position - eye).Magnitude < 220 then
				poseZombie(model, dt, now, serverNow)
			end
		end
	end
	local dropsFolder = workspace:FindFirstChild("Drops")
	if dropsFolder then
		for _, model in dropsFolder:GetChildren() do
			animateDrop(model, now, serverNow)
		end
	end
	-- Screen grade: a red flash on a hit, grey and red while down.
	local character = player.Character
	local down = character and character:GetAttribute("Downed") == true
	local flash = math.max(0, 1 - (now - hurtAt) / 0.5)
	local tint = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 120, 110), math.max(flash * 0.6, if down then 0.5 else 0))
	grade.TintColor = tint
	grade.Saturation = if down then -0.7 else -0.15 * flash
	slow += dt
	if slow >= 0.25 then
		slow = 0
		flickerLamps(now)
		wordAll()
		spectate()
	end
end)

Net.Get("Fx").OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "Blood" then
		drops(a, if typeof(b) == "Vector3" then b else Vector3.zero, 4 * (c or 1), 0.3)
	elseif kind == "Gib" then
		drops(a, Vector3.zero, 14, 0.45)
	end
end)

Net.Get("Hud").OnClientEvent:Connect(function(cue)
	if cue == "Hurt" then
		hurtAt = os.clock()
	end
end)

-- Zombie models come and go; their pose state goes with them.
workspace:WaitForChild("Zombies").ChildRemoved:Connect(function(model)
	rigs[model] = nil
end)
```

### 25. `StarterPlayer.StarterPlayerScripts.EndlessHud` (LocalScript)

Client: drives the lobby's authored HUD by name (builds no UI).

```lua
-- The Endless HUD. Owner rule: screens are authored PNG art, never built by script. So this script
-- builds nothing: it drives the zombie mode's authored HUD (StarterGui.HUD, copied from the lobby
-- place into this one) by the same names the lobby's MatchHud and GunClient use:
--   HUD.Match.Wave / HUD.Match.Sub   ROUND n; zombies left, or the time to the next round, and any
--                                    DOUBLE PAY / REAPER time left
--   HUD.Points.Value                 points, counting up; red when you can't afford something
--   HUD.Notice                       the one line for big moments (power, relics, power-ups)
--   HUD.Ammo.Mag/Reserve/Gun/MagBar.Fill   the gun in your hands
--   HUD.Crosshair, HUD.Hitmarker     shown when there's a gun / flashed on a hit
--   HUD.GameOver.Title/Waves         the end of a run
-- Elements of the lobby HUD this mode doesn't use (Clock, Hotbar, Scope, AmmoNote) are hidden.
-- Without a HUD in the place it warns once and the game plays on (prompts and the world carry the
-- rest); with no Crosshair the mouse shows Roblox's own locked-cursor cross.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Endless = ReplicatedStorage:WaitForChild("Endless")
local Config = require(Endless:WaitForChild("Config"))
local Weapons = require(Endless:WaitForChild("Weapons"))
local Net = require(Endless:WaitForChild("Net"))
local Sfx = require(Endless:WaitForChild("Sfx"))

local HUD = Config.Hud
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shownPoints = player:GetAttribute("Points") or 0
local brokeUntil = 0
local hitUntil = 0
local hitKill = false
local warned = false

-- StarterGui only reaches PlayerGui once a character loads, so the warning waits a few seconds past it.
local spawnedAt = if player.Character then os.clock() else nil
player.CharacterAdded:Connect(function()
	spawnedAt = spawnedAt or os.clock()
end)

local function hud()
	local gui = playerGui:FindFirstChild("HUD")
	if not gui and not warned and spawnedAt and os.clock() - spawnedAt > 3 then
		warned = true
		warn("Endless: no StarterGui.HUD in this place. Copy the lobby's HUD here to see rounds, points and ammo.")
	end
	return gui
end

local function find(root, ...)
	local node = root
	for _, name in { ... } do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function setText(label, text)
	if label and label:IsA("TextLabel") and label.Text ~= text then
		label.Text = text
	end
end

local function clock(at)
	local t = math.max(0, math.ceil((at or 0) - workspace:GetServerTimeNow()))
	return string.format("%d:%02d", t // 60, t % 60)
end

-- The one line.
local noticeToken = 0
local function notice(text)
	local label = find(hud(), "Notice")
	if not label or not label:IsA("TextLabel") then
		return
	end
	noticeToken += 1
	local token = noticeToken
	label.Text = text
	label.Visible = true
	label.TextTransparency = 0
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0.4
	end
	task.delay(HUD.NoticeTime, function()
		if token == noticeToken then
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end
		end
	end)
end

local function timers()
	local now = workspace:GetServerTimeNow()
	local parts = {}
	local pay = workspace:GetAttribute("DoublePayUntil")
	if pay and pay > now then
		table.insert(parts, "DOUBLE PAY " .. math.ceil(pay - now))
	end
	local reaper = workspace:GetAttribute("ReaperUntil")
	if reaper and reaper > now then
		table.insert(parts, "REAPER " .. math.ceil(reaper - now))
	end
	return table.concat(parts, "  \u{00B7}  ")
end

local function update(dt)
	local gui = hud()
	if not gui then
		return
	end
	for _, name in { "Clock", "Hotbar", "Scope", "AmmoNote" } do
		local e = gui:FindFirstChild(name)
		if e and e:IsA("GuiObject") and e.Visible then
			e.Visible = false
		end
	end
	-- The round.
	local state = workspace:GetAttribute("WaveState") or "Waiting"
	local wave = workspace:GetAttribute("Wave") or 0
	local match = gui:FindFirstChild("Match")
	if match then
		match.Visible = state ~= "GameOver"
		setText(match:FindFirstChild("Wave"), if wave > 0 then "ROUND " .. wave else "GET READY")
		local sub = ""
		if state == "Wave" then
			sub = (workspace:GetAttribute("ZombiesLeft") or 0) .. " LEFT"
		elseif state == "Intermission" then
			sub = (if wave > 0 then "NEXT ROUND " else "FIRST ROUND ") .. clock(workspace:GetAttribute("NextWaveAt"))
		end
		local extra = timers()
		if extra ~= "" then
			sub = if sub ~= "" then sub .. "  \u{00B7}  " .. extra else extra
		end
		setText(match:FindFirstChild("Sub"), sub)
	end
	-- Points, counting up.
	local points = gui:FindFirstChild("Points")
	if points then
		local target = player:GetAttribute("Points") or 0
		if shownPoints < target then
			shownPoints = math.min(target, shownPoints + math.max(1, (target - shownPoints) * dt * 8))
		else
			shownPoints = target
		end
		local value = points:FindFirstChild("Value")
		setText(value, tostring(math.floor(shownPoints + 0.5)))
		if value and value:IsA("TextLabel") then
			value.TextColor3 = if os.clock() < brokeUntil then HUD.Red else HUD.White
		end
	end
	-- The gun in hand.
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local stats = tool and tool:GetAttribute("Weapon") and Weapons.ForTool(tool, player)
	local ammo = gui:FindFirstChild("Ammo")
	if ammo then
		ammo.Visible = stats ~= nil
		if stats then
			local mag = tool:GetAttribute("Mag") or 0
			local reserve = tool:GetAttribute("Reserve") or 0
			local level = tool:GetAttribute("Level") or 0
			local magLabel = ammo:FindFirstChild("Mag")
			setText(magLabel, tostring(mag))
			if magLabel and magLabel:IsA("TextLabel") then
				magLabel.TextColor3 = if mag <= math.ceil(stats.Mag * 0.25) then HUD.Red else HUD.White
				magLabel.TextTransparency = if tool:GetAttribute("Reloading") then 0.5 else 0
			end
			setText(ammo:FindFirstChild("Reserve"), tostring(reserve))
			setText(ammo:FindFirstChild("Gun"), string.upper(stats.Name) .. (if level > 0 then "  \u{2726}" .. level else ""))
			local fill = find(ammo, "MagBar", "Fill")
			if fill and fill:IsA("GuiObject") then
				fill.Size = UDim2.new(math.clamp(mag / stats.Mag, 0, 1), 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
			end
		end
	end
	local crosshair = gui:FindFirstChild("Crosshair")
	if crosshair and crosshair:IsA("GuiObject") then
		crosshair.Visible = stats ~= nil and not (character and character:GetAttribute("Downed"))
	end
	local hitmarker = gui:FindFirstChild("Hitmarker")
	if hitmarker and hitmarker:IsA("GuiObject") then
		hitmarker.Visible = os.clock() < hitUntil
		if hitmarker:IsA("ImageLabel") then
			hitmarker.ImageColor3 = if hitKill then HUD.Red else HUD.White
		end
	end
	local over = gui:FindFirstChild("GameOver")
	if over and over:IsA("GuiObject") then
		over.Visible = state == "GameOver"
	end
end

RunService.RenderStepped:Connect(update)

-- The mouse: the authored crosshair, or Roblox's own cross when the HUD has none.
RunService.Heartbeat:Connect(function()
	local hasCross = find(playerGui, "HUD", "Crosshair") ~= nil
	if hasCross then
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
	elseif UserInputService.MouseIcon ~= "rbxasset://textures/MouseLockedCursor.png" then
		UserInputService.MouseIcon = "rbxasset://textures/MouseLockedCursor.png"
	end
end)

player:GetAttributeChangedSignal("Points"):Connect(function()
	if (player:GetAttribute("Points") or 0) < shownPoints then
		shownPoints = player:GetAttribute("Points") or 0
	end
end)

Net.Get("Hud").OnClientEvent:Connect(function(cue, a, b)
	if cue == "Notice" then
		notice(a)
	elseif cue == "Broke" then
		brokeUntil = os.clock() + 0.6
		Sfx.Play("Common/Empty")
	elseif cue == "Hit" then
		hitUntil = os.clock() + (if b then 0.25 else 0.12)
		hitKill = b == true
		Sfx.Play(if b then "Common/Kill" elseif a then "Common/HitHead" else "Common/Hit", { Volume = 0.7 })
	elseif cue == "Round" then
		notice("ROUND " .. a)
	elseif cue == "RoundOver" then
		Sfx.Play("Common/WaveClear")
	elseif cue == "PowerUp" then
		notice(b)
	elseif cue == "Down" then
		notice(string.upper(a) .. " IS DOWN")
	elseif cue == "GameOver" then
		local over = find(hud(), "GameOver")
		setText(find(over, "Title"), "YOU FELL")
		setText(find(over, "Waves"), if a == 1 then "SURVIVED 1 ROUND" else "SURVIVED " .. a .. " ROUNDS")
		if not over then
			notice("GAME OVER  \u{00B7}  ROUND " .. a)
		end
	end
end)
```

### 26. `StarterPlayer.StarterPlayerScripts.EndlessClient` (LocalScript)

Client: first-person guns, PC/gamepad/touch input, recoil, aim assist on touch and gamepad.

```lua
-- Guns on the client (the server's side is ServerStorage.Endless.Arsenal). First person; you see
-- and hear your own shots at once and the server checks them.
--   PC: left mouse fires, right mouse aims, R reloads, V knifes, 1-3 / Q / wheel change guns.
--   Gamepad: R2 fires, L2 aims, B reloads, R3 knifes, Y changes guns (X is for prompts).
--   Touch: on-screen FIRE, AIM, RELOAD, SWAP and KNIFE buttons (ContextActionService's own buttons).
-- Aim assist only on touch and gamepad, none on PC (owner rule; Config.AimAssist), picked by
-- UserInputService.PreferredInput: a shot leaving close to a zombie bends onto it.
-- Each shot sends Weapon "Fire" with the origin, the pellets' directions and the zombie part each
-- pellet hit here (the server's lag allowance). The magazine count is predicted on the tool (the
-- server's own count replaces it as it arrives).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Endless = ReplicatedStorage:WaitForChild("Endless")
local Config = require(Endless:WaitForChild("Config"))
local Weapons = require(Endless:WaitForChild("Weapons"))
local Net = require(Endless:WaitForChild("Net"))
local Sfx = require(Endless:WaitForChild("Sfx"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local weaponRemote = Net.Get("Weapon")
local fxRemote = Net.Get("Fx")

local ARSENAL = Config.Arsenal

player.CameraMode = Enum.CameraMode.LockFirstPerson
task.spawn(function()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
			break
		end
		task.wait(0.5)
	end
end)

-- Input mode ------------------------------------------------------------------------------------

local function inputMode(): string
	-- A touch screen with no keyboard is touch whatever PreferredInput says (it doesn't always report
	-- Touch: Studio's device emulator, some tablets; the lobby's TouchControls notes the same).
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if ok and preferred then
		if preferred == Enum.PreferredInput.Touch then
			return "Touch"
		elseif preferred == Enum.PreferredInput.KeyboardAndMouse then
			return "KeyboardAndMouse"
		end
		return "Gamepad"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "KeyboardAndMouse"
end

-- State -----------------------------------------------------------------------------------------

local triggerHeld = false
local wantsShot = false -- a click for semi, pump and bolt guns
local aiming = false
local lastShot = 0
local lastMelee = 0
local recoil = 0 -- radians of kick still on the camera

local function character()
	return player.Character
end

local function humanoid()
	local c = character()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function downed()
	local c = character()
	return c ~= nil and c:GetAttribute("Downed") == true
end

local function held(): Tool?
	local c = character()
	local tool = c and c:FindFirstChildOfClass("Tool")
	return if tool and tool:GetAttribute("Weapon") then tool else nil
end

local function tools(): { Tool }
	local list = {}
	local function scan(container)
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("Weapon") then
					table.insert(list, t)
				end
			end
		end
	end
	scan(character())
	scan(player:FindFirstChildOfClass("Backpack"))
	table.sort(list, function(a, b)
		return (a:GetAttribute("Slot") or 0) < (b:GetAttribute("Slot") or 0)
	end)
	return list
end

local function equip(index: number)
	local h = humanoid()
	local list = tools()
	local t = list[index]
	if h and t and not downed() and t.Parent ~= character() then
		aiming = false
		h:EquipTool(t)
	end
end

local function cycle(step: number)
	local list = tools()
	-- Nothing in hand (after a revive, say): the first gun comes out, even if it's the only one.
	local current = table.find(list, held())
	if not current then
		equip(1)
		return
	end
	if #list < 2 then
		return
	end
	equip((current - 1 + step) % #list + 1)
end

-- Effects ---------------------------------------------------------------------------------------

local fxFolder = workspace:WaitForChild("Fx")

local function flash(at: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.6, 0.6, 0.6)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Position = at
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3
	light.Range = 12
	light.Parent = p
	p.Parent = fxFolder
	Debris:AddItem(p, 0.05)
end

local function tracer(from: Vector3, to: Vector3, color: Color3, width: number)
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.35
	p.Size = Vector3.new(width, width, length)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = fxFolder
	Debris:AddItem(p, 0.06)
end

local function muzzleOf(tool: Tool?): Vector3?
	local handle = tool and tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	return if muzzle then muzzle.WorldPosition else nil
end

local TRACER = Color3.fromRGB(255, 220, 150)

local function shotFx(weaponId: string, origin: Vector3, ends: { Vector3 }, from: Vector3?)
	local w = Config.Weapons[weaponId]
	if not w then
		return
	end
	local start = from or origin
	flash(start, Color3.fromRGB(255, 196, 110))
	for _, e in ends do
		tracer(start, e, w.Beam or TRACER, if w.Beam then 0.35 else 0.08)
	end
end

-- Aim assist ------------------------------------------------------------------------------------

local assistParams = RaycastParams.new()
assistParams.FilterType = Enum.RaycastFilterType.Exclude

local function assist(origin: Vector3, dir: Vector3): Vector3
	local a = Config.AimAssist[inputMode()]
	if not a or not a.Enabled then
		return dir
	end
	local zombies = workspace:FindFirstChild("Zombies")
	if not zombies then
		return dir
	end
	assistParams.FilterDescendantsInstances = { character(), fxFolder }
	local best, bestAngle = nil, a.MagnetAngle
	for _, z in zombies:GetChildren() do
		local hum = z:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not z:GetAttribute("Dead") then
			for _, name in { "Head", "Torso" } do
				local part = z:FindFirstChild(name)
				if part and part.Transparency < 1 then
					local to = part.Position - origin
					if to.Magnitude < a.Range then
						local angle = math.deg(math.acos(math.clamp(dir:Dot(to.Unit), -1, 1)))
						if angle < bestAngle then
							local hit = workspace:Raycast(origin, to, assistParams)
							if hit and hit.Instance:IsDescendantOf(z) then
								best, bestAngle = part.Position, angle
							end
						end
					end
				end
			end
		end
	end
	if best then
		return dir:Lerp((best - origin).Unit, a.Strength).Unit
	end
	return dir
end

-- Shooting --------------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function spread(dir: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return dir
	end
	local r = math.rad(degrees) * math.sqrt(math.random())
	local a = math.random() * math.pi * 2
	local frame = CFrame.lookAt(Vector3.zero, dir)
	return (frame * CFrame.Angles(math.sin(a) * r, math.cos(a) * r, 0)).LookVector
end

local function zombiePart(inst: Instance): BasePart?
	local zombies = workspace:FindFirstChild("Zombies")
	if zombies and inst:IsDescendantOf(zombies) and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function reload(tool: Tool?)
	tool = tool or held()
	if not tool or downed() or tool:GetAttribute("Reloading") then
		return
	end
	local stats = Weapons.ForTool(tool, player)
	if not stats or (tool:GetAttribute("Mag") or 0) >= stats.Mag or (tool:GetAttribute("Reserve") or 0) <= 0 then
		return
	end
	weaponRemote:FireServer("Reload", tool)
	Sfx.Play(stats.Sounds .. "/MagOut")
	task.delay(stats.Reload * 0.7, function()
		Sfx.Play(stats.Sounds .. "/MagIn")
	end)
end

local function fire(tool: Tool)
	local stats = Weapons.ForTool(tool, player)
	if not stats or downed() or tool:GetAttribute("Reloading") then
		return
	end
	local now = os.clock()
	if now - lastShot < 60 / stats.Rpm then
		return
	end
	local mag = tool:GetAttribute("Mag") or 0
	if mag <= 0 then
		Sfx.Play("Common/Empty")
		reload(tool)
		return
	end
	lastShot = now
	local origin = camera.CFrame.Position
	local aim = assist(origin, camera.CFrame.LookVector)
	local cone = if aiming then stats.Spread.Aim else stats.Spread.Hip
	rayParams.FilterDescendantsInstances = { character(), fxFolder, workspace:FindFirstChild("Drops") }
	local dirs, claims, ends = {}, {}, {}
	for i = 1, stats.Pellets do
		local dir = spread(aim, cone)
		dirs[i] = dir
		local hit = workspace:Raycast(origin, dir * stats.Range, rayParams)
		claims[i] = hit and zombiePart(hit.Instance) or false
		ends[i] = if hit then hit.Position else origin + dir * stats.Range
	end
	tool:SetAttribute("Mag", mag - 1)
	weaponRemote:FireServer("Fire", tool, origin, dirs, claims)
	shotFx(stats.Id, origin, ends, muzzleOf(tool))
	Sfx.Play(stats.Sounds .. "/Crack")
	Sfx.Play(stats.Sounds .. "/Body", { Volume = 0.8 })
	recoil = math.min(recoil + math.rad(ARSENAL.Recoil.Kick) * (if aiming then 0.5 else 1) * math.clamp(stats.Damage / 80, 0.5, 2.2), math.rad(8))
	if mag - 1 <= 0 then
		task.delay(0.15, reload, tool)
	end
end

local function melee()
	local now = os.clock()
	if downed() or now - lastMelee < ARSENAL.Melee.Cooldown or not character() then
		return
	end
	lastMelee = now
	weaponRemote:FireServer("Melee")
end

-- Input -----------------------------------------------------------------------------------------

local function setTrigger(down: boolean)
	triggerHeld = down
	if down then
		wantsShot = true
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local t, k = input.UserInputType, input.KeyCode
	if t == Enum.UserInputType.MouseButton1 or k == Enum.KeyCode.ButtonR2 then
		setTrigger(true)
	elseif t == Enum.UserInputType.MouseButton2 or k == Enum.KeyCode.ButtonL2 then
		aiming = true
	elseif k == Enum.KeyCode.R or k == Enum.KeyCode.ButtonB then
		reload()
	elseif k == Enum.KeyCode.V or k == Enum.KeyCode.ButtonR3 then
		melee()
	elseif k == Enum.KeyCode.One then
		equip(1)
	elseif k == Enum.KeyCode.Two then
		equip(2)
	elseif k == Enum.KeyCode.Three then
		equip(3)
	elseif k == Enum.KeyCode.Q or k == Enum.KeyCode.ButtonY then
		cycle(1)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local t, k = input.UserInputType, input.KeyCode
	if t == Enum.UserInputType.MouseButton1 or k == Enum.KeyCode.ButtonR2 then
		setTrigger(false)
	elseif t == Enum.UserInputType.MouseButton2 or k == Enum.KeyCode.ButtonL2 then
		aiming = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
		cycle(if input.Position.Z > 0 then -1 else 1)
	end
end)

-- Touch: the engine's own context buttons (no screens built here).
local touchBound = false
local function bindTouch(on: boolean)
	if on == touchBound then
		return
	end
	touchBound = on
	if not on then
		for _, name in { "EndlessFire", "EndlessAim", "EndlessReload", "EndlessSwap", "EndlessKnife" } do
			ContextActionService:UnbindAction(name)
		end
		return
	end
	ContextActionService:BindAction("EndlessFire", function(_, state)
		if state == Enum.UserInputState.Begin then
			setTrigger(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setTrigger(false)
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:BindAction("EndlessAim", function(_, state)
		if state == Enum.UserInputState.Begin then
			aiming = not aiming
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:BindAction("EndlessReload", function(_, state)
		if state == Enum.UserInputState.Begin then
			reload()
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:BindAction("EndlessSwap", function(_, state)
		if state == Enum.UserInputState.Begin then
			cycle(1)
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:BindAction("EndlessKnife", function(_, state)
		if state == Enum.UserInputState.Begin then
			melee()
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:SetTitle("EndlessFire", "FIRE")
	ContextActionService:SetTitle("EndlessAim", "AIM")
	ContextActionService:SetTitle("EndlessReload", "R")
	ContextActionService:SetTitle("EndlessSwap", "SWAP")
	ContextActionService:SetTitle("EndlessKnife", "KNIFE")
	ContextActionService:SetPosition("EndlessFire", UDim2.new(0.05, 0, 0.15, 0))
	ContextActionService:SetPosition("EndlessAim", UDim2.new(-0.35, 0, 0.3, 0))
	ContextActionService:SetPosition("EndlessReload", UDim2.new(0.45, 0, -0.25, 0))
	ContextActionService:SetPosition("EndlessSwap", UDim2.new(0.75, 0, 0.15, 0))
	ContextActionService:SetPosition("EndlessKnife", UDim2.new(-0.35, 0, -0.15, 0))
end

local function refreshMode()
	bindTouch(inputMode() == "Touch")
end
refreshMode()
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refreshMode)
end)
UserInputService.LastInputTypeChanged:Connect(refreshMode)

-- Every frame -----------------------------------------------------------------------------------

local appliedRecoil = 0 -- how much of the kick is already in the camera

RunService:BindToRenderStep("EndlessRecoil", Enum.RenderPriority.Camera.Value + 1, function(dt)
	-- The kick goes on top of the camera and settles back. The camera script builds each frame from
	-- the camera's own look, so only the change since last frame is applied (applying the whole kick
	-- every frame would stack it up; the lobby GunClient does the same).
	recoil = math.max(0, recoil - recoil * math.min(1, ARSENAL.Recoil.Recover * dt) - math.rad(0.5) * dt)
	if recoil ~= appliedRecoil then
		camera.CFrame *= CFrame.Angles(recoil - appliedRecoil, 0, 0)
		appliedRecoil = recoil
	end
	local tool = held()
	local stats = tool and Weapons.ForTool(tool, player)
	local fov = Config.Player.Fov
	if aiming and stats and not downed() then
		fov = stats.AimFov or ARSENAL.AimFov
	end
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, dt * 14)
	-- Reloading: the gun dips (local only).
	if tool then
		local dip = 0
		local ends = tool:GetAttribute("ReloadEnd")
		if tool:GetAttribute("Reloading") and ends and stats then
			local left = ends - workspace:GetServerTimeNow()
			local t = 1 - math.clamp(left / stats.Reload, 0, 1)
			dip = math.sin(t * math.pi)
		end
		local grip = CFrame.Angles(math.rad(35) * dip, 0, 0)
		if tool.Grip ~= grip then
			tool.Grip = grip
		end
	end
	local h = humanoid()
	if h then
		h.CameraOffset = if downed() then Vector3.new(0, -2.2, 0) else Vector3.zero
	end
end)

RunService.Heartbeat:Connect(function()
	local tool = held()
	if not tool then
		wantsShot = false
		return
	end
	local w = Config.Weapons[tool:GetAttribute("Weapon")]
	if not w then
		return
	end
	if w.Fire == "Auto" then
		if triggerHeld then
			fire(tool)
		end
	elseif wantsShot then
		wantsShot = false
		fire(tool)
	end
end)

-- Other players' shots.
fxRemote.OnClientEvent:Connect(function(kind, userId, weaponId, origin, ends)
	if kind ~= "Shot" or userId == player.UserId then
		return
	end
	local shooter = Players:GetPlayerByUserId(userId)
	local tool = shooter and shooter.Character and shooter.Character:FindFirstChildOfClass("Tool")
	shotFx(weaponId, origin, ends, muzzleOf(tool))
	local w = Config.Weapons[weaponId]
	if w then
		Sfx.Play(w.Sounds .. "/Crack", { Position = origin })
	end
end)

player.CharacterAdded:Connect(function()
	aiming, triggerHeld, wantsShot, recoil, appliedRecoil = false, false, false, 0, 0
end)
```

### 27. `ServerScriptService.EndlessServer` (Script)

Boot (lighting, collision groups, remotes) and the run loop; wires the systems together.

```lua
-- The Endless reference: Call of Duty Zombies rounds with Mortuus' roguelike layer, in a huge
-- code-built house (docs/ENDLESS-REFERENCE.md). This script boots the place and runs run after run:
--   1. A run starts once someone is in the server: the house is built fresh (HouseBuilder, a new
--      draw of the box, perks, wall guns, altar, switch and door prices), every system is set up
--      on it, and everyone spawns in the start room with Config.Run.StartPoints and the start gun.
--   2. Director plays rounds until nobody is standing.
--   3. Game over: GameOverTime on the end screen, then everything is taken down and it begins again.
-- It also joins the systems up: a hit from Arsenal goes to Horde.Damage and pays points (Economy),
-- a kill may drop a power-up (PowerUps) and heals Bloodthirst players.
-- Players.CharacterAutoLoads is off: characters only load through Survivors.Spawn.
-- Studio only: workspace attributes EndlessStartRound, EndlessStartPoints, EndlessPower, EndlessGod,
-- EndlessOpenAll (Config.Debug).

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Modules = ServerStorage.Endless
local Util = require(Modules.Util)
local HouseBuilder = require(Modules.HouseBuilder)
local HouseLayout = require(Modules.HouseLayout)
local Economy = require(Modules.Economy)
local Survivors = require(Modules.Survivors)
local Arsenal = require(Modules.Arsenal)
local Windows = require(Modules.Windows)
local Horde = require(Modules.Horde)
local Doors = require(Modules.Doors)
local Randomizer = require(Modules.Randomizer)
local WallBuys = require(Modules.WallBuys)
local Perks = require(Modules.Perks)
local Altar = require(Modules.Altar)
local Choices = require(Modules.Choices)
local Relics = require(Modules.Relics)
local PowerUps = require(Modules.PowerUps)
local Director = require(Modules.Director)

-- Boot -------------------------------------------------------------------------------------------

Players.CharacterAutoLoads = false

for _, group in { "Players", "Zombies", "Corpses", "PlayerBlock" } do
	pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, group)
end
-- Zombies walk through each other (no jams at windows and doors); corpses, torn boards and limbs
-- only rest on the house; window blockers stop players and nothing else.
PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", false)
PhysicsService:CollisionGroupSetCollidable("Corpses", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Corpses", "Zombies", false)
PhysicsService:CollisionGroupSetCollidable("Corpses", "Corpses", false)
PhysicsService:CollisionGroupSetCollidable("PlayerBlock", "Zombies", false)
PhysicsService:CollisionGroupSetCollidable("PlayerBlock", "Corpses", false)
PhysicsService:CollisionGroupSetCollidable("PlayerBlock", "Default", false)

do
	local L = Config.Lighting
	Lighting.ClockTime = L.ClockTime
	Lighting.Brightness = L.Brightness
	Lighting.Ambient = L.Ambient
	Lighting.OutdoorAmbient = L.OutdoorAmbient
	Lighting.GlobalShadows = true
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = L.Atmosphere.Density
	atmosphere.Offset = L.Atmosphere.Offset
	atmosphere.Color = L.Atmosphere.Color
	atmosphere.Decay = L.Atmosphere.Decay
	atmosphere.Glare = L.Atmosphere.Glare
	atmosphere.Haze = L.Atmosphere.Haze
	atmosphere.Parent = Lighting
end

-- A bare place's baseplate and spawn would sit inside the yard.
for _, child in workspace:GetChildren() do
	if child:IsA("SpawnLocation") or (child:IsA("BasePart") and child.Name == "Baseplate") then
		child:Destroy()
	end
end

local fx = Instance.new("Folder")
fx.Name = "Fx"
fx.Parent = workspace

Net.Make()
Survivors.Start()
Arsenal.Start()
Horde.Start()

-- Joining the systems up --------------------------------------------------------------------------

local POINTS = Config.Points
local hud = Net.Get("Hud")

Arsenal.DamageZombie = function(player, zombie, part, amount, head, melee, direction, paysHit)
	local killed, dealt = Horde.Damage(zombie, amount, part, player, { Head = head, Melee = melee, Direction = direction })
	if dealt <= 0 then
		return
	end
	if killed then
		local kind = zombie:GetAttribute("Kind")
		local pay = if kind == "Brute" then Config.Specials.Brute.Points
			elseif melee then POINTS.MeleeKill
			elseif head then POINTS.HeadKill
			else POINTS.Kill
		Economy.Add(player, pay)
		Economy.Count(player, "Kills")
		if head then
			Economy.Count(player, "Headshots")
		end
	elseif paysHit then
		Economy.Add(player, POINTS.Hit)
	end
	hud:FireClient(player, "Hit", head, killed)
end

Horde.Killed:Connect(function(_, killer, info)
	if not info.Purge then
		PowerUps.OnKill(info.Position)
	end
	local leech = killer and killer:GetAttribute("RelicLeech") or 0
	if killer and leech > 0 then
		Survivors.Heal(killer, leech)
	end
end)

PowerUps.Purge = Horde.KillAll

-- Runs -------------------------------------------------------------------------------------------

local current = nil

local function studioNumber(name)
	local v = workspace:GetAttribute(name)
	return if RunService:IsStudio() and type(v) == "number" then v else nil
end

-- A player new to this run: clean slate.
local function enlist(player)
	Economy.Reset(player, studioNumber("EndlessStartPoints") or Config.Run.StartPoints)
	Perks.Reset(player)
	Relics.Reset(player)
end

local function spawnAt(player, at)
	if not Survivors.InRun(player) then
		enlist(player)
	end
	local character = Survivors.Spawn(player, at)
	if character then
		Arsenal.GiveStart(player)
	end
end

-- Everyone not alive in this run (dead, new, or holding a character from before the run) comes in at
-- the start room.
local function respawnDead(run)
	local waiting = {}
	for _, p in Players:GetPlayers() do
		if not Survivors.IsAlive(p) or not Survivors.InRun(p) then
			table.insert(waiting, p)
		end
	end
	local points = run.House:StartPoints(#waiting)
	for i, p in waiting do
		task.spawn(spawnAt, p, points[i])
	end
end

local function startRun()
	local run = { Maid = Util.Maid(), State = "Waiting", Round = 0 }
	workspace:SetAttribute("WaveState", "Waiting")
	workspace:SetAttribute("Wave", 0)
	local house = HouseBuilder.Build(HouseLayout, workspace)
	run.House = house
	run.Maid:Add(house.Model)
	for _, setup in { Windows.Setup, Doors.Setup, Randomizer.Setup, WallBuys.Setup, Perks.Setup, Altar.Setup, PowerUps.Setup } do
		local ok, err = pcall(setup, run, run.Maid)
		if not ok then
			warn("Endless: a system failed to set up:", err)
		end
	end
	for _, p in Players:GetPlayers() do
		Survivors.Reset(p)
	end
	task.wait(Config.Run.SpawnSettle)
	run.RespawnDead = function()
		respawnDead(run)
	end
	respawnDead(run)
	-- Joining between rounds: straight in. During a round: at its end (Director). During the end
	-- screen: with the next run.
	run.Maid:Add(Players.PlayerAdded:Connect(function(player)
		if run.State == "Intermission" or run.State == "Waiting" then
			spawnAt(player, house:StartPoints(1)[1])
		end
	end))
	return run
end

-- Back up after a revive: the gun comes out again (going down put it away).
Survivors.Revived:Connect(function(player)
	local _, humanoid = Survivors.Parts(player)
	local first = Arsenal.Tools(player)[1]
	if humanoid and first and not Arsenal.Held(player) then
		humanoid:EquipTool(first)
	end
end)

local function endRun(run, reached)
	run.State = "GameOver"
	workspace:SetAttribute("WaveState", "GameOver")
	workspace:SetAttribute("BestRound", math.max(workspace:GetAttribute("BestRound") or 0, reached))
	hud:FireAllClients("GameOver", reached)
	-- Hook for the zombie mode's port: save the best round on the profile here (Profile, never from
	-- a Studio test: owner rule, no live DataStore writes from tests).
	task.wait(Config.Run.GameOverTime)
	Relics.Clear()
	Choices.ClearAll()
	Horde.Clear()
	run.Maid:Clean()
	fx:ClearAllChildren()
	workspace:SetAttribute("Power", false)
	workspace:SetAttribute("ReaperUntil", nil)
	workspace:SetAttribute("DoublePayUntil", nil)
	for _, p in Players:GetPlayers() do
		if p.Character then
			p.Character:Destroy()
			p.Character = nil
		end
		for _, t in Arsenal.Tools(p) do
			t:Destroy()
		end
	end
end

while true do
	while #Players:GetPlayers() == 0 do
		task.wait(0.5)
	end
	current = startRun()
	local ok, reached = pcall(Director.Run, current)
	if not ok then
		warn("Endless: the run broke:", reached)
		reached = current.Round
	end
	endRun(current, reached or 0)
	current = nil
end
```
