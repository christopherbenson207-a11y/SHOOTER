-- FRONTLINE: the campaign place's mode since 6 Nov 2026 (horror-shooter/war/FRONTLINE-PLAN.md, numbers in Shared.Front).
-- A 12-a-side attack-and-defend push up the valley: HOUND attacks north, the Lamplighters hold, three sectors a match.
-- Players are on both sides (they swap sides every match) and FrontBattle's bots fill every empty place.
--   A sector: the flag is the centre of its Map.War spot group. Attackers fill it while they outnumber the
--   defenders inside, defenders drain it while they outnumber the attackers (Front.CaptureRate). Full = taken:
--   tickets back, time carried over, a short breather, the next sector. Attackers lose a ticket per player death
--   (bots are free) and lose the match when the tickets or the clock run out; they win by taking every sector.
--   The dead come back on the next wave tick (Front.NextWave) at their side's spawns; a player joining mid-fight
--   takes the calmest bot's place where it stands, a player leaving gives it back.
--   Kills: the LastHitBy attribute that GunServer and WarDamage put on whatever a player hurts. They count for the
--   player list (leaderstats Kills / Deaths), Points, Scrip at the end, and the killstreaks (Streak).
-- WarServer (the old story campaign) only runs when workspace PlayCampaign is set; then this script stays out.
-- Studio: workspace StudioMode = "Front" plays whole matches with bots alone (pass 1's test); FrontStartSector picks
-- the first sector.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")
local TeleportService = game:GetService("TeleportService")

if workspace:GetAttribute("PlayCampaign") then
	return
end

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Front = require(ReplicatedStorage.Shared.Front)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Points = require(ServerStorage.Modules.Points)
local Profile = require(ServerStorage.Modules.Profile)
local Uniform = require(ServerStorage.Modules.Uniform)
local CoverMap = require(ServerStorage.Modules.CoverMap)
local FrontBattle = require(ServerStorage.Modules.FrontBattle)
local FrontStreaks = require(ServerStorage.Modules.FrontStreaks)
local FrontWeek = require(ServerStorage.Modules.FrontWeek)
local Remotes = ReplicatedStorage.Remotes

local M = Front.Match
local CAP = Front.Capture
local PTS = Front.Points
local PAY = Front.Pay

TeleportService.TeleportInitFailed:Connect(function(player)
	if player.Parent then
		Profile.Reclaim(player)
	end
end)

workspace:SetAttribute("Campaign", true) -- MenuClient deploys straight in
workspace:SetAttribute("Front", true)
workspace:SetAttribute("Mode", "Front")
workspace:SetAttribute("HoldRespawns", true) -- MenuServer leaves respawns to this script
workspace:SetAttribute("FrontAttack", "Ally")
workspace:SetAttribute("WaveState", "FrontEnd")
PlayerHealth.Rules.HitGrace = 0.05
PlayerHealth.Rules.NoDown = true
Points.Start()

local map = workspace:WaitForChild("Map")
local warMap = map:WaitForChild("War")

-- Teams, for the player list.
local teams = {}
for side, info in Front.Sides do
	local team = Teams:FindFirstChild(info.Team) or Instance.new("Team")
	team.Name = info.Team
	team.TeamColor = BrickColor.new(info.Color)
	team.AutoAssignable = false
	team.Parent = Teams
	teams[side] = team
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function now()
	return workspace:GetServerTimeNow()
end

-- Spots ---------------------------------------------------------------------------------------------

local function warSpots(name)
	local f = name and warMap:FindFirstChild(name)
	local list = {}
	local kids = if not f then {} elseif f:IsA("BasePart") then { f } else f:GetChildren()
	for _, p in kids do
		if p:IsA("BasePart") then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function centre(list)
	local sum = Vector3.zero
	for _, p in list do
		sum += p.Position
	end
	return if #list > 0 then sum / #list else Vector3.zero
end

-- Sector i as the battle needs it: the flag point, the defenders' posts, both sides' spawn parts.
local function sectorData(i)
	local s = Front.Sectors[i]
	local posts = warSpots(s.Posts)
	local flag = centre(warSpots(s.Flag))
	local snapped = CoverMap.Snap(flag, 12)
	if snapped then
		flag = snapped
	end
	local attack = warSpots(s.Attack)
	for _, p in warSpots(s.Flanks) do
		table.insert(attack, p)
	end
	local rear = warSpots(s.Rear)
	local points = { flag }
	for _, list in { posts, attack, rear } do
		for _, p in list do
			table.insert(points, p.Position)
		end
	end
	return {
		Index = i, Key = s.Key, Name = s.Name, Flag = flag, Posts = posts,
		Attack = workspace:GetAttribute("FrontAttack") or "Ally",
		Spawns = { Ally = attack, Enemy = rear },
		Box = Front.PlayBox(points),
	}
end

-- Players -------------------------------------------------------------------------------------------

local function inMatch()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InMatch") then
			table.insert(list, p)
		end
	end
	return list
end

local function sideOf(player)
	return player:GetAttribute("Side") or "Ally"
end

local function isAlive(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character:IsDescendantOf(workspace)
end

local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function stat(player, name)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local v = ls:FindFirstChild(name)
	if not v then
		v = Instance.new("IntValue")
		v.Name = name
		v.Parent = ls
	end
	return v
end

local function countSides()
	local n = { Ally = 0, Enemy = 0 }
	for _, p in inMatch() do
		n[sideOf(p)] += 1
	end
	return n
end

local function setSide(player, side)
	player:SetAttribute("Side", side)
	player:SetAttribute("FrontOperator", Front.Sides[side].Operator)
	player.Team = teams[side]
	player.Neutral = false
end

-- The side with fewer players (ties: the attackers, who need the bodies more).
local function emptierSide(except)
	local n = countSides()
	if except then
		n[sideOf(except)] -= 1
	end
	return if n.Enemy < n.Ally then "Enemy" else "Ally"
end

-- Radio and sounds, per side (attackers and defenders hear different words).
local function radioSide(key, arg)
	local line = Front.Lines[key]
	if not line then
		return
	end
	local attack = workspace:GetAttribute("FrontAttack")
	for _, p in inMatch() do
		local text = if type(line) == "string" then line elseif sideOf(p) == attack then line.Attack else line.Defend
		if arg then
			text = string.format(text, arg)
		end
		Remotes.Match:FireClient(p, "Radio", text, "Front" .. key)
	end
end

local function sound(cue, side)
	for _, p in inMatch() do
		if not side or sideOf(p) == side then
			Remotes.Match:FireClient(p, "FrontSound", cue)
		end
	end
end

local function notice(text, side)
	for _, p in inMatch() do
		if not side or sideOf(p) == side then
			Remotes.Match:FireClient(p, "Notice", text)
		end
	end
end

-- The match state -----------------------------------------------------------------------------------

local match = {
	on = false,
	sector = nil, -- sectorData
	step = 0,
	tickets = M.Tickets,
	progress = 0,
	endsAt = 0,
	taken = 0,
	joined = {}, -- [player] = true once they've had their first spawn this match
	ring = {}, -- [player] = seconds inside the other side's spawn ring
	out = {}, -- [player] = server time of the last out-of-bounds hurt
	said = {}, -- radio lines already used this sector
}

-- The flag -------------------------------------------------------------------------------------------
-- A pole on the flag's ground with the holder's cloth: it comes down as the attackers fill the flag and goes back up in
-- their colour. A faint ring on the ground shows the capture area: white, or the colour of the side winning it.
local POLE = 18
local flag = nil -- { Model, Cloth, Ring, Base }
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
groundParams.IgnoreWater = true

local function groundAt(pos)
	local ignore = { workspace:FindFirstChild("Fx") }
	for _, name in { "Squad", "Hostiles" } do
		table.insert(ignore, workspace:FindFirstChild(name))
	end
	for _, p in Players:GetPlayers() do
		table.insert(ignore, p.Character)
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 25, 0), Vector3.new(0, -80, 0), groundParams)
	return if hit then hit.Position else pos
