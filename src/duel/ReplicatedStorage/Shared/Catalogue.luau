-- Shared.Catalogue (DATA, 2 Nov 2026): every cosmetic item, where it comes from, the Robux products and passes, and
-- the store's daily rotation. Plain data and small pure functions: no instances, no yields, the same on the server
-- and on clients. Contract: horror-shooter/menu/CONTRACTS.md sections 2 and 9; prices from MENU-PLAN 4.9 and 9.8.
--
-- Items: C.Items[itemId], itemId = "<Kind>/<Id>" (for example "Operator/Desert", "Camo/Rust", "Card/Watchtower",
--   "Beam/Gold"). The bare ids of contract section 9 collide across kinds (Desert, Woodland, Arctic, Gold, LastLight),
--   so the kind is part of the id; the item id is also its UiArt key. C.Id(kind, id) builds one.
-- Every item has exactly ONE Source (the loader below errors otherwise):
--   Default                      everyone has it
--   Level {Level}                account level (also listed in Shared.Progression.Rewards)
--   WeaponLevel {Level}          per gun, at that weapon level (camos)
--   Mastery {Rule}               per gun (Headshots100, Elites25), AllGold, or an account feat (NightmareEscape)
--   Pass {Track, Tier}           Night Pass reward (also listed in Shared.Progression.Pass)
--   Store {Scrip}                bought with Scrip (StoreServer "Buy")
--   Robux {Key}                  a game pass in C.Products (Beams, Vip)
--   Starter                      the Starter Pack product
-- Products: C.Products[key] = {Type = "Pass" | "Product", Id, Robux, Name, Art, ...}. Id = 0 means not made yet in
--   Creator Hub: the store hides it and the server never prompts it. Prices on screen come from MarketplaceService
--   once the id is real; Robux here is the planned price.
-- Rotation: C.Rotation(utcDay) -> {Hero, Tiles = {3}}: the hero changes weekly, the tiles daily, from the Store pool,
--   the same on every server. For a player whose Starter Pack deadline has not passed, StoreServer's "Catalogue"
--   action puts "Product/StarterPack" in the hero spot instead.
-- Phase 1.5 (not in the launch catalogue): charms, poses, emotes.

local Progression = require(script.Parent:WaitForChild("Progression"))

local C = {}

function C.Id(kind, id)
	if type(id) ~= "string" then
		return nil
	end
	if string.find(id, "/", 1, true) then
		return id
	end
	return kind .. "/" .. id
end

-- Split "Operator/Desert" into "Operator", "Desert".
function C.Split(itemId)
	local kind, id = string.match(itemId or "", "^(%a+)/(.+)$")
	return kind, id
end

local items = {}
local function item(kind, id, name, source, extra)
	local itemId = kind .. "/" .. id
	assert(not items[itemId], "Shared.Catalogue: item listed twice: " .. itemId)
	local t = { Kind = kind, Id = id, Name = name, Art = itemId, Source = source }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	items[itemId] = t
end
local DEFAULT = { Kind = "Default" }
local function level(n)
	return { Kind = "Level", Level = n }
end
local function store(scrip)
	return { Kind = "Store", Scrip = scrip }
end

-- Operators (Assets.Operators.<Id>) ---------------------------------------------------------------------------------
item("Operator", "Woodland", "WOODLAND", DEFAULT)
item("Operator", "Desert", "DESERT", level(5))
item("Operator", "Arctic", "ARCTIC", level(10))
item("Operator", "SWAT", "SWAT", level(25))
item("Operator", "Ghillie", "GHILLIE", level(40))
item("Operator", "Pathfinder", "PATHFINDER", { Kind = "Starter" })
item("Operator", "Warden", "WARDEN", store(4500))
item("Operator", "Revenant", "REVENANT", store(5000))
item("Operator", "Lamplighter", "LAMPLIGHTER", store(6000))

-- Camos (Shared.Camo.Camos; a weapon-level or mastery camo is per gun, a store or pass camo covers every gun) -------
item("Camo", "Gunmetal", "GUNMETAL", DEFAULT)
item("Camo", "Desert", "DESERT", { Kind = "WeaponLevel", Level = 5 })
item("Camo", "Woodland", "WOODLAND", { Kind = "WeaponLevel", Level = 5 })
item("Camo", "Arctic", "ARCTIC", { Kind = "WeaponLevel", Level = 10 })
item("Camo", "Gold", "GOLD", { Kind = "WeaponLevel", Level = 15 })
item("Camo", "Bone", "BONE", { Kind = "Mastery", Rule = "Headshots100" })
item("Camo", "Night", "NIGHT", { Kind = "Mastery", Rule = "Elites25" })
item("Camo", "LastLight", "LAST LIGHT", { Kind = "Mastery", Rule = "AllGold" })
item("Camo", "Rust", "RUST", store(4000))
item("Camo", "Ash", "ASH", store(4000))

