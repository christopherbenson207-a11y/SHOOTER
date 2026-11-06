-- First-person gun controller: the loadout and switching, viewmodel motion, input, firing,
-- reloads and hit feedback. The client raycasts for instant feedback; GunServer validates
-- and applies damage. Every shot runs the 7 punch steps (HORROR-SHOOTER-FEEL.md) using the
-- gun's Feel numbers; reloads, pumps and bolts play the gun's keyed animations. World
-- effects live in CombatFx, mob damage in Gore.
-- PC (keyboard and mouse) gets no aim assist; touch and controller get Shared.AimAssist (input type from the
-- Platform module, which reads PreferredInput). Against players (the duel) only R15 body parts are hitboxes and each
-- shot carries its server time for GunServer's lag compensation.
-- Melee (6 Nov 2026): the axe and knife (guns with a Melee table) swing instead of firing (meleeSwing), against
-- zombies or the other player.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Platform = require(Shared:WaitForChild("Platform"))
local Options = require(Shared:WaitForChild("Options"))
local Callout = require(Shared:WaitForChild("Callout"))
local Spring = require(Shared:WaitForChild("Spring"))
local SoundKit = require(Shared:WaitForChild("SoundKit"))
local Classes = require(Shared:WaitForChild("Classes"))
local Controls = require(Shared:WaitForChild("Controls"))
local AimAssist = require(Shared:WaitForChild("AimAssist"))
-- Scopes and attachments (Shared.Attachments): the gun's numbers come from Attachments.ConfigFor (GameConfig + the
-- player's picks), and the viewmodel is dressed with the attachment models and the player's camo before it is drawn.
local Attachments = require(Shared:WaitForChild("Attachments"))
local CombatFx = require(script.Parent:WaitForChild("CombatFx"))
local ViewArms = require(script.Parent:WaitForChild("ViewArms"))
local Gore = require(script.Parent:WaitForChild("Gore"))
local KillPredict = require(script.Parent:WaitForChild("KillPredict"))
local MobImpact = require(script.Parent:WaitForChild("MobImpact"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Assets = ReplicatedStorage:WaitForChild("Assets")
local EquipRemote = Remotes:WaitForChild("Equip")
local evadeStand = script.Parent:WaitForChild("Evade"):WaitForChild("Stand")

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local crosshair = hud:WaitForChild("Crosshair")
local hitmarker = hud:WaitForChild("Hitmarker")
local ammoFrame = hud:WaitForChild("Ammo")
local magLabel = ammoFrame:WaitForChild("Mag")
local reserveLabel = ammoFrame:WaitForChild("Reserve")
local magFill = ammoFrame:WaitForChild("MagBar"):WaitForChild("Fill")
local gunLabel = ammoFrame:WaitForChild("Gun")
local scopeFrame = hud:WaitForChild("Scope")
local scopeBlackout = scopeFrame:WaitForChild("Blackout")
-- 5 Nov 2026: the HUD keeps to the safe area (notched phones), which put the scope reticle off the screen
-- centre the shot goes through. The authored Scope frame moves into its own full-screen gui, shown with the HUD.
do
	local scopeGui = Instance.new("ScreenGui")
	scopeGui.Name = "ScopeView"
	scopeGui.ResetOnSpawn = false
	scopeGui.IgnoreGuiInset = true
	scopeGui.ScreenInsets = Enum.ScreenInsets.None
	scopeGui.DisplayOrder = hud.DisplayOrder
	scopeGui.ZIndexBehavior = hud.ZIndexBehavior
	scopeGui.Enabled = hud.Enabled
	scopeGui.Parent = hud.Parent
	scopeFrame.Parent = scopeGui
	hud:GetPropertyChangedSignal("Enabled"):Connect(function()
		scopeGui.Enabled = hud.Enabled
	end)
end
-- One soft line under the crosshair, no frame: "reload" with an empty mag and spare rounds,
-- "out of ammo" with nothing left.
local ammoNote = hud:WaitForChild("AmmoNote")
local ammoNoteAlpha = 0
local emptySince = nil
local fxWorld = workspace:WaitForChild("Fx")

local INFINITE_RESERVE = GameConfig.Debug.InfiniteReserve
local MOVE = GameConfig.Movement
local CAM = GameConfig.Camera
local LOADOUT = GameConfig.Loadout
-- Going down leaves only this gun (last stand); being eaten leaves none. PlayerHealthClient
-- draws health; this script only changes what the gun and camera do.
local DOWNED = GameConfig.Player.Downed
-- The bullet's sound on the world by what it struck (GameConfig.WorldDamage classes): metal pings,
-- stone and concrete crack, everything else the plain thud.
local IMPACT_CUE = { Dent = "Common/ImpactMetal", Chip = "Common/ImpactStone" }
local function impactCue(part)
	local wd = GameConfig.WorldDamage
	local class = wd and wd.Materials and wd.Materials[part.Material.Name]
	return IMPACT_CUE[class] or "Common/ImpactWorld"
end

local WHITE = Color3.fromRGB(240, 238, 232)
local AMBER = Color3.fromRGB(255, 176, 60)
local KILL_RED = Color3.fromRGB(235, 64, 52)
local LOW_AMMO = Color3.fromRGB(255, 120, 80)

local QUEUE_WINDOW = 0.2
-- A click that stops a shell reload fires once the shell in hand is in and the gun is back up.
local INTERRUPT_WINDOW = 1.2
local SLIDE_KICK_TIME = 0.09
local SHOT_LAYERS = { "Crack", "Body", "Tail" }
local ANIM_CHANNELS = { "GunPos", "GunRot", "HandPos", "HandRot", "Slide", "Pump", "BoltLift", "RightHand" }

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Platform --------------------------------------------------------------------

local function reportInputMode(mode)
	Remotes.SetInputMode:FireServer(mode)
end
Platform.Changed:Connect(reportInputMode)
reportInputMode(Platform.Get())

-- Helpers ---------------------------------------------------------------------

local function smooth(current, target, rate, dt)
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function approach(current, target, step)
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

local function easeInOut(t)
	return t * t * (3 - 2 * t)
end

local function randomSigned()
	return math.random() * 2 - 1
end

local function anglesDeg(v)
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

local function isHeadPart(part)
	return part:GetAttribute("Limb") == "Head" or part.Name == "Head"
end

-- Splits a gun's animation keys into per-channel lists and an ordered event list.
local function buildTrack(keys)
	local track = { Channels = {}, Events = {} }
	for _, name in ANIM_CHANNELS do
		track.Channels[name] = {}
	end
	for _, key in keys do
		for _, name in ANIM_CHANNELS do
			if key[name] ~= nil then
				table.insert(track.Channels[name], { T = key.T, V = key[name] })
			end
		end
		if key.Sound or key.Mag or key.Kick or key.Eject then
			table.insert(track.Events, key)
		end
	end
	return track
end

-- Eases between the two keys around t. Works for numbers and Vector3s.
local function sampleChannel(list, t)
	local n = #list
	if n == 0 then
		return nil
	end
	if t <= list[1].T then
		return list[1].V
	end
	for i = 2, n do
		local b = list[i]
		if t <= b.T then
			local a = list[i - 1]
			local alpha = easeInOut(math.clamp((t - a.T) / math.max(b.T - a.T, 1e-4), 0, 1))
			return a.V + (b.V - a.V) * alpha
		end
	end
	return list[n].V
end

-- Guns ------------------------------------------------------------------------

-- Each gun's animations (reloads, plus "Cycle" for the pump or bolt) and its ammo.
local tracks = {}
local ammo = {}
for _, name in LOADOUT do
	local g = GameConfig.Guns[name]
	local t = {}
	for animName, keys in g.ReloadAnim or {} do
		t[animName] = buildTrack(keys)
	end
	if g.Cycle then
		t.Cycle = buildTrack(g.Cycle.Anim)
	end
	tracks[name] = t
	ammo[name] = { Attachments.ConfigFor(player, name).MagSize, g.Reserve }
end

local gunName, gun, feel, gunTracks
local hipCF, aimCF = CFrame.identity, CFrame.identity

local function selectGun(name)
	gunName = name
	gun = Attachments.ConfigFor(player, name) or GameConfig.Guns[name]
	feel = gun.Feel
	gunTracks = tracks[name]
	hipCF = CFrame.new(gun.HipOffset) * anglesDeg(gun.HipAngles)
	aimCF = CFrame.new(0, 0, -gun.AimDistance)
	gunLabel.Text = gun.DisplayName or string.upper(name)
	-- The hotbar (StarterPlayerScripts.Hotbar) marks this slot.
	player:SetAttribute("EquippedGun", name)
end
selectGun(LOADOUT[1])

-- State -----------------------------------------------------------------------

local state = {
	alive = false,
	mag = gun.MagSize,
	reserve = gun.Reserve,
	reloading = false,
	-- "Mag", or for shell-by-shell guns "Start", "Shell", "End".
	reloadPhase = nil,
	reloadStart = 0,
	reloadDuration = 0,
	reloadTrack = nil,
	reloadEvent = 1,
	reloadWasEmpty = false,
	reloadStop = false,
	magMode = "Gun",
	pendingSync = nil,
	cycling = false,
	cycleStart = 0,
	cycleEvent = 1,
	switchTo = nil,
	switchStart = 0,
	lastShot = -math.huge,
	queuedShot = nil,
	queueWindow = QUEUE_WINDOW,
	triggerHeld = false,
	dryClicked = false,
	bloom = 0,
	aimHeld = false,
	aimLatched = false,
	aimPressAt = nil,
	firePressAt = -math.huge,
	aimAlpha = 0,
	sprintHeld = false,
	sprintAlpha = 0,
	sprintBlockedUntil = 0,
	equipStart = 0,
	pushStart = 0,
	pushUntil = 0,
	pushSpeed = 0,
	pushDir = Vector3.zero,
	scoped = false,
	breath = 0,
	swayMult = 1,
}

local camera = workspace.CurrentCamera
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

-- A state flag PlayerHealth keeps on the character ("Downed", "Devoured").
local function charFlag(name)
	local character = player.Character
	return character ~= nil and character:GetAttribute(name) == true
end

local swaySpring = Spring.new(14, 0.75)
local kickSpring = Spring.new(22, 0.6)
local camSpring = Spring.new(16, 0.85)
local shakeSpring = Spring.new(32, 0.35)
local fovSpring = Spring.new(20, 0.7)
local lastCamOffset = Vector3.zero
local lastCamCF: CFrame? = nil

local bobTime, bobAmount = 0, 0
local slideKickAt = -math.huge
local flashHideAt = 0
local hitmarkerHideAt = 0
local currentSensitivity = 1

-- Viewmodel -------------------------------------------------------------------

local viewModel: Model? = nil
local vmRoot: BasePart? = nil
local vmParts = {}
local vmOffsets = {}
local vmGroups = {}
-- Mag parts (a mag and the rounds on top of it) ride with the biggest one.
local magParts = {}
local magRel = {}
local magPart, shellPart, flashPart, flashLight, muzzle, ejectPoint
-- The flash (buildFlash), the barrel tip in the gun's own frame, and where the gun was last drawn.
local flashJet: Beam?, flashStar: ParticleEmitter?, flashTo: Attachment? = nil, nil, nil
local muzzleLocal = CFrame.identity
local lastRootCF: CFrame? = nil
local arms = nil
local rightGripCF: CFrame? = nil
local leftGripCF: CFrame? = nil
local magInHandCF = CFrame.identity
local shellInHandCF = CFrame.identity
local handPivot = Vector3.zero
local boltAxis = CFrame.identity
local boltHandle: CFrame? = nil
local vmHidden = false

local function setViewModelHidden(hidden)
	vmHidden = hidden
	if viewModel then
		for _, d in viewModel:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if hidden then 1 else 0
			end
		end
	end
end

-- The player's own arms, rebuilt whenever their avatar's look changes.
local function buildArms()
	if arms then
		arms:Destroy()
		arms = nil
	end
	local character = player.Character
	if viewModel and character and rightGripCF and leftGripCF then
		arms = ViewArms.new(character, viewModel)
	end
	if vmHidden then
		setViewModelHidden(true)
	end
end

local function volume(part)
	return part.Size.X * part.Size.Y * part.Size.Z
end

-- The muzzle flash: a flame jet out of the barrel (a Beam, seen side-on) and a star on the tip
-- (one particle facing the camera, a random one of four), both from the barrel tip and pointing
-- down the barrel. The Flash ball only holds the light now. Sizes: the gun's Feel.FlashSize is
-- the jet's length in studs.
local FLASH_JET = "rbxassetid://98406976901224"
local FLASH_STAR = "rbxassetid://133665235088795"

local function buildFlash()
	flashJet, flashStar, flashTo = nil, nil, nil
	if not (flashPart and muzzle and vmOffsets[flashPart]) then
		return
	end
	flashPart.Transparency = 1
	local tip = vmOffsets[flashPart]:Inverse() * muzzleLocal
	local from = Instance.new("Attachment")
	from.Name = "FlashFrom"
	from.CFrame = tip
	from.Parent = flashPart
	flashTo = Instance.new("Attachment")
	flashTo.Name = "FlashTo"
	flashTo.CFrame = tip * CFrame.new(0, 0, -feel.FlashSize)
	flashTo.Parent = flashPart
	local jet = Instance.new("Beam")
	jet.Attachment0 = from
	jet.Attachment1 = flashTo
	jet.Texture = FLASH_JET
	jet.TextureMode = Enum.TextureMode.Stretch
	jet.TextureLength = 1
	jet.TextureSpeed = 0
	jet.FaceCamera = true
	jet.LightEmission = 0.7
	jet.LightInfluence = 0
	jet.Brightness = 1
	jet.Segments = 1
	jet.Transparency = NumberSequence.new(0.25)
	jet.Enabled = false
	jet.Parent = flashPart
	flashJet = jet
	local star = Instance.new("ParticleEmitter")
	star.Texture = FLASH_STAR
	star.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
	star.FlipbookMode = Enum.ParticleFlipbookMode.Random
	star.Rate = 0
	star.Speed = NumberRange.new(0)
	star.Rotation = NumberRange.new(0, 360)
	star.LockedToPart = true
	star.LightEmission = 0.7
	star.LightInfluence = 0
	star.Brightness = 1
	star.ZOffset = 0.15
	star.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 1) })
	star.Enabled = false
	star.Parent = from
	flashStar = star
