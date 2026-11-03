-- The way out, on each player's screen. When the pickup helicopter climbs away
-- (MatchServer rescue(), Remotes.Match "Rescue" with the UserIds aboard), the escape plays
-- on the live helicopter EvacClient flies (workspace.EvacHeliLive) for Rescue.EscapeTime:
-- from its open door looking down at the Beacon reaching up from the road, then wide from the
-- rooftops as it climbs away with the Beacon chasing below. It ends on black with one line
-- (StarterGui.Attire.Line): YOU ESCAPED, and the first time ("Unlocked") what that opened.
-- (StarterGui.Attire keeps only the cutscene layers: Fade, Bars and Line. The one-time
-- uniform pick was removed in the 3 Nov 2026 menu revamp; uniforms are picked in the menu now.)
-- After the escape the match ends (Events.MatchEnded, the after-action report) and the menu
-- comes back with Remotes.Menu "Show".
-- The menu (StarterGui.Menu, MenuClient) is a separate screen: it stays off for all of this
-- and only comes back with that "Show".
-- While any of it runs the player attribute Cutscene is set, and GunClient hides the gun.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local CFG = GameConfig.Rescue

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local EVAC = GameConfig.Breakout.Evac
local unlockedNow = false -- this escape opened the other modes

local running = nil -- the current run's token; a newer run or the menu ends the old one
local heli, dust, rotors, parts, offsets
local hidden = {} -- parts hidden for the last shot, restored after

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

local function getGui()
	return playerGui:FindFirstChild("Attire") or playerGui:WaitForChild("Attire", 5)
end

local function fadeTo(gui, alpha, time)
	local tween = TweenService:Create(gui.Fade, TweenInfo.new(time), { BackgroundTransparency = alpha })
	tween:Play()
	return tween
end

local function setHud(on)
	local hud = playerGui:FindFirstChild("HUD")
	if hud then
		hud.Enabled = on
	end
end

local function hideMenu()
	local menu = playerGui:FindFirstChild("Menu")
	if menu then
		menu.Enabled = false
	end
	RunService:UnbindFromRenderStep("MenuCamera")
end

local function bezier(a, b, c, t)
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

local function wrap(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- The helicopter ----------------------------------------------------------------------

local function buildHeli()
	local source = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("EvacHeli")
	heli = source:Clone()
	local root = heli.PrimaryPart
	local base = root.CFrame
	parts, offsets, rotors = {}, {}, {}
	for _, d in heli:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			offsets[d] = base:ToObjectSpace(d.CFrame)
			local spin = d:GetAttribute("Spin")
			if spin then
				rotors[d] = if spin == "Main" then { Axis = Vector3.yAxis, Rate = -15 } else { Axis = Vector3.xAxis, Rate = 34 }
			end
		end
	end
	heli.Parent = workspace

	-- Rotor wash: dust kicked up off the road once it's low.
	dust = Instance.new("Part")
	dust.Name = "RotorWash"
	dust.Anchored = true
	dust.CanCollide = false
	dust.CanQuery = false
	dust.CanTouch = false
	dust.Transparency = 1
	dust.Size = Vector3.new(1, 1, 1)
	local fx = ReplicatedStorage.Assets:FindFirstChild("Fx")
	local smoke = fx and fx:FindFirstChild("Smoke")
	local emitter = smoke and smoke:FindFirstChildOfClass("ParticleEmitter")
	emitter = if emitter then emitter:Clone() else Instance.new("ParticleEmitter")
	emitter.Name = "Wash"
	emitter.Enabled = true
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(88, 88)
	emitter.Speed = NumberRange.new(22, 34)
	emitter.Drag = 2.2
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.Lifetime = NumberRange.new(1.6, 2.6)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 12) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.62), NumberSequenceKeypoint.new(1, 1) })
	emitter.Color = ColorSequence.new(Color3.fromRGB(120, 112, 98))
	emitter.LightInfluence = 1
	emitter.Parent = dust
	dust.Parent = heli

	local rotor = root:FindFirstChild("Rotor")
	if rotor then
		rotor.Volume = 0
		rotor:Play()
		TweenService:Create(rotor, TweenInfo.new(2), { Volume = 1 }):Play()
	end
end

local function clearHeli()
	if heli then
		heli:Destroy()
		heli = nil
	end
	dust = nil
end

