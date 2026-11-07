-- Offers (6 Nov 2026): picks at most one Robux offer for a player from what their saved profile says they need, and
-- logs those needs so the owner can see in Creator Hub (Analytics > Custom Events) what players run into.
--
-- Read by StoreServer:
--   Offers.Pick(player, data, moment) -> offer table or nil      Store action "Offers" {Moment = "Home"}
--   Offers.Hidden(player, data, id)                               Store action "OfferHide" {Id}
--   Offers.Want(player, data, itemId)                             Store action "Want" {ItemId}, and a failed Buy
--   Offers.Bought(player, data, key)                              after a product grant or a pass purchase
--
-- Moments. "Home": the HOME page just came up. An offer is only picked right after a match (a fresh AAR that has not
-- had an offer yet), never at join and never twice for one match.
--
-- Rules (first that fits wins; each one names the exact product and states its real effect):
--   Starter    no Starter Pack yet, its 48 h window still open           StarterPack   after a won match
--   Unlock     a class, gun, gear or operator 1-2 levels away             XpBoost30/60  any match
--   Revive     the match was lost and the player has no revive tokens     Revive5       after a lost match
--   NightPass  no premium Night Pass, 4+ premium rewards already earned   PassPremium   after a won match
--   Gems       short of gems for something they tried to buy (Want),     smallest pack that covers it
--              or close to the cheapest store operator they lack
--   Double     no Double Gems pass, 8+ matches, the match paid gems       DoubleScrip   after a won match
-- Guard rails (vault: Robux Price Points and Offer Design, Ethical Design and Player Trust):
--   * nothing until the store is open for the player (first escape or level 3) and 2 matches are played;
--   * one unprompted offer per server visit (two for players who have bought before), 10 min apart;
--   * every rule has a cooldown, and each time the player hides that rule's offer the cooldown doubles (max 7 days);
--   * permanent items only after a won match; after a lost match only small consumables;
--   * no fake timers: the only countdown shown is the Starter Pack's real deadline.
-- Saved in the profile under data.Offers = {Seen = {[rule] = {N, T, H}}, Want = {Item, At}, AarAt, Bought = {}}.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local P = require(Shared:WaitForChild("Progression"))
local C = require(Shared:WaitForChild("Catalogue"))
local Profile = require(ServerStorage.Modules.Profile)

local Offers = {}

local HOUR = 3600
local GAP = 10 * 60 -- seconds between two unprompted offers in one visit
local AAR_FRESH = 30 * 60 -- an AAR older than this is not "just played"
local WANT_FOR = 3 * 24 * HOUR -- how long a wanted item counts
local MAX_BACKOFF = 7 * 24 * HOUR
local ATTRIBUTE_FOR = 20 * 60 -- a purchase this soon after the offer counts as the offer's

-- rule -> {Cooldown (s), Max shows ever (nil = no cap)}
local RULES = {
	Starter = { Cooldown = 20 * HOUR, Max = 3 },
	Unlock = { Cooldown = 10 * HOUR },
	Revive = { Cooldown = 20 * HOUR },
	NightPass = { Cooldown = 30 * HOUR, Max = 4 },
	Gems = { Cooldown = 16 * HOUR },
	Double = { Cooldown = 48 * HOUR, Max = 3 },
}
local WON = { Escaped = true, Survived = true, MissionComplete = true }
local LOST = { Overrun = true, MissionFailed = true }

local session = {} -- [player] = {Shown = n, At = os.clock(), Offer = last offer}
Players.PlayerRemoving:Connect(function(player)
	session[player] = nil
end)

-- analytics -----------------------------------------------------------------------------------------------------------

local F1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
local F2 = Enum.AnalyticsCustomFieldKeys.CustomField02.Name
local F3 = Enum.AnalyticsCustomFieldKeys.CustomField03.Name

local function levelBand(level)
	local lo = (level - 1) // 5 * 5 + 1
	return string.format("Lv%02d-%02d", lo, lo + 4)
end

local function log(player, event, a, b, c)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, event, 1, { [F1] = a or "", [F2] = b or "", [F3] = c or "" })
	end)
end

-- helpers -------------------------------------------------------------------------------------------------------------

local function state(data)
	local o = data.Offers
	if type(o) ~= "table" then
		o = {}
		data.Offers = o
	end
	o.Seen = type(o.Seen) == "table" and o.Seen or {}
	o.Bought = type(o.Bought) == "table" and o.Bought or {}
	return o
end

local function live(key)
	local p = C.Products[key]
	return p ~= nil and p.Id ~= 0
end

local function niceId(id)
	return string.upper((string.gsub(id, "(%l)(%u)", "%1 %2")))
end

local function unlockName(r)
	if r.Kind == "Class" then
		local c = P.Classes[r.Id]
		return (c and c.Name or niceId(r.Id)) .. " CLASS"
	elseif r.Kind == "Operator" then
		local it = C.Items["Operator/" .. r.Id]
		return (it and it.Name or niceId(r.Id)) .. " OPERATOR"
	end
	return niceId(r.Id)
end

