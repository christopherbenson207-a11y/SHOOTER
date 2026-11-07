--!strict
-- The weather on this screen (Shared.Weather, 7 Nov 2026). WeatherServer names a preset and when its blend started
-- (workspace Weather, WeatherFrom, WeatherStart, WeatherBlend); this script eases Lighting, Atmosphere, Clouds, the
-- set's grade, bloom, sun rays and wind from what is on screen to the new preset over that time, timed from the
-- server clock so every screen matches. A preset only moves what it names; the rest stays as the place was saved.
-- It also drops the precipitation: one invisible box per kind rides with the camera and sheds flakes, dust or ice
-- motes into the world (LockedToPart off, so turning and running look right). Indoors (something solid right above
-- the camera) it eases off. Graphics Medium 60%, Low 35%, phones and tablets 60%. Workspace Snow = false stops it.
-- Replaces Snowfall and SnowFx (4 Nov), which were the campaign's two always-on snow boxes.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weather = require(Shared:WaitForChild("Weather"))

local set = Weather.Set()
if not set then
	return
end

local player = Players.LocalPlayer
local FLAKE = "rbxasset://textures/particles/smoke_main.dds"

local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
local grade = if set.Grade then Lighting:FindFirstChild(set.Grade) else nil
if grade and not grade:IsA("ColorCorrectionEffect") then
	grade = nil
end
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")

type Values = { [string]: any }

local KINDS = { "Snow", "Blizzard", "Motes", "Dust" }

local function read(): Values
	local v: Values = {
		Clock = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		Outdoor = Lighting.OutdoorAmbient,
		Exposure = Lighting.ExposureCompensation,
		Wind = workspace.GlobalWind,
		WindSound = 0,
		Gusts = 0,
	}
	if atmo then
		v.AtmoDensity, v.AtmoOffset, v.AtmoHaze, v.AtmoGlare = atmo.Density, atmo.Offset, atmo.Haze, atmo.Glare
		v.AtmoColor, v.AtmoDecay = atmo.Color, atmo.Decay
	end
	if clouds then
		v.CloudCover, v.CloudDensity, v.CloudColor = clouds.Cover, clouds.Density, clouds.Color
	end
	if grade then
		local g = grade :: ColorCorrectionEffect
		v.GradeBrightness, v.GradeContrast, v.GradeSaturation, v.GradeTint = g.Brightness, g.Contrast, g.Saturation, g.TintColor
	end
	if bloom then
		v.Bloom = bloom.Intensity
	end
	if rays then
		v.SunRays = rays.Intensity
	end
	for _, kind in KINDS do
		v["Fall" .. kind] = 0
		v["Glow" .. kind] = 0
	end
	return v
end

