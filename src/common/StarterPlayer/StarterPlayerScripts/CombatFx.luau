-- Client-side world effects for combat: tracers with tails and near-miss whizzes, muzzle
-- light, casings and dropped mags, bullet holes, splatter, hit flash and squash, and the
-- kill burst the server asks for through Remotes.MobFx (wounds and tearing are in Gore).
-- Casings, mags, holes and splatter stay in the world ("the fight leaves a mess") up to a
-- cap, oldest first out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local SoundKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundKit"))
local Options = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Options"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FxFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Fx")
local fxWorld = workspace:WaitForChild("Fx")

local CombatFx = {}

local LIMITS = { Brass = 60, Hole = 80, Splat = 120 }
local SETTLE_TIME = 3
local WHIZ_RADIUS = 6
local HOLE_COLOR = Color3.fromRGB(22, 20, 19)
-- Splatter is green zombie ichor, never red (keeps the maturity rating down).
local SPLAT_DARK = Color3.fromRGB(18, 27, 6)
local SPLAT_RED = Color3.fromRGB(64, 94, 22)
local FLASH_WHITE = Color3.fromRGB(255, 250, 240)

local mess = { Brass = {}, Hole = {}, Splat = {} }

-- Blood and gore off (Options Gore): no blood, drops or splats; hits still puff.
local GORE_FX = { Blood = true, Gore = true, Spurt = true, Drip = true }
local function goreOff()
	return Options.Get("Gore") == false
end

local function keep(kind, instance)
	local list = mess[kind]
	table.insert(list, instance)
	while #list > LIMITS[kind] do
		local oldest = table.remove(list, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	return p
end

local function perpendicular(normal)
	local p = normal:Cross(Vector3.yAxis)
	if p.Magnitude < 0.01 then
		p = normal:Cross(Vector3.xAxis)
	end
	return p.Unit
end

-- Orients an attachment so its +Y (the emitters' direction) points along `dir`.
local function aimCFrame(position, dir)
	local right = dir:Cross(Vector3.zAxis)
	if right.Magnitude < 0.01 then
		right = dir:Cross(Vector3.xAxis)
	end
	right = right.Unit
	return CFrame.fromMatrix(position, right, dir, right:Cross(dir))
end

-- World geometry only: no characters, mobs, effects or the viewmodel.
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.IgnoreWater = true

local function refreshWorldFilter()
	local ignore = { fxWorld, workspace.CurrentCamera }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	for _, enemy in CollectionService:GetTagged("Enemy") do
		table.insert(ignore, enemy)
	end
	worldParams.FilterDescendantsInstances = ignore
end

local function castWorld(origin, vector, keepFilter)
	if not keepFilter then
		refreshWorldFilter()
	end
	local result = workspace:Raycast(origin, vector, worldParams)
	if result and result.Instance.Anchored then
		return result
	end
	return nil
end

CombatFx.CastWorld = castWorld

-- color: optional tint for every emitter (wood dust is brown, glass glints white).
function CombatFx.Emit(name, position, dir, count, color)
	local template = FxFolder:FindFirstChild(name)
	if not template or count <= 0 or (GORE_FX[name] and goreOff()) then
		return
	end
	local a = template:Clone()
	a.Parent = workspace.Terrain
	a.WorldCFrame = aimCFrame(position, dir)
	for _, e in a:GetChildren() do
		if e:IsA("ParticleEmitter") then
			if color then
				e.Color = ColorSequence.new(color)
			end
			e:Emit(count)
		end
	end
	Debris:AddItem(a, 2)
end

-- Tracers ---------------------------------------------------------------------------

local tracers = {}

-- whiz: play a crack-by when the bullet passes close to this client's camera.
function CombatFx.Tracer(from, to, feel, whiz)
	local offset = to - from
	local dist = offset.Magnitude
	if dist < 3 then
		return
	end
	local dir = offset / dist
	local a0 = Instance.new("Attachment")
	local a1 = Instance.new("Attachment")
	a0.Parent = workspace.Terrain
	a1.Parent = workspace.Terrain
	a0.WorldPosition = from
	a1.WorldPosition = from
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = feel.TracerWidth * 0.25
	beam.Width1 = feel.TracerWidth
	beam.Color = ColorSequence.new(feel.TracerColor)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.7, 0.55),
		NumberSequenceKeypoint.new(1, 0),
	})
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = a0
	table.insert(tracers, {
		From = from,
		Dir = dir,
		Dist = dist,
		Len = feel.TracerLength,
		Speed = feel.TracerSpeed,
		Start = os.clock(),
		A0 = a0,
		A1 = a1,
	})

	if whiz then
		local camPos = workspace.CurrentCamera.CFrame.Position
		local along = math.clamp((camPos - from):Dot(dir), 0, dist)
		local closest = from + dir * along
		if along > 4 and (camPos - closest).Magnitude < WHIZ_RADIUS then
			task.delay(along / feel.TracerSpeed, function()
				SoundKit.Play("Common/Whiz", { Position = closest })
			end)
		end
	end
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for i = #tracers, 1, -1 do
		local t = tracers[i]
		local travelled = (now - t.Start) * t.Speed
		if travelled - t.Len >= t.Dist then
			t.A0:Destroy()
			t.A1:Destroy()
			table.remove(tracers, i)
		else
			t.A1.WorldPosition = t.From + t.Dir * math.min(travelled, t.Dist)
			t.A0.WorldPosition = t.From + t.Dir * math.clamp(travelled - t.Len, 0, t.Dist)
		end
	end
