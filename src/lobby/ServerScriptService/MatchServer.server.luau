-- The Defend match: Call of Duty Zombies' Nacht der Untoten loop in the house
-- (Workspace.Map.DefendHouse with DefendHouse = true). Numbers: GameConfig.Match.
--   Players spawn upstairs at the house's PlayerStart in police SWAT gear (Uniform) with the
--   pistol and 500 points, and make their way down: a few zombies are already standing in the
--   rooms below and wake when someone comes near or shoots. Every run puts those zombies
--   and the guns lying in the house (house.Shop, Kind Gun) on new random spots on the house
--   floors, so nobody can learn the house by heart.
--   Each wave sends zombies from Map.ZombieSpawns.House; they tear in through the boarded
--   ground windows (WindowEntry) and hunt (MobAI). A window frame with a Zone attribute (the
--   name of a debris model) is only used once that debris is cleared, so zombies come in
--   where the players can reach them. Hold E at a torn window to nail boards
--   back on for points. Points also come from hits (Points) and from the glowing shards a
--   kill spills (GlowDrops: walk over them to collect), and buy the debris
--   piles (tag Debris, Cost), guns and supplies on the stands (InteractServer, Cost) and the
--   mystery crate (Map.DefendHouse.Shop.MysteryCrate).
--   Once wave BreakoutFrom (GameConfig.Breakout) is cleared, players can hold E on the front
--   or back door (tag WaveDoor) to break out: the doors fly open, the Beacon wakes
--   (BeaconServer), and everyone gets a short look at it (Remotes.Match "Breakout",
--   StarterPlayerScripts.RescueClient's reveal; players are held still and can't be hurt for
--   Breakout.RevealTime). Then zombies pour in from Map.ZombieSpawns.Town without end and a
--   helicopter is on its way to the landing zone (Map.Extraction.Zone, marked by a red flare)
--   in EvacTime seconds. Anyone alive in the zone when it lands gets everyone out (if nobody
--   is there it goes round again for RetryTime): the helicopter cutscene plays, the Beacon
--   charging after it (GameConfig.Rescue, StarterPlayerScripts.RescueClient), then
--   players who have never picked a uniform pick the one they'll wear from now on (a one-time
--   screen: GameConfig.Attire, Remotes.Attire, saved by Profile), and everyone goes back to
--   the menu.
--   More players make it harder: the PerPlayer numbers in GameConfig.Match and .Breakout.
--   If nobody breaks out, at OpenAtWave the doors burst open anyway and zombies also come
--   from the town.
--   Dead players come back at the next intermission; when nobody is left alive the run ends
--   on the wave reached, then everything resets and everyone respawns.
-- Nights (GameConfig.Nights.Enabled, every mode but Endless) replace the waves and the
-- breakout door: players start downstairs (house.NightStart) with the sleepers upstairs, then
-- timed nights (the Director sends zombies at a share of what the team can kill) alternate with
-- lulls (WaveState Intermission: doors open, a few town zombies, the Beacon out from the first
-- lull on, Remotes.Match "Return" ReturnWarn seconds before the night). A player shut out at
-- night holds E on a door to get in. The last night calls the helicopter Breakout.EvacTime
-- before its end and becomes the breakout. Extra attributes: Nights, NightEndsAt, LastNight,
-- BeaconHome (where the Beacon heads on the last night).
-- State for the HUD (StarterPlayerScripts.MatchHud) lives on workspace attributes:
--   Wave, WaveState (Waiting / Intermission / Wave / Breakout / Rescue / Attire / GameOver),
--   ZombiesLeft, NextWaveAt, HouseOpen, BreakoutReady, Breakout, RevealUntil, EvacAt.
--   Remotes.Match sends
--   one-off cues: "Broke" (can't afford), "Wave", "Open", "Ready", "Breakout", "Evac",
--   "EvacMissed", "Rescue" (with the UserIds aboard), "Attire", "GameOver" (and
--   "BeaconDown", "LensOut", "Taken" from BeaconServer).
-- Strays (Map.StraySpawns): each lull puts NIGHTS.Strays asleep on the streets along the way
-- to the part; they wake like the sleepers in the house. A player's first ever match (Profile
-- Matches) gets the FirstMatch attribute, and PartsServer lays that match's first part in the
-- Shop. Outbreak (mode Outbreak) is its own run: see the Outbreak sections below. Endless (mode
-- Endless, HORROR-SHOOTER-ENDLESS.md) is the wave loop with three relics to pick from after every
-- round (ServerStorage.Modules.Relics), a twist on some rounds, and new debris costs and door round
-- every run (GameConfig.Endless).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local MobReactions = require(ServerStorage.Modules.MobReactions)
local MobAI = require(ServerStorage.Modules.MobAI)
local Barricades = require(ServerStorage.Modules.Barricades)
local WindowEntry = require(ServerStorage.Modules.WindowEntry)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Points = require(ServerStorage.Modules.Points)
local GlowDrops = require(ServerStorage.Modules.GlowDrops)
local EvacPath = require(ReplicatedStorage.Shared.EvacPath)
local RunService = game:GetService("RunService")
local Uniform = require(ServerStorage.Modules.Uniform)
local Profile = require(ServerStorage.Modules.Profile)
local Inventory = require(ServerStorage.Modules.Inventory)
local Relics = require(ServerStorage.Modules.Relics)
local Soldier = require(ServerStorage.Modules.Soldier)
local Classes = require(ReplicatedStorage.Shared.Classes)
local ModeSetup = require(ServerStorage.Modules.ModeSetup)
-- XP and the after-action report (the menu session's DATA module); nil in a place without it.
local Progression
do
	local m = ServerStorage.Modules:FindFirstChild("Progression")
	if m then
		local ok, P = pcall(require, m)
		Progression = if ok and type(P) == "table" then P else nil
	end
end

-- Runs start from the menu (MenuServer): ServerStorage.Events.StartMatch(mode, variant, players, partyId), on a
-- match server once the party is in and again on every REDEPLOY. Connected first thing so no start is missed
-- while the rest of this script sets up; the main loop at the bottom takes it.
local startQueued = nil
ServerStorage:WaitForChild("Events"):WaitForChild("StartMatch").Event:Connect(function(modeKey, _variant, players)
	startQueued = { Mode = modeKey, Players = players }
end)
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.Match
local ENDLESS = GameConfig.Endless
local BREAK = GameConfig.Breakout
local RESCUE = GameConfig.Rescue
local NIGHTS = GameConfig.Nights
local DIRECTOR = GameConfig.Director
local template = ServerStorage:WaitForChild("TestZombie")
local mobConfig = GameConfig.Mobs[template:GetAttribute("MobType")]

local map = workspace:WaitForChild("Map")
local house
for _, child in map:GetChildren() do
	if child:GetAttribute("DefendHouse") then
		house = child
	end
end
assert(house, "MatchServer: no model in Workspace.Map has DefendHouse = true")
local playerStart = house:WaitForChild("PlayerStart")
local nightStart = house:FindFirstChild("NightStart") or playerStart
local spawnFolder = map:WaitForChild("ZombieSpawns")

local zombies = Instance.new("Folder")
zombies.Name = "Zombies"
zombies.Parent = workspace

-- War (its section is below, before "Calling the bird"): set there, read by the shared code.
local warOn = false
local war, warSpawn, playWar, resetWar
local defendSpawn, playDefend, resetDefend -- Defend (ServerStorage.Modules.DefendMode)

Points.Start()

-- The house's box: the foundation footprint, two storeys up.
local foundation = house:FindFirstChild("Foundation")
local houseCf, houseSize
if foundation then
	houseSize = Vector3.new(foundation.Size.X, 40, foundation.Size.Z)
	houseCf = foundation.CFrame + Vector3.new(0, houseSize.Y / 2 - foundation.Size.Y / 2, 0)
else
	houseCf, houseSize = house:GetBoundingBox()
end
WindowEntry.SetHouse(houseCf, houseSize)

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function between(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.CollisionGroup = "Characters"

local function groundAt(pos, fromY)
	groundParams.FilterDescendantsInstances = { zombies, spawnFolder }
	local start = Vector3.new(pos.X, fromY or pos.Y, pos.Z)
	local hit = workspace:Raycast(start, Vector3.new(0, -30, 0), groundParams)
	return if hit then hit.Position else Vector3.new(pos.X, 0, pos.Z)
end

-- Windows ----------------------------------------------------------------------------------

local windows = {}
for _, boards in house:GetDescendants() do
	if boards:IsA("Model") and CollectionService:HasTag(boards, "Breakable") and boards.Parent:IsA("Model") then
		local frame = boards.Parent
		local cf, size = frame:GetBoundingBox()
		local axis = flat(if size.X < size.Z then cf.RightVector else cf.LookVector).Unit
		if (cf.Position - houseCf.Position):Dot(axis) < 0 then
			axis = -axis
		end
		local sill = frame:FindFirstChild("Sill")
		local sillTop = if sill then sill.Position.Y + sill.Size.Y / 2 else cf.Position.Y - size.Y / 2
		local window = {
			Name = frame.Name,
			Zone = frame:GetAttribute("Zone") and house:FindFirstChild(frame:GetAttribute("Zone")),
			Boards = boards,
			Center = cf.Position,
			SillTop = sillTop,
			Outside = groundAt(cf.Position + axis * 3.4, sillTop + 1),
			Inside = groundAt(cf.Position - axis * 3.4, sillTop + 1),
			Load = 0,
			Usable = true,
		}
		table.insert(windows, window)
	end
end

-- Spawns -----------------------------------------------------------------------------------

local function spots(folderName)
	local folder = spawnFolder:FindFirstChild(folderName)
	local list = {}
	if folder then
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(list, p)
			end
		end
	end
	return list
end
local houseSpots, townSpots = spots("House"), spots("Town")
-- Strays stand on these (Map.StraySpawns, tag StraySpawn): in lulls and in Outbreak.
local straySpots = {}
for _, p in CollectionService:GetTagged("StraySpawn") do
	if p:IsA("BasePart") and p:IsDescendantOf(map) then
		table.insert(straySpots, p)
	end
end

-- Random places to stand on the house floors (G_Floor_* downstairs, U_Slab_* upstairs): a
-- clear man-sized space above the floor, away from the others and from avoid (a list of
-- points). Returns up to count positions on the floor surface.
local groundFloors, upperFloors = {}, {}
for _, part in house:GetChildren() do
	if part:IsA("BasePart") then
		if part.Name:match("^G_Floor_") then
			table.insert(groundFloors, part)
		elseif part.Name:match("^U_Slab_") then
			table.insert(upperFloors, part)
		end
	end
end

local clearParams = OverlapParams.new()
clearParams.FilterType = Enum.RaycastFilterType.Exclude
clearParams.RespectCanCollide = true

local function floorSpots(floors, count, gap, avoid)
	local ignore = { zombies, spawnFolder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local drops = workspace:FindFirstChild("Drops")
	if drops then
		table.insert(ignore, drops)
	end
	clearParams.FilterDescendantsInstances = ignore
	local total = 0
	for _, f in floors do
		total += f.Size.X * f.Size.Z
	end
	local found = {}
	for _ = 1, 300 do
		if #found >= count or total <= 0 then
			break
		end
		-- A floor picked by its area, then a point on it away from the edges.
		local r, floor = math.random() * total, floors[1]
		for _, f in floors do
			r -= f.Size.X * f.Size.Z
			if r <= 0 then
				floor = f
				break
			end
		end
		local hx, hz = math.max(0, floor.Size.X / 2 - 2.5), math.max(0, floor.Size.Z / 2 - 2.5)
		local top = floor.CFrame:PointToWorldSpace(Vector3.new((math.random() * 2 - 1) * hx, floor.Size.Y / 2, (math.random() * 2 - 1) * hz))
		local ok = #workspace:GetPartBoundsInBox(CFrame.new(top + Vector3.new(0, 3.2, 0)), Vector3.new(3, 5.6, 3), clearParams) == 0
		for _, other in found do
			ok = ok and (other - top).Magnitude >= gap
		end
		for _, other in avoid or {} do
			ok = ok and (other - top).Magnitude >= gap
		end
		if ok then
			table.insert(found, top)
		end
	end
	return found
end

-- The guns lying in the house go to new spots, anywhere on either floor.
local function shuffleGuns()
	local guns = {}
	for _, model in house.Shop:GetDescendants() do
		if model:IsA("Model") and model:GetAttribute("Kind") == "Gun" and not model:GetAttribute("Owner")
			and CollectionService:HasTag(model, "Pickup")
		then
			table.insert(guns, model)
		end
	end
	local all = table.clone(groundFloors)
	for _, f in upperFloors do
		table.insert(all, f)
	end
	local places = floorSpots(all, #guns, 14, { playerStart.Position })
	for i, model in guns do
		local at = places[i]
		if at then
			model:PivotTo(CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi * 2, 0) * model:GetPivot().Rotation)
			local cf, size = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + Vector3.new(0, at.Y + size.Y / 2 + 0.02 - cf.Y, 0))
		end
	end
end

-- A taken gun comes back on a free spot of either floor, away from players and the other
-- guns (InteractServer invokes ServerStorage.FreeSpot with the gun; returns a Vector3 or nil).
local freeSpot = Instance.new("BindableFunction")
freeSpot.Name = "FreeSpot"
freeSpot.OnInvoke = function(exclude)
	local avoid = {}
	for _, p in Players:GetPlayers() do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			table.insert(avoid, r.Position)
		end
	end
	for _, model in house.Shop:GetDescendants() do
		if model:IsA("Model") and model ~= exclude and model:GetAttribute("Kind") == "Gun" and not model:GetAttribute("Taken") then
			table.insert(avoid, model:GetPivot().Position)
		end
	end
	local all = table.clone(groundFloors)
	for _, f in upperFloors do
		table.insert(all, f)
	end
	return floorSpots(all, 1, 10, avoid)[1]
end
freeSpot.Parent = ServerStorage

-- Windows a zombie can actually walk up to from outside (checked once, on the first run).
local checkedWindows = false
local function checkWindows()
	if checkedWindows or #houseSpots == 0 then
		return
	end
	checkedWindows = true
	local path = PathfindingService:CreatePath({ AgentRadius = 1.6, AgentHeight = 5.5, AgentCanJump = false })
	local usable = 0
	for _, window in windows do
		local from = houseSpots[math.random(#houseSpots)].Position
		local ok = pcall(path.ComputeAsync, path, from, window.Outside)
		window.Usable = ok and path.Status == Enum.PathStatus.Success
		if window.Usable then
			usable += 1
		else
			warn("MatchServer: no path to the outside of window", window.Name)
		end
	end
	if usable == 0 then
		for _, window in windows do
			window.Usable = true
		end
	end
end

-- The least busy of the three usable windows nearest pos.
local function pickWindow(pos)
	local list = {}
	for _, window in windows do
		if window.Usable and (not window.Zone or window.Zone:GetAttribute("Cleared")) then
			table.insert(list, window)
		end
	end
	table.sort(list, function(a, b)
		return (a.Outside - pos).Magnitude < (b.Outside - pos).Magnitude
	end)
	local best
	for i = 1, math.min(3, #list) do
		if not best or list[i].Load < best.Load then
			best = list[i]
		end
	end
	return best
end

-- Match state ------------------------------------------------------------------------------

local wave = 0
local running = false
local houseOpen = false
local breakout = false
local evacAt = nil
local aboard = {} -- [player] = os.clock() they grabbed the ladder
local leaveRel = EvacPath.DefaultLeave -- seconds after EvacAt it climbs away
local alive = {} -- model -> { Born, CheckPos, CheckAt }
local aliveCount = 0
local toSpawn = 0
local repairsThisWave = {}
local lull = false -- between two nights: town zombies only
local outbreakOn = false -- an Outbreak run (the Outbreak sections below)
local openAtWave = CFG.OpenAtWave -- the round the doors burst open (Endless draws it every run)
local twist = nil -- this round's Endless twist (GameConfig.Endless.Twists), if any

local function setState(state)
	workspace:SetAttribute("WaveState", state)
end

local function updateLeft()
	workspace:SetAttribute("ZombiesLeft", aliveCount + toSpawn)
end

local function inMatch()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InMatch") then
			table.insert(list, p)
		end
	end
	return list
end

local function isAlive(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Players past the first, for the PerPlayer numbers.
local function extra()
	return math.max(0, #inMatch() - 1)
end

local function anyoneAlive()
	for _, p in inMatch() do
		if isAlive(p) then
			return true
		end
	end
	return false
end

-- Zombies --------------------------------------------------------------------------------

-- The run's mode (GameConfig.Modes): the server's (ModeSetup, set by MenuServer).
local mode = GameConfig.Modes.Outbreak

-- Whether a run in these mode rules is played in nights (Endless keeps its waves).
local function nightsFor(rules)
	return NIGHTS.Enabled == true and not rules.NoBreakout
end
local nightsOn = nightsFor(mode)

local function waveCount(n)
	local players = math.max(1, #inMatch())
	return math.floor((CFG.Count.Base + CFG.Count.PerWave * n) * (1 + CFG.Count.PerPlayer * (players - 1)) * (mode.Count or 1)
		* (if twist then twist.Count or 1 else 1))
end

local function waveHealth(n)
	local perWave = if nightsOn then NIGHTS.HealthPerNight else CFG.Health.PerWave
	local health = CFG.Health.Base + perWave * (math.min(n, 10) - 1)
	if n > 10 then
		health *= CFG.Health.Late ^ (n - 10)
	end
	health *= (1 + CFG.PerPlayer.Health * extra()) * (mode.Health or 1) * (if twist then twist.Health or 1 else 1)
	return math.floor(health)
end

local function runnerChance(n)
	if twist and twist.Runners then
		return 1
	end
	local from = mode.RunnersFrom or CFG.RunnersFrom
	if n < from then
		return 0
	end
	return math.min(CFG.RunnerMax, CFG.RunnerStep * (n - from + 1) + CFG.PerPlayer.Runners * extra())
end

local function hunt(model)
	if model.Parent then
		MobAI.Hunt(model, mobConfig, { AggroRange = CFG.AggroRange })
	end
end

-- During the breakout: a town spawn out of sight range of every player but not too far off.
local function breakoutSpot()
	local good, fallback, fallbackDist = {}, nil, -1
	for _, spot in townSpots do
		local nearest = math.huge
		for _, p in inMatch() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and isAlive(p) then
				nearest = math.min(nearest, flat(root.Position - spot.Position).Magnitude)
			end
		end
		if nearest >= BREAK.Near and nearest <= BREAK.Far then
			table.insert(good, spot)
		elseif nearest >= BREAK.Near and (fallbackDist < 0 or nearest < fallbackDist) then
			fallback, fallbackDist = spot, nearest
		end
	end
	if #good > 0 then
		return good[math.random(#good)]
	end
	return fallback or townSpots[math.random(#townSpots)]
end

-- A fresh match zombie standing at spot (a part), facing the house: health and speed for the
-- current wave, counted alive, uncounted when it dies.
local function addZombie(spot, walker)
	local zombie = template:Clone()
	local humanoid = zombie:FindFirstChildOfClass("Humanoid")
	local rootHeight = if humanoid.RigType == Enum.HumanoidRigType.R15
		then humanoid.HipHeight + zombie.PrimaryPart.Size.Y / 2
		else 3
	local pos = spot.Position + Vector3.new(math.random() * 4 - 2, rootHeight, math.random() * 4 - 2)
	zombie:PivotTo(CFrame.lookAt(pos, Vector3.new(houseCf.X, pos.Y, houseCf.Z)))

	local health = waveHealth(math.max(wave, 1))
	humanoid.MaxHealth = health
	humanoid.Health = health
	local speed = if not walker and math.random() < runnerChance(wave) then CFG.RunSpeed else CFG.WalkSpeed
	humanoid.WalkSpeed = speed
	zombie:SetAttribute("BaseWalkSpeed", speed)
	if speed == CFG.RunSpeed then
		-- a runner: called out the first time the squad meets one, eyes burning brighter
		zombie:SetAttribute("Kind", "Runner")
		for _, eye in zombie:GetChildren() do
			local glow = eye.Name == "Eye" and eye:FindFirstChild("Glow")
			if glow then
				eye.Color = GameConfig.Runner.EyeColor
				glow.Color = GameConfig.Runner.EyeColor
				glow.Brightness *= GameConfig.Runner.EyeBrightness
				glow.Range *= GameConfig.Runner.EyeRange
			end
		end
	end
	zombie:SetAttribute("MatchMob", true)
	zombie.Parent = zombies
	zombie.PrimaryPart:SetNetworkOwner(nil)
	MobReactions.Spawned(zombie)

	local entry = { Born = os.clock(), CheckPos = pos, CheckAt = os.clock(), Window = nil }
	alive[zombie] = entry
	aliveCount += 1
	updateLeft()

	humanoid.Died:Once(function()
		if alive[zombie] then
			if entry.Window then
				entry.Window.Load -= 1
				entry.Window = nil
			end
			alive[zombie] = nil
			aliveCount -= 1
			updateLeft()
		end
	end)
	return zombie, entry
end

local function spawnZombie()
	local outside = breakout or lull or outbreakOn or warOn
	local useTown = outside or (houseOpen and #townSpots > 0 and math.random() < 0.5)
	local list = if useTown then townSpots else houseSpots
	if #list == 0 then
		list = townSpots
	end
	local spot = if outside and #townSpots > 0 then breakoutSpot() else list[math.random(#list)]
	local zombie, entry = addZombie(spot)
	toSpawn -= 1
	updateLeft()

	local window = not outside and (not houseOpen or (not useTown and math.random() < 0.5)) and pickWindow(entry.CheckPos)
	if window then
		window.Load += 1
		entry.Window = window
		WindowEntry.Enter(zombie, mobConfig, window, function(model)
			if entry.Window then
				entry.Window.Load -= 1
				entry.Window = nil
			end
			hunt(model)
		end)
	else
		hunt(zombie)
	end
end

-- Already inside when the run starts (Map.ZombieSpawns.Inside, InsideAtStart of them): they
-- stand still downstairs until a player comes near on their floor, shoots nearby, or hurts
-- one, so the first fight is a few of them in the house before any wave comes.
local function wake(zombie)
	local entry = alive[zombie]
	if entry and entry.Sleeping then
		entry.Sleeping = false
		entry.CheckPos, entry.CheckAt = zombie.PrimaryPart.Position, os.clock()
		hunt(zombie)
	end
end

local function spawnSleepers()
	local count = CFG.InsideAtStart + CFG.PerPlayer.InsideAtStart * extra()
	-- In nights players start downstairs, so the sleepers wait upstairs.
	for _, at in floorSpots(if nightsOn and #upperFloors > 0 then upperFloors else groundFloors, count, 9) do
		local zombie, entry = addZombie({ Position = at + Vector3.new(0, 0.4, 0) })
		entry.Sleeping = true
		zombie:PivotTo(CFrame.new(zombie.PrimaryPart.Position) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	end
end

-- Strays: slow walkers asleep on a street (Map.StraySpawns) until someone comes near, shoots
-- close by or hurts one, so the walk between buildings is never empty (the master plan: strays
-- cut idle time by a quarter). Lulls put a few along the way to the part; Outbreak keeps the
-- streets topped up.
local function addStray(spot)
	local zombie, entry = addZombie(spot, true)
	entry.Sleeping = true
	entry.Stray = true
	zombie:PivotTo(CFrame.new(zombie.PrimaryPart.Position) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	return zombie, entry
end

local function playerPositions()
	local list = {}
	for _, p in inMatch() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and isAlive(p) then
			table.insert(list, root.Position)
		end
	end
	return list
end

local function awakeCount()
	local count = 0
	for _, entry in alive do
		if not entry.Sleeping then
			count += 1
		end
	end
	return count
end

local function strayCount()
	local count = 0
	for _, entry in alive do
		if entry.Stray and entry.Sleeping then
			count += 1
		end
	end
	return count
end

-- Up to count stray spots at least clear studs from every player and 20 from every sleeping
-- stray; given a route (from, to), the ones nearest that line come first.
local function straySpotsFor(count, clear, from, to)
	local players = playerPositions()
	local taken = {}
	for zombie, entry in alive do
		if entry.Stray and entry.Sleeping and zombie.PrimaryPart then
			table.insert(taken, zombie.PrimaryPart.Position)
		end
	end
	local scored = {}
	for _, spot in straySpots do
		local ok = true
		for _, pos in players do
			if flat(pos - spot.Position).Magnitude < clear then
				ok = false
			end
		end
		for _, pos in taken do
			if flat(pos - spot.Position).Magnitude < 20 then
				ok = false
			end
		end
		if ok then
			local score = math.random() * 30
			if from and to then
				local ab = flat(to - from)
				local ap = flat(spot.Position - from)
				local u = if ab.Magnitude > 0 then math.clamp(ap:Dot(ab) / ab:Dot(ab), 0, 1) else 0
				score += (ap - ab * u).Magnitude
			end
			table.insert(scored, { spot, score })
		end
	end
	table.sort(scored, function(a, b)
		return a[2] < b[2]
	end)
	local picked = {}
	for i = 1, math.min(count, #scored) do
		table.insert(picked, scored[i][1])
	end
	return picked
end

-- Strays still asleep at dusk wander off.
local function clearSleepingStrays()
	for zombie, entry in alive do
		if entry.Stray and entry.Sleeping then
			alive[zombie] = nil
			aliveCount -= 1
			zombie:Destroy()
		end
	end
	updateLeft()
end

task.spawn(function()
	while true do
		task.wait(0.25)
		for zombie, entry in alive do
			if entry.Sleeping then
				local root = zombie.PrimaryPart
				local humanoid = zombie:FindFirstChildOfClass("Humanoid")
				local woken = not root or (humanoid and humanoid.Health < humanoid.MaxHealth)
				if root and not woken then
					for _, p in inMatch() do
						local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
						if hrp and isAlive(p) then
							local offset = hrp.Position - root.Position
							if math.abs(offset.Y) < 7 and flat(offset).Magnitude < CFG.InsideWakeRange then
								woken = true
							end
						end
					end
				end
				if woken then
					wake(zombie)
				end
			end
		end
	end
end)

ServerStorage.Events.Gunshot.Event:Connect(function(_, origin)
	for zombie, entry in alive do
		if entry.Sleeping and zombie.PrimaryPart and (zombie.PrimaryPart.Position - origin).Magnitude < 70 then
			wake(zombie)
		end
	end
end)

-- A zombie stuck somewhere (no headway for 25 s) or fallen off the map goes back in the queue.
local function unstick()
	local now = os.clock()
	for zombie, entry in alive do
		local root = zombie.PrimaryPart
		local lost = not root or root.Position.Y < -40
		if not lost and not zombie:GetAttribute("DevourTarget") and not entry.Sleeping then
			if (root.Position - entry.CheckPos).Magnitude > 3 then
				entry.CheckPos, entry.CheckAt = root.Position, now
			elseif now - entry.CheckAt > 25 then
				lost = true
			end
		end
		if lost then
			if entry.Window then
				entry.Window.Load -= 1
			end
			alive[zombie] = nil
			aliveCount -= 1
			toSpawn += 1
			zombie:Destroy()
			updateLeft()
		end
	end
end

local function clearZombies()
	for zombie in alive do
		zombie:Destroy()
	end
	table.clear(alive)
	zombies:ClearAllChildren()
	aliveCount, toSpawn = 0, 0
	for _, window in windows do
		window.Load = 0
		window.ClimbFreeAt = nil
	end
	updateLeft()
end

-- Points from shooting -------------------------------------------------------------------
-- Hits pay straight away; a kill spills glowing shards someone has to go and pick up.

ServerStorage.Events.EnemyHit.Event:Connect(function(model, _, dealt, isHead, killed, player)
	if not player or not model:GetAttribute("MatchMob") or not running then
		return
	end
	if killed then
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if root then
			GlowDrops.Spill(
				root.Position,
				if isHead then CFG.Points.HeadKill else CFG.Points.Kill,
				if isHead then CFG.Glow.HeadShards else CFG.Glow.Shards
			)
		end
	elseif dealt and dealt > 0 then
		Points.Add(player, CFG.Points.Hit * (if twist then twist.Points or 1 else 1))
	end
end)

-- Window repair ----------------------------------------------------------------------------

for _, window in windows do
	local holder = window.Boards.Parent:FindFirstChild("Sill") or window.Boards:FindFirstChildWhichIsA("BasePart", true)
	local attachment = Instance.new("Attachment")
	attachment.Name = "RepairPoint"
	attachment.Parent = holder
	attachment.WorldPosition = window.Inside + Vector3.new(0, 3, 0)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RepairPrompt"
	prompt.ActionText = "Repair"
	prompt.ObjectText = "Window"
	prompt.HoldDuration = CFG.Repair.HoldTime
	prompt.MaxActivationDistance = CFG.Repair.Range
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = false
	prompt.Parent = attachment
	window.Prompt = prompt
	-- One hold boards the whole window up again, a plank at a time in quick succession.
	prompt.Triggered:Connect(function(player)
		if window.Repairing or not isAlive(player) or PlayerHealth.IsDowned(player) then
			return
		end
		window.Repairing = true
		prompt.Enabled = false
		while isAlive(player) and not PlayerHealth.IsDowned(player) do
			local board = Barricades.RepairOne(window.Boards)
			if not board then
				break
			end
			SoundKit.Play("World/PlankDrop", { Position = board.Position })
			local done = repairsThisWave[player] or 0
			if running and done < CFG.Points.RepairCap then
				repairsThisWave[player] = done + 1
				Points.Add(player, math.floor(CFG.Points.Repair * Classes.Perk(player, "RepairPoints") + 0.5))
			end
			task.wait(0.12)
		end
		window.Repairing = false
		prompt.Enabled = Barricades.TornCount(window.Boards) > 0
	end)
end

task.spawn(function()
	while true do
		for _, window in windows do
			local torn = Barricades.TornCount(window.Boards)
			window.Prompt.Enabled = torn > 0 and not window.Repairing
			window.Prompt.HoldDuration = CFG.Repair.HoldTime + (CFG.Repair.PerBoard or 0) * torn
		end
		task.wait(0.25)
	end
end)

-- Debris -----------------------------------------------------------------------------------

local debrisList = {}
for _, model in CollectionService:GetTagged("Debris") do
	if model:IsDescendantOf(house) then
		table.insert(debrisList, model)
	end
end

local function setDebrisShown(model, shown)
	model:SetAttribute("Cleared", not shown)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("RestTransparency") == nil then
				d:SetAttribute("RestTransparency", d.Transparency)
				d:SetAttribute("RestCollide", d.CanCollide)
			end
			if shown then
				d.Transparency = d:GetAttribute("RestTransparency")
				d.CanCollide = d:GetAttribute("RestCollide")
				d.CanQuery = true
			else
				d.CanCollide = false
				d.CanQuery = false
				TweenService:Create(d, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = shown
		end
	end
end

-- The biggest visible piece (the plugs added to close side gaps and their invisible blockers
-- don't count, so the prompt sits on the pile you see).
local function largestPart(model)
	local best
	for _, d in model:GetDescendants() do
		local plug = d.Parent and d.Parent.Name:match("^Plug")
		if d:IsA("BasePart") and not plug and d.Transparency < 1 and (not best or d.Size.Magnitude > best.Size.Magnitude) then
			best = d
		end
	end
	return best
end

-- Debris is shot down, not bought (owner, 2 Nov): bullets on a pile (WorldDamage.OnShootDown)
-- take GameConfig.Match.DebrisHealth off it, and at none it comes down. Close up, a small line
-- on the pile says SHOOT IT DOWN (a BillboardGui that only shows within DebrisHint studs).
-- Cost stays 0 so the Guide's highlight always counts it as open to you.
local WorldDamage = require(ServerStorage.Modules.WorldDamage)
local debrisHealth = {} -- [model] = damage left
for _, model in debrisList do
	model:SetAttribute("Cost", 0)
	local old = model:FindFirstChild("BuyPrompt", true)
	if old then
		old:Destroy()
	end
	local anchor = largestPart(model)
	local hint = Instance.new("BillboardGui")
	hint.Name = "ShootHint"
	hint.Size = UDim2.fromOffset(220, 30)
	hint.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	hint.MaxDistance = CFG.DebrisHint
	hint.AlwaysOnTop = true
	hint.LightInfluence = 0
	hint.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "SHOOT IT DOWN"
	label.TextColor3 = Color3.fromRGB(255, 176, 60)
	label.TextSize = 18
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	local stroke = Instance.new("UIStroke")
	stroke.Transparency = 0.5
	stroke.Parent = label
	label.Parent = hint
	hint.Parent = anchor
	WorldDamage.OnShootDown(model, function(damage, hitPos)
		if model:GetAttribute("Cleared") then
			return
		end
		local left = (debrisHealth[model] or CFG.DebrisHealth) - damage
		debrisHealth[model] = left
		SoundKit.Play("World/PlankDrop", { Position = hitPos, Volume = 0.5, Speed = 1.3 })
		if left <= 0 then
			debrisHealth[model] = nil
			SoundKit.Play("World/WoodBreak", { Position = hitPos })
			SoundKit.Play("World/PlankDrop", { Position = hitPos })
			setDebrisShown(model, false)
			hint.Enabled = false
		end
	end)
	model:GetAttributeChangedSignal("Cleared"):Connect(function()
		if not model:GetAttribute("Cleared") then
			debrisHealth[model] = nil
			hint.Enabled = true
		end
	end)
end

-- Kept for the run setup's call; debris has no price any more.
local function setDebrisCosts()
end

-- Mystery crate (Call of Duty's mystery box) ---------------------------------------------

local shop = house:FindFirstChild("Shop")
local crate = shop and shop:FindFirstChild("MysteryCrate")
if crate then
	local top = crate:FindFirstChild("Top") or largestPart(crate)
	local glow = crate:FindFirstChild("Glow", true)
	local offers = Instance.new("Folder")
	offers.Name = "Offers"
	offers.Parent = crate
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Open " .. CFG.Crate.Cost
	prompt.ObjectText = "Mystery Crate"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = top

	local function roll()
		local total = 0
		for _, w in CFG.Crate.Guns do
			total += w
		end
		local r = math.random() * total
		for gun, w in CFG.Crate.Guns do
			r -= w
			if r <= 0 then
				return gun
			end
		end
		return next(CFG.Crate.Guns)
	end

	prompt.Triggered:Connect(function(player)
		if not prompt.Enabled or not isAlive(player) or PlayerHealth.IsDowned(player) then
			return
		end
		if not Points.Spend(player, CFG.Crate.Cost) then
			Remotes.Match:FireClient(player, "Broke")
			return
		end
		prompt.Enabled = false
		if glow then
			glow.Enabled = true
		end
		SoundKit.Play("Night/Stinger", { Position = top.Position })
		task.wait(CFG.Crate.RollTime)
		local marker = Instance.new("Part")
		marker.Name = "Offer"
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Transparency = 1
		marker.Size = Vector3.new(0.2, 0.2, 0.2)
		marker.Position = top.Position + Vector3.new(0, top.Size.Y / 2 + 1.5, 0)
		marker:SetAttribute("Gun", roll())
		marker:SetAttribute("Owner", player.UserId)
		marker:SetAttribute("Life", CFG.Crate.OfferTime)
		marker.Parent = offers
		CollectionService:AddTag(marker, "GunSpawn")
		local t = 0
		while t < CFG.Crate.OfferTime do
			t += task.wait(0.2)
			local left = false
			for _, child in offers:GetChildren() do
				if CollectionService:HasTag(child, "Pickup") then
					left = true
				end
			end
			if not left and t > 0.5 then
				break
			end
		end
		offers:ClearAllChildren()
		if glow then
			glow.Enabled = false
		end
		prompt.Enabled = true
	end)
end

-- The doors at OpenAtWave ------------------------------------------------------------------

local waveDoors = {}
for _, door in CollectionService:GetTagged("WaveDoor") do
	if door:IsDescendantOf(house) then
		local saved = {}
		for _, d in door:GetDescendants() do
			if d:IsA("BasePart") then
				saved[d] = { CFrame = d.CFrame, Transparency = d.Transparency, CanCollide = d.CanCollide }
			end
		end
		table.insert(waveDoors, { Model = door, Saved = saved })
	end
end

local function throwLoose(part, away)
	local loose = part:Clone()
	loose:ClearAllChildren()
	for _, tag in loose:GetTags() do
		loose:RemoveTag(tag)
	end
	loose.Anchored = false
	loose.CanQuery = false
	loose.CollisionGroup = "Debris"
	loose.Parent = workspace
	loose.AssemblyLinearVelocity = away * (16 + math.random() * 10) + Vector3.new(0, 10 + math.random() * 8, 0)
	loose.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 16
	loose:SetNetworkOwner(nil)
	task.delay(12, function()
		if loose.Parent then
			loose:Destroy()
		end
	end)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
end

local function openHouse(quiet)
	houseOpen = true
	workspace:SetAttribute("HouseOpen", true)
	for _, entry in waveDoors do
		local door = entry.Model
		local cf = door:GetBoundingBox()
		local outward = flat(cf.Position - houseCf.Position)
		outward = if outward.Magnitude > 0.1 then outward.Unit else Vector3.zAxis
		for _, d in door:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "Leaf" then
					-- Swings in on its left edge, hard, like it was kicked.
					local hinge = d.CFrame * CFrame.new(-d.Size.X / 2, 0, 0)
					local sign = if (hinge * CFrame.Angles(0, math.rad(95), 0) * CFrame.new(d.Size.X / 2, 0, 0)).Position:Dot(outward)
						< (hinge * CFrame.Angles(0, math.rad(-95), 0) * CFrame.new(d.Size.X / 2, 0, 0)).Position:Dot(outward)
						then 1
						else -1
					local goal = hinge * CFrame.Angles(0, math.rad(95 * sign), 0) * CFrame.new(d.Size.X / 2, 0, 0)
					TweenService:Create(d, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = goal }):Play()
				elseif d.Name:match("^Board") then
					throwLoose(d, -outward)
				end
			end
		end
		SoundKit.Play("World/WoodBreak", { Position = cf.Position })
		SoundKit.Play("World/DoorCreak", { Position = cf.Position })
	end
	if not quiet then
		Remotes.Match:FireAllClients("Open")
	end
end

local function closeHouse()
	houseOpen = false
	workspace:SetAttribute("HouseOpen", false)
	for _, entry in waveDoors do
		for part, saved in entry.Saved do
			part.CFrame = saved.CFrame
			part.Transparency = saved.Transparency
			part.CanCollide = saved.CanCollide
			part.CanQuery = true
		end
	end
end

-- Breaking out -----------------------------------------------------------------------------

local extraction = map:WaitForChild("Extraction")
local zonePart = extraction:FindFirstChild("Zone")
-- Where the helicopter comes down: the hilltop zone, or an Outbreak pad (workspace EvacZone for
-- the clients, BeaconServer and the HUD).
local evacZone = zonePart.Position

-- The landing zone's flare: red light and smoke on the road, lit through the breakout.
local flare = extraction:FindFirstChild("Flare")
if not flare then
	flare = Instance.new("Part")
	flare.Name = "Flare"
	flare.Size = Vector3.new(0.25, 0.9, 0.25)
	flare.Material = Enum.Material.Neon
	flare.Color = Color3.fromRGB(255, 60, 40)
	flare.Anchored = true
	flare.CanCollide = false
	flare.CanQuery = false
	flare.CanTouch = false
	local ground = groundAt(zonePart.Position, zonePart.Position.Y + 6)
	flare.CFrame = CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(80))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 50, 30)
	light.Range = 28
	light.Brightness = 0
	light.Shadows = true
	light.Parent = flare
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 40, 30))
	smoke.LightEmission = 0.4
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 9) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Rate = 14
	smoke.Speed = NumberRange.new(4, 7)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Acceleration = Vector3.new(1.5, 2, 0)
	smoke.EmissionDirection = Enum.NormalId.Left
	smoke.Enabled = false
	smoke.Parent = flare
	flare.Parent = extraction
end

local function setFlare(on)
	flare.Transparency = if on then 0 else 1
	flare.PointLight.Brightness = if on then 4 else 0
	flare.Smoke.Enabled = on
end
setFlare(false)

local doorPrompts = {}
local doorInside = {} -- [prompt] = where a player let in at night stands
local doorOutside = {} -- [prompt] = { Center (the doorway), Out (just outside it) }
for _, entry in waveDoors do
	local cf, size = entry.Model:GetBoundingBox()
	local frame = entry.Model:FindFirstChild("FrameHead")
	-- Ground-floor doors only (the upstairs one opens onto a drop).
	if frame and cf.Y - size.Y / 2 < houseCf.Y - houseSize.Y / 2 + 4 then
		local at = Instance.new("Attachment")
		at.Name = "BreakoutPoint"
		at.Parent = frame
		at.WorldPosition = cf.Position
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BreakoutPrompt"
		prompt.ActionText = "Break out"
		prompt.ObjectText = "Door"
		prompt.HoldDuration = BREAK.DoorHold
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = at
		table.insert(doorPrompts, prompt)
		local outward = flat(cf.Position - houseCf.Position)
		outward = if outward.Magnitude > 0.1 then outward.Unit else Vector3.zAxis
		doorInside[prompt] = groundAt(cf.Position - outward * 5, cf.Position.Y)
		doorOutside[prompt] = { Center = cf.Position, Out = cf.Position + outward * 2 }
	end
end

local function refreshDoorPrompts()
	-- Nights: the doors let a player shut outside back in while they're barred (the prompt
	-- sits on the outside, out of sight through the door from in the house).
	local on = if nightsOn then running and not houseOpen and not breakout
		else workspace:GetAttribute("BreakoutReady") == true and not breakout
	for _, prompt in doorPrompts do
		prompt.Enabled = on
		prompt.ActionText = if nightsOn then "Get in" else "Break out"
		prompt.HoldDuration = if nightsOn then NIGHTS.DoorHold else BREAK.DoorHold
		prompt.RequiresLineOfSight = nightsOn
		prompt.Parent.WorldPosition = if nightsOn then doorOutside[prompt].Out else doorOutside[prompt].Center
	end
end

local function insideHouse(pos)
	local rel = houseCf:PointToObjectSpace(pos)
	return math.abs(rel.X) <= houseSize.X / 2 and math.abs(rel.Z) <= houseSize.Z / 2
end

local function letIn(player, prompt)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not isAlive(player) or PlayerHealth.IsDowned(player) or insideHouse(root.Position) then
		return
	end
	local at = doorInside[prompt] + Vector3.new(0, 3.5, 0)
	player.Character:PivotTo(CFrame.lookAt(at, Vector3.new(houseCf.X, at.Y, houseCf.Z)))
	SoundKit.Play("World/DoorCreak", { Position = at })
end

local function freeze(player, on)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = on
	end
end

local function startBreakout(player)
	if breakout or not workspace:GetAttribute("BreakoutReady") or not isAlive(player) then
		return
	end
	breakout = true
	refreshDoorPrompts()
	if not houseOpen then
		openHouse(true)
	end
	-- Everyone gets a look at the Beacon first: held still, and nothing can hurt them.
	local revealUntil = workspace:GetServerTimeNow() + BREAK.RevealTime
	workspace:SetAttribute("RevealUntil", revealUntil)
	for _, p in inMatch() do
		PlayerHealth.Protect(p, BREAK.RevealTime + 1.5)
		freeze(p, true)
	end
	task.delay(BREAK.RevealTime, function()
		for _, p in inMatch() do
			freeze(p, false)
		end
	end)
	evacAt = revealUntil + BREAK.EvacTime
	leaveRel = EvacPath.DefaultLeave
	workspace:SetAttribute("EvacAt", evacAt)
	workspace:SetAttribute("EvacLeaveAt", evacAt + leaveRel)
	setFlare(true)
	workspace:SetAttribute("Breakout", true)
	setState("Breakout")
	Remotes.Match:FireAllClients("Breakout")
end
for _, prompt in doorPrompts do
	prompt.Triggered:Connect(function(player)
		if nightsOn then
			letIn(player, prompt)
		else
			startBreakout(player)
		end
	end)
end

-- The last night's way out: the helicopter is called with no door to break and no reveal (the
-- Beacon has been out since the first lull).
local function callEvac()
	if breakout then
		return
	end
	breakout = true
	refreshDoorPrompts()
	if not houseOpen then
		openHouse(true)
	end
	workspace:SetAttribute("RevealUntil", workspace:GetServerTimeNow())
	evacAt = workspace:GetServerTimeNow() + BREAK.EvacTime
	leaveRel = EvacPath.DefaultLeave
	workspace:SetAttribute("EvacAt", evacAt)
	workspace:SetAttribute("EvacLeaveAt", evacAt + leaveRel)
	workspace:SetAttribute("BeaconHome", nil)
	setFlare(true)
	workspace:SetAttribute("Breakout", true)
	setState("Breakout")
end

-- Studio testing: set workspace attribute DebugBreakout = true to break out straight away.
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("DebugBreakout"):Connect(function()
		if workspace:GetAttribute("DebugBreakout") then
			workspace:SetAttribute("DebugBreakout", nil)
			local first = inMatch()[1]
			if first and running then
				workspace:SetAttribute("BreakoutReady", true)
				startBreakout(first)
			end
		end
	end)
end

-- The pickup ---------------------------------------------------------------------------------
-- The helicopter flies Shared.EvacPath from EvacAt. While it hangs or crawls off with the ladder
-- down, a player near the ladder's foot can press GRAB (Remotes.Evac "Grab", EvacClient): the
-- server checks the reach against the same path and you hang on the bottom rung (character
-- attribute OnLadder). The first grab starts the helicopter climbing away EVAC.GrabLeave s later
-- (testers, 2 Nov: "you don't climb it, you just fly up"), and you climb yourself: holding
-- forward (Remotes.Evac "Climb", true/false from EvacClient) moves you up EVAC.ClimbTime s for
-- the whole ladder, while the Beacon can still see and take you. At the top you're in the door
-- (character attribute Aboard, Remotes.Match "Aboard"): nothing can hurt you and the Beacon
-- ignores you. Hanging on when it's gone still gets you out. Once everyone alive is on the
-- ladder it leaves at once (EvacLeaveAt). Whoever is still on the ground is left behind.

local EVAC = BREAK.Evac
local evacRemote = Remotes:FindFirstChild("Evac")
if not evacRemote then
	evacRemote = Instance.new("RemoteEvent")
	evacRemote.Name = "Evac"
	evacRemote.Parent = Remotes
end

local function evacTime()
	return if evacAt then workspace:GetServerTimeNow() - evacAt else -math.huge
end

local function evacPose(t)
	return EvacPath.Pose(evacZone, t, leaveRel)
end

local function setLeave(rel)
	leaveRel = rel
	workspace:SetAttribute("EvacLeaveAt", evacAt + rel)
end

local climb = {} -- [player] = 0..1 up the ladder
local climbing = {} -- [player] = true while they hold forward

evacRemote.OnServerEvent:Connect(function(player, action, value)
	if action == "Climb" then
		climbing[player] = aboard[player] ~= nil and value == true or nil
		return
	end
	if action ~= "Grab" or not (breakout or outbreakOn) or not evacAt or aboard[player] or not player:GetAttribute("InMatch") then
		return
	end
	local t = evacTime()
	local phase = EvacPath.Phase(t, leaveRel)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if (phase ~= "Hover" and phase ~= "Crawl") or not root or not isAlive(player)
		or character:GetAttribute("Downed") or character:GetAttribute("Devoured")
		or player:GetAttribute("BeaconCaughtAt")
	then
		return
	end
	local door, foot = EvacPath.Ladder(evacPose(t), t, leaveRel)
	-- A little slack over the client's reach for lag.
	if flat(root.Position - foot).Magnitude > EVAC.Grab + 3 or root.Position.Y < foot.Y - 7 or root.Position.Y > door.Y then
		return
	end
	local first = next(aboard) == nil
	aboard[player] = os.clock()
	climb[player] = 0
	character:SetAttribute("OnLadder", true)
	root.Anchored = true
	SoundKit.Play("Bandage/Rip", { Position = foot, Speed = 0.6 })
	evacRemote:FireClient(player, "OnLadder")
	-- The first hand on the ladder: it's going. Everyone standing is on: no reason to hang about.
	local waiting = false
	for _, p in inMatch() do
		if isAlive(p) and not aboard[p] then
			waiting = true
		end
	end
	local leave = if waiting then (if first then t + EVAC.GrabLeave else leaveRel) else t + 1.2
	if leave < leaveRel then
		setLeave(leave)
	end
end)
Players.PlayerRemoving:Connect(function(player)
	climb[player] = nil
	climbing[player] = nil
end)

-- Up the ladder as they climb, then riding in the door.
RunService.Heartbeat:Connect(function(dt)
	if next(aboard) == nil or not evacAt then
		return
	end
	local t = evacTime()
	local pose = evacPose(t)
	local door, foot = EvacPath.Ladder(pose, t, leaveRel)
	local seat = 0
	for player in aboard do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not isAlive(player) then
			-- Taken off the ladder (the Beacon): they fall with it.
			aboard[player] = nil
			climb[player], climbing[player] = nil, nil
			if root then
				root.Anchored = false
			end
		elseif root then
			local k = climb[player] or 1
			if k < 1 and climbing[player] then
				k = math.min(1, k + dt / EVAC.ClimbTime)
				climb[player] = k
				if k >= 1 then
					-- In the door: safe, and the ride camera (EvacClient).
					PlayerHealth.Protect(player, 600)
					character:SetAttribute("OnLadder", nil)
					character:SetAttribute("Aboard", true)
					player:SetAttribute("BeaconSeen", nil)
					Remotes.Match:FireAllClients("Aboard", player.UserId)
				end
			end
			local outward = -pose.RightVector
			if k < 1 then
				-- Rung by rung: a small lift on each step.
				local rung = (k * 14) % 1
				local at = (foot + Vector3.new(0, 3, 0)):Lerp(door + Vector3.new(0, 1.5, 0), k) + outward * 0.8
					+ Vector3.new(0, if climbing[player] then math.sin(rung * math.pi) * 0.25 else 0, 0)
				root.CFrame = CFrame.lookAt(at, at - outward)
			else
				seat += 1
				local at = pose:PointToWorldSpace(EVAC.Door + Vector3.new(1.4, 3.2, (seat - 1) * 2.2 - 1))
				root.CFrame = CFrame.lookAt(at, at + outward)
			end
		end
	end
end)

-- Endless town zombies until the helicopter has been and gone. Returns the players aboard.
local function runBreakout()
	toSpawn = 0
	updateLeft()
	local nextSpawn = os.clock() + BREAK.RevealTime + 2
	local nextUnstick = os.clock() + 5
	local cued = {}
	while true do
		task.wait(0.2)
		local t = evacTime()
		local phase = EvacPath.Phase(t, leaveRel)
		local standing = false
		for _, p in inMatch() do
			if isAlive(p) and not aboard[p] then
				standing = true
			end
		end
		if not standing and next(aboard) == nil then
			return {}
		end
		local now = os.clock()
		local more = extra()
		if aliveCount < BREAK.MaxAlive + BREAK.PerPlayer.MaxAlive * more and now >= nextSpawn and phase ~= "Leave" then
			toSpawn = 1
			spawnZombie()
			nextSpawn = now + between(if t > -15 then BREAK.EvacGap else BREAK.SpawnGap) * BREAK.PerPlayer.SpawnGap ^ more
		end
		if now >= nextUnstick then
			nextUnstick = now + 5
			unstick()
			toSpawn = 0
			updateLeft()
		end
		if t >= -EVAC.Inbound and not cued.Inbound then
			cued.Inbound = true
			Remotes.Match:FireAllClients("Evac")
		end
		if t >= 0 and not cued.Ladder then
			cued.Ladder = true
			Remotes.Match:FireAllClients("Ladder")
		end
		-- Gone over the rooftops: whoever made it, made it.
		if phase == "Leave" and t >= leaveRel + 2.5 or phase == "Gone" then
			local list = {}
			for p in aboard do
				if p.Parent then
					table.insert(list, p)
				end
			end
			return list
		end
	end
end

-- Outbreak: the map -----------------------------------------------------------------------------
-- The open town (GameConfig.Outbreak, HORROR-SHOOTER-MASTER-PLAN.md section 5), first playable,
-- one squad. Everyone drops on one of Map.Outbreak.Insertions (tag Insertion) with zombies
-- already on the wreck and an ammo crate (tag SupplyCrate: Take ammo, once a CrateRefill each).
-- Strays sleep on the streets. One radio post at a time (tag RadioPost, not Reserve) offers a
-- contract: Hold (stay by it while zombies come) or Hunt (a marked pack out in town). The pay
-- goes on everyone's carried Scrip (player Carried), banked into Profile Scrip at any radio
-- (player Banked counts it for this run) and lost on death. The Beacon wakes at BeaconAt; from
-- BirdFrom any landing pad (tag LandingPad) calls the helicopter to it (EvacPath, workspace
-- EvacZone): whoever grabs the ladder gets out with their carried Scrip banked plus EscapePay,
-- watches the escape (RescueClient) and goes back to the menu, and the rest play on and can call
-- it again after HeliCooldown. The dead come back on the insertion after RespawnTime. At
-- Length, once no helicopter is out, anyone left is taken.
-- Workspace attributes: OutbreakEndsAt, BirdAt, OfferPost (the post's Building), Contract (Hold
-- or Hunt), ContractLeft (seconds still to hold, or targets left), ContractHolding. Hunt targets
-- carry the ContractTarget attribute. Remotes.Match cues: Radio (text, key), ContractDone (pay),
-- Banked (amount), Lost, Notice (text).

local OUT = GameConfig.Outbreak
local AMBER = Color3.fromRGB(255, 176, 60)

local function tagged(tag)
	local list = {}
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsDescendantOf(map) then
			table.insert(list, inst)
		end
	end
	return list
end

local function newPrompt(parent, action, object, hold)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = parent
	return prompt
end

local insertions = {}
for _, model in tagged("Insertion") do
	local point = model:FindFirstChild("InsertPoint")
	if point then
		local entry = { Model = model, Point = point, Spawns = {}, Crate = model:FindFirstChild("SupplyCrate") }
		local folder = model:FindFirstChild("Spawns")
		for _, p in if folder then folder:GetChildren() else {} do
			if p:IsA("BasePart") then
				table.insert(entry.Spawns, p)
			end
		end
		local body = entry.Crate and (entry.Crate.PrimaryPart or entry.Crate:FindFirstChildWhichIsA("BasePart"))
		if body then
			entry.Prompt = newPrompt(body, "Take ammo", "Supplies", 0.4)
		end
		table.insert(insertions, entry)
	end
end

local posts = {}
for _, model in tagged("RadioPost") do
	if model:IsA("Model") and not model:GetAttribute("Reserve") then
		local use = model:FindFirstChild("Use", true)
		local point = use and use:FindFirstChild("PromptPoint") or use
		local glass = model:FindFirstChild("LampGlass", true)
		table.insert(posts, {
			Model = model,
			Building = model:GetAttribute("Building") or model.Name,
			At = if use then use.Position else model:GetPivot().Position,
			Lamp = model:FindFirstChild("Lamp", true),
			Glass = glass,
			GlassColor = glass and glass.Color,
			GlassMaterial = glass and glass.Material,
			Prompt = point and newPrompt(point, "Bank", "Radio", OUT.BankHold),
		})
	end
end

local pads = {}
for _, model in tagged("LandingPad") do
	local zone = model:FindFirstChild("Zone")
	if zone then
		local pad = { Model = model, Id = model:GetAttribute("PadId") or #pads + 1, Zone = zone, Flares = {}, Strobes = {} }
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and CollectionService:HasTag(d, "PadFlare") then
				table.insert(pad.Flares, { Part = d, Color = d.Color, Material = d.Material, Light = d:FindFirstChildWhichIsA("PointLight") })
			elseif d:IsA("PointLight") and d.Name == "StrobeLight" then
				table.insert(pad.Strobes, d)
			end
		end
		-- The call prompt sits on the strobe tripod; the hilltop has none, so on its middle.
		local box = model:FindFirstChild("StrobeBox", true)
		local at = Instance.new("Attachment")
		at.Name = "CallPoint"
		at.Parent = box or zone
		at.WorldPosition = (if box then box.Position else zone.Position) + Vector3.new(0, 1.5, 0)
		pad.Prompt = newPrompt(at, "Call helicopter", "Landing pad", OUT.PadHold)
		table.insert(pads, pad)
	end
end

local ob = {
	drop = nil, -- the run's insertion
	endsAt = 0,
	birdAt = math.huge,
	offered = nil, -- the post offering a contract
	lastPost = nil,
	nextOffer = math.huge,
	contract = nil, -- { Kind, Post, Deadline, Left, Targets, Spawned, NextSpawn }
	kinds = 0,
	heliPad = nil,
	heliDone = false,
	heliClearAt = nil,
	heliReadyAt = 0,
	crateUsed = {}, -- [insertion] = { [player] = os.clock() it can give them ammo again }
	respawnAt = {}, -- [player] = os.clock()
	beacon = false,
	birdsCalled = false,
	lastCalled = false,
}

local function radio(key, where)
	local text = OUT.Lines[key]
	if text then
		Remotes.Match:FireAllClients("Radio", (text:gsub("{where}", string.lower(where or ""))), "Outbreak" .. key)
	end
end

local function setLamp(post, color)
	if post.Lamp then
		post.Lamp.Enabled = color ~= nil
		if color then
			post.Lamp.Color = color
		end
	end
	if post.Glass then
		post.Glass.Material = if color then Enum.Material.Neon else post.GlassMaterial
		post.Glass.Color = color or post.GlassColor
	end
end

local function anyoneCarrying()
	for _, p in inMatch() do
		if (p:GetAttribute("Carried") or 0) > 0 then
			return true
		end
	end
	return false
end

-- The offered radio takes a contract; while anyone carries Scrip every radio banks it.
local function refreshPosts()
	local carrying = outbreakOn and anyoneCarrying()
	for _, post in posts do
		local offer = outbreakOn and post == ob.offered and ob.contract == nil
		local working = ob.contract ~= nil and ob.contract.Post == post
		if post.Prompt then
			post.Prompt.Enabled = offer or carrying
			post.Prompt.ActionText = if offer then "Take contract" else "Bank"
			post.Prompt.HoldDuration = if offer then 0.6 else OUT.BankHold
		end
		setLamp(post, if offer or working then AMBER else nil)
	end
	workspace:SetAttribute("OfferPost", if outbreakOn and ob.offered and not ob.contract then ob.offered.Building else nil)
end

local function padLights(pad, on)
	if pad.Model == extraction then
		setFlare(on)
	end
	for _, f in pad.Flares do
		f.Part.Material = if on then Enum.Material.Neon else f.Material
		f.Part.Color = if on then Color3.fromRGB(255, 60, 40) else f.Color
		if f.Light then
			f.Light.Enabled = on
		end
	end
	for _, light in pad.Strobes do
		light.Enabled = false
	end
end

local function refreshPads()
	local now = os.clock()
	local open = outbreakOn and now >= ob.birdAt and now < ob.endsAt and ob.heliPad == nil and now >= ob.heliReadyAt
	for _, pad in pads do
		pad.Prompt.Enabled = open
	end
end

local function clearHeli()
	if ob.heliPad then
		padLights(ob.heliPad, false)
	end
	ob.heliPad = nil
	ob.heliDone = false
	ob.heliClearAt = nil
	ob.heliReadyAt = os.clock() + OUT.HeliCooldown
	evacAt = nil
	evacZone = zonePart.Position
	leaveRel = EvacPath.DefaultLeave
	workspace:SetAttribute("EvacAt", nil)
	workspace:SetAttribute("EvacLeaveAt", nil)
	workspace:SetAttribute("EvacZone", nil)
	for p in aboard do
		local character = p.Character
		if character then
			character:SetAttribute("Aboard", nil)
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = false
			end
		end
	end
	table.clear(aboard)
end

-- The run's insertion, picked when the first player drops in.
local function outbreakDrop()
	if not ob.drop and #insertions > 0 then
		ob.drop = insertions[math.random(#insertions)]
	end
	if outbreakOn and #insertions > 1 then
		-- Coming back mid-run: the insertion with the fewest zombies around it.
		local best, bestScore = nil, math.huge
		for _, entry in insertions do
			local score = math.random()
			for zombie, info in alive do
				if not info.Sleeping and zombie.PrimaryPart and flat(zombie.PrimaryPart.Position - entry.Point.Position).Magnitude < 60 then
					score += 1
				end
			end
			if score < bestScore then
				best, bestScore = entry, score
			end
		end
		return best.Point
	end
	return ob.drop and ob.drop.Point
end

local function resetOutbreak()
	outbreakOn = false
	if ob.contract then
		for zombie in ob.contract.Targets do
			if zombie.Parent then
				zombie:SetAttribute("ContractTarget", nil)
			end
		end
	end
	ob.contract, ob.offered, ob.lastPost, ob.drop = nil, nil, nil, nil
	ob.kinds = 0
	ob.nextOffer, ob.birdAt, ob.endsAt = math.huge, math.huge, 0
	ob.beacon, ob.birdsCalled, ob.lastCalled = false, false, false
	table.clear(ob.crateUsed)
	table.clear(ob.respawnAt)
	clearHeli()
	ob.heliReadyAt = 0
	for _, pad in pads do
		padLights(pad, false)
		pad.Prompt.Enabled = false
	end
	for _, entry in insertions do
		if entry.Prompt then
			entry.Prompt.Enabled = false
		end
	end
	refreshPosts()
	for _, name in { "OutbreakEndsAt", "BirdAt", "Contract", "ContractLeft", "ContractHolding" } do
		workspace:SetAttribute(name, nil)
	end
	for _, p in Players:GetPlayers() do
		p:SetAttribute("Carried", nil)
		p:SetAttribute("Banked", nil)
	end
end

-- Players ----------------------------------------------------------------------------------

local spawnIndex = 0
local function placeAtStart(character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	task.wait()
	spawnIndex += 1
	local angle = spawnIndex * 2.1
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (if spawnIndex % 4 == 1 then 0 else 3)
	-- Before the run has started, the mode is the one this player picked.
	local player = Players:GetPlayerFromCharacter(character)
	local rules = if running or not player then mode else GameConfig.Modes[player:GetAttribute("Mode") or ""] or mode
	if rules.War and warSpawn and player then
		-- War: the squad's start, an NPC's place, or next to the squad (warSpawn).
		local cf = warSpawn(player)
		if cf then
			character:PivotTo(cf)
			PlayerHealth.Protect(player, 3)
			return
		end
	end
	if rules.Defend and defendSpawn and player then
		-- Defend: the safehouse, or next to the squad (defendSpawn).
		local cf = defendSpawn(player)
		if cf then
			character:PivotTo(cf)
			PlayerHealth.Protect(player, 3)
			return
		end
	end
	local point = rules.Extraction and outbreakDrop()
	if point then
		-- Extraction: on the run's insertion, facing into town.
		local pos = point.Position + offset + Vector3.new(0, 3.5, 0)
		character:PivotTo(CFrame.lookAt(pos, pos + flat(point.CFrame.LookVector)))
		if player then
			PlayerHealth.Protect(player, GameConfig.Outbreak.LandGrace)
		end
		return
	end
	local start = if nightsFor(rules) then nightStart else playerStart
	local pos = start.Position + offset + Vector3.new(0, 3.5, 0)
	character:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1)))
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		if player:GetAttribute("InMatch") then
			placeAtStart(character)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end

-- The dead come back while they have a life left (GameConfig.Lives, player attribute Lives); with
-- none they're Out and watch their team (SpectateClient) until the run ends. Between runs
-- (running false) everyone comes back.
local function respawnDead()
	for _, p in inMatch() do
		if not isAlive(p) then
			local lives = p:GetAttribute("Lives") or 0
			if not running then
				p:SetAttribute("Out", nil)
				Uniform.Load(p)
			elseif lives > 0 then
				p:SetAttribute("Lives", lives - 1)
				Uniform.Load(p)
			elseif not p:GetAttribute("Out") then
				p:SetAttribute("Out", true)
				Remotes.Match:FireClient(p, "Out")
			end
		end
	end
end

-- A run's lives: everyone in it (and anyone who joins it) starts with GameConfig.Lives.Extra.
local function giveLives(player)
	player:SetAttribute("Lives", GameConfig.Lives.Extra)
	player:SetAttribute("Out", nil)
end
Players.PlayerAdded:Connect(function(player)
	player:GetAttributeChangedSignal("InMatch"):Connect(function()
		if player:GetAttribute("InMatch") and running then
			-- a late join: their own ledger for this run (opening the same mode again keeps it)
			if Progression then
				pcall(Progression.OpenLedger, player, workspace:GetAttribute("Mode"), nil)
			end
			if player:GetAttribute("Lives") == nil then
				giveLives(player)
			end
		end
	end)
end)

-- The run ----------------------------------------------------------------------------------

local function resetWorld()
	clearZombies()
	for _, window in windows do
		Barricades.Repair(window.Boards)
	end
	for _, model in debrisList do
		setDebrisShown(model, true)
	end
	closeHouse()
	breakout = false
	lull = false
	evacAt = nil
	workspace:SetAttribute("NightEndsAt", nil)
	workspace:SetAttribute("LastNight", nil)
	workspace:SetAttribute("BeaconHome", nil)
	for _, p in Players:GetPlayers() do
		p:SetAttribute("SelfRevivesStart", nil)
	end
	workspace:SetAttribute("Breakout", false)
	workspace:SetAttribute("BreakoutReady", false)
	workspace:SetAttribute("EvacAt", nil)
	workspace:SetAttribute("RevealUntil", nil)
	workspace:SetAttribute("EvacLeaveAt", nil)
	for p in aboard do
		local character = p.Character
		if character then
			character:SetAttribute("Aboard", nil)
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = false
			end
		end
	end
	table.clear(aboard)
	setFlare(false)
	resetOutbreak()
	if resetWar then
		resetWar()
	end
	Relics.Clear()
	twist = nil
	refreshDoorPrompts()
	for _, d in workspace:FindFirstChild("Drops") and workspace.Drops:GetChildren() or {} do
		d:Destroy()
	end
end

-- Waits up to time seconds; false if everyone died (or left) meanwhile.
local function waitAlive(time)
	local t = 0
	while t < time do
		t += task.wait(0.25)
		if breakout or not anyoneAlive() then
			return false
		end
	end
	return true
end

-- Three spots for the Endless relic sigils, on the floor most of the standing squad is on.
local function relicSpots()
	local positions = playerPositions()
	local up = 0
	for _, pos in positions do
		if pos.Y > houseCf.Y - houseSize.Y / 2 + 12 then
			up += 1
		end
	end
	local floors = if up > #positions / 2 and #upperFloors > 0 then upperFloors else groundFloors
	return floorSpots(floors, ENDLESS.Offer, 7, positions)
end

local function intermission(time)
	setState("Intermission")
	workspace:SetAttribute("NextWaveAt", workspace:GetServerTimeNow() + time)
	respawnDead()
	return waitAlive(time)
end

local function playWave()
	wave += 1
	workspace:SetAttribute("Wave", wave)
	table.clear(repairsThisWave)
	-- Endless: last round's relics go, and some rounds come with a twist.
	Relics.Clear()
	twist = nil
	if mode.Relics and wave >= ENDLESS.TwistFrom and math.random() < ENDLESS.TwistChance then
		local names = {}
		for name in ENDLESS.Twists do
			table.insert(names, name)
		end
		table.sort(names)
		twist = ENDLESS.Twists[names[math.random(#names)]]
		task.delay(1.2, function()
			if twist then
				Remotes.Match:FireAllClients("Notice", twist.Text)
			end
		end)
	end
	if wave == openAtWave and not houseOpen then
		openHouse()
	end
	toSpawn = waveCount(wave)
	updateLeft()
	setState("Wave")
	Remotes.Match:FireAllClients("Wave", wave)
	local nextSpawn = os.clock() + 1.5
	local nextUnstick = os.clock() + 5
	while toSpawn > 0 or aliveCount > 0 do
		task.wait(0.2)
		if breakout or not anyoneAlive() then
			return false
		end
		local now = os.clock()
		local more = extra()
		if toSpawn > 0 and aliveCount < CFG.MaxAlive + CFG.PerPlayer.MaxAlive * more and now >= nextSpawn then
			spawnZombie()
			nextSpawn = now + between(CFG.SpawnGap) * (if wave < 3 then 1.6 else 1) * CFG.PerPlayer.SpawnGap ^ more
		end
		if now >= nextUnstick then
			nextUnstick = now + 5
			unstick()
		end
	end
	if not mode.NoBreakout and wave >= (mode.BreakoutFrom or BREAK.BreakoutFrom) and not workspace:GetAttribute("BreakoutReady") then
		workspace:SetAttribute("BreakoutReady", true)
		refreshDoorPrompts()
		Remotes.Match:FireAllClients("Ready")
	end
	return true
end

-- Nights ---------------------------------------------------------------------------------

-- Studio testing: workspace attribute DebugTimeScale (say 0.2) shortens every night and lull.
local function scaled(seconds)
	return seconds * (if RunService:IsStudio() then workspace:GetAttribute("DebugTimeScale") or 1 else 1)
end

local function nightLength(n)
	if n >= NIGHTS.LastNight then
		return scaled(NIGHTS.LastTime)
	end
	return scaled(math.min(NIGHTS.Base + NIGHTS.Step * (n - 1), NIGHTS.Cap))
end

-- How many zombies of this health the standing players can kill a second, going by the best
-- gun each one carries (GameConfig.Director.Dps).
local function killRate(health)
	local dps = 0
	for _, p in inMatch() do
		if isAlive(p) and not PlayerHealth.IsDowned(p) then
			local best = 0
			for _, slot in Inventory.Slots(p) do
				if slot then
					best = math.max(best, DIRECTOR.Dps[slot.Item] or 0)
				end
			end
			dps += if best > 0 then best else DIRECTOR.DefaultDps
		end
	end
	return dps / math.max(1, health)
end

-- One night in the house: the doors barred, zombies at the windows from the director until
-- its time is up, then a short wait for the last of them. The last night calls the helicopter
-- instead and returns as the breakout starts. False if everyone fell.
local function playNight()
	wave += 1
	-- The last night is the one after the radio tower is complete (PartsServer: TowerParts of
	-- TowerNeed); without parts it's night LastNight.
	local need = workspace:GetAttribute("TowerNeed")
	local last = if need then (workspace:GetAttribute("TowerParts") or 0) >= need else wave >= NIGHTS.LastNight
	lull = false
	clearSleepingStrays()
	workspace:SetAttribute("Wave", wave)
	workspace:SetAttribute("LastNight", last or nil)
	table.clear(repairsThisWave)
	if houseOpen then
		closeHouse()
	end
	refreshDoorPrompts()
	local length = nightLength(wave)
	local start = os.clock()
	local endsAt = start + length
	workspace:SetAttribute("NightEndsAt", workspace:GetServerTimeNow() + length)
	if last then
		workspace:SetAttribute("BeaconHome", houseCf.Position)
	end
	setState("Wave")
	Remotes.Match:FireAllClients("Wave", wave)

	local more = extra()
	local pressure = math.min(DIRECTOR.Max, DIRECTOR.Pressure + DIRECTOR.PerNight * (wave - 1) + DIRECTOR.PerPlayer * more)
		* (if last then DIRECTOR.LastNight else 1) * (mode.Count or 1)
	local maxAlive = math.floor(DIRECTOR.AliveSolo * (1 + DIRECTOR.AlivePerPlayer * more) + DIRECTOR.AlivePerNight * wave
		+ (if last then DIRECTOR.AliveLast else 0))
	local health = waveHealth(wave)
	local evacCall = if last then endsAt - math.min(BREAK.EvacTime, length * 0.5) else nil
	local quietAt = endsAt - DIRECTOR.QuietEnd
	local nextSpawn = start + 1.5
	local nextUnstick = start + 5
	-- One zombie always counts as still to come while spawning is open, so ZombiesLeft only
	-- reaches 0 at dawn.
	toSpawn = 1
	updateLeft()
	while true do
		task.wait(0.2)
		if not anyoneAlive() then
			return false
		end
		local now = os.clock()
		if evacCall and now >= evacCall then
			callEvac()
			return true
		end
		if now >= endsAt then
			break
		end
		local spawning = now < quietAt
		if spawning and aliveCount < maxAlive and now >= nextSpawn then
			toSpawn = 1
			spawnZombie()
			local gap = between(CFG.SpawnGap) * CFG.PerPlayer.SpawnGap ^ more
			local rate = killRate(health) * pressure
			if rate > 0 then
				gap = math.max(gap, (0.7 + math.random() * 0.6) / rate)
			end
			nextSpawn = now + gap
		end
		if now >= nextUnstick then
			nextUnstick = now + 5
			unstick()
		end
		toSpawn = if spawning then 1 else 0
		updateLeft()
	end
	-- Dawn: a moment for the last ones to fall; any left over stay out in the lull.
	local graceEnds = os.clock() + NIGHTS.DawnGrace
	while aliveCount > 0 and os.clock() < graceEnds do
		task.wait(0.25)
		if not anyoneAlive() then
			return false
		end
	end
	return true
end

-- The lull after a night: the doors open, a few zombies roam the town, the Beacon walks it
-- (waking at the first lull) and players go out; ReturnWarn seconds before the next night
-- everyone is called home. False if everyone fell.
local function playLull()
	lull = true
	setState("Intermission")
	local start = os.clock()
	local lullTime = scaled(NIGHTS.LullTime)
	local endsAt = start + lullTime
	workspace:SetAttribute("NightEndsAt", nil)
	workspace:SetAttribute("NextWaveAt", workspace:GetServerTimeNow() + lullTime)
	respawnDead()
	openHouse(true)
	refreshDoorPrompts()
	-- A few strays on the way to this lull's part (PartsServer lays it out as the lull starts).
	task.delay(0.6, function()
		if not lull then
			return
		end
		local at = workspace:GetAttribute("PartAt")
		local count = NIGHTS.Strays + NIGHTS.PerPlayer.Strays * extra()
		for _, spot in straySpotsFor(count, 40, houseCf.Position, if typeof(at) == "Vector3" then at else nil) do
			addStray(spot)
		end
	end)
	if not workspace:GetAttribute("Breakout") then
		-- The Beacon wakes and tears into the building next door; it sees nobody until that's done.
		workspace:SetAttribute("RevealUntil", workspace:GetServerTimeNow() + BREAK.RevealTime)
		workspace:SetAttribute("Breakout", true)
	end
	local cap = NIGHTS.LullAlive + NIGHTS.PerPlayer.LullAlive * extra()
	local nextSpawn = start + between(NIGHTS.LullGap)
	local nextUnstick = start + 5
	local warned = false
	toSpawn = 0
	updateLeft()
	while true do
		task.wait(0.25)
		if not anyoneAlive() then
			lull = false
			return false
		end
		local now = os.clock()
		if now >= endsAt then
			break
		end
		local homeTime = now >= endsAt - scaled(NIGHTS.ReturnWarn)
		if homeTime and not warned then
			warned = true
			Remotes.Match:FireAllClients("Return")
		end
		if not homeTime and #townSpots > 0 and awakeCount() < cap and now >= nextSpawn then
			toSpawn = 1
			spawnZombie()
			nextSpawn = now + between(NIGHTS.LullGap)
		end
		if now >= nextUnstick then
			nextUnstick = now + 5
			unstick()
			toSpawn = 0
			updateLeft()
		end
	end
	lull = false
	return true
end

-- The way out: the helicopter cutscene, the uniform pick, then back to the menu.
local attirePicked = {}
Remotes.Attire.OnServerEvent:Connect(function(player, name)
	if workspace:GetAttribute("WaveState") ~= "Attire" or not player:GetAttribute("InMatch") then
		return
	end
	for _, attire in GameConfig.Attire do
		if attire.Name == name then
			Profile.SetAttire(player, name)
			attirePicked[player] = true
			return
		end
	end
end)

-- The escape: everyone watches the helicopter get away with the Beacon reaching after it
-- (RescueClient). Those aboard get the escape points and, the first time, the other modes;
-- whoever was left behind is taken. The run's end (endRun) follows; nobody is sent anywhere.
local function rescue(escaped)
	setState("Rescue")
	local ids, made = {}, {}
	for _, p in escaped do
		table.insert(ids, p.UserId)
		made[p] = true
		Points.Add(p, BREAK.EscapePoints)
		if not Profile.Get(p).Escaped then
			Profile.SetEscaped(p)
			Remotes.Match:FireClient(p, "Unlocked")
		end
	end
	for _, p in inMatch() do
		if not made[p] and isAlive(p) then
			PlayerHealth.Take(p)
		end
	end
	Remotes.Match:FireAllClients("Rescue", ids)
	task.wait(0.6)
	clearZombies()
	-- The cutscene, then a beat on black for its last line.
	task.wait(RESCUE.EscapeTime - 0.6 + 2.6)
end

local function gameOver()
	setState("GameOver")
	Remotes.Match:FireAllClients("GameOver", wave)
	task.wait(CFG.GameOverTime)
end

-- Outbreak: the run -----------------------------------------------------------------------------

local gunsApi = ServerStorage:WaitForChild("GunsApi", 10)

local function bank(player)
	local carried = player:GetAttribute("Carried") or 0
	if carried <= 0 then
		return
	end
	local added = Profile.Earn(player, carried)
	player:SetAttribute("Carried", 0)
	player:SetAttribute("Banked", (player:GetAttribute("Banked") or 0) + added)
	Remotes.Match:FireClient(player, "Banked", added)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		SoundKit.Play("Pickup/Ammo", { Position = root.Position })
	end
end

-- Spawn spots (town and stray) between near and far studs from pos.
local function spotsAround(pos, near, far)
	local list = {}
	for _, group in { townSpots, straySpots } do
		for _, spot in group do
			local d = flat(spot.Position - pos).Magnitude
			if d >= near and d <= far then
				table.insert(list, spot)
			end
		end
	end
	return list
end

local function startContract(post)
	ob.kinds += 1
	local kind = if ob.kinds % 2 == 1 then "Hold" else "Hunt"
	local c = { Kind = kind, Post = post, Deadline = os.clock() + scaled(OUT.ContractTime), Targets = {}, Spawned = {}, NextSpawn = 0 }
	if kind == "Hold" then
		c.Left = OUT.Hold.Time
	else
		-- The pack waits asleep somewhere out in town, glowing red through the walls (WorldGlow).
		local list = spotsAround(post.At, OUT.Hunt.Near, OUT.Hunt.Far)
		local center = if #list > 0 then list[math.random(#list)] else townSpots[math.random(#townSpots)]
		for i = 1, OUT.Hunt.Count do
			local angle = i / OUT.Hunt.Count * math.pi * 2
			local zombie, entry = addZombie({ Position = center.Position + Vector3.new(math.cos(angle) * 4, 0, math.sin(angle) * 4) }, true)
			entry.Sleeping = true
			local humanoid = zombie:FindFirstChildOfClass("Humanoid")
			humanoid.MaxHealth = math.floor(humanoid.MaxHealth * OUT.Hunt.Health)
			humanoid.Health = humanoid.MaxHealth
			zombie:SetAttribute("ContractTarget", true)
			pcall(function()
				zombie.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			end)
			c.Targets[zombie] = true
		end
		c.Left = OUT.Hunt.Count
	end
	ob.contract = c
	workspace:SetAttribute("Contract", kind)
	workspace:SetAttribute("ContractLeft", c.Left)
	refreshPosts()
	radio(kind)
end

local function endContract(done)
	local c = ob.contract
	if not c then
		return
	end
	ob.contract = nil
	for zombie in c.Targets do
		if zombie.Parent then
			zombie:SetAttribute("ContractTarget", nil)
		end
	end
	ob.lastPost = c.Post
	ob.offered = nil
	ob.nextOffer = os.clock() + OUT.ContractGap
	workspace:SetAttribute("Contract", nil)
	workspace:SetAttribute("ContractLeft", nil)
	workspace:SetAttribute("ContractHolding", nil)
	if done then
		local pay = OUT[c.Kind].Pay
		for _, p in inMatch() do
			p:SetAttribute("Carried", (p:GetAttribute("Carried") or 0) + pay)
		end
		Remotes.Match:FireAllClients("ContractDone", pay)
		radio("Done")
	else
		radio("Failed")
	end
	refreshPosts()
end

local function contractTick(now, dt)
	local c = ob.contract
	if not c then
		return
	end
	if now >= c.Deadline then
		endContract(false)
		return
	end
	if c.Kind == "Hold" then
		local holding = false
		for _, p in inMatch() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and isAlive(p) and not PlayerHealth.IsDowned(p) then
				local off = root.Position - c.Post.At
				if flat(off).Magnitude <= OUT.Hold.Radius and math.abs(off.Y) < 12 then
					holding = true
				end
			end
		end
		if holding then
			c.Left -= dt
		end
		-- While it's held, zombies come for the radio.
		local coming = 0
		for zombie in c.Spawned do
			if alive[zombie] then
				coming += 1
			else
				c.Spawned[zombie] = nil
			end
		end
		if holding and coming < OUT.Hold.Alive + extra() and now >= c.NextSpawn then
			local list = spotsAround(c.Post.At, 35, 100)
			if #list > 0 then
				local zombie = addZombie(list[math.random(#list)])
				c.Spawned[zombie] = true
				hunt(zombie)
			end
			c.NextSpawn = now + between(OUT.Hold.Gap)
		end
		workspace:SetAttribute("ContractHolding", holding)
		workspace:SetAttribute("ContractLeft", math.max(0, c.Left))
		if c.Left <= 0 then
			endContract(true)
		end
	else
		local left = 0
		for zombie in c.Targets do
			local humanoid = zombie.Parent and zombie:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				left += 1
			end
		end
		c.Left = left
		workspace:SetAttribute("ContractLeft", left)
		if left == 0 then
			endContract(true)
		end
	end
end

-- The next contract lights up on the radio nearest the squad (not the one just done).
local function offerTick(now)
	if ob.contract or ob.offered or now < ob.nextOffer or #posts == 0 then
		return
	end
	local players = playerPositions()
	local best, bestD = nil, math.huge
	for _, post in posts do
		if post ~= ob.lastPost then
			local d = math.random()
			for _, pos in players do
				d += flat(pos - post.At).Magnitude
			end
			if d < bestD then
				best, bestD = post, d
			end
		end
	end
	ob.offered = best
	refreshPosts()
	if best then
		radio("Boards", OUT.Posts[best.Building] or best.Building)
	end
end

for _, post in posts do
	if post.Prompt then
		post.Prompt.Triggered:Connect(function(player)
			if not outbreakOn or not player:GetAttribute("InMatch") or not isAlive(player) then
				return
			end
			if post == ob.offered and not ob.contract then
				startContract(post)
			end
			bank(player)
			refreshPosts()
		end)
	end
end

for _, entry in insertions do
	if entry.Prompt then
		entry.Prompt.Triggered:Connect(function(player)
			if not outbreakOn or not isAlive(player) or not gunsApi then
				return
			end
			local used = ob.crateUsed[entry]
			if not used then
				used = {}
				ob.crateUsed[entry] = used
			end
			if os.clock() < (used[player] or 0) then
				Remotes.Match:FireClient(player, "Broke")
				return
			end
			local ok, got = pcall(function()
				return gunsApi:Invoke("GiveAmmo", player)
			end)
			if ok and type(got) == "number" and got > 0 then
				used[player] = os.clock() + OUT.CrateRefill
				SoundKit.Play("Pickup/Ammo", { Position = entry.Prompt.Parent.Position })
			end
		end)
	end
end

-- War: Operation Last Light ---------------------------------------------------------------------
-- (mode War, GameConfig.War, HORROR-SHOOTER-WAR.md) A campaign in three missions for a squad of
-- four: the players plus HOUND's NPC soldiers (ServerStorage.Modules.Soldier) in the slots no
-- player holds. A player joining mid-run takes the last NPC's place where it stands; a player
-- leaving gives it back. Spots: Map.War (Start, M1_Street, M1_Clinic, M1_Station, Codes, M2_Tower,
-- M2_Road, M2_Hold, M3 uses the Main Street landing pad). The objective is workspace Objective (a
-- point WarClient marks); its name goes on the HUD's one line. Dead players come back near the
-- squad after War.RespawnTime; if every player is down at once the mission restarts from its
-- checkpoint. The helicopter out is Outbreak's (callBird, the ladder) and the ending is Defend's
-- rescue.
do
	local WAR = GameConfig.War
	local warMap = map:FindFirstChild("War")
	war = {
		squad = {}, -- [slot] = NPC soldier
		enemies = {},
		mission = 0,
		checkpoint = nil, -- the CFrame players restart on
		codes = false,
		patched = false,
		pad = nil,
		contactAt = 0,
		respawnAt = {},
	}

	local function warSpot(name)
		return warMap and warMap:FindFirstChild(name)
	end

	local function warSpots(name)
		local f = warSpot(name)
		local list = {}
		if f then
			for _, p in f:GetChildren() do
				if p:IsA("BasePart") then
					table.insert(list, p)
				end
			end
			table.sort(list, function(a, b)
				return a.Name < b.Name
			end)
		end
		return list
	end

	local function centre(list)
		local sum = Vector3.zero
		for _, p in list do
			sum += p.Position
		end
		return if #list > 0 then sum / #list else Vector3.zero
	end

	local function warSay(key)
		local text = WAR.Lines[key]
		if text then
			Remotes.Match:FireAllClients("Radio", text, "War" .. key)
		end
	end

	local function setObjective(pos, notice)
		workspace:SetAttribute("Objective", pos)
		if notice then
			Remotes.Match:FireAllClients("Notice", notice)
		end
	end

	local function standing(p)
		return isAlive(p) and p.Character and not p.Character:GetAttribute("Downed")
	end

	-- Where an NPC keeps near: the nearest standing player, facing the objective.
	local function squadAnchor(soldier)
		local best, bestD = nil, math.huge
		for _, p in inMatch() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and standing(p) then
				local d = (root.Position - soldier.Root.Position).Magnitude
				if d < bestD then
					best, bestD = root, d
				end
			end
		end
		local obj = workspace:GetAttribute("Objective")
		if war.rally then
			return war.rally, if typeof(obj) == "Vector3" then flat(obj - war.rally).Unit else nil
		end
		if not best then
			return obj, nil
		end
		local look = flat(best.CFrame.LookVector)
		if typeof(obj) == "Vector3" and flat(obj - best.Position).Magnitude > 4 then
			look = flat(obj - best.Position).Unit
		end
		return best.Position, look
	end

	local function spawnAlly(slot, cf)
		local def = WAR.Squad[slot]
		local s = Soldier.Spawn("Ally", cf, {
			Callsign = def.Callsign,
			Rig = def.Rig,
			Gun = def.Gun,
			Slot = slot,
			Follow = squadAnchor,
		})
		s.OnContact = function()
			if os.clock() >= war.contactAt then
				war.contactAt = os.clock() + WAR.ContactGap
				warSay("Contact")
			end
		end
		s.OnDowned = function()
			Remotes.Match:FireAllClients("Notice", def.Callsign .. " IS DOWN")
		end
		war.squad[slot] = s
		return s
	end

	-- How many NPC slots there are with this many players: the first player has their own place, each
	-- one after takes an NPC's.
	local function npcSlots()
		return math.clamp(#WAR.Squad - (#inMatch() - 1), 0, #WAR.Squad)
	end

	-- Squad names for the menu and the HUD: Squad1..3 (NPC callsign or the player in that slot).
	local function nameSlots()
		local players = inMatch()
		local n = npcSlots()
		for i = 1, #WAR.Squad do
			local p = if i > n then players[#WAR.Squad - i + 2] else nil
			workspace:SetAttribute("Squad" .. i, if p then p.DisplayName else WAR.Squad[i].Callsign)
		end
	end

	-- Brings the squad to what the player count says: NPCs in slots 1..npcSlots(), none past it.
	-- New NPCs stand at near (a CFrame).
	local function rebalance(near)
		if not warOn then
			return
		end
		local n = npcSlots()
		for i = 1, #WAR.Squad do
			local s = war.squad[i]
			if i <= n then
				if (not s or not s.Alive) and near then
					local offset = Vector3.new((i - 2) * 3, 0, 3)
					spawnAlly(i, near + offset)
				end
			elseif s then
				s:Remove()
				war.squad[i] = nil
			end
		end
		nameSlots()
	end

	-- Where a (re)spawning player lands in War.
	warSpawn = function(player)
		local start = warSpot("Start")
		if not warOn or not start then
			return if start then start.CFrame + Vector3.new(0, 3.5, 0) else nil
		end
		-- Joining: take over the NPC whose slot is now yours, where it stands.
		local n = npcSlots()
		for i = #WAR.Squad, n + 1, -1 do
			local s = war.squad[i]
			if s and s.Alive then
				local cf = s.Root.CFrame
				s:Remove()
				war.squad[i] = nil
				nameSlots()
				Remotes.Match:FireAllClients("Notice", string.upper(player.DisplayName) .. " TAKES " .. WAR.Squad[i].Callsign .. "'S PLACE")
				return cf
			end
		end
		if war.restart and war.checkpoint then
			return war.checkpoint
		end
		-- Back in: next to a standing player, else an NPC, else the checkpoint.
		for _, p in inMatch() do
			local root = p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and standing(p) then
				return root.CFrame * CFrame.new(3, 0, 3)
			end
		end
		for _, s in war.squad do
			if s.Alive and not s.Downed then
				return s.Root.CFrame * CFrame.new(3, 0, 3)
			end
		end
		return war.checkpoint or start.CFrame + Vector3.new(0, 3.5, 0)
	end

	Players.PlayerRemoving:Connect(function(player)
		if not warOn then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = if root then root.CFrame else war.checkpoint
		task.defer(rebalance, at)
	end)

	local function spawnGroup(name, opts)
		local list = {}
		for _, spot in warSpots(name) do
			local kind = spot:GetAttribute("Kind") or "Lamplighter"
			local advance = opts and opts.Advance and opts.Advance[(#list % #opts.Advance) + 1]
			local s = Soldier.Spawn(kind, spot.CFrame + Vector3.new(0, 3, 0), {
				Post = spot.Position,
				Advance = advance,
			})
			table.insert(list, s)
			table.insert(war.enemies, s)
		end
		return list
	end

	local function left(list)
		local n = 0
		for _, s in list do
			if s.Alive and s.Humanoid.Health > 0 then
				n += 1
			end
		end
		return n
	end

	local function reach(pos, radius)
		for _, p in inMatch() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and standing(p) and flat(root.Position - pos).Magnitude <= radius and math.abs(root.Position.Y - pos.Y) < 14 then
				return true
			end
		end
		return false
	end

	local function wiped()
		for _, p in inMatch() do
			if standing(p) then
				return false
			end
		end
		return true
	end

	local function clearEnemies()
		Soldier.Clear("Enemy")
		table.clear(war.enemies)
	end

	-- The war world between checks: the dead come back, zombies trickle in up to cap.
	local function warTick(cap)
		local now = os.clock()
		for _, p in inMatch() do
			if isAlive(p) then
				war.respawnAt[p] = nil
			elseif not aboard[p] then
				if not war.respawnAt[p] then
					war.respawnAt[p] = now + WAR.RespawnTime
				elseif now >= war.respawnAt[p] then
					war.respawnAt[p] = now + WAR.RespawnTime
					task.spawn(Uniform.Load, p)
				end
			end
		end
		if cap and #townSpots > 0 and awakeCount() < cap + WAR.ZombiesPerPlayer * extra() and now >= (war.nextZombie or 0) then
			toSpawn = 1
			spawnZombie()
			toSpawn = 0
			war.nextZombie = now + between(WAR.ZombieGap)
		end
		if now >= (war.nextUnstick or 0) then
			war.nextUnstick = now + 5
			unstick()
		end
	end

	-- Runs the war world until done() (true), the squad wipes (false) or timeout (true).
	local function warUntil(done, cap, timeout)
		local start = os.clock()
		while true do
			task.wait(0.25)
			if #inMatch() == 0 then
				return false
			end
			warTick(cap)
			if wiped() then
				return false
			end
			if done() then
				return true
			end
			if timeout and os.clock() - start >= timeout then
				return true
			end
		end
	end

	-- A hold-E prompt on a spot that flips a flag in war when used.
	local function objectivePrompt(spot, action, object, hold, flag)
		local prompt = spot:FindFirstChild("WarPrompt")
		if not prompt then
			prompt = newPrompt(spot, action, object, hold)
			prompt.Name = "WarPrompt"
			prompt.Triggered:Connect(function(player)
				if prompt.Enabled and standing(player) then
					prompt.Enabled = false
					war[prompt:GetAttribute("Flag")] = true
				end
			end)
		end
		prompt:SetAttribute("Flag", flag)
		prompt.Enabled = true
		return prompt
	end

	local function checkpoint(name)
		local spot = warSpot(name)
		war.checkpoint = if spot then spot.CFrame + Vector3.new(0, 3.5, 0) else war.checkpoint
	end

	-- Mission 1: HOT DROP. Down at the west wreck, up Main Street through two fights, into the police
	-- station, the tower codes off the dispatch desk.
	local function missionDrop()
		checkpoint("Start")
		local street, clinic, station = spawnGroup("M1_Street"), spawnGroup("M1_Clinic"), spawnGroup("M1_Station")
		for _, spot in straySpotsFor(WAR.Strays, 40) do
			addStray(spot)
		end
		local streetAt = centre(warSpots("M1_Street"))
		setObjective(streetAt, "PUSH UP MAIN STREET")
		warSay("Drop")
		if not warUntil(function()
			return left(street) <= 1 and reach(streetAt, 45)
		end, WAR.Zombies.Drop) then
			return false
		end
		checkpoint("Checkpoint1")
		local clinicAt = centre(warSpots("M1_Clinic"))
		setObjective(clinicAt, "TAKE THE CLINIC CORNER")
		warSay("Clinic")
		if not warUntil(function()
			return left(clinic) <= 1 and reach(clinicAt, 45)
		end, WAR.Zombies.Drop) then
			return false
		end
		local codes = warSpot("Codes")
		setObjective(centre(warSpots("M1_Station")), "CLEAR THE CHECKPOINT")
		warSay("Station")
		if not warUntil(function()
			return left(station) == 0 or (left(station) <= 2 and codes and reach(codes.Position, 14))
		end, WAR.Zombies.Drop) then
			return false
		end
		if codes then
			war.codes = false
			setObjective(codes.Position, "GET THE TOWER CODES")
			warSay("Codes")
			objectivePrompt(codes, "Take codes", "Checkpoint booth", WAR.CodesHold, "codes")
			if not warUntil(function()
				return war.codes
			end, WAR.Zombies.Drop) then
				return false
			end
		end
		warSay("GotCodes")
		return true
	end

	-- Mission 2: SIGNAL. Up the hill, the codes into the tower, then hold it while it transmits:
	-- zombies up the slope and Lamplighter squads from the road, the heavy among them.
	local function missionSignal()
		checkpoint("Checkpoint2")
		local tower = warSpot("M2_Tower")
		if not tower then
			return true
		end
		setObjective(tower.Position, "GET TO THE RADIO TOWER")
		warSay("Tower")
		if not warUntil(function()
			return reach(tower.Position, 24)
		end, WAR.Zombies.Walk) then
			return false
		end
		war.patched = false
		setObjective(tower.Position, "PATCH THE CODES IN")
		objectivePrompt(tower, "Patch in codes", "Radio tower", WAR.PatchHold, "patched")
		if not warUntil(function()
			return war.patched
		end, WAR.Zombies.Walk) then
			return false
		end
		warSay("Hold")
		Remotes.Match:FireAllClients("Notice", "HOLD THE TOWER")
		war.rally = tower.Position
		local hold = WAR.Hold
		local progress, squadsSent, heavySent = 0, 0, false
		local holdSpots = {}
		for _, p in warSpots("M2_Hold") do
			table.insert(holdSpots, p.Position)
		end
		local last = os.clock()
		local ok = warUntil(function()
			local now = os.clock()
			local dt = now - last
			last = now
			-- It only transmits while someone stands by it.
			if reach(tower.Position, hold.Radius) then
				progress += dt
			end
			workspace:SetAttribute("WarProgress", math.clamp(progress / hold.Time, 0, 1))
			local nextSquad = hold.Squads[squadsSent + 1]
			if nextSquad and progress >= nextSquad then
				squadsSent += 1
				spawnGroup("M2_Road", { Advance = holdSpots })
				warSay("Wave")
			end
			if not heavySent and progress >= hold.HeavyAt then
				heavySent = true
				local road = warSpots("M2_Road")
				if #road > 0 then
					local s = Soldier.Spawn("Heavy", road[1].CFrame + Vector3.new(0, 3.5, 0), {
						Post = road[1].Position,
						Advance = tower.Position + Vector3.new(0, 0, 18),
					})
					table.insert(war.enemies, s)
				end
				warSay("Heavy")
			end
			return progress >= hold.Time
		end, hold.Zombies)
		war.rally = nil
		workspace:SetAttribute("WarProgress", nil)
		return ok
	end

	-- Mission 3: LAST LIGHT. The broadcast wakes the Beacon. Main Street pad, call the bird, hold
	-- it, grab the ladder. Returns the players aboard.
	local function missionLastLight()
		checkpoint("Checkpoint3")
		warSay("Sent")
		task.wait(3)
		workspace:SetAttribute("RevealUntil", workspace:GetServerTimeNow() + BREAK.RevealTime)
		workspace:SetAttribute("Breakout", true)
		warSay("Beacon")
		local pad = nil
		for _, p in pads do
			if p.Id == WAR.PadId then
				pad = p
			end
		end
		pad = pad or pads[1]
		if not pad then
			return {}
		end
		war.pad = pad
		setObjective(pad.Zone.Position, "CALL THE BIRD ON MAIN STREET")
		local escaped = {}
		while true do
			clearHeli()
			ob.heliReadyAt = 0
			pad.Prompt.Enabled = true
			if not warUntil(function()
				return ob.heliPad ~= nil
			end, WAR.Zombies.Beacon) then
				pad.Prompt.Enabled = false
				return nil
			end
			pad.Prompt.Enabled = false
			war.rally = pad.Zone.Position
			Remotes.Match:FireAllClients("Notice", "HOLD THE PAD")
			local gone = false
			local ok = warUntil(function()
				local t = evacTime()
				local phase = EvacPath.Phase(t, leaveRel)
				local blink = t > -EVAC.Inbound and math.floor(os.clock() * 2) % 2 == 0
				for _, light in pad.Strobes do
					light.Enabled = blink
				end
				if phase == "Leave" and t >= leaveRel + 2.5 or phase == "Gone" then
					gone = true
				end
				return gone
			end, WAR.Zombies.Pad)
			war.rally = nil
			if not ok then
				return nil
			end
			for p in aboard do
				if p.Parent then
					table.insert(escaped, p)
				end
			end
			if #escaped > 0 then
				return escaped
			end
			warSay("Missed")
		end
	end

	local MISSIONS = { missionDrop, missionSignal, missionLastLight }

	-- The whole operation. Returns the players who got out (for rescue), or {}.
	playWar = function()
		warOn = true
		setState("War")
		wave = 1
		workspace:SetAttribute("Wave", wave)
		if not houseOpen then
			openHouse(true)
		end
		local start = warSpot("Start")
		rebalance(if start then start.CFrame + Vector3.new(0, 3, 6) else nil)
		local escaped = {}
		war.mission = 1
		while war.mission <= #MISSIONS and #inMatch() > 0 do
			workspace:SetAttribute("WarMission", war.mission)
			Remotes.Match:FireAllClients("Notice", WAR.Missions[war.mission])
			local result = MISSIONS[war.mission]()
			if result == false or result == nil then
				if #inMatch() == 0 then
					break
				end
				-- Wiped: back to the checkpoint, the mission from the top.
				warSay("Failed")
				Remotes.Match:FireAllClients("Notice", "MISSION FAILED")
				task.wait(WAR.FailWait)
				clearEnemies()
				clearZombies()
				clearHeli()
				war.restart = true
				for _, p in inMatch() do
					task.spawn(Uniform.Load, p)
				end
				for i, s in war.squad do
					if s.Alive and war.checkpoint then
						s.Model:PivotTo(war.checkpoint * CFrame.new((i - 2) * 3, 0, 4))
						s:GetUp()
					end
				end
				task.wait(2)
				war.restart = false
			elseif type(result) == "table" then
				escaped = result
				break
			else
				war.mission += 1
			end
		end
		return escaped
	end

	resetWar = function()
		warOn = false
		Soldier.Clear()
		table.clear(war.squad)
		table.clear(war.enemies)
		table.clear(war.respawnAt)
		war.mission, war.checkpoint, war.rally, war.pad = 0, nil, nil, nil
		war.codes, war.patched, war.restart = false, false, false
		for _, name in { "Objective", "WarMission", "WarProgress", "Squad1", "Squad2", "Squad3" } do
			workspace:SetAttribute(name, nil)
		end
		if warMap then
			for _, d in warMap:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					d.Enabled = false
				end
			end
		end
	end
end

-- Calling the bird: it flies EvacPath to this pad; the ladder, the grab and the ride are the
-- breakout's own (evacZone, aboard).
local function callBird(pad)
	ob.heliPad = pad
	ob.heliDone = false
	evacZone = pad.Zone.Position
	workspace:SetAttribute("EvacZone", evacZone)
	evacAt = workspace:GetServerTimeNow() + scaled(OUT.HeliInbound)
	leaveRel = EvacPath.DefaultLeave
	workspace:SetAttribute("EvacAt", evacAt)
	workspace:SetAttribute("EvacLeaveAt", evacAt + leaveRel)
	padLights(pad, true)
	refreshPads()
	radio("Called", OUT.Pads[pad.Id] or "pad")
	Remotes.Match:FireAllClients("Evac")
end

for _, pad in pads do
	pad.Prompt.Triggered:Connect(function(player)
		local now = os.clock()
		if warOn then
			if war and pad == war.pad and not ob.heliPad and isAlive(player) then
				callBird(pad)
			end
			return
		end
		if not outbreakOn or ob.heliPad or now < ob.birdAt or now >= ob.endsAt or now < ob.heliReadyAt or not isAlive(player) then
			return
		end
		callBird(pad)
	end)
end

-- Whoever got aboard is out: their Scrip banked with EscapePay on top, the escape on their
-- screen, then the menu. Everyone else plays on.
local function escapeOutbreak(list)
	local ids = {}
	for _, p in list do
		table.insert(ids, p.UserId)
	end
	for _, p in list do
		p:SetAttribute("Carried", (p:GetAttribute("Carried") or 0) + OUT.EscapePay)
		bank(p)
		if not Profile.Get(p).Escaped then
			Profile.SetEscaped(p)
			Remotes.Match:FireClient(p, "Unlocked")
		end
		Remotes.Match:FireClient(p, "Rescue", ids)
	end
	task.delay(RESCUE.EscapeTime + 2.6, function()
		for _, p in list do
			aboard[p] = nil
		end
	end)
end

local function heliTick()
	local pad = ob.heliPad
	if not pad or not evacAt then
		return
	end
	local t = evacTime()
	local phase = EvacPath.Phase(t, leaveRel)
	if not ob.heliDone then
		local blink = t > -EVAC.Inbound and math.floor(os.clock() * 2) % 2 == 0
		for _, light in pad.Strobes do
			light.Enabled = blink
		end
	end
	if not ob.heliDone and (phase == "Leave" and t >= leaveRel + 2.5 or phase == "Gone") then
		ob.heliDone = true
		padLights(pad, false)
		local out = {}
		for p in aboard do
			if p.Parent then
				table.insert(out, p)
			end
		end
		if #out > 0 then
			escapeOutbreak(out)
		else
			radio("Missed")
		end
		ob.heliClearAt = os.clock() + (if #out > 0 then RESCUE.EscapeTime + 3 else 2)
	end
	if ob.heliDone and os.clock() >= (ob.heliClearAt or 0) then
		clearHeli()
		refreshPads()
	end
end

-- The dead come back on the insertion; what they carried is gone.
local function respawnTick(now)
	for _, p in inMatch() do
		if isAlive(p) then
			ob.respawnAt[p] = nil
		elseif not aboard[p] then
			if not ob.respawnAt[p] then
				ob.respawnAt[p] = now + OUT.RespawnTime
				if (p:GetAttribute("Carried") or 0) > 0 then
					p:SetAttribute("Carried", 0)
					Remotes.Match:FireClient(p, "Lost")
					refreshPosts()
				end
			elseif now >= ob.respawnAt[p] then
				ob.respawnAt[p] = now + OUT.RespawnTime
				task.spawn(Uniform.Load, p)
			end
		end
	end
end

local function playOutbreak()
	outbreakOn = true
	setState("Outbreak")
	local start = os.clock()
	local serverStart = workspace:GetServerTimeNow()
	ob.endsAt = start + scaled(OUT.Length)
	ob.birdAt = start + scaled(OUT.BirdFrom)
	ob.nextOffer = start + scaled(OUT.BoardsAt)
	ob.heliReadyAt = 0
	local beaconAt = start + scaled(OUT.BeaconAt)
	local lastCallAt = ob.endsAt - scaled(OUT.LastCall)
	workspace:SetAttribute("OutbreakEndsAt", serverStart + scaled(OUT.Length))
	workspace:SetAttribute("BirdAt", serverStart + scaled(OUT.BirdFrom))
	wave = 1
	workspace:SetAttribute("Wave", wave)
	if not houseOpen then
		openHouse(true)
	end
	for _, p in inMatch() do
		p:SetAttribute("Carried", 0)
		p:SetAttribute("Banked", 0)
	end
	for _, entry in insertions do
		if entry.Prompt then
			entry.Prompt.Enabled = true
		end
	end
	-- The hot drop: zombies already on the wreck.
	outbreakDrop()
	local drop = ob.drop
	if drop then
		for i = 1, OUT.HotDrop.Base + OUT.HotDrop.PerPlayer * extra() do
			local spot = if #drop.Spawns > 0 then drop.Spawns[(i - 1) % #drop.Spawns + 1] else drop.Point
			-- Asleep on the wreck until Delay is up (or a shot, or someone walks up), then on you.
			local zombie, entry = addZombie(spot)
			entry.Sleeping = true
			task.delay(OUT.HotDrop.Delay, wake, zombie)
		end
	end
	for _, spot in straySpotsFor(OUT.Strays, OUT.StrayClear) do
		addStray(spot)
	end
	radio("Drop")
	refreshPosts()

	local nextTown = start + 4
	local nextStray = start + scaled(OUT.StrayRefill)
	local nextUnstick = start + 5
	local last = start
	while true do
		task.wait(0.2)
		local now = os.clock()
		local dt = now - last
		last = now
		if #inMatch() == 0 then
			break
		end
		local elapsed = now - start
		local more = extra()
		-- Zombies toughen up as the run goes on.
		local w = 1 + math.floor(elapsed / scaled(OUT.WaveEvery))
		if w ~= wave then
			wave = w
			workspace:SetAttribute("Wave", wave)
		end
		if not ob.beacon and now >= beaconAt then
			ob.beacon = true
			workspace:SetAttribute("RevealUntil", workspace:GetServerTimeNow() + BREAK.RevealTime)
			workspace:SetAttribute("Breakout", true)
			radio("Beacon")
			Remotes.Match:FireAllClients("Notice", "THE BEACON IS AWAKE")
		end
		if not ob.birdsCalled and now >= ob.birdAt then
			ob.birdsCalled = true
			radio("Birds")
			Remotes.Match:FireAllClients("Notice", "BIRDS ARE FLYING")
		end
		if not ob.lastCalled and now >= lastCallAt then
			ob.lastCalled = true
			radio("LastCall")
		end
		-- Hunting zombies town-wide, out of sight of everyone.
		local cap = OUT.Town.Base + OUT.Town.PerPlayer * more + (if elapsed >= scaled(OUT.Town.LateFrom) then OUT.Town.Late else 0)
		if #townSpots > 0 and awakeCount() < cap and now >= nextTown then
			toSpawn = 1
			spawnZombie()
			nextTown = now + between(OUT.Town.Gap) * BREAK.PerPlayer.SpawnGap ^ more
		end
		-- Strays topped up, away from everyone.
		if now >= nextStray then
			nextStray = now + scaled(OUT.StrayRefill)
			for _, spot in straySpotsFor(math.min(2, OUT.Strays - strayCount()), OUT.StrayClear) do
				addStray(spot)
			end
		end
		if now >= nextUnstick then
			nextUnstick = now + 5
			unstick()
		end
		toSpawn = 0
		offerTick(now)
		contractTick(now, dt)
		heliTick()
		refreshPads()
		respawnTick(now)
		-- The last bird has gone: anyone still down here is taken, with what they carry.
		if now >= ob.endsAt and not ob.heliPad then
			for _, p in inMatch() do
				p:SetAttribute("Carried", 0)
				if isAlive(p) then
					PlayerHealth.Take(p)
				end
			end
			break
		end
	end
	endContract(false)
end

workspace:SetAttribute("HoldRespawns", true)
workspace:SetAttribute("Wave", 0)
updateLeft()
setState("Waiting")

-- Scrip for a match (GameConfig.Scrip; Outbreak banks its own as it goes, the campaign is its
-- own place): every night (or Endless round) survived, a share of the points earned, and the
-- escape for those aboard. VIP adds its share (Profile.Earn).
local SCRIP = GameConfig.Scrip
local function payScrip(escaped)
	local aboard = {}
	for _, p in escaped do
		aboard[p] = true
	end
	for _, p in inMatch() do
		local survived = if aboard[p] then wave else math.max(0, wave - 1)
		local pay = survived * (if nightsOn then SCRIP.PerNight else SCRIP.PerWave)
			+ math.floor((p:GetAttribute("PointsEarned") or 0) * SCRIP.PointsShare)
			+ (if aboard[p] then SCRIP.Escape else 0)
		if pay > 0 then
			-- shown in the after-action report (Profile.Earn puts it in the ledger), not as a toast
			Profile.Earn(p, pay)
		end
	end
end

-- This run's tallies for the after-action report.
local runNights, runWaves, runObjectives = 0, 0, 0

-- XP for something the squad got through together (Night, Wave, Objective): everyone still in it.
local function credit(reason)
	if not Progression then
		return
	end
	for _, p in inMatch() do
		if not p:GetAttribute("Out") then
			task.spawn(pcall, Progression.Add, p, reason)
		end
	end
end

-- The one end of every run (MENU contract): Scrip, then each player's after-action report, then
-- ServerStorage.Events.MatchEnded(result, info) once. MenuServer takes it from there: REDEPLOY fires StartMatch
-- again (this loop resets the world and waits for it), CONTINUE takes the party to a lobby.
-- result: "Escaped" | "Survived" (lived through every night, missed the helicopter) | "Overrun".
local function endRun(result, escaped)
	if not mode.Extraction and not mode.War and not mode.Defend then
		payScrip(escaped)
	end
	local aboard = {}
	for _, p in escaped do
		aboard[p] = true
	end
	local squad = inMatch()
	local info = {
		Mode = workspace:GetAttribute("Mode"),
		Nights = runNights,
		Waves = runWaves,
		Objectives = runObjectives,
		Squad = squad,
	}
	if Progression then
		for _, p in squad do
			-- someone left behind when the helicopter went was taken
			local own = if aboard[p] then "Escaped" elseif result == "Escaped" then "Overrun" else result
			local ok, err = pcall(Progression.EndMatch, p, own, info)
			if not ok then
				warn("MatchServer: EndMatch failed", p, err)
			end
		end
	end
	ServerStorage.Events.MatchEnded:Fire(result, info)
end

while true do
	-- Wait for the menu to start a run, then for its players' bodies (MenuServer lets them in just after).
	while not startQueued do
		task.wait(0.25)
	end
	local start = startQueued
	startQueued = nil
	local waitFrom = os.clock()
	while not anyoneAlive() and os.clock() - waitFrom < 20 do
		task.wait(0.25)
	end
	checkWindows()
	-- The mode: the server's (one mode per server, ModeSetup). A server not locked yet takes the
	-- started mode, else the first player's Mode (GameConfig.Modes names), and is locked to it here.
	local modeName = workspace:GetAttribute("ServerMode")
	if not modeName and GameConfig.Modes[start.Mode or ""] then
		modeName = ModeSetup.Apply(start.Mode)
	end
	if not modeName then
		for _, p in inMatch() do
			if GameConfig.Modes[p:GetAttribute("Mode") or ""] then
				modeName = p:GetAttribute("Mode")
				break
			end
		end
		modeName = ModeSetup.Apply(modeName or GameConfig.Menu.Modes[1])
	end
	mode = GameConfig.Modes[modeName] or GameConfig.Modes.Outbreak
	nightsOn = nightsFor(mode)
	workspace:SetAttribute("Mode", modeName)
	workspace:SetAttribute("Nights", nightsOn)
	workspace:SetAttribute("ModeSeenFill", mode.SeenFill or 1)
	workspace:SetAttribute("ModeLensHealth", mode.LensHealth or 1)
	wave = 0
	workspace:SetAttribute("Wave", 0)
	runNights, runWaves, runObjectives = 0, 0, 0
	for _, p in Players:GetPlayers() do
		Points.Reset(p)
		Relics.Reset(p)
	end
	if Progression then
		for _, p in inMatch() do
			pcall(Progression.OpenLedger, p, modeName, nil)
		end
	end
	-- Endless: a new house every run (where the guns lie, what the debris costs, when the doors go).
	openAtWave = if mode.Relics then math.random(ENDLESS.OpenAtWave.Min, ENDLESS.OpenAtWave.Max) else CFG.OpenAtWave
	setDebrisCosts(if mode.Relics then ENDLESS.DebrisCost else nil)
	-- Alone, you get more self-revives (PlayerHealth gives every new life SelfRevivesStart).
	local solo = #inMatch() == 1
	for _, p in inMatch() do
		local revives = if nightsOn and solo then NIGHTS.SoloSelfRevives else nil
		p:SetAttribute("SelfRevivesStart", revives)
		if revives and p.Character then
			p.Character:SetAttribute("SelfRevives", revives)
		end
	end
	running = true
	-- A player's first ever match: PartsServer lays its first part in the Shop.
	for _, p in inMatch() do
		p:SetAttribute("FirstMatch", (Profile.Get(p).Matches or 0) == 0 or nil)
		Profile.Count(p, "Matches")
	end
	refreshDoorPrompts()
	shuffleGuns()
	if not mode.War and not mode.Defend then
		spawnSleepers()
	end
	for _, p in inMatch() do
		giveLives(p)
	end
	local warEscaped = nil
	if mode.Defend and playDefend then
		warEscaped = playDefend()
	elseif mode.War then
		warEscaped = playWar()
	elseif mode.Extraction then
		playOutbreak()
	elseif nightsOn then
		local ok = intermission(scaled(NIGHTS.FirstDelay))
		while ok and not breakout do
			ok = playNight()
			if ok then
				runNights += 1
				credit("Night")
			end
			if ok and not breakout then
				ok = playLull()
			end
		end
	elseif mode.Relics then
		-- Endless: rounds, and three relics to choose from after each one.
		local ok = intermission(CFG.FirstWaveDelay)
		while ok do
			ok = playWave()
			if ok then
				runWaves += 1
				credit("Wave")
				Relics.Offer(relicSpots(), wave)
				ok = intermission(ENDLESS.Intermission)
			end
		end
		Relics.Clear()
	else
		local ok = intermission(CFG.FirstWaveDelay)
		while ok do
			ok = playWave()
			if ok then
				runWaves += 1
				credit("Wave")
				ok = intermission(CFG.Intermission)
			end
		end
	end
	local escaped = if breakout and anyoneAlive() then runBreakout() else warEscaped or {}
	running = false
	local result = if #escaped > 0 then "Escaped" elseif breakout then "Survived" else "Overrun"
	if #escaped > 0 then
		rescue(escaped)
	elseif #inMatch() > 0 then
		if breakout then
			Remotes.Match:FireAllClients("HeliLeft")
		end
		gameOver()
		if mode.Relics then
			-- The best Endless round goes on the profile (a board later).
			for _, p in inMatch() do
				local best = Profile.Get(p).EndlessBest or 0
				local reached = math.max(0, wave - 1)
				if reached > best then
					Profile.Count(p, "EndlessBest", reached - best)
				end
			end
		end
	end
	endRun(result, escaped)
	resetWorld()
	wave = 0
	workspace:SetAttribute("Wave", 0)
	setState("Waiting")
	respawnDead()
	task.wait(1)
end
