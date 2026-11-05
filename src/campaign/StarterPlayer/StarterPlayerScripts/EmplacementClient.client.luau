-- Mounted guns and artillery on the client (horror-shooter/war/WAR-V2-CONTRACTS.md, GUNS contract).
--   Puts a "Man the gun" prompt on every nest of the player's side (workspace.Emplacements, tag
--   Emplacement) while no player has it (a soldier on it hands it over: Emplacements' mount). Mounted (player attribute OnEmplacement = the nest's name): a
--   first-person camera behind the gun, the mouse (or right stick, or a touch drag) aims inside the
--   arc, the Shoot key (left mouse / RT) or a held touch fires, the Use or Crouch key (E or C / X or B) gets off
--   (the player's own keys, Shared.Controls). The gun's own shots are drawn
--   here at once and the aim and trigger go to the server about 15 times a second; the server fires.
--   Every nest within 300 studs: the gun turns smoothly to its Aim attribute, the barrel glows with
--   Heat, and the rounds from Remotes.EmplacementFx come out as tracers, a muzzle flash and the gun.
--   Artillery (Remotes.Emplacement "Shell"): a falling whistle, then a flash, snow and dirt, smoke,
--   a boom heard far off, a scorch on the ground and a shake within 60 studs.
-- Per-frame work only for live effects and guns near the camera; every effect is pooled.
-- While mounted, a bar above the hotbar says how to use it on this device with the player's own keys (mouse
-- "CLICK fire / E get off", pad "RT fire / B get off" with the pad's own button pictures, phone "HOLD fire" and a
-- GET OFF button) and shows the barrel's heat.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = Remotes:WaitForChild("Emplacement")
local fxRemote = Remotes:WaitForChild("EmplacementFx")
local Sounds = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds")
local Controls = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Controls"))

local PITCH_UP, PITCH_DOWN = math.rad(25), math.rad(18)
local TURN = math.rad(220) -- how fast the mounted gun follows the aim
local GAP = 60 / 900
local HEAT_TIME, COOL_TIME = 3, 2
local SPREAD = math.rad(1.0)
local RANGE = 250
local DRAW = 300
local SEND = 1 / 15
local EYE = CFrame.new(0, 0.8, 2.55) -- the gunner's eye, from the swivel (behind the M2's spade grips)
local TRACER_SPEED, TRACER_LEN = 1100, 7
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local HOT1 = Color3.fromRGB(125, 30, 18)
local HOT2 = Color3.fromRGB(255, 112, 36)
local FAR = CFrame.new(0, 10000, 0) -- where pooled parts wait, hidden
local SHAKE_RANGE = 60

local rng = Random.new()

local fxFolder = Instance.new("Folder")
fxFolder.Name = "EmplacementFxLocal"
fxFolder.Parent = workspace

local function find(path)
	local node = Sounds
	for name in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end
local SHOT_SOUNDS = { find("Guns/AK/Crack/Shot1"), find("Guns/AK/Crack/Shot2") }
local TAIL_SOUND = find("Guns/AK/Tail/Tail1")
local BOOM_SOUND = find("World/Explosion")
local WHISTLE_SOUND = find("War/Whistle")

local function approach(from, to, maxStep)
	local d = to - from
	if math.abs(d) <= maxStep then
		return to
	end
	return from + math.sign(d) * maxStep
end

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = 1
	p.CFrame = FAR
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = fxFolder
	return p
end

local function newSound(template, props)
	local s = template:Clone()
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	for k, v in props do
		(s :: any)[k] = v
	end
	return s
end

