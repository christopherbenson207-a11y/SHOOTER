-- The WAR test arena (Studio only): two nations' infantry fight across a built battlefield so the
-- soldier brain (Modules.Soldier, Modules.CoverMap) can be watched and judged against
-- docs/ALLIED-AI-PROMPT.md and docs/HOSTILE-AI-PROMPT.md. Numbers: GameConfig.War.TestScene.
--   To run it: in Studio, select Workspace, add the boolean attribute WarTestScene = true, press
--   Play and press PLAY in the menu. WarServer stays off while it is set. Remove the attribute (or
--   set it false) to get the operation back. Nothing here runs in a live server.
--   Optional workspace attributes, read when a round starts:
--     WarTestScenario  "Assault" (allies attack a held line; the default), "Counter" (the enemy
--                      attacks the allied trench), "Meeting" (both push to the middle).
--     WarTestAllied    a GameConfig.War.Dress name for the player's side (default USA).
--     WarTestAxis      a Dress name for the enemy (default Germany).
--     WarTestWatch     true: you stand on the tower east of the field and nobody shoots at you.
--   The field (built once, far from the valley, at TestScene.Origin): allied trench in the south,
--   no-man's land with a wrecked truck, a wrecked tank, crate stacks, rocks, a broken stone wall
--   and a roofless farmhouse with windows, then the enemy line in the north: sandbags, a trench,
--   a bunker with a firing slit and a ruined barn. Half cover is about 3.3 studs tall (kneel to
--   hide, stand to fire), full cover 7 or more, so CoverMap's survey finds both kinds.
--   Each round: PerSide soldiers a side and a Reserve each that walks in from the rear. A round
--   ends when one side is gone (its survivors' "Clear" is called) or after eight minutes; the next
--   starts RoundGap seconds later. Every ten seconds Output shows each side: alive, in cover,
--   moving, exposed, pinned.
--   Soldiers speak (Modules.SoldierVoice) and wear their nation's colours (SoldierView, Dress).
--   Enemies are the Lamplighter kind dressed as the Axis nation, so player guns hit them as usual.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

if not RunService:IsStudio() or workspace:GetAttribute("WarTestScene") ~= true then
	return
end

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Soldier = require(ServerStorage.Modules.Soldier)
local CoverMap = require(ServerStorage.Modules.CoverMap)
local SoldierVoice = require(ServerStorage.Modules.SoldierVoice)

local WAR = GameConfig.War
local CFG = WAR.TestScene
local B = WAR.Battle
local O = CFG.Origin
local ROUND_TIME = 8 * 60

-- So the menu deploys players straight in, as it does for the operation.
workspace:SetAttribute("Campaign", true)
SoldierVoice.Install()

local function between(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

-- Building -----------------------------------------------------------------------------------------

local root = workspace:FindFirstChild("WarTestScene")
if root then
	root:Destroy()
end
root = Instance.new("Model")
root.Name = "WarTestScene"
root.Parent = workspace

local COLORS = {
	Mud = Color3.fromRGB(92, 78, 60),
	Snow = Color3.fromRGB(208, 212, 214),
	Sand = Color3.fromRGB(150, 132, 98),
	Stone = Color3.fromRGB(118, 114, 106),
	Brick = Color3.fromRGB(112, 72, 56),
	Wood = Color3.fromRGB(104, 78, 52),
	Burnt = Color3.fromRGB(46, 42, 40),
	Rust = Color3.fromRGB(96, 60, 42),
	Rock = Color3.fromRGB(96, 94, 90),
	Plank = Color3.fromRGB(86, 66, 46),
}

-- A world point from field coordinates: x across (west to east), z from the enemy (north, -z)
-- to the allies (south, +z), y above the ground.
local function at(x, y, z)
	return O + Vector3.new(x, y, z)
end

local function part(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function group(name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = root
	return m
end

-- A box standing on the ground at field (x, z), turned yaw degrees.
local function block(parent, name, x, z, size, yaw, color, material, lift)
	local cf = CFrame.new(at(x, size.Y / 2 + (lift or 0), z)) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	return part(parent, name, size, cf, color, material)
end

-- A run of sandbags (half cover) from (x1, z1) to (x2, z2).
local function sandbags(parent, x1, z1, x2, z2, height)
	local a, b = Vector3.new(x1, 0, z1), Vector3.new(x2, 0, z2)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local yaw = math.deg(math.atan2(-(b - a).Z, (b - a).X))
	local h = height or 3.3
	block(parent, "Sandbags", mid.X, mid.Z, Vector3.new(len, h, 2.4), yaw, COLORS.Sand, Enum.Material.Fabric)
	-- A darker top row, for the look of stacked bags.
	block(parent, "SandbagsTop", mid.X, mid.Z, Vector3.new(len - 0.6, 0.5, 2.6), yaw, COLORS.Sand:Lerp(COLORS.Mud, 0.35), Enum.Material.Fabric, h - 0.3)
end

-- A trench line: parapets either side of a duckboard floor, with gaps to pass through.
local function trench(name, z, x1, x2, gaps)
	local g = group(name)
	local edges = { x1 }
	for _, gx in gaps do
		table.insert(edges, gx - 3.5)
		table.insert(edges, gx + 3.5)
	end
	table.insert(edges, x2)
	for i = 1, #edges, 2 do
		local a, b = edges[i], edges[i + 1]
		sandbags(g, a, z - 3.6, b, z - 3.6)
		sandbags(g, a, z + 3.6, b, z + 3.6, 2.6)
	end
	block(g, "Duckboards", (x1 + x2) / 2, z, Vector3.new(x2 - x1, 0.2, 4.6), 0, COLORS.Plank, Enum.Material.WoodPlanks)
	return g
end

-- A wall from (x1, z1) to (x2, z2), height h, with optional window gaps (sill at 3.3, head at 7).
local function wall(parent, x1, z1, x2, z2, h, color, material, windows, doors)
	local a, b = Vector3.new(x1, 0, z1), Vector3.new(x2, 0, z2)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local yaw = math.deg(math.atan2(-dir.Z, dir.X))
	local cuts = {}
	for _, w in windows or {} do
		table.insert(cuts, { From = w - 2, To = w + 2, Kind = "Window" })
	end
	for _, d in doors or {} do
		table.insert(cuts, { From = d - 2.75, To = d + 2.75, Kind = "Door" })
	end
	table.sort(cuts, function(p, q)
		return p.From < q.From
	end)
	local function piece(s, e, y0, y1)
		if e - s < 0.2 or y1 - y0 < 0.2 then
			return
		end
		local c = a + dir * ((s + e) / 2)
		block(parent, "Wall", c.X, c.Z, Vector3.new(e - s, y1 - y0, 1.2), yaw, color, material, y0)
	end
	local s = 0
	for _, cut in cuts do
		piece(s, cut.From, 0, h)
		if cut.Kind == "Window" then
			piece(cut.From, cut.To, 0, 3.3)
			piece(cut.From, cut.To, 7, h)
		else
			piece(cut.From, cut.To, 8, h)
		end
		s = cut.To
	end
	piece(s, len, 0, h)
end

local function crate(parent, x, z, stack, yaw)
	for i = 1, stack do
		block(parent, "Crate", x, z, Vector3.new(4, 4, 4), (yaw or 0) + (i - 1) * 9, COLORS.Wood, Enum.Material.WoodPlanks, (i - 1) * 4)
	end
end

local function rock(parent, x, z, size)
	local p = block(parent, "Rock", x, z, size, math.random(0, 359), COLORS.Rock, Enum.Material.Slate, -0.6)
	p.CFrame *= CFrame.Angles(math.rad(math.random(-8, 8)), 0, math.rad(math.random(-8, 8)))
	return p
end

local function rubble(parent, x, z)
	for i = 1, 5 do
		local s = Vector3.new(math.random(20, 45) / 10, math.random(12, 30) / 10, math.random(20, 45) / 10)
		local p = block(parent, "Rubble", x + math.random(-25, 25) / 10, z + math.random(-25, 25) / 10, s, math.random(0, 359), if i % 2 == 0 then COLORS.Brick else COLORS.Stone, Enum.Material.Brick)
		p.CFrame *= CFrame.Angles(math.rad(math.random(-15, 15)), 0, math.rad(math.random(-15, 15)))
	end
	block(parent, "RubbleCore", x, z, Vector3.new(6, 3.2, 5), math.random(0, 359), COLORS.Stone, Enum.Material.Brick)
end

local function truck(x, z, yaw)
	local g = group("WreckedTruck")
	local base = CFrame.new(at(x, 0, z)) * CFrame.Angles(0, math.rad(yaw), math.rad(4))
	local function piece(name, size, off, color, mat)
		part(g, name, size, base * CFrame.new(off), color, mat or Enum.Material.CorrodedMetal)
	end
	piece("Chassis", Vector3.new(15, 1.6, 6.4), Vector3.new(0, 2.2, 0), COLORS.Burnt)
	piece("Cab", Vector3.new(5, 4.6, 6.4), Vector3.new(-5, 5.2, 0), COLORS.Rust)
	piece("Bonnet", Vector3.new(3, 2.4, 5.6), Vector3.new(-8.8, 4.1, 0), COLORS.Rust)
	piece("BedFloor", Vector3.new(9, 0.6, 6.4), Vector3.new(2.5, 3.3, 0), COLORS.Burnt)
	piece("BedLeft", Vector3.new(9, 3, 0.4), Vector3.new(2.5, 5, -3), COLORS.Plank, Enum.Material.WoodPlanks)
	piece("BedRight", Vector3.new(9, 3, 0.4), Vector3.new(2.5, 5, 3), COLORS.Plank, Enum.Material.WoodPlanks)
	for _, w in { Vector3.new(-7, 1.4, -3.4), Vector3.new(-7, 1.4, 3.4), Vector3.new(4, 1.4, -3.4), Vector3.new(4, 1.4, 3.4) } do
		part(g, "Wheel", Vector3.new(0.9, 2.8, 2.8), base * CFrame.new(w) * CFrame.Angles(0, math.rad(90), 0), COLORS.Burnt, Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
	end
end

local function tank(x, z, yaw)
	local g = group("WreckedTank")
	local base = CFrame.new(at(x, 0, z)) * CFrame.Angles(0, math.rad(yaw), math.rad(-3))
	local function piece(name, size, off, color, rot)
		part(g, name, size, base * CFrame.new(off) * (rot or CFrame.identity), color, Enum.Material.CorrodedMetal)
	end
	piece("Hull", Vector3.new(18, 4.6, 9.5), Vector3.new(0, 2.9, 0), COLORS.Burnt)
	piece("TrackLeft", Vector3.new(19, 3, 2), Vector3.new(0, 1.5, -5.6), COLORS.Rust)
	piece("TrackRight", Vector3.new(19, 3, 2), Vector3.new(0, 1.5, 5.6), COLORS.Rust)
	piece("Turret", Vector3.new(7.5, 3.2, 7), Vector3.new(-1, 6.8, 0), COLORS.Burnt, CFrame.Angles(0, math.rad(25), 0))
	piece("Barrel", Vector3.new(9, 0.8, 0.8), Vector3.new(-7.2, 7.4, 2.2), COLORS.Burnt, CFrame.Angles(0, math.rad(25), math.rad(-6)))
end

-- A roofless building: four walls with windows and doors, part of a floor above in one corner.
local function ruin(name, x, z, w, d, h, color, material, windowsLong, windowsShort, doorsLong, doorsShort)
	local g = group(name)
	local x1, x2, z1, z2 = x - w / 2, x + w / 2, z - d / 2, z + d / 2
	wall(g, x1, z1, x2, z1, h, color, material, windowsLong, doorsLong)
	wall(g, x1, z2, x2, z2, h, color, material, windowsLong, doorsLong)
	wall(g, x1, z1, x1, z2, h, color, material, windowsShort, doorsShort)
	wall(g, x2, z1, x2, z2, h, color, material, windowsShort, doorsShort)
	block(g, "Floor", x, z, Vector3.new(w, 0.3, d), 0, COLORS.Plank, Enum.Material.WoodPlanks)
	-- A broken beam fallen across the room: half cover inside.
	local beam = block(g, "FallenBeam", x - w * 0.15, z, Vector3.new(w * 0.45, 1.4, 1.4), 30, COLORS.Wood, Enum.Material.Wood, 0)
	beam.CFrame *= CFrame.Angles(0, 0, math.rad(8))
	crate(g, x + w * 0.3, z - d * 0.25, 1)
	return g
end

local function bunker(x, z)
	local g = group("Bunker")
	local w, d = 16, 11
	local x1, x2, z1, z2 = x - w / 2, x + w / 2, z - d / 2, z + d / 2
	-- The front wall (facing the allies, +z) has a slit from 3.3 to 5.4 studs up.
	block(g, "FrontLow", x, z2, Vector3.new(w, 3.3, 1.6), 0, COLORS.Stone, Enum.Material.Concrete)
	block(g, "FrontHigh", x, z2, Vector3.new(w, 2.8, 1.6), 0, COLORS.Stone, Enum.Material.Concrete, 5.4)
	for _, sx in { -w / 2 + 0.8, -2, 2, w / 2 - 0.8 } do
		block(g, "SlitPost", x + sx, z2, Vector3.new(1.2, 2.1, 1.6), 0, COLORS.Stone, Enum.Material.Concrete, 3.3)
	end
	wall(g, x1, z1, x1, z2, 8.2, COLORS.Stone, Enum.Material.Concrete)
	wall(g, x2, z1, x2, z2, 8.2, COLORS.Stone, Enum.Material.Concrete)
	wall(g, x1, z1, x2, z1, 8.2, COLORS.Stone, Enum.Material.Concrete, nil, { w / 2 })
	block(g, "Roof", x, z, Vector3.new(w + 1.6, 1.2, d + 1.6), 0, COLORS.Stone:Lerp(COLORS.Mud, 0.3), Enum.Material.Concrete, 8.2)
	sandbags(g, x1 - 1, z2 + 2.4, x2 + 1, z2 + 2.4, 2.4)
end

local function tower(x, z)
	local g = group("WatchTower")
	local h = 38
	for _, c in { Vector2.new(-5, -5), Vector2.new(5, -5), Vector2.new(-5, 5), Vector2.new(5, 5) } do
		block(g, "Leg", x + c.X, z + c.Y, Vector3.new(1.2, h, 1.2), 0, COLORS.Wood, Enum.Material.Wood)
	end
	block(g, "Deck", x, z, Vector3.new(13, 1, 13), 0, COLORS.Plank, Enum.Material.WoodPlanks, h)
	for _, r in { { 0, -6.5, 13, 0.4 }, { 0, 6.5, 13, 0.4 }, { -6.5, 0, 0.4, 13 }, { 6.5, 0, 0.4, 13 } } do
		block(g, "Rail", x + r[1], z + r[2], Vector3.new(r[3], 3, r[4]), 0, COLORS.Wood, Enum.Material.Wood, h + 1)
	end
	return at(x, h + 4, z)
end

local function build()
	local W, D = 340, 440
	part(root, "Ground", Vector3.new(W, 4, D), CFrame.new(at(0, -2, 0)), COLORS.Snow, Enum.Material.Snow)
	-- A churned mud strip through no-man's land.
	part(root, "Mud", Vector3.new(W - 40, 0.2, 170), CFrame.new(at(0, 0.1, 30)), COLORS.Mud, Enum.Material.Mud)
	-- Bounds: invisible, so the survey never takes them for cover.
	for _, b in { { 0, -D / 2, W, 2 }, { 0, D / 2, W, 2 }, { -W / 2, 0, 2, D }, { W / 2, 0, 2, D } } do
		part(root, "Bound", Vector3.new(b[3], 40, b[4]), CFrame.new(at(b[1], 20, b[2])), COLORS.Stone, nil, { Transparency = 1 })
	end

	-- Allied side (south).
	trench("AlliedTrench", 165, -110, 110, { -55, 0, 55 })
	local nests = group("AlliedNests")
	sandbags(nests, -128, 150, -118, 140)
	sandbags(nests, 118, 140, 128, 150)
	crate(nests, -30, 148, 1)
	crate(nests, 34, 146, 2)

	-- No-man's land.
	truck(-62, 92, 20)
	local cr = group("Crates")
	crate(cr, 36, 104, 1)
	crate(cr, 41, 104, 2, 8)
	crate(cr, 46, 100, 1, 20)
	crate(cr, -10, 22, 1)
	crate(cr, -6, 26, 2)
	local rocks = group("Rocks")
	rock(rocks, -112, 64, Vector3.new(7, 5.5, 6))
	rock(rocks, 112, 72, Vector3.new(6, 4, 7))
	rock(rocks, 2, 62, Vector3.new(5, 3.4, 6))
	rock(rocks, -130, -10, Vector3.new(8, 7, 7))
	rock(rocks, 130, 20, Vector3.new(7, 3.6, 5))
	local stoneWall = group("StoneWall")
	local x = -126
	local i = 0
	while x < 120 do
		i += 1
		local h = if i % 3 == 0 then 7.2 else 3.4
		wall(stoneWall, x, 40, x + 14, 40, h, COLORS.Stone, Enum.Material.Cobblestone)
		x += 14 + 8
	end
	ruin("Farmhouse", -52, -2, 30, 22, 10, COLORS.Brick, Enum.Material.Brick, { 6, 24 }, { 11 }, { 15 }, nil)
	tank(64, 8, -30)
	local rub = group("Rubble")
	rubble(rub, 22, -22)
	rubble(rub, -102, -32)
	rubble(rub, 108, -24)
	rubble(rub, -20, 70)

	-- Enemy side (north).
	local line = group("EnemySandbags")
	x = -112
	while x < 110 do
		sandbags(line, x, -70, x + 18, -70)
		x += 18 + 7
	end
	trench("EnemyTrench", -112, -120, 120, { -60, 0, 60 })
	bunker(0, -144)
	ruin("Barn", 92, -136, 26, 18, 11, COLORS.Wood, Enum.Material.WoodPlanks, { 7, 19 }, { 9 }, { 13 }, nil)
	local back = group("EnemyRear")
	crate(back, -70, -150, 2)
	crate(back, -64, -152, 1)
	rock(back, -110, -150, Vector3.new(8, 6, 7))

	return tower(158, 10)
end

-- Places -------------------------------------------------------------------------------------------

local towerTop = build()
print("WarTestScene: field built; surveying cover...")
local floorY = O.Y
for _, z in { -130, -40, 50, 140 } do
	CoverMap.Survey(at(0, 0, z), 150, floorY)
end
print(("WarTestScene: %d cover spots in the map"):format(CoverMap.Survey(at(0, 0, 0), 1, floorY)))

local ALLY_START = { at(-45, 3, 185), at(45, 3, 185) }
local ALLY_REAR_Z, AXIS_REAR_Z = 198, -198
local ALLY_TRENCH = { at(-45, 0, 165), at(45, 0, 165) }
local MIDDLE = at(0, 0, 20)
-- Enemy posts (Defend): the sandbag line, the trench, the bunker slit, the barn windows.
local POSTS = {
	at(-95, 0, -74), at(-50, 0, -74), at(-15, 0, -74), at(20, 0, -74), at(55, 0, -74), at(95, 0, -74),
	at(-80, 0, -112), at(-30, 0, -112), at(30, 0, -112), at(80, 0, -112),
	at(0, 0, -142), at(92, 0, -136),
}
local ENEMY_GOAL = at(0, 0, -105)

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function facing(from, to)
	local d = flat(to - from)
	if d.Magnitude < 0.1 then
		d = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(from, from + d)
end

-- Orders ---------------------------------------------------------------------------------------------

local round = { Scenario = CFG.Scenario, Allied = CFG.Allied, Axis = CFG.Axis, Reserve = {}, Due = {}, N = 0 }

local function attack(from, goal, laneX, facingPoint)
	local g = goal + Vector3.new(laneX, 0, 0)
	return { Mode = "Attack", Goal = g, Radius = B.AttackRadius, LaneA = Vector3.new(from.X, goal.Y, from.Z), LaneB = g, Facing = { facingPoint or goal } }
end

local function allyOrder(team, from)
	local laneX = if team == 1 then -40 else 40
	if round.Scenario == "Counter" then
		return { Mode = "Hold", Goal = ALLY_TRENCH[team], Radius = B.HoldRadius, Facing = { at(laneX, 0, -100) } }
	elseif round.Scenario == "Meeting" then
		return attack(from, MIDDLE, laneX, at(0, 0, -100))
	end
	return attack(from, ENEMY_GOAL, laneX)
end

local function enemyOrder(index, from)
	local laneX = (math.random() * 2 - 1) * 60
	if round.Scenario == "Counter" then
		return attack(from, at(0, 0, 165), laneX, at(0, 0, 175))
	elseif round.Scenario == "Meeting" then
		return attack(from, MIDDLE, laneX, at(0, 0, 160))
	end
	local post = POSTS[(index - 1) % #POSTS + 1]
	return { Mode = "Defend", Goal = post, Radius = B.DefendRadius, Facing = { at(post.X - O.X, 0, 170) } }
end

-- Spawning -------------------------------------------------------------------------------------------

local function rigFor(dressName)
	local d = WAR.Dress[dressName]
	local rigs = d and d.Rigs
	return if rigs and #rigs > 0 then rigs[math.random(#rigs)] else nil
end

local function spawnAlly(i, cf)
	local team = if i <= 6 then 1 else 2
	local name = CFG.Allies[(i - 1) % #CFG.Allies + 1]
	return Soldier.Spawn("Ally", cf, {
		Callsign = name,
		Slot = i,
		Team = team,
		Dress = round.Allied,
		Rig = rigFor(round.Allied),
		Order = allyOrder(team, cf.Position),
	})
end

local function spawnEnemy(i, cf)
	return Soldier.Spawn("Lamplighter", cf, {
		Slot = (i - 1) % CFG.PerSide + 1,
		Team = if i % 2 == 1 then 1 else 2,
		Dress = round.Axis,
		Rig = rigFor(round.Axis),
		Order = enemyOrder(i, cf.Position),
	})
end

local function startRound()
	round.N += 1
	round.Scenario = workspace:GetAttribute("WarTestScenario") or CFG.Scenario
	round.Allied = workspace:GetAttribute("WarTestAllied") or CFG.Allied
	round.Axis = workspace:GetAttribute("WarTestAxis") or CFG.Axis
	if not WAR.Dress[round.Allied] then
		warn("WarTestScene: no Dress named " .. tostring(round.Allied) .. "; using " .. CFG.Allied)
		round.Allied = CFG.Allied
	end
	if not WAR.Dress[round.Axis] then
		warn("WarTestScene: no Dress named " .. tostring(round.Axis) .. "; using " .. CFG.Axis)
		round.Axis = CFG.Axis
	end
	round.Reserve = { Ally = CFG.Reserve, Enemy = CFG.Reserve }
	round.Due = {}
	round.Started = os.clock()
	round.Spawned = { Ally = 0, Enemy = 0 }
	SoldierVoice.Reset()
	print(("WarTestScene: round %d, %s, %s against %s"):format(round.N, round.Scenario, round.Allied, round.Axis))
	workspace:SetAttribute("WarTestStatus", ("Round %d: %s"):format(round.N, round.Scenario))
	for i = 1, CFG.PerSide do
		local team = if i <= 6 then 1 else 2
		local slot = (i - 1) % 6
		local start = ALLY_START[team] + Vector3.new((slot - 2.5) * 4, 0, (slot % 2) * 3)
		local target = if round.Scenario == "Counter" then ALLY_TRENCH[team] else at(0, 0, -100)
		round.Spawned.Ally += 1
		spawnAlly(i, facing(start, target))
		task.wait(0.05)
	end
	for i = 1, CFG.PerSide do
		local pos
		if round.Scenario == "Assault" then
			pos = POSTS[(i - 1) % #POSTS + 1] + Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))
		else
			pos = at((i - 6.5) * 9, 3, -180 + (i % 2) * 4)
		end
		round.Spawned.Enemy += 1
		spawnEnemy(i, facing(pos, at(pos.X - O.X, 0, 170)))
		task.wait(0.05)
	end
end

-- Tops a side up from its reserve, one at a time, ReinforceDelay after each loss.
local function reinforce(side, now)
	local alive = #Soldier.All(side)
	if alive >= CFG.PerSide or round.Reserve[side] <= 0 then
		round.Due[side] = nil
		return
	end
	if not round.Due[side] then
		round.Due[side] = now + between(CFG.ReinforceDelay)
		return
	end
	if now < round.Due[side] then
		return
	end
	round.Due[side] = nil
	round.Reserve[side] -= 1
	round.Spawned[side] += 1
	local n = round.Spawned[side]
	if side == "Ally" then
		local pos = at(math.random(-60, 60), 3, ALLY_REAR_Z)
		spawnAlly((n - 1) % CFG.PerSide + 1, facing(pos, at(0, 0, -100)))
	else
		local pos = at(math.random(-60, 60), 3, AXIS_REAR_Z)
		spawnEnemy(n, facing(pos, at(0, 0, 170)))
	end
end

local function report()
	local parts = {}
	for _, side in { "Ally", "Enemy" } do
		local list = Soldier.All(side)
		local cover, moving, exposed, pinned = 0, 0, 0, 0
		for _, s in list do
			if s.Cover and (s.Phase == "Hidden" or s.Phase == "Exposing" or s.Phase == "Exposed") then
				cover += 1
			end
			if s.Phase == "Moving" then
				moving += 1
			end
			if s.Phase == "Exposed" or s.Phase == "Open" then
				exposed += 1
			end
			if s.Suppression >= B.Brain.Suppress.Pin then
				pinned += 1
			end
		end
		local label = if side == "Ally" then round.Allied else round.Axis
		table.insert(parts, ("%s %d (cover %d, moving %d, exposed %d, pinned %d, reserve %d)"):format(label, #list, cover, moving, exposed, pinned, round.Reserve[side] or 0))
	end
	print("WarTestScene: " .. table.concat(parts, " | "))
end

local function endRound(winner)
	local survivors = if winner then Soldier.All(winner) else {}
	if survivors[1] then
		SoldierVoice.Say(survivors[1], "Clear")
	end
	local label = if winner == "Ally" then round.Allied elseif winner == "Enemy" then round.Axis else "nobody (time)"
	print(("WarTestScene: round %d won by %s"):format(round.N, label))
	workspace:SetAttribute("WarTestStatus", ("Round %d won by %s"):format(round.N, label))
	task.wait(CFG.RoundGap)
	Soldier.Clear()
	task.wait(0.5)
end

-- Players -------------------------------------------------------------------------------------------

local function place(player, character)
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp or not player:GetAttribute("InMatch") and not player:GetAttribute("WarTestWatching") then
		return
	end
	task.wait(0.2)
	if workspace:GetAttribute("WarTestWatch") == true then
		character:PivotTo(CFrame.lookAt(towerTop, at(0, 0, 0)))
		-- Soldiers only fight players in the match: a watcher is left alone.
		player:SetAttribute("WarTestWatching", true)
		player:SetAttribute("InMatch", false)
	else
		player:SetAttribute("Side", "Ally")
		local start = at(math.random(-8, 8), 4, 178)
		character:PivotTo(CFrame.lookAt(start, start + Vector3.new(0, 0, -1)))
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		place(player, character)
	end)
	if player.Character then
		task.spawn(place, player, player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end

-- The loop -----------------------------------------------------------------------------------------

local function anyoneHere()
	for _, p in Players:GetPlayers() do
		if p.Character and (p:GetAttribute("InMatch") or p:GetAttribute("WarTestWatching")) then
			return true
		end
	end
	return false
end

while true do
	while not anyoneHere() do
		task.wait(0.5)
	end
	task.wait(1.5)
	startRound()
	local nextReport = os.clock() + 10
	local winner = nil
	while true do
		task.wait(0.5)
		local now = os.clock()
		reinforce("Ally", now)
		reinforce("Enemy", now)
		if now >= nextReport then
			nextReport = now + 10
			report()
		end
		local allies, enemies = #Soldier.All("Ally"), #Soldier.All("Enemy")
		if enemies == 0 and round.Reserve.Enemy <= 0 then
			winner = "Ally"
			break
		elseif allies == 0 and round.Reserve.Ally <= 0 then
			winner = "Enemy"
			break
		elseif now - round.Started > ROUND_TIME then
			break
		end
	end
	report()
	endRound(winner)
end
