--!strict
-- Shared.MuzzleFx (7 Nov 2026): the flash at the tip of every gun, different per gun.
--
-- Each gun family has its own flash: a front-on burst in its own shape (sprites from horror-shooter/vfx/make_flash.py
-- and make_flash2.py), a hot core, a side-on flame jet, side jets out of a muzzle brake, embers, a smoke puff, and a
-- heat wisp that curls off the barrel after sustained fire. Every shot varies (frame, turn, size, jet length), so a
-- burst never strobes the same picture. A silencer swaps the flash for a soft gas puff; a flash cap shrinks it into
-- small dim prongs. GameConfig.Guns.X.Feel.Muzzle can name a style or give a table to override one.
--
--   MuzzleFx.Fire(tip, gunName, gun, dir, scale)   flash at an Attachment (the viewmodel's FlashFrom, or a world
--                                                  gun's Muzzle). dir: down the barrel (world). scale: 1 first person.
--   MuzzleFx.Remote(character, gunName, gun, firstEnd)  someone else's shot (ShotFx): finds the Muzzle on their
--                                                  WorldGun (or a soldier model), flashes it, returns its position.
--
-- GunClient keeps the scene light (CombatFx.MuzzleLight) and its spark and smoke emits; this adds the rest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local MuzzleFx = {}

local TEX = {
	Star = "rbxassetid://133665235088795", -- 4-6 petals (make_flash.py)
	Jet = "rbxassetid://98406976901224", -- side-on flame (make_flash.py)
	Prong = "rbxassetid://70417316871215", -- 3-4 thin prongs (make_flash2.py)
	Burst = "rbxassetid://88577675586106", -- ragged fireball (make_flash2.py)
	Pop = "rbxassetid://112856487421069", -- tight round pop (make_flash2.py)
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
}

export type Style = {
	Front: string?, -- TEX key of the front-on burst, nil for none
	FrontSize: NumberRange?, -- studs
	FrontChance: number?, -- 0..1: some autos skip a frame now and then, like a real flash
	FrontTint: Color3?,
	FrontAlpha: number?, -- start transparency
	Life: number, -- seconds the flash shows
	Core: number, -- hot core diameter (studs), 0 for none
	Jet: number, -- forward flame length (studs), 0 for none
	JetWidth: number,
	Side: number, -- muzzle brake side jets: length (studs), 0 for none
	SideWidth: number?,
	Embers: number, -- extra glowing bits thrown forward
	EmberSpeed: NumberRange?,
	EmberSpread: number?,
	Smoke: number, -- puff particles
	SmokeSize: number?,
	SmokeSpeed: NumberRange?,
	SmokeLife: number?,
	Ring: boolean?, -- the puff spreads out sideways (a brake)
	Heat: number, -- wisp heat added per shot (the barrel smokes past 1)
}

local STYLES: { [string]: Style } = {
	-- Pistol: a quick, tight, white-hot pop.
	Pop = {
		Front = "Pop",
		FrontSize = NumberRange.new(0.3, 0.38),
		Life = 0.04,
		Core = 0.2,
		Jet = 0.3,
		JetWidth = 0.13,
		Side = 0,
		Embers = 0,
		Smoke = 1,
		SmokeSize = 0.35,
		Heat = 0.22,
	},
	-- Assault rifle: long thin prongs out of the brake and a lean flame tongue; skips a frame now and then.
	Rifle = {
		Front = "Prong",
		FrontSize = NumberRange.new(0.5, 0.66),
		FrontChance = 0.82,
		Life = 0.045,
		Core = 0.2,
		Jet = 0.6,
		JetWidth = 0.15,
		Side = 0,
		Embers = 1,
		EmberSpeed = NumberRange.new(18, 30),
		EmberSpread = 8,
		Smoke = 2,
		SmokeSize = 0.45,
		Heat = 0.11,
	},
	-- Shotgun: a wide ragged fireball, a fat short flame, a spray of embers and a big grey puff.
	Burst = {
		Front = "Burst",
		FrontSize = NumberRange.new(0.95, 1.2),
		FrontTint = Color3.fromRGB(255, 225, 190),
		Life = 0.06,
		Core = 0.4,
		Jet = 0.8,
		JetWidth = 0.42,
		Side = 0,
		Embers = 12,
		EmberSpeed = NumberRange.new(14, 34),
		EmberSpread = 16,
		Smoke = 5,
		SmokeSize = 0.9,
		SmokeSpeed = NumberRange.new(3, 7),
		SmokeLife = 1.6,
		Heat = 0.7,
	},
	-- Sniper: a long bright flame, two side jets out of the muzzle brake, and a dust ring that hangs.
	Brake = {
		Front = "Star",
		FrontSize = NumberRange.new(0.8, 0.95),
		Life = 0.06,
		Core = 0.32,
		Jet = 1.15,
		JetWidth = 0.24,
		Side = 0.55,
		SideWidth = 0.22,
		Embers = 3,
		EmberSpeed = NumberRange.new(20, 34),
		EmberSpread = 6,
		Smoke = 7,
		SmokeSize = 0.8,
		SmokeSpeed = NumberRange.new(4, 8),
		SmokeLife = 1.8,
		Ring = true,
		Heat = 0.9,
	},
	-- Machine gun: like the rifle but heavier, with more fire in the tongue.
	Heavy = {
		Front = "Prong",
		FrontSize = NumberRange.new(0.62, 0.8),
		FrontChance = 0.9,
		Life = 0.05,
		Core = 0.26,
		Jet = 0.75,
		JetWidth = 0.2,
		Side = 0,
		Embers = 2,
		EmberSpeed = NumberRange.new(18, 30),
		EmberSpread = 9,
		Smoke = 3,
		SmokeSize = 0.6,
		Heat = 0.14,
	},
	-- Silencer: no fire to see, a soft puff of gas and a faint glow inside the can.
	Suppressed = {
		Front = nil,
		Life = 0.04,
		Core = 0.07,
		Jet = 0,
		JetWidth = 0,
		Side = 0,
		Embers = 0,
		Smoke = 2,
		SmokeSize = 0.3,
		SmokeSpeed = NumberRange.new(1, 2.5),
		SmokeLife = 0.9,
		Heat = 0.15,
	},
}
MuzzleFx.Styles = STYLES

-- Which style a gun uses: Feel.Muzzle, then its name, then its fire mode.
local BY_NAME = { Pistol = "Pop", AK = "Rifle", Shotgun = "Burst", Sniper = "Brake", M60 = "Heavy", LMG = "Heavy" }
local BY_MODE = { Semi = "Pop", Auto = "Rifle", Pump = "Burst", Bolt = "Brake" }

local styleCache = setmetatable({}, { __mode = "k" }) :: { [any]: Style }

local function styleFor(gunName: string, gun: any): Style?
	if not gun or gun.Melee then
		return nil
	end
	local cached = styleCache[gun]
	if cached then
		return cached
	end
	local feel = gun.Feel or {}
	if (feel.FlashSize or 1) <= 0 and not gun.Suppressed then
		return nil
	end
	local pick = feel.Muzzle
	local style: Style
	if type(pick) == "table" then
		style = pick
	else
		local name = if type(pick) == "string" then pick else BY_NAME[gunName] or BY_MODE[gun.FireMode] or "Pop"
		style = STYLES[name] or STYLES.Pop
	end
	if gun.Suppressed then
		style = STYLES.Suppressed
	else
		-- A flash cap (Shared.Attachments Mods.Flash) shrinks the flash: small dim prongs, a short jet, few embers.
		local base = GameConfig.Guns[gunName]
		local baseSize = base and base.Feel and base.Feel.FlashSize
		local mul = if baseSize and baseSize > 0 and feel.FlashSize then feel.FlashSize / baseSize else 1
		if mul < 0.7 then
			local s = table.clone(style)
			s.Front = "Prong"
			local fs = style.FrontSize or NumberRange.new(0.5)
			s.FrontSize = NumberRange.new(fs.Min * 0.55, fs.Max * 0.55)
			s.FrontAlpha = 0.45
			s.Core *= 0.6
			s.Jet *= 0.4
			s.Side = 0
			s.Embers = math.floor(s.Embers * 0.4)
			style = s
		end
	end
	styleCache[gun] = style
	return style
end
MuzzleFx.StyleFor = styleFor

-- Rigs ------------------------------------------------------------------------------------------------------------

type Rig = {
	Tip: Attachment,
	Style: Style,
	Front: ParticleEmitter?,
	Core: ParticleEmitter,
	Wisp: ParticleEmitter,
	JetEnd: Attachment,
	Jet: Beam,
	Sides: { { End: Attachment, Beam: Beam } },
	Puff: Attachment,
	Embers: ParticleEmitter,
	Smoke: ParticleEmitter,
	Shot: number,
	Heat: number,
	Scale: number,
}

local rigs = setmetatable({}, { __mode = "k" }) :: { [Attachment]: Rig }

local HOT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 235)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 110)),
})
local FLASH_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.55, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Enabled = false
	e.LightInfluence = 0
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function beam(a0: Attachment, a1: Attachment, parent: Instance): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Texture = TEX.Jet
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureLength = 1
	b.TextureSpeed = 0
	b.FaceCamera = true
	b.LightEmission = 0.75
	b.LightInfluence = 0
	b.Brightness = 1.2
	b.Segments = 1
	b.Transparency = NumberSequence.new(0.2)
	b.Enabled = false
	b.Parent = parent
	return b
