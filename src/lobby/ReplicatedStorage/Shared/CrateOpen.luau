--!strict
-- Shared.CrateOpen v2 (4 Nov 2026): the crate reward screen. The same module runs in the lobby and the match places.
--   CrateOpen.Earned(info, opts)  after a match: the crate drops onto the stage, its tier slams in, then OPEN NOW or
--                                 OPEN LATER. info = Progression's payload.Crate {Tier, Pity?, Opened?}; Opened (the
--                                 stack was full) skips straight to the reveal.
--   CrateOpen.Open(tier, opts)    the opening: tap the crate (3 taps, it shakes and glows harder each time), it bursts,
--                                 the best reward takes its place, the reward cards deal in.
--   CrateOpen.Odds(opts)          the ODDS panel (Shared.Rewards.Odds, the same tables the server rolls, plus pity).
--   CrateOpen.Tap() / NextTier() / StackSize() / Close()
--   opts = {Request = function(tier) -> (ok, crate | reason), Result = match result?, OnClose = fn?}
-- The server rolls and grants everything (Store action "OpenCrate"); this only shows the answer. Crates are earned by
-- playing, never sold: no countdown and no upsell here.
--
-- 3D: ViewportFrames draw no particles, so the crate stands in a small dark room built on the client far above the map
-- (STAGE_AT) and the camera is moved there while the screen is up (RenderStep "CrateOpenCam", after MenuCamera and the
-- default camera), framing the crate at the centre of the Stage frame for every layout. Other ScreenGuis are switched
-- off while it is up and switched back on at close. Effects: ReplicatedStorage.Assets.CrateFx (Creator Store emitters,
-- no scripts), recoloured per tier. Crates: Assets.Crates.<Tier> (credit in the folder's attribute). Hero: a camo shows
-- on a 3D gun (Assets.WorldGuns, Shared.Camo.Apply, the same pattern the gun wears in game), an operator as the 3D
-- operator (Assets.Operators), anything else as its art.
-- 2D: the lobby's authored plates (ART below: the same images Shared.UiArt holds in the lobby, embedded so the match
-- places, which carry a smaller UiArt, look the same). Layouts: Wide, Phone landscape (crate left, rewards right) and
-- Phone portrait (stacked); Phone = short side < 560; re-laid on every viewport change. Every GuiObject has the _Clone
-- attribute so Menu.Router.Fit skips it.
-- Studio test hook: CrateOpen._Mock = {Player = <Instance with attributes>, Gui = <parent for the ScreenGui>}.

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rewards = require(Shared:WaitForChild("Rewards")) :: any
local Catalogue = require(Shared:WaitForChild("Catalogue")) :: any
local Camo = (Shared:FindFirstChild("Camo") and require(Shared.Camo)) :: any
local Menu = Shared:FindFirstChild("Menu")
local Ui = (Menu and Menu:FindFirstChild("Ui") and require(Menu.Ui)) :: any
local UiSound = (Menu and Menu:FindFirstChild("UiSound") and require(Menu.UiSound)) :: any

local CrateOpen = {} :: any
CrateOpen._Mock = nil

local AMBER = Color3.fromRGB(255, 212, 38) -- kid palette (5 Nov)
local AMBER_INK = Color3.fromRGB(22, 17, 9)
local TEXT = Color3.fromRGB(255, 255, 255)
local DIM = Color3.fromRGB(160, 154, 142)
local INK = Color3.fromRGB(12, 12, 13)
local WHITE = Color3.new(1, 1, 1)
local HEAD = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local BODY = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Medium)
local BODY_BOLD = Font.new("rbxasset://fonts/families/RobotoCondensed.json", Enum.FontWeight.Bold)

-- Lobby menu art (Shared.UiArt keys in brackets). Slice = Rect(left, top, W - right, H - bottom).
local function art(id: string, w: number, h: number, slice: { number }?): any
	return {
		Id = "rbxassetid://" .. id,
		W = w,
		H = h,
		Slice = if slice then Rect.new(slice[1], slice[2], w - slice[3], h - slice[4]) else nil,
	}
end
local ART = {
	Primary = { -- amber hazard plate, notch bottom right (lobby generator primary_button, blank)
		Idle = art("97360370554333", 300, 72),
		Hover = art("95713221099676", 300, 72),
		Down = art("113864883595537", 300, 72),
	},
	Secondary = { -- grunge plate (secondary_button, blank)
		Idle = art("96804529082570", 260, 72),
		Hover = art("101248409218039", 260, 72),
	},
	PanelDeep = art("90141160517978", 56, 56, { 20, 20, 20, 20 }), -- [Kit/PanelDeep]
	Panel = art("116677203377279", 56, 56, { 20, 20, 20, 20 }), -- [Kit/Panel]
	Edge = art("75253411451962", 88, 88, { 40, 40, 40, 40 }), -- [Store/Edge_Idle]
	EdgeNew = art("138955664815629", 88, 88, { 40, 40, 40, 40 }), -- [Store/Edge_Selected]
	Glow = art("125903607342492", 84, 84, { 38, 38, 38, 38 }), -- [Kit/CardGlow]
	Toast = art("95045683012674", 150, 72, { 86, 16, 32, 16 }), -- [Kit/ToastAmber]
	Vignette = art("117123576252414", 1024, 576), -- [Kit/Vignette]
	Scrim = art("114062130093638", 256, 144), -- [Kit/Scrim]
	NewPip = art("96922162369199", 80, 36), -- [Kit/NewPip]
	Scrip = art("86491024538773", 64, 64), -- [Kit/Scrip]
	Underline = art("93625547286301", 64, 3, { 2, 0, 2, 0 }), -- [Kit/TabUnderline]
}

local STAGE_AT = CFrame.new(0, 2600, 0) -- the stage room, far above every map
local FOV = 34
local POWER = { Common = 0.55, Rare = 0.8, Epic = 1.1, Legendary = 1.5 }

local rng = Random.new()

local function me(): any
	local mock = CrateOpen._Mock
	return if mock then mock.Player else Players.LocalPlayer
end

local function sound(name: string)
	if UiSound then
		pcall(UiSound.Play, name)
	end
end

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	if i:IsA("GuiObject") then
		i:SetAttribute("_Clone", true)
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function setImage(img: any, a: any)
	img.Image = a.Id
	if a.Slice then
		img.ScaleType = Enum.ScaleType.Slice
		img.SliceCenter = a.Slice
	else
		img.ScaleType = Enum.ScaleType.Stretch
	end
end

local function image(parent: Instance, a: any, props: { [string]: any }): any
	local img = make("ImageLabel", { BackgroundTransparency = 1, BorderSizePixel = 0 }, nil)
	setImage(img, a)
	for k, v in props do
		img[k] = v
	end
	img.Parent = parent
	return img
end

local function label(parent: Instance, str: string, font: Font, color: Color3, props: { [string]: any }, max: number?): TextLabel
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = str,
		FontFace = font,
		TextColor3 = color,
		TextScaled = true,
		TextWrapped = true,
	}, parent)
	for k, v in props do
		(t :: any)[k] = v
	end
	if max then
		make("UITextSizeConstraint", { MaxTextSize = max, MinTextSize = 10 }, t)
	end
	return t
end

