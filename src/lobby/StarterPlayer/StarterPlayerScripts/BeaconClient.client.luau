-- The Beacon on this client (BeaconServer runs it):
--   Walks its bones (Shared.BeaconRig), slumping while its lamps cool and leaning in when it
--   runs at someone.
--   The Seen meter (HUD.Detect, top centre) shows how close you are to being seen: faint
--   while it hunts, filling amber to red while a lamp is on you. The screen edge
--   (HUD.BeaconWarn) burns red as it fills.
--   Once it has seen you (BeaconCaughtAt on you), the screen half darkens (HUD.Blackout) as it
--   comes for you; when it grabs you (character attribute Grabbed, Beacon GrabAt) the camera
--   looks up at its lamps as it lifts you, and the dark closes at the end. In nights you live
--   through it (dropped in the yard): the dark lifts again.
--   The lamps: BeaconServer moves each lamp's aim point (LensLTip / LensRTip); this draws a
--   bright core and a soft halo from the lens to it, smoothed, and a spotlight pool on the
--   ground as wide as what the lamp can see (GameConfig.Beacon.BeamWidth). Walls and roofs
--   stop the light. Lens attributes LampOn, LampColor, LampPower.
--   While it vents, its lenses glow with an outline you can see through walls: that's the
--   moment to shoot them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BeaconRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BeaconRig"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local CFG = GameConfig.Beacon
local CAUGHT_TIME = CFG.Caught.Time
local GRAB_TIME = CFG.Caught.Grab

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local beacon = workspace:WaitForChild("Beacon")
local rig = BeaconRig.new(beacon)

local AMBER = Color3.fromRGB(255, 176, 60)
local RED = Color3.fromRGB(230, 50, 40)
local WHITE = Color3.fromRGB(240, 238, 232)

local wasCaught = false
local shown = 0 -- the meter as drawn, easing toward the real value
local heat = 0
local alpha = 1 -- the meter's group transparency

-- Outlines on the lenses while it vents.
local marks = {}
for _, name in { "LensL", "LensR" } do
	local lens = beacon:WaitForChild(name)
	local h = Instance.new("Highlight")
	h.Name = "ShootMark"
	h.Adornee = lens
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.FillColor = AMBER
	h.OutlineColor = AMBER
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.Enabled = false
	h.Parent = lens
	marks[lens] = h
end

-- The lamps ---------------------------------------------------------------------------------

local POOL_HEIGHT = 14

local function newBeam(a0, a1, w0, w1, t0, t1, brightness)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = w0
	beam.Width1 = w1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Brightness = brightness
	beam.Segments = 1
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, t0),
		NumberSequenceKeypoint.new(0.6, t0 + (t1 - t0) * 0.7),
		NumberSequenceKeypoint.new(1, t1),
	})
	beam.Enabled = false
	beam.Parent = workspace.Terrain
	return beam
end

local lamps = {}
for _, name in { "LensL", "LensR" } do
	local lens = beacon:WaitForChild(name)
	local tip = beacon:WaitForChild(name .. "Tip")
	local from = Instance.new("Attachment")
	from.Name = name .. "LampFrom"
	from.Parent = workspace.Terrain
	local to = Instance.new("Attachment")
	to.Name = name .. "LampTo"
	to.Parent = workspace.Terrain
	local above = Instance.new("Attachment")
	above.Name = name .. "LampPool"
	above.Parent = workspace.Terrain
	local pool = Instance.new("SpotLight")
	pool.Face = Enum.NormalId.Front
	pool.Angle = math.deg(2 * math.atan(CFG.BeamWidth / POOL_HEIGHT))
	pool.Range = POOL_HEIGHT + 8
	pool.Brightness = 6
	pool.Shadows = true
	pool.Enabled = false
	pool.Parent = above
	lamps[name] = {
		Lens = lens,
		Tip = tip,
		From = from,
		To = to,
		Above = above,
		Pool = pool,
		Core = newBeam(from, to, 0.7, CFG.BeamWidth * 0.6, 0.15, 0.8, 2.6),
		Halo = newBeam(from, to, 2.4, CFG.BeamWidth * 2 + 2, 0.72, 0.93, 1.6),
		Point = nil,
	}
end

local function stepLamps(dt)
	local ease = 1 - math.exp(-dt * 14)
	for _, lamp in lamps do
		local lens = lamp.Lens
		local on = lens:GetAttribute("LampOn") == true and lens.Parent ~= nil
		lamp.Core.Enabled = on
		lamp.Halo.Enabled = on
		lamp.Pool.Enabled = on
		if on then
			local want = lamp.Tip.Position - Vector3.new(0, 1.5, 0)
			lamp.Point = if lamp.Point then lamp.Point:Lerp(want, ease) else want
			lamp.From.WorldPosition = lens.Position
			lamp.To.WorldPosition = lamp.Point
			lamp.Above.WorldCFrame = CFrame.new(lamp.Point + Vector3.new(0, POOL_HEIGHT, 0)) * CFrame.Angles(-math.pi / 2, 0, 0)
			local color = lens:GetAttribute("LampColor") or WHITE
			local power = lens:GetAttribute("LampPower") or 1
			lamp.Core.Color = ColorSequence.new(color)
			lamp.Halo.Color = ColorSequence.new(color)
			lamp.Core.Brightness = 2.6 * power
			lamp.Halo.Brightness = 1.6 * power
			lamp.Pool.Color = color
			lamp.Pool.Brightness = 6 * power
		else
			lamp.Point = nil
		end
	end
end

-- Grabbed: looking up at its lamps as it lifts you ------------------------------------------

