-- The Beacon: a giant that wakes when the players break out of the house (workspace attribute
-- Breakout, set by MatchServer). Numbers: GameConfig.Beacon.
--   Its two lamps are its eyes; they never hurt anyone. Each sweeps its own pattern across the
--   ground. A player standing in a beam, in the lamp's line of sight, not hiding (Hiding,
--   set on the character by EvadeServer) and not indoors (a roof overhead), fills their Seen meter: faster running and close,
--   slower standing still, far off, crouched by cover or in a back alley (Map.Alleys). The lamp that found them slows and
--   follows them at TrackSpeed, and the Beacon stops and turns to look. Out of every beam the
--   meter drains again. A full meter means it has seen you: it screams and runs at you, the
--   screen goes black, and you're taken (PlayerHealth.Take). In nights (workspace Nights, set
--   by MatchServer) it is out from the first lull and looks in the lulls and nights too, and
--   a catch drops you in the yard behind the house (Map.Yard) for GameConfig.Nights.CaughtCost
--   of your points instead of taking you, and puts back any tower part you carried
--   (ServerStorage.DropPart, PartsServer). On the last night it heads for the house
--   (workspace BeaconHome) whenever it has nothing better to do.
--   It walks the town toward the last noise it heard: footsteps carry Hearing.Walk studs,
--   sprinting Hearing.Sprint, gunshots Hearing.Shot. With nothing heard it wanders, often to
--   a building in Map.Town.Buildings that it smashes with both arms (Smash); whatever its
--   body walks through breaks too. The pieces fly, settle as rubble, and go back every match.
--   It never walks onto the hill behind the house: parts tagged BeaconNoGo are footprints too.
--   When it wakes it stands by the building nearest the house and smashes it while everyone
--   watches (the reveal: MatchServer's RevealUntil, when it sees nobody).
--   The pickup (workspace EvacAt, Shared.EvacPath): from EvacStart seconds before, it sweeps
--   both lamps over the landing zone and comes for it at EvacSpeed; in the escape (WaveState
--   Rescue) it runs after the helicopter and reaches up at it. Players aboard (character
--   attribute Aboard) are out of its reach.
--   Every VentEvery seconds the lamps overheat: it stands still for VentTime, lamps dim and
--   smoking, blind. Only then do bullets hurt the lenses (LensL, LensR; GunServer fires
--   Events.WorldShot); the rest of the time they spark off. With both out it falls, and
--   everyone in the match gets KillPoints.
-- State for clients (StarterPlayerScripts.BeaconClient) lives in attributes. On the Beacon:
-- State (Asleep / Hunt / Vent / Chase / Dead), Moving, TrackL and TrackR (UserId each lamp is
-- following, or 0), Chasing (UserId or 0), and the pose flags Smash, Run and Reach. On each player: BeaconSeen (0-1) and, while being
-- taken, BeaconCaughtAt (server time the screen is fully black).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local EvacPath = require(ReplicatedStorage.Shared.EvacPath)
local Points = require(ServerStorage.Modules.Points)
local Classes = require(ReplicatedStorage.Shared.Classes)
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.Beacon
local SEEN = CFG.Seen
local SMASH = CFG.Smash
local EVAC_TO = GameConfig.Breakout.Evac.To.Unit
local beacon = workspace:WaitForChild("Beacon")
local root = beacon.PrimaryPart
beacon:SetAttribute("Indestructible", true)

local LIGHT_IDLE = Color3.fromRGB(255, 226, 170)
local LIGHT_ALERT = Color3.fromRGB(255, 40, 30)
local LIGHT_VENT = Color3.fromRGB(255, 110, 40)
local LENS_DEAD = Color3.fromRGB(24, 24, 24)

-- Where it stands asleep, and how it is turned: the model's front faces world +Z at rest.
local parkCf = root.CFrame
local baseRot = parkCf.Rotation
local saved = {}
for _, d in beacon:GetDescendants() do
	if d:IsA("BasePart") then
		saved[d] = { Color = d.Color, Material = d.Material }
	elseif d:IsA("Light") then
		saved[d] = { Enabled = d.Enabled, Brightness = d.Brightness }
	end
end

local siren = ReplicatedStorage.Assets.Sounds.Beacon.Siren:Clone()
siren.Parent = beacon:WaitForChild("Head")
local sirenSpeed = siren.PlaybackSpeed

-- Steam off the head while the lamps cool.
local steam = ReplicatedStorage.Assets.Fx.Smoke:Clone()
steam.Name = "VentSteam"
steam.Parent = beacon.Head
local function setSteam(on)
	for _, e in steam:GetChildren() do
		if e:IsA("ParticleEmitter") then
			e.Enabled = on
		end
	end
end
setSteam(false)

-- Lamps: the server moves each lamp's aim point (the LensXTip part, on the ground where the
-- beam lands); BeaconClient draws the beam, smoothed, from the lens to it, with a pool of light
-- the size of what the lamp can see. Lens attributes for the look: LampOn, LampColor, LampPower.
local lenses = {}
for _, name in { "LensL", "LensR" } do
	local lens = beacon:WaitForChild(name)
	local tip = Instance.new("Part")
	tip.Name = name .. "Tip"
	tip.Size = Vector3.new(0.2, 0.2, 0.2)
	tip.Transparency = 1
	tip.Anchored = true
	tip.CanCollide = false
	tip.CanQuery = false
	tip.CanTouch = false
	tip.Parent = beacon
	lens:SetAttribute("LampOn", false)
	lens:SetAttribute("LampColor", LIGHT_IDLE)
	lens:SetAttribute("LampPower", 1)
	-- Each lamp sweeps at its own pace and range, so the two never move together.
	local left = name == "LensL"
	lenses[name] = {
		Name = name,
		Attr = if left then "TrackL" else "TrackR",
		Part = lens,
		Tip = tip,
		Health = CFG.LensHealth,
		MaxHealth = CFG.LensHealth,
		Side = if left then -1 else 1,
		Speed = if left then 0.7 else 1.13,
		ReachSpeed = if left then 0.41 else 0.67,
		Phase = if left then 0 else 2.1,
		Point = nil, -- where the beam is pointed on the ground
		Mode = "Sweep", -- Sweep / Track / Linger
		Track = nil, -- { Player, Root, Character, LostAt }
		LingerUntil = 0,
	}
end