-- Beams (flashlight colours, all the same brightness). Color matches the Beam/<Id> chip art (CHROME components.BEAMS);
-- the flashlight reads C.Items["Beam/" .. player:GetAttribute("Beam")].Color.
local BEAM_RGB = {
	Warm = Color3.fromRGB(255, 236, 206), Cold = Color3.fromRGB(204, 226, 255), Red = Color3.fromRGB(255, 86, 68),
	Green = Color3.fromRGB(118, 255, 140), Amber = Color3.fromRGB(255, 176, 60), Violet = Color3.fromRGB(178, 132, 255),
	Ice = Color3.fromRGB(140, 232, 255), Gold = Color3.fromRGB(255, 204, 84),
}
item("Beam", "Warm", "WARM", DEFAULT, { Color = BEAM_RGB.Warm })
for _, id in { "Cold", "Red", "Green", "Amber", "Violet", "Ice" } do
	item("Beam", id, string.upper(id), { Kind = "Robux", Key = "Beams" }, { Color = BEAM_RGB[id] })
end
item("Beam", "Gold", "GOLD", { Kind = "Robux", Key = "Vip" }, { Color = BEAM_RGB.Gold })

-- Calling cards (512x128) ---------------------------------------------------------------------------------------------
item("Card", "Default", "LAST LIGHT RECRUIT", DEFAULT)
item("Card", "FirstNight", "FIRST NIGHT", { Kind = "Starter" })
item("Card", "Static", "STATIC", store(750))
item("Card", "Ashfall", "ASHFALL", store(750))
item("Card", "Deadlight", "DEADLIGHT", { Kind = "Mastery", Rule = "NightmareEscape" })

-- Level and pass items come from Shared.Progression's tables, so the two lists can never disagree.
local NAMES = {
	LastLight = "LAST LIGHT", Porchlight = "PORCHLIGHT", Crossing = "CROSSING", Evac = "EVAC", Hollow = "HOLLOW",
	Watchtower = "WATCHTOWER", Signalfire = "SIGNALFIRE", Nightshift = "NIGHTSHIFT", Redline = "REDLINE",
	Floodline = "FLOODLINE", Lamplight = "LAMPLIGHT", Drifter = "DRIFTER", Nightjar = "NIGHTJAR", Ember = "EMBER",
	Moth = "MOTH", Signal = "SIGNAL",
}
local COSMETIC = { Operator = true, Card = true, Camo = true, Beam = true }
for lvl = 1, Progression.LevelCap do
	for _, r in Progression.Rewards[lvl] or {} do
		if COSMETIC[r.Kind] and not items[r.Kind .. "/" .. r.Id] then
			item(r.Kind, r.Id, NAMES[r.Id] or string.upper(r.Id), level(lvl))
		end
	end
end
for season, pass in Progression.Seasons do
	for _, track in { "Free", "Premium" } do
		for tier, r in pass[track] do
			if COSMETIC[r.Kind] then
				item(r.Kind, r.Id, NAMES[r.Id] or string.upper(r.Id), { Kind = "Pass", Track = track, Tier = tier, Season = season })
			end
		end
	end
end
C.Items = items