end

local function destroyRig(rig: Rig)
	for _, inst in { rig.Front, rig.Core, rig.Wisp, rig.JetEnd, rig.Jet, rig.Puff } :: { Instance? } do
		if inst then
			inst:Destroy()
		end
	end
	for _, side in rig.Sides do
		side.End:Destroy()
		side.Beam:Destroy()
	end
end

local function buildRig(tip: Attachment, style: Style): Rig?
	local holder = tip.Parent
	if not (holder and (holder:IsA("BasePart") or holder:IsA("Terrain"))) then
		return nil
	end
	local front = nil
	if style.Front then
		front = emitter(tip, {
			Name = "MuzzleFront",
			Texture = TEX[style.Front],
			FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
			FlipbookMode = Enum.ParticleFlipbookMode.Random,
			Speed = NumberRange.new(0),
			Rotation = NumberRange.new(0, 360),
			LockedToPart = true,
			LightEmission = 0.75,
			Brightness = 1.3,
			ZOffset = 0.2,
			Color = ColorSequence.new(style.FrontTint or Color3.new(1, 1, 1)),
		})
	end
	local core = emitter(tip, {
		Name = "MuzzleCore",
		Texture = TEX.Pop,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
		FlipbookMode = Enum.ParticleFlipbookMode.Random,
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		LockedToPart = true,
		LightEmission = 1,
		Brightness = 2,
		ZOffset = 0.3,
		Color = HOT,
		Transparency = FLASH_FADE,
	})
	-- Barrel heat: a thin wisp that curls up off the tip after sustained fire.
	local wisp = emitter(tip, {
		Name = "MuzzleWisp",
		Texture = TEX.Smoke,
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 1.6, 0),
		Drag = 1.5,
		Lifetime = NumberRange.new(1.1, 1.8),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0.5) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.82),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(190, 190, 192)),
		LightInfluence = 0.6,
		LockedToPart = false,
	})
	wisp.Enabled = true
	local jetEnd = Instance.new("Attachment")
	jetEnd.Name = "MuzzleJetEnd"
	jetEnd.Parent = holder
	local jet = beam(tip, jetEnd, holder)
	local sides = {}
	if style.Side > 0 then
		for i = 1, 2 do
			local e = Instance.new("Attachment")
			e.Name = "MuzzleSideEnd" .. i
			e.Parent = holder
			local b = beam(tip, e, holder)
			b.Transparency = NumberSequence.new(0.3)
			table.insert(sides, { End = e, Beam = b })
		end
	end
	-- World-space emitters (embers and the puff) ride on their own attachment, pointed down the barrel each shot.
	local puff = Instance.new("Attachment")
	puff.Name = "MuzzlePuff"
	puff.Parent = workspace.Terrain
	local embers = emitter(puff, {
		Name = "MuzzleEmbers",
		Texture = TEX.Spark,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.12, 0.3),
		Speed = style.EmberSpeed or NumberRange.new(16, 28),
		SpreadAngle = Vector2.new(style.EmberSpread or 10, style.EmberSpread or 10),
		Acceleration = Vector3.new(0, -30, 0),
		Drag = 3,
		LightEmission = 1,
		Brightness = 3,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.07), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 196, 110), Color3.fromRGB(255, 120, 40)),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(-1.2),
	})
	local smoke = emitter(puff, {
		Name = "MuzzleSmoke",
		Texture = TEX.Smoke,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new((style.SmokeLife or 1.2) * 0.7, style.SmokeLife or 1.2),
		Speed = style.SmokeSpeed or NumberRange.new(2, 5),
		SpreadAngle = if style.Ring then Vector2.new(80, 80) else Vector2.new(22, 22),
		Acceleration = Vector3.new(0, 0.8, 0),
		Drag = 4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, (style.SmokeSize or 0.5) * 0.5),
			NumberSequenceKeypoint.new(1, (style.SmokeSize or 0.5) * 2.2),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.62),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(176, 172, 166)),
		LightInfluence = 0.7,
	})
	return {
		Tip = tip,
		Style = style,
		Front = front,
		Core = core,
		Wisp = wisp,
		JetEnd = jetEnd,
		Jet = jet,
		Sides = sides,
		Puff = puff,
		Embers = embers,
		Smoke = smoke,
		Shot = 0,
		Heat = 0,
		Scale = 1,
	}
