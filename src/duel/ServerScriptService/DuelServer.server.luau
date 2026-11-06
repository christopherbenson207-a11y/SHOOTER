-- MULTIPLAYER: the 1v1 duel, the duel place's game (7 Nov 2026; numbers and rules in Shared.Duel).
-- The lobby (MenuServer there) sends a party of one or two to a public server of this place (MaxPlayers 2). MenuClient
-- deploys straight in (workspace Campaign) and MenuServer loads the character with InMatch set; from then on this
-- script owns every spawn (workspace HoldRespawns).
--   Waiting: one player alone walks the yard and can warm up; they come back LoneRespawn seconds after dying.
--   A match: the first two InMatch players are the duelists, slot 1 and slot 2. Sides are "Ally" and "Enemy" so the
--   gun code's FRONTLINE rules (workspace Front) make each the other's target. Each round both are loaded fresh (full
--   health, full ammo, their own loadout and operator) at their end, held for the countdown, then let go.
--   A round ends on a death (the other takes it) or on the clock (Duel.TimeoutWinner). First to RoundsToWin wins.
--   Leaving mid-match hands the match to the one who stays (paid as a forfeit win).
--   After the match: Remotes.Duel "Rematch" (both = start now) or "Lobby" (teleport back). The window running out with
--   both still here starts a new match.
-- A third player (the server should hold two; this covers a bigger server) is sent to another duel server.
-- Workspace attributes for the HUD: WaveState ("DuelWait" | "DuelCount" | "Duel" | "DuelRound" | "DuelEnd"),
-- DuelRound, DuelEndsAt (server time), DuelRoundWinner / DuelWinner (UserId, 0 = draw), DuelReason ("Left").
-- Player attributes: DuelSlot (1 | 2), DuelScore (rounds won), Rematch (bool), DuelOutAt (out-of-bounds hurt time).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Duel = require(ReplicatedStorage.Shared.Duel)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Points = require(ServerStorage.Modules.Points)
local Profile = require(ServerStorage.Modules.Profile)
local Uniform = require(ServerStorage.Modules.Uniform)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local LOBBY_PLACE = GameConfig.War.Campaign.LobbyPlaceId
local L = Duel.Lines
local kitRng = Random.new()

workspace:SetAttribute("Campaign", true) -- MenuClient deploys straight in
workspace:SetAttribute("Front", true) -- the other side is a target (GunServer, GunClient)
workspace:SetAttribute("Duel", true)
workspace:SetAttribute("Mode", "Duel")
workspace:SetAttribute("HoldRespawns", true) -- MenuServer leaves respawns to this script
PlayerHealth.Rules.HitGrace = 0.05
PlayerHealth.Rules.NoDown = true -- a duel has no downed state: at 0 you are dead
Points.Start()

local duelRemote = Remotes:FindFirstChild("Duel")
if not duelRemote then
	duelRemote = Instance.new("RemoteEvent")
	duelRemote.Name = "Duel"
	duelRemote.Parent = Remotes
end

local map = workspace:WaitForChild("Map")

local function now()
	return workspace:GetServerTimeNow()
end

-- The map -----------------------------------------------------------------------------------------------------------

local function spawnsOf(endName)
	local list = {}
	local folder = map:FindFirstChild("Spawns")
	for _, p in (folder and folder:GetChildren()) or {} do
		if p:IsA("BasePart") and p.Name:sub(1, 1) == endName then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function padCF(spot)
	local pos = spot.Position + Vector3.new(0, 3.2, 0)
	local look = spot.CFrame.LookVector * Vector3.new(1, 0, 1)
	return if look.Magnitude > 0.1 then CFrame.lookAt(pos, pos + look) else CFrame.new(pos)
end

