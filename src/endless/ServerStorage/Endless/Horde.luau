-- The zombies (numbers: Config.Zombie, Config.Rounds, Config.Specials). A zombie is a classic R6
-- rig built from blocks (no assets), so the reference runs in an empty place; clients pose it
-- (StarterPlayerScripts.EndlessFx: arms out, legs walking, the swipe, the crawl).
-- Spawn(entry, kind, health, speed) brings one up out of the ground outside a window (entry.Window)
-- or out of a floor hatch (entry.Hatch). Through a window it walks up to the boards, tears them off
-- one by one (Windows.Rip), swipes at anyone holding the window from inside, and climbs in over the
-- sill; for an upper window it first climbs the wall to hang outside it. Inside it hunts the nearest
-- standing player (straight at them when close and in sight, else along a PathfindingService path)
-- and swipes: a windup the client sees (model attribute SwingAt), then it lands if you are still in
-- reach and in front of it.
-- Damage(model, amount, part, player, opts) hurts one; an arm or leg that has taken its share tears
-- off (heads never do; owner: less gore on faces), and a zombie with no legs crawls. Blood is green.
-- Kinds: "Walker", "Runner", "Brute" (big and slow), "Crawler" (on its arms from the start).
-- Model attributes for clients: Kind, SwingAt (server time), Crawling, Dead.
-- Signals: Killed (model, killer or nil, info {Head, Melee, Kind, Position}); Lost (a stuck zombie was
-- taken away; the round owes one more).

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Windows = require(ServerStorage.Endless.Windows)
local Survivors = require(ServerStorage.Endless.Survivors)

local ZOMBIE = Config.Zombie
local ATTACK = ZOMBIE.Attack
local NAV = ZOMBIE.Navigation
local BRUTE = Config.Specials.Brute
local SOUNDS = ZOMBIE.Sounds

local Horde = {}
Horde.Killed = Util.Signal()
Horde.Lost = Util.Signal()

local folder
local alive = {} -- [model] = z
local count = 0
local templates = {} -- [scale] = Model

local LIMBS = { ["Left Arm"] = "Arm", ["Right Arm"] = "Arm", ["Left Leg"] = "Leg", ["Right Leg"] = "Leg" }

-- The rig --------------------------------------------------------------------------------------

