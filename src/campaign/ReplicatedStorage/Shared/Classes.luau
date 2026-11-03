-- Class perks (GameConfig.Classes): the multiplier a player's class puts on one thing, 1 when it
-- leaves it alone. The class is the player attribute Class (Profile; picked and bought through
-- StoreServer), Classes.Default when there is none. Works on the server and on clients.

local GameConfig = require(script.Parent.GameConfig)

local CFG = GameConfig.Classes

local Classes = {}

function Classes.Of(player)
	local name = player:GetAttribute("Class")
	return if name and CFG.List[name] then name else CFG.Default
end

function Classes.Perk(player, key)
	return CFG.List[Classes.Of(player)].Perks[key] or 1
end

return Classes