-- Art from the place's own UiArt (camos, operators, products), if it has the key.
local function placeArt(img: any, key: string?): boolean
	if key and Ui and Ui.Art and Ui.Art(key) then
		return (pcall(Ui.SetArt, img, key))
	end
	return false
end

local function tierOf(tier: string)
	return Rewards.Tiers[tier] or Rewards.Tiers.Common
end

-- A camo's rarity (Shared.Camo.Rarity) and its pattern swatch (the ColorMap of MaterialVariant Camo_<Id>, the same
-- pattern the gun wears).
local function rarityOf(item: any): string?
	if item and item.Kind == "Camo" and Camo and Camo.RarityOf then
		return Camo.RarityOf(item.Id)
	end
	return nil
end

local function camoSwatch(item: any): any?
	if not (item and item.Kind == "Camo") then
		return nil
	end
	local v = game:GetService("MaterialService"):FindFirstChild("Camo_" .. item.Id)
	return if v and v:IsA("MaterialVariant") and v.ColorMap ~= "" then { Id = v.ColorMap } else nil
end

local function decode(attr: string): { [string]: any }
	local p = me()
	local ok, t = pcall(HttpService.JSONDecode, HttpService, (p and p:GetAttribute(attr)) or "{}")
	return if ok and type(t) == "table" then t else {}
end

-- The best crate left on the stack (Legendary first), or nil.
function CrateOpen.NextTier(): string?
	local c = decode("Crates")
	for i = #Rewards.Order, 1, -1 do
		local tier = Rewards.Order[i]
		if (tonumber(c[tier]) or 0) > 0 then
			return tier
		end
	end
	return nil
end

function CrateOpen.StackSize(): number
	local n = 0
	for _, v in decode("Crates") do
		n += tonumber(v) or 0
	end
	return n
end

-- state -------------------------------------------------------------------------------------------------------------
local ui: any = nil
local world: any = nil -- the 3D stage
local hidden: { ScreenGui } = {}
local savedFov: number? = nil
local savedType: Enum.CameraType? = nil
local bound = false
local stepConn: RBXScriptConnection? = nil
local opts: any = {}
local state = "Closed"
local tapConn: RBXScriptConnection? = nil
local currentTap: (() -> ())? = nil

local anim = {
	Tier = "Common",
	Crate = nil :: Model?,
	CrateSize = Vector3.new(4, 2.3, 2.6),
	Scale = 1,
	ScaleWant = 1,
	Drop = 0,
	DropV = 0,
	Shake = 0,
	Spin = 0,
	Intensity = 0.3,
	Boost = 0,
	Hero = nil :: Model?,
	HeroKind = "",
	HeroScale = 0,
	HeroSpin = 0,
	HeroSize = Vector3.one * 4,
	HeroOffset = Vector3.zero, -- pivot to bounding-box centre, at full size
	Radius = 2.6,
	D = nil :: number?,
	CamShake = 0,
	UiShake = 0,
}

-- 3D stage ------------------------------------------------------------------------------------------------------------
local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function quiet(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
end

local function buildWorld()
	local cam = workspace.CurrentCamera
	local folder = Instance.new("Model")
	folder.Name = "CrateStage"
	local at = STAGE_AT
	-- the room: concrete floor, dark walls all round so no sky or map shows
	part(folder, { Name = "Floor", Size = Vector3.new(140, 1, 140), CFrame = at * CFrame.new(0, -0.5, 20), Material = Enum.Material.Concrete, Color = Color3.fromRGB(34, 33, 31) })
	part(folder, { Name = "Back", Size = Vector3.new(140, 70, 1), CFrame = at * CFrame.new(0, 30, -16), Material = Enum.Material.Concrete, Color = Color3.fromRGB(26, 26, 28) })
	part(folder, { Name = "Front", Size = Vector3.new(140, 70, 1), CFrame = at * CFrame.new(0, 30, 90), Material = Enum.Material.SmoothPlastic, Color = INK })
	part(folder, { Name = "Left", Size = Vector3.new(1, 70, 110), CFrame = at * CFrame.new(-70, 30, 37), Material = Enum.Material.SmoothPlastic, Color = INK })
	part(folder, { Name = "Right", Size = Vector3.new(1, 70, 110), CFrame = at * CFrame.new(70, 30, 37), Material = Enum.Material.SmoothPlastic, Color = INK })
	part(folder, { Name = "Top", Size = Vector3.new(140, 1, 110), CFrame = at * CFrame.new(0, 65, 37), Material = Enum.Material.SmoothPlastic, Color = INK })
	-- lights: warm key (shadows), tier rim behind, tier wash on the back wall, tier pool under the crate
	local key = part(folder, { Name = "Key", Size = Vector3.one * 0.2, Transparency = 1, CFrame = at * CFrame.new(-6, 9, 9) })
	local keyLight = make("PointLight", { Range = 26, Brightness = 1.6, Color = Color3.fromRGB(255, 236, 210), Shadows = true }, key)
	local rim = part(folder, { Name = "Rim", Size = Vector3.one * 0.2, Transparency = 1, CFrame = at * CFrame.new(4, 5, -5) })
	local rimLight = make("PointLight", { Range = 14, Brightness = 3, Shadows = false }, rim)
	local wash = part(folder, { Name = "Wash", Size = Vector3.one * 0.2, Transparency = 1, CFrame = at * CFrame.new(0, 4, -13) })
	local washLight = make("PointLight", { Range = 22, Brightness = 1.4, Shadows = false }, wash)
	local pool = part(folder, { Name = "Pool", Size = Vector3.one * 0.2, Transparency = 1, CFrame = at * CFrame.new(0, 0.6, 1.5) })
	local poolLight = make("PointLight", { Range = 7, Brightness = 1.2, Shadows = false }, pool)
	-- effects, cloned from Assets.CrateFx onto an anchor at the crate's centre (Rise and Dust on the floor)
	local anchor = part(folder, { Name = "FxAnchor", Size = Vector3.one * 0.2, Transparency = 1, CFrame = at * CFrame.new(0, 1.15, 0) })
	local floorAnchor = part(folder, { Name = "FxFloor", Size = Vector3.one * 0.2, Transparency = 1, CFrame = at * CFrame.new(0, 0.05, 0) })
	local fx: { [string]: { [string]: ParticleEmitter } } = {}
	local base: { [ParticleEmitter]: any } = {}
	local src = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("CrateFx")
	if src then
		for _, att in src:GetChildren() do
			if att:IsA("Attachment") then
				local a = att:Clone()
				for _, d in a:GetDescendants() do
					if not d:IsA("ParticleEmitter") then
						d:Destroy()
					end
				end
				a.Position = Vector3.zero
				a.Parent = if att.Name == "Rise" or att.Name == "Dust" then floorAnchor else anchor
				fx[att.Name] = {}
				for _, e in a:GetChildren() do
					if e:IsA("ParticleEmitter") then
						e.Enabled = false
						fx[att.Name][e.Name] = e
						base[e] = { Rate = e.Rate }
					end
				end
			end
		end
	end
	-- the landing dust as a short puff
	local dust = fx.Dust and fx.Dust.Dust
	if dust then
		dust.Lifetime = NumberRange.new(0.7, 1.5)
		dust.Speed = NumberRange.new(3, 7)
		dust.SpreadAngle = Vector2.new(85, 85)
		dust.Acceleration = Vector3.new(0, 1.5, 0)
		dust.Drag = 3
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.2) })
	end
	-- sparks sized to the crate, not to a character hit
	local sparks = fx.Burst and fx.Burst.Sparks
	if sparks then
		sparks.Speed = NumberRange.new(14, 26)
		sparks.Drag = 3
		sparks.Acceleration = Vector3.new(0, -12, 0)
	end
	-- the column of light under an Epic or Legendary, thinner so it doesn't burn out
	if fx.Rise then
		for _, e in fx.Rise do
			e.Rate *= 0.45
		end
	end
	-- the glow behind the crate stays behind it
	if fx.Idle then
		for _, e in fx.Idle do
			e.ZOffset = -1.5
		end
	end
	folder.Parent = cam
	world = {
		Folder = folder, KeyLight = keyLight, RimLight = rimLight, WashLight = washLight, PoolLight = poolLight,
		Anchor = anchor, Floor = floorAnchor, Fx = fx, Base = base,
	}
