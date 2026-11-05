-- The breakout and the pickup on this screen (HORROR-SHOOTER-ESCAPE.md):
--   The reveal: when the doors blow (Remotes.Match "Breakout") the camera leaves your eyes,
--   rises over your shoulder and finds the Beacon down the street, then comes back
--   (Breakout.RevealTime; the server holds you still and safe meanwhile).
--   The helicopter: a local copy of ReplicatedStorage.Assets.EvacHeli flown along
--   Shared.EvacPath from the workspace attributes EvacAt / EvacLeaveAt, rotors turning, the
--   searchlight on the landing zone, a rope ladder unrolling from the door once it's over the
--   zone. RescueClient films the escape with the same copy (workspace.EvacHeliLive).
--   GRAB: a "GRAB LADDER" ProximityPrompt rides the ladder's foot (hold E, gamepad X, tap the
--   hand on touch; drawn like every other prompt by PromptLook). Testers, 5 Nov: the old amber
--   GRAB button didn't read as "grab the ladder". Triggering it asks the server (Remotes.Evac "Grab"); once it says you're aboard
--   (Remotes.Match "Aboard") the camera pulls out behind you as you climb, then rides in the
--   door looking back down at the street.
-- While the reveal or the ride runs, the player attribute Cutscene is set (GunClient hides
-- the gun, TouchControls hide).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Controls = require(Shared:WaitForChild("Controls"))
local EvacPath = require(Shared:WaitForChild("EvacPath"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local BREAK = GameConfig.Breakout
local EVAC = BREAK.Evac
local AMBER = Color3.fromRGB(255, 176, 60)
local ROPE = Color3.fromRGB(92, 78, 56)
local RUNGS = 26

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function zonePos()
	-- Outbreak sends it to any landing pad (MatchServer's EvacZone); otherwise the hilltop zone.
	local at = workspace:GetAttribute("EvacZone")
	if typeof(at) == "Vector3" then
		return at
	end
	local map = workspace:FindFirstChild("Map")
	local extraction = map and map:FindFirstChild("Extraction")
	local zone = extraction and extraction:FindFirstChild("Zone")
	return zone and zone.Position
end

local function evacTimes()
	local at = workspace:GetAttribute("EvacAt")
	if not at then
		return nil
	end
	local leave = workspace:GetAttribute("EvacLeaveAt")
	return workspace:GetServerTimeNow() - at, if leave then leave - at else EvacPath.DefaultLeave
end

local function myRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character
end

local function setHud(on)
	local hud = playerGui:FindFirstChild("HUD")
	if hud then
		hud.Enabled = on
	end
end

local function showOwnBody()
	local character = player.Character
	if character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = 0
			end
		end
	end
end

local function restoreCamera()
	local camera = workspace.CurrentCamera
	local _, character = myRoot()
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	if character then
		camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
	end
end

-- The helicopter --------------------------------------------------------------------------

local heli, parts, offsets, rotors, ladder, ropes, rungs
local grip: BasePart?, gripPrompt: ProximityPrompt? -- the GRAB LADDER prompt at the ladder's foot
local grab: () -> () -- defined with the GRAB section below

local function buildHeli()
	local source = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("EvacHeli")
	heli = source:Clone()
	heli.Name = "EvacHeliLive"
	local base = heli.PrimaryPart.CFrame
	parts, offsets, rotors = {}, {}, {}
	for _, d in heli:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			table.insert(parts, d)
			offsets[d] = base:ToObjectSpace(d.CFrame)
			local spin = d:GetAttribute("Spin")
			if spin then
				rotors[d] = if spin == "Main" then { Axis = Vector3.yAxis, Rate = -15 } else { Axis = Vector3.xAxis, Rate = 34 }
			end
		end
	end
	heli.Parent = workspace
	local rotor = heli.PrimaryPart:FindFirstChild("Rotor")
	if rotor then
		rotor.Volume = 0
		rotor:Play()
		TweenService:Create(rotor, TweenInfo.new(3), { Volume = 1 }):Play()
	end

	-- The rope ladder: two ropes and rungs, laid out every frame.
	ladder = Instance.new("Model")
	ladder.Name = "Ladder"
	local function piece(size)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Fabric
		p.Color = ROPE
		p.Size = size
		p.Parent = ladder
		return p
	end
	ropes = { piece(Vector3.new(0.14, 0.14, 1)), piece(Vector3.new(0.14, 0.14, 1)) }
	rungs = {}
	for i = 1, RUNGS do
		rungs[i] = piece(Vector3.new(1.3, 0.16, 0.16))
		rungs[i].Material = Enum.Material.Wood
		rungs[i].Color = Color3.fromRGB(120, 96, 64)
	end
	-- The grab point: an invisible part kept at the ladder's foot, carrying the prompt. The prompt only
	-- turns on when the server would take the grab (see the loop); its range sits inside the server's
	-- slack (Evac.Grab + 3 flat), so a press it shows is a press the server accepts.
	local point = Instance.new("Part")
	point.Name = "Grip"
	point.Anchored = true
	point.CanCollide = false
	point.CanQuery = false
	point.CanTouch = false
	point.Transparency = 1
	point.Size = Vector3.new(1, 1, 1)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GrabLadder"
	prompt.ActionText = "Grab ladder"
	prompt.ObjectText = "Rescue helicopter"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = EVAC.Grab + 2
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.ClickablePrompt = true
	prompt.Enabled = false
	prompt:SetAttribute("KeepReach", true) -- sized to the ladder, not PromptReach's default
	prompt.Triggered:Connect(function()
		grab()
	end)
	prompt.Parent = point
	point.Parent = ladder
	grip, gripPrompt = point, prompt
	ladder.Parent = heli
end

local function clearHeli()
	if heli then
		heli:Destroy()
	end
	heli, ladder = nil, nil
	grip, gripPrompt = nil, nil
end

local function placeHeli(pose, t, leaveRel, zone)
	local spin = os.clock()
	local cframes = table.create(#parts)
	for i, part in parts do
		local off = offsets[part]
		local rotor = rotors[part]
		if rotor then
			cframes[i] = pose * CFrame.new(off.Position) * CFrame.fromAxisAngle(rotor.Axis, spin * rotor.Rate) * off.Rotation
		else
			cframes[i] = pose * off
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	-- Searchlight on the zone until it leaves.
	local root = heli.PrimaryPart
	local search, tip = root:FindFirstChild("Search"), root:FindFirstChild("SearchEnd")
	if search and tip then
		local from = search.WorldPosition
		local phase = EvacPath.Phase(t, leaveRel)
		local dir = if phase == "Leave" or phase == "Gone" then pose:VectorToWorldSpace(Vector3.new(0, -0.62, -0.78).Unit) else (zone - from).Unit
		search.WorldCFrame = CFrame.lookAt(from, from + dir)
		tip.WorldPosition = from + dir * 55
	end
	local strobe = heli:FindFirstChild("TailStrobe")
	if strobe then
		local on = (os.clock() % 1.1) < 0.08
		strobe.Transparency = if on then 0 else 1
		local light = strobe:FindFirstChildOfClass("PointLight")
		if light then
			light.Enabled = on
		end
	end

	-- The ladder unrolls over its first second over the zone.
	local door, foot = EvacPath.Ladder(pose, t, leaveRel)
	local unroll = math.clamp(t / 1.2, 0, 1)
	local shown = t >= 0
	foot = door:Lerp(foot, unroll)
	local side = pose.LookVector * 0.6
	for i, rope in ropes do
		local s = if i == 1 then side else -side
		local a, b = door + s, foot + s
		local len = math.max((b - a).Magnitude, 0.05)
		rope.Size = Vector3.new(0.14, 0.14, len)
		rope.CFrame = CFrame.lookAt((a + b) / 2, b)
		rope.Transparency = if shown then 0 else 1
	end
	for i, rung in rungs do
		local k = i / RUNGS
		local at = door:Lerp(foot, k)
		rung.CFrame = CFrame.lookAt(at, at + pose.RightVector) * CFrame.Angles(0, math.rad(90), 0)
		rung.Transparency = if shown and k * EVAC.Ladder <= (foot - door).Magnitude + 0.1 then 0 else 1
	end
	-- Prompt at about chest height on the bottom rungs, so its bubble sits on the ladder you grab.
	if grip then
		grip.CFrame = CFrame.new(foot + Vector3.new(0, 3, 0))
	end
	return door, foot
end

-- GRAB ----------------------------------------------------------------------------------
-- The GRAB LADDER prompt (built with the ladder) is the only grab input; the old amber button and
-- its Use/Shoot/Jump binding are gone (testers didn't read it as the ladder).

local grabbing = false
local canGrab = false -- everything but distance (the prompt's own range covers that)

-- Fired by the GRAB LADDER prompt; the server re-checks reach against the same path.
grab = function()
	if canGrab and not grabbing then
		grabbing = true
		Remotes:WaitForChild("Evac"):FireServer("Grab")
		task.delay(0.8, function()
			grabbing = false
		end)
	end
end

-- Cameras -------------------------------------------------------------------------------

local ride = nil -- { Start } once you're aboard
local reveal = nil -- { Start, From }

local function housePos()
	local map = workspace:FindFirstChild("Map")
	for _, child in map and map:GetChildren() or {} do
		if child:GetAttribute("DefendHouse") then
			return child:GetPivot().Position
		end
	end
	return nil
end

local function beaconGround()
	local beacon = workspace:FindFirstChild("Beacon")
	return if beacon and beacon.PrimaryPart then beacon.PrimaryPart.Position.Y else 1
end

-- Which way from the Beacon to put the reveal camera: the first of a fan of angles (from the
-- house's side, swinging round) with nothing between the lens and its head.
local function revealAngle(head, root)
	local from = housePos() or root.Position
	local toHouse = (from - head) * Vector3.new(1, 0, 1)
	local base = if toHouse.Magnitude > 1 then toHouse.Unit else Vector3.new(0, 0, -1)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Beacon"), player.Character }
	for _, dist in { 46, 32 } do
		for _, deg in { 0, 55, -55, 80, -80, 30, -30, 110, -110, 150, -150, 180 } do
			local out = CFrame.Angles(0, math.rad(deg), 0):VectorToWorldSpace(base)
			local eye = Vector3.new(head.X, beaconGround() + 6, head.Z) + out * dist
			local aim = head - Vector3.new(0, 4, 0)
			if not workspace:Raycast(eye, aim - eye, params) and not workspace:Raycast(aim, eye - aim, params) then
				return out, dist
			end
		end
	end
	return base, 30
end

local function beaconHead()
	local beacon = workspace:FindFirstChild("Beacon")
	local head = beacon and beacon:FindFirstChild("Head")
	return head and head.Position
end

local function startReveal()
	local camera = workspace.CurrentCamera
	reveal = { Start = os.clock(), From = camera.CFrame }
	player:SetAttribute("Cutscene", true)
	setHud(false)
end

local function endReveal()
	reveal = nil
	player:SetAttribute("Cutscene", nil)
	setHud(true)
	restoreCamera()
end

local function ease(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

Remotes:WaitForChild("Match").OnClientEvent:Connect(function(cue, value)
	if cue == "Breakout" then
		local root = myRoot()
		if root and player:GetAttribute("InMatch") then
			startReveal()
		end
	elseif cue == "Aboard" and value == player.UserId then
		ride = { Start = os.clock() }
		player:SetAttribute("Cutscene", true)
		setHud(false)
	elseif cue == "Rescue" then
		-- RescueClient takes the camera from here.
		ride = nil
	end
end)

RunService:BindToRenderStep("EvacCamera", Enum.RenderPriority.Camera.Value + 8, function()
	local camera = workspace.CurrentCamera
	local root = myRoot()
	if reveal then
		local t = os.clock() - reveal.Start
		local target = beaconHead()
		if t >= BREAK.RevealTime or not root or not target then
			endReveal()
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		-- A cut to the street: low, a clear angle on it (picked when the reveal starts), looking up
		-- at it as it tears into a building, pushing slowly in, with a little shake on the hit. Then
		-- a cut back to your eyes.
		if not reveal.Out then
			reveal.Out, reveal.Dist = revealAngle(target, root)
		end
		local push = ease(t / BREAK.RevealTime) * reveal.Dist * 0.25
		local eye = Vector3.new(target.X, beaconGround() + 6, target.Z) + reveal.Out * (reveal.Dist - push)
		local shake = math.max(0, 1 - math.abs(t - 1.75) * 2.5)
		eye += Vector3.new(math.noise(t * 20, 1), math.noise(t * 20, 2), 0) * shake * 0.8
		camera.CFrame = CFrame.lookAt(eye, target - Vector3.new(0, 4, 0))
		camera.FieldOfView = 58
		if t >= BREAK.RevealTime - 0.05 then
			camera.FieldOfView = 70
		end
		return
	end
	if ride and heli and root then
		camera.CameraType = Enum.CameraType.Scriptable
		showOwnBody()
		local t = os.clock() - ride.Start
		local heliPos = heli.PrimaryPart.Position
		local outward = -heli.PrimaryPart.CFrame.RightVector
		if t < EVAC.Climb + 0.4 then
			-- Out behind and below you as you climb, the helicopter overhead.
			local eye = root.Position + outward * 11 - Vector3.new(0, 4, 0) + heli.PrimaryPart.CFrame.LookVector * 4
			camera.CFrame = CFrame.lookAt(eye, root.Position:Lerp(heliPos, 0.35))
			camera.FieldOfView = 62
		else
			-- In the door, looking back down at the street (and whatever is coming).
			local target = beaconHead() or (heliPos - Vector3.new(0, 30, 0))
			local eye = root.Position + Vector3.new(0, 1.8, 0) + outward * 1.2
			local look = (eye + outward * 20 - Vector3.new(0, 14, 0)):Lerp(target, 0.5)
			camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, look), 0.12)
			camera.FieldOfView = 66
		end
	end
end)

-- The loop ------------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	local state = workspace:GetAttribute("WaveState")
	local t, leaveRel = evacTimes()
	local zone = zonePos()
	-- "War": the campaign's pickup (WarServer) flies the same helicopter; without it the bird never showed.
	local live = t ~= nil and zone ~= nil and (state == "Breakout" or state == "Rescue" or state == "Outbreak" or state == "War")
		and t >= -EVAC.Inbound - 1
	if live and not heli then
		buildHeli()
	elseif not live and heli then
		clearHeli()
	end
	if not live and ride then
		ride = nil
		player:SetAttribute("Cutscene", nil)
		setHud(true)
		restoreCamera()
	end

	local eligible = false
	if heli then
		local pose = EvacPath.Pose(zone, t, leaveRel)
		placeHeli(pose, t, leaveRel, zone)
		local phase = EvacPath.Phase(t, leaveRel)
		local root, character = myRoot()
		eligible = root ~= nil and not ride and (state == "Breakout" or state == "Outbreak" or state == "War") and (phase == "Hover" or phase == "Crawl")
			and t > 1 and not character:GetAttribute("Downed") and not character:GetAttribute("Aboard")
	end
	canGrab = eligible
	if gripPrompt and gripPrompt.Enabled ~= eligible then
		gripPrompt.Enabled = eligible
	end
end)
