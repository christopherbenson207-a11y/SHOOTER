-- The front end's server side (DATA, 2 Nov 2026): characters, the menu, parties and deploying. Contract:
-- horror-shooter/menu/CONTRACTS.md sections 4, 5 and 6; MENU-PLAN 9.1.
--
-- Server role (workspace attribute ServerRole): a reserved server of this place (PrivateServerId set, no owner) is a
-- "Match" server; every other server is a "Lobby". Public lobbies never run a match: DEPLOY teleports the party to a
-- reserved server of this same place with teleport data {Mode, Variant, Mission, Join, PartyId, Members, Leader}. In
-- Studio (TeleportService does not work there) the deploy runs locally: ServerRole becomes "Match" and the match
-- starts in this server; CONTINUE turns it back into the lobby.
--
-- Remotes.Menu, client to server:
--   "Deploy", {Mode = <a GameConfig.Menu.Modes key> | "Campaign", Mission, Join}   party leader; starts the countdown
--     (Modes v3: Outbreak, Defend, Endless, Nightmare; Variant is unused, but an old {Mode = "Defend", Variant =
--     "Nightmare" | "Endless"} still means that mode)
--   "Cancel" | "Ready", bool | "Status", "IDLE" | "LOADOUT" | "STORE" | "Redeploy" | "Continue" | "FirstDeploy"
--   "Rejoin"                    back into the reserved match server this player's party is still playing in
--   old MenuClient: "Play", mode (a solo deploy of that mode) and "Campaign" (a campaign quick join)
-- Server to client: "Show", "Aar" (Progression), "Deploying" {Seconds, Mode, Variant, Mission, Join},
--   "DeployFailed" reason ("NotLeader" | "Locked" | "Unknown" | "Teleport" | "Studio" | "Rejoin"), "Unlocked"
--   (Progression), "CampaignFailed" (old MenuClient).
-- Campaign: Join "Quick" (or nil) teleports the party with one TeleportAsync to a public campaign server (no reserved
-- server, Mission ignored); "Squad" reserves a campaign server for the party and carries Mission.
-- Before every teleport each player's profile is saved and released (Profile.SaveNow(player, true)); a teleport
-- that fails takes the profile back (Profile.Reclaim) and sends "DeployFailed".
-- A Match server reads each arrival's join data, waits for the whole party (at most 20 s), consumes one Squad Boost
-- for the whole party if any member holds one (BoostActive for that match), opens each ledger, fires
-- ServerStorage.Events.StartMatch(mode, variant, players, partyId) and lets everyone in. Late or rejoining members
-- are let in at once. After MatchEnded: "Redeploy" (leader; members mark READY) restarts the same mode here;
-- "Continue" (leader: the whole party; a member: alone) teleports back to a public lobby together.
-- The reserved server's access code is kept in MemoryStore by party id and by user id, so a dropped member can rejoin
-- from a lobby (the player attribute Rejoin holds the mode while that is possible).
-- Characters never load on join (Players.CharacterAutoLoads = false). A player who dies while InMatch respawns after
-- Players.RespawnTime unless workspace HoldRespawns is set (MatchServer owns respawns then).
-- Every match start (Match servers and Studio) first calls Modules.ModeSetup.Apply(mode), which locks the server to
-- that mode for its life (in Studio a later deploy of another mode plays the locked one).
-- Player attributes: InMatch, Mode (the GameConfig.Modes key), PartyId (Party),
-- BoostActive, Rejoin. Workspace: ServerRole, MatchMode, MatchVariant, PartyId.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Uniform = require(ServerStorage.Modules.Uniform)
local Profile = require(ServerStorage.Modules.Profile)
local Party = require(ServerStorage.Modules.Party)
local Progression = require(ServerStorage.Modules.Progression)
local okSetup, ModeSetup = pcall(function()
	return require(ServerStorage.Modules.ModeSetup)
end)
if not okSetup then
	warn("MenuServer: no ModeSetup", ModeSetup)
	ModeSetup = nil
end
local Remotes = ReplicatedStorage.Remotes
local Events = ServerStorage:WaitForChild("Events")

local CFG = GameConfig.Menu
local CAMPAIGN_PLACE = GameConfig.War.Campaign.PlaceId -- 78870312741411
local STUDIO = RunService:IsStudio()
local COUNTDOWN = 5
local WAIT_PARTY = 20
local REJOIN_TTL = 3 * 3600

