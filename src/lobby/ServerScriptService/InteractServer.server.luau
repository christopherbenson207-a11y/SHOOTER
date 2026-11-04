-- Things you press E on: doors (ServerStorage.Modules.Doors) and pickups on the ground.
-- A pickup is a model tagged "Pickup" with Kind "Ammo", "Bandage" or "Gun" (templates in
-- ServerStorage.Pickups; gun pickups are made from the gun models). Bandages and guns go in
-- the inventory (ServerStorage.Modules.Inventory); ammo refills the guns you carry. A gun or
-- bandage taken with no free slot swaps with the gun in your hands, which drops with its ammo.
-- Placed pickups come back after a while; zombies sometimes drop ammo when they die. The
-- outline is drawn on each client (StarterPlayerScripts.Pickups).
-- A pickup with a Cost attribute is a shop stand (the Defend match): it costs that many points
-- (a gun you already carry refills its ammo for Match.AmmoShare of it) and never runs out.
-- A pickup with an Owner attribute (a UserId, the mystery crate's offer) is only for them.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Doors = require(ServerStorage.Modules.Doors)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Inventory = require(ServerStorage.Modules.Inventory)
local Points = require(ServerStorage.Modules.Points)
local Remotes = ReplicatedStorage.Remotes

local Settings = GameConfig.Pickups
local Templates = ServerStorage.Pickups
local GunsApi = ServerStorage:WaitForChild("GunsApi")
local ViewModels = ReplicatedStorage.Assets.ViewModels
-- Pickups use the same world model as the gun in a character's hands (Assets.WorldGuns, made at world size).
-- A gun without one falls back to its viewmodel, scaled to its GameConfig WorldLength.
local WorldGuns = ReplicatedStorage.Assets:FindFirstChild("WorldGuns")

-- Viewmodels are made for the first-person view; on the ground each is scaled to this
-- length in studs (the visible parts, muzzle to stock).
local GUN_LENGTH = { Pistol = 1.3, Shotgun = 3.3, AK = 3.1, Sniper = 3.7 }

local Camo = nil
do
	local m = ReplicatedStorage.Shared:FindFirstChild("Camo")
	if m then
		local ok, mod = pcall(require, m)
		Camo = if ok and type(mod) == "table" and mod.Apply then mod else nil
	end
end

local function visibleLength(model)
	local pivot = model:GetPivot()
	local lo, hi = math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			local half = d.Size / 2
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						local p = pivot:PointToObjectSpace(d.CFrame:PointToWorldSpace(half * Vector3.new(x, y, z)))
						lo = math.min(lo, p.Z)
						hi = math.max(hi, p.Z)
					end
				end
			end
		end
	end
	return hi - lo
end

Doors.Start()

local dropFolder = Instance.new("Folder")
dropFolder.Name = "Drops"
dropFolder.Parent = workspace

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.CollisionGroup = "Characters"

-- Lays a model on the ground below position, turned a random way.
local function placeOnGround(model, position, exclude)
	groundParams.FilterDescendantsInstances = { exclude, dropFolder }
	local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -20, 0), groundParams)
	local ground = if hit then hit.Position else position
	model:PivotTo(CFrame.new(ground) * CFrame.Angles(0, math.random() * math.pi * 2, 0) * model:GetPivot().Rotation)
	local cf, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, ground.Y + size.Y / 2 + 0.02 - cf.Y, 0))
end

-- A gun lying on its side, world size, as a pickup model (not yet tagged or parented), in camoId if given.
local function makeGun(gunName, camoId)
	local gun = GameConfig.Guns[gunName]
	local world = gun and WorldGuns and WorldGuns:FindFirstChild(gunName)
	local source = world or (gun and ViewModels:FindFirstChild(gun.ViewModel))
	if not source then
		return nil
	end
	local model = source:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Light")
			or d:IsA("Beam") or d:IsA("JointInstance") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CollisionGroup = "Debris"
		end
	end
	if world then
		for name in model:GetAttributes() do
			model:SetAttribute(name, nil)
		end
	else
		local length = gun.WorldLength or GUN_LENGTH[gunName]
		model:ScaleTo(model:GetScale() * (if length then length / visibleLength(model) else 1))
	end
	if Camo and camoId then
		pcall(Camo.Apply, model, gunName, camoId)
	end
	model:PivotTo(model:GetPivot() * CFrame.Angles(0, 0, math.rad(90)))
	model.Name = gunName
	model:SetAttribute("Kind", "Gun")
	model:SetAttribute("Gun", gunName)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

