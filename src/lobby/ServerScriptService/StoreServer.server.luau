-- The store and every menu action that changes the profile (DATA, 2 Nov 2026). Contract:
-- horror-shooter/menu/CONTRACTS.md section 5 (Remotes.Store), items and products in ReplicatedStorage.Shared.Catalogue,
-- unlock rules in Shared.Progression (and Shared.LoadoutRules once GUNS has made it).
--
-- Remotes.Store (a RemoteFunction in the Edit tree): Store:InvokeServer(action, payload) always returns
-- {Ok = bool, Reason = string?, ...}. Everything is checked here; the client is never trusted.
--   Loadout {Index, Slot, Item}   Select {Index}              Operator / Beam / Card / Pose {Id}
--   Camo / Charm {Gun, Id}        Buy {ItemId}                Product {Key}
--   PassClaim {Tier, Track} | {All = true}                    Reroll {Index}       Seen {Ids}
--   Aar {}   AarSeen {}   Record {UserId}   Catalogue {}
--   Offers {Moment}   OfferHide {Id}   Want {ItemId}         (the HOME offer strip, ServerStorage.Modules.Offers)
-- Old MenuClient actions still answer until the new front end lands: "Class", name -> "Picked" | "Locked" | "No";
-- "Offer" -> false (the menu never opens the store by itself any more).
--
-- Robux: products and game passes come from Shared.Catalogue.Products; an Id of 0 is hidden and never prompted.
-- ProcessReceipt answers NotProcessedYet unless this server holds the player's profile lock; the grant and the
-- receipt id go out in the same UpdateAsync (Profile.SaveNow), so a receipt is never granted twice or lost.
-- Game passes (Vip, DoubleScrip, Beams) are checked on join and when bought, and published as player attributes.
-- Roblox Premium members get the Premium Scrip bonus (Profile.Earn reads MembershipType; attribute Premium); the
-- group reward pays Catalogue.GroupScrip once to members of Catalogue.GroupId (0 = off).
-- It runs in both places, so a purchase is granted wherever Roblox delivers it.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local P = require(Shared:WaitForChild("Progression"))
local C = require(Shared:WaitForChild("Catalogue"))
local Profile = require(ServerStorage.Modules.Profile)
local Attachments = require(Shared:WaitForChild("Attachments"))
local Crates = nil
do
	local m = ServerStorage:FindFirstChild("Modules") and ServerStorage.Modules:FindFirstChild("Crates")
	local okC, r = pcall(require, m)
	if m and okC and type(r) == "table" then
		Crates = r
	end
end
local Progression = require(ServerStorage.Modules.Progression)
-- the data-driven offer strip on HOME (6 Nov 2026); optional so the store still runs without it
local Offers = nil
do
	local m = ServerStorage.Modules:FindFirstChild("Offers")
	local okO, r = pcall(require, m)
	if m and okO and type(r) == "table" then
		Offers = r
	end
end

local LEGACY = GameConfig.Store

local remote = ReplicatedStorage.Remotes:FindFirstChild("Store")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "Store"
	remote.Parent = ReplicatedStorage.Remotes
end

local function productId(key)
	local p = C.Products[key]
	if not p then
		return 0
	end
	if p.Id ~= 0 then
		return p.Id
	end
	-- ids set in the old GameConfig.Store still count until they move into the catalogue
	if key == "Vip" then
		return LEGACY.Vip.Pass
	elseif key == "StarterPack" then
		return LEGACY.StarterPack.Product
	elseif key == "Revive" then
		return LEGACY.Revive.Product
	elseif key == "K9" then
		return LEGACY.K9 and LEGACY.K9.Pass or 0
	end
	return 0
end

local function keyForId(id)
	local key = C.ProductKey(id)
	if key then
		return key
	end
	for k in C.Products do
		local pid = productId(k)
		if pid ~= 0 and pid == id then
			return k
		end
	end
	return nil
end

local function level(player)
	local data = Profile.Get(player)
	return data and (P.FromXp(data.Xp)) or 1
end

local function ctxFor(player, gun)
	local data = Profile.Get(player)
	return {
		Level = (P.FromXp(data.Xp)),
		Owned = data.Owned,
		GunXp = data.GunXp,
		GunStats = data.GunStats,
		Stats = data.Stats,
		Beams = player:GetAttribute("Beams") == true,
		Vip = player:GetAttribute("Vip") == true,
		Gun = gun,
	}
end

