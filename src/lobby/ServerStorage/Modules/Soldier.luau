-- NPC soldiers for WAR (HORROR-SHOOTER-WAR.md): HOUND's squad (allies) and the Lamplighters, the
-- militia that follows the Beacon (enemies). Numbers: GameConfig.War.Soldiers[kind].
--   Bodies are clones of ServerStorage.SoldierRigs (Toolbox R15 operators, scripts stripped, enemy
--   gear re-coloured, each holding the Toolbox carbine in a rifle-ready pose; AttireLineup is the
--   fallback). Rig may be a list: one is picked at random. Walked by a copy of the zombie's Animate
--   with the plain R15 idle/walk/run; StarterPlayerScripts.SoldierPose keeps the arms on the rifle
--   and leans the upper body to AimPitch on every client.
--   Enemies are tagged Enemy with MobType Lamplighter, so player guns hit them through GunServer and
--   MobReactions (reactions, ragdoll, fade; no limb tearing, black lamp-oil blood). Allies are
--   tagged Ally: zombies hunt them (MobAI, MobAttack) and enemy rounds hit them, but they never die:
--   at zero they sit down hurt for DownTime seconds (a player can hold E to get them up sooner).
--   Shots: a server ray from the muzzle with spread by range; players take PlayerHealth.Damage
--   (kind Bullet), mobs MobReactions.Hit, allies Soldier.Hurt. Every client draws the tracer and
--   plays the gun from Remotes.ShotFx (shooter = the soldier's model).
-- Attributes on the model: Soldier (kind), Side ("Ally"/"Enemy"), Callsign, AimPitch, Downed.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local PlayerHealth = require(script.Parent.PlayerHealth)
local MobReactions = require(script.Parent.MobReactions)
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.War
local LINEUP = ReplicatedStorage.Assets.AttireLineup
local RIGS = ServerStorage:FindFirstChild("SoldierRigs")
local VIEW = ReplicatedStorage.Assets.ViewModels
local ANIMATE = ServerStorage.TestZombie:FindFirstChild("Animate")
local TICK = 0.2

-- The plain R15 set (the zombie's Animate script, its overrides swapped for these).
local ANIMS = {
	idle = { Animation1 = "rbxassetid://507766388", Animation2 = "rbxassetid://507766666" },
	walk = { RunAnim = "rbxassetid://507767714" },
}
local LIMBS = {
	Head = "Head",
	LeftUpperArm = "LeftArm", LeftLowerArm = "LeftArm", LeftHand = "LeftArm",
	RightUpperArm = "RightArm", RightLowerArm = "RightArm", RightHand = "RightArm",
	LeftUpperLeg = "LeftLeg", LeftLowerLeg = "LeftLeg", LeftFoot = "LeftLeg",
	RightUpperLeg = "RightLeg", RightLowerLeg = "RightLeg", RightFoot = "RightLeg",
}

local Soldier = {}
Soldier.__index = Soldier

local folders = {}
local function folder(side)
	local f = folders[side]
	if not f or not f.Parent then
		f = Instance.new("Folder")
		f.Name = if side == "Ally" then "Squad" else "Hostiles"
		f.Parent = workspace
		folders[side] = f
	end
	return f
end

local live = {} -- [model] = soldier

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function between(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

-- Rays that see the world and bodies, not glass-like effects or guns.
local function rayParams(ignore)
	local list = { workspace:FindFirstChild("Fx"), workspace:FindFirstChild("Relics") }
	for _, i in ignore do
		table.insert(list, i)
	end
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = list
	p.IgnoreWater = true
	return p
end

-- What a ray hit, as a side: a player's character, an ally, an enemy (mob or Lamplighter).
local function ownerOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model and model.Parent ~= workspace and not model:FindFirstChildOfClass("Humanoid") do
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	if not model then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return "Player", model, player
	end
	if CollectionService:HasTag(model, "Ally") then
		return "Ally", model
	end
	if CollectionService:HasTag(model, "Enemy") then
		return "Enemy", model
	end
	return nil
end

-- The rifle. A SoldierRigs body comes with its own (attribute Rifle): the Toolbox carbine welded in
-- the right hand, the arms posed holding it, and a Muzzle attachment at the barrel tip; SoldierPose
-- keeps the arms in that pose while the legs walk. Otherwise the view model is scaled to the hands
-- and held on GunJoint, and SoldierPose aims it with arm IK.
local function arm(model, gunName)
	if model:GetAttribute("Rifle") then
		local gun = model:FindFirstChild("Gun")
		local muzzle = gun and gun:FindFirstChild("Muzzle", true)
		if muzzle then
			return gun, muzzle
		end
	end
	local source = VIEW:FindFirstChild(gunName) or VIEW.AK
	local gun = source:Clone()
	gun.Name = "Gun"
	for _, d in gun:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Light") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	local root = gun:FindFirstChild("Root") or gun.PrimaryPart
	gun.PrimaryPart = root
	local muzzle, grip, sight = root:FindFirstChild("Muzzle"), root:FindFirstChild("RightGrip"), root:FindFirstChild("AimPoint")
	if not (muzzle and grip) then
		gun:Destroy()
		return nil
	end
	local reach = (muzzle.WorldPosition - grip.WorldPosition).Magnitude
	if reach > 0 then
		gun:ScaleTo(gun:GetScale() * (CFG.GunReach[gunName] or CFG.GunReach.AK) / reach)
	end
	-- Everything on the gun rides its Root; nothing on it collides, weighs or stops a ray.
	for _, d in gun:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = d.Size.Magnitude > 0.3
			if d ~= root and not d:FindFirstChildWhichIsA("JointInstance") then
				-- A Weld with its offset written now; a WeldConstraint would take the offset when the
				-- soldier enters the world, after GunJoint has already moved the Root to the hand.
				local weld = Instance.new("Weld")
				weld.Part0, weld.Part1 = root, d
				weld.C0 = root.CFrame:ToObjectSpace(d.CFrame)
				weld.Parent = d
			end
		end
	end
	local flash = gun:FindFirstChild("Flash", true)
	if flash and flash:IsA("BasePart") then
		flash.Transparency = 1
	end
	-- The grip's frame: forward along the barrel, up toward the sights.
	local gripW, muzzleW = grip.WorldPosition, muzzle.WorldPosition
	local dir = (muzzleW - gripW).Unit
	local up = if sight then sight.WorldPosition - gripW else root.CFrame.UpVector
	up = (up - dir * up:Dot(dir))
	up = if up.Magnitude > 1e-3 then up.Unit else Vector3.yAxis
	local gripFrame = CFrame.lookAt(gripW, gripW + dir, up)
	local torso = model:FindFirstChild("UpperTorso")
	local joint = Instance.new("Motor6D")
	joint.Name = "GunJoint"
	joint.Part0 = torso
	joint.Part1 = root
	joint.C0 = CFG.GunHold -- the right hand's grip, in the torso's frame
	joint.C1 = root.CFrame:ToObjectSpace(gripFrame)
	joint.Parent = torso
	gun.Parent = model
	return gun, muzzle
end

local function dress(model, kind)
	local look = CFG.Looks[kind]
	if not look then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Shirt") and look.Shirt then
			d.ShirtTemplate = look.Shirt
		elseif d:IsA("Pants") and look.Pants then
			d.PantsTemplate = look.Pants
		elseif d:IsA("BodyColors") and look.Skin then
			d.HeadColor3, d.LeftArmColor3, d.RightArmColor3 = look.Skin, look.Skin, look.Skin
			d.TorsoColor3, d.LeftLegColor3, d.RightLegColor3 = look.Skin, look.Skin, look.Skin
		end
	end
	-- The Lamplighter's lamp: a caged light on the chest that sweeps where it looks.
	if look.Lamp then
		local torso = model:FindFirstChild("UpperTorso")
		local lamp = Instance.new("Part")
		lamp.Name = "ChestLamp"
		lamp.Shape = Enum.PartType.Cylinder
		lamp.Size = Vector3.new(0.35, 0.55, 0.55)
		lamp.Material = Enum.Material.Neon
		lamp.Color = look.Lamp
		lamp.CanCollide, lamp.CanQuery, lamp.CanTouch, lamp.Massless = false, false, false, true
		lamp.CastShadow = false
		local cage = Instance.new("Part")
		cage.Name = "LampCage"
		cage.Shape = Enum.PartType.Cylinder
		cage.Size = Vector3.new(0.3, 0.68, 0.68)
		cage.Material = Enum.Material.DiamondPlate
		cage.Color = Color3.fromRGB(38, 34, 30)
		cage.Transparency = 0.35
		cage.CanCollide, cage.CanQuery, cage.CanTouch, cage.Massless = false, false, false, true
		local at = torso.CFrame * CFrame.new(-0.35, 0.25, -0.62) * CFrame.Angles(0, math.rad(90), 0)
		lamp.CFrame, cage.CFrame = at, at * CFrame.new(-0.06, 0, 0)
		for _, p in { lamp, cage } do
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = torso, p
			w.Parent = p
			p.Parent = model
		end
		local beamFrom = Instance.new("Attachment")
		beamFrom.Parent = lamp
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Left
		spot.Range = 34
		spot.Angle = 50
		spot.Brightness = 2.4
		spot.Color = look.Lamp
		spot.Parent = lamp
		local glow = Instance.new("PointLight")
		glow.Range = 7
		glow.Brightness = 1.2
		glow.Color = look.Lamp
		glow.Shadows = false
		glow.Parent = lamp
	end
	-- A gas mask: dark faceplate and a filter can, over the face.
	if look.Mask then
		local head = model:FindFirstChild("Head")
		local plate = Instance.new("Part")
		plate.Name = "Mask"
		plate.Size = Vector3.new(1.05, 0.72, 0.3)
		plate.Material = Enum.Material.Rubber
		plate.Color = look.Mask
		local can = Instance.new("Part")
		can.Name = "MaskFilter"
		can.Shape = Enum.PartType.Cylinder
		can.Size = Vector3.new(0.32, 0.42, 0.42)
		can.Material = Enum.Material.Metal
		can.Color = Color3.fromRGB(58, 60, 54)
		local eyes = Instance.new("Part")
		eyes.Name = "MaskEyes"
		eyes.Size = Vector3.new(0.82, 0.2, 0.06)
		eyes.Material = Enum.Material.Glass
		eyes.Color = Color3.fromRGB(150, 120, 60)
		eyes.Reflectance = 0.3
		local face = head.CFrame
		plate.CFrame = face * CFrame.new(0, -0.08, -0.5)
		eyes.CFrame = face * CFrame.new(0, 0.12, -0.66)
		can.CFrame = face * CFrame.new(0, -0.3, -0.75) * CFrame.Angles(0, math.rad(90), 0)
		for _, p in { plate, can, eyes } do
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p.CastShadow = false
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = head, p
			w.Parent = p
			p.Parent = model
		end
		for _, d in head:GetChildren() do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
	end
end

local function build(kind, cf, opts)
	local stats = CFG.Soldiers[kind]
	local rigName = opts.Rig or stats.Rig
	if type(rigName) == "table" then
		rigName = rigName[math.random(#rigName)]
	end
	local source = (RIGS and RIGS:FindFirstChild(rigName)) or LINEUP:FindFirstChild(rigName) or LINEUP.SWATSoldier
	local model = source:Clone()
	model.Name = opts.Callsign or kind
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			local limb = LIMBS[d.Name]
			if limb then
				d:SetAttribute("Limb", limb)
			end
		end
	end
	if stats.Scale and stats.Scale ~= 1 then
		model:ScaleTo(stats.Scale)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = stats.Health
	humanoid.Health = stats.Health
	humanoid.WalkSpeed = stats.WalkSpeed
	humanoid.AutoRotate = false
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
	model:PivotTo(cf)
	dress(model, kind)
	if ANIMATE then
		local animate = ANIMATE:Clone()
		for set, ids in ANIMS do
			local f = animate:FindFirstChild(set)
			if f then
				for name, id in ids do
					local a = f:FindFirstChild(name)
					if a then
						a.AnimationId = id
					end
				end
			end
		end
		animate.Parent = model
	end
	local _, muzzle = arm(model, opts.Gun or stats.Gun)

	-- Turning: the body faces where the soldier aims (or walks), strafing when they differ.
	local root = model.PrimaryPart
	local att = Instance.new("Attachment")
	att.Name = "FaceAt"
	att.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.Responsiveness = 22
	align.MaxTorque = 1e6
	align.PrimaryAxisOnly = true
	align.CFrame = CFrame.lookAt(Vector3.zero, flat(cf.LookVector).Unit)
	align.Parent = root

	model:SetAttribute("Soldier", kind)
	model:SetAttribute("AimPitch", 0)
	return model, humanoid, muzzle, align
end

-- Spawns one soldier. kind: a key of GameConfig.War.Soldiers ("Ally", "Lamplighter", "Heavy").
-- opts: Callsign, Rig, Gun, Post (Vector3 to hold), Leash (studs from Post), Follow (function
-- returning the point an ally keeps near), Slot (formation index), Advance (Vector3 an enemy pushes to).
function Soldier.Spawn(kind, cf, opts)
	opts = opts or {}
	local stats = CFG.Soldiers[kind]
	local side = stats.Side
	local model, humanoid, muzzle, align = build(kind, cf, opts)
	local self = setmetatable({
		Kind = kind,
		Side = side,
		Stats = stats,
		Model = model,
		Humanoid = humanoid,
		Root = model.PrimaryPart,
		Muzzle = muzzle,
		Align = align,
		Gun = GameConfig.Guns[opts.Gun or stats.Gun] or GameConfig.Guns.AK,
		GunName = opts.Gun or stats.Gun,
		Post = opts.Post or cf.Position,
		Leash = opts.Leash or stats.Leash or 12,
		Follow = opts.Follow,
		Slot = opts.Slot or 1,
		Advance = opts.Advance,
		Target = nil,
		TargetAt = 0,
		Mag = stats.Mag,
		Downed = false,
		Path = nil,
		PathGoal = nil,
		PathAt = 0,
		Waypoints = nil,
		WaypointIndex = 0,
		StrafeAt = 0,
		Strafe = Vector3.zero,
		SeenAt = 0,
		Alive = true,
	}, Soldier)
	model:SetAttribute("Side", side)
	if opts.Callsign then
		model:SetAttribute("Callsign", opts.Callsign)
	end
	if side == "Enemy" then
		CollectionService:AddTag(model, "Enemy")
		model:SetAttribute("MobType", stats.MobType or "Lamplighter")
		model:SetAttribute("MatchMob", true)
	else
		CollectionService:AddTag(model, "Ally")
		self:MakeRevivePrompt()
	end
	CollectionService:AddTag(model, "Soldier")
	model.Parent = folder(side)
	pcall(function()
		self.Root:SetNetworkOwner(nil)
	end)
	if side == "Enemy" then
		MobReactions.Spawned(model)
		humanoid.Died:Once(function()
			self.Alive = false
			live[model] = nil
		end)
	end
	live[model] = self
	self.Path = PathfindingService:CreatePath({
		AgentRadius = 1.6,
		AgentHeight = 5.5,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})
	task.spawn(self.Run, self)
	return self
end

-- A downed ally: a prompt on the body so a player can get them up.
function Soldier:MakeRevivePrompt()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Revive"
	prompt.ActionText = "Revive"
	prompt.ObjectText = self.Model:GetAttribute("Callsign") or ""
	prompt.HoldDuration = self.Stats.ReviveHold or 2
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = false
	prompt.Parent = self.Root
	prompt.Triggered:Connect(function()
		if self.Downed then
			self:GetUp()
		end
	end)
	self.Prompt = prompt
end

function Soldier:GetUp()
	if not self.Downed or not self.Alive then
		return
	end
	self.Downed = false
	self.Model:SetAttribute("Downed", false)
	self.Humanoid.Sit = false
	self.Humanoid.Health = self.Humanoid.MaxHealth * 0.6
	self.Humanoid.WalkSpeed = self.Stats.WalkSpeed
	if self.Prompt then
		self.Prompt.Enabled = false
	end
	SoundKit.Play("Player/GetUp", { Position = self.Root.Position })
end

-- Damage to an ally (zombie swings, enemy rounds). Allies go down instead of dying.
function Soldier:Hurt(amount, fromPos)
	if not self.Alive or self.Downed or self.Side ~= "Ally" then
		return
	end
	local h = self.Humanoid
	h.Health = math.max(1, h.Health - amount)
	self.HurtAt = os.clock()
	if fromPos then
		self.HurtFrom = fromPos
	end
	if h.Health <= 1 then
		self.Downed = true
		self.DownedAt = os.clock()
		self.Model:SetAttribute("Downed", true)
		h.WalkSpeed = 0
		h:MoveTo(self.Root.Position)
		h.Sit = true
		if self.Prompt then
			self.Prompt.Enabled = true
		end
		SoundKit.Play("Player/Down", { Position = self.Root.Position })
		if self.OnDowned then
			task.spawn(self.OnDowned, self)
		end
	end
end

function Soldier.FromModel(model)
	return live[model]
end

-- Everyone alive on a side ("Ally" / "Enemy"), as soldier objects.
function Soldier.All(side)
	local list = {}
	for _, s in live do
		if s.Alive and (not side or s.Side == side) then
			table.insert(list, s)
		end
	end
	return list
end

function Soldier:Remove()
	self.Alive = false
	live[self.Model] = nil
	self.Model:Destroy()
end

function Soldier.Clear(side)
	for model, s in live do
		if not side or s.Side == side then
			s.Alive = false
			live[model] = nil
			model:Destroy()
		end
	end
	for key, f in folders do
		if (not side or key == side) and f.Parent then
			f:ClearAllChildren()
		end
	end
end

-- Targets ---------------------------------------------------------------------------------------

local function aimPoint(model)
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model.PrimaryPart
	return torso, head
end

-- Who this soldier could shoot at, nearest first: { Model, Part, Player }.
function Soldier:Foes()
	local foes = {}
	local from = self.Root.Position
	local range = self.Stats.Range
	local function add(model, player)
		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		if hum and root and hum.Health > 0 and not model:GetAttribute("Dead") then
			local d = (root.Position - from).Magnitude
			if d <= range then
				table.insert(foes, { Model = model, Root = root, Player = player, Dist = d })
			end
		end
	end
	if self.Side == "Enemy" then
		for _, p in Players:GetPlayers() do
			local c = p.Character
			if c and p:GetAttribute("InMatch") and not c:GetAttribute("Downed") and not c:GetAttribute("Inside") then
				add(c, p)
			end
		end
		for _, s in Soldier.All("Ally") do
			if not s.Downed then
				add(s.Model)
			end
		end
	else
		for _, enemy in CollectionService:GetTagged("Enemy") do
			if enemy:IsDescendantOf(workspace) and enemy ~= self.Model then
				add(enemy)
			end
		end
	end
	table.sort(foes, function(a, b)
		return a.Dist < b.Dist
	end)
	return foes
end

-- A clear line from the eyes to the foe's body (other bodies count as blocking, so allies don't
-- fire through their own side).
function Soldier:Sees(foe)
	local head = self.Model:FindFirstChild("Head")
	if not head then
		return false
	end
	local torso, fhead = aimPoint(foe.Model)
	local params = rayParams({ self.Model })
	for _, part in { torso, fhead } do
		if part then
			local to = part.Position - head.Position
			local hit = workspace:Raycast(head.Position, to, params)
			if not hit or hit.Instance:IsDescendantOf(foe.Model) then
				return true, part
			end
		end
	end
	return false
end

-- Firing ------------------------------------------------------------------------------------------

function Soldier:Shoot(foe, part)
	local stats = self.Stats
	local origin = if self.Muzzle and self.Muzzle.Parent then self.Muzzle.WorldPosition else self.Root.Position + Vector3.new(0, 1.5, 0)
	local aimAt = part.Position
	if self.Side == "Ally" and foe.Model:FindFirstChild("Head") and math.random() < (stats.HeadChance or 0) then
		aimAt = foe.Model.Head.Position
	end
	local toTarget = aimAt - origin
	local dist = toTarget.Magnitude
	-- Spread grows with range and while the soldier or the target moves.
	local spread = stats.Spread * (0.6 + dist / 80)
	if self.Humanoid.MoveDirection.Magnitude > 0.1 then
		spread *= 1.5
	end
	if foe.Root and foe.Root.AssemblyLinearVelocity.Magnitude > 8 then
		spread *= 1.3
	end
	local r = math.rad(spread)
	local dir = (CFrame.lookAt(origin, aimAt) * CFrame.Angles((math.random() - 0.5) * r, (math.random() - 0.5) * r, 0)).LookVector
	local params = rayParams({ self.Model })
	local hit = workspace:Raycast(origin, dir * (stats.Range + 10), params)
	local endPos = if hit then hit.Position else origin + dir * stats.Range
	Remotes.ShotFx:FireAllClients(self.Model, { endPos }, self.GunName)
	self.FiredAt = os.clock()
	if not hit then
		return
	end
	local who, model, player = ownerOf(hit.Instance)
	local falloff = math.clamp((hit.Distance - 40) / 120, 0, 0.5)
	if who == "Player" and self.Side == "Enemy" then
		PlayerHealth.Damage(player, stats.Damage * (1 - falloff), origin, "Bullet")
	elseif who == "Ally" and self.Side == "Enemy" then
		local s = live[model]
		if s then
			s:Hurt(stats.Damage * (1 - falloff), origin)
		end
	elseif who == "Enemy" and self.Side == "Ally" then
		local isHead = hit.Instance.Name == "Head"
		local damage = stats.Damage * (1 - falloff) * (if isHead then 2 else 1)
		MobReactions.Hit(model, { { Part = hit.Instance, Damage = damage, Pos = hit.Position, IsHead = isHead } }, {
			Player = nil,
			Gun = self.Gun,
			GunName = self.GunName,
			HitPos = hit.Position,
			Dir = dir,
			Distance = hit.Distance,
			Share = 1,
		})
	end
end

-- A burst at the current target, then a pause; a reload after Mag rounds.
function Soldier:Burst(foe, part)
	local stats = self.Stats
	local count = math.floor(between(stats.Burst) + 0.5)
	local gap = 60 / stats.RPM
	for _ = 1, count do
		if not self.Alive or self.Downed or self.Mag <= 0 then
			break
		end
		if not foe.Model.Parent or foe.Model:GetAttribute("Dead") then
			break
		end
		local hum = foe.Model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			break
		end
		self:Face(part.Position)
		self:Shoot(foe, part)
		self.Mag -= 1
		task.wait(gap)
	end
	if self.Mag <= 0 then
		self.Reloading = true
		if self.OnReload then
			task.spawn(self.OnReload, self)
		end
		task.wait(stats.Reload)
		self.Mag = stats.Mag
		self.Reloading = false
	end
	self.NextBurst = os.clock() + between(stats.BurstGap)
end

function Soldier:Face(pos)
	local root = self.Root
	local to = pos - root.Position
	local f = flat(to)
	if f.Magnitude > 0.1 then
		self.Align.CFrame = CFrame.lookAt(Vector3.zero, f.Unit)
	end
	local pitch = math.atan2(to.Y - 1.5, math.max(f.Magnitude, 0.1))
	self.Model:SetAttribute("AimPitch", math.clamp(pitch, -1.1, 1.1))
end

-- Moving --------------------------------------------------------------------------------------------

function Soldier:MoveTo(goal)
	local root = self.Root
	local here = root.Position
	if flat(goal - here).Magnitude < 2 then
		self.Humanoid:MoveTo(here)
		self.Waypoints = nil
		return false
	end
	-- Close and in the open: straight there. Else a path, refreshed now and then.
	local direct = flat(goal - here).Magnitude < 18
	if direct then
		local hit = workspace:Raycast(here, goal - here, rayParams({ self.Model }))
		direct = hit == nil or (hit.Position - goal).Magnitude < 3
	end
	if direct then
		self.Waypoints = nil
		self.Humanoid:MoveTo(goal)
		return true
	end
	local now = os.clock()
	if not self.Waypoints or not self.PathGoal or (self.PathGoal - goal).Magnitude > 6 or now - self.PathAt > 3 then
		self.PathGoal, self.PathAt = goal, now
		local ok = pcall(self.Path.ComputeAsync, self.Path, here, goal)
		if ok and self.Path.Status == Enum.PathStatus.Success then
			self.Waypoints, self.WaypointIndex = self.Path:GetWaypoints(), 2
		else
			self.Waypoints = nil
			self.Humanoid:MoveTo(goal)
			return true
		end
	end
	local wps = self.Waypoints
	while wps[self.WaypointIndex + 1] and flat(wps[self.WaypointIndex].Position - here).Magnitude < 3 do
		self.WaypointIndex += 1
	end
	local wp = wps[self.WaypointIndex]
	self.Humanoid:MoveTo(if wp then wp.Position else goal)
	return true
end

-- Where this soldier wants to stand right now.
function Soldier:Goal(foe)
	local stats = self.Stats
	if self.Side == "Ally" then
		local anchor, facing = nil, nil
		if self.Follow then
			anchor, facing = self.Follow(self)
		end
		anchor = anchor or self.Post
		facing = facing or Vector3.new(1, 0, 0)
		local slots = CFG.Formation
		local offset = slots[(self.Slot - 1) % #slots + 1]
		local right = Vector3.yAxis:Cross(-facing).Unit
		local goal = anchor + right * offset.X - facing * offset.Z
		-- Pushing toward a foe out of range.
		if foe and foe.Dist > stats.Range * 0.7 then
			goal = goal:Lerp(foe.Root.Position, 0.25)
		end
		return goal
	end
	-- Enemies hold their post (or push to Advance), side-stepping while they fight.
	local post = self.Post
	if self.Advance then
		post = self.Advance
	end
	if foe then
		local now = os.clock()
		if now >= self.StrafeAt then
			self.StrafeAt = now + between(stats.StrafeTime)
			local side = Vector3.yAxis:Cross(flat(foe.Root.Position - self.Root.Position).Unit)
			self.Strafe = side * (math.random() * 2 - 1) * stats.Strafe
		end
		local goal = post + self.Strafe
		-- Rushers close in when the foe is far.
		if stats.Rush and foe.Dist > stats.Rush then
			goal = self.Root.Position:Lerp(foe.Root.Position, 0.3)
		end
		return goal
	end
	return post
end

-- The brain -------------------------------------------------------------------------------------------

function Soldier:Run()
	local stats = self.Stats
	task.wait(math.random() * TICK)
	while self.Alive and self.Model.Parent and self.Humanoid.Health > 0 do
		if self.Downed then
			if os.clock() - (self.DownedAt or 0) >= stats.DownTime then
				self:GetUp()
			end
		else
			-- Pick a target: keep the current one while it's seen, else the nearest seen foe.
			local foe, part = nil, nil
			local now = os.clock()
			if now >= (self.LookAt or 0) then
				self.LookAt = now + 0.35
				local best, bestPart = nil, nil
				for i, f in self:Foes() do
					if i > 6 then
						break
					end
					local seen, p = self:Sees(f)
					if seen then
						best, bestPart = f, p
						break
					end
				end
				self.Foe, self.FoePart = best, bestPart
				if best and not self.Engaged then
					self.Engaged = true
					self.SeenAt = now
					if self.OnContact then
						task.spawn(self.OnContact, self, best)
					end
				elseif not best then
					self.Engaged = false
				end
			end
			foe, part = self.Foe, self.FoePart
			if foe and (not foe.Model.Parent or foe.Model:GetAttribute("Dead")) then
				foe, part, self.Foe = nil, nil, nil
			end
			local goal = self:Goal(foe)
			local moving = self:MoveTo(goal)
			if foe and part then
				self:Face(part.Position)
				local react = if self.SeenAt then now - self.SeenAt else 1
				if not self.Firing and not self.Reloading and now >= (self.NextBurst or 0) and react >= between(stats.React) then
					self.Firing = true
					task.spawn(function()
						self:Burst(foe, part)
						self.Firing = false
					end)
				end
			elseif moving then
				local to = flat(self.Humanoid.WalkToPoint - self.Root.Position)
				if to.Magnitude > 0.5 then
					self.Align.CFrame = CFrame.lookAt(Vector3.zero, to.Unit)
				end
				self.Model:SetAttribute("AimPitch", -0.15)
			end
		end
		task.wait(TICK)
	end
end

return Soldier
