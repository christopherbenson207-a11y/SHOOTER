-- GearClient (MATCH, menu revamp 3 Nov 2026; CONTRACTS sections 2, 5; MENU-PLAN 3.13, 4.6, 9.5, 9.10).
-- Keys: G lethal, Q tactical (T also works), X field item (X again detonates a placed Breaching Charge); gamepad RB,
-- LB, DPad-right; touch: the Lethal, Tactical and Field buttons in StarterGui.TouchControls. The client draws a throw
-- at once along Shared.Gear.Simulate and tells GearServer ("Throw" / "Field" with Origin, Direction, Id); the server
-- checks everything and runs the real arc. Fx from the server draws other players' throws (the thrower's own Id is
-- skipped), blasts, the flashbang flash, the Extinguisher spray and the Stim speed.
-- Throwing (4 Nov 2026): G / Q put the item in your hand (the gun goes down); hold right mouse to wind up and see the
-- dotted arc and a disc as wide as its blast; let go or left click to throw. G again puts it away. See "Using gear".
-- HUD: StarterGui.HUD.Gear.<Lethal|Tactical|Field> (authored slot plates; images come from Shared.UiArt keys
-- Hud/<Slot>Slot, Gear/<Key> and Hud/Cooldown, looked up at runtime so late uploads still show), with the count, the
-- key hint and the field cooldown veil (FieldReadyAt). The Gear row sits just right of the Hotbar.

local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gear = require(Shared:WaitForChild("Gear"))
local Controls = require(Shared:WaitForChild("Controls"))
local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gear")
local GearAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Gear")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SLOTS = { "Lethal", "Tactical", "Field" }

-- Art -------------------------------------------------------------------------------------------------------------

local uiArt = nil
local function art(key)
	if uiArt == nil then -- (see setArt below for sprite-sheet rects)
		local mod = Shared:FindFirstChild("UiArt")
		local ok, m = pcall(require, mod)
		uiArt = ok and type(m) == "table" and m or false
	end
	if not uiArt then
		return ""
	end
	local v = uiArt[key]
	if type(uiArt.Get) == "function" and v == nil then
		local ok, got = pcall(uiArt.Get, key)
		v = ok and got or nil
	end
	if type(v) == "table" then
		v = v.Id or v.Image
	end
	if type(v) == "number" then
		v = "rbxassetid://" .. v
	end
	return if type(v) == "string" then v else ""
end

-- Image plus its sprite-sheet rect (UiArt.Atlas); keys outside a sheet show their whole image.
local function setArt(img: ImageLabel | ImageButton, key: string)
	local id = art(key)
	if id == "" then
		return
	end
	local entry = uiArt and uiArt[key]
	local r = type(entry) == "table" and entry.Rect or nil
	local offset = if r then Vector2.new(r[1], r[2]) else Vector2.zero
	local size = if r then Vector2.new(r[3], r[4]) else Vector2.zero
	if img.Image ~= id then
		img.Image = id
	end
	if img.ImageRectOffset ~= offset then
		img.ImageRectOffset = offset
	end
	if img.ImageRectSize ~= size then
		img.ImageRectSize = size
	end
end

local function sound(name)
	local mod = Shared:FindFirstChild("Menu") and Shared.Menu:FindFirstChild("UiSound")
	if mod then
		local ok, m = pcall(require, mod)
		if ok and m and m.Play then
			pcall(m.Play, name)
		end
	end
end

-- State from attributes -------------------------------------------------------------------------------------------

local function decode(name)
	local raw = player:GetAttribute(name)
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(t) == "table" then t else {}
end

local kit, counts = decode("GearKit"), decode("GearCounts")
player:GetAttributeChangedSignal("GearKit"):Connect(function()
	kit = decode("GearKit")
end)
player:GetAttributeChangedSignal("GearCounts"):Connect(function()
	counts = decode("GearCounts")
end)

local function character()
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local head = c and c:FindFirstChild("Head")
	if not h or h.Health <= 0 or not head then
		return nil
	end
	if c:GetAttribute("Downed") or c:GetAttribute("Devoured") or c:GetAttribute("Bandaging") or c:GetAttribute("Aboard")
		or player:GetAttribute("OnEmplacement") then -- campaign: not while manning a gun
		return nil
	end
	return c, h, head
