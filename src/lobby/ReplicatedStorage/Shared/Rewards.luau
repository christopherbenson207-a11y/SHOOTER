--!strict
-- Shared.Rewards (4 Nov 2026): the SUPPLY CRATE every finished match gives. Plain data and pure functions, the same on
-- the server and on clients: the server rolls with these tables, the crate screen's ODDS panel prints Rewards.Odds
-- from the same tables (one source). Same source in the lobby and zombies places.
--
-- Crates are EARNED ONLY: never sold for Robux, Scrip or anything bought with Robux, and no paid item changes their odds
-- (VIP, Double Scrip and Squad Boost do not touch crates). So they are not paid random items; the odds are shown anyway.
-- Pity: a Legendary at the latest every PityLegendary crates, an Epic or better every PityEpic crates (saved counters).
-- An item you already own is never rolled while the tier's pool still has one you don't; a full pool pays DupeScrip.
-- Earn and open are two steps ("players can open in lobby"): a finished match rolls the crate's TIER and keeps it in the
-- player's crate stack; opening it (now, or later in the lobby) rolls what is inside. MaxStack crates at most; an earned
-- crate past the cap opens on the spot.
--   Rewards.Tiers[tier]              {Name, Color, Scrip = {min, max}, Tokens, TokenChance, BoostChance, ItemChance, Pool}
--   Rewards.TierOdds(result)         {Common = %, Rare = %, Epic = %, Legendary = %} for that match result
--   Rewards.RollTier(rng, result, counters) -> tier, pity?, newCounters
--   Rewards.RollContents(rng, tier, owned)  -> crate {Tier, Scrip, Tokens, Boosts, Item?, Dupe?}
--   Rewards.Roll(rng, result, counters, owned) -> both at once (tests)
--   Rewards.Count(stack)             {Common = n, ...}
--   Rewards.Odds(result, owned)      rows for the ODDS panel

local Rewards = {}

Rewards.Order = { "Common", "Rare", "Epic", "Legendary" }

Rewards.Tiers = {
	Common = {
		Name = "FIELD CRATE", Color = Color3.fromRGB(190, 186, 176),
		Scrip = { 60, 120 }, Tokens = 1, TokenChance = 0.15, BoostChance = 0, ItemChance = 0, Pool = {}, DupeScrip = 0,
	},
	Rare = {
		Name = "RARE CRATE", Color = Color3.fromRGB(80, 160, 255),
		Scrip = { 150, 250 }, Tokens = 1, TokenChance = 0.3, BoostChance = 0, ItemChance = 0.15,
		Pool = { "Card/Static", "Card/Ashfall" }, DupeScrip = 300,
	},
	Epic = {
		Name = "EPIC CRATE", Color = Color3.fromRGB(178, 102, 255),
		Scrip = { 350, 550 }, Tokens = 1, TokenChance = 1, BoostChance = 0.1, ItemChance = 0.3,
		Pool = { "Camo/Rust", "Camo/Ash", "Card/Static", "Card/Ashfall" }, DupeScrip = 800,
	},
	Legendary = {
		Name = "LEGENDARY CRATE", Color = Color3.fromRGB(255, 176, 60),
		Scrip = { 900, 1300 }, Tokens = 2, TokenChance = 1, BoostChance = 1, ItemChance = 1,
		Pool = { "Operator/Warden", "Operator/Revenant", "Operator/Lamplighter", "Camo/Rust", "Camo/Ash" }, DupeScrip = 2000,
	},
}

Rewards.ByResult = {
	Default = { Common = 70, Rare = 22, Epic = 7, Legendary = 1 },
	Won = { Common = 45, Rare = 35, Epic = 15, Legendary = 5 },
}
Rewards.Won = { Escaped = true, MissionComplete = true, Survived = true }

Rewards.PityLegendary = 30
Rewards.PityEpic = 10
Rewards.MaxStack = 50

