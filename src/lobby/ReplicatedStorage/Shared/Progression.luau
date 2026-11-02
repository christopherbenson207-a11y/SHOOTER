-- Shared.Progression (DATA, 2 Nov 2026): account levels and their rewards, classes, weapon levels, the Night Pass and
-- challenges. Plain data and small pure functions: no instances, no yields, the same on the server and on clients.
-- Contract: horror-shooter/menu/CONTRACTS.md section 2 (ids in section 9); numbers from MENU-PLAN 9.4-9.6.
-- Read by ServerStorage.Modules.Progression, Profile and StoreServer, Shared.Catalogue, Shared.Classes and the menu.
--
-- Levels: XP from level L to L+1 is 1000 + 200*(L-1), cap 50 (284,200 XP). Past the cap every StarXp is a star on the
--   insignia and pays StarScrip. Rewards[level] is what a level gives; there is something at every level. Guns, gear,
--   classes and loadout slots are unlocked by level alone; operators and cards go into Owned; Scrip is paid.
--   A new rank insignia every 5 levels (Rank 1 at level 1, Rank 10 at 45); level 50 starts the stars.
-- Classes: one passive (Perks, read through Shared.Classes.Perk) and one field item each. A veteran class unlocks at
--   its level or earlier through its Trial, counted from the profile's Stats. Classes are never sold.
-- Weapon levels: weapon XP per kill (Weapon.Xp); level n to n+1 costs 20 + 10*(n-1), cap 15; camos by weapon level,
--   then mastery (per gun: Bone for 100 headshot kills, Night for 25 elite kills; LastLight once every gun is Gold).
-- Night Pass: TierXp pass XP per tier. Tier 1 is reached at 0 XP: PassTier(xp) = 1 + floor(xp / TierXp), max 30.
--   Reward kinds: Scrip, Card, Camo, Operator (Catalogue items), Boost (Squad Boosts), Token (revive tokens).
-- Challenges: Daily (3 a day from 00:00 UTC: one Mode, one Gear = class or gun, one Team) and Weekly (5 a week from
--   Monday 00:00 UTC), picked by date so every server agrees. Events are counted by Progression.Event (server).

local P = {}

P.LevelCap = 50
P.StarXp = 10000
P.StarScrip = 500
P.RerollScrip = 200 -- one daily challenge may be swapped once a day
P.FirstMatchBonus = 2 -- account XP on the first match of the UTC day (never on pass XP)
P.BoostPassXp = 1.5 -- pass XP while a Squad Boost is active for the match

function P.XpToNext(level)
	return 1000 + 200 * (level - 1)
end

local REACH = { [1] = 0 }
for level = 2, P.LevelCap do
	REACH[level] = REACH[level - 1] + P.XpToNext(level - 1)
end
P.CapXp = REACH[P.LevelCap]

-- Total XP at which a level is reached (level 1 = 0).
function P.XpAt(level)
	return REACH[math.clamp(math.floor(tonumber(level) or 1), 1, P.LevelCap)]
end

-- level, XP into it, XP it needs, stars. At the cap, into and need count toward the next star.
function P.FromXp(total)
	total = math.max(0, math.floor(tonumber(total) or 0))
	if total >= P.CapXp then
		local past = total - P.CapXp
		local stars = past // P.StarXp
		return P.LevelCap, past - stars * P.StarXp, P.StarXp, stars
	end
	local lo, hi = 1, P.LevelCap - 1
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if REACH[mid] <= total then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo, total - REACH[lo], P.XpToNext(lo), 0
end

-- Rank insignia 1..10 (art Rank/<n>); the stars after 50 go on top of rank 10 (art Rank/Star).
function P.Rank(level)
	return math.clamp(1 + math.floor((tonumber(level) or 1) / 5), 1, 10)
end

-- XP awards (Progression.Add(player, reason)). Beacon: the Beacon brought down, to everyone in the match.
P.Xp = {
	Kill = 10,
	Elite = 50,
	Headshot = 5,
	Revive = 50,
	Board = 5,
	Night = 150,
	Wave = 60,
	Contract = 200,
	Objective = 250,
	MissionComplete = 500,
	Escape = 750,
	Finished = 150,
	Beacon = 400,
}