local function setShown(model, shown)
	model:SetAttribute("Taken", not shown)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("ShownTransparency") == nil then
				d:SetAttribute("ShownTransparency", d.Transparency)
			end
			d.Transparency = if shown then d:GetAttribute("ShownTransparency") else 1
			d.CanQuery = shown
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = shown
		end
	end
end

local function dropGun(gunName, mag, reserve, near, exclude)
	-- A gun someone drops keeps their camo.
	local dropper = exclude and game:GetService("Players"):GetPlayerFromCharacter(exclude)
	local model = makeGun(gunName, Camo and Camo.ForPlayer and dropper and Camo.ForPlayer(dropper, gunName))
	if not model then
		return
	end
	model:SetAttribute("Mag", mag)
	model:SetAttribute("Reserve", reserve)
	placeOnGround(model, near, exclude)
	model.Parent = dropFolder
	CollectionService:AddTag(model, "Pickup")
end

-- No room: frees the slot of the gun in your hands (or the first gun carried) by dropping
-- that gun at your feet with its ammo. Returns the slot, or nil.
local function dropHeld(player)
	local held = GunsApi:Invoke("Current", player)
	local slot = Inventory.IndexOf(player, held)
	if not slot then
		for i, s in Inventory.Slots(player) do
			if s and GameConfig.Guns[s.Item] then
				slot = i
				break
			end
		end
	end
	if not slot then
		return nil
	end
	local old = Inventory.Slots(player)[slot].Item
	local oldMag, oldReserve = GunsApi:Invoke("GetAmmo", player, old)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		dropGun(old, oldMag, oldReserve, root.Position - root.CFrame.RightVector * 2.2 + root.CFrame.LookVector * 0.5, player.Character)
	end
	return slot
end

local function takeGun(model, player)
	local gunName = model:GetAttribute("Gun")
	if not GameConfig.Guns[gunName] then
		return false
	end
	if Inventory.IndexOf(player, gunName) then
		-- Already carried: take its ammo instead. The gun on the floor is used up either way,
		-- so a pickup always leaves the floor when you take it.
		GunsApi:Invoke("GiveAmmo", player)
		return true
	end
	local mag, reserve = model:GetAttribute("Mag"), model:GetAttribute("Reserve")
	local slot = Inventory.FreeSlot(player) or dropHeld(player)
	if not slot then
		return false
	end
	Inventory.Set(player, slot, gunName, 1)
	GunsApi:Invoke("SetAmmo", player, gunName, mag, reserve)
	GunsApi:Invoke("Equip", player, gunName)
	return true
end

