-- Class perks: the multiplier a player's class puts on one thing, 1 when it leaves it alone.
-- The eight classes and their perks live in Shared.Progression.Classes (DATA, 2 Nov 2026; menu contract
-- section 2); GameConfig.Classes is the fallback when that module is missing (an older place copy).
-- The class is the player attribute Class (Profile; picked in the loadout through StoreServer "Class"),
-- Classes.Default when there is none or it is not a known class. Works on the server and on clients.

local GameConfig = require(script.Parent.GameConfig)

local CFG = GameConfig.Classes
local LIST = CFG.List
local progression = script.Parent:FindFirstChild("Progression") or script.Parent:WaitForChild("Progression", 5)
if progression then
	local ok, P = pcall(require, progression)
	if ok and type(P) == "table" and type(P.Classes) == "table" then
		LIST = P.Classes
	end
end

local Classes = {}
Classes.Default = if LIST[CFG.Default] then CFG.Default else "Rifleman"
Classes.List = LIST

function Classes.Of(player)
	local name = player and player:GetAttribute("Class")
	return if name and LIST[name] then name else Classes.Default
end

function Classes.Perk(player, key)
	local class = LIST[Classes.Of(player)]
	return class and class.Perks and class.Perks[key] or 1
end

return Classes