Players.CharacterAutoLoads = false

local IS_MATCH = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
workspace:SetAttribute("ServerRole", if IS_MATCH then "Match" else "Lobby")

local partyMap, userMap = nil, nil
pcall(function()
	partyMap = MemoryStoreService:GetSortedMap("LastLightParties")
	userMap = MemoryStoreService:GetSortedMap("LastLightRejoin")
end)

-- Characters -------------------------------------------------------------------------------------------------------

local avatars = Instance.new("Folder")
avatars.Name = "MenuAvatars"
avatars.Parent = ReplicatedStorage

local function buildAvatar(player)
	-- In the uniform, like the character they will play (kept for anything still reading MenuAvatars).
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

-- Modes ------------------------------------------------------------------------------------------------------------

-- Modes v3: the mode keys are GameConfig.Modes keys; the menu offers GameConfig.Menu.Modes plus the Campaign.
local function isMode(mode)
	return type(mode) == "string" and (mode == "Campaign" or GameConfig.Modes[mode] ~= nil)
end

-- The GameConfig.Modes key for a request (an old {Defend, Variant = Nightmare} -> "Nightmare").
local function legacyMode(mode, variant)
	if (variant == "Nightmare" or variant == "Endless") and GameConfig.Modes[variant] then
		return variant
	end
	return mode
end

-- The first mode of the PLAY screen (the old Defend house run is OUTBREAK).
local function firstMode()
	return CFG.Modes[1] or "Outbreak"
end

local function unlocked(player, legacy)
	local rules = GameConfig.Modes[legacy]
	if not rules then
		return false
	end
	if rules.Unlock then
		local data = Profile.Get(player)
		return data ~= nil and data[rules.Unlock] == true
	end
	return true
end

-- A validated deploy request, or nil and a reason.
local function cleanRequest(party, req)
	if type(req) ~= "table" then
		return nil, "Unknown"
	end
	local mode = if isMode(req.Mode) then legacyMode(req.Mode, req.Variant) else nil
	if not mode then
		return nil, "Unknown"
	end
	local out = { Mode = mode }
	if mode == "Campaign" then
		out.Join = if req.Join == "Squad" then "Squad" else "Quick"
		if out.Join == "Squad" then
			local m = tonumber(req.Mission)
			out.Mission = if m and m % 1 == 0 and m >= 1 and m <= 3 then m else 1
		end
	end
	if mode ~= "Campaign" then
		if not table.find(CFG.Modes, mode) then
			return nil, "Unknown"
		end
		for _, m in party.Members do
			if not unlocked(m, mode) then
				return nil, "Locked"
			end
		end
	end
	return out
end

