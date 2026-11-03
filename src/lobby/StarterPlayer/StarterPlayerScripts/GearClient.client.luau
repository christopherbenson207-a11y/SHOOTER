-- GearClient (MATCH, menu revamp 3 Nov 2026; CONTRACTS sections 2, 5; MENU-PLAN 3.13, 4.6, 9.5, 9.10).
-- Keys: G lethal, Q tactical (T also works), X field item (X again detonates a placed Breaching Charge); gamepad RB,
-- LB, DPad-right; touch: the Lethal, Tactical and Field buttons in StarterGui.TouchControls. The client draws a throw
-- at once along Shared.Gear.Simulate and tells GearServer ("Throw" / "Field" with Origin, Direction, Id); the server
-- checks everything and runs the real arc. Fx from the server draws other players' throws (the thrower's own Id is
-- skipped), blasts, the flashbang flash, the Extinguisher spray and the Stim speed.
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
local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gear")
local GearAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Gear")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SLOTS = { "Lethal", "Tactical", "Field" }
local KEY_TEXT = { Lethal = "G", Tactical = "Q", Field = "X" }
local PAD_TEXT = { Lethal = "RB", Tactical = "LB", Field = "D>" }

-- Art -------------------------------------------------------------------------------------------------------------

local uiArt = nil
local function art(key)
	if uiArt == nil then
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
	if c:GetAttribute("Downed") or c:GetAttribute("Devoured") or c:GetAttribute("Bandaging") or c:GetAttribute("Aboard") then
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

local mine = {} -- ids this client already drew
local nextId = 0

local function fly(key, origin, velocity)
	local item = Gear.Items[key]
	local template = GearAssets:FindFirstChild(key)
	if not item or not template or not velocity then
		return
	end
	refreshFilter()
	local points = Gear.Simulate(origin, velocity, cast, item.Bounce)
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

local function use(slot)
	if os.clock() - lastUse < Gear.Throw.Gap then
		return
	end
	local c, _, head = character()
	if not c then
		return
	end
	if slot == "Field" then
		local key = kit.Field
		local item = Gear.Items[key or ""]
		if not item then
			return
		end
		if key == "Charge" and player:GetAttribute("ChargeOut") then
			lastUse = os.clock()
			Remote:FireServer("Detonate")
			return
		end
		if (player:GetAttribute("FieldReadyAt") or 0) > workspace:GetServerTimeNow() then
			sound("Locked")
			return
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
		return
	end
	local key = kit[slot]
	local item = Gear.Items[key or ""]
	if not item then
		return
	end
	if (counts[slot] or 0) <= 0 then
		sound("Locked")
		return
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
end

local function action(slot)
	return function(_, state)
		if state == Enum.UserInputState.Begin then
			use(slot)
		end
		return Enum.ContextActionResult.Pass
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
		local K = Gear.Keys
		ContextActionService:BindActionAtPriority("GearLethal", action("Lethal"), false, 2000, K.Lethal.Key, K.Lethal.Pad)
		ContextActionService:BindActionAtPriority("GearTactical", action("Tactical"), false, 2000, K.Tactical.Key, K.Tactical.Alt, K.Tactical.Pad)
		ContextActionService:BindActionAtPriority("GearField", action("Field"), false, 2000, K.Field.Key, K.Field.Pad)
	else
		ContextActionService:UnbindAction("GearLethal")
		ContextActionService:UnbindAction("GearTactical")
		ContextActionService:UnbindAction("GearField")
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

local function blast(pos, radius)
	local e = Instance.new("Explosion")
	e.Position = pos
	e.BlastRadius = math.min(radius or 12, 16) * 0.5
	e.BlastPressure = 0
	e.DestroyJointRadiusPercent = 0
	e.ExplosionType = Enum.ExplosionType.NoCraters
	e.Parent = workspace.CurrentCamera
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
	end
end)

-- HUD -------------------------------------------------------------------------------------------------------------

local hud = playerGui:WaitForChild("HUD", 30)
local row = hud and hud:WaitForChild("Gear", 10)
local touchGui = playerGui:WaitForChild("TouchControls", 10)

local function usingPad()
	local t = UserInputService:GetLastInputType()
	return t.Name:find("Gamepad") ~= nil
end

-- Touch buttons fire their slot.
if touchGui then
	for _, slot in SLOTS do
		local b = touchGui:FindFirstChild(slot)
		if b and b:IsA("GuiButton") then
			b.Activated:Connect(function()
				use(slot)
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
	local plateArt = art("Hud/" .. slot .. "Slot")
	if plateArt ~= "" and plate.Image ~= plateArt then
		plate.Image = plateArt
	end
	local icon = plate:FindFirstChild("Icon")
	if icon then
		local a = art(item.Art or ("Gear/" .. key))
		if icon.Image ~= a then
			icon.Image = a
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
		keyLabel.Text = if showKey then (if usingPad() then PAD_TEXT[slot] else KEY_TEXT[slot]) else ""
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
			local veilArt = art("Hud/Cooldown")
			if veilArt ~= "" and veil.Image ~= veilArt then
				veil.Image = veilArt
			end
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
		row.Visible = active
		local hotbar = hud:FindFirstChild("Hotbar")
		if hotbar then
			row.Visible = active and hotbar.Visible
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
