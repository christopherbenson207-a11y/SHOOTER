-- Profile (campaign), session-locked (4 Nov 2026). What a player keeps between matches, shared with the lobby and
-- zombies places: one record per player in LastLightProfile_v1 (LastLightProfile_Studio_v1 in Studio, so tests never
-- touch live saves), key "u"..UserId.
--
-- Saving works exactly like the lobby/zombies Profile v2 (ServerStorage.Modules.Profile there):
--   * Load with UpdateAsync and take a session lock Lock = {JobId, Time}. If another server holds a lock younger than
--     LOCK_AGE, retry for about LOAD_WAIT seconds, then take it over. If loading fails the session never saves
--     (noSave) and the player attribute ProfileFailed is set.
--   * Changes only touch the cached table and attributes and mark it dirty. A write goes out at most every THROTTLE
--     seconds per player, plus a keep-alive write every KEEPALIVE seconds that refreshes the lock. Every write is an
--     UpdateAsync whose transform refuses unless the stored Lock is this server's; a refused write stops this server
--     saving that player (another server owns the record now).
--   * PlayerRemoving flushes and releases the lock; BindToClose waits for those flushes.
--   * SaveNow(player, release) writes at once. release = true (before a teleport) writes Lock = nil and stops this
--     server saving that player; Reclaim(player) takes the lock back after a teleport that failed.
--   * Every read and write is a locked UpdateAsync: the campaign can no longer overwrite the lobby's data or bypass
--     its lock (the old module read and blind-wrote the whole record with no lock).
--
-- Schema: this place has no Shared.Progression / Shared.Catalogue, so it never migrates. A v1 record (no Version) is
-- kept v1 and the lobby migrates it on the player's next lobby visit; a v2 record keeps every v2 field untouched
-- (the whole loaded table is written back) and only the shared fields below change. A record with a Version newer
-- than KNOWN_VERSION is not loaded for saving (rolling updates must not strip fields this server does not know).
--
-- The campaign's API is unchanged: Get, SaveNow, AddScrip, Earn, SpendScrip, Owns, Grant, SetClass, Flag, SetFlag,
-- Count, HasReceipt, AddReceipt, SetAttire, SetEscaped, SetSettings (plus WaitFor, Holds, Touch, Reclaim).
-- Fields the campaign uses: Scrip, Owned, Flags, Tokens, Class (top-level, ignored by the lobby's v2 loadouts),
-- Attire, Escaped, Settings, the counters Matches, Deaths, EndlessBest, WarRuns (top-level; on a v2 record also
-- Stats.<name>, WarRuns as Stats.CampaignClears, the way the lobby counts them), and receipts (Receipts on v1,
-- PurchaseIds on v2). Clients read the Scrip, Class, Owned (JSON), Tokens, Attire, Escaped and Settings attributes.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local STORE = if RunService:IsStudio() then "LastLightProfile_Studio_v1" else "LastLightProfile_v1"
local KNOWN_VERSION = 2 -- the newest schema the lobby writes
local THROTTLE = 7 -- seconds between writes for one key
local KEEPALIVE = 60 -- a write at least this often while the player is here (keeps the lock fresh)
local LOCK_AGE = 90 -- a lock older than this is stale (same as the lobby and zombies)
local LOAD_WAIT = 10 -- seconds to wait for another server's lock before taking over
local JOB = if game.JobId ~= "" then game.JobId else "Studio"
local LEGACY_TOP = { Matches = true, Deaths = true, EndlessBest = true, WarRuns = true }

local Profile = {}
Profile.StoreName = STORE

local cache = {} -- [userId] = data
local loading = {} -- [userId] = true while the first load runs
local noSave = {} -- [userId] = true: never write (load failed, newer schema, or the lock was lost)
local handedOff = {} -- [userId] = true: lock released for a teleport; never write again here
local dirty = {} -- [userId] = true: changed since the last write
local lastWrite = {} -- [userId] = os.clock() of the last write attempt
local writing = {} -- [userId] = true while a write runs
local flushing = {} -- [userId] = true while the leave flush runs (BindToClose waits)

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore(STORE)
end)

local function key(userId)
	return "u" .. userId
end

local function json(v)
	local ok, s = pcall(HttpService.JSONEncode, HttpService, v)
	return ok and s or "{}"
end

local function isV2(data)
	return data.Version ~= nil
end