-- Gives the pickup to the player. Returns false if they had no use for it.
local function use(model, player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or PlayerHealth.IsDowned(player) then
		return false
	end
	local owner = model:GetAttribute("Owner")
	if owner and owner ~= player.UserId then
		return false
	end
	local kind = model:GetAttribute("Kind")
	if kind == "Ammo" then
		return (GunsApi:Invoke("GiveAmmo", player, model:GetAttribute("Magazines")) or 0) > 0
	elseif kind == "Bandage" then
		if Inventory.Add(player, "Bandage", 1) > 0 then
			return true
		end
		-- A full stack stays full (nothing is taken or charged); with no bandage slot and no
		-- room, it takes the gun's slot.
		if Inventory.IndexOf(player, "Bandage") then
			Remotes.Match:FireClient(player, "Full", "Bandage")
			return false
		end
		local slot = dropHeld(player)
		if not slot then
			return false
		end
		Inventory.Set(player, slot, "Bandage", 1)
		return true
	elseif kind == "Gun" then
		return takeGun(model, player)
	end
	return false
end

local function setup(model)
	local body = model.PrimaryPart
	if not body or body:FindFirstChild("PickupPrompt") then
		return
	end
	local kind = model:GetAttribute("Kind")
	local gun = GameConfig.Guns[model:GetAttribute("Gun") or ""]
	local cost = model:GetAttribute("Cost")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = if cost then "Buy " .. cost else "Take"
	prompt.ObjectText = if gun then gun.DisplayName or model:GetAttribute("Gun") else kind
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = Settings.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	local busy = false
	prompt.Triggered:Connect(function(player)
		if busy or model:GetAttribute("Taken") then
			return
		end
		busy = true
		local price = cost
		if cost and kind == "Gun" and Inventory.IndexOf(player, model:GetAttribute("Gun")) then
			price = math.floor(cost * GameConfig.Match.AmmoShare)
		end
		if price and not Points.CanAfford(player, price) then
			Remotes.Match:FireClient(player, "Broke")
			busy = false
			return
		end
		if use(model, player) then
			if price then
				Points.Spend(player, price)
			end
			SoundKit.Play("Pickup/" .. (if kind == "Gun" then "Ammo" else kind), { Position = body.Position })
			local respawn = model:GetAttribute("Respawn")
			if cost then
				-- A shop stand stays.
			elseif respawn then
				setShown(model, false)
				task.delay(respawn, function()
					if not model.Parent then
						return
					end
					-- A gun comes back somewhere else on the house floors where nothing lies
					-- (MatchServer's FreeSpot), never where it was taken.
					local freeSpot = kind == "Gun" and ServerStorage:FindFirstChild("FreeSpot")
					local at = freeSpot and freeSpot:Invoke(model)
					if typeof(at) == "Vector3" then
						model:PivotTo(CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi * 2, 0) * model:GetPivot().Rotation)
						local cf, size = model:GetBoundingBox()
						model:PivotTo(model:GetPivot() + Vector3.new(0, at.Y + size.Y / 2 + 0.02 - cf.Y, 0))
					end
					setShown(model, true)
				end)
			else
				model:Destroy()
			end
		end
		busy = false
	end)
end

CollectionService:GetInstanceAddedSignal("Pickup"):Connect(setup)
for _, model in CollectionService:GetTagged("Pickup") do
	setup(model)
end

-- Placed guns: markers in workspace tagged "GunSpawn" with a Gun attribute get a gun lying
-- there that comes back after Settings.Gun.Respawn once taken. A marker's Cost and Owner
-- carry over to the gun (a shop stand or a crate offer, which don't respawn); Life makes the
-- gun vanish after that many seconds.
local function spawnGun(marker)
	local model = makeGun(marker:GetAttribute("Gun"))
	if not model then
		return
	end
	local cost, owner, life = marker:GetAttribute("Cost"), marker:GetAttribute("Owner"), marker:GetAttribute("Life")
	model:SetAttribute("Cost", cost)
	model:SetAttribute("Owner", owner)
	if not cost and not owner then
		model:SetAttribute("Respawn", Settings.Gun.Respawn)
	end
	placeOnGround(model, marker.Position, marker)
	model.Parent = marker.Parent
	CollectionService:AddTag(model, "Pickup")
	if life then
		Debris:AddItem(model, life)
	end
end
CollectionService:GetInstanceAddedSignal("GunSpawn"):Connect(spawnGun)
for _, marker in CollectionService:GetTagged("GunSpawn") do
	spawnGun(marker)
end

-- Zombie drops --------------------------------------------------------------------------

local function dropAmmo(position, exclude)
	local box = Templates.AmmoBox:Clone()
	box:SetAttribute("Magazines", Settings.Drop.Magazines)
	placeOnGround(box, position, exclude)
	box.Parent = dropFolder
	CollectionService:AddTag(box, "Pickup")
	Debris:AddItem(box, Settings.Drop.Life)
end

local function watchEnemy(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	humanoid.Died:Once(function()
		local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if root and math.random() < Settings.Drop.Chance then
			dropAmmo(root.Position, model)
		end
	end)
end

CollectionService:GetInstanceAddedSignal("Enemy"):Connect(watchEnemy)
for _, model in CollectionService:GetTagged("Enemy") do
	task.spawn(watchEnemy, model)
end