-- Robux grants ---------------------------------------------------------------------------------------------------------

local function addPassXp(player, data, tiers)
	local maxXp = P.PassXpFor(P.Pass.Tiers)
	data.Pass.Xp = math.min(maxXp, data.Pass.Xp + tiers * P.Pass.TierXp)
	Profile.Publish(player, "Pass")
end

local function claimPremiumReached(player, data)
	local reached = P.PassTier(data.Pass.Xp)
	for tier = 1, reached do
		local key = tostring(tier)
		local r = P.Pass.Premium[tier]
		if r and not data.Pass.Claimed.Premium[key] then
			data.Pass.Claimed.Premium[key] = true
			Profile.Reward(player, r, "Pass:Premium:" .. tier)
		end
	end
	Profile.Publish(player, "Pass")
end

-- The premium track of the current season; a second purchase in the same season pays Duplicate Scrip instead.
local function premium(player, data, key)
	if data.Pass.Premium and data.Pass.Season == P.Pass.Season then
		Profile.AddScrip(player, C.Products[key].Duplicate, "Product:" .. key .. ":Duplicate")
	else
		data.Pass.Premium = true
		claimPremiumReached(player, data)
	end
end

local GRANTS = {
	StarterPack = function(player, data)
		local pack = C.Products.StarterPack
		if data.Owned.StarterPack then
			Profile.AddScrip(player, pack.Duplicate, "Product:StarterPack:Duplicate")
			return
		end
		Profile.Grant(player, "StarterPack")
		for _, itemId in pack.Items do
			Profile.Grant(player, itemId)
		end
		Profile.AddScrip(player, pack.Scrip, "Product:StarterPack")
		Profile.Count(player, "Tokens", pack.Tokens)
	end,
	PassPremium = function(player, data)
		premium(player, data, "PassPremium")
	end,
	PassPremium10 = function(player, data)
		addPassXp(player, data, C.Products.PassPremium10.Tiers)
		premium(player, data, "PassPremium10")
	end,
	PassTiers5 = function(player, data)
		addPassXp(player, data, C.Products.PassTiers5.Tiers)
		if data.Pass.Premium then
			claimPremiumReached(player, data)
		end
	end,
	PassTier1 = function(player, data)
		addPassXp(player, data, C.Products.PassTier1.Tiers)
		if data.Pass.Premium then
			claimPremiumReached(player, data)
		end
	end,
	Revive = function(player)
		Profile.Count(player, "Tokens", C.Products.Revive.Tokens)
	end,
	Revive5 = function(player)
		Profile.Count(player, "Tokens", C.Products.Revive5.Tokens)
	end,
	SquadBoost = function(player, data)
		data.Boosts += C.Products.SquadBoost.Boosts
		player:SetAttribute("Boosts", data.Boosts)
	end,
}
for _, key in C.ScripPacks do
	GRANTS[key] = function(player)
		Profile.AddScrip(player, C.Products[key].Scrip, "Product:" .. key)
	end
end
-- timed boosters: minutes on top of what is left (Profile.AddTimed publishes BoostXpUntil / BoostGemsUntil)
for key, p in C.Products do
	if p.Booster then
		GRANTS[key] = function(player)
			Profile.AddTimed(player, p.Booster, p.Minutes * 60)
		end
	end