-- Starting a match in this server (Match servers, and Studio's local deploy) ----------------------------------------

local match = nil -- {Mode, Variant, Mission, PartyId, Players = {}, Started = bool}

local function letIn(player)
	if not player.Parent or player:GetAttribute("InMatch") then
		return
	end
	player:SetAttribute("Mode", legacyMode(match.Mode, match.Variant))
	player:SetAttribute("InMatch", true)
	Uniform.Load(player)
end

-- One Squad Boost for the whole party: the leader's first, else the first member holding one.
local function consumeBoost(party, players)
	local order = {}
	if party and party.Leader then
		table.insert(order, party.Leader)
	end
	for _, p in players do
		if not table.find(order, p) then
			table.insert(order, p)
		end
	end
	for _, p in order do
		local data = Profile.WaitFor(p, 10)
		if data and p.Parent and table.find(players, p) and (data.Boosts or 0) > 0 then
			data.Boosts -= 1
			p:SetAttribute("Boosts", data.Boosts)
			Profile.Touch(p)
			for _, q in players do
				q:SetAttribute("BoostActive", true)
			end
			return true
		end
	end
	return false
end

local function startMatch(players)
	if not match or match.Started then
		return
	end
	match.Started = true
	local live = {}
	for _, p in players do
		if p.Parent then
			table.insert(live, p)
		end
	end
	match.Players = live
	if ModeSetup then
		-- one mode per server (MODES-V3): strip the map to this mode; a locked server keeps its mode
		local ok, locked = pcall(ModeSetup.Apply, legacyMode(match.Mode, match.Variant))
		if ok and type(locked) == "string" and GameConfig.Modes[locked] then
			match.Mode, match.Variant = locked, nil
		elseif not ok then
			warn("MenuServer: ModeSetup.Apply failed", locked)
		end
	end
	workspace:SetAttribute("ServerRole", "Match")
	workspace:SetAttribute("MatchMode", match.Mode)
	workspace:SetAttribute("MatchVariant", match.Variant)
	workspace:SetAttribute("PartyId", match.PartyId)
	consumeBoost(Party.ById(match.PartyId), live)
	for _, p in live do
		p:SetAttribute("Mode", legacyMode(match.Mode, match.Variant))
		Progression.OpenLedger(p, match.Mode, match.Variant)
	end
	Events.StartMatch:Fire(match.Mode, match.Variant, live, match.PartyId)
	for _, p in live do
		letIn(p)
	end
end

-- Teleports --------------------------------------------------------------------------------------------------------

local sending = {} -- [player] = what they were sent to (until they leave or the teleport fails)

local function teleportFailed(players, reason)
	for _, p in players do
		if p.Parent then
			sending[p] = nil
			task.spawn(Profile.Reclaim, p)
			Remotes.Menu:FireClient(p, "DeployFailed", reason or "Teleport")
			Remotes.Menu:FireClient(p, "CampaignFailed")
		end
	end
	local party = players[1] and Party.Of(players[1])
	if party then
		party.State = "Idle"
		party.Count = nil
		Party.Changed(party)
	end
end

local function remember(partyId, code, privateId, players, data)
	if not partyMap or not userMap or not code then
		return
	end
	task.spawn(function()
		local entry = { Code = code, PrivateServerId = privateId, Mode = data.Mode, Variant = data.Variant, At = os.time() }
		pcall(partyMap.SetAsync, partyMap, partyId, entry, REJOIN_TTL)
		for _, p in players do
			pcall(userMap.SetAsync, userMap, "u" .. p.UserId, { PartyId = partyId, Code = code, Mode = data.Mode,
				Variant = data.Variant, Members = data.Members, Leader = data.Leader }, REJOIN_TTL)
		end
	end)
end

local function teleport(players, req, partyId, leader)
	local members = {}
	for _, p in players do
		table.insert(members, p.UserId)
		sending[p] = req
		-- save and release every profile first, so the next server loads what was saved here
		task.spawn(Profile.SaveNow, p, true)
	end
	local t = os.clock()
	while os.clock() - t < 8 do
		local done = true
		for _, p in players do
			if Profile.Holds(p) then
				done = false
			end
		end
		if done then
			break
		end
		task.wait(0.2)
	end
	local data = {
		Mode = req.Mode, Variant = req.Variant, Mission = req.Mission, Join = req.Join,
		PartyId = partyId, Members = members, Leader = leader and leader.UserId,
	}
	local placeId = game.PlaceId
	local options = Instance.new("TeleportOptions")
	if req.Mode == "Campaign" then
		placeId = CAMPAIGN_PLACE
		options.ShouldReserveServer = req.Join == "Squad"
	elseif not req.Continue then
		options.ShouldReserveServer = true
	end
	options:SetTeleportData(data)
	local ok, result = pcall(TeleportService.TeleportAsync, TeleportService, placeId, players, options)
	if not ok then
		warn("MenuServer: teleport failed", result)
		teleportFailed(players, "Teleport")
		return
	end
	if options.ShouldReserveServer and placeId == game.PlaceId and typeof(result) == "Instance" then
		remember(partyId, result.ReservedServerAccessCode, result.PrivateServerId, players, data)
	end
end

TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
	if sending[player] then
		warn("MenuServer: teleport did not start for", player.Name, message)
		teleportFailed({ player }, "Teleport")
	end
end)

-- Deploying (lobby) ------------------------------------------------------------------------------------------------

local function deployNow(party, req)
	local players = {}
	for _, m in party.Members do
		if m.Parent then
			table.insert(players, m)
		end
	end
	if #players == 0 then
		return
	end
	party.State = "Deploying"
	party.Count = 0
	Party.Changed(party)
	if STUDIO then
		-- TeleportService does not work in Studio: run the match here
		if req.Mode == "Campaign" then
			teleportFailed(players, "Studio")
			return
		end
		match = { Mode = req.Mode, Variant = req.Variant, Mission = req.Mission, PartyId = party.Id, Players = {}, Started = false }
		startMatch(players)
		return
	end
	teleport(players, req, party.Id, party.Leader)
