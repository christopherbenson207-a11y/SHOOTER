-- The menu on join: the camera stands on the town road at night and drifts while the Beacon
-- weaves across the road toward you and back (see buildScene below), and the choices are
-- a worn stencil logo and heavy words on the left (StarterGui.Menu, authored in Studio):
-- PLAY, MODES, SHOP, SETTINGS (SettingsClient's screen). A hovered word turns amber, steps right, and its row lights with an
-- amber bar and wash (Bar, Glow). PLAY asks ServerScriptService.MenuServer to spawn you in
-- the chosen mode, then the screen cuts through black into the game. A match sends you back
-- here with Remotes.Menu "Show" (after the rescue).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local BeaconRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BeaconRig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local CFG = GameConfig.Menu
local HOVER = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
-- Characters don't load on join, and Roblox only copies StarterGui into PlayerGui when one
-- does, so the menu is copied in here; the copy Roblox adds at spawn is dropped.
local gui = playerGui:FindFirstChild("Menu") or game:GetService("StarterGui"):WaitForChild("Menu"):Clone()
gui.Parent = playerGui
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "Menu" and child ~= gui then
		child:Destroy()
	end
end)
local fade = gui:WaitForChild("Fade")
local pages = {
	Main = gui:WaitForChild("Main"),
	Modes = gui:WaitForChild("Modes"),
	Shop = gui:WaitForChild("Shop"),
}
local mainList = pages.Main:WaitForChild("List")
local playButton = mainList:WaitForChild("Play")

local camera = workspace.CurrentCamera
local scene, cameraHome
local mode = CFG.Modes[1]
local leaving = false
local currentPage = pages.Main
local beaconConn = nil

-- The background: the camera on the town road at night (GameConfig.Menu.RoadCamera) and a
-- local copy of the Beacon walking the road, lamps sweeping the asphalt.
local function buildScene()
	scene = Instance.new("Folder")
	scene.Name = "MenuScene"
	scene.Parent = workspace
	cameraHome = CFrame.lookAt(CFG.RoadCamera.From, CFG.RoadCamera.To)
	-- With no character nothing streams in on its own, so ask for the road around the shot,
	-- and again now and then while the menu is up so it doesn't stream back out.
	local folder = scene
	task.spawn(function()
		local spots = { CFG.RoadCamera.From, CFG.RoadCamera.To, (CFG.RoadCamera.To + CFG.BeaconRoute[1].At) / 2 }
		while scene == folder do
			for _, at in spots do
				pcall(player.RequestStreamAroundAsync, player, at, 5)
			end
			task.wait(8)
		end
	end)
end

