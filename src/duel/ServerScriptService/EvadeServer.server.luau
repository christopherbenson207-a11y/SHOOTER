-- Hiding and rolling, server side (numbers: GameConfig.Evade; client: StarterPlayerScripts.Evade).
-- Every hiding spot (parts tagged HideSpot: boxes round the wrecked cars, the dumpsters and
-- the police car) gets a Hide prompt while a match is running (from wave 1). Using it crouches you there:
-- the character carries Hiding = true, which the Beacon's lamps can't see through
-- (BeaconServer), and HideId, the spot's HideId attribute. You come out when you use the
-- prompt again or jump (Remotes.Evade "Leave"), go down, die, wander off the
-- spot, or the breakout ends.
-- A dumpster takes you inside: you're held anchored in it and carry Inside = true (every
-- client hides your body, and StarterPlayerScripts.HideWatch lifts your camera outside to
-- watch the street). Coming out puts you back where you climbed in.
-- A stance (Remotes.Evade "Stance", "Stand" / "Crouch" / "Prone"; the older "Crouch", on still works) sets
-- Crouching and Prone on the character (prone carries both) and a slide ("Slide") sets SlideUntil (server time);
-- teammates' screens and the Beacon read them, and the body is posed from them for everyone (Shared.CrouchPose).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.Evade

local spots = {} -- HideId -> part
local prompts = {}
local lastSlide = {}
local exits = {} -- [player] = CFrame they climbed in from
local insideSince = {} -- [player] = os.clock() they climbed into a dumpster
local insideBlocked = {} -- [player] = os.clock() they may climb into one again

-- Hiding works whenever a match is running (from wave 1; the Beacon is out from the start).
local function hidingOpen()
	local state = workspace:GetAttribute("WaveState")
	return state == "Wave" or state == "Intermission" or state == "Breakout" or state == "Outbreak"
end

local function label(part)
	local name = part.Name:gsub("^HideSpot_", "")
	if name:find("Police") then
		return "Police car"
	elseif name:find("Dumpster") then
		return "Dumpster"
	end
	return "Car"
end

-- How far a point is outside a spot's box, flat (0 inside).
local function outside(part, point)
	local rel = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local dx = math.max(0, math.abs(rel.X) - half.X)
	local dz = math.max(0, math.abs(rel.Z) - half.Z)
	return math.sqrt(dx * dx + dz * dz)
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root then
		return character, root
	end
	return nil, nil
end

local function leave(player)
	local character = player.Character
	if character and character:GetAttribute("Hiding") then
		character:SetAttribute("Hiding", nil)
		character:SetAttribute("HideId", nil)
	end
	local exit = exits[player]
	exits[player] = nil
	if insideSince[player] then
		insideSince[player] = nil
		insideBlocked[player] = os.clock() + CFG.InsideCooldown
	end
	if character and character:GetAttribute("Inside") then
		character:SetAttribute("Inside", nil)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			if exit then
				root.CFrame = exit
			end
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = false
		end
	end
end

-- Inside a dumpster: low in the middle of its box, facing the way the box faces.
local function climbIn(player, character, root, part)
	exits[player] = root.CFrame
	local bottom = part.Position.Y - part.Size.Y / 2
	root.Anchored = true
	root.CFrame = CFrame.new(part.Position.X, bottom + 1.6, part.Position.Z) * part.CFrame.Rotation
	character:SetAttribute("Inside", true)
	insideSince[player] = os.clock()
end

local function hide(player, part)
	local character, root = rootOf(player)
	if not character or not hidingOpen() or not player:GetAttribute("InMatch") then
		return
	end
	if character:GetAttribute("Hiding") then
		leave(player)
		return
	end
	if PlayerHealth.IsDowned(player) or outside(part, root.Position) > CFG.HideRange + 1 then
		return
	end
	-- Out of a dumpster only a little while ago: not back in yet (stalling a wave).
	if part.Name:find("Dumpster") and os.clock() < (insideBlocked[player] or 0) then
		return
	end
	character:SetAttribute("Hiding", true)
	character:SetAttribute("Crouching", nil)
	character:SetAttribute("Prone", nil)
	character:SetAttribute("HideId", part:GetAttribute("HideId"))
	if part.Name:find("Dumpster") then
		climbIn(player, character, root, part)
	end
end

local nextId = 0
local function addSpot(part)
	if not part:IsA("BasePart") or part:GetAttribute("HidePrompted") then
		return
	end
	part:SetAttribute("HidePrompted", true)
	nextId += 1
	part:SetAttribute("HideId", nextId)
	spots[nextId] = part
	local at = Instance.new("Attachment")
	at.Name = "HidePoint"
	at.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HidePrompt"
	prompt.ActionText = "Hide"
	prompt.ObjectText = label(part)
	prompt.HoldDuration = 0
	-- Generous reach, so on a phone a tap near the spot is enough.
	prompt.MaxActivationDistance = math.max(part.Size.X, part.Size.Z) / 2 + CFG.HideRange + 2
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = hidingOpen()
	prompt.Parent = at
	prompt.Triggered:Connect(function(player)
		hide(player, part)
	end)
	table.insert(prompts, prompt)
end

CollectionService:GetInstanceAddedSignal("HideSpot"):Connect(addSpot)
for _, part in CollectionService:GetTagged("HideSpot") do
	addSpot(part)