end

local function colourFx(tier: string)
	if not world then
		return
	end
	local c = tierOf(tier).Color
	local hot = c:Lerp(WHITE, 0.55)
	for group, list in world.Fx do
		if group ~= "Dust" then
			for name, e in list do
				if name == "Sparks" or name == "Motes" or name == "Flash" then
					e.Color = ColorSequence.new(WHITE, hot)
				else
					e.Color = ColorSequence.new(hot, c)
				end
			end
		end
	end
	world.RimLight.Color = c:Lerp(WHITE, 0.15)
	world.WashLight.Color = c
	world.PoolLight.Color = c
end

local function emit(group: string, name: string, n: number)
	local e = world and world.Fx[group] and world.Fx[group][name]
	if e and n > 0 then
		e:Emit(math.max(1, math.floor(n + 0.5)))
	end
end

local function setIdle(intensity: number)
	anim.Intensity = intensity
	local list = world and world.Fx.Idle
	if not list then
		return
	end
	for _, e in list do
		local r = world.Base[e].Rate
		e.Rate = r * (0.35 + intensity * 1.4)
		-- the white core sits inside the crate; with the crate gone it would wash out the reward
		e.Enabled = intensity > 0.01 and not (e.Name == "Core" and not anim.Crate)
	end
end

local function setRise(on: boolean)
	local list = world and world.Fx.Rise
	if list then
		for _, e in list do
			e.Enabled = on
		end
	end
end

local function clearCrate()
	if anim.Crate then
		anim.Crate:Destroy()
		anim.Crate = nil
	end
end

local function clearHero()
	if anim.Hero then
		anim.Hero:Destroy()
		anim.Hero = nil
	end
	anim.HeroKind = ""
	if ui then
		local h = ui.Stage:FindFirstChild("Hero2D")
		if h then
			h:Destroy()
		end
	end
end

local function setCrate(tier: string)
	clearCrate()
	clearHero()
	anim.Tier = tier
	colourFx(tier)
	local src = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Crates")
	local m = src and src:FindFirstChild(tier)
	if not (m and world) then
		return
	end
	local c = m:Clone() :: Model
	quiet(c)
	for _, d in c:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = true
		end
	end
	c.Parent = world.Folder
	local _, size = c:GetBoundingBox()
	anim.Crate = c
	anim.CrateSize = size
	anim.Scale, anim.ScaleWant = 1, 1
	anim.Radius = Vector3.new(size.X, size.Y, size.Z).Magnitude * 0.5
	world.Anchor.CFrame = STAGE_AT * CFrame.new(0, size.Y * 0.5, 0)
	make("PointLight", { Name = "TierLight", Range = 6, Brightness = 0.8, Color = tierOf(tier).Color }, c.PrimaryPart or c:FindFirstChildWhichIsA("BasePart"))
end

-- The best reward as a 3D model: a camo on a gun, or an operator. Returns false when it has no model.
local function setHero3D(itemId: string?): boolean
	local item = itemId and Catalogue.Items[itemId]
	if not (item and world) then
		return false
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local m: Model? = nil
	local kind = item.Kind
	if kind == "Camo" and Camo and assets and assets:FindFirstChild("WorldGuns") then
		local gunKey = "AK"
		local gun = assets.WorldGuns:FindFirstChild(gunKey) or assets.WorldGuns:FindFirstChildWhichIsA("Model")
		if gun then
			m = gun:Clone()
			pcall(Camo.Apply, m, gun.Name, item.Id)
		end
	elseif kind == "Operator" and assets and assets:FindFirstChild("Operators") then
		local op = assets.Operators:FindFirstChild(item.Id)
		if op and op:IsA("Model") then
			m = op:Clone()
		end
	end
	if not m then
		return false
	end
	quiet(m)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = true
		end
	end
	m.Parent = world.Folder
	local _, size = m:GetBoundingBox()
	local target = if kind == "Camo" then 5.4 else 5.2
	local s = target / math.max(size.X, size.Y, size.Z, 0.1)
	m:ScaleTo(m:GetScale() * s)
	local box, size2 = m:GetBoundingBox()
	anim.Hero = m
	anim.HeroKind = kind
	anim.HeroScale = 0
	anim.HeroSpin = 0
	anim.HeroSize = size2
	anim.HeroOffset = m:GetPivot():PointToObjectSpace(box.Position)
	m:SetAttribute("_S", 1)
	anim.Radius = size2.Magnitude * 0.5
	return true
end

local function hideOtherGuis(parent: Instance)
	for _, g in parent:GetChildren() do
		if g:IsA("ScreenGui") and g ~= (ui and ui.Gui) and g.Enabled then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
end

local function restoreGuis()
	for _, g in hidden do
		if g.Parent then
			g.Enabled = true
		end
	end
	table.clear(hidden)
end

