-- WAR tanks (horror-shooter/war/WAR-V2-CONTRACTS.md, TANKS). A tank is one solid box (the hull) that
-- physics drives over the ground, a turret on a servo hinge, and about thirty plain parts welded on
-- that nothing collides with. Its crew is the AI in this module: it drives a lane of points and then
-- holds there, turns the turret onto the nearest enemy it can see, fires the main gun every few
-- seconds (a single shell from Emplacements.Barrage where the round lands) and the coaxial gun
-- (WarDamage.Ray rounds) at anyone in reach.
--   Bullets only scratch it. A player of the other side holds E at its back deck to plant a satchel;
--   a few seconds later the charge goes off and the tank burns out where it stands. Artillery and
--   other blasts hurt it in full.
--   Tank.Spawn(side, at, opts) -> tank. at: a Vector3 on the ground (or near it). opts: Lane = points
--   driven in order; or Goal = a point it paths toward and stops Stop studs short of (default 26);
--   Speed, Health; OnDestroyed(tank, player).
--   tank.Model, tank.Side, tank.Alive, tank:Position(), tank:Remove().
--   Tank.All(side) (the ones still running), Tank.Clear() (every tank and wreck gone).
--   Tank.Lane(name): the points of workspace.Map.War[name] (a part, or a folder of parts taken in
--   name order), or nil. WarServer looks for <group>_Tank lanes there.
-- The model: Side, Health and Dead attributes, the tag "Tank", a part named Head (the turret, for
-- Remotes.ShotFx) and an attachment named Muzzle at the end of the gun.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Remotes = ReplicatedStorage.Remotes

-- WarDamage requires Soldier; both load on first use so either can require this module.
local WarDamage, Soldier, Emplacements
local function deps()
	if not WarDamage then
		WarDamage = require(script.Parent.WarDamage)
		Soldier = require(script.Parent.Soldier)
		local e = script.Parent:FindFirstChild("Emplacements")
		Emplacements = e and require(e)
	end
end

local CFG = {
	Speed = 7, -- studs a second on the move
	TurretSpeed = 1.1, -- radians a second
	Health = 1000,
	Range = 170, -- the main gun
	CoaxRange = 110,
	MainGap = 6.5, -- seconds between shells (plus up to 2)
	MainDamage = 50,
	MainRadius = 11,
	MainSpread = 0.035, -- studs off per stud of range
	CoaxGap = 1.4,
	CoaxRounds = 4,
	CoaxDamage = 7,
	CoaxSpread = 0.05,
	BulletScale = 0, -- bullets don't hurt it: satchels, artillery and other blasts do
	Fuse = 4,
	SatchelHold = 2.5,
	Think = 0.1,
	Retarget = 0.5,
}

local PALETTE = {
	Enemy = { Hull = Color3.fromRGB(46, 44, 41), Trim = Color3.fromRGB(84, 60, 40), Lamp = Color3.fromRGB(255, 176, 88) },
	Ally = { Hull = Color3.fromRGB(78, 86, 58), Trim = Color3.fromRGB(58, 62, 44), Lamp = Color3.fromRGB(232, 236, 214) },
}
local TRACK = Color3.fromRGB(34, 33, 31)
local IRON = Color3.fromRGB(62, 60, 56)
local SATCHEL = Color3.fromRGB(112, 104, 74)

local Tank = {}
Tank.__index = Tank

local tanks = {} -- [model] = tank
local folder = nil
local running = false

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function root()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "Tanks"
		folder.Parent = workspace
	end
	return folder
end

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.RespectCanCollide = true
worldParams.IgnoreWater = true

-- Rays through the world only: tanks, soldiers, effects, the story's props and players are skipped.
local function world(extra)
	local list = { root() }
	for _, name in { "Squad", "Hostiles", "Fx", "Story" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	if extra then
		table.insert(list, extra)
	end
	worldParams.FilterDescendantsInstances = list
	return worldParams
end

local function groundAt(pos)
	local hit = workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), world())
	return if hit then hit.Position else pos