end

local function buildViewModel()
	if viewModel then
		viewModel:Destroy()
		arms = nil
	end
	viewModel = Assets.ViewModels:WaitForChild(gun.ViewModel):Clone()
	vmRoot = viewModel.PrimaryPart
	-- Attachments and camo go on before the parts are read, so they are drawn with the gun.
	Attachments.Dress(viewModel, gunName, player, "VM")
	table.clear(vmParts)
	table.clear(vmOffsets)
	table.clear(vmGroups)
	table.clear(magParts)
	table.clear(magRel)
	magPart, shellPart = nil, nil
	for _, d in viewModel:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if d ~= vmRoot then
				table.insert(vmParts, d)
				vmOffsets[d] = vmRoot.CFrame:ToObjectSpace(d.CFrame)
				vmGroups[d] = d:GetAttribute("VmGroup")
				if vmGroups[d] == "Mag" then
					table.insert(magParts, d)
					if not magPart or volume(d) > volume(magPart) then
						magPart = d
					end
				elseif vmGroups[d] == "Shell" then
					shellPart = d
				end
			end
		end
	end
	local rightGrip = vmRoot:FindFirstChild("RightGrip")
	local leftGrip = vmRoot:FindFirstChild("LeftGrip")
	rightGripCF = rightGrip and rightGrip.CFrame
	leftGripCF = leftGrip and leftGrip.CFrame
	-- Animation keys turn the left hand about its resting spot on the gun.
	handPivot = if leftGripCF then leftGripCF.Position else Vector3.zero
	-- A mag in the left hand rides with its base in the palm (on the hand's grip point).
	if magPart then
		local magCF = vmOffsets[magPart]
		local magBase = magCF * Vector3.new(0, -magPart.Size.Y / 2, 0)
		magInHandCF = CFrame.new(handPivot - magBase) * magCF
		for _, p in magParts do
			magRel[p] = magCF:Inverse() * vmOffsets[p]
		end
	end
	-- A shell lies along the gun in the fingers, just under the grip point.
	if shellPart then
		shellInHandCF = CFrame.new(handPivot + Vector3.new(0, -0.03, 0)) * vmOffsets[shellPart].Rotation
	end
	local axis = vmRoot:FindFirstChild("BoltAxis")
	boltAxis = if axis then axis.CFrame else CFrame.identity
	local handle = vmRoot:FindFirstChild("BoltHandle")
	boltHandle = handle and handle.CFrame
	flashPart = viewModel:FindFirstChild("Flash")
	flashLight = flashPart and flashPart:FindFirstChildOfClass("PointLight")
	muzzle = viewModel:FindFirstChild("Muzzle", true)
	-- The Muzzle attachment hangs on the root part, which never moves (only the other parts are
	-- drawn each frame), so keep the barrel tip in the gun's frame and carry it along instead.
	muzzleLocal = if muzzle then vmRoot.CFrame:ToObjectSpace(CFrame.new(muzzle.WorldPosition)) else CFrame.identity
	lastRootCF = nil
	buildFlash()
	ejectPoint = viewModel:FindFirstChild("Eject", true)
	-- Aim down sights puts the AimPoint (rear sight notch) dead centre, AimDistance ahead.
	-- Only its position counts: the gun keeps pointing down the view. (The Shotgun's and
	-- Sniper's AimPoints face sideways and the AK's backwards, which turned the gun on aim.)
	-- An optic's sight line (OpticSight, added by Attachments) replaces the iron sights.
	local aimPoint = vmRoot:FindFirstChild("OpticSight") or viewModel:FindFirstChild("AimPoint", true)
	local aimLocal = if aimPoint then CFrame.new(vmRoot.CFrame:PointToObjectSpace(aimPoint.WorldPosition)) else CFrame.new()
	aimCF = CFrame.new(0, 0, -gun.AimDistance) * aimLocal:Inverse()
	viewModel.Parent = camera
	vmHidden = false
	buildArms()
end

-- FRONTLINE (workspace attribute Front, Shared.Front): anything with a Humanoid on the other side is a target, players
-- and bots alike; anything on your own side stops the round. Otherwise only models tagged Enemy are.
local function sideOf(model)
	local owner = Players:GetPlayerFromCharacter(model)
	if owner then
		return owner:GetAttribute("Side") or "Ally"
	end
	return model:GetAttribute("Side")
end

local function getEnemyModel(part)
	local front = workspace:GetAttribute("Front")
	local mine = player:GetAttribute("Side") or "Ally"
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") then
			if front then
				if node:FindFirstChildOfClass("Humanoid") then
					local side = sideOf(node)
					return if side and side ~= mine then node else nil
				end
			elseif CollectionService:HasTag(node, "Enemy") then
				return node
			end
		end
		node = node.Parent
	end
	return nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function refreshRayFilter()
	local ignore = { camera, fxWorld }
	local front = workspace:GetAttribute("Front")
	local mine = player:GetAttribute("Side") or "Ally"
	for _, p in Players:GetPlayers() do
		if p.Character and (not front or p == player or (p:GetAttribute("Side") or "Ally") == mine) then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
end

local function gunSound(name, opts)
	return SoundKit.Play(feel.Sounds .. "/" .. name, opts)
end

local function carrierVelocity()
	return if rootPart then rootPart.AssemblyLinearVelocity else Vector3.zero
end

local function shake(degrees)
	local r = math.rad(degrees)
	-- Degrees of shake look several times bigger through a narrow scope: scaled by the zoom.
	if state.scoped then
		r *= math.clamp(camera.FieldOfView / math.max(Options.Get("Fov"), 1), 0.15, 1)
	end
	shakeSpring:Kick(Vector3.new(randomSigned() * r * 0.6, randomSigned() * r, randomSigned() * r * 1.4))
end

-- The muzzle where it is this frame. fire() can run before the viewmodel moves this frame,
-- so the muzzle rides along with the camera from where the viewmodel last put it.
local vmCamCF = nil
local function muzzleWorld()
	if not muzzle or not (vmCamCF and lastRootCF) then
		return camera.CFrame.Position
	end
	return camera.CFrame * vmCamCF:ToObjectSpace(lastRootCF * muzzleLocal).Position
end

-- Straight down the barrel, carried along the same way.
local function barrelLook()
	if not (vmCamCF and lastRootCF) then
		return camera.CFrame.LookVector
	end
	return camera.CFrame:VectorToWorldSpace(vmCamCF:VectorToObjectSpace(lastRootCF.LookVector))
end

-- Mobs this client already saw die (KillPredict); the server's kill confirm skips them.
local predictedKills = setmetatable({}, { __mode = "k" })

local function muzzleFlash()
	local size = feel.FlashSize * (0.8 + math.random() * 0.4)
	if flashJet and flashTo and not vmHidden then
		flashTo.CFrame = (flashJet.Attachment0 :: Attachment).CFrame * CFrame.new(0, 0, -size * 0.75)
		flashJet.Width0 = size * 0.12
		flashJet.Width1 = size * 0.12
		flashJet.Enabled = true
	end
	if flashStar and not vmHidden then
		flashStar.Size = NumberSequence.new(size * 0.14)
		flashStar.Lifetime = NumberRange.new(feel.FlashTime * 1.2)
		flashStar:Emit(1)
	end
	if flashLight then
		flashLight.Brightness = 0.6
	end
	flashHideAt = os.clock() + feel.FlashTime
	if muzzle then
		local look = barrelLook()
		local at = muzzleWorld()
		CombatFx.MuzzleLight(at + look * 0.6, feel)
		CombatFx.Emit("Spark", at, look, feel.MuzzleSparks)
		CombatFx.Emit("Smoke", at, look, feel.MuzzleSmoke)
	end
end

local function ejectCasing()
	if ejectPoint then
		CombatFx.Casing(ejectPoint.WorldPosition, camera.CFrame, carrierVelocity(), feel)
	end
end

local function setHitmarkerColor(color)
	for _, line in hitmarker:GetChildren() do
		if line:IsA("Frame") then
			line.BackgroundColor3 = color
		end
	end
end

-- kind: "hit" | "head" | "kill"
local function showHitmarker(kind)
	setHitmarkerColor(if kind == "kill" then KILL_RED elseif kind == "head" then AMBER else WHITE)
	hitmarker.Visible = true
	local scale = hitmarker:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = if kind == "hit" then 1.25 elseif kind == "head" then 1.55 else 1.8
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	hitmarkerHideAt = os.clock() + (if kind == "kill" then 0.36 else 0.18)
end

local function horizontalSpeed()
	if not rootPart then
		return 0
	end
	local v = rootPart.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- In the air (duel pass, 5 Nov 2026): GameConfig.Movement.AirSpread on top, AirSpreadScoped behind a scope, so jumping
-- round a corner is a gamble rather than a free shot. Swimming and climbing don't count.
local function airborne()
	return humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
		and humanoid:GetState() ~= Enum.HumanoidStateType.Climbing
		and humanoid:GetState() ~= Enum.HumanoidStateType.Swimming
end

local function currentSpread()
	local s = gun.Spread
	-- 5 Nov 2026 scope fix: scoped, only the gun's aimed spread (walking and follow-up bloom put a sniper's
	-- round well off the reticle at FOV 14).
	if state.scoped then
		return s.Aim + (if airborne() then MOVE.AirSpreadScoped or 0 else 0)
	end
	local aim = easeInOut(state.aimAlpha)
	local base = s.Hip + (s.Aim - s.Hip) * aim
	local moving = math.clamp(horizontalSpeed() / MOVE.WalkSpeed, 0, 1.5) * s.Move * (1 - aim * 0.8)
	local air = if airborne() then MOVE.AirSpread or 0 else 0
	return math.min(base + moving + air + state.bloom * (1 - aim * 0.6), s.Max + air)
