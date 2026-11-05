-- Mounted machine guns and artillery for WAR (horror-shooter/war/WAR-V2-CONTRACTS.md, GUNS contract).
--   Nests stand on markers: any BasePart tagged GunNest with attributes Side ("Ally"/"Enemy"), Kind
--   ("MG") and optionally Arc (degrees either side of the marker's facing, default 60). Start()
--   clones ServerStorage.WarProps.Emplacements.MGNest onto each one (into workspace.Emplacements),
--   hides the marker and keeps listening for new markers.
--   Players man a gun with the prompt EmplacementClient puts on it ("Man the gun"); the client sends
--   its aim and trigger about 15 times a second on Remotes.Emplacement and the server checks the
--   arc, the swivel rate and the fire rate itself. NPCs use the same guns through this module:
--     Emplacements.Nearest(pos, side, maxDist) -> emp | nil   (free and on that side)
--     emp:Claim(soldier) -> seatCFrame | nil, emp:Release(soldier)
--     emp:AimAt(pos) -> inArc, emp:Fire(targetPos) -> firing   (the gun keeps its own rate, bursts, heat)
--     emp.Model, emp.Side, emp.Arc, emp.Gunner (soldier, player or nil), emp.Heat, emp.Overheated,
--     emp.Seat (a standing gunner's root CFrame: 3 studs above the nest floor, facing the gun's rest
--     direction; Claim returns it), emp.SeatGround (the same spot on the nest floor)
--   Every round is a WarDamage.Ray; artillery is Emplacements.Barrage(center, radius, shells, side, opts?).
--   Server work runs in one 10 Hz loop over the guns that are busy; clients draw everything.
-- Model attributes (read by EmplacementClient): Side, Kind, Arc, Aim (Vector2 yaw/pitch, radians, from
-- the facing), Heat (0..1), Overheated, Manned, Gunner. Player attribute: OnEmplacement = nest name.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Emplacements = {}

local CFG = {
	Arc = 60, -- degrees either side of the facing (marker attribute Arc overrides)
	PitchUp = 25,
	PitchDown = 18,
	RPM = 900,
	Damage = 12, -- per round, a player's gun
	NpcDamage = 5, -- per round, a soldier's gun (12 at 900 RPM downed a player inside one burst)
	Range = 250,
	Spread = 1.0, -- degrees, a player's gun
	NpcSpread = 2.2, -- degrees, a soldier's gun
	HeatTime = 3, -- seconds of continuous fire to overheat
	CoolTime = 2, -- seconds from full heat to cold
	SwivelRate = 110, -- degrees a second, the gun turning to an NPC's aim
	PlayerRate = 330, -- degrees a second a player's reported aim may move (the client turns at 220)
	OnTarget = 6, -- degrees: an NPC's burst only fires when the gun is this close to the aim
	Burst = NumberRange.new(0.35, 0.75), -- seconds of fire per NPC burst
	BurstGap = NumberRange.new(0.3, 0.7),
	Tick = 0.1,
	FxRange = 320,
	MountRange = 12,
	InputTimeout = 0.4,
	Bore = 0.33, -- the barrel's height above the swivel
	Shell = {
		Lead = 1.2, -- whistle before impact
		BlastRadius = 14,
		Damage = 120,
		MaxLive = 24,
		Spacing = 0.45, -- seconds of spread per shell when opts.Duration is not given
	},
}
Emplacements.Config = CFG

local TEMPLATES = { MG = "MGNest" }

local rng = Random.new()
local list = {} -- every emp
local byModel = {} -- [model] = emp
local byMarker = {} -- [marker] = emp
local byPlayer = {} -- [player] = emp
local active = {} -- [emp] = true while busy
local started = false
local remote, fxRemote, folder
local liveShells = 0
local gunName

-- WarDamage requires Soldier; load both on first use so Soldier or Battle can require this module.
local WarDamage, Soldier
local function deps()
	if not WarDamage then
		WarDamage = require(script.Parent.WarDamage)
		local ok, s = pcall(require, script.Parent.Soldier)
		Soldier = ok and s or nil
	end
	return WarDamage
end

local function between(range)
	return range.Min + rng:NextNumber() * (range.Max - range.Min)
end

local function approach(from, to, maxStep)
	local d = to - from
	if math.abs(d) <= maxStep then
		return to
	end
	return from + math.sign(d) * maxStep
end

local function isPlayer(x)
	return typeof(x) == "Instance" and x:IsA("Player")
end

local function excludeParams(extra)
	local ex = {}
	local function add(i)
		if i then
			table.insert(ex, i)
		end
	end
	add(folder)
	add(workspace:FindFirstChild("Fx"))
	local map = workspace:FindFirstChild("Map")
	add(map and map:FindFirstChild("War"))
	for _, name in { "Squad", "Hostiles", "Zombies", "Dogs" } do
		add(workspace:FindFirstChild(name))
	end
	for _, p in Players:GetPlayers() do
		add(p.Character)
	end
	for _, e in extra or {} do
		add(e)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ex
	params.IgnoreWater = true
	return params
end

-- The ground under pos (the first solid surface within depth below from), or nil.
local function groundAt(pos, up, depth, extra)
	local hit = workspace:Raycast(pos + Vector3.new(0, up, 0), Vector3.new(0, -(up + depth), 0), excludeParams(extra))
	if hit then
		return hit.Position, hit.Normal
	end
	return nil
end

-- The emp object -------------------------------------------------------------------------------------

local Emp = {}
Emp.__index = Emp

-- The gun's frame at yaw/pitch (radians from the facing): the swivel turned, then tipped.
function Emp:Frame(yaw, pitch)
	return self.Swivel * CFrame.Angles(0, yaw or self.Yaw, 0) * CFrame.Angles(pitch or self.Pitch, 0, 0)
end

-- Yaw and pitch (radians, from the facing) that point the barrel at pos, unclamped, and the distance.
function Emp:AnglesTo(pos)
	local from = self.Swivel * Vector3.new(0, CFG.Bore, 0)
	local d = self.Swivel:VectorToObjectSpace(pos - from)
	local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
	return math.atan2(-d.X, -d.Z), math.atan2(d.Y, flat), d.Magnitude
end

function Emp:InArc(pos)
	local yaw, pitch = self:AnglesTo(pos)
	return math.abs(yaw) <= math.rad(self.Arc) + 0.02 and pitch <= math.rad(CFG.PitchUp) + 0.02 and pitch >= -math.rad(CFG.PitchDown) - 0.02
end

function Emp:Clamp(yaw, pitch)
	local arc = math.rad(self.Arc)
	return math.clamp(yaw, -arc, arc), math.clamp(pitch, -math.rad(CFG.PitchDown), math.rad(CFG.PitchUp))
end

function Emp:MuzzlePosition()
	return (self:Frame() * self.MuzzleOffset).Position
end

-- Where a gunner's HumanoidRootPart goes. humanoid (optional) fits the height to its legs; without
-- one it is a standard R15 root, 3 studs above the nest floor. Faces the gun's rest direction.
function Emp:SeatCFrame(humanoid, root)
	if not humanoid then
		return self.Seat
	end
	local hip = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	local half = if root then root.Size.Y / 2 else 1
	local p = self.Seat.Position
	return CFrame.new(p.X, self.Base.Position.Y + hip + half, p.Z) * self.Seat.Rotation
end

local function activate(emp)
	active[emp] = true
end

local function setManned(emp, name)
	emp.Model:SetAttribute("Manned", name ~= nil)
	emp.Model:SetAttribute("Gunner", name)
end

function Emp:AimAt(pos)
	if typeof(pos) ~= "Vector3" then
		return false
	end
	local yaw, pitch = self:AnglesTo(pos)
	self.WantYaw, self.WantPitch = self:Clamp(yaw, pitch)
	activate(self)
	return self:InArc(pos)
end

-- An NPC (or the story) fires at targetPos: the gun turns to it and fires a burst when it is on
-- target, at its own rate. False when it is out of the arc, overheated or a player has the gun.
function Emp:Fire(targetPos)
	if isPlayer(self.Gunner) then
		return false
	end
	if targetPos ~= nil and not self:AimAt(targetPos) then
		return false
	end
	if self.Overheated then
		return false
	end
	local now = os.clock()
	if now >= self.BurstUntil and now >= self.NextBurst then
		self.BurstUntil = now + between(CFG.Burst)
		self.NextBurst = self.BurstUntil + between(CFG.BurstGap)
		self.Acc = math.max(self.Acc, 1)
	end
	activate(self)
	return true
end

-- An NPC takes the gun: returns the seat CFrame (see SeatCFrame), or nil when it is taken or on the
-- other side.
function Emp:Claim(soldier)
	if soldier == nil or (self.Gunner ~= nil and self.Gunner ~= soldier) then
		return nil
	end
	if type(soldier) == "table" and soldier.Side and soldier.Side ~= self.Side then
		return nil
	end
	self.Gunner = soldier
	local name = type(soldier) == "table" and soldier.Model and soldier.Model.Name or "Soldier"
	setManned(self, name)
	activate(self)
	return self.Seat
end

local releasePlayer

function Emp:Release(who)
	if who == nil or self.Gunner ~= who then
		return
	end
	if isPlayer(who) then
		releasePlayer(who, false)
		return
	end
	self.Gunner = nil
	self.BurstUntil = 0
	setManned(self, nil)
end

-- Firing -------------------------------------------------------------------------------------------------

local function gunnerModel(emp)
	local g = emp.Gunner
	if isPlayer(g) then
		return g.Character
	elseif type(g) == "table" then
		return g.Model
	end
	return nil
end

local function snap(emp, from, to, hitModel)
	if Soldier and type(Soldier.Snap) == "function" then
		pcall(Soldier.Snap, { Side = emp.Side }, from, to, hitModel)
	end
end

local function noise(emp, at, now)
	if now - emp.NoiseAt < 0.75 or not Soldier or type(Soldier.Noise) ~= "function" then
		return
	end
	local model = gunnerModel(emp)
	if model then
		emp.NoiseAt = now
		pcall(Soldier.Noise, at, emp.Side, model)
	end
end

local function fireRound(emp, now)
	local frame = emp:Frame()
	local origin = (frame * emp.MuzzleOffset).Position
	local player = if isPlayer(emp.Gunner) then emp.Gunner else nil
	local spread = math.rad(if player then CFG.Spread else CFG.NpcSpread)
	local dir = (frame * CFrame.Angles((rng:NextNumber() - 0.5) * spread, (rng:NextNumber() - 0.5) * spread, 0)).LookVector
	local by = { Side = emp.Side, Player = player, Kind = "Bullet", Gun = gunName, Model = emp.Model }
	local ignore = {}
	local gm = gunnerModel(emp)
	if gm then
		table.insert(ignore, gm)
	end
	local damage = if player then CFG.Damage else CFG.NpcDamage
	local hit, model = WarDamage.Ray(origin, dir, CFG.Range, damage, by, ignore)
	local endPos = if hit then hit.Position else origin + dir * CFG.Range
	table.insert(emp.FxEnds, endPos)
	if hit then
		emp.FxMask += 2 ^ (#emp.FxEnds - 1)
	end
	emp.FxOrigin = origin
	snap(emp, origin, endPos, model)
	noise(emp, origin, now)
end

local function flushFx(emp)
	local ends = emp.FxEnds
	if #ends == 0 then
		return
	end
	local origin, mask = emp.FxOrigin, emp.FxMask
	local skip = if isPlayer(emp.Gunner) then emp.Gunner else nil -- the gunner draws its own shots
	local r2 = CFG.FxRange * CFG.FxRange
	for _, p in Players:GetPlayers() do
		if p ~= skip then
			local c = p.Character
			local root = c and c.PrimaryPart
			local d = root and (root.Position - origin)
			if d and d:Dot(d) <= r2 then
				fxRemote:FireClient(p, emp.Model, origin, ends, mask)
			end
		end
	end
	emp.FxEnds = {}
	emp.FxMask = 0
end

local function publish(emp)
	local m = emp.Model
	local last = emp.SentAim
	if math.abs(last.X - emp.Yaw) > 0.002 or math.abs(last.Y - emp.Pitch) > 0.002 then
		emp.SentAim = Vector2.new(emp.Yaw, emp.Pitch)
		m:SetAttribute("Aim", emp.SentAim)
	end
	local heat = math.floor(emp.Heat * 20 + 0.5) / 20
	if heat ~= emp.SentHeat then
		emp.SentHeat = heat
		m:SetAttribute("Heat", heat)
	end
	if emp.Overheated ~= emp.SentOverheated then
		emp.SentOverheated = emp.Overheated
		m:SetAttribute("Overheated", emp.Overheated)
	end
end

-- Drops a gunner that died, left or was moved off the gun.
local function checkGunner(emp)
	local g = emp.Gunner
	if g == nil then
		return
	end
	if isPlayer(g) then
		local c = g.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if g.Parent == nil or not hum or hum.Health <= 0 or g:GetAttribute("OnEmplacement") ~= emp.Model.Name then
			releasePlayer(g, g.Parent == nil)
		end
	elseif type(g) == "table" then
		if g.Alive == false or (g.Model and not g.Model.Parent) then
			emp:Release(g)
		end
	end
end

local function step(emp, now, dt)
	if not emp.Model.Parent then
		active[emp] = nil
		return
	end
	checkGunner(emp)
	local player = isPlayer(emp.Gunner)
	if not player then
		local turn = math.rad(CFG.SwivelRate) * dt
		emp.Yaw = approach(emp.Yaw, emp.WantYaw, turn)
		emp.Pitch = approach(emp.Pitch, emp.WantPitch, turn)
	end

	local firing
	if player then
		firing = now < emp.TriggerUntil or emp.Taps > 0
	else
		local off = math.max(math.abs(emp.Yaw - emp.WantYaw), math.abs(emp.Pitch - emp.WantPitch))
		firing = now < emp.BurstUntil and off <= math.rad(CFG.OnTarget)
	end
	if emp.Overheated then
		firing = false
	end

	if firing then
		emp.Acc += dt * CFG.RPM / 60
		local rounds = math.min(math.floor(emp.Acc), 3)
		emp.Acc -= rounds
		for _ = 1, rounds do
			fireRound(emp, now)
		end
		emp.Taps = math.max(0, emp.Taps - rounds)
		emp.Heat += dt / CFG.HeatTime
		if emp.Heat >= 1 then
			emp.Heat = 1
			emp.Overheated = true
			emp.Acc = 0
			emp.Taps = 0
			emp.BurstUntil = 0
		end
	else
		emp.Acc = math.min(emp.Acc, 0.95)
		emp.Heat = math.max(0, emp.Heat - dt / CFG.CoolTime)
		if emp.Overheated and emp.Heat <= 0 then
			emp.Overheated = false
		end
	end
	flushFx(emp)
	publish(emp)

	local settled = emp.Yaw == emp.WantYaw and emp.Pitch == emp.WantPitch
	if emp.Gunner == nil and not firing and emp.Heat <= 0 and settled and now >= emp.BurstUntil then
		active[emp] = nil
	end
end

local function loop()
	local last = os.clock()
	while true do
		task.wait(CFG.Tick)
		local now = os.clock()
		local dt = math.min(now - last, 0.3)
		last = now
		for emp in active do
			local ok, err = pcall(step, emp, now, dt)
			if not ok then
				warn("[Emplacements] " .. emp.Model.Name .. ": " .. tostring(err))
				active[emp] = nil
			end
		end
	end
end

-- Players ----------------------------------------------------------------------------------------------

releasePlayer = function(player, gone)
	local emp = byPlayer[player]
	if not emp then
		return
	end
	byPlayer[player] = nil
	for _, c in emp.Conns do
		c:Disconnect()
	end
	emp.Conns = {}
	if emp.Gunner == player then
		emp.Gunner = nil
		emp.TriggerUntil = 0
		emp.Taps = 0
		setManned(emp, nil)
	end
	if gone then
		return
	end
	if player:GetAttribute("OnEmplacement") == emp.Model.Name then
		player:SetAttribute("OnEmplacement", nil)
	end
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local hum = c:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			c:PivotTo(emp:SeatCFrame(hum, root) * CFrame.new(0, 0, 1.6))
		end
		root.Anchored = emp.WasAnchored == true
	end
end

-- A player always comes before a soldier: a gun worked by a soldier of the player's side is handed over (the
-- soldier sees emp.Gunner change on its next think and goes back to cover). Another player keeps their gun.
local function mount(player, model)
	local emp = typeof(model) == "Instance" and byModel[model]
	if not emp or byPlayer[player] or not emp.Model.Parent then
		return
	end
	local bumped = emp.Gunner
	if bumped ~= nil and (isPlayer(bumped) or type(bumped) ~= "table" or bumped.Side ~= emp.Side) then
		return
	end
	if deps().PlayerSide(player) ~= emp.Side then
		return
	end
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - emp.Seat.Position).Magnitude > CFG.MountRange then
		return
	end
	if type(bumped) == "table" then
		-- Step the soldier off the seat (behind and to the side) so the two don't stand in each other.
		local sm = bumped.Model
		if sm and sm.Parent then
			pcall(function()
				sm:PivotTo(emp.SeatGround * CFrame.new(2.2, 3, 3))
			end)
		end
		emp.BurstUntil = 0
	end
	emp.Gunner = player
	byPlayer[player] = emp
	emp.WasAnchored = root.Anchored
	emp.LastAimAt = os.clock()
	emp.TriggerUntil = 0
	emp.Taps = 0
	emp.BurstUntil = 0
	root.Anchored = true
	c:PivotTo(emp:SeatCFrame(hum, root))
	setManned(emp, player.Name)
	player:SetAttribute("OnEmplacement", emp.Model.Name)
	table.insert(emp.Conns, hum.Died:Connect(function()
		releasePlayer(player, false)
	end))
	table.insert(emp.Conns, player.CharacterRemoving:Connect(function()
		releasePlayer(player, false)
	end))
	activate(emp)
