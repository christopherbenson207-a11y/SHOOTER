-- Relics: Mortuus' upgrade draft after every round (the lobby Endless pool plus four; numbers:
-- Config.Relics). When a round is cleared, Offer relics stand on sigils in the room most of the
-- standing squad is in. Everyone may take one before the next round starts (player attribute
-- RelicRound marks this round's pick; clients darken the sigils for whoever has picked). They
-- stack and last the run, as player attributes the systems read: RelicDamage, RelicHead (Weapons),
-- RelicHealth (Survivors), RelicArmor, RelicRegen, RelicSelfRevives, RelicReserve, RelicReload,
-- RelicSpeed, RelicLeech (EndlessServer heals on kills), RelicPoints (Economy); Relic_<id> counts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Util = require(ServerStorage.Endless.Util)
local Choices = require(ServerStorage.Endless.Choices)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)

local RELICS = Config.Relics

local Relics = {}

local offer = nil

function Relics.Reset(player: Player)
	for _, relic in RELICS.Pool do
		player:SetAttribute("Relic" .. relic.Stat, nil)
	end
	for id in RELICS.Pool do
		player:SetAttribute("Relic_" .. id, nil)
	end
	player:SetAttribute("RelicRound", nil)
end

function Relics.Apply(player: Player, id: string)
	local relic = RELICS.Pool[id]
	if not relic then
		return
	end
	player:SetAttribute("Relic_" .. id, (player:GetAttribute("Relic_" .. id) or 0) + 1)
	local key = "Relic" .. relic.Stat
	local value = (player:GetAttribute(key) or 0) + relic.Add
	if relic.Cap then
		value = math.min(value, relic.Cap)
	end
	player:SetAttribute(key, value)
	if relic.Stat == "Health" then
		Survivors.RefreshMaxHealth(player)
	elseif relic.Stat == "Speed" then
		local _, humanoid = Survivors.Parts(player)
		if humanoid and Survivors.IsStanding(player) then
			humanoid.WalkSpeed = Survivors.WalkSpeed(player)
		end
	elseif relic.Stat == "Reserve" then
		-- The bigger pouch comes filled.
		for _, tool in Arsenal.Tools(player) do
			Arsenal.Fill(player, tool)
		end
	end
end

function Relics.Clear()
	if offer then
		offer:Clear()
		offer = nil
	end
end

-- Up to n floor points in the room most standing players are in, near the middle of them.
local function spots(house, n)
	local rooms, best, bestCount = {}, nil, 0
	local sum, count = Vector3.zero, 0
	for _, p in Survivors.StandingPlayers() do
		local _, _, root = Survivors.Parts(p)
		local room = root and house:RoomAt(root.Position)
		if room then
			rooms[room] = (rooms[room] or 0) + 1
			if rooms[room] > bestCount then
				best, bestCount = room, rooms[room]
			end
			sum += root.Position
			count += 1
		end
	end
	best = best or house.Rooms[house.StartRoom]
	local near = if count > 0 then sum / count else nil
	local points = house:FloorPoints(best, n + 2, near)
	-- A small room (a hall full of doorways) may not have enough: the rest of its zone helps out.
	if #points < n then
		for _, id in house.Zones[best.Zone].Rooms do
			if id ~= best.Id then
				for _, p in house:FloorPoints(house.Rooms[id], n - #points, near) do
					table.insert(points, p)
				end
			end
		end
	end
	-- Not right under someone's feet: skip the nearest if there are spare points.
	while #points > n do
		table.remove(points, 1)
	end
	return points
end

function Relics.Offer(run, round: number)
	Relics.Clear()
	local ids = {}
	for id in RELICS.Pool do
		table.insert(ids, id)
	end
	table.sort(ids)
	Util.Shuffle(ids)
	local options = {}
	for i = 1, math.min(RELICS.Offer, #ids) do
		local relic = RELICS.Pool[ids[i]]
		table.insert(options, { Id = ids[i], Name = relic.Name, Text = relic.Text, Color = relic.Color })
	end
	local points = spots(run.House, #options)
	if #points == 0 then
		return
	end
	offer = Choices.Offer({
		Points = points,
		Options = options,
		Group = "Relic",
		Round = round,
		Hold = RELICS.HoldTime,
		OnPick = function(player, option)
			if not Survivors.IsStanding(player) or player:GetAttribute("RelicRound") == round then
				return false
			end
			player:SetAttribute("RelicRound", round)
			Relics.Apply(player, option.Id)
			Net.Get("Hud"):FireClient(player, "Notice", string.upper(option.Name) .. "  \u{00B7}  " .. option.Text)
			return false
		end,
	})
	Net.Get("Hud"):FireAllClients("Notice", "CHOOSE A RELIC")
end

return Relics
