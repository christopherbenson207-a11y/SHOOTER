-- Cover for WAR's soldiers (horror-shooter/war/BATTLE-PLAN.md). Surveys the ground round a point
-- with rays and keeps every spot a soldier can hide at, in an 8-stud grid. Numbers:
-- GameConfig.War.Battle.Cover.
--   On a Step-stud lattice: a ray down finds walkable ground within Band studs of the fight's floor;
--   a box the size of a standing soldier must be empty there; eight rays at crouched-chest height
--   (Low) look for an upright surface within Probe studs, each one a covered direction. A ray at
--   standing-eye height (High) says what kind: clear over the top is half cover (crouch to hide,
--   stand to fire over it); blocked is full cover, and then a peek spot Peek studs to either side
--   with an open line of fire is looked for (step out to fire, step back to hide).
--   Walkable samples are kept as ground too, so respawns and lanes snap onto real floor.
-- A spot: { Pos (the ground point), Dirs = { { Dir, Full, Fire, Peek } }, Owner, BadUntil }.
-- A soldier claims the spot it uses; one it could not reach is marked bad for a while. The map needs
-- no tags: Map.War (the spots) and anything see-through or non-colliding is not cover.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local C = GameConfig.War.Battle.Cover
local CELL = 8
local UP = Vector3.yAxis
local BODY = Vector3.new(2.2, 4.2, 2.2)
local SLIM = Vector3.new(1.8, 4, 1.8)

local CoverMap = {}

local spots = {} -- [cell] = { spot, ... }
local ground = {} -- [cell] = { Vector3, ... }
local sampled = {} -- [lattice key] = true
local total = 0

local DIRS = {}
for i = 0, 7 do
	local a = i * math.pi / 4
	table.insert(DIRS, Vector3.new(math.cos(a), 0, math.sin(a)))
end

local function cell(x, z)
	return (math.floor(x / CELL) + 4096) * 8192 + math.floor(z / CELL) + 4096
end

local function add(store, pos, item)
	local key = cell(pos.X, pos.Z)
	local bucket = store[key]
	if not bucket then
		bucket = {}
		store[key] = bucket
	end
	table.insert(bucket, item)
end

-- Rays and boxes that see the world: not soldiers, players, effects or the spot markers.
local function queries()
	local ignore = {}
	for _, name in { "Squad", "Hostiles", "Fx", "Relics" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	local map = workspace:FindFirstChild("Map")
	local war = map and map:FindFirstChild("War")
	if war then
		table.insert(ignore, war)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.IgnoreWater = true
	rp.RespectCanCollide = true
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = ignore
	op.RespectCanCollide = true
	return rp, op
end

-- Something you could hide behind: terrain (not water) or a part you can see.
local function solid(hit)
	if hit.Instance:IsA("Terrain") then
		return hit.Material ~= Enum.Material.Water
	end
	-- A map mesh's invisible collision box (MeshProxy) is as solid as the mesh it stands in for.
	return hit.Instance.Transparency < 0.9 or hit.Instance:GetAttribute("MeshProxy") ~= nil
end

-- Nothing solid in a soldier-sized box standing at ground point g.
local function clear(g, op, size)
	local box = CFrame.new(g + Vector3.new(0, 0.6 + size.Y / 2, 0))
	for _, part in workspace:GetPartBoundsInBox(box, size, op) do
		if not part:IsA("Terrain") then
			return false
		end
	end
	return true
end

-- Walkable ground under x, z near the floor height, or nil.
local function groundAt(x, z, floorY, rp)
	local hit = workspace:Raycast(Vector3.new(x, floorY + C.Band + 3, z), Vector3.new(0, -(C.Band * 2 + 3), 0), rp)
	if hit and hit.Normal.Y > 0.75 and solid(hit) and math.abs(hit.Position.Y - floorY) <= C.Band then
		return hit.Position
	end
	return nil
end

-- A spot beside full cover where a soldier can step out and fire along d.
local function peekSpot(g, d, rp, op)
	local side = d:Cross(UP)
	for _, s in { side, -side } do
		if not workspace:Raycast(g + Vector3.new(0, C.Low, 0), s * C.Peek, rp) then
			local p = g + s * C.Peek
			local down = workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -6, 0), rp)
			if down and down.Normal.Y > 0.75 and math.abs(down.Position.Y - g.Y) < 1.5 and clear(down.Position, op, SLIM) then
				local pg = down.Position
				if not workspace:Raycast(pg + Vector3.new(0, C.High, 0), d * 10, rp) then
					return pg
				end
			end
		end
	end
	return nil
end

local function sample(x, z, floorY, rp, op)
	local g = groundAt(x, z, floorY, rp)
	if not g or not clear(g, op, BODY) then
		return
	end
	add(ground, g, g)
	local low = g + Vector3.new(0, C.Low, 0)
	local high = g + Vector3.new(0, C.High, 0)
	local dirs = {}
	for _, d in DIRS do
		local hit = workspace:Raycast(low, d * C.Probe, rp)
		if hit and math.abs(hit.Normal.Y) < 0.6 and solid(hit) then
			local over = workspace:Raycast(high, d * (C.Probe + 0.5), rp)
			if over and solid(over) then
				local peek = peekSpot(g, d, rp, op)
				table.insert(dirs, { Dir = d, Full = true, Fire = peek ~= nil, Peek = peek })
			else
				-- Half cover: standing, the line of fire over the top has to go somewhere.
				local beyond = workspace:Raycast(high, d * 12, rp)
				table.insert(dirs, { Dir = d, Full = false, Fire = beyond == nil or beyond.Distance > 8 })
			end
		end
	end
	if #dirs > 0 then
		add(spots, g, { Pos = g, Dirs = dirs, Owner = nil, BadUntil = 0 })
		total += 1
	end