end

-- Drawing throws --------------------------------------------------------------------------------------------------

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true

local function refreshFilter()
	local list = { workspace.CurrentCamera }
	for _, name in { "GearFx", "GearSmoke", "Zombies", "Fx", "Drops" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	castParams.FilterDescendantsInstances = list
end

local function cast(from, delta)
	return workspace:Raycast(from, delta, castParams)
end

-- Impact items (Shared.Gear Item.Impact) stop on the first mob too, the same way GearServer casts them.
local mobParams = RaycastParams.new()
mobParams.FilterType = Enum.RaycastFilterType.Include
mobParams.RespectCanCollide = false

local function castFor(item)
	if not item.Impact then
		return cast
	end
	local folders = {}
	for _, name in Gear.MobFolders or {} do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(folders, f)
		end
	end
	if #folders == 0 or not Gear.ImpactCast then
		return cast
	end
	mobParams.FilterDescendantsInstances = folders
	return Gear.ImpactCast(cast, mobParams)
end

local mine = {} -- ids this client already drew
local nextId = 0

local function fly(key, origin, velocity)
	local item = Gear.Items[key]
	local template = GearAssets:FindFirstChild(key)
	if not item or not template or not velocity then
		return
	end
	refreshFilter()
	local points = Gear.Simulate(origin, velocity, castFor(item), item.Bounce)
	local model = template:Clone()
	model.PrimaryPart.Anchored = true
	model:PivotTo(CFrame.new(origin))
	model.Parent = workspace.CurrentCamera
	local step = Gear.Throw.Step
	local t = 0
	local spin = CFrame.Angles(math.random() * 6, math.random() * 6, 0)
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local f = t / step + 1
		local i = math.floor(f)
		if i >= #points or not model.Parent then
			conn:Disconnect()
			model:Destroy()
			return
		end
		local a, b = points[i], points[i + 1]
		local pos = a:Lerp(b, f - i)
		spin *= CFrame.Angles(dt * 9, dt * 4, 0)
		model:PivotTo(CFrame.new(pos) * spin)
	end)
end

-- Using gear ------------------------------------------------------------------------------------------------------
-- Lethal and tactical throws are readied first (4 Nov 2026): G (or Q, RB, LB) puts the gun down and brings the item
-- up in your right hand (StarterPlayerScripts.ViewArms). Hold right mouse (LT) to wind up and see the arc; let go, or
-- click (RT), to throw. The same key again, a gun switch or going down puts it away. A touch button: hold to aim, lift
-- to throw. Stim and the field item (X) act at once.

local function aim(head)
	local camera = workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local origin = camera.CFrame.Position
	if (origin - head.Position).Magnitude > Gear.Throw.MaxOriginOffset - 1 then
		origin = head.Position
	end
	return origin + look * 1.2, look
end

local lastUse = 0

-- Throws or uses the item in slot now. Returns true when something was sent to the server.
local function useNow(slot)
	if os.clock() - lastUse < Gear.Throw.Gap then
		return false
	end
	local c, _, head = character()
	if not c then
		return false
	end
	if slot == "Field" then
		local key = kit.Field
		local item = Gear.Items[key or ""]
		if not item then
			return false
		end
		if key == "Charge" and player:GetAttribute("ChargeOut") then
			lastUse = os.clock()
			Remote:FireServer("Detonate")
			return true
		end
		if (player:GetAttribute("FieldReadyAt") or 0) > workspace:GetServerTimeNow() then
			sound("Locked")
			return false
		end
		local origin, dir = aim(head)
		nextId += 1
		local id = player.UserId .. ":" .. nextId
		lastUse = os.clock()
		if item.Kind == "Throw" then
			mine[id] = true
			fly(key, origin, Gear.Velocity(key, dir))
		end
		Remote:FireServer("Field", { Origin = origin, Direction = dir, Id = id })
		return true
	end
	local key = kit[slot]
	local item = Gear.Items[key or ""]
	if not item then
		return false
	end
	if (counts[slot] or 0) <= 0 then
		sound("Locked")
		return false
	end
	local origin, dir = aim(head)
	nextId += 1
	local id = player.UserId .. ":" .. nextId
	lastUse = os.clock()
	if item.Kind == "Throw" then
		mine[id] = true
		fly(key, origin, Gear.Velocity(key, dir))
	end
	-- Show the count drop at once; the attribute confirms it.
	counts[slot] = math.max(0, (counts[slot] or 0) - 1)
	Remote:FireServer("Throw", { Slot = slot, Origin = origin, Direction = dir, Id = id })
	return true