local function spawnCF(endName)
	local list = spawnsOf(endName)
	if #list == 0 then
		warn("DuelServer: no spawns for end " .. endName)
		return CFrame.new(if endName == "A" then Vector3.new(0, 6, 40) else Vector3.new(0, 6, -40))
	end
	return padCF(list[math.random(1, #list)])
end

-- No spawn camping (owner, 5 Nov 2026). Each end has seven pads spread over its third of the yard (Map.Spawns A1-A7;
-- B1-B7 are the same spots turned half round, so neither end is better), each hidden from the whole other end.
-- Every round both pads are drawn fresh: never the pad that player last used at that end, and never a pair with a
-- line of sight between them (eye height, against Map.Collision). So the other player can't pre-aim where you appear.
local lastPad = setmetatable({}, { __mode = "k" }) -- [player] = { [endName] = pad }
local sightParams = nil
local SPAWN_EYE = Vector3.new(0, 5, 0)

local function padsSee(a, b)
	local collision = map:FindFirstChild("Collision")
	if not collision then
		return false
	end
	if not sightParams then
		sightParams = RaycastParams.new()
		sightParams.FilterType = Enum.RaycastFilterType.Include
		sightParams.FilterDescendantsInstances = { collision }
	end
	local from, to = a.Position + SPAWN_EYE, b.Position + SPAWN_EYE
	return workspace:Raycast(from, to - from, sightParams) == nil
end

-- The two spawn CFrames for a round: p1 at end1, p2 at end2.
local function pickSpawns(p1, end1, p2, end2)
	local list1, list2 = spawnsOf(end1), spawnsOf(end2)
	if #list1 == 0 or #list2 == 0 then
		return spawnCF(end1), spawnCF(end2)
	end
	local last1 = lastPad[p1] and lastPad[p1][end1]
	local last2 = lastPad[p2] and lastPad[p2][end2]
	local options, fallback = {}, {}
	for _, a in list1 do
		for _, b in list2 do
			if not padsSee(a, b) then
				table.insert(fallback, { a, b })
				if (a ~= last1 or #list1 == 1) and (b ~= last2 or #list2 == 1) then
					table.insert(options, { a, b })
				end
			end
		end
	end
	local pick = options[math.random(1, math.max(#options, 1))] or fallback[math.random(1, math.max(#fallback, 1))]
		or { list1[math.random(1, #list1)], list2[math.random(1, #list2)] }
	lastPad[p1] = lastPad[p1] or {}
	lastPad[p1][end1] = pick[1]
	lastPad[p2] = lastPad[p2] or {}
	lastPad[p2][end2] = pick[2]
	return padCF(pick[1]), padCF(pick[2])
end

local playBox = nil
local function inBounds(pos)
	playBox = playBox or (map:FindFirstChild("Bounds") and map.Bounds:FindFirstChild("PlayBox"))
	if not playBox then
		return true
	end
	local p = playBox.CFrame:PointToObjectSpace(pos)
	local h = playBox.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Z) <= h.Z and p.Y <= h.Y + 30 and p.Y >= -h.Y - 30
end

-- Players -----------------------------------------------------------------------------------------------------------

local function inMatch()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InMatch") then
			table.insert(list, p)
		end
	end
	return list
end

local function isAlive(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and c:IsDescendantOf(workspace)
end

local function healthOf(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 then h.Health else 0
end

local function stat(player, name)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local v = ls:FindFirstChild(name)
	if not v then
		v = Instance.new("IntValue")
		v.Name = name
		v.Parent = ls
	end
	return v
end

local function notice(player, text)
	if player.Parent then
		Remotes.Match:FireClient(player, "Notice", text)
	end
end

local function cue(player, name)
	if player.Parent then
		duelRemote:FireClient(player, name)
	end
end

local function setState(state, endsAt)
	workspace:SetAttribute("WaveState", state)
	workspace:SetAttribute("DuelEndsAt", endsAt)
end

-- Spawning ------------------------------------------------------------------------------------------------------------
-- pending[player] = { CF, Freeze = seconds }: where the next character goes and how long it is held there.

local pending = {}
local loading = {} -- [player] = true while a load is on its way (the respawn loops leave them be)

local function hold(character, seconds)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or seconds <= 0 then
		return
	end
	root.Anchored = true
	task.delay(seconds, function()
		if root.Parent then
			root.Anchored = false
		end
	end)
end

local function load(player, cf, freeze)
	if not player.Parent then
		return
	end
	pending[player] = { CF = cf, Freeze = freeze or 0 }
	loading[player] = true
	task.spawn(function()
		local ok, err = pcall(Uniform.Load, player)
		if not ok then
			warn("DuelServer: load failed for " .. player.Name .. ": " .. tostring(err))
			loading[player] = nil
		end
	end)
end

local function onCharacter(player, character)
	local p = pending[player]
	pending[player] = nil
	loading[player] = nil
	-- A body is up again: forget a death noted while the first load was still on its way (MenuServer's load is not ours).
	player:SetAttribute("DuelDiedAt", nil)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or player.Character ~= character then
		return
	end
	task.wait()
	local cf = if p then p.CF else spawnCF(Duel.EndFor(player:GetAttribute("DuelSlot") or 1, 1))
	character:PivotTo(cf)
	local freeze = if p then p.Freeze else 0
	hold(character, freeze)
	PlayerHealth.Protect(player, freeze + 0.5)
end

-- The match -------------------------------------------------------------------------------------------------------------

local match = nil -- { Duelists = {p1, p2}, Round, Score = {0, 0}, RoundWinner = nil | 1 | 2 | 0, Over = false }

local function slotOf(player)
	if not match then
		return nil
	end
	return if match.Duelists[1] == player then 1 elseif match.Duelists[2] == player then 2 else nil
end

local function other(slot)
	return if slot == 1 then 2 else 1
end

-- Kill credit: the opponent, if they hurt the body within Credit seconds.
local function creditOf(character)
	local id = character:GetAttribute("LastHitBy")
	local at = character:GetAttribute("LastHitAt") or 0
	if not id or now() - at > Duel.Credit then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

local function clearPlayer(p)
	p:SetAttribute("DuelSlot", nil)
	p:SetAttribute("DuelScore", nil)
	p:SetAttribute("Rematch", nil)
	p:SetAttribute("DuelOutAt", nil)
	p:SetAttribute("Side", nil)
	p:SetAttribute("DuelKit", nil)
end

local function onDied(player, character)
	-- Only a death in a live round counts (a body swapped out by the next round's load is not a death).
	local slot = slotOf(player)
	if not slot or workspace:GetAttribute("WaveState") ~= "Duel" then
		return
	end
	stat(player, "Deaths").Value += 1
	local killer = creditOf(character)
	if killer and slotOf(killer) then
		stat(killer, "Kills").Value += 1
		Points.Add(killer, Duel.Points.Kill + (if character:GetAttribute("LastHitHead") then Duel.Points.Headshot else 0))
	end
	if match.RoundWinner == nil then
		match.RoundWinner = other(slot)
	end
end

local function onPlayer(player)
	stat(player, "Kills")
	stat(player, "Deaths")
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Once(function()
				onDied(player, character)
			end)
		end
		onCharacter(player, character)
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
	loading[player] = nil
	if match and slotOf(player) and not match.Over then
		match.Left = slotOf(player)
	end
end)

-- Leaving the box hurts after a warning (player attribute DuelOutAt: when it starts, the HUD counts down).
local outHurt = {}
local function boundsTick()
	local t = now()
	for _, p in inMatch() do
		local root = isAlive(p) and p.Character:FindFirstChild("HumanoidRootPart")
		if root and not inBounds(root.Position) then
			local at = p:GetAttribute("DuelOutAt")
			if not at then
				p:SetAttribute("DuelOutAt", t + Duel.Bounds.Grace)
				notice(p, L.OutOfBounds)
			elseif t >= at and t - (outHurt[p] or 0) >= 1 then
				outHurt[p] = t
				PlayerHealth.Damage(p, Duel.Bounds.Damage, root.Position + Vector3.new(0, 10, 0), "Blast")
			end
		elseif p:GetAttribute("DuelOutAt") then
			p:SetAttribute("DuelOutAt", nil)
			outHurt[p] = nil
		end
	end
end

-- Anyone in the server who is not a duelist (alone, waiting) is kept alive and walking.
local function loneTick()
	for _, p in inMatch() do
		if not slotOf(p) and not isAlive(p) and not loading[p] then
			local diedAt = p:GetAttribute("DuelDiedAt")
			if not diedAt then
				p:SetAttribute("DuelDiedAt", now())
			elseif now() - diedAt >= Duel.LoneRespawn then
				p:SetAttribute("DuelDiedAt", nil)
				load(p, spawnCF("A"), 0)
			end
		end
	end
end

local function matchGone()
	if not match then
		return true
	end
	if match.Left then
		return true
	end
	for _, p in match.Duelists do
		if not p.Parent then
			match.Left = slotOf(p)
			return true
		end
	end
	return false
end

-- Waits seconds while the match stands; false if someone left.
local function waitFor(seconds, tick)
	local stop = os.clock() + seconds
	while os.clock() < stop do
		task.wait(0.2)
		if matchGone() then
			return false
		end
		boundsTick()
		if tick and tick() then
			return true
		end
	end
	return true
end

local function playRound()
	match.Round += 1
	match.RoundWinner = nil
	workspace:SetAttribute("DuelRound", match.Round)
	workspace:SetAttribute("DuelRoundWinner", nil)
	-- The round's weapons (Shared.Duel.Kits): round 1 is everyone's own loadout, then one random kit for both,
	-- never the last one. Inventory reads DuelKit when the new body loads.
	local kit = nil
	if match.Round > 1 then
		kit = Duel.PickKit(function(item)
			return GameConfig.Guns[item] ~= nil
		end, match.LastKit, kitRng)
	end
	match.LastKit = kit and kit.Name
	workspace:SetAttribute("DuelKit", if kit then kit.Name else Duel.OwnKitName)
	-- Both fresh at their ends (a new blind pair of pads each round), held for the countdown.
	local d1, d2 = match.Duelists[1], match.Duelists[2]
	local cf1, cf2 = pickSpawns(d1, Duel.EndFor(1, match.Round), d2, Duel.EndFor(2, match.Round))
	local spawnAt = { cf1, cf2 }
	for slot, p in match.Duelists do
		p:SetAttribute("DuelOutAt", nil)
		p:SetAttribute("DuelKit", if kit then table.concat(kit.Items, "|") else nil)
		load(p, spawnAt[slot], Duel.Countdown + 0.4)
	end
	setState("DuelCount", now() + Duel.Countdown)
	for _, p in match.Duelists do
		notice(p, ("ROUND %d  ·  %s"):format(match.Round, if kit then kit.Name else Duel.OwnKitName))
		cue(p, "Countdown")
	end
	if not waitFor(Duel.Countdown) then
		return false
	end
	setState("Duel", now() + Duel.RoundTime)
	for _, p in match.Duelists do
		notice(p, L.Go)
		cue(p, "Go")
	end
	local timedOut = true
	local ok = waitFor(Duel.RoundTime, function()
		if match.RoundWinner ~= nil then
			timedOut = false
			return true
		end
		return false
	end)
	if not ok then
		return false
	end
	if timedOut then
		match.RoundWinner = Duel.TimeoutWinner(healthOf(match.Duelists[1]), healthOf(match.Duelists[2])) or 0
	end
	-- A last shot can land in the same breath: both down is a draw.
	if match.RoundWinner ~= 0 and not isAlive(match.Duelists[match.RoundWinner]) then
		match.RoundWinner = 0
	end
	local w = match.RoundWinner
	if w ~= 0 then
		match.Score[w] += 1
		match.Duelists[w]:SetAttribute("DuelScore", match.Score[w])
		Points.Add(match.Duelists[w], Duel.Points.Round)
	end
	workspace:SetAttribute("DuelRoundWinner", if w == 0 then 0 else match.Duelists[w].UserId)
	setState("DuelRound", now() + Duel.RoundPause)
	for slot, p in match.Duelists do
		local line = if w == 0 then L.Draw elseif w == slot then L.RoundWon else L.RoundLost
		notice(p, line)
		cue(p, if w == 0 then "Draw" elseif w == slot then "RoundWon" else "RoundLost")
	end
	return waitFor(Duel.RoundPause)
end

local function pay(winnerSlot, forfeit)
	for slot, p in match.Duelists do
		if p.Parent then
			local won = slot == winnerSlot
			if won then
				Points.Add(p, Duel.Points.Match)
			end
			local amount = Duel.MatchPay(won, match.Score[slot], forfeit and won)
			local ok, banked = pcall(Profile.Earn, p, amount)
			if ok then
				Remotes.Match:FireClient(p, "Banked", banked)
			end
			pcall(Profile.Count, p, "DuelMatches")
			if won then
				pcall(Profile.Count, p, "DuelWins")
			end
		end
	end
end

local function endMatch(winnerSlot, reason)
	match.Over = true
	local winner = match.Duelists[winnerSlot]
	workspace:SetAttribute("DuelWinner", if winner then winner.UserId else 0)
	workspace:SetAttribute("DuelReason", reason)
	pay(winnerSlot, reason == "Left")
	for slot, p in match.Duelists do
		if p.Parent then
			p:SetAttribute("Rematch", false)
			if reason == "Left" then
				notice(p, L.Left)
			else
				notice(p, if slot == winnerSlot then L.Won else L.Lost)
			end
			cue(p, if slot == winnerSlot then "Won" else "Lost")
		end
	end
	print(("DuelServer: match over, %s won %d-%d%s"):format(winner and winner.Name or "nobody", match.Score[1],
		match.Score[2], if reason then " (" .. reason .. ")" else ""))
end

-- Runs one match between a and b. Returns the two players still here, if both stayed through the end.
local function playMatch(a, b)
	match = { Duelists = { a, b }, Round = 0, Score = { 0, 0 }, Over = false }
	workspace:SetAttribute("DuelWinner", nil)
	workspace:SetAttribute("DuelReason", nil)
	workspace:SetAttribute("DuelRound", 0)
	for slot, p in match.Duelists do
		p:SetAttribute("DuelSlot", slot)
		p:SetAttribute("DuelScore", 0)
		p:SetAttribute("Rematch", nil)
		p:SetAttribute("Side", if slot == 1 then "Ally" else "Enemy")
		p:SetAttribute("DuelDiedAt", nil)
		p.Neutral = true
		Points.Reset(p)
		notice(p, L.Found)
		cue(p, "Found")
	end
	setState("DuelCount", now() + Duel.FirstWait)
	if not waitFor(Duel.FirstWait) then
		-- someone left before round 1: nothing to pay
		match.Over = true
		return nil
	end
	while true do
		if not playRound() then
			break
		end
		if match.Score[1] >= Duel.RoundsToWin or match.Score[2] >= Duel.RoundsToWin then
			break
		end
	end
	if match.Left then
		local stay = other(match.Left)
		if match.Duelists[stay].Parent then
			endMatch(stay, "Left")
		else
			match.Over = true
		end
		return nil
	end
	endMatch(if match.Score[1] > match.Score[2] then 1 else 2, nil)
	return true
end

-- After a match: the window for REMATCH / LOBBY. Returns true if both stayed for another.
local function rematchWindow()
	setState("DuelEnd", now() + Duel.RematchWindow)
	local stop = os.clock() + Duel.RematchWindow
	while os.clock() < stop do
		task.wait(0.2)
		local a, b = match.Duelists[1], match.Duelists[2]
		if not (a.Parent and b.Parent) then
			return false
		end
		if a:GetAttribute("Rematch") and b:GetAttribute("Rematch") then
			return true
		end
	end
	return true
end

-- Remotes.Duel, client to server: "Rematch" (toggle) and "Lobby". A short per-player gap stops floods.
local lastAsk = {}
local sending = {}

local function toLobby(player)
	if sending[player] or not player.Parent then
		return
	end
	if RunService:IsStudio() then
		notice(player, "THE LOBBY IS A TELEPORT AWAY (NOT IN STUDIO)")
		return
	end
	sending[player] = true
	task.spawn(function()
		pcall(Profile.SaveNow, player, true)
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({ From = "Duel" })
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, LOBBY_PLACE, { player }, options)
		if not ok then
			warn("DuelServer: lobby teleport failed for " .. player.Name .. ": " .. tostring(err))
			sending[player] = nil
			pcall(Profile.Reclaim, player)
			notice(player, "COULDN'T REACH THE LOBBY. TRY AGAIN")
		end
	end)
end

TeleportService.TeleportInitFailed:Connect(function(player)
	if sending[player] and player.Parent then
		sending[player] = nil
		pcall(Profile.Reclaim, player)
		notice(player, "COULDN'T REACH THE LOBBY. TRY AGAIN")
	end
end)

duelRemote.OnServerEvent:Connect(function(player, action)
	if type(action) ~= "string" then
		return
	end
	local t = os.clock()
	if t - (lastAsk[player] or 0) < 0.4 then
		return
	end
	lastAsk[player] = t
	if action == "Rematch" then
		if workspace:GetAttribute("WaveState") == "DuelEnd" and slotOf(player) then
			player:SetAttribute("Rematch", not player:GetAttribute("Rematch"))
		end
	elseif action == "Lobby" then
		toLobby(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastAsk[player] = nil
	sending[player] = nil
	outHurt[player] = nil
end)

-- A third player in a two-player server goes to another duel server.
local function sendExtras(keep)
	for _, p in inMatch() do
		if not table.find(keep, p) and not sending[p] and not RunService:IsStudio() then
			sending[p] = true
			task.spawn(function()
				notice(p, "THIS DUEL IS FULL. FINDING ANOTHER")
				pcall(Profile.SaveNow, p, true)
				local ok = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { p })
				if not ok then
					sending[p] = nil
					pcall(Profile.Reclaim, p)
				end
			end)
		end
	end
end

-- The loop: wait for two, play, rematch or go back to waiting.
task.spawn(function()
	while true do
		task.wait(0.25)
		if not match or match.Over then
			loneTick()
			boundsTick()
		end
	end
end)

while true do
	-- Waiting for two.
	match = nil
	for _, p in Players:GetPlayers() do
		clearPlayer(p)
	end
	setState("DuelWait", nil)
	workspace:SetAttribute("DuelRound", nil)
	workspace:SetAttribute("DuelRoundWinner", nil)
	local list = inMatch()
	local said = {}
	while #list < 2 do
		for _, p in list do
			if not said[p] then
				said[p] = true
				notice(p, L.Waiting)
			end
		end
		task.wait(0.5)
		list = inMatch()
	end
	local a, b = list[1], list[2]
	sendExtras({ a, b })
	while true do
		local ok, result = pcall(playMatch, a, b)
		if not ok then
			warn("DuelServer: the match failed (" .. tostring(result) .. ")")
			break
		end
		if not result then
			break -- someone left
		end
		if not rematchWindow() then
			break
		end
		if not (a.Parent and b.Parent) then
			break
		end
		-- the second match deals the ends the other way round
		a, b = b, a
	end
	-- Whoever stayed waits alone for the next opponent: up and walking again.
	if match then
		match.Over = true
	end
	for _, p in inMatch() do
		if not isAlive(p) and not loading[p] then
			load(p, spawnCF("A"), 0)
		end
	end
end