-- Loader checks: exactly one source per item, and level items agree with Shared.Progression.
do
	local KINDS = { Default = true, Level = true, WeaponLevel = true, Mastery = true, Pass = true, Store = true,
		Robux = true, Starter = true, Group = true }
	for itemId, it in items do
		local s = it.Source
		assert(type(s) == "table" and KINDS[s.Kind], "Shared.Catalogue: bad source for " .. itemId)
		if s.Kind == "Level" then
			assert(Progression.UnlockLevel(itemId) == s.Level, "Shared.Catalogue: level mismatch for " .. itemId)
		end
	end
	-- an item rewarded by a level AND by the pass (or listed by hand and also rewarded) would be two sources
	local seen = {}
	for lvl = 1, Progression.LevelCap do
		for _, r in Progression.Rewards[lvl] or {} do
			if COSMETIC[r.Kind] then
				local itemId = r.Kind .. "/" .. r.Id
				assert(not seen[itemId], "Shared.Catalogue: two sources for " .. itemId)
				seen[itemId] = true
				assert(items[itemId].Source.Kind == "Level", "Shared.Catalogue: two sources for " .. itemId)
			end
		end
	end
	for _, pass in Progression.Seasons do
		for _, track in { "Free", "Premium" } do
			for _, r in pass[track] do
				if COSMETIC[r.Kind] then
					local itemId = r.Kind .. "/" .. r.Id
					assert(not seen[itemId], "Shared.Catalogue: two sources for " .. itemId)
					seen[itemId] = true
					assert(items[itemId].Source.Kind == "Pass", "Shared.Catalogue: two sources for " .. itemId)
				end
			end
		end
	end
end

-- Robux products and game passes (MENU-PLAN 4.9). Id 0 = hidden. ----------------------------------------------------
C.Products = {
	Vip = { Type = "Pass", Id = 2075661062, Robux = 299, Name = "VIP", Art = "Product/Vip", Section = "Passes" },
	DoubleScrip = { Type = "Pass", Id = 2075937113, Robux = 399, Name = "DOUBLE SCRIP", Art = "Product/DoubleScrip", Section = "Passes" },
	Beams = { Type = "Pass", Id = 2074977093, Robux = 149, Name = "FLASHLIGHT COLOURS", Art = "Product/Beams", Section = "Passes" },
	-- K9 partner dog for every Outbreak run (4 Nov 2026: sold here in the store, no longer on the downed screen).
	-- Until this Id is set the zombies place falls back to GameConfig.Store.K9.Pass.
	K9 = { Type = "Pass", Id = 2075421085, Robux = 299, Name = "K9 PARTNER", Art = "Product/K9", Section = "Passes" },
	PassPremium = { Type = "Product", Id = 3729096803, Robux = 399, Name = "NIGHT PASS", Art = "Product/PassPremium", Section = "Pass",
		Duplicate = 4800 },
	PassPremium10 = { Type = "Product", Id = 3729096822, Robux = 599, Name = "NIGHT PASS + 10 TIERS", Art = "Product/PassPremium10",
		Section = "Pass", Tiers = 10, Duplicate = 4800 },
	PassTiers5 = { Type = "Product", Id = 3729096839, Robux = 149, Name = "+5 TIERS", Art = "Product/PassTiers5", Section = "Pass",
		Tiers = 5, MinLeft = 5 },
	PassTier1 = { Type = "Product", Id = 3729096939, Robux = 35, Name = "+1 TIER", Art = "Product/PassTier1", Section = "Pass", Tiers = 1 },
	StarterPack = { Type = "Product", Id = 3729096959, Robux = 99, Name = "STARTER PACK", Art = "Product/StarterPack", Section = "Featured",
		Scrip = 2500, Tokens = 3, Items = { "Operator/Pathfinder", "Card/FirstNight" }, Duplicate = 1000, Hours = 48 },
	Scrip1 = { Type = "Product", Id = 3729096474, Robux = 99, Name = "1,000 SCRIP", Art = "Product/Scrip1", Section = "Scrip", Scrip = 1000 },
	Scrip2 = { Type = "Product", Id = 3729096574, Robux = 249, Name = "2,750 SCRIP", Art = "Product/Scrip2", Section = "Scrip", Scrip = 2750 },
	Scrip3 = { Type = "Product", Id = 3729096590, Robux = 499, Name = "6,000 SCRIP", Art = "Product/Scrip3", Section = "Scrip", Scrip = 6000 },
	Scrip4 = { Type = "Product", Id = 3729096609, Robux = 999, Name = "13,000 SCRIP", Art = "Product/Scrip4", Section = "Scrip", Scrip = 13000 },
	Revive = { Type = "Product", Id = 3729096682, Robux = 25, Name = "REVIVE", Art = "Product/Revive", Section = "Extras", Tokens = 1 },
	Revive5 = { Type = "Product", Id = 3729096704, Robux = 99, Name = "5 REVIVE TOKENS", Art = "Product/Revive5", Section = "Extras", Tokens = 5 },
	SquadBoost = { Type = "Product", Id = 3729096719, Robux = 79, Name = "SQUAD BOOST", Art = "Product/SquadBoost", Section = "Extras", Boosts = 1 },
	-- Bundles (4 Nov 2026, field shop): fixed contents, no randomness. An item already owned is paid back as Scrip at its
	-- store price inside the same grant. "Worth" text is C.BundleWorth(key), never typed by hand.
	CamoBundle = { Type = "Product", Id = 3729098089, Robux = 399, Name = "CAMO BUNDLE", Art = "Camo/Rust", Section = "Bundles",
		Bundle = true, Items = { "Camo/Rust", "Camo/Ash" }, Scrip = 1000 },
	SpecialistBundle = { Type = "Product", Id = 3729098111, Robux = 799, Name = "SPECIALIST BUNDLE", Art = "Operator/Warden",
		Section = "Bundles", Bundle = true, Items = { "Operator/Warden", "Operator/Revenant", "Operator/Lamplighter" }, Scrip = 0 },
}
C.ScripPacks = { "Scrip1", "Scrip2", "Scrip3", "Scrip4" }