end

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local key = keyForId(receipt.ProductId)
	local grant = key and GRANTS[key]
	if not player or not grant then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = Profile.WaitFor(player, 15)
	if not data or not Profile.Holds(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not Profile.HasReceipt(player, receipt.PurchaseId) then
		local ok, err = pcall(grant, player, data)
		if not ok then
			warn("StoreServer: grant failed", key, player.Name, err)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		Profile.AddReceipt(player, receipt.PurchaseId)
		if Offers then
			pcall(Offers.Bought, player, data, key)
		end
	end
	-- the grant and the receipt id leave together in one UpdateAsync; if it fails Roblox asks again and the
	-- receipt id (still in the cached profile) keeps the retry from granting twice
	if not Profile.SaveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Game passes, Premium, group --------------------------------------------------------------------------------------------

local PASS_ATTR = { Vip = "Vip", DoubleScrip = "DoubleScrip", Beams = "Beams", K9 = "K9" }
-- K9 shares its attribute with the one-run rental ("Rental"); the pass writes "Pass" like EscapeRun does
local PASS_VALUE = { K9 = "Pass" }

-- Ownership check with retries (1, 2, 4 s). An error never counts as "not owned": after the last failed try the
-- attribute is left unset and the next join (or a purchase) checks again.
local PASS_RETRY = { 1, 2, 4 }
local function ownsPass(player, id)
	for try = 1, #PASS_RETRY + 1 do
		if not player.Parent then
			return nil
		end
		local good, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
		if good then
			return owns == true
		end
		if try <= #PASS_RETRY then
			task.wait(PASS_RETRY[try])
		else
			warn("StoreServer: pass check failed", id, player.Name, owns)
		end
	end
	return nil
end

local function checkPasses(player)
	for key, attr in PASS_ATTR do
		local id = productId(key)
		if id ~= 0 then
			task.spawn(function()
				if ownsPass(player, id) and player.Parent then
					player:SetAttribute(attr, PASS_VALUE[key] or true)
				end
			end)
		end
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	if not bought then
		return
	end
	for key, attr in PASS_ATTR do
		local id = productId(key)
		if id ~= 0 and passId == id then
			player:SetAttribute(attr, PASS_VALUE[key] or true)
			local data = Offers and Profile.Get(player)
			if data then
				pcall(Offers.Bought, player, data, key)
			end
		end
	end
end)

local function checkPremium(player)
	player:SetAttribute("Premium", player.MembershipType == Enum.MembershipType.Premium)
end
Players.PlayerMembershipChanged:Connect(checkPremium)

local function checkGroup(player)
	if C.GroupId == 0 then
		return
	end
	local ok, inGroup = pcall(player.IsInGroup, player, C.GroupId)
	if ok and inGroup and Profile.WaitFor(player, 20) and Profile.SetFlag(player, "GroupReward") then
		Profile.AddScrip(player, C.GroupScrip, "Group")
	end
end

local function onPlayer(player)
	task.spawn(checkPasses, player)
	task.spawn(checkGroup, player)
	checkPremium(player)
	-- deaths in a match (Stats.Deaths; also the old top-level Deaths)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Once(function()
				if player.Parent and player:GetAttribute("InMatch") then
					Profile.Count(player, "Deaths")
				end
			end)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end

-- Remote actions --------------------------------------------------------------------------------------------------------

local function fail(reason, extra)
	local t = extra or {}
	t.Ok = false
	t.Reason = reason
	return t
end
local function ok(extra)
	local t = extra or {}
	t.Ok = true
	return t
end

local function loadoutRules()
	local m = Shared:FindFirstChild("LoadoutRules")
	if not m then
		return nil
	end
	local good, R = pcall(require, m)
	return if good and type(R) == "table" and R.CanEquip then R else nil
end

local function slotOpen(player, index)
	local need = P.UnlockLevel("Slot" .. index) or 1
	return level(player) >= need
end

-- Can this item go into this loadout slot? ok, reason ("Locked" | "WrongSlot" | "Unknown").
local function canEquip(data, slot, item)
	local lvl = P.FromXp(data.Xp)
	local R = loadoutRules()
	if R then
		local good, okv, reason = pcall(R.CanEquip, slot, item, lvl, data.Stats, data.Owned)
		if good then
			return okv, reason
		end
	end
	if slot == "Class" then
		if not P.Classes[item] then
			return false, "Unknown"
		end
		return P.ClassUnlocked(item, lvl, data.Stats, data.Owned), "Locked"
	end
	if not table.find(P.LoadoutSlots, slot) then
		return false, "Unknown"
	end
	local itemSlot = P.Slots[item]
	if not itemSlot then
		return false, "Unknown"
	end
	if itemSlot ~= slot then
		return false, "WrongSlot"
	end
	return (P.UnlockLevel(item) or math.huge) <= lvl, "Locked"
end

local function claimTier(player, data, tier, track)
	local reward = P.Pass[track] and P.Pass[track][tier]
	if not reward then
		return nil, "Unknown"
	end
	if tier > P.PassTier(data.Pass.Xp) then
		return nil, "Locked"
	end
	if track == "Premium" and not data.Pass.Premium then
		return nil, "Locked"
	end
	local k = tostring(tier)
	if data.Pass.Claimed[track][k] then
		return nil, "Owned"
	end
	data.Pass.Claimed[track][k] = true
	local u = Profile.Reward(player, reward, "Pass:" .. track .. ":" .. tier)
	if u then
		u.Tier = tier
		u.Track = track
	end
	return u
end

