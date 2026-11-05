-- Dents: a bullet pushes the flesh in where it lands, so a wound sits in a real crater.
-- The struck body part gets a soft copy built as an EditableMesh (the DevForum's vertex-push
-- method): a finely divided box for block parts, or the part's own mesh when this game owns
-- it (Roblox only lets a game edit meshes it owns or that are shared with it). The copy is
-- drawn in the part's place and the vertices round a hit are pushed in along the surface
-- and the shot.
-- Roblox allows a client only a handful of editable meshes (about 8), so copies live in a
-- small pool: the parts being shot right now get one, and the part shot longest ago gives
-- its copy back (its dents flatten; Dents.Released tells Gore to lift its wounds out).

local AssetService = game:GetService("AssetService")

local Dents = {}

-- Most soft copies alive at once. Shrinks by itself if the device allows fewer.
local POOL = 6
-- After Roblox refuses a mesh, wait this long before asking again (s).
local REFUSED_WAIT = 4
-- Target vertex spacing on block faces (studs), and the most cuts per edge.
local GRID = 0.15
local MAX_CUTS = 20
-- Parts thinner than this (eyes, trim) are left alone, as is the invisible root.
local MIN_SIZE = 0.4
-- One dent: reach and depth at its centre (studs).
local RADIUS = 0.3
local DEPTH = 0.14
-- No point sinks further than this in total, or a third of the part's thickness.
local MAX_DEPTH = 0.3
-- Share of the push that follows the bullet instead of going straight into the surface.
local ALONG_SHOT = 0.35

-- Called with a part whose copy was given back (its dents are gone). Set by Gore.
Dents.Released = nil

local rng = Random.new()
local poolSize = POOL
local refusedUntil = 0
-- part -> soft copy; { Building = true, Pending = {...} } while it's being made;
-- false when the part can never have one.
local soft = setmetatable({}, { __mode = "k" })
-- Parts holding (or building) a copy, least recently shot first.
local order = {}

-- One face of a box: a grid of vertices from origin along u and v, facing u x v.
local function addGrid(em, origin, u, v, nu, nv, ids, rest)
	local row = nu + 1
	local grid = {}
	for j = 0, nv do
		for i = 0, nu do
			local p = origin + u * (i / nu) + v * (j / nv)
			local id = em:AddVertex(p)
			grid[j * row + i] = id
			table.insert(ids, id)
			rest[id] = p
		end
	end
	for j = 0, nv - 1 do
		for i = 0, nu - 1 do
			local a = grid[j * row + i]
			local b = grid[j * row + i + 1]
			local c = grid[(j + 1) * row + i]
			local d = grid[(j + 1) * row + i + 1]
			em:AddTriangle(a, b, c)
			em:AddTriangle(b, d, c)
		end
	end
end

local function cuts(length)
	return math.clamp(math.round(length / GRID), 2, MAX_CUTS)
end

local function buildBox(em, size)
	local ids, rest = {}, {}
	local h = size / 2
	local X, Y, Z = Vector3.new(size.X, 0, 0), Vector3.new(0, size.Y, 0), Vector3.new(0, 0, size.Z)
	local nx, ny, nz = cuts(size.X), cuts(size.Y), cuts(size.Z)
	addGrid(em, Vector3.new(h.X, -h.Y, -h.Z), Y, Z, ny, nz, ids, rest) -- +X
	addGrid(em, Vector3.new(-h.X, -h.Y, -h.Z), Z, Y, nz, ny, ids, rest) -- -X
	addGrid(em, Vector3.new(-h.X, h.Y, -h.Z), Z, X, nz, nx, ids, rest) -- +Y
	addGrid(em, Vector3.new(-h.X, -h.Y, -h.Z), X, Z, nx, nz, ids, rest) -- -Y
	addGrid(em, Vector3.new(-h.X, -h.Y, h.Z), X, Y, nx, ny, ids, rest) -- +Z
	addGrid(em, Vector3.new(-h.X, -h.Y, -h.Z), Y, X, ny, nx, ids, rest) -- -Z
	return ids, rest