local function walkBeacon()
	local source = ReplicatedStorage:WaitForChild("MenuBeacon", 10)
	if not source or not scene then
		return
	end
	local model = source:Clone()
	local root = model.PrimaryPart
	local route = CFG.BeaconRoute
	local rest = root.Position.Y - model:GetPivot().Y + 0.3 -- root height over the feet
	local baseRot = root.CFrame.Rotation
	local start = route[1].At
	local pos = Vector3.new(start.X, start.Y + rest, start.Z)
	local heading = -math.pi / 2
	local leg, holdLeft, t = 2, route[2].Hold or 0, 0
	model.Parent = scene
	local rig = BeaconRig.new(model)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local lamps = {}
	for i, name in { "LensL", "LensR" } do
		local lens = model:FindFirstChild(name)
		if lens then
			local from = Instance.new("Attachment")
			from.Parent = lens
			local tip = Instance.new("Part")
			tip.Size = Vector3.new(0.2, 0.2, 0.2)
			tip.Transparency = 1
			tip.Anchored = true
			tip.CanCollide = false
			tip.CanQuery = false
			tip.CanTouch = false
			tip.Parent = model
			local to = Instance.new("Attachment")
			to.Parent = tip
			local beam = Instance.new("Beam")
			beam.Attachment0 = from
			beam.Attachment1 = to
			-- A wide pale searchlight, like the match Beacon's (its lamps are its eyes).
			beam.Width0, beam.Width1 = 1.4, 14
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Brightness = 2.2
			beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.7, 0.72),
				NumberSequenceKeypoint.new(1, 0.86),
			})
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 226, 170))
			beam.Parent = lens
			local spot = Instance.new("PointLight")
			spot.Range = 18
			spot.Brightness = 3
			spot.Color = Color3.fromRGB(255, 226, 170)
			spot.Parent = tip
			-- Each lamp sweeps at its own pace, so the two never move together.
			table.insert(lamps, {
				Lens = lens,
				Tip = tip,
				Side = if i == 1 then -1 else 1,
				Speed = if i == 1 then 0.7 else 1.13,
				Phase = if i == 1 then 0 else 2.1,
			})
		end
	end

	-- A faint cold light on the side facing the camera, so it reads against the night sky.
	local rim = Instance.new("Part")
	rim.Size = Vector3.new(0.2, 0.2, 0.2)
	rim.Transparency = 1
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanQuery = false
	rim.CanTouch = false
	rim.Parent = model
	local rimLight = Instance.new("PointLight")
	rimLight.Range = 42
	rimLight.Brightness = 3
	rimLight.Color = Color3.fromRGB(150, 172, 215)
	rimLight.Shadows = false
	rimLight.Parent = rim

	local function turnTo(want, dt)
		local diff = (want - heading + math.pi) % (2 * math.pi) - math.pi
		heading += math.clamp(diff, -1.3 * dt, 1.3 * dt)
		return math.abs(diff)
	end

	beaconConn = RunService.RenderStepped:Connect(function(dt)
		if not root.Parent then
			return
		end
		t += dt
		local stop = route[leg]
		local target = Vector3.new(stop.At.X, pos.Y, stop.At.Z)
		local toTarget = target - pos
		local moving, staring = false, false
		if toTarget.Magnitude > 0.5 then
			if turnTo(math.atan2(toTarget.X, toTarget.Z), dt) < 0.9 then
				pos += toTarget.Unit * math.min(toTarget.Magnitude, CFG.BeaconSpeed * dt)
				moving = true
			end
		elseif holdLeft > 0 then
			-- Stands in the road and stares down it at you, lamps sweeping.
			local toCam = CFG.RoadCamera.From - pos
			staring = turnTo(math.atan2(toCam.X, toCam.Z), dt) < 0.2
			if staring then
				holdLeft -= dt
			end
		else
			leg = leg % #route + 1
			holdLeft = route[leg].Hold or 0
		end
		root.CFrame = CFrame.new(pos) * CFrame.Angles(0, heading, 0) * baseRot
		rig:Step(dt, moving)
		local toCam = (CFG.RoadCamera.From - pos) * Vector3.new(1, 0, 1)
		rim.CFrame = CFrame.new(pos + toCam.Unit * 16 + Vector3.new(0, 20, 0))
		for _, lamp in lamps do
			lamp.Phase += dt * 0.8 * lamp.Speed
			local swing = math.sin(lamp.Phase) * 0.55 + lamp.Side * 0.15
			local wave = math.sin(lamp.Phase * 0.6 + lamp.Side)
			local reach = if staring then 40 + wave * 14 else 30 + wave * 12
			local from = lamp.Lens.Position
			local angle = heading + swing
			local ground = Vector3.new(pos.X, start.Y + 1, pos.Z) + Vector3.new(math.sin(angle), 0, math.cos(angle)) * reach
			local dir = (ground - from).Unit * 140
			local hit = workspace:Raycast(from, dir, params)
			lamp.Tip.CFrame = CFrame.new(if hit then hit.Position else from + dir)
		end
	end)
end

local function clearScene()
	if beaconConn then
		beaconConn:Disconnect()
		beaconConn = nil
	end
	if scene then
		scene:Destroy()
		scene = nil
	end
end

-- Words: amber and a step right while hovered or selected with a gamepad.
local function hover(button, on)
	local pad = button:FindFirstChildOfClass("UIPadding")
	local base = button:GetAttribute("BaseColor")
	if not base then
		base = button.TextColor3
		button:SetAttribute("BaseColor", base)
	end
	TweenService:Create(button, HOVER, { TextColor3 = if on then CFG.Accent else base }):Play()
	if pad then
		TweenService:Create(pad, HOVER, { PaddingLeft = UDim.new(if on then 0.03 else 0, 0) }):Play()
	end
	local bar = button:FindFirstChild("Bar")
	if bar then
		TweenService:Create(bar, HOVER, { BackgroundTransparency = if on then 0 else 1 }):Play()
	end
	local glow = button:FindFirstChild("Glow")
	if glow then
		TweenService:Create(glow, HOVER, { BackgroundTransparency = if on then 0 else 1 }):Play()
	end
