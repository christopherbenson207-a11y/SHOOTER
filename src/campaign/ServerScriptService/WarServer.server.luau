-- Operation Last Light: the WAR campaign in its own place (HORROR-SHOOTER-WAR.md). Three missions
-- on the winter map for HOUND, twelve soldiers: the players plus bots in the slots no player holds,
-- against twelve Lamplighters at a time (Modules.Battle, horror-shooter/war/BATTLE-PLAN.md). A
-- player joining mid-run takes a bot's place where it stands; a player leaving gives it back.
--   The story (Modules.WarStory): HOUND's transport is shot down (Modules.CrashIntro, if installed)
--   and Captain HALE is badly hurt. The squad carries him up the valley on a stretcher while it
--   fights for medicine; it gets there too late and he dies; then HOUND is cut down at the LZ and
--   only the players get out.
--   HOT DROP: up from the crash, through the road contact, clear the depot, find morphine for HALE.
--   SIGNAL: take the plaza (a Lamplighter tank rolls in: a satchel on its back deck kills it), find
--   blood in the clinic (HALE dies), patch into the relay mast, hold it while it transmits.
--   LAST LIGHT: no more reinforcements; push through the yards past another tank to the basin, clear the LZ, call the
--   bird and hold the pad while the squad falls one by one, until it is down and the players grab
--   the ladder (EvacClient flies it, as in Outbreak). The escape plays (RescueClient), then
--   everyone goes back to the lobby place.
-- Each mission is steps; a step starts from its checkpoint, and if every player is down at once
-- the step starts again from there. A fight step is won when the Lamplighters' reserve is spent
-- and the field is clear, or two are left and a player stands on the objective.
-- Spots are parts in Map.War: Start, Checkpoint1..3 and the groups M1_Road, M1_Depot, M2_Plaza,
-- M2_Hold, M2_Road, M3_Mid, M3_LZ, M3_Road (a spot's Kind attribute picks the soldier,
-- Lamplighter if none), and <group>_Rear, where reinforcements walk in from. The mast is
-- Map.WarDressing.RelayMast, the pad Map.WarDressing.LZPad, the ammo crates every SupplyCrate in
-- Map.WarDressing. Numbers: GameConfig.War (soldiers, respawn), GameConfig.War.Battle (the battle)
-- and GameConfig.War.Campaign (this run).
-- Workspace attributes: Campaign (MenuClient deploys straight in), WaveState War, WarMission (the
-- mission's name, the HUD's big line), WarObjective (its one small line), Objective (the point
-- WarClient marks), WarProgress (0..1 while the mast transmits), EnemyLeft (Battle). HoldRespawns
-- keeps MenuServer from respawning anyone: the dead come back near the squad after War.RespawnTime.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local EvacPath = require(ReplicatedStorage.Shared.EvacPath)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Points = require(ServerStorage.Modules.Points)
local Profile = require(ServerStorage.Modules.Profile)
local Uniform = require(ServerStorage.Modules.Uniform)
local Battle = require(ServerStorage.Modules.Battle)
local CoverMap = require(ServerStorage.Modules.CoverMap)
local WarStory = require(ServerStorage.Modules.WarStory)
local Tank = require(ServerStorage.Modules.Tank)
local introModule = ServerStorage.Modules:FindFirstChild("CrashIntro")
local CrashIntro = introModule and require(introModule)
local Remotes = ReplicatedStorage.Remotes

-- A teleport that fails for one player after their profile was handed over: take the lock back so it saves again.
TeleportService.TeleportInitFailed:Connect(function(player)
	if player.Parent then
		Profile.Reclaim(player)
	end
end)

local WAR = GameConfig.War
local OP = WAR.Campaign
local BATTLE = WAR.Battle
local EVAC = GameConfig.Breakout.Evac
local RESCUE = GameConfig.Rescue

local map = workspace:WaitForChild("Map")
local warMap = map:WaitForChild("War")
local dressing = map:WaitForChild("WarDressing")
local mast = dressing:WaitForChild("RelayMast")
local padModel = dressing:WaitForChild("LZPad")
local zone = padModel:WaitForChild("Zone")
local gunsApi = ServerStorage:WaitForChild("GunsApi", 10)

workspace:SetAttribute("Campaign", true)
workspace:SetAttribute("Mode", "War")
workspace:SetAttribute("HoldRespawns", true)
Points.Start()

local evacRemote = Remotes:FindFirstChild("Evac")
if not evacRemote then
	evacRemote = Instance.new("RemoteEvent")
	evacRemote.Name = "Evac"
	evacRemote.Parent = Remotes
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function inMatch()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InMatch") then
			table.insert(list, p)
		end
	end
	return list
end