end

-- The arc -----------------------------------------------------------------------------------------------------------
-- While aiming, a dotted arc (the same Gear.Simulate the throw and the server use) shows where it flies, and a disc on
-- the landing spot is as wide as its blast (Radius; a small marker for items without one). Local, in the camera.

local AIM = {
	Spacing = 1.6, -- studs between arc dots
	Dots = 48,
	Dot = 0.32, -- dot size
	Marker = 3, -- landing disc width for items with no blast radius
	Colors = {
		Lethal = Color3.fromRGB(255, 120, 90),
		Tactical = Color3.fromRGB(236, 232, 214),
		Field = Color3.fromRGB(190, 200, 205),
	},
}

local aimFolder, aimDisc, aimCore = nil, nil, nil
local aimDots = {}
local filterAt = 0

local function aimPart(shape, size)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = aimFolder
	return p
end

local function buildAim()
	aimFolder = Instance.new("Folder")
	aimFolder.Name = "GearAim"
	for i = 1, AIM.Dots do
		aimDots[i] = aimPart(Enum.PartType.Ball, Vector3.one * AIM.Dot)
	end
	aimDisc = aimPart(Enum.PartType.Cylinder, Vector3.new(0.06, 1, 1))
	aimCore = aimPart(Enum.PartType.Cylinder, Vector3.new(0.1, 1.1, 1.1))
end

