-- Records each player's current input type (sent by the client's Platform module)
-- as the "InputMode" attribute, so server systems and analytics can split by platform.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VALID = { KeyboardAndMouse = true, Touch = true, Gamepad = true }

ReplicatedStorage.Remotes.SetInputMode.OnServerEvent:Connect(function(player, mode)
	if typeof(mode) == "string" and VALID[mode] then
		player:SetAttribute("InputMode", mode)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("InputMode", "KeyboardAndMouse")
end)