-- per frame ------------------------------------------------------------------------------------------------------------
local function step(dt: number)
	local cam = workspace.CurrentCamera
	if not (cam and world and ui) then
		return
	end
	local t = os.clock()
	-- crate: drop and bounce, shake, a slow sway, pop
	local c = anim.Crate
	if c then
		if anim.Drop > 0 or anim.DropV ~= 0 then
			anim.DropV -= 70 * dt
			anim.Drop += anim.DropV * dt
			if anim.Drop <= 0 then
				anim.Drop = 0
				if math.abs(anim.DropV) > 5 then
					anim.DropV = -anim.DropV * 0.28
					anim.CamShake = math.max(anim.CamShake, math.abs(anim.DropV) * 0.05)
					emit("Dust", "Dust", 5 * (POWER[anim.Tier] or 1))
					sound("Stamp")
				else
					anim.DropV = 0
				end
			end
		end
		anim.Spin += dt * (0.6 + anim.Shake * 3)
		local s = anim.Shake
		local jitter = CFrame.new(rng:NextNumber(-1, 1) * s * 0.09, math.abs(rng:NextNumber(-1, 1)) * s * 0.06, 0)
			* CFrame.Angles(rng:NextNumber(-1, 1) * s * 0.05, 0, rng:NextNumber(-1, 1) * s * 0.07)
		local k = 1 - math.exp(-dt * 30)
		local old = anim.Scale
		anim.Scale += (anim.ScaleWant - anim.Scale) * k
		if math.abs(anim.Scale - old) > 0.002 then
			c:ScaleTo(math.max(0.02, anim.Scale))
		end
		local half = anim.CrateSize.Y * 0.5 * anim.Scale
		c:PivotTo(STAGE_AT * CFrame.new(0, half + anim.Drop, 0) * jitter * CFrame.Angles(0, math.rad(-24) + math.sin(anim.Spin * 0.5) * 0.18, 0))
	end
	-- hero: grows in with overshoot, then turns
	local h = anim.Hero
	if h then
		anim.HeroScale = math.min(1, anim.HeroScale + dt * 3.2)
		local x = anim.HeroScale
		local grow = 1 + 2.4 * (x - 1) ^ 3 + 1.4 * (x - 1) ^ 2 -- back-out ease
		anim.HeroSpin += dt
		local want = math.max(0.02, grow)
		local gun = anim.HeroKind == "Camo"
		local yaw = if gun then anim.HeroSpin * 0.7 else math.pi + math.sin(anim.HeroSpin * 0.6) * 0.45
		-- the bounding-box centre: a gun floats, an operator stands on the floor
		local lift = if gun then 2.2 + math.sin(t * 1.6) * 0.08 else anim.HeroSize.Y * 0.5 * want
		h:PivotTo(STAGE_AT * CFrame.new(0, lift, 0) * CFrame.Angles(0, yaw, if gun then math.rad(8) else 0)
			* CFrame.new(-anim.HeroOffset * want))
		local cur = h:GetAttribute("_S") or 1
		if math.abs(want - cur) > 0.004 then
			h:ScaleTo(h:GetScale() * want / cur)
			h:SetAttribute("_S", want)
		end
	end
	-- lights breathe with the intensity; a reveal flares them
	anim.Boost *= math.exp(-dt * 3)
	local pulse = 0.85 + 0.15 * math.sin(t * 3)
	world.RimLight.Brightness = (1.5 + anim.Intensity * 3 + anim.Boost * 6) * pulse
	world.WashLight.Brightness = 0.8 + anim.Intensity * 1.6 + anim.Boost * 3
	world.PoolLight.Brightness = 0.6 + anim.Intensity * 1.5 + anim.Boost * 4
	world.KeyLight.Brightness = 1.6 + anim.Boost * 1.5
	-- camera: frame the crate (or hero) at the centre of the Stage frame
	local view = cam.ViewportSize
	if view.X < 2 then
		return
	end
	local sp, ss = ui.Stage.AbsolutePosition, ui.Stage.AbsoluteSize
	local u = (sp.X + ss.X * 0.5) / view.X
	local v = (sp.Y + ss.Y * 0.5) / view.Y
	local frac = math.clamp(ss.Y / view.Y, 0.15, 1)
	local tn = math.tan(math.rad(FOV * 0.5))
	local want = anim.Radius / (frac * tn) * 0.92 * (1 - anim.Intensity * 0.06)
	anim.D = if anim.D then anim.D + (want - anim.D) * (1 - math.exp(-dt * 4)) else want
	local d = anim.D :: number
	local aspect = view.X / view.Y
	local x = (2 * u - 1) * aspect * tn * d
	local y = (1 - 2 * v) * tn * d
	anim.CamShake *= math.exp(-dt * 6)
	local cs = anim.CamShake
	local rot = CFrame.Angles(0, math.sin(t * 0.25) * 0.05, 0) * CFrame.Angles(math.rad(-11), 0, 0)
		* CFrame.Angles(rng:NextNumber(-1, 1) * cs * 0.02, rng:NextNumber(-1, 1) * cs * 0.02, rng:NextNumber(-1, 1) * cs * 0.015)
	local focus = STAGE_AT.Position + Vector3.new(0, 1.3, 0)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = FOV
	cam.CFrame = CFrame.new(focus) * rot * CFrame.new(-x, -y, d)
	cam.Focus = CFrame.new(focus)
	-- 2D shake
	if anim.UiShake > 0.01 then
		anim.UiShake *= math.exp(-dt * 7)
		ui.Holder.Position = UDim2.fromOffset(rng:NextNumber(-1, 1) * anim.UiShake * 10, rng:NextNumber(-1, 1) * anim.UiShake * 7)
	else
		ui.Holder.Position = UDim2.new()
	end
end

