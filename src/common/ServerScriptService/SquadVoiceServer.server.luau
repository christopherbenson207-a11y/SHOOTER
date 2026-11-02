--!strict
-- Squad callouts (GameConfig.Voice): a client tells the server which line it just said
-- (Remotes.Callout); this checks it and passes it to everyone else, who play it from that
-- player's head (SquadVoiceClient).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Callout") :: RemoteEvent

local CFG = GameConfig.Voice
local voices: { [string]: boolean } = {}
for _, name in CFG.Voices do
	voices[name] = true
end

local lastAt: { [Player]: number } = {}

remote.OnServerEvent:Connect(function(player: Player, key: any, index: any, voice: any)
	if typeof(key) ~= "string" or not CFG.Keys[key] then
		return
	end
	if typeof(index) ~= "number" or index ~= index or index < 1 or index > 8 or index % 1 ~= 0 then
		return
	end
	if typeof(voice) ~= "string" or not voices[voice] then
		return
	end
	if player:GetAttribute("InMatch") ~= true then
		return
	end
	-- A higher-priority line may cut in early, so half the gap is the floor.
	local now = os.clock()
	if now - (lastAt[player] or -math.huge) < CFG.Gap * 0.5 then
		return
	end
	lastAt[player] = now
	for _, other in Players:GetPlayers() do
		if other ~= player then
			remote:FireClient(other, player, key, index, voice)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastAt[player] = nil
end)