-- The place as saved (LightingGuard has already put the server's lighting back by the time this runs).
local base = read()

local function resolve(preset: Weather.Preset?): Values
	local v = table.clone(base)
	if not preset then
		return v
	end
	v.Clock = preset.Clock or v.Clock
	v.Brightness = preset.Brightness or v.Brightness
	v.Ambient = preset.Ambient or v.Ambient
	v.Outdoor = preset.Outdoor or v.Outdoor
	v.Exposure = preset.Exposure or v.Exposure
	v.Wind = preset.Wind or v.Wind
	v.WindSound = preset.WindSound or 0
	v.Gusts = if preset.Gusts then 1 else 0
	local a = preset.Atmo
	if a and atmo then
		v.AtmoDensity = a.Density or v.AtmoDensity
		v.AtmoOffset = a.Offset or v.AtmoOffset
		v.AtmoHaze = a.Haze or v.AtmoHaze
		v.AtmoGlare = a.Glare or v.AtmoGlare
		v.AtmoColor = a.Color or v.AtmoColor
		v.AtmoDecay = a.Decay or v.AtmoDecay
	end
	local c = preset.Clouds
	if c and clouds then
		v.CloudCover = c.Cover or v.CloudCover
		v.CloudDensity = c.Density or v.CloudDensity
		v.CloudColor = c.Color or v.CloudColor
	end
	local g = preset.Grade
	if g and grade then
		v.GradeBrightness = g.Brightness or v.GradeBrightness
		v.GradeContrast = g.Contrast or v.GradeContrast
		v.GradeSaturation = g.Saturation or v.GradeSaturation
		v.GradeTint = g.Tint or v.GradeTint
	end
	if bloom and preset.Bloom then
		v.Bloom = preset.Bloom
	end
	if rays and preset.SunRays then
		v.SunRays = preset.SunRays
	end
	if preset.Fall then
		v["Fall" .. preset.Fall.Kind] = preset.Fall.Rate
		v["Glow" .. preset.Fall.Kind] = preset.Fall.Glow or 0
	end
	return v
end

local function lerp(a: any, b: any, t: number): any
	local kind = typeof(a)
	if kind == "number" then
		return a + (b - a) * t
	elseif kind == "Color3" or kind == "Vector3" then
		return a:Lerp(b, t)
	end
	return if t < 0.5 then a else b
end

local function mix(a: Values, b: Values, t: number): Values
	local out: Values = {}
	for k, va in a do
		local vb = b[k]
		if vb == nil then
			out[k] = va
		elseif k == "Clock" then
			-- the short way round the clock (17.4 to 22.5 goes forward, never back through noon)
			local d = ((vb - va + 12) % 24) - 12
			out[k] = (va + d * t) % 24
		else
			out[k] = lerp(va, vb, t)
		end
	end
	return out
end

-- Where each value lives. A blend writes only the values one of its two presets changes (owned), so lighting that
-- other scripts drive (the Zombies room flicker sets Ambient) is left alone.
type Target = { Inst: Instance?, Prop: string }
local TARGETS: { [string]: Target } = {
	Clock = { Inst = Lighting, Prop = "ClockTime" },
	Brightness = { Inst = Lighting, Prop = "Brightness" },
	Ambient = { Inst = Lighting, Prop = "Ambient" },
	Outdoor = { Inst = Lighting, Prop = "OutdoorAmbient" },
	Exposure = { Inst = Lighting, Prop = "ExposureCompensation" },
	AtmoDensity = { Inst = atmo, Prop = "Density" },
	AtmoOffset = { Inst = atmo, Prop = "Offset" },
	AtmoHaze = { Inst = atmo, Prop = "Haze" },
	AtmoGlare = { Inst = atmo, Prop = "Glare" },
	AtmoColor = { Inst = atmo, Prop = "Color" },
	AtmoDecay = { Inst = atmo, Prop = "Decay" },
	CloudCover = { Inst = clouds, Prop = "Cover" },
	CloudDensity = { Inst = clouds, Prop = "Density" },
	CloudColor = { Inst = clouds, Prop = "Color" },
	GradeBrightness = { Inst = grade, Prop = "Brightness" },
	GradeContrast = { Inst = grade, Prop = "Contrast" },
	GradeSaturation = { Inst = grade, Prop = "Saturation" },
	GradeTint = { Inst = grade, Prop = "TintColor" },
	Bloom = { Inst = bloom, Prop = "Intensity" },
	SunRays = { Inst = rays, Prop = "Intensity" },
}
local owned: { [string]: boolean } = {}

local function write(v: Values)
	for key in owned do
		local target = TARGETS[key]
		local value = v[key]
		if target and target.Inst and value ~= nil then
			(target.Inst :: any)[target.Prop] = value
		end
	end
end

-- Precipitation ---------------------------------------------------------------------------------------------------
-- Per kind: the box (size, height above the camera, how far upwind), the flakes, and how hard the wind pushes them.
type Look = {
	Box: Vector3,
	Height: number,
	Upwind: number,
	Push: number,
	Make: (ParticleEmitter) -> (),
}

local LOOKS: { [string]: Look } = {
	Snow = {
		Box = Vector3.new(90, 1, 90),
		Height = 26,
		Upwind = 10,
		Push = 0.2,
		Make = function(e)
			e.EmissionDirection = Enum.NormalId.Bottom
			e.Lifetime = NumberRange.new(5.5, 7.5)
			e.Speed = NumberRange.new(4, 6.5)
			e.SpreadAngle = Vector2.new(12, 12)
			e.RotSpeed = NumberRange.new(-40, 40)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0.14) })
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.08, 0.15),
				NumberSequenceKeypoint.new(0.85, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Color = ColorSequence.new(Color3.fromRGB(244, 246, 252))
			e.Brightness = 1.6
		end,
	},
	-- Driving snow: falls fast and is shoved sideways hard; each flake is stretched along its flight, so it streaks
	-- across the view. Brighter than plain snow, or it vanishes into the white fog.
	Blizzard = {
		Box = Vector3.new(80, 22, 80),
		Height = 10,
		Upwind = 25,
		Push = 0.6,
		Make = function(e)
			e.EmissionDirection = Enum.NormalId.Bottom
			e.Lifetime = NumberRange.new(2, 2.8)
			e.Speed = NumberRange.new(14, 20)
			e.SpreadAngle = Vector2.new(25, 25)
			e.RotSpeed = NumberRange.new(0, 0)
			e.Orientation = Enum.ParticleOrientation.VelocityParallel
			e.Squash = NumberSequence.new(1.4)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0.22) })
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.1, 0.1),
				NumberSequenceKeypoint.new(0.85, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Color = ColorSequence.new(Color3.fromRGB(240, 244, 252))
			e.LightEmission = 0.25
			e.Brightness = 2
		end,
	},
	-- Freezing fog: tiny glints of ice hanging round you, barely drifting.
	Motes = {
		Box = Vector3.new(70, 24, 70),
		Height = 3,
		Upwind = 0,
		Push = 0.05,
		Make = function(e)
			e.EmissionDirection = Enum.NormalId.Top
			e.Lifetime = NumberRange.new(4, 7)
			e.Speed = NumberRange.new(0.2, 0.6)
			e.SpreadAngle = Vector2.new(180, 180)
			e.RotSpeed = NumberRange.new(0, 0)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0.05) })
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.35),
				NumberSequenceKeypoint.new(0.7, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Color = ColorSequence.new(Color3.fromRGB(230, 240, 255))
			e.LightEmission = 0.8
			e.Brightness = 2
		end,
	},
	-- Blowing sand: big faint puffs pushed along the ground.
	Dust = {
		Box = Vector3.new(140, 10, 140),
		Height = 3,
		Upwind = 55,
		Push = 0.8,
		Make = function(e)
			e.EmissionDirection = Enum.NormalId.Bottom
			e.Lifetime = NumberRange.new(3, 4.5)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.SpreadAngle = Vector2.new(30, 30)
			e.RotSpeed = NumberRange.new(-20, 20)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.84),
				NumberSequenceKeypoint.new(0.8, 0.9),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Color = ColorSequence.new(Color3.fromRGB(196, 168, 130))
			e.Brightness = 1
		end,
	},
}