-- A flat disc lying on a surface (a Cylinder's axis is its X).
local function flat(pos, normal)
	local side = if math.abs(normal.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	return CFrame.fromMatrix(pos, normal, normal:Cross(side).Unit)
end

local function hideArc()
	if aimFolder then
		aimFolder.Parent = nil
	end
end

local function drawArc(slot, key, item)
	local _, _, head = character()
	if not head then
		hideArc()
		return
	end
	if not aimFolder then
		buildAim()
	end
	if os.clock() - filterAt > 0.5 then
		filterAt = os.clock()
		refreshFilter()
	end
	local origin, dir = aim(head)
	local velocity = Gear.Velocity(key, dir)
	if not velocity then
		hideArc()
		return
	end
	local points, rest, normal, _, landed = Gear.Simulate(origin, velocity, castFor(item), item.Bounce)
	local color = AIM.Colors[slot] or AIM.Colors.Tactical
	-- a dot every AIM.Spacing studs along the arc, fading toward the end; the first stretch by the face is left out
	local n, walked, need = 0, 0, AIM.Spacing * 1.5
	for k = 2, #points do
		local a, b = points[k - 1], points[k]
		local seg = (b - a).Magnitude
		while n < AIM.Dots and walked + seg >= need do
			n += 1
			local dot = aimDots[n]
			dot.CFrame = CFrame.new(a:Lerp(b, (need - walked) / seg))
			dot.Color = color
			dot.Transparency = 0.1 + 0.5 * (n / AIM.Dots)
			need += AIM.Spacing
		end
		walked += seg
	end
	for k = n + 1, AIM.Dots do
		aimDots[k].Transparency = 1
	end
	local width = if item.Radius then item.Radius * 2 else AIM.Marker
	aimDisc.Size = Vector3.new(0.06, width, width)
	aimDisc.CFrame = flat(rest + normal * 0.06, normal)
	aimDisc.Color = color
	aimDisc.Transparency = if landed then 0.8 else 1
	aimCore.CFrame = flat(rest + normal * 0.08, normal)
	aimCore.Color = color
	aimCore.Transparency = if landed then 0.25 else 1
	aimFolder.Parent = workspace.CurrentCamera
end

-- Ready state -------------------------------------------------------------------------------------------------------

local ready = nil -- {Slot, Key, Item, Aiming, ThrownAt}
local THROW_TIME = 0.28 -- the arm swing after a throw, before the gun comes back

local function setReadyFlag(on)
	local c = player.Character
	if c then
		c:SetAttribute("GearReady", if on then true else nil) -- GunClient lowers the gun and holds fire
	end
end

local function unbindThrowInput()
	Controls.Unbind("GearThrowInput")
end

local function cancelReady()
	if not ready then
		return
	end
	ready = nil
	hideArc()
	unbindThrowInput()
	setReadyFlag(false)
end

local function release()
	local r = ready
	if not r or r.ThrownAt then
		return
	end
	unbindThrowInput()
	hideArc()
	if useNow(r.Slot) then
		r.ThrownAt = os.clock()
		r.Aiming = false
	else
		cancelReady()
	end
end

local function onThrowInput(_, state, input)
	local r = ready
	if not r or r.ThrownAt then
		return Enum.ContextActionResult.Pass
	end
	local isAim = Controls.Matches("Aim", input)
	if state == Enum.UserInputState.Begin then
		if isAim then
			r.Aiming = true
		else
			release()
		end
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if isAim and r.Aiming then
			r.Aiming = false
			if state == Enum.UserInputState.End then
				release()
			end
		end
	end
	return Enum.ContextActionResult.Sink
end

-- Returns true when the item is now in hand.
local function readyUp(slot)
	if ready then
		if ready.ThrownAt then
			return false
		end
		if ready.Slot == slot then
			cancelReady()
			return false
		end
		cancelReady()
	end
	local key = kit[slot]
	local item = Gear.Items[key or ""]
	if not item then
		return false
	end
	if item.Kind ~= "Throw" then
		useNow(slot)
		return false
	end
	if not character() then
		return false
	end
	if (counts[slot] or 0) <= 0 then
		sound("Locked")
		return false
	end
	ready = { Slot = slot, Key = key, Item = item, Aiming = false }
	setReadyFlag(true)
	-- Throw on Shoot, wind up on Aim (the player's own keys, Shared.Controls).
	Controls.Bind("GearThrowInput", { "Fire", "Aim" }, onThrowInput, 3000)
	return true
end

player:GetAttributeChangedSignal("EquippedGun"):Connect(function()
	if ready and not ready.ThrownAt then
		cancelReady()
	end
end)

-- The view: your own arms (ViewArms), the item in the right hand -------------------------------------------------

local ViewArms = require(script.Parent:WaitForChild("ViewArms"))
-- Camera space (x right, y up, -z forward). HOLD: item low right, left hand out of view. WIND: aiming, the item back
-- by the ear, the left hand pointing ahead. SWING: the arm thrown forward.
local POSE = {
	HOLD = { Right = Vector3.new(0.36, -0.42, -0.95), Left = Vector3.new(-0.45, -1.4, -0.45) },
	WIND = { Right = Vector3.new(0.5, -0.05, -0.55), Left = Vector3.new(-0.22, -0.3, -1.05) },
	SWING = { Right = Vector3.new(0.08, -0.25, -1.4), Left = Vector3.new(-0.4, -1.1, -0.6) },
}
local RAISE_TIME = 0.16

local view = nil -- {Model, Arms, Held, HeldKey, HeldOffset}
local raise, wind = 0, 0

local function clearView()
	if view then
		view.Arms:Destroy()
		view.Model:Destroy()
		view = nil
	end
end

local function holdModel(key, parent)
	local template = GearAssets:FindFirstChild(key)
	if not template then
		return nil, nil
	end
	local m = template:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local bbox = m:GetBoundingBox()
	local offset = m:GetPivot():ToObjectSpace(bbox) -- pivot to centre
	m.Parent = parent
	return m, offset
end

local function lerpPose(a, b, k)
	return { Right = a.Right:Lerp(b.Right, k), Left = a.Left:Lerp(b.Left, k) }
end

RunService:BindToRenderStep("GearView", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local c = character()
	if ready and (not c or (ready.ThrownAt and os.clock() - ready.ThrownAt > THROW_TIME)) then
		cancelReady()
	end
	raise = math.clamp(raise + (if ready then dt else -dt * 1.5) / RAISE_TIME, 0, 1)
	if raise <= 0 or not player.Character then
		clearView()
		return
	end
	if not view then
		local model = Instance.new("Model")
		model.Name = "GearView"
		model.Parent = workspace.CurrentCamera
		view = { Model = model, Arms = ViewArms.new(player.Character, model) }
	end
	local key = ready and ready.Key or view.HeldKey
	if key ~= view.HeldKey then
		if view.Held then
			view.Held:Destroy()
		end
		view.Held, view.HeldOffset = holdModel(key, view.Model)
		view.HeldKey = key
	end

	wind += ((if ready and ready.Aiming then 1 else 0) - wind) * math.min(1, dt * 12)
	local pose = lerpPose(POSE.HOLD, POSE.WIND, wind)
	local swing = 0
	if ready and ready.ThrownAt then
		swing = math.clamp((os.clock() - ready.ThrownAt) / (THROW_TIME * 0.6), 0, 1)
		pose = lerpPose(pose, POSE.SWING, 1 - (1 - swing) ^ 3)
	end
	local up = 1 - (1 - raise) ^ 3
	local camera = workspace.CurrentCamera
	local bob = math.sin(os.clock() * 6) * 0.006
	local base = camera.CFrame * CFrame.new(0, -0.6 * (1 - up) + bob, 0.15 * (1 - up))
	local rightGrip = base * CFrame.new(pose.Right) * CFrame.Angles(math.rad(10), math.rad(-15), 0)
	local leftGrip = base * CFrame.new(pose.Left)
	view.Arms:Update(base, rightGrip, leftGrip, 0)

	if view.Held then
		-- in the fist, a little ahead of the grip point; gone once it leaves the hand
		local inHand = swing < 0.35
		if inHand then
			local target = rightGrip * CFrame.new(0, -0.02, -0.12) * CFrame.Angles(math.rad(-20), 0, 0)
			view.Held:PivotTo(target * view.HeldOffset:Inverse())
		end
		for _, d in view.Held:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if inHand then 0 else 1
			end
		end
	end

	if ready and ready.Aiming and not ready.ThrownAt then
		drawArc(ready.Slot, ready.Key, ready.Item)
	else
		hideArc()
	end
end)

player.CharacterRemoving:Connect(function()
	cancelReady()
	clearView()
	raise, wind = 0, 0
end)

local function action(slot)
	return function(_, state)
		if state == Enum.UserInputState.Begin then
			if slot == "Field" then
				useNow(slot)
			else
				readyUp(slot)
			end
		end
		return Enum.ContextActionResult.Pass
	end
end

-- Touch: hold a gear button to aim (the item comes up and the arc shows), lift to throw.
local function touchPress(slot)
	if slot == "Field" then
		useNow(slot)
		return
	end
	if ready and ready.Slot == slot and not ready.ThrownAt then
		ready.Aiming = true
		return
	end
	if readyUp(slot) and ready then
		ready.Aiming = true
	end
end

local function touchRelease(slot)
	if ready and ready.Slot == slot and ready.Aiming then
		release()
	end
end

local function inMatch()
	return player:GetAttribute("InMatch") == true or RunService:IsStudio()
end

-- Bound only while the player is in a match, so the menu keeps its shoulder buttons.
local bound = false
local function rebind()
	local want = inMatch() and player.Character ~= nil
	if want == bound then
		return
	end
	bound = want
	if want then
		-- Keys from Shared.Controls (G / RB, Q or T / LB, X / D-pad right by default; follow rebinds).
		Controls.Bind("GearLethal", "Lethal", action("Lethal"), 2000)
		Controls.Bind("GearTactical", "Tactical", action("Tactical"), 2000)
		Controls.Bind("GearField", "Field", action("Field"), 2000)
	else
		cancelReady()
		Controls.Unbind("GearLethal")
		Controls.Unbind("GearTactical")
		Controls.Unbind("GearField")
	end
end
player:GetAttributeChangedSignal("InMatch"):Connect(rebind)
player.CharacterAdded:Connect(function()
	task.defer(rebind)
end)
player.CharacterRemoving:Connect(function()
	task.defer(rebind)
end)
rebind()

-- Stim: a short speed lift on top of whatever sets the walk speed.
local stimBase, stimSet = nil, nil
local function stimStep()
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local untilT = c and c:GetAttribute("StimUntil") or 0
	if not h then
		return
	end
	if untilT > workspace:GetServerTimeNow() then
		local mult = c:GetAttribute("StimSpeed") or 1.15
		if stimSet == nil or math.abs(h.WalkSpeed - stimSet) > 0.01 then
			stimBase = h.WalkSpeed
		end
		stimSet = stimBase * mult
		h.WalkSpeed = stimSet
	elseif stimSet then
		if math.abs(h.WalkSpeed - stimSet) < 0.01 and stimBase then
			h.WalkSpeed = stimBase
		end
		stimBase, stimSet = nil, nil
	end
end
RunService:BindToRenderStep("GearStim", Enum.RenderPriority.Last.Value, stimStep)

-- Fx from the server ----------------------------------------------------------------------------------------------

local function shake(pos, strength)
	local camera = workspace.CurrentCamera
	local d = (camera.CFrame.Position - pos).Magnitude
	local k = math.clamp(1 - d / 45, 0, 1) * strength
	if k <= 0 then
		return
	end
	local t = 0
	local name = "GearShake" .. tostring(os.clock())
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt)
		t += dt
		if t > 0.35 then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local a = k * (1 - t / 0.35) * 0.02
		camera.CFrame *= CFrame.Angles((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
	end)
end

local function flash(pos, radius)
	local camera = workspace.CurrentCamera
	local to = pos - camera.CFrame.Position
	local d = to.Magnitude
	if d > radius * 1.6 then
		return
	end
	refreshFilter()
	if workspace:Raycast(camera.CFrame.Position, to, castParams) then
		return
	end
	local facing = math.clamp(camera.CFrame.LookVector:Dot(to.Unit), 0, 1)
	local k = math.clamp(1 - d / (radius * 1.6), 0, 1) * (0.35 + 0.65 * facing)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "GearFlash"
	cc.Brightness = 0.9 * k
	cc.Contrast = -0.3 * k
	cc.Parent = Lighting
	local t = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local f = math.clamp(1 - t / (0.6 + 1.6 * k), 0, 1)
		cc.Brightness = 0.9 * k * f
		cc.Contrast = -0.3 * k * f
		if f <= 0 then
			conn:Disconnect()
			cc:Destroy()
		end
	end)
end

local function spray(origin, dir)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.lookAt(origin, origin + dir)
	local a = Instance.new("Attachment")
	a.Parent = p
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(235, 235, 232))
	e.EmissionDirection = Enum.NormalId.Front
	e.Speed = NumberRange.new(30, 45)
	e.SpreadAngle = Vector2.new(18, 18)
	e.Lifetime = NumberRange.new(0.4, 0.7)
	e.Drag = 3
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.5) })
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Rate = 0
	e.Parent = a
	p.Parent = workspace.CurrentCamera
	e:Emit(70)
	task.delay(1.2, function()
		p:Destroy()
	end)
