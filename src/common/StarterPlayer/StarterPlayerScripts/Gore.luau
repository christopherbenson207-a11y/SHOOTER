-- Visible damage on mobs, drawn on each client.
--   Shot: one bullet landing on a mob: the instant kick (MobImpact), a crater pushed into
--   the flesh (Dents), the wound in it and the blood. GunClient calls it the moment it fires.
--   Wound: a hole with a torn rim where the shot went in, blood running down from it and
--   drops falling from it (the drops pool on the floor).
--   Loosen: a limb about to come off hangs open at the joint, held by a few flesh strands.
--   Tear: flesh holds the limb a moment while strands stretch and snap one by one; both
--   torn ends get a ragged meat face with torn skin and bone; the stump spurts in time
--   with a heartbeat, then drips; the flying limb trails blood, chunks scatter, and a splat
--   marks where the limb lands.
--   Pop: a head bursting (sniper headshots): chunks, a cloud of blood, splatter on whatever
--   is behind, and a torn neck that spurts.
--   Burst: a point-blank shotgun kill bursting the torso open, splattering the room.
-- Colours and counts come from the mob's GameConfig.Mobs[...].Gore. Server events arrive
-- on Remotes.MobFx; the shooter's own hits are predicted by GunClient.
-- With blood and gore off (Options Gore) none of it is drawn: no wounds, torn faces, strands,
-- spurts or chunks (CombatFx drops the blood); the kick, dents and sounds stay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Options = require(Shared:WaitForChild("Options"))
local SoundKit = require(Shared:WaitForChild("SoundKit"))
local CombatFx = require(script.Parent:WaitForChild("CombatFx"))
local MobImpact = require(script.Parent:WaitForChild("MobImpact"))
local Dents = require(script.Parent:WaitForChild("Dents"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FxFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Fx")
local fxWorld = workspace:WaitForChild("Fx")

local Gore = {}

local CHUNK_LIMIT = 50
local DRIP_LIMIT = 12
local TEAR_STRAND_LIFE = 1.6

local rng = Random.new()
local wounds = setmetatable({}, { __mode = "k" })
local strands = {}
local chunks = {}
local drips = 0

local function mobConfig(mobType)
	return GameConfig.Mobs[mobType or ""]
end

local function goreOff()
	return Options.Get("Gore") == false
end

local function mobOf(part)
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("MobType") then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- 0 = raw flesh, 1 = dark blood.
local function shade(cfg, t)
	return cfg.FleshColor:Lerp(cfg.BloodColor, t)
end

local function perpendicular(v)
	local p = v:Cross(Vector3.yAxis)
	if p.Magnitude < 0.01 then
		p = v:Cross(Vector3.xAxis)
	end
	return p.Unit
end

-- X axis along normal (Roblox cylinders run along X), spun about it.
local function alongX(position, normal, spin)
	return CFrame.fromMatrix(position, normal, perpendicular(normal)) * CFrame.Angles(spin or 0, 0, 0)
end

-- +Y along dir, which is the way particle emitters fire.
local function aimY(position, dir)
	local right = perpendicular(dir)
	return CFrame.fromMatrix(position, right, dir, right:Cross(dir))
end

-- Where a line from the part's centre toward `toward` leaves its box, and that face's
-- outward normal. Joints can sit inside a part (or past its edge), torn flesh can't.
local function surfaceToward(part, toward)
	local cf = part.CFrame
	local dir = toward - cf.Position
	dir = if dir.Magnitude > 1e-3 then dir.Unit else cf.UpVector
	local l = cf:VectorToObjectSpace(dir)
	local h = part.Size / 2
	local t, face = math.huge, Vector3.yAxis
	for _, axis in { "X", "Y", "Z" } do
		local c = math.abs(l[axis])
		if c > 1e-4 and h[axis] / c < t then
			t = h[axis] / c
			face = Vector3.FromAxis(Enum.Axis[axis]) * math.sign(l[axis])
		end
	end
	return cf.Position + dir * t, cf:VectorToWorldSpace(face)
end

local function randomInDisc(normal, radius)
	local u = perpendicular(normal)
	local v = normal:Cross(u)
	local a = rng:NextNumber(0, math.pi * 2)
	local r = radius * math.sqrt(rng:NextNumber())
	return u * math.cos(a) * r + v * math.sin(a) * r
end

-- A render-only piece of gore stuck to a body part (moves with it, even after it flies off).
local function stuck(host, props)
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = host
	weld.Part1 = p
	weld.Parent = p
	p.Parent = host
	return p
end

local function cloneEmitter(fxName, host, cframe, color)
	local a = FxFolder[fxName]:Clone()
	a.Parent = host
	a.WorldCFrame = cframe
	local e = a:FindFirstChildOfClass("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	return a, e
end

-- Strands -------------------------------------------------------------------------------

-- A strip of flesh between two attachments. It thins as it stretches and snaps past
-- breakLength, spitting a few drops. maxAge (optional) snaps it regardless.
local function addStrand(a0, a1, cfg, breakLength, width, maxAge)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, cfg.FleshColor),
		ColorSequenceKeypoint.new(0.5, cfg.BloodColor),
		ColorSequenceKeypoint.new(1, shade(cfg, 0.3)),
	})
	beam.Transparency = NumberSequence.new(0)
	beam.Width0 = width
	beam.Width1 = width * rng:NextNumber(0.5, 0.9)
	beam.CurveSize0 = rng:NextNumber(-0.35, 0.35)
	beam.CurveSize1 = rng:NextNumber(-0.35, 0.35)
	beam.Segments = 10
	beam.FaceCamera = true
	beam.LightInfluence = 1
	beam.Parent = a0
	table.insert(strands, {
		Beam = beam,
		A0 = a0,
		A1 = a1,
		Break = breakLength,
		Width = width,
		Born = os.clock(),
		MaxAge = maxAge,
	})