local function startLoop()
	if bound or stepConn then
		return
	end
	local function run(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("CrateOpen:", err)
		end
	end
	local ok = pcall(function()
		RunService:BindToRenderStep("CrateOpenCam", Enum.RenderPriority.Camera.Value + 20, run)
	end)
	if ok then
		bound = true
	else
		stepConn = RunService.RenderStepped:Connect(run)
	end
end

local function stopLoop()
	if bound then
		pcall(function()
			RunService:UnbindFromRenderStep("CrateOpenCam")
		end)
		bound = false
	end
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

-- 2D screen ------------------------------------------------------------------------------------------------------------
local function build()
	local gui = make("ScreenGui", {
		Name = "CrateOpen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, nil)
	image(gui, ART.Vignette, { Name = "Vignette", Size = UDim2.fromScale(1, 1), ImageTransparency = 0.05, ZIndex = 1 })
	local catcher = make("TextButton", { Name = "Catcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Modal = true, AutoButtonColor = false, Selectable = false, ZIndex = 2 }, gui)
	local holder = make("Frame", { Name = "Holder", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, gui)
	-- safe area inside the holder (notches, home bar)
	local safe = make("Frame", { Name = "Safe", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, holder)
	local stage = make("Frame", { Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 }, safe)
	local kicker = label(safe, "", BODY_BOLD, AMBER, { Name = "Kicker", AnchorPoint = Vector2.new(0.5, 0.5) }, 22)
	make("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.3 }, kicker)
	local title = label(safe, "", HEAD, TEXT, { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5) }, 92)
	local titleScale = make("UIScale", {}, title)
	make("UIStroke", { Color = INK, Thickness = 2.5, Transparency = 0.25 }, title)
	local underline = make("Frame", { Name = "Underline", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = AMBER, BorderSizePixel = 0 }, safe)
	local sub = label(safe, "", BODY_BOLD, DIM, { Name = "Sub", AnchorPoint = Vector2.new(0.5, 0.5) }, 24)
	make("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.3 }, sub)
	local cards = make("Frame", { Name = "Cards", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 }, safe)
	local grid = make("UIGridLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, CellPadding = UDim2.fromOffset(12, 12),
	}, cards)
	local bar = make("Frame", { Name = "Buttons", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 }, safe)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder,
	}, bar)
	local flash = make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8 }, gui)
	local toast = image(gui, ART.Toast, { Name = "Toast", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(520, 52), ImageTransparency = 1, Visible = false, ZIndex = 9 })
	local toastText = label(toast, "", BODY_BOLD, AMBER_INK, { Name = "Text", Position = UDim2.new(0, 26, 0, 8), Size = UDim2.new(1, -52, 1, -16), ZIndex = 10 }, 20)
	ui = {
		Gui = gui, Catcher = catcher, Holder = holder, Safe = safe, Stage = stage, Kicker = kicker, Title = title,
		TitleScale = titleScale, Underline = underline, Sub = sub, Cards = cards, Grid = grid, Bar = bar, Flash = flash,
		Toast = toast, ToastText = toastText, Phone = false, OddsButton = nil,
	}
	return ui
end

local function layout()
	if not ui then
		return
	end
	local size = ui.Gui.AbsoluteSize
	if size.X < 2 then
		local cam = workspace.CurrentCamera
		size = if cam then cam.ViewportSize else Vector2.new(1920, 1080)
	end
	local inset = GuiService:GetGuiInset()
	local short = math.min(size.X, size.Y)
	local phone = short < 560
	local portrait = size.Y > size.X
	ui.Phone = phone
	ui.Safe.Position = UDim2.fromOffset(if phone and not portrait then 44 else 0, inset.Y)
	ui.Safe.Size = UDim2.new(1, if phone and not portrait then -88 else 0, 1, -inset.Y - (if phone then 8 else 0))
	local n = 0
	for _, c in ui.Cards:GetChildren() do
		if c:IsA("GuiObject") then
			n += 1
		end
	end
	n = math.max(1, n)
	local cols
	local function put(inst, px, py, sx, sy)
		inst.Position, inst.Size = UDim2.fromScale(px, py), UDim2.fromScale(sx, sy)
	end
	if phone and not portrait then
		put(ui.Stage, 0.27, 0.56, 0.5, 0.6)
		put(ui.Kicker, 0.27, 0.07, 0.5, 0.05)
		put(ui.Title, 0.27, 0.15, 0.5, 0.11)
		put(ui.Underline, 0.27, 0.215, 0.14, 0.006)
		put(ui.Sub, 0.27, 0.26, 0.52, 0.05)
		put(ui.Cards, 0.75, 0.45, 0.48, 0.62)
		put(ui.Bar, 0.75, 0.88, 0.5, 0.15)
		cols = 2
	elseif phone then
		put(ui.Stage, 0.5, 0.33, 0.9, 0.3)
		put(ui.Kicker, 0.5, 0.06, 0.9, 0.025)
		put(ui.Title, 0.5, 0.1, 0.9, 0.06)
		put(ui.Underline, 0.5, 0.135, 0.22, 0.003)
		put(ui.Sub, 0.5, 0.16, 0.9, 0.03)
		put(ui.Cards, 0.5, 0.66, 0.92, 0.34)
		put(ui.Bar, 0.5, 0.91, 0.94, 0.08)
		cols = 2
	else
		put(ui.Stage, 0.5, 0.42, 0.5, 0.42)
		put(ui.Kicker, 0.5, 0.06, 0.5, 0.03)
		put(ui.Title, 0.5, 0.115, 0.7, 0.08)
		put(ui.Underline, 0.5, 0.163, 0.08, 0.004)
		put(ui.Sub, 0.5, 0.195, 0.7, 0.032)
		put(ui.Cards, 0.5, 0.75, 0.84, 0.22)
		put(ui.Bar, 0.5, 0.925, 0.7, 0.075)
		cols = math.min(n, 4)
	end
	ui.Underline.Size = UDim2.new(ui.Underline.Size.X.Scale, 0, 0, if phone then 3 else 4)
	local rows = math.ceil(n / cols)
	local area = ui.Cards.AbsoluteSize
	local pad = if phone then 8 else 14
	ui.Grid.CellPadding = UDim2.fromOffset(pad, pad)
	local w = (area.X - pad * (cols - 1)) / cols
	local h = (area.Y - pad * (rows - 1)) / rows
	w = math.min(w, h * 1.3, 250)
	h = math.min(h, w * 1.05)
	ui.Grid.CellSize = UDim2.fromOffset(math.max(64, w), math.max(58, h))
	-- buttons keep the plate's shape; touch targets at least 48 px tall
	local bh = math.clamp(ui.Bar.AbsoluteSize.Y, if phone then 48 else 46, if phone then 58 else 60)
	local count = 0
	for _, b in ui.Bar:GetChildren() do
		if b:IsA("ImageButton") then
			count += 1
		end
	end
	for _, b in ui.Bar:GetChildren() do
		if b:IsA("ImageButton") then
			local aspect = b:GetAttribute("Aspect") or 4
			local bw = math.min(bh * aspect, (ui.Bar.AbsoluteSize.X - 16 * (count - 1)) / math.max(count, 1))
			b.Size = UDim2.fromOffset(bw, bw / aspect)
		end
	end
	if ui.OddsButton then
		local oh = if phone then 44 else 46
		ui.OddsButton.Size = UDim2.fromOffset(oh * 260 / 72, oh)
		ui.OddsButton.Position = UDim2.new(1, if phone and not portrait then -52 else -18, 0, inset.Y + (if phone then 8 else 16))
	end
	ui.Toast.Size = UDim2.fromOffset(math.min(560, size.X - 32), if phone then 48 else 54)
end

local function toast(str: string)
	if not ui then
		return
	end
	ui.ToastText.Text = str
	ui.Toast.Visible = true
	ui.Toast.ImageTransparency = 0
	ui.ToastText.TextTransparency = 0
	task.delay(2.6, function()
		if ui and ui.ToastText.Text == str then
			tween(ui.Toast, 0.4, { ImageTransparency = 1 })
			tween(ui.ToastText, 0.4, { TextTransparency = 1 })
		end
	end)
end

local function flash(strength: number)
	ui.Flash.BackgroundColor3 = WHITE:Lerp(tierOf(anim.Tier).Color, 0.3)
	ui.Flash.BackgroundTransparency = 1 - strength
	tween(ui.Flash, 0.35, { BackgroundTransparency = 1 })
end

local function slam(kicker: string, text: string, color: Color3)
	ui.Kicker.Text = kicker
	ui.Kicker.TextTransparency = 0
	ui.Title.Text = text
	ui.Title.TextColor3 = color
	ui.Title.TextTransparency = 0
	ui.Underline.BackgroundColor3 = color
	ui.Underline.BackgroundTransparency = 0
	ui.TitleScale.Scale = 2.2
	tween(ui.TitleScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(0.1, function()
		anim.UiShake = math.max(anim.UiShake, 0.6)
	end)
end

local function clearCards()
	for _, c in ui.Cards:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function clearButtons()
	for _, b in ui.Bar:GetChildren() do
		if b:IsA("ImageButton") then
			b:Destroy()
		end
	end
end

-- A lobby plate button: Primary (amber, dark label) or Secondary (grunge, light label).
local function plateButton(parent: Instance, str: string, primary: boolean, fn: () -> ()): ImageButton
	local set = if primary then ART.Primary else ART.Secondary
	local b = make("ImageButton", {
		Name = str, BackgroundTransparency = 1, AutoButtonColor = false, Image = set.Idle.Id, ScaleType = Enum.ScaleType.Stretch,
		Size = UDim2.fromOffset(set.Idle.W, set.Idle.H), ZIndex = 5,
	}, parent)
	b:SetAttribute("Aspect", set.Idle.W / set.Idle.H)
	local txt = label(b, str, HEAD, if primary then AMBER_INK else TEXT, {
		Name = "Label", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.5), ZIndex = 6,
	}, 28)
	local sc = make("UIScale", {}, b)
	local hovered, pressed = false, false
	local function refresh()
		local a = (pressed and set.Down) or (hovered and set.Hover) or set.Idle
		b.Image = a.Id
		b.ImageColor3 = if pressed and not set.Down then Color3.fromRGB(200, 196, 188) else WHITE
	end
	b.MouseEnter:Connect(function()
		hovered = true
		refresh()
		sound("Hover")
	end)
	b.MouseLeave:Connect(function()
		hovered, pressed = false, false
		refresh()
		tween(sc, 0.08, { Scale = 1 })
	end)
	b.SelectionGained:Connect(function()
		hovered = true
		refresh()
	end)
	b.SelectionLost:Connect(function()
		hovered = false
		refresh()
	end)
	b.InputBegan:Connect(function(input)
		local ty = input.UserInputType
		if ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch then
			pressed = true
			refresh()
			tween(sc, 0.06, { Scale = 0.97 })
		end
	end)
	b.InputEnded:Connect(function(input)
		local ty = input.UserInputType
		if ty == Enum.UserInputType.MouseButton1 or ty == Enum.UserInputType.Touch then
			pressed = false
			refresh()
			tween(sc, 0.08, { Scale = 1 })
		end
	end)
	local busy = false
	b.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		sound("Click")
		task.spawn(fn)
		task.delay(0.3, function()
			busy = false
		end)
	end)
	txt.TextTransparency = 0
	return b
end

local function button(str: string, primary: boolean, order: number, fn: () -> ())
	local b = plateButton(ui.Bar, str, primary, fn)
	b.LayoutOrder = order
	local sc = b:FindFirstChildOfClass("UIScale")
	if sc then
		sc.Scale = 0.6
		tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	layout()
	if primary and UserInputService.GamepadEnabled then
		GuiService.SelectedObject = b
	end
	return b
end

-- One reward card: deep panel, tier-tinted edge (the store's NEW edge for a new item), art or a badge, number, name.
local function card(order: number, color: Color3, artKey: string?, fallback: any?, glyph: string, amount: string, name: string, note: string?, isNew: boolean, badge: Color3?)
	local f = make("Frame", { Name = "Card" .. order, LayoutOrder = order, BackgroundTransparency = 1, ZIndex = 5 }, ui.Cards)
	image(f, ART.Glow, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 34, 1, 34), ImageColor3 = color, ImageTransparency = if isNew then 0.05 else 0.55, ZIndex = 4 })
	image(f, ART.PanelDeep, { Name = "Panel", Size = UDim2.fromScale(1, 1), ZIndex = 5 })
	image(f, if isNew then ART.EdgeNew else ART.Edge, { Name = "Edge", Size = UDim2.fromScale(1, 1), ImageColor3 = if isNew then WHITE else color, ZIndex = 6 })
	local icon = make("ImageLabel", {
		Name = "Icon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.09), Size = UDim2.fromScale(0.72, 0.42),
		BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 7,
	}, f)
	local has = placeArt(icon, artKey)
	if has then
		icon.ScaleType = Enum.ScaleType.Fit
	elseif fallback then
		icon.Image = fallback.Id
		icon.ScaleType = Enum.ScaleType.Fit
		has = true
	end
	if not has then
		local disc = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8), BackgroundColor3 = badge or color, ZIndex = 7 }, icon)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disc)
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, disc)
		make("UIStroke", { Color = WHITE, Thickness = 2, Transparency = 0.4 }, disc)
		label(disc, glyph, HEAD, WHITE, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromScale(0.8, 0.8), ZIndex = 8 })
	end
	local amt = label(f, amount, HEAD, TEXT, { Name = "Amount", Position = UDim2.fromScale(0.06, 0.53), Size = UDim2.fromScale(0.88, 0.23), ZIndex = 7 }, 40)
	label(f, name, BODY_BOLD, DIM, { Name = "Name", Position = UDim2.fromScale(0.06, 0.76), Size = UDim2.fromScale(0.88, if note then 0.1 else 0.15), ZIndex = 7 }, 17)
	if note then
		label(f, note, BODY_BOLD, color:Lerp(WHITE, 0.25), { Name = "Note", Position = UDim2.fromScale(0.06, 0.865), Size = UDim2.fromScale(0.88, 0.09), ZIndex = 7 }, 14)
	end
	if isNew then
		image(f, ART.NewPip, { Name = "New", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromScale(0.34, 0.15), ZIndex = 8 })
		make("UIAspectRatioConstraint", { AspectRatio = 80 / 36 }, f:FindFirstChild("New"))
	end
	local sc = make("UIScale", { Scale = 0 }, f)
	f.Rotation = rng:NextNumber(-7, 7)
	return f, sc, amt
