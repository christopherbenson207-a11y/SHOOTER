-- Holds players in the menu (StarterPlayerScripts.MenuClient) until they press PLAY: characters
-- don't load on join. PLAY (Remotes.Menu "Play", mode) spawns you in that mode and you
-- respawn there after dying (Players.RespawnTime, set by PlayerHealth), unless the match holds
-- respawns (workspace attribute HoldRespawns, set by MatchServer, which brings the dead back
-- at the next intermission). Each player's avatar
-- is built once into ReplicatedStorage.MenuAvatars/<UserId> for the menu room to show.
-- CAMPAIGN (Remotes.Menu "Campaign") teleports you to Operation Last Light, the campaign's own
-- place (GameConfig.War.Campaign.PlaceId), into any of its servers with room: a squad of four,
-- a joining player takes an NPC soldier's place. If the teleport can't start (Studio, or it
-- failed), the menu comes back (Remotes.Menu "CampaignFailed").
-- One match per server (horror-shooter/MODES-V3.md, GameConfig.Matchmaking): the place's public
-- servers are the lobby, and PLAY (Remotes.Menu "Play", mode, "Private" or "Quick") sends you to
-- a match server, a reserved server of this same place, with TeleportData { Mode, Code }. Private
-- reserves a new one; Quick joins an open match of that mode listed in MemoryStore, or reserves
-- one if none has room. A match server (workspace attribute MatchServer) never shows the menu:
-- whoever arrives goes straight in, and the first arrival's mode locks the server and strips the
-- map (ServerStorage.Modules.ModeSetup). In Studio there's no teleport, so the first PLAY locks
-- the Studio server the same way and later PLAYs join that mode.
-- Player attributes: InMatch (bool), Mode (one of GameConfig.Menu.Modes).

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Uniform = require(game:GetService("ServerStorage").Modules.Uniform)
local Profile = require(game:GetService("ServerStorage").Modules.Profile)
local ModeSetup = require(game:GetService("ServerStorage").Modules.ModeSetup)
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.Menu
local MATCH = GameConfig.Matchmaking

local matchServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
workspace:SetAttribute("MatchServer", matchServer or nil)
local openMap = nil
pcall(function()
	openMap = MemoryStoreService:GetSortedMap(MATCH.OpenMap)
end)
local accessCode = nil -- this match server's own code, from the first arrival's TeleportData

Players.CharacterAutoLoads = false

local avatars = Instance.new("Folder")
avatars.Name = "MenuAvatars"
avatars.Parent = ReplicatedStorage

local function buildAvatar(player)
	-- In the police uniform, like the character they'll play.
	local ok, model = pcall(function()
		local description = Uniform.Description(player.UserId)
		if description then
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end
		return Players:CreateHumanoidModelFromUserId(player.UserId)
	end)
	if not ok or not model then
		warn("MenuServer: no avatar for", player.Name, model)
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	model.Name = tostring(player.UserId)
	model.Parent = avatars
end

local function onCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Once(function()
		task.delay(Players.RespawnTime, function()
			if player.Parent and player:GetAttribute("InMatch") and player.Character == character
				and not workspace:GetAttribute("HoldRespawns")
			then
				Uniform.Load(player)
			end
		end)
	end)
end

-- A mode the player may play (an Unlock needs its Profile flag), else the menu's first.
local function allowedMode(player, mode)
	local rules = GameConfig.Modes[mode or ""]
	if not table.find(CFG.Modes, mode) or not rules or (rules.Unlock and not Profile.Get(player)[rules.Unlock]) then
		return CFG.Modes[1]
	end
	return mode
end

local function goIn(player, mode)
	player:SetAttribute("Mode", ModeSetup.Apply(mode))
	player:SetAttribute("InMatch", true)
	Uniform.Load(player)
end