do
	for name, row in Rewards.ByResult do
		local sum = 0
		for _, tier in Rewards.Order do
			sum += row[tier]
		end
		assert(sum == 100, "Shared.Rewards: odds row " .. name .. " sums to " .. sum)
	end
	for _, tier in Rewards.Order do
		local t = Rewards.Tiers[tier]
		assert(t and t.Scrip[1] <= t.Scrip[2], "Shared.Rewards: bad tier " .. tier)
		assert(t.ItemChance == 0 or #t.Pool > 0, "Shared.Rewards: " .. tier .. " has an item chance and no pool")
	end
end

function Rewards.TierOdds(result: string?): { [string]: number }
	return if result and Rewards.Won[result] then Rewards.ByResult.Won else Rewards.ByResult.Default
end

export type Counters = { N: number, SinceLegendary: number, SinceEpic: number }
export type Crate = { Tier: string, Scrip: number, Tokens: number, Boosts: number, Item: string?, Dupe: number?, Pity: string? }

function Rewards.NewCounters(): Counters
	return { N = 0, SinceLegendary = 0, SinceEpic = 0 }
end

function Rewards.Unowned(tier: string, owned: { [string]: any }?): { string }
	local list = {}
	for _, itemId in Rewards.Tiers[tier].Pool do
		if not (owned and owned[itemId]) then
			table.insert(list, itemId)
		end
	end
	return list
end

function Rewards.RollTier(rng: Random, result: string?, counters: Counters?): (string, string?, Counters)
	local c = counters or Rewards.NewCounters()
	local odds = Rewards.TierOdds(result)
	local tier, pity = "Common", nil
	if c.SinceLegendary + 1 >= Rewards.PityLegendary then
		tier, pity = "Legendary", "Legendary"
	else
		local r = rng:NextNumber(0, 100)
		local acc = 0
		for _, name in Rewards.Order do
			acc += odds[name]
			if r < acc then
				tier = name
				break
			end
		end
		if (tier == "Common" or tier == "Rare") and c.SinceEpic + 1 >= Rewards.PityEpic then
			tier, pity = "Epic", "Epic"
		end
	end
	local epicUp = tier == "Epic" or tier == "Legendary"
	local nextC: Counters = {
		N = c.N + 1,
		SinceLegendary = if tier == "Legendary" then 0 else c.SinceLegendary + 1,
		SinceEpic = if epicUp then 0 else c.SinceEpic + 1,
	}
	return tier, pity, nextC
end

function Rewards.RollContents(rng: Random, tier: string, owned: { [string]: any }?): Crate
	local t = Rewards.Tiers[tier]
	assert(t, "Shared.Rewards: unknown tier " .. tostring(tier))
	local crate: Crate = {
		Tier = tier,
		Scrip = rng:NextInteger(t.Scrip[1], t.Scrip[2]),
		Tokens = if rng:NextNumber() < t.TokenChance then t.Tokens else 0,
		Boosts = if rng:NextNumber() < t.BoostChance then 1 else 0,
	}
	if t.ItemChance > 0 and rng:NextNumber() < t.ItemChance then
		local open = Rewards.Unowned(tier, owned)
		if #open > 0 then
			crate.Item = open[rng:NextInteger(1, #open)]
		else
			crate.Dupe = t.DupeScrip
		end
	end
	return crate
end

function Rewards.Roll(rng: Random, result: string?, counters: Counters?, owned: { [string]: any }?): (Crate, Counters)
	local tier, pity, nextC = Rewards.RollTier(rng, result, counters)
	local crate = Rewards.RollContents(rng, tier, owned)
	crate.Pity = pity
	return crate, nextC
end

function Rewards.Count(stack: { any }?): { [string]: number }
	local n = { Common = 0, Rare = 0, Epic = 0, Legendary = 0 }
	for _, e in stack or {} do
		local tier = if type(e) == "table" then e.Tier else e
		if n[tier] then
			n[tier] += 1
		end
	end
	return n
end

function Rewards.Odds(result: string?, owned: { [string]: any }?): { { Tier: string, Name: string, Chance: number, Lines: { string } } }
	local odds = Rewards.TierOdds(result)
	local rows = {}
	for _, tier in Rewards.Order do
		local t = Rewards.Tiers[tier]
		local lines = { string.format("%d-%d Scrip (always)", t.Scrip[1], t.Scrip[2]) }
		if t.TokenChance > 0 then
			table.insert(lines, string.format("%d revive token%s: %d%%", t.Tokens, if t.Tokens > 1 then "s" else "", math.floor(t.TokenChance * 100 + 0.5)))
		end
		if t.BoostChance > 0 then
			table.insert(lines, string.format("Squad Boost: %d%%", math.floor(t.BoostChance * 100 + 0.5)))
		end
		if t.ItemChance > 0 then
			local open = Rewards.Unowned(tier, owned)
			local pct = t.ItemChance * 100
			if #open > 0 then
				table.insert(lines, string.format("A cosmetic you don't own: %d%% (each of %d: %.1f%%)", math.floor(pct + 0.5), #open, pct / #open))
			else
				table.insert(lines, string.format("You own the whole pool: %d%% for +%d Scrip instead", math.floor(pct + 0.5), t.DupeScrip))
			end
		end
		table.insert(rows, { Tier = tier, Name = t.Name, Chance = odds[tier], Lines = lines })
	end
	return rows
end

return Rewards
