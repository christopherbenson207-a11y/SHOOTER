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
local GyroAim = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GyroAim"))
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

-- Gyro aim: Shared.GyroAim turns each rotation reading into (yaw, pitch) and filters it per frame
-- (player-space yaw, tightening, soft tiered smoothing; docs/GYRO-AIM.md). It works out how this
-- phone reports its axes by itself, from the gravity sensor, and keeps doing so while the gyro is
-- off so it's ready when switched on. The event is connected even when GyroscopeEnabled says no
-- (some phones report it wrongly); it just never fires on a phone without one.
local gyroAim = GyroAim.new()
local gravity: Vector3? = nil
if UserInputService.AccelerometerEnabled then
	local ok, reading = pcall(UserInputService.GetDeviceGravity, UserInputService)
	if ok and reading then
		gravity = reading.Position
	end
end
UserInputService.DeviceGravityChanged:Connect(function(reading)
	gravity = reading.Position
end)

local function gyroOn(): boolean
	local mode = Options.Get("Gyro")
	return gui.Enabled and (mode == "Always" or (mode == "Aiming" and player:GetAttribute("Aiming") == true))
end

UserInputService.DeviceRotationChanged:Connect(function(_rotation, cf)
	gyroAim:Reading(cf, gravity, gyroOn())
end)

-- Turn the view by the drag (and the gyro) before the camera runs; the camera keeps whatever
-- way we face.
RunService:BindToRenderStep("TouchLook", Enum.RenderPriority.Input.Value, function(dt)
	local gyro = gyroAim:Step(dt)
	if lookDelta == Vector2.zero and gyro == Vector2.zero then
		return
	end
	local delta = lookDelta
	lookDelta = Vector2.zero
	local camera = workspace.CurrentCamera
	if not camera or player:GetAttribute("Cutscene") then
		return
	end
	local sens = Options.Get("LookSens") * (if player:GetAttribute("Aiming") then Options.Get("AimSens") else 1)
	local flip = if Options.Get("InvertY") then -1 else 1
	local speed = LOOK_SPEED * sens * camera.FieldOfView / 70
	-- The gyro follows the phone itself (sensitivity 1 turns the view as far as the phone turns);
	-- InvertY is for the drag only. GyroFlip reverses left/right only: up/down always comes out
	-- right from GyroAim's self-check, left/right is the one thing a phone can still report backwards.
	local gyroSens = Options.Get("GyroSens")
	local gyroYaw = if Options.Get("GyroFlip") then -1 else 1
	local cf = camera.CFrame
	local pitch, yaw = cf:ToOrientation()
	pitch = math.clamp(pitch - delta.Y * speed * flip + gyro.Y * gyroSens, -PITCH_LIMIT, PITCH_LIMIT)
	yaw += gyro.X * gyroSens * gyroYaw - delta.X * speed
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
