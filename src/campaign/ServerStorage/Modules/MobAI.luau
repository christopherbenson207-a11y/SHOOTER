-- Hunting mobs: pick the nearest player, get to them, swipe (MobAttack), and feed during a
-- devour (PlayerHealth). Close and in plain sight a mob walks straight at its target;
-- otherwise it follows a PathfindingService path, which may run through fences and plank
-- barricades at a cost (PathfindingModifier labels "Vault" and "Break"), so the horde comes
-- over or through instead of walking all the way round.
-- At an obstacle it is dumb first (Left 4 Dead / CoD Zombies): it bumps into it, shuffles
-- along it and claws at it for a while, then vaults it (tag "Vaultable") or tears its boards
-- off one by one (tag "Breakable", Barricades), or shoves a closed door open (tag
-- "Door", Doors). A mob that stops making headway shuffles
-- aside and repaths. Numbers: Mobs.<type>.Navigation and .Attack.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local MobAttack = require(ServerStorage.Modules.MobAttack)
local Barricades = require(ServerStorage.Modules.Barricades)
local Doors = require(ServerStorage.Modules.Doors)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = ReplicatedStorage.Remotes

local TICK = 0.15
-- How close a mob gets to a path waypoint before heading for the next one.
local WAYPOINT_REACH = 2.5