end

-- The pellet cone around the aim point (0 for single-round guns).
local function pelletCone()
	if (gun.Pellets or 1) <= 1 then
		return 0
	end
	return gun.PelletSpread + (gun.AimPelletSpread - gun.PelletSpread) * easeInOut(state.aimAlpha)
end

local function spreadAround(dir, degrees)
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local spin = math.random() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
end

local function fireDirection(spreadDeg)
	return spreadAround(camera.CFrame.LookVector, spreadDeg)
end

-- Animation -------------------------------------------------------------------

local function runEvent(event)
	if event.Sound then
		gunSound(event.Sound)
	end
	if event.Kick then
		kickSpring:Kick(Vector3.new(math.rad(7) * event.Kick, 0, 0.05 * event.Kick))
	end
	if event.Eject then
		ejectCasing()
	end
	if event.Mag == "Drop" then
		if magPart and state.magMode == "Gun" then
			CombatFx.DroppedMag(magPart, carrierVelocity())
		end
		state.magMode = "Hidden"
	elseif event.Mag then
		state.magMode = event.Mag
	end
end

local NO_CHANNELS = {}

-- The gun offset, the left-hand offset and the moving parts (Slide, Pump, BoltLift,
-- RightHand) for one track at time t (0-1).
local function trackPose(track, t)
	local ch = track.Channels
	local gunPos = sampleChannel(ch.GunPos, t) or Vector3.zero
	local gunRot = sampleChannel(ch.GunRot, t) or Vector3.zero
	local handPos = sampleChannel(ch.HandPos, t) or Vector3.zero
	local handRot = sampleChannel(ch.HandRot, t) or Vector3.zero
	local gunCF = CFrame.new(gunPos) * anglesDeg(gunRot)
	-- The hand turns about its resting spot, then moves.
	local handCF = CFrame.new(handPos) * CFrame.new(handPivot) * anglesDeg(handRot) * CFrame.new(-handPivot)
	return gunCF, handCF, {
		Slide = sampleChannel(ch.Slide, t),
		Pump = sampleChannel(ch.Pump, t),
		BoltLift = sampleChannel(ch.BoltLift, t),
		RightHand = sampleChannel(ch.RightHand, t),
	}
end

-- This frame's animated pose: a reload, else the pump or bolt cycle, else rest.
-- The player attribute "DebugReloadT" (0-1) holds a pose for screenshots: "DebugAnim" names
-- the track (Tactical, Empty, Cycle, Start, Shell, End, EndEmpty); without it
-- "DebugReloadEmpty" picks the empty reload.
local function animPose(now)
	local debugT = player:GetAttribute("DebugReloadT")
	if typeof(debugT) == "number" then
		local name = player:GetAttribute("DebugAnim")
		local track = (typeof(name) == "string" and gunTracks[name])
			or (if player:GetAttribute("DebugReloadEmpty") then gunTracks.Empty else nil)
			or gunTracks.Tactical
			or gunTracks.Cycle
		if not track then
			return CFrame.identity, CFrame.identity, NO_CHANNELS
		end
		local t = math.clamp(debugT, 0, 1)
		state.magMode = if gun.ReloadStyle == "Shells" then "Hidden" else "Gun"
		for _, event in track.Events do
			if event.T <= t and event.Mag then
				state.magMode = if event.Mag == "Drop" then "Hidden" else event.Mag
			end
		end
		return trackPose(track, t)
	end
	if state.reloading and state.reloadTrack then
		local t = math.clamp((now - state.reloadStart) / state.reloadDuration, 0, 1)
		local events = state.reloadTrack.Events
		while events[state.reloadEvent] and events[state.reloadEvent].T <= t do
			runEvent(events[state.reloadEvent])
			state.reloadEvent += 1
		end
		return trackPose(state.reloadTrack, t)
	end
	if state.cycling and gunTracks.Cycle then
		local t = (now - state.cycleStart) / gun.Cycle.Time
		if t < 0 then
			return CFrame.identity, CFrame.identity, NO_CHANNELS
		end
		local events = gunTracks.Cycle.Events
		while events[state.cycleEvent] and events[state.cycleEvent].T <= t do
			runEvent(events[state.cycleEvent])
			state.cycleEvent += 1
		end
		if t >= 1 then
			state.cycling = false
		end
		return trackPose(gunTracks.Cycle, math.min(t, 1))
	end
	return CFrame.identity, CFrame.identity, NO_CHANNELS
end

-- Reload ----------------------------------------------------------------------

local function beginPhase(phase, track, duration)
	state.reloadPhase = phase
	state.reloadTrack = track
	state.reloadStart = os.clock()
	state.reloadDuration = duration
	state.reloadEvent = 1
end

local function hasSpare()
	return state.mag < gun.MagSize and (INFINITE_RESERVE or state.reserve > 0)
end

local function startReload()
	if not state.alive or state.reloading or state.switchTo or not hasSpare() then
		if state.alive and state.mag == 0 and not INFINITE_RESERVE and state.reserve <= 0 then
			Callout.Say("NoAmmo")
		end
		return
	end
	local empty = state.mag == 0
	state.reloading = true
	-- Under a full mag left after this one is "last mag".
	Callout.Say(if not INFINITE_RESERVE and state.reserve - (gun.MagSize - state.mag) < gun.MagSize then "LowAmmo" else "Reload")
	state.reloadWasEmpty = empty
	state.reloadStop = false
	state.queuedShot = nil
	state.cycling = false
	if gun.ReloadStyle == "Shells" then
		-- No shell in the hand until it reaches for one.
		state.magMode = "Hidden"
		beginPhase("Start", gunTracks.Start, gun.ShellReload.StartTime)
	else
		state.magMode = "Gun"
		local track = if empty then gunTracks.Empty or gunTracks.Tactical else gunTracks.Tactical
		beginPhase("Mag", track, if empty then gun.ReloadEmptyTime else gun.ReloadTime)
	end
	Remotes.Reload:FireServer()
end

local function finishReload()
	if state.pendingSync then
		state.mag, state.reserve = state.pendingSync[1], state.pendingSync[2]
		state.pendingSync = nil
	end
	state.reloading = false
	state.reloadPhase = nil
	state.reloadTrack = nil
	state.magMode = "Gun"
end

local function cancelReload()
	state.reloading = false
	state.reloadPhase = nil
	state.reloadTrack = nil
	state.pendingSync = nil
	state.magMode = "Gun"
end

-- Moves a reload on when its phase runs out. Shell guns load a shell at the end of each
-- Shell phase and go on until full, out of shells or stopped by a click.
local function stepReload(now)
	if now - state.reloadStart < state.reloadDuration then
		return
	end
	local phase = state.reloadPhase
	if phase == "Mag" then
		local need = gun.MagSize - state.mag
		local take = if INFINITE_RESERVE then need else math.min(need, state.reserve)
		state.mag += take
		if not INFINITE_RESERVE then
			state.reserve -= take
		end
		finishReload()
	elseif phase == "Start" or phase == "Shell" then
		if phase == "Shell" and hasSpare() then
			state.mag += 1
			if not INFINITE_RESERVE then
				state.reserve -= 1
			end
		end
		-- A stopped reload still puts one shell in an empty gun.
		if hasSpare() and (not state.reloadStop or state.mag == 0) then
			beginPhase("Shell", gunTracks.Shell, gun.ShellReload.ShellTime)
		else
			if state.reloadStop then
				Remotes.Reload:FireServer("Stop")
			end
			local racked = state.reloadWasEmpty and gunTracks.EndEmpty
			beginPhase("End", racked or gunTracks.End, if racked then gun.ShellReload.EndEmptyTime else gun.ShellReload.EndTime)
		end
	else
		finishReload()
	end