end

local function rigFor(tip: Attachment, style: Style): Rig?
	local rig = rigs[tip]
	if rig and rig.Style ~= style then
		destroyRig(rig)
		rig = nil
	end
	if not rig then
		rig = buildRig(tip, style)
		if rig then
			rigs[tip] = rig
		end
	end
	return rig
end

local function vary(r: NumberRange): number
	return r.Min + math.random() * (r.Max - r.Min)
end

local function upAlong(position: Vector3, dir: Vector3): CFrame
	-- Y along dir, for EmissionDirection Top (the same trick as CombatFx.Emit).
	local right = dir:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-3 then
		right = Vector3.xAxis
	end
	right = right.Unit
	return CFrame.fromMatrix(position, right, dir, right:Cross(dir))
end

function MuzzleFx.Fire(tip: Attachment?, gunName: string, gun: any, dir: Vector3, scale: number?)
	if not tip or not tip.Parent then
		return
	end
	local style = styleFor(gunName, gun)
	if not style then
		return
	end
	local rig = rigFor(tip, style)
	if not rig then
		return
	end
	local k = scale or 1
	dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1)
	local at = tip.WorldPosition
	rig.Shot += 1
	rig.Scale = k
	local shotId = rig.Shot

	if rig.Front and style.FrontSize and math.random() <= (style.FrontChance or 1) then
		rig.Front.Size = NumberSequence.new(vary(style.FrontSize) * k)
		rig.Front.Lifetime = NumberRange.new(style.Life * 1.2)
		rig.Front.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, style.FrontAlpha or 0.2),
			NumberSequenceKeypoint.new(0.6, math.min(1, (style.FrontAlpha or 0.2) + 0.25)),
			NumberSequenceKeypoint.new(1, 1),
		})
		rig.Front:Emit(1)
	end
	if style.Core > 0 then
		rig.Core.Size = NumberSequence.new(style.Core * k * (0.85 + math.random() * 0.3))
		rig.Core.Lifetime = NumberRange.new(style.Life)
		rig.Core:Emit(1)
	end
	if style.Jet > 0 then
		local len = style.Jet * k * (0.75 + math.random() * 0.45)
		rig.JetEnd.WorldPosition = at + dir * len
		rig.Jet.Width0 = style.JetWidth * k * 0.6
		rig.Jet.Width1 = style.JetWidth * k * (0.9 + math.random() * 0.4)
		rig.Jet.Enabled = true
	end
	if #rig.Sides > 0 then
		local right = dir:Cross(Vector3.yAxis)
		right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
		for i, side in rig.Sides do
			local s = if i == 1 then 1 else -1
			local len = style.Side * k * (0.8 + math.random() * 0.35)
			-- a brake throws its gas out and a little back
			side.End.WorldPosition = at + (right * s - dir * 0.2).Unit * len
			side.Beam.Width0 = (style.SideWidth or 0.2) * k * 0.5
			side.Beam.Width1 = (style.SideWidth or 0.2) * k
			side.Beam.Enabled = true
		end
	end
	rig.Puff.WorldCFrame = upAlong(at + dir * 0.1 * k, dir)
	if style.Embers > 0 then
		rig.Embers:Emit(style.Embers)
	end
	if style.Smoke > 0 then
		rig.Smoke:Emit(style.Smoke)
	end
	rig.Heat = math.min(rig.Heat + style.Heat, 2.5)

	task.delay(style.Life, function()
		if rig.Shot ~= shotId then
			return
		end
		rig.Jet.Enabled = false
		for _, side in rig.Sides do
			side.Beam.Enabled = false
		end
	end)