local function map(data, field)
	if type(data[field]) ~= "table" then
		data[field] = {}
	end
	return data[field]
end

local function publish(player, data)
	player:SetAttribute("Scrip", tonumber(data.Scrip) or 0)
	player:SetAttribute("Class", if type(data.Class) == "string" then data.Class else nil)
	player:SetAttribute("Owned", json(type(data.Owned) == "table" and data.Owned or {}))
	player:SetAttribute("Tokens", tonumber(data.Tokens) or 0)
	player:SetAttribute("Attire", if type(data.Attire) == "string" then data.Attire else nil)
	player:SetAttribute("Escaped", data.Escaped == true)
	if type(data.Settings) == "table" then
		player:SetAttribute("Settings", json(data.Settings))
	end
end

-- Loading ------------------------------------------------------------------------------------------------------------

-- One UpdateAsync that takes the lock. Returns data (table) | nil, "locked" | "newer" | error.
local function tryLoad(userId, force)
	local loaded, why = nil, nil
	local ok, err = pcall(store.UpdateAsync, store, key(userId), function(old)
		old = type(old) == "table" and old or {}
		local version = tonumber(old.Version)
		if version and version > KNOWN_VERSION then
			why = "newer"
			return nil -- a schema this server doesn't know: no lock, no write
		end
		local lock = old.Lock
		if not force and type(lock) == "table" and lock.JobId ~= JOB and os.time() - (tonumber(lock.Time) or 0) < LOCK_AGE then
			why = "locked"
			return nil -- leave the record as it is
		end
		why = nil
		old.Lock = { JobId = JOB, Time = os.time() }
		loaded = old
		return old
	end)
	if not ok then
		return nil, tostring(err)
	end
	return loaded, why
end

-- Returns data, failed. failed = true means this session must never save.
local function loadData(player)
	local id = player.UserId
	if not store then
		return {}, true -- no DataStore access (Studio API off): play on, never save
	end
	local started = os.clock()
	local tries = 0
	while true do
		tries += 1
		local force = os.clock() - started >= LOAD_WAIT
		local data, why = tryLoad(id, force)
		if data then
			return data, false
		end
		if not player.Parent then
			return nil, true
		end
		if why == "newer" then
			warn("Profile: save from a newer version for", player.Name, "- this session won't save")
			return {}, true
		end
		if why ~= "locked" and tries >= 4 then
			warn("Profile: couldn't load", player.Name, "- this session won't save", why)
			return {}, true
		end
		task.wait(if why == "locked" then 2 else tries)
	end
end

-- The player's saved data (loads once; callers wait for a load already running). A player who already left gets an
-- empty table that is never saved, so old callers can always index the result.
function Profile.Get(player)
	local id = player.UserId
	while loading[id] do
		task.wait()
	end
	local data = cache[id]
	if data then
		return data
	end
	if not player.Parent then
		return {}
	end
	loading[id] = true
	local ok, loaded, failed = pcall(loadData, player)
	if not ok then
		warn("Profile: load error for", player.Name, loaded)
		loaded, failed = {}, true
	end
	if failed then
		noSave[id] = true
		if store then
			player:SetAttribute("ProfileFailed", true)
		end
	end
	data = type(loaded) == "table" and loaded or {}
	data.Lock = nil
	cache[id] = data
	loading[id] = nil
	lastWrite[id] = os.clock()
	if player.Parent then
		publish(player, data)
	end
	return data
end

-- The profile if it is loaded, waiting up to timeout seconds for it (nil after that).
function Profile.WaitFor(player, timeout)
	local t = os.clock()
	while not cache[player.UserId] do
		if os.clock() - t > (timeout or 10) or not player.Parent then
			return cache[player.UserId]
		end
		if not loading[player.UserId] then
			task.spawn(Profile.Get, player)
		end
		task.wait(0.1)
	end
	return cache[player.UserId]
end

-- Whether this server holds the player's lock (loaded, saving allowed, not handed off).
function Profile.Holds(player)
	local id = player.UserId
	return cache[id] ~= nil and store ~= nil and not noSave[id] and not handedOff[id]
end

-- Writing ------------------------------------------------------------------------------------------------------------