end

local countdowns = {} -- [party] = token

local function deploy(player, req)
	if STUDIO and match and match.Started and not player:GetAttribute("InMatch") then
		-- Studio's local match is running (the old menu came back with "Show"): join it, as the old menu did
		Progression.OpenLedger(player, match.Mode, match.Variant)
		letIn(player)
		return
	end
	if IS_MATCH or (match and match.Started) then
		return
	end
	if player:GetAttribute("InMatch") or sending[player] then
		return
	end
	local party = Party.Of(player) or Party.Solo(player)
	if party.Leader ~= player then
		Remotes.Menu:FireClient(player, "DeployFailed", "NotLeader")
		return
	end
	if party.State ~= "Idle" then
		return
	end
	local clean, why = cleanRequest(party, req)
	if not clean then
		Remotes.Menu:FireClient(player, "DeployFailed", why)
		return
	end
	party.State = "Countdown"
	party.Mode, party.Variant, party.Mission, party.Join = clean.Mode, clean.Variant, clean.Mission, clean.Join
	local token = {}
	countdowns[party] = token
	local seconds = if #party.Members > 1 then COUNTDOWN else math.min(COUNTDOWN, 3)
	for n = seconds, 1, -1 do
		if countdowns[party] ~= token or party.State ~= "Countdown" then
			return
		end
		party.Count = n
		Party.Changed(party)
		for _, m in party.Members do
			Remotes.Menu:FireClient(m, "Deploying", { Seconds = n, Mode = clean.Mode, Variant = clean.Variant,
				Mission = clean.Mission, Join = clean.Join })
		end
		task.wait(1)
	end
	if countdowns[party] ~= token or party.State ~= "Countdown" then
		return
	end
	countdowns[party] = nil
	deployNow(party, clean)
end

local function cancel(player)
	local party = Party.Of(player)
	if party and party.State == "Countdown" then
		countdowns[party] = nil
		party.State = "Idle"
		party.Count = nil
		Party.Changed(party)
	end
end

-- After a match (Match servers and Studio) -------------------------------------------------------------------------

local ended = false
Events:WaitForChild("MatchEnded").Event:Connect(function()
	ended = true
end)

local function redeploy(player)
	if not match or not match.Started or not ended then
		return
	end
	local party = Party.Of(player)
	if party and party.Leader ~= player and #party.Members > 1 then
		Party.SetStatus(player, "READY")
		return
	end
	ended = false
	match.Started = false
	local players = {}
	for _, p in (party and party.Members or { player }) do
		if p.Parent then
			table.insert(players, p)
			p:SetAttribute("InMatch", nil)
			p:SetAttribute("BoostActive", nil)
		end
	end
	startMatch(players)
end

local function backToLobby(players)
	for _, p in players do
		p:SetAttribute("InMatch", nil)
		p:SetAttribute("BoostActive", nil)
		if p.Character then
			p.Character:Destroy()
			p.Character = nil
		end
		Remotes.Menu:FireClient(p, "Show")
	end
end

local function continueRun(player)
	if not match or not ended then
		return
	end
	local party = Party.Of(player)
	local players = { player }
	if party and party.Leader == player then
		players = {}
		for _, m in party.Members do
			if m.Parent then
				table.insert(players, m)
			end
		end
	end
	if STUDIO then
		match = nil
		ended = false
		workspace:SetAttribute("ServerRole", "Lobby")
		workspace:SetAttribute("MatchMode", nil)
		workspace:SetAttribute("MatchVariant", nil)
		workspace:SetAttribute("PartyId", nil)
		backToLobby(players)
		if party then
			party.State = "Idle"
			party.Count = nil
			Party.Changed(party)
		end
		return
	end
	if party and party.Leader ~= player then
		Party.Solo(player)
	end
	local req = { Mode = match.Mode, Variant = match.Variant, Continue = true }
	local p1 = Party.Of(players[1])
	teleport(players, req, p1 and p1.Id or "", p1 and p1.Leader)
end

-- Match server: arrivals --------------------------------------------------------------------------------------------

local expected = nil -- {[userId] = true}
local firstArrival = nil