local MobAI = {}

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function between(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

local function alive(model, humanoid)
	if model.Parent ~= nil and model.PrimaryPart == nil and humanoid.Health > 0 then
		-- Lost its root part (out of the world): it can't walk again, so it dies and stops counting.
		humanoid.Health = 0
	end
	return model.Parent ~= nil and humanoid.Health > 0 and not model:GetAttribute("Dead")
end

-- Humanoid:MoveTo gives up after 8 s, and calling it again with the very same point (a
-- player standing still) doesn't restart it, so every call nudges the goal a hair.
local function walkTo(humanoid, pos)
	if (humanoid.WalkToPoint - pos).Magnitude < 0.05 then
		pos += Vector3.new(0.1, 0, 0)
	end
	humanoid:MoveTo(pos)
end

-- Waits up to `time`, giving up early when the mob dies. Returns false if it died.
local function hold(model, humanoid, time)
	local t = 0
	while t < time do
		t += task.wait(math.min(TICK, time - t + 0.01))
		if not alive(model, humanoid) then
			return false
		end
	end
	return true
end

-- Hidden players (EvadeServer): inside a dumpster no mob can find you. Crouched in cover in
-- the open, only a mob within Evade.OpenNotice studs with a clear line to you notices, or any
-- mob for Evade.ShotReveal seconds after you fire (character FiredAt, set by GunServer).
local EVADE = GameConfig.Evade
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
local sightRefreshAt = 0

local function noticed(from, character, root, d)
	if character:GetAttribute("Inside") then
		return false
	end
	if not character:GetAttribute("Hiding") then
		return true
	end
	if (character:GetAttribute("FiredAt") or 0) + EVADE.ShotReveal > workspace:GetServerTimeNow() then
		return true
	end
	if d > EVADE.OpenNotice then
		return false
	end
	if os.clock() > sightRefreshAt then
		sightRefreshAt = os.clock() + 3
		local ignore = { workspace:FindFirstChild("Zombies"), workspace:FindFirstChild("Fx") }
		for _, spot in CollectionService:GetTagged("HideSpot") do
			table.insert(ignore, spot)
		end
		sightParams.FilterDescendantsInstances = ignore
	end
	local eye = from + Vector3.new(0, 1.5, 0)
	local hit = workspace:Raycast(eye, root.Position - eye, sightParams)
	return hit == nil or hit.Instance:IsDescendantOf(character)
end

-- The nearest player standing or down that this mob can find. Someone already being eaten is
-- left to the mobs feeding on them; the rest go for their friends.
local function nearestPlayer(from, maxRange)
	local best, bestRoot, bestDist = nil, nil, maxRange
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 and not character:GetAttribute("Devoured") then
			local d = (root.Position - from).Magnitude
			if d < bestDist and noticed(from, character, root, d) then
				best, bestRoot, bestDist = p, root, d
			end
		end
	end
	-- WAR's NPC squad (tag Ally, ServerStorage.Modules.Soldier) is prey too, unless sat down hurt.
	for _, ally in CollectionService:GetTagged("Ally") do
		local hum = ally:FindFirstChildOfClass("Humanoid")
		local root = ally:FindFirstChild("HumanoidRootPart")
		if hum and root and hum.Health > 0 and not ally:GetAttribute("Downed") and ally:IsDescendantOf(workspace) then
			local d = (root.Position - from).Magnitude
			if d < bestDist then
				best, bestRoot, bestDist = nil, root, d
			end
		end
	end
	return best, bestRoot, bestDist
end

-- A mob that loses its target (it hid) searches where it last saw them for this long.
local SEARCH_TIME = 4

-- During a devour each mob takes its own spot around the body (DevourSlot).
local function devourSpot(model, root)
	local slot = model:GetAttribute("DevourSlot") or 1
	return root.Position + CFrame.Angles(0, slot * 2.4, 0).LookVector * 1.8
end

-- Obstacles ----------------------------------------------------------------------------

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.CollisionGroup = "Characters"

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.CollisionGroup = "Characters"

local function ignoreList(model)
	local list = { model.Parent }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function taggedAncestor(part)
	local node = part
	while node and node ~= workspace do
		if CollectionService:HasTag(node, "Vaultable") then
			return node, "Vault"
		elseif CollectionService:HasTag(node, "Breakable") then
			return node, "Break"
		elseif CollectionService:HasTag(node, "Door") then
			return node, "Door"
		end
		node = node.Parent
	end
	return nil
end

local function bounds(obstacle)
	if obstacle:IsA("BasePart") then
		return obstacle.CFrame, obstacle.Size
	end
	return obstacle:GetBoundingBox()
end

-- The obstacle's thin horizontal axis (the way across it), its thickness and its centre.
local function crossing(obstacle)
	local cf, size = bounds(obstacle)
	if size.X < size.Z then
		return flat(cf.RightVector).Unit, size.X, cf, size
	end
	return flat(cf.LookVector).Unit, size.Z, cf, size
end

-- A tagged obstacle right in front of the mob that stands between it and `goal`.
local function obstacleAhead(model, goal)
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local look = flat(root.CFrame.LookVector)
	if look.Magnitude < 0.1 then
		return nil
	end
	look = look.Unit
	overlap.FilterDescendantsInstances = ignoreList(model)
	local boxCf = CFrame.lookAt(root.Position, root.Position + look) * CFrame.new(0, -0.5, -1.8)
	for _, part in workspace:GetPartBoundsInBox(boxCf, Vector3.new(2.5, 4, 2.4), overlap) do
		local obstacle, kind = taggedAncestor(part)
		if obstacle and not (kind == "Break" and Barricades.IsBroken(obstacle))
			and not (kind == "Door" and Doors.IsOpen(obstacle)) then
			local axis, _, cf = crossing(obstacle)
			local mySide = (root.Position - cf.Position):Dot(axis)
			local goalSide = (goal - cf.Position):Dot(axis)
			if mySide * goalSide < 0 then
				return obstacle, kind
			end
		end
	end
	return nil
end

local function groundBelow(model, pos)
	groundParams.FilterDescendantsInstances = ignoreList(model)
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), groundParams)
	return hit and hit.Position.Y
end