local state = "Asleep"
local heading = 0 -- radians; 0 faces +Z
local pos = parkCf.Position
local goal = nil
local goalIsNoise = false
local nextWander = 0
local lastShot = {} -- player -> os.clock() of their last gunshot
local stepAt = 0
local seen = {} -- player -> 0..1
local seenAt = {} -- player -> os.clock() they were last in a beam
local chase = nil -- { Player, Root, Ends }
local ventEnds = 0
local nextVent = math.huge
local roamTo = nil -- the end of GameConfig.Beacon.Roam it's walking to while asleep
local stuckSince = nil -- when it last failed to step toward its wander goal

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshFilter()
	local ignore = { beacon }
	for _, name in { "Zombies", "Fx", "Drops" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
end

local function setState(s)
	state = s
	beacon:SetAttribute("State", s)
end

local function place()
	root.CFrame = CFrame.new(pos) * CFrame.Angles(0, heading, 0) * baseRot
end

local function flatDir(angle)
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

local function angleOf(v)
	return math.atan2(v.X, v.Z)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function playersInMatch()
	local list = {}
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if p:GetAttribute("InMatch") and humanoid and humanoid.Health > 0 and hrp and not character:GetAttribute("Aboard") then
			table.insert(list, { Player = p, Root = hrp, Character = character })
		end
	end
	return list
end

local function inBox(part, point)
	local rel = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function inCover(point)
	for _, spot in CollectionService:GetTagged("HideSpot") do
		if inBox(spot, point) then
			return true
		end
	end
	return false
end

-- In a back alley (GameConfig.Beacon.Seen.Alley).
local function inAlley(point)
	for _, zone in CollectionService:GetTagged("Alley") do
		if inBox(zone, point) then
			return true
		end
	end
	return false
end

-- Indoors: a roof (the house's or a town building's) overhead. The lamps can't make anyone
-- out indoors, even close to a wall or window; a roof it has smashed off no longer counts.
local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Include
local roofsSet = false
local roofCache = {} -- [player] = { At, Indoors }
local function indoors(e)
	local now = os.clock()
	local cached = roofCache[e.Player]
	if cached and now - cached.At < 0.25 then
		return cached.Indoors
	end
	if not roofsSet then
		roofsSet = true
		local map = workspace:FindFirstChild("Map")
		local list = {}
		local town = map and map:FindFirstChild("Town")
		if town and town:FindFirstChild("Buildings") then
			table.insert(list, town.Buildings)
		end
		for _, child in map and map:GetChildren() or {} do
			if child:GetAttribute("DefendHouse") then
				table.insert(list, child)
			end
		end
		roofParams.FilterDescendantsInstances = list
	end
	local inside = workspace:Raycast(e.Root.Position + Vector3.new(0, 2, 0), Vector3.new(0, 60, 0), roofParams) ~= nil
	roofCache[e.Player] = { At = now, Indoors = inside }
	return inside
end

-- How much of a player the lamps can make out: 0 hidden or indoors, Cover crouched by cover
-- (or just fired from a hiding spot), 1 in the open.
local function exposure(e)
	if indoors(e) then
		return 0
	end
	local shotRecently = lastShot[e.Player] and os.clock() - lastShot[e.Player] < SEEN.ShotReveal
	if e.Character:GetAttribute("Hiding") then
		return if shotRecently then SEEN.Cover else 0
	end
	local open = if inCover(e.Root.Position) then SEEN.Cover else 1
	return if inAlley(e.Root.Position) then open * SEEN.Alley else open
end

local function movingScale(e)
	if e.Character:GetAttribute("Crouching") then
		return SEEN.Moving.Crouch
	end
	local v = e.Root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if speed > CFG.Hearing.SprintSpeed then
		return SEEN.Moving.Sprint
	elseif speed > CFG.Hearing.WalkSpeed then
		return SEEN.Moving.Walk
	end
	return SEEN.Moving.Still
end

local function rangeScale(d)
	local r = SEEN.Range
	local k = math.clamp((d - r.Near) / (r.Far - r.Near), 0, 1)
	return r.NearScale + (r.FarScale - r.NearScale) * k
end

local function canSee(from, point)
	return workspace:Raycast(from, point - from, rayParams) == nil
end

local function liveLenses()
	local list = {}
	for _, lens in lenses do
		if lens.Health > 0 then
			table.insert(list, lens)
		end
	end
	return list
end

local function setLight(lens, color, strength)
	lens.Part:SetAttribute("LampColor", color)
	lens.Part:SetAttribute("LampPower", strength)
end

local function setBeams(on)
	for _, lens in lenses do
		lens.Part:SetAttribute("LampOn", on and lens.Health > 0)
	end
end

local function setTrack(lens, track)
	lens.Track = track
	lens.Mode = if track then "Track" else lens.Mode
	beacon:SetAttribute(lens.Attr, if track then track.Player.UserId else 0)
end

local function linger(lens, now)
	setTrack(lens, nil)
	lens.Mode = "Linger"
	lens.LingerUntil = now + SEEN.Linger
end

local function setSeen(p, value)
	value = math.clamp(value, 0, 1)
	local old = seen[p] or 0
	seen[p] = value
	if math.abs(value - (p:GetAttribute("BeaconSeen") or 0)) > 0.01 or (value == 0 and old ~= 0) or value == 1 then
		p:SetAttribute("BeaconSeen", value)
	end
end

local function clearSeen()
	for _, p in Players:GetPlayers() do
		seen[p] = 0
		p:SetAttribute("BeaconSeen", nil)
		p:SetAttribute("BeaconCaughtAt", nil)
	end
end

-- Moves a lens's beam toward a ground point at most speed studs a second; returns the beam's
-- start and end.
local function aimLens(lens, want, speed, dt)
	local point = lens.Point or want
	local step = want - point
	local maxStep = speed * dt
	point = if step.Magnitude > maxStep then point + step.Unit * maxStep else want
	lens.Point = point
	local from = lens.Part.Position
	local dir = (point - from)
	dir = if dir.Magnitude > 0.01 then dir.Unit else -Vector3.yAxis
	local hit = workspace:Raycast(from, dir * CFG.BeamReach, rayParams)
	local tipPos = if hit then hit.Position else from + dir * CFG.BeamReach
	lens.Tip.CFrame = CFrame.new(tipPos + Vector3.new(0, 1.5, 0))
	return from, tipPos
end

-- Whether a player stands inside a lamp's beam (a strip on the ground that widens toward the
-- far end) with nothing in between.
local function inBeam(from, tipPos, e)
	local seg = flat(tipPos - from)
	local len = seg.Magnitude
	if len <= 0.5 then
		return false
	end
	local rel = flat(e.Root.Position - from)
	local along = rel:Dot(seg / len)
	if along < len * 0.1 or along > len + 5 then
		return false
	end
	local side = (rel - seg / len * along).Magnitude
	local width = CFG.BeamWidth * math.clamp(along / len, 0.35, 1)
	return side <= width and canSee(from, e.Root.Position + Vector3.new(0, 1.5, 0))