end

local function strandBetween(partA, pointA, partB, pointB, cfg, breakLength, width, maxAge)
	if goreOff() then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "Strand"
	a0.Parent = partA
	a0.WorldPosition = pointA
	local a1 = Instance.new("Attachment")
	a1.Name = "Strand"
	a1.Parent = partB
	a1.WorldPosition = pointB
	addStrand(a0, a1, cfg, breakLength, width, maxAge)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for i = #strands, 1, -1 do
		local s = strands[i]
		local alive = s.A0.Parent ~= nil and s.A1.Parent ~= nil
		local from, to = s.A0.WorldPosition, s.A1.WorldPosition
		local length = if alive then (to - from).Magnitude else math.huge
		if length > s.Break or (s.MaxAge and now - s.Born > s.MaxAge) then
			if alive then
				local dir = if length > 1e-3 and length < math.huge then (to - from).Unit else Vector3.yAxis
				CombatFx.Emit("Blood", from:Lerp(to, 0.5), dir, 4)
			end
			s.A0:Destroy()
			s.A1:Destroy()
			table.remove(strands, i)
		else
			local thin = math.clamp(1 - length / s.Break, 0.12, 1)
			s.Beam.Width0 = s.Width * thin
			s.Beam.Width1 = s.Width * thin * 0.75
		end
	end
end)

-- Torn ends ----------------------------------------------------------------------------