local function placeHeli(rootCF, spinAngle, zonePos, aimAtZone)
	local cframes = table.create(#parts)
	for i, part in parts do
		local off = offsets[part]
		local rotor = rotors[part]
		if rotor then
			cframes[i] = rootCF * CFrame.new(off.Position) * CFrame.fromAxisAngle(rotor.Axis, spinAngle * rotor.Rate) * off.Rotation
		else
			cframes[i] = rootCF * off
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	local root = heli.PrimaryPart
	local search = root:FindFirstChild("Search")
	local tip = root:FindFirstChild("SearchEnd")
	if search and tip then
		local from = search.WorldPosition
		local dir
		if aimAtZone then
			dir = (zonePos - from).Unit
		else
			dir = rootCF:VectorToWorldSpace(Vector3.new(0, -0.62, -0.78).Unit)
		end
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
	if dust then
		local height = rootCF.Position.Y - zonePos.Y
		dust.CFrame = CFrame.new(rootCF.Position.X, zonePos.Y + 0.5, rootCF.Position.Z)
		dust.Wash.Rate = math.clamp((40 - height) / 22, 0, 1) * 60
	end
end

local function setCharactersHidden(on)
	if on then
		for _, p in Players:GetPlayers() do
			local character = p.Character
			if character then
				for _, d in character:GetDescendants() do
					if d:IsA("BasePart") or d:IsA("Decal") then
						d.LocalTransparencyModifier = 1
						hidden[d] = true
					end
				end
			end
		end
	else
		for d in hidden do
			if d.Parent then
				d.LocalTransparencyModifier = 0
			end
		end
		table.clear(hidden)
	end
end

-- Your own body shows in the shots (the first-person camera had hidden it).
local function showOwnBody()
	local character = player.Character
	if character then
		for _, d in character:GetDescendants() do
			if (d:IsA("BasePart") or d:IsA("Decal")) and not hidden[d] then
				d.LocalTransparencyModifier = 0
			end
		end
	end
end

-- The cutscene ------------------------------------------------------------------------

local function playRescue(ids)
	local token = {}
	running = token
	local gui = getGui()
	local zone = zonePos()
	if not gui or not zone then
		return
	end
	local escaped = table.find(ids or {}, player.UserId) ~= nil
	player:SetAttribute("Cutscene", true)
	hideMenu()
	gui.Bars.Visible = true
	setHud(false)
	gui.Fade.BackgroundTransparency = 1

	local total = CFG.EscapeTime
	local shotB = total * 0.45
	local to = EVAC.To.Unit
	local side = to:Cross(Vector3.yAxis)
	local camCF, start = nil, os.clock()
	local cut = false

	RunService:BindToRenderStep("RescueCamera", Enum.RenderPriority.Camera.Value + 10, function(dt)
		if running ~= token then
			return
		end
		local t = os.clock() - start
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		local heli = workspace:FindFirstChild("EvacHeliLive")
		local beacon = workspace:FindFirstChild("Beacon")
		local head = beacon and beacon:FindFirstChild("Head")
		if not heli or not heli.PrimaryPart then
			return
		end
		local pose = heli.PrimaryPart.CFrame
		local target = if head then head.Position else zone
		local want
		if t < shotB then
			-- From the open door, looking down: the Beacon has reached the road and reaches up,
			-- lamps blazing into the cabin.
			local outward = -pose.RightVector
			local eye = pose:PointToWorldSpace(EVAC.Door + Vector3.new(0.6, 4, 1.5)) + outward * 0.5
			want = CFrame.lookAt(eye, target + Vector3.new(0, 4, 0))
			camera.FieldOfView = 60
		else
			-- Wide, from the rooftops: it climbs away over the town while the Beacon chases below
			-- and falls behind.
			if not cut then
				cut = true
				camCF = nil
				setCharactersHidden(true)
			end
			local eye = zone + to * 70 + side * 75 + Vector3.new(0, 32, 0)
			want = CFrame.lookAt(eye, heli.PrimaryPart.Position:Lerp(target, 0.35))
			camera.FieldOfView = 55
		end
		camCF = if camCF then camCF:Lerp(want, 1 - math.exp(-6 * dt)) else want
		camera.CFrame = camCF
	end)

	-- Out to black, with one line: you made it (and, the first time, what it unlocked).
	task.delay(total - 1.2, function()
		if running ~= token then
			return
		end
		fadeTo(gui, 0, 0.8)
		local line = gui:FindFirstChild("Line")
		if line then
			line.Text = if escaped then "YOU ESCAPED" else "YOU WERE LEFT BEHIND"
			line.Visible = true
			TweenService:Create(line, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
			if escaped and unlockedNow then
				task.delay(1.6, function()
					if running == token then
						line.Text = "NIGHTMARE AND ENDLESS UNLOCKED"
					end
				end)
			end
		end
	end)
end

local function finish()
	running = nil
	RunService:UnbindFromRenderStep("RescueCamera")
	clearHeli()
	setCharactersHidden(false)
	local gui = playerGui:FindFirstChild("Attire")
	if gui then
		gui.Bars.Visible = false
		gui.Fade.BackgroundTransparency = 1
		local line = gui:FindFirstChild("Line")
		if line then
			line.Visible = false
			line.TextTransparency = 1
		end
	end
	player:SetAttribute("Cutscene", nil)
end

Remotes.Match.OnClientEvent:Connect(function(cue, value)
	if cue == "Unlocked" then
		unlockedNow = true
	elseif cue == "Rescue" then
		task.spawn(playRescue, value)
		task.delay(CFG.EscapeTime + 8, function()
			unlockedNow = false
		end)
	end
end)

-- The menu takes over from here (its own fade covers the cut).
Remotes.Menu.OnClientEvent:Connect(function(action)
	if action == "Show" then
		finish()
	end
end)
