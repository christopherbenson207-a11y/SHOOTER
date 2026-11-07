-- Phone and tablet controls (shown while the last input was touch). The buttons live in StarterGui.TouchControls.
-- Right thumb: big Fire, which follows the gun's TouchFire style (GameConfig.Guns): AK aims
-- and fires while held, the Sniper aims while held and fires on release, Pistol and Shotgun
-- fire from the hip. Around it: Aim (toggle), Reload, Jump and Crouch (a slide while sprinting). Dragging a held Fire
-- button also turns the view, so you can track a target while shooting. Everywhere else on
-- the right of the screen, LookPad turns the view (it takes those touches from Roblox's own
-- camera so the player's settings apply): Options LookSens (AimSens on top while aiming),
-- InvertY, and gyro aim (Gyro Off / Aiming / Always, GyroSens). ButtonSize scales the buttons.
-- Left thumb: Roblox's thumbstick; pushing it to the edge sprints.
-- No flashlight button on touch (the owner had it removed). The Roblox jump button is hidden,
-- since Jump replaces it. While they're up the player attribute TouchHud is true, and HudScale moves health and ammo to the top corners, out from under
-- the thumbs.
-- A phone counts as touch from its device flags as well as Platform, since PreferredInput
-- doesn't always report Touch (Studio's device emulator, some tablets).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Platform = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Platform"))
local Options = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Options"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local touchInput = script.Parent:WaitForChild("GunClient"):WaitForChild("TouchInput")
local gui = playerGui:WaitForChild("TouchControls")

local LOOK_SPEED = math.rad(GameConfig.Settings.TouchLook) -- per pixel of drag at 70 FOV, sensitivity 1
local SPRINT_PUSH = 0.95
local PITCH_LIMIT = math.rad(80)

-- Buttons are laid out for a 480-pixel-tall screen and shrink on shorter ones.
local REF_HEIGHT = 480
local scale = 1
local bases = {}
for _, button in gui:GetChildren() do
	if button:IsA("GuiButton") then
		bases[button] = { button.Size, button.Position }
	end
end

local function sized(button, down)
	local base = bases[button]
	local s = scale * (if down then 0.9 else 1)
	button.Size = UDim2.fromOffset(base[1].X.Offset * s, base[1].Y.Offset * s)
end

local function rescale()
	local camera = workspace.CurrentCamera
	scale = math.clamp((camera and camera.ViewportSize.Y or REF_HEIGHT) / REF_HEIGHT, 0.62, 1) * Options.Get("ButtonSize")
	for button, base in bases do
		local p = base[2]
		button.Position = UDim2.new(p.X.Scale, p.X.Offset * scale, p.Y.Scale, p.Y.Offset * scale)
		sized(button, false)
	end
end
rescale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(rescale)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end
Options.Changed:Connect(function(key)
	if key == "ButtonSize" then
		rescale()
	end
end)

-- Press feedback: the button shrinks a little while held.
local function press(button, down)
	sized(button, down)
end

-- Fire buttons: hold to shoot, drag to look.
local lookDelta = Vector2.zero
local fireTouches = {} -- [InputObject] = last position
local firing = 0

local function wireFire(button)
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or fireTouches[input] then
			return
		end
		fireTouches[input] = input.Position
		firing += 1
		press(button, true)
		if firing == 1 then
			touchInput:Fire("Fire", true)
		end
	end)
end
wireFire(gui:WaitForChild("Fire"))

-- The look pad: a drag anywhere on it turns the view.
local padTouches = {} -- [InputObject] = last position
gui:WaitForChild("LookPad").InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch and not fireTouches[input] then
		padTouches[input] = input.Position
	end
end)

UserInputService.TouchMoved:Connect(function(input)
	local last = fireTouches[input] or padTouches[input]
	if last then
		local pos = input.Position
		lookDelta += Vector2.new(pos.X - last.X, pos.Y - last.Y)
		if fireTouches[input] then
			fireTouches[input] = pos
		else
			padTouches[input] = pos
		end
	end
end)

UserInputService.TouchEnded:Connect(function(input)
	padTouches[input] = nil
	if not fireTouches[input] then
		return
	end
	fireTouches[input] = nil
	firing -= 1
	if firing <= 0 then
		firing = 0
		press(gui.Fire, false)
		touchInput:Fire("Fire", false)
	end
end)

