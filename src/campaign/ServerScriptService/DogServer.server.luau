local CAMPAIGN_K9 = false -- 4 Nov 2026: K9 is a zombie-modes partner only; no police dog in the campaign (zombie dog packs unaffected)
-- The dogs (numbers: GameConfig.Dog and GameConfig.ZombieDogs; bones posed by StarterPlayerScripts.DogClient).
--   The squad's police dog: one per match while anyone is in it. It trots at the heel of the player it follows
--   (the first one in; the next one if they leave or die), runs to catch up, and is brought back behind them
--   when it falls far behind or gets stuck. A zombie (or zombie dog) within Guard of that player gets chased
--   and bitten (MobReactions.Hit, credited to the player, GunName "Dog", so no bullet wounds; its KillAt
--   attribute makes the squad say "GoodDog"). It lies flat while they hide, sits when they stand still,
--   whimpers by them while they're down, barks at the Beacon, and when they die it goes to the body, sits
--   and howls (HowlTime) before it goes on to the next player. Nothing hurts it.
--   Zombie dogs: packs from night ZombieDogs.FromNight while a night runs, out of the town spawns, running
--   down the nearest player who isn't hiding. Tag Enemy, Kind Dog (the squad calls out "Dogs"), in
--   workspace.Zombies; guns kill them like any zombie.
-- Both are the imported models in ServerStorage.Dogs (Dog, ZombieDog): skinned meshes with bones. Each gets
-- an invisible HumanoidRootPart and a Humanoid here; clients pose the bones from the dog's speed and its Pose
-- attribute (Sit, Flat, Bark, Bite, Whimper, Lie). The police dog also carries Partner, the UserId of the player at
-- its heel (kept through the howl), which PlayerHealthClient reads for the death cam. Until the models are imported
-- this does nothing.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local MobReactions = require(ServerStorage.Modules.MobReactions)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)

local CFG = GameConfig.Dog
local ZCFG = GameConfig.ZombieDogs
local GROUP = "Dogs"
local TICK = 0.15

-- Dogs walk through players (never shove them) but not through walls.
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP)
end)
PhysicsService:CollisionGroupSetCollidable(GROUP, "Characters", false)
PhysicsService:CollisionGroupSetCollidable(GROUP, "Debris", false)
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)

local dogsFolder = Instance.new("Folder")
dogsFolder.Name = "Dogs"
dogsFolder.Parent = workspace
local zombies = workspace:WaitForChild("Zombies")
local spawns = workspace:WaitForChild("Map"):WaitForChild("ZombieSpawns")

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function between(range): number
	return range.Min + math.random() * (range.Max - range.Min)
end

-- The imported model: ServerStorage.Dogs[name], or one of that name still where Import 3D put it.
local store = ServerStorage:FindFirstChild("Dogs")
local function template(name: string): Model?
	local found = store and store:FindFirstChild(name)
	if not found then
		local loose = workspace:FindFirstChild(name)
		if loose and loose:IsA("Model") and loose:FindFirstChildWhichIsA("Bone", true) then
			if not store then
				store = Instance.new("Folder")
				store.Name = "Dogs"
				store.Parent = ServerStorage
			end
			loose.Parent = store
			found = loose
		end
	end
	return found :: Model?
end