end

-- The body ----------------------------------------------------------------------------------------

local function part(model, name, size, cf, color, shape, material)
	local p = if shape == "Wedge" then Instance.new("WedgePart") else Instance.new("Part")
	if shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = size.Magnitude > 4
	p.Parent = model
	return p
end

local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Built around base (the hull's middle, -Z forward). Returns the model, hull, turret base, muzzle,
-- the deck attachment for the satchel, and the lamps.
local function build(side, base)
	local c = PALETTE[side] or PALETTE.Enemy
	local model = Instance.new("Model")
	model.Name = side .. "Tank"
	-- Streams in whole: clients need the hull, the Head and the Muzzle together.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local hull = part(model, "Hull", Vector3.new(7.6, 2.6, 11.5), base, c.Hull)
	hull.Transparency = 1
	hull.CanCollide = true
	hull.Massless = false
	hull.CastShadow = false
	hull.CustomPhysicalProperties = PhysicalProperties.new(3, 0.05, 0, 100, 100)
	model.PrimaryPart = hull
	local function onHull(name, size, offset, color, shape, material)
		local p = part(model, name, size, base * offset, color, shape, material)
		weld(hull, p)
		return p
	end
	-- Tracks with rounded ends, road wheels, fenders.
	for _, x in { -3, 3 } do
		onHull("Track", Vector3.new(1.7, 2.3, 11.8), CFrame.new(x, -0.15, 0), TRACK)
		for _, z in { -5.9, 5.9 } do
			onHull("TrackEnd", Vector3.new(1.7, 2.3, 2.3), CFrame.new(x, -0.15, z), TRACK, "Cylinder")
		end
		for _, z in { -4.2, -1.4, 1.4, 4.2 } do
			onHull("Wheel", Vector3.new(0.4, 1.7, 1.7), CFrame.new(x * 1.3, -0.45, z), IRON, "Cylinder")
		end
		onHull("Fender", Vector3.new(1.9, 0.18, 12.2), CFrame.new(x, 1.06, 0), c.Hull)
		onHull("ToolBox", Vector3.new(0.7, 0.55, 2.2), CFrame.new(x * 1.08, 1.43, 2.6), c.Trim)
	end
	-- Upper hull, sloped glacis, engine deck, headlamps, bow gun, exhausts.
	onHull("UpperHull", Vector3.new(5, 1.3, 9), CFrame.new(0, 0.95, 0.6), c.Hull)
	onHull("Glacis", Vector3.new(5, 1.3, 2.4), CFrame.new(0, 0.95, -5.1), c.Hull, "Wedge")
	onHull("Deck", Vector3.new(4.4, 0.25, 2.6), CFrame.new(0, 1.72, 3.7), c.Trim)
	local lamps = {}
	for _, x in { -1.9, 1.9 } do
		table.insert(lamps, onHull("Headlamp", Vector3.new(0.3, 0.6, 0.6), CFrame.new(x, 1.45, -5) * CFrame.Angles(0, math.rad(90), 0), c.Lamp, "Cylinder", Enum.Material.Neon))
		onHull("Exhaust", Vector3.new(0.9, 0.45, 0.45), CFrame.new(x * 0.8, 1.2, 5.85) * CFrame.Angles(0, math.rad(90), 0), IRON, "Cylinder")
	end
	onHull("BowGun", Vector3.new(0.7, 0.7, 0.7), CFrame.new(1.3, 1.2, -4.75), IRON, "Ball")
	-- The turret: its own assembly on a servo hinge.
	local ringCF = base * CFrame.new(0, 1.85, -0.3)
	local turretBase = part(model, "TurretRing", Vector3.new(0.5, 4.2, 4.2), ringCF * CFrame.Angles(0, 0, math.rad(90)), IRON, "Cylinder")
	turretBase.Massless = false
	local function onTurret(name, size, offset, color, shape, material)
		local p = part(model, name, size, ringCF * offset, color, shape, material)
		weld(turretBase, p)
		return p
	end
	local head = onTurret("Head", Vector3.new(4, 1.6, 4.6), CFrame.new(0, 1, 0.3), c.Hull)
	head.CastShadow = true
	onTurret("TurretFront", Vector3.new(4, 1.6, 1.4), CFrame.new(0, 1, -2.65), c.Hull, "Wedge")
	onTurret("Mantlet", Vector3.new(1.6, 1, 0.6), CFrame.new(0, 0.9, -3.4), IRON)
	onTurret("Barrel", Vector3.new(6.5, 0.45, 0.45), CFrame.new(0, 0.9, -6.65) * CFrame.Angles(0, math.rad(90), 0), IRON, "Cylinder")
	local brake = onTurret("MuzzleBrake", Vector3.new(0.8, 0.68, 0.68), CFrame.new(0, 0.9, -10), IRON, "Cylinder")
	brake.CFrame = ringCF * CFrame.new(0, 0.9, -10) * CFrame.Angles(0, math.rad(90), 0)
	onTurret("Hatch", Vector3.new(0.3, 1.6, 1.6), CFrame.new(0.8, 1.95, 0.9) * CFrame.Angles(0, 0, math.rad(90)), IRON, "Cylinder")
	onTurret("Stowage", Vector3.new(3.4, 0.8, 0.9), CFrame.new(0, 0.8, 3.05), c.Trim)
	if side == "Enemy" then
		-- The Lamplighters' mark: a caged lamp on a post behind the hatch.
		onTurret("LampPost", Vector3.new(0.25, 1.1, 0.25), CFrame.new(-1.3, 2.3, 1.2), IRON)
		local glass = onTurret("Lamp", Vector3.new(0.7, 0.8, 0.7), CFrame.new(-1.3, 3.2, 1.2), c.Lamp, nil, Enum.Material.Neon)
		onTurret("LampCap", Vector3.new(0.95, 0.2, 0.95), CFrame.new(-1.3, 3.7, 1.2), IRON)
		onTurret("LampCage", Vector3.new(0.9, 0.12, 0.9), CFrame.new(-1.3, 2.8, 1.2), IRON)
		local light = Instance.new("PointLight")
		light.Color = c.Lamp
		light.Range = 16
		light.Brightness = 1.4
		light.Shadows = false
		light.Parent = glass
		table.insert(lamps, glass)
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = brake
	muzzle.WorldPosition = (ringCF * CFrame.new(0, 0.9, -10.45)).Position
	-- The hinge: both attachments' X axes point up through the turret ring.
	local axis = ringCF * CFrame.Angles(0, 0, math.rad(90))
	local a0 = Instance.new("Attachment")
	a0.Name = "TurretAxis"
	a0.Parent = hull
	a0.WorldCFrame = axis
	local a1 = Instance.new("Attachment")
	a1.Name = "TurretAxis"
	a1.Parent = turretBase
	a1.WorldCFrame = axis
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Servo
	hinge.AngularSpeed = CFG.TurretSpeed
	hinge.ServoMaxTorque = 1e8
	hinge.Parent = hull
	-- The back deck, where a satchel goes.
	local deck = Instance.new("Attachment")
	deck.Name = "Deck"
	deck.Parent = hull
	deck.WorldPosition = (base * CFrame.new(0, 1.9, 3.7)).Position
	return model, hull, turretBase, hinge, muzzle, deck, lamps
end

-- Driving -----------------------------------------------------------------------------------------

local function drivers(hull)
	local att = Instance.new("Attachment")
	att.Name = "Drive"
	att.Parent = hull
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxTorque = math.huge
	align.Responsiveness = 8
	align.CFrame = hull.CFrame.Rotation
	align.Parent = hull
	local vel = Instance.new("LinearVelocity")
	vel.Attachment0 = att
	vel.RelativeTo = Enum.ActuatorRelativeTo.World
	vel.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	vel.PrimaryTangentAxis = Vector3.xAxis
	vel.SecondaryTangentAxis = Vector3.zAxis
	vel.PlaneVelocity = Vector2.zero
	vel.MaxForce = 1e6
	vel.Parent = hull
	return align, vel
end

-- The points from at toward goal, stopping stop studs short (a straight line if no path is found).
local function pathTo(at, goal, stop)
	local points = {}
	local path = PathfindingService:CreatePath({ AgentRadius = 5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 10 })
	local ok = pcall(path.ComputeAsync, path, at, goal)
	if ok and path.Status == Enum.PathStatus.Success then
		for _, w in path:GetWaypoints() do
			table.insert(points, w.Position)
		end
	else
		points = { at, goal }
	end
	-- Trim the end: hold off from the goal.
	while #points > 1 and flat(points[#points] - goal).Magnitude < stop do
		table.remove(points)
	end
	if #points == 1 then
		local dir = flat(goal - at)
		if dir.Magnitude > stop then
			table.insert(points, at + dir.Unit * (dir.Magnitude - stop))
		end
	end
	return points
end

function Tank:Position()
	return self.Hull.Position
end

function Tank:Drive(now)
	local hullCF = self.Hull.CFrame
	local pos = hullCF.Position
	local goal = self.Lane[self.LaneAt]
	while goal and flat(goal - pos).Magnitude < 4 do
		self.LaneAt += 1
		goal = self.Lane[self.LaneAt]
	end
	if not goal then
		self.Velocity.PlaneVelocity = Vector2.zero
		self.Moving = false
		return
	end
	local dir = flat(goal - pos).Unit
	local look = flat(hullCF.LookVector)
	look = if look.Magnitude > 0.1 then look.Unit else dir
	local off = math.acos(math.clamp(look:Dot(dir), -1, 1))
	self.Align.CFrame = CFrame.lookAt(Vector3.zero, dir)
	-- Tracks: it drives the way it faces, slowing to turn on the spot.
	local speed = self.Speed * (if off > 0.6 then 0.1 else 1 - off)
	local v = look * speed
	self.Velocity.PlaneVelocity = Vector2.new(v.X, v.Z)
	self.Moving = true
	-- Stuck: two checks running without getting anywhere skips to the next point.
	if now - self.StuckAt >= 3 then
		if (pos - self.StuckFrom).Magnitude < 1.2 and speed > 1 then
			self.Stuck += 1
		else
			self.Stuck = 0
		end
		if self.Stuck >= 2 then
			self.Stuck = 0
			self.LaneAt += 1
		end
		self.StuckFrom, self.StuckAt = pos, now
	end
end

-- Fighting ----------------------------------------------------------------------------------------

local function otherSide(side)
	return if side == "Enemy" then "Ally" else "Enemy"
end

-- The nearest enemy it can see from the gun, in range: { Model, Pos } or nil.
function Tank:FindTarget()
	local muzzle = self.Muzzle.WorldPosition
	local list = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if r and h and h.Health > 0 and p:GetAttribute("InMatch") and not c:GetAttribute("Downed")
			and WarDamage.Hostile(self.Side, WarDamage.PlayerSide(p)) then
			table.insert(list, { Model = c, Pos = r.Position, D = (r.Position - muzzle).Magnitude })
		end
	end
	for _, s in Soldier.All(otherSide(self.Side)) do
		if s.Alive then
			table.insert(list, { Model = s.Model, Pos = s.Root.Position, D = (s.Root.Position - muzzle).Magnitude })
		end
	end
	table.sort(list, function(a, b)
		return a.D < b.D
	end)
	for i = 1, math.min(#list, 8) do
		local f = list[i]
		if f.D > CFG.Range then
			break
		end
		local look = f.Pos + Vector3.new(0, 1, 0)
		if not workspace:Raycast(muzzle, look - muzzle, world(self.Model)) then
			return f
		end
	end
	return nil
end

local function spread(amount)
	return Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.5, math.random() - 0.5) * 2 * amount
end

function Tank:FireMain(target)
	local muzzle = self.Muzzle.WorldPosition
	local d = (target.Pos - muzzle).Magnitude
	local aim = target.Pos + spread(d * CFG.MainSpread)
	local hit = workspace:Raycast(muzzle, (aim - muzzle).Unit * (d + 25), world(self.Model))
	local at = if hit then hit.Position else aim
	Remotes.ShotFx:FireAllClients(self.Model, { at }, "Sniper")
	SoundKit.Play("Intro/Artillery", { Position = muzzle })
	if Emplacements then
		Emplacements.Barrage(at, 0, 1, self.Side, { Lead = 0.12, BlastRadius = CFG.MainRadius, Damage = CFG.MainDamage, Vehicles = 1 })
	else
		WarDamage.Blast(at, CFG.MainRadius, CFG.MainDamage, { Side = self.Side, Kind = "Shell", Model = self.Model }, { Vehicles = 1 })
	end
	-- The recoil rocks the hull back.
	local back = flat(muzzle - at)
	if back.Magnitude > 0.1 then
		self.Hull:ApplyImpulse(back.Unit * self.Hull.AssemblyMass * 2.5)
	end
end

function Tank:FireCoax(target)
	local muzzle = self.Muzzle.WorldPosition
	local by = { Side = self.Side, Kind = "Bullet", Model = self.Model, Gun = "AK" }
	local ends = {}
	for i = 1, CFG.CoaxRounds do
		local d = (target.Pos - muzzle).Magnitude
		local aim = target.Pos + Vector3.new(0, 1, 0) + spread(d * CFG.CoaxSpread)
		local dir = (aim - muzzle).Unit
		local hit = WarDamage.Ray(muzzle, dir, CFG.CoaxRange + 10, CFG.CoaxDamage, by)
		ends[i] = if hit then hit.Position else muzzle + dir * (CFG.CoaxRange + 10)
	end
	Remotes.ShotFx:FireAllClients(self.Model, ends, "AK")
end

function Tank:Fight(now)
	if now >= self.NextLook then
		self.NextLook = now + CFG.Retarget
		self.Target = self:FindTarget()
	end
	local target = self.Target
	if not target or not target.Model.Parent then
		return
	end
	local turretPos = self.Turret.Position
	local rel = self.Hull.CFrame:VectorToObjectSpace(flat(target.Pos - turretPos))
	local want = math.deg(math.atan2(-rel.X, -rel.Z))
	self.Hinge.TargetAngle = want
	local off = math.abs((want - self.Hinge.CurrentAngle + 180) % 360 - 180)
	local d = (target.Pos - turretPos).Magnitude
	if off < 5 and now >= self.NextMain and d <= CFG.Range then
		self.NextMain = now + CFG.MainGap + math.random() * 2
		self:FireMain(target)
	elseif off < 12 and now >= self.NextCoax and d <= CFG.CoaxRange then
		self.NextCoax = now + CFG.CoaxGap
		self:FireCoax(target)
	end
end

-- Hits, the satchel, the wreck --------------------------------------------------------------------

function Tank:Wreck(player)
	if not self.Alive then
		return
	end
	self.Alive = false
	self.Model:SetAttribute("Dead", true)
	self.Model:SetAttribute("Health", 0)
	self.Velocity.Enabled = false
	self.Align.Enabled = false
	if self.Prompt then
		self.Prompt:Destroy()
		self.Prompt = nil
	end
	if self.Engine then
		self.Engine:Stop()
	end
	-- The turret is blown off its ring: it pops up and drops back onto the hull. It doesn't collide,
	-- so it can't land on a player (it used to fling or trap whoever planted the satchel).
	self.Hinge:Destroy()
	self.Turret.CanCollide = false
	self.Turret.Anchored = true
	local from = self.Hull.CFrame:ToObjectSpace(self.Turret.CFrame)
	local tilt = CFrame.Angles(math.rad(math.random(-14, 14)), math.rad(math.random(-40, 40)), math.rad(math.random(-14, 14)))
	local to = CFrame.new(math.random(-8, 8) / 10, 0, math.random(-8, 8) / 10) * from * tilt
	task.spawn(function()
		local t0 = os.clock()
		while self.Turret.Parent do
			local k = math.min((os.clock() - t0) / 0.7, 1)
			local lift = 3.2 * math.sin(k * math.pi) -- up and back down
			self.Turret.CFrame = self.Hull.CFrame * from:Lerp(to, k) + Vector3.new(0, lift, 0)
			if k >= 1 then
				break
			end
			task.wait()
		end
	end)
	local burnt = Color3.fromRGB(20, 19, 18)
	for _, d in self.Model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = d.Color:Lerp(burnt, 0.7)
			if d.Material == Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic
			end
		elseif d:IsA("Light") then
			d.Enabled = false
		end
	end
	local fire = Instance.new("Fire")
	fire.Size = 7
	fire.Heat = 9
	fire.Parent = self.Hull
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(46, 44, 42)
	smoke.Size = 6
	smoke.Opacity = 0.3
	smoke.RiseVelocity = 8
	smoke.Parent = self.Hull
	SoundKit.Play("World/Explosion", { Position = self.Hull.Position })
	-- Settled, the wreck stops costing physics.
	task.delay(5, function()
		if self.Model.Parent then
			self.Hull.Anchored = true
			self.Turret.Anchored = true
		end
	end)
	if self.OnDestroyed then
		task.spawn(self.OnDestroyed, self, player)
	end
end

function Tank:Hurt(amount, fromPos, by)
	if not self.Alive then
		return 0, false
	end
	if by.Kind == "Bullet" then
		amount *= CFG.BulletScale
	end
	self.Health -= amount
	self.Model:SetAttribute("Health", math.max(0, math.floor(self.Health)))
	if self.Health <= 0 then
		self:Wreck(by.Player)
		return amount, true
	end
	return amount, false
end

local function standing(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and not c:GetAttribute("Downed")
end

function Tank:Plant(player)
	self.Prompt.Enabled = false
	local deckCF = self.Deck.WorldCFrame
	local charge = part(self.Model, "Satchel", Vector3.new(1.2, 0.7, 0.9), deckCF * CFrame.new(0.6, 0.35, 0) * CFrame.Angles(0, math.rad(20), 0), SATCHEL, nil, Enum.Material.Fabric)
	weld(self.Hull, charge)
	local strap = part(self.Model, "Strap", Vector3.new(0.2, 0.75, 0.95), charge.CFrame, Color3.fromRGB(60, 50, 34))
	weld(self.Hull, strap)
	local side = WarDamage.PlayerSide(player)
	task.spawn(function()
		local fuse = os.clock() + CFG.Fuse
		while os.clock() < fuse and charge.Parent do
			SoundKit.Play("Night/FlashlightClick", { Position = charge.Position })
			task.wait(if fuse - os.clock() < 1.2 then 0.2 else 0.5)
		end
		if not charge.Parent or not self.Model.Parent then
			return
		end
		local at = charge.Position
		charge:Destroy()
		strap:Destroy()
		if Emplacements then
			Emplacements.Barrage(at, 0, 1, side, { Lead = 0.01, Damage = 0 })
		end
		SoundKit.Play("World/Explosion", { Position = at })
		local by = { Side = side, Kind = "Blast", Player = player }
		WarDamage.Blast(at, 12, 80, by, { Vehicles = 0 })
		self:Hurt(self.MaxHealth * 2, at, by)
	end)
end

function Tank:Remove()
	self.Alive = false
	tanks[self.Model] = nil
	WarDamage.UnregisterVehicle(self.Model)
	self.Model:Destroy()
end

-- The crew ----------------------------------------------------------------------------------------

local function loop()
	running = true
	while next(tanks) do
		local now = os.clock()
		for model, t in tanks do
			if not model.Parent then
				tanks[model] = nil
				WarDamage.UnregisterVehicle(model)
			elseif t.Alive then
				local ok, err = pcall(function()
					t:Drive(now)
					t:Fight(now)
				end)
				if not ok then
					warn("Tank: " .. tostring(err))
				end
			end
		end
		task.wait(CFG.Think)
	end
	running = false
end

function Tank.Spawn(side, at, opts)
	deps()
	opts = opts or {}
	local lane = opts.Lane
	local g = groundAt(if lane then lane[1] else at)
	if not lane then
		lane = if opts.Goal then pathTo(g, groundAt(opts.Goal), opts.Stop or 26) else { g }
	end
	local ahead = lane[2] or lane[1] + Vector3.new(0, 0, -1)
	local look = flat(ahead - g)
	local base = CFrame.lookAt(g + Vector3.new(0, 1.6, 0), g + Vector3.new(0, 1.6, 0) + (if look.Magnitude > 0.1 then look else Vector3.new(0, 0, -1)))
	local model, hull, turret, hinge, muzzle, deck, lamps = build(side, base)
	local align, vel = drivers(hull)
	local health = opts.Health or CFG.Health
	local self = setmetatable({
		Model = model,
		Side = side,
		Hull = hull,
		Turret = turret,
		Hinge = hinge,
		Muzzle = muzzle,
		Deck = deck,
		Lamps = lamps,
		Align = align,
		Velocity = vel,
		Lane = lane,
		LaneAt = 2,
		Speed = opts.Speed or CFG.Speed,
		Health = health,
		MaxHealth = health,
		Alive = true,
		Moving = false,
		Target = nil,
		NextLook = 0,
		NextMain = os.clock() + 3,
		NextCoax = 0,
		Stuck = 0,
		StuckAt = os.clock(),
		StuckFrom = g,
		OnDestroyed = opts.OnDestroyed,
	}, Tank)
	model:SetAttribute("Side", side)
	model:SetAttribute("Health", health)
	CollectionService:AddTag(model, "Tank")
	-- The satchel: a player of the other side, at the back deck.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Plant satchel"
	prompt.ObjectText = "Tank"
	prompt.HoldDuration = CFG.SatchelHold
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Parent = deck
	self.Prompt = prompt
	prompt.Triggered:Connect(function(player)
		if self.Alive and prompt.Enabled and standing(player) and WarDamage.Hostile(self.Side, WarDamage.PlayerSide(player)) then
			self:Plant(player)
		end
	end)
	-- Studio tests: set the model's DevWreck attribute to burn it out as a satchel would.
	if game:GetService("RunService"):IsStudio() then
		model:GetAttributeChangedSignal("DevWreck"):Connect(function()
			self:Hurt(self.MaxHealth * 2, hull.Position, { Kind = "Blast" })
		end)
	end
	-- The engine.
	local template = SoundKit.Pick("Intro/EngineDrone")
	if template then
		local engine = template:Clone()
		engine.Looped = true
		engine.PlaybackSpeed = 0.5
		engine.Volume = 0.55
		engine.RollOffMaxDistance = 220
		engine.Parent = hull
		engine:Play()
		self.Engine = engine
	end
	model.Parent = root()
	hull:SetNetworkOwner(nil)
	WarDamage.RegisterVehicle(model, function(amount, fromPos, by)
		return self:Hurt(amount, fromPos, by)
	end)
	tanks[model] = self
	if not running then
		task.spawn(loop)
	end
	return self
end

function Tank.All(side)
	local out = {}
	for _, t in tanks do
		if t.Alive and (side == nil or t.Side == side) then
			table.insert(out, t)
		end
	end
	return out
end

function Tank.Clear()
	for _, t in tanks do
		t:Remove()
	end
	table.clear(tanks)
	if folder then
		folder:ClearAllChildren()
	end
end

function Tank.Lane(name)
	local map = workspace:FindFirstChild("Map")
	local war = map and map:FindFirstChild("War")
	local node = war and war:FindFirstChild(name)
	if not node then
		return nil
	end
	local parts = if node:IsA("BasePart") then { node } else {}
	for _, p in node:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	if #parts == 0 then
		return nil
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	local points = {}
	for _, p in parts do
		table.insert(points, p.Position)
	end
	return points
end

return Tank