end

-- Someone else's shot: their world gun's Muzzle (GunRoot's, which sits on the barrel for every hold) or a soldier's.
local REMOTE_RANGE = 220
function MuzzleFx.Remote(character: Instance?, gunName: string, gun: any, firstEnd: any): Vector3?
	if not character then
		return nil
	end
	local holder = character:FindFirstChild("WorldGun")
	local tip: Instance? = nil
	if holder then
		local root = holder:FindFirstChild("GunRoot")
		tip = (root and root:FindFirstChild("Muzzle")) or holder:FindFirstChild("Muzzle", true)
	else
		tip = character:FindFirstChild("Muzzle", true)
	end
	if not (tip and tip:IsA("Attachment")) then
		return nil
	end
	local at = tip.WorldPosition
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - at).Magnitude > REMOTE_RANGE then
		return at
	end
	local dir = if typeof(firstEnd) == "Vector3" and (firstEnd - at).Magnitude > 0.5 then (firstEnd - at).Unit
		else (tip :: Attachment).WorldCFrame.LookVector
	MuzzleFx.Fire(tip :: Attachment, gunName, gun, dir, 1.35)
	return at
end

-- Heat: the wisp's rate follows the barrel's heat, which cools over a few seconds.
if RunService:IsClient() then
	RunService.Heartbeat:Connect(function(dt)
		for tip, rig in rigs do
			if not tip.Parent then
				destroyRig(rig)
				rigs[tip] = nil
				continue
			end
			if rig.Heat > 0 then
				rig.Heat = math.max(0, rig.Heat - dt * 0.45)
				local over = math.max(0, rig.Heat - 1)
				rig.Wisp.Rate = over * 14
				rig.Wisp.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.06 * rig.Scale),
					NumberSequenceKeypoint.new(1, 0.45 * rig.Scale),
				})
			elseif rig.Wisp.Rate ~= 0 then
				rig.Wisp.Rate = 0
			end
		end
	end)
end

return MuzzleFx