end

local function wearsClothes(model)
	return model ~= nil and (model:FindFirstChildOfClass("Shirt") or model:FindFirstChildOfClass("Pants")) ~= nil
end

local function canSoften(part)
	local model = part.Parent
	return part:IsA("BasePart")
		and part.Transparency < 1
		and math.min(part.Size.X, part.Size.Y, part.Size.Z) >= MIN_SIZE
		and not (model and model:IsA("Model") and model.PrimaryPart == part)
		and part.Name ~= "_Flesh"
		and ((part:IsA("Part") and part.Shape == Enum.PartType.Block) or part:IsA("MeshPart"))
		-- A box copy would replace a custom mesh (a SpecialMesh head) with a plain block.
		and not part:FindFirstChildWhichIsA("DataModelMesh")
		-- Shirts and pants are painted onto the body parts themselves; a copy would be bare.
		and not (part:IsA("MeshPart") and wearsClothes(model))
end

local function release(part)
	local s = soft[part]
	soft[part] = nil
	local i = table.find(order, part)
	if i then
		table.remove(order, i)
	end
	if type(s) ~= "table" then
		return
	end
	if s.Building then
		-- Hits waiting on this copy get flat wounds.
		for _, hit in s.Pending do
			local cf = part.CFrame
			hit.Done(0, cf * hit.Pos, cf:VectorToWorldSpace(hit.Normal))
		end
		return
	end
	s.Changed:Disconnect()
	s.Copy:Destroy()
	s.Mesh:Destroy()
	if part.Parent then
		part.LocalTransparencyModifier = 0
	end
	if Dents.Released then
		Dents.Released(part)
	end
end

-- Pushes one crater into a built copy. Inputs are world space. Returns the depth reached.
local function push(s, part, hitPos, normal, dir)
	local cf = part.CFrame
	-- Work in part space (studs), then map each move back to mesh space.
	local center = cf:PointToObjectSpace(hitPos)
	local way = (-cf:VectorToObjectSpace(normal) * (1 - ALONG_SHOT) + cf:VectorToObjectSpace(dir) * ALONG_SHOT).Unit
	local radius = RADIUS * rng:NextNumber(0.85, 1.2)
	local depth = DEPTH * rng:NextNumber(0.8, 1.25)
	local scale, origin, em = s.Scale, s.Center, s.Mesh
	local deepest = 0
	for _, id in s.Ids do
		local partPos = (s.Now[id] - origin) * scale
		local t = (partPos - center).Magnitude / radius
		if t < 1 then
			local f = (1 - t * t) ^ 2
			local rest = (s.Rest[id] - origin) * scale
			local moved = partPos + way * depth * f
			local off = moved - rest
			if off.Magnitude > s.Max then
				moved = rest + off.Unit * s.Max
			end
			deepest = math.max(deepest, (moved - rest).Magnitude)
			local meshPos = origin + moved / scale
			s.Now[id] = meshPos
			em:SetPosition(id, meshPos)
		end
	end
	return deepest
end