-- One UpdateAsync with the whole profile. Refuses unless the stored lock is ours. true when written.
local function write(player, userId, release)
	local data = cache[userId]
	if not data or not store or noSave[userId] or handedOff[userId] then
		return false
	end
	while writing[userId] do
		task.wait()
	end
	if handedOff[userId] or noSave[userId] or cache[userId] ~= data then
		return false
	end
	writing[userId] = true
	lastWrite[userId] = os.clock()
	dirty[userId] = nil
	local refused = false
	local ok, err = pcall(store.UpdateAsync, store, key(userId), function(old)
		old = type(old) == "table" and old or {}
		local lock = old.Lock
		if type(lock) ~= "table" or lock.JobId ~= JOB then
			refused = true
			return nil
		end
		refused = false
		data.Lock = if release then nil else { JobId = JOB, Time = os.time() }
		return data
	end)
	data.Lock = nil
	writing[userId] = nil
	if not ok or refused then
		dirty[userId] = true
		if refused then
			-- another server took this profile over: stop writing from here so neither overwrites the other
			warn("Profile: lock lost for", player and player.Name or userId, "- this session stops saving")
			noSave[userId] = true
		else
			warn("Profile: couldn't save", player and player.Name or userId, err)
		end
		return false
	end
	if release then
		handedOff[userId] = true
	end
	return true
end

local function touch(player)
	dirty[player.UserId] = true
end
Profile.Touch = touch

-- Writes now and waits; true once it is in the DataStore. release = true before a teleport: the lock is released
-- and this server stops saving the player.
function Profile.SaveNow(player, release)
	Profile.Get(player)
	local id = player.UserId
	if not cache[id] then
		return false
	end
	local since = os.clock() - (lastWrite[id] or 0)
	if since < 6 then
		task.wait(6 - since) -- the DataStore allows one write per key about every 6 s
	end
	return write(player, id, release == true)
end

-- After a teleport that failed: take the lock back (only if nobody else holds it) so this server saves again.
function Profile.Reclaim(player)
	local id = player.UserId
	if not handedOff[id] or not cache[id] or not store then
		return not handedOff[id]
	end
	local took = false
	local okCall = pcall(store.UpdateAsync, store, key(id), function(old)
		old = type(old) == "table" and old or {}
		local lock = old.Lock
		if type(lock) == "table" and lock.JobId ~= JOB and os.time() - (tonumber(lock.Time) or 0) < LOCK_AGE then
			took = false
			return nil
		end
		local version = tonumber(old.Version)
		if version and version > KNOWN_VERSION then
			took = false
			return nil
		end
		took = true
		local data = cache[id]
		data.Lock = { JobId = JOB, Time = os.time() }
		return data
	end)
	if cache[id] then
		cache[id].Lock = nil
	end
	if okCall and took then
		handedOff[id] = nil
		lastWrite[id] = os.clock()
		return true
	end
	return false
end

-- the throttle and the keep-alive
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local id = player.UserId
			if cache[id] and not writing[id] and not flushing[id] and not handedOff[id] and not noSave[id] then
				local since = now - (lastWrite[id] or 0)
				if (dirty[id] and since >= THROTTLE) or since >= KEEPALIVE then
					task.spawn(write, player, id, false)
				end
			end
		end
	end
end)

-- Setters ------------------------------------------------------------------------------------------------------------

function Profile.SetAttire(player, name)
	local data = Profile.Get(player)
	data.Attire = name
	player:SetAttribute("Attire", name)
	touch(player)
end

function Profile.SetEscaped(player)
	local data = Profile.Get(player)
	data.Escaped = true
	player:SetAttribute("Escaped", true)
	touch(player)
end

function Profile.SetSettings(player, settings)
	local data = Profile.Get(player)
	data.Settings = settings
	touch(player)
end

-- Scrip: adds (or with a negative amount takes) and returns the new balance.
function Profile.AddScrip(player, amount)
	local data = Profile.Get(player)
	amount = math.floor(tonumber(amount) or 0)
	data.Scrip = math.max(0, (tonumber(data.Scrip) or 0) + amount)
	player:SetAttribute("Scrip", data.Scrip)
	touch(player)
	return data.Scrip
end

-- Scrip earned by playing (not bought): VIP (the Vip attribute, StoreServer) adds GameConfig.Scrip.VipBonus on top.
-- Returns what went in.
function Profile.Earn(player, amount)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if player:GetAttribute("Vip") then
		amount = math.floor(amount * (1 + GameConfig.Scrip.VipBonus) + 0.5)
	end
	Profile.AddScrip(player, amount)
	return amount
end

