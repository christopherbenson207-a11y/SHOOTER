-- The kit a player spawns with (GUNS, CONTRACTS.md section 3; replaces CORE's stub). Inventory.reset and
-- GunServer.onCharacter both call Resolve on every spawn, so the gun in your hands never depends on which
-- CharacterAdded handler runs first. Never yields.
--   Resolve(player) -> {Class, Primary, Secondary, Lethal, Tactical, Field}
--     The selected loadout from the profile, cleaned by Shared.LoadoutRules (anything locked, unknown or in the
--     wrong slot falls back to the default kit). The first match ever is LoadoutRules.FirstMatch (pistol only).
--     Without a profile (not loaded, or the save failed) it uses the player's Kit attribute, else FirstMatch.
--   GearCount(kit, slot) -> how many of the kit's Lethal or Tactical item a life starts with.
--   IsFirstMatch(player) -> bool

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared:WaitForChild("LoadoutRules"))

local Kit = {}

local function optional(parent, name)
	local m = parent:FindFirstChild(name)
	if not (m and m:IsA("ModuleScript")) then
		return nil
	end
	local ok, mod = pcall(require, m)
	return if ok and type(mod) == "table" then mod else nil
end

local Profile = optional(script.Parent, "Profile")
local P = optional(Shared, "Progression")

-- Gear counts while Shared.Gear is missing (MENU-PLAN 4.6).
local GEAR_COUNT = { Frag = 1, Molotov = 1, Flare = 2, Flashbang = 2, Stim = 1 }

local function levelOf(data)
	if P and P.FromXp and data.Xp then
		return (P.FromXp(data.Xp))
	end
	return tonumber(data.Level) or 1
end

local function matchesPlayed(data)
	local stats = type(data.Stats) == "table" and data.Stats or {}
	return math.max(tonumber(stats.Matches) or 0, tonumber(data.Matches) or 0)
end

local function field(class)
	local c = P and P.Classes and P.Classes[class]
	return c and c.Field or nil
end

local function withField(kit)
	kit.Field = field(kit.Class)
	return kit
end

function Kit.IsFirstMatch(player)
	local data = Profile and Profile.Get and Profile.Get(player)
	if not data then
		return player:GetAttribute("Kit") == nil
	end
	return matchesPlayed(data) == 0
end

function Kit.Resolve(player)
	local data = Profile and Profile.Get and Profile.Get(player)
	if data then
		if matchesPlayed(data) == 0 then
			return withField(table.clone(Rules.FirstMatch))
		end
		local loadouts = type(data.Loadouts) == "table" and data.Loadouts or {}
		local selected = loadouts[tonumber(data.Selected) or 1] or loadouts[1]
		return withField(Rules.Clean(selected, levelOf(data), data.Stats, data.Owned))
	end
	-- No profile: the resolved kit DATA last published, cleaned at level 1 so nothing locked slips in.
	local raw = player:GetAttribute("Kit")
	if type(raw) == "string" then
		local ok, kit = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(kit) == "table" then
			return withField(Rules.Clean(kit, tonumber(player:GetAttribute("Level")) or 1, nil, nil))
		end
	end
	return withField(table.clone(Rules.FirstMatch))
end

function Kit.GearCount(kit, slot)
	local key = kit and kit[slot]
	if not key then
		return 0
	end
	local G = optional(Shared, "Gear")
	local item = G and G.Items and G.Items[key]
	local n = (item and item.Count) or GEAR_COUNT[key] or 1
	if slot == "Lethal" then
		local c = P and P.Classes and P.Classes[kit.Class]
		local extra = c and c.Perks and c.Perks.LethalCount
		if extra then
			n = math.max(n, extra)
		end
	end
	return n
end

return Kit