end

workspace:GetAttributeChangedSignal("WaveState"):Connect(function()
	local on = hidingOpen()
	for _, prompt in prompts do
		prompt.Enabled = on
	end
	if not on then
		for _, p in Players:GetPlayers() do
			leave(p)
		end
	end
end)

-- fwjelaa-ignore: remote-unvalidated-args (extra is only ever compared to true or to the three stance names)
Remotes.Evade.OnServerEvent:Connect(function(player, action, extra)
	if typeof(action) ~= "string" then
		return
	end
	if action == "Leave" then
		leave(player)
	elseif action == "Crouch" then
		local character = rootOf(player)
		if character and not character:GetAttribute("Hiding") then
			character:SetAttribute("Crouching", if extra == true and not PlayerHealth.IsDowned(player) then true else nil)
			character:SetAttribute("Prone", nil)
		end
	elseif action == "Stance" then
		local character = rootOf(player)
		if not character or character:GetAttribute("Hiding") then
			return
		end
		local low = (extra == "Crouch" or extra == "Prone") and not PlayerHealth.IsDowned(player)
		character:SetAttribute("Crouching", if low then true else nil)
		character:SetAttribute("Prone", if low and extra == "Prone" then true else nil)
	elseif action == "Slide" then
		local character = rootOf(player)
		local now = os.clock()
		if not character or PlayerHealth.IsDowned(player) or character:GetAttribute("Hiding")
			or now - (lastSlide[player] or 0) < CFG.SlideCooldown * 0.8
		then
			return
		end
		lastSlide[player] = now
		character:SetAttribute("Crouching", true)
		character:SetAttribute("Prone", nil)
		character:SetAttribute("SlideUntil", workspace:GetServerTimeNow() + CFG.SlideTime)
	end
end)

-- The stance everyone sees (Shared.CrouchPose, 5 Nov 2026 duel pass; prone 7 Nov): the body follows the server's
-- Crouching and Prone attributes (a slide sets Crouching too), so the head other players aim at sinks as far as the
-- player's camera. Re-posing waits at least POSE_GAP after the last one, so stance spam costs the server a few tweens
-- a second at most; the body always ends in the state the attributes say. Going down stands the body up but leaves
-- the root joint to PlayerHealth's downed pose.
local CrouchPose = require(ReplicatedStorage.Shared.CrouchPose)
local POSE_GAP = 0.1
if CrouchPose.Enabled() then
	local function watch(character)
		local posed = "Stand"
		local lastPose = -math.huge
		local queued = false
		local function update()
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 or not character.Parent then
				return
			end
			local downed = character:GetAttribute("Downed") == true
			local want = if downed then "Stand"
				elseif character:GetAttribute("Prone") == true then "Prone"
				elseif character:GetAttribute("Crouching") == true then "Crouch"
				else "Stand"
			if want == posed then
				return
			end
			local wait = POSE_GAP - (os.clock() - lastPose)
			if wait > 0 then
				if not queued then
					queued = true
					task.delay(wait, function()
						queued = false
						update()
					end)
				end
				return
			end
			local time = if want == "Prone" or posed == "Prone" then CFG.ProneTime or CFG.CrouchTime else CFG.CrouchTime
			posed = want
			lastPose = os.clock()
			CrouchPose.Apply(character, want, time, downed)
		end
		character:GetAttributeChangedSignal("Crouching"):Connect(update)
		character:GetAttributeChangedSignal("Prone"):Connect(update)
		-- Going down: off the floor and out of a crouch on the server too (the client also stands itself up).
		character:GetAttributeChangedSignal("Downed"):Connect(function()
			if character:GetAttribute("Downed") == true then
				character:SetAttribute("Prone", nil)
				character:SetAttribute("Crouching", nil)
			end
			update()
		end)
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(watch)
		if player.Character then
			watch(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

Players.PlayerRemoving:Connect(function(player)
	lastSlide[player] = nil
	insideSince[player] = nil
	insideBlocked[player] = nil
	exits[player] = nil
end)

-- Studio testing: setting the player attribute DebugHide uses the nearest spot's prompt.
if game:GetService("RunService"):IsStudio() then
	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal("DebugHide"):Connect(function()
			if not player:GetAttribute("DebugHide") then
				return
			end
			player:SetAttribute("DebugHide", nil)
			local _, root = rootOf(player)
			local best, bestDist = nil, math.huge
			for _, part in spots do
				local d = if root then outside(part, root.Position) else math.huge
				if d < bestDist then
					best, bestDist = part, d
				end
			end
			if best then
				hide(player, best)
			end
		end)
	end)
end

-- Hiding ends on its own when you can't stay there.
task.spawn(function()
	while true do
		task.wait(0.2)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character and character:GetAttribute("Hiding") then
				local _, root = rootOf(player)
				local part = spots[character:GetAttribute("HideId") or 0]
				local tooLong = insideSince[player] and os.clock() - insideSince[player] > CFG.InsideMax
				if not root or not part or PlayerHealth.IsDowned(player) or tooLong
					or (not character:GetAttribute("Inside") and outside(part, root.Position) > CFG.HideRange + 1.5)
				then
					leave(player)
				end
			end
		end
	end
end)
