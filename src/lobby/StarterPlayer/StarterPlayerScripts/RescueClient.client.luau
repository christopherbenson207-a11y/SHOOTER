-- The way out, on each player's screen. When the pickup helicopter climbs away
-- (MatchServer rescue(), Remotes.Match "Rescue" with the UserIds aboard), the escape plays
-- on the live helicopter EvacClient flies (workspace.EvacHeliLive) for Rescue.EscapeTime:
-- from its open door looking down at the Beacon reaching up from the road, then wide from the
-- rooftops as it climbs away with the Beacon chasing below. It ends on black with one line
-- (StarterGui.Attire.Line): YOU ESCAPED, and the first time ("Unlocked") what that opened.
-- Then (Remotes.Match "Attire") the camera takes in
-- the uniform lineup (a local copy of ReplicatedStorage.Assets.AttireLineup, on a dark stage
-- off the map; it only exists while the pick is open) under StarterGui.Attire's two lines, "YOU ARE A
-- SOLDIER NOW." / "PICK YOUR ATTIRE.": tap or click a uniform and it lights up amber (a
-- gamepad steps through them with the D-pad or shoulders), WEAR saves it (Remotes.Attire).
-- The pick is a one-time screen: the server only sends "Attire" to players with no saved
-- uniform. The match sends everyone back to the menu after that (Remotes.Menu "Show").
-- The menu (StarterGui.Menu, MenuClient) is a separate screen: it stays off for all of this
-- and only comes back with that "Show".
-- While any of it runs the player attribute Cutscene is set, and GunClient hides the gun.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local CFG = GameConfig.Rescue
local ACCENT = GameConfig.Menu.Accent
local HOVER = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LINEUP = Vector3.new(0, 3.2, -6000) -- where AttireLineup stands (on its own Stage), far off the map

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local EVAC = GameConfig.Breakout.Evac
local unlockedNow = false -- this escape opened the other modes

local running = nil -- the current run's token; a newer run or the menu ends the old one
local heli, dust, rotors, parts, offsets
local hidden = {} -- parts hidden for the last shot, restored after
local lampBase = {} -- lineup lamp brightness before the attire screen
local swatHidden = {}

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

-- The uniform pick --------------------------------------------------------------------

local function hover(button, on)
	local pad = button:FindFirstChildOfClass("UIPadding")
	local base = button:GetAttribute("BaseColor")
	if not base then
		base = button.TextColor3
		button:SetAttribute("BaseColor", base)
	end
	TweenService:Create(button, HOVER, { TextColor3 = if on then ACCENT else base }):Play()
	if pad then
		TweenService:Create(pad, HOVER, { PaddingLeft = UDim.new(if on then 0.03 else 0, 0) }):Play()
	end
	for _, name in { "Bar", "Glow" } do
		local f = button:FindFirstChild(name)
		if f then
			TweenService:Create(f, HOVER, { BackgroundTransparency = if on then 0 else 1 }):Play()
		end
	end
end

local wiredGui = nil
local selected = GameConfig.Attire[1].Name
local worn = false
local picking = false
local pickMark, hoverMark = nil, nil
local lineup = nil -- this player's copy of the uniform lineup while the pick is open
local moved = {} -- lineup pieces slid over to close the hidden SWAT rig's gap -> old pivot

local function rigFor(name)
	for _, attire in GameConfig.Attire do
		if attire.Name == name then
			local rigs = lineup
			return rigs and rigs:FindFirstChild(attire.Rig), attire.Rig
		end
	end
end

local function lightLineup(name)
	local rigs = lineup
	local lamps = rigs and rigs:FindFirstChild("Lights")
	if not lamps then
		return
	end
	local _, rigName = rigFor(name)
	for _, lamp in lamps:GetChildren() do
		local light = lamp:FindFirstChildWhichIsA("Light")
		if light then
			if lampBase[light] == nil then
				lampBase[light] = light.Brightness
			end
			local on = name and lamp.Name == (rigName or "") .. "Lamp"
			TweenService:Create(light, TweenInfo.new(0.35), { Brightness = if on then lampBase[light] * 1.8 else lampBase[light] * 0.75 }):Play()
		end
	end