end

local function aim(player, yaw, pitch, trigger)
	local emp = byPlayer[player]
	if not emp or emp.Gunner ~= player then
		return
	end
	if type(yaw) ~= "number" or type(pitch) ~= "number" or yaw ~= yaw or pitch ~= pitch then
		return
	end
	local now = os.clock()
	local dt = now - emp.LastAimAt
	if dt >= 0.03 then -- faster messages only carry the trigger
		emp.LastAimAt = now
		local maxStep = math.rad(CFG.PlayerRate) * math.min(dt, 0.5) + math.rad(1.5)
		yaw, pitch = emp:Clamp(yaw, pitch)
		emp.Yaw = approach(emp.Yaw, yaw, maxStep)
		emp.Pitch = approach(emp.Pitch, pitch, maxStep)
		emp.WantYaw, emp.WantPitch = emp.Yaw, emp.Pitch
	end
	if trigger == true then
		if now >= emp.TriggerUntil and not emp.Overheated then
			emp.Acc = math.max(emp.Acc, 1)
			emp.Taps = 2 -- a quick tap still fires a pair
		end
		emp.TriggerUntil = now + CFG.InputTimeout
	else
		emp.TriggerUntil = 0
	end
	activate(emp)
end

local function onEvent(player, action, a, b, c)
	if action == "Aim" then
		aim(player, a, b, c)
	elseif action == "Mount" then
		mount(player, a)
	elseif action == "Dismount" then
		releasePlayer(player, false)
	end