-- The ragged face where a limb tore: wet meat, a darker core, splayed flesh and skin flaps
-- around the edge, and a bone sticking out (boneLength 0 for none).
local function tornFace(part, position, normal, radius, cfg, boneLength)
	if goreOff() then
		return
	end
	local spin = rng:NextNumber(0, math.pi * 2)
	local base = alongX(position, normal, spin)
	local d = radius * 2
	stuck(part, {
		Name = "TornFace",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, d * 0.92, d * 0.92),
		Color = shade(cfg, 0.35),
		Reflectance = 0.08,
		CFrame = base * CFrame.new(0.02, 0, 0),
	})
	stuck(part, {
		Name = "TornCore",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, d * 0.5, d * 0.5),
		Color = cfg.BloodColor,
		Reflectance = 0.12,
		CFrame = base * CFrame.new(0.04, rng:NextNumber(-0.1, 0.1) * d, rng:NextNumber(-0.1, 0.1) * d),
	})
	local flaps = rng:NextInteger(6, 9)
	for i = 1, flaps do
		local a = (i / flaps) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local skin = i % 3 == 0
		local length = rng:NextNumber(0.12, 0.3) * radius / 0.45
		stuck(part, {
			Name = "TornFlap",
			Size = Vector3.new(length, rng:NextNumber(0.04, 0.08), rng:NextNumber(0.1, 0.22) * radius / 0.45),
			Color = if skin then part.Color:Lerp(cfg.FleshColor, 0.25) else shade(cfg, rng:NextNumber(0, 0.7)),
			-- Out to the rim, then bent outward like torn skin peeling back.
			CFrame = base * CFrame.Angles(a, 0, 0) * CFrame.new(length * 0.3, radius * 0.85, 0)
				* CFrame.Angles(0, 0, rng:NextNumber(0.25, 0.9)),
		})
	end
	if boneLength > 0 then
		local tilt = CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.25, 0.25))
		local off = CFrame.new(boneLength * 0.4, rng:NextNumber(-0.15, 0.15) * d, rng:NextNumber(-0.15, 0.15) * d)
		local bone = stuck(part, {
			Name = "Bone",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(boneLength, radius * 0.38, radius * 0.38),
			Color = cfg.BoneColor,
			CFrame = base * off * tilt,
		})
		-- Splintered end: a sliver and the dark marrow.
		stuck(part, {
			Name = "BoneSplinter",
			Size = Vector3.new(boneLength * 0.45, radius * 0.1, radius * 0.16),
			Color = cfg.BoneColor,
			CFrame = bone.CFrame * CFrame.new(boneLength * 0.55, radius * 0.1, 0) * CFrame.Angles(0, 0, 0.35),
		})
		stuck(part, {
			Name = "Marrow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.02, radius * 0.2, radius * 0.2),
			Color = cfg.BloodColor,
			CFrame = bone.CFrame * CFrame.new(boneLength / 2 + 0.005, 0, 0),
		})
	end
end

-- A drop falling off a part at a point given in its space (so it follows the body).
local function dripFrom(part, localPos, cfg, size)
	CombatFx.BloodDrops(part.CFrame * localPos, Vector3.new(0, -1, 0), 1, {
		Color = cfg.BloodColor,
		Speed = NumberRange.new(0, 1.5),
		Spread = 10,
		Size = size or NumberRange.new(0.05, 0.09),
	})
end

-- Heartbeat spurts that fade, then a slow drip. Each pulse throws real drops that pool.
local function spurt(part, position, dir, cfg, pulses)
	if goreOff() then
		return
	end
	local a, e = cloneEmitter("Spurt", part, aimY(position, dir), cfg.BloodColor)
	local localPos = part.CFrame:PointToObjectSpace(position)
	local localDir = part.CFrame:VectorToObjectSpace(dir)
	task.spawn(function()
		for i = 1, pulses do
			if not a.Parent then
				return
			end
			local fade = 1 - (i - 1) / pulses
			e:Emit(math.max(2, math.floor(16 * fade)))
			CombatFx.BloodDrops(part.CFrame * localPos, part.CFrame:VectorToWorldSpace(localDir), math.max(1, math.floor(6 * fade)), {
				Color = cfg.BloodColor,
				Speed = NumberRange.new(4 * fade + 2, 11 * fade + 3),
				Spread = 14,
				Size = NumberRange.new(0.06, 0.13),
			})
			task.wait(0.34 + rng:NextNumber(0, 0.08))
		end
		local start = os.clock()
		while a.Parent and os.clock() - start < cfg.DripTime do
			dripFrom(part, localPos, cfg)
			task.wait(rng:NextNumber(0.2, 0.5))
		end
		a:Destroy()
	end)