end

local function showCards(crate: any)
	clearCards()
	local tier = tierOf(crate.Tier)
	local list = {}
	-- {artKey, fallback, glyph, amount, name, note, countUp, badge, isNew}
	table.insert(list, { "Kit/Scrip", ART.Scrip, "$", crate.Scrip, "GEMS", nil, true, nil, false })
	if (crate.Tokens or 0) > 0 then
		table.insert(list, { "Product/Revive", nil, "+", "x" .. crate.Tokens, if crate.Tokens > 1 then "REVIVE TOKENS" else "REVIVE TOKEN", nil, false, Color3.fromRGB(200, 64, 52), false })
	end
	if (crate.Boosts or 0) > 0 then
		table.insert(list, { "Product/SquadBoost", nil, "^", "x" .. crate.Boosts, "SQUAD BOOST", nil, false, Color3.fromRGB(70, 160, 84), false })
	end
	if crate.Item then
		local item = Catalogue.Items[crate.Item]
		local rarity = rarityOf(item)
		local swatch = camoSwatch(item)
		local kindName = string.upper(item and item.Kind or "ITEM")
		table.insert(list, {
			if swatch then nil else item and item.Art, swatch, "*", item and item.Name or crate.Item,
			if rarity then string.upper(rarity) .. " " .. kindName else kindName, "UNLOCKED", false, nil, true,
			if rarity then tierOf(rarity).Color else nil,
		})
	elseif crate.Dupe then
		table.insert(list, { "Kit/Scrip", ART.Scrip, "$", "+" .. crate.Dupe, "BONUS GEMS", "POOL ALL OWNED", false, nil, false })
	end
	for i, row in list do
		local f, sc, amt = card(i, row[10] or tier.Color, row[1], row[2], row[3], if row[7] then "0" else tostring(row[4]), row[5], row[6], row[9], row[8])
		task.delay(0.1 + (i - 1) * 0.18, function()
			if not f.Parent then
				return
			end
			sound("Tick")
			tween(sc, 0.36, { Scale = 1 }, Enum.EasingStyle.Back)
			tween(f, 0.36, { Rotation = 0 }, Enum.EasingStyle.Back)
			if row[7] then
				local target = tonumber(row[4]) or 0
				local t0 = os.clock()
				while os.clock() - t0 < 0.9 and amt.Parent do
					local k = (os.clock() - t0) / 0.9
					amt.Text = Ui and Ui.Money and Ui.Money(target * (1 - (1 - k) ^ 3)) or tostring(math.floor(target * (1 - (1 - k) ^ 3)))
					task.wait()
				end
				amt.Text = Ui and Ui.Money and Ui.Money(target) or tostring(target)
			end
			if row[9] then
				anim.UiShake = math.max(anim.UiShake, 0.5)
				anim.Boost = math.max(anim.Boost, 0.6)
				emit("Burst", "Stars", 3)
				sound("Stamp")
			end
		end)
	end
	layout()
end

-- open / close ----------------------------------------------------------------------------------------------------------
local function guiParent(): Instance
	local mock = CrateOpen._Mock
	if mock and mock.Gui then
		return mock.Gui
	end
	return me():WaitForChild("PlayerGui")