end

-- A frag or charge going off: a one-frame flash, a short fireball, dark lit smoke, thrown dirt and a few sparks
-- (no engine Explosion: its big unlit puff glowed at night). Everything is a one-shot Emit, gone in 3 s.
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local function burst(attachment, count, props)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightInfluence = 1
	e.LightEmission = 0
	e.SpreadAngle = Vector2.new(180, 180)
	for k, v in props do
		e[k] = v
	end
	e.Parent = attachment
	e:Emit(count)
end

local function blast(pos, radius)
	local k = math.clamp((radius or 12) / 14, 0.6, 1.3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0))
	local a = Instance.new("Attachment")
	a.Parent = p
	p.Parent = workspace.CurrentCamera
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 95)
	light.Range = 22 * k
	light.Brightness = 3
	light.Shadows = false
	light.Parent = a
	burst(a, 9, {
		Texture = TEX_FIRE, LightEmission = 0.55, LightInfluence = 0.2,
		Color = ColorSequence.new(Color3.fromRGB(255, 196, 120), Color3.fromRGB(150, 50, 20)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2 * k), NumberSequenceKeypoint.new(1, 4.5 * k) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.14, 0.26), Speed = NumberRange.new(6, 12), Drag = 6,
		Rotation = NumberRange.new(0, 360),
	})
	burst(a, 12, {
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(70, 66, 62), Color3.fromRGB(110, 106, 100)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3 * k), NumberSequenceKeypoint.new(1, 9 * k) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.6, 0.6),
			NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.4, 2.4), Speed = NumberRange.new(4, 10), Drag = 2.5,
		Acceleration = Vector3.new(0, 3, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
	})
	burst(a, 16, {
		Texture = TEX_SMOKE, EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(55, 55),
		Color = ColorSequence.new(Color3.fromRGB(84, 68, 52)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.2) }),
		Transparency = NumberSequence.new(0.1, 0.6),
		Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(18, 32), Drag = 0.6,
		Acceleration = Vector3.new(0, -60, 0),
	})
	burst(a, 10, {
		Texture = TEX_SPARK, LightEmission = 0.8, LightInfluence = 0,
		Color = ColorSequence.new(Color3.fromRGB(255, 210, 140)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.15, 0.3), Speed = NumberRange.new(35, 55), Drag = 5,
	})
	task.spawn(function()
		local t = 0
		while t < 0.25 do
			t += RunService.RenderStepped:Wait()
			light.Brightness = 3 * math.max(0, 1 - t / 0.25)
		end
		light:Destroy()
	end)
	task.delay(3, function()
		p:Destroy()
	end)
	shake(pos, 1)