-- Up and over in VaultTime: the root is anchored and carried along a curve above the top.
-- Returns false if the obstacle is too tall to vault.
local function vault(model, humanoid, obstacle, nav)
	local root = model.PrimaryPart
	local axis, thickness, cf, size = crossing(obstacle)
	local side = if (cf.Position - root.Position):Dot(axis) > 0 then 1 else -1
	local dir = axis * side
	local top = cf.Position.Y + size.Y / 2
	local ground = groundBelow(model, root.Position) or (root.Position.Y - 3)
	if top - ground > nav.MaxVault then
		return false
	end
	local rootHeight = root.Position.Y - ground

	local start = root.Position
	local past = (cf.Position - start):Dot(dir) + thickness / 2 + 2
	local landXZ = start + dir * past
	local landGround = groundBelow(model, landXZ) or ground
	local land = Vector3.new(landXZ.X, landGround + rootHeight, landXZ.Z)
	local overXZ = start + dir * ((cf.Position - start):Dot(dir))
	local over = Vector3.new(overXZ.X, math.max(top + rootHeight * 0.55, start.Y + 1), overXZ.Z)
	-- The bezier control point that puts the curve's peak at `over`.
	local control = over * 2 - (start + land) / 2

	humanoid:MoveTo(root.Position)
	Remotes.MobAttack:FireAllClients(model, "Windup", nav.VaultTime * 0.35, "Vault")
	root.Anchored = true
	local facing = CFrame.lookAt(Vector3.zero, dir)
	local t = 0
	local swung = false
	while t < 1 do
		t = math.min(t + RunService.Heartbeat:Wait() / nav.VaultTime, 1)
		if not alive(model, humanoid) then
			-- MobReactions anchors and then frees the corpse itself.
			return true
		end
		if not swung and t >= 0.5 then
			swung = true
			Remotes.MobAttack:FireAllClients(model, "Swing", nav.VaultTime * 0.4, "Vault")
		end
		local a = start:Lerp(control, t)
		local b = control:Lerp(land, t)
		root.CFrame = CFrame.new(a:Lerp(b, t)) * facing
	end
	root.Anchored = false
	pcall(root.SetNetworkOwner, root, nil)
	return true
end

-- Something is in the way: act dumb for a while (bump, shuffle, claw), then go over or
-- through it. Returns early when the target can be hit after all.
local function handleObstacle(model, humanoid, obstacle, kind, cfg, canHit)
	local nav = cfg.Navigation
	local root = model.PrimaryPart
	local axis, _, cf = crossing(obstacle)
	local side = if (cf.Position - root.Position):Dot(axis) > 0 then 1 else -1
	local into = axis * side
	local along = Vector3.new(-into.Z, 0, into.X)

	local dumbShare = if kind == "Break" then 0.5 elseif kind == "Door" then GameConfig.Doors.ShoveDumbShare else 1
	local dumbUntil = os.clock() + between(nav.DumbTime) * dumbShare
	while os.clock() < dumbUntil do
		if not alive(model, humanoid) or canHit() then
			return
		end
		local roll = math.random()
		if roll < 0.35 then
			walkTo(humanoid, root.Position + into * 4)
			if not hold(model, humanoid, 0.5 + math.random() * 0.4) then
				return
			end
		elseif roll < 0.7 then
			local step = (1.5 + math.random() * 1.5) * (if math.random() < 0.5 then -1 else 1)
			walkTo(humanoid, root.Position + along * step + into * 0.5)
			if not hold(model, humanoid, between(nav.MillTime)) then
				return
			end
		else
			MobAttack.Claw(model, humanoid, root.Position + into * 3, cfg)
			if not hold(model, humanoid, between(nav.ClawGap) * 0.5) then
				return
			end
		end
	end

	if kind == "Door" then
		-- Shoved open, away from the zombie, like a player would.
		Doors.Open(obstacle, root.Position)
		hold(model, humanoid, GameConfig.Doors.OpenTime)
		return
	end

	if kind == "Vault" then
		if not vault(model, humanoid, obstacle, nav) then
			-- Too tall after all: shuffle aside and let the path find another way.
			walkTo(humanoid, root.Position - into * 2 + along * 3)
			hold(model, humanoid, between(nav.MillTime))
		end
		return
	end

	while alive(model, humanoid) and not Barricades.IsBroken(obstacle) do
		if canHit() then
			return
		end
		MobAttack.Claw(model, humanoid, root.Position + into * 3, cfg)
		if not alive(model, humanoid) then
			return
		end
		Barricades.Rip(obstacle, root.Position)
		if not hold(model, humanoid, between(nav.BreakDelay)) then
			return
		end
	end
end

-- Hunting --------------------------------------------------------------------------------