-- Gyro aim: how far the phone turned since the last reading, as (yaw, pitch) in radians, measured
-- against gravity so it reads the same in portrait, either landscape, upright or tilted back.
-- Roblox reports both the device rotation and gravity in the phone's own frame: X toward its left
-- edge, Y out of the screen, Z toward its top edge, gravity pointing at the ground (upright
-- portrait reads (0, 0, -9.81), screen up reads (0, -9.81, 0)). Each reading's turn is the rotation
-- from the last device CFrame to this one in that frame, as axis times angle. Yaw is the part of it
-- about the up direction; pitch the part about the screen's own horizontal edge (up x screen
-- normal). Reading Euler angles in the phone's frame instead (the old way) took the screen normal
-- for the up axis: in landscape a turn left or right came out as the view tilting down or up.
-- Options GyroFlip reverses both, for a device that reports the other way round.
local gyroDelta = Vector2.zero
local lastGyro: CFrame? = nil
local SCREEN_OUT = Vector3.yAxis
local MAX_STEP = math.rad(30) -- one reading turning further than this is the sensor re-centring

-- Up in the phone's frame: from gravity, or from the screen orientation on a phone without one.
local function upInDevice(): Vector3
	if UserInputService.AccelerometerEnabled then
		local ok, gravity = pcall(UserInputService.GetDeviceGravity, UserInputService)
		local g = if ok and gravity then gravity.Position else nil
		if g and g.Magnitude > 0.5 then
			return -g.Unit
		end
	end
	local orientation = playerGui.CurrentScreenOrientation
	if orientation == Enum.ScreenOrientation.LandscapeLeft then
		return -Vector3.xAxis
	elseif orientation == Enum.ScreenOrientation.LandscapeRight or orientation == Enum.ScreenOrientation.LandscapeSensor then
		return Vector3.xAxis
	end
	return Vector3.zAxis
end

if UserInputService.GyroscopeEnabled then
	UserInputService.DeviceRotationChanged:Connect(function(_rotation, cf)
		local mode = Options.Get("Gyro")
		local on = gui.Enabled and (mode == "Always" or (mode == "Aiming" and player:GetAttribute("Aiming") == true))
		if not on then
			lastGyro = nil
			return
		end
		if lastGyro then
			local axis, angle = lastGyro:ToObjectSpace(cf):ToAxisAngle()
			if angle == angle and angle > 1e-5 and angle < MAX_STEP then
				local turn = axis * angle
				local up = upInDevice()
				local side = up:Cross(SCREEN_OUT)
				local pitch = if side.Magnitude > 0.15 then turn:Dot(side.Unit) else 0
				gyroDelta += Vector2.new(turn:Dot(up), pitch)
			end
		end
		lastGyro = cf
	end)
end

-- Turn the view by the drag (and the gyro) before the camera runs; the camera keeps whatever
-- way we face.
RunService:BindToRenderStep("TouchLook", Enum.RenderPriority.Input.Value, function()
	if lookDelta == Vector2.zero and gyroDelta == Vector2.zero then
		return
	end
	local delta, gyro = lookDelta, gyroDelta
	lookDelta, gyroDelta = Vector2.zero, Vector2.zero
	local camera = workspace.CurrentCamera
	if not camera or player:GetAttribute("Cutscene") then
		return
	end
	local sens = Options.Get("LookSens") * (if player:GetAttribute("Aiming") then Options.Get("AimSens") else 1)
	local flip = if Options.Get("InvertY") then -1 else 1
	local speed = LOOK_SPEED * sens * camera.FieldOfView / 70
	-- The gyro follows the phone itself; InvertY is for the drag only.
	local gyroSens = Options.Get("GyroSens") * (if Options.Get("GyroFlip") then -1 else 1)
	local cf = camera.CFrame
	local pitch, yaw = cf:ToOrientation()
	pitch = math.clamp(pitch - delta.Y * speed * flip + gyro.Y * gyroSens, -PITCH_LIMIT, PITCH_LIMIT)
	yaw += gyro.X * gyroSens - delta.X * speed
	camera.CFrame = CFrame.new(cf.Position) * CFrame.fromOrientation(pitch, yaw, 0)
end)