end)

-- Muzzle -------------------------------------------------------------------------------

local lightHolder = Instance.new("Attachment")
lightHolder.Name = "MuzzleLight"
lightHolder.Parent = workspace.Terrain
local muzzleLight = Instance.new("PointLight")
muzzleLight.Color = Color3.fromRGB(255, 190, 120)
muzzleLight.Shadows = false
muzzleLight.Brightness = 0
muzzleLight.Parent = lightHolder
local lightOffAt = 0

-- Lights the walls around the shooter for a frame or two.
function CombatFx.MuzzleLight(position, feel)
	lightHolder.WorldPosition = position
	muzzleLight.Brightness = feel.LightBrightness
	muzzleLight.Range = feel.LightRange
	lightOffAt = os.clock() + feel.FlashTime
end

RunService.Heartbeat:Connect(function()
	if muzzleLight.Brightness > 0 and os.clock() > lightOffAt then
		muzzleLight.Brightness = 0
	end
end)

-- Brass and mags ---------------------------------------------------------------------

local function dropPhysical(part, velocity, spin, landCue)
	part.Anchored = false
	part.CanCollide = true
	part.CanTouch = true
	part.CollisionGroup = "Debris"
	part.Parent = fxWorld
	part.AssemblyLinearVelocity = velocity
	part.AssemblyAngularVelocity = spin
	local landed = false
	local conn
	conn = part.Touched:Connect(function()
		if landed then
			return
		end
		landed = true
		conn:Disconnect()
		SoundKit.Play(landCue, { Position = part.Position })
	end)
	task.delay(SETTLE_TIME, function()
		if conn.Connected then
			conn:Disconnect()
		end
		if part.Parent then
			part.Anchored = true
			part.CanTouch = false
		end
	end)
	keep("Brass", part)
end

function CombatFx.Casing(position, cameraCF, carrierVelocity, feel)
	local e = feel.CasingEject
	local jitter = 0.8 + math.random() * 0.4
	local velocity = (cameraCF.RightVector * e.X + cameraCF.UpVector * e.Y + cameraCF.LookVector * e.Z) * jitter
		+ carrierVelocity
	local casing = newPart({
		Name = "Casing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(feel.CasingSize.Z, feel.CasingSize.X, feel.CasingSize.Y),
		Color = feel.CasingColor,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
		CFrame = cameraCF.Rotation + position,
	})
	local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 40
	dropPhysical(casing, velocity, spin, "Common/Casing")
end

-- The old magazine falls out of the viewmodel and stays on the floor: a copy of the gun's
-- own mag model, grown from viewmodel size to world size.
local MAG_WORLD_SCALE = 1.6

function CombatFx.DroppedMag(magPart, carrierVelocity)
	local mag = magPart:Clone()
	for _, child in mag:GetChildren() do
		if child:IsA("SpecialMesh") then
			child.Scale *= MAG_WORLD_SCALE
		elseif not (child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture")) then
			child:Destroy()
		end
	end
	mag.Name = "Mag"
	mag.Size = magPart.Size * MAG_WORLD_SCALE
	mag.CFrame = magPart.CFrame
	mag.Transparency = 0
	mag.LocalTransparencyModifier = 0
	mag.CastShadow = true
	mag.Massless = false
	mag.CanQuery = false
	dropPhysical(mag, carrierVelocity + Vector3.new(0, -5, 0), Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 6, "Common/MagDrop")
end

-- Surface marks ------------------------------------------------------------------------

local function disc(cf, diameter, color, kind)
	local p = newPart({
		Name = kind,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.02, diameter, diameter),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CFrame = cf,
	})
	p.Parent = fxWorld
	keep(kind, p)
	return p