end

-- The mode tag sits just after the word PLAY, however wide it renders.
local function placeModeTag()
	local tag = playButton:FindFirstChild("Mode")
	if tag and playButton.AbsoluteSize.X > 0 then
		tag.Position = UDim2.new(0, playButton.TextBounds.X + playButton.AbsoluteSize.Y * 0.22, 0.55, 0)
		tag.TextSize = math.max(12, math.floor(playButton.AbsoluteSize.Y * 0.3))
	end
end
playButton:GetPropertyChangedSignal("TextBounds"):Connect(placeModeTag)
playButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeModeTag)

local function firstButton(page)
	local best
	for _, b in page.List:GetChildren() do
		if b:IsA("TextButton") and (not best or b.LayoutOrder < best.LayoutOrder) then
			best = b
		end
	end
	return best
end

local function show(name)
	for key, page in pages do
		page.Visible = key == name
	end
	currentPage = pages[name]
	for _, b in currentPage.List:GetChildren() do
		if b:IsA("TextButton") then
			hover(b, false)
		end
	end
	if GuiService.SelectedObject then
		GuiService.SelectedObject = firstButton(currentPage)
	end
end

-- A mode with an Unlock (GameConfig.Modes) stays dim, with one small line after its name,
-- until the player has that Profile flag (Escaped: they got out on the helicopter once).
local function isLocked(name)
	local rules = GameConfig.Modes[name]
	return rules ~= nil and rules.Unlock ~= nil and player:GetAttribute(rules.Unlock) ~= true
end

local function setMode(name)
	if isLocked(name) then
		name = CFG.Modes[1]
	end
	mode = name
	playButton.Mode.Text = string.upper(name)
	placeModeTag()
	for _, b in pages.Modes.List:GetChildren() do
		local mark = b:FindFirstChild("Pick")
		if mark then
			mark.Visible = b:GetAttribute("Mode") == name
			mark.Position = UDim2.new(0, b.TextBounds.X + 14, 0.52, 0)
		end
		local lock = b:FindFirstChild("Locked")
		if lock then
			local locked = isLocked(b:GetAttribute("Mode"))
			lock.Visible = locked
			lock.Position = UDim2.new(0, b.TextBounds.X + 18, 0.55, 0)
			b.TextTransparency = if locked then 0.55 else 0
		end
	end
end

local function cameraLoop()
	local t0 = os.clock()
	RunService:BindToRenderStep("MenuCamera", Enum.RenderPriority.Camera.Value + 5, function()
		if not scene or not cameraHome then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		local t = os.clock() - t0
		local drift = Vector3.new(math.sin(t * 0.21), math.sin(t * 0.33) * 0.6, math.sin(t * 0.17) * 0.5) * CFG.Drift
		local view = camera.ViewportSize
		local mouse = UserInputService:GetMouseLocation()
		local mx = math.clamp(mouse.X / math.max(view.X, 1) - 0.5, -0.5, 0.5)
		local my = math.clamp(mouse.Y / math.max(view.Y, 1) - 0.5, -0.5, 0.5)
		local lean = Vector3.new(mx, -my * 0.5, 0) * CFG.Parallax
		camera.CFrame = cameraHome * CFrame.new(drift + lean) * CFrame.Angles(0, -mx * 0.02, 0)
		camera.FieldOfView = 60
	end)
end