local R6 = {
	-- name, part0, part1, C0, C1 (the classic R6 joints)
	{ "RootJoint", "HumanoidRootPart", "Torso", CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	{ "Neck", "Torso", "Head", CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	{ "Right Shoulder", "Torso", "Right Arm", CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	{ "Left Shoulder", "Torso", "Left Arm", CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	{ "Right Hip", "Torso", "Right Leg", CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	{ "Left Hip", "Torso", "Left Leg", CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
}

local function buildRig(scale: number): Model
	local model = Instance.new("Model")
	model.Name = "Zombie"
	local parts = {}
	local function limb(name, size)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * scale
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CollisionGroup = "Zombies"
		p.Parent = model
		parts[name] = p
		return p
	end
	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1))
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = false
	limb("Torso", Vector3.new(2, 2, 1))
	local head = limb("Head", Vector3.new(2, 1, 1))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	limb("Left Arm", Vector3.new(1, 2, 1))
	limb("Right Arm", Vector3.new(1, 2, 1))
	limb("Left Leg", Vector3.new(1, 2, 1))
	limb("Right Leg", Vector3.new(1, 2, 1))
	root.CFrame = CFrame.new()
	for _, j in R6 do
		local c0 = CFrame.new(j[4].Position * scale) * j[4].Rotation
		local c1 = CFrame.new(j[5].Position * scale) * j[5].Rotation
		local p0, p1 = parts[j[2]], parts[j[3]]
		p1.CFrame = p0.CFrame * c0 * c1:Inverse()
		local m = Instance.new("Motor6D")
		m.Name = j[1]
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = c0
		m.C1 = c1
		m.Parent = p0
	end
	for side = -1, 1, 2 do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.22, 0.22, 0.22) * scale
		eye.Material = Enum.Material.Neon
		eye.Color = ZOMBIE.Eyes
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.Massless = true
		eye.CFrame = head.CFrame * CFrame.new(side * 0.24 * scale, 0.12 * scale, -0.55 * scale)
		eye.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = eye
		weld.Parent = eye
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function template(scale)
	local t = templates[scale]
	if not t then
		t = buildRig(scale)
		templates[scale] = t
	end
	return t
end

local function pick(list)
	return list[math.random(#list)]
end

-- Flat on the floor on its arms. Clients draw the same pose (EndlessFx); setting it here too moves
-- the server's parts, so a crawler's torso and head are hit where they are seen, not standing up.
-- (Motor6D.Transform does not replicate; each side sets its own.)
local CRAWL = CFrame.new(0, 0, -1.9) * CFrame.Angles(math.rad(78), 0, 0)
local function crawlPose(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local joint = root and root:FindFirstChild("RootJoint")
	if joint then
		joint.Transform = CRAWL
	end
end

local function dress(model, kind)
	local skin = if kind == "Brute" then Color3.fromRGB(86, 96, 78) else pick(ZOMBIE.Skin)
	local shirt, pants = pick(ZOMBIE.Shirt), pick(ZOMBIE.Pants)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			if p.Name == "Torso" then
				p.Color = shirt
				p.Material = Enum.Material.Fabric
			elseif p.Name == "Left Leg" or p.Name == "Right Leg" then
				p.Color = pants
				p.Material = Enum.Material.Fabric
			elseif p.Name == "Eye" then
				p.Color = if kind == "Runner" or kind == "Brute" then ZOMBIE.RunnerEyes else ZOMBIE.Eyes
			elseif p.Name ~= "HumanoidRootPart" then
				p.Color = skin
			end
		end
	end
end

-- Helpers ---------------------------------------------------------------------------------------

local function isAlive(z)
	return z.Model.Parent ~= nil and z.Humanoid.Health > 0 and alive[z.Model] == z
end

local function hold(z, time)
	local t = 0
	while t < time do
		t += task.wait(math.min(NAV.Tick, time - t + 0.01))
		if not isAlive(z) then
			return false
		end
	end
	return true
end

-- Humanoid:MoveTo gives up after 8 s, and the very same point again doesn't restart it.
local function walkTo(z, pos)
	local h = z.Humanoid
	if (h.WalkToPoint - pos).Magnitude < 0.05 then
		pos += Vector3.new(0.1, 0, 0)
	end
	h:MoveTo(pos)
end

local function stand(z)
	z.Humanoid:MoveTo(z.Root.Position)
end

local function face(z, pos)
	local to = Util.Flat(pos - z.Root.Position)
	if to.Magnitude > 0.1 and not z.Root.Anchored then
		z.Root.CFrame = CFrame.lookAt(z.Root.Position, z.Root.Position + to)
	end
end

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude

local function sees(z, target: BasePart)
	local ignore = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local fx = workspace:FindFirstChild("Fx")
	if fx then
		table.insert(ignore, fx)
	end
	sightParams.FilterDescendantsInstances = ignore
	local from = z.Root.Position + Vector3.new(0, 1.2 * z.Scale, 0)
	return workspace:Raycast(from, target.Position - from, sightParams) == nil
end

-- The nearest standing player.
local function nearest(from: Vector3)
	local best, bestRoot, bestD = nil, nil, math.huge
	for _, p in Survivors.StandingPlayers() do
		local _, _, root = Survivors.Parts(p)
		if root then
			local d = (root.Position - from).Magnitude
			if d < bestD then
				best, bestRoot, bestD = p, root, d
			end
		end
	end
	return best, bestRoot, bestD
end

local function rootHeight(z)
	return 3 * z.Scale
end

-- Anchored carry along a curve (rising, climbing walls and sills). Returns false if it died.
local function carry(z, to: Vector3, time: number, over: Vector3?)
	local root = z.Root
	local from = root.Position
	local control = if over then over * 2 - (from + to) / 2 else (from + to) / 2
	local facing = Util.Flat(to - from)
	local rot = if facing.Magnitude > 0.1 then CFrame.lookAt(Vector3.zero, facing.Unit) else root.CFrame.Rotation
	root.Anchored = true
	local t = 0
	while t < 1 do
		t = math.min(t + RunService.Heartbeat:Wait() / time, 1)
		if not isAlive(z) then
			return false
		end
		local a = from:Lerp(control, t)
		local b = control:Lerp(to, t)
		root.CFrame = CFrame.new(a:Lerp(b, t)) * rot
	end
	return true
end

local function release(z)
	z.Root.Anchored = false
	pcall(z.Root.SetNetworkOwner, z.Root, nil)
end

-- The swipe.
local function swing(z, player)
	local _, _, target = Survivors.Parts(player)
	if not target then
		return
	end
	if not z.Root.Anchored then
		stand(z)
		face(z, target.Position)
	end
	z.Model:SetAttribute("SwingAt", workspace:GetServerTimeNow())
	if not hold(z, ATTACK.Windup) then
		return
	end
	Sfx.Play(SOUNDS .. "/Swing", { Position = z.Root.Position })
	if not hold(z, ATTACK.Swing) then
		return
	end
	z.ReadyAt = os.clock() + ATTACK.Cooldown
	local to = target.Position - z.Root.Position
	local flat = Util.Flat(to)
	local look = Util.Flat(z.Root.CFrame.LookVector)
	local inArc = flat.Magnitude < 0.5 or look.Magnitude < 0.1 or look.Unit:Dot(flat.Unit) >= math.cos(math.rad(ATTACK.Arc / 2))
	local reach = ATTACK.Reach * z.Scale + (if z.Window then 2 else 0)
	if to.Magnitude <= reach and inArc and target.Parent then
		Survivors.Damage(player, z.Damage)
	end
end

local function ready(z)
	return os.clock() >= (z.ReadyAt or 0)
end

-- Phases ----------------------------------------------------------------------------------------

-- Up out of the yard (from depth studs down) or a floor hatch. A hatch is a hole in a 1-stud floor
-- with a room under it, so it starts only waist-deep: the legs must not hang out of the ceiling below.
local function rise(z, at: Vector3, depth: number)
	local h = rootHeight(z)
	z.Root.CFrame = CFrame.new(at + Vector3.new(0, h - depth * z.Scale, 0)) * z.Root.CFrame.Rotation
	z.Root.Anchored = true
	Sfx.Play(SOUNDS .. "/Idle", { Position = at })
	local ok = carry(z, at + Vector3.new(0, h, 0), ZOMBIE.Emerge)
	if ok then
		release(z)
	end
	return ok
end

-- A standing player holding this window from inside, close enough to swipe.
local function defender(window)
	for _, p in Survivors.StandingPlayers() do
		local _, _, root = Survivors.Parts(p)
		if root and (root.Position - (window.Inside + Vector3.new(0, 3, 0))).Magnitude < 7 then
			return p
		end
	end
	return nil
end

local function approach(z)
	local window = z.Window
	local side = Vector3.new(-window.Normal.Z, 0, window.Normal.X)
	local spot = window.Outside + side * (math.random() * 3 - 1.5) + Vector3.new(0, rootHeight(z), 0)
	local checkPos, checkAt = z.Root.Position, os.clock()
	local started = os.clock()
	while isAlive(z) do
		if Util.Flat(spot - z.Root.Position).Magnitude < 1.8 then
			return true
		end
		walkTo(z, spot)
		if Util.Flat(z.Root.Position - checkPos).Magnitude > NAV.StuckDistance then
			checkPos, checkAt = z.Root.Position, os.clock()
		elseif os.clock() - checkAt > NAV.StuckTime * 3 then
			-- Something in the way outside: step to the window regardless.
			z.Root.CFrame = CFrame.new(spot) * z.Root.CFrame.Rotation
			checkPos, checkAt = z.Root.Position, os.clock()
		end
		if os.clock() - started > NAV.LostTime then
			return false
		end
		task.wait(NAV.Tick)
	end
	return false
end

local function breach(z)
	local window = z.Window
	local inward = -window.Normal
	if window.Perch then
		-- Up the wall to hang outside an upper window.
		local height = window.Perch.Y - z.Root.Position.Y
		if not carry(z, window.Perch, 0.5 + ZOMBIE.Window.ClimbPerStud * math.abs(height)) then
			return false
		end
		z.Root.CFrame = CFrame.lookAt(window.Perch, window.Perch + inward)
	else
		stand(z)
	end
	while isAlive(z) do
		local broken = Windows.Broken(window)
		if broken and os.clock() >= (window.ClimbFreeAt or 0) then
			return true
		end
		if not z.Root.Anchored then
			z.Root.CFrame = CFrame.lookAt(z.Root.Position, z.Root.Position + inward)
		end
		local player = defender(window)
		if player and ready(z) then
			swing(z, player)
		elseif not broken then
			z.Model:SetAttribute("SwingAt", workspace:GetServerTimeNow())
			if not hold(z, 0.35) then
				return false
			end
			Windows.Rip(window, z.Root.Position)
			local delay = ZOMBIE.Window.BreakDelay
			if not hold(z, delay.Min + math.random() * (delay.Max - delay.Min)) then
				return false
			end
		elseif not hold(z, 0.3) then
			return false
		end
	end
	return false
end

local function climbIn(z)
	local window = z.Window
	local h = rootHeight(z)
	local time = ZOMBIE.Window.ClimbTime
	window.ClimbFreeAt = os.clock() + time + 0.25
	local over = Vector3.new(window.Center.X, window.SillTop + h * 0.6, window.Center.Z)
	if not carry(z, window.Inside + Vector3.new(0, h, 0), time, over) then
		return false
	end
	release(z)
	window.Load = math.max(0, window.Load - 1)
	z.Window = nil
	return true
end

local function hunt(z)
	local scale = z.Scale
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.5 * scale,
		AgentHeight = 5 * scale,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})
	local waypoints, index, pathAt, pathGoal = nil, 0, 0, nil
	local checkPos, checkAt = z.Root.Position, os.clock()
	local lastProgress = os.clock()
	local aggro = false
	while isAlive(z) do
		local root = z.Root
		local player, target, dist = nearest(root.Position)
		local moving = false
		if target then
			if not aggro then
				aggro = true
				Sfx.Play(SOUNDS .. "/Aggro", { Position = root.Position })
			end
			local dy = math.abs(target.Position.Y - root.Position.Y)
			local range = ATTACK.Range * scale
			local inSight = dist <= NAV.DirectRange and dy < 5 and sees(z, target)
			if dist <= range and inSight then
				if ready(z) then
					swing(z, player)
				else
					stand(z)
				end
				lastProgress = os.clock()
			else
				local goal = target.Position
				if not inSight then
					-- A new path at most every Repath seconds (a failed one too, or a stuck zombie
					-- would ask for one every tick).
					if os.clock() - pathAt > NAV.Repath and (not waypoints or (target.Position - pathGoal).Magnitude > 4) then
						pathAt, pathGoal = os.clock(), target.Position
						local ok = pcall(path.ComputeAsync, path, root.Position, target.Position)
						if ok and path.Status == Enum.PathStatus.Success then
							waypoints, index = path:GetWaypoints(), 2
						else
							waypoints = nil
						end
					end
					if waypoints then
						while waypoints[index + 1] and Util.Flat(waypoints[index].Position - root.Position).Magnitude < 2.5 do
							index += 1
						end
						if waypoints[index] then
							goal = waypoints[index].Position
						end
					end
				else
					waypoints = nil
				end
				walkTo(z, goal)
				moving = true
			end
		else
			stand(z)
			lastProgress = os.clock()
		end
		-- Stuck: shuffle aside and repath; no headway at all for LostTime and it's taken away.
		if moving then
			if Util.Flat(root.Position - checkPos).Magnitude > NAV.StuckDistance then
				checkPos, checkAt = root.Position, os.clock()
				lastProgress = os.clock()
			elseif os.clock() - checkAt > NAV.StuckTime then
				local look = Util.Flat(root.CFrame.LookVector)
				local aside = Vector3.new(-look.Z, 0, look.X) * (if math.random() < 0.5 then -1 else 1)
				walkTo(z, root.Position + aside * 3 - look)
				hold(z, 0.5)
				waypoints = nil
				checkPos, checkAt = root.Position, os.clock()
			end
			if os.clock() - lastProgress > NAV.LostTime then
				Horde.Remove(z.Model, true)
				return
			end
		end
		task.wait(NAV.Tick)
	end
end

local function brain(z)
	local entry = z.Entry
	if entry.Window then
		if not rise(z, entry.Window.Spawn, 4.5) then
			return
		end
		if not approach(z) then
			if isAlive(z) then
				Horde.Remove(z.Model, true)
			end
			return
		end
		if not breach(z) or not climbIn(z) then
			return
		end
	elseif not rise(z, entry.Hatch.Position, 2) then
		return
	end
	hunt(z)
end

-- Spawning ---------------------------------------------------------------------------------------

function Horde.Count(): number
	return count
end

-- entry: {Window = window} or {Hatch = hatch}. kind: Walker, Runner, Brute, Crawler.
function Horde.Spawn(entry, kind: string, health: number, speed: number)
	local scale = if kind == "Brute" then BRUTE.Scale else 1
	local model = template(scale):Clone()
	dress(model, kind)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = speed
	model:SetAttribute("Kind", kind)
	local z = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Kind = kind,
		Scale = scale,
		MaxHealth = health,
		Damage = if kind == "Brute" then BRUTE.Damage else ATTACK.Damage,
		Limb = {},
		ArmsLost = 0,
		LegsLost = 0,
		Entry = entry,
		Window = entry.Window,
	}
	if kind == "Crawler" then
		z.LegsLost = 2
		z.Damage *= 0.7
		model:SetAttribute("Crawling", true)
		for _, name in { "Left Leg", "Right Leg" } do
			local leg = model:FindFirstChild(name)
			leg.Transparency = 1
			leg.CanQuery = false
		end
		crawlPose(model)
	end
	if entry.Window then
		entry.Window.Load += 1
	end
	alive[model] = z
	count += 1
	local at = if entry.Window then entry.Window.Spawn else entry.Hatch.Position
	root.CFrame = CFrame.new(at - Vector3.new(0, 6, 0))
	root.Anchored = true -- held until it has risen (brain)
	model.Parent = folder
	humanoid.Died:Once(function()
		if alive[model] == z then
			Horde.Remove(model, false)
		end
	end)
	task.spawn(brain, z)
	return model
end

-- Takes a zombie out of the count. lost: it was stuck, not killed (the round owes one more).
function Horde.Remove(model: Model, lost: boolean)
	local z = alive[model]
	if not z then
		return
	end
	alive[model] = nil
	count -= 1
	if z.Window then
		z.Window.Load = math.max(0, z.Window.Load - 1)
	end
	if lost then
		model:Destroy()
		Horde.Lost:Fire()
	end
end

-- Damage and death -------------------------------------------------------------------------------

local function fxFolder()
	return workspace:FindFirstChild("Fx") or workspace
end

local function tear(z, part, dir)
	if part.Transparency >= 1 then
		return
	end
	local loose = part:Clone()
	loose:ClearAllChildren()
	loose.Anchored = false
	loose.CanCollide = true
	loose.CanQuery = false
	loose.CollisionGroup = "Corpses"
	loose.Parent = fxFolder()
	loose.AssemblyLinearVelocity = (dir or Vector3.zero) * 18 + Vector3.new(0, 10, 0)
	loose.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 16
	Debris:AddItem(loose, 8)
	part.Transparency = 1
	part.CanQuery = false
	Net.Get("Fx"):FireAllClients("Gib", part.Position)
	if LIMBS[part.Name] == "Arm" then
		z.ArmsLost += 1
		z.Damage *= ATTACK.ArmLost
	else
		z.LegsLost += 1
		if z.LegsLost >= 2 and not z.Model:GetAttribute("Crawling") then
			z.Model:SetAttribute("Crawling", true)
			z.Humanoid.WalkSpeed *= ZOMBIE.CrawlSpeed
			z.Damage *= 0.7
			crawlPose(z.Model)
		end
	end
end

local function ragdoll(model, push)
	for _, m in model:GetDescendants() do
		if m:IsA("Motor6D") then
			local a0 = Instance.new("Attachment")
			a0.CFrame = m.C0
			a0.Parent = m.Part0
			local a1 = Instance.new("Attachment")
			a1.CFrame = m.C1
			a1.Parent = m.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 70
			socket.Parent = m.Part0
			m:Destroy()
		end
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Corpses"
			p.CanCollide = p.Name ~= "HumanoidRootPart" and p.Name ~= "Eye" and p.Transparency < 1
			p.CanQuery = false
			p.Anchored = false
		end
	end
	local root = model.PrimaryPart
	if root then
		pcall(root.SetNetworkOwner, root, nil)
		root.AssemblyLinearVelocity = push * 14 + Vector3.new(0, 6, 0)
	end
end

local function die(z, killer, info)
	local model = z.Model
	Horde.Remove(model, false)
	model:SetAttribute("Dead", true)
	info.Kind = z.Kind
	info.Position = z.Root.Position
	Sfx.Play(SOUNDS .. "/Death", { Position = z.Root.Position })
	ragdoll(model, info.Direction or Vector3.zero)
	Horde.Killed:Fire(model, killer, info)
	task.delay(ZOMBIE.CorpseTime, function()
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				TweenService:Create(p, TweenInfo.new(1), { Transparency = 1 }):Play()
			end
		end
		task.wait(1.1)
		model:Destroy()
	end)
end

-- Hurts a zombie. opts: {Head, Melee, Direction}. Returns killed, damage dealt.
function Horde.Damage(model: Model, amount: number, part: BasePart?, killer: Player?, opts)
	local z = alive[model]
	if not z or z.Humanoid.Health <= 0 then
		return false, 0
	end
	opts = opts or {}
	if (workspace:GetAttribute("ReaperUntil") or 0) > workspace:GetServerTimeNow() then
		-- REAPER: anything dies in one hit, a brute takes four times the damage.
		amount = if z.Kind == "Brute" then amount * 4 else z.Humanoid.Health
	end
	local dealt = math.min(amount, z.Humanoid.Health)
	z.Humanoid.Health -= dealt
	local at = if part then part.Position else z.Root.Position
	-- Less on faces (owner rule): a headshot sprays half as much.
	Net.Get("Fx"):FireAllClients("Blood", at, opts.Direction or Vector3.zero, if opts.Head then 0.5 else 1)
	if part and LIMBS[part.Name] and z.Humanoid.Health > 0 then
		z.Limb[part.Name] = (z.Limb[part.Name] or 0) + amount
		local share = if LIMBS[part.Name] == "Arm" then ZOMBIE.ArmShare else ZOMBIE.LegShare
		if z.Limb[part.Name] >= share * z.MaxHealth then
			tear(z, part, opts.Direction)
		end
	end
	if z.Humanoid.Health <= 0 then
		die(z, killer, { Head = opts.Head == true, Melee = opts.Melee == true, Direction = opts.Direction })
		return true, dealt
	end
	if math.random() < 0.3 then
		Sfx.Play(SOUNDS .. "/Hurt", { Position = z.Root.Position, Volume = 0.8 })
	end
	return false, dealt
end

-- PURGE: every zombie standing dies (no points each, Call of Duty's nuke).
function Horde.KillAll()
	for model, z in alive do
		if z.Humanoid.Health > 0 then
			z.Humanoid.Health = 0
			die(z, nil, { Purge = true })
		end
	end
end

-- Run over: every zombie and corpse goes.
function Horde.Clear()
	for model in alive do
		model:Destroy()
	end
	table.clear(alive)
	count = 0
	folder:ClearAllChildren()
end

-- Zombies that fell out of the world go back in the queue.
local function sweep()
	while true do
		task.wait(2)
		for model, z in alive do
			if z.Root.Position.Y < -80 then
				Horde.Remove(model, true)
			end
		end
	end
end

function Horde.Start()
	folder = workspace:FindFirstChild("Zombies") or Instance.new("Folder")
	folder.Name = "Zombies"
	folder.Parent = workspace
	template(1)
	template(BRUTE.Scale)
	task.spawn(sweep)
end

return Horde
