-- Hiding inside a dumpster (EvadeServer sets the character attribute Inside):
--   your camera lifts out over the dumpster and watches the street, turned to keep the Beacon
--   in view, so you can see where it went and pick your moment. Drag (mouse, touch or the
--   right stick) to look round yourself; it drifts back to the Beacon once you let go.
--   Jump, roll or the Leave prompt climbs out (StarterPlayerScripts.Evade, EvadeServer).
-- Anyone inside a dumpster is invisible on every screen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local HEIGHT = 5 -- pivot above you (the dumpster's lid)
local DISTANCE = 15
local PITCH = math.rad(-14)
local PITCH_MIN, PITCH_MAX = math.rad(-55), math.rad(20)
local MOUSE_SPEED = math.rad(0.25) -- per pixel
local TOUCH_SPEED = math.rad(0.35)
local STICK_SPEED = math.rad(160) -- per second at full tilt
local FOLLOW_AFTER = 1.5 -- seconds without input before it turns back to the Beacon
local FOLLOW_RATE = 2.5

local watching = nil -- { Yaw, Pitch, LastInput }
local touches = {} -- [InputObject] = last position
local stick = Vector2.zero

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

-- No crosshair while you watch from the dumpster (you can't shoot from in there).
local function showCrosshair(on)
	local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("HUD")
	local crosshair = hud and hud:FindFirstChild("Crosshair")
	if crosshair then
		crosshair.Visible = on
	end
end

local function insideNow()
	local character = player.Character
	return character ~= nil and character:GetAttribute("Inside") == true
end

local function beaconPos()
	local beacon = workspace:FindFirstChild("Beacon")
	local head = beacon and (beacon:FindFirstChild("Head") or beacon.PrimaryPart)
	return head and head.Position
end

-- The yaw that puts the dumpster in front of the camera and the Beacon beyond it.
local function yawToward(from, to)
	local d = (to - from) * Vector3.new(1, 0, 1)
	if d.Magnitude < 0.5 then
		return nil
	end
	return math.atan2(-d.X, -d.Z)
end

local function start(root)
	local camera = workspace.CurrentCamera
	local _, yaw = camera.CFrame:ToOrientation()
	local target = beaconPos()
	yaw = (target and yawToward(root.Position, target)) or yaw
	watching = { Yaw = yaw, Pitch = PITCH, LastInput = -math.huge }
	table.clear(touches)
	showCrosshair(false)
end

local function stop()
	watching = nil
	showCrosshair(true)
	local camera = workspace.CurrentCamera
	local character = player.Character
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	if character then
		camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
	end
end

local function look(dx, dy, speed)
	if watching then
		watching.Yaw -= dx * speed
		watching.Pitch = math.clamp(watching.Pitch - dy * speed, PITCH_MIN, PITCH_MAX)
		watching.LastInput = os.clock()
	end
end

UserInputService.InputChanged:Connect(function(input, processed)
	if not watching then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		look(input.Delta.X, input.Delta.Y, MOUSE_SPEED)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stick = Vector2.new(input.Position.X, input.Position.Y)
	elseif input.UserInputType == Enum.UserInputType.Touch and touches[input] and not processed then
		local last = touches[input]
		touches[input] = input.Position
		look(input.Position.X - last.X, input.Position.Y - last.Y, TOUCH_SPEED)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if watching and input.UserInputType == Enum.UserInputType.Touch and not processed then
		touches[input] = input.Position
	end
end)

UserInputService.InputEnded:Connect(function(input)
	touches[input] = nil
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stick = Vector2.zero
	end
end)

RunService:BindToRenderStep("HideWatch", Enum.RenderPriority.Camera.Value + 20, function(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local inside = root ~= nil and insideNow()
	if inside and not watching then
		start(root)
	elseif not inside and watching then
		stop()
	end
	if not watching then
		return
	end
	if stick.Magnitude > 0.15 then
		look(stick.X * STICK_SPEED * dt, -stick.Y * STICK_SPEED * dt, 1)
	end
	-- Left alone, it turns back to keep the Beacon in view.
	local target = beaconPos()
	if target and os.clock() - watching.LastInput > FOLLOW_AFTER then
		local want = yawToward(root.Position, target)
		if want then
			local diff = (want - watching.Yaw + math.pi) % (2 * math.pi) - math.pi
			watching.Yaw += diff * math.min(1, dt * FOLLOW_RATE)
		end
		watching.Pitch += (PITCH - watching.Pitch) * math.min(1, dt * FOLLOW_RATE)
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	local pivot = root.Position + Vector3.new(0, HEIGHT, 0)
	local rot = CFrame.fromOrientation(watching.Pitch, watching.Yaw, 0)
	local back = rot:VectorToWorldSpace(Vector3.new(0, 0, DISTANCE))
	-- Don't put the lens through a wall.
	params.FilterDescendantsInstances = { character, workspace:FindFirstChild("Beacon") }
	local hit = workspace:Raycast(pivot, back, params)
	local eye = if hit then pivot + back.Unit * math.max(hit.Distance - 0.8, 2) else pivot + back
	camera.CFrame = CFrame.new(eye) * rot
end)

-- Bodies inside dumpsters are hidden on this screen. Coming out, each part gets back exactly
-- the transparency it had (your own body stays hidden the way first person keeps it).
local hidden = {} -- [character] = { [part] = LocalTransparencyModifier before hiding }
RunService.Heartbeat:Connect(function()
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if character then
			local inside = character:GetAttribute("Inside") == true
			local saved = hidden[character]
			if inside then
				saved = saved or {}
				hidden[character] = saved
				for _, d in character:GetDescendants() do
					if (d:IsA("BasePart") or d:IsA("Decal")) and saved[d] == nil then
						saved[d] = d.LocalTransparencyModifier
					end
					if saved[d] ~= nil then
						d.LocalTransparencyModifier = 1
					end
				end
			elseif saved then
				for d, ltm in saved do
					if d.Parent then
						d.LocalTransparencyModifier = ltm
					end
				end
				hidden[character] = nil
			end
		end
	end
	for character in hidden do
		if not character.Parent then
			hidden[character] = nil
		end
	end
end)
