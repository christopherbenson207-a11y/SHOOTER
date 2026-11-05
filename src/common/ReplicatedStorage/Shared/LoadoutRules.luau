-- Loadout rules (GUNS, CONTRACTS.md section 2). Which item may go in which loadout slot, and the clean-up that turns
-- any saved loadout into one that is safe to spawn with. Plain tables and pure functions: no instances, no yields.
-- Guns come from GameConfig.Guns (Slot, Level) and count only once registered in GameConfig.Arsenal; gear comes from
-- Shared.Gear (MATCH) when it exists; classes and unlock levels from Shared.Progression (DATA) when it exists.

local Shared = script.Parent
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local R = {}

R.Default = { Class = "Rifleman", Primary = "AK", Secondary = "Pistol", Lethal = "Frag", Tactical = "Flare" }
-- The first match ever: the tested pistol-only kit (MENU-PLAN 9.4). Its AAR reveals the loadout.
R.FirstMatch = { Class = "Rifleman", Primary = nil, Secondary = "Pistol", Lethal = nil, Tactical = nil }
R.Slots = { "Class", "Primary", "Secondary", "Lethal", "Tactical" }

-- Gear while Shared.Gear is missing (MENU-PLAN 4.6).
local GEAR_FALLBACK = {
	Frag = { Slot = "Lethal", Level = 1 },
	Molotov = { Slot = "Lethal", Level = 8 },
	Flare = { Slot = "Tactical", Level = 1 },
	Flashbang = { Slot = "Tactical", Level = 11 },
	Stim = { Slot = "Tactical", Level = 3 },
}

local cache = {}
local function optional(name)
	if cache[name] == nil then
		local m = Shared:FindFirstChild(name)
		local ok, mod = false, nil
		if m and m:IsA("ModuleScript") then
			ok, mod = pcall(require, m)
		end
		cache[name] = if ok and type(mod) == "table" then mod else false
	end
	return cache[name] or nil
end

local function registered(gun)
	return GameConfig.Guns[gun] ~= nil and table.find(GameConfig.Arsenal or GameConfig.Loadout or {}, gun) ~= nil
end

-- The slot an item belongs in and the level that unlocks it, or nil for an unknown item.
function R.ItemInfo(item)
	if type(item) ~= "string" then
		return nil
	end
	local P = optional("Progression")
	local gun = GameConfig.Guns[item]
	if gun then
		if not registered(item) then
			return nil
		end
		local level = (P and P.UnlockLevel and P.UnlockLevel(item)) or gun.Level or 1
		return gun.Slot, level
	end
	local G = optional("Gear")
	local gear = (G and G.Items and G.Items[item]) or GEAR_FALLBACK[item]
	if gear and (gear.Slot == "Lethal" or gear.Slot == "Tactical") then
		local level = (P and P.UnlockLevel and P.UnlockLevel(item)) or gear.Level or 1
		return gear.Slot, level
	end
	return nil
end

-- ok, reason ("Locked" | "WrongSlot" | "Unknown"). stats = the profile's Stats, owned = its Owned set.
function R.CanEquip(slot, item, level, stats, owned)
	level = tonumber(level) or 1
	if type(item) ~= "string" or not table.find(R.Slots, slot) then
		return false, "Unknown"
	end
	if slot == "Class" then
		local P = optional("Progression")
		if P and P.Classes then
			if not P.Classes[item] then
				return false, "Unknown"
			end
			if P.ClassUnlocked(item, level, stats, owned) then
				return true
			end
			return false, "Locked"
		end
		local list = GameConfig.Classes and GameConfig.Classes.List
		if list and list[item] then
			return true
		end
		return item == R.Default.Class, "Unknown"
	end
	local itemSlot, need = R.ItemInfo(item)
	if not itemSlot then
		return false, "Unknown"
	end
	if itemSlot ~= slot then
		return false, "WrongSlot"
	end
	if level < need then
		return false, "Locked"
	end
	return true
end

-- A copy of the loadout where every invalid or missing part is the Default's.
function R.Clean(loadout, level, stats, owned)
	if type(loadout) ~= "table" then
		loadout = {}
	end
	local out = {}
	for _, slot in R.Slots do
		local item = loadout[slot]
		out[slot] = if R.CanEquip(slot, item, level, stats, owned) then item else R.Default[slot]
	end
	return out
end

return R
