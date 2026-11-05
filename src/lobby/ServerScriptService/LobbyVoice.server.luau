--!strict
-- ServerScriptService.LobbyVoice (lobby place only, 4 Nov 2026; user: "allow voice chat in lobby").
-- The lobby spawns no characters (Players.CharacterAutoLoads = false), so Roblox's default proximity voice has no
-- emitter and nobody is heard. Here every microphone (the AudioDeviceInput that VoiceChatService creates under each
-- Player, UseAudioApi = Enabled) is wired into one shared, non-spatial output, and each microphone's access list allows
-- only the speaker's party (attribute PartyId, set by ServerStorage.Modules.Party). Squadmates hear each other at equal
-- volume; strangers in the server never hear you, and you never hear yourself.
-- Roblox still decides who may use voice (13+, age verified, opted in) and keeps its own mute and report tools.
-- Needs: Experience Settings > Communication > voice chat on (a universe setting), Players.MaxPlayers <= 100 (lobby: 60),
-- VoiceChatService.EnableDefaultVoice = true and UseAudioApi = Enabled (both already set in the lobby).
-- Routing only restricts: it never lets two players talk who could not already. Reviewed, not run with two voices.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local folder = Instance.new("Folder")
folder.Name = "LobbyVoice"
local mix = Instance.new("AudioFader")
mix.Name = "Mix"
mix.Parent = folder
local out = Instance.new("AudioDeviceOutput") -- Player = nil: plays on every client's speakers
out.Name = "Out"
out.Parent = folder
local toOut = Instance.new("Wire")
toOut.SourceInstance = mix
toOut.TargetInstance = out
toOut.Parent = out
folder.Parent = SoundService

local wires: { [Player]: Wire } = {}

local function micOf(player: Player): AudioDeviceInput?
	return player:FindFirstChildWhichIsA("AudioDeviceInput")
end

-- Who may hear this player: the other members of their party.
local function listeners(player: Player): { number }
	local ids = {}
	local partyId = player:GetAttribute("PartyId")
	if partyId == nil then
		return ids
	end
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("PartyId") == partyId then
			table.insert(ids, other.UserId)
		end
	end
	return ids
end

local function refreshAll()
	for _, player in Players:GetPlayers() do
		local mic = micOf(player)
		if mic then
			mic.AccessType = Enum.AccessModifierType.Allow
			mic:SetUserIdAccessList(listeners(player))
			local wire = wires[player]
			if not wire or wire.SourceInstance ~= mic then
				if wire then
					wire:Destroy()
				end
				local w = Instance.new("Wire")
				w.Name = tostring(player.UserId)
				w.SourceInstance = mic
				w.TargetInstance = mix
				w.Parent = mix
				wires[player] = w
			end
		end
	end
end

-- Party changes arrive in bursts (a join moves several attributes): refresh once per frame at most.
local queued = false
local function queue()
	if queued then
		return
	end
	queued = true
	task.defer(function()
		queued = false
		refreshAll()
	end)
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("PartyId"):Connect(queue)
	player.ChildAdded:Connect(function(child)
		if child:IsA("AudioDeviceInput") then
			queue()
		end
	end)
	queue()
end

Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player)
	local wire = wires[player]
	if wire then
		wire:Destroy()
	end
	wires[player] = nil
	queue()
end)
for _, player in Players:GetPlayers() do
	watch(player)
end