end

local function select(name)
	if worn or not name then
		return
	end
	selected = name
	if pickMark then
		pickMark.Adornee = rigFor(name)
	end
	lightLineup(name)
end

local function step(dir)
	local list = GameConfig.Attire
	for i, attire in list do
		if attire.Name == selected then
			select(list[(i - 1 + dir) % #list + 1].Name)
			return
		end
	end
end

-- The uniform under a tap or the cursor: the nearest rig across, between its head and feet.
local function rigAt(pos)
	local camera = workspace.CurrentCamera
	local best, bestDx
	for _, attire in GameConfig.Attire do
		local rig = rigFor(attire.Name)
		if rig then
			local at = rig:GetPivot().Position
			local head = camera:WorldToViewportPoint(at + Vector3.new(0, 3, 0))
			local feet = camera:WorldToViewportPoint(at - Vector3.new(0, 3.2, 0))
			local side = camera:WorldToViewportPoint(at + camera.CFrame.RightVector * 2.6)
			local dx = math.abs(pos.X - head.X)
			if pos.Y > head.Y - 30 and pos.Y < feet.Y + 10 and dx < math.abs(side.X - head.X) and (not bestDx or dx < bestDx) then
				best, bestDx = attire.Name, dx
			end
		end
	end
	return best
end

-- The SWAT rig (the uniform you start in) is hidden here; the ones after it slide over.
local function tidyLineup(on)
	local rigs = lineup
	local swat = rigs and rigs:FindFirstChild("SWATSoldier")
	if on and swat then
		local gapX = swat:GetPivot().X
		for _, d in swat:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = 1
				swatHidden[d] = true
			end
		end
		local lamps = rigs:FindFirstChild("Lights")
		for _, attire in GameConfig.Attire do
			local rig = rigFor(attire.Name)
			if rig and rig:GetPivot().X > gapX + 1 and not moved[rig] then
				moved[rig] = rig:GetPivot()
				rig:PivotTo(rig:GetPivot() - Vector3.new(6, 0, 0))
				local lamp = lamps and lamps:FindFirstChild(attire.Rig .. "Lamp")
				if lamp and not moved[lamp] then
					moved[lamp] = lamp.CFrame
					lamp.CFrame -= Vector3.new(6, 0, 0)
				end
			end
		end
	elseif not on then
		for d in swatHidden do
			if d.Parent then
				d.LocalTransparencyModifier = 0
			end
		end
		table.clear(swatHidden)
		for inst, cf in moved do
			if inst.Parent then
				inst:PivotTo(cf)
			end
		end
		table.clear(moved)
	end
end

local function newMark(name, fill, outline)
	local h = Instance.new("Highlight")
	h.Name = name
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.FillColor = ACCENT
	h.OutlineColor = if name == "AttirePick" then ACCENT else Color3.new(1, 1, 1)
	h.FillTransparency = fill
	h.OutlineTransparency = outline
	h.Parent = workspace.CurrentCamera
	return h
end

local function wireGui(gui)
	if wiredGui == gui then
		return
	end
	wiredGui = gui
	local wear = gui.Pick.Wear
	wear.MouseEnter:Connect(function()
		hover(wear, true)
	end)
	wear.MouseLeave:Connect(function()
		if not worn then
			hover(wear, false)
		end
	end)
	wear.SelectionGained:Connect(function()
		hover(wear, true)
	end)
	wear.Activated:Connect(function()
		if worn or workspace:GetAttribute("WaveState") ~= "Attire" then
			return
		end
		worn = true
		Remotes.Attire:FireServer(selected)
		hover(wear, true)
		if hoverMark then
			hoverMark.Adornee = nil
		end
		GuiService.SelectedObject = nil
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not picking then
		return
	end
	local kind = input.UserInputType
	if (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and not processed then
		select(rigAt(input.Position))
	elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.ButtonL1 then
		step(-1)
	elseif input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.ButtonR1 then
		step(1)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if picking and hoverMark and not worn and input.UserInputType == Enum.UserInputType.MouseMovement then
		local name = rigAt(input.Position)
		hoverMark.Adornee = if name and name ~= selected then rigFor(name) else nil
	end
end)

local function openAttire()
	local token = {}
	running = token
	local gui = getGui()
	if not gui then
		return
	end
	player:SetAttribute("Cutscene", true)
	hideMenu()
	RunService:UnbindFromRenderStep("RescueCamera")
	gui.Fade.BackgroundTransparency = 0
	clearHeli()
	setCharactersHidden(false)
	setHud(false)
	if running ~= token then
		return
	end
	if lineup then
		lineup:Destroy()
	end
	lineup = ReplicatedStorage.Assets.AttireLineup:Clone()
	lineup.Parent = workspace

	worn = false
	wireGui(gui)
	gui.Bars.Visible = false
	gui.Pick.Visible = true
	hover(gui.Pick.Wear, false)
	tidyLineup(true)
	pickMark = pickMark or newMark("AttirePick", 0.82, 0)
	hoverMark = hoverMark or newMark("AttireHover", 1, 0.55)
	hoverMark.Adornee = nil
	select(player:GetAttribute("Attire") or GameConfig.Attire[1].Name)
	picking = true
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = gui.Pick.Wear
	end

	-- The whole lineup in one shot, centred on the uniforms you can pick.
	local sum, n = Vector3.zero, 0
	for _, attire in GameConfig.Attire do
		local rig = rigFor(attire.Name)
		if rig then
			sum += rig:GetPivot().Position
			n += 1
		end
	end
	local center = if n > 0 then sum / n else LINEUP
	local camCF = nil
	RunService:BindToRenderStep("AttireCamera", Enum.RenderPriority.Camera.Value + 10, function(dt)
		if running ~= token then
			return
		end
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 50
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		setHud(false)
		local t = os.clock()
		local drift = Vector3.new(math.sin(t * 0.3) * 0.3, math.sin(t * 0.45) * 0.15, 0)
		local want = CFrame.lookAt(center + Vector3.new(0, 1.6, -15.5) + drift, center + Vector3.new(0, 0.1, 0))
		camCF = if camCF then camCF:Lerp(want, 1 - math.exp(-6 * math.min(dt, 0.1))) else want
		camera.CFrame = camCF
		if pickMark then
			pickMark.FillTransparency = 0.78 + 0.1 * math.sin(t * 3)
		end
	end)
	fadeTo(gui, 1, 0.8)
end

local function finish()
	running = nil
	picking = false
	RunService:UnbindFromRenderStep("RescueCamera")
	RunService:UnbindFromRenderStep("AttireCamera")
	clearHeli()
	setCharactersHidden(false)
	tidyLineup(false)
	if lineup then
		lineup:Destroy()
		lineup = nil
	end
	for _, mark in { pickMark, hoverMark } do
		if mark then
			mark:Destroy()
		end
	end
	pickMark, hoverMark = nil, nil
	for light, b in lampBase do
		light.Brightness = b
	end
	table.clear(lampBase)
	local gui = playerGui:FindFirstChild("Attire")
	if gui then
		gui.Bars.Visible = false
		gui.Pick.Visible = false
		gui.Fade.BackgroundTransparency = 1
		local line = gui:FindFirstChild("Line")
		if line then
			line.Visible = false
			line.TextTransparency = 1
		end
	end
	GuiService.SelectedObject = nil
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
	elseif cue == "Attire" then
		local gui = playerGui:FindFirstChild("Attire")
		local line = gui and gui:FindFirstChild("Line")
		if line then
			line.Visible = false
			line.TextTransparency = 1
		end
		task.spawn(openAttire)
	end
end)

-- The menu takes over from here (its own fade covers the cut).
Remotes.Menu.OnClientEvent:Connect(function(action)
	if action == "Show" then
		finish()
	end
end)
