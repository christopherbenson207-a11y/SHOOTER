-- Health on screen and in the ears. PlayerHealth (server) owns the numbers; this draws them:
--   * The readout, bottom left: a heart monitor trace over a thin bar, labelled FINE /
--     CAUTION / DANGER (Resident Evil's ECG). The beat quickens as health drops.
--   * Taking a hit: claw streaks from the side it came from and the screen edges closing
--     in (GunClient snaps the camera). At low health the edges stay, the colour drains and
--     the heartbeat plays.
--   * Down: eyes near the floor, the bar becomes the bleed-out, the trace slows and skips.
--     Hold the interact key to spend a self-revive; teammates get a Revive prompt on you.
--   * The devour: every claw lands on screen while the view sinks and goes black.
--   * The death cam: dying with the police dog at your side, the black lifts for a few
--     seconds over your body from outside while the dog sits beside it and howls.
-- Mob attack poses (MobPose) start here too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Platform = require(Shared:WaitForChild("Platform"))
local Controls = require(Shared:WaitForChild("Controls"))
local SoundKit = require(Shared:WaitForChild("SoundKit"))
local Classes = require(Shared:WaitForChild("Classes"))
local MobPose = require(script.Parent:WaitForChild("MobPose"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local CFG = GameConfig.Player
local DOWN = CFG.Downed
local DEVOUR = CFG.Devour
local DCAM = CFG.DeathCam

local player = Players.LocalPlayer
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")
local healthFrame = hud:WaitForChild("Health")
local stateLabel = healthFrame:WaitForChild("State")
local ecg = healthFrame:WaitForChild("Ecg")
local ecgHead = ecg:WaitForChild("Head")
local bar = healthFrame:WaitForChild("Bar")
local barFill = bar:WaitForChild("Fill")
local barLag = bar:WaitForChild("Lag")
local barTrauma = bar:WaitForChild("Trauma")
local reviveRow = healthFrame:WaitForChild("SelfRevive")
local reviveKey = reviveRow:WaitForChild("Key")
local reviveFill = reviveRow:WaitForChild("Hold"):WaitForChild("Fill")
local hurtFrame = hud:WaitForChild("Hurt")
local clawFrame = hud:WaitForChild("Claw")
local blackout = hud:WaitForChild("Blackout")
local grade = Lighting:WaitForChild("HurtColor")

-- Roblox's own health bar would double up with the readout.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local WHITE = Color3.fromRGB(240, 238, 232)
local AMBER = Color3.fromRGB(255, 176, 60)
local DANGER = Color3.fromRGB(255, 120, 80)
local DOWN_COLOR = Color3.fromRGB(190, 82, 60)

-- Readout states: label, colour, beats per minute and trace height.
local LEVELS = {
	Fine = { Text = "FINE", Color = WHITE, Bpm = 72, Amp = 1 },
	Caution = { Text = "CAUTION", Color = AMBER, Bpm = 96, Amp = 0.95 },
	Danger = { Text = "DANGER", Color = DANGER, Bpm = 128, Amp = 0.85 },
	Down = { Text = "DOWN", Color = DOWN_COLOR, Bpm = 46, Amp = 0.55 },
	Gone = { Text = "", Color = DOWN_COLOR, Bpm = 30, Amp = 0 },
}
-- Being picked up: the beat comes back.
local REVIVING = { Bpm = 104, Amp = 0.9 }
local CAUTION_AT = 0.66
-- The trace crosses the monitor in SWEEP seconds; GAP segments ahead of the pen are blank.
local SWEEP = 2.6
local GAP = 4
-- The bar's damage chunk waits, then drains (share of the bar per second).
local LAG_DELAY = 0.45
local LAG_SPEED = 0.6

local segments = {}
for _, child in ecg:GetChildren() do
	if string.match(child.Name, "^Seg") then
		table.insert(segments, child)
	end
end
table.sort(segments, function(a, b)
	return a.Name < b.Name
end)
local N = #segments
-- Trace points 1..N+1 (point k sits at (k - 1) / N across the monitor).
local samples = table.create(N + 1, 0)

local character: Model? = nil
local humanoid: Humanoid? = nil
local pen = 0
local phase = 0
local samplePhase = 0
local beatScale = 1
local bpm, amp = LEVELS.Fine.Bpm, 1
local penValue = 0
local flash = 0
local low = 0
local lag = 1
local lagHoldUntil = 0
local lastFrac = 1
local holdStart = nil
local devourStart = nil
local cameraDrop = 0
local jitterUntil = 0
local heartbeat: Sound? = nil
local heartbeatVolume = 0
local edges = 1
local deathCam = nil

local function smooth(current, target, rate, dt)
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flag(name)
	return character ~= nil and character:GetAttribute(name) == true
end

-- The trace ---------------------------------------------------------------------------

local function bump(x, at, width)
	local d = (x - at) / width
	return math.exp(-d * d * 0.5)
end

-- One heartbeat for x in [0, 1): the P wave, the QRS spike, the T wave.
local function wave(x)
	return 0.12 * bump(x, 0.12, 0.025)
		- 0.18 * bump(x, 0.215, 0.008)
		+ 1.0 * bump(x, 0.235, 0.01)
		- 0.32 * bump(x, 0.258, 0.01)
		+ 0.22 * bump(x, 0.45, 0.04)
end

-- The biggest swing between two phases, so the narrow spike never falls between samples.
local function sampleSpan(p0, p1)
	local best = 0
	for i = 0, 5 do
		local v = wave((p0 + (p1 - p0) * i / 5) % 1)
		if math.abs(v) > math.abs(best) then
			best = v
		end
	end
	return best
end

local function advanceTrace(dt, down)
	local oldPen, oldPhase = pen, phase
	pen += dt / SWEEP * N
	phase += dt * bpm / 60 * beatScale
	if math.floor(phase) > math.floor(oldPhase) then
		-- Down, the rhythm stumbles: every beat comes early or late.
		beatScale = if down then 0.55 + math.random() * 0.9 else 1
	end
	for b = math.floor(oldPen) + 1, math.floor(pen) do
		local f = (b - oldPen) / (pen - oldPen)
		local p = oldPhase + (phase - oldPhase) * f
		local v = sampleSpan(samplePhase, p) * amp + (math.random() - 0.5) * 0.04 * amp
		samplePhase = p
		local index = b % N
		samples[index + 1] = v
		if index == 0 then
			samples[N + 1] = v
		end
	end
	if pen >= N then
		pen -= N
	end
	penValue = wave(phase % 1) * amp
end

-- The segments only change when the pen moves on a segment, the colour changes or the monitor resizes.
local drawnPen, drawnColor, drawnSize = -1, nil, nil
local function drawTrace(color)
	local size = ecg.AbsoluteSize
	local w, h = size.X, size.Y
	local mid, scale = h * 0.5, h * 0.42
	local penIndex = math.floor(pen)
	ecgHead.Position = UDim2.fromOffset(pen / N * w, mid - penValue * scale)
	if penIndex == drawnPen and color == drawnColor and size == drawnSize then
		return
	end
	drawnPen, drawnColor, drawnSize = penIndex, color, size
	for i, seg in segments do
		if (i - 1 - penIndex) % N < GAP then
			seg.Visible = false
		else
			local x0, x1 = (i - 1) / N * w, i / N * w
			local y0, y1 = mid - samples[i] * scale, mid - samples[i + 1] * scale
			local dx, dy = x1 - x0, y1 - y0
			seg.Visible = true
			seg.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
			seg.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 1, 2)
			seg.Rotation = math.deg(math.atan2(dy, dx))
			seg.BackgroundColor3 = color
			-- Older trace fades out toward the pen.
			local age = ((penIndex - i) % N) / N
			seg.BackgroundTransparency = 0.05 + 0.8 * age ^ 1.4
		end
	end
	ecgHead.Position = UDim2.fromOffset(pen / N * w, mid - penValue * scale)
	ecgHead.BackgroundColor3 = color
end

-- Hits --------------------------------------------------------------------------------

local function showClaw(fromPos)
	local camera = workspace.CurrentCamera
	local side = 1
	if typeof(fromPos) == "Vector3" then
		side = if camera.CFrame:PointToObjectSpace(fromPos).X >= 0 then 1 else -1
	end
	clawFrame.Position = UDim2.fromScale(0.5 + side * (0.08 + math.random() * 0.1), 0.5 + (math.random() - 0.5) * 0.14)
	-- The streaks lean one way; a swipe from the left mirrors them.
	clawFrame.Rotation = (if side > 0 then 0 else 52) + (math.random() - 0.5) * 16
	clawFrame.GroupTransparency = 0.1
	TweenService:Create(clawFrame, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 }):Play()
end

Remotes:WaitForChild("PlayerHit").OnClientEvent:Connect(function(fromPos, _damage, downed, kind)
	-- A hard landing is no claw: just the edges closing in for a moment (GunClient thumps the view).
	if kind == "Fall" then
		flash = math.max(flash, 0.55)
		jitterUntil = os.clock() + 0.08
		return
	end
	flash = math.max(flash, if downed then 0.6 else 0.85)
	-- A round from a Lamplighter (WAR): the edges close in, no claw marks.
	if kind == "Bullet" then
		jitterUntil = os.clock() + 0.06
		return
	end
	showClaw(fromPos)
end)

-- During the devour every claw from the pile lands on screen.
Remotes:WaitForChild("MobAttack").OnClientEvent:Connect(function(model, phase)
	if phase ~= "Swing" or not flag("Devoured") or typeof(model) ~= "Instance" then
		return
	end
	if model:GetAttribute("DevourTarget") ~= player.UserId then
		return
	end
	local root = model.PrimaryPart
	flash = 0.9
	jitterUntil = os.clock() + 0.12
	showClaw(root and root.Position)
end)

-- Self-revive -------------------------------------------------------------------------

local function canSelfRevive()
	return flag("Downed") and not flag("Devoured") and (character:GetAttribute("SelfRevives") or 0) > 0
end

local function beginHold()
	if holdStart or not canSelfRevive() then
		return
	end
	holdStart = os.clock()
	Remotes.SelfRevive:FireServer("Start")
end

local function endHold()
	if holdStart then
		holdStart = nil
		Remotes.SelfRevive:FireServer("Stop")
	end
end

local function isReviveInput(input)
	-- The Revive keys from Shared.Controls (E / B by default). B shares with Crouch and E with Use by design: while
	-- downed they get you up.
	return Controls.Matches("Revive", input)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and isReviveInput(input) then
		beginHold()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if isReviveInput(input) then
		endHold()
	end
end)
-- Touch: press and hold the key itself.
reviveKey.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		beginHold()
	end