local function comma(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- When this rule may show again (doubling with every hide).
local function ready(o, rule, now)
	local seen = o.Seen[rule]
	if type(seen) ~= "table" then
		return true
	end
	local cfg = RULES[rule]
	if cfg.Max and (tonumber(seen.N) or 0) >= cfg.Max then
		return false
	end
	local wait = math.min(MAX_BACKOFF, cfg.Cooldown * 2 ^ math.min(6, tonumber(seen.H) or 0))
	return now - (tonumber(seen.T) or 0) >= wait
end

-- rules ---------------------------------------------------------------------------------------------------------------
-- Each returns {Key, Line, Need} when the player has that need (whether or not it may show right now).

local function ruleStarter(player, data, ctx)
	if data.Owned.StarterPack or os.time() >= (tonumber(data.StarterDeadline) or 0) then
		return nil
	end
	local p = C.Products.StarterPack
	local operator = C.Items[p.Items[1]]
	return {
		Key = "StarterPack",
		Line = string.format("%s OPERATOR + %s GEMS + %d REVIVES", operator and operator.Name or "PATHFINDER",
			comma(p.Scrip), p.Tokens),
		Until = data.StarterDeadline,
		Need = "NewPlayer",
		OnlyWon = true,
	}
end

local UNLOCK_KINDS = { Class = 1, Gun = 2, Operator = 3, Gear = 4 }
local function ruleUnlock(player, data, ctx)
	if Profile.TimedActive(player, "Xp") or ctx.level >= P.LevelCap then
		return nil
	end
	for ahead = 1, 2 do
		local lvl = ctx.level + ahead
		local best = nil
		for _, r in P.Rewards[lvl] or {} do
			local rank = UNLOCK_KINDS[r.Kind]
			if rank and (not best or rank < UNLOCK_KINDS[best.Kind]) then
				best = r
			end
		end
		if best then
			local gap = P.XpAt(lvl) - data.Xp
			-- out of reach of a couple of matches: a booster would not get them there tonight
			if gap > ctx.matchXp * 4 then
				return nil
			end
			return {
				Key = if ahead == 1 then "XpBoost30" else "XpBoost60",
				Line = string.format("%s UNLOCKS AT LEVEL %d", unlockName(best), lvl),
				Need = "Unlock:" .. best.Kind .. "/" .. best.Id,
			}
		end
	end
	return nil
end

local function ruleRevive(player, data, ctx)
	if not ctx.lost or (tonumber(data.Tokens) or 0) > 0 then
		return nil
	end
	return {
		Key = "Revive5",
		Line = "GET BACK UP NEXT TIME YOU GO DOWN: 5 TOKENS",
		Need = "Revives",
	}
end

local function ruleNightPass(player, data, ctx)
	if data.Pass.Premium or os.time() >= P.Pass.Ends then
		return nil
	end
	local tier = P.PassTier(data.Pass.Xp)
	local earned = 0
	for t = 1, tier do
		if P.Pass.Premium[t] then
			earned += 1
		end
	end
	if earned < 4 then
		return nil
	end
	return {
		Key = "PassPremium",
		Line = string.format("UNLOCKS %d PREMIUM REWARDS YOU ALREADY EARNED", earned),
		Need = "NightPass",
		OnlyWon = true,
	}
end

local function ruleGems(player, data, ctx, o)
	local want = o.Want
	local target = nil
	if type(want) == "table" and type(want.Item) == "string" and os.time() - (tonumber(want.At) or 0) < WANT_FOR then
		local price = C.Price(want.Item)
		if price and not data.Owned[want.Item] and data.Scrip < price then
			target = want.Item
		end
	end
	if not target then
		-- the "outfit" push: the cheapest store operator they lack, once they have half of its price
		local cheapest, cost = nil, math.huge
		for itemId, it in C.Items do
			if it.Kind == "Operator" and it.Source.Kind == "Store" and not data.Owned[itemId] and it.Source.Scrip < cost then
				cheapest, cost = itemId, it.Source.Scrip
			end
		end
		if cheapest and data.Scrip < cost and data.Scrip >= cost * 0.5 then
			target = cheapest
		end
	end
	if not target then
		return nil
	end
	local it = C.Items[target]
	local short = (C.Price(target) or 0) - data.Scrip
	local pack = C.PackFor(short)
	if not pack then
		return nil
	end
	local kind = it.Kind == "Operator" and " OPERATOR" or ""
	return {
		Key = pack,
		Line = string.format("ENOUGH FOR %s%s (%s GEMS SHORT)", it.Name, kind, comma(short)),
		Need = "Gems:" .. target,
	}
end

local function ruleDouble(player, data, ctx)
	if player:GetAttribute("DoubleScrip") or data.Stats.Matches < 8 then
		return nil
	end
	local scrip = type(ctx.aar.Scrip) == "table" and ctx.aar.Scrip or {}
	local base = tonumber(scrip.Base) or 0
	local total = tonumber(scrip.Total) or 0
	if base <= 0 then
		return nil
	end
	local m = Profile.Multiplier(player)
	local extra = math.floor(base * math.min(C.Multipliers.Cap or 4, m * (C.Multipliers.DoubleScrip or 2)) + 0.5) - total
	if extra < 50 then
		return nil
	end
	return {
		Key = "DoubleScrip",
		Line = string.format("THAT MATCH WOULD HAVE PAID +%s GEMS", comma(extra)),
		Need = "DoubleGems",
		OnlyWon = true,
	}
end

local ORDER = {
	{ "Starter", ruleStarter },
	{ "Unlock", ruleUnlock },
	{ "Revive", ruleRevive },
	{ "NightPass", ruleNightPass },
	{ "Gems", ruleGems },
	{ "Double", ruleDouble },
}

-- api -----------------------------------------------------------------------------------------------------------------

function Offers.Pick(player, data, moment)
	if moment ~= "Home" then
		return nil
	end
	local o = state(data)
	local aar = data.LastAar
	local now = os.time()
	if type(aar) ~= "table" or now - (tonumber(aar.At) or 0) > AAR_FRESH or o.AarAt == aar.At then
		return nil
	end
	o.AarAt = aar.At -- one look per match, offer or not
	Profile.Touch(player)

	local level = P.FromXp(data.Xp)
	local xp = type(aar.Xp) == "table" and tonumber(aar.Xp.Total) or 0
	local ctx = {
		level = level,
		aar = aar,
		won = WON[aar.Result] == true,
		lost = LOST[aar.Result] == true,
		matchXp = math.max(400, xp),
	}

	-- every need found is logged, shown or not: this is the "what do players run into" data
	local pick, pickRule = nil, nil
	for _, entry in ORDER do
		local rule, fn = entry[1], entry[2]
		local ok, offer = pcall(fn, player, data, ctx, o)
		if ok and offer then
			log(player, "PlayerNeed", offer.Need, aar.Result or "", levelBand(level))
			local allowed = live(offer.Key) and ready(o, rule, now) and not (offer.OnlyWon and not ctx.won)
			if allowed and not pick then
				pick, pickRule = offer, rule
			end
		elseif not ok then
			warn("Offers:", rule, offer)
		end
	end
	if not pick then
		return nil
	end

	-- the visit's gates (store open, matches played, one or two per visit, 10 min apart)
	local selling = data.Stats.Escapes > 0 or data.Escaped == true or level >= 3
	if not selling or data.Stats.Matches < 2 then
		return nil
	end
	local s = session[player] or { Shown = 0, At = -math.huge }
	session[player] = s
	local payer = next(data.PurchaseIds) ~= nil or player:GetAttribute("Vip") or player:GetAttribute("DoubleScrip")
	if s.Shown >= (if payer then 2 else 1) or os.clock() - s.At < GAP then
		return nil
	end

	s.Shown += 1
	s.At = os.clock()
	local seen = o.Seen[pickRule]
	if type(seen) ~= "table" then
		seen = { N = 0, T = 0, H = 0 }
		o.Seen[pickRule] = seen
	end
	seen.N = (tonumber(seen.N) or 0) + 1
	seen.T = now
	Profile.Touch(player)

	local p = C.Products[pick.Key]
	local offer = {
		Id = pickRule .. ":" .. tostring(now),
		Rule = pickRule,
		Key = pick.Key,
		Title = p.Name,
		Line = pick.Line,
		Art = p.Art,
		Until = pick.Until,
	}
	s.Offer = { Id = offer.Id, Rule = pickRule, Key = pick.Key, At = os.clock() }
	log(player, "OfferShown", pickRule, pick.Key, levelBand(level))
	return offer
end

-- The player tucked the strip away: that rule waits twice as long next time.
function Offers.Hidden(player, data, id)
	local s = session[player]
	local last = s and s.Offer
	if not last or last.Id ~= id then
		return
	end
	local o = state(data)
	local seen = o.Seen[last.Rule]
	if type(seen) == "table" then
		seen.H = (tonumber(seen.H) or 0) + 1
		Profile.Touch(player)
	end
	log(player, "OfferHidden", last.Rule, last.Key, "")
	s.Offer = nil
end

-- Something they tried to buy and could not afford (the Gems rule offers the pack that covers it after a match).
function Offers.Want(player, data, itemId)
	if type(itemId) ~= "string" or not C.Items[itemId] or not C.Price(itemId) then
		return
	end
	local o = state(data)
	o.Want = { Item = itemId, At = os.time() }
	Profile.Touch(player)
	log(player, "WantItem", itemId, comma(C.Price(itemId) - data.Scrip), "")
end

-- A product was granted or a pass bought. Counted as the offer's when it is the offered key, soon after.
function Offers.Bought(player, data, key)
	local s = session[player]
	local last = s and s.Offer
	if not last or last.Key ~= key or os.clock() - last.At > ATTRIBUTE_FOR then
		return
	end
	local o = state(data)
	o.Bought[last.Rule] = (tonumber(o.Bought[last.Rule]) or 0) + 1
	log(player, "OfferBought", last.Rule, key, "")
	s.Offer = nil
end

return Offers