local function record(target)
	local data = Profile.Get(target)
	if not data then
		return nil
	end
	local lvl, into, need, stars = P.FromXp(data.Xp)
	local most = data.Stats.MostUsedGun
	local gunLevel = nil
	if type(most) == "string" and P.WeaponFromXp then
		gunLevel = (P.WeaponFromXp(tonumber(data.GunXp[most]) or 0))
	end
	return {
		UserId = target.UserId, Name = target.DisplayName, Level = lvl, Stars = stars, Rank = P.Rank(lvl),
		Card = data.Card, Operator = data.Operator, Class = target:GetAttribute("Class"),
		Stats = table.clone(data.Stats),
		Xp = { Into = into, Need = need }, GunLevel = gunLevel,
	}
end

local ACTIONS = {}

ACTIONS.Loadout = function(player, data, payload)
	if player:GetAttribute("InMatch") then
		return fail("InMatch")
	end
	local index, slot, item = tonumber(payload.Index), payload.Slot, payload.Item
	if not index or index % 1 ~= 0 or index < 1 or index > P.Loadouts or type(slot) ~= "string" or type(item) ~= "string" then
		return fail("Unknown")
	end
	if not slotOpen(player, index) then
		return fail("Locked")
	end
	local good, reason = canEquip(data, slot, item)
	if not good then
		return fail(reason or "Locked")
	end
	data.Loadouts[index][slot] = item
	Profile.Publish(player, "Loadouts")
	Profile.Touch(player)
	return ok()
end

ACTIONS.Select = function(player, data, payload)
	if player:GetAttribute("InMatch") then
		return fail("InMatch")
	end
	local index = tonumber(payload.Index)
	if not index or index % 1 ~= 0 or index < 1 or index > P.Loadouts then
		return fail("Unknown")
	end
	if not slotOpen(player, index) then
		return fail("Locked")
	end
	data.Selected = index
	Profile.Publish(player, "Loadouts")
	Profile.Touch(player)
	return ok()
end

local function cosmetic(kind, field)
	return function(player, data, payload)
		local itemId = C.Id(kind, payload.Id)
		if not itemId or C.Split(itemId) ~= kind then
			return fail("Unknown")
		end
		local good, reason = C.Available(itemId, ctxFor(player))
		if not good then
			return fail(reason or "Locked")
		end
		local _, id = C.Split(itemId)
		data[field] = id
		Profile.Publish(player, "Cosmetics")
		Profile.Touch(player)
		return ok()
	end
end
ACTIONS.Operator = cosmetic("Operator", "Operator")
ACTIONS.Beam = cosmetic("Beam", "Beam")
ACTIONS.Card = cosmetic("Card", "Card")
ACTIONS.Pose = function(player, data, payload)
	-- poses are phase 1.5: only the default exists
	if payload.Id ~= "Default" then
		return fail("Unknown")
	end
	data.Pose = "Default"
	Profile.Publish(player, "Cosmetics")
	return ok()
end

ACTIONS.Camo = function(player, data, payload)
	local gun = payload.Gun
	if type(gun) ~= "string" or not table.find(P.Guns, gun) then
		return fail("Unknown")
	end
	local itemId = C.Id("Camo", payload.Id)
	if not itemId or C.Split(itemId) ~= "Camo" then
		return fail("Unknown")
	end
	local good, reason = C.Available(itemId, ctxFor(player, gun))
	if not good then
		return fail(reason or "Locked")
	end
	local _, camo = C.Split(itemId)
	data.Camos[gun] = if camo == "Gunmetal" then nil else camo
	Profile.Publish(player, "Cosmetics")
	Profile.Touch(player)
	return ok()
end

-- Scopes and attachments (6 Nov 2026, Shared.Attachments): {Gun, Slot, Id} puts that attachment on the gun, Id nil
-- clears the slot. Each one unlocks at a weapon level of that gun (Attachments.UnlockLevel, from GunXp).
ACTIONS.Attach = function(player, data, payload)
	local gun, slot, id = payload.Gun, payload.Slot, payload.Id
	if type(gun) ~= "string" or not table.find(P.Guns, gun) or type(slot) ~= "string" or not table.find(Attachments.Slots, slot) then
		return fail("Unknown")
	end
	data.Attach = type(data.Attach) == "table" and data.Attach or {}
	local picks = type(data.Attach[gun]) == "table" and data.Attach[gun] or {}
	if id == nil or id == "None" then
		picks[slot] = nil
	else
		if type(id) ~= "string" or not Attachments.Fits(gun, slot, id) then
			return fail("Unknown")
		end
		local level = P.WeaponFromXp(tonumber(data.GunXp and data.GunXp[gun]) or 0)
		if level < (Attachments.UnlockLevel(gun, id) or math.huge) then
			return fail("Locked")
		end
		picks[slot] = id
	end
	data.Attach[gun] = if next(picks) then picks else nil
	Profile.Publish(player, "Attach")
	Profile.Touch(player)
	return ok()
