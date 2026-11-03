-- The breakout and the pickup on this screen (HORROR-SHOOTER-ESCAPE.md):
--   The reveal: when the doors blow (Remotes.Match "Breakout") the camera leaves your eyes,
--   rises over your shoulder and finds the Beacon down the street, then comes back
--   (Breakout.RevealTime; the server holds you still and safe meanwhile).
--   The helicopter: a local copy of ReplicatedStorage.Assets.EvacHeli flown along
--   Shared.EvacPath from the workspace attributes EvacAt / EvacLeaveAt, rotors turning, the
--   searchlight on the landing zone, a rope ladder unrolling from the door once it's over the
--   zone. RescueClient films the escape with the same copy (workspace.EvacHeliLive).
--   GRAB: while the ladder's foot is within Evac.Grab studs of you, a big amber GRAB button
--   shows at the bottom centre (tap; E, Space or a click; gamepad X or A).
--   Pressing it asks the server (Remotes.Evac "Grab"); you hang on the bottom rung (Remotes.Evac
--   "OnLadder") and the helicopter starts climbing away. You climb it yourself: hold forward
--   (W, the stick, or hold the CLIMB button on touch) and Remotes.Evac "Climb" tells the server.
--   At the top (Remotes.Match "Aboard") the camera rides in the door looking back down at the
--   street.
-- While the reveal or the ride runs, the player attribute Cutscene is set (GunClient hides
-- the gun, TouchControls hide).

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
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
	ladder.Parent = heli
end

local function clearHeli()
	if heli then
		heli:Destroy()
	end
	heli, ladder = nil, nil
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
	return door, foot
end

-- GRAB ----------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "Evac"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 8
gui.Enabled = false
gui.Parent = playerGui

local grabButton = Instance.new("TextButton")
grabButton.Name = "Grab"
grabButton.AnchorPoint = Vector2.new(0.5, 1)
grabButton.Position = UDim2.new(0.5, 0, 1, -110)
grabButton.Size = UDim2.fromOffset(132, 132)
grabButton.BackgroundColor3 = AMBER
grabButton.BackgroundTransparency = 0.1
grabButton.Text = "GRAB"
grabButton.TextColor3 = Color3.fromRGB(28, 22, 14)
grabButton.TextScaled = true
grabButton.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
grabButton.AutoButtonColor = false
grabButton.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = grabButton
local pad = Instance.new("UIPadding")
for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
	pad[side] = UDim.new(0.22, 0)
end
pad.Parent = grabButton
local ring = Instance.new("UIStroke")
ring.Color = AMBER
ring.Thickness = 4
ring.Parent = grabButton
local grabScale = Instance.new("UIScale")
grabScale.Parent = grabButton

local grabbing = false
local inReach = false
local onLadder = false
local holdClimb = false -- the CLIMB button held (touch)
local sentClimb = false
local controls = nil
-- Not every setup has a PlayerModule (this game ships its own); without it the climb reads Humanoid.MoveDirection.
task.spawn(function()
	local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
	if module then
		pcall(function()
			controls = require(module):GetControls()
		end)
	end
end)
grabButton.InputBegan:Connect(function(input)
	if onLadder and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
		holdClimb = true
	end
end)
grabButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		holdClimb = false
	end
end)

local function notice(text)
	local hud = playerGui:FindFirstChild("HUD")
	local label = hud and hud:FindFirstChild("Notice")
	if label then
		label.Text = text
		label.TextTransparency = 0
		task.delay(3, function()
			if label.Text == text then
				TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
			end
		end)
	end
end

Remotes:WaitForChild("Evac").OnClientEvent:Connect(function(cue)
	if cue == "OnLadder" then
		onLadder = true
		sentClimb = false
		notice(if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "HOLD CLIMB" else "HOLD W TO CLIMB")
	end
end)

local function grab()
	if inReach and not grabbing then
		grabbing = true
		Remotes:WaitForChild("Evac"):FireServer("Grab")
		task.delay(0.8, function()
			grabbing = false
		end)
	end
end
grabButton.Activated:Connect(grab)

local bound = false
local function bindKeys(on)
	if on == bound then
		return
	end
	bound = on
	if on then
		ContextActionService:BindActionAtPriority("EvacGrab", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				grab()
			end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.KeyCode.E, Enum.KeyCode.Space, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonA, Enum.UserInputType.MouseButton1)
	else
		ContextActionService:UnbindAction("EvacGrab")
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
		-- You climbed it yourself: straight to the seat in the door.
		onLadder = false
		ride = { Start = os.clock() - EVAC.Climb - 0.4 }
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
	local live = t ~= nil and zone ~= nil and (state == "Breakout" or state == "Rescue" or state == "Outbreak")
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

	local reach = false
	if heli then
		local pose = EvacPath.Pose(zone, t, leaveRel)
		local door, foot = placeHeli(pose, t, leaveRel, zone)
		local phase = EvacPath.Phase(t, leaveRel)
		local root, character = myRoot()
		reach = root ~= nil and not ride and (state == "Breakout" or state == "Outbreak") and (phase == "Hover" or phase == "Crawl")
			and t > 1 and not character:GetAttribute("Downed") and not character:GetAttribute("Aboard")
			and not character:GetAttribute("OnLadder")
			and ((root.Position - foot) * Vector3.new(1, 0, 1)).Magnitude <= EVAC.Grab
			and root.Position.Y > foot.Y - 6 and root.Position.Y < door.Y
	end
	inReach = reach
	-- On the ladder: forward climbs (the stick, W, or the CLIMB button held on touch).
	local _, character = myRoot()
	if onLadder and not (character and character:GetAttribute("OnLadder")) then
		onLadder = false
	end
	if onLadder then
		local move = if controls then controls:GetMoveVector() else Vector3.zero
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local stick = not controls and humanoid and humanoid.MoveDirection.Magnitude > 0.3
		local want = holdClimb or stick or move.Z < -0.3 or UserInputService:IsKeyDown(Enum.KeyCode.W)
			or UserInputService:IsKeyDown(Enum.KeyCode.Up)
		if want ~= sentClimb then
			sentClimb = want
			Remotes.Evac:FireServer("Climb", want)
		end
		grabButton.Text = "CLIMB"
	else
		grabButton.Text = "GRAB"
		holdClimb = false
	end
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	gui.Enabled = reach or (onLadder and touchOnly)
	bindKeys(reach)
	if reach then
		grabScale.Scale = 1 + math.sin(os.clock() * 7) * 0.06
		ring.Transparency = 0.2 + (math.sin(os.clock() * 7) + 1) * 0.3
	end
end)
