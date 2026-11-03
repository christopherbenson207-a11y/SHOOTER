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
