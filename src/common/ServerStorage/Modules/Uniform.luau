-- What everyone wears: police SWAT (GameConfig.Match.Uniform) until their first rescue, then
-- the uniform they picked (GameConfig.Attire, saved by Profile). The shirt and pants replace
-- the avatar's own, any graphic T-shirt and layered clothing come off, and the rest of the
-- avatar (body, face, hair, hats) stays. Characters are loaded already dressed, so everything
-- that copies the avatar on spawn (first-person arms) sees the uniform.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Profile = require(script.Parent.Profile)

local CFG = GameConfig.Match.Uniform

local Uniform = {}

local cache = {} -- [userId] = the avatar's description, stripped, without the uniform

-- The shirt and pants this player wears now.
local function outfit(userId)
	local player = Players:GetPlayerByUserId(userId)
	local name = player and Profile.Get(player).Attire
	for _, attire in GameConfig.Attire do
		if attire.Name == name then
			return attire.Shirt, attire.Pants
		end
	end
	return CFG.Shirt, CFG.Pants
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
	description.Shirt, description.Pants = outfit(userId)
	return description
end

-- Spawns the player in uniform (falls back to a plain LoadCharacter).
function Uniform.Load(player)
	local description = Uniform.Description(player.UserId)
	if description then
		local ok = pcall(player.LoadCharacterWithHumanoidDescription, player, description)
		if ok then
			return
		end
	end
	player:LoadCharacter()
end

Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
end)

return Uniform