-- Every Scrip store item can also be bought straight with Robux (4 Nov 2026: "pay or grind"): one developer product per
-- item, key "Item_<Kind><Id>" (e.g. Item_CamoRust), Section "Items" (shown on the item itself, not as a tile).
-- Price ladder by Scrip price; a direct buy is a little cheaper than the Scrip it would take from packs, so paying is
-- fair and grinding still reaches everything. One per player: the server refuses the prompt when you own the item.
C.ItemRobux = { [750] = 75, [4000] = 299, [4500] = 349, [5000] = 399, [6000] = 449 }
C.ItemProduct = {} -- itemId -> product key
for itemId, it in items do
	if it.Source.Kind == "Store" then
		local robux = C.ItemRobux[it.Source.Scrip]
		assert(robux, "Shared.Catalogue: no Robux price on the ladder for " .. itemId .. " (" .. it.Source.Scrip .. " Scrip)")
		local key = "Item_" .. it.Kind .. it.Id
		assert(not C.Products[key], "Shared.Catalogue: product key used twice: " .. key)
		C.Products[key] = { Type = "Product", Id = 0, Robux = robux, Name = it.Name .. " " .. string.upper(it.Kind),
			Art = itemId, Section = "Items", Item = itemId }
		C.ItemProduct[itemId] = key
	end
end
-- Product ids for the direct buys, set once they exist in Creator Hub (key -> id). Kept apart from the generated table
-- so pasting ids is one line each.
C.ItemProductIds = {
	Item_CamoRust = 3729098136, Item_CamoAsh = 3729098243, Item_CardStatic = 3729098278, Item_CardAshfall = 3729098294,
	Item_OperatorWarden = 3729098374, Item_OperatorRevenant = 3729098389, Item_OperatorLamplighter = 3729098408,
}
for key, id in C.ItemProductIds do
	assert(C.Products[key], "Shared.Catalogue: ItemProductIds names an unknown product " .. key)
	C.Products[key].Id = id
end

-- Free bonuses.
C.GroupId = 0 -- the game's Roblox group; 0 = no group reward yet
C.GroupScrip = 500
C.PremiumScrip = 1.1 -- Roblox Premium members' Scrip multiplier (Profile.Earn)

-- Every multiplier on match Scrip (Profile.Earn), capped at x4 together.
C.Multipliers = { Vip = 1.2, DoubleScrip = 2, Boost = 1.5, Premium = 1.1, Cap = 4 }

local BY_PRODUCT = {}
for key, p in C.Products do
	p.Key = key
	if p.Id ~= 0 then
		assert(not BY_PRODUCT[p.Id], "Shared.Catalogue: product id used twice: " .. key)
		BY_PRODUCT[p.Id] = key
	end
end