end

function CombatFx.BulletHole(result)
	if not result.Instance.Anchored then
		return
	end
	local n = result.Normal
	local cf = CFrame.fromMatrix(result.Position + n * 0.012, n, perpendicular(n))
	disc(cf, 0.16 + math.random() * 0.1, HOLE_COLOR, "Hole")
end

-- What a bullet leaves on the world, by material class (GameConfig.WorldDamage): stone
-- chips with a dark hole and grey dust, metal dents bright with sparks, wood splinters with
-- brown dust, glass glints (the server breaks it). Marks on a part that later breaks go
-- with it.
local WORLD_DAMAGE = require(ReplicatedStorage.Shared.GameConfig).WorldDamage

local function worldClass(part)
	if part.Transparency > 0.1 and part.Transparency < 1 then
		local name = part.Name:lower()
		for _, word in WORLD_DAMAGE.GlassNames do
			if name:find(word, 1, true) then
				return "Shatter"
			end
		end
	end
	return WORLD_DAMAGE.Materials[part.Material.Name]
end
-- A dent is a bright scuffed ring round a small dark pit, so it reads on any metal.
local DENT_RING = Color3.fromRGB(196, 198, 202)
local DENT_PIT = Color3.fromRGB(40, 40, 44)
local WOOD_HOLE = Color3.fromRGB(44, 30, 18)
local WOOD_DUST = Color3.fromRGB(150, 112, 72)
local marksOn = setmetatable({}, { __mode = "k" })

local function markOn(part, mark)
	local list = marksOn[part]
	if not list then
		list = {}
		marksOn[part] = list
		part:GetAttributeChangedSignal("Shot"):Connect(function()
			if part:GetAttribute("Shot") then
				for _, m in list do
					m:Destroy()
				end
				table.clear(list)
			end
		end)
	end
	table.insert(list, mark)
end

function CombatFx.WorldImpact(result, light)
	local part, pos, n = result.Instance, result.Position, result.Normal
	local class = worldClass(part)
	local few = if light then 1 else 3
	if class == "Shatter" then
		CombatFx.Emit("Spark", pos, n, few + 2, Color3.fromRGB(220, 235, 240))
		return
	end
	if not part.Anchored then
		CombatFx.Emit("Dust", pos, n, few, if class == "Break" then WOOD_DUST else nil)
		return
	end
	local cf = CFrame.fromMatrix(pos + n * 0.012, n, perpendicular(n))
	local mark
	if class == "Dent" then
		CombatFx.Emit("Spark", pos, n, if light then 4 else 9)
		markOn(part, disc(cf * CFrame.new(0.004, 0, 0), 0.07 + math.random() * 0.03, DENT_PIT, "Hole"))
		mark = disc(cf, 0.2 + math.random() * 0.08, DENT_RING, "Hole")
	elseif class == "Break" then
		CombatFx.Emit("Dust", pos, n, few + 1, WOOD_DUST)
		mark = disc(cf, 0.18 + math.random() * 0.1, WOOD_HOLE, "Hole")
	elseif class == "Chip" then
		CombatFx.Emit("Dust", pos, n, few + 2)
		CombatFx.Emit("Spark", pos, n, few)
		mark = disc(cf, 0.22 + math.random() * 0.12, HOLE_COLOR, "Hole")
	else
		CombatFx.Emit("Spark", pos, n, if light then 3 else 7)
		CombatFx.Emit("Dust", pos, n, few)
		mark = disc(cf, 0.16 + math.random() * 0.1, HOLE_COLOR, "Hole")
	end
	markOn(part, mark)
end

-- A stylized dark green splat: one blob plus a few drops around it.
function CombatFx.Splat(position, normal, scale)
	if goreOff() then
		return
	end
	local base = CFrame.fromMatrix(position + normal * 0.014, normal, perpendicular(normal))
		* CFrame.Angles(math.random() * math.pi * 2, 0, 0)
	local size = (0.7 + math.random() * 0.8) * scale
	disc(base, size, SPLAT_DARK:Lerp(SPLAT_RED, math.random() * 0.6), "Splat")
	for i = 1, math.random(1, 3) do
		local spread = size * 0.9
		local drop = base
			* CFrame.new(0.002 * i, (math.random() - 0.5) * 2 * spread, (math.random() - 0.5) * 2 * spread)
		disc(drop, size * (0.12 + math.random() * 0.22), SPLAT_DARK:Lerp(SPLAT_RED, math.random()), "Splat")
	end
end