local function enterGame()
	if leaving then
		return
	end
	leaving = true
	GuiService.SelectedObject = nil
	TweenService:Create(fade, TweenInfo.new(CFG.FadeTime), { BackgroundTransparency = 0 }):Play()
	task.wait(CFG.FadeTime)
	Remotes.Menu:FireServer("Play", mode)
	-- The body from the last run (sent back here alive or dead) is gone: wait for the new one.
	local character = player.Character
	if not character or not character:IsDescendantOf(workspace) then
		character = player.CharacterAdded:Wait()
	end
	character:WaitForChild("Humanoid")
	task.wait(0.2)
	RunService:UnbindFromRenderStep("MenuCamera")
	-- Hand the cursor back to GunClient's first-person setup (hidden, locked to the centre).
	UserInputService.MouseIconEnabled = false
	clearScene()
	for _, page in pages do
		page.Visible = false
	end
	gui.Shade.Visible = false
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
	camera.FieldOfView = 70
	local hud = playerGui:WaitForChild("HUD", 5)
	if hud then
		hud.Enabled = true
	end
	local out = TweenService:Create(fade, TweenInfo.new(CFG.FadeTime * 1.6), { BackgroundTransparency = 1 })
	out:Play()
	out.Completed:Wait()
	gui.Enabled = false
end

-- Wire the words.
local function wire(button, onClick)
	button.MouseEnter:Connect(function()
		hover(button, true)
	end)
	button.MouseLeave:Connect(function()
		hover(button, false)
	end)
	button.SelectionGained:Connect(function()
		hover(button, true)
	end)
	button.SelectionLost:Connect(function()
		hover(button, false)
	end)
	button.Activated:Connect(function()
		if not leaving then
			onClick()
		end
	end)
end

wire(playButton, function()
	task.spawn(enterGame)
end)
wire(mainList:WaitForChild("Modes"), function()
	show("Modes")
	setMode(mode)
end)
wire(mainList:WaitForChild("Shop"), function()
	show("Shop")
end)
wire(mainList:WaitForChild("Settings"), function()
	script.Parent:WaitForChild("SettingsClient"):WaitForChild("Open"):Fire()
end)
for _, b in pages.Modes.List:GetChildren() do
	if b:IsA("TextButton") and b:GetAttribute("Mode") then
		wire(b, function()
			if isLocked(b:GetAttribute("Mode")) then
				return
			end
			setMode(b:GetAttribute("Mode"))
			show("Main")
		end)
	end
end
wire(pages.Modes.List:WaitForChild("Back"), function()
	show("Main")
end)
wire(pages.Shop.List:WaitForChild("Back"), function()
	show("Main")
end)

-- A gamepad picks words with the D-pad; B goes back.
UserInputService.InputBegan:Connect(function(input)
	if leaving or not gui.Enabled then
		return
	end
	if input.UserInputType.Name:find("Gamepad") then
		if input.KeyCode == Enum.KeyCode.ButtonB and currentPage ~= pages.Main then
			show("Main")
		elseif not GuiService.SelectedObject then
			GuiService.SelectedObject = firstButton(currentPage)
		end
	end
end)

-- Every spawn after the menu hands the camera back to the normal follow camera, so a
-- camera left in the menu's Scriptable mode can never strand a player.
player.CharacterAdded:Connect(function(character)
	if gui.Enabled and not leaving then
		return
	end
	local humanoid = character:WaitForChild("Humanoid")
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
end)

-- Open the menu: on join (players already in a match skip it), and again whenever a match
-- sends you back.
local function openMenu()
	leaving = false
	clearScene()
	local hud = playerGui:FindFirstChild("HUD")
	if hud then
		hud.Enabled = false
	end
	gui.Enabled = true
	gui.Shade.Visible = true
	fade.BackgroundTransparency = 0
	show("Main")
	setMode(mode)
	buildScene()
	walkBeacon()
	cameraLoop()
	TweenService:Create(fade, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
end

if workspace:GetAttribute("Campaign") then
	-- Operation Last Light's own place: no menu here. Black covers the load, then you deploy
	-- with the squad (WarServer); the lobby is a teleport away when it is over.
	mode = "War"
	gui.Enabled = true
	for _, page in pages do
		page.Visible = false
	end
	gui.Shade.Visible = false
	fade.BackgroundTransparency = 0
	task.spawn(enterGame)
elseif player:GetAttribute("InMatch") then
	gui.Enabled = false
else
	openMenu()
end

Remotes.Menu.OnClientEvent:Connect(function(action)
	if action == "Show" and not player:GetAttribute("InMatch") and not workspace:GetAttribute("Campaign") then
		openMenu()
	end
end)
