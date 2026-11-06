-- FrontLobby (5 Nov 2026): LOBBY on FRONTLINE's end card (StarterPlayerScripts.MatchHud, Shared.EndCard).
-- Remotes.ToLobby is made here. Only while a match is over (WaveState FrontEnd): the profile is saved and handed
-- over first (as WarServer's finish does), then the one player goes back to the lobby place. In Studio the teleport
-- fails and the lock is taken back, so nothing changes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Profile = require(ServerStorage.Modules.Profile)

local LOBBY = GameConfig.War.Campaign.LobbyPlaceId

local remote = Instance.new("RemoteEvent")
remote.Name = "ToLobby"
remote.Parent = ReplicatedStorage.Remotes

local busy = {}

remote.OnServerEvent:Connect(function(player)
	if busy[player] or workspace:GetAttribute("WaveState") ~= "FrontEnd" then
		return
	end
	busy[player] = true
	pcall(Profile.SaveNow, player, true)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(LOBBY, { player })
	end)
	if not ok then
		warn("FrontLobby: back to the lobby failed (" .. tostring(err) .. ")")
		if player.Parent then
			task.spawn(Profile.Reclaim, player)
		end
		task.wait(3)
		busy[player] = nil
	end
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
end)