local boxes: { [string]: { Part: BasePart, Emitter: ParticleEmitter } } = {}

local function boxFor(kind: string)
	local made = boxes[kind]
	if made then
		return made
	end
	local look = LOOKS[kind]
	local part = Instance.new("Part")
	part.Name = "Weather" .. kind
	part.Size = look.Box
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local e = Instance.new("ParticleEmitter")
	e.Name = "Fall"
	e.Texture = FLAKE
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rotation = NumberRange.new(0, 360)
	e.LightInfluence = 1
	e.LightEmission = 0
	e.LockedToPart = false
	e.Rate = 0
	e.Enabled = false
	look.Make(e)
	e.Parent = part
	part.Parent = workspace.CurrentCamera
	made = { Part = part, Emitter = e }
	boxes[kind] = made
	return made
end

local function quality(): number
	local tier = player:GetAttribute("GraphicsTier")
	local k = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then 0.6 else 1
	if tier == "Low" then
		return k * 0.35
	elseif tier == "Medium" then
		return k * 0.6
	end
	return k
end

-- Indoors: something solid within 45 studs straight above the camera.
local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Exclude
roofParams.RespectCanCollide = true
local covered = 0 -- eased 0 (open sky) .. 1 (under a roof)
local underRoof = false
local nextRoofCheck = 0

-- Blending ---------------------------------------------------------------------------------------------------------
local shown: Values = base
local fromV: Values = base
local toV: Values = base
local startAt = 0
local blendFor = 0
local blending = false
local started = false