end

-- How many players are in the match, for the PerPlayer numbers.
local function extraPlayers()
	local n = 0
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InMatch") then
			n += 1
		end
	end
	return math.max(0, n - 1)
end

-- Hearing --------------------------------------------------------------------------------

local function hear(at, radius)
	if state ~= "Hunt" then
		return
	end
	local d = Vector3.new(at.X - pos.X, 0, at.Z - pos.Z).Magnitude
	if d <= radius then
		goal = Vector3.new(at.X + math.random(-8, 8), pos.Y, at.Z + math.random(-8, 8))
		goalIsNoise = true
	end
end

ServerStorage.Events.Gunshot.Event:Connect(function(player, origin)
	lastShot[player] = os.clock()
	hear(origin, CFG.Hearing.Shot)
end)

-- Venting: the lamps overheat and it stands blind for a while -------------------------------

local function startVent(now)
	setState("Vent")
	ventEnds = now + CFG.VentTime
	for _, lens in lenses do
		setTrack(lens, nil)
		lens.Mode = "Sweep"
		setLight(lens, LIGHT_VENT, 0.35)
	end
	setSteam(true)
	siren.PlaybackSpeed = sirenSpeed * 0.7
	SoundKit.Play("Beacon/Charge", { Position = pos + Vector3.new(0, 30, 0), Speed = 0.55 })
end

local function endVent(now)
	setState("Hunt")
	nextVent = now + CFG.VentEvery.Min + math.random() * (CFG.VentEvery.Max - CFG.VentEvery.Min)
	for _, lens in lenses do
		setLight(lens, LIGHT_IDLE, 1)
	end
	setSteam(false)
	siren.PlaybackSpeed = sirenSpeed
	SoundKit.Play("Beacon/Alarm", { Position = pos + Vector3.new(0, 30, 0) })
end

-- Weak points ----------------------------------------------------------------------------

local function fall()
	setState("Dead")
	for _, lens in lenses do
		setTrack(lens, nil)
	end
	setBeams(false)
	setSteam(false)
	siren:Stop()
	chase = nil
	beacon:SetAttribute("Chasing", 0)
	clearSeen()
	SoundKit.Play("Beacon/Collapse", { Position = pos + Vector3.new(0, 10, 0) })
	-- Topples backwards about its feet.
	local back = -flatDir(heading)
	local axis = Vector3.new(back.Z, 0, -back.X) -- right of the fall direction
	local start = root.CFrame
	local t = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		t = math.min(t + dt / 2.4, 1)
		local a = math.rad(84) * (t * t)
		root.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(axis, -a) * CFrame.new(-pos) * start
		if t >= 1 then
			conn:Disconnect()
			SoundKit.Play("Beacon/Step", { Position = pos + back * 30 })
		end
	end)
	for _, entry in playersInMatch() do
		Points.Add(entry.Player, CFG.KillPoints)
	end
	Remotes.Match:FireAllClients("BeaconDown")
end

ServerStorage.Events.WorldShot.Event:Connect(function(player, part, hitPos, damage)
	if state == "Asleep" or state == "Dead" then
		return
	end
	for _, lens in lenses do
		if lens.Part == part and lens.Health > 0 then
			if state ~= "Vent" then
				-- Shuttered: the round sparks off, and it looks your way.
				SoundKit.Play("Common/ImpactWorld", { Position = hitPos })
				local character = player.Character
				if character and character.PrimaryPart then
					goal = Vector3.new(character.PrimaryPart.Position.X, pos.Y, character.PrimaryPart.Position.Z)
					goalIsNoise = true
				end
				return
			end
			lens.Health -= damage
			SoundKit.Play("Common/HitHead", { Position = hitPos })
			local flash = TweenService:Create(part, TweenInfo.new(0.15), { Color = Color3.new(1, 1, 1) })
			flash:Play()
			flash.Completed:Once(function()
				if lens.Health > 0 then
					part.Color = saved[part].Color
				end
			end)
			if lens.Health <= 0 then
				part.Color = LENS_DEAD
				part.Material = Enum.Material.Glass
				for _, light in part:GetChildren() do
					if light:IsA("Light") then
						light.Enabled = false
					end
				end
				setTrack(lens, nil)
				part:SetAttribute("LampOn", false)
				SoundKit.Play("World/GlassBreak", { Position = hitPos })
				Points.Add(player, math.floor(CFG.KillPoints / 4))
				if #liveLenses() == 0 then
					fall()
				else
					Remotes.Match:FireAllClients("LensOut")
				end
			end
			return
		end
	end
end)

-- Smashing the town ----------------------------------------------------------------------

local town = workspace:WaitForChild("Map"):WaitForChild("Town")
local buildings = town:WaitForChild("Buildings")
local smashParams = OverlapParams.new()
smashParams.FilterType = Enum.RaycastFilterType.Include
smashParams.FilterDescendantsInstances = { buildings }