end

local function flagPart(model, name, shape, size, cf, material, color, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Material = material
	p.Color = color
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = transparency == nil
	p.Parent = model
	return p
end

local function clearFlag()
	if flag then
		flag.Model:Destroy()
		flag = nil
	end
end

local function buildFlag(s)
	clearFlag()
	local model = Instance.new("Model")
	model.Name = "FrontFlag"
	local base = groundAt(s.Flag)
	local up = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis is X; this stands it up
	local steel = Color3.fromRGB(70, 72, 76)
	flagPart(model, "Foot", Enum.PartType.Cylinder, Vector3.new(0.8, 2.4, 2.4), CFrame.new(base + Vector3.new(0, 0.4, 0)) * up, Enum.Material.Concrete, Color3.fromRGB(120, 118, 112))
	flagPart(model, "Pole", Enum.PartType.Cylinder, Vector3.new(POLE, 0.45, 0.45), CFrame.new(base + Vector3.new(0, POLE / 2, 0)) * up, Enum.Material.Metal, steel)
	flagPart(model, "Top", Enum.PartType.Ball, Vector3.one * 0.8, CFrame.new(base + Vector3.new(0, POLE + 0.3, 0)), Enum.Material.Metal, steel)
	local cloth = flagPart(model, "Cloth", Enum.PartType.Block, Vector3.new(0.1, 2.6, 4.2), CFrame.new(base + Vector3.new(0, POLE - 1.6, 2.3)), Enum.Material.Fabric, Front.Sides[Front.Other(s.Attack)].Color)
	local ring = flagPart(model, "Ring", Enum.PartType.Cylinder, Vector3.new(0.12, CAP.Radius * 2, CAP.Radius * 2), CFrame.new(base + Vector3.new(0, 0.15, 0)) * up, Enum.Material.Neon, Color3.new(1, 1, 1), 0.85)
	model.Parent = map:FindFirstChild("WarDressing") or workspace
	flag = { Model = model, Cloth = cloth, Ring = ring, Base = base }
end

local function paintFlag()
	local s = match.sector
	if not (flag and s) then
		return
	end
	local attack = s.Attack
	local defend = Front.Other(attack)
	local p = match.progress
	local height = if p < 0.5 then 1 - p * 2 else (p - 0.5) * 2 -- 1 at the top, 0 at the foot
	flag.Cloth.Color = Front.Sides[if p < 0.5 then defend else attack].Color
	flag.Cloth.CFrame = CFrame.new(flag.Base + Vector3.new(0, 3 + height * (POLE - 4.6), 2.3))
	local contest = workspace:GetAttribute("FrontContest")
	flag.Ring.Color = if contest == "Attack" then Front.Sides[attack].Color
		elseif contest == "Defend" then Front.Sides[defend].Color
		else Color3.new(1, 1, 1)
	flag.Ring.Transparency = if contest then 0.7 else 0.85
end

local function publish()
	workspace:SetAttribute("FrontTickets", match.tickets)
	workspace:SetAttribute("FrontProgress", match.progress)
	workspace:SetAttribute("FrontEndsAt", if match.on then match.endsAt else nil)
	paintFlag()
end

-- Where a player of side comes in: one of the side's spawns, the one furthest from the other side.
local function spawnCF(side)
	local s = match.sector
	local spots = if s then s.Spawns[side] else {}
	if #spots == 0 then
		spots = warSpots("Start")
	end
	local goal = if s then s.Flag else Vector3.zero
	if #spots == 0 then
		return CFrame.new(goal + Vector3.new(0, 5, 60))
	end
	local foes = FrontBattle.Positions(Front.Other(side))
	for _, p in inMatch() do
		local root = sideOf(p) ~= side and isAlive(p) and rootOf(p)
		if root then
			table.insert(foes, root.Position)
		end
	end
	local best, bestD = spots[1], -math.huge
	for _, spot in spots do
		local d = 400
		for _, f in foes do
			d = math.min(d, (f - spot.Position).Magnitude)
		end
		d += math.random() * 20 -- not always the same one
		if d > bestD then
			best, bestD = spot, d
		end
	end
	local spread = Front.Bots.SpawnSpread
	local at = best.Position + Vector3.new((math.random() * 2 - 1) * spread, 0, (math.random() * 2 - 1) * spread)
	local pos = (CoverMap.Snap(at, spread + 2) or best.Position) + Vector3.new(0, 3.5, 0)
	local look = flat(goal - pos)
	return if look.Magnitude > 1 then CFrame.lookAt(pos, pos + look) else CFrame.new(pos)
end

local function placeCharacter(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or player.Character ~= character then
		return
	end
	task.wait()
	local side = sideOf(player)
	local cf = nil
	if match.on and not match.joined[player] then
		-- First spawn this match: a bot's place where it stands.
		cf = FrontBattle.Claim(side)
		FrontBattle.SetPlayers(side, countSides()[side])
	end
	match.joined[player] = true
	cf = cf or spawnCF(side)
	if character.Parent then
		character:PivotTo(cf)
		PlayerHealth.Protect(player, M.Protect)
	end
	player:SetAttribute("FrontSpawnAt", nil)
	player:SetAttribute("Streak", 0)
	player:SetAttribute("StreakReady", nil)
	if match.on then
		Remotes.Match:FireClient(player, "FrontSound", "SpawnIn")
	end
end

-- Kill credit: whoever last hurt model within Credit seconds, if they are on the other side.
local function creditOf(model, victimSide)
	local id = model:GetAttribute("LastHitBy")
	local at = model:GetAttribute("LastHitAt") or 0
	if not id or now() - at > M.Credit then
		return nil
	end
	local killer = Players:GetPlayerByUserId(id)
	if killer and killer:GetAttribute("InMatch") and sideOf(killer) ~= victimSide then
		return killer
	end
	return nil
end

-- Hooks: the killstreaks (Modules.FrontStreaks) and the weekly Front counter (below).
local FrontServer = { OnKill = FrontStreaks.OnKill, OnDeath = FrontStreaks.OnDeath, OnSectorsTaken = FrontWeek.Add }
FrontWeek.Start()

local function addKill(killer, points)
	stat(killer, "Kills").Value += 1
	Points.Add(killer, points)
	killer:SetAttribute("FrontKills", (killer:GetAttribute("FrontKills") or 0) + 1)
	if isAlive(killer) then
		killer:SetAttribute("Streak", (killer:GetAttribute("Streak") or 0) + 1)
	end
	if FrontServer.OnKill then
		task.spawn(FrontServer.OnKill, killer)
	end
end

local function onDied(player, character)
	stat(player, "Deaths").Value += 1
	player:SetAttribute("Streak", 0)
	player:SetAttribute("StreakReady", nil)
	if FrontServer.OnDeath then
		task.spawn(FrontServer.OnDeath, player)
	end
	local side = sideOf(player)
	local killer = creditOf(character, side)
	if killer then
		local head = character:GetAttribute("LastHitHead")
		addKill(killer, PTS.Kill + (if head then PTS.Headshot else 0))
		Remotes.Match:FireClient(player, "Notice", "KILLED BY " .. string.upper(killer.DisplayName))
	end
	if match.on and side == workspace:GetAttribute("FrontAttack") then
		match.tickets = math.max(0, match.tickets - 1)
		publish()
	end
	player:SetAttribute("FrontSpawnAt", Front.NextWave(now()))
end

FrontBattle.OnBotDied = function(soldier, side)
	local killer = creditOf(soldier.Model, side)
	if killer then
		addKill(killer, PTS.BotKill)
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Once(function()
				if player:GetAttribute("InMatch") then
					onDied(player, character)
				end
			end)
		end
		if player:GetAttribute("InMatch") then
			if not player:GetAttribute("Side") then
				setSide(player, emptierSide(player))
			end
			placeCharacter(player, character)
		end
	end)
	-- MenuServer sets InMatch just before it loads the character, so the side (and the uniform it picks) is
	-- chosen here first.
	player:GetAttributeChangedSignal("InMatch"):Connect(function()
		if player:GetAttribute("InMatch") then
			if not player:GetAttribute("Side") then
				setSide(player, emptierSide(player))
			end
			-- MenuServer is loading them now; the respawn loops leave them be until placeCharacter clears this.
			player:SetAttribute("FrontSpawnAt", now() + 20)
		end
	end)
	stat(player, "Kills")
	stat(player, "Deaths")
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end

Players.PlayerRemoving:Connect(function(player)
	match.joined[player] = nil
	match.ring[player] = nil
	match.out[player] = nil
	if match.on and player:GetAttribute("InMatch") then
		local root = rootOf(player)
		FrontBattle.Release(sideOf(player), if root and isAlive(player) then root.CFrame else nil)
	end
end)

-- The tick -----------------------------------------------------------------------------------------

local function respawnTick()
	local t = now()
	for _, p in inMatch() do
		if not isAlive(p) then
			local at = p:GetAttribute("FrontSpawnAt")
			if not at then
				p:SetAttribute("FrontSpawnAt", Front.NextWave(t))
			elseif t >= at then
				p:SetAttribute("FrontSpawnAt", t + 30) -- held until the load lands (placeCharacter clears it)
				task.spawn(Uniform.Load, p)
			end
		end
	end
end

-- Standing in the other side's spawn ring for SpawnRingTime starts to hurt, SpawnRingDamage a second.
local function ringTick(dt)
	local s = match.sector
	if not s then
		return
	end
	local r2 = M.SpawnRing * M.SpawnRing
	for _, p in inMatch() do
		local root = isAlive(p) and rootOf(p)
		local inside = false
		if root then
			for _, spot in s.Spawns[Front.Other(sideOf(p))] do
				local d = flat(spot.Position - root.Position)
				if d:Dot(d) <= r2 then
					inside = true
					break
				end
			end
		end
		if inside then
			local was = match.ring[p] or 0
			match.ring[p] = was + dt
			if match.ring[p] >= M.SpawnRingTime and math.floor(match.ring[p]) ~= math.floor(was) then
				PlayerHealth.Damage(p, M.SpawnRingDamage, root.Position + Vector3.new(0, 10, 0), "Blast")
				if math.floor(was) == M.SpawnRingTime - 1 then
					Remotes.Match:FireClient(p, "Notice", "GET OUT OF THEIR SPAWN")
				end
			end
		else
			match.ring[p] = nil
		end
	end
end

-- Outside the sector's play box: a warning (player attribute FrontOutAt = when it starts to hurt, the HUD counts down),
-- then Bounds.Damage a second until they are back inside.
local BOUNDS = Front.Bounds
local function boundsTick()
	local s = match.sector
	if not s then
		return
	end
	local t = now()
	for _, p in inMatch() do
		local root = isAlive(p) and rootOf(p)
		if root and not Front.InBox(s.Box, root.Position) then
			local hurtAt = p:GetAttribute("FrontOutAt")
			if not hurtAt then
				p:SetAttribute("FrontOutAt", t + BOUNDS.Grace)
			elseif t >= hurtAt and t - (match.out[p] or 0) >= 1 then
				match.out[p] = t
				PlayerHealth.Damage(p, BOUNDS.Damage, root.Position + Vector3.new(0, 10, 0), "Blast")
			end
		elseif p:GetAttribute("FrontOutAt") then
			p:SetAttribute("FrontOutAt", nil)
			match.out[p] = nil
		end
	end
end

-- Who stands on the flag: { Ally = players, Enemy = players } and the bot counts.
local function onFlag()
	local s = match.sector
	local players = { Ally = {}, Enemy = {} }
	for _, p in inMatch() do
		local root = isAlive(p) and rootOf(p)
		if root then
			local d = root.Position - s.Flag
			if d.X * d.X + d.Z * d.Z <= CAP.Radius * CAP.Radius and math.abs(d.Y) <= CAP.Height then
				table.insert(players[sideOf(p)], p)
			end
		end
	end
	return players, FrontBattle.CountIn(s.Flag, CAP.Radius, CAP.Height)
end

local function sayOnce(key, arg)
	if not match.said[key] then
		match.said[key] = true
		radioSide(key, arg)
	end
end

local function botsOnly()
	return RunService:IsStudio() and workspace:GetAttribute("StudioMode") == "Front"
end

-- Runs one sector. Returns "Taken", "Held" (tickets or clock out) or "Empty" (everyone left).
local function playSector(s)
	local attack = s.Attack
	local defend = Front.Other(attack)
	match.sector = s
	match.progress = 0
	match.said = {}
	workspace:SetAttribute("FrontSector", s.Index)
	workspace:SetAttribute("FrontStep", match.step)
	workspace:SetAttribute("WarMission", s.Name)
	workspace:SetAttribute("WarObjective", s.Name)
	workspace:SetAttribute("Objective", s.Flag + Vector3.new(0, 6, 0))
	workspace:SetAttribute("FrontContest", nil)
	workspace:SetAttribute("FrontBoxMin", Vector3.new(s.Box[1], 0, s.Box[3]))
	workspace:SetAttribute("FrontBoxMax", Vector3.new(s.Box[2], 0, s.Box[4]))
	FrontBattle.SetSector(s)
	if not (flag and (flag.Base - s.Flag).Magnitude < 40) then
		buildFlag(s)
	end
	publish()
	radioSide("Start", s.Name)
	local pointClock = 0
	local last = os.clock()
	while true do
		task.wait(0.25)
		local t0 = os.clock()
		local dt = t0 - last
		last = t0
		if #inMatch() == 0 and not botsOnly() then
			return "Empty"
		end
		local counts = countSides()
		FrontBattle.SetPlayers("Ally", counts.Ally)
		FrontBattle.SetPlayers("Enemy", counts.Enemy)
		respawnTick()
		ringTick(dt)
		boundsTick()
		local players, bots = onFlag()
		local rate = Front.CaptureRate(#players[attack], bots[attack], #players[defend], bots[defend])
		local before = match.progress
		match.progress = math.clamp(match.progress + rate * dt, 0, 1)
		local contest = nil
		if rate > 0 then
			contest = "Attack"
		elseif rate < 0 and match.progress > 0 then
			contest = "Defend"
		elseif rate == 0 and (#players[attack] + bots[attack]) > 0 and (#players[defend] + bots[defend]) > 0 then
			contest = "Contested"
		end
		if workspace:GetAttribute("FrontContest") ~= contest then
			workspace:SetAttribute("FrontContest", contest)
			paintFlag()
			if contest == "Attack" and before < 0.05 then
				sound("Lost", defend) -- the flag starts to go
			end
		end
		if contest == "Defend" and match.progress > 0.3 then
			sayOnce("Losing")
		end
		-- Points for standing on the flag while it moves your way, once a second.
		pointClock += dt
		if pointClock >= 1 then
			pointClock -= 1
			if contest == "Attack" then
				for _, p in players[attack] do
					Points.Add(p, PTS.Capture)
				end
				sound("CaptureTick", attack)
			elseif contest == "Defend" then
				for _, p in players[defend] do
					Points.Add(p, PTS.Capture)
				end
			end
		end
		if math.abs(match.progress - before) > 0.004 or match.progress == 1 then
			publish()
		end
		if match.progress >= 1 then
			for _, p in players[attack] do
				Points.Add(p, PTS.Taken)
			end
			return "Taken"
		end
		if match.tickets <= 10 then
			sayOnce("LowTickets")
		end
		if match.tickets <= 0 or now() >= match.endsAt then
			return "Held"
		end
	end
end

local function clearMatch()
	match.on = false
	match.sector = nil
	FrontBattle.Stop()
	FrontStreaks.Clear()
	clearFlag()
	table.clear(match.ring)
	table.clear(match.out)
	for _, p in Players:GetPlayers() do
		p:SetAttribute("FrontOutAt", nil)
	end
	for _, name in { "Objective", "WarObjective", "WarMission", "FrontProgress", "FrontContest", "FrontSector", "FrontStep", "FrontTickets", "FrontEndsAt", "FrontBoxMin", "FrontBoxMax" } do
		workspace:SetAttribute(name, nil)
	end
end

-- Pays every player in the match: sectors their side took or held, the result, and kills.
local function pay(winner, taken)
	local attack = workspace:GetAttribute("FrontAttack")
	for _, p in inMatch() do
		local side = sideOf(p)
		local won = side == winner
		local sectors = if side == attack then taken else (if won then 1 else 0)
		local kills = p:GetAttribute("FrontKills") or 0
		local amount = sectors * PAY.Sector + (if won then PAY.Win else PAY.Loss) + math.floor(kills / PAY.Kills) * PAY.PerKills
		if won then
			Points.Add(p, PTS.Held)
		end
		local ok, banked = pcall(Profile.Earn, p, amount)
		if ok then
			Remotes.Match:FireClient(p, "Banked", banked)
		end
		pcall(Profile.Count, p, "FrontMatches")
		if won then
			pcall(Profile.Count, p, "FrontWins")
		end
	end
end

-- Sides for a new match: on a fresh server they are dealt out in turn; after that everyone swaps. Then the bigger
-- side gives players to the smaller until they are within one.
local function dealSides(first)
	local list = inMatch()
	for i, p in list do
		if first or not p:GetAttribute("Side") then
			setSide(p, if i % 2 == 1 then "Ally" else "Enemy")
		else
			setSide(p, Front.Other(sideOf(p)))
		end
	end
	local n = countSides()
	while math.abs(n.Ally - n.Enemy) > 1 do
		local from = if n.Ally > n.Enemy then "Ally" else "Enemy"
		for i = #list, 1, -1 do
			if sideOf(list[i]) == from then
				setSide(list[i], Front.Other(from))
				break
			end
		end
		n = countSides()
	end
end

local function playMatch(first)
	dealSides(first)
	local starts = #Front.Sectors - Front.MatchSectors + 1
	local start = math.random(1, starts)
	local pick = RunService:IsStudio() and workspace:GetAttribute("FrontStartSector")
	if typeof(pick) == "number" then
		start = math.clamp(pick, 1, starts)
	end
	match.on = true
	match.step = 0
	match.taken = 0
	match.tickets = M.Tickets
	table.clear(match.joined)
	workspace:SetAttribute("FrontWinner", nil)
	workspace:SetAttribute("FrontNextAt", nil)
	for _, p in inMatch() do
		p:SetAttribute("FrontKills", 0)
		stat(p, "Kills").Value = 0
		stat(p, "Deaths").Value = 0
		p:SetAttribute("FrontSpawnAt", nil)
	end
	FrontBattle.Start()
	local counts = countSides()
	FrontBattle.SetPlayers("Ally", counts.Ally)
	FrontBattle.SetPlayers("Enemy", counts.Enemy)
	local opening = sectorData(start)
	match.sector = opening
	FrontBattle.SetSector(opening)
	buildFlag(opening)
	workspace:SetAttribute("WarMission", opening.Name)
	workspace:SetAttribute("WaveState", "Front")
	-- Everyone (re)spawns dressed for their side at the first sector.
	for _, p in inMatch() do
		match.joined[p] = true
		task.spawn(Uniform.Load, p)
	end
	notice("FRONTLINE: " .. opening.Name)
	sound("Countdown")
	match.endsAt = now() + M.StartDelay
	publish()
	task.wait(M.StartDelay)
	local winner = nil
	local leftover = 0
	for step = 1, Front.MatchSectors do
		match.step = step
		local s = sectorData(start + step - 1)
		match.endsAt = now() + M.SectorTime + math.min(leftover, M.Bonus)
		local result = playSector(s)
		if result == "Empty" then
			clearMatch()
			return
		end
		local attack = s.Attack
		if result == "Held" then
			winner = Front.Other(attack)
			break
		end
		match.taken += 1
		leftover = math.max(0, match.endsAt - now())
		match.tickets += M.Refund
		publish()
		notice(s.Name .. " TAKEN")
		sound("SectorWon", attack)
		sound("SectorLost", Front.Other(attack))
		if step == Front.MatchSectors then
			winner = attack
			break
		end
		radioSide("Taken", s.Name)
		-- The breather: the next flag shows, the bots move up, the dead come back.
		local nextS = sectorData(start + step)
		match.sector = nextS
		workspace:SetAttribute("WarMission", nextS.Name)
		workspace:SetAttribute("Objective", nextS.Flag + Vector3.new(0, 6, 0))
		FrontBattle.SetSector(nextS)
		match.progress = 0
		buildFlag(nextS)
		local resume = match.endsAt
		match.endsAt = now() + M.Breather
		publish()
		local stop = os.clock() + M.Breather
		while os.clock() < stop do
			task.wait(0.25)
			respawnTick()
		end
		match.endsAt = resume
	end
	if FrontServer.OnSectorsTaken then
		task.spawn(FrontServer.OnSectorsTaken, match.taken)
	end
	-- The end: who won, the pay, then the intermission.
	local attack = workspace:GetAttribute("FrontAttack")
	for _, p in inMatch() do
		local won = sideOf(p) == winner
		local line = Front.Lines[if won then "Win" else "Loss"]
		Remotes.Match:FireClient(p, "Radio", if sideOf(p) == attack then line.Attack else line.Defend, "FrontEnd")
		Remotes.Match:FireClient(p, "FrontSound", if won then "MatchWin" else "MatchLose")
	end
	pay(winner, match.taken)
	print(("FrontServer: match over, %s won, %d sectors taken"):format(tostring(winner), match.taken))
	clearMatch()
	workspace:SetAttribute("FrontWinner", winner)
	workspace:SetAttribute("WaveState", "FrontEnd")
end

FrontStreaks.Install({
	Running = function()
		return match.on and match.sector ~= nil
	end,
	Flag = function()
		return match.sector and match.sector.Flag
	end,
	Spawn = spawnCF,
	Radio = function(side, text)
		for _, p in inMatch() do
			if sideOf(p) == side then
				Remotes.Match:FireClient(p, "Radio", text, "FrontStreak")
			end
		end
	end,
	Notice = function(player, text)
		Remotes.Match:FireClient(player, "Notice", text)
	end,
})

-- Cover round every sector's flag and spawns, once at server start.
local surveyed = false
task.spawn(function()
	local points = {}
	for i = 1, #Front.Sectors do
		local s = sectorData(i)
		table.insert(points, s.Flag)
		for _, side in { "Ally", "Enemy" } do
			if #s.Spawns[side] > 0 then
				table.insert(points, centre(s.Spawns[side]))
			end
		end
	end
	for _, p in points do
		CoverMap.Survey(p, GameConfig.War.Battle.Survey)
	end
	print(("FrontServer: %d cover spots round %d places"):format(CoverMap.Count(), #points))
	surveyed = true
end)

-- Between matches the dead still come back.
task.spawn(function()
	while true do
		task.wait(0.5)
		if not match.on then
			for _, p in inMatch() do
				if not isAlive(p) and not p:GetAttribute("FrontSpawnAt") then
					p:SetAttribute("FrontSpawnAt", now() + 30)
					task.spawn(Uniform.Load, p)
				end
			end
		end
	end
end)

local firstMatch = true
while true do
	while not surveyed or (#inMatch() == 0 and not botsOnly()) do
		task.wait(0.5)
	end
	if firstMatch then
		task.wait(M.StartDelay) -- a party arriving together starts together
	end
	local ok, err = pcall(playMatch, firstMatch)
	if not ok then
		warn("FrontServer: the match failed (" .. tostring(err) .. ")")
		clearMatch()
		workspace:SetAttribute("WaveState", "FrontEnd")
	end
	firstMatch = false
	local nextAt = now() + M.Intermission
	workspace:SetAttribute("FrontNextAt", nextAt)
	while now() < nextAt do
		task.wait(0.5)
	end
	workspace:SetAttribute("FrontNextAt", nil)
end