local function begin()
	local start = workspace:GetAttribute("WeatherStart")
	if typeof(start) ~= "number" then
		return
	end
	toV = resolve(Weather.Preset(workspace:GetAttribute("Weather")))
	-- Joining: start from the preset before (or the place as saved); later changes start from what's on screen.
	fromV = if started then shown else resolve(Weather.Preset(workspace:GetAttribute("WeatherFrom")))
	started = true
	-- The values this blend moves: whatever either end changes from the place as saved.
	owned = {}
	for key, saved in base do
		if fromV[key] ~= saved or toV[key] ~= saved then
			owned[key] = true
		end
	end
	startAt = start
	local blend = workspace:GetAttribute("WeatherBlend")
	blendFor = if typeof(blend) == "number" then blend else 0
	blending = true
end

workspace:GetAttributeChangedSignal("WeatherStart"):Connect(begin)
begin()

-- Wind howl for the stormy presets (the Night/Wind loop, in its own Ambience group).
local howl: Sound? = nil
local howlBase = 0
do
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	local night = sounds and sounds:FindFirstChild("Night")
	local wind = night and night:FindFirstChild("Wind")
	if wind and wind:IsA("Sound") then
		howlBase = wind.Volume
		local s = wind:Clone()
		s.Name = "WeatherHowl"
		s.Looped = true
		s.Volume = 0
		s.Parent = workspace.CurrentCamera
		howl = s
	end
end

local function step(dt: number)
	local now = workspace:GetServerTimeNow()
	local moving = blending -- still true on the blend's last frame, so its end values get written
	if blending then
		local a = if blendFor <= 0 then 1 else math.clamp((now - startAt) / blendFor, 0, 1)
		shown = mix(fromV, toV, a * a * (3 - 2 * a))
		write(shown)
		if a >= 1 then
			blending = false
		end
	end

	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position

	-- Gusts: the wind surges and drops on a slow noise.
	local gust = 1
	if shown.Gusts > 0 then
		gust = 1 + shown.Gusts * 0.7 * math.noise(now * 0.18, 4.2)
		workspace.GlobalWind = shown.Wind * gust
	elseif moving and owned.Wind then
		workspace.GlobalWind = shown.Wind
	end

	if os.clock() >= nextRoofCheck then
		nextRoofCheck = os.clock() + 0.3
		local list: { Instance } = { cam }
		if player.Character then
			table.insert(list, player.Character)
		end
		roofParams.FilterDescendantsInstances = list
		underRoof = workspace:Raycast(camPos, Vector3.new(0, 45, 0), roofParams) ~= nil
	end
	covered = math.clamp(covered + ((if underRoof then 1 else 0) - covered) * math.min(1, dt * 3), 0, 1)

	local off = workspace:GetAttribute("Snow") == false
	local q = quality() * (1 - covered)
	local wind = shown.Wind :: Vector3
	local flat = Vector3.new(wind.X, 0, wind.Z)
	local upwind = if flat.Magnitude > 0.01 then -flat.Unit else Vector3.zero
	for _, kind in KINDS do
		local rate = if off then 0 else (shown["Fall" .. kind] :: number) * q
		local made = boxes[kind]
		if rate > 0.5 or made then
			made = made or boxFor(kind)
			local look = LOOKS[kind]
			local e = made.Emitter
			e.Rate = rate
			e.Enabled = rate > 0.5
			e.Acceleration = wind * gust * look.Push
			e.LightInfluence = 1 - (shown["Glow" .. kind] :: number)
			made.Part.CFrame = CFrame.new(camPos + Vector3.new(0, look.Height, 0) + upwind * look.Upwind)
		end
	end

	if howl then
		local want = shown.WindSound * gust * (1 - covered * 0.6)
		howl.Volume = howlBase * want * 2.2
		if want > 0.01 and not howl.IsPlaying then
			howl:Play()
		elseif want <= 0.01 and howl.IsPlaying then
			howl:Stop()
		end
	end
end

RunService:BindToRenderStep("Weather", Enum.RenderPriority.Camera.Value + 10, step)
