--!strict
-- Shared.Front: FRONTLINE, the campaign place's mode since 6 Nov 2026 (horror-shooter/war/FRONTLINE-PLAN.md).
-- A 12-a-side attack-and-defend push up the valley: three sectors a match, HOUND against the Lamplighters, humans on
-- both sides and bots in every empty place. Every number lives here; ServerScriptService.FrontServer runs the match,
-- ServerStorage.Modules.FrontBattle the bots, StarterPlayerScripts.FrontClient the side's view (teammate outlines,
-- spotted foes, the streak key) and MatchHud the two HUD lines. Its presence in Shared also turns on the "Streak"
-- key in Shared.Controls (Requires = "Front").
--
-- Workspace attributes (FrontServer): Front (true), WaveState "Front" | "FrontEnd", FrontAttack (the attacking side,
-- "Ally" | "Enemy"), FrontSector (index into Sectors), FrontStep (1..MatchSectors), FrontEndsAt (server time),
-- FrontTickets, FrontProgress (0..1), FrontContest ("Attack" | "Defend" | "Contested" | nil: who is winning the flag),
-- WarMission (the sector's name), Objective (the flag, for WarClient's marker), FrontWinner (at match end),
-- FrontWeek / FrontWeekGoal (pass 5's universe-wide count of sectors taken this week).
-- Player attributes: Side ("Ally" = HOUND, "Enemy" = Lamplighters), Streak (kills this life), StreakReady (a Streaks
-- key, or nil), plus leaderstats Kills / Deaths for the player list.
-- Model attributes: LastHitBy (UserId) and LastHitAt (server time) on anything a player hurts (kill credit),
-- SpottedAlly / SpottedEnemy (server time the SPOTTER mark ends, for that side's eyes).

local Front = {}

Front.Version = 1

Front.Sides = {
	Ally = { Name = "HOUND", Team = "HOUND", Color = Color3.fromRGB(110, 170, 235), Operator = "Woodland", Kind = "FrontHound" },
	Enemy = { Name = "LAMPLIGHTERS", Team = "LAMPLIGHTERS", Color = Color3.fromRGB(255, 160, 60), Operator = "Lamplighter", Kind = "FrontLamp" },
}

function Front.Other(side: string): string
	return if side == "Ally" then "Enemy" else "Ally"
end

-- The five fights in map order (Map.War spot groups, MAP-PLAN.md). Flag: the group whose centre is the flag; Posts:
-- the defenders' posts; Rear: where defenders come back in; Attack: where attackers come back in (a checkpoint part)
-- and Flanks: extra attacker spawns (the previous sector's rear spots, out of the defenders' sight).
Front.Sectors = {
	{ Key = "Road", Name = "THE ROAD", Flag = "M1_Road", Posts = "M1_Road", Rear = "M1_Road_Rear", Attack = "Start", Flanks = nil },
	{ Key = "Depot", Name = "THE DEPOT", Flag = "M1_Depot", Posts = "M1_Depot", Rear = "M1_Depot_Rear", Attack = "Start", Flanks = "M1_Road_Rear" },
	{ Key = "Plaza", Name = "THE PLAZA", Flag = "M2_Plaza", Posts = "M2_Plaza", Rear = "M2_Plaza_Rear", Attack = "Checkpoint1", Flanks = "M1_Depot_Rear" },
	{ Key = "Yards", Name = "THE YARDS", Flag = "M3_Mid", Posts = "M3_Mid", Rear = "M3_Mid_Rear", Attack = "Checkpoint2", Flanks = "M2_Plaza_Rear" },
	{ Key = "Basin", Name = "THE BASIN", Flag = "M3_LZ", Posts = "M3_LZ", Rear = "M3_LZ_Rear", Attack = "Checkpoint3", Flanks = "M3_Mid_Rear" },
}
Front.MatchSectors = 3 -- a match is this many sectors in a row, starting at 1, 2 or 3

-- The flag: a ring Radius studs across its middle, within Height studs up or down. Attackers fill it while they
-- outnumber the defenders inside, the defenders drain it while they outnumber the attackers, equal numbers freeze
-- it. Time: seconds to fill it with one attacker more than the defenders; every extra one adds Extra (up to Max).
-- Bots count BotWeight each, at most BotCap a side, so bots alone can take a flag but slowly.
Front.Capture = {
	Radius = 20,
	Height = 14,
	Time = 30,
	Extra = 0.25,
	Max = 2,
	BotWeight = 0.5,
	BotCap = 1,
	Drain = 1, -- the defenders drain at this share of the fill speed
}

Front.Match = {
	Tickets = 40, -- the attackers' per sector; a player of theirs dying costs one, a bot nothing
	Refund = 15, -- tickets back for taking a sector
	SectorTime = 240, -- seconds per sector
	Bonus = 90, -- seconds added for taking one
	Breather = 10, -- seconds between sectors
	Intermission = 15, -- seconds between matches
	StartDelay = 4, -- seconds from the first player in to the match starting
	Wave = 8, -- the dead come back on the next wave tick (every Wave seconds), at least MinDead seconds after dying
	MinDead = 4,
	Protect = 3, -- seconds nothing hurts a fresh spawn
	SpawnRing = 30, -- studs round a spawn the other side should not stand in
	SpawnRingTime = 3, -- seconds in it before it starts to hurt
	SpawnRingDamage = 25, -- a second
	Credit = 6, -- seconds a hit counts for kill credit
}

Front.Bots = {
	Size = 12, -- a side: players plus bots
	Respawn = 8, -- seconds before a fallen bot comes back
	Callsigns = {
		Ally = { "REYES", "OKAFOR", "HASKINS", "MORROW", "TAKEDA", "BRANDT", "KESSLER", "DUBOIS", "NOVAK", "IBARRA", "QUINN", "VOSS" },
		Enemy = { "WICK", "TALLOW", "CINDER", "ASH", "EMBER", "SOOT", "FLINT", "TINDER", "CHAR", "SMOKE", "GLOAM", "BRAND" },
	},
	Rigs = { Ally = { "OperatorB", "OperatorA", "OperatorC" }, Enemy = { "HostileA", "HostileB" } },
	LaneWidth = 26,
	AttackRadius = 8, -- tight, so the attackers step onto the flag (pass 1 test: at 16 they stalled 40 studs out)
	DefendRadius = 14,
	SpawnSpread = 6,
}

-- The two bot kinds, added to GameConfig.War.Soldiers by FrontBattle (the same body and brain as the campaign's, even
-- numbers both ways: a bot dies to about as many rounds as a player does).
Front.Soldiers = {
	FrontHound = {
		Side = "Ally", Rig = "OperatorA", Gun = "AK",
		Health = 100, WalkSpeed = 14, Damage = 11, HeadChance = 0.2,
		RPM = 450, Mag = 30, Reload = 2.4,
		Burst = NumberRange.new(3, 5), BurstGap = NumberRange.new(0.5, 1.2),
		Spread = 3.2, Range = 160, React = NumberRange.new(0.45, 0.9),
		Leash = 12, Strafe = 6, StrafeTime = NumberRange.new(1.2, 2.6),
	},
	FrontLamp = {
		Side = "Enemy", MobType = "Lamplighter", Rig = { "HostileA", "HostileB" }, Gun = "AK",
		Health = 100, WalkSpeed = 14, Damage = 11, HeadChance = 0.2,
		RPM = 450, Mag = 30, Reload = 2.4,
		Burst = NumberRange.new(3, 5), BurstGap = NumberRange.new(0.5, 1.2),
		Spread = 3.2, Range = 160, React = NumberRange.new(0.45, 0.9),
		Leash = 12, Strafe = 6, StrafeTime = NumberRange.new(1.2, 2.6),
	},
}

-- Points (the HUD's top right, Modules.Points) and Scrip (Profile.Earn) for a match.
Front.Points = { Kill = 100, Headshot = 25, BotKill = 50, Capture = 20, Taken = 200, Held = 150 }
Front.Pay = { Sector = 60, Win = 150, Loss = 40, Kills = 5, PerKills = 10 }

-- Killstreaks: kills in one life. One key (Controls "Streak") calls the best one ready; dying loses what is not used.
Front.Streaks = {
	{ Key = "Spotter", Name = "SPOTTER", Kills = 3, Time = 10, Radius = 140 },
	{ Key = "Mortars", Name = "MORTARS", Kills = 5, Shells = 5, Spread = 10, Damage = 200, BlastRadius = 12, Duration = 6, Range = 320 },
	{ Key = "Armour", Name = "ARMOUR", Kills = 8, Time = 60, Health = 900 },
}
function Front.Streak(key: string?)
	for _, s in Front.Streaks do
		if s.Key == key then
			return s
		end
	end
	return nil
end

-- Pass 5, "the Front": every sector taken in any server adds to this week's count (Modules.FrontWeek: one UpdateAsync a
-- match, key "Week<n>"). Once it reaches Goal, everyone who plays FRONTLINE that week gets Reward (a Catalogue item).
-- The lobby's FrontBoard reads the same store (its copy of these names must match). Studio uses StudioStore.
Front.Week = { Goal = 2500, Store = "FrontWeek_v1", StudioStore = "FrontWeek_Studio_v1", Refresh = 60, Reward = "Camo/Signal", RewardName = "SIGNAL CAMO" }

-- Monday 00:00 UTC weeks since the Unix epoch's first Monday (5 Jan 1970).
function Front.WeekOf(t: number): number
	return math.floor((t - 345600) / 604800)
end

-- The radio (RadioVoice), per side: what the attackers hear and what the defenders hear.
Front.Lines = {
	Start = { Attack = "All units, push the line. Take %s.", Defend = "They're coming for %s. Hold it." },
	Taken = { Attack = "%s is ours. Move up.", Defend = "%s is lost. Fall back to the next line." },
	Losing = { Attack = "They're taking the flag back, get on it!", Defend = "They're on the flag, clear them off!" },
	LowTickets = { Attack = "We're running out of men. Take that flag!", Defend = "They're nearly spent. Hold on!" },
	Win = { Attack = "The valley is ours. Good work.", Defend = "They broke. The line held." },
	Loss = { Attack = "The push failed. Pull back.", Defend = "We've lost the valley." },
	Mortars = "Mortars on the way, keep your heads down.",
	Armour = "Armour moving up, follow it in.",
	Spotter = "Eyes in the sky. Targets marked.",
}

-- The capture rate this tick (signed: + toward the attackers), from how many of each side stand on the flag.
-- Pure, so it can be tested on its own.
function Front.CaptureRate(attPlayers: number, attBots: number, defPlayers: number, defBots: number): number
	local C = Front.Capture
	local att = attPlayers + math.min(attBots * C.BotWeight, C.BotCap)
	local def = defPlayers + math.min(defBots * C.BotWeight, C.BotCap)
	local diff = att - def
	if math.abs(diff) < 0.01 then
		return 0
	end
	local speed = math.min(1 + C.Extra * (math.abs(diff) - 1), C.Max) / C.Time
	return if diff > 0 then speed else -speed * C.Drain
end

-- Next respawn wave at or after `now + MinDead` (waves tick every Wave seconds from the server's start).
function Front.NextWave(now: number): number
	local M = Front.Match
	local t = now + M.MinDead
	return math.ceil(t / M.Wave) * M.Wave
end

return Front