end

-- Nests ------------------------------------------------------------------------------------------------

local function uniqueName(base)
	local name, i = base, 1
	while folder:FindFirstChild(name) do
		i += 1
		name = base .. "_" .. i
	end
	return name
end

local function setup(marker)
	if not marker:IsA("BasePart") or byMarker[marker] or not marker:IsDescendantOf(workspace) then
		return
	end
	local kind = marker:GetAttribute("Kind") or "MG"
	local template = ServerStorage.WarProps.Emplacements:FindFirstChild(TEMPLATES[kind] or "MGNest")
	if not template then
		warn("[Emplacements] no template for " .. tostring(kind) .. " at " .. marker:GetFullName())
		return
	end
	local side = marker:GetAttribute("Side")
	if side ~= "Ally" and side ~= "Enemy" then
		warn("[Emplacements] marker " .. marker:GetFullName() .. " has no Side; taking Enemy")
		side = "Enemy"
	end
	local look = marker.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local bottom = marker.Position - Vector3.new(0, marker.Size.Y / 2, 0)
	local ground = groundAt(marker.Position, 3, 12, { marker })
	local at = Vector3.new(bottom.X, if ground then ground.Y else bottom.Y, bottom.Z)
	local base = CFrame.lookAt(at, at + flat)

	local model = template:Clone()
	model.Name = uniqueName(marker.Name)
	model:PivotTo(base)
	model:SetAttribute("Side", side)
	model:SetAttribute("Kind", kind)
	local arc = tonumber(marker:GetAttribute("Arc")) or CFG.Arc
	model:SetAttribute("Arc", arc)
	model:SetAttribute("Aim", Vector2.zero)
	model:SetAttribute("Heat", 0)
	model:SetAttribute("Overheated", false)
	model:SetAttribute("Manned", false)
	CollectionService:AddTag(model, "Emplacement")

	local pad = model:FindFirstChild("Pad")
	local gun = model:FindFirstChild("GunRig") and model.GunRig:FindFirstChild("Gun")
	local swivel = pad and pad:FindFirstChild("Swivel")
	local seat = pad and pad:FindFirstChild("Seat")
	local muzzle = gun and gun:FindFirstChild("Muzzle")
	if not (swivel and seat and muzzle) then
		warn("[Emplacements] template " .. template.Name .. " lacks Pad.Swivel / Pad.Seat / GunRig.Gun.Muzzle")
		model:Destroy()
		return
	end
	model.Parent = folder
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false

	local emp = setmetatable({
		Model = model,
		Marker = marker,
		Side = side,
		Kind = kind,
		Arc = arc,
		Gunner = nil,
		Base = base,
		Swivel = swivel.WorldCFrame,
		Seat = seat.WorldCFrame,
		SeatGround = seat.WorldCFrame - Vector3.new(0, seat.WorldPosition.Y - base.Position.Y, 0),
		MuzzleOffset = swivel.WorldCFrame:ToObjectSpace(muzzle.WorldCFrame),
		Yaw = 0,
		Pitch = 0,
		WantYaw = 0,
		WantPitch = 0,
		Heat = 0,
		Overheated = false,
		Acc = 0,
		Taps = 0,
		TriggerUntil = 0,
		BurstUntil = 0,
		NextBurst = 0,
		NoiseAt = 0,
		LastAimAt = 0,
		FxEnds = {},
		FxMask = 0,
		FxOrigin = Vector3.zero,
		SentAim = Vector2.zero,
		SentHeat = 0,
		SentOverheated = false,
		Conns = {},
	}, Emp)
	table.insert(list, emp)
	byModel[model] = emp
	byMarker[marker] = emp
	return emp