end

-- The floor height under pos (a ray down from a little above it), or pos.Y.
function CoverMap.FloorAt(pos)
	local rp = queries()
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), rp)
	return if hit then hit.Position.Y else pos.Y
end

-- Surveys the ground within radius of center (floorY: the fight's floor, found under center if
-- nil). Yields as it goes; a lattice point already surveyed is skipped, so overlapping areas are
-- cheap. Returns how many cover spots the map holds now.
function CoverMap.Survey(center, radius, floorY)
	floorY = floorY or CoverMap.FloorAt(center)
	local rp, op = queries()
	local step = C.Step
	local r2 = radius * radius
	local done = 0
	for x = math.floor((center.X - radius) / step) * step, center.X + radius, step do
		for z = math.floor((center.Z - radius) / step) * step, center.Z + radius, step do
			local dx, dz = x - center.X, z - center.Z
			local key = x .. "," .. z
			if dx * dx + dz * dz <= r2 and not sampled[key] then
				sampled[key] = true
				sample(x, z, floorY, rp, op)
				done += 1
				if done % 40 == 0 then
					task.wait()
				end
			end
		end
	end
	return total
end

-- Cover spots within radius of pos.
function CoverMap.Near(pos, radius)
	local list = {}
	local r2 = radius * radius
	for cx = math.floor((pos.X - radius) / CELL), math.floor((pos.X + radius) / CELL) do
		for cz = math.floor((pos.Z - radius) / CELL), math.floor((pos.Z + radius) / CELL) do
			local bucket = spots[(cx + 4096) * 8192 + cz + 4096]
			if bucket then
				for _, s in bucket do
					local dx, dz = s.Pos.X - pos.X, s.Pos.Z - pos.Z
					if dx * dx + dz * dz <= r2 then
						table.insert(list, s)
					end
				end
			end
		end
	end
	return list
end

-- The surveyed walkable point nearest pos within radius, or nil.
function CoverMap.Snap(pos, radius)
	local best, bestD = nil, radius * radius
	for cx = math.floor((pos.X - radius) / CELL), math.floor((pos.X + radius) / CELL) do
		for cz = math.floor((pos.Z - radius) / CELL), math.floor((pos.Z + radius) / CELL) do
			local bucket = ground[(cx + 4096) * 8192 + cz + 4096]
			if bucket then
				for _, g in bucket do
					local dx, dz = g.X - pos.X, g.Z - pos.Z
					local d = dx * dx + dz * dz
					if d < bestD then
						best, bestD = g, d
					end
				end
			end
		end
	end
	return best
end

-- The spot's covered direction facing a threat at pos (within about 53 degrees), or nil.
function CoverMap.Facing(spot, pos)
	local to = Vector3.new(pos.X - spot.Pos.X, 0, pos.Z - spot.Pos.Z)
	if to.Magnitude < 0.1 then
		return nil
	end
	to = to.Unit
	local best, bestDot = nil, C.Arc
	for _, d in spot.Dirs do
		local dot = d.Dir:Dot(to)
		if dot > bestDot then
			best, bestDot = d, dot
		end
	end
	return best
end

function CoverMap.Claim(spot, who)
	if spot.Owner and spot.Owner ~= who then
		return false
	end
	spot.Owner = who
	return true
end

function CoverMap.Release(spot, who)
	if spot and spot.Owner == who then
		spot.Owner = nil
	end
end

-- A spot nobody could reach: left alone for seconds.
function CoverMap.Bad(spot, seconds)
	spot.BadUntil = os.clock() + seconds
	spot.Owner = nil
end

function CoverMap.Count()
	return total
end

-- Forgets the survey (the map changed).
function CoverMap.Reset()
	table.clear(spots)
	table.clear(ground)
	table.clear(sampled)
	total = 0
end

-- Markers for checking a survey in Studio: green half cover, orange full, a stub toward each
-- covered direction. Returns the folder; destroy it when done.
function CoverMap.Draw(parent)
	local f = Instance.new("Folder")
	f.Name = "_CoverMarkers"
	for _, bucket in spots do
		for _, s in bucket do
			for _, d in s.Dirs do
				local p = Instance.new("Part")
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
				p.Material = Enum.Material.Neon
				p.Color = if d.Full then Color3.fromRGB(255, 150, 40) else Color3.fromRGB(80, 230, 90)
				p.Size = Vector3.new(0.3, 0.3, 1.2)
				p.CFrame = CFrame.lookAt(s.Pos + Vector3.new(0, 0.4, 0), s.Pos + Vector3.new(0, 0.4, 0) + d.Dir) * CFrame.new(0, 0, -0.6)
				p.Parent = f
			end
		end
	end
	f.Parent = parent or workspace
	return f
end

return CoverMap
