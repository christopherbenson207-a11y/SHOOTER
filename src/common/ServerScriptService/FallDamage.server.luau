-- Fall damage. The client measures the drop (StarterCharacterScripts.FallWatch) and sends
-- Remotes.Fall with it; past GameConfig.Match.FallDamage.Safe studs it hurts through
-- PlayerHealth, the same as a hit. Only the faller is hurt, so trusting the number is fine;
-- it's still clamped and rate-limited.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Classes = require(ReplicatedStorage.Shared.Classes)

local CFG = GameConfig.Match.FallDamage
local last = {}

ReplicatedStorage.Remotes.Fall.OnServerEvent:Connect(function(player, drop)
	if typeof(drop) ~= "number" or drop ~= drop then
		return
	end
	local now = os.clock()
	if last[player] and now - last[player] < 0.5 then
		return
	end
	last[player] = now
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or root.Anchored or character:GetAttribute("Grabbed") or player:GetAttribute("Cutscene") then
		return
	end
	local damage = math.floor((math.min(drop, 200) - CFG.Safe) * CFG.PerStud * Classes.Perk(player, "FallDamage"))
	if damage > 0 then
		PlayerHealth.Damage(player, damage, root.Position - Vector3.new(0, 3, 0), "Fall")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)