local function arrive(player)
	local joinData = player:GetJoinData()
	local td = type(joinData) == "table" and joinData.TeleportData
	if type(td) ~= "table" then
		td = {}
	end
	if not match then
		local mode = if isMode(td.Mode) and td.Mode ~= "Campaign" then legacyMode(td.Mode, td.Variant) else firstMode()
		match = {
			Mode = mode,
			Variant = nil,
			Mission = td.Mission,
			PartyId = type(td.PartyId) == "string" and td.PartyId ~= "" and td.PartyId or ("solo-" .. player.UserId),
			Players = {},
			Started = false,
		}
		expected = {}
		for _, id in (type(td.Members) == "table" and td.Members or {}) do
			expected[tonumber(id) or 0] = true
		end
		expected[player.UserId] = true
		firstArrival = os.clock()
	end
	Party.Adopt(player, match.PartyId, td.Leader)
	Profile.WaitFor(player, 15)
	if match.Started then
		Progression.OpenLedger(player, match.Mode, match.Variant)
		letIn(player)
		return
	end
	-- everyone expected here? start; else the timer below starts with whoever came
	for id in expected do
		if not Players:GetPlayerByUserId(id) then
			return
		end
	end
	startMatch(Players:GetPlayers())
end

if IS_MATCH then
	task.spawn(function()
		while true do
			task.wait(1)
			if match and not match.Started and firstArrival and os.clock() - firstArrival >= WAIT_PARTY then
				startMatch(Players:GetPlayers())
			end
		end
	end)
end

-- Lobby: rejoin offer ----------------------------------------------------------------------------------------------

local rejoin = {} -- [player] = entry

local function checkRejoin(player)
	if IS_MATCH or not userMap then
		return
	end
	local ok, entry = pcall(userMap.GetAsync, userMap, "u" .. player.UserId)
	if ok and type(entry) == "table" and entry.Code and player.Parent then
		rejoin[player] = entry
		player:SetAttribute("Rejoin", entry.Mode or firstMode())
	end
end

local function doRejoin(player)
	local entry = rejoin[player]
	if not entry or STUDIO or sending[player] or player:GetAttribute("InMatch") then
		return
	end
	sending[player] = entry
	Profile.SaveNow(player, true)
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = entry.Code
	options:SetTeleportData({ Mode = entry.Mode, Variant = entry.Variant, PartyId = entry.PartyId,
		Members = entry.Members, Leader = entry.Leader })
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if not ok then
		warn("MenuServer: rejoin failed", err)
		rejoin[player] = nil
		player:SetAttribute("Rejoin", nil)
		pcall(userMap.RemoveAsync, userMap, "u" .. player.UserId)
		teleportFailed({ player }, "Rejoin")
	end
end

-- Players ----------------------------------------------------------------------------------------------------------

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	task.spawn(buildAvatar, player)
	if IS_MATCH then
		task.spawn(arrive, player)
	else
		task.spawn(checkRejoin, player)
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
	sending[player] = nil
	rejoin[player] = nil
end)

-- Remotes.Menu -----------------------------------------------------------------------------------------------------

Remotes.Menu.OnServerEvent:Connect(function(player, action, arg)
	if action == "Deploy" then
		task.spawn(deploy, player, arg)
	elseif action == "FirstDeploy" then
		task.spawn(deploy, player, { Mode = firstMode() })
	elseif action == "Play" then
		-- old MenuClient: a solo deploy of the picked mode (GameConfig.Modes keys)
		local mode = if type(arg) == "string" and table.find(CFG.Modes, arg) then arg else firstMode()
		if not unlocked(player, mode) then
			mode = firstMode()
		end
		local variant = nil
		local party = Party.Of(player)
		if party and #party.Members > 1 and party.Leader ~= player then
			Party.Solo(player)
		end
		task.spawn(deploy, player, { Mode = mode, Variant = variant })
	elseif action == "Campaign" then
		task.spawn(deploy, player, { Mode = "Campaign", Join = "Quick" })
	elseif action == "Cancel" then
		cancel(player)
	elseif action == "Ready" then
		Party.SetStatus(player, if arg == true then "READY" else "IDLE")
	elseif action == "Status" then
		if arg == "IDLE" or arg == "LOADOUT" or arg == "STORE" then
			Party.SetStatus(player, arg)
		end
	elseif action == "Redeploy" then
		redeploy(player)
	elseif action == "Continue" then
		task.spawn(continueRun, player)
	elseif action == "Rejoin" then
		task.spawn(doRejoin, player)
	end
end)