end)
reviveKey.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		endHold()
	end
end)

local function keyText()
	if Platform.IsGamepad() then
		return Controls.Glyph("Revive", "Pad")
	elseif Platform.IsTouch() then
		return "UP"
	end
	return Controls.Glyph("Revive", "Kb")
end

-- Heartbeat ---------------------------------------------------------------------------

local function setHeartbeat(volume, speed)
	if not heartbeat then
		local template = SoundKit.Pick("Player/Heartbeat")
		if not template then
			return
		end
		heartbeatVolume = template.Volume
		heartbeat = template:Clone()
		heartbeat.Looped = true
		heartbeat.Volume = 0
		heartbeat.Parent = SoundService
	end
	heartbeat.Volume = heartbeatVolume * volume
	heartbeat.PlaybackSpeed = speed
	if volume > 0.01 and not heartbeat.IsPlaying then
		heartbeat:Play()
	elseif volume <= 0.01 and heartbeat.IsPlaying then
		heartbeat:Stop()
	end
end

-- Per frame ---------------------------------------------------------------------------

local function currentLevel()
	if not humanoid or humanoid.Health <= 0 or flag("Devoured") then
		return LEVELS.Gone
	end
	if flag("Downed") then
		return LEVELS.Down
	end
	local frac = humanoid.Health / humanoid.MaxHealth
	if frac > CAUTION_AT then
		return LEVELS.Fine
	elseif frac > CFG.LowHealth then
		return LEVELS.Caution
	end
	return LEVELS.Danger
