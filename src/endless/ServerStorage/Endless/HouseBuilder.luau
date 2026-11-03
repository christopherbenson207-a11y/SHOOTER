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

	local function standable(room, c)
		local key = cellKey(room.Level, c[1], c[2])
		return not ramp[key] and not hole[key] and not busy[key]
	end

	-- Up to count spots to stand on in the start room (cell middles, spread out).
	function house:StartPoints(count)
		local room = rooms[startRoom]
		local list = {}
		for _, c in room.Cells do
			if standable(room, c) then
				table.insert(list, cellCenter(c[1], c[2], room.Floor))
			end
		end
		for i = #list, 2, -1 do
			local j = math.random(i)
			list[i], list[j] = list[j], list[i]
		end
		local out = {}
		for i = 1, count do
			table.insert(out, list[(i - 1) % math.max(1, #list) + 1])
		end
		return out
	end

	-- Up to count floor points in a room (cell middles), the ones nearest `near` first.
	function house:FloorPoints(room, count, near)
		local list = {}
		for _, c in room.Cells do
			if standable(room, c) then
				table.insert(list, cellCenter(c[1], c[2], room.Floor))
			end
		end
		if near then
			table.sort(list, function(a, b)
				return (a - near).Magnitude < (b - near).Magnitude
			end)
		end
		local out = {}
		for i = 1, math.min(count, #list) do
			table.insert(out, list[i])
		end
		return out
	end

	return house
end

return HouseBuilder
