-- The hotbar (StarterGui.HUD.Hotbar, authored in Studio): the three inventory slots
-- (ServerStorage.Modules.Inventory, read from the player attribute "Inventory"). A gun slot
-- equips that gun; a bandage slot uses one (ServerStorage.Modules.Bandages) and fills while
-- it's being applied. The slot keys (1-3) or a tap pick a slot; the Bandage key (H / D-pad down) uses a
-- bandage. Keys are the player's own (Shared.Controls) and the slot labels show them. Icons are the
-- models themselves in ViewportFrames. The gun in your hands gets the amber line.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Controls = require(Shared:WaitForChild("Controls"))
local Platform = require(Shared:WaitForChild("Platform"))
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local hotbarEquip = script.Parent:WaitForChild("GunClient"):WaitForChild("HotbarEquip")

local IDLE_STROKE = 0.86
local IDLE_BACK = 0.35
local EMPTY_BACK = 0.6

-- Frames a model side-on in a ViewportFrame, pointing right.
local function showModel(viewport, source)
	viewport:ClearAllChildren()
	if not source then
		return
	end
	local model = source:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		elseif d:IsA("BasePart") and d.Transparency >= 0.99 then
			d:Destroy()
		end
	end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	model.Parent = world
	local cf, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local forward = pivot.LookVector
	local up = pivot.UpVector
	-- A roll of bandage has no "forward": show it from a three-quarter angle instead.
	if model:GetAttribute("Kind") then
		forward = (pivot.RightVector + pivot.LookVector * 0.6).Unit
	end
	local side = forward:Cross(up)
	local length = math.max(size.X, size.Y, size.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local aspect = viewport.AbsoluteSize.X / math.max(viewport.AbsoluteSize.Y, 1)
	local half = math.atan(math.tan(math.rad(15)) * math.max(aspect, 1))
	local distance = (length / 2) / math.tan(half) * 1.08 + length / 2
	camera.CFrame = CFrame.lookAt(cf.Position + side * distance + up * length * 0.06, cf.Position, up)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function iconSource(item)
	local gun = GameConfig.Guns[item]
	if gun then
		return Assets.ViewModels:FindFirstChild(gun.ViewModel)
	end
	return Assets.Icons:FindFirstChild(item)
end

-- { Item, Count } per slot, false when empty.
local function readInventory()
	local list = {}
	local i = 0
	for field in ((player:GetAttribute("Inventory") or "") .. "|"):gmatch("([^|]*)|") do
		i += 1
		local item, count = field:match("^(.+):(%d+)$")
		list[i] = if item then { Item = item, Count = tonumber(count) } else false
	end
	return list
end

local slots = {} -- { Button, Stroke, Item }

local function flash(slot)
	if not slot then
		return
	end
	slot.Stroke.Color = Color3.fromRGB(230, 70, 60)
	slot.Stroke.Transparency = 0.1
	task.delay(0.25, function()
		slot.Stroke.Color = Color3.new(1, 1, 1)
		slot.Stroke.Transparency = IDLE_STROKE
	end)
end

local function bandageSlot()
	for _, slot in slots do
		if slot.Item == "Bandage" then
			return slot
		end
	end
	return nil
end

local function useBandage()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local slot = bandageSlot()
	local hurt = humanoid and (humanoid.Health < humanoid.MaxHealth or (character:GetAttribute("Trauma") or 0) > 0)
	if not slot or not hurt or character:GetAttribute("Bandaging") or character:GetAttribute("Downed") then
		flash(slot or slots[1])
		return
	end
	Remotes.Bandage:FireServer()
end

local function pick(index)
	local slot = slots[index]
	if not slot or not slot.Item then
		flash(slot)
	elseif GameConfig.Guns[slot.Item] then
		-- Picking a gun puts a half-done bandage away (it isn't used up).
		local character = player.Character
		if character and character:GetAttribute("Bandaging") then
			Remotes.Bandage:FireServer("Cancel")
		end
		hotbarEquip:Fire(slot.Item)
	elseif slot.Item == "Bandage" then
		useBandage()
	end
end

-- Redraws the slots from the inventory; equips a gun that just came in, or a carried gun if
-- the one in hand is gone (it was swapped away).
local function refresh()
	local inventory = readInventory()
	local hadGun = {}
	for _, slot in slots do
		if slot.Item then
			hadGun[slot.Item] = true
		end
	end
	local newGun, firstGun
	for i, slot in slots do
		local content = inventory[i]
		local item = content and content.Item or nil
		if item ~= slot.Item then
			slot.Item = item
			task.defer(showModel, slot.Button.Icon, item and iconSource(item))
			if item and GameConfig.Guns[item] and not hadGun[item] and slot.Ready then
				newGun = item
			end
		end
		slot.Ready = true
		if item and GameConfig.Guns[item] and not firstGun then
			firstGun = item
		end
		slot.Button.Count.Text = if content and content.Count > 1 or item == "Bandage" then "x" .. content.Count else ""
		local keyLabel = slot.Button:FindFirstChild("Key")
		if keyLabel then
			-- The player's own key for this slot; hidden on a phone (4 Nov 2026), or when the slot has no key on
			-- this device (controllers pick guns with Y, not slot keys).
			local key = Controls.Short("Slot" .. i, Controls.ActiveDevice())
			keyLabel.Text = key
			keyLabel.Visible = player:GetAttribute("TouchHud") ~= true and key ~= ""
		end
		slot.Button.BackgroundTransparency = if item then IDLE_BACK else EMPTY_BACK
	end
	local character = player.Character
	if character and character:GetAttribute("Downed") then
		return
	end
	local equipped = player:GetAttribute("EquippedGun")
	if newGun then
		hotbarEquip:Fire(newGun)
	elseif firstGun and equipped and not string.find("|" .. (player:GetAttribute("Inventory") or "") , "|" .. equipped .. ":", 1, true) then
		hotbarEquip:Fire(firstGun)
	end
end

local function bind(hud)
	local bar = hud:WaitForChild("Hotbar")
	table.clear(slots)
	local buttons = {}
	for _, button in bar:GetChildren() do
		if button:IsA("GuiButton") then
			table.insert(buttons, button)
		end
	end
	table.sort(buttons, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i, button in buttons do
		local slot = { Button = button, Stroke = button:FindFirstChildOfClass("UIStroke"), Item = nil }
		slots[i] = slot
		button:WaitForChild("Icon")
		button.Activated:Connect(function()
			pick(i)
		end)
	end
	refresh()
end

player:GetAttributeChangedSignal("Inventory"):Connect(refresh)
player:GetAttributeChangedSignal("TouchHud"):Connect(function()
	if #slots > 0 then
		refresh()
	end
end)

-- A rebind, or switching between keyboard and controller, redraws the slot keys.
local function redrawKeys()
	if #slots > 0 then
		refresh()
	end
end
Controls.Changed:Connect(redrawKeys)
Platform.Changed:Connect(redrawKeys)

-- Slot and bandage keys from Shared.Controls (1-3 and H / D-pad down by default; follow rebinds).
local SLOTS = { "Slot1", "Slot2", "Slot3" }
Controls.Bind("HotbarSlot", SLOTS, function(_, inputState, input)
	if inputState == Enum.UserInputState.Begin and not Controls.Listening then
		for i, name in SLOTS do
			if Controls.Matches(name, input) then
				pick(i)
				break
			end
		end
	end
	return Enum.ContextActionResult.Sink
end)
Controls.Bind("Bandage", "Bandage", function(_, inputState)
	if inputState == Enum.UserInputState.Begin and not Controls.Listening then
		useBandage()
	end
	return Enum.ContextActionResult.Sink
end)

local playerGui = player:WaitForChild("PlayerGui")
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUD" then
		bind(child)
	end
end)
if playerGui:FindFirstChild("HUD") then
	bind(playerGui.HUD)
end

RunService.RenderStepped:Connect(function()
	if #slots == 0 or not slots[1].Button.Parent then
		return
	end
	local equipped = player:GetAttribute("EquippedGun")
	local character = player.Character
	local done = character and character:GetAttribute("BandageDone")
	for _, slot in slots do
		local button = slot.Button
		if slot.Item == "Bandage" then
			local k = 0
			if done then
				local left = done - workspace:GetServerTimeNow()
				k = math.clamp(1 - left / GameConfig.Bandages.ApplyTime, 0, 1)
			end
			button.Fill.Size = UDim2.fromScale(1, k)
			button.Accent.Visible = done ~= nil
		else
			local selected = slot.Item ~= nil and slot.Item == equipped
			button.Accent.Visible = selected
			if slot.Item then
				button.BackgroundTransparency = if selected then 0.15 else IDLE_BACK
			end
			if slot.Stroke.Color == Color3.new(1, 1, 1) then
				slot.Stroke.Transparency = if selected then 0.55 else IDLE_STROKE
			end
			button.Fill.Size = UDim2.fromScale(1, 0)
		end
	end
end)