local function isAlive(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character:IsDescendantOf(workspace)
end

local function standing(player)
	return isAlive(player) and not player.Character:GetAttribute("Downed")
end

local function setState(state)
	workspace:SetAttribute("WaveState", state)
end

local function newPrompt(parent, action, object, hold)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = parent
	return prompt
end

local war = {
	step = 0,
	checkpoint = nil, -- the CFrame players start again on
	patched = false,
	called = false,
	restart = false,
	contactAt = 0,
	respawnAt = {}, -- [player] = os.clock() they come back
}
local warOn = false
local aboard = {} -- [player] = os.clock() they grabbed the ladder
local evacAt = nil
local leaveRel = EvacPath.DefaultLeave

-- Spots -------------------------------------------------------------------------------------------

-- A spot group's parts by name (a single part is a group of one).
local function warSpots(name)
	local f = warMap:FindFirstChild(name)
	local list = {}
	local kids = if not f then {} elseif f:IsA("BasePart") then { f } else f:GetChildren()
	for _, p in kids do
		if p:IsA("BasePart") then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function warSpot(name)
	return warSpots(name)[1]
end

local function centre(list)
	local sum = Vector3.zero
	for _, p in list do
		sum += p.Position
	end
	return if #list > 0 then sum / #list else Vector3.zero
end

local function say(key)
	local text = OP.Lines[key] or WAR.Lines[key] or WarStory.Lines[key]
	if text then
		Remotes.Match:FireAllClients("Radio", text, "War" .. key)
	end
end

-- A radio line made up on the spot (a callsign going down).
local function radio(text)
	Remotes.Match:FireAllClients("Radio", text, "WarCallout")
end

-- The objective: a point for the marker and its words for the HUD's small line.
local function setObjective(pos, words)
	local was = workspace:GetAttribute("Objective")
	if not (typeof(pos) == "Vector3" and typeof(was) == "Vector3" and (pos - was).Magnitude < 2) then
		workspace:SetAttribute("Objective", pos)
	end
	workspace:SetAttribute("WarObjective", words)
end

local function checkpoint(name)
	local spot = warSpot(name)
	if spot then
		war.checkpoint = spot.CFrame + Vector3.new(0, 3.5, 0)
	end
end

-- The squad ---------------------------------------------------------------------------------------
-- Battle keeps a bot in every one of HOUND's slots no player holds.

-- "Contact!" on the radio when a bot first has the enemy in sight (not more often than ContactGap).
Battle.OnContact = function()
	if os.clock() >= war.contactAt then
		war.contactAt = os.clock() + WAR.ContactGap
		say("Contact")
	end
end

-- Where a (re)spawning player lands.
local function warSpawn(player)
	local start = warSpot("Start")
	local home = if start then start.CFrame + Vector3.new(0, 3.5, 0) else CFrame.new(0, 120, 0)
	if not warOn then
		return home
	end
	-- Joining: a bot's slot, and its place where it stands.
	local cf, callsign = Battle.Claim(player)
	if callsign then
		Remotes.Match:FireAllClients("Notice", string.upper(player.DisplayName) .. " TAKES " .. callsign .. "'S PLACE")
	end
	if cf then
		return cf
	end
	if war.restart and war.checkpoint then
		return war.checkpoint
	end
	-- Back in: next to a standing player, else the checkpoint.
	for _, p in inMatch() do
		local root = p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and standing(p) and not aboard[p] then
			return root.CFrame * CFrame.new(3, 0, 3)
		end
	end
	return war.checkpoint or home
end

-- The kit (AK in hand, Pistol, Bandage) is this place's GameConfig.Inventory.Start and Loadout
-- order, so the inventory, GunServer and GunClient all start every life on the AK.
local function placeCharacter(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	task.wait()
	local cf = warSpawn(player)
	if cf and character.Parent then
		character:PivotTo(cf)
		PlayerHealth.Protect(player, 3)
	end
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		if player:GetAttribute("InMatch") then
			placeCharacter(player, character)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end

Players.PlayerRemoving:Connect(function(player)
	aboard[player] = nil
	war.respawnAt[player] = nil
	if not warOn then
		return
	end
	-- Their slot goes back to a bot, standing where they stood.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	Battle.Release(player, if root and isAlive(player) then root.CFrame else nil)
end)

-- The run between checks ------------------------------------------------------------------------

local function reach(pos, radius)
	for _, p in inMatch() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and standing(p) and flat(root.Position - pos).Magnitude <= radius and math.abs(root.Position.Y - pos.Y) < 14 then
			return true
		end
	end
	return false
end

local function wiped()
	for _, p in inMatch() do
		if standing(p) then
			return false
		end
	end
	return true
end

-- The dead come back after RespawnTime (not while the squad is boarding).
local function warTick()
	local now = os.clock()
	for _, p in inMatch() do
		if isAlive(p) then
			war.respawnAt[p] = nil
		elseif not aboard[p] then
			if not war.respawnAt[p] then
				war.respawnAt[p] = now + WAR.RespawnTime
			elseif now >= war.respawnAt[p] then
				war.respawnAt[p] = now + WAR.RespawnTime
				task.spawn(Uniform.Load, p)
			end
		end
	end
end

-- Runs the war until done() (true) or the squad wipes / everyone leaves (false).
local function warUntil(done)
	while true do
		task.wait(0.25)
		if #inMatch() == 0 then
			return false
		end
		warTick()
		if wiped() then
			return false
		end
		if done() then
			return true
		end
	end
end

-- Ammo ---------------------------------------------------------------------------------------------
-- Each SupplyCrate in the dressing refills the magazines of whoever holds E on it (once every
-- OP.AmmoGap seconds each).

local ammoUsed = {} -- [prompt] = { [player] = os.clock() it can give them ammo again }
for _, crate in dressing:GetChildren() do
	if crate.Name == "SupplyCrate" and crate:IsA("Model") then
		local body = crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart", true)
		if body then
			local prompt = newPrompt(body, "Take ammo", "Supplies", 0.4)
			prompt.Enabled = true
			ammoUsed[prompt] = {}
			prompt.Triggered:Connect(function(player)
				local now = os.clock()
				if not gunsApi or not standing(player) or now < (ammoUsed[prompt][player] or 0) then
					return
				end
				local given = gunsApi:Invoke("GiveAmmo", player) or 0
				if given > 0 then
					ammoUsed[prompt][player] = now + OP.AmmoGap
					SoundKit.Play("Pickup/Ammo", { Position = body.Position })
				end
			end)
		end
	end
end

-- The relay mast ----------------------------------------------------------------------------------

local cabinet = mast:FindFirstChild("Body", true) or mast:FindFirstChild("InstallPoint", true) or mast:FindFirstChildWhichIsA("BasePart", true)
local topLight = mast:FindFirstChild("TopLight", true)
local topColor, topMaterial = if topLight then topLight.Color else nil, if topLight then topLight.Material else nil
-- The cabinet's four lamps: red until someone patches in, green from then on.
local lamps = {}
for _, d in mast:GetDescendants() do
	if d:IsA("BasePart") and string.match(d.Name, "^Lamp%d") then
		table.insert(lamps, { Part = d, Color = d.Color })
	end
end
local function mastLamps(green)
	for _, lamp in lamps do
		lamp.Part.Color = if green then Color3.fromRGB(70, 255, 110) else lamp.Color
	end
end
local mastPrompt = newPrompt(cabinet, "Patch in", "Relay mast", OP.PatchHold)
mastPrompt.Triggered:Connect(function(player)
	if mastPrompt.Enabled and standing(player) then
		mastPrompt.Enabled = false
		war.patched = true
		mastLamps(true)
	end
end)

local function mastBlink(on)
	if topLight then
		local lit = on and math.floor(os.clock() * 2) % 2 == 0
		topLight.Material = if lit then Enum.Material.Neon else topMaterial
		topLight.Color = if lit then Color3.fromRGB(255, 50, 40) else topColor
	end
end

-- The bird ------------------------------------------------------------------------------------------
-- It flies Shared.EvacPath to the pad from EvacAt; while it hangs or crawls off with the ladder
-- down, a player at the ladder's foot can GRAB (Remotes.Evac "Grab", EvacClient): the server
-- checks the reach against the same path, carries them up and keeps them in the door. Once
-- everyone alive is aboard it leaves at once.

local flares, strobes = {}, {}
for _, d in padModel:GetDescendants() do
	if d:IsA("BasePart") and d.Name == "Flare" then
		table.insert(flares, { Part = d, Color = d.Color, Material = d.Material, Light = d:FindFirstChildWhichIsA("PointLight") })
	elseif d:IsA("PointLight") and d.Name == "StrobeLight" then
		table.insert(strobes, d)
	end
end

local function padLights(on)
	for _, f in flares do
		f.Part.Material = if on then Enum.Material.Neon else f.Material
		f.Part.Color = if on then Color3.fromRGB(255, 60, 40) else f.Color
		if f.Light then
			f.Light.Enabled = on
		end
	end
	for _, light in strobes do
		light.Enabled = false
	end
end
padLights(false)

local callBox = padModel:FindFirstChild("StrobeBox", true) or zone
local callPoint = Instance.new("Attachment")
callPoint.Name = "CallPoint"
callPoint.Parent = callBox
callPoint.WorldPosition = callBox.Position + Vector3.new(0, 1.5, 0)
local callPrompt = newPrompt(callPoint, "Call helicopter", "Landing pad", OP.CallHold)

local function evacTime()
	return if evacAt then workspace:GetServerTimeNow() - evacAt else -math.huge
end

local function evacPose(t)
	return EvacPath.Pose(zone.Position, t, leaveRel)
end

local function callBird()
	evacAt = workspace:GetServerTimeNow() + OP.LZ.Inbound
	leaveRel = EvacPath.DefaultLeave
	workspace:SetAttribute("EvacZone", zone.Position)
	workspace:SetAttribute("EvacAt", evacAt)
	workspace:SetAttribute("EvacLeaveAt", evacAt + leaveRel)
	padLights(true)
	Remotes.Match:FireAllClients("Evac")
end

callPrompt.Triggered:Connect(function(player)
	if callPrompt.Enabled and standing(player) and not evacAt then
		callPrompt.Enabled = false
		war.called = true
		callBird()
	end
end)

local function clearHeli()
	padLights(false)
	evacAt = nil
	leaveRel = EvacPath.DefaultLeave
	workspace:SetAttribute("EvacAt", nil)
	workspace:SetAttribute("EvacLeaveAt", nil)
	workspace:SetAttribute("EvacZone", nil)
	for p in aboard do
		local character = p.Character
		if character then
			character:SetAttribute("Aboard", nil)
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = false
			end
		end
	end
	table.clear(aboard)
end

evacRemote.OnServerEvent:Connect(function(player, action)
	if action ~= "Grab" or not warOn or not evacAt or aboard[player] or not player:GetAttribute("InMatch") then
		return
	end
	local t = evacTime()
	local phase = EvacPath.Phase(t, leaveRel)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if (phase ~= "Hover" and phase ~= "Crawl") or not root or not standing(player) then
		return
	end
	local door, foot = EvacPath.Ladder(evacPose(t), t, leaveRel)
	-- A little slack over the client's reach for lag.
	if flat(root.Position - foot).Magnitude > EVAC.Grab + 3 or root.Position.Y < foot.Y - 7 or root.Position.Y > door.Y then
		return
	end
	aboard[player] = os.clock()
	PlayerHealth.Protect(player, 600)
	character:SetAttribute("Aboard", true)
	root.Anchored = true
	SoundKit.Play("Bandage/Rip", { Position = foot, Speed = 0.6 })
	Remotes.Match:FireAllClients("Aboard", player.UserId)
	-- Everyone still standing is on: no reason to hang about.
	for _, p in inMatch() do
		if isAlive(p) and not aboard[p] then
			return
		end
	end
	if t + 1.2 < leaveRel then
		leaveRel = t + 1.2
		workspace:SetAttribute("EvacLeaveAt", evacAt + leaveRel)
	end
end)

-- Up the ladder, then riding in the door.
RunService.Heartbeat:Connect(function()
	if next(aboard) == nil or not evacAt then
		return
	end
	local t = evacTime()
	local pose = evacPose(t)
	local door, foot = EvacPath.Ladder(pose, t, leaveRel)
	local seat = 0
	for player, grabbedAt in aboard do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local k = math.clamp((os.clock() - grabbedAt) / EVAC.Climb, 0, 1)
			local outward = -pose.RightVector
			if k < 1 then
				local e = k * k * (3 - 2 * k)
				local at = (foot + Vector3.new(0, 3, 0)):Lerp(door + Vector3.new(0, 1.5, 0), e) + outward * 0.8
				root.CFrame = CFrame.lookAt(at, at - outward)
			else
				seat += 1
				local at = pose:PointToWorldSpace(EVAC.Door + Vector3.new(1.4, 3.2, (seat - 1) * 2.2 - 1))
				root.CFrame = CFrame.lookAt(at, at + outward)
			end
		end
	end
end)

-- The steps -------------------------------------------------------------------------------------------
-- Each returns true when done, false if the squad wiped, or (the last) the players aboard.

-- A fight for groupName's posts: HOUND's bots attack their centre in three lanes, the
-- Lamplighters hold them with the step's reserve (Battle.Pools[pool]) walking in from
-- groupName_Rear. Won when the reserve is spent and the field is clear, or two are left and a
-- player is within near of the centre; the survivors fall back and HOUND holds the ground.
-- Where the players still standing are (their middle), or nil.
local function squadCentre()
	local sum, n = Vector3.zero, 0
	for _, p in inMatch() do
		local r = standing(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			sum += r.Position
			n += 1
		end
	end
	return if n > 0 then sum / n else nil
end

-- The live enemy nearest to any player still standing, and how far: where the last of a fight is.
local function nearestFoe()
	local hostiles = workspace:FindFirstChild("Hostiles")
	if not hostiles then
		return nil, math.huge
	end
	local roots = {}
	for _, p in inMatch() do
		local r = standing(p) and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			table.insert(roots, r.Position)
		end
	end
	local best, bestD = nil, math.huge
	for _, m in hostiles:GetChildren() do
		local r = not m:GetAttribute("Dead") and m:FindFirstChild("HumanoidRootPart")
		if r then
			for _, at in roots do
				local d = (r.Position - at).Magnitude
				if d < bestD then
					best, bestD = r.Position, d
				end
			end
		end
	end
	return best, bestD
end

-- What a fight asks of the players, on the top-left line and the marker: get there, take them down,
-- then the last few with the marker on the nearest one so nobody hunts the map for a straggler.
local function guideFight(at, near, advance)
	local left = Battle.EnemyLeft()
	local foe, foeD = nearestFoe()
	if not reach(at, near * 1.8) and foeD > 70 then
		setObjective(at, advance)
	elseif left <= 3 and foe then
		setObjective(foe + Vector3.new(0, 4, 0), "FINISH THEM OFF  ·  " .. left .. " LEFT")
	else
		setObjective(at, "TAKE DOWN THE ENEMIES  ·  " .. left .. " LEFT")
	end
end

local function assault(groupName, words, sayKey, near, pool, advance)
	local posts = warSpots(groupName)
	local at = centre(posts)
	advance = advance or words
	setObjective(at, advance)
	say(sayKey)
	Battle.HoundAttack(at, near * 0.6)
	-- A few of the reserve come straight at the squad, so the shooting starts soon after the step
	-- does instead of after a long walk to the posts (the defenders hold their posts until pushed).
	local reserve = BATTLE.Pools[pool] or 0
	local screen = math.min(BATTLE.Screen or 3, reserve)
	Battle.EnemyDefend(posts, warSpots(groupName .. "_Rear"), reserve - screen)
	if screen > 0 then
		Battle.EnemyAttack(posts, screen, squadCentre() or at)
	end
	local ok = warUntil(function()
		if Battle.EnemyLeft() == 0 then
			return true
		end
		if Battle.EnemyReserve() == 0 and Battle.EnemyAlive() <= 2 and reach(at, near) then
			return true
		end
		guideFight(at, near, advance)
		return false
	end)
	if ok then
		Battle.RetireEnemies()
		Battle.HoundHold(at, BATTLE.HoldRadius)
	end
	return ok
end

-- Where a group's spots are, as points (where an attack comes from).
local function spotPoints(name)
	local list = {}
	for _, p in warSpots(name) do
		table.insert(list, p.Position)
	end
	return list
end

-- The story's medicine run in group's ground: HALE carried up beside it, a med case hidden at one of
-- the map's MedSpot parts for the group (attribute Group), else one of its posts, until a player
-- gets it to him (true) or the squad wipes (false).
local function medicine(group, what, sayKey, words)
	local posts = warSpots(group)
	local at = centre(posts)
	local hidden = {}
	for _, p in CollectionService:GetTagged("MedSpot") do
		if p:IsA("BasePart") and p:GetAttribute("Group") == group then
			table.insert(hidden, p)
		end
	end
	local lay = CoverMap.Snap(at + Vector3.new(5, 0, 5), 12) or at
	WarStory.Carry(lay, at)
	say(sayKey)
	local job = WarStory.Medicine(if #hidden > 0 then hidden else posts, what, say)
	local ok = warUntil(function()
		-- job.Target is the case where it lies (or HALE while it's carried), so the marker shows
		-- exactly where to go; its words override the search line once the case is moving.
		local pos, line = job.Target()
		setObjective(pos or at, line or words)
		return job.Done()
	end)
	job.Clean()
	if ok then
		setObjective(WarStory.HalePosition() or at, string.upper(what) .. " DELIVERED")
	end
	return ok
end

-- An enemy tank for group's fight: along the map's <group>_Tank lane if there is one, else from the
-- group's rear spawn farthest from its posts toward them. nil if there is nowhere to start it.
local function armor(group)
	local lane = Tank.Lane(group .. "_Tank")
	local start, goal = nil, nil
	if lane then
		start = lane[1]
	else
		local at = centre(warSpots(group))
		local far = -1
		for _, p in warSpots(group .. "_Rear") do
			local d = (p.Position - at).Magnitude
			if d > far then
				start, far = p.Position, d
			end
		end
		goal = at
	end
	if not start then
		return nil
	end
	local tank = Tank.Spawn("Enemy", start, {
		Lane = lane,
		Goal = goal,
		Stop = 24,
		OnDestroyed = function()
			radio("TANK'S BURNING! NICE WORK!")
		end,
	})
	task.delay(4, radio, "TANK! Get a satchel on its back deck!")
	return tank
end

-- A tank still running after its fight is the objective until it burns.
local function killTank(tank)
	if not tank or not tank.Alive then
		return true
	end
	radio("That tank's still up! Get behind it and plant a satchel!")
	return warUntil(function()
		if tank.Alive then
			setObjective(tank:Position() + Vector3.new(0, 5, 0), "DESTROY THE TANK  ·  SATCHEL ON ITS BACK DECK")
		end
		return not tank.Alive
	end)
end

local function stepRoad()
	say("NeedMorphine")
	setObjective(centre(warSpots("M1_Road")), "ADVANCE UP THE ROAD")
	task.wait(4)
	return assault("M1_Road", "PUSH TO THE DEPOT", "Drop", 30, "Road", "ADVANCE UP THE ROAD")
end

local function stepDepot()
	if not assault("M1_Depot", "CLEAR THE DEPOT", "Depot", 26, "Depot", "ADVANCE TO THE DEPOT") then
		return false
	end
	if not medicine("M1_Depot", "Medicine", "SearchMorphine", "FIND THE MEDICINE IN THE DEPOT") then
		return false
	end
	say("MorphineIn")
	task.wait(4)
	return true
end

local function stepPlaza()
	say("DepotClear")
	task.wait(2.5)
	local tank = armor("M2_Plaza")
	if not assault("M2_Plaza", "TAKE THE PLAZA", "Plaza", 28, "Plaza", "ADVANCE TO THE PLAZA") or not killTank(tank) then
		return false
	end
	if not medicine("M2_Plaza", "Blood", "SearchBlood", "FIND THE BLOOD IN THE CLINIC") then
		return false
	end
	-- Too late.
	say("BloodIn")
	setObjective(WarStory.HalePosition() or centre(warSpots("M2_Plaza")), "STAY WITH HALE")
	task.wait(8)
	WarStory.Die()
	say("HaleDead")
	task.wait(6)
	return true
end

local function stepMast()
	local roads = warSpots("M2_Road")
	war.patched = false
	mastLamps(false)
	mastPrompt.Enabled = true
	setObjective(cabinet.Position, "PATCH INTO THE RELAY MAST")
	say("Mast")
	Battle.HoundHold(cabinet.Position, BATTLE.HoldRadius, spotPoints("M2_Road"))
	if not warUntil(function()
		return war.patched
	end) then
		mastPrompt.Enabled = false
		return false
	end
	say("Hold")
	setObjective(cabinet.Position, "STAND YOUR GROUND AT THE MAST")
	local hold = OP.Hold
	local progress, sent, heavySent = 0, 0, false
	local last = os.clock()
	local ok = warUntil(function()
		local now = os.clock()
		local dt = now - last
		last = now
		-- It only transmits while someone stands by it.
		if reach(cabinet.Position, hold.Radius) then
			progress += dt
			setObjective(cabinet.Position, "STAND YOUR GROUND AT THE MAST")
		else
			setObjective(cabinet.Position, "GET BACK TO THE MAST  ·  IT ONLY SENDS WITH YOU BESIDE IT")
		end
		mastBlink(true)
		workspace:SetAttribute("WarProgress", math.clamp(progress / hold.Time, 0, 1))
		local nextWave = hold.Waves[sent + 1]
		if nextWave and progress >= nextWave then
			sent += 1
			Battle.EnemyAttack(roads, hold.Squad, cabinet.Position)
			if sent > 1 then
				say("Wave")
			end
		end
		if not heavySent and progress >= hold.HeavyAt then
			heavySent = true
			Battle.EnemyAttack(roads, 1, cabinet.Position, "Heavy")
			say("Heavy")
		end
		return progress >= hold.Time
	end)
	mastBlink(false)
	workspace:SetAttribute("WarProgress", nil)
	if ok then
		Battle.RetireEnemies()
	end
	return ok
end

local function stepYards()
	Battle.SetReinforce(false)
	say("NoHelp")
	task.wait(5)
	say("Sent")
	task.wait(3)
	local tank = armor("M3_Mid")
	return assault("M3_Mid", "PUSH THROUGH THE YARDS", "Push", 26, "Yards", "ADVANCE THROUGH THE YARDS") and killTank(tank)
end

local function stepLZ()
	if not assault("M3_LZ", "CLEAR THE LZ", "LZ", 30, "LZ", "ADVANCE TO THE LZ") then
		return false
	end
	local roads = warSpots("M3_Road")
	while true do
		clearHeli()
		war.called = false
		callPrompt.Enabled = true
		setObjective(callPoint.WorldPosition, "CALL THE BIRD")
		say("Call")
		Battle.HoundHold(zone.Position, BATTLE.HoldRadius, spotPoints("M3_Road"))
		if not warUntil(function()
			return war.called
		end) then
			callPrompt.Enabled = false
			return false
		end
		say("Called")
		setObjective(zone.Position, "STAND YOUR GROUND  ·  HOLD THE LZ")
		local sent, heavySent, inboundSaid, boardSaid = 0, false, false, false
		local nextLoss, standSaid = 7, false
		local ok = warUntil(function()
			local t = evacTime()
			local since = OP.LZ.Inbound + t -- seconds since the call
			-- The squad is cut down one by one while the bird comes in: none left when it lands.
			if since >= nextLoss then
				local left = #Battle.HoundBots()
				local name = Battle.HoundLoss()
				if name then
					radio(string.upper(name) .. " IS DOWN!")
				end
				if not standSaid and left <= 4 then
					standSaid = true
					task.delay(1.8, say, "LastStand")
				end
				nextLoss = if left > 1 then since + math.max(2.5, (OP.LZ.Inbound - since - 3) / (left - 1)) else math.huge
			end
			local phase = EvacPath.Phase(t, leaveRel)
			local blink = t > -EVAC.Inbound and t < 0 and math.floor(os.clock() * 2) % 2 == 0
			for _, light in strobes do
				light.Enabled = blink
			end
			local nextWave = OP.LZ.Waves[sent + 1]
			if nextWave and since >= nextWave then
				sent += 1
				Battle.EnemyAttack(roads, OP.LZ.Squad, zone.Position)
				if sent > 1 then
					say("Wave")
				end
			end
			if not heavySent and since >= OP.LZ.HeavyAt then
				heavySent = true
				Battle.EnemyAttack(roads, 1, zone.Position, "Heavy")
				say("Heavy")
			end
			if not inboundSaid and t >= -EVAC.Inbound then
				inboundSaid = true
				say("Inbound")
			end
			if not boardSaid and t >= 0 then
				boardSaid = true
				setObjective(zone.Position, "GET ON THE BIRD")
				say(if #Battle.HoundBots() == 0 then "Alone" else "Board")
			end
			return phase == "Leave" and t >= leaveRel + 2.5 or phase == "Gone"
		end)
		if not ok then
			return false
		end
		local escaped = {}
		for p in aboard do
			if p.Parent then
				table.insert(escaped, p)
			end
		end
		if #escaped > 0 then
			return escaped
		end
		say("Missed")
	end
end

local STEPS = {
	{ Mission = 1, Checkpoint = "Start", Run = stepRoad },
	{ Mission = 1, Checkpoint = "Start", Run = stepDepot },
	{ Mission = 2, Checkpoint = "Checkpoint1", Run = stepPlaza },
	{ Mission = 2, Checkpoint = "Checkpoint2", Run = stepMast },
	{ Mission = 3, Checkpoint = "Checkpoint2", Run = stepYards },
	{ Mission = 3, Checkpoint = "Checkpoint3", Run = stepLZ },
}

-- The run -----------------------------------------------------------------------------------------

local function award(mission)
	local amount = OP.Reward[mission]
	if not amount then
		return
	end
	for _, p in inMatch() do
		Remotes.Match:FireClient(p, "Banked", Profile.Earn(p, amount))
	end
end

local function restartStep()
	say("Failed")
	Remotes.Match:FireAllClients("Notice", "MISSION FAILED")
	task.wait(WAR.FailWait)
	Battle.ClearEnemies()
	Tank.Clear()
	clearHeli()
	callPrompt.Enabled = false
	mastPrompt.Enabled = false
	war.restart = true
	for _, p in inMatch() do
		task.spawn(Uniform.Load, p)
	end
	if war.checkpoint then
		Battle.Regroup(war.checkpoint)
	end
	task.wait(2)
	war.restart = false
end

-- The whole operation. Returns the players who got out, or {}.
local function playWar()
	warOn = true
	setState("War")
	local start = warSpot("Start")
	Battle.Start(if start then start.CFrame + Vector3.new(0, 3.5, 0) else CFrame.new(0, 120, 0))
	-- A teammate who falls stays down for the whole operation: no coming back at the next checkpoint.
	Battle.SetReinforce(false)
	-- HALE on his stretcher by the wreck, then the crash itself on every screen.
	local startPos = if start then start.Position else Vector3.new(0, 110, 0)
	local firstGoal = centre(warSpots("M1_Road"))
	WarStory.Start(CoverMap.Snap(startPos + Vector3.new(7, 0, 4), 10) or startPos + Vector3.new(7, 0, 4), firstGoal)
	if CrashIntro then
		local players = inMatch()
		for _, p in players do
			PlayerHealth.Protect(p, 40)
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = true
			end
		end
		local ok, err = pcall(CrashIntro.Play, players)
		if not ok then
			warn("WarServer: the intro failed (" .. tostring(err) .. ")")
		end
		for _, p in players do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = false
			end
		end
	end
	say("Wake")
	task.wait(4)
	-- In Studio a test can start further on (workspace attribute WarStartStep, a STEPS index).
	war.step = if RunService:IsStudio() then math.clamp(workspace:GetAttribute("WarStartStep") or 1, 1, #STEPS) else 1
	local mission = 0
	while war.step <= #STEPS and #inMatch() > 0 do
		local step = STEPS[war.step]
		if step.Mission ~= mission then
			mission = step.Mission
			workspace:SetAttribute("WarMission", WAR.Missions[mission])
			Remotes.Match:FireAllClients("Notice", WAR.Missions[mission])
		end
		checkpoint(step.Checkpoint)
		if war.checkpoint then
			Battle.SetSpawn(war.checkpoint)
		end
		-- A step that errors used to end the whole operation with no objective; now it's retried
		-- from its checkpoint like a wipe.
		local ok, result = pcall(step.Run)
		if not ok then
			warn("WarServer: step " .. war.step .. " failed (" .. tostring(result) .. "); restarting it")
			result = false
		end
		if type(result) == "table" then
			award(mission)
			return result
		elseif result then
			local nextStep = STEPS[war.step + 1]
			if not nextStep or nextStep.Mission ~= mission then
				award(mission)
			end
			war.step += 1
		elseif #inMatch() > 0 then
			-- Wiped: back to the checkpoint, the step from the top.
			restartStep()
		end
	end
	return {}
end

local function resetWar()
	warOn = false
	Battle.Stop()
	WarStory.Clear()
	Tank.Clear()
	table.clear(war.respawnAt)
	clearHeli()
	callPrompt.Enabled = false
	mastPrompt.Enabled = false
	mastBlink(false)
	mastLamps(false)
	war.step, war.checkpoint = 0, nil
	war.patched, war.called, war.restart = false, false, false
	for _, name in { "Objective", "WarObjective", "WarMission", "WarProgress", "EnemyLeft" } do
		workspace:SetAttribute(name, nil)
	end
	setState("Waiting")
end

-- Out: the escape on every screen, the completion banked, then the lobby. In Studio, where a
-- teleport can't happen, the operation starts over instead.
local function finish(escaped)
	local ids = {}
	for _, p in escaped do
		table.insert(ids, p.UserId)
	end
	say("Complete")
	for _, p in inMatch() do
		Profile.Earn(p, OP.Reward.Complete)
		Profile.SetFlag(p, "WarCleared")
		Profile.Count(p, "WarRuns")
	end
	Remotes.Match:FireAllClients("Rescue", ids)
	task.wait(RESCUE.EscapeTime + 2.6)
	local players = inMatch()
	local ok, err = false, "nobody to send"
	if #players > 0 then
		-- Hand each profile over first (save + release the session lock) so the lobby loads it at once.
		local pending = #players
		for _, p in players do
			task.spawn(function()
				pcall(Profile.SaveNow, p, true)
				pending -= 1
			end)
		end
		local t = os.clock()
		while pending > 0 and os.clock() - t < 15 do
			task.wait(0.1)
		end
		ok, err = pcall(function()
			TeleportService:TeleportAsync(OP.LobbyPlaceId, players)
		end)
	end
	if not ok then
		for _, p in players do
			task.spawn(Profile.Reclaim, p) -- take the released locks back so this server saves again
		end
		warn("WarServer: back to the lobby failed (" .. tostring(err) .. "); starting the operation over")
		clearHeli()
		for _, p in inMatch() do
			Remotes.Menu:FireClient(p, "Show")
		end
		task.wait(0.5)
		resetWar()
		for _, p in inMatch() do
			task.spawn(Uniform.Load, p)
		end
		return
	end
	task.wait(OP.OutroTime)
end

-- Cover round every spot group and checkpoint, surveyed once while the first party is in the menu.
task.spawn(function()
	local points = {}
	for _, f in warMap:GetChildren() do
		local list = warSpots(f.Name)
		if #list > 0 then
			table.insert(points, centre(list))
		end
	end
	local n = Battle.Survey(points)
	print(("WarServer: %d cover spots round %d places"):format(n, #points))
end)

while true do
	while #inMatch() == 0 do
		task.wait(0.5)
	end
	-- A party arriving together deploys together.
	task.wait(2)
	local escaped = playWar()
	if #escaped > 0 then
		finish(escaped)
	end
	resetWar()
	task.wait(1)
end