local function groundBelow(pos: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.CollisionGroup = GROUP
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	return if hit then hit.Position else pos
end

export type Dog = {
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Params: RaycastParams,
	Waypoints: { PathWaypoint }?,
	Wp: number,
	PathAt: number,
	PathGoal: Vector3,
	MovedAt: number,
	MovedFrom: Vector3,
	Target: Model?,
	LastBite: number,
	NextBark: number,
	NextWhine: number,
	LeaderPos: Vector3,
	LeaderStill: number,
	Busy: boolean,
	Moving: boolean,
	Following: Model?, -- the character it was at the heel of, last tick
	HowlUntil: number,
	HowlAt: Vector3,
	NextHowl: number,
}

-- The world box round the parts you can see. Import 3D adds an invisible 2x2x1 RootPart round the paws (the bones
-- hang off it), and counting it would stand the dog a stud off the floor.
local function visibleBox(model: Model): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf, h = p.CFrame, p.Size / 2
			local ext = Vector3.new(
				math.abs(cf.XVector.X) * h.X + math.abs(cf.YVector.X) * h.Y + math.abs(cf.ZVector.X) * h.Z,
				math.abs(cf.XVector.Y) * h.X + math.abs(cf.YVector.Y) * h.Y + math.abs(cf.ZVector.Y) * h.Z,
				math.abs(cf.XVector.Z) * h.X + math.abs(cf.YVector.Z) * h.Y + math.abs(cf.ZVector.Z) * h.Z
			)
			lo, hi = lo:Min(cf.Position - ext), hi:Max(cf.Position + ext)
		end
	end
	return (lo + hi) / 2, hi - lo
end

-- A dog from an imported model, standing at ground (a point on the floor) facing along facing.
local function build(source: Model, ground: Vector3, facing: Vector3, parent: Instance): Dog
	local model = source:Clone()
	local head, tail
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
			d.CollisionGroup = GROUP
		elseif d:IsA("Bone") then
			if d.Name == "Head" then
				head = d
			elseif d.Name == "Tail1" then
				tail = d
			end
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local mid, size = visibleBox(model)
	local along = if head and tail then flat(head.WorldPosition - tail.WorldPosition) else Vector3.zero
	if along.Magnitude < 0.1 then
		along = -Vector3.zAxis
	end
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(1.2, 1, 3)
	root.Transparency = 1
	root.CanTouch = false
	root.CanQuery = false
	root.CollisionGroup = GROUP
	local centre = Vector3.new(mid.X, mid.Y - size.Y / 2 + CFG.HipHeight + root.Size.Y / 2, mid.Z)
	root.CFrame = CFrame.lookAt(centre, centre + along.Unit)
	root.Parent = model
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = root
		end
	end
	model.PrimaryPart = root
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = CFG.HipHeight
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	model:SetAttribute("Dog", true)
	model.Parent = parent
	local up = CFG.HipHeight + root.Size.Y / 2
	model:PivotTo(CFrame.lookAt(ground + Vector3.new(0, up, 0), ground + Vector3.new(facing.X, up, facing.Z)))
	root:SetNetworkOwner(nil)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, dogsFolder, zombies }
	params.CollisionGroup = GROUP
	return {
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Params = params,
		Waypoints = nil,
		Wp = 0,
		PathAt = 0,
		PathGoal = Vector3.zero,
		MovedAt = os.clock(),
		MovedFrom = root.Position,
		Target = nil,
		LastBite = 0,
		NextBark = 0,
		NextWhine = 0,
		LeaderPos = Vector3.zero,
		LeaderStill = os.clock(),
		Busy = false,
		Moving = false,
		Following = nil,
		HowlUntil = 0,
		HowlAt = Vector3.zero,
		NextHowl = 0,
	}
end