end

Remote.OnClientEvent:Connect(function(msg, fx)
	if msg ~= "Fx" or type(fx) ~= "table" then
		return
	end
	local kind = fx.Kind
	if kind == "Throw" then
		if fx.Owner == player and fx.Id and mine[fx.Id] then
			mine[fx.Id] = nil
			return
		end
		fly(fx.Key, fx.Origin, fx.Velocity)
	elseif kind == "Blast" then
		blast(fx.Origin, fx.Radius)
	elseif kind == "Flash" then
		flash(fx.Origin, fx.Radius or 20)
		shake(fx.Origin, 0.5)
	elseif kind == "Spray" then
		if typeof(fx.Origin) == "Vector3" and typeof(fx.Direction) == "Vector3" then
			spray(fx.Origin, fx.Direction)
		end
	elseif kind == "Denied" then
		counts = decode("GearCounts")
		sound("Locked")
	elseif kind == "Upgrade" then
		-- a wall-station tier bought (Points); the prompt repaints its next price from the Tiers attribute
		sound("Stamp")
	end
end)

-- HUD -------------------------------------------------------------------------------------------------------------

local hud = playerGui:WaitForChild("HUD", 30)
local row = hud and hud:WaitForChild("Gear", 10)
local touchGui = playerGui:WaitForChild("TouchControls", 10)