local function splatOnWorld(origin, vector, scale, chance)
	if math.random() > chance then
		return
	end
	local result = castWorld(origin, vector, false)
	if result then
		CombatFx.Splat(result.Position, result.Normal, scale)
	end
end

-- Blood drops ----------------------------------------------------------------------------
-- Real drops, after Blood Engine's approach (rotntake/BloodEngine): each one flies its own
-- arc, stretched along its speed, and where it lands it leaves a pool or grows the pool
-- already there. Drops on walls run down a little. Pools stay ("the fight leaves a mess").

local DROP_LIMIT = 180
local DROP_LIFE = 3
local DROP_DRAG = 0.6
local POOL_MAX = 2.6
local POOL_THICK = 0.02
local BLOOD_DEFAULT = Color3.fromRGB(70, 104, 24)
local POOL_GROW = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RUN_GROW = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local drops = {}
local pools = {}
local poolLayer = 0
local dropRng = Random.new()

local function spreadDir(dir, degrees)
	local right = perpendicular(dir)
	local up = dir:Cross(right)
	local a = dropRng:NextNumber(0, math.pi * 2)
	local r = math.tan(math.rad(degrees)) * math.sqrt(dropRng:NextNumber())
	return (dir + right * math.cos(a) * r + up * math.sin(a) * r).Unit
end

-- A thin streak of blood running down a wall from where a drop hit it.
local function wallRun(position, normal, color, width)
	local down = Vector3.new(0, -1, 0) - normal * -normal.Y
	if down.Magnitude < 0.3 then
		return
	end
	down = down.Unit
	local length = dropRng:NextNumber(0.25, 0.9)
	local top = position + normal * 0.013
	local run = newPart({
		Name = "Run",
		Size = Vector3.new(0.01, 0.01, width),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.04,
		CFrame = CFrame.fromMatrix(top, normal, -down),
	})
	run.Parent = fxWorld
	keep("Splat", run)
	local grown = CFrame.fromMatrix(top + down * length / 2, normal, -down)
	TweenService:Create(run, RUN_GROW, { Size = Vector3.new(0.01, length, width * 0.7), CFrame = grown }):Play()
end

local function landDrop(d, hit)
	local n = hit.Normal
	local pos = hit.Position
	for i = #pools, 1, -1 do
		local pool = pools[i]
		if not pool.Part.Parent then
			table.remove(pools, i)
		elseif pool.Normal:Dot(n) > 0.9 and (pool.Center - pos).Magnitude < pool.Size * 0.5 + 0.3 then
			if pool.Size < POOL_MAX then
				pool.Size = math.min(POOL_MAX, pool.Size + d.Size * 0.8)
				TweenService:Create(pool.Part, POOL_GROW, { Size = Vector3.new(POOL_THICK, pool.Size, pool.Size) }):Play()
			end
			return
		end
	end
	-- A new pool: a blob with a couple of smaller drops beside it so it isn't a perfect disc.
	poolLayer = (poolLayer + 1) % 10
	local size = d.Size * dropRng:NextNumber(2.4, 3.6)
	local cf = CFrame.fromMatrix(pos + n * (0.012 + poolLayer * 0.0015), n, perpendicular(n))
		* CFrame.Angles(dropRng:NextNumber(0, math.pi * 2), 0, 0)
	local color = d.Color:Lerp(SPLAT_DARK, dropRng:NextNumber(0, 0.45))
	local pool = newPart({
		Name = "Pool",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(POOL_THICK, size * 0.3, size * 0.3),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.04,
		CFrame = cf,
	})
	for _ = 1, dropRng:NextInteger(0, 2) do
		local s = size * dropRng:NextNumber(0.2, 0.45)
		local off = size * dropRng:NextNumber(0.4, 0.7)
		local a = dropRng:NextNumber(0, math.pi * 2)
		local bit = newPart({
			Name = "PoolDrop",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(POOL_THICK, s, s),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.04,
			CFrame = cf * CFrame.new(-0.001, math.cos(a) * off, math.sin(a) * off),
		})
		bit.Parent = pool
	end
	pool.Parent = fxWorld
	keep("Splat", pool)
	TweenService:Create(pool, POOL_GROW, { Size = Vector3.new(POOL_THICK, size, size) }):Play()
	table.insert(pools, { Part = pool, Normal = n, Center = pos, Size = size })
	if n.Y < 0.5 and dropRng:NextNumber() < 0.7 then
		wallRun(pos, n, color, size * 0.35)
	end
end

