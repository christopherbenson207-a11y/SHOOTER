-- FRONTLINE's bots (Shared.Front, horror-shooter/war/FRONTLINE-PLAN.md): both sides, Front.Bots.Size bodies a side,
-- players plus bots. The same light soldiers and brain as the campaign (Modules.Soldier, cover from Modules.CoverMap);
-- this module only decides how many of each side stand on the field, where they come back in and what they are told.
--   FrontBattle.Start() / Stop()
--   FrontBattle.SetSector(s): s = { Flag = Vector3, Posts = {parts}, Attack = "Ally" | "Enemy",
--     Spawns = { Ally = {parts}, Enemy = {parts} } }. Every living bot gets its new order at once: the attackers
--     push the flag in three lanes, the defenders hold the posts (every third one the flag itself).
--   FrontBattle.SetPlayers(side, n): how many players that side has; the bots make up the rest.
--   FrontBattle.Claim(side) -> CFrame | nil: a joining player takes the calmest bot's place (the bot goes).
--   FrontBattle.Release(side, cf): a leaving player's place goes back to a bot standing at cf.
--   FrontBattle.CountIn(pos, radius, height) -> { Ally = n, Enemy = n }: living bots round a point.
--   FrontBattle.Positions(side) -> { Vector3 }: where that side's living bots are.
--   FrontBattle.OnBotDied(soldier, side) and FrontBattle.OnContact(soldier): hooks for FrontServer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Front = require(ReplicatedStorage.Shared.Front)
local Soldier = require(script.Parent.Soldier)
local CoverMap = require(script.Parent.CoverMap)

local BOTS = Front.Bots
local LANES = { 0, -1, 1 }

-- The two bot kinds join the campaign's in GameConfig.War.Soldiers (Soldier reads its kinds from there).
for kind, stats in Front.Soldiers do
	GameConfig.War.Soldiers[kind] = stats
end

local FrontBattle = {}
FrontBattle.OnBotDied = nil
FrontBattle.OnContact = nil

local on = false
local gen = 0
local sector = nil
local sides = {}

local function newSide(side)
	return { Side = side, Players = 0, Bots = {}, Due = {}, Count = 0 }
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function hostilesOf(side)
	local list = {}
	for _, s in Soldier.All(Front.Other(side)) do
		table.insert(list, s.Root.Position)
	end
	return list
end

