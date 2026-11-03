-- The hotbar (StarterGui.HUD.Hotbar, authored in Studio): one button per inventory slot
-- (ServerStorage.Modules.Inventory, read from the player attribute "Inventory"; button N is slot N, by LayoutOrder).
-- Slot 1 is the kit's primary, 2 its secondary, 3 a gun picked up, 4 the bandage stack. A gun slot equips that gun;
-- the bandage slot uses one (ServerStorage.Modules.Bandages) and fills while it's being applied. Keys 1-4 or a tap
-- pick a slot; D-pad down uses a bandage. Icons are the world models (Assets.WorldGuns, in the player's camo) in
-- ViewportFrames. The gun in your hands gets the amber line.
-- A respawn rebuilds the whole inventory: that change never equips anything (GunClient raises the kit's StartGun);
-- only a gun that arrives on its own (a pickup) is put in your hands.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Assets = ReplicatedStorage:WaitForChild("Assets")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Camo = nil
do
	local m = Shared:FindFirstChild("Camo")
	if m then
		local ok, mod = pcall(require, m)
		Camo = if ok and type(mod) == "table" then mod else nil
	end
end

local player = Players.LocalPlayer
local hotbarEquip = script.Parent:WaitForChild("GunClient"):WaitForChild("HotbarEquip")

local IDLE_STROKE = 0.86
local IDLE_BACK = 0.35
local EMPTY_BACK = 0.6

local function camoFor(gunKey)
	local raw = player:GetAttribute("Camos")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, map = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(map) == "table" then map[gunKey] else nil
end

-- Frames a model side-on in a ViewportFrame, pointing right.
local function showModel(viewport, source, gunKey)
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
	if gunKey and Camo and Camo.Apply then
		pcall(Camo.Apply, model, gunKey, camoFor(gunKey))
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
		local worldGuns = Assets:FindFirstChild("WorldGuns")
		return (worldGuns and worldGuns:FindFirstChild(item)) or Assets.ViewModels:FindFirstChild(gun.ViewModel)
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
	if not slot or not slot.Stroke then
		return
	end
	slot.Stroke.Color = Color3.fromRGB(230, 70, 60)
	slot.Stroke.Transparency = 0.1
	task.delay(0.25, function()
		slot.Stroke.Color = Color3.new(1, 1, 1)
		slot.Stroke.Transparency = IDLE_STROKE
	end)
end

-- The inventory slot holding bandages (whether or not it has a button).
local function bandageIndex()
	for i, content in readInventory() do
		if content and content.Item == "Bandage" then
			return i
		end
	end
	return nil
end

local function useBandage()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local index = bandageIndex()
	local slot = index and slots[index]
	local hurt = humanoid and (humanoid.Health < humanoid.MaxHealth or (character:GetAttribute("Trauma") or 0) > 0)
	if not index or not hurt or character:GetAttribute("Bandaging") or character:GetAttribute("Downed") then
		flash(slot or slots[GameConfig.Inventory.BandageSlot or 1] or slots[1])
		return
	end
	Remotes.Bandage:FireServer()
end

local function pick(index)
	if not index then
		return
	end
	local content = readInventory()[index]
	local item = content and content.Item or nil
	if not item then
		flash(slots[index])
	elseif GameConfig.Guns[item] then
		-- Picking a gun puts a half-done bandage away (it isn't used up).
		local character = player.Character
		if character and character:GetAttribute("Bandaging") then
			Remotes.Bandage:FireServer("Cancel")
		end
		hotbarEquip:Fire(item)
	elseif item == "Bandage" then
		useBandage()
	end
end

local seenSpawn = player:GetAttribute("SpawnId")
local ready = false -- the first redraw after binding never equips
local lastGuns = {} -- [gun] = true for the guns carried at the last refresh

-- Redraws the slots from the inventory; equips a gun that just came in on its own (a pickup), or a carried gun if
-- the one in hand is gone (it was swapped away). The first change of a new life (SpawnId) equips nothing.
local function refresh()
	local inventory = readInventory()
	local spawnId = player:GetAttribute("SpawnId")
	local fresh = spawnId ~= seenSpawn
	seenSpawn = spawnId

	local guns, arrived, firstGun = {}, {}, nil
	for _, content in inventory do
		if content and GameConfig.Guns[content.Item] then
			guns[content.Item] = true
			firstGun = firstGun or content.Item
			if not lastGuns[content.Item] then
				table.insert(arrived, content.Item)
			end
		end
	end
	lastGuns = guns

	for i, slot in slots do
		local content = inventory[i]
		local item = content and content.Item or nil
		if item ~= slot.Item then
			slot.Item = item
			task.defer(showModel, slot.Button.Icon, item and iconSource(item), item and GameConfig.Guns[item] and item or nil)
		end
		slot.Button.Count.Text = if content and (content.Count > 1 or item == "Bandage") then "x" .. content.Count else ""
		slot.Button.BackgroundTransparency = if item then IDLE_BACK else EMPTY_BACK
	end

	local character = player.Character
	if fresh or not ready or (character and character:GetAttribute("Downed")) then
		ready = true
		return
	end
	local equipped = player:GetAttribute("EquippedGun")
	-- A pickup brings exactly one gun; a whole new set is a respawn and equips nothing.
	if #arrived == 1 then
		hotbarEquip:Fire(arrived[1])
	elseif firstGun and equipped and not guns[equipped] then
		hotbarEquip:Fire(firstGun)
	end
end

-- Camo changed: redraw the gun icons.
player:GetAttributeChangedSignal("Camos"):Connect(function()
	for _, slot in slots do
		if slot.Item and GameConfig.Guns[slot.Item] then
			task.defer(showModel, slot.Button.Icon, iconSource(slot.Item), slot.Item)
		end
	end
end)

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

local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
ContextActionService:BindAction("HotbarSlot", function(_, inputState, input)
	if inputState == Enum.UserInputState.Begin then
		pick(table.find(KEYS, input.KeyCode))
	end
	return Enum.ContextActionResult.Sink
end, false, table.unpack(KEYS))
ContextActionService:BindAction("Bandage", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		useBandage()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.DPadDown)

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
			if slot.Stroke and slot.Stroke.Color == Color3.new(1, 1, 1) then
				slot.Stroke.Transparency = if selected then 0.55 else IDLE_STROKE
			end
			button.Fill.Size = UDim2.fromScale(1, 0)
		end
	end
end)
