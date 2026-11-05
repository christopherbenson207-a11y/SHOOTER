-- Party (DATA, 2 Nov 2026): squads of up to four in a server. Contract: horror-shooter/menu/CONTRACTS.md sections 3 and
-- 5 (Remotes.Party), MENU-PLAN 9.1.
--
-- Every player is always in a party; on join it is a party of one with them as leader. The first player is leader;
-- when the leader leaves, the longest-standing member takes over.
--   Party.Of(player) -> {Id, Leader = player, Members = {player...}, Status = {[userId] = "IDLE" | "LOADOUT" | "STORE"
--                       | "READY"}, Fill = false, State = "Idle" | "Countdown" | "Deploying", Count, Mode, Variant,
--                       Chapter, Mission, Join}
--   Party.Snapshot(party) -> the table Remotes.Party "State" carries (contract section 5)
--   Party.Changed(party)  -> sends "State" to every member and refreshes their PartyId attributes
--   Party.Solo(player), Party.Adopt(player, partyId, leaderUserId) (a Match server rebuilding the party from join
--   data), Party.SetStatus(player, status), Party.ReadyCount(party), Party.ById(id), Party.OnChanged(fn)
-- Remotes.Party, client to server: "Invite", userId | "Accept", partyId | "Decline", partyId | "Leave" |
--   "Kick", userId | "Fill", bool | "Refresh". Server to client: "State", snapshot | "Invited", {PartyId,
--   FromUserId, FromName}.
-- Deploying, the countdown and teleports are MenuServer's (it sets State, Count, Mode, Variant, Chapter, Mission and Join
-- here).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local MAX = 4
local INVITE_TIME = 60

local remote = Remotes:FindFirstChild("Party")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "Party"
	remote.Parent = Remotes
end

local Party = {}
Party.Remote = remote
Party.Max = MAX

local byId = {} -- [partyId] = party
local of = {} -- [player] = party
local invites = {} -- [player] = {[partyId] = os.clock() of the invite}
local listeners = {} -- fn(party) on every change

function Party.Of(player)
	return of[player]
end

function Party.ById(id)
	return byId[id]
end

function Party.OnChanged(fn)
	table.insert(listeners, fn)
end

local function newParty(leader, id)
	local party = {
		Id = id or HttpService:GenerateGUID(false),
		Leader = leader,
		Members = {},
		Status = {},
		Fill = false,
		State = "Idle",
	}
	byId[party.Id] = party
	return party
end

function Party.Snapshot(party)
	local members = {}
	for _, m in party.Members do
		table.insert(members, {
			UserId = m.UserId,
			Name = m.DisplayName,
			Level = m:GetAttribute("Level") or 1,
			Class = m:GetAttribute("Class"),
			Operator = m:GetAttribute("Operator"),
			Card = m:GetAttribute("Card"),
			Status = party.Status[m.UserId] or "IDLE",
			Boost = (m:GetAttribute("Boosts") or 0) > 0 or m:GetAttribute("BoostActive") == true,
		})
	end
	return {
		Id = party.Id,
		Leader = party.Leader and party.Leader.UserId,
		Fill = party.Fill,
		State = party.State,
		Count = party.Count,
		Mode = party.Mode,
		Variant = party.Variant,
		Chapter = party.Chapter,
		Mission = party.Mission,
		Join = party.Join,
		Members = members,
	}
end

function Party.Changed(party)
	if not party or byId[party.Id] ~= party then
		return
	end
	local snap = Party.Snapshot(party)
	for _, m in party.Members do
		if m.Parent then
			m:SetAttribute("PartyId", party.Id)
			remote:FireClient(m, "State", snap)
		end
	end
	for _, fn in listeners do
		task.spawn(fn, party)
	end
end

local function remove(player)
	local party = of[player]
	if not party then
		return
	end
	of[player] = nil
	local i = table.find(party.Members, player)
	if i then
		table.remove(party.Members, i)
	end
	party.Status[player.UserId] = nil
	if #party.Members == 0 then
		byId[party.Id] = nil
		return
	end
	if party.Leader == player then
		party.Leader = party.Members[1]
	end
	-- a squad change stops a countdown that was running for the old squad
	if party.State == "Countdown" then
		party.State = "Idle"
		party.Count = nil
	end
	Party.Changed(party)
end