-- Same device test as every other HUD key hint (Shared.Platform via Controls), so the plates switch with them.
local function usingPad()
	return Controls.ActiveDevice() == "Pad"
end

-- Touch buttons: hold to aim a throwable (it comes up in hand with the arc), lift to throw.
if touchGui then
	for _, slot in SLOTS do
		local b = touchGui:FindFirstChild(slot)
		if b and b:IsA("GuiButton") then
			b.InputBegan:Connect(function(input)
				local t = input.UserInputType
				if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
					return
				end
				touchPress(slot)
				local conn
				conn = input.Changed:Connect(function(prop)
					if prop ~= "UserInputState" then
						return
					end
					if input.UserInputState == Enum.UserInputState.End then
						conn:Disconnect()
						touchRelease(slot)
					elseif input.UserInputState == Enum.UserInputState.Cancel then
						conn:Disconnect()
						if ready and ready.Slot == slot and not ready.ThrownAt then
							cancelReady()
						end
					end
				end)
			end)
		end
	end
end

local function keyFor(slot)
	if slot == "Field" then
		return kit.Field
	end
	return kit[slot]
end

local function paint(plate, slot, showKey)
	if not plate then
		return
	end
	local key = keyFor(slot)
	local item = Gear.Items[key or ""]
	plate.Visible = item ~= nil
	if not item then
		return
	end
	setArt(plate, "Hud/" .. slot .. "Slot")
	local icon = plate:FindFirstChild("Icon")
	if icon then
		local iconKey = item.Art or ("Gear/" .. key)
		if art(iconKey) == "" then
			icon.Image = ""
		else
			setArt(icon, iconKey)
		end
	end
	local count = plate:FindFirstChild("Count")
	if count then
		if slot == "Field" then
			count.Text = if key == "Charge" and player:GetAttribute("ChargeOut") then "1" else ""
		else
			count.Text = tostring(counts[slot] or 0)
		end
	end
	local keyLabel = plate:FindFirstChild("Key")
	if keyLabel then
		-- The player's own key for this slot (Shared.Controls), so a rebind shows here at once.
		keyLabel.Text = if showKey then Controls.Short(slot, if usingPad() then "Pad" else "Kb") else ""
	end
	local cd = plate:FindFirstChild("Cooldown")
	if cd then
		local frac = 0
		if slot == "Field" then
			local left = (player:GetAttribute("FieldReadyAt") or 0) - workspace:GetServerTimeNow()
			frac = math.clamp(left / (item.Cooldown or 90), 0, 1)
		elseif (counts[slot] or 0) <= 0 then
			frac = 1
		end
		cd.Size = UDim2.fromScale(1, frac)
		local veil = cd:FindFirstChild("Veil")
		if veil then
			setArt(veil, "Hud/Cooldown")
			veil.Size = UDim2.fromOffset(plate.AbsoluteSize.X, plate.AbsoluteSize.Y)
		end
	end