end

local function open()
	if not ui then
		build()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
		end
		ui.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
		local odds = plateButton(ui.Gui, "ODDS", false, function()
			CrateOpen.Odds(opts)
		end)
		odds.Name = "OddsButton"
		odds.AnchorPoint = Vector2.new(1, 0)
		odds.ZIndex = 7
		ui.OddsButton = odds
	end
	local parent = guiParent()
	if ui.Gui.Parent ~= parent then
		ui.Gui.Parent = parent
	end
	if not ui.Gui.Enabled then
		hideOtherGuis(parent)
		local cam = workspace.CurrentCamera
		savedFov = cam and cam.FieldOfView
		savedType = cam and cam.CameraType
		anim.D = nil
	end
	if not world then
		buildWorld()
	end
	ui.Gui.Enabled = true
	layout()
	startLoop()
	return ui
end

local function close()
	if state == "Closed" then
		return
	end
	state = "Closed"
	sound("Back")
	clearButtons()
	clearCards()
	local odds = ui.Gui:FindFirstChild("OddsPanel")
	if odds then
		odds:Destroy()
	end
	currentTap = nil
	stopLoop()
	clearCrate()
	clearHero()
	if world then
		world.Folder:Destroy()
		world = nil
	end
	ui.Gui.Enabled = false
	local cam = workspace.CurrentCamera
	if cam and savedFov then
		cam.FieldOfView = savedFov
	end
	if cam and savedType then
		cam.CameraType = savedType
	end
	savedFov, savedType = nil, nil
	restoreGuis()
	local onClose = opts.OnClose
	if onClose then
		task.spawn(onClose)
	end
end

-- Taps the crate being opened (gamepad A, Enter and Space do this too).
function CrateOpen.Tap()
	if currentTap and state == "Opening" then
		currentTap()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	local k = input.KeyCode
	if state == "Opening" and (k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.Return or k == Enum.KeyCode.Space) then
		if processed and k ~= Enum.KeyCode.ButtonA then
			return
		end
		CrateOpen.Tap()
	end
end)

