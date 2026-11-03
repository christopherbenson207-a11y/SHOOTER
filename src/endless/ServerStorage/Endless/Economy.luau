-- Points (Call of Duty Zombies' economy). A player's points are the player attribute Points; the
-- HUD reads it. Add pays with this moment's multipliers: DOUBLE PAY (workspace DoublePayUntil)
-- and the Scavenger relic (player RelicPoints). Bonus pays a flat amount (power-ups). Spend takes
-- points if there are enough and tells the player's HUD when there aren't ("Broke").
-- Run stats are player attributes too: Kills, Headshots, Downs, Revives, Earned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)

local Economy = {}

local STATS = { "Kills", "Headshots", "Downs", "Revives", "Earned" }

function Economy.Get(player: Player): number
	return player:GetAttribute("Points") or 0
end

function Economy.Reset(player: Player, points: number?)
	player:SetAttribute("Points", points or Config.Run.StartPoints)
	for _, stat in STATS do
		player:SetAttribute(stat, 0)
	end
end

function Economy.Count(player: Player, stat: string, by: number?)
	player:SetAttribute(stat, (player:GetAttribute(stat) or 0) + (by or 1))
end

function Economy.Multiplier(player: Player): number
	local mult = 1 + (player:GetAttribute("RelicPoints") or 0)
	if (workspace:GetAttribute("DoublePayUntil") or 0) > workspace:GetServerTimeNow() then
		mult *= 2
	end
	return mult
end

function Economy.Add(player: Player, amount: number): number
	local paid = math.floor(amount * Economy.Multiplier(player) + 0.5)
	player:SetAttribute("Points", Economy.Get(player) + paid)
	Economy.Count(player, "Earned", paid)
	return paid
end

function Economy.Bonus(player: Player, amount: number)
	player:SetAttribute("Points", Economy.Get(player) + amount)
	Economy.Count(player, "Earned", amount)
end

function Economy.Spend(player: Player, amount: number): boolean
	local have = Economy.Get(player)
	if have < amount then
		Net.Get("Hud"):FireClient(player, "Broke")
		return false
	end
	player:SetAttribute("Points", have - amount)
	return true
end

-- Going down costs a share of what you have (Config.Player.Downed.PointsLost).
function Economy.Lose(player: Player, share: number)
	local have = Economy.Get(player)
	player:SetAttribute("Points", have - math.floor(have * share / 10 + 0.5) * 10)
end

return Economy