-- A frame at pos whose +Y is normal.
local function upFrame(pos, normal)
	local n = if normal and normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	local ref = if math.abs(n.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	return CFrame.fromMatrix(pos, n:Cross(ref).Unit, n)
end

local function camPos()
	return workspace.CurrentCamera.CFrame.Position
end

local function mySide()
	return player:GetAttribute("Side") or "Ally"
end

-- Nests -------------------------------------------------------------------------------------------------

local nests = {} -- [model] = nest
local near = {} -- nests within DRAW of the camera (refreshed twice a second)
local mounted = nil
local refreshPrompts

local function frameOf(nest, yaw, pitch)
	return nest.Swivel * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

local function setRig(nest, frame)
	local cfs = table.create(#nest.Parts)
	for i, off in nest.Offsets do
		cfs[i] = frame * off
	end
	workspace:BulkMoveTo(nest.Parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function applyHeat(nest, h)
	h = math.floor(h * 20 + 0.5) / 20
	if h == nest.HeatShown then
		return
	end
	nest.HeatShown = h
	for _, hot in nest.Hot do
		local color, glow = hot.Color, false
		if h >= 0.7 then
			color, glow = HOT1:Lerp(HOT2, math.clamp((h - 0.7) / 0.3, 0, 1)), h >= 0.8
		elseif h > 0.35 then
			color = hot.Color:Lerp(HOT1, (h - 0.35) / 0.35)
		end
		hot.Part.Color = color
		hot.Part.Material = if glow then Enum.Material.Neon else hot.Material
	end
end

local function makePrompt(nest)
	local pad = nest.Model:FindFirstChild("Pad")
	local at = pad and pad:FindFirstChild("Prompt")
	if not at then
		return
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "ManGun"
	p.ActionText = "Man the gun"
	p.ObjectText = ""
	p.HoldDuration = 0.3
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Enabled = false
	p.Triggered:Connect(function()
		if not mounted then
			remote:FireServer("Mount", nest.Model)
		end
	end)
	p.Parent = at
	nest.Prompt = p
end

local function unregister(model)
	local nest = nests[model]
	if not nest then
		return
	end
	nests[model] = nil
	for _, c in nest.Conns do
		c:Disconnect()
	end
	if nest.Prompt then
		nest.Prompt:Destroy()
	end
	if nest.Fx then
		nest.Fx.Core:Destroy()
		nest.Fx.Plume:Destroy()
		nest.Fx.Holder:Destroy()
	end
	table.remove(near, table.find(near, nest) or #near + 1)
end

local function register(model)
	if nests[model] or not model:IsA("Model") then
		return nests[model]
	end
	local pad = model:FindFirstChild("Pad")
	local rig = model:FindFirstChild("GunRig")
	local swivel = pad and pad:FindFirstChild("Swivel")
	local gun = rig and rig:FindFirstChild("Gun")
	local muzzle = gun and gun:FindFirstChild("Muzzle")
	if not (swivel and gun and muzzle) then
		return nil
	end
	local swivelCf = swivel.WorldCFrame
	local nest = {
		Model = model,
		Swivel = swivelCf,
		MuzzleOffset = swivelCf:ToObjectSpace(muzzle.WorldCFrame),
		Parts = {},
		Offsets = {},
		Hot = {},
		Yaw = 0,
		Pitch = 0,
		TargetYaw = 0,
		TargetPitch = 0,
		HeatShown = 0,
		Conns = {},
	}
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(nest.Parts, d)
			table.insert(nest.Offsets, swivelCf:ToObjectSpace(d.CFrame))
			if d.Name == "Jacket" or d.Name == "Barrel" or d.Name == "Booster" then
				table.insert(nest.Hot, { Part = d, Color = d.Color, Material = d.Material })
			end
		end
	end
	nests[model] = nest
	local function readAim()
		local aim = model:GetAttribute("Aim")
		if typeof(aim) == "Vector2" then
			nest.TargetYaw, nest.TargetPitch = aim.X, aim.Y
		end
	end
	readAim()
	nest.Yaw, nest.Pitch = nest.TargetYaw, nest.TargetPitch
	setRig(nest, frameOf(nest, nest.Yaw, nest.Pitch))
	applyHeat(nest, model:GetAttribute("Heat") or 0)
	table.insert(nest.Conns, model:GetAttributeChangedSignal("Aim"):Connect(readAim))
	table.insert(nest.Conns, model:GetAttributeChangedSignal("Heat"):Connect(function()
		if mounted ~= nest then
			applyHeat(nest, model:GetAttribute("Heat") or 0)
		end
	end))
	table.insert(nest.Conns, model:GetAttributeChangedSignal("Manned"):Connect(function()
		refreshPrompts()
	end))
	table.insert(nest.Conns, model:GetAttributeChangedSignal("Gunner"):Connect(function()
		refreshPrompts()
	end))
	makePrompt(nest)
	refreshPrompts()
	return nest
end

-- A player is on this gun (a soldier on it doesn't count: the player takes it over).
local function playerOn(model)
	if model:GetAttribute("Manned") ~= true then
		return false
	end
	local name = model:GetAttribute("Gunner")
	return type(name) ~= "string" or Players:FindFirstChild(name) ~= nil
end

refreshPrompts = function()
	local side = mySide()
	for model, nest in nests do
		if nest.Prompt then
			nest.Prompt.Enabled = mounted == nil and model:GetAttribute("Side") == side and not playerOn(model)
		end
	end
end

local function tryRegister(model)
	if register(model) then
		return
	end
	-- Not all there yet (streaming): try again as pieces arrive.
	local conn
	conn = model.DescendantAdded:Connect(function()
		if register(model) or not model.Parent then
			conn:Disconnect()
		end
	end)
end

for _, m in CollectionService:GetTagged("Emplacement") do
	tryRegister(m)
end
CollectionService:GetInstanceAddedSignal("Emplacement"):Connect(tryRegister)
CollectionService:GetInstanceRemovedSignal("Emplacement"):Connect(unregister)
player:GetAttributeChangedSignal("Side"):Connect(function()
	refreshPrompts()
end)

-- Effects ----------------------------------------------------------------------------------------------

-- Tracers.
local tracerFree, tracers = {}, {}
for _ = 1, 48 do
	table.insert(tracerFree, newPart({ Name = "Tracer", Size = Vector3.new(0.09, 0.09, 1), Color = Color3.fromRGB(255, 196, 110) }))
end

local puffs, puffAt = {}, 0
local function puff(pos, normal)
	if (camPos() - pos).Magnitude > 160 then
		return
	end
	puffAt = puffAt % 12 + 1
	local p = puffs[puffAt]
	if not p then
		local a = Instance.new("Attachment")
		a.Name = "EmplacementPuff"
		a.Parent = workspace.Terrain
		local e = Instance.new("ParticleEmitter")
		e.Texture = SMOKE_TEX
		e.Enabled = false
		e.Rate = 0
		e.Color = ColorSequence.new(Color3.fromRGB(226, 229, 233), Color3.fromRGB(165, 165, 162))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.8) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.35, 0.65)
		e.Speed = NumberRange.new(5, 11)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Acceleration = Vector3.new(0, -14, 0)
		e.Drag = 3
		e.Parent = a
		p = { A = a, E = e }
		puffs[puffAt] = p
	end
	p.A.WorldCFrame = upFrame(pos, normal)
	p.E:Emit(3)
end

local function spawnTracer(origin, endPos, t0, hit, normal)
	local v = endPos - origin
	local dist = v.Magnitude
	local part = dist > 0.5 and table.remove(tracerFree)
	if not part then
		return
	end
	local dir = v / dist
	table.insert(tracers, { Part = part, Origin = origin, Dir = dir, Rot = CFrame.lookAt(Vector3.zero, dir), Dist = dist, T0 = t0, Hit = hit, Normal = normal })
end

local function updateTracers(now)
	for i = #tracers, 1, -1 do
		local tr = tracers[i]
		local travel = (now - tr.T0) * TRACER_SPEED
		if travel >= 0 then
			local head = math.min(travel, tr.Dist)
			local tail = math.max(0, travel - TRACER_LEN)
			local part = tr.Part
			if tail >= tr.Dist then
				part.Transparency = 1
				part.CFrame = FAR
				table.insert(tracerFree, part)
				tracers[i] = tracers[#tracers]
				tracers[#tracers] = nil
				if tr.Hit then
					puff(tr.Origin + tr.Dir * tr.Dist, tr.Normal or -tr.Dir)
				end
			else
				part.Size = Vector3.new(0.09, 0.09, math.max(head - tail, 0.05))
				part.CFrame = tr.Rot + (tr.Origin + tr.Dir * ((head + tail) / 2))
				part.Transparency = 0.1
			end
		end
	end
end

-- Muzzle flash and the gun's voice, one set per nest, made when it first fires near the camera.
local flashing = {}
local function gunFx(nest)
	local fx = nest.Fx
	if fx then
		return fx
	end
	fx = {
		Core = newPart({ Name = "Flash", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, Color = Color3.fromRGB(255, 222, 150) }),
		Plume = newPart({ Name = "Flash", Size = Vector3.new(0.3, 0.3, 1.4), Color = Color3.fromRGB(255, 168, 78) }),
		Holder = Instance.new("Attachment"),
		Shots = {},
		Next = 1,
		TailAt = 0,
		Off = 0,
	}
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Shadows = false
	light.Enabled = false
	light.Parent = fx.Core
	fx.Light = light
	fx.Holder.Name = "EmplacementGun"
	fx.Holder.Parent = workspace.Terrain
	for i = 1, 5 do
		local t = SHOT_SOUNDS[(i % #SHOT_SOUNDS) + 1]
		if t then
			local s = newSound(t, { RollOffMinDistance = 12, RollOffMaxDistance = 450, Volume = 0.75 })
			s.Parent = fx.Holder
			table.insert(fx.Shots, s)
		end
	end
	if TAIL_SOUND then
		fx.Tail = newSound(TAIL_SOUND, { RollOffMinDistance = 30, RollOffMaxDistance = 800, Volume = 0.42 })
		fx.Tail.Parent = fx.Holder
	end
	nest.Fx = fx
	return fx
end

local function muzzle(nest, origin, dir, now)
	local fx = gunFx(nest)
	local rot = CFrame.lookAt(origin, origin + dir) * CFrame.Angles(0, 0, rng:NextNumber(0, math.pi * 2))
	local s = rng:NextNumber(0.8, 1.25)
	fx.Core.Size = Vector3.one * 0.45 * s
	fx.Core.CFrame = rot
	fx.Core.Transparency = 0.35
	fx.Plume.Size = Vector3.new(0.24 * s, 0.24 * s, 1.1 * s)
	fx.Plume.CFrame = rot * CFrame.new(0, 0, -0.5 * s)
	fx.Plume.Transparency = 0.4
	fx.Light.Enabled = true
	fx.Off = now + 0.04
	flashing[nest] = true
	fx.Holder.WorldPosition = origin
	local snd = fx.Shots[fx.Next]
	if snd then
		fx.Next = fx.Next % #fx.Shots + 1
		snd.PlaybackSpeed = rng:NextNumber(0.84, 0.94)
		snd.TimePosition = 0
		snd:Play()
	end
	if fx.Tail and now >= fx.TailAt then
		fx.TailAt = now + 0.5
		fx.Tail.TimePosition = 0
		fx.Tail:Play()
	end
end

local function updateFlashes(now)
	for nest in flashing do
		local fx = nest.Fx
		if not fx or now >= fx.Off then
			flashing[nest] = nil
			if fx then
				fx.Core.Transparency = 1
				fx.Plume.Transparency = 1
				fx.Core.CFrame = FAR
				fx.Plume.CFrame = FAR
				fx.Light.Enabled = false
			end
		end
	end
end

-- Rounds the server fired (another player's or a soldier's gun): staggered across the batch.
local pending = {}
fxRemote.OnClientEvent:Connect(function(model, origin, ends, mask)
	if typeof(origin) ~= "Vector3" or type(ends) ~= "table" then
		return
	end
	if mounted and model == mounted.Model then
		return
	end
	if (camPos() - origin).Magnitude > DRAW then
		return
	end
	local nest = model and nests[model]
	local now = os.clock()
	mask = tonumber(mask) or 0
	for i, e in ends do
		if typeof(e) == "Vector3" then
			local t = now + (i - 1) * GAP
			local hit = math.floor(mask / 2 ^ (i - 1)) % 2 == 1
			spawnTracer(origin, e, t, hit, nil)
			if nest then
				table.insert(pending, { Nest = nest, Origin = origin, Dir = (e - origin).Unit, T = t })
			end
		end
	end
end)

local function updatePending(now)
	for i = #pending, 1, -1 do
		local p = pending[i]
		if now >= p.T then
			pending[i] = pending[#pending]
			pending[#pending] = nil
			if p.Nest.Model.Parent then
				muzzle(p.Nest, p.Origin, p.Dir, now)
			end
		end
	end
end

-- Artillery ------------------------------------------------------------------------------------------------

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	e.Texture = SMOKE_TEX
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function seq(a, b)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local bursts, burstAt = {}, 0
local function burstRig()
	burstAt = burstAt % 6 + 1
	local b = bursts[burstAt]
	if b then
		return b
	end
	local a = Instance.new("Attachment")
	a.Name = "EmplacementBurst"
	a.Parent = workspace.Terrain
	b = {
		A = a,
		Snow = emitter(a, {
			Color = ColorSequence.new(Color3.fromRGB(240, 243, 246), Color3.fromRGB(200, 204, 208)),
			Size = seq(1.1, 3.2), Transparency = seq(0.1, 1), Lifetime = NumberRange.new(0.8, 1.5),
			Speed = NumberRange.new(22, 48), SpreadAngle = Vector2.new(32, 32), Acceleration = Vector3.new(0, -55, 0), Drag = 1.5,
		}),
		Dirt = emitter(a, {
			Color = ColorSequence.new(Color3.fromRGB(92, 76, 56), Color3.fromRGB(66, 58, 48)),
			Size = seq(0.8, 2.2), Transparency = seq(0, 1), Lifetime = NumberRange.new(0.7, 1.2),
			Speed = NumberRange.new(25, 50), SpreadAngle = Vector2.new(26, 26), Acceleration = Vector3.new(0, -70, 0), Drag = 1,
		}),
		Smoke = emitter(a, {
			Color = ColorSequence.new(Color3.fromRGB(58, 56, 54), Color3.fromRGB(96, 93, 89)),
			Size = seq(3, 10), Transparency = seq(0.35, 1), Lifetime = NumberRange.new(2.5, 4),
			Speed = NumberRange.new(3, 9), SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(0, 2.5, 0), Drag = 1,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
		}),
		Sparks = emitter(a, {
			Texture = SPARK_TEX, LightEmission = 1, Color = ColorSequence.new(Color3.fromRGB(255, 196, 120)),
			Size = seq(0.4, 0), Lifetime = NumberRange.new(0.25, 0.6), Speed = NumberRange.new(35, 70),
			SpreadAngle = Vector2.new(55, 55), Acceleration = Vector3.new(0, -60, 0),
		}),
	}
	bursts[burstAt] = b
	return b
end

local flashes, flashAt = {}, 0
local liveFlashes = {}
local function shellFlash(pos, now)
	flashAt = flashAt % 4 + 1
	local f = flashes[flashAt]
	if not f then
		f = { Part = newPart({ Name = "ShellFlash", Shape = Enum.PartType.Ball, Color = Color3.fromRGB(255, 196, 120) }) }
		local light = Instance.new("PointLight")
		light.Range = 50
		light.Color = Color3.fromRGB(255, 170, 90)
		light.Shadows = false
		light.Parent = f.Part
		f.Light = light
		flashes[flashAt] = f
	end
	f.Pos = pos
	f.T0 = now
	liveFlashes[f] = true
end

local function updateShellFlashes(now)
	for f in liveFlashes do
		local t = now - f.T0
		if t >= 0.45 then
			liveFlashes[f] = nil
			f.Part.Transparency = 1
			f.Part.CFrame = FAR
			f.Light.Brightness = 0
		else
			local grow = math.min(t / 0.12, 1)
			f.Part.Size = Vector3.one * (2 + 9 * grow)
			f.Part.CFrame = CFrame.new(f.Pos + Vector3.new(0, 1, 0))
			f.Part.Transparency = math.clamp(t / 0.35, 0, 1)
			f.Light.Brightness = 7 * (1 - t / 0.45)
		end
	end
end

-- Clods of snow and earth thrown out of the crater.
local chunkFree, chunks = {}, {}
for i = 1, 36 do
	table.insert(chunkFree, newPart({
		Name = "Clod",
		Material = Enum.Material.SmoothPlastic,
		Color = if i % 3 == 0 then Color3.fromRGB(84, 70, 54) else Color3.fromRGB(232, 236, 240),
	}))
end

local function throwChunks(pos, normal)
	local up = if normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	for _ = 1, 6 do
		local part = table.remove(chunkFree)
		if not part then
			return
		end
		local s = rng:NextNumber(0.35, 0.9)
		part.Size = Vector3.new(s, s * rng:NextNumber(0.6, 1), s)
		part.Transparency = 0
		local side = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		table.insert(chunks, {
			Part = part,
			Pos = pos + up * 0.5,
			Vel = up * rng:NextNumber(25, 45) + side * rng:NextNumber(8, 20),
			Spin = CFrame.Angles(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), 0),
			Rot = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			Life = rng:NextNumber(1, 1.4),
		})
	end
end

local function updateChunks(dt)
	for i = #chunks, 1, -1 do
		local c = chunks[i]
		c.Life -= dt
		if c.Life <= 0 then
			c.Part.Transparency = 1
			c.Part.CFrame = FAR
			table.insert(chunkFree, c.Part)
			chunks[i] = chunks[#chunks]
			chunks[#chunks] = nil
		else
			c.Vel += Vector3.new(0, -90 * dt, 0)
			c.Pos += c.Vel * dt
			c.Rot = c.Rot:Lerp(c.Rot * c.Spin, math.min(dt * 2, 1))
			c.Part.CFrame = c.Rot + c.Pos
		end
	end
end

-- Scorch marks: flat dark discs on the ground that fade after half a minute.
local scorches, scorchAt = {}, 0
local function scorch(pos, normal, now)
	scorchAt = scorchAt % 24 + 1
	local s = scorches[scorchAt]
	if not s then
		s = { Part = newPart({ Name = "Scorch", Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(26, 24, 22) }) }
		scorches[scorchAt] = s
	end
	local r = rng:NextNumber(5, 6.5)
	local n = if normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	local ref = if math.abs(n.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	s.Part.Size = Vector3.new(0.05, r, r)
	s.Part.CFrame = CFrame.fromMatrix(pos + n * 0.03, n, n:Cross(ref).Unit) * CFrame.Angles(rng:NextNumber(0, 6), 0, 0)
	s.Part.Transparency = 0.12
	s.T0 = now
end

local function updateScorches(now)
	for _, s in scorches do
		if s.T0 then
			local age = now - s.T0
			if age > 36 then
				s.T0 = nil
				s.Part.Transparency = 1
				s.Part.CFrame = FAR
			elseif age > 30 then
				s.Part.Transparency = 0.12 + 0.88 * (age - 30) / 6
			end
		end
	end
end

-- Camera shake from blasts within SHAKE_RANGE. Undone next frame if nothing else moved the camera.
local shakes = {}
local shakeWrote, shakeBase
RunService:BindToRenderStep("EmplacementShake", Enum.RenderPriority.Camera.Value + 30, function()
	local cam = workspace.CurrentCamera
	if shakeWrote and cam.CFrame == shakeWrote then
		cam.CFrame = shakeBase
	end
	shakeWrote = nil
	if #shakes == 0 then
		return
	end
	local now = os.clock()
	local total = 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local k = 1 - (now - s.T0) / s.Dur
		if k <= 0 then
			table.remove(shakes, i)
		else
			total += s.Amp * k * k
		end
	end
	if total <= 0 then
		return
	end
	local t = now * 24
	local offset = CFrame.new(math.noise(t, 3.1) * 0.3 * total, math.noise(t, 7.7) * 0.3 * total, 0)
		* CFrame.Angles(math.noise(t, 1.3) * math.rad(2.4) * total, math.noise(t, 5.9) * math.rad(2.4) * total, math.noise(t, 9.2) * math.rad(1.2) * total)
	shakeBase = cam.CFrame
	shakeWrote = shakeBase * offset
	cam.CFrame = shakeWrote
end)

local function impact(pos, normal)
	local now = os.clock()
	local d = (camPos() - pos).Magnitude
	if BOOM_SOUND then
		local a = Instance.new("Attachment")
		a.Name = "EmplacementBoom"
		a.Parent = workspace.Terrain
		a.WorldPosition = pos
		local s = newSound(BOOM_SOUND, { RollOffMinDistance = 45, RollOffMaxDistance = 1600, Volume = 2, PlaybackSpeed = rng:NextNumber(0.82, 0.98) })
		s.Parent = a
		s:Play()
		task.delay(5, function()
			a:Destroy()
		end)
	end
	if d > 450 then
		return
	end
	shellFlash(pos, now)
	local b = burstRig()
	b.A.WorldCFrame = upFrame(pos + normal * 0.3, normal)
	b.Snow:Emit(22)
	b.Dirt:Emit(14)
	b.Smoke:Emit(7)
	b.Sparks:Emit(16)
	if d <= 200 then
		throwChunks(pos, normal)
	end
	scorch(pos, normal, now)
	if d <= SHAKE_RANGE then
		table.insert(shakes, { Amp = (1 - d / SHAKE_RANGE) ^ 1.5, T0 = now, Dur = 0.7 })
	end
end

local function shell(pos, lead, normal)
	if typeof(pos) ~= "Vector3" then
		return
	end
	lead = tonumber(lead) or 1.2
	normal = if typeof(normal) == "Vector3" then normal else Vector3.yAxis
	local d = (camPos() - pos).Magnitude
	if WHISTLE_SOUND and d <= 450 then
		local a = Instance.new("Attachment")
		a.Name = "EmplacementWhistle"
		a.Parent = workspace.Terrain
		a.WorldPosition = pos + Vector3.new(0, 14, 0)
		local s = newSound(WHISTLE_SOUND, {})
		s.Parent = a
		local stop = WHISTLE_SOUND:GetAttribute("WhistleEnd") or WHISTLE_SOUND.TimeLength
		s.TimePosition = math.max(0, stop - lead)
		s:Play()
		task.delay(lead, function()
			a:Destroy()
		end)
	end
	task.delay(lead, impact, pos, normal)
end

remote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "Shell" then
		shell(a, b, c)
	end
end)

-- Manning a gun ------------------------------------------------------------------------------------

local aimYaw, aimPitch, gunYaw, gunPitch = 0, 0, 0, 0
local trigger = false
local touchFire = false
local touches = {}
local localHeat, localOver = 0, false
local shotAcc = 0
local sendAt, sentFire = 0, false
local mountedAt, leaveAt = 0, 0
local kickPitch, kickYaw, kickBack = 0, 0, 0
local saved = {}
local localParams = RaycastParams.new()
localParams.FilterType = Enum.RaycastFilterType.Exclude
localParams.IgnoreWater = true

local function hideCharacter(hidden)
	local c = player.Character
	if not c then
		return
	end
	for _, d in c:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function localShot(nest, frame, now)
	local origin = (frame * nest.MuzzleOffset).Position
	local dir = (frame * CFrame.Angles((rng:NextNumber() - 0.5) * SPREAD, (rng:NextNumber() - 0.5) * SPREAD, 0)).LookVector
	local hit = workspace:Raycast(origin, dir * RANGE, localParams)
	local endPos = if hit then hit.Position else origin + dir * RANGE
	spawnTracer(origin, endPos, now, hit ~= nil, hit and hit.Normal)
	muzzle(nest, origin, dir, now)
	kickPitch += math.rad(0.35)
	kickYaw += math.rad(rng:NextNumber(-0.25, 0.25))
	kickBack = 0.12
end

-- Controls bar while mounted ---------------------------------------------------------------------------------

local playerGui = player:WaitForChild("PlayerGui")
local BAR_TEXT = Color3.fromRGB(240, 238, 232)
local BAR_INK = Color3.fromRGB(24, 24, 26)
local BAR_AMBER = Color3.fromRGB(255, 186, 72)
local BAR_HOT = Color3.fromRGB(235, 70, 40)
local BAR_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local config = shared and shared:FindFirstChild("GameConfig")
	if config then
		local ok, cfg = pcall(require, config)
		if ok and type(cfg) == "table" and cfg.Hud and typeof(cfg.Hud.Lull) == "Color3" then
			BAR_AMBER = cfg.Hud.Lull
		end
	end
end

local function ui(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	i.Parent = parent
	return i
end

local barGui = ui("ScreenGui", {
	Name = "GunControls", ResetOnSpawn = false, Enabled = false, DisplayOrder = 5,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
}, playerGui)
local bar = ui("Frame", {
	Name = "Bar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -96),
	Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
}, barGui)
ui("UICorner", { CornerRadius = UDim.new(0, 10) }, bar)
local barScale = ui("UIScale", { Name = "HudScale" }, bar)
ui("UIPadding", {
	PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
}, bar)
ui("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder,
}, bar)

-- One "[key] WORD" pair; the key is a light chip with text, or the pad's own button picture.
local function barItem(order)
	local f = ui("Frame", {
		LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X,
	}, bar)
	ui("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
	}, f)
	local chip = ui("Frame", {
		LayoutOrder = 1, Size = UDim2.fromOffset(32, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = BAR_TEXT,
	}, f)
	ui("UICorner", { CornerRadius = UDim.new(0, 7) }, chip)
	ui("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, chip)
	local key = ui("TextLabel", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X,
		FontFace = BAR_FONT, TextSize = 16, TextColor3 = BAR_INK, Text = "",
	}, chip)
	local pic = ui("ImageLabel", { LayoutOrder = 2, BackgroundTransparency = 1, Size = UDim2.fromOffset(32, 32), Visible = false }, f)
	local label = ui("TextLabel", {
		LayoutOrder = 3, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X,
		FontFace = BAR_FONT, TextSize = 16, TextColor3 = BAR_TEXT, Text = "",
	}, f)
	return { Frame = f, Chip = chip, Key = key, Pic = pic, Label = label }
end

local fireItem = barItem(1)
local leaveItem = barItem(2)
local heatBox = ui("Frame", { Name = "Heat", LayoutOrder = 3, Size = UDim2.fromOffset(104, 32), BackgroundTransparency = 1 }, bar)
local heatLabel = ui("TextLabel", {
	BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), FontFace = BAR_FONT, TextSize = 13,
	TextColor3 = BAR_TEXT, Text = "HEAT", TextXAlignment = Enum.TextXAlignment.Left,
}, heatBox)
local heatTrack = ui("Frame", {
	Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 8), BorderSizePixel = 0,
	BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.75,
}, heatBox)
ui("UICorner", { CornerRadius = UDim.new(1, 0) }, heatTrack)
local heatFill = ui("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, BackgroundColor3 = BAR_AMBER }, heatTrack)
ui("UICorner", { CornerRadius = UDim.new(1, 0) }, heatFill)
local offButton = ui("TextButton", {
	Name = "GetOff", LayoutOrder = 4, Size = UDim2.fromOffset(120, 56), Visible = false, AutoButtonColor = true,
	BackgroundColor3 = BAR_TEXT, FontFace = BAR_FONT, TextSize = 18, TextColor3 = BAR_INK, Text = "GET OFF",
}, bar)
ui("UICorner", { CornerRadius = UDim.new(0, 10) }, offButton)

local function setKey(item, text, code)
	local image = ""
	if code then
		local ok, result = pcall(UserInputService.GetImageForKeyCode, UserInputService, code)
		image = if ok and type(result) == "string" then result else ""
	end
	item.Pic.Image = image
	item.Pic.Visible = image ~= ""
	item.Chip.Visible = image == ""
	item.Key.Text = text
end

local function refreshBar()
	local last = UserInputService:GetLastInputType()
	local pad = Controls.ActiveDevice() == "Pad"
	local touch = not pad and (last == Enum.UserInputType.Touch
		or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled))
	if pad then
		-- Get off shows the Crouch button (B by default): X is also Use, but B is what players reach for to back out.
		local fire, off = Controls.Get("Fire", "Pad")[1], Controls.Get("Crouch", "Pad")[1]
		setKey(fireItem, Controls.ShortText(fire), fire :: any)
		setKey(leaveItem, Controls.ShortText(off), off :: any)
	elseif touch then
		setKey(fireItem, "HOLD", nil)
	else
		local fire = Controls.Get("Fire", "Kb")[1]
		setKey(fireItem, if fire == Enum.UserInputType.MouseButton1 then "CLICK" else Controls.ShortText(fire), nil)
		setKey(leaveItem, Controls.Short("Interact", "Kb"), nil)
	end
	fireItem.Label.Text = "FIRE"
	leaveItem.Label.Text = "GET OFF"
	leaveItem.Frame.Visible = not touch
	offButton.Visible = touch
	-- Just above the HUD's hotbar, at the HUD's own scale.
	local hud = playerGui:FindFirstChild("HUD")
	local hotbar = hud and hud:FindFirstChild("Hotbar")
	local scale = hotbar and hotbar:FindFirstChild("HudScale")
	barScale.Scale = if scale and scale:IsA("UIScale") then scale.Scale else 1
	local height = if hotbar and hotbar:IsA("GuiObject") and hotbar.Visible then hotbar.AbsoluteSize.Y else 0
	bar.Position = UDim2.new(0.5, 0, 1, -(27 + height + 12))
end

local heatShownBar = -1
local function paintHeat(h, over)
	h = math.floor(math.clamp(h, 0, 1) * 50 + 0.5) / 50
	local key = h + (if over then 2 else 0)
	if key == heatShownBar then
		return
	end
	heatShownBar = key
	heatFill.Size = UDim2.fromScale(h, 1)
	heatFill.BackgroundColor3 = if over or h >= 0.8 then BAR_HOT else BAR_AMBER
	heatLabel.Text = if over then "TOO HOT - WAIT" else "HEAT"
	heatLabel.TextColor3 = if over then BAR_HOT else BAR_TEXT
end

local function showBar(on)
	barGui.Enabled = on
	heatShownBar = -1
	if on then
		refreshBar()
		paintHeat(0, false)
	end
end

local function stepGun(dt)
	local nest = mounted
	if not nest then
		return
	end
	local now = os.clock()
	local cam = workspace.CurrentCamera
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	hideCharacter(true)

	-- Aim: mouse, right stick, touch drags.
	local sens = UserSettings():GetService("UserGameSettings").MouseSensitivity
	local delta = UserInputService:GetMouseDelta()
	aimYaw -= delta.X * 0.0032 * sens
	aimPitch -= delta.Y * 0.0032 * sens
	for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if state.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = Vector2.new(state.Position.X, state.Position.Y)
			if v.Magnitude > 0.15 then
				aimYaw -= v.X * 2.2 * dt
				aimPitch += v.Y * 1.6 * dt
			end
		end
	end
	touchFire = false
	for _, t in touches do
		aimYaw -= t.Delta.X * 0.006
		aimPitch -= t.Delta.Y * 0.006
		t.Delta = Vector2.zero
		if not t.Moved and now - t.Start > 0.2 then
			t.Fire = true
		end
		touchFire = touchFire or t.Fire
	end
	local arc = math.rad(nest.Model:GetAttribute("Arc") or 60)
	aimYaw = math.clamp(aimYaw, -arc, arc)
	aimPitch = math.clamp(aimPitch, -PITCH_DOWN, PITCH_UP)
	gunYaw = approach(gunYaw, aimYaw, TURN * dt)
	gunPitch = approach(gunPitch, aimPitch, TURN * dt)

	-- Fire: drawn here at once; the server fires the real rounds from the aim we send.
	local wantFire = trigger or touchFire
	local over = localOver or nest.Model:GetAttribute("Overheated") == true
	local frame = frameOf(nest, gunYaw, gunPitch)
	if wantFire and not over then
		shotAcc += dt / GAP
		local n = 0
		while shotAcc >= 1 and n < 3 do
			shotAcc -= 1
			n += 1
			localShot(nest, frame, now)
		end
		localHeat += dt / HEAT_TIME
		if localHeat >= 1 then
			localHeat, localOver = 1, true
		end
	else
		shotAcc = if wantFire then 0 else 1 -- the next press fires at once
		localHeat = math.max(0, localHeat - dt / COOL_TIME)
		if localOver and localHeat <= 0 then
			localOver = false
		end
	end
	local decay = math.exp(-dt * 14)
	kickPitch *= decay
	kickYaw *= decay
	kickBack *= math.exp(-dt * 25)

	setRig(nest, frame * CFrame.new(0, 0, kickBack))
	nest.Yaw, nest.Pitch = gunYaw, gunPitch
	cam.CFrame = frame * EYE * CFrame.Angles(kickPitch, kickYaw, 0)
	local heatNow = math.max(localHeat, nest.Model:GetAttribute("Heat") or 0)
	applyHeat(nest, heatNow)
	paintHeat(heatNow, over)

	local firing = wantFire and not over
	if now >= sendAt or firing ~= sentFire then
		sendAt = now + SEND
		sentFire = firing
		remote:FireServer("Aim", gunYaw, gunPitch, firing)
	end
end

local function leave()
	local now = os.clock()
	if mounted and now - mountedAt > 0.4 and now - leaveAt > 0.3 then
		leaveAt = now
		remote:FireServer("Dismount")
	end
end

local function onFire(_, state)
	if state == Enum.UserInputState.Begin then
		trigger = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		trigger = false
	end
	return Enum.ContextActionResult.Sink
end

local function onLeave(_, state)
	if state == Enum.UserInputState.Begin and not Controls.Listening then
		leave()
	end
	return Enum.ContextActionResult.Sink
end

offButton.Activated:Connect(leave)
UserInputService.LastInputTypeChanged:Connect(function()
	if barGui.Enabled then
		refreshBar()
	end
end)
Controls.Changed:Connect(function()
	if barGui.Enabled then
		refreshBar()
	end
end)

local function enter(nest)
	mounted = nest
	mountedAt = os.clock()
	local aim = nest.Model:GetAttribute("Aim")
	aimYaw, aimPitch = if typeof(aim) == "Vector2" then aim.X else 0, if typeof(aim) == "Vector2" then aim.Y else 0
	gunYaw, gunPitch = aimYaw, aimPitch
	trigger, touchFire, touches = false, false, {}
	localHeat, localOver = nest.Model:GetAttribute("Heat") or 0, nest.Model:GetAttribute("Overheated") == true
	shotAcc, sendAt, sentFire = 1, 0, false
	kickPitch, kickYaw, kickBack = 0, 0, 0
	local cam = workspace.CurrentCamera
	saved = { Fov = cam.FieldOfView, Mouse = UserInputService.MouseBehavior, Icon = UserInputService.MouseIconEnabled }
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 62
	local ignore = { nest.Model, fxFolder, cam }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local worldFx = workspace:FindFirstChild("Fx")
	if worldFx then
		table.insert(ignore, worldFx)
	end
	localParams.FilterDescendantsInstances = ignore
	-- The player's own keys (Shared.Controls); they follow a rebind made while mounted.
	Controls.Bind("EmplacementFire", "Fire", onFire, 3000)
	Controls.Bind("EmplacementLeave", { "Interact", "Crouch" }, onLeave, 3000)
	RunService:BindToRenderStep("EmplacementGun", Enum.RenderPriority.Camera.Value + 7, stepGun)
	refreshPrompts()
	showBar(true)
end

local function exit()
	local nest = mounted
	if not nest then
		return
	end
	mounted = nil
	showBar(false)
	trigger, touchFire, touches = false, false, {}
	RunService:UnbindFromRenderStep("EmplacementGun")
	Controls.Unbind("EmplacementFire")
	Controls.Unbind("EmplacementLeave")
	hideCharacter(false)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	cam.FieldOfView = saved.Fov or 70
	UserInputService.MouseBehavior = saved.Mouse or Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = if saved.Icon == nil then true else saved.Icon
	nest.TargetYaw, nest.TargetPitch = gunYaw, gunPitch
	refreshPrompts()
end

local syncing = false
local function sync()
	local name = player:GetAttribute("OnEmplacement")
	if not name then
		exit()
		return
	end
	if syncing then
		return
	end
	syncing = true
	task.spawn(function()
		local deadline = os.clock() + 5
		while player:GetAttribute("OnEmplacement") == name and os.clock() < deadline do
			local folder = workspace:FindFirstChild("Emplacements")
			local model = folder and folder:FindFirstChild(name)
			local nest = model and register(model)
			if nest then
				if mounted ~= nest then
					exit()
					enter(nest)
				end
				break
			end
			task.wait(0.1)
		end
		syncing = false
	end)
end
player:GetAttributeChangedSignal("OnEmplacement"):Connect(sync)
player.CharacterAdded:Connect(function()
	if mounted and not player:GetAttribute("OnEmplacement") then
		exit()
	end
end)
sync()

UserInputService.JumpRequest:Connect(leave)

UserInputService.InputBegan:Connect(function(input, processed)
	if mounted and not processed and input.UserInputType == Enum.UserInputType.Touch then
		touches[input] = { Start = os.clock(), Origin = input.Position, Delta = Vector2.zero, Moved = false, Fire = false }
	end
end)
UserInputService.InputChanged:Connect(function(input)
	local t = touches[input]
	if t then
		t.Delta += Vector2.new(input.Delta.X, input.Delta.Y)
		if (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(t.Origin.X, t.Origin.Y)).Magnitude > 12 and not t.Fire then
			t.Moved = true
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	touches[input] = nil
end)

-- Near guns, every frame: smooth turning, flashes, tracers, blasts --------------------------------------

local nearAt = 0
RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	if now >= nearAt then
		nearAt = now + 0.5
		table.clear(near)
		local cp = camPos()
		for _, nest in nests do
			if (nest.Swivel.Position - cp).Magnitude <= DRAW then
				table.insert(near, nest)
			end
		end
	end
	local k = 1 - math.exp(-dt * 10)
	for _, nest in near do
		if nest ~= mounted then
			local dy, dp = nest.TargetYaw - nest.Yaw, nest.TargetPitch - nest.Pitch
			if math.abs(dy) > 0.0005 or math.abs(dp) > 0.0005 then
				nest.Yaw += dy * k
				nest.Pitch += dp * k
				setRig(nest, frameOf(nest, nest.Yaw, nest.Pitch))
			end
		end
	end
	if #tracers > 0 then
		updateTracers(now)
	end
	if #pending > 0 then
		updatePending(now)
	end
	if next(flashing) then
		updateFlashes(now)
	end
	if next(liveFlashes) then
		updateShellFlashes(now)
	end
	if #chunks > 0 then
		updateChunks(dt)
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		updateScorches(os.clock())
	end
end)