-- A standing place near one of the side's spawns, away from the other side when it can be.
local function spawnCF(side)
	local spots = sector and sector.Spawns[side] or {}
	local goal = sector and sector.Flag or Vector3.zero
	if #spots == 0 then
		return CFrame.new(goal + Vector3.new(0, 3, 60))
	end
	local foes = hostilesOf(side)
	local best, bestD = spots[1], -1
	for _ = 1, 4 do
		local spot = spots[math.random(#spots)]
		local d = math.huge
		for _, f in foes do
			d = math.min(d, (f - spot.Position).Magnitude)
		end
		if d > bestD then
			best, bestD = spot, d
		end
		if d >= 50 then
			break
		end
	end
	local spread = BOTS.SpawnSpread
	local at = best.Position + Vector3.new((math.random() * 2 - 1) * spread, 0, (math.random() * 2 - 1) * spread)
	local g = CoverMap.Snap(at, spread + 2)
	local pos = (g or best.Position) + Vector3.new(0, 3, 0)
	local look = flat(goal - pos)
	return if look.Magnitude > 1 then CFrame.lookAt(pos, pos + look) else CFrame.new(pos)
end

-- The order for a bot of side, by its number (lane or post).
local function orderFor(side, n)
	if not sector then
		return nil
	end
	local flag = sector.Flag
	if side == sector.Attack then
		local from = Vector3.zero
		local spots = sector.Spawns[side]
		for _, p in spots do
			from += p.Position
		end
		from = if #spots > 0 then from / #spots else flag + Vector3.new(0, 0, 80)
		local fwd = flat(flag - from)
		fwd = if fwd.Magnitude > 1 then fwd.Unit else Vector3.new(0, 0, -1)
		local right = fwd:Cross(Vector3.yAxis)
		local lane = LANES[(n - 1) % #LANES + 1] * BOTS.LaneWidth
		local goal = flag + right * lane * 0.3
		return {
			Mode = "Attack", Goal = goal, Radius = BOTS.AttackRadius,
			LaneA = from + right * lane * 0.5, LaneB = goal, Facing = { flag + fwd * 30 },
		}
	end
	local facing = {}
	for _, p in sector.Spawns[sector.Attack] or {} do
		table.insert(facing, p.Position)
	end
	local posts = sector.Posts
	local goal = flag
	if n % 3 ~= 0 and #posts > 0 then
		goal = posts[(n - 1) % #posts + 1].Position
	end
	return { Mode = "Defend", Goal = goal, Radius = BOTS.DefendRadius, Facing = if #facing > 0 then facing else nil }
end

local function spawnBot(side, cf)
	local st = sides[side]
	st.Count += 1
	local n = st.Count
	local names = BOTS.Callsigns[side]
	local rigs = BOTS.Rigs[side]
	local kind = Front.Sides[side].Kind
	local s = Soldier.Spawn(kind, cf, {
		Callsign = names[(n - 1) % #names + 1],
		Rig = rigs[(n - 1) % #rigs + 1],
		Slot = n,
		Team = (n - 1) % 3 + 1,
		Order = orderFor(side, n),
	})
	s.FrontN = n
	st.Bots[s] = true
	s.OnContact = function(soldier)
		if FrontBattle.OnContact then
			FrontBattle.OnContact(soldier)
		end
	end
	s.OnDied = function()
		if st.Bots[s] then
			st.Bots[s] = nil
			if FrontBattle.OnBotDied then
				task.spawn(FrontBattle.OnBotDied, s, side)
			end
		end
	end
	return s
end

local function alive(st)
	local n = 0
	for s in st.Bots do
		if s.Alive then
			n += 1
		else
			st.Bots[s] = nil
		end
	end
	return n
end

local function calmest(st)
	local best, bestScore = nil, -math.huge
	for s in st.Bots do
		if s.Alive then
			local score = (if s:Calm() then 100 else 0) - (s.Suppression or 0) * 10
			if score > bestScore then
				best, bestScore = s, score
			end
		end
	end
	return best
end

local function balance(st, now)
	local want = math.max(0, BOTS.Size - st.Players)
	local have = alive(st)
	-- Too many (players joined this side): the calmest goes.
	while have > want do
		local s = calmest(st)
		if not s then
			break
		end
		st.Bots[s] = nil
		s:Remove()
		have -= 1
	end
	-- Too few: one comes back Respawn seconds after each loss.
	local pending = #st.Due
	while have + pending < want do
		table.insert(st.Due, now + BOTS.Respawn)
		pending += 1
	end
	while #st.Due > 0 and have + #st.Due > want do
		table.remove(st.Due)
	end
	local i = 1
	while i <= #st.Due do
		if now >= st.Due[i] and sector then
			table.remove(st.Due, i)
			spawnBot(st.Side, spawnCF(st.Side))
			have += 1
		else
			i += 1
		end
	end
end

local function loop(mine)
	while on and gen == mine do
		local now = os.clock()
		for _, st in sides do
			balance(st, now)
		end
		task.wait(0.5)
	end
end

function FrontBattle.Start()
	FrontBattle.Stop()
	on = true
	gen += 1
	sides.Ally = newSide("Ally")
	sides.Enemy = newSide("Enemy")
	task.spawn(loop, gen)
end

function FrontBattle.Stop()
	on = false
	gen += 1
	sector = nil
	Soldier.Clear()
	table.clear(sides)
end

-- A new sector: spawns, the flag and every living bot's order. The first sector fills both sides at once.
function FrontBattle.SetSector(s)
	sector = s
	if not on then
		return
	end
	for side, st in sides do
		for bot in st.Bots do
			if bot.Alive then
				bot:SetOrder(orderFor(side, bot.FrontN or 1))
			end
		end
		local want = math.max(0, BOTS.Size - st.Players)
		local have = alive(st)
		if have == 0 then
			table.clear(st.Due)
			for _ = 1, want do
				spawnBot(side, spawnCF(side))
			end
		end
	end
end

function FrontBattle.SetPlayers(side, n)
	local st = sides[side]
	if st then
		st.Players = n
	end
end

-- A player joining side mid-fight takes the calmest bot's place where it stands (nil if there is none).
function FrontBattle.Claim(side)
	local st = sides[side]
	if not (on and st) then
		return nil
	end
	local s = calmest(st)
	if not s then
		return nil
	end
	local root = s.Root
	local cf = CFrame.new(root.Position + Vector3.new(0, 1.5, 0)) * root.CFrame.Rotation
	st.Bots[s] = nil
	s:Remove()
	return cf
end

-- A player leaving side: a bot stands where they stood (cf), else one comes in at the spawn soon.
function FrontBattle.Release(side, cf)
	local st = sides[side]
	if not (on and st) then
		return
	end
	st.Players = math.max(0, st.Players - 1)
	if cf and sector then
		spawnBot(side, cf)
	end
end

function FrontBattle.CountIn(pos, radius, height)
	local out = { Ally = 0, Enemy = 0 }
	local r2 = radius * radius
	for side, st in sides do
		for s in st.Bots do
			if s.Alive and s.Root then
				local d = s.Root.Position - pos
				if d.X * d.X + d.Z * d.Z <= r2 and math.abs(d.Y) <= height then
					out[side] += 1
				end
			end
		end
	end
	return out
end

function FrontBattle.Positions(side)
	local list = {}
	local st = sides[side]
	if st then
		for s in st.Bots do
			if s.Alive and s.Root then
				table.insert(list, s.Root.Position)
			end
		end
	end
	return list
end

function FrontBattle.Bots(side)
	local list = {}
	local st = sides[side]
	if st then
		for s in st.Bots do
			if s.Alive then
				table.insert(list, s)
			end
		end
	end
	return list
end

return FrontBattle