end

local function teardown(marker)
	local emp = byMarker[marker]
	if not emp then
		return
	end
	if isPlayer(emp.Gunner) then
		releasePlayer(emp.Gunner, false)
	end
	byMarker[marker] = nil
	byModel[emp.Model] = nil
	active[emp] = nil
	table.remove(list, table.find(list, emp))
	emp.Model:Destroy()
end

-- API ------------------------------------------------------------------------------------------------

function Emplacements.Start()
	if started then
		return
	end
	started = true
	deps()
	gunName = if GameConfig.Guns and GameConfig.Guns.M60 then "M60" else "AK"
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	remote = remotes:FindFirstChild("Emplacement")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "Emplacement"
		remote.Parent = remotes
	end
	fxRemote = remotes:FindFirstChild("EmplacementFx")
	if not fxRemote then
		fxRemote = Instance.new("UnreliableRemoteEvent")
		fxRemote.Name = "EmplacementFx"
		fxRemote.Parent = remotes
	end
	folder = workspace:FindFirstChild("Emplacements")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Emplacements"
		folder.Parent = workspace
	end
	remote.OnServerEvent:Connect(onEvent)
	Players.PlayerRemoving:Connect(function(p)
		releasePlayer(p, true)
	end)
	for _, marker in CollectionService:GetTagged("GunNest") do
		setup(marker)
	end
	CollectionService:GetInstanceAddedSignal("GunNest"):Connect(setup)
	CollectionService:GetInstanceRemovedSignal("GunNest"):Connect(teardown)
	task.spawn(loop)