-- The arsenal by slot. GUNS (Shared.GunStats, Shared.LoadoutRules) and MATCH (Shared.Gear) own the real data; this is
-- the fallback the server checks loadouts against while those modules are missing.
P.Guns = { "AK", "Shotgun", "Sniper", "Pistol", "MP5", "M4", "HandCannon", "SR25", "M60" }
P.Gear = { "Frag", "Molotov", "Flare", "Flashbang", "Stim" }
P.Slots = {
	AK = "Primary",
	Shotgun = "Primary",
	Sniper = "Primary",
	MP5 = "Primary",
	M4 = "Primary",
	SR25 = "Primary",
	M60 = "Primary",
	Pistol = "Secondary",
	HandCannon = "Secondary",
	Frag = "Lethal",
	Molotov = "Lethal",
	Flare = "Tactical",
	Flashbang = "Tactical",
	Stim = "Tactical",
}
P.LoadoutSlots = { "Class", "Primary", "Secondary", "Lethal", "Tactical" }
P.Loadouts = 3 -- loadouts in the profile; the third opens at UnlockLevel("Slot3")
P.DefaultLoadout = { Class = "Rifleman", Primary = "AK", Secondary = "Pistol", Lethal = "Frag", Tactical = "Flare" }

-- Level rewards ------------------------------------------------------------------------------------------------
-- Kinds: Gun, Gear, Class, Slot, Operator, Card, Insignia (Id = rank number as text, or "Star"), Scrip (Amount).

local R = {}
local function give(level, kind, id, amount)
	R[level] = R[level] or {}
	table.insert(R[level], { Kind = kind, Id = id, Amount = amount })
end

give(1, "Class", "Rifleman")
give(1, "Gun", "AK")
give(1, "Gun", "Shotgun")
give(1, "Gun", "Pistol")
give(1, "Gear", "Frag")
give(1, "Gear", "Flare")
give(1, "Slot", "Slot1")
give(1, "Slot", "Slot2")
give(1, "Insignia", "1")
give(2, "Gun", "MP5")
give(3, "Class", "Medic")
give(3, "Gear", "Stim")
give(4, "Gun", "M4")
give(5, "Slot", "Slot3")
give(5, "Operator", "Desert")
give(6, "Class", "Engineer")
give(6, "Gun", "HandCannon")
give(7, "Gun", "SR25")
give(8, "Gear", "Molotov")
give(9, "Class", "Scout")
give(10, "Gun", "Sniper")
give(10, "Operator", "Arctic")
give(11, "Gear", "Flashbang")
give(12, "Class", "Hunter")
give(13, "Gun", "M60")
give(15, "Class", "Firefighter")
give(18, "Class", "Marksman")
give(21, "Class", "Demolition")
give(25, "Operator", "SWAT")
give(40, "Operator", "Ghillie")
for level = 5, 45, 5 do
	give(level, "Insignia", tostring(P.Rank(level)))
end
give(50, "Card", "LastLight")
give(50, "Insignia", "Star")
local SCRIP_LEVELS = {
	[14] = 300, [16] = 300, [17] = 350, [19] = 350, [20] = 500, [22] = 400, [23] = 400, [24] = 400,
	[26] = 400, [27] = 450, [28] = 450, [29] = 450, [30] = 500, [31] = 450, [32] = 450, [33] = 450,
	[34] = 450, [35] = 500, [36] = 500, [37] = 500, [38] = 500, [39] = 500, [41] = 500, [42] = 500,
	[43] = 500, [44] = 500, [45] = 500, [46] = 500, [47] = 500, [48] = 500, [49] = 500,
}
for level, amount in SCRIP_LEVELS do
	give(level, "Scrip", nil, amount)
end
P.Rewards = R