-- Tap buttons.
local function tap(button, fn)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			press(button, true)
			fn(input)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			press(button, false)
		end
	end)
end

tap(gui:WaitForChild("Aim"), function()
	touchInput:Fire("Aim", true)
end)
tap(gui:WaitForChild("Reload"), function()
	touchInput:Fire("Reload", true)
end)
local touchCrouch = script.Parent:WaitForChild("Evade"):WaitForChild("TouchCrouch")
-- The touch goes with it so holding the button lies you down (Evade watches it end).
tap(gui:WaitForChild("Crouch"), function(input)
	touchCrouch:Fire(input)
end)
-- Jump. Roblox's control script writes Humanoid.Jump every frame from its own (hidden) jump
-- button, which wiped a one-frame Jump = true before physics ever saw it. So the press jumps
-- at once through the state machine, and while the finger stays down Jump is held after
-- the control script has run (auto-jump on landing, like the stock button).
local jumpHeld = false
local evadeStand = script.Parent:WaitForChild("Evade"):WaitForChild("Stand")
local jumpButton = gui:WaitForChild("Jump")
jumpButton.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	press(jumpButton, true)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if character:GetAttribute("Hiding") then
		Remotes.Evade:FireServer("Leave")
		return
	end
	if character:GetAttribute("Crouching") then
		evadeStand:Fire()
		return
	end
	jumpHeld = true
	local canJump = if humanoid.UseJumpPower then humanoid.JumpPower > 0 else humanoid.JumpHeight > 0
	if canJump and humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)
jumpButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		press(jumpButton, false)
		jumpHeld = false
	end
end)
RunService:BindToRenderStep("LastLightTouchJump", Enum.RenderPriority.Input.Value + 2, function()
	if not jumpHeld then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and not character:GetAttribute("Crouching") then
		humanoid.Jump = true
	end
end)

-- Last real input: a touch turns the controls on, a key or mouse click on a device that has
-- a keyboard turns them off (a laptop with a touchscreen).
local lastTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
UserInputService.InputBegan:Connect(function(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch then
		lastTouch = true
	elseif kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton1
		or kind == Enum.UserInputType.MouseButton2 or kind.Name:match("^Gamepad")
	then
		lastTouch = false
	end
end)

local function isTouch()
	if player:GetAttribute("ForceTouch") == true then
		return true
	end
	local override = player:GetAttribute("DebugInputMode")
	if override then
		return override == "Touch"
	end
	return Platform.IsTouch() or (UserInputService.TouchEnabled and lastTouch)
end

-- Hide what these buttons replace.
local function hideStock()
	for _, name in { "Crouch", "Flashlight" } do
		local stock = ContextActionService:GetButton(name)
		if stock then
			stock.Visible = false
		end
	end
	-- The PlayerModule shows its jump button again whenever the humanoid changes, so this
	-- runs every frame.
	local touchGui = playerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") then
		jump.Visible = false
		jump.Active = false
	end
end

-- Show the controls only while you're playing (not in the menu or a cutscene, not dead).
local sprinting = false
RunService.Heartbeat:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local menu = playerGui:FindFirstChild("Menu")
	local hud = playerGui:FindFirstChild("HUD")
	-- ForceTouch (player attribute) shows these on a PC, for testing in Studio.
	local playing = isTouch()
		and humanoid ~= nil
		and humanoid.Health > 0
		and not player:GetAttribute("Cutscene")
		and not (menu and menu.Enabled)
		and (hud == nil or hud.Enabled)
	if gui.Enabled ~= playing then
		gui.Enabled = playing
		player:SetAttribute("TouchHud", playing)
		table.clear(padTouches)
		if not playing and firing > 0 then
			table.clear(fireTouches)
			firing = 0
			touchInput:Fire("Fire", false)
		end
	end
	if playing or isTouch() then
		hideStock()
	end

	-- The stick's push shows in MoveDirection's length; sprint when it's near full and forward.
	local push = humanoid and humanoid.MoveDirection or Vector3.zero
	local camera = workspace.CurrentCamera
	local ahead = camera and (camera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit or Vector3.zero
	local sprint = playing and push.Magnitude >= SPRINT_PUSH and push.Unit:Dot(ahead) > 0.5
	if sprint ~= sprinting then
		sprinting = sprint
		touchInput:Fire("Sprint", sprint)
	end
end)
