-- NPC soldiers for WAR (horror-shooter/war/BATTLE-PLAN.md, WAR-V2-CONTRACTS.md): HOUND's bots
-- (side "Ally") and the Lamplighters, the militia that follows the Beacon (side "Enemy"). Numbers:
-- GameConfig.War.Soldiers[kind] and GameConfig.War.Battle (Brain, Cover, Crouch). Modules.Battle
-- gives them their orders.
--   Light bodies (v2, 2 Nov): on the server a soldier is two invisible anchored parts that never
--   collide (HumanoidRootPart, the body's hitbox, and Head) and a Humanoid with no state machine,
--   there for its health and for the guns that look for one. Nothing is simulated: one Heartbeat
--   loop (the mover) walks every soldier along the ground and writes its CFrame 20 times a second.
--   Every client draws the bodies (StarterPlayerScripts.SoldierView: a low-poly R15 from
--   ReplicatedStorage.WarRigs named by the attribute Rig, walking, kneeling, aiming and falling).
--   Roles (ROLES): Leader, Rifleman, Support (long bursts, hangs back), Marksman (aimed single
--   shots, hangs back) and Assault (moves up and flanks sooner). The same brain fights for both
--   sides and against players of either side (player attribute Side, "Ally" if missing).
--   Enemies are tagged Enemy with MobType Lamplighter, so player guns hit them through GunServer and
--   MobReactions (blood and sounds only: LightBody skips the limb and stagger reactions). Allies are
--   tagged Ally. A fallen soldier lies where it dropped (drawn by every client) and is gone after
--   Battle.BodyTime; Battle sends a new one from the checkpoint or the reserve.
--   The brain (Run) thinks every Brain.Think seconds. Eyes: a view cone and rays from the head, a
--   memory of each foe (Known) and the side's shared sightings and heard gunfire. Orders: Attack
--   (advance on Goal, in a lane from LaneA to LaneB), Defend / Hold (stay within Radius of Goal,
--   facing the points in Facing) and Retire (walk to Goal, no fighting). Cover comes from
--   Modules.CoverMap: a soldier hides at a spot (crouched behind half cover), comes up or steps out
--   to fire a burst and goes back down; it leapfrogs forward while a teammate is in cover, flanks a
--   foe it has lost behind cover, falls back when badly hurt and keeps its head down when rounds
--   snap past (Suppression). Rushers (the Heavy) skip cover and walk in firing.
--   Shots: a server ray from the muzzle with spread by range, role, movement, suppression and
--   settling (and a second ray that sees the light bodies, which world rays pass through); players
--   take PlayerHealth.Damage (kind Bullet), Lamplighters MobReactions.Hit, HOUND Soldier.Hurt.
--   Every client draws the tracer and plays the gun from Remotes.ShotFx (shooter = the model).
-- Attributes on the model: Soldier (kind), Side ("Ally"/"Enemy"), Role, Rig, Gun, Scale, LightBody,
-- Callsign, AimPitch, Stance, Dead, and for SoldierView's poses Phase, Alert (a foe in sight lately)
-- and Reloading (the reload's length in seconds while it lasts).

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
-- Fog, snow and night shorten how far a soldier sees (Shared.Weather, workspace WeatherSight).
local weatherModule = ReplicatedStorage.Shared:FindFirstChild("Weather")
local Weather = weatherModule and require(weatherModule)
local PlayerHealth = require(script.Parent.PlayerHealth)
local MobReactions = require(script.Parent.MobReactions)
local CoverMap = require(script.Parent.CoverMap)
-- Mounted guns, if the place has them (Emplacements loads WarDamage and this module lazily).
local empModule = script.Parent:FindFirstChild("Emplacements")
local Emplacements = empModule and require(empModule)
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.War
local BATTLE = CFG.Battle
local BRAIN = BATTLE.Brain
local SUPPRESS = BRAIN.Suppress
local COVER = BATTLE.Cover
local THINK = BRAIN.Think

-- The body, in studs at Scale 1, from the feet: the hitbox standing and kneeling, the head cube on
-- top, and where the muzzle sits (forward and right of the middle). A kneeling soldier's head tops
-- out at 3.9, under most half cover.
local BODY = {
	Width = 1.8, Depth = 1.2, Stand = 3.9, Crouch = 2.8, Head = 1.1,
	Muzzle = { Stand = 4.3, Crouch = 3.2, Forward = 1.2, Right = 0.35 },
}
local WRITE = 1 / 20 -- seconds between CFrame writes (clients ease between them)
local GROUND = 0.15 -- seconds between ground and wall rays
local TURN = 8 -- radians a second
-- Speed multipliers: a dash between cover with a foe about; a Lamplighter who knows of no one walks.
local PACE = { Sprint = 1.25, Patrol = 0.6 }
local ELBOW = 2.4 -- studs: a soldier standing closer than this to a teammate steps apart
local AIM = BATTLE.Aim or 0.65 -- spread scale on GameConfig's numbers (owner: they shoot well)

-- Roles: multipliers on the soldier's stats and habits. Hop: time between moves up; Hold: prefers
-- cover with a line of fire over ground gained (hangs back); Shots: a fixed burst.
local ROLES = {
	Leader = {},
	Rifleman = {},
	Support = { Spread = 1.15, Burst = 2.4, BurstGap = 0.8, Mag = 3, Hop = 2, Hold = true, Gun = "M60" },
	Marksman = { Spread = 0.3, Shots = 1, BurstGap = 1.5, React = 0.8, HeadChance = 0.45, Hop = 2.5, Hold = true, Gun = "Sniper" },
	Assault = { Speed = 1.1, Hop = 0.6, Flank = 0.5, Spread = 1.1 },
	Heavy = {},
}
-- Each fireteam of six, in slot order.
local ROLE_ORDER = { "Leader", "Rifleman", "Support", "Assault", "Marksman", "Rifleman" }

local Soldier = {}
Soldier.__index = Soldier

local folders = {}
local filtersDirty = true
local function folder(side)
	local f = folders[side]
	if not f or not f.Parent then
		f = Instance.new("Folder")
		f.Name = if side == "Ally" then "Squad" else "Hostiles"
		f.Parent = workspace
		folders[side] = f
		filtersDirty = true
	end
	return f
end

local live = {} -- [model] = soldier

local function playerSide(player)
	return player:GetAttribute("Side") or "Ally"
end

-- Ground and walls under a walking soldier: the world that collides, not bodies, effects or markers.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true
groundParams.RespectCanCollide = true
-- The light bodies only (world rays, which respect CanCollide, pass through them).
local bodyParams = RaycastParams.new()
bodyParams.FilterType = Enum.RaycastFilterType.Include
bodyParams.RespectCanCollide = false

local function refreshFilters()
	if not filtersDirty then
		return
	end
	filtersDirty = false
	local map = workspace:FindFirstChild("Map")
	groundParams.FilterDescendantsInstances = { folder("Ally"), folder("Enemy"), workspace:FindFirstChild("Fx"), map and map:FindFirstChild("War") }
	bodyParams.FilterDescendantsInstances = { folder("Ally"), folder("Enemy") }
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function between(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

-- Rays that see the world and bodies: not effects, guns, the spot markers or anything a body
-- walks through (leaves, triggers).
local function rayParams(ignore)
	local list = { workspace:FindFirstChild("Fx"), workspace:FindFirstChild("Relics") }
	local map = workspace:FindFirstChild("Map")
	table.insert(list, map and map:FindFirstChild("War"))
	for _, i in ignore do
		table.insert(list, i)
	end
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = list
	p.IgnoreWater = true
	p.RespectCanCollide = true
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

local function yawOf(dir)
	return math.atan2(-dir.X, -dir.Z)
end

local function hitbox(name, size, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.Transparency = 1
	p.CastShadow = false
	p.Massless = true
	p.Locked = true
	return p
end

-- Where the ground is under pos (a spawn point is about 3 studs up).
local function groundBelow(pos)
	refreshFilters()
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), groundParams)
	return if hit then hit.Position else pos - Vector3.new(0, 3, 0)
end

-- The light body: the hitbox with its feet on the ground, the head on top (welded, so the two move
-- as one), a Humanoid for its health. The rig, gun and scale are attributes for SoldierView.
local function build(kind, cf, opts, feet, yaw)
	local stats = CFG.Soldiers[kind]
	local rigName = opts.Rig or stats.Rig
	if type(rigName) == "table" then
		rigName = rigName[math.random(#rigName)]
	end
	local scale = stats.Scale or 1
	local height = BODY.Stand * scale
	local model = Instance.new("Model")
	model.Name = opts.Callsign or kind
	local rootCF = CFrame.new(feet + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, yaw, 0)
	local root = hitbox("HumanoidRootPart", Vector3.new(BODY.Width, BODY.Stand, BODY.Depth) * scale, rootCF)
	root.Parent = model
	local head = hitbox("Head", Vector3.one * BODY.Head * scale, rootCF)
	head.Anchored = false
	head:SetAttribute("Limb", "Head")
	local neck = Instance.new("Weld")
	neck.Name = "Neck"
	neck.Part0, neck.Part1 = root, head
	neck.C0 = CFrame.new(0, (height + BODY.Head * scale) / 2, 0)
	neck.Parent = head
	head.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.EvaluateStateMachine = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = stats.Health
	humanoid.Health = stats.Health
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model:SetAttribute("Soldier", kind)
	model:SetAttribute("LightBody", true)
	model:SetAttribute("Rig", rigName)
	model:SetAttribute("Scale", scale)
	model:SetAttribute("AimPitch", 0)
	return model, humanoid, root, head, neck
end

-- The mover --------------------------------------------------------------------------------------------
-- One loop walks every soldier toward its WalkPoint at its speed (half that kneeling), keeps its feet
-- on the ground, stops it at walls (the brain then chooses again), turns it toward WantYaw and writes
-- its CFrame 20 times a second. Battle's PivotTo is picked up: the next step starts from there.

local function stepBody(s, now, dt)
	local root = s.Root
	if s.Wrote and (root.Position - s.Wrote).Magnitude > 0.5 then
		s.Feet = root.Position - Vector3.new(0, s.Height / 2, 0)
		s.GroundY = s.Feet.Y
		local look = root.CFrame.LookVector
		s.Yaw = yawOf(look)
		s.WantYaw = s.Yaw
		s.Dirty = true
	end
	local feet = s.Feet
	local walk = s.WalkPoint
	local dx, dz, dist = 0, 0, 0
	if walk then
		dx, dz = walk.X - feet.X, walk.Z - feet.Z
		dist = math.sqrt(dx * dx + dz * dz)
	end
	if now >= s.NextGround then
		s.NextGround = now + GROUND
		local hit = workspace:Raycast(feet + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), groundParams)
		if hit then
			s.GroundY = hit.Position.Y
		end
		s.Blocked = false
		if dist > 0.5 then
			local probe = workspace:Raycast(feet + Vector3.new(0, 1.6, 0), Vector3.new(dx, 0, dz) / dist * 1.1, groundParams)
			s.Blocked = probe ~= nil and probe.Normal.Y < 0.5 and probe.Distance < dist - 0.3
		end
	end
	local moved = false
	if dist > 0.25 and not s.Blocked and s.Alive then
		local speed = s.Speed * (s.Pace or 1) * (if s.Stance == "Crouch" then 0.5 else 1)
		local step = math.min(dist, speed * dt)
		feet += Vector3.new(dx, 0, dz) / dist * step
		moved = true
	end
	s.Moving = moved
	if s.GroundY then
		local dy = s.GroundY - feet.Y
		if math.abs(dy) > 0.02 then
			feet = Vector3.new(feet.X, feet.Y + dy * math.min(1, dt * 14), feet.Z)
			moved = true
		end
	end
	s.Feet = feet
	local diff = (s.WantYaw - s.Yaw + math.pi) % (2 * math.pi) - math.pi
	if math.abs(diff) > 1e-3 then
		local turn = TURN * dt
		s.Yaw += math.clamp(diff, -turn, turn)
		moved = true
	end
	s.Pending = s.Pending or moved
	if s.Dirty or (s.Pending and now - s.WroteAt >= WRITE) then
		s.Dirty, s.Pending = false, false
		s.WroteAt = now
		local cf = CFrame.new(feet.X, feet.Y + s.Height / 2, feet.Z) * CFrame.Angles(0, s.Yaw, 0)
		root.CFrame = cf
		s.Wrote = cf.Position
	end
end

RunService.Heartbeat:Connect(function(dt)
	refreshFilters()
	local now = os.clock()
	for model, s in live do
		if s.Alive and s.Root.Parent then
			local ok, err = pcall(stepBody, s, now, dt)
			if not ok and not s.MoverWarned then
				s.MoverWarned = true
				warn("Soldier mover " .. model.Name .. ": " .. tostring(err))
			end
		end
	end
end)

-- The side's shared picture ---------------------------------------------------------------------------
-- What each side has seen lately: intel[side][model] = { Root, Player, Pos, At }. A soldier takes in
-- what its side saw within Brain.Share studs of it.

local intel = { Ally = {}, Enemy = {} }

-- A soldier of side saw a foe (its model, root, player if any) at pos.
function Soldier.Spot(side, model, root, player, pos)
	local book = intel[side]
	local rec = book[model]
	if not rec then
		rec = {}
		book[model] = rec
	end
	rec.Root, rec.Player, rec.Pos, rec.At = root, player, pos, os.clock()
end

-- Gunfire at pos from shooter (a model) of side: the other side's soldiers within Brain.Hear studs
-- learn roughly where it came from.
function Soldier.Noise(pos, side, shooter, radius)
	if not shooter then
		return
	end
	local now = os.clock()
	local hear = radius or BRAIN.Hear
	local hear2 = hear * hear
	local root = shooter:FindFirstChild("HumanoidRootPart")
	local player = Players:GetPlayerFromCharacter(shooter)
	for _, s in live do
		if s.Alive and s.Side ~= side then
			local d = s.Root.Position - pos
			if d:Dot(d) <= hear2 then
				local rec = s.Known[shooter]
				if not rec then
					local jitter = Vector3.new(math.random() * 8 - 4, 0, math.random() * 8 - 4)
					s.Known[shooter] = { Model = shooter, Root = root, Player = player, Pos = pos + jitter, SeenAt = now, FirstSeen = 0, Visible = false }
				elseif not rec.Visible then
					rec.SeenAt = math.max(rec.SeenAt, now - 1)
				end
			end
		end
	end
end

-- Spawning --------------------------------------------------------------------------------------------

local roleCount = { Ally = 0, Enemy = 0 }

-- A role for a new soldier: by its slot (a HOUND bot), else the next in its side's rota.
local function pickRole(side, stats, opts)
	if stats.Rush then
		return "Heavy"
	end
	local n = opts.Slot
	if not n then
		roleCount[side] += 1
		n = roleCount[side]
	end
	return ROLE_ORDER[(n - 1) % #ROLE_ORDER + 1]
end

-- Spawns one soldier. kind: a key of GameConfig.War.Soldiers ("Ally", "Lamplighter", "Heavy").
-- opts: Callsign, Rig, Gun, Role, Slot, Team (fireteam), Order (see the top; Defend at cf if none).
function Soldier.Spawn(kind, cf, opts)
	opts = opts or {}
	local stats = CFG.Soldiers[kind]
	local side = stats.Side
	local role = opts.Role or pickRole(side, stats, opts)
	local r = ROLES[role] or ROLES.Rifleman
	local look = flat(cf.LookVector)
	local yaw = if look.Magnitude > 0.1 then yawOf(look) else 0
	local feet = groundBelow(cf.Position)
	local model, humanoid, root, head, neck = build(kind, cf, opts, feet, yaw)
	local gunName = opts.Gun or (r.Gun and GameConfig.Guns[r.Gun] and r.Gun) or stats.Gun
	local scale = stats.Scale or 1
	local self = setmetatable({
		Kind = kind,
		Side = side,
		Stats = stats,
		Role = role,
		RoleStats = r,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Head = head,
		Neck = neck,
		Params = rayParams({ model }),
		Gun = GameConfig.Guns[gunName] or GameConfig.Guns.AK,
		GunName = gunName,
		Callsign = opts.Callsign,
		Slot = opts.Slot,
		Team = opts.Team or 1,
		Order = opts.Order or { Mode = "Defend", Goal = cf.Position, Radius = stats.Leash or 12 },
		Alive = true,
		MagSize = math.floor(stats.Mag * (r.Mag or 1)),
		Known = {}, -- [model] = { Model, Root, Player, Pos, SeenAt, FirstSeen, Visible, Part }
		Target = nil,
		Phase = "Open", -- Open, Moving, Hidden, Exposing, Exposed
		Cover = nil, -- the CoverMap spot it holds
		Entry = nil, -- that spot's covered direction in use
		Dest = nil,
		Stance = "Stand",
		Scale = scale,
		Suppression = 0,
		HurtAt = -math.huge,
		NextLook = 0,
		NextChoose = 0,
		NextHop = 0,
		NextPeek = 0,
		NextBurst = 0,
		NextFlank = 0,
		NextRefire = 0,
		ExposeAt = -math.huge,
		Settle = 0,
		React = between(stats.React) * (r.React or 1),
		-- The mover's state.
		Feet = feet,
		GroundY = feet.Y,
		Height = BODY.Stand * scale,
		Speed = stats.WalkSpeed * (r.Speed or 1),
		Yaw = yaw,
		WantYaw = yaw,
		WalkPoint = nil,
		Moving = false,
		Blocked = false,
		NextGround = 0,
		WroteAt = -math.huge,
		Wrote = root.Position,
	}, Soldier)
	self.Mag = self.MagSize
	model:SetAttribute("Side", side)
	model:SetAttribute("Role", role)
	model:SetAttribute("Gun", gunName)
	model:SetAttribute("Stance", "Stand")
	if opts.Callsign then
		model:SetAttribute("Callsign", opts.Callsign)
	end
	if side == "Enemy" then
		CollectionService:AddTag(model, "Enemy")
		model:SetAttribute("MobType", stats.MobType or "Lamplighter")
		model:SetAttribute("MatchMob", true)
	else
		CollectionService:AddTag(model, "Ally")
	end
	CollectionService:AddTag(model, "Soldier")
	model.Parent = folder(side)
	if side == "Enemy" then
		MobReactions.Spawned(model)
	end
	-- Every hit, whoever fired it: head down, and a look for who did it. A light body's Humanoid has
	-- no state machine, so death is read off the health.
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(h)
		if h < last and self.Alive then
			if h <= 0 then
				self:Fall()
			else
				self:Damaged()
			end
		end
		last = h
	end)
	humanoid.Died:Once(function()
		self:Fall()
	end)
	live[model] = self
	-- Soldiers can't open doors, so the door slabs Doors marks as pass-through are walls to them.
	self.Path = PathfindingService:CreatePath({
		AgentRadius = 1.6,
		AgentHeight = 5.5,
		AgentCanJump = false,
		WaypointSpacing = 4,
		Costs = { Door = math.huge },
	})
	task.spawn(self.Run, self)
	return self
end

function Soldier:SetOrder(order)
	self.Order = order
	self.NextChoose = 0
	self.NextHop = 0
	if order.Mode == "Retire" then
		self:Leave()
		self:SetStance("Stand")
		self.Phase = "Moving"
		self.Dest = order.Goal
		self.MoveStart = os.clock()
	end
end

-- Back to a clean slate where it stands (the squad regrouping at a checkpoint).
function Soldier:Reset()
	self:Leave()
	self:SetStance("Stand")
	table.clear(self.Known)
	self.Target = nil
	self.Phase = "Open"
	self.Dest = nil
	self.Waypoints = nil
	self.Suppression = 0
	self.FellBack = false
end

-- Crouch shrinks the hitbox to kneeling height (the head comes down with it) and every client's
-- SoldierView kneels the body; rushers never do.
function Soldier:SetStance(stance)
	if self.Stance == stance or (stance == "Crouch" and self.Stats.Rush) then
		return
	end
	self.Stance = stance
	self.Model:SetAttribute("Stance", stance)
	local scale = self.Scale
	local h = (if stance == "Crouch" then BODY.Crouch else BODY.Stand) * scale
	self.Height = h
	self.Root.Size = Vector3.new(BODY.Width, h / scale, BODY.Depth) * scale
	self.Neck.C0 = CFrame.new(0, (h + BODY.Head * scale) / 2, 0)
	self.Dirty = true
end

-- Walking: the mover takes it there (nil stands still).
function Soldier:WalkTo(pos)
	self.WalkPoint = pos
end

-- Turning toward dir (flat); the mover turns at TURN radians a second. snap: at once.
function Soldier:Turn(dir, snap)
	if dir.X * dir.X + dir.Z * dir.Z > 1e-4 then
		self.WantYaw = yawOf(dir)
		if snap then
			self.Yaw = self.WantYaw
			self.Dirty = true
		end
	end
end

function Soldier:Facing()
	return Vector3.new(-math.sin(self.Yaw), 0, -math.cos(self.Yaw))
end

-- The rifle's muzzle: in front and to the right of the chest (kneeling: lower).
function Soldier:MuzzlePos()
	local m = BODY.Muzzle
	local scale = self.Scale
	local up = (if self.Stance == "Crouch" then m.Crouch else m.Stand) * scale
	local look = self:Facing()
	local right = Vector3.new(-look.Z, 0, look.X)
	return self.Feet + Vector3.new(0, up, 0) + look * m.Forward * scale + right * m.Right * scale
end

-- Not fighting: nothing in sight and not hit lately (Battle hands a player the calmest bot's place).
function Soldier:Calm()
	return not (self.Target and self.Target.Visible) and os.clock() - self.HurtAt > 5
end

-- Damage and death --------------------------------------------------------------------------------------

-- Damage from a soldier's round, a zombie's swing, a shell. fromPos turns it toward whoever did it.
function Soldier:Hurt(amount, fromPos)
	if not self.Alive then
		return
	end
	if fromPos then
		self.HurtFrom = fromPos
	end
	local h = self.Humanoid
	h.Health = math.max(0, h.Health - amount)
end

function Soldier:Suppress(amount)
	self.Suppression = math.min(1, self.Suppression + amount)
end

-- A hit landed: head down, choose again, and with nothing in sight, take the foe nearest where the
-- shot came from (else the nearest) as the threat.
-- The foe standing nearest where a shot came from (within 25 studs of it), if any.
function Soldier:ShooterAt(from)
	local best, bestD = nil, 25
	for _, foe in self:Foes() do
		local d = (foe.Root.Position - from).Magnitude
		if d < bestD then
			best, bestD = foe, d
		end
	end
	return best
end

-- Shot or killed (4 Nov 2026): it calls out where the shot came from. Every teammate within
-- Brain.Callout studs (default 160) learns the shooter's place, a few studs off, and rethinks its
-- cover, so a shooter on a roof can't pick a squad off one at a time while nobody looks up.
function Soldier:CallOut(from)
	if not from then
		return
	end
	local foe = self:ShooterAt(from)
	if not foe then
		return
	end
	local now = os.clock()
	local here = self.Root.Position
	local reach = BRAIN.Callout or 160
	local r2 = reach * reach
	for _, s in live do
		if s ~= self and s.Alive and s.Side == self.Side then
			local d = s.Root.Position - here
			if d:Dot(d) <= r2 then
				local pos = foe.Root.Position + Vector3.new(math.random() * 4 - 2, 0, math.random() * 4 - 2)
				local rec = s.Known[foe.Model]
				if not rec then
					s.Known[foe.Model] = { Model = foe.Model, Root = foe.Root, Player = foe.Player, Pos = pos, SeenAt = now, FirstSeen = 0, Visible = false }
				elseif not rec.Visible then
					rec.Pos, rec.SeenAt = pos, now
				end
				s.HurtFrom = from
				s.NextChoose = 0
			end
		end
	end
	Soldier.Spot(self.Side, foe.Model, foe.Root, foe.Player, foe.Root.Position)
end

function Soldier:Damaged()
	local now = os.clock()
	self.HurtAt = now
	self:Suppress(SUPPRESS.Hit)
	self.NextChoose = 0
	if self.HurtFrom then
		self:CallOut(self.HurtFrom)
	end
	if self.Target and self.Target.Visible then
		return
	end
	local from = self.HurtFrom or self.Root.Position
	local best, bestD = nil, math.huge
	for _, foe in self:Foes() do
		local d = (foe.Root.Position - from).Magnitude
		if d < bestD then
			best, bestD = foe, d
		end
	end
	if best then
		local rec = self.Known[best.Model]
		if not rec then
			rec = { Model = best.Model, Root = best.Root, Player = best.Player, FirstSeen = 0, Visible = false }
			self.Known[best.Model] = rec
		end
		rec.Pos, rec.SeenAt = best.Root.Position, now
	end
end

-- Bodies: the dead lie BATTLE.BodyTime (shorter, and fewer at once, when the server is lagging);
-- the oldest go first. Each client also fades its own copies sooner if it is the one struggling.
local bodies = {} -- { { Model, At } } oldest first
local reaping = false
local function reap()
	reaping = true
	local rules = BATTLE.Bodies or {}
	while #bodies > 0 do
		task.wait(2)
		local lag = workspace:GetRealPhysicsFPS() < (rules.LagFps or 40)
		local life = if lag then rules.LagTime or 45 else BATTLE.BodyTime
		local cap = if lag then rules.LagCap or 15 else rules.Cap or 40
		local now = os.clock()
		for i = #bodies, 1, -1 do
			local b = bodies[i]
			if not b.Model.Parent then
				table.remove(bodies, i)
			end
		end
		while #bodies > 0 and (#bodies > cap or now - bodies[1].At > life) do
			local b = table.remove(bodies, 1)
			if b.Model.Parent then
				b.Model:Destroy()
			end
		end
	end
	reaping = false
end

-- Down for good: off the books, its cover freed, OnDied told. Rays stop seeing it; every client
-- drops the body where it stood, and the model lies as a body (above) until it's reaped.
function Soldier:Fall()
	if not self.Alive then
		return
	end
	if self.HurtFrom then
		local ok, err = pcall(self.CallOut, self, self.HurtFrom) -- the dying shout
		if not ok then
			warn("Soldier callout: " .. tostring(err))
		end
	end
	self.Alive = false
	live[self.Model] = nil
	self:Leave()
	self.WalkPoint = nil
	local model = self.Model
	if self.HurtFrom then
		model:SetAttribute("FallFrom", self.HurtFrom) -- SoldierView throws the body away from it
	end
	model:SetAttribute("Dead", true)
	self.Root.CanQuery = false
	self.Head.CanQuery = false
	if self.Side == "Ally" then
		SoundKit.Play("Player/Down", { Position = self.Root.Position })
	end
	table.insert(bodies, { Model = model, At = os.clock() })
	if not reaping then
		task.spawn(reap)
	end
	if self.OnDied then
		task.spawn(self.OnDied, self)
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
	self:Leave()
	self.Model:Destroy()
end

function Soldier.Clear(side)
	for model, s in live do
		if not side or s.Side == side then
			s.Alive = false
			live[model] = nil
			s:Leave()
			model:Destroy()
		end
	end
	for key, f in folders do
		if (not side or key == side) and f.Parent then
			f:ClearAllChildren()
		end
	end
	for key, book in intel do
		if not side or key ~= side then
			table.clear(book)
		end
	end
end

-- Eyes ----------------------------------------------------------------------------------------------------

local function aimPoint(model)
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model.PrimaryPart
	return torso, head
end

-- Who this soldier could shoot at, nearest first: { Model, Root, Player, Dist }. Players on the
-- other side, soldiers on the other side, and for HOUND the zombies and other mobs too.
function Soldier:Foes()
	local foes = {}
	local from = self.Root.Position
	local range = if Weather then math.min(self.Stats.Range, Weather.Sight()) else self.Stats.Range
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
	for _, p in Players:GetPlayers() do
		local c = p.Character
		if c and p:GetAttribute("InMatch") and playerSide(p) ~= self.Side and not c:GetAttribute("Downed") and not c:GetAttribute("Inside") then
			add(c, p)
		end
	end
	for _, s in live do
		if s.Alive and s.Side ~= self.Side then
			add(s.Model)
		end
	end
	if self.Side == "Ally" then
		for _, enemy in CollectionService:GetTagged("Enemy") do
			if not live[enemy] and enemy:IsA("Model") and enemy:IsDescendantOf(workspace) and not Players:GetPlayerFromCharacter(enemy) then
				add(enemy)
			end
		end
	end
	table.sort(foes, function(a, b)
		return a.Dist < b.Dist
	end)
	return foes
end

-- A clear line from the eyes to the foe's body or head (other bodies count as blocking, so nobody
-- fires through their own side). A soldier kneeling behind half cover shows the top of its head at
-- most, so only its body counts.
-- Smoke grenades (GearServer) leave clouds in workspace.GearSmoke; a line through one is blind. Gear is required on
-- first use so a place without the gear system still works.
local GearShared
local function smokeBlocks(from, to)
	local folder = workspace:FindFirstChild("GearSmoke")
	if not folder or #folder:GetChildren() == 0 then
		return false
	end
	if GearShared == nil then
		local module = ReplicatedStorage:FindFirstChild("Shared") and ReplicatedStorage.Shared:FindFirstChild("Gear")
		GearShared = if module then require(module) else false
	end
	return GearShared ~= false and GearShared.SmokeBlocks(from, to, GearShared.SmokeSpheres(folder))
end

function Soldier:Sees(foe)
	local head = self.Head
	if not head or not head.Parent then
		return false
	end
	local torso, fhead = aimPoint(foe.Model)
	if foe.Model:GetAttribute("Stance") == "Crouch" then
		fhead = nil
	end
	for _, part in { torso, fhead } do
		if part and part.Parent and not smokeBlocks(head.Position, part.Position) then
			local hit = workspace:Raycast(head.Position, part.Position - head.Position, self.Params)
			if not hit or hit.Instance:IsDescendantOf(foe.Model) then
				return true, part
			end
		end
	end
	return false
end

-- A line of fire from its eyes to near pos: the rounds would land there, not in its own cover.
function Soldier:FireLine(pos)
	local from = self.Head.Position
	local to = pos + Vector3.new(0, 1.6, 0)
	local hit = workspace:Raycast(from, to - from, self.Params)
	return not hit or (hit.Position - to).Magnitude < 6
end

-- Looks round: foes in the view cone (or close, or just seen) get a ray; what it can't see any
-- more stays remembered for Brain.Memory seconds; the side's sightings near it come in too.
function Soldier:Look(now)
	local head = self.Head
	if not head or not head.Parent then
		return
	end
	local facing = self:Facing()
	local rays = 0
	local seen = {}
	for _, foe in self:Foes() do
		if rays >= BRAIN.LookRays then
			break
		end
		local rec = self.Known[foe.Model]
		local to = flat(foe.Root.Position - head.Position)
		local inView = foe.Dist <= BRAIN.Near or (to.Magnitude > 0.1 and facing:Dot(to.Unit) >= BRAIN.ViewCos) or (rec ~= nil and now - rec.SeenAt < 3)
		if inView then
			rays += 1
			local visible, part = self:Sees(foe)
			if visible then
				if not rec then
					rec = { FirstSeen = now }
					self.Known[foe.Model] = rec
				elseif not rec.Visible then
					rec.FirstSeen = now
				end
				rec.Model, rec.Root, rec.Player, rec.Part = foe.Model, foe.Root, foe.Player, part
				rec.Pos, rec.SeenAt, rec.Visible = foe.Root.Position, now, true
				seen[foe.Model] = true
				Soldier.Spot(self.Side, foe.Model, foe.Root, foe.Player, foe.Root.Position)
			end
		end
	end
	for model, rec in self.Known do
		if not seen[model] then
			rec.Visible = false
		end
		local hum = model.Parent and model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or model:GetAttribute("Dead") or now - rec.SeenAt > BRAIN.Memory then
			self.Known[model] = nil
		end
	end
	local book = intel[self.Side]
	local share2 = BRAIN.Share * BRAIN.Share
	local here = self.Root.Position
	for model, info in book do
		local hum = model.Parent and model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or now - info.At > BRAIN.Memory then
			book[model] = nil
		else
			local d = info.Pos - here
			if d:Dot(d) <= share2 then
				local rec = self.Known[model]
				if not rec then
					self.Known[model] = { Model = model, Root = info.Root, Player = info.Player, Pos = info.Pos, SeenAt = info.At, FirstSeen = 0, Visible = false }
				elseif not rec.Visible and info.At > rec.SeenAt then
					rec.Pos, rec.SeenAt = info.Pos, info.At
				end
			end
		end
	end
end

-- The foe to fight: one in sight (the nearest, keeping the current one), else the freshest memory.
function Soldier:PickTarget(now)
	local here = self.Root.Position
	local best, bestScore = nil, -math.huge
	for _, rec in self.Known do
		local score = -flatDist(rec.Pos, here) - (now - rec.SeenAt) * 6
		if rec.Visible then
			score += 1000
		end
		if rec == self.Target then
			score += 20
		end
		if score > bestScore then
			best, bestScore = rec, score
		end
	end
	self.Target = best
	if best and best.Visible then
		if not self.Engaged and self.OnContact then
			task.spawn(self.OnContact, self, best)
		end
		self.Engaged, self.EngagedAt = true, now
	elseif self.Engaged and now - (self.EngagedAt or 0) > 10 then
		self.Engaged = false
	end
end

-- What to hide from, at most three, those in sight first then the nearest: the foes it knows of,
-- else the order's Facing points (where the enemy is expected).
function Soldier:Threats()
	local list = {}
	local here = self.Root.Position
	for _, rec in self.Known do
		table.insert(list, rec)
	end
	if #list == 0 and self.Order.Facing then
		for _, p in self.Order.Facing do
			table.insert(list, { Pos = p, Pseudo = true, SeenAt = -math.huge, Visible = false })
		end
	end
	table.sort(list, function(a, b)
		if a.Visible ~= b.Visible then
			return a.Visible
		end
		return flatDist(a.Pos, here) < flatDist(b.Pos, here)
	end)
	while #list > 3 do
		table.remove(list)
	end
	return list
end

-- Cover ---------------------------------------------------------------------------------------------------

-- How far p strays from the lane a..b (flat).
local function laneGap(a, b, p)
	local ab = flat(b - a)
	local ap = flat(p - a)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

-- True if someone at pos can't see a crouched soldier at spot (a ray from there hits the cover).
function Soldier:CoverHolds(spot, pos)
	local eye = pos + Vector3.new(0, 1.5, 0)
	local at = spot.Pos + Vector3.new(0, COVER.Hide, 0)
	local hit = workspace:Raycast(eye, at - eye, self.Params)
	return hit ~= nil and (hit.Position - at).Magnitude < COVER.Probe + 1.5
end

-- Firing from spot at pos: standing over half cover, or from the peek beside full cover.
function Soldier:SpotFires(spot, entry, pos)
	if not entry or not entry.Fire then
		return false
	end
	local from = (if entry.Full then entry.Peek else spot.Pos) + Vector3.new(0, COVER.High, 0)
	local to = pos + Vector3.new(0, 1.5, 0)
	local hit = workspace:Raycast(from, to - from, self.Params)
	return not hit or (hit.Position - to).Magnitude < 4
end

-- The best cover for why: "Engage" (fight from near here), "Advance" (forward toward the goal),
-- "Retreat" (back from the main threat), "Flank" (a new angle on it) or "Hold" (inside the order's
-- area). Scores every free spot in reach (protection from each threat, a line of fire, travel,
-- crowding, the lane, the order's area), then checks the best few with rays from the main threat.
-- Returns the spot and its covered direction toward the main threat, or nil.
function Soldier:ChooseCover(why, threats)
	local here = self.Root.Position
	local order = self.Order
	local goal = order.Goal or here
	local from, reach = here, COVER.Search
	if why == "Advance" then
		reach = COVER.Search + 8
	elseif why == "Hold" then
		from, reach = goal, (order.Radius or 16) + 4
	end
	local main = threats[1]
	local now = os.clock()
	local mates = {}
	for _, s in live do
		if s ~= self and s.Side == self.Side and s.Alive then
			table.insert(mates, if s.Cover then s.Cover.Pos else s.Root.Position)
		end
	end
	local toGoal = flatDist(here, goal)
	local scored = {}
	for _, spot in CoverMap.Near(from, reach) do
		if (spot.Owner and spot.Owner ~= self) or spot.BadUntil > now then
			continue
		end
		local p = spot.Pos
		local travel = flatDist(here, p)
		local score = -travel * 0.35
		local entry = nil
		for i, t in threats do
			local w = if i == 1 then 1 else 0.6
			local facing = CoverMap.Facing(spot, t.Pos)
			if facing then
				score += 10 * w
				if i == 1 then
					entry = facing
				end
			else
				score -= 12 * w
			end
			if not t.Pseudo and flatDist(p, t.Pos) < 10 then
				score -= 20 * w
			end
		end
		if entry and entry.Fire then
			score += 4
		end
		for _, m in mates do
			if flatDist(p, m) < 4.5 then
				score -= 8
			end
		end
		if why == "Advance" then
			local gain = toGoal - flatDist(p, goal)
			if gain < 4 or travel > reach then
				continue
			end
			score += math.min(gain, 24) * (if self.RoleStats.Hold then 0.45 else 0.9)
			if self.RoleStats.Hold and entry and entry.Fire then
				score += 6
			end
			if order.LaneA then
				score -= math.max(0, laneGap(order.LaneA, order.LaneB, p) - 8) * 0.3
			end
		elseif why == "Engage" then
			if order.Mode == "Attack" then
				score -= math.max(0, flatDist(p, goal) - toGoal) * 0.4
			end
		elseif why == "Retreat" then
			if main then
				score += (flatDist(p, main.Pos) - flatDist(here, main.Pos)) * 0.7
			end
		elseif why == "Flank" then
			if not main then
				continue
			end
			local a, b = flat(here - main.Pos), flat(p - main.Pos)
			if a.Magnitude < 1 or b.Magnitude < 1 or a.Unit:Dot(b.Unit) > 0.77 then
				continue
			end
			score += 10
		end
		if order.Mode ~= "Attack" and order.Radius then
			local d = flatDist(p, goal)
			if d > order.Radius then
				score -= (d - order.Radius) * 2
			end
		end
		table.insert(scored, { Spot = spot, Score = score, Entry = entry })
	end
	table.sort(scored, function(a, b)
		return a.Score > b.Score
	end)
	for i = 1, math.min(4, #scored) do
		local c = scored[i]
		local ok = not main or main.Pseudo or self:CoverHolds(c.Spot, main.Pos)
		if ok and why == "Flank" then
			ok = self:SpotFires(c.Spot, c.Entry, main.Pos)
		end
		if ok then
			return c.Spot, c.Entry
		end
	end
	return nil
end

function Soldier:Leave()
	if self.Cover then
		CoverMap.Release(self.Cover, self)
		self.Cover = nil
	end
	self.Entry = nil
	if self.Emp then
		local emp = self.Emp
		self.Emp = nil
		pcall(emp.Release, emp, self)
	end
end

-- Runs for the cover ChooseCover picks for why. False if there is none.
function Soldier:TakeCover(why, threats, now)
	local spot, entry = self:ChooseCover(why, threats)
	if not spot then
		return false
	end
	if spot == self.Cover and self.Phase ~= "Moving" then
		-- Already the best place: stay, facing the threat.
		self.Entry = entry or (threats[1] and CoverMap.Facing(spot, threats[1].Pos)) or self.Entry
		return true
	end
	if spot ~= self.Cover then
		self:Leave()
		CoverMap.Claim(spot, self)
		self.Cover = spot
	end
	self.Entry = entry or (threats[1] and CoverMap.Facing(spot, threats[1].Pos)) or spot.Dirs[1]
	self.Dest = spot.Pos
	self.Phase = "Moving"
	self.MoveStart = now
	self:SetStance("Stand")
	return true
end

-- Out in the open toward pos (onto surveyed ground near it when there is some).
function Soldier:GoOpen(pos, now)
	self:Leave()
	self:SetStance("Stand")
	self.Dest = CoverMap.Snap(pos, 10) or pos
	self.Phase = "Moving"
	self.MoveStart = now
end

-- A teammate in cover within 30 studs to watch it move.
function Soldier:Overwatched()
	local here = self.Root.Position
	for _, s in live do
		if s ~= self and s.Side == self.Side and s.Alive and s.Cover and s.Phase ~= "Moving" and flatDist(s.Root.Position, here) < 30 then
			return true
		end
	end
	return false
end

-- Deciding -----------------------------------------------------------------------------------------------

-- Rushers (the Heavy): walk at the target until within Rush studs, else on to the goal.
function Soldier:Rush(now)
	local t = self.Target
	local here = self.Root.Position
	local goal = self.Order.Goal or here
	self.Phase = "Open"
	if t then
		self.Dest = if flatDist(here, t.Pos) > self.Stats.Rush then here:Lerp(t.Pos, 0.3) else nil
	else
		self.Dest = if flatDist(here, goal) > 6 then goal else nil
	end
end

-- Where to be: what cover, or the open, or on to the goal. Runs twice a second at most, and at
-- once after a hit or a new order.
function Soldier:Decide(now)
	local order = self.Order
	if order.Mode == "Retire" then
		return
	end
	if self.Stats.Rush then
		self:Rush(now)
		return
	end
	if now < self.NextChoose then
		return
	end
	self.NextChoose = now + 0.5
	local threats = self:Threats()
	local main = threats[1]
	local real = main ~= nil and not main.Pseudo
	local here = self.Root.Position
	local goal = order.Goal or here
	local radius = order.Radius or 16
	local hp = self.Humanoid.Health / self.Humanoid.MaxHealth
	local holding = order.Mode ~= "Attack" or flatDist(here, goal) < radius

	if self.Phase == "Moving" then
		if real and main.Visible and now - self.MoveStart > 1 then
			if not self.Cover then
				-- Caught in the open: the nearest cover that faces it, if there is any.
				self:TakeCover("Engage", threats, now)
			elseif not CoverMap.Facing(self.Cover, main.Pos) then
				-- The threat came round the spot it is running to: choose again.
				self:TakeCover("Engage", threats, now)
			end
		end
		return
	end

	if self.Cover then
		if real and not CoverMap.Facing(self.Cover, main.Pos) then
			-- Flanked: cover that faces it.
			if self:TakeCover("Engage", threats, now) then
				return
			end
		end
		if real and hp < BRAIN.Retreat and not self.FellBack then
			self.FellBack = true
			if self:TakeCover("Retreat", threats, now) then
				return
			end
		end
		if holding then
			-- A new area to hold: move into it.
			if flatDist(self.Cover.Pos, goal) > radius + 4 then
				if not self:TakeCover("Hold", threats, now) then
					self:GoOpen(goal, now)
				end
				return
			end
		elseif now >= self.NextHop and self.Phase == "Hidden" and self.Suppression < 0.4 then
			local close = real and main.Visible and flatDist(main.Pos, here) < 25
			if not close or self:Overwatched() then
				self.NextHop = now + between(BRAIN.Hop) * (self.RoleStats.Hop or 1)
				if self:TakeCover("Advance", threats, now) then
					return
				end
				if not real then
					self:GoOpen(goal, now)
					return
				end
			end
		end
		local flankAfter = BRAIN.Flank * (self.RoleStats.Flank or 1)
		if real and not main.Visible and now - main.SeenAt > flankAfter and now >= self.NextFlank then
			self.NextFlank = now + flankAfter * 2
			if self:TakeCover("Flank", threats, now) then
				return
			end
		end
		if real and self.Entry and not self.Entry.Fire and now >= self.NextRefire then
			-- No line of fire from here: somewhere it can shoot from.
			self.NextRefire = now + 4
			if self:TakeCover("Engage", threats, now) then
				return
			end
		end
		if main then
			self.Entry = CoverMap.Facing(self.Cover, main.Pos) or self.Entry
		end
		return
	end

	-- In the open.
	if real then
		if self:TakeCover("Engage", threats, now) then
			return
		end
		if order.Mode == "Attack" and not holding then
			-- Nothing to hide behind here: keep pushing, firing on the move.
			local ahead = flat(goal - here)
			self:GoOpen(here + (if ahead.Magnitude > 1 then ahead.Unit else Vector3.zero) * 12, now)
			return
		end
		-- Nothing to hide behind: down on one knee to fight.
		self.Phase, self.Dest = "Open", nil
		self:SetStance("Crouch")
	elseif holding then
		if self:TakeCover("Hold", threats, now) then
			return
		end
		if flatDist(here, goal) > radius then
			self:GoOpen(goal, now)
		else
			self.Phase, self.Dest = "Open", nil
			self:SetStance("Stand")
		end
	else
		if self:TakeCover("Advance", threats, now) then
			return
		end
		self:GoOpen(goal, now)
	end
end

-- Firing ------------------------------------------------------------------------------------------------

function Soldier:Expose(now)
	self.Phase = "Exposing"
	self.ExposeAt = now
	self.Settle = between(BRAIN.Settle)
	self:SetStance("Stand")
	if self.Entry and self.Entry.Full then
		self.Settle += 0.35 -- the step out
	end
end

function Soldier:Hide(now)
	self.Phase = "Hidden"
	if not (self.Entry and self.Entry.Full) then
		self:SetStance("Crouch")
	end
	-- With no foe seen lately the next look round waits twice as long.
	local fresh = self.Target ~= nil and now - self.Target.SeenAt < BRAIN.PeekMemory
	self.NextPeek = now + between(BRAIN.PeekGap) * (1 + self.Suppression * 2) * (if fresh then 1 else 2)
end

function Soldier:Arrive(now)
	if self.Cover then
		self.Phase = "Hidden"
		if not (self.Entry and self.Entry.Full) then
			self:SetStance("Crouch")
		end
		self.NextHop = now + between(BRAIN.Hop) * (self.RoleStats.Hop or 1)
		self.NextPeek = now + between(BRAIN.FirstPeek)
	else
		self.Phase, self.Dest = "Open", nil
	end
end

function Soldier:Reload()
	if self.Reloading then
		return
	end
	self.Reloading = true
	self.Model:SetAttribute("Reloading", self.Stats.Reload)
	if self.OnReload then
		task.spawn(self.OnReload, self)
	end
	task.delay(self.Stats.Reload, function()
		self.Mag = self.MagSize
		self.Reloading = false
		self.Model:SetAttribute("Reloading", nil)
	end)
end

function Soldier:Face(pos, snap)
	local to = pos - self.Root.Position
	local f = flat(to)
	if f.Magnitude > 0.1 then
		self:Turn(f, snap)
	end
	local eye = self.Feet.Y + (if self.Stance == "Crouch" then BODY.Muzzle.Crouch else BODY.Muzzle.Stand) * self.Scale
	local pitch = math.atan2(pos.Y - eye, math.max(f.Magnitude, 0.1))
	-- Rounded, so a steady aim doesn't send an attribute change every think.
	self.Model:SetAttribute("AimPitch", math.floor(math.clamp(pitch, -1.1, 1.1) * 50 + 0.5) / 50)
end

-- Rounds passing close: every foe soldier whose head is within Suppress.Radius of the shot's path
-- (bar the one it hit) keeps its head down.
function Soldier:Snap(from, to, hitModel)
	local seg = to - from
	local len2 = seg:Dot(seg)
	if len2 < 1 then
		return
	end
	local r2 = SUPPRESS.Radius * SUPPRESS.Radius
	for model, s in live do
		if s.Side ~= self.Side and s.Alive and model ~= hitModel and s.Head then
			local h = s.Head.Position
			local k = math.clamp((h - from):Dot(seg) / len2, 0, 1)
			local d = from + seg * k - h
			if d:Dot(d) <= r2 then
				s:Suppress(SUPPRESS.Miss)
				s.HurtFrom = from
			end
		end
	end
end

-- One round at aimAt (t: the target's record). Spread grows with range, while moving, at a moving
-- target, under fire, just after coming up, and when only suppressing a last-known spot.
function Soldier:Shoot(aimAt, t, suppressing)
	local stats = self.Stats
	local origin = self:MuzzlePos()
	local dist = (aimAt - origin).Magnitude
	local spread = stats.Spread * AIM * (self.RoleStats.Spread or 1) * (0.6 + dist / 80)
	if self.Moving then
		spread *= 1.5
	end
	local mover = live[t.Model]
	if (mover and mover.Moving) or (not mover and t.Root and t.Root.Parent and t.Root.AssemblyLinearVelocity.Magnitude > 8) then
		spread *= 1.3
	end
	spread *= 1 + self.Suppression * SUPPRESS.Aim
	if os.clock() - self.ExposeAt < 0.6 then
		spread *= 1.25
	end
	if suppressing then
		spread *= 1.6
	end
	local r = math.rad(spread)
	local dir = (CFrame.lookAt(origin, aimAt) * CFrame.Angles((math.random() - 0.5) * r, (math.random() - 0.5) * r, 0)).LookVector
	local range = stats.Range + 10
	local hit = workspace:Raycast(origin, dir * range, self.Params)
	local body = workspace:Raycast(origin, dir * (if hit then hit.Distance else range), bodyParams)
	if body and not body.Instance:IsDescendantOf(self.Model) then
		hit = body
	end
	local endPos = if hit then hit.Position else origin + dir * stats.Range
	Remotes.ShotFx:FireAllClients(self.Model, { endPos }, self.GunName)
	self.FiredAt = os.clock()
	local who, model, player = nil, nil, nil
	if hit then
		who, model, player = ownerOf(hit.Instance)
	end
	self:Snap(origin, endPos, model)
	if not hit or not who then
		return
	end
	local falloff = math.clamp((hit.Distance - 40) / 120, 0, 0.5)
	local isHead = hit.Instance.Name == "Head"
	if who == "Player" then
		if playerSide(player) ~= self.Side then
			PlayerHealth.Damage(player, stats.Damage * (1 - falloff) * (if isHead then 1.5 else 1), origin, "Bullet")
		end
		return
	end
	local s = live[model]
	if s then
		if s.Side == self.Side then
			return
		end
		local amount = (stats.BotDamage or stats.Damage) * (1 - falloff) * (if isHead then 2 else 1)
		if s.Side == "Ally" then
			s:Hurt(amount, origin)
			return
		end
		s.HurtFrom = origin
		MobReactions.Hit(model, { { Part = hit.Instance, Damage = amount, Pos = hit.Position, IsHead = isHead } }, {
			Player = nil,
			Gun = self.Gun,
			GunName = self.GunName,
			HitPos = hit.Position,
			Dir = dir,
			Distance = hit.Distance,
			Share = 1,
		})
	elseif who == "Enemy" and self.Side == "Ally" then
		-- A zombie or other mob.
		MobReactions.Hit(model, { { Part = hit.Instance, Damage = stats.Damage * (1 - falloff) * (if isHead then 2 else 1), Pos = hit.Position, IsHead = isHead } }, {
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

-- A burst at the target (part: what it sees of it), or at the spot it was last seen when
-- suppressing; a reload when the magazine runs dry.
function Soldier:Burst(t, part, suppressing)
	local stats = self.Stats
	local role = self.RoleStats
	local count = role.Shots or math.max(1, math.floor(between(stats.Burst) * (role.Burst or 1) + 0.5))
	local gap = 60 / stats.RPM
	Soldier.Noise(self.Root.Position, self.Side, self.Model)
	for _ = 1, count do
		if not self.Alive or self.Mag <= 0 or not t.Model.Parent then
			break
		end
		local hum = t.Model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or t.Model:GetAttribute("Dead") then
			break
		end
		local aim
		if suppressing then
			aim = t.Pos + Vector3.new(0, 1.6, 0)
		else
			if not part or not part.Parent then
				break
			end
			aim = part.Position
			if math.random() < (role.HeadChance or stats.HeadChance or 0) then
				local head = t.Model:FindFirstChild("Head")
				if head then
					aim = head.Position
				end
			end
		end
		self:Face(aim, true)
		self:Shoot(aim, t, suppressing)
		self.Mag -= 1
		task.wait(gap)
	end
	if self.Mag <= 0 then
		self:Reload()
	end
	self.NextBurst = os.clock() + between(stats.BurstGap) * (role.BurstGap or 1)
end

function Soldier:StartBurst(t, part, suppressing)
	self.Firing = true
	task.spawn(function()
		self:Burst(t, part, suppressing)
		self.Firing = false
		if self.Alive and self.Cover and self.Phase == "Exposed" then
			self:Hide(os.clock())
		end
	end)
end

-- From cover: come up (or step out) when the peek is due and the target was seen lately, settle,
-- then a burst at it, or at the cover it went behind, or back down if nothing shows. In the open:
-- a burst at whatever is in sight (on the move only when it is close). Reloads while down.
function Soldier:Fight(now)
	if self.Firing or self.Reloading or self.Order.Mode == "Retire" then
		return
	end
	local t = self.Target
	local phase = self.Phase
	if phase == "Hidden" then
		if self.Mag < self.MagSize * 0.4 and not (t and t.Visible) then
			self:Reload()
		elseif now >= self.NextPeek and self.Suppression < SUPPRESS.Pin and self.Entry and self.Entry.Fire then
			-- Up to fire at a foe seen lately, or now and then just to look round.
			self:Expose(now)
		end
		return
	end
	if (phase == "Exposing" or phase == "Exposed") and self.Suppression >= SUPPRESS.Pin then
		-- Rounds snapping past: back down.
		self:Hide(now)
		return
	end
	if phase == "Exposing" then
		if now - self.ExposeAt < self.Settle then
			return
		end
		self.Phase, phase = "Exposed", "Exposed"
	end
	if not t then
		if phase == "Exposed" then
			-- A look round: up for PeekLook seconds, then back down.
			if now - self.ExposeAt > self.Settle + BRAIN.PeekLook then
				self:Hide(now)
			end
		elseif phase == "Open" and self.Mag < self.MagSize * 0.4 then
			self:Reload()
		end
		return
	end
	if phase == "Moving" and not self.Stats.Rush and flatDist(t.Pos, self.Root.Position) > BRAIN.MoveFire then
		return
	end
	if now < self.NextBurst or not (t.Visible or phase == "Exposed") then
		return
	end
	local seen, part = false, nil
	if t.Model.Parent then
		seen, part = self:Sees(t)
	end
	if seen then
		if not t.Visible then
			t.FirstSeen = now
		end
		t.Root = t.Root or t.Model:FindFirstChild("HumanoidRootPart")
		t.Visible, t.Part, t.SeenAt = true, part, now
		if t.Root then
			t.Pos = t.Root.Position
		end
		if now - t.FirstSeen >= self.React then
			self:StartBurst(t, part, false)
		end
	elseif phase == "Exposed" then
		if now - t.SeenAt < BRAIN.SuppressFire and self:FireLine(t.Pos) then
			self:StartBurst(t, nil, true)
		elseif now - self.ExposeAt > self.Settle + BRAIN.PeekLook then
			self:Hide(now)
		end
	end
end

-- Moving ---------------------------------------------------------------------------------------------------

-- Toward goal: straight there when close and clear, else along a path refreshed now and then.
function Soldier:MoveTo(goal)
	local here = self.Root.Position
	local direct = flatDist(goal, here) < 18
	if direct then
		local hit = workspace:Raycast(here, goal - here, self.Params)
		direct = hit == nil or (hit.Position - goal).Magnitude < 3
	end
	if direct then
		self.Waypoints = nil
		self:WalkTo(goal)
		return true
	end
	local now = os.clock()
	if not self.Waypoints or not self.PathGoal or (self.PathGoal - goal).Magnitude > 3 or now - self.PathAt > 3 then
		self.PathGoal, self.PathAt = goal, now
		local ok = pcall(self.Path.ComputeAsync, self.Path, here, goal)
		if ok and self.Path.Status == Enum.PathStatus.Success then
			self.Waypoints, self.WaypointIndex = self.Path:GetWaypoints(), 2
		else
			self.Waypoints = nil
			self:WalkTo(goal)
			return true
		end
	end
	local wps = self.Waypoints
	while wps[self.WaypointIndex + 1] and flatDist(wps[self.WaypointIndex].Position, here) < 3 do
		self.WaypointIndex += 1
	end
	local wp = wps[self.WaypointIndex]
	self:WalkTo(if wp then wp.Position else goal)
	return true
end

-- Not getting anywhere for 2.5 seconds: that cover is bad for a while, choose again.
function Soldier:CheckStuck(now)
	local here = self.Root.Position
	if not self.StuckPos or (here - self.StuckPos).Magnitude > 1.5 then
		self.StuckPos, self.StuckAt = here, now
		return
	end
	if now - self.StuckAt > 2.5 then
		self.StuckPos, self.StuckAt = here, now
		if self.Cover then
			CoverMap.Bad(self.Cover, 20)
			self.Cover, self.Entry = nil, nil
		end
		self:SetStance("Stand")
		self.Phase, self.Dest, self.Waypoints = "Open", nil, nil
		self.NextChoose = 0
	end
end

-- Room to stand: a step away from the nearest teammate it stands almost on top of (two sent to the
-- same open ground end up in one spot), else nil.
function Soldier:Elbow(here)
	local near, nearD = nil, ELBOW
	for _, s in live do
		if s ~= self and s.Alive and s.Side == self.Side then
			local d = flatDist(s.Root.Position, here)
			if d < nearD then
				near, nearD = s, d
			end
		end
	end
	if not near then
		return nil
	end
	local away = flat(here - near.Root.Position)
	if away.Magnitude < 0.1 then
		local a = math.random() * 2 * math.pi
		away = Vector3.new(math.cos(a), 0, math.sin(a))
	end
	return here + away.Unit * math.max(2, ELBOW + 0.8 - nearD)
end

-- Legs and facing: to the spot the phase wants (cover, the peek beside it, the open destination),
-- facing the target while fighting or hiding, else the way it walks, else out over its cover.
function Soldier:Steer(now)
	local here = self.Root.Position
	local phase = self.Phase
	local dest = self.Dest
	if phase == "Open" and not dest then
		dest = self:Elbow(here)
	end
	if phase == "Hidden" then
		dest = self.Cover and self.Cover.Pos
	elseif phase == "Exposing" or phase == "Exposed" then
		dest = if self.Entry and self.Entry.Full and self.Entry.Peek then self.Entry.Peek elseif self.Cover then self.Cover.Pos else nil
	end
	local moving = false
	if dest and flatDist(here, dest) > 1.6 then
		moving = self:MoveTo(dest)
		self:CheckStuck(now)
	else
		self:WalkTo(nil)
		self.Waypoints = nil
		self.StuckPos = nil
		if phase == "Moving" then
			self:Arrive(now)
		end
	end
	local t = self.Target
	if t and (t.Visible or phase ~= "Moving") then
		self:Face(if t.Visible and t.Part and t.Part.Parent then t.Part.Position else t.Pos + Vector3.new(0, 1.5, 0))
	elseif moving then
		local to = flat((self.WalkPoint or here) - here)
		if to.Magnitude > 0.5 then
			self:Turn(to)
		end
		self.Model:SetAttribute("AimPitch", -0.16)
	elseif self.Entry then
		self:Turn(self.Entry.Dir)
		self.Model:SetAttribute("AimPitch", 0)
	end
end

-- Mounted guns ------------------------------------------------------------------------------------------

-- Gun roles that will man a mounted gun of their side.
local GUNNERS = { Support = true, Rifleman = true }
local GUN_REACH = 45 -- how far it looks for a free gun
local GUN_LEASH = 30 -- how far past its order's area a gun may be
local GUN_CLOSE = 22 -- a foe this near and off the gun's arc gets it off the gun

-- Whether the gun at seat is inside the ground its order holds (plus the leash).
local function gunInOrder(order, seat)
	return order.Mode ~= "Retire" and (order.Goal == nil or flatDist(order.Goal, seat) <= (order.Radius or 16) + GUN_LEASH)
end

-- A Support or Rifleman holding ground near a free gun of its side mans it: it walks to the seat,
-- stands behind the gun and works it at its target (the gun keeps its own rate, bursts and heat)
-- until its order moves it on or the gun is lost. True while it is on a gun (Decide and Fight rest).
function Soldier:Gunner(now)
	local emp = self.Emp
	if emp then
		local seat = emp.SeatGround.Position
		if not emp.Model.Parent or emp.Gunner ~= self or not gunInOrder(self.Order, seat) then
			self:Leave()
			self.Phase, self.Dest = "Open", nil
			self.NextChoose = 0
			self.NextGunLook = now + 8
			return false
		end
		local t = self.Target
		if flatDist(self.Root.Position, seat) > 1.5 then
			self:MoveTo(seat)
			local to = flat((self.WalkPoint or seat) - self.Root.Position)
			if to.Magnitude > 0.5 then
				self:Turn(to)
			end
			return true
		end
		self:WalkTo(nil)
		self:SetStance("Stand")
		if t and t.Pos and not emp:InArc(t.Pos) then
			-- Its target is off the gun's arc: it works one inside it, else gets off for one close by.
			local best, bestDist = nil, math.huge
			for _, rec in self.Known do
				if rec.Pos and (rec.Visible or now - rec.SeenAt < 3) and emp:InArc(rec.Pos) then
					local d = flatDist(rec.Pos, seat)
					if d < bestDist then
						best, bestDist = rec, d
					end
				end
			end
			if best then
				t = best
				self.Target = best
			elseif t.Visible and flatDist(t.Pos, seat) < GUN_CLOSE then
				self:Leave()
				self.Phase, self.Dest = "Open", nil
				self.NextChoose = 0
				self.NextGunLook = now + 8
				return false
			end
		end
		if t and t.Pos then
			-- Its own look over the gun (Fight, which keeps t up to date otherwise, rests here).
			local seen, part = false, nil
			if t.Model.Parent then
				seen, part = self:Sees(t)
			end
			if seen then
				t.Root = t.Root or t.Model:FindFirstChild("HumanoidRootPart")
				t.Visible, t.Part, t.SeenAt = true, part, now
				if t.Root then
					t.Pos = t.Root.Position
				end
			end
			local aim = if seen and part then part.Position else t.Pos + Vector3.new(0, 1, 0)
			self:Face(aim)
			if emp:AimAt(aim) and (seen or now - (t.SeenAt or 0) < 3) then
				emp:Fire(aim)
			end
		else
			self:Turn(emp.Base.LookVector)
			self.Model:SetAttribute("AimPitch", 0)
		end
		return true
	end
	if not Emplacements or not GUNNERS[self.Role] or self.Stats.Rush or now < (self.NextGunLook or 0) then
		return false
	end
	self.NextGunLook = now + 3
	local near = Emplacements.Nearest(self.Root.Position, self.Side, GUN_REACH)
	if near and gunInOrder(self.Order, near.SeatGround.Position) and near:Claim(self) then
		if self.Cover then
			CoverMap.Release(self.Cover, self)
			self.Cover, self.Entry = nil, nil
		end
		self.Emp = near
		self.Phase, self.Dest = "Gun", nil
		return true
	end
	return false
end

-- The brain ------------------------------------------------------------------------------------------------

function Soldier:Think(now, dt)
	self.Suppression = math.max(0, self.Suppression - SUPPRESS.Fade * dt)
	local h = self.Humanoid
	if self.Side == "Ally" and now - self.HurtAt > BRAIN.HealAfter and h.Health < h.MaxHealth then
		h.Health = math.min(h.MaxHealth, h.Health + BRAIN.Heal * dt)
		if h.Health > h.MaxHealth * 0.7 then
			self.FellBack = false
		end
	end
	if now >= self.NextLook then
		self.NextLook = now + BRAIN.Look
		self:Look(now)
	end
	self:PickTarget(now)
	if self:Gunner(now) then
		return
	end
	self:Decide(now)
	self:Steer(now)
	self:Fight(now)
end

-- What every client's SoldierView poses from, sent only when it changes: Phase (down in cover, up to
-- fire, on the move) and Alert (a foe in sight lately). And its pace: a sprint between cover with a
-- foe about, a walk for a Lamplighter who knows of no one.
function Soldier:Publish(now)
	local t = self.Target
	local alert = t ~= nil and (t.Visible or now - t.SeenAt < 4)
	if self.Phase == "Moving" and alert and self.Order.Mode ~= "Retire" then
		self.Pace = PACE.Sprint
	elseif self.Side == "Enemy" and next(self.Known) == nil and self.Order.Mode ~= "Attack" then
		self.Pace = PACE.Patrol
	else
		self.Pace = 1
	end
	local model = self.Model
	if self.Phase ~= self.ShownPhase then
		self.ShownPhase = self.Phase
		model:SetAttribute("Phase", self.Phase)
	end
	if alert ~= self.ShownAlert then
		self.ShownAlert = alert
		model:SetAttribute("Alert", alert or nil)
	end
end

function Soldier:Run()
	task.wait(math.random() * THINK)
	local last = os.clock()
	local warned = false
	while self.Alive and self.Model.Parent and self.Humanoid.Health > 0 do
		local now = os.clock()
		local ok, err = pcall(self.Think, self, now, now - last)
		if ok then
			ok, err = pcall(self.Publish, self, now)
		end
		last = now
		if not ok and not warned then
			warned = true
			warn("Soldier " .. self.Model.Name .. ": " .. tostring(err))
		end
		task.wait(THINK)
	end
end

-- A player's gunshot (GunServer fires ServerStorage.Events.Gunshot) is heard by the other side like a
-- soldier's: within Brain.PlayerHear studs (default 140, guns are loud), at most once every 0.3 s each.
do
	local events = game:GetService("ServerStorage"):FindFirstChild("Events")
	local gunshot = events and events:FindFirstChild("Gunshot")
	if gunshot and gunshot:IsA("BindableEvent") then
		local heardAt = setmetatable({}, { __mode = "k" })
		gunshot.Event:Connect(function(player, origin)
			local char = typeof(player) == "Instance" and player:IsA("Player") and player.Character
			if not char or typeof(origin) ~= "Vector3" then
				return
			end
			local now = os.clock()
			if now - (heardAt[player] or 0) < 0.3 then
				return
			end
			heardAt[player] = now
			Soldier.Noise(origin, playerSide(player), char, BRAIN.PlayerHear or 140)
		end)
	end
end

return Soldier