end

local function throwChunks(position, dir, cfg)
	if goreOff() then
		return
	end
	for _ = 1, rng:NextInteger(cfg.Chunks.Min, cfg.Chunks.Max) do
		local s = rng:NextNumber(0.07, 0.18)
		local c = Instance.new("Part")
		c.Name = "FleshChunk"
		c.Size = Vector3.new(s, s * rng:NextNumber(0.5, 1), s * rng:NextNumber(0.6, 1.3))
		c.Color = shade(cfg, rng:NextNumber(0, 0.8))
		c.Material = Enum.Material.SmoothPlastic
		c.Reflectance = 0.08
		c.CFrame = CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), 0)
		c.CanQuery = false
		c.CanTouch = false
		c.CastShadow = false
		c.CollisionGroup = "Debris"
		c.Parent = fxWorld
		c.AssemblyLinearVelocity = dir * rng:NextNumber(5, 15) + randomInDisc(dir, 7) + Vector3.yAxis * rng:NextNumber(4, 11)
		c.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 20
		task.delay(2.5, function()
			if c.Parent then
				c.Anchored = true
			end
		end)
		table.insert(chunks, c)
		while #chunks > CHUNK_LIMIT do
			table.remove(chunks, 1):Destroy()
		end
	end
end

-- Blood thrown along dir lands on whatever is behind: walls, the floor.
local function splatter(origin, dir, count, scale)
	for _ = 1, count do
		local v = (dir + randomInDisc(dir, 0.5)).Unit * rng:NextNumber(9, 16) + Vector3.new(0, -rng:NextNumber(0, 5), 0)
		local hit = CombatFx.CastWorld(origin, v)
		if hit then
			CombatFx.Splat(hit.Position, hit.Normal, scale * rng:NextNumber(0.8, 1.4))
		end
	end
end

-- Blood drops behind a flying limb, then a splat and a thud where it comes down.
local function trailAndLand(limbPart, endLocal, cfg, mob, delay)
	task.spawn(function()
		task.wait(delay)
		local start = os.clock()
		local landed = false
		while limbPart.Parent and os.clock() - start < 3 do
			local t = os.clock() - start
			if t < 1.2 then
				-- Drops shed from the torn end keep some of the limb's speed.
				local v = limbPart.AssemblyLinearVelocity
				local speed = v.Magnitude
				CombatFx.BloodDrops(limbPart.CFrame * endLocal, if speed > 0.5 then v / speed else Vector3.new(0, -1, 0), 1, {
					Color = cfg.BloodColor,
					Speed = NumberRange.new(speed * 0.4, speed * 0.7),
					Spread = 30,
				})
			end
			if not landed and limbPart.AssemblyLinearVelocity.Y < 1 and t > 0.12 then
				local hit = CombatFx.CastWorld(limbPart.Position, Vector3.new(0, -2.4, 0))
				if hit then
					landed = true
					CombatFx.Splat(hit.Position, hit.Normal, 1.1)
					SoundKit.Play(mob.Sounds .. "/BodyFall", { Position = hit.Position, Volume = 0.55, Speed = 1.25 })
				end
			end
			if landed and t > 1.2 then
				break
			end
			task.wait(0.05)
		end
	end)
end

-- Public --------------------------------------------------------------------------------

