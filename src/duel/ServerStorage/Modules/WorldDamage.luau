-- Bullets against the world: glass shatters, wood and plastic split into chunks once their
-- health runs out, stone and metal only take marks (classes and numbers:
-- GameConfig.WorldDamage). GunServer calls Hit for every validated world hit; the marks,
-- dust and sparks are drawn on the clients (CombatFx.WorldImpact).
-- Big breakables are cut up round each hit so bullets knock holes where they land
-- (Rainbow Six Siege soft walls). A broken or fractured part is hidden in place
-- (attribute Shot) so Restore can bring it back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Settings = GameConfig.WorldDamage
local Barricades = require(game:GetService("ServerStorage").Modules.Barricades)

local WorldDamage = {}

local function volume(part)
	local s = part.Size
	return s.X * s.Y * s.Z
end

local function indestructible(part)
	local node = part
	while node and node ~= workspace do
		if node:GetAttribute("Indestructible") then
			return true
		end
		node = node.Parent
	end
	return false
end

local function barricadeOf(part)
	local node = part.Parent
	while node and node ~= workspace do
		if CollectionService:HasTag(node, "Breakable") then
			return node
		end
		node = node.Parent
	end
	return nil
end

function WorldDamage.Class(part)
	if part.Transparency > 0.1 and part.Transparency < 1 then
		local name = part.Name:lower()
		for _, word in Settings.GlassNames do
			if name:find(word, 1, true) then
				return "Shatter"
			end
		end
	end
	return Settings.Materials[part.Material.Name]
end