end

-- Upgrade stations (Points): this player's own next-tier price for the gun in hand, written on the prompt locally.
local ProximityPromptService = game:GetService("ProximityPromptService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local shownUpgrade = nil
local function paintUpgrade(prompt)
	local list = GameConfig.Director and GameConfig.Director.Tiers
	local gun = player:GetAttribute("EquippedGun")
	if not list or type(gun) ~= "string" then
		return
	end
	local tier = tonumber(decode("Tiers")[gun]) or 1
	local nextTier = list[tier + 1]
	if nextTier then
		prompt.ActionText = "Upgrade " .. nextTier.Cost
		prompt.ObjectText = "Tier " .. nextTier.Name
		prompt.Enabled = true
	else
		prompt.ActionText = "Upgrade"
		prompt.ObjectText = "Tier " .. list[#list].Name
	end
end
ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt:GetAttribute("Station") == "Upgrade" then
		shownUpgrade = prompt
		paintUpgrade(prompt)
	end
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	if prompt == shownUpgrade then
		shownUpgrade = nil
	end
end)
for _, name in { "Tiers", "EquippedGun" } do
	player:GetAttributeChangedSignal(name):Connect(function()
		if shownUpgrade then
			paintUpgrade(shownUpgrade)
		end
	end)
end

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < 0.1 then
		return
	end
	accum = 0
	local active = inMatch() and player.Character ~= nil
	if row then
		-- Phones throw from the TouchControls buttons (they show the gear and its count); the HUD plates would repeat them.
		local showRow = active and player:GetAttribute("TouchHud") ~= true
		row.Visible = showRow
		local hotbar = hud:FindFirstChild("Hotbar")
		if hotbar then
			row.Visible = showRow and hotbar.Visible
			row.Position = UDim2.new(hotbar.Position.X.Scale, hotbar.Position.X.Offset + hotbar.AbsoluteSize.X / 2 + 12,
				hotbar.Position.Y.Scale, hotbar.Position.Y.Offset)
		end
		for _, slot in SLOTS do
			paint(row:FindFirstChild(slot), slot, true)
		end
	end
	if touchGui then
		for _, slot in SLOTS do
			local b = touchGui:FindFirstChild(slot)
			if b then
				paint(b, slot, false)
				b.Visible = b.Visible and active
			end
		end
	end
end)