end

-- Fire ------------------------------------------------------------------------

-- One round or pellet. Penetrating rounds carry on through up to Penetration.Count mobs;
-- anything else stops it. Returns the mobs hit in order, the end point, and the world hit.
-- A player's body (5 Nov 2026 duel pass): only the parts in GameConfig.Pvp.Zones are hitboxes. A round passes through
-- anything else on a character (gear, the held gun, the root part) to whatever is behind it, as GunServer expects.
local PVP_ZONES = GameConfig.Pvp.Zones
local function castShot(origin, dir)
	local hits = {}
	local maxHits = if gun.Penetration then gun.Penetration.Count else 1
	local params = rayParams
	local ignore = nil
	local from, left = origin, gun.Range
	local function skip(instance)
		if not ignore then
			ignore = table.clone(rayParams.FilterDescendantsInstances)
			params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.IgnoreWater = true
		end
		table.insert(ignore, instance)
		params.FilterDescendantsInstances = ignore
	end
	for _ = 1, 24 do
		local result = workspace:Raycast(from, dir * left, params)
		if not result then
			return hits, from + dir * left, nil
		end
		local enemy = getEnemyModel(result.Instance)
		local body = enemy and Players:GetPlayerFromCharacter(enemy) ~= nil
		if body and not (result.Instance.Parent == enemy and PVP_ZONES[result.Instance.Name]) then
			-- Not a hitbox: carry on from here without it.
			skip(result.Instance)
			left -= (result.Position - from).Magnitude
			from = result.Position
		else
			if not enemy then
				return hits, result.Position, result
			end
			table.insert(hits, { Enemy = enemy, Result = result })
			if #hits >= maxHits then
				return hits, result.Position, nil
			end
			skip(enemy)
			left -= (result.Position - from).Magnitude
			from = result.Position
		end
	end
	return hits, from, nil
end

-- The shove on the shooter: held against the walk controller for PushTime, easing out.
local function pushPlayer(camCF)
	if not rootPart then
		return
	end
	local flatLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	if flatLook.Magnitude < 0.01 then
		return
	end
	local dir = -flatLook.Unit
	if feel.PushTime then
		state.pushDir = dir
		state.pushSpeed = feel.PlayerPush
		state.pushStart = os.clock()
		state.pushUntil = state.pushStart + feel.PushTime
	else
		rootPart.AssemblyLinearVelocity += dir * feel.PlayerPush
	end
end

local function startCycle(now)
	if gun.Cycle then
		state.cycling = true
		state.cycleStart = now + gun.Cycle.Delay
		state.cycleEvent = 1
	end
end

-- Melee (the axe and knife: GameConfig.Guns.X.Melee; 6 Nov 2026, the axe's swing from the zombies place) ------------

-- The axe's swing on your own body (GameConfig.Squad.Anims.AxeSwing moves the held axe's GunRoot). It replicates, so
-- the other player sees the swing as it starts; their WorldGunArms bends your arms onto the moving haft.
local bodySwings = setmetatable({}, { __mode = "k" }) -- [Animator] = track
local function playBodySwing()
	local anims = GameConfig.Squad and GameConfig.Squad.Anims
	local id = anims and anims.AxeSwing
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if type(id) ~= "string" or id == "" or not animator then
		return
	end
	local track = bodySwings[animator]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, loaded = pcall(animator.LoadAnimation, animator, anim)
		if not ok then
			return
		end
		track = loaded
		bodySwings[animator] = track
	end
	track:Play(0.05)
end

-- One sphere cast of a swing. On a player's body only the Pvp.Zones parts count (as castShot): anything else on a
-- character (the root part, gear, the held weapon) is passed through.
local function meleeCast(origin, dir, radius, range)
	local params, ignore = rayParams, nil
	for _ = 1, 8 do
		local r = workspace:Spherecast(origin, radius, dir * range, params)
		if not r then
			return nil, nil
		end
		local enemy = getEnemyModel(r.Instance)
		if enemy and Players:GetPlayerFromCharacter(enemy) and not (r.Instance.Parent == enemy and PVP_ZONES[r.Instance.Name]) then
			if not ignore then
				ignore = table.clone(rayParams.FilterDescendantsInstances)
				params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.IgnoreWater = true
			end
			table.insert(ignore, r.Instance)
			params.FilterDescendantsInstances = ignore
		else
			return r, enemy
		end
	end
	return nil, nil
end

-- The swing plays as the weapon's Cycle; HitDelay in, a fan of sphere casts across Melee.Arc finds up to Pellets
-- targets (zombies or the other player). The swing always reaches GunServer as one Fire (a miss is a shot with no
-- hits), so the other player sees every swing; no rounds are used.
local function meleeSwing()
	local now = os.clock()
	state.lastShot = now
	state.queuedShot = nil
	state.sprintBlockedUntil = now + MOVE.SprintBlockAfterShot
	startCycle(now)
	gunSound("Swing")
	if gun.Hold == "Axe" then
		playBodySwing()
	end
	camSpring:Kick(Vector3.new(math.rad(-1.5), math.rad(1.5), 0))
	local swungWith = gunName
	local swung = gun
	local melee = gun.Melee
	task.delay(melee.HitDelay, function()
		if not state.alive or gunName ~= swungWith or charFlag("Devoured") then
			return
		end
		local camCF = camera.CFrame
		local origin = camCF.Position
		local shotTime = workspace:GetServerTimeNow()
		refreshRayFilter()
		local found, order = {}, {}
		local wall = nil
		for _, step in { 0, -1, 1, -2, 2 } do
			local dir = CFrame.fromAxisAngle(camCF.UpVector, math.rad(melee.Arc / 4 * step)):VectorToWorldSpace(camCF.LookVector)
			local r, enemy = meleeCast(origin, dir, melee.Radius, swung.Range)
			if r then
				local enemyHumanoid = enemy and enemy:FindFirstChildOfClass("Humanoid")
				if enemyHumanoid and enemyHumanoid.Health > 0 then
					if not found[enemy] and #order < (swung.Pellets or 1) then
						found[enemy] = r
						table.insert(order, enemy)
					end
				elseif not enemy and step == 0 then
					wall = r
				end
			end
		end
		local shots = {}
		local anyHead, killed = false, false
		for i, enemy in order do
			local r = found[enemy]
			local toHit = r.Position - origin
			local dir = if toHit.Magnitude > 0.01 then toHit.Unit else camCF.LookVector
			shots[i] = { Dir = dir, End = r.Position, Hits = { { Part = r.Instance, Pos = r.Position } } }
			anyHead = anyHead or isHeadPart(r.Instance)
			CombatFx.BloodHit(r.Position, r.Normal, dir)
			CombatFx.FlashEnemy(enemy)
			CombatFx.Squash(r.Instance, feel.Squash)
			-- A player's body: a spurt only; the server confirms the kill (HitConfirm).
			if not Players:GetPlayerFromCharacter(enemy) then
				Gore.Shot(enemy, r.Instance, r.Position, r.Normal, dir, feel, 1)
				local hits = { { Part = r.Instance, Pos = r.Position, Dist = toHit.Magnitude, Index = 1 } }
				if KillPredict.Shot(enemy, hits, swung, dir, 1) then
					if not predictedKills[enemy] then
						predictedKills[enemy] = true
						killed = true
					end
				else
					MobImpact.Hit(enemy, r.Instance, r.Position, dir, feel, 1.6)
				end
			end
		end
		if #shots == 0 then
			shots[1] = { Dir = camCF.LookVector, End = origin + camCF.LookVector * swung.Range, Hits = {} }
		end
		Remotes.Fire:FireServer(origin, swungWith, shots, shotTime)
		if #order > 0 then
			gunSound("Hit")
			SoundKit.Play("Common/ImpactFlesh", { Position = found[order[1]].Position })
			showHitmarker(if killed then "kill" elseif anyHead then "head" else "hit")
			SoundKit.Play(if anyHead then "Common/HitHead" else "Common/Hit")
			if killed then
				SoundKit.Play("Common/Kill")
			end
			shake(if killed then feel.KillShake else feel.Shake)
			kickSpring:Kick(Vector3.new(math.rad(-4), 0, 0.04))
		elseif wall then
			CombatFx.WorldImpact(wall, false)
			SoundKit.Play(impactCue(wall.Instance), { Position = wall.Position })
			shake(feel.Shake * 0.6)
		end
	end)
end