-- Runs a hit queued while the copy was being built (it was stored in the part's space).
local function runPending(part, s, hit)
	local cf = part.CFrame
	local hitPos, normal, dir = cf * hit.Pos, cf:VectorToWorldSpace(hit.Normal), cf:VectorToWorldSpace(hit.Dir)
	local depth = if s then push(s, part, hitPos, normal, dir) else 0
	hit.Done(depth, hitPos, normal)
end

local function build(part)
	local marker = soft[part]
	local function fail(never)
		soft[part] = if never then false else nil
		local i = table.find(order, part)
		if i then
			table.remove(order, i)
		end
		for _, hit in marker.Pending do
			runPending(part, nil, hit)
		end
	end

	local em, ids, rest
	if part:IsA("MeshPart") then
		local ok, result = pcall(AssetService.CreateEditableMeshAsync, AssetService, part.MeshContent, { FixedSize = true })
		if not ok then
			-- Not ours to edit: this part keeps flat wounds.
			fail(true)
			return
		elseif not result then
			poolSize = math.max(1, #order - 1)
			refusedUntil = os.clock() + REFUSED_WAIT
			fail(false)
			return
		end
		em = result
		ids, rest = em:GetVertices(), {}
		for _, id in ids do
			rest[id] = em:GetPosition(id)
		end
	else
		em = AssetService:CreateEditableMesh()
		if not em then
			-- Out of budget: use fewer copies from now on and try again later.
			poolSize = math.max(1, #order - 1)
			refusedUntil = os.clock() + REFUSED_WAIT
			fail(false)
			return
		end
		ids, rest = buildBox(em, marker.Size)
	end

	local ok, copy = pcall(AssetService.CreateMeshPartAsync, AssetService, Content.fromObject(em))
	if not ok or not part.Parent or soft[part] ~= marker then
		em:Destroy()
		if soft[part] == marker then
			fail(false)
		end
		return
	end
	copy.Name = "_Flesh"
	-- The size the part had when it was shot, before the hit squash (CombatFx.Squash).
	local size = marker.Size
	copy.Size = size
	copy.CFrame = part.CFrame
	copy.Color = part.Color
	copy.Material = part.Material
	copy.MaterialVariant = part.MaterialVariant
	copy.Reflectance = part.Reflectance
	copy.Transparency = part.Transparency
	copy.CastShadow = part.CastShadow
	copy.Anchored = false
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Massless = true
	if part:IsA("MeshPart") then
		copy.TextureContent = part.TextureContent
		local look = part:FindFirstChildOfClass("SurfaceAppearance")
		if look then
			look:Clone().Parent = copy
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = copy
	weld.Parent = copy
	copy.Parent = part
	part.LocalTransparencyModifier = 1

	local meshSize = em:GetSize()
	local s = {
		Mesh = em,
		Copy = copy,
		Ids = ids,
		Rest = rest,
		Now = table.clone(rest),
		-- Mesh space to part space, per axis.
		Scale = Vector3.new(size.X / meshSize.X, size.Y / meshSize.Y, size.Z / meshSize.Z),
		Center = em:GetCenter(),
		Max = math.min(MAX_DEPTH, math.min(size.X, size.Y, size.Z) / 3),
		-- The corpse fade and anything else that hides the part hides the copy too.
		Changed = part:GetPropertyChangedSignal("Transparency"):Connect(function()
			copy.Transparency = part.Transparency
		end),
	}
	soft[part] = s
	part.Destroying:Once(function()
		release(part)
	end)
	for _, hit in marker.Pending do
		runPending(part, s, hit)
	end
end

-- Pushes a crater in where a bullet struck, then calls done(depth, hitPos, normal) with
-- how deep the centre went (0 when the part can't dent) and where the hit now is (the part
-- may have moved while its copy was being made, which takes a frame or two).
function Dents.Dent(part, hitPos, normal, dir, done)
	local s = soft[part]
	if s == false or (s == nil and (not canSoften(part) or os.clock() < refusedUntil)) then
		if s == nil and not canSoften(part) then
			soft[part] = false
		end
		done(0, hitPos, normal)
		return
	end

	local i = table.find(order, part)
	if i then
		table.remove(order, i)
	end
	table.insert(order, part)

	if s == nil then
		-- Make room, then build. The hit waits in the part's own space.
		while #order > poolSize do
			release(order[1])
		end
		local cf = part.CFrame
		soft[part] = {
			Building = true,
			Size = part.Size,
			Pending = { { Pos = cf:PointToObjectSpace(hitPos), Normal = cf:VectorToObjectSpace(normal), Dir = cf:VectorToObjectSpace(dir), Done = done } },
		}
		task.spawn(build, part)
	elseif s.Building then
		local cf = part.CFrame
		table.insert(s.Pending, { Pos = cf:PointToObjectSpace(hitPos), Normal = cf:VectorToObjectSpace(normal), Dir = cf:VectorToObjectSpace(dir), Done = done })
	else
		done(push(s, part, hitPos, normal, dir), hitPos, normal)
	end
end

return Dents
