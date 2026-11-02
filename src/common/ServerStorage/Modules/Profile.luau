-- What a player keeps between matches: the uniform they picked after their first rescue
-- (Attire: one of GameConfig.Attire's names, nil until then) and whether they have ever got
-- out on the helicopter (Escaped: unlocks the other modes, GameConfig.Modes), and their
-- settings (Settings: checked by SettingsServer). The player's Attire and Escaped attributes
-- mirror them for clients, and Settings arrives as JSON in the Settings attribute. Studio saves to its own DataStore, so tests never touch live saves;
-- without DataStore access (Studio API access off) it still works for the session.
-- The store's part (StoreServer, GameConfig.Store): Scrip (the currency kept between matches),
-- Owned (classes and store items by name), Class (the one picked on the menu), Flags (one-time
-- things: analytics funnel steps, offers due and shown), the counters Matches, Deaths and
-- Tokens (revive tokens bought but not used yet), and Receipts (recent purchase ids, so a
-- purchase is never granted twice). Clients read the Scrip, Class, Owned (JSON) and Tokens
-- attributes. If a save can't be read the session goes on but never saves, so a DataStore
-- hiccup can't overwrite a real save with an empty one.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local STORE = if RunService:IsStudio() then "LastLightProfile_Studio_v1" else "LastLightProfile_v1"

local Profile = {}

local cache = {} -- [userId] = data
local loading = {} -- [userId] = true while the first load runs (other callers wait for it)
local noSave = {} -- [userId] = true when the save couldn't be read
local saving = {} -- [userId] = "busy" while a save runs, "again" if more changed meanwhile
local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE)
end)

local function key(userId)
	return "u" .. userId
end

-- The player's saved data (loaded once, then cached for the session).
function Profile.Get(player)
	local id = player.UserId
	while loading[id] do
		task.wait()
	end
	local data = cache[id]
	if data then
		return data
	end
	loading[id] = true
	data = {}
	if store then
		local ok, saved
		for try = 1, 3 do
			ok, saved = pcall(store.GetAsync, store, key(id))
			if ok then
				break
			end
			task.wait(try)
		end
		if ok and type(saved) == "table" then
			data = saved
		elseif not ok then
			noSave[id] = true
			warn("Profile: couldn't load", player.Name, "- this session won't save", saved)
		end
	end
	cache[id] = data
	loading[id] = nil
	player:SetAttribute("Scrip", data.Scrip or 0)
	player:SetAttribute("Class", data.Class)
	player:SetAttribute("Owned", HttpService:JSONEncode(data.Owned or {}))
	player:SetAttribute("Tokens", data.Tokens or 0)
	player:SetAttribute("Attire", data.Attire)
	player:SetAttribute("Escaped", data.Escaped == true)
	if type(data.Settings) == "table" then
		player:SetAttribute("Settings", HttpService:JSONEncode(data.Settings))
	end
	return data
end

-- Saves in the background; changes made while a save is running go out in one more save.
local function save(player, data)
	local id = player.UserId
	if not store or noSave[id] then
		return
	end
	if saving[id] then
		saving[id] = "again"
		return
	end
	saving[id] = "busy"
	task.spawn(function()
		repeat
			saving[id] = "busy"
			local ok, err = pcall(store.SetAsync, store, key(id), data)
			if not ok then
				warn("Profile: couldn't save", player.Name, err)
			end
		until saving[id] ~= "again"
		saving[id] = nil
	end)
end

-- Saves now and waits; true once it's in the DataStore. A purchase is only reported granted
-- after this (StoreServer's ProcessReceipt).
function Profile.SaveNow(player)
	local data = Profile.Get(player)
	if not store or noSave[player.UserId] then
		return false
	end
	local ok, err = pcall(store.SetAsync, store, key(player.UserId), data)
	if not ok then
		warn("Profile: couldn't save", player.Name, err)
	end
	return ok
end

function Profile.SetAttire(player, name)
	local data = Profile.Get(player)
	data.Attire = name
	player:SetAttribute("Attire", name)
	save(player, data)
end

function Profile.SetEscaped(player)
	local data = Profile.Get(player)
	data.Escaped = true
	player:SetAttribute("Escaped", true)
	save(player, data)
end

function Profile.SetSettings(player, settings)
	local data = Profile.Get(player)
	data.Settings = settings
	save(player, data)
end

-- Scrip: adds (or with a negative amount takes) and returns the new balance.
function Profile.AddScrip(player, amount)
	local data = Profile.Get(player)
	data.Scrip = math.max(0, (data.Scrip or 0) + amount)
	player:SetAttribute("Scrip", data.Scrip)
	save(player, data)
	return data.Scrip
end

-- Scrip earned by playing (not bought): VIP (the Vip attribute, StoreServer) adds
-- GameConfig.Scrip.VipBonus on top. Returns what went in.
function Profile.Earn(player, amount)
	if player:GetAttribute("Vip") then
		amount = math.floor(amount * (1 + GameConfig.Scrip.VipBonus) + 0.5)
	end
	Profile.AddScrip(player, amount)
	return amount
end

-- Takes amount Scrip; false (and takes nothing) if the player hasn't got it.
function Profile.SpendScrip(player, amount)
	local data = Profile.Get(player)
	if (data.Scrip or 0) < amount then
		return false
	end
	Profile.AddScrip(player, -amount)
	return true
end

function Profile.Owns(player, item)
	local owned = Profile.Get(player).Owned
	return owned ~= nil and owned[item] == true
end

function Profile.Grant(player, item)
	local data = Profile.Get(player)
	data.Owned = data.Owned or {}
	data.Owned[item] = true
	player:SetAttribute("Owned", HttpService:JSONEncode(data.Owned))
	save(player, data)
end

function Profile.SetClass(player, name)
	local data = Profile.Get(player)
	data.Class = name
	player:SetAttribute("Class", name)
	save(player, data)
end

-- One-time flags. SetFlag returns false if the flag was already set.
function Profile.Flag(player, name)
	local flags = Profile.Get(player).Flags
	return flags ~= nil and flags[name] == true
end

function Profile.SetFlag(player, name)
	local data = Profile.Get(player)
	data.Flags = data.Flags or {}
	if data.Flags[name] then
		return false
	end
	data.Flags[name] = true
	save(player, data)
	return true
end

-- Counters (Matches, Deaths, Tokens): adds by (default 1) and returns the new count.
function Profile.Count(player, name, by)
	local data = Profile.Get(player)
	data[name] = math.max(0, (data[name] or 0) + (by or 1))
	if name == "Tokens" then
		player:SetAttribute("Tokens", data.Tokens)
	end
	save(player, data)
	return data[name]
end

-- Purchases: whether this receipt was granted before, and remembering one (the last 50).
function Profile.HasReceipt(player, purchaseId)
	local receipts = Profile.Get(player).Receipts
	return receipts ~= nil and table.find(receipts, purchaseId) ~= nil
end

function Profile.AddReceipt(player, purchaseId)
	local data = Profile.Get(player)
	data.Receipts = data.Receipts or {}
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > 50 do
		table.remove(data.Receipts, 1)
	end
end

Players.PlayerAdded:Connect(function(player)
	Profile.Get(player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(Profile.Get, player)
end
Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
	noSave[player.UserId] = nil
end)
-- On shutdown, let saves that are still running finish.
game:BindToClose(function()
	local t = os.clock()
	while next(saving) and os.clock() - t < 25 do
		task.wait(0.5)
	end
end)

return Profile
