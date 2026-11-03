-- Badges (DATA, menu revamp, 3 Nov 2026). Each badge is a rule on the player attributes Profile and Progression
-- already publish (Level, Escaped, Stats JSON), so no other script calls this one. A badge whose Id is 0 is skipped:
-- the owner makes the badges in Creator Hub and puts their ids here; each one turns on by itself then.
-- Awards run in pcall, at most once per player per server, and never in Studio's local test unless the id is set.

local BadgeService = game:GetService("BadgeService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- Stat: a field of the Stats attribute; Level: the account level; Attr: a boolean player attribute.
local BADGES = {
	{ Key = "Welcome", Id = 0, Level = 1 },
	{ Key = "FirstEscape", Id = 0, Attr = "Escaped" },
	{ Key = "Level10", Id = 0, Level = 10 },
	{ Key = "Level25", Id = 0, Level = 25 },
	{ Key = "Level50", Id = 0, Level = 50 },
	{ Key = "NightmareEscape", Id = 0, Stat = "NightmareEscapes", Count = 1 },
	{ Key = "CampaignClear", Id = 0, Stat = "CampaignClears", Count = 1 },
	{ Key = "Medic50", Id = 0, Stat = "Revives", Count = 50 },
	{ Key = "Elites100", Id = 0, Stat = "Elites", Count = 100 },
	{ Key = "Kills1000", Id = 0, Stat = "Kills", Count = 1000 },
}

local live = {}
for _, b in BADGES do
	if (tonumber(b.Id) or 0) > 0 then
		table.insert(live, b)
	end
end
if #live == 0 then
	return -- nothing to award until the owner sets an id
end

local given = {} -- [player] = {[badgeId] = true}

local function stats(player)
	local raw = player:GetAttribute("Stats")
	if type(raw) ~= "string" then
		return {}
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(t) == "table" then t else {}
end

local function earned(player, b, st)
	if b.Level then
		return (player:GetAttribute("Level") or 0) >= b.Level
	end
	if b.Attr then
		return player:GetAttribute(b.Attr) == true
	end
	if b.Stat then
		return (tonumber(st[b.Stat]) or 0) >= (b.Count or 1)
	end
	return false
end

local function award(player, id)
	local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, id)
	if ok and has then
		return
	end
	if not player.Parent then
		return
	end
	local okAward, err = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, id)
	if not okAward then
		warn("BadgeServer: could not award", id, err)
		given[player][id] = nil -- try again on the next change
	end
end

local function check(player)
	local mine = given[player]
	if not mine or player:GetAttribute("ProfileFailed") or player:GetAttribute("Level") == nil then
		return
	end
	local st = stats(player)
	for _, b in live do
		if not mine[b.Id] and earned(player, b, st) then
			mine[b.Id] = true
			task.spawn(award, player, b.Id)
		end
	end
end

local function onPlayer(player)
	given[player] = {}
	local pending = false
	local function soon()
		if pending then
			return
		end
		pending = true
		task.delay(1, function()
			pending = false
			if player.Parent then
				check(player)
			end
		end)
	end
	for _, name in { "Level", "Escaped", "Stats" } do
		player:GetAttributeChangedSignal(name):Connect(soon)
	end
	soon()
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	given[player] = nil
end)
