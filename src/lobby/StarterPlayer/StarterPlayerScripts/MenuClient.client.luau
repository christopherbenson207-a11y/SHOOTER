-- MenuClient (FRONT-A rewrite, 4 Nov 2026; contract horror-shooter/menu/CONTRACTS.md, MENU-PLAN 9).
-- The scene and the shell around the authored menu:
--   * The camera stands on the town road at night (GameConfig.Menu.RoadCamera) and drifts; the mouse leans it a
--     little. A local copy of the Beacon walks GameConfig.Menu.BeaconRoute with two independent sweeping lamps and a
--     cold rim light. The Beacon never stands still (it turns and stares while holding) and carries no sound.
--   * MenuStage puts the operators in the dark observation post on the right (Workspace.Menu) and eases the camera
--     between framings (Home, Loadout, Operator, Store) chosen by the page on screen.
--   * Router (Shared.Menu.Router) runs the pages in MenuPages; this script only decides when the menu is up:
--       Lobby server: always, until a deploy drops you into a body (InMatch).
--       Match server (ServerRole "Match"): never, except for the AAR (the Aar page turns it on and off itself).
--   * First session (Stats.Matches == 0): FirstDeploy only (logo and DEPLOY, no top bar). After the first match the
--     full menu is revealed panel by panel.
--   * Deploying: the countdown runs on PLAY / HOME; at 1 s the Loading page shows and the teleport screen
--     (Assets.LoadingGui, filled with the mode art and the squad) is handed to TeleportService:SetTeleportGui, so the
--     same screen carries through the teleport (ReplicatedFirst.Boot keeps it up on arrival and skips the logo).
-- Old menu (Shade, Main, Modes, Shop, Fade, Classes) is gone; a copy of the old script is in
-- ServerStorage._Backups.MenuClient_2026-11-04_beforeFrontA. RescueClient unbinds the RenderStep "MenuCamera";
-- keep that name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local BeaconRig = require(Shared:WaitForChild("BeaconRig"))
local MenuShared = Shared:WaitForChild("Menu")
local Router = require(MenuShared:WaitForChild("Router"))
local Ui = require(MenuShared:WaitForChild("Ui"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Stage = require(script.Parent:WaitForChild("MenuStage"))
local pagesFolder = script.Parent:WaitForChild("MenuPages")
local Common = require(pagesFolder:WaitForChild("TopBar"):WaitForChild("Common"))
local LoadingPage = require(pagesFolder:WaitForChild("Loading"))

local CFG = GameConfig.Menu
local DRONE_ID = "rbxassetid://9125970426"
local DRONE_VOLUME = 0.22

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- The ScreenGuis --------------------------------------------------------------------------------------------------
-- Characters don't load on join and Roblox copies StarterGui into PlayerGui only when one does, so the menu's
-- ScreenGuis are copied in here; the copies Roblox adds at each spawn are dropped.
local OWN = { Menu = true, MenuBack = true, MenuFade = true }
local guis = {}
for name in OWN do
	local g = playerGui:FindFirstChild(name) or StarterGui:WaitForChild(name):Clone()
	g.Parent = playerGui
	guis[name] = g
end
playerGui.ChildAdded:Connect(function(child)
	if OWN[child.Name] and guis[child.Name] ~= child then
		child:Destroy()
	end
end)
local gui = guis.Menu
local back = guis.MenuBack
local fadeGui = guis.MenuFade
local fadeInk = fadeGui:WaitForChild("Ink")
local backInk = back:FindFirstChild("Ink")

local function isMatch()
	return workspace:GetAttribute("MatchServer") == true or workspace:GetAttribute("ServerRole") == "Match"
end

-- Fade through ink (the authored MenuFade image) -------------------------------------------------------------------
local fadeTween = nil
local function fade(toBlack, time)
	if fadeTween then
		fadeTween:Cancel()
	end
	fadeGui.Enabled = true
	fadeTween = TweenService:Create(fadeInk, TweenInfo.new(time, Enum.EasingStyle.Quad), {
		ImageTransparency = if toBlack then 0 else 1,
	})
	local t = fadeTween
	t:Play()
	if not toBlack then
		t.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and fadeTween == t then
				fadeGui.Enabled = false
			end
		end)
	end
	return t
end
local function black()
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
	fadeInk.ImageTransparency = 0
	fadeGui.Enabled = true
end

-- The low drone under the menu (no sound on the Beacon) ------------------------------------------------------------
local drone = nil
local function droneOn()
	if not drone then
		drone = Instance.new("Sound")
		drone.Name = "MenuDrone"
		drone.SoundId = DRONE_ID
		drone.Looped = true
		drone.Volume = 0
		local group = SoundService:FindFirstChild("Menu")
		if group and group:IsA("SoundGroup") then
			drone.SoundGroup = group
		end
		drone.Parent = SoundService
	end
	if not drone.IsPlaying then
		drone:Play()
	end
	TweenService:Create(drone, TweenInfo.new(2), { Volume = DRONE_VOLUME }):Play()
end
local function droneOff(time)
	if drone and drone.IsPlaying then
		local s = drone
		local t = TweenService:Create(s, TweenInfo.new(time or 0.8), { Volume = 0 })
		t:Play()
		t.Completed:Once(function()
			if s.Volume <= 0.001 then
				s:Stop()
			end
		end)
	end
end

-- The scene ---------------------------------------------------------------------------------------------------------
local scene = nil
local beaconConn = nil

-- With no character nothing streams in on its own, so ask for the road around the shot, and again now and then
-- while the menu is up so it doesn't stream back out.
-- The lean lobby place (workspace attribute LeanLobby, 4 Nov 2026) has no town: only the backdrop sets, so there is no
-- road to stream in and no Beacon walking it.
local LEAN = workspace:GetAttribute("LeanLobby") == true

local function buildScene()
	scene = Instance.new("Folder")
	scene.Name = "MenuScene"
	scene.Parent = workspace
	local folder = scene
	if LEAN then
		return
	end
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

-- A local copy of the Beacon walking the road, lamps sweeping the asphalt (each lamp at its own pace).
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
			table.insert(lamps, {
				Lens = lens,
				Tip = tip,
				Side = if i == 1 then -1 else 1,
				Speed = if i == 1 then 0.7 else 1.13,
				Phase = if i == 1 then 0 else 2.1,
			})
		end
	end
	Stage.SetBeacon(lamps, root)

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
	Stage.SetBeacon(nil, nil)
	if scene then
		scene:Destroy()
		scene = nil
	end
end

-- The camera: MenuStage's eased framing, a slow drift and a little mouse lean. Forced Scriptable every frame so a
-- respawn or another script can never leave the menu on a follow camera.
local function cameraLoop()
	local t0 = os.clock()
	RunService:UnbindFromRenderStep("MenuCamera")
	RunService:BindToRenderStep("MenuCamera", Enum.RenderPriority.Camera.Value + 5, function(dt)
		if not scene then
			return
		end
		camera = workspace.CurrentCamera
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
		camera.CFrame = Stage.Camera(dt) * CFrame.new(drift + lean) * CFrame.Angles(0, -mx * 0.02, 0)
		camera.FieldOfView = if Stage.Fov then Stage.Fov() else 60
		-- local lights only render near the camera's focus: keep it on the squad
		local focus = Stage.FocusPoint and Stage.FocusPoint()
		if focus then
			camera.Focus = CFrame.new(focus)
		end
	end)
end

-- The Router --------------------------------------------------------------------------------------------------------
local ctx = Router.Start({
	gui = gui,
	pages = pagesFolder,
	stage = Stage,
	camera = function(name)
		Stage.Frame(name)
	end,
})

local state = {
	leaving = false, -- deploying or in a body: the menu is on its way out
	loading = false, -- the Loading page is up
	revealed = false, -- the post-first-match reveal ran this session
	deploy = nil, -- the last Deploying payload
	teleportGui = false,
	status = nil,
}

local function hud(on)
	local h = playerGui:FindFirstChild("HUD")
	if h then
		h.Enabled = on
	end
end

local function loadingBack(on)
	if backInk then
		backInk.Visible = on
	end
end

-- Squad mates on the stage (you stand on Spot1, the others on Spot2..4 in party order) and who is READY on the plates
local function feedSquad()
	local ids = {}
	local ready = {}
	for _, m in Common.Squad(ctx).Members do
		if m.UserId ~= player.UserId then
			table.insert(ids, m.UserId)
		end
		if Common.IsReady(m) then
			ready[m.UserId] = true
		end
	end
	Stage.SetSquad(ids)
	if Stage.SetReady then
		Stage.SetReady(ready)
	end
end

-- Status for the squad slots: LOADOUT / STORE while on those pages, else IDLE. READY is separate (Party keeps it
-- through page changes and shows it over these).
local STATUS_OF = { Loadout = "LOADOUT", Picker = "LOADOUT", Store = "STORE", Confirm = "STORE" }
local function sendStatus(page)
	if player:GetAttribute("InMatch") == true or isMatch() then
		return
	end
	local s = STATUS_OF[page] or "IDLE"
	if s ~= state.status then
		state.status = s
		ctx.menu("Status", s)
	end
end

-- Wait (briefly) for the profile, so the first-session check reads real stats.
local function waitProfile()
	local t0 = os.clock()
	while player:GetAttribute("Stats") == nil and os.clock() - t0 < 20 do
		task.wait(0.1)
	end
end

local function matches()
	return tonumber(Common.Stats(player).Matches) or 0
end

-- After the first match: the top bar and HOME's panels appear one at a time, each with a tick.
local function reveal()
	state.revealed = true
	local top = ctx.pages.TopBar
	local parts = top and top.Parts and top.Parts(ctx) or {}
	for _, p in parts do
		p.Visible = false
	end
	ctx.showChrome(true)
	ctx.go("Home", { Reveal = true })
	task.spawn(function()
		task.wait(0.3)
		for _, p in parts do
			p.Visible = true
			Ui.Stagger({ p })
			ctx.sound("Tick")
			task.wait(0.12)
		end
	end)
end

-- A slow profile: if the stats arrive after we landed on the first-session screen, a returning player goes HOME.
player:GetAttributeChangedSignal("Stats"):Connect(function()
	if ctx.current == "FirstDeploy" and matches() > 0 and not state.leaving then
		ctx.showChrome(true)
		ctx.go("Home")
	end
end)

local function landingPage()
	if matches() == 0 then
		ctx.showChrome(false)
		ctx.go("FirstDeploy")
	elseif matches() == 1 and not state.revealed then
		reveal()
	else
		ctx.showChrome(true)
		ctx.go("Home")
	end
end

-- Open the menu: on join in a lobby, and again whenever a match sends you back ("Show").
local opening = false
local function openMenu()
	if opening or isMatch() or player:GetAttribute("InMatch") == true then
		return
	end
	opening = true
	RunService:UnbindFromRenderStep("MenuMouse")
	state.leaving = false
	state.loading = false
	state.deploy = nil
	state.teleportGui = false
	state.status = nil
	black()
	hud(false)
	loadingBack(false)
	clearScene()
	buildScene()
	if not LEAN then
		task.spawn(walkBeacon)
	end
	Stage.Start()
	Stage.Frame("Home")
	feedSquad()
	cameraLoop()
	ctx.setActive(true)
	waitProfile()
	landingPage()
	ctx.party("Refresh")
	droneOn()
	fade(false, 1.2)
	opening = false
end

-- Into the body the server gave you: the camera, cursor and HUD go back to the game.
local taking = false
local function takeBody()
	if taking then
		return
	end
	taking = true
	state.leaving = true
	if fadeInk.ImageTransparency > 0.01 then
		fade(true, 0.3).Completed:Wait()
	end
	-- The body from the last run (sent back here alive or dead) is gone: wait for the new one.
	local character = player.Character
	if not character or not character:IsDescendantOf(workspace) then
		character = player.CharacterAdded:Wait()
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	task.wait(0.2)
	RunService:UnbindFromRenderStep("MenuCamera")
	ctx.setActive(false)
	loadingBack(false)
	Stage.Stop()
	clearScene()
	droneOff(0.4)
	state.loading = false
	-- Hand the cursor back to GunClient's first-person setup (hidden, locked to the centre).
	UserInputService.MouseIconEnabled = false
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.FieldOfView = 70
	hud(true)
	fade(false, (CFG.FadeTime or 0.45) * 1.6)
	taking = false
end

-- Deploying -----------------------------------------------------------------------------------------------------------

-- The teleport screen: Assets.LoadingGui (authored), the current variant only, filled like the Loading page.
local function setTeleportGui(payload)
	local src = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("LoadingGui")
	if not src then
		return
	end
	local g = src:Clone()
	local variant = ctx.variant
	local view = workspace.CurrentCamera.ViewportSize
	local ref = Router.Variants[variant] or Router.Variants.Wide
	for name in Router.Variants do
		local root = g:FindFirstChild(name)
		if root then
			root.Visible = name == variant
			if name == variant then
				Router.Fit(root, Router.Variants[name] or ref, view)
			end
		end
	end
	Ui.Apply(g)
	local root = g:FindFirstChild(variant)
	local frame = root and root:FindFirstChild("Pages") and root.Pages:FindFirstChild("Loading")
	if frame then
		frame.Visible = true
		LoadingPage.Fill(frame, LoadingPage.Info(ctx, payload), Ui)
		Ui.Bar(frame:FindFirstChild("Progress"), 0.9)
	end
	local ok, err = pcall(TeleportService.SetTeleportGui, TeleportService, g)
	if not ok then
		warn("[MenuClient] SetTeleportGui", err)
	end
end

local function showLoading(payload)
	if state.loading then
		return
	end
	state.loading = true
	state.leaving = true
	loadingBack(true)
	ctx.showChrome(false)
	ctx.go("Loading", { Mode = payload.Mode, Chapter = payload.Chapter, Hold = 8 })
	droneOff(1.5)
end

-- Back to the menu after a cancel or a failed deploy.
local function backFromLoading()
	if not state.loading and not state.leaving then
		return
	end
	state.loading = false
	state.leaving = false
	state.deploy = nil
	state.teleportGui = false
	loadingBack(false)
	pcall(TeleportService.SetTeleportGui, TeleportService, nil)
	if player:GetAttribute("InMatch") == true or isMatch() then
		return
	end
	droneOn()
	landingPage()
end

ctx.on("Deploying", function(p)
	if type(p) ~= "table" or isMatch() then
		return
	end
	state.deploy = p
	player:SetAttribute("MenuLastMode", if p.Mode == "Campaign" or GameConfig.Modes[p.Mode] then p.Mode else nil)
	if not state.teleportGui then
		state.teleportGui = true
		setTeleportGui(p)
	end
	local s = tonumber(p.Seconds) or 0
	if s <= 1 then
		showLoading(p)
	else
		ctx.sound("Beep")
	end
end)

ctx.on("DeployFailed", function(reason)
	if reason ~= "NotLeader" then
		ctx.sound("Error")
	end
	if state.loading then
		fade(true, 0.25).Completed:Wait()
		backFromLoading()
		fade(false, 0.6)
	else
		state.teleportGui = false
	end
end)

-- The party state: squad mates on the stage, and a cancelled countdown takes you back.
ctx.on("Party", function(s)
	feedSquad()
	if type(s) == "table" and s.State == "Idle" and (state.loading or state.teleportGui) and not taking
		and player:GetAttribute("InMatch") ~= true
	then
		if state.loading then
			backFromLoading()
		else
			state.teleportGui = false
			pcall(TeleportService.SetTeleportGui, TeleportService, nil)
		end
	end
end)

-- How much the 3D stage dims behind each page (MenuBack.Dim, 0 = clear): dense pages get a calm, dark backing so
-- their text reads at a glance; the pages that show your soldier keep the stage clear.
local DIM = { Home = 0, Loadout = 0, Picker = 0.35, Store = 0.35, Play = 0.75, Pass = 0.82, Record = 0.82, Aar = 0.7 }
local backDim = back:FindFirstChild("Dim")

-- HOME's backdrop switcher (Pages.Home.Backdrop): the arrows step through Settings > Menu backdrop, which saves it;
-- MenuStage follows Options.Changed and cuts to the new set.
do
	local okO, Options = pcall(require, ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Options"))
	local okG, Config = pcall(require, ReplicatedStorage.Shared:WaitForChild("GameConfig"))
	local option = okG and Config.Settings and Config.Settings.Backdrop
	if okO and option and option.Choices then
		local names = {}
		local function label(id)
			local sets = workspace:FindFirstChild("MenuSets")
			local set = sets and sets:FindFirstChild(id)
			local shown = set and set:GetAttribute("DisplayName")
			return if type(shown) == "string" then shown else string.upper(id)
		end
		local function refresh()
			local id = Options.Get("Backdrop") or option.Default
			for _, l in names do
				l.Text = label(id)
			end
		end
		local function stepBy(d)
			local list = option.Choices
			local i = table.find(list, Options.Get("Backdrop")) or 1
			Options.Set("Backdrop", list[((i - 1 + d) % #list) + 1])
		end
		for _, variant in { "Wide", "Phone" } do
			local root = gui:FindFirstChild(variant)
			local pages = root and root:FindFirstChild("Pages")
			local home = pages and pages:FindFirstChild("Home")
			local w = home and home:FindFirstChild("Backdrop")
			if w then
				local prev, nxt, name = w:FindFirstChild("Prev"), w:FindFirstChild("Next"), w:FindFirstChild("SetName")
				if prev and prev:IsA("GuiButton") then
					Ui.Button(prev, function()
						stepBy(-1)
					end)
				end
				if nxt and nxt:IsA("GuiButton") then
					Ui.Button(nxt, function()
						stepBy(1)
					end)
				end
				if name and name:IsA("TextLabel") then
					table.insert(names, name)
				end
			end
		end
		Options.Changed:Connect(function(key)
			if key == "Backdrop" then
				refresh()
			end
		end)
		refresh()
	end
end

ctx.on("Page", function(name)
	local p = ctx.pages[name]
	Stage.Frame(p and p.Camera or "Home")
	if Stage.SetPlates then
		Stage.SetPlates(name == "Home")
	end
	sendStatus(name)
	if backDim and backDim:IsA("ImageLabel") then
		local d = DIM[name]
		if d ~= nil then
			TweenService:Create(backDim, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { ImageTransparency = 1 - d }):Play()
		end
	end
end)

ctx.on("Show", function()
	task.spawn(function()
		-- Studio's local match turns the server back into a lobby just before "Show"; give that a moment to arrive
		local t0 = os.clock()
		while (isMatch() or player:GetAttribute("InMatch") == true) and os.clock() - t0 < 2 do
			task.wait(0.05)
		end
		openMenu()
	end)
end)

-- The AAR in a match server: the Aar page turns the menu on; the mouse stays free while it is up.
ctx.on("Active", function(on)
	if not isMatch() then
		return
	end
	if on then
		RunService:BindToRenderStep("MenuMouse", Enum.RenderPriority.Camera.Value + 6, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
		loadingBack(false)
	else
		RunService:UnbindFromRenderStep("MenuMouse")
		UserInputService.MouseIconEnabled = false
	end
end)

-- A deploy put you in a body (a Studio local match, or this match server letting you in).
player:GetAttributeChangedSignal("InMatch"):Connect(function()
	if player:GetAttribute("InMatch") == true and not (isMatch() and ctx.active and ctx.current == "Aar") then
		task.spawn(takeBody)
	end
end)

-- Every spawn while the menu is not up hands the camera back to the normal follow camera, so a camera left in the
-- menu's Scriptable mode can never strand a player.
player.CharacterAdded:Connect(function(character)
	if ctx.active and not state.leaving and not isMatch() then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or (ctx.active and not state.leaving) then
		return
	end
	camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
end)

-- Start --------------------------------------------------------------------------------------------------------------
if isMatch() then
	-- A match server: no menu, straight into the body MenuServer gives you (Boot keeps the teleport screen up).
	ctx.setActive(false)
	ctx.showChrome(false)
	black()
	task.spawn(takeBody)
elseif player:GetAttribute("InMatch") == true then
	ctx.setActive(false)
	task.spawn(takeBody)
else
	task.spawn(openMenu)
end