-- A bullet hole where a shot went in. sink is how deep the dent under it went (studs).
function Gore.Wound(model, part, hitPos, normal, dir, sink)
	local mob = model and mobConfig(model:GetAttribute("MobType"))
	local cfg = mob and mob.Gore
	if not cfg or not part:IsA("BasePart") or not part.Parent or goreOff() then
		return
	end
	sink = sink or 0

	local list = wounds[part] or {}
	wounds[part] = list
	while #list >= cfg.WoundsPerPart do
		for _, bit in table.remove(list, 1).Bits do
			bit:Destroy()
		end
	end

	local bits = {}
	local d = rng:NextNumber(0.15, 0.22)
	local spin = rng:NextNumber(0, math.pi * 2)
	local base = alongX(hitPos, normal, spin)
	-- The hole, at the bottom of the dent.
	table.insert(bits, stuck(part, {
		Name = "Wound",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.03, d, d),
		Color = cfg.WoundColor,
		CFrame = base * CFrame.new(0.008 - sink * 0.9, 0, 0),
	}))
	-- Torn rim: flesh splayed out round the hole, with a couple of curled skin flaps.
	local rim = rng:NextInteger(4, 6)
	for i = 1, rim do
		local a = (i / rim) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local skin = i <= 2
		table.insert(bits, stuck(part, {
			Name = "WoundRim",
			Size = Vector3.new(0.025, rng:NextNumber(0.05, 0.09), rng:NextNumber(0.04, 0.08)),
			Color = if skin then part.Color:Lerp(cfg.FleshColor, 0.3) else shade(cfg, rng:NextNumber(0, 0.6)),
			CFrame = base * CFrame.Angles(a, 0, 0) * CFrame.new(0.014 - sink * 0.6, d * 0.52, 0) * CFrame.Angles(0, 0, rng:NextNumber(-0.6, -0.15)),
		}))
	end
	-- Blood running down the surface from the hole, starting at the dent's lip.
	local down = Vector3.new(0, -1, 0)
	down -= normal * down:Dot(normal)
	local start = if sink > 0.02 then 0.26 else d * 0.35
	local length = rng:NextNumber(0.2, 0.55)
	if down.Magnitude > 0.25 then
		down = down.Unit
		-- Stop the run at the part's edge.
		local p = part.CFrame:PointToObjectSpace(hitPos)
		local dl = part.CFrame:VectorToObjectSpace(down)
		local h = part.Size / 2
		local room = math.huge
		for _, axis in { "X", "Y", "Z" } do
			if math.abs(dl[axis]) > 1e-3 then
				room = math.min(room, (math.sign(dl[axis]) * h[axis] - p[axis]) / dl[axis])
			end
		end
		length = math.min(length, room - start - 0.03)
	end
	if down.Magnitude > 0.25 and length > 0.08 then
		local center = hitPos + down * (start + length / 2) + normal * 0.007
		table.insert(bits, stuck(part, {
			Name = "WoundRun",
			Size = Vector3.new(0.012, length, rng:NextNumber(0.035, 0.055)),
			Color = cfg.BloodColor,
			CFrame = CFrame.fromMatrix(center, normal, down),
		}))
	end
	table.insert(list, { Bits = bits, Sink = sink, Normal = part.CFrame:VectorToObjectSpace(normal) })

	-- A few drops fall from the fresh hole and pool under the mob as it walks.
	if drips < DRIP_LIMIT then
		drips += 1
		local localPos = part.CFrame:PointToObjectSpace(hitPos + normal * 0.04)
		task.spawn(function()
			for _ = 1, rng:NextInteger(3, 6) do
				task.wait(rng:NextNumber(0.25, 0.6))
				if not part.Parent then
					break
				end
				dripFrom(part, localPos, cfg)
			end
			drips -= 1
		end)
	end
end