local UNLOCK = {}
for level = 1, P.LevelCap do
	local list = R[level]
	assert(list and #list > 0, "Shared.Progression: level " .. level .. " gives nothing")
	for _, r in list do
		if r.Id ~= nil and r.Kind ~= "Scrip" and r.Kind ~= "Insignia" then
			UNLOCK[r.Kind .. "/" .. r.Id] = UNLOCK[r.Kind .. "/" .. r.Id] or level
			UNLOCK[r.Id] = UNLOCK[r.Id] or level
		end
	end
end

-- The level that unlocks a gun, gear item, class, loadout slot ("Slot3"), level operator or card; nil if no level
-- does. Takes a bare id ("MP5") or a kind-prefixed one ("Operator/Desert").
function P.UnlockLevel(id)
	return UNLOCK[id]
end

-- Classes ------------------------------------------------------------------------------------------------------
-- Perks are multipliers (1 = untouched) read through Shared.Classes.Perk(player, key). Readers: Reload (GUNS),
-- ReviveTime (PlayerHealth / PlayerHealthClient), BandageHeal (Bandages), RepairPoints (MatchServer), RepairTime
-- (MATCH), Noise and SeenFill (BeaconServer), Sprint (whoever owns walk speed), EliteDamage (GUNS / MobReactions),
-- SelfReviveTime (PlayerHealth), FallDamage (FallDamage), Recoil (GunClient), EliteStagger (MobReactions),
-- LethalCount and BlastRadius (Kit / GearServer). Field is the Shared.Gear field item key. Art: Class/<Id> is the
-- card render, Emblem/<Id> the emblem (CHROME).

P.DefaultClass = "Rifleman"
P.Classes = {
	Rifleman = {
		Order = 1, Name = "RIFLEMAN", Level = 1, Trial = nil,
		Perks = { Reload = 0.8 },
		Field = "Smoke", Emblem = "Emblem/Rifleman", Art = "Class/Rifleman",
	},
	Medic = {
		Order = 2, Name = "MEDIC", Level = 3, Trial = nil,
		Perks = { ReviveTime = 0.6, BandageHeal = 1.5 },
		Field = "MedPouch", Emblem = "Emblem/Medic", Art = "Class/Medic",
	},
	Engineer = {
		Order = 3, Name = "ENGINEER", Level = 6, Trial = nil,
		Perks = { RepairPoints = 1.5, RepairTime = 0.7 },
		Field = "AmmoCrate", Emblem = "Emblem/Engineer", Art = "Class/Engineer",
	},
	Scout = {
		Order = 4, Name = "SCOUT", Level = 9, Trial = nil,
		Perks = { Noise = 0.7, SeenFill = 0.8, Sprint = 1.08 },
		Field = "ReconFlare", Emblem = "Emblem/Scout", Art = "Class/Scout",
	},
	Hunter = {
		Order = 5, Name = "HUNTER", Level = 12, Trial = { Stat = "Elites", Count = 10 },
		Perks = { EliteDamage = 1.15 },
		Field = "Mark", Emblem = "Emblem/Hunter", Art = "Class/Hunter",
	},
	Firefighter = {
		Order = 6, Name = "FIREFIGHTER", Level = 15, Trial = { Stat = "Escapes", Count = 3 },
		Perks = { SelfReviveTime = 0.6, FallDamage = 0.5 },
		Field = "Extinguisher", Emblem = "Emblem/Firefighter", Art = "Class/Firefighter",
	},
	Marksman = {
		Order = 7, Name = "MARKSMAN", Level = 18, Trial = { Stat = "Headshots", Count = 100 },
		Perks = { Recoil = 0.8, EliteStagger = 2 },
		Field = "Decoy", Emblem = "Emblem/Marksman", Art = "Class/Marksman",
	},
	Demolition = {
		Order = 8, Name = "DEMOLITION", Level = 21, Trial = { Stat = "FragKills", Count = 30 },
		Perks = { LethalCount = 2, BlastRadius = 1.25 },
		Field = "Charge", Emblem = "Emblem/Demolition", Art = "Class/Demolition",
	},
}
P.ClassOrder = {}
for id, c in P.Classes do
	P.ClassOrder[c.Order] = id
end

-- Whether a class can be used: its level reached, its trial done (stats = the profile's Stats), or owned from before
-- the update (owned = the Owned set; "Class/<Id>" or the bare id).
function P.ClassUnlocked(classId, level, stats, owned)
	local c = P.Classes[classId]
	if not c then
		return false
	end
	if (tonumber(level) or 1) >= c.Level then
		return true
	end
	if type(owned) == "table" and (owned["Class/" .. classId] or owned[classId]) then
		return true
	end
	local t = c.Trial
	return t ~= nil and type(stats) == "table" and (tonumber(stats[t.Stat]) or 0) >= t.Count
end

-- A veteran class's trial: progress, goal, stat name (nil for classes without one).
function P.TrialProgress(classId, stats)
	local c = P.Classes[classId]
	local t = c and c.Trial
	if not t then
		return nil
	end
	local n = type(stats) == "table" and tonumber(stats[t.Stat]) or 0
	return math.min(n, t.Count), t.Count, t.Stat
end

-- Weapon levels ------------------------------------------------------------------------------------------------

P.Weapon = {
	Cap = 15,
	XpToNext = function(n)
		return 20 + 10 * (n - 1)
	end,
	Camos = { [5] = { "Desert", "Woodland" }, [10] = { "Arctic" }, [15] = { "Gold" } },
	-- weapon XP for a kill with the gun: +Headshot for a headshot kill, +Elite for an elite
	Xp = { Kill = 1, Headshot = 1, Elite = 5 },
	-- per-gun mastery after Gold (Profile GunStats[gun] = { K = kills, H = headshot kills, E = elite kills })
	Mastery = { Bone = { Stat = "H", Count = 100 }, Night = { Stat = "E", Count = 25 } },
}
local WREACH = { [1] = 0 }
for n = 2, P.Weapon.Cap do
	WREACH[n] = WREACH[n - 1] + P.Weapon.XpToNext(n - 1)
end
P.Weapon.CapXp = WREACH[P.Weapon.Cap]

-- level, XP into it, XP it needs (need = 0 at the cap).
function P.WeaponFromXp(gunXp)
	gunXp = math.max(0, math.floor(tonumber(gunXp) or 0))
	if gunXp >= P.Weapon.CapXp then
		return P.Weapon.Cap, 0, 0
	end
	local level = 1
	for n = P.Weapon.Cap - 1, 1, -1 do
		if gunXp >= WREACH[n] then
			level = n
			break
		end
	end
	return level, gunXp - WREACH[level], P.Weapon.XpToNext(level)
end

-- The weapon level a camo needs (nil if no weapon level gives it).
function P.WeaponCamoLevel(camoId)
	for level, list in P.Weapon.Camos do
		if table.find(list, camoId) then
			return level
		end
	end
	return nil
end

-- Night Pass ---------------------------------------------------------------------------------------------------
-- Season 1 "First Night": 6 weeks from Monday 2 Nov 2026 00:00 UTC to Monday 14 Dec 2026 00:00 UTC (move Starts and
-- Ends together if launch moves). Free: a reward every 2-3 tiers; Premium: one every tier, 6 x 500 Scrip among them.

local FREE = {
	[2] = { Kind = "Scrip", Amount = 250 },
	[4] = { Kind = "Card", Id = "Watchtower" },
	[7] = { Kind = "Boost", Amount = 1 },
	[9] = { Kind = "Scrip", Amount = 250 },
	[12] = { Kind = "Camo", Id = "Moth" },
	[14] = { Kind = "Token", Amount = 1 },
	[17] = { Kind = "Scrip", Amount = 250 },
	[20] = { Kind = "Operator", Id = "Drifter" },
	[22] = { Kind = "Boost", Amount = 1 },
	[25] = { Kind = "Scrip", Amount = 250 },
	[27] = { Kind = "Token", Amount = 1 },
	[30] = { Kind = "Card", Id = "Signalfire" },
}
local PREMIUM = {
	[1] = { Kind = "Card", Id = "Nightshift" },
	[2] = { Kind = "Boost", Amount = 1 },
	[3] = { Kind = "Scrip", Amount = 500 },
	[4] = { Kind = "Token", Amount = 1 },
	[5] = { Kind = "Card", Id = "Redline" },
	[6] = { Kind = "Boost", Amount = 1 },
	[7] = { Kind = "Token", Amount = 1 },
	[8] = { Kind = "Scrip", Amount = 500 },
	[9] = { Kind = "Boost", Amount = 1 },
	[10] = { Kind = "Operator", Id = "Nightjar" },
	[11] = { Kind = "Token", Amount = 1 },
	[12] = { Kind = "Boost", Amount = 1 },
	[13] = { Kind = "Scrip", Amount = 500 },
	[14] = { Kind = "Token", Amount = 1 },
	[15] = { Kind = "Camo", Id = "Signal" },
	[16] = { Kind = "Boost", Amount = 1 },
	[17] = { Kind = "Token", Amount = 1 },
	[18] = { Kind = "Scrip", Amount = 500 },
	[19] = { Kind = "Boost", Amount = 1 },
	[20] = { Kind = "Card", Id = "Floodline" },
	[21] = { Kind = "Token", Amount = 1 },
	[22] = { Kind = "Boost", Amount = 1 },
	[23] = { Kind = "Scrip", Amount = 500 },
	[24] = { Kind = "Token", Amount = 1 },
	[25] = { Kind = "Operator", Id = "Ember" },
	[26] = { Kind = "Boost", Amount = 1 },
	[27] = { Kind = "Token", Amount = 1 },
	[28] = { Kind = "Scrip", Amount = 500 },
	[29] = { Kind = "Boost", Amount = 1 },
	[30] = { Kind = "Card", Id = "Lamplight" },
}

P.Pass = {
	Season = 1,
	Name = "FIRST NIGHT",
	Tiers = 30,
	TierXp = 6500,
	Starts = 1793577600, -- 2026-11-02 00:00 UTC
	Ends = 1797206400, -- 2026-12-14 00:00 UTC
	Free = FREE,
	Premium = PREMIUM,
}
-- Every season's table by number, so a profile from an older season can still be paid out at rollover.
P.Seasons = { [1] = P.Pass }

-- tier reached (1..Tiers), pass XP into it, pass XP it needs (need = 0 at the last tier).
function P.PassTier(passXp)
	passXp = math.max(0, math.floor(tonumber(passXp) or 0))
	local pass = P.Pass
	local tier = math.min(pass.Tiers, 1 + passXp // pass.TierXp)
	if tier >= pass.Tiers then
		return pass.Tiers, 0, 0
	end
	return tier, passXp - (tier - 1) * pass.TierXp, pass.TierXp
end

-- The pass XP at which a tier is reached.
function P.PassXpFor(tier)
	return (math.clamp(math.floor(tier), 1, P.Pass.Tiers) - 1) * P.Pass.TierXp
end

do
	local last, scrip = 0, 0
	for tier = 1, P.Pass.Tiers do
		if FREE[tier] then
			assert(tier - last <= 3, "Shared.Progression: free pass gap before tier " .. tier)
			last = tier
		end
		local r = PREMIUM[tier]
		assert(r, "Shared.Progression: premium pass tier " .. tier .. " is empty")
		if r.Kind == "Scrip" then
			assert(r.Amount == 500, "Shared.Progression: premium Scrip rewards are 500")
			scrip += 1
		end
	end
	assert(scrip == 6, "Shared.Progression: the premium track carries 6 x 500 Scrip")
end

-- Challenges ---------------------------------------------------------------------------------------------------
-- { Id, Label (four words at most), Event, Goal, Xp, Kind = "Mode" | "Gear" | "Team", One = doable in one match }.
-- Class:<Id> counts kills made as that class; Mode:<Mode> (and Mode:Nightmare / Mode:Endless) counts finished matches.

local function ch(id, label, event, goal, xp, kind, one)
	return { Id = id, Label = label, Event = event, Goal = goal, Xp = xp, Kind = kind, One = one == true }
end

P.Challenges = {
	Daily = {
		ch("Nights4", "SURVIVE 4 NIGHTS", "Night", 4, 450, "Mode", true),
		ch("DefendRun", "FINISH A DEFEND RUN", "Mode:Defend", 1, 400, "Mode", true),
		ch("OutbreakRun", "FINISH AN OUTBREAK", "Mode:Outbreak", 1, 450, "Mode", true),
		ch("Contracts2", "COMPLETE 2 CONTRACTS", "Contract", 2, 500, "Mode", true),
		ch("EscapeOnce", "ESCAPE ONCE", "Escape", 1, 600, "Mode", true),
		ch("Objectives3", "CLEAR 3 OBJECTIVES", "Objective", 3, 500, "Mode", true),
		ch("CampaignRun", "PLAY THE CAMPAIGN", "Mode:Campaign", 1, 450, "Mode", true),
		ch("Nights6", "SURVIVE 6 NIGHTS", "Night", 6, 550, "Mode", false),
		ch("AkKills", "50 AK-47 KILLS", "Kill:AK", 50, 400, "Gear", true),
		ch("ShotgunKills", "40 SHOTGUN KILLS", "Kill:Shotgun", 40, 400, "Gear", true),
		ch("PistolKills", "25 PISTOL KILLS", "Kill:Pistol", 25, 400, "Gear", true),
		ch("Mp5Kills", "50 MP5 KILLS", "Kill:MP5", 50, 450, "Gear", true),
		ch("Headshots30", "LAND 30 HEADSHOTS", "Headshot", 30, 450, "Gear", true),
		ch("Elites3", "KILL 3 ELITES", "Elite", 3, 500, "Gear", true),
		ch("RiflemanKills", "75 KILLS AS RIFLEMAN", "Class:Rifleman", 75, 400, "Gear", true),
		ch("MedicKills", "60 KILLS AS MEDIC", "Class:Medic", 60, 450, "Gear", true),
		ch("Revives2", "REVIVE 2 SQUADMATES", "Revive", 2, 500, "Team", true),
		ch("Revives4", "REVIVE 4 SQUADMATES", "Revive", 4, 600, "Team", false),
		ch("Boards20", "REPAIR 20 BOARDS", "Board", 20, 400, "Team", true),
		ch("Boards40", "REPAIR 40 BOARDS", "Board", 40, 500, "Team", false),
		ch("Field3", "DEPLOY 3 FIELD ITEMS", "Field", 3, 450, "Team", true),
		ch("Field6", "DEPLOY 6 FIELD ITEMS", "Field", 6, 550, "Team", false),
		ch("Bandages5", "USE 5 BANDAGES", "Bandage", 5, 350, "Team", true),
		ch("Bandages10", "USE 10 BANDAGES", "Bandage", 10, 500, "Team", false),
	},
	Weekly = {
		ch("WKills", "KILL 750 ZOMBIES", "Kill", 750, 2500, "Gear", false),
		ch("WElites", "KILL 25 ELITES", "Elite", 25, 2500, "Gear", false),
		ch("WHeadshots", "LAND 200 HEADSHOTS", "Headshot", 200, 2500, "Gear", false),
		ch("WEscapes", "ESCAPE 3 TIMES", "Escape", 3, 3000, "Mode", false),
		ch("WNights", "SURVIVE 20 NIGHTS", "Night", 20, 2500, "Mode", false),
		ch("WWaves", "SURVIVE 40 WAVES", "Wave", 40, 2500, "Mode", false),
		ch("WContracts", "COMPLETE 10 CONTRACTS", "Contract", 10, 2500, "Mode", false),
		ch("WObjectives", "CLEAR 12 OBJECTIVES", "Objective", 12, 2500, "Mode", false),
		ch("WNightmare", "PLAY 2 NIGHTMARE RUNS", "Mode:Nightmare", 2, 3000, "Mode", false),
		ch("WRevives", "REVIVE 15 SQUADMATES", "Revive", 15, 2500, "Team", false),
		ch("WBoards", "REPAIR 200 BOARDS", "Board", 200, 2000, "Team", false),
		ch("WField", "DEPLOY 20 FIELD ITEMS", "Field", 20, 2000, "Team", false),
	},
}
P.DailyCount = 3
P.WeeklyCount = 5

local BY_ID, BY_KIND, WEEKLY_IDS = {}, { Mode = {}, Gear = {}, Team = {} }, {}
for _, c in P.Challenges.Daily do
	assert(not BY_ID[c.Id], "Shared.Progression: duplicate challenge " .. c.Id)
	c.Weekly = false
	BY_ID[c.Id] = c
	table.insert(BY_KIND[c.Kind], c)
end
for _, c in P.Challenges.Weekly do
	assert(not BY_ID[c.Id], "Shared.Progression: duplicate challenge " .. c.Id)
	c.Weekly = true
	BY_ID[c.Id] = c
	table.insert(WEEKLY_IDS, c.Id)
end
for id, c in BY_ID do
	local words = 0
	for _ in string.gmatch(c.Label, "%S+") do
		words += 1
	end
	assert(words <= 4, "Shared.Progression: challenge label over four words: " .. id)
end

function P.Challenge(id)
	return BY_ID[id]
end

-- UTC day and Monday-based UTC week numbers (os.time() if t is nil).
function P.Day(t)
	return math.floor((t or os.time()) / 86400)
end
function P.Week(t)
	return math.floor((P.Day(t) + 3) / 7)
end
-- When a day or week ends (os.time), for countdowns.
function P.DayEnds(day)
	return (day + 1) * 86400
end
function P.WeekEnds(week)
	return ((week + 1) * 7 - 3) * 86400
end

-- A 32-bit hash of two integers (xorshift), the same on every server.
local function hash(a, b)
	local x = (math.floor(a) * 2654435761 + math.floor(b) * 40503 + 2654435769) % 4294967296
	if x == 0 then
		x = 1
	end
	for _ = 1, 4 do
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
	end
	return x
end
P.Hash = hash

local DAILY_KINDS = { "Mode", "Gear", "Team" }

-- The three dailies of a UTC day: one Mode, one Gear (class or gun), one Team; at least one doable in one match.
function P.DailyIds(utcDay)
	utcDay = math.floor(tonumber(utcDay) or 0)
	local ids, any = {}, false
	for i, kind in DAILY_KINDS do
		local pool = BY_KIND[kind]
		local c = pool[hash(utcDay, i) % #pool + 1]
		ids[i] = c.Id
		any = any or c.One
	end
	if not any then
		local pool = BY_KIND.Mode
		local start = hash(utcDay, 1) % #pool
		for k = 1, #pool do
			local c = pool[(start + k) % #pool + 1]
			if c.One then
				ids[1] = c.Id
				break
			end
		end
	end
	return ids
end

-- The five weeklies of a UTC week (P.Week).
function P.WeeklyIds(utcWeek)
	utcWeek = math.floor(tonumber(utcWeek) or 0)
	local pool = table.clone(WEEKLY_IDS)
	for i = #pool, 2, -1 do
		local j = hash(utcWeek, 100 + i) % i + 1
		pool[i], pool[j] = pool[j], pool[i]
	end
	local ids = {}
	for i = 1, math.min(P.WeeklyCount, #pool) do
		ids[i] = pool[i]
	end
	return ids
end

-- The re-roll for daily slot `index` on `utcDay`: another challenge of the same kind not already in `current`.
function P.RerollId(utcDay, index, current)
	local def = BY_ID[current[index]]
	local pool = BY_KIND[def and not def.Weekly and def.Kind or DAILY_KINDS[index] or "Mode"]
	local start = hash(utcDay, 50 + index) % #pool
	for k = 0, #pool - 1 do
		local c = pool[(start + k) % #pool + 1]
		if not table.find(current, c.Id) then
			return c.Id
		end
	end
	return nil
end

return P