-- Starts the hunt loop for a mob. options.AggroRange: how far it notices players.
function MobAI.Hunt(model, cfg, options)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local attack, nav = cfg.Attack, cfg.Navigation
	local aggroRange = options and options.AggroRange or 150
	model:SetAttribute("Hunts", true)

	local path = PathfindingService:CreatePath({
		AgentRadius = 1.6,
		AgentHeight = 5.5,
		AgentCanJump = false,
		WaypointSpacing = 3,
		Costs = nav.Costs,
	})
	local waypoints, nextIndex = nil, 0
	local pathGoal, pathAt = nil, 0
	path.Blocked:Connect(function(index)
		if index >= nextIndex then
			waypoints = nil
		end
	end)

	local function repath(from, goal)
		pathGoal, pathAt = goal, os.clock()
		local ok = pcall(path.ComputeAsync, path, from, goal)
		if ok and path.Status == Enum.PathStatus.Success then
			waypoints, nextIndex = path:GetWaypoints(), 2
		else
			waypoints = nil
		end
	end

	-- Stuck check: where the mob was when it last made headway, and when.
	local checkPos, checkAt = nil, os.clock()

	task.spawn(function()
		local alerted = false
		local lastSeen, lastSeenAt = nil, 0
		while alive(model, humanoid) do
			local root = model.PrimaryPart
			local feedOn = model:GetAttribute("DevourTarget")
			local prey = feedOn and Players:GetPlayerByUserId(feedOn)
			local preyRoot = prey and prey.Character and prey.Character:FindFirstChild("HumanoidRootPart")
			local moving = false
			if preyRoot then
				local spot = devourSpot(model, preyRoot)
				if (spot - root.Position).Magnitude > 1.5 then
					walkTo(humanoid, spot)
					moving = true
				else
					MobAttack.Maul(model, humanoid, preyRoot.Position, cfg)
				end
			else
				local player, target, dist = nearestPlayer(root.Position, aggroRange)
				if target then
					lastSeen, lastSeenAt = target.Position, os.clock()
				end
				if target then
					if not alerted then
						alerted = true
						SoundKit.Play(cfg.Sounds .. "/Aggro", { Position = root.Position })
					end
					local reach = if model:GetAttribute("Crawling") then attack.CrawlRange else attack.Range
					local function canHit()
						return target.Parent ~= nil
							and (target.Position - root.Position).Magnitude <= reach
							and MobAttack.Sees(model, target)
					end
					if canHit() then
						if MobAttack.Ready(model) then
							MobAttack.Swing(model, humanoid, player or target.Parent, cfg)
						else
							humanoid:MoveTo(root.Position)
						end
						checkPos = nil
					else
						-- Where to head this tick: straight at the target, or the next waypoint.
						local goal = target.Position
						if dist > nav.DirectRange or not MobAttack.Sees(model, target) then
							if not waypoints
								or os.clock() - pathAt > nav.RepathTime and (target.Position - pathGoal).Magnitude > nav.RepathMove
							then
								repath(root.Position, target.Position)
							end
							if waypoints then
								while waypoints[nextIndex + 1]
									and flat(waypoints[nextIndex].Position - root.Position).Magnitude < WAYPOINT_REACH
								do
									nextIndex += 1
								end
								local wp = waypoints[nextIndex]
								if wp then
									goal = wp.Position
								end
							end
						else
							waypoints = nil
						end

						local obstacle, kind = obstacleAhead(model, target.Position)
						if obstacle then
							handleObstacle(model, humanoid, obstacle, kind, cfg, canHit)
							waypoints = nil
							checkPos = nil
						else
							walkTo(humanoid, goal)
							moving = true
						end
					end
				elseif lastSeen and os.clock() - lastSeenAt < SEARCH_TIME and flat(lastSeen - root.Position).Magnitude > 3 then
					-- Lost them: go and look where they were.
					walkTo(humanoid, lastSeen)
					moving = true
				else
					lastSeen = nil
					humanoid:MoveTo(root.Position)
				end
			end

			-- No headway for StuckTime while trying to walk: shuffle aside, then repath.
			if moving and alive(model, humanoid) then
				local here = model.PrimaryPart.Position
				if not checkPos or flat(here - checkPos).Magnitude > nav.StuckDistance then
					checkPos, checkAt = here, os.clock()
				elseif os.clock() - checkAt > nav.StuckTime then
					local look = flat(model.PrimaryPart.CFrame.LookVector)
					local aside = Vector3.new(-look.Z, 0, look.X) * (if math.random() < 0.5 then -1 else 1)
					walkTo(humanoid, here + aside * 3 - look * 1)
					hold(model, humanoid, between(nav.MillTime))
					waypoints = nil
					checkPos = nil
				end
			else
				checkPos = nil
			end
			-- Always yield here, even after a swing or maul that returned at once.
			task.wait(TICK)
		end
	end)
end

return MobAI
