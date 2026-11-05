--!strict
-- ServerStorage.Modules.Crates (4 Nov 2026; same source in the lobby and zombies places).
-- Earned crates, kept until the player opens them ("players can open in lobby").
--   * A finished match rolls a crate TIER (Shared.Rewards.RollTier, pity counters in data.Crates) and puts it on the
--     player's stack (data.Crates.Stack, a list of tier names, at most Rewards.MaxStack; past the cap it opens on the spot).
--   * Opening (Store action "OpenCrate", lobby or the match end screen) rolls the contents (Rewards.RollContents) and
--     grants them in the same profile table as the stack removal, so a crash before the save loses neither or both.
-- Crates are earned only, never sold, and no paid modifier touches them (Shared.Rewards header).
-- Attributes for the UI: Crates = JSON {Common = n, Rare = n, Epic = n, Legendary = n}, CratePity = JSON
-- {SinceLegendary, SinceEpic}.
--   Crates.Earn(player, data, result) -> {Tier, Pity?, Opened? (crate, when the stack was full)}
--   Crates.Open(player, data, tier)   -> crate | nil, "NoCrate"
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rewards = require(ReplicatedStorage.Shared.Rewards)
local Profile = require(script.Parent.Profile)

local Crates = {}
local rng = Random.new()

local function state(data)
	local c = data.Crates
	if type(c) ~= "table" then
		c = Rewards.NewCounters()
		data.Crates = c
	end
	if type(c.Stack) ~= "table" then
		c.Stack = {}
	end
	return c
end

function Crates.Publish(player: Player, data)
	local c = state(data)
	player:SetAttribute("Crates", HttpService:JSONEncode(Rewards.Count(c.Stack)))
	player:SetAttribute("CratePity", HttpService:JSONEncode({
		SinceLegendary = c.SinceLegendary or 0,
		SinceEpic = c.SinceEpic or 0,
	}))
end

-- Grants one rolled crate. Scrip is added flat (no paid multiplier).
local function grant(player: Player, data, crate)
	local scrip = crate.Scrip + (crate.Dupe or 0)
	if scrip > 0 then
		Profile.AddScrip(player, scrip, "Crate:" .. crate.Tier)
	end
	if crate.Tokens > 0 then
		Profile.Count(player, "Tokens", crate.Tokens)
	end
	if crate.Boosts > 0 then
		data.Boosts = (tonumber(data.Boosts) or 0) + crate.Boosts
		player:SetAttribute("Boosts", data.Boosts)
	end
	if crate.Item then
		Profile.Grant(player, crate.Item)
	end
end

function Crates.Earn(player: Player, data, result: string?)
	local c = state(data)
	local tier, pity, nextC = Rewards.RollTier(rng, result, c)
	c.N, c.SinceLegendary, c.SinceEpic = nextC.N, nextC.SinceLegendary, nextC.SinceEpic
	local earned: { [string]: any } = { Tier = tier, Pity = pity }
	if #c.Stack >= Rewards.MaxStack then
		local crate = Rewards.RollContents(rng, tier, data.Owned)
		grant(player, data, crate)
		earned.Opened = crate
	else
		table.insert(c.Stack, tier)
	end
	Crates.Publish(player, data)
	Profile.Touch(player)
	return earned
end

function Crates.Open(player: Player, data, tier: any)
	if type(tier) ~= "string" or not Rewards.Tiers[tier] then
		return nil, "NoCrate"
	end
	local c = state(data)
	local index = table.find(c.Stack, tier)
	if not index then
		return nil, "NoCrate"
	end
	table.remove(c.Stack, index)
	local crate = Rewards.RollContents(rng, tier, data.Owned)
	grant(player, data, crate)
	Crates.Publish(player, data)
	Profile.Touch(player)
	return crate
end

Profile.OnLoaded(function(player, data)
	Crates.Publish(player, data)
end)

return Crates
