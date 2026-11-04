-- What everyone wears (menu revamp 3 Nov 2026, MENU-PLAN 9.8). A player with an operator (the player attribute
-- Operator that DATA publishes, else the profile's Operator) spawns as that operator: Assets.Operators.<Id> gives the
-- shirt and pants (its ShirtTemplate / PantsTemplate, tinted by its ClothingTint) and its kit (the clean copies in
-- its Accessories folder: helmet, plate carrier, belt, pouches...). The avatar's own hats and hair come off so the
-- helmet sits right; body, face and skin stay the player's own. A profile without an operator (not migrated yet)
-- keeps the old path: police SWAT (GameConfig.Match.Uniform) until the first rescue, then the picked GameConfig.Attire.
-- Graphic T-shirts and layered clothing always come off. Characters are loaded already dressed, so everything that
-- copies the avatar on spawn (first-person arms) sees the uniform.
--   Uniform.Description(userId) -> the player's description in uniform (nil if Roblox wouldn't give one)
--   Uniform.Load(player)        -> spawns the player dressed
--   Uniform.OperatorOf(player)  -> the operator id they wear, or nil (old Attire path)
--   Uniform.Dress(character, operatorId) -> puts an operator's clothes and kit on a character already spawned

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Profile = require(script.Parent.Profile)

local CFG = GameConfig.Match.Uniform

local Uniform = {}

local cache = {} -- [userId] = the avatar's description, stripped, without the uniform

local function operators()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Operators")
end

function Uniform.OperatorOf(player)
	if not player then
		return nil
	end
	-- DATA publishes the equipped operator as the attribute (a bare id); the profile field is the fallback.
	local id = player:GetAttribute("Operator")
	if type(id) ~= "string" then
		local data = Profile.Get(player)
		id = type(data) == "table" and data.Operator or nil
	end
	local folder = operators()
	if type(id) == "string" and folder and folder:FindFirstChild(id) then
		return id
	end
	return nil
end

-- The shirt and pants catalogue ids this player wears now, and the operator (nil on the old Attire path).
local function outfit(player)
	local id = Uniform.OperatorOf(player)
	if id then
		local op = operators()[id]
		local shirt, pants = op:GetAttribute("ShirtId"), op:GetAttribute("PantsId")
		-- An operator without catalogue ids is dressed from its templates after spawn (Dress).
		return tonumber(shirt) or CFG.Shirt, tonumber(pants) or CFG.Pants, id
	end
	local data = player and Profile.Get(player)
	local name = type(data) == "table" and data.Attire or nil
	for _, attire in GameConfig.Attire do
		if attire.Name == name then
			return attire.Shirt, attire.Pants, nil
		end
	end
	return CFG.Shirt, CFG.Pants, nil
end

local function isHatOrHair(accessory)
	local t = accessory.AccessoryType
	return t == Enum.AccessoryType.Hat or t == Enum.AccessoryType.Hair
end

-- The player's own description with their uniform on (nil if Roblox wouldn't give one).
function Uniform.Description(userId)
	local base = cache[userId]
	if not base then
		local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
		if not ok or not description then
			warn("Uniform: no avatar description for", userId, description)
			return nil
		end
		description.GraphicTShirt = 0
		local kept = {}
		for _, accessory in description:GetAccessories(true) do
			if not accessory.IsLayered then
				table.insert(kept, accessory)
			end
		end
		description:SetAccessories(kept, true)
		cache[userId] = description
		base = description
	end
	local description = base:Clone()
	local shirt, pants, operatorId = outfit(Players:GetPlayerByUserId(userId))
	description.Shirt, description.Pants = shirt, pants
	if operatorId then
		-- The operator's helmet replaces the avatar's hats and hair.
		description.HatAccessory = ""
		description.HairAccessory = ""
		local kept = {}
		for _, accessory in description:GetAccessories(true) do
			if not isHatOrHair(accessory) then
				table.insert(kept, accessory)
			end
		end
		description:SetAccessories(kept, true)
	end
	return description
end

local function clothing(character, className, template, tint)
	if type(template) ~= "string" or template == "" then
		return
	end
	local item = character:FindFirstChildOfClass(className)
	if not item then
		item = Instance.new(className)
		item.Name = className
		item.Parent = character
	end
	if className == "Shirt" then
		item.ShirtTemplate = template
	else
		item.PantsTemplate = template
	end
	item.Color3 = tint
end

-- Puts an accessory on by its attachment, the way Humanoid:AddAccessory does, but with the whole piece moved first
-- (the kit is several welded parts) and a plain Weld, so it also holds in Studio's edit preview.
local function wear(character, humanoid, accessory)
	local handle = accessory:FindFirstChild("Handle")
	local handleAtt = handle and handle:FindFirstChildWhichIsA("Attachment")
	local bodyAtt = nil
	if handleAtt then
		-- Only the body's own attachments (an avatar accessory's handle has the same names).
		for _, part in character:GetChildren() do
			local a = part:IsA("BasePart") and part:FindFirstChild(handleAtt.Name)
			if a and a:IsA("Attachment") then
				bodyAtt = a
				break
			end
		end
	end
	if not bodyAtt then
		pcall(humanoid.AddAccessory, humanoid, accessory)
		return
	end
	local move = bodyAtt.WorldCFrame * handleAtt.CFrame:Inverse() * handle.CFrame:Inverse()
	for _, d in accessory:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CFrame = move * d.CFrame
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "AccessoryWeld"
	weld.Part0 = handle
	weld.Part1 = bodyAtt.Parent
	weld.C0 = handleAtt.CFrame
	weld.C1 = bodyAtt.CFrame
	weld.Parent = handle
	accessory.Parent = character
end

function Uniform.Dress(character, operatorId)
	local folder = operators()
	local op = folder and operatorId and folder:FindFirstChild(operatorId)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (op and humanoid) then
		return false
	end
	local tint = op:GetAttribute("ClothingTint")
	tint = if typeof(tint) == "Color3" then tint else Color3.new(1, 1, 1)
	local shirt, pants = op:FindFirstChild("ShirtTemplate"), op:FindFirstChild("PantsTemplate")
	clothing(character, "Shirt", shirt and shirt.Value, tint)
	clothing(character, "Pants", pants and pants.Value, tint)
	-- Hats and hair the description could not take off (bundles), and any kit from before, then the operator's kit.
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and (isHatOrHair(child) or child:GetAttribute("OperatorKit")) then
			child:Destroy()
		end
	end
	local kit = op:FindFirstChild("Accessories")
	if kit then
		for _, accessory in kit:GetChildren() do
			if accessory:IsA("Accessory") then
				local copy = accessory:Clone()
				for _, d in copy:GetDescendants() do
					if d:IsA("LuaSourceContainer") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.Massless = true
					end
				end
				copy:SetAttribute("OperatorKit", true)
				wear(character, humanoid, copy)
			end
		end
	end
	character:SetAttribute("Operator", operatorId)
	return true
end

-- Spawns the player in uniform (falls back to a plain LoadCharacter).
function Uniform.Load(player)
	local description = Uniform.Description(player.UserId)
	if description then
		local ok = pcall(player.LoadCharacterWithHumanoidDescription, player, description)
		if ok then
			local operatorId = Uniform.OperatorOf(player)
			if operatorId and player.Character then
				Uniform.Dress(player.Character, operatorId)
			end
			return
		end
	end
	player:LoadCharacter()
	local operatorId = Uniform.OperatorOf(player)
	if operatorId and player.Character then
		Uniform.Dress(player.Character, operatorId)
	end
end

Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
end)

return Uniform
