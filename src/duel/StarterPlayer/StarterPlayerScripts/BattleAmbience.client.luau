--!strict
-- The war around the fight (7 Nov 2026, FRONTLINE open-world plan phase 1), client only, from the place's
-- Shared.Weather set (Ambience block; a set without one, like the Zombies manor, runs none of this):
--   Artillery  a gun flash on the horizon (beyond the objective when there is one), its thump arriving late
--              (sound covers about 1,100 studs a second), sometimes a salvo of three.
--   Tracers    a burst of anti-aircraft fire climbing into the sky far off.
--   Planes     one to three bombers (Assets.IntroPlane) passing high over with their drone; just the drone where
--              the place has no plane model.
--   Smoke      a smoke column rising behind the objective (workspace Objective), moved when the objective moves.
--   Flares     when the weather preset has Flares (Night Battle): an illumination flare drifting down over the
--              objective every half minute, lighting the ground under it.
-- Nothing here can hurt anyone or block a shot: every piece is local, non-colliding and not queryable.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weather = require(Shared:WaitForChild("Weather"))
local SoundKit = require(Shared:WaitForChild("SoundKit"))

local set = Weather.Set()
local amb = set and set.Ambience
if not set or not amb then
	return
end

local player = Players.LocalPlayer
local rng = Random.new()
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SOUND_SPEED = 1100 -- studs a second
local FLARE_BRIGHT = 3.4
local OUT_TIME = 1.5 -- seconds a flare takes to go out when the weather changes

local folder = Instance.new("Folder")
folder.Name = "BattleAmbience"
folder.Parent = workspace.CurrentCamera

local function quality(): number
	local tier = player:GetAttribute("GraphicsTier")
	local k = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then 0.6 else 1
	return k * (if tier == "Low" then 0.4 elseif tier == "Medium" then 0.7 else 1)
end

local function camPos(): Vector3
	local cam = workspace.CurrentCamera
	return if cam then cam.CFrame.Position else Vector3.zero
end