-- Runs at goal: straight there when the way is clear, along a path when a wall is in the way.
local function moveTo(d: Dog, goal: Vector3, speed: number)
	local humanoid, pos = d.Humanoid, d.Root.Position
	humanoid.WalkSpeed = speed
	d.Moving = true
	local to = flat(goal - pos)
	if to.Magnitude < 1 then
		d.Waypoints = nil
		humanoid:MoveTo(pos)
		return
	end
	if not workspace:Raycast(pos, to, d.Params) then
		d.Waypoints = nil
		humanoid:MoveTo(goal)
		return
	end
	if not d.Waypoints or os.clock() - d.PathAt > 1.2 or (d.PathGoal - goal).Magnitude > 5 then
		d.PathAt, d.PathGoal = os.clock(), goal
		local path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 3, AgentCanJump = true, WaypointSpacing = 4 })
		local ok = pcall(function()
			path:ComputeAsync(pos, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			d.Waypoints, d.Wp = path:GetWaypoints(), 2
		else
			d.Waypoints = nil
			humanoid:MoveTo(goal)
			return
		end
	end
	local wps = d.Waypoints :: { PathWaypoint }
	while d.Wp <= #wps and flat(wps[d.Wp].Position - d.Root.Position).Magnitude < 2.5 do
		d.Wp += 1
	end
	local wp = wps[d.Wp]
	if wp then
		if wp.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(wp.Position)
	else
		humanoid:MoveTo(goal)
	end
end

local function stop(d: Dog, face: Vector3?)
	d.Waypoints = nil
	d.Moving = false
	d.Humanoid:MoveTo(d.Root.Position)
	if face then
		local pos = d.Root.Position
		local look = flat(face - pos)
		if look.Magnitude > 0.5 then
			d.Root.CFrame = CFrame.lookAt(pos, pos + look)
		end
	end
end

local function alive(m: Model?): boolean
	local humanoid = m and m:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and m.Parent ~= nil and m.PrimaryPart ~= nil and not m:GetAttribute("Dead")
end

local function nearestEnemy(point: Vector3, range: number): Model?
	local best, bestDist = nil, range
	for _, m in CollectionService:GetTagged("Enemy") do
		if m:IsA("Model") and m:IsDescendantOf(workspace) and alive(m) then
			local dist = (m.PrimaryPart.Position - point).Magnitude
			if dist < bestDist then
				best, bestDist = m, dist
			end
		end
	end
	return best
end

-- A player who is in the match and alive: their root and character.
local function playing(p: Player): (BasePart?, Model?)
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if p:GetAttribute("InMatch") and humanoid and humanoid.Health > 0 and root then
		return root :: BasePart, character
	end
	return nil, nil
end

-- The police dog ------------------------------------------------------------------------------

local police: Dog? = nil
local leader: Player? = nil

local function behind(root: BasePart, ignore: { Instance }): Vector3
	return groundBelow((root.CFrame * CFrame.new(2.5, 0, CFG.Heel)).Position, ignore)
end

local function bringBack(d: Dog, root: BasePart, character: Model)
	local at = behind(root, { d.Model, character })
	local up = CFG.HipHeight + d.Root.Size.Y / 2
	d.Model:PivotTo(CFrame.lookAt(at + Vector3.new(0, up, 0), at + Vector3.new(0, up, 0) + root.CFrame.LookVector))
	d.Waypoints = nil
	d.Target = nil -- a zombie it couldn't reach is left to the guns
	d.MovedAt, d.MovedFrom = os.clock(), d.Root.Position
end

local function bite(d: Dog, target: Model, by: Player)
	local tr = target.PrimaryPart :: BasePart
	local part = target:FindFirstChild("UpperTorso") or target:FindFirstChild("Torso") or tr
	local dir = flat(tr.Position - d.Root.Position)
	dir = if dir.Magnitude > 0.01 then dir.Unit else d.Root.CFrame.LookVector
	local at = (part :: BasePart).Position - dir * 0.6
	d.Model:SetAttribute("BiteAt", workspace:GetServerTimeNow())
	SoundKit.Play("Dog/Growl", { Position = d.Root.Position })
	local ok, killed = pcall(MobReactions.Hit, target, { { Part = part, Damage = CFG.BiteDamage, Pos = at, IsHead = false } }, {
		Player = by,
		Gun = { Feel = {} },
		GunName = "Dog",
		HitPos = at,
		Dir = dir,
		Distance = 2,
		Share = 1,
	})
	if ok and killed then
		d.Model:SetAttribute("KillAt", workspace:GetServerTimeNow())
	end
end

local function pickLeader(): (Player?, BasePart?, Model?)
	if leader and leader.Parent then
		local root, character = playing(leader)
		if root then
			return leader, root, character
		end
	end
	for _, p in Players:GetPlayers() do
		local root, character = playing(p)
		if root then
			return p, root, character
		end
	end
	return nil, nil, nil
end

-- Where it sits to howl: beside the body, on the side it comes from.
local function howlSpot(d: Dog): Vector3
	local away = flat(d.Root.Position - d.HowlAt)
	return if away.Magnitude > 0.1 then d.HowlAt + away.Unit * 2.5 else d.Root.Position
end

-- Brought to that spot at once, facing the body (like bringBack).
local function toBody(d: Dog)
	local at = groundBelow(howlSpot(d), { d.Model, dogsFolder, zombies })
	local up = CFG.HipHeight + d.Root.Size.Y / 2
	d.Model:PivotTo(CFrame.lookAt(at + Vector3.new(0, up, 0), Vector3.new(d.HowlAt.X, at.Y + up, d.HowlAt.Z)))
	d.Waypoints = nil
end

-- The player at its heel last tick has died: time to howl. (Checked before anything decides the match is
-- empty, or the dog would be gone before it noticed.)
local function noticeDeath(d: Dog, now: number)
	local was = d.Following
	if not was then
		return
	end
	local humanoid = was:FindFirstChildOfClass("Humanoid")
	local body = was:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health <= 0 and body then
		d.Following, d.Target = nil, nil
		d.HowlUntil, d.HowlAt, d.NextHowl = now + CFG.HowlTime, (body :: BasePart).Position, now + 0.4
		if flat(d.Root.Position - d.HowlAt).Magnitude > CFG.HowlReach then
			toBody(d)
		end
	elseif not was.Parent then
		d.Following = nil -- gone alive (an escape, back to the menu): no howl
	end
end

-- Its player has died: it runs to the body, sits beside it facing them and howls.
local function howlTick(d: Dog, now: number)
	local pos = d.Root.Position
	local spot = howlSpot(d)
	if flat(spot - pos).Magnitude > 1.5 and now < d.HowlUntil - CFG.HowlTime + 3 then
		moveTo(d, spot, CFG.RunSpeed)
		d.Model:SetAttribute("Pose", nil)
		return
	end
	if flat(spot - pos).Magnitude > 3 then
		toBody(d) -- couldn't get there in time (a shut door, no path)
	end
	stop(d, d.HowlAt)
	d.Model:SetAttribute("Pose", "Howl")
	if now >= d.NextHowl then
		d.NextHowl = now + CFG.HowlGap
		SoundKit.Play("Dog/Howl", { Position = d.Root.Position })
	end
end

local function policeTick(d: Dog)
	local now = os.clock()
	if now < d.HowlUntil then
		howlTick(d, now)
		return
	end

	local who, lr, lc = pickLeader()
	leader = who
	if not who or not lr or not lc then
		stop(d)
		d.Model:SetAttribute("Pose", "Sit")
		d.Model:SetAttribute("Partner", nil)
		return
	end
	d.Following = lc
	d.Model:SetAttribute("Partner", who.UserId)
	local pos = d.Root.Position
	if (lr.Position - pos).Magnitude > CFG.Teleport then
		bringBack(d, lr, lc)
		return
	end
	if flat(lr.Position - d.LeaderPos).Magnitude > 1 then
		d.LeaderPos, d.LeaderStill = lr.Position, now
	end

	local hiding = lc:GetAttribute("Hiding") == true
	local downed = lc:GetAttribute("Downed") == true
	local pose = nil
	local target = d.Target
	if target and (hiding or not alive(target) or (target.PrimaryPart.Position - lr.Position).Magnitude > CFG.Leash) then
		target = nil
	end
	if not target and not hiding then
		target = nearestEnemy(lr.Position, CFG.Guard)
		if target then
			SoundKit.Play("Dog/Bark", { Position = pos })
		end
	end
	d.Target = target

	if target then
		local tp = target.PrimaryPart.Position
		if flat(tp - pos).Magnitude > CFG.BiteRange then
			moveTo(d, tp, CFG.RunSpeed)
		else
			stop(d, tp)
			if now - d.LastBite >= CFG.BiteGap then
				d.LastBite = now
				bite(d, target, who)
			end
		end
	elseif hiding then
		-- down beside them, out of the lamps
		local spot = lr.Position + lr.CFrame.RightVector * 2.5
		if flat(spot - pos).Magnitude > 2.5 then
			moveTo(d, spot, CFG.RunSpeed)
		else
			stop(d)
			pose = "Flat"
		end
	else
		local heel = (lr.CFrame * CFrame.new(2.5, 0, CFG.Heel)).Position
		local dist = flat(heel - pos).Magnitude
		if dist > 2.5 then
			moveTo(d, heel, if dist > CFG.CatchUp then CFG.RunSpeed else CFG.WalkSpeed)
		else
			stop(d)
			if downed then
				pose = "Whimper"
				if now >= d.NextWhine then
					d.NextWhine = now + 4 + math.random() * 4
					SoundKit.Play("Dog/Whine", { Position = pos })
				end
			elseif now - d.LeaderStill > CFG.SitAfter then
				pose = "Sit"
			end
		end
	end

	-- it barks at the Beacon (never while they hide: that would give them away)
	local beacon = workspace:FindFirstChild("Beacon")
	local bp = beacon and beacon:IsA("Model") and beacon.PrimaryPart
	if bp and not hiding and now >= d.NextBark and (bp.Position - pos).Magnitude < CFG.BarkRange then
		d.NextBark = now + between(CFG.BarkGap)
		SoundKit.Play("Dog/Bark", { Position = pos })
		if not target and not d.Moving then
			pose = "Bark"
		end
	end
	d.Model:SetAttribute("Pose", pose)

	-- stuck: trying to get somewhere but not getting anywhere (a wall, a shut door, no path)
	if not d.Moving or (d.Root.Position - d.MovedFrom).Magnitude > 1.5 then
		d.MovedAt, d.MovedFrom = now, d.Root.Position
	elseif now - d.MovedAt > CFG.StuckTime then
		bringBack(d, lr, lc)
	end
end

-- Zombie dogs ---------------------------------------------------------------------------------

local pack: { [Model]: Dog } = {}
local packCount = 0

local function preyFor(pos: Vector3): (Player?, BasePart?)
	local best, bestRoot, bestDist = nil, nil, math.huge
	for _, p in Players:GetPlayers() do
		local root, character = playing(p)
		if root and character and not character:GetAttribute("Hiding") and not PlayerHealth.IsDowned(p) then
			local dist = (root.Position - pos).Magnitude
			if dist < bestDist then
				best, bestRoot, bestDist = p, root, dist
			end
		end
	end
	return best, bestRoot
end

local function zombieTick(d: Dog)
	local prey, pr = preyFor(d.Root.Position)
	local pose = nil
	if prey and pr then
		local pos = d.Root.Position
		if flat(pr.Position - pos).Magnitude > ZCFG.BiteRange then
			moveTo(d, pr.Position, ZCFG.Speed)
			-- snarls on the run, so a pack is heard before it is seen (throttled per dog, 5 Nov 2026)
			local now = os.clock()
			if now >= d.NextBark then
				d.NextBark = now + 2.5 + math.random() * 3
				SoundKit.Play(if math.random() < 0.65 then "ZombieDog/Growl" else "ZombieDog/Bark", { Position = pos })
			end
		else
			stop(d, pr.Position)
			local now = os.clock()
			if now - d.LastBite >= ZCFG.BiteGap then
				d.LastBite = now
				d.Model:SetAttribute("BiteAt", workspace:GetServerTimeNow())
				SoundKit.Play("ZombieDog/Attack", { Position = pos })
				PlayerHealth.Damage(prey, ZCFG.BiteDamage, pos, "Dog")
			end
		end
	else
		stop(d)
		pose = "Sniff"
	end
	d.Model:SetAttribute("Pose", pose)
end

local function zombieDied(d: Dog)
	local model = d.Model
	if pack[model] then
		pack[model] = nil
		packCount -= 1
	end
	model:SetAttribute("Dead", true)
	model:SetAttribute("Pose", "Lie")
	CollectionService:RemoveTag(model, "Enemy")
	SoundKit.Play("ZombieDog/Yowl", { Position = d.Root.Position })
	-- over on its side where it fell
	d.Root.Anchored = true
	local cf = d.Root.CFrame
	d.Root.CFrame = cf * CFrame.new(0, -0.9, 0) * CFrame.Angles(0, 0, math.rad(80))
	task.delay(ZCFG.CorpseTime, function()
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p ~= d.Root then
				TweenService:Create(p, TweenInfo.new(1), { Transparency = 1 }):Play()
			end
		end
		task.delay(1.1, function()
			model:Destroy()
		end)
	end)
end

local function spawnPack(source: Model)
	local town = spawns:FindFirstChild("Town")
	if not town then
		return
	end
	local far = {}
	for _, spot in town:GetChildren() do
		if spot:IsA("BasePart") then
			local near = math.huge
			for _, p in Players:GetPlayers() do
				local root = playing(p)
				if root then
					near = math.min(near, (root.Position - spot.Position).Magnitude)
				end
			end
			if near >= ZCFG.SpawnAway then
				table.insert(far, spot)
			end
		end
	end
	if #far == 0 then
		return
	end
	local spot = far[math.random(#far)]
	local count = math.random(ZCFG.Pack.Min, ZCFG.Pack.Max)
	count = math.min(count, ZCFG.MaxAlive - packCount)
	for i = 1, count do
		local offset = Vector3.new(math.random() * 6 - 3, 0, math.random() * 6 - 3)
		local ground = groundBelow(spot.Position + offset, { spot, dogsFolder, zombies })
		local _, pr = preyFor(ground)
		local facing = if pr then flat(pr.Position - ground) else Vector3.new(1, 0, 0)
		local d = build(source, ground, if facing.Magnitude > 0.1 then facing.Unit else Vector3.xAxis, zombies)
		local model = d.Model
		model.Name = "ZombieDog"
		model:SetAttribute("Kind", "Dog")
		model:SetAttribute("MatchMob", true)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p ~= d.Root then
				p.CanQuery = true -- guns hit the body
			end
		end
		d.Humanoid.MaxHealth = ZCFG.Health
		d.Humanoid.Health = ZCFG.Health
		CollectionService:AddTag(model, "Enemy")
		d.Humanoid.Died:Once(function()
			zombieDied(d)
		end)
		pack[model] = d
		packCount += 1
		d.NextBark = os.clock() + 2 + math.random() * 2 -- let the pack howl finish before the first snarl
		if i == 1 then
			SoundKit.Play("ZombieDog/Howl", { Position = ground })
		end
	end
end

-- The loops -----------------------------------------------------------------------------------

task.spawn(function()
	local warned = false
	local nextPack = os.clock() + between(ZCFG.Gap)
	while true do
		task.wait(TICK)
		local someone = false
		for _, p in Players:GetPlayers() do
			if playing(p) then
				someone = true
			end
		end

		-- the police dog comes in with the first player and goes when the last one leaves (after its howl)
		if police and police.Model.Parent then
			noticeDeath(police, os.clock())
		end
		if someone and not police and CAMPAIGN_K9 then
			local source = template("Dog")
			local who, lr, lc = pickLeader()
			if source and who and lr and lc then
				leader = who
				police = build(source, behind(lr, { lc, dogsFolder }), lr.CFrame.LookVector, dogsFolder)
				police.Model.Name = "PoliceDog"
				for _, p in police.Model:GetDescendants() do
					if p:IsA("BasePart") then
						p.CanQuery = false -- bullets pass by it
					end
				end
				police.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
			elseif not source and not warned then
				warned = true
				warn("DogServer: no Dog model yet (import horror-shooter/blender/out_dog/Dog.fbx)")
			end
		elseif not someone and police and os.clock() >= police.HowlUntil then
			police.Model:Destroy()
			police = nil
		end
		if police then
			if police.Model.Parent then
				policeTick(police)
			else
				police = nil
			end
		end

		-- zombie dog packs while a night runs
		local night = workspace:GetAttribute("Wave") or 0
		if someone and workspace:GetAttribute("WaveState") == "Wave" and night >= ZCFG.FromNight then
			if os.clock() >= nextPack then
				nextPack = os.clock() + between(ZCFG.Gap)
				local source = template("ZombieDog")
				if source and packCount < ZCFG.MaxAlive then
					spawnPack(source)
				end
			end
		else
			nextPack = math.max(nextPack, os.clock() + ZCFG.Gap.Min * 0.5)
		end
		for model, d in pack do
			if model.Parent and alive(model) then
				if not d.Busy then
					-- a path can take a moment to work out; one think at a time per dog
					d.Busy = true
					task.spawn(function()
						zombieTick(d)
						d.Busy = false
					end)
				end
			elseif not model.Parent then
				pack[model] = nil
				packCount -= 1
			end
		end
	end
end)