local function add(player, party)
	remove(player)
	table.insert(party.Members, player)
	of[player] = party
	party.Status[player.UserId] = "IDLE"
	Party.Changed(party)
end

-- A player on their own (a new party of one, unless they already are one).
function Party.Solo(player)
	if of[player] and #of[player].Members == 1 then
		return of[player]
	end
	local party = newParty(player)
	add(player, party)
	return party
end

-- A Match server rebuilding the party that teleported in: same id; the leader if present, else the first member.
function Party.Adopt(player, id, leaderUserId)
	if type(id) ~= "string" or #id > 64 then
		return Party.Solo(player)
	end
	local party = byId[id]
	if not party then
		party = newParty(player, id)
	end
	if of[player] == party then
		return party
	end
	if #party.Members >= MAX then
		return Party.Solo(player)
	end
	add(player, party)
	if player.UserId == leaderUserId or not party.Leader or not party.Leader.Parent or of[party.Leader] ~= party then
		party.Leader = player
		Party.Changed(party)
	end
	return party
end

local STATUS = { IDLE = true, LOADOUT = true, STORE = true, READY = true }
function Party.SetStatus(player, status)
	local party = of[player]
	if not party or not STATUS[status] then
		return
	end
	if party.Status[player.UserId] ~= status then
		party.Status[player.UserId] = status
		Party.Changed(party)
	end
end

-- How many members are READY (the leader counts as ready).
function Party.ReadyCount(party)
	local n = 0
	for _, m in party.Members do
		if m == party.Leader or party.Status[m.UserId] == "READY" then
			n += 1
		end
	end
	return n
end

local function busy(party)
	return party.State ~= "Idle"
end

remote.OnServerEvent:Connect(function(player, action, arg)
	local party = of[player] or Party.Solo(player)
	if action == "Invite" then
		local target = Players:GetPlayerByUserId(tonumber(arg) or 0)
		if not target or target == player or of[target] == party or #party.Members >= MAX or busy(party) then
			return
		end
		invites[target] = invites[target] or {}
		invites[target][party.Id] = os.clock()
		remote:FireClient(target, "Invited", { PartyId = party.Id, FromUserId = player.UserId, FromName = player.DisplayName })
	elseif action == "Accept" then
		if type(arg) ~= "string" then
			return
		end
		local mine = invites[player]
		local at = mine and mine[arg]
		local target = at and byId[arg]
		if mine then
			mine[arg] = nil
		end
		if not target or os.clock() - at > INVITE_TIME or #target.Members >= MAX or busy(target) or busy(party) then
			Party.Changed(party)
			return
		end
		add(player, target)
	elseif action == "Decline" then
		if invites[player] and type(arg) == "string" then
			invites[player][arg] = nil
		end
	elseif action == "Leave" then
		if #party.Members > 1 and party.State ~= "Deploying" then
			Party.Solo(player)
		end
	elseif action == "Kick" then
		local target = Players:GetPlayerByUserId(tonumber(arg) or 0)
		if party.Leader == player and target and target ~= player and of[target] == party and party.State ~= "Deploying" then
			Party.Solo(target)
		end
	elseif action == "Fill" then
		if party.Leader == player then
			party.Fill = arg == true -- FILL matchmaking is phase 1.5; the flag is kept for the menu
			Party.Changed(party)
		end
	elseif action == "Refresh" then
		remote:FireClient(player, "State", Party.Snapshot(party))
	end
end)

Players.PlayerAdded:Connect(function(player)
	-- a Match server adopts arrivals into their teleport party (MenuServer); everyone else starts solo
	task.defer(function()
		if player.Parent and not of[player] then
			Party.Solo(player)
		end
	end)
end)
for _, player in Players:GetPlayers() do
	if not of[player] then
		Party.Solo(player)
	end
end
Players.PlayerRemoving:Connect(function(player)
	invites[player] = nil
	remove(player)
end)

-- the attributes the snapshot shows change: refresh the squad (batched every 0.5 s)
local WATCH = { "Level", "Class", "Operator", "Card", "Boosts", "BoostActive" }
local function watch(player)
	for _, name in WATCH do
		player:GetAttributeChangedSignal(name):Connect(function()
			local party = of[player]
			if party then
				party._dirty = true
			end
		end)
	end
end
Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, party in byId do
			if party._dirty then
				party._dirty = nil
				Party.Changed(party)
			end
		end
	end
end)

return Party