local function fire()
	if gun.Melee then
		meleeSwing()
		return
	end
	local now = os.clock()
	state.lastShot = now
	state.queuedShot = nil
	state.mag -= 1
	state.sprintBlockedUntil = now + MOVE.SprintBlockAfterShot

	local camCF = camera.CFrame
	local origin = camCF.Position
	-- The server time of this shot, for lag compensation on player targets (GunServer shotTiming).
	local shotTime = workspace:GetServerTimeNow()
	local aimDir = fireDirection(currentSpread())
	refreshRayFilter()
	local pellets = gun.Pellets or 1
	local cone = pelletCone()
	local impact = if pellets > 1 then feel.PelletImpact or 1 else 1
	local muzzlePos = muzzleWorld()

	-- 1. The shot: sound, kick and flash on the same frame as the click.
	SoundKit.PlayLayers(feel.Sounds, SHOT_LAYERS, if feel.ShotVolume then { Volume = feel.ShotVolume } else nil)
	muzzleFlash()
	slideKickAt = now

	local shots = {}
	local struck = {}
	local anyHead = false
	local fleshAt = nil
	local worldHits = 0
	local predict, predictOrder = {}, {}
	for i = 1, pellets do
		local dir = if pellets > 1 then spreadAround(aimDir, cone) else aimDir
		local hits, endPos, world = castShot(origin, dir)
		local report = { Dir = dir, End = endPos, Hits = {}, World = if world then { Part = world.Instance, Pos = world.Position } else nil }

		-- 2. Bullets: a tracer with a tail.
		CombatFx.Tracer(muzzlePos, endPos, feel, false)

		-- 3. The hit: kick, dent, wound and blood on this frame; everyone else gets it from
		-- the server.
		for index, h in hits do
			local r = h.Result
			local enemyHumanoid = h.Enemy:FindFirstChildOfClass("Humanoid")
			-- A player on the other side (FRONTLINE): a spurt only, no gore and no predicted kill on a real character.
			local playerBody = Players:GetPlayerFromCharacter(h.Enemy) ~= nil
			if playerBody then
				CombatFx.BloodHit(r.Position, r.Normal, dir)
			else
				Gore.Shot(h.Enemy, r.Instance, r.Position, r.Normal, dir, feel, impact)
			end
			-- Every pellet that lands shows its own spurt, so the spread reads on the body.
			if pellets > 1 then
				CombatFx.BloodHit(r.Position, r.Normal, dir)
			end
			fleshAt = fleshAt or r.Position
			if enemyHumanoid and enemyHumanoid.Health > 0 then
				table.insert(report.Hits, { Part = r.Instance, Pos = r.Position })
				struck[h.Enemy] = struck[h.Enemy] or r.Instance
				anyHead = anyHead or isHeadPart(r.Instance)
				local entry = predict[h.Enemy]
				if playerBody then
					entry = { Hits = {}, Dir = Vector3.zero } -- not predicted
				elseif not entry then
					entry = { Hits = {}, Dir = Vector3.zero }
					predict[h.Enemy] = entry
					table.insert(predictOrder, h.Enemy)
				end
				table.insert(entry.Hits, { Part = r.Instance, Pos = r.Position, Dist = (r.Position - origin).Magnitude, Index = index })
				entry.Dir += dir
			end
		end
		if world then
			worldHits += 1
			CombatFx.WorldImpact(world, pellets > 1)
			if worldHits <= 2 then
				SoundKit.Play(impactCue(world.Instance), { Position = world.Position })
			end
		end
		shots[i] = report
	end
	Remotes.Fire:FireServer(origin, gunName, shots, shotTime)

	-- A shot that kills drops the body on this frame (KillPredict); a heavy blast that doesn't
	-- still throws the body back hard right now, before the server's shove arrives.
	local predictedKill = false
	for _, enemy in predictOrder do
		local entry = predict[enemy]
		local share = #entry.Hits / pellets
		local shotDir = if entry.Dir.Magnitude > 1e-3 then entry.Dir.Unit else aimDir
		if KillPredict.Shot(enemy, entry.Hits, gun, shotDir, share) then
			if not predictedKills[enemy] then
				predictedKills[enemy] = true
				predictedKill = true
			end
		elseif feel.KnockDown and share >= feel.KnockDown then
			MobImpact.Hit(enemy, entry.Hits[1].Part, entry.Hits[1].Pos, shotDir, feel, 2.2)
		end
	end

	if fleshAt then
		SoundKit.Play("Common/ImpactFlesh", { Position = fleshAt })
	end
	if next(struck) then
		showHitmarker(if anyHead then "head" else "hit")
		SoundKit.Play(if anyHead then "Common/HitHead" else "Common/Hit")
		for enemy, part in struck do
			CombatFx.FlashEnemy(enemy)
			CombatFx.Squash(part, feel.Squash)
		end
	end
	-- Feel moments (no numbers): a headshot snaps the view a hair; a headshot kill crunches
	-- harder; two or more bodies dropped by one blast get a heavier double crunch.
	local killsThisShot = 0
	for _, enemy in predictOrder do
		if predictedKills[enemy] and KillPredict.IsPredicted(enemy) then
			killsThisShot += 1
		end
	end
	if anyHead and not predictedKill then
		fovSpring:Kick(Vector3.new(-1.6, 0, 0))
		shake(feel.Shake * 0.35)
	end
	if predictedKill then
		showHitmarker("kill")
		SoundKit.Play("Common/Kill")
		if anyHead then
			SoundKit.Play("Common/KillCrunch")
			SoundKit.Play("Common/HitHead", { Volume = 0.8 })
			fovSpring:Kick(Vector3.new(-3, 0, 0))
		end
		if killsThisShot >= 2 then
			SoundKit.Play("Common/KillCrunch")
			task.delay(0.06, function()
				SoundKit.Play("Common/KillCrunch", { Volume = 0.8 })
			end)
		end
		shake(feel.KillShake * (if anyHead then 1.25 else 1) * (if killsThisShot >= 2 then 1.4 else 1))
	end
	-- The brass flies out and stays (pump and bolt guns throw theirs when they cycle).
	if feel.EjectOnFire ~= false then
		ejectCasing()
	end

	-- 4. Recoil: kick the camera and the gun, shake, punch the FOV, shove the player.
	local r = gun.Recoil
	local aimMul = (1 + (r.AimMultiplier - 1) * easeInOut(state.aimAlpha)) * Classes.Perk(player, "Recoil")
	local yaw = randomSigned() * r.Yaw + (r.YawBias or 0)
	-- Scoped: a firm climb, not a jump of a third of the screen (5 Nov 2026).
	local scopeMul = if state.scoped then 0.45 else 1
	camSpring:Kick(Vector3.new(math.rad(r.Pitch), math.rad(yaw), 0) * aimMul * scopeMul)
	kickSpring:Kick(Vector3.new(math.rad(r.KickPitch) * aimMul, math.rad(yaw * 1.5), r.KickBack * aimMul))
	shake(feel.Shake * aimMul)
	fovSpring:Kick(Vector3.new(feel.FovKick * aimMul * (if state.scoped then 0.25 else 1), 0, 0))
	pushPlayer(camCF)
	state.bloom = math.min(state.bloom + gun.Spread.PerShot, gun.Spread.Max)

	startCycle(now)
	if state.mag <= 0 then
		-- Reload once the pump or bolt has thrown the last case.
		local firedWith = gunName
		local wait = 0.2 + (if gun.Cycle then gun.Cycle.Delay + gun.Cycle.Time else 0)
		task.delay(wait, function()
			if state.alive and gunName == firedWith and state.mag <= 0 and not state.switchTo then
				startReload()
			end
		end)
	end
end

-- The gun stands down while something else owns the view: a cutscene (RescueClient, the crash
-- intro) or a mounted gun (EmplacementClient sets OnEmplacement).
local function standDown()
	return player:GetAttribute("Cutscene") or player:GetAttribute("InCutscene") or player:GetAttribute("OnEmplacement")
end

local function canShootNow(now)
	return not standDown()
		and not charFlag("Inside")
		and not charFlag("Devoured")
		and not charFlag("Bandaging")
		and not charFlag("GearReady")
		and not state.reloading
		and not state.cycling
		and not state.switchTo
		and state.mag > 0
		and state.sprintAlpha <= 0.35
		and now - state.equipStart >= (gun.EquipTime or 0.35) * 0.7
		and now - state.lastShot >= 60 / gun.RPM
end

local function tryFire()
	if not state.alive or state.switchTo or charFlag("Devoured") then
		return
	end
	local now = os.clock()
	if state.reloading then
		-- A click stops a shell reload after the shell in hand; the shot follows.
		if gun.ReloadStyle == "Shells" then
			state.reloadStop = true
			state.queuedShot = now
			state.queueWindow = INTERRUPT_WINDOW
		end
		return
	end
	if state.mag <= 0 then
		gunSound("DryFire")
		startReload()
		return
	end
	-- Shooting cancels sprint; the shot goes off as soon as the gun is back up.
	state.sprintBlockedUntil = now + MOVE.SprintBlockAfterShot
	if canShootNow(now) then
		fire()
	else
		state.queuedShot = now
		state.queueWindow = QUEUE_WINDOW
	end
end

-- Switching -------------------------------------------------------------------

-- The old gun drops out of view for SwitchLowerTime, then the new one comes up.
local function equip(name)
	if not state.alive or not tracks[name] then
		return
	end
	if charFlag("Downed") and name ~= DOWNED.Gun then
		return
	end
	if not state.switchTo and name == gunName then
		return
	end
	if state.switchTo == name then
		return
	end
	if state.reloading then
		cancelReload()
	end
	state.cycling = false
	state.queuedShot = nil
	if not state.switchTo then
		state.switchStart = os.clock()
	end
	state.switchTo = name
	EquipRemote:FireServer(name)
end

-- The hotbar's slots equip guns through this (mouse clicks and touch taps).
local hotbarEquip = Instance.new("BindableEvent")
hotbarEquip.Name = "HotbarEquip"
hotbarEquip.Event:Connect(function(name)
	equip(name)
end)
hotbarEquip.Parent = script

-- Keys 1-3 belong to the hotbar (StarterPlayerScripts.Hotbar); ButtonY and the wheel step
-- through the guns you carry (the player attribute "Inventory").
local function carriedGuns()
	local list = {}
	for item in (player:GetAttribute("Inventory") or ""):gmatch("([^|:]+):%d+") do
		if tracks[item] then
			table.insert(list, item)
		end
	end
	return list
end

