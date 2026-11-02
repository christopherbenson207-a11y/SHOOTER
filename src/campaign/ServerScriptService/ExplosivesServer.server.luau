-- Explosive drums: a model tagged "Explosive" (one fuel drum, placed by the map's zone scripts)
-- goes off once it has soaked GameConfig.Explosives.Health of gunfire. The blast hurts every
-- enemy and squad soldier within Radius (less toward the edge; the shooter gets the kills),
-- hurts players caught in it, sets off other drums in reach a beat later and throws the drum's
-- own pieces, which lie a while and fade. Fire, smoke and the flash live on a short-lived anchor:
-- nothing is left burning.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local MobReactions = require(ServerStorage.Modules.MobReactions)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Soldier = require(ServerStorage.Modules.Soldier)

local CFG = GameConfig.Explosives
local WorldShot = ServerStorage.Events.WorldShot

-- MobReactions reads a gun's Feel to decide how hard a hit throws a mob; the blast is a gun here.
local BLAST = { Feel = CFG.Feel }
local FADE = TweenInfo.new(1.5)

local soaked = {} -- [drum] = gunfire taken so far
local spent = {} -- [drum] = true once it has gone off

local function drumOf(part)
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, "Explosive") then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Full damage at the centre, EdgeShare of it at the rim, nothing past it.
local function share(distance)
	if distance > CFG.Radius then
		return 0
	end
	return 1 - (1 - CFG.EdgeShare) * distance / CFG.Radius
end

local function away(from, to)
	local d = to - from
	return if d.Magnitude > 0.1 then d.Unit else Vector3.zAxis
end

-- A fireball, a column of smoke, a spray of sparks and a flash that dies in half a second.
local function burst(center)
	local anchor = Instance.new("Part")
	anchor.Name = "Blast"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(center)

	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 170)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 132, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 30, 18)),
	})
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 13) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.45, 0.85)
	fire.Speed = NumberRange.new(10, 26)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Drag = 4
	fire.Acceleration = Vector3.new(0, 14, 0)
	fire.Rate = 0
	fire.Parent = anchor

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(46, 44, 44), Color3.fromRGB(88, 86, 84))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 18) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(2.2, 4)
	smoke.Speed = NumberRange.new(3, 9)
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.Acceleration = Vector3.new(0, 6, 0)
	smoke.Drag = 1.5
	smoke.Rate = 0
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = anchor

	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 196, 110))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.18)
	sparks.Lifetime = NumberRange.new(0.5, 1.2)
	sparks.Speed = NumberRange.new(30, 60)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Rate = 0
	sparks.Parent = anchor

	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 160, 70)
	flash.Brightness = 9
	flash.Range = 40
	flash.Parent = anchor

	anchor.Parent = workspace
	fire:Emit(36)
	smoke:Emit(22)
	sparks:Emit(40)
	TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(anchor, 5)
end

-- The drum's own pieces fly up and out, lie a while, then fade.
local function scatter(drum, center)
	local rng = Random.new()
	for _, p in drum:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = p.Size.Magnitude > 1
			p.CanQuery = false
			p.CollisionGroup = "Debris"
			p.Color = p.Color:Lerp(Color3.fromRGB(28, 24, 22), 0.6)
			local out = away(center, p.Position + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)))
			p.AssemblyLinearVelocity = out * rng:NextNumber(14, 30) + Vector3.new(0, rng:NextNumber(30, 55), 0)
			p.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
		end
	end
	for _, d in drum:GetDescendants() do
		if d:IsA("Light") then
			d.Enabled = false
		end
	end
	task.delay(CFG.DebrisTime, function()
		for _, p in drum:GetDescendants() do
			if p:IsA("BasePart") then
				TweenService:Create(p, FADE, { Transparency = 1 }):Play()
			end
		end
		Debris:AddItem(drum, FADE.Time + 0.1)
	end)
end

local explode

-- Everyone in reach: enemies through MobReactions (as if the shooter's gun did it), squad
-- soldiers through Soldier:Hurt, players through PlayerHealth; then the drums in reach.
local function blast(center, player)
	for _, model in CollectionService:GetTagged("Enemy") do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model.PrimaryPart
		if humanoid and humanoid.Health > 0 and root and model:IsDescendantOf(workspace) then
			local distance = (root.Position - center).Magnitude
			local k = share(distance)
			if k > 0 then
				local target = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or root
				MobReactions.Hit(model, { { Part = target, Damage = CFG.Damage * k, Pos = target.Position, IsHead = false } }, {
					Player = player,
					Gun = BLAST,
					GunName = "Explosion",
					HitPos = center,
					Dir = away(center, root.Position),
					Distance = distance,
					Share = 1,
				})
			end
		end
	end
	for _, ally in Soldier.All("Ally") do
		local k = share((ally.Root.Position - center).Magnitude)
		if k > 0 then
			ally:Hurt(CFG.Damage * k, center)
		end
	end
	for _, other in Players:GetPlayers() do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		local k = if root then share((root.Position - center).Magnitude) else 0
		if k > 0 then
			PlayerHealth.Damage(other, CFG.PlayerDamage * k, center, "Bullet")
		end
	end
	for _, drum in CollectionService:GetTagged("Explosive") do
		if not spent[drum] and drum:IsDescendantOf(workspace) then
			local distance = (drum:GetPivot().Position - center).Magnitude
			if distance <= CFG.ChainRadius then
				task.delay(CFG.ChainDelay + distance * 0.01, explode, drum, player)
			end
		end
	end
end

function explode(drum, player)
	if spent[drum] or not drum:IsDescendantOf(workspace) then
		return
	end
	spent[drum] = true
	soaked[drum] = nil
	local center = drum:GetBoundingBox().Position
	SoundKit.Play("World/Explosion", { Position = center })
	burst(center)
	scatter(drum, center)
	blast(center, player)
end

-- Every bullet that stops in a part (GunServer): count it against the drum it hit.
WorldShot.Event:Connect(function(player, part, _pos, damage)
	if typeof(part) ~= "Instance" or type(damage) ~= "number" then
		return
	end
	local drum = drumOf(part)
	if not drum or spent[drum] then
		return
	end
	soaked[drum] = (soaked[drum] or 0) + damage
	if soaked[drum] >= (drum:GetAttribute("Health") or CFG.Health) then
		explode(drum, player)
	end
end)

CollectionService:GetInstanceRemovedSignal("Explosive"):Connect(function(drum)
	soaked[drum] = nil
end)