-- One bullet landing on a mob. normal may be nil (it is found on the part); feel is the
-- gun's Feel; scale shrinks the kick (each shotgun pellet carries a share of it).
-- Kick, dent, wound and blood, in that order, on this frame.
function Gore.Shot(model, part, hitPos, normal, dir, feel, scale)
	local mob = mobConfig(model:GetAttribute("MobType"))
	if not mob or not part:IsA("BasePart") or not part.Parent then
		return
	end
	MobImpact.Hit(model, part, hitPos, dir, feel, scale)
	-- Rounds that carry through throw blood out of the back of the wound.
	if (feel.ExitSpray or 0) > 0 and mob.Gore then
		CombatFx.BloodDrops(hitPos + dir * 0.4, dir, feel.ExitSpray, {
			Color = mob.Gore.BloodColor,
			Speed = NumberRange.new(10, 22),
			Spread = 16,
		})
	end
	if not normal then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { part }
		local hit = workspace:Raycast(hitPos - dir * 2, dir * 4, params)
		if not hit then
			CombatFx.BloodHit(hitPos, -dir, dir, mob.Gore and mob.Gore.BloodColor)
			return
		end
		hitPos, normal = hit.Position, hit.Normal
	end
	CombatFx.BloodHit(hitPos, normal, dir, mob.Gore and mob.Gore.BloodColor)
	-- The wound goes in once the crater is there (a frame or two on a part's first hit).
	Dents.Dent(part, hitPos, normal, dir, function(sink, at, n)
		Gore.Wound(model, part, at, n, dir, sink)
	end)
end

-- A part's dent copy went back to the pool and its craters flattened: lift its wounds
-- back out to the surface.
Dents.Released = function(part)
	local cf = part.CFrame
	for _, entry in wounds[part] or {} do
		if entry.Sink > 0 then
			local n = cf:VectorToWorldSpace(entry.Normal)
			for _, bit in entry.Bits do
				local lift = if bit.Name == "Wound" then 0.9 elseif bit.Name == "WoundRim" then 0.6 else 0
				local weld = bit:FindFirstChildOfClass("WeldConstraint")
				if lift > 0 and bit.Parent and weld then
					weld.Enabled = false
					bit.CFrame += n * entry.Sink * lift
					weld.Enabled = true
				end
			end
			entry.Sink = 0
		end
	end
end

-- A limb about to come off: the joint hangs open, bridged by a few strands of flesh.
-- bodyLocal / limbLocal are the joint point in each part's space.
function Gore.Loosen(bodyPart, bodyLocal, limbPart, limbLocal, mobType)
	local mob = mobConfig(mobType)
	local cfg = mob and mob.Gore
	if not cfg or not limbPart.Parent or not bodyPart.Parent then
		return
	end
	local joint = bodyPart.CFrame * bodyLocal
	local pivot, out = surfaceToward(bodyPart, joint)
	local limbEnd, limbFace = surfaceToward(limbPart, limbPart.CFrame * limbLocal)
	local radius = math.min(limbPart.Size.X, limbPart.Size.Z) * 0.5
	-- The joint has opened: raw meat shows on both sides of the gap.
	tornFace(bodyPart, pivot, out, radius * 0.7, cfg, 0)
	tornFace(limbPart, limbEnd, limbFace, radius * 0.7, cfg, rng:NextNumber(0.08, 0.14))
	for _ = 1, rng:NextInteger(3, 4) do
		local off = randomInDisc(out, radius * 0.6)
		strandBetween(bodyPart, pivot + off, limbPart, limbEnd + off * 0.8, cfg, rng:NextNumber(2.2, 3.4), rng:NextNumber(0.05, 0.1) * radius / 0.45, nil)
	end
	spurt(bodyPart, pivot, out, cfg, 3)
	CombatFx.Emit("Gore", pivot, out, 10)
	SoundKit.Play(mob.Sounds .. "/LimbOff", { Position = pivot, Volume = 0.6, Speed = 1.15 })
	SoundKit.Play(mob.Sounds .. "/Tear", { Position = pivot, Volume = 0.5, Speed = 1.2 })
end

-- A limb tearing off. stumpLocal / limbLocal are the joint point in each part's space;
-- hold is how long the server lets the flesh hold before it snaps.
function Gore.Tear(stumpPart, stumpLocal, limbPart, limbLocal, dir, hold, mobType, gunName)
	local mob = mobConfig(mobType)
	local cfg = mob and mob.Gore
	if not cfg or not limbPart or not limbPart.Parent then
		return
	end
	local hasStump = stumpPart ~= nil and stumpPart.Parent ~= nil
	local limbEnd, limbFace = surfaceToward(limbPart, limbPart.CFrame * limbLocal)
	local stumpPos, stumpFace = limbEnd, -limbFace
	if hasStump then
		stumpPos, stumpFace = surfaceToward(stumpPart, stumpPart.CFrame * stumpLocal)
	end
	local radius = math.min(limbPart.Size.X, limbPart.Size.Z) * 0.5

	-- Bone stays with one side; the other gets a short stub.
	local longBone = rng:NextNumber(0.35, 0.6) * radius / 0.45
	local stub = rng:NextNumber(0.08, 0.15) * radius / 0.45
	local boneOnStump = rng:NextNumber() < 0.5
	tornFace(limbPart, limbEnd, limbFace, radius, cfg, if boneOnStump then stub else longBone)
	throwChunks(stumpPos, dir, cfg)
	SoundKit.Play(mob.Sounds .. "/Tear", { Position = stumpPos })

	if hasStump then
		tornFace(stumpPart, stumpPos, stumpFace, radius, cfg, if boneOnStump then longBone else stub)
		for _ = 1, rng:NextInteger(cfg.Strands.Min, cfg.Strands.Max) do
			local off = randomInDisc(stumpFace, radius * 0.75)
			strandBetween(stumpPart, stumpPos + off, limbPart, limbEnd + off * rng:NextNumber(0.6, 1.1), cfg,
				rng:NextNumber(cfg.StrandBreak.Min, cfg.StrandBreak.Max), rng:NextNumber(0.05, 0.14) * radius / 0.45, TEAR_STRAND_LIFE)
		end
		spurt(stumpPart, stumpPos, stumpFace, cfg, cfg.SpurtPulses)
	end

	-- The snap: crunch, a burst of blood and the body reeling from it.
	task.delay(hold, function()
		SoundKit.Play(mob.Sounds .. "/LimbOff", { Position = stumpPos })
		SoundKit.Play(mob.Sounds .. "/Splat", { Position = stumpPos })
		CombatFx.Emit("Gore", stumpPos, dir, 24)
		CombatFx.Emit("Blood", stumpPos, stumpFace, 10)
		CombatFx.BloodDrops(stumpPos, stumpFace, 10, { Color = cfg.BloodColor, Speed = NumberRange.new(5, 15), Spread = 35 })
		local floor = CombatFx.CastWorld(stumpPos, Vector3.new(0, -10, 0))
		if floor then
			CombatFx.Splat(floor.Position, floor.Normal, 1.3)
		end
		local model = hasStump and mobOf(stumpPart)
		local gun = GameConfig.Guns[gunName or ""]
		if model and gun then
			MobImpact.Hit(model, stumpPart, stumpPos, dir, gun.Feel, 1.6)
		end
	end)
	trailAndLand(limbPart, limbPart.CFrame:PointToObjectSpace(limbEnd), cfg, mob, hold)
end

-- A head bursting where it was struck. stumpLocal is the neck point in the torso's space.
function Gore.Pop(stumpPart, stumpLocal, center, dir, mobType)
	local mob = mobConfig(mobType)
	local cfg = mob and mob.Gore
	if not cfg then
		return
	end
	SoundKit.Play(mob.Sounds .. "/Splat", { Position = center, Volume = 1.3, Speed = 0.85 })
	SoundKit.Play(mob.Sounds .. "/LimbOff", { Position = center, Speed = 0.9 })
	CombatFx.Emit("Gore", center, dir, 40)
	CombatFx.Emit("Blood", center, dir, 24)
	CombatFx.BloodDrops(center, dir, 26, { Color = cfg.BloodColor, Speed = NumberRange.new(8, 26), Spread = 50 })
	throwChunks(center, dir, cfg)
	throwChunks(center, dir, cfg)
	splatter(center, dir, 4, 1.2)
	if stumpPart and stumpPart.Parent and typeof(stumpLocal) == "Vector3" then
		local pos, face = surfaceToward(stumpPart, stumpPart.CFrame * stumpLocal)
		tornFace(stumpPart, pos, face, 0.32, cfg, rng:NextNumber(0.1, 0.18))
		spurt(stumpPart, pos, face, cfg, cfg.SpurtPulses)
	end
end

-- A point-blank shotgun kill: the torso bursts open toward the shooter and the room
-- behind it is splattered.
function Gore.Burst(torso, center, dir, mobType)
	local mob = mobConfig(mobType)
	local cfg = mob and mob.Gore
	if not cfg then
		return
	end
	SoundKit.Play(mob.Sounds .. "/Splat", { Position = center, Volume = 1.4, Speed = 0.75 })
	SoundKit.Play(mob.Sounds .. "/Tear", { Position = center, Speed = 0.8 })
	CombatFx.Emit("Gore", center, dir, 60)
	CombatFx.Emit("Blood", center, dir, 30)
	CombatFx.BloodDrops(center, dir, 40, { Color = cfg.BloodColor, Speed = NumberRange.new(10, 30), Spread = 40 })
	for _ = 1, 3 do
		throwChunks(center, dir, cfg)
	end
	splatter(center, dir, 7, 1.7)
	local floor = CombatFx.CastWorld(center, Vector3.new(0, -8, 0))
	if floor then
		CombatFx.Splat(floor.Position, floor.Normal, 2.2)
	end
	if torso and torso.Parent then
		local pos, face = surfaceToward(torso, center - dir * 3)
		tornFace(torso, pos, face, 0.5, cfg, 0)
	end
end

-- Server events ------------------------------------------------------------------------

local localPlayer = Players.LocalPlayer

Remotes:WaitForChild("MobFx").OnClientEvent:Connect(function(kind, part, local0, position, dir, extra)
	if typeof(dir) ~= "Vector3" or typeof(extra) ~= "table" then
		return
	end
	if kind == "Hit" then
		-- The shooter already drew their own hits the moment they fired.
		local gun = GameConfig.Guns[extra.Gun or ""]
		if extra.Shooter == localPlayer or not gun or typeof(extra.Parts) ~= "table" or typeof(extra.Positions) ~= "table" then
			return
		end
		local scale = if (gun.Pellets or 1) > 1 then gun.Feel.PelletImpact or 1 else 1
		for i, hitPart in extra.Parts do
			local at = extra.Positions[i]
			local model = typeof(hitPart) == "Instance" and hitPart:IsA("BasePart") and mobOf(hitPart)
			if model and typeof(at) == "Vector3" then
				Gore.Shot(model, hitPart, at, nil, dir, gun.Feel, scale)
			end
		end
	elseif kind == "Pop" then
		if typeof(position) == "Vector3" then
			local stump = if typeof(part) == "Instance" and part:IsA("BasePart") then part else nil
			Gore.Pop(stump, local0, position, dir, extra.MobType)
		end
	elseif kind == "Burst" then
		if typeof(position) == "Vector3" then
			local torso = if typeof(part) == "Instance" and part:IsA("BasePart") then part else nil
			Gore.Burst(torso, position, dir, extra.MobType)
		end
	elseif kind == "Loosen" then
		if typeof(part) == "Instance" and part:IsA("BasePart") and typeof(local0) == "Vector3"
			and typeof(extra.Limb) == "Instance" and typeof(extra.LimbLocal) == "Vector3" then
			Gore.Loosen(part, local0, extra.Limb, extra.LimbLocal, extra.MobType)
		end
	elseif kind == "Sever" then
		if typeof(extra.Limb) == "Instance" and typeof(local0) == "Vector3" and typeof(extra.LimbLocal) == "Vector3" then
			local stump = if typeof(part) == "Instance" and part:IsA("BasePart") then part else nil
			Gore.Tear(stump, local0, extra.Limb, extra.LimbLocal, dir, extra.Hold or 0.12, extra.MobType, extra.Gun)
		end
	end
end)

return Gore