-- Bundle checks: every item is a real store item.
for key, p in C.Products do
	if p.Bundle then
		assert(type(p.Items) == "table" and #p.Items > 0, "Shared.Catalogue: empty bundle " .. key)
		for _, itemId in p.Items do
			assert(items[itemId] and items[itemId].Source.Kind == "Store", "Shared.Catalogue: bundle item not sold for Scrip: " .. itemId)
		end
	end
end

-- What a bundle is worth in Scrip: its items at store price plus its Scrip. The same for every player, because an item
-- already owned is paid back at its store price.
function C.BundleWorth(key)
	local p = C.Products[key]
	if not (p and p.Bundle) then
		return 0
	end
	local total = p.Scrip or 0
	for _, itemId in p.Items do
		local price = items[itemId].Source.Scrip
		total += price
	end
	return total
end

-- The product key for a Roblox product or pass id (nil if unknown or 0).
function C.ProductKey(id)
	return BY_PRODUCT[id]
end

-- Whether a product is on sale (its id has been set).
function C.Live(key)
	local p = C.Products[key]
	return p ~= nil and p.Id ~= 0
end

-- The smallest live Scrip pack that covers `short` Scrip (or the biggest live one); nil while none is live.
function C.PackFor(short)
	local best = nil
	for _, key in C.ScripPacks do
		local p = C.Products[key]
		if p.Id ~= 0 then
			best = key
			if p.Scrip >= short then
				return key
			end
		end
	end
	return best
end

-- Store pool and rotation --------------------------------------------------------------------------------------------

local POOL, HEROES = {}, {}
for itemId, it in items do
	if it.Source.Kind == "Store" then
		table.insert(POOL, itemId)
		if it.Kind == "Operator" then
			table.insert(HEROES, itemId)
		end
	end
end
table.sort(POOL)
table.sort(HEROES)
C.Pool = POOL

-- The Scrip price of an item, nil if it is not sold for Scrip.
function C.Price(itemId)
	local it = items[itemId]
	return it and it.Source.Kind == "Store" and it.Source.Scrip or nil
end

-- Today's FEATURED: the hero (weekly, a store operator) and three tiles (daily, the rest of the pool).
function C.Rotation(utcDay)
	utcDay = math.floor(tonumber(utcDay) or Progression.Day())
	local week = Progression.Week(utcDay * 86400)
	local hero = HEROES[Progression.Hash(week, 7) % #HEROES + 1]
	local rest = {}
	for _, itemId in POOL do
		if itemId ~= hero then
			table.insert(rest, itemId)
		end
	end
	for i = #rest, 2, -1 do
		local j = Progression.Hash(utcDay, 200 + i) % i + 1
		rest[i], rest[j] = rest[j], rest[i]
	end
	return { Hero = hero, Tiles = { rest[1], rest[2], rest[3] }, Day = utcDay }
end

-- Availability -------------------------------------------------------------------------------------------------------
-- Whether a player may equip an item. ctx = {Level, Owned (set), GunXp (gun -> xp), GunStats (gun -> {K, H, E}),
-- Stats, Beams = bool, Vip = bool, Gun = gunKey (for per-gun camos)}. Returns ok, reason ("Locked" | "Unknown").
function C.Available(itemId, ctx)
	local it = items[itemId]
	if not it then
		return false, "Unknown"
	end
	ctx = ctx or {}
	local owned = ctx.Owned or {}
	local s = it.Source
	if s.Kind == "Default" then
		return true
	elseif owned[itemId] then
		return true
	elseif s.Kind == "Level" then
		return (tonumber(ctx.Level) or 1) >= s.Level, "Locked"
	elseif s.Kind == "WeaponLevel" then
		local gun = ctx.Gun
		local lvl = gun and Progression.WeaponFromXp((ctx.GunXp or {})[gun]) or 0
		return lvl >= s.Level, "Locked"
	elseif s.Kind == "Mastery" then
		local gun = ctx.Gun
		local gs = gun and (ctx.GunStats or {})[gun] or {}
		if s.Rule == "Headshots100" then
			return (gs.H or 0) >= 100, "Locked"
		elseif s.Rule == "Elites25" then
			return (gs.E or 0) >= 25, "Locked"
		elseif s.Rule == "AllGold" then
			for _, g in Progression.Guns do
				if Progression.WeaponFromXp((ctx.GunXp or {})[g]) < Progression.Weapon.Cap then
					return false, "Locked"
				end
			end
			return true
		elseif s.Rule == "NightmareEscape" then
			return ((ctx.Stats or {}).NightmareEscapes or 0) >= 1, "Locked"
		end
		return false, "Locked"
	elseif s.Kind == "Robux" then
		if s.Key == "Beams" then
			return ctx.Beams == true, "Locked"
		elseif s.Key == "Vip" then
			return ctx.Vip == true, "Locked"
		end
		return false, "Locked"
	end
	-- Pass, Store, Starter, Group: granted into Owned
	return false, "Locked"
end

return C