local grabbedCam = false
RunService:BindToRenderStep("BeaconGrab", Enum.RenderPriority.Camera.Value + 20, function()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local grabbed = character and character:GetAttribute("Grabbed") and head
	local camera = workspace.CurrentCamera
	if grabbed then
		grabbedCam = true
		player:SetAttribute("Cutscene", true)
		camera.CameraType = Enum.CameraType.Scriptable
		local t = os.clock()
		local shake = Vector3.new(math.noise(t * 9, 1), math.noise(t * 9, 2), 0) * 0.35
		local look = beacon.Head.Position - Vector3.new(0, 2, 0)
		camera.CFrame = CFrame.lookAt(head.Position + shake, look)
		camera.FieldOfView = 62
	elseif grabbedCam then
		grabbedCam = false
		player:SetAttribute("Cutscene", nil)
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
	end
end)

local function hudPart(name)
	local hud = playerGui:FindFirstChild("HUD")
	return hud and hud:FindFirstChild(name)
end

RunService.RenderStepped:Connect(function(dt)
	local state = beacon:GetAttribute("State")
	local awake = state == "Hunt" or state == "Vent" or state == "Chase"
	-- Asleep it can still be walking (BeaconServer's far-off roam before the first lull).
	if awake or beacon:GetAttribute("Moving") then
		-- Pose attributes from BeaconServer: GrabAt (lifting someone it caught), Reach (at the
		-- helicopter), Smash (into a building), Run (to the landing zone, a chase's stride).
		local grabAt = beacon:GetAttribute("GrabAt")
		local grabK = if grabAt then (workspace:GetServerTimeNow() - grabAt) / GRAB_TIME else nil
		local mode = if grabK then "Grab"
			elseif beacon:GetAttribute("Reach") then "Reach"
			elseif beacon:GetAttribute("Smash") then "Smash"
			elseif beacon:GetAttribute("Run") then "Chase"
			else state
		rig:Step(dt, beacon:GetAttribute("Moving") == true, mode, grabK)
	end
	stepLamps(dt)

	-- Shoot marks: pulsing while it vents, on the lenses still lit.
	local now = os.clock()
	for lens, h in marks do
		local on = state == "Vent" and lens.Material ~= Enum.Material.Glass
		h.Enabled = on
		if on then
			local pulse = 0.5 + 0.5 * math.sin(now * 6)
			h.OutlineTransparency = 0.1 * pulse
			h.FillTransparency = 0.45 + 0.35 * pulse
		end
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local inMatch = player:GetAttribute("InMatch") and humanoid and humanoid.Health > 0
	local value = player:GetAttribute("BeaconSeen") or 0
	local caughtAt = player:GetAttribute("BeaconCaughtAt")
	if caughtAt then
		value = 1
	end
	shown += (value - shown) * math.min(1, dt * 12)

	-- The meter.
	local detect = hudPart("Detect")
	if detect then
		local want = if not (awake and inMatch) then 1 elseif shown > 0.01 then 0 else 0.55
		alpha += (want - alpha) * math.min(1, dt * 6)
		detect.Visible = alpha < 0.99
		detect.GroupTransparency = alpha
		local fill = detect.Track.Fill
		fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
		local color = AMBER:Lerp(RED, math.clamp((shown - 0.35) / 0.5, 0, 1))
		fill.BackgroundColor3 = color
		local eye = detect.Eye
		local stroke = eye:FindFirstChildOfClass("UIStroke")
		local open = math.clamp(shown * 1.6, 0, 1)
		if stroke then
			stroke.Color = WHITE:Lerp(color, open)
		end
		eye.Pupil.BackgroundColor3 = WHITE:Lerp(color, open)
		eye.Pupil.Size = UDim2.fromOffset(6 + 4 * open, 6 + 4 * open)
		-- Close to seen, the meter shivers.
		local shiver = if shown > 0.75 then (shown - 0.75) * 8 else 0
		-- Its height is the layout's (under the HUD ring; HudScale on phones).
		local y = detect.Position.Y
		detect.Position = UDim2.new(0.5, math.sin(now * 55) * shiver, y.Scale, y.Offset)
	end

	-- The screen edge.
	local edge = math.clamp((shown - 0.3) / 0.6, 0, 1)
	heat += (edge - heat) * math.min(1, dt * 6)
	local warn = hudPart("BeaconWarn")
	local warnStroke = warn and warn:FindFirstChildOfClass("UIStroke")
	if warnStroke then
		local flicker = if shown > 0.8 then 0.15 * math.sin(now * 30) else 0
		warnStroke.Transparency = 1 - heat * (0.75 + flicker)
	end

	-- Seen: the dark creeps in while it comes for you, and closes once it has you up at its
	-- lamps.
	local blackout = hudPart("Blackout")
	if caughtAt and blackout and inMatch then
		local left = caughtAt - workspace:GetServerTimeNow()
		local k = 0.45 * (1 - math.clamp(left / CAUGHT_TIME, 0, 1))
		local grabAt = character:GetAttribute("Grabbed") and beacon:GetAttribute("GrabAt")
		if grabAt then
			local g = (workspace:GetServerTimeNow() - grabAt) / GRAB_TIME
			k = 0.45 * math.clamp(1 - g / 0.25, 0, 1) + math.clamp((g - 0.7) / 0.3, 0, 1)
		end
		blackout.BackgroundTransparency = 1 - math.clamp(k, 0, 1) ^ 1.4
		wasCaught = true
	elseif wasCaught and blackout and inMatch then
		-- Nights: thrown in the yard alive; the dark lifts.
		blackout.BackgroundTransparency = math.min(1, blackout.BackgroundTransparency + dt * 0.9)
		if blackout.BackgroundTransparency >= 1 then
			wasCaught = false
		end
	else
		wasCaught = false
	end
end)