-- Throws real drops. opts: Color, Speed (NumberRange), Spread (degrees), Size (NumberRange).
function CombatFx.BloodDrops(position, dir, count, opts)
	if goreOff() then
		return
	end
	opts = opts or {}
	local color = opts.Color or BLOOD_DEFAULT
	local speed = opts.Speed or NumberRange.new(6, 16)
	local sizes = opts.Size or NumberRange.new(0.05, 0.12)
	local spread = opts.Spread or 25
	local now = os.clock()
	for _ = 1, count do
		if #drops >= DROP_LIMIT then
			table.remove(drops, 1).Part:Destroy()
		end
		local size = dropRng:NextNumber(sizes.Min, sizes.Max)
		local p = newPart({
			Name = "Drop",
			Size = Vector3.new(size, size, size),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.06,
			CFrame = CFrame.new(position),
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.Parent = fxWorld
		table.insert(drops, {
			Part = p,
			Mesh = mesh,
			Pos = position,
			Vel = spreadDir(dir, spread) * dropRng:NextNumber(speed.Min, speed.Max),
			Size = size,
			Color = color,
			Born = now,
		})
	end
end

local dropParts, dropFrames = {}, {}
RunService.Heartbeat:Connect(function(dt)
	if #drops == 0 then
		return
	end
	refreshWorldFilter()
	table.clear(dropParts)
	table.clear(dropFrames)
	local gravity = Vector3.new(0, -workspace.Gravity, 0)
	local now = os.clock()
	for i = #drops, 1, -1 do
		local d = drops[i]
		local vel = (d.Vel + gravity * dt) * (1 - DROP_DRAG * dt)
		local move = (d.Vel + vel) * 0.5 * dt
		local hit = castWorld(d.Pos, move, true)
		if hit or now - d.Born > DROP_LIFE or not d.Part.Parent then
			if hit then
				landDrop(d, hit)
			end
			d.Part:Destroy()
			table.remove(drops, i)
		else
			d.Pos += move
			d.Vel = vel
			local speed = vel.Magnitude
			d.Mesh.Scale = Vector3.new(1, 1, math.clamp(1 + speed * 0.06, 1, 2.6))
			table.insert(dropParts, d.Part)
			table.insert(dropFrames, if speed > 0.1 then CFrame.lookAt(d.Pos, d.Pos + vel) else CFrame.new(d.Pos))
		end
	end
	workspace:BulkMoveTo(dropParts, dropFrames, Enum.BulkMoveMode.FireCFrameChanged)
end)

-- Blood for a bullet entering a body: a fine mist and a spray of drops out along the shot,
-- a puff and a few drops back toward the shooter. The drops make the pools.
function CombatFx.BloodHit(position, normal, dir, color)
	CombatFx.Emit("Blood", position, dir, 5)
	CombatFx.Emit("HitPuff", position, normal, 4)
	CombatFx.BloodDrops(position, dir, math.random(5, 9), { Color = color, Speed = NumberRange.new(7, 19), Spread = 24 })
	CombatFx.BloodDrops(position, normal, math.random(2, 3), { Color = color, Speed = NumberRange.new(2, 7), Spread = 45 })
end

-- Mob feedback ---------------------------------------------------------------------------

function CombatFx.FlashEnemy(model)
	local h = model:FindFirstChild("_HitFlash")
	if not h then
		h = Instance.new("Highlight")
		h.Name = "_HitFlash"
		h.FillColor = FLASH_WHITE
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
	end
	h.FillTransparency = 0.1
	TweenService:Create(h, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1 }):Play()
end

local restSize = setmetatable({}, { __mode = "k" })

-- Squashes the part that was hit for a split second (punch step 3). A part drawn by its
-- dentable copy (Dents) squashes the copy.
function CombatFx.Squash(part, amount)
	part = part:FindFirstChild("_Flesh") or part
	local size = restSize[part] or part.Size
	restSize[part] = size
	local bulge = 1 + (1 - amount) * 0.6
	part.Size = size * Vector3.new(bulge, amount, bulge)
	TweenService:Create(part, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = size }):Play()
end

Remotes:WaitForChild("MobFx").OnClientEvent:Connect(function(kind, _part, _local, position, dir)
	if typeof(position) ~= "Vector3" or typeof(dir) ~= "Vector3" then
		return
	end
	if kind == "Kill" then
		CombatFx.Emit("Gore", position, dir, 14)
		CombatFx.BloodDrops(position, dir, 10, { Speed = NumberRange.new(8, 20), Spread = 35 })
		splatOnWorld(position, Vector3.new(0, -10, 0), 1.3, 1)
		splatOnWorld(position, dir * 10, 1, 0.8)
	end
end)

return CombatFx