local function prop(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.Shape = Enum.PartType.Ball
	p.Parent = folder
	return p
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.FilterDescendantsInstances = { folder }

local function groundAt(x: number, z: number, fallback: number): number
	local hit = workspace:Raycast(Vector3.new(x, fallback + 600, z), Vector3.new(0, -1400, 0), groundParams)
	return if hit then hit.Position.Y else fallback - 25
end

local function objective(): Vector3?
	local o = workspace:GetAttribute("Objective")
	return if typeof(o) == "Vector3" then o else nil
end

-- A point far off, on the ground: beyond the objective (the enemy's side of it) when there is one.
local function farPoint(minD: number, maxD: number): Vector3
	local c = camPos()
	local o = objective()
	local yaw
	if o and (Vector3.new(o.X, 0, o.Z) - Vector3.new(c.X, 0, c.Z)).Magnitude > 20 then
		local d = Vector3.new(o.X - c.X, 0, o.Z - c.Z).Unit
		yaw = math.atan2(d.X, d.Z) + rng:NextNumber(-1.1, 1.1)
	else
		yaw = rng:NextNumber(0, math.pi * 2)
	end
	local dist = rng:NextNumber(minD, maxD)
	local x, z = c.X + math.sin(yaw) * dist, c.Z + math.cos(yaw) * dist
	return Vector3.new(x, groundAt(x, z, c.Y), z)
end

-- Moving pieces, stepped each frame. Flare pieces put out early (OutAt) fade from FromT over OUT_TIME seconds.
type Mover = {
	Part: BasePart,
	Vel: Vector3,
	Life: number,
	Age: number,
	Fade: boolean,
	Light: PointLight?,
	Flare: boolean?,
	OutAt: number?,
	FromT: number?,
}
local movers: { Mover } = {}

-- Artillery -------------------------------------------------------------------------------------------------------
local function gunFlash(at: Vector3)
	local d = (at - camPos()).Magnitude
	local p = prop("GunFlash", Vector3.one * 16, Color3.fromRGB(255, 196, 128))
	p.Position = at + Vector3.new(0, 6, 0)
	p.Transparency = 0.15
	table.insert(movers, { Part = p, Vel = Vector3.zero, Life = 0.35, Age = 0, Fade = true })
	local glow = prop("GunGlow", Vector3.one * 60, Color3.fromRGB(255, 150, 80))
	glow.Position = at + Vector3.new(0, 18, 0)
	glow.Transparency = 0.75
	table.insert(movers, { Part = glow, Vel = Vector3.new(0, 10, 0), Life = 0.5, Age = 0, Fade = true })
	task.delay(d / SOUND_SPEED, function()
		local loud = math.clamp(260 / math.max(d, 1), 0.08, 0.32)
		SoundKit.Play("Intro/Artillery", { Volume = loud, Speed = rng:NextNumber(0.7, 0.88) })
	end)
end

local function artillery()
	local at = farPoint(520, 950)
	local shots = if rng:NextNumber() < 0.3 then 3 else 1
	for i = 1, shots do
		task.delay((i - 1) * rng:NextNumber(0.25, 0.6), gunFlash, at + Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(-40, 40)))
	end
end

-- Tracers ---------------------------------------------------------------------------------------------------------
local TRACER_COLORS = { Color3.fromRGB(255, 120, 60), Color3.fromRGB(255, 170, 70), Color3.fromRGB(140, 255, 120) }

local function tracers()
	local at = farPoint(600, 1000)
	local color = TRACER_COLORS[rng:NextInteger(1, #TRACER_COLORS)]
	local yaw = rng:NextNumber(0, math.pi * 2)
	local count = rng:NextInteger(8, 14)
	for i = 1, count do
		task.delay(i * rng:NextNumber(0.07, 0.14), function()
			local sweep = yaw + i * 0.03
			local elev = math.rad(rng:NextNumber(58, 78))
			local dir = Vector3.new(math.sin(sweep) * math.cos(elev), math.sin(elev), math.cos(sweep) * math.cos(elev))
			local p = prop("Tracer", Vector3.new(1.4, 1.4, 34), color)
			p.Shape = Enum.PartType.Block
			p.CFrame = CFrame.lookAt(at, at + dir)
			table.insert(movers, { Part = p, Vel = dir * 420, Life = 1.3, Age = 0, Fade = false })
		end)
	end
	local d = (at - camPos()).Magnitude
	task.delay(d / SOUND_SPEED + 0.6, function()
		SoundKit.Play("Intro/Flak", { Volume = math.clamp(140 / math.max(d, 1), 0.04, 0.18), Speed = rng:NextNumber(0.85, 1) })
	end)
end

-- Planes ----------------------------------------------------------------------------------------------------------
local function planeTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local m = assets and assets:FindFirstChild("IntroPlane")
	return if m and m:IsA("Model") then m else nil
end

local function planes()
	local c = camPos()
	local yaw = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local side = Vector3.new(dir.Z, 0, -dir.X)
	local passBy = rng:NextNumber(-500, 500)
	local height = c.Y + rng:NextNumber(380, 520)
	local start = c - dir * 1600 + side * passBy
	start = Vector3.new(start.X, height, start.Z)
	local speed = rng:NextNumber(110, 140)
	local life = 3200 / speed
	local template = planeTemplate()
	local count = if template then rng:NextInteger(1, 3) else 1
	for i = 1, count do
		local offset = if i == 1 then Vector3.zero else (-dir * 120 * (i - 1) + side * (if i == 2 then -110 else 110) + Vector3.new(0, 20, 0))
		local holder: BasePart
		local model: Model? = nil
		if template then
			local plane = template:Clone()
			for _, d in plane:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.CastShadow = false
				end
			end
			plane.Parent = folder
			model = plane
		end
		local anchor = prop("PlaneSound", Vector3.one, Color3.new())
		anchor.Transparency = 1
		holder = anchor
		local pos = start + offset
		anchor.CFrame = CFrame.lookAt(pos, pos + dir)
		if model then
			model:PivotTo(anchor.CFrame)
		end
		if i == 1 then
			local s = SoundKit.Play("Intro/EngineDrone", { Parent = anchor, Volume = 1.2 })
			if s then
				s.RollOffMode = Enum.RollOffMode.InverseTapered
				s.RollOffMinDistance = 260
				s.RollOffMaxDistance = 2600
			end
		end
		local mover: Mover = { Part = holder, Vel = dir * speed, Life = life, Age = 0, Fade = false }
		table.insert(movers, mover)
		if model then
			local m = model
			task.spawn(function()
				while anchor.Parent do
					m:PivotTo(anchor.CFrame)
					RunService.RenderStepped:Wait()
				end
				m:Destroy()
			end)
		end
	end
end

-- Smoke column over the objective ---------------------------------------------------------------------------------
local column: Part? = nil
local columnFor: Vector3? = nil

local function placeColumn()
	local o = objective()
	if not amb.Smoke or not o then
		if column then
			column:Destroy()
			column = nil
		end
		return
	end
	if columnFor and (columnFor - o).Magnitude < 1 then
		return
	end
	columnFor = o
	if column then
		column:Destroy()
	end
	-- Behind the objective as seen from wherever you are, so it frames the point and never sits on the flag.
	local c = camPos()
	local away = Vector3.new(o.X - c.X, 0, o.Z - c.Z)
	away = if away.Magnitude > 1 then away.Unit else Vector3.new(0, 0, 1)
	local base = o + away * rng:NextNumber(70, 110) + Vector3.new(rng:NextNumber(-25, 25), 0, rng:NextNumber(-25, 25))
	base = Vector3.new(base.X, groundAt(base.X, base.Z, o.Y) + 4, base.Z)
	local p = prop("SmokeColumn", Vector3.new(16, 2, 16), Color3.new())
	p.Shape = Enum.PartType.Block
	p.Transparency = 1
	p.Position = base
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.EmissionDirection = Enum.NormalId.Top
	e.Lifetime = NumberRange.new(20, 26)
	e.Speed = NumberRange.new(6, 9)
	e.SpreadAngle = Vector2.new(8, 8)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-8, 8)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(0.4, 40), NumberSequenceKeypoint.new(1, 75) })
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.06, 0.4),
		NumberSequenceKeypoint.new(0.6, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(Color3.fromRGB(52, 50, 48), Color3.fromRGB(112, 110, 106))
	e.LightInfluence = 1
	e.LockedToPart = false
	e.Rate = 2.5 * quality()
	e.Parent = p
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 140, 70)
	glow.Range = 30
	glow.Brightness = 1.2
	glow.Shadows = false
	glow.Parent = p
	column = p