-- Takes amount Scrip; false (and takes nothing) if the player hasn't got it.
function Profile.SpendScrip(player, amount)
	local data = Profile.Get(player)
	amount = math.floor(tonumber(amount) or 0)
	if amount < 0 or (tonumber(data.Scrip) or 0) < amount then
		return false
	end
	Profile.AddScrip(player, -amount)
	return true
end

function Profile.Owns(player, item)
	local owned = Profile.Get(player).Owned
	return type(owned) == "table" and owned[item] == true
end

function Profile.Grant(player, item)
	if type(item) ~= "string" then
		return
	end
	local data = Profile.Get(player)
	local owned = map(data, "Owned")
	owned[item] = true
	player:SetAttribute("Owned", json(owned))
	touch(player)
end

-- The campaign's class pick (top-level Class; the lobby's v2 loadouts are not touched).
function Profile.SetClass(player, name)
	local data = Profile.Get(player)
	data.Class = name
	player:SetAttribute("Class", name)
	touch(player)
end

-- One-time flags. SetFlag returns false if the flag was already set; value = false clears it.
function Profile.Flag(player, name)
	local flags = Profile.Get(player).Flags
	return type(flags) == "table" and flags[name] == true
end

function Profile.SetFlag(player, name, value)
	local data = Profile.Get(player)
	local flags = map(data, "Flags")
	if value == false then
		flags[name] = nil
		touch(player)
		return true
	end
	if flags[name] then
		return false
	end
	flags[name] = true
	touch(player)
	return true
end

-- Counters (Matches, Deaths, EndlessBest, WarRuns, Tokens): adds by (default 1) and returns the new count. The
-- top-level field is what the campaign reads; on a v2 record Stats is kept in step the way the lobby counts.
function Profile.Count(player, name, by)
	local data = Profile.Get(player)
	local n = tonumber(by) or 1
	touch(player)
	if name == "Tokens" then
		data.Tokens = math.max(0, (tonumber(data.Tokens) or 0) + n)
		player:SetAttribute("Tokens", data.Tokens)
		return data.Tokens
	end
	if not isV2(data) then
		data[name] = math.max(0, (tonumber(data[name]) or 0) + n)
		return data[name]
	end
	local stats = map(data, "Stats")
	if name == "WarRuns" then
		data.WarRuns = math.max(0, (tonumber(data.WarRuns) or 0) + n)
		stats.CampaignClears = math.max(0, (tonumber(stats.CampaignClears) or 0) + n)
		return data.WarRuns
	end
	stats[name] = math.max(0, (tonumber(stats[name]) or 0) + n)
	if LEGACY_TOP[name] then
		data[name] = stats[name]
	end
	return stats[name]
end

-- Purchases: whether this receipt was granted before, and remembering one (the last 50). v1 keeps them in Receipts,
-- v2 in PurchaseIds (the lobby copies Receipts into PurchaseIds when it migrates).
function Profile.HasReceipt(player, purchaseId)
	local data = Profile.Get(player)
	for _, field in { "PurchaseIds", "Receipts" } do
		local list = data[field]
		if type(list) == "table" and table.find(list, purchaseId) ~= nil then
			return true
		end
	end
	return false
end

function Profile.AddReceipt(player, purchaseId)
	local data = Profile.Get(player)
	local list = map(data, if isV2(data) then "PurchaseIds" else "Receipts")
	table.insert(list, purchaseId)
	while #list > 50 do
		table.remove(list, 1)
	end
	touch(player)
end

-- Join and leave -----------------------------------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	Profile.Get(player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(Profile.Get, player)
end

Players.PlayerRemoving:Connect(function(player)
	local id = player.UserId
	while loading[id] do
		task.wait()
	end
	if cache[id] and not handedOff[id] and not noSave[id] and store then
		flushing[id] = true
		local since = os.clock() - (lastWrite[id] or 0)
		if since < 6 then
			task.wait(6 - since)
		end
		write(player, id, true)
		flushing[id] = nil
	end
	cache[id] = nil
	noSave[id] = nil
	handedOff[id] = nil
	dirty[id] = nil
	lastWrite[id] = nil
end)

game:BindToClose(function()
	-- PlayerRemoving fires for everyone still here; wait for those flushes (and any write in flight)
	local t = os.clock()
	task.wait(0.5)
	while (next(flushing) or next(writing)) and os.clock() - t < 25 do
		task.wait(0.25)
	end
end)

return Profile