-- Where it can't walk: each building's footprint (and the house's), taken once while the
-- town stands, widened by its body. It walks the streets and only ever smashes from outside.
local footprints = {} -- { Model, CFrame, Half }
do
	local list = buildings:GetChildren()
	for _, child in workspace.Map:GetChildren() do
		if child:GetAttribute("DefendHouse") then
			table.insert(list, child)
		end
	end
	for _, model in list do
		if model:IsA("Model") then
			local cf, size = model:GetBoundingBox()
			table.insert(footprints, {
				Model = model,
				CFrame = cf,
				Half = Vector3.new(size.X / 2 + CFG.BodyRadius, 0, size.Z / 2 + CFG.BodyRadius),
			})
		end
	end
	for _, part in CollectionService:GetTagged("BeaconNoGo") do
		if part:IsA("BasePart") then
			table.insert(footprints, {
				Model = part,
				CFrame = part.CFrame,
				Half = Vector3.new(part.Size.X / 2 + CFG.BodyRadius, 0, part.Size.Z / 2 + CFG.BodyRadius),
			})
		end
	end
end

local function inFootprint(f, p)
	local rel = f.CFrame:PointToObjectSpace(Vector3.new(p.X, f.CFrame.Y, p.Z))
	return math.abs(rel.X) < f.Half.X and math.abs(rel.Z) < f.Half.Z
end

local function blocked(p)
	for _, f in footprints do
		if inFootprint(f, p) then
			return f
		end
	end
	return nil
end

-- The nearest point just outside a building, heading out from its middle toward `toward`.
local function outsidePoint(model, toward)
	for _, f in footprints do
		if f.Model == model then
			local center = Vector3.new(f.CFrame.X, toward.Y, f.CFrame.Z)
			local out = flat(toward - center)
			out = if out.Magnitude > 0.1 then out.Unit else Vector3.new(0, 0, 1)
			local p = center
			for _ = 1, 100 do
				if not inFootprint(f, p) then
					break
				end
				p += out * 2
			end
			return p + out * 2, center
		end
	end
	return nil
end

local loose = {} -- [part] = how it stood: { CFrame, CanCollide, Group }
local settling = {} -- { Part, At }, oldest first
local smash = nil -- { Until, HitAt, Hit, Face } while both arms come down on a building
local smashTarget = nil -- the building model it's walking up to
local grab = nil -- { Player, Root, Character, Start, From } while it lifts someone it caught

-- Knocks loose up to max building pieces within radius of center, flung away from `from`.
local function smashAt(center, radius, max, from, params)
	local found = workspace:GetPartBoundsInRadius(center, radius, params or smashParams)
	table.sort(found, function(a, b)
		return (a.Position - center).Magnitude < (b.Position - center).Magnitude
	end)
	local n = 0
	for _, part in found do
		if n >= max then
			break
		end
		-- Floors, stairs and foundations stay; so does anything huge.
		local structural = part.Name:find("Floor") or part.Name:find("Slab") or part.Name:find("Stair")
		if not loose[part] and not structural and part.Anchored and part.Size.Magnitude < 70 and part.Position.Y - part.Size.Y / 2 > 0.8 then
			n += 1
			loose[part] = { CFrame = part.CFrame, CanCollide = part.CanCollide, Group = part.CollisionGroup }
			part.Anchored = false
			part.CanCollide = true
			part.CollisionGroup = "Debris"
			local away = flat(part.Position - from)
			away = if away.Magnitude > 0.1 then away.Unit else flatDir(heading)
			part.AssemblyLinearVelocity = away * (18 + math.random() * 26) + Vector3.new(0, 10 + math.random() * 24, 0)
			part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8
			table.insert(settling, { Part = part, At = os.clock() + SMASH.Settle })
		end
	end
	if n > 0 then
		SoundKit.Play("World/WoodBreak", { Position = center, Volume = 1.8, Speed = 0.7 })
		if n > 10 then
			SoundKit.Play("Beacon/Step", { Position = center, Volume = 1.6 })
			SoundKit.Play("World/GlassBreak", { Position = center })
		end
	end
	return n
end

-- Rubble that has come to rest is pinned where it lies, so it stops costing physics.
local function settle(now)
	while settling[1] and settling[1].At <= now do
		local entry = table.remove(settling, 1)
		if entry.Part.Parent and loose[entry.Part] then
			entry.Part.Anchored = true
		end
	end
end

-- Puts every knocked-out piece back (each match).
local function restoreTown()
	for part, s in loose do
		if part.Parent then
			part.Anchored = true
			part.CFrame = s.CFrame
			part.CanCollide = s.CanCollide
			part.CollisionGroup = s.Group
		end
	end
	table.clear(loose)
	table.clear(settling)
	smash, smashTarget = nil, nil
	beacon:SetAttribute("Smash", nil)
	if grab then
		if grab.Root.Parent then
			grab.Root.Anchored = false
			grab.Character:SetAttribute("Grabbed", nil)
		end
		grab = nil
	end
	beacon:SetAttribute("GrabAt", nil)
end

local function startSmash(now, face)
	smash = { Until = now + SMASH.Time, HitAt = now + SMASH.HitAt, Hit = false, Face = face }
	beacon:SetAttribute("Smash", true)
	SoundKit.Play("Beacon/Charge", { Position = pos + Vector3.new(0, 30, 0), Speed = 0.8 })
end

local function buildingBox(model)
	local cf, size = model:GetBoundingBox()
	return Vector3.new(cf.X, pos.Y, cf.Z), math.max(size.X, size.Z) / 2
end

-- The pickup --------------------------------------------------------------------------------

local evacPlaced = false

local function zonePos()
	-- Outbreak sends the helicopter to any landing pad (MatchServer's EvacZone).
	local at = workspace:GetAttribute("EvacZone")
	if typeof(at) == "Vector3" then
		return at
	end
	local extraction = workspace.Map:FindFirstChild("Extraction")
	local zone = extraction and extraction:FindFirstChild("Zone")
	return zone and zone.Position
end

-- Seconds since the helicopter reached the zone and when it climbs away (both relative), or nil.
local function evacTimes()
	local at = workspace:GetAttribute("EvacAt")
	if not at then
		return nil
	end
	local leave = workspace:GetAttribute("EvacLeaveAt")
	return workspace:GetServerTimeNow() - at, if leave then leave - at else EvacPath.DefaultLeave
end

-- Wake and sleep -------------------------------------------------------------------------

local function reset()
	setState("Asleep")
	roamTo = nil
	beacon:SetAttribute("Moving", false)
	beacon:SetAttribute("Chasing", 0)
	goal = nil
	chase = nil
	pos = parkCf.Position
	heading = 0
	root.CFrame = parkCf
	siren:Stop()
	siren.PlaybackSpeed = sirenSpeed
	setSteam(false)
	for inst, s in saved do
		if inst:IsA("BasePart") then
			inst.Color = s.Color
			inst.Material = s.Material
		else
			inst.Enabled = false
		end
	end
	for _, lens in lenses do
		lens.Health = CFG.LensHealth
		lens.Point = nil
		lens.Mode = "Sweep"
		setTrack(lens, nil)
		setLight(lens, LIGHT_IDLE, 1)
	end
	setBeams(false)
	clearSeen()
	nextVent = math.huge
	restoreTown()
	evacPlaced = false
	beacon:SetAttribute("Run", nil)
	beacon:SetAttribute("Reach", nil)
end

local function wake()
	reset()
	setState("Hunt")
	for inst, s in saved do
		if inst:IsA("Light") then
			inst.Enabled = s.Enabled
			inst.Brightness = s.Brightness
		end
	end
	-- More players (and Nightmare), tougher lenses.
	local health = math.floor(CFG.LensHealth * (1 + CFG.PerPlayer.LensHealth * extraPlayers()) * (workspace:GetAttribute("ModeLensHealth") or 1))
	for _, lens in lenses do
		lens.Health = health
		lens.MaxHealth = health
	end
	setBeams(true)
	siren:Play()
	SoundKit.Play("Beacon/Alarm", { Position = pos + Vector3.new(0, 30, 0) })
	goal = Vector3.new(CFG.Start.X, pos.Y, CFG.Start.Z)
	goalIsNoise = false
	nextVent = os.clock() + CFG.VentEvery.Max

	-- The reveal: it stands just past the building nearest the house and tears into it while
	-- everyone watches.
	local map = workspace:FindFirstChild("Map")
	local home
	for _, child in map and map:GetChildren() or {} do
		if child:GetAttribute("DefendHouse") then
			home = child:GetPivot().Position
		end
	end
	local nearest, nearestDist
	for _, model in buildings:GetChildren() do
		if model:IsA("Model") and home then
			local at = buildingBox(model)
			local d = flat(at - home).Magnitude
			if not nearest or d < nearestDist then
				nearest, nearestDist = model, d
			end
		end
	end
	if nearest then
		local at = buildingBox(nearest)
		local ground = Vector3.new(at.X, parkCf.Position.Y, at.Z)
		local outside, center = outsidePoint(nearest, ground + flat(at - home).Unit * 200)
		pos = outside or ground
		heading = angleOf((center or at) - pos)
		place()
		goal = nil
		smashTarget = nil
		startSmash(os.clock() + 1.1, center)
	end
end

workspace:GetAttributeChangedSignal("Breakout"):Connect(function()
	if workspace:GetAttribute("Breakout") then
		wake()
	else
		reset()
	end
end)
reset()

-- Seeing you: the chase ------------------------------------------------------------------

local function startChase(e, now)
	chase = { Player = e.Player, Root = e.Root, Ends = now + CFG.Caught.Time }
	setState("Chase")
	beacon:SetAttribute("Chasing", e.Player.UserId)
	e.Player:SetAttribute("BeaconCaughtAt", workspace:GetServerTimeNow() + CFG.Caught.Time)
	for _, lens in liveLenses() do
		setTrack(lens, { Player = e.Player, Root = e.Root, Character = e.Character })
		setLight(lens, LIGHT_ALERT, 1.3)
	end
	siren.PlaybackSpeed = sirenSpeed * 1.25
	SoundKit.Play("Beacon/Alarm", { Position = pos + Vector3.new(0, 30, 0), Volume = 1.4 })
	SoundKit.Play("Beacon/Charge", { Position = e.Root.Position })
end

-- Nights: a catch costs points, not your life. Dropped in the yard, the dark lifts (BeaconClient).
local yardIndex = 0
local function throwToYard(player, character)
	local yard = workspace.Map:FindFirstChild("Yard")
	if not yard then
		return false
	end
	Points.Spend(player, math.floor(Points.Get(player) * GameConfig.Nights.CaughtCost))
	yardIndex += 1
	local angle = yardIndex * 2.4
	local at = yard.Position + Vector3.new(math.cos(angle) * 4, 3.5, math.sin(angle) * 4)
	local look = yard.Position + yard.CFrame.LookVector * 20
	local drop = ServerStorage:FindFirstChild("DropPart")
	if drop then
		drop:Fire(player)
	end
	character:PivotTo(CFrame.lookAt(at, Vector3.new(look.X, at.Y, look.Z)))
	PlayerHealth.Protect(player, 3)
	SoundKit.Play("Beacon/Step", { Position = at, Volume = 1.3 })
	Remotes.Match:FireClient(player, "Thrown")
	return true
end

local function endChase(now)
	local c = chase
	chase = nil
	beacon:SetAttribute("Chasing", 0)
	siren.PlaybackSpeed = sirenSpeed
	if c and c.Player.Parent and workspace:GetAttribute("Nights") then
		local character = c.Root.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not PlayerHealth.IsDowned(c.Player) and throwToYard(c.Player, character) then
			SoundKit.Play("Beacon/Blast", { Position = c.Root.Position })
		elseif humanoid and humanoid.Health > 0 and PlayerHealth.Take(c.Player) then
			SoundKit.Play("Beacon/Blast", { Position = c.Root.Position })
			Remotes.Match:FireAllClients("Taken", c.Player.DisplayName)
		end
		c.Player:SetAttribute("BeaconCaughtAt", nil)
		setSeen(c.Player, 0)
	elseif c and c.Player.Parent then
		local humanoid = c.Root.Parent and c.Root.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and PlayerHealth.Take(c.Player) then
			SoundKit.Play("Beacon/Blast", { Position = c.Root.Position })
			Remotes.Match:FireAllClients("Taken", c.Player.DisplayName)
		end
		c.Player:SetAttribute("BeaconCaughtAt", nil)
		setSeen(c.Player, 0)
	end
	setState("Hunt")
	for _, lens in liveLenses() do
		setLight(lens, LIGHT_IDLE, 1)
		linger(lens, now)
	end
	goal = nil
	goalIsNoise = false
end

-- Asleep in a running nights match (before the first lull): it walks GameConfig.Beacon.Roam's
-- far-off line, lamps dark, so it's never a statue in view. Out of a match it stands parked.
local function roam(dt)
	local waveState = workspace:GetAttribute("WaveState")
	if workspace:GetAttribute("Nights") ~= true or (waveState ~= "Wave" and waveState ~= "Intermission") then
		if roamTo then
			roamTo = nil
			pos = parkCf.Position
			heading = 0
			root.CFrame = parkCf
			beacon:SetAttribute("Moving", false)
		end
		return
	end
	local r = CFG.Roam
	if not roamTo then
		pos = Vector3.new(r.From.X, parkCf.Position.Y, r.From.Z)
		roamTo = r.To
		heading = angleOf(r.To - r.From)
	end
	local to = flat(Vector3.new(roamTo.X, pos.Y, roamTo.Z) - pos)
	if to.Magnitude < 4 then
		roamTo = if roamTo == r.To then r.From else r.To
		to = flat(Vector3.new(roamTo.X, pos.Y, roamTo.Z) - pos)
	end
	local diff = (angleOf(to) - heading + math.pi) % (2 * math.pi) - math.pi
	local turn = CFG.TurnSpeed * 0.5 * dt
	heading += math.clamp(diff, -turn, turn)
	local moving = math.abs(diff) < math.rad(40)
	if moving then
		pos += flatDir(heading) * r.Speed * dt
	end
	place()
	beacon:SetAttribute("Moving", moving)
	if moving and os.clock() >= stepAt then
		stepAt = os.clock() + CFG.StepEvery
		SoundKit.Play("Beacon/Step", { Position = pos, Volume = 0.6 })
	end
end

-- The loop -------------------------------------------------------------------------------

-- A random spot on the streets.
local function wanderGoal()
	local b = CFG.Bounds
	local p
	for _ = 1, 12 do
		p = Vector3.new(b.Min.X + math.random() * (b.Max.X - b.Min.X), pos.Y, b.Min.Y + math.random() * (b.Max.Y - b.Min.Y))
		if not blocked(p) then
			break
		end
	end
	return p
end

local function turnToward(target, dt, rate)
	local want = angleOf(target - pos)
	local diff = (want - heading + math.pi) % (2 * math.pi) - math.pi
	local stepTurn = (rate or CFG.TurnSpeed) * dt
	heading += math.clamp(diff, -stepTurn, stepTurn)
	return math.abs(diff)
end

local function clampToBounds(p)
	local b = CFG.Bounds
	return Vector3.new(math.clamp(p.X, b.Min.X, b.Max.X), p.Y, math.clamp(p.Z, b.Min.Y - 20, b.Max.Y))
end

-- Walks toward target at speed along the streets: straight if it can, otherwise the smallest
-- turn to one side that keeps clear of every building (it sticks to the side it picked so it
-- goes round a block instead of dithering). Returns whether it moved.
local avoidSide = 1
local function moveToward(target, speed, dt, rate, stopAt, clamp)
	local to = flat(target - pos)
	local dist = to.Magnitude
	if dist <= stopAt + 0.05 then
		turnToward(target, dt, rate)
		return false
	end
	local step = math.min(speed * dt, dist - stopAt)
	local want = angleOf(to)
	local chosen
	local inside = blocked(pos)
	if inside then
		-- Somehow inside a footprint: straight out the nearest way.
		chosen = angleOf(flat(pos - inside.CFrame.Position))
	else
		for _, off in { 0, 0.35, 0.7, 1.05, 1.4, 1.8, 2.3, 2.8 } do
			for _, sign in (if off == 0 then { 1 } else { avoidSide, -avoidSide }) do
				local a = want + off * sign
				if not blocked(pos + flatDir(a) * math.max(step, 10)) then
					chosen = a
					if off > 0 then
						avoidSide = sign
					end
					break
				end
			end
			if chosen then
				break
			end
		end
	end
	if not chosen then
		turnToward(target, dt, rate)
		return false
	end
	local diff = (chosen - heading + math.pi) % (2 * math.pi) - math.pi
	heading += math.clamp(diff, -rate * dt, rate * dt)
	local k = if math.abs(diff) < math.rad(50) then 1 else 0.35
	local nextPos = pos + flatDir(chosen) * step * k
	if clamp then
		nextPos = clampToBounds(nextPos)
	end
	if not inside and blocked(nextPos) then
		return false
	end
	pos = nextPos
	return true
end

-- The ground point a sweeping lamp is aiming at right now.
local function sweepPoint(lens, dt)
	lens.Phase += dt * CFG.SweepSpeed * lens.Speed
	local swing = math.sin(lens.Phase) * CFG.Sweep + lens.Side * math.rad(9)
	local reach = 55 + math.sin(lens.Phase * lens.ReachSpeed / lens.Speed + lens.Side) * 28
	return pos + flatDir(heading + swing) * reach
end

local function groundUnder(root)
	return Vector3.new(root.Position.X, root.Position.Y - 2.5, root.Position.Z)
end

-- While the helicopter comes in, both lamps circle the landing zone.
local function zoneSweep(lens, dt, zone)
	lens.Phase += dt * CFG.SweepSpeed * lens.Speed * 1.5
	return zone + Vector3.new(math.cos(lens.Phase + lens.Side), 0, math.sin(lens.Phase * 1.3 + lens.Side)) * 14
end

-- A building to walk to and tear into.
local function pickBuilding()
	local list = {}
	for _, m in buildings:GetChildren() do
		if m:IsA("Model") then
			table.insert(list, m)
		end
	end
	if #list == 0 then
		return nil
	end
	local m = list[math.random(#list)]
	local at = outsidePoint(m, pos)
	if not at or (clampToBounds(at) - at).Magnitude > 1 then
		return nil
	end
	return m, at
end

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Caught: it bends down, closes a hand round them (tearing off any wall in the way) and lifts
-- them up to its lamps; then the dark (endChase takes them). Everyone sees it.
local grabParams = OverlapParams.new()
grabParams.FilterType = Enum.RaycastFilterType.Include

local function startGrab(c, now)
	local character = c.Root.Parent
	grab = { Player = c.Player, Root = c.Root, Character = character, Start = now, From = c.Root.Position }
	c.Root.Anchored = true
	character:SetAttribute("Grabbed", true)
	beacon:SetAttribute("GrabAt", workspace:GetServerTimeNow())
	local include = { buildings }
	for _, f in footprints do
		if f.Model:GetAttribute("DefendHouse") then
			table.insert(include, f.Model)
		end
	end
	grabParams.FilterDescendantsInstances = include
	smashAt(c.Root.Position:Lerp(Vector3.new(pos.X, c.Root.Position.Y, pos.Z), 0.25) + Vector3.new(0, 3, 0), 11, 30, pos, grabParams)
	SoundKit.Play("Beacon/Charge", { Position = c.Root.Position, Speed = 0.6, Volume = 1.3 })
end

local function stepGrab(now, dt)
	local g = grab
	local k = (now - g.Start) / CFG.Caught.Grab
	if k >= 1 or not g.Root.Parent then
		grab = nil
		beacon:SetAttribute("GrabAt", nil)
		if g.Root.Parent then
			g.Character:SetAttribute("Grabbed", nil)
			g.Root.Anchored = false
		end
		endChase(now)
		return
	end
	turnToward(g.From, dt, CFG.TurnSpeed * 4)
	-- The hand comes down (they stay put), lifts them in front of the lamps, and holds them
	-- there, shaking.
	local hand = pos + flatDir(heading) * 9 + Vector3.new(0, 23, 0)
	local up = smooth((k - 0.3) / 0.35)
	local at = g.From:Lerp(hand, up)
	at += Vector3.new(math.noise(now * 7, 1), math.noise(now * 7, 2), math.noise(now * 7, 3)) * 0.7 * up
	local head = beacon.Head.Position
	g.Root.CFrame = CFrame.lookAt(at, Vector3.new(head.X, at.Y, head.Z))
end

local hearAt = 0
local filterAt = 0
RunService.Heartbeat:Connect(function(dt)
	if state == "Asleep" then
		roam(dt)
		return
	elseif state == "Dead" then
		return
	end
	local now = os.clock()
	if now >= filterAt then
		filterAt = now + 1
		refreshFilter()
	end
	local players = playersInMatch()
	-- During the reveal and the rescue cutscene it keeps moving but sees nobody.
	local waveState = workspace:GetAttribute("WaveState")
	local nights = workspace:GetAttribute("Nights") == true
	local looking = (waveState == "Breakout" or waveState == "Outbreak" or nights and (waveState == "Wave" or waveState == "Intermission"))
		and workspace:GetServerTimeNow() >= (workspace:GetAttribute("RevealUntil") or 0)

	-- The pickup: it hears the helicopter coming and goes for the zone, then for the helicopter.
	local zone = zonePos()
	local evacT, leaveRel = evacTimes()
	local evacMode = nil
	local heliPos = nil
	if zone and evacT then
		-- Outbreak's birds come and go while the match runs: it chases one only until it's gone.
		local outbreak = waveState == "Outbreak"
		if waveState == "Rescue" or (waveState == "Breakout" and evacT >= leaveRel)
			or (outbreak and evacT >= leaveRel and evacT < leaveRel + GameConfig.Breakout.Evac.Leave)
		then
			evacMode = "Rescue"
			heliPos = EvacPath.Pose(zone, evacT, leaveRel).Position
		elseif (waveState == "Breakout" or outbreak) and evacT >= -CFG.EvacStart and evacT < leaveRel then
			evacMode = "Hunt"
		end
	end
	local running, reaching = false, false

	-- Hearing: footsteps, a few times a second.
	if state == "Hunt" and now >= hearAt then
		hearAt = now + 0.25
		for _, e in players do
			local v = e.Root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local sliding = (e.Character:GetAttribute("SlideUntil") or 0) > workspace:GetServerTimeNow()
			local crouched = e.Character:GetAttribute("Crouching") and not sliding
			local radius = if sliding then CFG.Hearing.Walk
				elseif crouched then (if speed > CFG.Hearing.WalkSpeed then CFG.Hearing.Walk * 0.35 else 0)
				elseif speed > CFG.Hearing.SprintSpeed then CFG.Hearing.Sprint
				elseif speed > CFG.Hearing.WalkSpeed then CFG.Hearing.Walk
				else 0
			if radius > 0 and (e.Character:GetAttribute("Hiding") or inCover(e.Root.Position) or indoors(e)) then
				radius *= 0.3
			end
			if radius > 0 then
				hear(e.Root.Position, radius * Classes.Perk(e.Player, "Noise"))
			end
		end
	end

	-- Venting comes round on a timer, once no lamp is busy with someone.
	if state == "Hunt" and now >= nextVent and not evacMode and not smash then
		local busy = false
		for _, lens in liveLenses() do
			if lens.Track then
				busy = true
			end
		end
		if not busy then
			startVent(now)
		end
	elseif state == "Vent" and (now >= ventEnds or evacMode) then
		endVent(now)
	end

	-- Moving: standing blind while it vents, running at you once it has seen you, standing to
	-- look while a lamp follows someone, otherwise walking to the last noise or wandering.
	local moving = false
	local tracked = nil
	for _, lens in liveLenses() do
		if lens.Track then
			tracked = lens.Track.Root
		end
	end
	if state == "Chase" then
		local target = chase and chase.Root
		if grab then
			stepGrab(now, dt)
		elseif not target or not target.Parent or now >= chase.Ends then
			local character = target and target.Parent
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not character:GetAttribute("Aboard")
				and flat(target.Position - pos).Magnitude <= CFG.Caught.GrabReach
			then
				startGrab(chase, now)
			else
				endChase(now)
			end
		else
			moving = moveToward(target.Position, CFG.Caught.Sprint, dt, CFG.TurnSpeed * 4, 14, true)
		end
	elseif state == "Vent" then
		moving = false
	elseif evacMode then
		if smash or smashTarget then
			smash, smashTarget = nil, nil
			beacon:SetAttribute("Smash", nil)
		end
		local target
		if evacMode == "Hunt" then
			-- From far across town it would never make it; it comes from just out of sight.
			if not evacPlaced then
				evacPlaced = true
				if flat(zone - pos).Magnitude > 180 then
					pos = Vector3.new(zone.X, pos.Y, zone.Z) - EVAC_TO * CFG.EvacFrom
					local inside = blocked(pos)
					if inside then
						pos = outsidePoint(inside.Model, Vector3.new(zone.X, pos.Y, zone.Z)) or pos
					end
					heading = angleOf(zone - pos)
				end
			end
			target = Vector3.new(zone.X, pos.Y, zone.Z)
		else
			target = Vector3.new(heliPos.X, pos.Y, heliPos.Z)
		end
		local stopAt = if evacMode == "Hunt" then 16 else 4
		local speed = if evacMode == "Hunt" then CFG.EvacSpeed else CFG.RescueSpeed
		moving = moveToward(target, speed, dt, CFG.TurnSpeed * 3, stopAt, evacMode == "Rescue")
		running = true
		reaching = evacMode == "Rescue" and flat(heliPos - pos).Magnitude < 30
	elseif smash then
		-- Both arms come down on whatever is in front of it.
		if smash.Face then
			turnToward(smash.Face, dt, CFG.TurnSpeed * 3)
		end
		if not smash.Hit and now >= smash.HitAt then
			smash.Hit = true
			smashAt(pos + flatDir(heading) * 14 + Vector3.new(0, 14, 0), SMASH.Radius, SMASH.MaxParts, pos)
		end
		if now >= smash.Until then
			smash = nil
			beacon:SetAttribute("Smash", nil)
			nextWander = now + 2
		end
	elseif tracked then
		turnToward(tracked.Position, dt)
	else
		local home = workspace:GetAttribute("BeaconHome")
		if not goal or now >= nextWander and not goalIsNoise then
			goal = wanderGoal()
			goalIsNoise = false
			smashTarget = nil
			-- Long enough to get there: a flat timer turned it round halfway across town.
			nextWander = now + math.max(14, (goal - pos).Magnitude / CFG.WalkSpeed + 4)
			if typeof(home) == "Vector3" then
				-- The last night: it comes for the house, pacing the middle of the road out front (well
				-- clear of the house's footprint, or it dithers along the edge).
				goal = clampToBounds(Vector3.new(home.X + math.random(-30, 30), pos.Y, home.Z + 60))
				nextWander = now + 10
			-- Most of the time it has a house in mind.
			elseif math.random() < SMASH.TargetChance then
				local model, at = pickBuilding()
				if model then
					goal, smashTarget = at, model
					nextWander = now + 25
				end
			end
		end
		-- A noise from inside a building: it goes to the nearest wall of it.
		local inside = blocked(goal)
		if inside then
			goal = outsidePoint(inside.Model, pos) or goal
		end
		local toGoal = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
		if toGoal.Magnitude > (if goalIsNoise then 18 else 6) then
			moving = moveToward(goal, CFG.WalkSpeed, dt, CFG.TurnSpeed, 0, true)
			-- Wedged against a building or the hill with no way round: give up on that goal.
			if moving then
				stuckSince = nil
			else
				stuckSince = stuckSince or now
				if now - stuckSince > 1.5 then
					stuckSince = nil
					goal, goalIsNoise, smashTarget = nil, false, nil
					nextWander = now
				end
			end
		else
			goal = nil
			goalIsNoise = false
			nextWander = now + 2
			if smashTarget then
				local _, center = outsidePoint(smashTarget, pos)
				smashTarget = nil
				startSmash(now, center)
			end
		end
	end
	place()
	beacon:SetAttribute("Moving", moving)
	beacon:SetAttribute("Run", running or nil)
	beacon:SetAttribute("Reach", reaching or nil)
	settle(now)
	if moving and now >= stepAt then
		stepAt = now + (if state == "Chase" or running then CFG.StepEvery * 0.35 else CFG.StepEvery)
		SoundKit.Play("Beacon/Step", { Position = pos })
	end

	-- The lamps.
	local rates = {}
	for _, lens in liveLenses() do
		local from, tipPos
		if state == "Vent" then
			-- Drooping to the ground in front of it, dim.
			from, tipPos = aimLens(lens, pos + flatDir(heading + lens.Side * 0.25) * 18, 20, dt)
		elseif heliPos then
			-- Blazing up into the cabin as it climbs away.
			from, tipPos = aimLens(lens, heliPos + Vector3.new(lens.Side * 3, 0, 0), 90, dt)
		elseif lens.Mode == "Track" and lens.Track then
			local t = lens.Track
			from, tipPos = aimLens(lens, groundUnder(t.Root), if state == "Chase" then 200 else CFG.TrackSpeed, dt)
			if state ~= "Chase" then
				local e = { Player = t.Player, Root = t.Root, Character = t.Character }
				local alive = t.Player.Parent and t.Root.Parent and t.Player:GetAttribute("InMatch")
				local inside = alive and looking and exposure(e) > 0 and inBeam(from, tipPos, e)
				if inside then
					t.LostAt = nil
				else
					t.LostAt = t.LostAt or now
					if not alive or now - t.LostAt > 0.3 then
						-- Lost them: it walks over to where they were.
						if alive then
							goal = Vector3.new(t.Root.Position.X, pos.Y, t.Root.Position.Z)
							goalIsNoise = true
						end
						linger(lens, now)
					end
				end
			end
		elseif lens.Mode == "Linger" then
			from, tipPos = aimLens(lens, if evacMode then zoneSweep(lens, dt, zone) else lens.Point or sweepPoint(lens, 0), 6, dt)
			if now >= lens.LingerUntil then
				lens.Mode = "Sweep"
			end
		else
			from, tipPos = aimLens(lens, if evacMode then zoneSweep(lens, dt, zone) else sweepPoint(lens, dt), 60, dt)
		end

		-- Who this lamp can see right now.
		if state == "Hunt" and looking and from then
			for _, e in players do
				local expose = exposure(e)
				if expose > 0 and inBeam(from, tipPos, e) then
					local d = (e.Root.Position - lens.Part.Position).Magnitude
					local touch = if e.Player:GetAttribute("InputMode") == "Touch" then SEEN.Touch else 1
					local modeFill = workspace:GetAttribute("ModeSeenFill") or 1
					rates[e.Player] = (rates[e.Player] or 0) + SEEN.Fill * movingScale(e) * rangeScale(d) * expose * touch * modeFill * Classes.Perk(e.Player, "SeenFill")
					if lens.Mode ~= "Track" then
						setTrack(lens, { Player = e.Player, Root = e.Root, Character = e.Character })
						SoundKit.Play("Beacon/Charge", { Position = e.Root.Position, Volume = 0.6 })
					end
				end
			end
		end
	end

	-- The meters: fill in a beam, drain out of every beam after a beat; frozen in a chase.
	if state ~= "Chase" then
		for _, e in players do
			local p = e.Player
			local rate = rates[p]
			if rate then
				seenAt[p] = now
				setSeen(p, (seen[p] or 0) + rate * dt)
				if (seen[p] or 0) >= 1 then
					startChase(e, now)
					break
				end
			elseif now - (seenAt[p] or 0) > SEEN.DrainDelay and (seen[p] or 0) > 0 then
				setSeen(p, seen[p] - SEEN.Drain * dt)
			end
		end
	end

	-- Lamp colour: warm while searching, reddening on whoever it follows.
	if state == "Hunt" then
		for _, lens in liveLenses() do
			local t = lens.Track
			local k = if t then seen[t.Player] or 0 else 0
			setLight(lens, LIGHT_IDLE:Lerp(LIGHT_ALERT, k), 1 + 0.3 * k)
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	seen[p] = nil
	seenAt[p] = nil
	lastShot[p] = nil
	roofCache[p] = nil
end)
