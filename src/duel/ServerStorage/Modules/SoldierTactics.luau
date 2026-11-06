--!nocheck
-- SoldierTactics: squad tactics for WAR's soldiers, added on top of ServerStorage.Modules.Soldier
-- without replacing it. The behaviour was designed and tested in the browser sandbox
-- (prototypes/war-ai/index.html) against docs/ALLIED-AI-PROMPT.md and docs/HOSTILE-AI-PROMPT.md.
-- Install: mcp/soldier-tactics/INSTALL.md. Turn on with require(this).Install() once on the server
-- (the SoldierTacticsBoot script does that).
--
-- What it adds (each part can be switched off in TUNING.Features):
--   Bounds      A fireteam advances in two halves: one half moves while the other stays in cover and
--               fires; when the moving half has all moved (or BoundTimeout passes) they swap.
--   NoBack      An attacking soldier never re-picks cover behind itself; with nothing ahead it stays
--               and fights from where it is.
--   Flanks      Flanking only while attacking or pushing, so defenders are not pulled out of their
--               posts and dragged back again.
--   Pressure    A fireteam with the advantage (friendly soldiers within PressRadius outnumber the foes
--               it knows of, or most of those foes are hurt, pinned, reloading or caught moving in the
--               open) commits to an attack on the foes' position that follows them. It keeps at it for
--               at least PressMin seconds; a failing push goes back to its old orders and waits
--               PressCooldown; a push that clears the ground holds it.
--   Grenades    Hand grenades (most roles) and rifle grenades (one rifleman per fireteam), thrown only
--               at a foe dug in behind cover, a crew on a mounted gun, or foes bunched together; never
--               near its own side; a clear arc checked with rays; a wind-up while standing; damage
--               through WarDamage.Blast.
--   Dodge       Soldiers who see a grenade land, or hear a teammate call it, run for cover outside the
--               blast in the time left, or away from it.
--   HighGround  Marksmen and gunners (roles with RoleStats.Hold) take posts tagged "HighGround" (a part
--               where a soldier stands at an upper window or on a roof) that cover the fight.
--   Spotting    A still soldier crouched in cover is hard to see past SpotCrouch studs unless it fires.
--
-- How it hooks in (all checked at Install; a missing function turns that feature off with a warning):
--   Soldier.Spawn (fireteams, grenades), Soldier.ChooseCover (NoBack), Soldier.TakeCover (Flanks,
--   HighGround), Soldier.SetOrder (Pressure gives way to Battle's orders), Soldier.Sees (Spotting).
--   A loop every Tick seconds runs the fireteams, grenades and dodging. It reads and writes soldier
--   fields the brain already uses: Order, Phase, Cover, Entry, Dest, MoveStart, NextHop, NextPeek,
--   NextBurst, NextChoose, Known, Suppression, Reloading, Firing, Emp, Speed, Team, Role, RoleStats.
--
-- Studio: workspace attribute TacticsDebug = true prints each decision. SoldierTactics.Report() prints
-- the counters.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local SoldierTactics = {}

SoldierTactics.TUNING = {
	Features = {
		Bounds = true,
		NoBack = true,
		Flanks = true,
		Pressure = true,
		Grenades = true,
		Dodge = true,
		HighGround = true,
		Spotting = true,
	},
	Tick = 0.25, -- seconds between passes of the tactics loop
	TeamThink = 1, -- seconds between fireteam decisions
	TeamSize = 6, -- enemies are grouped into fireteams of this many by where they spawn
	TeamJoin = 70, -- studs: a new enemy joins a fireteam whose centre is this close

	BoundTimeout = 8, -- seconds before the halves swap even if someone has not moved
	BoundStagger = 0.8, -- seconds of random delay between movers starting

	PressRadius = 90, -- studs: friendly strength counted round the fireteam
	PressMargin = { Ally = 1, Enemy = 1 }, -- friendlies needed over the foes known
	PressMaxSuppression = 0.45, -- a fireteam this suppressed (mean) does not push
	PressMin = 12, -- seconds a push lasts at least
	PressFailSuppression = 0.65, -- mean suppression that ends a push
	PressCooldown = 35, -- seconds after a failed push before another
	PressHeldCooldown = 20,
	PressQuiet = 15, -- seconds with no foe known that count as the ground cleared
	PressFar = 140, -- studs from home that end a defenders' push
	PressStartRange = 130, -- studs: foes farther than this are not pushed at

	HandGrenades = { Leader = 2, Rifleman = 2, Support = 1, Assault = 2, Marksman = 0, Heavy = 0 },
	RifleGrenades = 3, -- for the first rifleman of each fireteam
	Grenade = {
		Min = 12, Max = 110, -- hand throw, studs (110 is about 30 m)
		RifleMin = 40, RifleMax = 200, -- rifle grenade
		Radius = 14, Damage = 120, RifleRadius = 11, RifleDamage = 100,
		Fuse = 3.5, Windup = 0.9, TeamGap = 8, Look = 1.2,
		Still = 4.5, -- seconds a target must sit still to count as dug in
		Friendly = 10, -- studs: no throw this close to its own side
		Error = 3, -- studs of scatter at 40 studs, growing with distance
		Suppress = 0.6, SuppressRadius = 22,
		SeeRange = 26, -- studs: a soldier this close who sees it land calls it
	},
	DodgeReach = 24, -- studs searched for cover outside the blast
	DodgeSpeed = 1.4, -- speed multiplier while running from a grenade

	HighGroundTag = "HighGround",
	HighGroundReach = 70,
	HighGroundStay = 40, -- seconds it holds the post before reconsidering
	HighGroundPerTeam = 2,

	SpotCrouch = 140, -- studs
	SpotProne = 60,
}

local T = SoldierTactics.TUNING
local Soldier, CoverMap, WarDamage, SoundKit
local PIN = 0.65
local RETREAT = 0.35
local installed = false
local applying = false -- true while this module sets an order itself

local teams = {} -- [key] = team record
local enemyTeams = {} -- keys of enemy fireteams, for joining
local grenades = {}
local highPosts = {}
local stats = {}
SoldierTactics.Stats = stats

-- Helpers ------------------------------------------------------------------------------------------

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function gauss()
	return (math.random() + math.random() + math.random() - 1.5) / 1.5
end

local function stat(key)
	stats[key] = (stats[key] or 0) + 1
end

local function debug(...)
	if workspace:GetAttribute("TacticsDebug") then
		print("[Tactics]", ...)
	end
end

local function alive(s)
	return s and s.Alive and s.Model and s.Model.Parent and s.Humanoid and s.Humanoid.Health > 0
end

local function nameOf(s)
	return s.Model and s.Model.Name or "?"
end

-- Rays that see the world but not soldiers, players or effects.
local worldParams, worldAt = nil, -math.huge
local function params()
	if worldParams and os.clock() - worldAt < 2 then
		return worldParams
	end
	local ignore = {}
	for _, n in { "Squad", "Hostiles", "Fx", "Relics", "_Grenades" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ignore, f)
		end
	end
	local map = workspace:FindFirstChild("Map")
	local war = map and map:FindFirstChild("War")
	if war then
		table.insert(ignore, war)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.IgnoreWater = true
	rp.RespectCanCollide = true
	worldParams, worldAt = rp, os.clock()
	return rp
end

local function clear(a, b)
	return workspace:Raycast(a, b - a, params()) == nil
end

local function grenadeFolder()
	local f = workspace:FindFirstChild("_Grenades")
	if not f then
		f = Instance.new("Folder")
		f.Name = "_Grenades"
		f.Parent = workspace
		worldAt = -math.huge
	end
	return f
end

-- Fireteams ----------------------------------------------------------------------------------------

local function teamOf(s)
	local key = s.TacTeam
	if not key then
		return nil
	end
	local t = teams[key]
	if not t then
		t = { Key = key, Side = s.Side, BoundEl = 1, BoundId = 0, BoundStart = os.clock(), NextThrow = 0, Joined = 0, Downs = {}, NextPress = 0, Members = {} }
		teams[key] = t
	end
	return t
end

-- The living members; one who has dropped out since the last pass counts as a loss.
local function membersOf(t)
	local list = {}
	for s in t.Members do
		if alive(s) then
			table.insert(list, s)
		else
			t.Members[s] = nil
			table.insert(t.Downs, os.clock())
		end
	end
	return list
end

local function centreOf(list)
	local sum, n = Vector3.zero, 0
	for _, s in list do
		sum += s.Root.Position
		n += 1
	end
	return if n > 0 then sum / n else Vector3.zero
end

-- An ally joins its Battle fireteam (Team); an enemy joins the nearest unfilled enemy fireteam.
local function joinTeam(s)
	local key
	if s.Side == "Ally" then
		key = "A" .. tostring(s.Team or 1)
	else
		local here = s.Root.Position
		local best, bestD = nil, T.TeamJoin
		for _, k in enemyTeams do
			local t = teams[k]
			local list = t and membersOf(t) or {}
			if #list > 0 and #list < T.TeamSize then
				local d = flatDist(centreOf(list), here)
				if d < bestD then
					best, bestD = k, d
				end
			end
		end
		if not best then
			best = "E" .. tostring(#enemyTeams + 1)
			table.insert(enemyTeams, best)
		end
		key = best
	end
	s.TacTeam = key
	local t = teamOf(s)
	t.Joined += 1
	t.Members[s] = true
	s.TacElement = t.Joined % 2
	-- Grenades by role; rifle grenades for the first rifleman of the fireteam.
	s.TacNades = T.HandGrenades[s.Role] or 1
	s.TacRifle = 0
	if s.Role == "Rifleman" and not t.HasRifleGrenadier then
		t.HasRifleGrenadier = true
		s.TacRifle = T.RifleGrenades
	end
	s.TacStill = {}
	s.TacNextGrenade = 0
	s.TacNextHigh = os.clock() + math.random() * 4
end

-- Bounds: the halves take turns. The brain advances a soldier when its NextHop comes due, so the
-- half whose turn it is gets NextHop due now (staggered) and the other half is held.
local function gateBounds(t, list, now)
	local attacking = 0
	for _, s in list do
		if s.Order and s.Order.Mode == "Attack" then
			attacking += 1
		end
	end
	if attacking * 2 < #list or #list <= 1 then
		for _, s in list do
			s.TacArm = nil
			if s.NextHop and s.NextHop > now + 900 then
				s.NextHop = now
			end
		end
		return
	end
	local pushing = t.PushUntil and t.PushUntil > now
	for _, s in list do
		if s.Emp or s.TacThrowing or s.TacEvade then
			continue
		end
		local mover = pushing or (s.TacElement == t.BoundEl and s.TacBoundId ~= t.BoundId)
		if mover then
			if s.TacArm then
				-- The brain used the hop (it set a NextHop of its own): it moved, or tried to.
				if s.NextHop ~= s.TacArmHop and s.NextHop > now and s.NextHop < now + 900 then
					s.TacBoundId = t.BoundId
					s.TacArm = nil
				end
			else
				if s.NextHop > now + 900 or not pushing then
					s.NextHop = now + math.random() * T.BoundStagger
				end
				s.TacArm = true
				s.TacArmHop = s.NextHop
			end
		else
			s.TacArm = nil
			if s.NextHop < now + 900 then
				s.NextHop = now + 999
			end
		end
	end
end

local function swapBounds(t, list, now)
	local movers = {}
	for _, s in list do
		if s.TacElement == t.BoundEl and not s.Emp and not s.TacEvade and s.Humanoid.Health / s.Humanoid.MaxHealth > RETREAT then
			table.insert(movers, s)
		end
	end
	local allMoved = #movers > 0
	for _, s in movers do
		if s.TacBoundId ~= t.BoundId or s.Phase == "Moving" then
			allMoved = false
			break
		end
	end
	if allMoved or now - t.BoundStart > T.BoundTimeout then
		t.BoundEl = 1 - t.BoundEl
		t.BoundId += 1
		t.BoundStart = now
		stat("Bounds")
		debug(t.Key, "bound: half", t.BoundEl, "moves")
	end
	-- The half staying put covers: up to fire at the last threat while a mover is in the open.
	local moverOut = false
	for _, s in list do
		if s.TacElement == t.BoundEl and s.Phase == "Moving" then
			moverOut = true
			break
		end
	end
	if moverOut then
		for _, s in list do
			if s.TacElement ~= t.BoundEl and s.Cover and s.Phase == "Hidden" and s.Suppression < PIN then
				s.NextPeek = math.min(s.NextPeek or now, now)
			end
		end
	end
end

-- Pressure ------------------------------------------------------------------------------------------

-- What a fireteam knows of the enemy: foes seen in the last 8 s, their centre, how many are weak.
local function picture(list, now)
	local foes = {}
	for _, s in list do
		for model, rec in s.Known or {} do
			if model.Parent and rec.Pos and now - (rec.SeenAt or -math.huge) < 8 then
				local hum = model:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local o = foes[model]
					if not o or rec.SeenAt > o.SeenAt then
						foes[model] = rec
					end
				end
			end
		end
	end
	local n, sum, weak = 0, Vector3.zero, 0
	for model, rec in foes do
		n += 1
		sum += rec.Pos
		local hum = model:FindFirstChildOfClass("Humanoid")
		local fs = Soldier.FromModel and Soldier.FromModel(model)
		local isWeak = hum.Health / math.max(1, hum.MaxHealth) < 0.5
		if fs then
			isWeak = isWeak or (fs.Suppression or 0) >= PIN or fs.Reloading or (rec.Visible and (fs.Phase == "Moving" or fs.Phase == "Open"))
		elseif rec.Visible then
			isWeak = isWeak or hum.MoveDirection.Magnitude > 0.1
		end
		if isWeak then
			weak += 1
		end
	end
	if n == 0 then
		return nil
	end
	return { N = n, Pos = sum / n, Weak = weak }
end

local function setOrder(s, order)
	applying = true
	local ok, err = pcall(s.SetOrder, s, order)
	applying = false
	if not ok then
		warn("SoldierTactics: SetOrder: " .. tostring(err))
	end
end

local function endPress(t, list, failed)
	for _, s in list do
		if s.Order and s.Order.TacPress then
			local home = s.TacHome
			if failed or not home or home.Mode == "Attack" then
				setOrder(s, home or { Mode = "Hold", Goal = s.Root.Position, Radius = 22 })
			else
				setOrder(s, { Mode = "Hold", Goal = t.PressCentre or s.Root.Position, Radius = 22, Facing = home.Facing })
			end
			s.TacHome = nil
		end
	end
	t.Press = nil
end

local function pressure(t, list, now)
	if #list < 2 then
		return
	end
	local sumSup = 0
	for _, s in list do
		sumSup += s.Suppression or 0
		if s.Order and s.Order.Mode == "Retire" then
			return
		end
	end
	local meanSup = sumSup / #list
	for i = #t.Downs, 1, -1 do
		if now - t.Downs[i] > 10 then
			table.remove(t.Downs, i)
		end
	end
	local pic = picture(list, now)
	local centre = centreOf(list)
	local friends = 0
	for _, o in Soldier.All(t.Side) do
		if flatDist(o.Root.Position, centre) < T.PressRadius then
			friends += 1
		end
	end
	local margin = T.PressMargin[t.Side] or 1
	local adv = pic ~= nil and meanSup < T.PressMaxSuppression and #t.Downs < 2
		and (friends >= pic.N + margin or (friends >= pic.N and pic.Weak * 2 >= pic.N))

	if not t.Press then
		if not adv or now < t.NextPress or flatDist(centre, pic.Pos) > T.PressStartRange then
			return
		end
		t.Press = { Start = now, Quiet = nil }
		t.PushUntil = now + 5
		t.BoundId += 1
		t.BoundStart = now
		local goal = pic.Pos
		for _, s in list do
			if not s.Emp then
				s.TacHome = s.Order
				setOrder(s, { Mode = "Attack", Goal = goal, Radius = 10, LaneA = centre, LaneB = goal, Facing = { goal }, TacPress = true })
			end
		end
		stat("Pushes")
		debug(t.Key, ("pushes: %d friendlies against %d known (%d weak)"):format(friends, pic.N, pic.Weak))
		return
	end

	if pic then
		t.Press.Quiet = nil
		for _, s in list do
			if s.Order and s.Order.TacPress then
				s.Order.Goal = pic.Pos
				s.Order.LaneB = pic.Pos
				s.Order.Facing = { pic.Pos }
			end
		end
		if adv then
			t.PushUntil = math.max(t.PushUntil or 0, now + 2)
		end
	elseif not t.Press.Quiet then
		t.Press.Quiet = now
	end
	local pressing = 0
	local home = nil
	for _, s in list do
		if s.Order and s.Order.TacPress then
			pressing += 1
			home = home or s.TacHome
		end
	end
	if pressing < 2 then
		t.Press = nil -- Battle gave new orders; follow them
		return
	end
	local failing = now - t.Press.Start > T.PressMin and (meanSup > T.PressFailSuppression or #t.Downs >= 2 or (pic and friends < pic.N))
	local far = home and home.Mode ~= "Attack" and home.Goal and flatDist(centre, home.Goal) > T.PressFar
	local won = t.Press.Quiet and now - t.Press.Quiet > T.PressQuiet
	if failing or far then
		endPress(t, list, true)
		t.NextPress = now + T.PressCooldown
		stat("PushesFailed")
		debug(t.Key, "push", failing and "stalls" or "has gone too far", "- back to its orders")
	elseif won then
		t.PressCentre = centre
		endPress(t, list, false)
		t.NextPress = now + T.PressHeldCooldown
		stat("PushesHeld")
		debug(t.Key, "push cleared the ground; holding")
	end
end

-- Grenades -------------------------------------------------------------------------------------------

local function launchParams(from, to, rifle)
	local d = flatDist(from, to)
	local tf = if rifle then 0.6 + d / 110 else 0.9 + d / 60
	local g = workspace.Gravity
	local delta = to - from
	return Vector3.new(delta.X / tf, (delta.Y + 0.5 * g * tf * tf) / tf, delta.Z / tf), tf
end

-- The arc is clear until it comes down at the target.
local function arcClear(from, to, rifle)
	local v, tf = launchParams(from, to, rifle)
	local g = Vector3.new(0, -workspace.Gravity, 0)
	local last = from
	for k = 1, 9 do
		local u = k / 10
		if u > 0.85 then
			break
		end
		local tt = u * tf
		local p = from + v * tt + 0.5 * g * tt * tt
		if workspace:Raycast(last, p - last, params()) then
			return false
		end
		last = p
	end
	return true
end

local function throwFrom(s)
	if s.MuzzlePos then
		local ok, p = pcall(s.MuzzlePos, s)
		if ok and p then
			return p
		end
	end
	return s.Root.Position + Vector3.new(0, 2.5, 0)
end

local function explode(g)
	g.Done = true
	local pos = g.Pos
	local radius = if g.Rifle then T.Grenade.RifleRadius else T.Grenade.Radius
	local damage = if g.Rifle then T.Grenade.RifleDamage else T.Grenade.Damage
	if WarDamage then
		local ok, err = pcall(WarDamage.Blast, pos, radius, damage, { Side = g.Side, Kind = "Blast", Model = g.ByModel })
		if not ok then
			warn("SoldierTactics: blast: " .. tostring(err))
		end
	end
	local boom = Instance.new("Explosion")
	boom.BlastPressure = 0
	boom.BlastRadius = 6 -- the look only: no pressure, no joints broken; damage is WarDamage's
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters -- the default digs holes in the terrain
	boom.Position = pos
	boom.Parent = workspace
	if SoundKit then
		pcall(SoundKit.Play, "World/Explosion", { Position = pos })
	end
	for _, s in Soldier.All() do
		local d = (s.Root.Position - pos).Magnitude
		if d < T.Grenade.SuppressRadius and s.Suppress then
			pcall(s.Suppress, s, T.Grenade.Suppress * (1 - d / T.Grenade.SuppressRadius))
		end
		if s.TacEvade == g then
			s.TacEvade = nil
		end
	end
	if g.Part then
		g.Part:Destroy()
	end
end

local function launch(s, target, rifle)
	if not alive(s) then
		return
	end
	local from = throwFrom(s)
	local d = flatDist(from, target)
	local err = T.Grenade.Error * math.max(1, d / 40)
	local aim = target + Vector3.new(gauss() * err, 0, gauss() * err)
	-- Aim at the ground there, not at the foe's waist.
	local down = workspace:Raycast(aim + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), params())
	if down then
		aim = down.Position + Vector3.new(0, 0.3, 0)
	end
	local v = launchParams(from, aim, rifle)
	local part = Instance.new("Part")
	part.Name = if rifle then "RifleGrenade" else "Grenade"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * 0.7
	part.Color = Color3.fromRGB(52, 62, 40)
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(from)
	part.Parent = grenadeFolder()
	table.insert(grenades, {
		Part = part, Pos = from, Vel = v, Start = os.clock(), Rifle = rifle, Side = s.Side,
		ByModel = s.Model, Warned = { [s.Side] = true }, Rest = false, Done = false,
	})
end

-- Thrown only when it will do something, by a soldier free to stand up for it.
local function considerGrenade(s, t, now)
	if now < (s.TacNextGrenade or 0) or now < t.NextThrow then
		return
	end
	s.TacNextGrenade = now + T.Grenade.Look
	if (s.TacNades or 0) <= 0 and (s.TacRifle or 0) <= 0 then
		return
	end
	if s.Emp or s.Phase == "Moving" or s.Firing or s.Reloading or s.TacThrowing or s.TacEvade then
		return
	end
	if s.Order and s.Order.Mode == "Retire" then
		return
	end
	local here = s.Root.Position
	local best = nil
	for model, rec in s.Known or {} do
		local age = now - (rec.SeenAt or -math.huge)
		local hum = model.Parent and model:FindFirstChildOfClass("Humanoid")
		if age > 5 or not hum or hum.Health <= 0 or not rec.Pos then
			continue
		end
		-- Track how long it has stayed put.
		local still = s.TacStill[model]
		if not still then
			still = { Pos = rec.Pos, Since = now }
			s.TacStill[model] = still
		elseif flatDist(still.Pos, rec.Pos) > 3 then
			still.Pos, still.Since = rec.Pos, now
		end
		local d = flatDist(rec.Pos, here)
		local hand = (s.TacNades or 0) > 0 and d >= T.Grenade.Min and d <= T.Grenade.Max
		local rifle = not hand and (s.TacRifle or 0) > 0 and d >= T.Grenade.RifleMin and d <= T.Grenade.RifleMax
		if not hand and not rifle then
			continue
		end
		local fs = Soldier.FromModel and Soldier.FromModel(model)
		local onGun = fs ~= nil and fs.Emp ~= nil
		local near = 0
		for m2, r2 in s.Known do
			if r2.Pos and now - (r2.SeenAt or -math.huge) < 5 and flatDist(r2.Pos, rec.Pos) < 6 then
				near += 1
			end
		end
		local cluster = near >= 2
		local dug = not rec.Visible or (fs ~= nil and (fs.Phase == "Hidden" or fs.Cover ~= nil))
		local sat = now - still.Since >= T.Grenade.Still
		local why = if onGun then "a crew on a mounted gun" elseif cluster then "foes bunched together" elseif sat and dug then "a foe dug in" else nil
		if not why then
			continue
		end
		local friendly = false
		for _, o in Soldier.All(s.Side) do
			if flatDist(o.Root.Position, rec.Pos) < T.Grenade.Friendly then
				friendly = true
				break
			end
		end
		if not friendly then
			for _, p in Players:GetPlayers() do
				local c = p.Character
				local root = c and c:FindFirstChild("HumanoidRootPart")
				if root and (p:GetAttribute("Side") or "Ally") == s.Side and flatDist(root.Position, rec.Pos) < T.Grenade.Friendly then
					friendly = true
					break
				end
			end
		end
		if friendly or not arcClear(throwFrom(s), rec.Pos, rifle) then
			continue
		end
		local score = (if onGun then 3 else 0) + (if cluster then 2 else 0) + (if dug then 1 else 0) - d / 50
		if not best or score > best.Score then
			best = { Pos = rec.Pos, Rifle = rifle, Why = why, Score = score, Model = model }
		end
	end
	if not best then
		return
	end
	if best.Rifle then
		s.TacRifle -= 1
	else
		s.TacNades -= 1
	end
	t.NextThrow = now + T.Grenade.TeamGap
	s.TacThrowing = true
	s.NextBurst = math.max(s.NextBurst or 0, now + T.Grenade.Windup + 0.5)
	s.NextChoose = math.max(s.NextChoose or 0, now + T.Grenade.Windup)
	pcall(s.SetStance, s, "Stand")
	s.Model:SetAttribute("Throwing", true)
	stat(if best.Rifle then "RifleGrenades" else "Grenades")
	debug(nameOf(s), best.Rifle and "fires a rifle grenade" or "throws a grenade", "at", best.Model.Name, "(" .. best.Why .. ")")
	task.delay(T.Grenade.Windup, function()
		if s.Model then
			s.Model:SetAttribute("Throwing", nil)
		end
		s.TacThrowing = nil
		launch(s, best.Pos, best.Rifle)
		if alive(s) and s.Cover and s.Phase == "Hidden" and not (s.Entry and s.Entry.Full) then
			pcall(s.SetStance, s, "Crouch")
		end
	end)
end

-- Away from the blast: cover outside it reachable in the time left, else straight away from it.
local function dodge(s, g, now)
	local left = T.Grenade.Fuse - (now - g.Start)
	local radius = T.Grenade.Radius
	local here = s.Root.Position
	if s.Emp and s.Leave then
		pcall(s.Leave, s)
	end
	local speed = (s.Speed or 12) * T.DodgeSpeed
	local best, bestScore = nil, -math.huge
	for _, spot in CoverMap.Near(here, T.DodgeReach) do
		if (spot.Owner and spot.Owner ~= s) or (spot.BadUntil or 0) > now then
			continue
		end
		local dg = flatDist(spot.Pos, g.Pos)
		local travel = flatDist(here, spot.Pos)
		if dg < radius + 3 or travel / speed > left - 0.2 then
			continue
		end
		-- Not across the grenade.
		local ab = flat(spot.Pos - here)
		local k = if ab.Magnitude > 0.1 then math.clamp(flat(g.Pos - here):Dot(ab) / ab:Dot(ab), 0, 1) else 0
		if flatDist(here + ab * k, g.Pos) < radius * 0.5 then
			continue
		end
		local score = -travel + dg * 0.3
		if score > bestScore then
			best, bestScore = spot, score
		end
	end
	if s.Leave then
		pcall(s.Leave, s)
	end
	if best then
		CoverMap.Claim(best, s)
		s.Cover = best
		s.Entry = best.Dirs[1]
		s.Dest = best.Pos
		s.Phase = "Moving"
		s.MoveStart = now
		pcall(s.SetStance, s, "Stand")
	else
		local away = flat(here - g.Pos)
		away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
		pcall(s.GoOpen, s, here + away * speed * math.max(0.4, left - 0.3), now)
	end
	s.TacEvade = g
	s.NextChoose = now + left + 0.4
	if not s.TacSpeed then
		s.TacSpeed = s.Speed
		s.Speed = (s.Speed or 12) * T.DodgeSpeed
		task.delay(left + 0.6, function()
			if s.TacSpeed then
				s.Speed = s.TacSpeed
				s.TacSpeed = nil
			end
		end)
	end
	stat("Dodges")
	debug(nameOf(s), "runs from a grenade", best and "to cover" or "into the open")
end

local function stepGrenades(dt)
	local now = os.clock()
	local g3 = Vector3.new(0, -workspace.Gravity, 0)
	for i = #grenades, 1, -1 do
		local g = grenades[i]
		if g.Done then
			table.remove(grenades, i)
			continue
		end
		if not g.Rest then
			g.Vel += g3 * dt
			local step = g.Vel * dt
			local hit = workspace:Raycast(g.Pos, step, params())
			if hit then
				if g.Rifle then
					g.Pos = hit.Position
					explode(g)
					continue
				end
				local n = hit.Normal
				g.Pos = hit.Position + n * 0.35
				g.Vel = (g.Vel - 2 * g.Vel:Dot(n) * n) * 0.35
				if g.Vel.Magnitude < 4 and n.Y > 0.6 then
					g.Rest = true
					g.Vel = Vector3.zero
				end
			else
				g.Pos += step
			end
			if g.Part then
				g.Part.CFrame = CFrame.new(g.Pos)
			end
		end
		if (g.Rifle and now - g.Start > 6) or (not g.Rifle and now - g.Start >= T.Grenade.Fuse) then
			explode(g)
		end
	end
end

-- Who knows of each live hand grenade, and who runs.
local function watchGrenades(now)
	if not T.Features.Dodge then
		return
	end
	for _, g in grenades do
		if g.Done or g.Rifle then
			continue
		end
		for _, s in Soldier.All() do
			if s.TacEvade == g then
				continue
			end
			local head = s.Head or s.Root
			local d = (s.Root.Position - g.Pos).Magnitude
			if not g.Warned[s.Side] then
				if d < T.Grenade.SeeRange and clear(head.Position, g.Pos + Vector3.new(0, 0.3, 0)) then
					g.Warned[s.Side] = true
					stat("GrenadeCalls")
					debug(nameOf(s), "sees a grenade and calls it")
				else
					continue
				end
			end
			if d < T.Grenade.Radius + 3 then
				dodge(s, g, now)
			end
		end
	end
end

-- High ground ----------------------------------------------------------------------------------------

-- A post is a cover spot the brain understands: Pos, Dirs (one, facing the way the part looks), Owner.
local function buildPosts()
	table.clear(highPosts)
	for _, part in CollectionService:GetTagged(T.HighGroundTag) do
		if part:IsA("BasePart") then
			local look = flat(part.CFrame.LookVector)
			look = if look.Magnitude > 0.1 then look.Unit else Vector3.new(0, 0, -1)
			local down = workspace:Raycast(part.Position + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params())
			local pos = if down then down.Position else part.Position
			table.insert(highPosts, { Pos = pos, Dirs = { { Dir = look, Full = false, Fire = true } }, Owner = nil, BadUntil = 0, TacHigh = true, Part = part })
		end
	end
	return #highPosts
end

local function considerHigh(s, t, list, now)
	if now < (s.TacNextHigh or 0) then
		return
	end
	s.TacNextHigh = now + 6
	if #highPosts == 0 or not (s.RoleStats and s.RoleStats.Hold) or s.Emp or s.TacEvade then
		return
	end
	if s.Cover and s.Cover.TacHigh then
		return
	end
	local up = 0
	for _, m in list do
		if m.Cover and m.Cover.TacHigh then
			up += 1
		end
	end
	if up >= T.HighGroundPerTeam then
		return
	end
	local threat = s.Target
	if not threat or not threat.Pos then
		return
	end
	local here = s.Root.Position
	local best, bestD = nil, T.HighGroundReach
	for _, post in highPosts do
		if (post.Owner and post.Owner ~= s and alive(post.Owner)) or post.BadUntil > now then
			continue
		end
		local d = flatDist(here, post.Pos)
		if d < bestD and CoverMap.Facing(post, threat.Pos) and clear(post.Pos + Vector3.new(0, 4.6, 0), threat.Pos + Vector3.new(0, 1.5, 0)) then
			best, bestD = post, d
		end
	end
	if not best then
		return
	end
	pcall(s.Leave, s)
	best.Owner = s
	s.Cover = best
	s.Entry = best.Dirs[1]
	s.Dest = best.Pos
	s.Phase = "Moving"
	s.MoveStart = now
	s.TacHighUntil = now + T.HighGroundStay
	stat("HighGround")
	debug(nameOf(s), "takes the high ground at", best.Part:GetFullName())
end

-- The loop -------------------------------------------------------------------------------------------

local lastTeamThink = 0

local function tick()
	local now = os.clock()
	-- Fireteams from the soldiers alive now.
	local byTeam = {}
	for _, s in Soldier.All() do
		if not s.TacTeam then
			joinTeam(s)
		end
		local t = teamOf(s)
		t.Members[s] = true
		byTeam[t] = true
	end
	local teamThink = now - lastTeamThink >= T.TeamThink
	if teamThink then
		lastTeamThink = now
	end
	for t in byTeam do
		local list = membersOf(t)
		if #list == 0 then
			continue
		end
		if teamThink then
			if T.Features.Bounds then
				swapBounds(t, list, now)
			end
			if T.Features.Pressure then
				pressure(t, list, now)
			end
		end
		if T.Features.Bounds then
			gateBounds(t, list, now)
		end
		for _, s in list do
			if T.Features.Grenades then
				considerGrenade(s, t, now)
			end
			if T.Features.HighGround then
				considerHigh(s, t, list, now)
			end
		end
	end
	watchGrenades(now)
end

-- Hooks ----------------------------------------------------------------------------------------------

local function hook(name, make)
	local orig = Soldier[name]
	if type(orig) ~= "function" then
		warn("SoldierTactics: Soldier." .. name .. " not found; the parts that need it are off")
		return false
	end
	Soldier[name] = make(orig)
	return true
end

local function installHooks()
	-- Fireteams and grenades for every new soldier.
	hook("Spawn", function(orig)
		return function(...)
			local s = orig(...)
			if s and s.Root then
				local ok, err = pcall(joinTeam, s)
				if not ok then
					warn("SoldierTactics: joinTeam: " .. tostring(err))
				end
			end
			return s
		end
	end)

	-- NoBack: an attacker re-picking cover never takes a spot farther from its goal.
	if T.Features.NoBack then
		hook("ChooseCover", function(orig)
			return function(self, why, threats, ...)
				local spot, entry = orig(self, why, threats, ...)
				local o = self.Order
				if not spot or why ~= "Engage" or not o or o.Mode ~= "Attack" or not o.Goal then
					return spot, entry
				end
				local toGoal = flatDist(self.Root.Position, o.Goal)
				if toGoal <= (o.Radius or 16) then
					return spot, entry
				end
				local saved = {}
				for _ = 1, 3 do
					if flatDist(spot.Pos, o.Goal) <= toGoal + 2 then
						break
					end
					saved[spot] = spot.BadUntil
					spot.BadUntil = os.clock() + 1
					spot, entry = orig(self, why, threats, ...)
					if not spot then
						break
					end
				end
				for sp, v in saved do
					sp.BadUntil = v
				end
				if spot and flatDist(spot.Pos, o.Goal) > toGoal + 2 then
					stat("NoBack")
					return nil
				end
				return spot, entry
			end
		end)
	end

	-- Flanks only while attacking; a soldier on high ground stays there a while.
	hook("TakeCover", function(orig)
		return function(self, why, threats, now, ...)
			if T.Features.Flanks and why == "Flank" and self.Order and self.Order.Mode ~= "Attack" then
				return false
			end
			if self.Cover and self.Cover.TacHigh and self.TacHighUntil and os.clock() < self.TacHighUntil and (why == "Hold" or why == "Advance") then
				return true
			end
			return orig(self, why, threats, now, ...)
		end
	end)

	-- Orders from anywhere else (Battle, WarServer) end this soldier's part in a push.
	hook("SetOrder", function(orig)
		return function(self, order, ...)
			if not applying then
				self.TacHome = nil
			end
			return orig(self, order, ...)
		end
	end)

	-- Spotting: a still soldier crouched in cover is hard to make out far off.
	if T.Features.Spotting then
		hook("Sees", function(orig)
			return function(self, foe, ...)
				local fs = foe and foe.Model and Soldier.FromModel and Soldier.FromModel(foe.Model)
				if fs and fs.Root and self.Root then
					local d = flatDist(fs.Root.Position, self.Root.Position)
					local gaveAway = (fs.FiredAt and os.clock() - fs.FiredAt < 1.5) or fs.Phase == "Moving"
					if not gaveAway then
						if fs.Stance == "Prone" and d > T.SpotProne then
							return false
						end
						if fs.Stance == "Crouch" and (fs.Cover or fs.Phase == "Hidden") and d > T.SpotCrouch then
							return false
						end
					end
				end
				return orig(self, foe, ...)
			end
		end)
	end
end

-- API ------------------------------------------------------------------------------------------------

-- Turns the tactics on. Safe to call more than once. opts: { Features = { Name = false, ... } } to
-- switch parts off, or any TUNING field to override.
function SoldierTactics.Install(opts)
	if installed then
		return true
	end
	local modules = ServerStorage:WaitForChild("Modules", 30)
	local soldierModule = modules and modules:WaitForChild("Soldier", 30)
	if not soldierModule then
		warn("SoldierTactics: ServerStorage.Modules.Soldier not found; not installed")
		return false
	end
	Soldier = require(soldierModule)
	local cm = modules:FindFirstChild("CoverMap")
	CoverMap = cm and require(cm)
	if not CoverMap or type(Soldier.All) ~= "function" then
		warn("SoldierTactics: this Soldier module is not the WAR v2 brain (no CoverMap or Soldier.All); not installed")
		return false
	end
	local wd = modules:FindFirstChild("WarDamage")
	WarDamage = wd and require(wd)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local sk = shared and shared:FindFirstChild("SoundKit")
	SoundKit = sk and require(sk)
	local okCfg, cfg = pcall(function()
		return require(shared.GameConfig).War.Battle.Brain
	end)
	if okCfg and cfg then
		PIN = (cfg.Suppress and cfg.Suppress.Pin) or PIN
		RETREAT = cfg.Retreat or RETREAT
	end
	if opts then
		for k, v in opts do
			if k == "Features" then
				for f, on in v do
					T.Features[f] = on
				end
			else
				T[k] = v
			end
		end
	end
	if not WarDamage and T.Features.Grenades then
		warn("SoldierTactics: no WarDamage module; grenades are off")
		T.Features.Grenades = false
	end
	installHooks()
	local posts = buildPosts()
	CollectionService:GetInstanceAddedSignal(T.HighGroundTag):Connect(buildPosts)
	installed = true
	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				warn("SoldierTactics: " .. tostring(err))
			end
			task.wait(T.Tick)
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if #grenades > 0 then
			local ok, err = pcall(stepGrenades, dt)
			if not ok then
				warn("SoldierTactics: grenades: " .. tostring(err))
			end
		end
	end)
	local on = {}
	for f, v in T.Features do
		if v then
			table.insert(on, f)
		end
	end
	table.sort(on)
	print(("SoldierTactics: installed (%s); %d high-ground posts tagged %q"):format(table.concat(on, ", "), posts, T.HighGroundTag))
	return true
end

-- Prints the counters: bounds, pushes, grenades, dodges, high ground and so on.
function SoldierTactics.Report()
	local keys = {}
	for k in stats do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, k .. " " .. stats[k])
	end
	print("SoldierTactics: " .. (if #parts > 0 then table.concat(parts, ", ") else "nothing yet"))
end

-- Rebuilds the high-ground posts (after tagging or moving marker parts).
function SoldierTactics.RefreshHighGround()
	return buildPosts()
end

return SoldierTactics