end

local function update(dt)
	if not character or not humanoid or not character.Parent then
		-- No body (sent back to the menu): nothing of the last life stays on screen.
		if low > 0 or flash > 0 then
			low, flash = 0, 0
			hurtFrame.GroupTransparency = 1
			grade.Saturation, grade.Contrast, grade.Brightness = 0, 0, 0
			setHeartbeat(0, 1)
		end
		return
	end
	dt = math.min(dt, 0.1)
	local now = os.clock()
	local level = currentLevel()
	local down = level == LEVELS.Down
	local devoured = flag("Devoured")
	local reviving = down and (flag("SelfReviving") or flag("BeingRevived"))

	-- Trace
	local target = if reviving then REVIVING else level
	bpm = smooth(bpm, target.Bpm, 2.5, dt)
	amp = smooth(amp, target.Amp, 3, dt)
	advanceTrace(dt, down and not reviving)
	drawTrace(level.Color)
	stateLabel.Text = level.Text
	stateLabel.TextColor3 = if level == LEVELS.Fine then Color3.fromRGB(176, 174, 170) else level.Color

	-- Bar: health standing, the bleed-out while down.
	local frac
	if down or devoured then
		local left = (character:GetAttribute("BleedOutAt") or 0) - workspace:GetServerTimeNow()
		frac = if devoured then 0 else math.clamp(left / DOWN.BleedOut, 0, 1)
		lag = frac
	else
		frac = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		if frac < lastFrac - 1e-3 then
			lagHoldUntil = now + LAG_DELAY
		end
		if frac >= lag then
			lag = frac
		elseif now >= lagHoldUntil then
			lag = math.max(frac, lag - LAG_SPEED * dt)
		end
	end
	lastFrac = frac
	barFill.Size = UDim2.fromScale(frac, 1)
	barFill.BackgroundColor3 = level.Color
	barLag.Size = UDim2.fromScale(lag, 1)
	-- Trauma: the end of the bar that won't regenerate until a bandage goes on.
	local trauma = if down or devoured then 0 else (character:GetAttribute("Trauma") or 0) / humanoid.MaxHealth
	barTrauma.Size = UDim2.fromScale(math.clamp(trauma, 0, 1), 1)

	-- Self-revive key
	local canRevive = canSelfRevive()
	reviveRow.Visible = canRevive
	if canRevive then
		reviveKey.Text = keyText()
		reviveKey.TextSize = if #reviveKey.Text > 1 then 10 else 14
		reviveFill.Size = UDim2.fromScale(if holdStart then math.clamp((now - holdStart) / (DOWN.SelfReviveTime * Classes.Perk(game:GetService("Players").LocalPlayer, "SelfReviveTime")), 0, 1) else 0, 1)
	elseif holdStart then
		holdStart = nil
	end

	-- Screen: hit flashes, low health closing in with the pulse, colour draining.
	local lowTarget = 0
	if devoured or down then
		lowTarget = 0.9
	elseif frac <= CFG.LowHealth then
		lowTarget = 0.35 + 0.65 * (1 - frac / CFG.LowHealth)
	end
	low = smooth(low, lowTarget, 4, dt)
	flash = math.max(0, flash - dt * 1.6)
	local pulse = bump(phase % 1, 0.24, 0.06) * 0.2 * low
	-- The edges go while the death cam runs; the colour stays drained.
	edges = smooth(edges, if deathCam then 0 else 1, 3, dt)
	hurtFrame.GroupTransparency = 1 - math.clamp(math.max(flash, low * 0.7 + pulse), 0, 1) * edges
	grade.Saturation = -0.8 * low
	grade.Contrast = 0.12 * low
	grade.Brightness = -0.05 * low
	setHeartbeat(if devoured then 0 else low, if down then 0.8 else 0.95 + 0.3 * low)

	-- Eyes near the floor while down; lower still and shaken while being eaten.
	local dropTarget = if devoured then DOWN.CameraDrop + 0.5 elseif down then DOWN.CameraDrop else 0
	cameraDrop = smooth(cameraDrop, dropTarget, 6, dt)
	local jitter = Vector3.zero
	if now < jitterUntil then
		jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.35
	end
	if humanoid.Health > 0 then
		-- EvadeDrop: crouched in a hiding spot or mid-roll (StarterPlayerScripts.Evade).
		local evadeDrop = humanoid:GetAttribute("EvadeDrop") or 0
		humanoid.CameraOffset = Vector3.new(0, -cameraDrop - evadeDrop, 0) + jitter
	end

	-- The devour sinks into black (the death cam owns the black while it runs).
	if devourStart and not deathCam then
		local k = math.clamp((now - devourStart) / DEVOUR.Time, 0, 1)
		blackout.BackgroundTransparency = 1 - math.clamp((k - 0.2) / 0.8, 0, 1) ^ 1.5
	end