local function equipOffset(step)
	local list = carriedGuns()
	if #list == 0 then
		return
	end
	local index = table.find(list, state.switchTo or gunName) or 1
	equip(list[(index - 1 + step) % #list + 1])
end

local function finishSwitch(now)
	ammo[gunName] = { state.mag, state.reserve }
	local name = state.switchTo
	state.switchTo = nil
	selectGun(name)
	state.mag, state.reserve = ammo[name][1], ammo[name][2]
	state.magMode = "Gun"
	state.bloom = 0
	state.cycling = false
	state.pushUntil = 0
	state.equipStart = now
	slideKickAt = -math.huge
	buildViewModel()
end

-- New attachments or camo (picked in the lobby, or a run-only one from the zombies Gunsmith): take the numbers and
-- redress the viewmodel, between actions so a reload or a switch is never cut.
local function refreshAttachments()
	if not state.alive or not gunName then
		return
	end
	if state.reloading or state.cycling or state.switchTo then
		task.delay(0.4, refreshAttachments)
		return
	end
	selectGun(gunName)
	state.mag = math.min(state.mag, gun.MagSize)
	for name, entry in ammo do
		entry[1] = math.min(entry[1], Attachments.ConfigFor(player, name).MagSize)
	end
	buildViewModel()
end
for _, attr in { "Attach", "RunAttach", "Camos" } do
	player:GetAttributeChangedSignal(attr):Connect(function()
		task.defer(refreshAttachments)
	end)
end

-- Input -----------------------------------------------------------------------

-- Aim: hold the button, or tap it to toggle. Some mice and touchpads report the right
-- button released the instant the left one goes down; a release that lands with a shot
-- keeps the sights up (latched) until the next aim press, so firing never drops aim.
local AIM_TAP = 0.2
local AIM_DROP_WINDOW = 0.05

local function aimPressed()
	if charFlag("GearReady") then
		return -- a throw is held up (GearClient); the gun is stowed
	end
	-- A press on a latched aim keeps the sights up while held; letting go lowers them.
	state.aimPressAt = if state.aimLatched then nil else os.clock()
	state.aimLatched = false
	state.aimHeld = true
end

local function aimReleased()
	local pressAt = state.aimPressAt
	state.aimPressAt = nil
	if not pressAt then
		-- Letting go of the press that took over a latched aim lowers it.
		if not state.aimLatched then
			state.aimHeld = false
		end
		return
	end
	local now = os.clock()
	if now - state.firePressAt < AIM_DROP_WINDOW or now - pressAt < AIM_TAP then
		state.aimLatched = true
	else
		state.aimHeld = false
	end
end

local function dropAim()
	state.aimHeld = false
	state.aimLatched = false
	state.aimPressAt = nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	-- Keys come from Shared.Controls (the player's own bindings). Reload shares X with use prompts by design:
	-- with a prompt on screen for this press, the prompt takes it.
	if Controls.Is("Fire", input) then
		state.firePressAt = os.clock()
		state.triggerHeld = true
		tryFire()
	elseif Controls.Is("Aim", input) then
		aimPressed()
	elseif Controls.Is("SwitchWeapon", input) then
		equipOffset(1)
	elseif Controls.Is("Reload", input) then
		if not Controls.PromptTakes(input) then
			startReload()
		end
	elseif Controls.Is("Sprint", input) then
		state.sprintHeld = true
		-- Sprinting lowers a toggled aim; a held aim still blocks the sprint. Behind a
		-- scope, Shift holds the breath instead.
		if state.aimLatched and not gun.Scope then
			dropAim()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if Controls.Matches("Fire", input) then
		state.triggerHeld = false
		state.dryClicked = false
	elseif Controls.Matches("Aim", input) then
		aimReleased()
	elseif Controls.Matches("Sprint", input) and Controls.DeviceOf(input) == "Kb" then
		-- Keyboard sprint is held; the controller's stick click toggles it (dropped when you stop running forward).
		state.sprintHeld = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	-- No swap from a wheel that didn't turn, or while aiming (a touchpad's two-finger right
	-- click sends scrolls as the fingers move).
	if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel or input.Position.Z == 0 or state.aimHeld then
		return
	end
	equipOffset(if input.Position.Z > 0 then -1 else 1)
end)

-- Touch buttons (TouchControls) drive the same state. The Fire button follows the gun's
-- TouchFire style, so on a phone one thumb aims and shoots.
local touchAimed = false
local touchInput = Instance.new("BindableEvent")
touchInput.Name = "TouchInput"
touchInput.Event:Connect(function(action, down)
	if action == "Fire" then
		local style = gun.TouchFire or "Hip"
		if down then
			if style ~= "Hip" and not state.aimHeld then
				state.aimHeld = true
				touchAimed = true
			end
			if style ~= "AimRelease" then
				state.firePressAt = os.clock()
				state.triggerHeld = true
				tryFire()
			end
		else
			if style == "AimRelease" then
				state.firePressAt = os.clock()
				state.triggerHeld = true
				tryFire()
			end
			state.triggerHeld = false
			state.dryClicked = false
			if touchAimed then
				touchAimed = false
				if not state.aimLatched then
					state.aimHeld = false
				end
			end
		end
	elseif action == "Aim" and down then
		if state.aimLatched or state.aimHeld then
			dropAim()
		else
			state.aimHeld = true
			state.aimLatched = true
		end
		touchAimed = false
	elseif action == "Reload" and down then
		startReload()
	elseif action == "Swap" and down then
		equipOffset(1)
	elseif action == "Sprint" then
		if down and not state.sprintHeld and state.aimLatched and not state.triggerHeld then
			dropAim()
		end
		state.sprintHeld = down
	end
end)
touchInput.Parent = script

-- Server sync -----------------------------------------------------------------

Remotes.AmmoSync.OnClientEvent:Connect(function(name, mag, reserve)
	if name ~= gunName then
		if ammo[name] then
			ammo[name] = { mag, reserve }
		end
		return
	end
	if state.reloading then
		-- The server finishes slightly early; apply when the animation ends.
		state.pendingSync = { mag, reserve }
	else
		state.mag, state.reserve = mag, reserve
	end
end)

-- 7. The kill: heavier marker, crunch and shake. The server freezes the body, lets it go
-- limp and throws it.
Remotes.HitConfirm.OnClientEvent:Connect(function(enemy, isHead, killed, severed)
	-- Already shown on the frame of the shot.
	if killed and enemy and predictedKills[enemy] then
		if severed and not isHead then
			SoundKit.Play("Common/KillCrunch", { Volume = 0.7 })
		end
		return
	end
	if killed then
		showHitmarker("kill")
		SoundKit.Play("Common/Kill")
		if isHead or severed then
			SoundKit.Play("Common/KillCrunch")
		end
		shake(feel.KillShake)
	elseif severed then
		SoundKit.Play("Common/KillCrunch", { Volume = 0.7 })
		shake(feel.Shake)
	end
end)

Remotes.ShotFx.OnClientEvent:Connect(function(shooter, ends, shooterGun)
	-- The shooter is another player, or a WAR soldier's model (ServerStorage.Modules.Soldier).
	local isModel = typeof(shooter) == "Instance" and shooter:IsA("Model")
	local character = if isModel then shooter else shooter and shooter.Character
	local head = character and character:FindFirstChild("Head")
	if typeof(ends) == "Vector3" then
		ends = { ends }
	end
	if not head or typeof(ends) ~= "table" then
		return
	end
	-- Far off gunfire (a WAR battle has two dozen rifles going) is not drawn or heard here.
	local cam = workspace.CurrentCamera
	local far = if cam then (head.Position - cam.CFrame.Position).Magnitude else 0
	if far > 500 then
		return
	end
	local shooterPlayer = if isModel then nil else shooter
	local shotGun = (if shooterPlayer then Attachments.ConfigFor(shooterPlayer, shooterGun) else nil)
		or GameConfig.Guns[shooterGun] or gun
	local cf = head.CFrame
	local from = cf.Position + cf.LookVector * 1.2 + cf.RightVector * 0.6 - Vector3.yAxis * 0.5
	-- Someone's melee swing (axe, knife): no tracer, no shot; a weapon others can hear (Melee.Heard) whooshes.
	if shotGun.Melee then
		local heard = shotGun.Melee.Heard
		if heard and heard > 0 then
			SoundKit.Play(shotGun.Feel.Sounds .. "/Swing", { Position = from, Volume = heard })
		end
		return
	end
	local muzzle = isModel and character:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") then
		from = muzzle.WorldPosition
		-- Only close soldiers light the scene, and softly: a whole battle relighting it strobed.
		if far < 70 then
			CombatFx.MuzzleLight(from, shotGun.Feel, 0.45)
		end
	end
	for i, endPos in ends do
		if typeof(endPos) == "Vector3" then
			CombatFx.Tracer(from, endPos, shotGun.Feel, i == 1)
		end
	end
	SoundKit.PlayLayers(shotGun.Feel.Sounds, SHOT_LAYERS, { Position = from, Volume = shotGun.Feel.ShotVolume })
end)

-- The last zombie of a wave: a low sting under everything else.
local lastLeft = workspace:GetAttribute("ZombiesLeft") or 0
workspace:GetAttributeChangedSignal("ZombiesLeft"):Connect(function()
	local left = workspace:GetAttribute("ZombiesLeft") or 0
	if left == 0 and lastLeft > 0 and workspace:GetAttribute("WaveState") == "Wave" and player:GetAttribute("InMatch") then
		SoundKit.Play("Common/WaveClear")
		shake(1.2)
	end
	lastLeft = left
end)

-- Taking a hit: the head snaps away from the swipe and the view shakes. PlayerHealthClient
-- draws the screen side (claw marks, vignette, heartbeat).
Remotes:WaitForChild("PlayerHit").OnClientEvent:Connect(function(fromPos, damage, downed, kind)
	if not state.alive or typeof(fromPos) ~= "Vector3" then
		return
	end
	-- A hard landing: the view slams down and wobbles, the knees take it.
	if kind == "Fall" then
		local weight = math.clamp((tonumber(damage) or 20) / 30, 0.5, 1.6)
		camSpring:Kick(Vector3.new(math.rad(-9), 0, randomSigned() * math.rad(4)) * weight)
		shake(4.5 * weight)
		fovSpring:Kick(Vector3.new(-6 * weight, 0, 0))
		return
	end
	local rel = camera.CFrame:PointToObjectSpace(fromPos)
	local side = if rel.X >= 0 then 1 else -1
	local weight = math.clamp((tonumber(damage) or 30) / 34, 0.4, 1.4) * (if downed then 0.6 else 1)
	-- A round from the other player (duel pass): only GameConfig.Pvp.Flinch of the kick, so the first hit doesn't
	-- also throw the victim's aim and decide the fight on its own.
	if kind == "Bullet" then
		weight *= GameConfig.Pvp.Flinch or 1
	end
	camSpring:Kick(Vector3.new(math.rad(-3.5), side * math.rad(5.5), -side * math.rad(7)) * weight)
	shake(3.5 * weight)
	fovSpring:Kick(Vector3.new(-4 * weight, 0, 0))
end)

-- Per-frame -------------------------------------------------------------------

local function updateAmmoNote(dt)
	local text = nil
	if state.alive and state.mag == 0 and not state.reloading and not state.switchTo
		and not standDown() and player:GetAttribute("InMatch") and not charFlag("Inside")
	then
		emptySince = emptySince or os.clock()
		if state.reserve <= 0 and not INFINITE_RESERVE then
			text = "out of ammo"
		elseif os.clock() - emptySince > 0.4 then
			text = "reload"
		end
	else
		emptySince = nil
	end
	if text then
		ammoNote.Text = text
	end
	ammoNoteAlpha += ((if text then 1 else 0) - ammoNoteAlpha) * math.min(1, dt * 8)
	ammoNote.TextTransparency = 1 - ammoNoteAlpha * 0.8
	ammoNote.TextStrokeTransparency = 1 - ammoNoteAlpha * 0.35
end

local function updateHud(spreadDeg, aim)
	local halfFov = math.rad(camera.FieldOfView / 2)
	local gap = math.tan(math.rad(spreadDeg)) / math.tan(halfFov) * camera.ViewportSize.Y / 2
	gap = math.max(gap, 3) + 5
	crosshair.Top.Position = UDim2.fromOffset(0, -gap)
	crosshair.Bottom.Position = UDim2.fromOffset(0, gap)
	crosshair.Left.Position = UDim2.fromOffset(-gap, 0)
	crosshair.Right.Position = UDim2.fromOffset(gap, 0)

	-- Fade out while aiming down sights or sprinting; iron sights take over.
	local fade = math.max(aim, state.sprintAlpha)
	for _, line in crosshair:GetChildren() do
		if line:IsA("Frame") then
			line.BackgroundTransparency = fade
			local s = line:FindFirstChildOfClass("UIStroke")
			if s then
				s.Transparency = 0.5 + 0.5 * fade
			end
		end
	end

	-- Melee: no rounds to count.
	magLabel.Text = if gun.Melee then "" else tostring(state.mag)
	reserveLabel.Text = if gun.Melee then "" elseif INFINITE_RESERVE then "/ ∞" else "/ " .. state.reserve
	local low = state.mag <= math.max(1, math.floor(gun.MagSize * 0.25))
	magLabel.TextColor3 = if low then LOW_AMMO else WHITE
	magLabel.TextTransparency = if state.reloading then 0.5 else 0
	magFill.Size = UDim2.fromScale(state.mag / gun.MagSize, 1)

	if hitmarker.Visible and os.clock() > hitmarkerHideAt then
		hitmarker.Visible = false
	end
end

-- Scope: the overlay replaces the viewmodel once the sights are nearly up.
local function setScoped(scoped)
	if scoped == state.scoped then
		return
	end
	state.scoped = scoped
	scopeFrame.Visible = scoped
	setViewModelHidden(scoped)
	if scoped then
		scopeBlackout.BackgroundTransparency = 0
		TweenService:Create(scopeBlackout, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
end

-- Idle sway behind a scope (radians): a slow figure of eight. Shift holds the breath
-- steady until it runs out; after that the sway is worse while it recovers.
local function scopeSway(now, dt, scope)
	local holding = state.sprintHeld and state.breath > 0
	if holding then
		state.breath = math.max(0, state.breath - dt)
	else
		state.breath = math.min(scope.HoldBreath, state.breath + dt * scope.HoldBreath / scope.BreathRecover)
	end
	local target = if holding then 0.08 elseif state.breath < scope.HoldBreath * 0.25 then 1.7 else 1
	state.swayMult = smooth(state.swayMult, target, 5, dt)
	local a = math.rad(scope.Sway) * state.swayMult
	return Vector3.new(math.sin(now * 1.1) * a * 0.6, math.sin(now * 0.7 + 1.3) * a, 0)
end

local cutsceneHidden = false

local function update(dt)
	if not state.alive or not viewModel or not humanoid or not rootPart then
		updateAmmoNote(math.min(dt, 0.1))
		return
	end
	-- The rescue cutscene (StarterPlayerScripts.RescueClient) owns the camera: the gun and arms
	-- go out of view until it ends. So does hiding inside a dumpster (HideWatch's camera), and a
	-- body taken away alive (an escape sends you to the menu without dying).
	if standDown() or charFlag("Inside") or not rootPart.Parent then
		if not cutsceneHidden then
			cutsceneHidden = true
			setViewModelHidden(true)
			crosshair.Visible = false
		end
		lastCamCF = nil
		updateAmmoNote(math.min(dt, 0.1))
		return
	elseif cutsceneHidden then
		cutsceneHidden = false
		setViewModelHidden(false)
		crosshair.Visible = true
	end
	dt = math.min(dt, 0.1)
	local now = os.clock()

	if state.switchTo and now - state.switchStart >= GameConfig.SwitchLowerTime then
		finishSwitch(now)
	end

	if state.reloading then
		stepReload(now)
	end

	if state.queuedShot then
		if now - state.queuedShot > state.queueWindow then
			state.queuedShot = nil
		elseif canShootNow(now) then
			fire()
		end
	end

	-- Full auto keeps firing while the trigger is held; an empty mag clicks once.
	if gun.FireMode == "Auto" and state.triggerHeld and not state.switchTo then
		if state.mag > 0 then
			if canShootNow(now) then
				fire()
			end
		elseif not state.reloading and not state.dryClicked then
			state.dryClicked = true
			gunSound("DryFire")
			startReload()
		end
	end

	-- Movement: sprint, aim, walk speed
	local speed = horizontalSpeed()
	local look = camera.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local forwardness = if flatLook.Magnitude > 0.01 then humanoid.MoveDirection:Dot(flatLook.Unit) else 0
	if Platform.IsGamepad() and forwardness < 0.3 then
		state.sprintHeld = false
	end
	local down = charFlag("Downed")
	-- Nothing to aim with an axe or a knife.
	local wantsAim = state.aimHeld and not state.reloading and not state.switchTo and not gun.Melee
	-- Hiding and sliding (StarterPlayerScripts.Evade) never count as sprinting, and starting to
	-- sprint stands you up out of a crouch.
	local evading = charFlag("Hiding") or charFlag("Sliding")
	local crouched = charFlag("Crouching") and not evading
	if crouched and state.sprintHeld and forwardness > 0.6 and not down and not wantsAim then
		evadeStand:Fire()
		crouched = false
	end
	local sprinting = not down and not evading and state.sprintHeld and forwardness > 0.6 and not wantsAim and now >= state.sprintBlockedUntil

	state.aimAlpha = approach(state.aimAlpha, if wantsAim then 1 else 0, dt / gun.AimTime)
	state.sprintAlpha = smooth(state.sprintAlpha, if sprinting then 1 else 0, 10, dt)
	local aim = easeInOut(state.aimAlpha)
	local scope = gun.Scope
	setScoped(scope ~= nil and state.aimAlpha >= scope.At)

	if charFlag("Devoured") or charFlag("Hiding") then
		humanoid.WalkSpeed = 0
	elseif down then
		humanoid.WalkSpeed = DOWNED.Speed
	else
		local baseSpeed = if sprinting then MOVE.SprintSpeed elseif wantsAim then MOVE.AimSpeed else MOVE.WalkSpeed
		if crouched then
			baseSpeed = math.min(baseSpeed, GameConfig.Evade.CrouchSpeed)
		end
		-- Gun weight (Shared.Attachments): heavier guns walk and aim slower and lose more when sprinting.
		humanoid.WalkSpeed = baseSpeed * (if sprinting then gun.SprintMult or gun.MoveSpeed or 1 else gun.MoveSpeed or 1)
	end
	local fovPunch = fovSpring:Update(dt)
	if state.scoped then
		camera.FieldOfView = scope.Fov + fovPunch.X * 0.5
	else
		-- The player's field of view (Options Fov) moves the aimed view with it.
		local hipFov = Options.Get("Fov")
		local aimFov = gun.AimFov * hipFov / CAM.HipFov
		camera.FieldOfView = hipFov + (aimFov - hipFov) * aim + CAM.SprintFovBonus * state.sprintAlpha + fovPunch.X
	end

	-- Mouse look: the player's sensitivity (Options LookSens), and AimSens on top while aiming.
	local aimSens = Options.Get("AimSens")
	local sensitivity = Options.Get("LookSens")
		* (if state.scoped then scope.Sensitivity * aimSens else 1 + (gun.AimSensitivity * aimSens - 1) * aim)
	if math.abs(sensitivity - currentSensitivity) > 0.01 then
		currentSensitivity = sensitivity
		pcall(function()
			UserInputService.MouseDeltaSensitivity = sensitivity
		end)
	end

	-- Aiming (player attribute) for gyro aim set to "Aiming" (TouchControls).
	local aiming = state.scoped or aim > 0.5
	if (player:GetAttribute("Aiming") == true) ~= aiming then
		player:SetAttribute("Aiming", aiming)
	end

	state.bloom = math.max(0, state.bloom - gun.Spread.Recover * dt)

	-- The blast's shove on the shooter: never slower than the push backward while it lasts.
	if now < state.pushUntil then
		local k = 1 - (now - state.pushStart) / (state.pushUntil - state.pushStart)
		local v = rootPart.AssemblyLinearVelocity
		local along = Vector3.new(v.X, 0, v.Z):Dot(state.pushDir)
		local want = state.pushSpeed * k
		if along < want then
			rootPart.AssemblyLinearVelocity = v + state.pushDir * (want - along)
		end
	end

	-- Camera: sway input, then recoil, shake and scope sway. The camera module builds each
	-- frame from the current look direction, so pitch/yaw go in as a per-frame delta (and
	-- recover fully), while roll is dropped every frame and goes in whole.
	local camBase = camera.CFrame
	if lastCamCF then
		-- Controller look speed, invert and aim assist (Shared.AimAssist; never on mouse and keyboard) bend this
		-- frame's look input before anything else reads it.
		if camera.CameraType == Enum.CameraType.Custom and humanoid then
			local padSens = (Options.Get("PadSens") or 1) * sensitivity / math.max(Options.Get("LookSens") or 1, 0.05)
			camBase = AimAssist.Step(dt, lastCamCF, camBase, {
				mode = Platform.Get(),
				preset = Options.Get("AimAssist"),
				aim = aim,
				moving = humanoid.MoveDirection.Magnitude > 0.1,
				sens = padSens,
				invert = Options.Get("InvertY") == true,
				ignore = { player.Character :: Instance, camera },
			})
		end
		local rx, ry = lastCamCF:ToObjectSpace(camBase):ToEulerAnglesYXZ()
		local lag = 0.55 * (1 - 0.75 * aim)
		local p = swaySpring.Position - Vector3.new(rx, ry, 0) * lag
		if p.Magnitude > 0.12 then
			p = p.Unit * 0.12
		end
		swaySpring.Position = p
	end
	local offset = camSpring:Update(dt) + shakeSpring:Update(dt)
	-- A slide's lean (StarterPlayerScripts.Evade).
	local evadeTilt = humanoid:GetAttribute("EvadeTilt")
	if typeof(evadeTilt) == "Vector3" then
		offset += evadeTilt
	end
	if scope then
		local sway = scopeSway(now, dt, scope)
		if state.scoped then
			offset += sway
		end
	end
	local delta = offset - lastCamOffset
	lastCamOffset = Vector3.new(offset.X, offset.Y, 0)
	lastCamCF = camBase * CFrame.Angles(delta.X, delta.Y, 0)
	camera.CFrame = lastCamCF * CFrame.Angles(0, 0, offset.Z)

	-- Viewmodel pose
	local sway = swaySpring:Update(dt)
	local kick = kickSpring:Update(dt)

	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local moveAmount = math.clamp(speed / MOVE.WalkSpeed, 0, 1.5)
	bobAmount = smooth(bobAmount, if grounded then moveAmount else 0, 8, dt)
	bobTime += dt * speed * 0.55
	local bobScale = bobAmount * (1 - 0.85 * aim) * (1 + 0.8 * state.sprintAlpha) * Options.Get("Bob")
	local bob = CFrame.new(math.sin(bobTime) * 0.035 * bobScale, -math.abs(math.cos(bobTime)) * 0.03 * bobScale, 0)
		* CFrame.Angles(0, 0, math.sin(bobTime) * 0.02 * bobScale)
	local breathe = CFrame.new(0, math.sin(now * 1.6) * 0.006 * (1 - aim), 0)

	local sa = state.sprintAlpha
	local sprintPose = CFrame.new(-0.05 * sa, -0.12 * sa, 0.05 * sa)
		* CFrame.Angles(math.rad(-22) * sa, math.rad(38) * sa, math.rad(14) * sa)

	local animGun, animHand, ch = animPose(now)

	local equip = 1 - (1 - math.clamp((now - state.equipStart) / (gun.EquipTime or 0.35), 0, 1)) ^ 3
	local equipPose = CFrame.new(0, -0.5 * (1 - equip), 0.1 * (1 - equip)) * CFrame.Angles(math.rad(-50) * (1 - equip), 0, 0)
	local lower = if state.switchTo then math.clamp((now - state.switchStart) / GameConfig.SwitchLowerTime, 0, 1) else 0
	local lowerPose = CFrame.new(0, -0.45 * lower, 0.08 * lower) * CFrame.Angles(math.rad(-40) * lower, 0, math.rad(-8) * lower)
	-- Bandaging puts the gun down out of view (the hands are in StarterPlayerScripts.BandageView).
	local gearReady = charFlag("GearReady")
	if gearReady and (state.aimHeld or state.aimLatched) then
		dropAim()
	end
	state.stowAlpha = approach(state.stowAlpha or 0, if charFlag("Bandaging") or gearReady then 1 else 0,
		dt * (if gearReady then 8 else 4))
	local stow = easeInOut(state.stowAlpha)
	lowerPose *= CFrame.new(0.15 * stow, -1.3 * stow, 0.25 * stow) * CFrame.Angles(math.rad(-55) * stow, 0, math.rad(-20) * stow)

	local swayScale = 1 - 0.7 * aim
	local swayCF = CFrame.Angles(sway.X * swayScale, sway.Y * swayScale, sway.Y * 0.6 * swayScale)
	local kickCF = CFrame.new(0, 0, kick.Z) * CFrame.Angles(kick.X, kick.Y, 0)

	-- Tuning aid: the player attributes DebugHipOffset / DebugHipAngles (Vector3) override the
	-- gun's hip pose while set.
	local hip = hipCF
	local debugHip = player:GetAttribute("DebugHipOffset")
	if typeof(debugHip) == "Vector3" then
		local debugAngles = player:GetAttribute("DebugHipAngles")
		hip = CFrame.new(debugHip) * anglesDeg(if typeof(debugAngles) == "Vector3" then debugAngles else gun.HipAngles)
	end
	vmCamCF = camera.CFrame
	local rootCF = camera.CFrame * hip:Lerp(aimCF, aim) * bob * breathe * swayCF * sprintPose * animGun * equipPose * lowerPose * kickCF
	lastRootCF = rootCF

	-- Moving parts: the slide (or bolt carrier) kicks back on each shot, locks back on an
	-- empty pistol; the pump and the bolt follow their animation channels.
	local travel = gun.SlideTravel or 0
	local slideBack = 0
	if gun.SlideKick ~= false then
		local sinceShot = now - slideKickAt
		if sinceShot < SLIDE_KICK_TIME then
			slideBack = travel * (1 - sinceShot / SLIDE_KICK_TIME)
		end
	end
	if ch.Slide then
		slideBack = ch.Slide * travel
	elseif gun.LockOnEmpty and state.mag == 0 and not state.reloading then
		slideBack = travel
	end
	local slideCF = CFrame.new(0, 0, slideBack)
	local pumpCF = CFrame.new(0, 0, (ch.Pump or 0) * (gun.PumpTravel or 0))
	local lift = (ch.BoltLift or 0) * math.rad(gun.BoltLiftAngle or 0)
	local boltCF = slideCF * boltAxis * CFrame.Angles(0, 0, lift) * boltAxis:Inverse()
	-- The left hand rides the pump.
	local handCF = pumpCF * animHand

	local cframes = table.create(#vmParts)
	for i, part in vmParts do
		local group = vmGroups[part]
		local offsetCF = vmOffsets[part]
		if group == "Slide" then
			cframes[i] = rootCF * slideCF * offsetCF
		elseif group == "Bolt" then
			cframes[i] = rootCF * boltCF * offsetCF
		elseif group == "Pump" then
			cframes[i] = rootCF * pumpCF * offsetCF
		elseif group == "Mag" and state.magMode == "Hand" then
			cframes[i] = rootCF * handCF * magInHandCF * magRel[part]
		elseif group == "Shell" then
			cframes[i] = rootCF * handCF * shellInHandCF
		elseif group == "LeftHand" then
			cframes[i] = rootCF * handCF * offsetCF
		else
			cframes[i] = rootCF * offsetCF
		end
	end
	workspace:BulkMoveTo(vmParts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	if arms then
		local rightCF = rootCF * rightGripCF
		-- Working a bolt: the right hand leaves the grip for the bolt handle.
		local onBolt = ch.RightHand or 0
		if onBolt > 0 and boltHandle then
			local handle = rootCF * boltCF * boltHandle
			rightCF = rightCF:Lerp(CFrame.new(handle.Position) * rightCF.Rotation, onBolt)
		end
		local shoulder = player:GetAttribute("DebugLeftShoulder")
		arms:Update(camera.CFrame * bob * breathe, rightCF, rootCF * handCF * leftGripCF, aim, if typeof(shoulder) == "Vector3" then shoulder else gun.LeftShoulder)
	end
	for _, p in magParts do
		p.LocalTransparencyModifier = if vmHidden or state.magMode == "Hidden" then 1 else 0
	end
	if shellPart then
		shellPart.LocalTransparencyModifier = if not vmHidden and state.magMode == "Hand" then 0 else 1
	end

	if now > flashHideAt then
		if flashJet and flashJet.Enabled then
			flashJet.Enabled = false
		end
		if flashLight and flashLight.Brightness > 0 then
			flashLight.Brightness = 0
		end
	end

	updateHud(currentSpread() + pelletCone(), aim)
	updateAmmoNote(dt)
end

RunService:BindToRenderStep("LastLightGun", Enum.RenderPriority.Camera.Value + 1, update)

-- Character lifecycle -------------------------------------------------------------

-- Going down: last stand with the pistol. Getting up brings back the gun you had out.
local gunBeforeDown = nil

local function onDownedChanged(character)
	if character ~= player.Character then
		return
	end
	if character:GetAttribute("Downed") then
		gunBeforeDown = state.switchTo or gunName
		dropAim()
		state.sprintHeld = false
		if gunBeforeDown ~= DOWNED.Gun then
			equip(DOWNED.Gun)
		end
	elseif gunBeforeDown then
		local back = gunBeforeDown
		gunBeforeDown = nil
		if back ~= DOWNED.Gun then
			equip(back)
		end
	end
end

-- Being eaten: the gun goes; the screen is PlayerHealthClient's.
local function onDevouredChanged(character)
	if character ~= player.Character or not character:GetAttribute("Devoured") then
		return
	end
	state.triggerHeld = false
	dropAim()
	setScoped(false)
	setViewModelHidden(true)
	crosshair.Visible = false
	ammoFrame.Visible = false
	hitmarker.Visible = false
end

local function onCharacter(character)
	camera = workspace.CurrentCamera
	gunBeforeDown = nil
	character:GetAttributeChangedSignal("Downed"):Connect(function()
		onDownedChanged(character)
	end)
	character:GetAttributeChangedSignal("Devoured"):Connect(function()
		onDevouredChanged(character)
	end)
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	-- A bandage wrapped on an arm shows on the first-person arms too (ViewArms copies it).
	character.DescendantAdded:Connect(function(d)
		if d.Name == "Bandage" and d:IsA("BasePart") and d.Parent and d.Parent.Name:find("Arm") then
			task.defer(buildArms)
		end
	end)

	for _, name in LOADOUT do
		local g = GameConfig.Guns[name]
		ammo[name] = { Attachments.ConfigFor(player, name).MagSize, g.Reserve }
	end
	-- In hand: the first gun this life carries (slot order), as GunServer does. If the new kit lands after this, the
	-- hotbar brings its first gun up (Hotbar refresh).
	selectGun(carriedGuns()[1] or LOADOUT[1])
	state.alive = true
	state.mag = gun.MagSize
	state.reserve = gun.Reserve
	cancelReload()
	state.cycling = false
	state.switchTo = nil
	state.queuedShot = nil
	state.triggerHeld = false
	state.bloom = 0
	dropAim()
	state.aimAlpha = 0
	state.sprintAlpha = 0
	state.pushUntil = 0
	state.equipStart = os.clock()
	state.breath = if gun.Scope then gun.Scope.HoldBreath else 4
	swaySpring:Reset()
	kickSpring:Reset()
	camSpring:Reset()
	shakeSpring:Reset()
	fovSpring:Reset()
	lastCamOffset = Vector3.zero
	lastCamCF = nil

	buildViewModel()
	setScoped(false)
	setViewModelHidden(false)
	-- Avatar clothes and body parts arrive after the character spawns; dress the arms again then.
	if not player:HasAppearanceLoaded() then
		player.CharacterAppearanceLoaded:Once(function(loaded)
			if loaded == player.Character then
				buildArms()
			end
		end)
	end
	crosshair.Visible = true
	ammoFrame.Visible = true
	UserInputService.MouseIconEnabled = false

	humanoid.Died:Once(function()
		state.alive = false
		if viewModel then
			viewModel:Destroy()
			viewModel = nil
			arms = nil
		end
		setScoped(false)
		crosshair.Visible = false
		ammoFrame.Visible = false
		hitmarker.Visible = false
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end