-- A match server: whoever arrives goes straight into the server's mode.
local function arrive(player)
	local data = player:GetJoinData().TeleportData
	local mode = type(data) == "table" and data.Mode or nil
	if not accessCode and type(data) == "table" and type(data.Code) == "string" then
		accessCode = data.Code
	end
	goIn(player, allowedMode(player, mode))
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	task.spawn(buildAvatar, player)
	if matchServer then
		task.spawn(arrive, player)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	local model = avatars:FindFirstChild(tostring(player.UserId))
	if model then
		model:Destroy()
	end
end)

local sending = {} -- [player] = true while their campaign teleport is under way

local function campaign(player)
	if player:GetAttribute("InMatch") or sending[player] then
		return
	end
	sending[player] = true
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(GameConfig.War.Campaign.PlaceId, { player })
	end)
	if not ok then
		sending[player] = nil
		warn("MenuServer: no campaign teleport for", player.Name, err)
		Remotes.Menu:FireClient(player, "CampaignFailed")
	end
end

TeleportService.TeleportInitFailed:Connect(function(player)
	if sending[player] then
		sending[player] = nil
		Remotes.Menu:FireClient(player, "CampaignFailed")
	end
end)

-- An open match of this mode with room (Quick), from the MemoryStore list.
local function openMatch(mode)
	if not openMap then
		return nil
	end
	local ok, items = pcall(function()
		return openMap:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	if not ok then
		return nil
	end
	for _, item in items do
		local v = item.value
		if type(v) == "table" and v.Mode == mode and type(v.Code) == "string" and (v.Count or 0) < MATCH.MaxPlayers then
			return v.Code
		end
	end
	return nil
end

-- PLAY from a lobby server: off to a match server of the mode.
local function sendToMatch(player, mode, how)
	if sending[player] then
		return
	end
	sending[player] = true
	local ok, err = pcall(function()
		local code = if how == "Quick" then openMatch(mode) else nil
		code = code or TeleportService:ReserveServer(game.PlaceId)
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({ Mode = mode, Code = code })
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		sending[player] = nil
		warn("MenuServer: no match teleport for", player.Name, err)
		Remotes.Menu:FireClient(player, "CampaignFailed")
	end
end

-- A match server lists itself while it has room, so QUICK JOIN can find it.
if matchServer then
	local function unlist()
		if openMap then
			pcall(function()
				openMap:RemoveAsync(game.JobId)
			end)
		end
	end
	task.spawn(function()
		while true do
			local mode = workspace:GetAttribute("ServerMode")
			local state = workspace:GetAttribute("WaveState")
			local ending = state == "Rescue" or state == "Attire" or state == "GameOver"
			if openMap and mode and accessCode and #Players:GetPlayers() < MATCH.MaxPlayers and not ending then
				pcall(function()
					openMap:SetAsync(game.JobId, { Mode = mode, Code = accessCode, Count = #Players:GetPlayers() }, MATCH.Refresh * 2 + 5)
				end)
			else
				unlist()
			end
			task.wait(MATCH.Refresh)
		end
	end)
	game:BindToClose(unlist)
end

-- The end of a run on a match server: back to a lobby server. Elsewhere (Studio) the menu.
local toLobby = Instance.new("BindableEvent")
toLobby.Name = "ToLobby"
toLobby.Parent = game:GetService("ServerStorage"):FindFirstChild("Events") or game:GetService("ServerStorage")
toLobby.Event:Connect(function(player)
	local ok = matchServer and pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	if not ok then
		Remotes.Menu:FireClient(player, "Show")
	end
end)
Players.PlayerRemoving:Connect(function(player)
	sending[player] = nil
end)

Remotes.Menu.OnServerEvent:Connect(function(player, action, mode, how)
	if action == "Campaign" then
		campaign(player)
		return
	end
	if action ~= "Play" or player:GetAttribute("InMatch") then
		return
	end
	mode = allowedMode(player, mode)
	if matchServer or RunService:IsStudio() then
		-- Studio stands in for a match server: the first PLAY locks its mode (ModeSetup).
		goIn(player, mode)
	else
		sendToMatch(player, mode, how)
	end
end)