local function reveal(crate: any)
	state = "Reveal"
	clearButtons()
	local tier = tierOf(crate.Tier)
	local power = POWER[crate.Tier] or 1
	local big = crate.Tier == "Epic" or crate.Tier == "Legendary"
	anim.Shake = 0
	anim.Tier = crate.Tier
	colourFx(crate.Tier)
	-- the crate swells, then bursts
	anim.ScaleWant = 1.16
	task.delay(0.09, function()
		anim.ScaleWant = 0.02
	end)
	task.delay(0.16, function()
		if state ~= "Reveal" then
			return
		end
		clearCrate()
		emit("Burst", "Flash", 1)
		emit("Burst", "Wave", 1 + power)
		emit("Burst", "Ring", 1 + power)
		emit("Burst", "Sparks", 26 * power)
		emit("Burst", "Halo", 4 * power)
		emit("Burst", "Radial", if big then 2 else 1)
		emit("Burst", "Stars", if big then 4 else 2)
		emit("Dust", "Dust", 4)
		anim.Boost = 1
		anim.CamShake = if crate.Tier == "Legendary" then 1.6 elseif big then 1.1 else 0.6
		setIdle(if big then 0.45 else 0.3)
		-- the glow steps back so the reward reads in front of it
		world.Anchor.CFrame = STAGE_AT * CFrame.new(0, 2, -2.5)
		if big then
			setRise(true)
			task.delay(if crate.Tier == "Legendary" then 2.2 else 1.2, function()
				if state == "Reveal" then
					setRise(false)
				end
			end)
		end
		-- the best reward takes the crate's place: 3D when it has a model, else its art
		if not setHero3D(crate.Item) then
			local item = crate.Item and Catalogue.Items[crate.Item]
			local hero = make("ImageLabel", {
				Name = "Hero2D", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.78),
				BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 4,
			}, ui.Stage)
			make("UIAspectRatioConstraint", { AspectRatio = if item then 4 / 3 else 1 }, hero)
			if not placeArt(hero, item and item.Art) then
				if item then
					label(hero, item.Name, HEAD, tier.Color, { Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.3), ZIndex = 4 })
				else
					setImage(hero, ART.Scrip)
					hero.ScaleType = Enum.ScaleType.Fit
					local amt = label(hero, (Ui and Ui.Money and Ui.Money(crate.Scrip)) or tostring(crate.Scrip), HEAD, TEXT, {
						AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 1.02), Size = UDim2.fromScale(1.4, 0.3), ZIndex = 5,
					}, 64)
					make("UIStroke", { Color = INK, Thickness = 2, Transparency = 0.3 }, amt)
				end
			end
			local hs = make("UIScale", { Scale = 0 }, hero)
			tween(hs, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	task.delay(0.14, function()
		flash(if crate.Tier == "Legendary" then 0.9 elseif big then 0.7 else 0.45)
		anim.UiShake = if crate.Tier == "Legendary" then 1.4 elseif big then 1 else 0.6
		sound(if big then "LevelUp" else "Stamp")
		local item = crate.Item and Catalogue.Items[crate.Item]
		local rarity = rarityOf(item)
		if item and rarity then
			slam(string.upper(rarity) .. " CAMO  /  NEW UNLOCK", string.upper(item.Name), tierOf(rarity).Color)
		elseif item then
			slam(tier.Name .. "  /  NEW UNLOCK", string.upper(item.Name .. " " .. (item.Kind or "")), tier.Color)
		else
			slam("SUPPLY CRATE", tier.Name, tier.Color)
		end
		ui.Sub.Text = if crate.Pity then "PITY: GUARANTEED " .. string.upper(crate.Pity) .. " OR BETTER" else ""
	end)
	task.delay(0.45, function()
		if state == "Reveal" then
			showCards(crate)
		end
	end)
	task.delay(0.45 + 0.18 * 4 + 0.7, function()
		if state ~= "Reveal" then
			return
		end
		clearButtons()
		local nextTier = CrateOpen.NextTier()
		if nextTier then
			button("OPEN NEXT (" .. CrateOpen.StackSize() .. ")", false, 2, function()
				CrateOpen.Open(nextTier, opts)
			end)
		end
		button("COLLECT", true, 1, close)
	end)
end

-- the opening: tap the crate (or OPEN) three times; the request goes out on the first tap
function CrateOpen.Open(tier: string, o: any?)
	opts = o or opts
	open()
	state = "Opening"
	clearButtons()
	clearCards()
	setCrate(tier)
	local t = tierOf(tier)
	anim.Drop, anim.DropV, anim.Shake = 0, 0, 0.04
	setIdle(0.35)
	setRise(false)
	ui.Kicker.Text, ui.Kicker.TextTransparency = "SUPPLY CRATE", 0
	ui.Title.Text, ui.Title.TextColor3, ui.Title.TextTransparency = t.Name, t.Color, 0
	ui.Underline.BackgroundColor3, ui.Underline.BackgroundTransparency = t.Color, 0
	ui.TitleScale.Scale = 1
	ui.Sub.Text = if ui.Phone then "TAP THE CRATE" else "CLICK THE CRATE"
	local result: any = nil
	local asked = false
	local taps = 0
	local function ask()
		if asked then
			return
		end
		asked = true
		task.spawn(function()
			local okR, a, b = pcall(opts.Request, tier)
			result = { Ok = okR and a == true, Crate = if okR and a == true then b else nil, Reason = if okR then b else "Error" }
		end)
	end
	local function tap()
		if state ~= "Opening" then
			return
		end
		ask()
		taps += 1
		sound("Beep")
		anim.Shake = 0.3 + taps * 0.35
		setIdle(0.35 + taps * 0.22)
		anim.Boost = math.max(anim.Boost, 0.25 * taps)
		anim.ScaleWant = 1 + 0.05 * taps
		task.delay(0.1, function()
			if state == "Opening" then
				anim.ScaleWant = 1
			end
		end)
		anim.CamShake = math.max(anim.CamShake, 0.25 * taps)
		anim.UiShake = math.max(anim.UiShake, 0.15 * taps)
		emit("Burst", "Sparks", 4 + taps * 4)
		if taps == 2 then
			emit("Burst", "Ring", 1)
		end
		if taps >= 3 then
			state = "Waiting"
			ui.Sub.Text = "..."
			if tier == "Epic" or tier == "Legendary" then
				setRise(true)
			end
			task.spawn(function()
				local t0 = os.clock()
				while not result and os.clock() - t0 < 10 do
					task.wait()
				end
				-- a short build-up even when the server answers at once
				while os.clock() - t0 < 0.35 do
					task.wait()
				end
				if result and result.Ok and result.Crate then
					reveal(result.Crate)
				else
					setRise(false)
					toast(if result and result.Reason == "NoCrate" then "That crate is already open." else "Couldn't open the crate. It is still yours: try again.")
					task.wait(0.6)
					close()
				end
			end)
		end
	end
	if tapConn then
		tapConn:Disconnect()
	end
	tapConn = ui.Catcher.Activated:Connect(tap)
	currentTap = tap
	button("OPEN", true, 1, function()
		while state == "Opening" do
			tap()
			task.wait(0.16)
		end
	end)
end

-- after a match: the crate drops onto the stage, its tier slams in; OPEN NOW or keep it for the lobby
function CrateOpen.Earned(info: any, o: any?)
	if type(info) ~= "table" or not info.Tier then
		return
	end
	opts = o or opts
	open()
	if info.Opened then
		setCrate(info.Tier)
		reveal(info.Opened)
		task.delay(0.2, function()
			ui.Sub.Text = "CRATE STACK FULL: OPENED ON THE SPOT"
		end)
		return
	end
	state = "Earned"
	clearButtons()
	clearCards()
	setCrate(info.Tier)
	local t = tierOf(info.Tier)
	anim.Shake, anim.Drop, anim.DropV = 0, 9, 0
	setIdle(0)
	setRise(false)
	ui.Kicker.Text, ui.Title.Text, ui.Sub.Text = "", "", ""
	ui.Underline.BackgroundTransparency = 1
	task.delay(0.5, function()
		if state ~= "Earned" then
			return
		end
		setIdle(0.4)
		emit("Burst", "Ring", 1)
		anim.Boost = 0.5
		slam("CRATE EARNED", t.Name, t.Color)
		local n = CrateOpen.StackSize()
		ui.Sub.Text = (if info.Pity then "PITY: GUARANTEED " .. string.upper(info.Pity) .. ". " else "")
			.. (if n > 1 then n .. " CRATES WAITING" else "OPEN IT NOW OR IN THE LOBBY STORE")
		task.delay(0.4, function()
			if state ~= "Earned" then
				return
			end
			button("OPEN LATER", false, 2, function()
				toast("Saved. Open your crates any time from the lobby STORE.")
				task.wait(0.4)
				close()
			end)
			button("OPEN NOW", true, 1, function()
				CrateOpen.Open(info.Tier, opts)
			end)
		end)
	end)
end

-- ODDS: the same tables the server rolls (Shared.Rewards), plus this player's pity counters
function CrateOpen.Odds(o: any?)
	opts = o or opts
	if not ui or not ui.Gui.Enabled then
		return
	end
	local old = ui.Gui:FindFirstChild("OddsPanel")
	if old then
		old:Destroy()
		return
	end
	local phone = ui.Phone
	local root = make("Frame", { Name = "OddsPanel", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20 }, ui.Gui)
	local scrim = make("ImageButton", { Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, AutoButtonColor = false, Image = ART.Scrim.Id, ScaleType = Enum.ScaleType.Stretch, ImageTransparency = 0.1, Selectable = false, ZIndex = 20 }, root)
	scrim.Activated:Connect(function()
		root:Destroy()
	end)
	local p = image(root, ART.Panel, {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = if phone then UDim2.fromScale(0.94, 0.9) else UDim2.fromScale(0.5, 0.74), ZIndex = 21,
	})
	make("UISizeConstraint", { MaxSize = Vector2.new(820, 780) }, p)
	label(p, "CRATE ODDS", HEAD, AMBER, { Position = UDim2.fromOffset(22, 12), Size = UDim2.new(1, -120, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 }, 32)
	make("Frame", { Position = UDim2.fromOffset(22, 50), Size = UDim2.fromOffset(72, 3), BackgroundColor3 = AMBER, BorderSizePixel = 0, ZIndex = 22 }, p)
	local x = plateButton(p, "CLOSE", false, function()
		root:Destroy()
	end)
	x.AnchorPoint = Vector2.new(1, 0)
	x.Position = UDim2.new(1, -12, 0, 10)
	x.Size = UDim2.fromOffset(44 * 260 / 72, 44)
	x.ZIndex = 23
	for _, d in x:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 24
		end
	end
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(22, 64), Size = UDim2.new(1, -44, 1, -80), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = if phone then 8 else 5, ScrollBarImageColor3 = AMBER, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ZIndex = 22,
	}, p)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local size = if phone then 15 else 17
	local order = 0
	local function line(str: string, color: Color3, font: Font, s: number?)
		order += 1
		make("TextLabel", {
			LayoutOrder = order, Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
			Text = str, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, FontFace = font, TextSize = s or size,
			TextColor3 = color, ZIndex = 22,
		}, list)
	end
	local result = opts.Result
	line("Every finished match earns one crate. Crates are earned by playing and are never sold.", TEXT, BODY)
	line(if result then "Odds for this match's result:" else "Odds per match (a won match has the better column):", DIM, BODY)
	local won = Rewards.TierOdds("Escaped")
	for _, row in Rewards.Odds(result, decode("Owned")) do
		local head = string.format("%s   %s%%", row.Name, tostring(row.Chance))
		if not result then
			head ..= string.format("   (win: %s%%)", tostring(won[row.Tier]))
		end
		line(head, tierOf(row.Tier).Color, HEAD, size + 3)
		for _, l in row.Lines do
			line("    " .. l, TEXT, BODY)
		end
	end
	local pity = decode("CratePity")
	line(string.format("Pity: an Epic or better crate is guaranteed within %d crates (you are at %d), a Legendary within %d (you are at %d).",
		Rewards.PityEpic, tonumber(pity.SinceEpic) or 0, Rewards.PityLegendary, tonumber(pity.SinceLegendary) or 0), AMBER, BODY_BOLD)
	line("A cosmetic is only ever one you don't own yet; when you own the whole pool you get Gems instead.", DIM, BODY)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = x
	end
end

function CrateOpen.Close()
	close()
end

return CrateOpen