end

ACTIONS.Charm = function(player, data, payload)
	-- charms are phase 1.5: clearing is the only valid change
	local gun = payload.Gun
	if type(gun) ~= "string" or not table.find(P.Guns, gun) or (payload.Id ~= nil and payload.Id ~= "None") then
		return fail("Unknown")
	end
	data.Charms[gun] = nil
	Profile.Publish(player, "Cosmetics")
	return ok()
end

-- Opens one earned crate of that tier (Modules.Crates rolls and grants; earned only, never sold).
ACTIONS.OpenCrate = function(player, data, payload)
	if not Crates then
		return fail("Unknown")
	end
	local crate, err = Crates.Open(player, data, payload.Tier)
	if not crate then
		return fail(err or "NoCrate")
	end
	task.spawn(Profile.SaveNow, player)
	return ok({ Crate = crate })
end

ACTIONS.Buy = function(player, data, payload)
	local itemId = payload.ItemId
	if type(itemId) ~= "string" or not C.Items[itemId] then
		return fail("Unknown")
	end
	local price = C.Price(itemId)
	if not price then
		return fail("NotForSale")
	end
	if data.Owned[itemId] then
		return fail("Owned")
	end
	if data.Scrip < price or not Profile.SpendScrip(player, price, "Shop:" .. itemId) then
		local short = price - data.Scrip
		if Offers then
			pcall(Offers.Want, player, data, itemId)
		end
		return fail("Short", { Need = short, Pack = C.PackFor(short) })
	end
	Profile.Grant(player, itemId)
	task.spawn(Profile.SaveNow, player)
	return ok({ ItemId = itemId })
end

ACTIONS.Product = function(player, data, payload)
	local key = payload.Key
	local p = type(key) == "string" and C.Products[key]
	if not p then
		return fail("Unknown")
	end
	local id = productId(key)
	if id == 0 then
		return fail("NotForSale")
	end
	local tier = P.PassTier(data.Pass.Xp)
	if key == "PassTiers5" and P.Pass.Tiers - tier < (p.MinLeft or 0) then
		return fail("NotForSale")
	end
	if key == "PassTier1" and tier >= P.Pass.Tiers then
		return fail("Owned")
	end
	if p.Type == "Pass" then
		local have = player:GetAttribute(PASS_ATTR[key] or key)
		if have and have == (PASS_VALUE[key] or true) then
			return fail("Owned")
		end
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
	return ok()
end

ACTIONS.PassClaim = function(player, data, payload)
	local granted = {}
	if payload.All == true then
		local reached = P.PassTier(data.Pass.Xp)
		for tier = 1, reached do
			for _, track in { "Free", "Premium" } do
				local u = claimTier(player, data, tier, track)
				if u then
					table.insert(granted, u)
				end
			end
		end
	else
		local tier, track = tonumber(payload.Tier), payload.Track
		if not tier or (track ~= "Free" and track ~= "Premium") then
			return fail("Unknown")
		end
		local u, reason = claimTier(player, data, math.floor(tier), track)
		if not u then
			return fail(reason or "Locked")
		end
		table.insert(granted, u)
	end
	Profile.Publish(player, "Pass")
	Profile.Touch(player)
	if #granted > 0 then
		task.spawn(Profile.SaveNow, player)
	end
	return ok({ Granted = granted })
end

ACTIONS.Reroll = function(player, data, payload)
	Profile.Rollover(player)
	local index = tonumber(payload.Index)
	local daily = data.Daily
	if not index or not daily.Ids or not daily.Ids[index] then
		return fail("Unknown")
	end
	if daily.Rerolled then
		return fail("Used")
	end
	local old = daily.Ids[index]
	if daily.Done[old] then
		return fail("Done")
	end
	local new = P.RerollId(daily.Day, index, daily.Ids)
	if not new then
		return fail("Unknown")
	end
	if not Profile.SpendScrip(player, P.RerollScrip, "Reroll") then
		local short = P.RerollScrip - data.Scrip
		return fail("Short", { Need = short, Pack = C.PackFor(short) })
	end
	daily.Ids[index] = new
	daily.Progress[old] = nil
	daily.Rerolled = true
	Profile.Publish(player, "Challenges")
	Profile.Touch(player)
	return ok({ Id = new })
