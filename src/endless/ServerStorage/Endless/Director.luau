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