end

-- The nearest free gun on side (nil: any side) whose seat is within maxDist of pos.
function Emplacements.Nearest(pos, side, maxDist)
	local best, bestD = nil, maxDist or math.huge
	for _, emp in list do
		if emp.Gunner == nil and emp.Model.Parent and (side == nil or emp.Side == side) then
			local d = (emp.Seat.Position - pos).Magnitude
			if d <= bestD then
				best, bestD = emp, d
			end
		end
	end
	return best
end

function Emplacements.All(side)
	local out = {}
	for _, emp in list do
		if side == nil or emp.Side == side then
			table.insert(out, emp)
		end
	end
	return out
end

function Emplacements.FromModel(model)
	return byModel[model]
end

-- The gun a player is on, or nil.
function Emplacements.OfPlayer(player)
	return byPlayer[player]
end

-- Takes a player off their gun (cutscenes, round end).
function Emplacements.Dismount(player)
	releasePlayer(player, false)
end

-- Artillery: shells land at random inside radius of center over about opts.Duration seconds
-- (default 0.45 s a shell). Each one whistles for opts.Lead (1.2) seconds, then flashes, throws snow
-- and dirt, booms and does WarDamage.Blast(at, opts.BlastRadius 14, opts.Damage 120, { Side = side,
-- Kind = "Shell", Player = opts.Player }, { Vehicles = opts.Vehicles }). No more than 24 shells are
-- in the air at once (the rest of a barrage is dropped). opts.OnImpact(pos) runs after each blast.
-- Returns how many shells were sent.
function Emplacements.Barrage(center, radius, shells, side, opts)
	if not started then
		Emplacements.Start()
	end
	opts = opts or {}
	local S = CFG.Shell
	shells = math.clamp(math.floor(shells or 1), 1, 60)
	radius = math.max(radius or 0, 0)
	local duration = opts.Duration or shells * S.Spacing
	local lead = opts.Lead or S.Lead
	local blastRadius = opts.BlastRadius or S.BlastRadius
	local damage = opts.Damage or S.Damage
	local by = { Side = side, Kind = "Shell", Player = opts.Player }
	local sent = 0
	for i = 1, shells do
		if liveShells >= S.MaxLive then
			break
		end
		liveShells += 1
		sent += 1
		local delay = if i == 1 then 0 else rng:NextNumber(0, duration)
		task.delay(delay, function()
			local ok, err = pcall(function()
				local r = radius * math.sqrt(rng:NextNumber())
				local a = rng:NextNumber(0, math.pi * 2)
				local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				local ground, normal = groundAt(p, 80, 160)
				local at = ground or p
				remote:FireAllClients("Shell", at, lead, normal or Vector3.yAxis)
				task.wait(lead)
				deps().Blast(at, blastRadius, damage, by, { Vehicles = opts.Vehicles })
				if opts.OnImpact then
					opts.OnImpact(at)
				end
			end)
			liveShells -= 1
			if not ok then
				warn("[Emplacements] shell: " .. tostring(err))
			end
		end)
	end
	return sent
end

-- Plain functions for tests.
Emplacements._approach = approach
Emplacements._Emp = Emp

return Emplacements
