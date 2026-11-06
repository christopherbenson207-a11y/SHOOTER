-- Getting into the house, Call of Duty Zombies' Nacht der Untoten style: a zombie walks to
-- its boarded window, tears the boards off (Barricades.Rip, a pull every BreakDelay), swipes
-- at anyone standing at the window, then climbs over the sill into the room and starts
-- hunting (MobAI). One zombie climbs a window at a time. On the way, a player in plain sight
-- within Match.DistractRange pulls it off its window to hunt them instead.
-- A window is { Boards, Outside, Inside, SillTop, Center } (built by MatchServer).

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MobAttack = require(ServerStorage.Modules.MobAttack)
local Barricades = require(ServerStorage.Modules.Barricades)
local Remotes = ReplicatedStorage.Remotes

local MATCH = GameConfig.Match
local TICK = 0.15
local REACH = 2.5

local WindowEntry = {}

-- The house's box (MatchServer sets it): players inside it don't pull zombies off their
-- window on the way, since the only way in is through one.
local houseCf, houseSize

function WindowEntry.SetHouse(cf, size)
	houseCf, houseSize = cf, size
end

local function inHouse(pos)
	if not houseCf then
		return false
	end
	local p = houseCf:PointToObjectSpace(pos)
	return math.abs(p.X) <= houseSize.X / 2 and math.abs(p.Y) <= houseSize.Y / 2 and math.abs(p.Z) <= houseSize.Z / 2
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function between(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

local function alive(model, humanoid)
	return model.Parent ~= nil and humanoid.Health > 0 and not model:GetAttribute("Dead")
end

local function walkTo(humanoid, pos)
	if (humanoid.WalkToPoint - pos).Magnitude < 0.05 then
		pos += Vector3.new(0.1, 0, 0)
	end
	humanoid:MoveTo(pos)
end

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

-- A standing player close by and in plain sight (outside the house, unless indoors is allowed).
local function distraction(model, range, indoors)
	local root = model.PrimaryPart
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		local target = character and character:FindFirstChild("HumanoidRootPart")
		if hum and target and hum.Health > 0 and not character:GetAttribute("Devoured")
			and (indoors or not inHouse(target.Position))
			and (target.Position - root.Position).Magnitude <= range and MobAttack.Sees(model, target)
		then
			return p, target
		end
	end
	return nil
end

-- Walks to pos along a path. Returns "arrived", "dead" or "distracted".
local function travel(model, humanoid, pos)
	local path = PathfindingService:CreatePath({
		AgentRadius = 1.6,
		AgentHeight = 5.5,
		AgentCanJump = false,
		WaypointSpacing = 3,
	})
	local waypoints, nextIndex, pathAt = nil, 0, 0
	local checkPos, checkAt = nil, os.clock()
	while alive(model, humanoid) do
		local root = model.PrimaryPart
		if flat(pos - root.Position).Magnitude < REACH then
			return "arrived"
		end
		if distraction(model, MATCH.DistractRange) then
			return "distracted"
		end
		if not waypoints or os.clock() - pathAt > 3 then
			pathAt = os.clock()
			local ok = pcall(path.ComputeAsync, path, root.Position, pos)
			if ok and path.Status == Enum.PathStatus.Success then
				waypoints, nextIndex = path:GetWaypoints(), 2
			else
				waypoints = nil
			end
		end
		local goal = pos
		if waypoints then
			while waypoints[nextIndex + 1] and flat(waypoints[nextIndex].Position - root.Position).Magnitude < REACH do
				nextIndex += 1
			end
			if waypoints[nextIndex] then
				goal = waypoints[nextIndex].Position
			end
		end
		walkTo(humanoid, goal)
		-- No headway for a second: shuffle aside and repath.
		local here = root.Position
		if not checkPos or flat(here - checkPos).Magnitude > 0.8 then
			checkPos, checkAt = here, os.clock()
		elseif os.clock() - checkAt > 1.2 then
			local look = flat(root.CFrame.LookVector)
			local aside = Vector3.new(-look.Z, 0, look.X) * (if math.random() < 0.5 then -1 else 1)
			walkTo(humanoid, here + aside * 3 - look)
			if not hold(model, humanoid, 0.6) then
				return "dead"
			end
			waypoints, checkPos = nil, nil
		end
		task.wait(TICK)
	end
	return "dead"
end

-- Over the sill into the room, like MobAI's vault: the root is carried along a curve.
local function climb(model, humanoid, window)
	local root = model.PrimaryPart
	local start = root.Position
	local rootHeight = math.max(2.5, start.Y - window.Outside.Y)
	local land = window.Inside + Vector3.new(0, rootHeight, 0)
	local over = Vector3.new(window.Center.X, window.SillTop + rootHeight * 0.6, window.Center.Z)
	local control = over * 2 - (start + land) / 2
	local facing = CFrame.lookAt(Vector3.zero, flat(land - start).Unit)
	humanoid:MoveTo(root.Position)
	Remotes.MobAttack:FireAllClients(model, "Windup", MATCH.ClimbTime * 0.35, "Vault")
	root.Anchored = true
	local t, swung = 0, false
	while t < 1 do
		t = math.min(t + RunService.Heartbeat:Wait() / MATCH.ClimbTime, 1)
		if not alive(model, humanoid) then
			return false
		end
		if not swung and t >= 0.5 then
			swung = true
			Remotes.MobAttack:FireAllClients(model, "Swing", MATCH.ClimbTime * 0.4, "Vault")
		end
		local a = start:Lerp(control, t)
		local b = control:Lerp(land, t)
		root.CFrame = CFrame.new(a:Lerp(b, t)) * facing
	end
	root.Anchored = false
	pcall(root.SetNetworkOwner, root, nil)
	return true
end

-- Runs the whole entry, then calls onInside(model) (also when it was distracted on the way).
function WindowEntry.Enter(model, cfg, window, onInside)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local attack, nav = cfg.Attack, cfg.Navigation
	task.spawn(function()
		local result = travel(model, humanoid, window.Outside)
		if result == "dead" then
			return
		elseif result == "distracted" then
			onInside(model)
			return
		end
		-- At the window: tear in, swiping at anyone holding it.
		local root = model.PrimaryPart
		local into = flat(window.Inside - window.Outside).Unit
		while alive(model, humanoid) do
			local broken = Barricades.IsBroken(window.Boards)
			if broken and os.clock() >= (window.ClimbFreeAt or 0) then
				break
			end
			-- Stay squared up on the window.
			if flat(window.Outside - root.Position).Magnitude > 1.6 then
				walkTo(humanoid, window.Outside)
			else
				humanoid:MoveTo(root.Position)
				root.CFrame = CFrame.lookAt(root.Position, root.Position + into)
			end
			local player = distraction(model, attack.Range + 1, true)
			if player and MobAttack.Ready(model) then
				MobAttack.Swing(model, humanoid, player, cfg)
			elseif not broken then
				MobAttack.Claw(model, humanoid, window.Center, cfg)
				if not alive(model, humanoid) then
					return
				end
				Barricades.Rip(window.Boards, root.Position)
				if not hold(model, humanoid, between(nav.BreakDelay)) then
					return
				end
			else
				-- Someone else is climbing through (or a swing is cooling down); wait a moment.
				if not hold(model, humanoid, 0.3) then
					return
				end
			end
		end
		if not alive(model, humanoid) then
			return
		end
		window.ClimbFreeAt = os.clock() + MATCH.ClimbTime + 0.2
		if climb(model, humanoid, window) then
			onInside(model)
		end
	end)
end

return WindowEntry