local function loose(props, velocity, className)
	local p = Instance.new(className or "Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Anchored = false
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.CollisionGroup = "Debris"
	p.Parent = workspace
	p.AssemblyLinearVelocity = velocity
	p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 16
	p:SetNetworkOwner(nil)
	task.delay(Settings.DebrisTime * (0.8 + math.random() * 0.4), function()
		if p.Parent then
			local fade = TweenService:Create(p, TweenInfo.new(1), { Transparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			p:Destroy()
		end
	end)
	return p
end

local function throw(dir, scale)
	return dir * Settings.ThrowSpeed * scale * (0.5 + math.random() * 0.7)
		+ Vector3.new((math.random() - 0.5) * 6, 4 + math.random() * 6, (math.random() - 0.5) * 6)
end

local function hide(part)
	part:SetAttribute("Shot", true)
	part:SetAttribute("RestTransparency", part.Transparency)
	part:SetAttribute("RestCollide", part.CanCollide)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	for _, d in part:GetChildren() do
		if d:IsA("Decal") or d:IsA("Texture") then
			d:SetAttribute("RestTransparency", d.Transparency)
			d.Transparency = 1
		end
	end
end

-- The part breaks into a rough grid of pieces (up to MaxPieces) that collapse where it
-- stood; the side the bullet came from gets a shove along the shot.
local function splitApart(part, hitPos, dir)
	local size = part.Size
	local function cutsFor(length)
		return math.clamp(math.floor(length / 1.4 + 0.5), 1, 4)
	end
	local nx, ny, nz = cutsFor(size.X), cutsFor(size.Y), cutsFor(size.Z)
	while nx * ny * nz > Settings.MaxPieces do
		if nx >= ny and nx >= nz then
			nx -= 1
		elseif ny >= nz then
			ny -= 1
		else
			nz -= 1
		end
	end
	if nx * ny * nz < 2 then
		-- Tiny parts still snap in two along their long side.
		if size.X >= size.Y and size.X >= size.Z then
			nx = 2
		elseif size.Y >= size.Z then
			ny = 2
		else
			nz = 2
		end
	end
	local cell = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
	for ix = 1, nx do
		for iy = 1, ny do
			for iz = 1, nz do
				local offset = Vector3.new((ix - 0.5) * cell.X, (iy - 0.5) * cell.Y, (iz - 0.5) * cell.Z) - size / 2
				local cf = part.CFrame * CFrame.new(offset)
				local near = math.clamp(1 - (cf.Position - hitPos).Magnitude / (size.Magnitude * 0.6), 0, 1)
				loose({
					Name = "Chunk",
					-- Slightly smaller and skewed so the pieces read as broken, not sliced.
					Size = cell * Vector3.new(0.82 + math.random() * 0.16, 0.82 + math.random() * 0.16, 0.82 + math.random() * 0.16),
					CFrame = cf * CFrame.Angles((math.random() - 0.5) * 0.3, (math.random() - 0.5) * 0.3, (math.random() - 0.5) * 0.3),
					Color = part.Color,
					Material = part.Material,
					MaterialVariant = part.MaterialVariant,
					Transparency = part.Transparency,
				}, dir * Settings.ThrowSpeed * (0.3 + near) + Vector3.new((math.random() - 0.5) * 3, math.random() * 3, (math.random() - 0.5) * 3))
			end
		end
	end
end

-- Every hit on something breakable knocks a splinter off at the hole, so it visibly wears
-- down before it gives.
local function splinter(part, hitPos, dir)
	local s = 0.18 + math.random() * 0.25
	loose({
		Name = "Chunk",
		Size = Vector3.new(s, s * (0.4 + math.random() * 0.6), s * (1 + math.random())),
		CFrame = CFrame.new(hitPos - dir * 0.2) * CFrame.Angles(math.random() * 6.3, math.random() * 6.3, math.random() * 6.3),
		Color = part.Color,
		Material = part.Material,
		MaterialVariant = part.MaterialVariant,
	}, -dir * (3 + math.random() * 4) + Vector3.new((math.random() - 0.5) * 4, 3 + math.random() * 3, (math.random() - 0.5) * 4))
end

-- Glass bursts into thin shards spread over its face.
local function shatter(part, dir)
	local size = part.Size
	local thin = math.min(size.X, size.Y, size.Z)
	local count = math.random(Settings.Shards.Min, Settings.Shards.Max)
	for _ = 1, count do
		local offset = Vector3.new(
			(math.random() - 0.5) * size.X * 0.9,
			(math.random() - 0.5) * size.Y * 0.9,
			(math.random() - 0.5) * size.Z * 0.9
		)
		-- Wedges read as shards better than slabs.
		loose({
			Name = "Shard",
			Size = Vector3.new(math.max(thin, 0.05), 0.25 + math.random() * 0.7, 0.25 + math.random() * 0.7),
			CFrame = part.CFrame * CFrame.new(offset) * CFrame.Angles(math.random() * 6.3, math.random() * 6.3, math.random() * 6.3),
			Color = part.Color,
			Material = Enum.Material.Glass,
			Transparency = math.max(part.Transparency, 0.3),
			Reflectance = part.Reflectance,
		}, throw(dir, 0.25), "WedgePart")
	end
end

-- Holes ---------------------------------------------------------------------------------

-- A big breakable is cut up only where it's hit: a patch of small cells round the hit, and
-- the rest stays as up to six whole blocks, so the grain only breaks up round the damage.
-- Every piece cut from one original shares a group: { Original, Folder, Total, Left }
-- (Total and Left are volumes, for the collapse).
local groups = {}
local groupOf = {}
local cellOf = {}

local function radiusFor(damage, radius)
	return radius or (0.6 + damage / 100)
end

local function newPiece(group, source, name, cf, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = source.Color
	p.Material = source.Material
	p.MaterialVariant = source.MaterialVariant
	p.Transparency = group.Original:GetAttribute("RestTransparency") or source.Transparency
	p.Reflectance = source.Reflectance
	p.CanCollide = if group.Original:GetAttribute("RestCollide") ~= nil then group.Original:GetAttribute("RestCollide") else source.CanCollide
	p.CastShadow = source.CastShadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = group.Folder
	groupOf[p] = group
	return p
end

local function dropCell(cell, dir, group)
	cellOf[cell] = nil
	groupOf[cell] = nil
	group.Left -= volume(cell)
	cell:SetAttribute("Shot", true)
	cell.Anchored = false
	cell.CanQuery = false
	cell.CanTouch = false
	cell.CollisionGroup = "Debris"
	cell.AssemblyLinearVelocity = dir * Settings.ThrowSpeed * (0.3 + math.random() * 0.5)
		+ Vector3.new((math.random() - 0.5) * 3, math.random() * 2, (math.random() - 0.5) * 3)
	cell.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 10
	cell:SetNetworkOwner(nil)
	cell.Parent = workspace
	task.delay(Settings.DebrisTime * (0.8 + math.random() * 0.4), function()
		if cell.Parent then
			local fade = TweenService:Create(cell, TweenInfo.new(1), { Transparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			cell:Destroy()
		end
	end)
end

-- Cuts `part` round the hit: a cell grid (CellSize, snapped to the part's own grid) over
-- the hit's reach, and whole blocks for the rest. Thin sides are not cut.
local function cutAround(part, hitPos, radius)
	local group = groupOf[part]
	if not group then
		local folder = Instance.new("Folder")
		folder.Name = part.Name .. "_Pieces"
		folder.Parent = part.Parent
		group = { Original = part, Folder = folder, Total = volume(part), Left = volume(part) }
		groups[part] = group
		hide(part)
	end
	local size = part.Size
	local half = size / 2
	local h = part.CFrame:PointToObjectSpace(hitPos)
	local c = Settings.CellSize
	local reach = math.max(radius, c * 0.5)
	local function span(axisSize, axisHit)
		local hs = axisSize / 2
		if axisSize <= c * 1.5 then
			return -hs, hs, 1
		end
		local lo = math.max(math.floor((axisHit - reach + hs) / c) * c - hs, -hs)
		local hi = math.min(math.ceil((axisHit + reach + hs) / c) * c - hs, hs)
		-- No slivers thinner than half a cell left at the edges.
		if lo + hs < c * 0.5 then
			lo = -hs
		end
		if hs - hi < c * 0.5 then
			hi = hs
		end
		return lo, hi, math.max(1, math.floor((hi - lo) / c + 0.5))
	end
	local x0, x1, nx = span(size.X, h.X)
	local y0, y1, ny = span(size.Y, h.Y)
	local z0, z1, nz = span(size.Z, h.Z)

	local function block(from, to)
		local s = to - from
		if s.X > 0.05 and s.Y > 0.05 and s.Z > 0.05 then
			newPiece(group, part, part.Name, part.CFrame * CFrame.new((from + to) / 2), s)
		end
	end
	block(Vector3.new(-half.X, -half.Y, -half.Z), Vector3.new(x0, half.Y, half.Z))
	block(Vector3.new(x1, -half.Y, -half.Z), Vector3.new(half.X, half.Y, half.Z))
	block(Vector3.new(x0, -half.Y, -half.Z), Vector3.new(x1, y0, half.Z))
	block(Vector3.new(x0, y1, -half.Z), Vector3.new(x1, half.Y, half.Z))
	block(Vector3.new(x0, y0, -half.Z), Vector3.new(x1, y1, z0))
	block(Vector3.new(x0, y0, z1), Vector3.new(x1, y1, half.Z))

	local lo = Vector3.new(x0, y0, z0)
	local cell = (Vector3.new(x1, y1, z1) - lo) / Vector3.new(nx, ny, nz)
	for ix = 1, nx do
		for iy = 1, ny do
			for iz = 1, nz do
				local p = newPiece(group, part, "Cell", part.CFrame * CFrame.new(lo + cell * Vector3.new(ix - 0.5, iy - 0.5, iz - 0.5)), cell)
				p:SetAttribute("ShotHealth", Settings.CellHealth)
				cellOf[p] = true
			end
		end
	end

	if part ~= group.Original then
		groupOf[part] = nil
		-- Clients drop the marks on a part once it's Shot.
		part:SetAttribute("Shot", true)
		part:Destroy()
	end
	return group
end

-- A bullet into a cut-up part: every cell near the hit loses health by distance. Once
-- under CollapseShare of the original is left, the rest falls.
local function hurtCells(group, hitPos, dir, damage, radius)
	radius = radiusFor(damage, radius)
	local broke = 0
	for _, cell in group.Folder:GetChildren() do
		if cellOf[cell] then
			local d = (cell.Position - hitPos).Magnitude - cell.Size.Magnitude * 0.25
			if d < radius then
				local health = cell:GetAttribute("ShotHealth") - damage * math.clamp(1 - (d / radius) ^ 2, 0.3, 1)
				cell:SetAttribute("ShotHealth", health)
				if health <= 0 then
					dropCell(cell, dir, group)
					broke += 1
				end
			end
		end
	end
	if broke > 0 then
		SoundKit.Play("World/WoodBreak", { Position = hitPos })
	end
	if group.Left < group.Total * Settings.CollapseShare then
		for _, piece in group.Folder:GetChildren() do
			if groupOf[piece] then
				dropCell(piece, Vector3.new(0, -1, 0), group)
			end
		end
		SoundKit.Play("World/PlankDrop", { Position = hitPos })
	end
end

-- One validated bullet on a world part. Returns the part's class.
function WorldDamage.Hit(part, hitPos, dir, damage, radius)
	local group = groupOf[part]
	if group then
		if not cellOf[part] then
			cutAround(part, hitPos, radiusFor(damage, radius))
		end
		hurtCells(group, hitPos, dir, damage, radius)
		return "Break"
	end
	local class = WorldDamage.Class(part)
	if not part.Anchored and not part:GetAttribute("Shot") then
		-- Loose props get knocked along the shot.
		part:ApplyImpulseAtPosition(dir * damage * Settings.PushPerDamage * math.min(part.AssemblyMass, 8), hitPos)
	end
	local barricade = barricadeOf(part)
	if barricade then
		Barricades.Shoot(barricade, part, hitPos, dir, damage)
		return class
	end
	if not class or class == "Chip" or class == "Dent" then
		return class
	end
	if part:GetAttribute("Shot") or indestructible(part) or volume(part) > Settings.MaxBreakVolume then
		return class
	end
	if class == "Shatter" then
		-- Pieces first: they copy the part's look, which hide() blanks.
		shatter(part, dir)
		hide(part)
		SoundKit.Play("World/GlassBreak", { Position = hitPos })
		return class
	end
	if part.Anchored and volume(part) > Settings.SmallVolume then
		hurtCells(cutAround(part, hitPos, radiusFor(damage, radius)), hitPos, dir, damage, radius)
		return class
	end
	local health = part:GetAttribute("ShotHealth")
		or math.max(Settings.MinHealth, volume(part) * Settings.HealthPerVolume)
	health -= damage
	part:SetAttribute("ShotHealth", health)
	if health > 0 then
		splinter(part, hitPos, dir)
	else
		splitApart(part, hitPos, dir)
		hide(part)
		SoundKit.Play(if part.Material == Enum.Material.Wood or part.Material == Enum.Material.WoodPlanks
			then "World/WoodBreak" else "World/PlankDrop", { Position = hitPos })
	end
	return class
end

-- Puts a broken part back whole.
function WorldDamage.Restore(part)
	local group = groups[part]
	if group then
		groups[part] = nil
		for _, piece in group.Folder:GetChildren() do
			groupOf[piece] = nil
			cellOf[piece] = nil
		end
		group.Folder:Destroy()
	end
	if not part:GetAttribute("Shot") then
		part:SetAttribute("ShotHealth", nil)
		return
	end
	part.Transparency = part:GetAttribute("RestTransparency") or 0
	part.CanCollide = part:GetAttribute("RestCollide") ~= false
	part.CanQuery = true
	part.CanTouch = true
	for _, d in part:GetChildren() do
		if (d:IsA("Decal") or d:IsA("Texture")) and d:GetAttribute("RestTransparency") then
			d.Transparency = d:GetAttribute("RestTransparency")
			d:SetAttribute("RestTransparency", nil)
		end
	end
	for _, key in { "Shot", "ShotHealth", "RestTransparency", "RestCollide" } do
		part:SetAttribute(key, nil)
	end
end

return WorldDamage
