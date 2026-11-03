-- Match points (Call of Duty Zombies): earned by shooting zombies and repairing windows,
-- spent on debris, guns, supplies and the mystery crate. The server owns them; clients read
-- the player attribute "Points" (the HUD ticks it up quietly, no floating numbers). PointsEarned
-- adds up everything earned this match (MatchServer pays a share of it out as Scrip).
-- Numbers: GameConfig.Match.Points.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local CFG = GameConfig.Match.Points

local Points = {}

function Points.Get(player)
	return player:GetAttribute("Points") or 0
end

function Points.Add(player, amount)
	if amount > 0 and player.Parent then
		-- Scavenger (an Endless relic, ServerStorage.Modules.Relics) pays RelicPoints more.
		amount = math.floor(amount * (1 + (player:GetAttribute("RelicPoints") or 0)) + 0.5)
		player:SetAttribute("Points", Points.Get(player) + amount)
		player:SetAttribute("PointsEarned", (player:GetAttribute("PointsEarned") or 0) + amount)
	end
end

function Points.CanAfford(player, cost)
	return Points.Get(player) >= cost
end

-- Takes cost from the player. Returns false (and takes nothing) if they can't afford it.
function Points.Spend(player, cost)
	if not Points.CanAfford(player, cost) then
		return false
	end
	player:SetAttribute("Points", Points.Get(player) - cost)
	return true
end

function Points.Reset(player)
	player:SetAttribute("Points", CFG.Start)
	player:SetAttribute("PointsEarned", 0)
end

function Points.Start()
	local function onPlayer(player)
		if player:GetAttribute("Points") == nil then
			Points.Reset(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

return Points