end

-- Flares (Night Battle) -------------------------------------------------------------------------------------------
local function flare()
	local o = objective()
	local c = camPos()
	local at = if o then o + Vector3.new(rng:NextNumber(-80, 80), 0, rng:NextNumber(-80, 80)) else c + Vector3.new(rng:NextNumber(-150, 150), 0, rng:NextNumber(-150, 150))
	-- Low enough that the light (60 studs at most) reaches the ground for the whole fall.
	local y = groundAt(at.X, at.Z, at.Y) + rng:NextNumber(45, 58)
	local p = prop("Flare", Vector3.one * 2.4, Color3.fromRGB(255, 244, 220))
	p.Position = Vector3.new(at.X, y, at.Z)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 232, 196)
	light.Range = 60
	light.Brightness = FLARE_BRIGHT
	light.Shadows = false
	light.Parent = p
	local trail = Instance.new("ParticleEmitter")
	trail.Texture = SMOKE
	trail.Lifetime = NumberRange.new(3, 5)
	trail.Speed = NumberRange.new(0.5, 1)
	trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 5) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	trail.Color = ColorSequence.new(Color3.fromRGB(150, 146, 140))
	trail.LightInfluence = 0.6
	trail.Rate = 6 * quality()
	trail.LockedToPart = false
	trail.Parent = p
	local vel = Vector3.new(rng:NextNumber(-1, 1), -1.5, rng:NextNumber(-1, 1))
	table.insert(movers, { Part = p, Vel = vel, Life = 26, Age = 0, Fade = false, Light = light, Flare = true })
	-- A soft halo so it reads as a burning flare from across the valley, not a speck.
	local halo = prop("FlareHalo", Vector3.one * 10, Color3.fromRGB(255, 226, 170))
	halo.Transparency = 0.72
	halo.Position = p.Position
	table.insert(movers, { Part = halo, Vel = vel, Life = 26, Age = 0, Fade = false, Flare = true })
end

local function flaresOn(): boolean
	local preset = Weather.Preset(workspace:GetAttribute("Weather"))
	return preset ~= nil and preset.Flares == true
end

-- Timers ----------------------------------------------------------------------------------------------------------
local function every(range: NumberRange?, fn: () -> (), gate: (() -> boolean)?)
	if not range then
		return
	end
	task.spawn(function()
		task.wait(rng:NextNumber(2, range.Max))
		while folder.Parent do
			if not gate or gate() then
				local ok, err = pcall(fn)
				if not ok then
					warn("[BattleAmbience]", err)
				end
			end
			task.wait(rng:NextNumber(range.Min, range.Max))
		end
	end)
end

every(amb.Artillery, artillery)
every(amb.Tracers, tracers)
every(amb.Planes, planes)
every(NumberRange.new(18, 32), flare, flaresOn)

-- A preset without flares (the next match's morning) puts out the ones still falling.
workspace:GetAttributeChangedSignal("Weather"):Connect(function()
	if flaresOn() then
		return
	end
	for _, m in movers do
		if m.Flare and not m.OutAt then
			m.OutAt = m.Age
			m.FromT = m.Part.Transparency
		end
	end
end)

workspace:GetAttributeChangedSignal("Objective"):Connect(placeColumn)
task.defer(placeColumn)

RunService.RenderStepped:Connect(function(dt: number)
	for i = #movers, 1, -1 do
		local m = movers[i]
		m.Age += dt
		local part = m.Part
		if m.Age >= m.Life or not part.Parent then
			part:Destroy()
			table.remove(movers, i)
		else
			part.CFrame += m.Vel * dt
			local k = m.Age / m.Life
			local out = 0
			if m.OutAt then
				out = math.clamp((m.Age - m.OutAt) / OUT_TIME, 0, 1)
				part.Transparency = 1 - (1 - (m.FromT or 0)) * (1 - out)
				if out >= 1 then
					m.Life = m.Age -- gone next frame
				end
			elseif m.Fade then
				part.Transparency = math.max(part.Transparency, k)
			end
			if m.Light then
				m.Light.Brightness = FLARE_BRIGHT * (1 - k ^ 3) * (1 - out) * (0.85 + 0.15 * math.noise(m.Age * 9, 2.2))
			end
		end
	end
end)