end

ACTIONS.Seen = function(player, _data, payload)
	if type(payload.Ids) ~= "table" then
		return fail("Unknown")
	end
	Profile.MarkSeen(player, payload.Ids)
	return ok()
end

ACTIONS.Aar = function(player)
	return ok({ Payload = Progression.LastAar(player) })
end

ACTIONS.AarSeen = function(player)
	Progression.AarSeen(player)
	return ok()
end

ACTIONS.Record = function(player, _data, payload)
	local target = player
	if payload.UserId ~= nil then
		target = Players:GetPlayerByUserId(tonumber(payload.UserId) or 0)
	end
	if not target then
		return fail("Unknown")
	end
	return ok({ Record = record(target) })
end

ACTIONS.Catalogue = function(player, data)
	local day = P.Day()
	local rot = C.Rotation(day)
	local hero = rot.Hero
	-- nothing is sold before the first escape or level 3 (MENU-PLAN 9.3)
	local selling = data.Stats.Escapes > 0 or data.Escaped == true or level(player) >= 3
	-- the starter offer's 48 h start when the store first opens for this player, not at first join, so the
	-- countdown the player sees is the whole real window (set once; Profile.SetFlag is true only the first time)
	if selling and not data.Owned.StarterPack and Profile.SetFlag(player, "StarterClock") then
		data.StarterDeadline = os.time() + 48 * 3600
		player:SetAttribute("StarterDeadline", data.StarterDeadline)
		Profile.Touch(player)
	end
	if selling and not data.Owned.StarterPack and productId("StarterPack") ~= 0 and os.time() < data.StarterDeadline then
		hero = "Product/StarterPack"
	end
	return ok({
		Hero = hero, Tiles = rot.Tiles, Day = day, StarterDeadline = data.StarterDeadline,
		Selling = selling, WeekEnds = P.WeekEnds(P.Week()), DayEnds = P.DayEnds(day),
	})
end

-- The HOME offer strip: {Moment = "Home"} -> {Offer = {Id, Rule, Key, Title, Line, Art, Until?}} or {} (see Offers).
ACTIONS.Offers = function(player, data, payload)
	if not Offers or player:GetAttribute("InMatch") then
		return ok({})
	end
	return ok({ Offer = Offers.Pick(player, data, payload.Moment) })
end

ACTIONS.OfferHide = function(player, data, payload)
	if Offers and type(payload.Id) == "string" then
		Offers.Hidden(player, data, payload.Id)
	end
	return ok()
end

-- The store sent a player to the gem packs for an item they could not afford.
ACTIONS.Want = function(player, data, payload)
	if Offers then
		Offers.Want(player, data, payload.ItemId)
	end
	return ok()
end

-- light flood guard: 40 calls per 5 s per player
local calls = {}
Players.PlayerRemoving:Connect(function(player)
	calls[player] = nil
end)

remote.OnServerInvoke = function(player, action, payload)
	local now = os.clock()
	local c = calls[player]
	if not c or now - c.At > 5 then
		c = { At = now, N = 0 }
		calls[player] = c
	end
	c.N += 1
	if c.N > 40 then
		return fail("Busy")
	end

	-- old MenuClient (until the new front end replaces it)
	if action == "Class" then
		local data = Profile.WaitFor(player, 10)
		if typeof(payload) ~= "string" or not data or not P.Classes[payload] or player:GetAttribute("InMatch") then
			return "No"
		end
		if not P.ClassUnlocked(payload, level(player), data.Stats, data.Owned) then
			return "Locked"
		end
		Profile.SetClass(player, payload)
		return "Picked"
	elseif action == "Offer" then
		return false
	end

	local fn = type(action) == "string" and ACTIONS[action]
	if not fn then
		return fail("Unknown")
	end
	local data = Profile.WaitFor(player, 10)
	if not data then
		return fail("NoProfile")
	end
	if type(payload) ~= "table" then
		payload = {}
	end
	local good, result = pcall(fn, player, data, payload)
	if not good then
		warn("StoreServer:", action, "failed for", player.Name, result)
		return fail("Error")
	end
	return result
end