end

RunService:BindToRenderStep("LastLightHealth", Enum.RenderPriority.Camera.Value - 1, update)

-- The death cam ------------------------------------------------------------------------
-- Dying with the police dog at your side (DogServer: the dog's Partner attribute is you):
-- instead of straight to black, a few seconds over your body from outside while the dog
-- sits beside it and howls (GameConfig.Player.DeathCam), then the black. After the devour
-- the screen is already black, so the shot opens with the black lifting. Not after the
-- Beacon takes you (Taken, Grabbed). The player carries DeathCam while the shot runs
-- (MatchHud holds YOU FELL back until it ends) and Cutscene (no touch HUD, gear or evade).

local function policeDog(): Model?
	local dogs = workspace:FindFirstChild("Dogs")
	local dog = dogs and dogs:FindFirstChild("PoliceDog")
	return if dog and dog:IsA("Model") and dog.PrimaryPart then dog else nil
end

-- What the shot is framed round: between the body and the dog (the body alone until the dog
-- gets there), and the line across the pair.
local function camFocus(cam): (Vector3, Vector3)
	local body = cam.Body.Position
	local root = cam.Dog.PrimaryPart
	if root and (root.Position - body).Magnitude < 12 then
		return (body + root.Position) / 2, flat(root.Position - body)
	end
	return body, Vector3.zero
end

-- The side of the pair the camera stands on: the clearer one (the longer line from the
-- focus to where it would stand), and the side it's on already unless that one is walled.
local function pickSide(cam, focus: Vector3, across: Vector3, prefer: Vector3?): Vector3
	local axis = if across.Magnitude > 0.3 then across.Unit else Vector3.xAxis
	local from = focus + Vector3.new(0, 1, 0)
	local best, bestScore = Vector3.xAxis, -1
	for _, sign in { 1, -1 } do
		local side = axis:Cross(Vector3.yAxis) * sign
		local want = focus + side * DCAM.Distance + Vector3.new(0, DCAM.Height, 0)
		local hit = workspace:Raycast(from, want - from, cam.Params)
		local score = math.min(if hit then hit.Distance else math.huge, DCAM.Distance)
		if prefer and side:Dot(prefer) > 0 then
			score += DCAM.Distance * 0.5
		end
		if score > bestScore then
			best, bestScore = side, score
		end
	end
	return best
end

-- Where the camera stands this frame: off to the side, creeping in over the shot, pulled in
-- to the first wall in the way.
local function camSpot(cam, focus: Vector3, now: number): Vector3
	local k = math.clamp((now - cam.Start) / DCAM.Time, 0, 1)
	local want = focus + cam.Side * (DCAM.Distance - DCAM.PushIn * k) + Vector3.new(0, DCAM.Height, 0)
	local from = focus + Vector3.new(0, 1, 0)
	local hit = workspace:Raycast(from, want - from, cam.Params)
	if hit then
		-- never closer than 1.5 studs, so a wall right by the body can't put the lens in it
		want = from + (want - from).Unit * math.max(hit.Distance - 0.6, 1.5)
	end
	return want
end

-- handBack: give the camera back to Roblox (not when someone else has it: MenuClient once
-- the body is gone, RescueClient in the rescue). Cut short, the screen goes black at once,
-- so whatever comes next (a respawn lifts the black) never cuts straight from the shot.
local function endDeathCam(handBack: boolean)
	local cam = deathCam
	if not cam then
		return
	end
	deathCam = nil
	RunService:UnbindFromRenderStep("LastLightDeathCam")
	player:SetAttribute("DeathCam", nil)
	if workspace:GetAttribute("WaveState") ~= "Rescue" then
		player:SetAttribute("Cutscene", nil)
	end
	blackout.BackgroundTransparency = 0
	if handBack then
		local camera = workspace.CurrentCamera
		camera.FieldOfView = cam.Fov
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function stepDeathCam(dt)
	local cam = deathCam
	if not cam then
		return
	end
	if not cam.Character.Parent or workspace:GetAttribute("WaveState") == "Rescue" then
		-- The body is gone (sent to the menu) or the rescue cutscene is on: theirs now.
		endDeathCam(false)
		return
	end
	dt = math.min(dt, 0.1)
	local now = os.clock()
	local t = now - cam.Start
	if t >= DCAM.Time + DCAM.Fade then
		endDeathCam(true)
		return
	end
	if t >= DCAM.Time and not cam.Fading then
		cam.Fading = true
		TweenService:Create(blackout, TweenInfo.new(DCAM.Fade), { BackgroundTransparency = 0 }):Play()
		player:SetAttribute("DeathCam", nil)
	end
	local focus, across = camFocus(cam)
	-- The side follows the dog in (it comes to the body from anywhere) and settles once it
	-- sits to howl, so it never ends up on the line between the camera and the body.
	if not cam.Settled and across.Magnitude > 0.3 then
		cam.Settled = cam.Dog:GetAttribute("Pose") == "Howl" or t > 1.5
		cam.Side = pickSide(cam, focus, across, cam.Side)
	end
	cam.Pos = smooth(cam.Pos, camSpot(cam, focus, now), DCAM.Follow, dt)
	cam.Look = smooth(cam.Look, focus + Vector3.new(0, 0.6, 0), DCAM.Follow * 2, dt)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	if (cam.Pos - cam.Look).Magnitude > 0.1 then
		camera.CFrame = CFrame.lookAt(cam.Pos, cam.Look)
	end
	-- First person hides your own body on your screen; this shot is of it.
	for _, part in cam.Parts do
		part.LocalTransparencyModifier = 0
	end
	camera.FieldOfView = smooth(camera.FieldOfView, DCAM.Fov, 3, dt)
end

-- Starts the shot over this body; false when it's not one for the dog (then the plain black).
local function startDeathCam(c: Model): boolean
	if c:GetAttribute("Taken") or c:GetAttribute("Grabbed") then
		return false
	end
	local dog = policeDog()
	if not dog or dog:GetAttribute("Partner") ~= player.UserId then
		return false
	end
	local root = c:FindFirstChild("HumanoidRootPart")
	local body = c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso") or root
	local head = c:FindFirstChild("Head")
	if not root or not body or not head then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { c, dog }
	for _, name in { "Dogs", "Zombies" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local camera = workspace.CurrentCamera
	local now = os.clock()
	-- The body's own line (hips to head) stands in for the pair until the dog is there.
	local along = flat((head :: BasePart).Position - (root :: BasePart).Position)
	if along.Magnitude < 0.3 then
		along = flat((root :: BasePart).CFrame.LookVector)
	end
	local cam = {
		Character = c,
		Body = body,
		Dog = dog,
		Params = params,
		Start = now,
		Side = Vector3.xAxis,
		Settled = false,
		Fading = false,
		Pos = (head :: BasePart).Position,
		Look = (body :: BasePart).Position,
		-- the live value can be a scope's (dying with the sniper up); the game's own is 70
		Fov = 70,
		Parts = {},
	}
	for _, d in c:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(cam.Parts, d)
		end
	end
	local focus, across = camFocus(cam)
	cam.Side = pickSide(cam, focus, if across.Magnitude > 0.3 then across else along, nil)
	if devourStart then
		-- Black already: open on the shot and lift it.
		cam.Pos = camSpot(cam, focus, now)
		cam.Look = focus + Vector3.new(0, 0.6, 0)
		camera.FieldOfView = DCAM.Fov
		TweenService:Create(blackout, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	end
	deathCam = cam
	player:SetAttribute("DeathCam", true)
	player:SetAttribute("Cutscene", true)
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep("LastLightDeathCam", Enum.RenderPriority.Camera.Value + 25, stepDeathCam)
	return true
end

-- Character lifecycle -------------------------------------------------------------------

-- The Revive prompt on your own body is for teammates; hide it here.
local function hideOwnPrompt(prompt)
	prompt.Enabled = false
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if prompt.Enabled then
			prompt.Enabled = false
		end
	end)
end

local function onCharacter(c)
	endDeathCam(true)
	character = c
	humanoid = c:WaitForChild("Humanoid")
	devourStart = nil
	holdStart = nil
	flash = 0
	edges = 1
	lag, lastFrac = 1, 1
	cameraDrop = 0
	clawFrame.GroupTransparency = 1
	healthFrame.Visible = true
	TweenService:Create(blackout, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()

	c:GetAttributeChangedSignal("Devoured"):Connect(function()
		if c == character and c:GetAttribute("Devoured") then
			devourStart = os.clock()
			endHold()
		end
	end)
	c:GetAttributeChangedSignal("Downed"):Connect(function()
		if c == character and not c:GetAttribute("Downed") then
			holdStart = nil
		end
	end)
	humanoid.Died:Once(function()
		if c ~= character then
			return
		end
		endHold()
		healthFrame.Visible = false
		if not startDeathCam(c) then
			TweenService:Create(blackout, TweenInfo.new(if devourStart then 0.3 else 1.2), { BackgroundTransparency = 0 }):Play()
		end
	end)

	local root = c:WaitForChild("HumanoidRootPart")
	local prompt = root:FindFirstChild("Revive")
	if prompt then
		hideOwnPrompt(prompt)
	end
	root.ChildAdded:Connect(function(child)
		if child:IsA("ProximityPrompt") and child.Name == "Revive" then
			hideOwnPrompt(child)
		end
	end)
end

MobPose.Start()
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end
