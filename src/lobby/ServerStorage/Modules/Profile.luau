-- Profile v2 (DATA, 2 Nov 2026): what a player keeps between sessions, and the player attributes the menu reads.
-- Contract: horror-shooter/menu/CONTRACTS.md sections 3 and 4; schema MENU-PLAN 4.1, saving and migration 9.9.
--
-- DataStore: LastLightProfile_Studio_v1 in Studio, LastLightProfile_v1 live (unchanged from v1: Studio never touches
-- live saves). Key "u"..UserId. The record carries Version = 2; a v1 record is migrated once on its first load.
--
-- Saving (9.9):
--   * Load with UpdateAsync and take a session lock Lock = {JobId, Time}. If another server holds a lock younger than
--     LOCK_AGE, retry for about LOAD_WAIT seconds, then take it over. If loading still fails the session never saves
--     (noSave) and the player attribute ProfileFailed is set, so the menu can ask for a rejoin.
--   * Changes only touch the cached table and attributes (Profile.Touch marks it dirty). A write goes out at most
--     every THROTTLE seconds per player, plus a keep-alive write every KEEPALIVE seconds that refreshes the lock.
--     Every write is an UpdateAsync whose transform refuses unless the stored Lock is this server's.
--   * PlayerRemoving flushes and releases the lock; BindToClose waits for those flushes.
--   * SaveNow(player, release) writes at once (purchases, teleports). release = true writes Lock = nil and marks the
--     session handed off: later saves in this server are skipped, so the next server loads what was handed over.
--     Reclaim(player) takes the lock back after a teleport that failed.
-- Scrip: Earn (match pay, the only place multipliers apply), AddScrip (purchases and rewards), SpendScrip. Every
--   Scrip source and sink is logged with AnalyticsService:LogEconomyEvent (in pcall).
--
-- Old callers keep working: Get(player) still yields until loaded and returns the table (nil only if the player left);
-- Count(player, "Matches" | "Deaths" | "EndlessBest" | "WarRuns") also keeps the old top-level field; Tokens stays
-- top-level; SetAttire, SetEscaped, SetSettings, SetClass, HasReceipt and AddReceipt still exist.

local AnalyticsService = game:GetService("AnalyticsService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local P = require(Shared:WaitForChild("Progression"))
local C = require(Shared:WaitForChild("Catalogue"))

local STORE = if RunService:IsStudio() then "LastLightProfile_Studio_v1" else "LastLightProfile_v1"
local VERSION = 2
local THROTTLE = 7 -- seconds between writes for one key
local KEEPALIVE = 60 -- a write at least this often while the player is here (keeps the lock fresh)
local LOCK_AGE = 90 -- a lock older than this is stale
local LOAD_WAIT = 10 -- seconds to wait for another server's lock before taking over
local JOB = if game.JobId ~= "" then game.JobId else "Studio"

local Profile = {}
Profile.StoreName = STORE

local cache = {} -- [userId] = data
local loading = {} -- [userId] = true while the first load runs
local noSave = {} -- [userId] = true: never write (load failed, or the lock was lost)
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

-- Analytics --------------------------------------------------------------------------------------------------------

local TRANSACTION = {
	Match = "Gameplay", Reward = "Gameplay", Level = "Gameplay", Pass = "Gameplay", Group = "Gameplay",
	Robux = "IAP", Product = "IAP", Shop = "Shop", Reroll = "Shop",
}
local function logEconomy(player, amount, balance, reason)
	if amount == 0 then
		return
	end
	pcall(function()
		local reasonText = tostring(reason or "Gameplay")
		local head = string.match(reasonText, "^(%a+)") or "Gameplay"
		local tname = TRANSACTION[head] or "Gameplay"
		AnalyticsService:LogEconomyEvent(
			player,
			if amount > 0 then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
			"Scrip",
			math.abs(amount),
			balance,
			Enum.AnalyticsEconomyTransactionType[tname].Name,
			reasonText
		)
	end)
end
Profile.LogEconomy = logEconomy

-- Schema -----------------------------------------------------------------------------------------------------------

local STAT_KEYS = { "Kills", "Elites", "Headshots", "FragKills", "Revives", "Escapes", "NightmareEscapes",
	"CampaignClears", "Matches", "Deaths", "EndlessBest", "Bandages", "Boards", "Objectives", "Contracts" }
local LEGACY_TOP = { Matches = true, Deaths = true, EndlessBest = true, WarRuns = true }

local function defaultLoadout()
	return table.clone(P.DefaultLoadout)
end

-- Fill every missing v2 field (safe to run on every load).
local function fill(data)
	data.Scrip = tonumber(data.Scrip) or 0
	data.Owned = type(data.Owned) == "table" and data.Owned or {}
	data.Flags = type(data.Flags) == "table" and data.Flags or {}
	data.Tokens = tonumber(data.Tokens) or 0
	data.Xp = tonumber(data.Xp) or 0
	data.Stars = tonumber(data.Stars) or 0
	if type(data.Loadouts) ~= "table" then
		data.Loadouts = {}
	end
	for i = 1, P.Loadouts do
		if type(data.Loadouts[i]) ~= "table" then
			data.Loadouts[i] = defaultLoadout()
		end
	end
	data.Selected = math.clamp(math.floor(tonumber(data.Selected) or 1), 1, P.Loadouts)
	data.Operator = type(data.Operator) == "string" and data.Operator or "Woodland"
	data.Camos = type(data.Camos) == "table" and data.Camos or {}
	data.Attach = type(data.Attach) == "table" and data.Attach or {} -- {gun = {slot = id}}, Shared.Attachments
	data.Charms = type(data.Charms) == "table" and data.Charms or {}
	data.Beam = type(data.Beam) == "string" and data.Beam or "Warm"
	data.Card = type(data.Card) == "string" and data.Card or "Default"
	data.Pose = type(data.Pose) == "string" and data.Pose or "Default"
	data.GunXp = type(data.GunXp) == "table" and data.GunXp or {}
	data.GunStats = type(data.GunStats) == "table" and data.GunStats or {}
	data.Pass = type(data.Pass) == "table" and data.Pass or {}
	data.Pass.Season = tonumber(data.Pass.Season) or P.Pass.Season
	data.Pass.Xp = tonumber(data.Pass.Xp) or 0
	data.Pass.Premium = data.Pass.Premium == true
	data.Pass.Claimed = type(data.Pass.Claimed) == "table" and data.Pass.Claimed or {}
	data.Pass.Claimed.Free = type(data.Pass.Claimed.Free) == "table" and data.Pass.Claimed.Free or {}
	data.Pass.Claimed.Premium = type(data.Pass.Claimed.Premium) == "table" and data.Pass.Claimed.Premium or {}
	data.Daily = type(data.Daily) == "table" and data.Daily or { Day = -1 }
	data.Weekly = type(data.Weekly) == "table" and data.Weekly or { Week = -1 }
	data.Stats = type(data.Stats) == "table" and data.Stats or {}
	for _, k in STAT_KEYS do
		data.Stats[k] = tonumber(data.Stats[k]) or 0
	end
	data.LastFirstMatch = tonumber(data.LastFirstMatch) or -1
	data.Boosts = tonumber(data.Boosts) or 0
	-- timed boosters (6 Nov 2026, store BOOSTERS rows): os.time() each one runs until, Shared.Catalogue.Boosters
	data.Timed = type(data.Timed) == "table" and data.Timed or {}
	data.Timed.Xp = tonumber(data.Timed.Xp) or 0
	data.Timed.Gems = tonumber(data.Timed.Gems) or 0
	data.Seen = type(data.Seen) == "table" and data.Seen or {}
	data.PurchaseIds = type(data.PurchaseIds) == "table" and data.PurchaseIds or {}
	data.Badges = type(data.Badges) == "table" and data.Badges or {}
	if (tonumber(data.FirstJoin) or 0) <= 0 then
		data.FirstJoin = os.time()
	end
	if (tonumber(data.StarterDeadline) or 0) <= 0 then
		data.StarterDeadline = data.FirstJoin + 48 * 3600
	end
	if data.Version == nil then
		data.Version = VERSION
	end
	return data
end

-- Everything a level reached so far unlocks, as Seen keys ("Gun/AK", "Class/Medic", "Operator/Desert", ...).
local function unlockKeys(level)
	local out = {}
	for lvl = 1, math.min(level, P.LevelCap) do
		for _, r in P.Rewards[lvl] or {} do
			if r.Id and r.Kind ~= "Scrip" and r.Kind ~= "Insignia" then
				table.insert(out, r.Kind .. "/" .. r.Id)
			end
		end
	end
	return out
end
Profile.UnlockKeys = unlockKeys

-- v1 -> v2, once (MENU-PLAN 9.9 and the class compensation in 9.5). Returns data, migrated (true for a real v1 save,
-- false for a new player or a v2 save). Exposed for tests.
function Profile.Migrate(data)
	if type(data) ~= "table" then
		data = {}
	end
	if data.Version ~= nil then
		return fill(data), false
	end
	local fresh = next(data) == nil
	local owned = type(data.Owned) == "table" and data.Owned or {}
	data.Owned = owned
	-- operator from the old Attire pick
	local attire = type(data.Attire) == "string" and data.Attire or nil
	if attire and C.Items["Operator/" .. attire] then
		data.Operator = attire
		owned["Operator/" .. attire] = true
	else
		data.Operator = "Woodland"
	end
	-- classes bought before the update keep working under their new names, plus the perk they paid for (9.5)
	for _, id in { "Hunter", "Firefighter", "Marksman", "Demolition" } do
		if owned[id] then
			owned["Class/" .. id] = true
		end
	end
	if owned.Hunter then
		owned["Class/Scout"] = true
	end
	if owned.Demolition then
		owned["Class/Engineer"] = true
	end
	if owned.StarterPack then
		owned["Operator/Pathfinder"] = true
		owned["Card/FirstNight"] = true
	end
	-- the old class goes into every loadout
	local class = type(data.Class) == "string" and P.Classes[data.Class] and data.Class or P.DefaultClass
	data.Loadouts = {}
	for i = 1, P.Loadouts do
		local l = defaultLoadout()
		l.Class = class
		data.Loadouts[i] = l
	end
	-- counters move into Stats (the old top-level fields stay as mirrors for old readers)
	local stats = {}
	stats.Matches = tonumber(data.Matches) or 0
	stats.Deaths = tonumber(data.Deaths) or 0
	stats.EndlessBest = tonumber(data.EndlessBest) or 0
	stats.CampaignClears = tonumber(data.WarRuns) or 0
	stats.Escapes = data.Escaped and 1 or 0
	data.Stats = stats
	-- a level from the matches already played: 1,500 XP a match, at most level 15
	data.Xp = math.min(stats.Matches * 1500, P.XpAt(15))
	if type(data.Receipts) == "table" then
		data.PurchaseIds = table.clone(data.Receipts)
	end
	data.Version = VERSION
	fill(data)
	-- nothing that was already open shows as NEW
	local level = P.FromXp(data.Xp)
	for _, k in unlockKeys(level) do
		data.Seen[k] = true
	end
	for itemId in owned do
		data.Seen[itemId] = true
	end
	data.Migrated = if fresh then nil else os.time()
	return data, not fresh
end

-- Attributes (contract section 4) ----------------------------------------------------------------------------------

local function cleanLoadout(data, loadout)
	local rules = Shared:FindFirstChild("LoadoutRules")
	local level = P.FromXp(data.Xp)
	if rules then
		local ok, R = pcall(require, rules)
		if ok and type(R) == "table" and R.Clean then
			local ok2, clean = pcall(R.Clean, loadout, level, data.Stats, data.Owned)
			if ok2 and type(clean) == "table" then
				return clean
			end
		end
	end
	local out = {}
	for _, slot in P.LoadoutSlots do
		local v = loadout[slot]
		local okv = false
		if slot == "Class" then
			okv = P.ClassUnlocked(v, level, data.Stats, data.Owned)
		elseif type(v) == "string" and P.Slots[v] == slot then
			okv = (P.UnlockLevel(v) or math.huge) <= level
		end
		out[slot] = if okv then v else P.DefaultLoadout[slot]
	end
	return out
end
Profile.CleanLoadout = cleanLoadout

local function publishLevel(player, data)
	local level, into, need, stars = P.FromXp(data.Xp)
	data.Level = level
	player:SetAttribute("Xp", data.Xp)
	player:SetAttribute("Level", level)
	player:SetAttribute("XpInto", into)
	player:SetAttribute("XpNeed", need)
	player:SetAttribute("Stars", stars)
end

local function publishLoadouts(player, data)
	player:SetAttribute("Loadouts", json(data.Loadouts))
	player:SetAttribute("Selected", data.Selected)
	local kit = cleanLoadout(data, data.Loadouts[data.Selected] or {})
	player:SetAttribute("Kit", json(kit))
	player:SetAttribute("Class", kit.Class)
end

local function publishPass(player, data)
	local tier = P.PassTier(data.Pass.Xp)
	player:SetAttribute("PassSeason", data.Pass.Season)
	player:SetAttribute("PassXp", data.Pass.Xp)
	player:SetAttribute("PassTier", tier)
	player:SetAttribute("PassPremium", data.Pass.Premium)
	player:SetAttribute("PassClaimed", json(data.Pass.Claimed))
end

local function publishChallenges(player, data)
	player:SetAttribute("Daily", json(data.Daily))
	player:SetAttribute("Weekly", json(data.Weekly))
end

local function publishAll(player, data)
	player:SetAttribute("Scrip", data.Scrip)
	player:SetAttribute("Tokens", data.Tokens)
	player:SetAttribute("Owned", json(data.Owned))
	player:SetAttribute("Attire", data.Attire)
	player:SetAttribute("Escaped", data.Escaped == true)
	if type(data.Settings) == "table" then
		player:SetAttribute("Settings", json(data.Settings))
	end
	publishLevel(player, data)
	publishLoadouts(player, data)
	player:SetAttribute("Operator", data.Operator)
	player:SetAttribute("Beam", data.Beam)
	player:SetAttribute("Card", data.Card)
	player:SetAttribute("Pose", data.Pose)
	player:SetAttribute("Camos", json(data.Camos))
	player:SetAttribute("Attach", json(data.Attach))
	player:SetAttribute("Charms", json(data.Charms))
	player:SetAttribute("GunXp", json(data.GunXp))
	player:SetAttribute("GunStats", json(data.GunStats)) -- per-gun mastery {K, H, E} (the picker's Bone and Night locks)
	player:SetAttribute("Stats", json(data.Stats))
	publishPass(player, data)
	publishChallenges(player, data)
	player:SetAttribute("Boosts", data.Boosts)
	player:SetAttribute("BoostXpUntil", data.Timed.Xp)
	player:SetAttribute("BoostGemsUntil", data.Timed.Gems)
	player:SetAttribute("StarterDeadline", data.StarterDeadline)
	player:SetAttribute("FirstJoin", data.FirstJoin)
	player:SetAttribute("Seen", json(data.Seen))
	player:SetAttribute("AarPending", type(data.LastAar) == "table" and data.LastAar.Seen ~= true
		and os.time() - (tonumber(data.LastAar.At) or 0) < 30 * 60)
end

-- Re-publish a group of attributes after a change: "Level", "Loadouts", "Pass", "Challenges", "Stats", "Gun",
-- "Cosmetics", "Owned", "Seen", "Aar", or "All".
function Profile.Publish(player, what)
	local data = cache[player.UserId]
	if not data or not player.Parent then
		return
	end
	if what == "Level" then
		publishLevel(player, data)
		publishLoadouts(player, data) -- a level-up can unlock a class or gun the loadout already names
	elseif what == "Loadouts" then
		publishLoadouts(player, data)
	elseif what == "Pass" then
		publishPass(player, data)
	elseif what == "Challenges" then
		publishChallenges(player, data)
	elseif what == "Stats" then
		player:SetAttribute("Stats", json(data.Stats))
	elseif what == "Gun" then
		player:SetAttribute("GunXp", json(data.GunXp))
		player:SetAttribute("GunStats", json(data.GunStats))
	elseif what == "Cosmetics" then
		player:SetAttribute("Operator", data.Operator)
		player:SetAttribute("Beam", data.Beam)
		player:SetAttribute("Card", data.Card)
		player:SetAttribute("Pose", data.Pose)
		player:SetAttribute("Camos", json(data.Camos))
		player:SetAttribute("Charms", json(data.Charms))
	elseif what == "Attach" then
		player:SetAttribute("Attach", json(data.Attach))
	elseif what == "Owned" then
		player:SetAttribute("Owned", json(data.Owned))
	elseif what == "Seen" then
		player:SetAttribute("Seen", json(data.Seen))
	elseif what == "Aar" then
		-- Only a recent report pops up on its own (30 min): an unseen AAR from days ago greeted players on join.
		local aar = data.LastAar
		local fresh = type(aar) == "table" and os.time() - (tonumber(aar.At) or 0) < 30 * 60
		player:SetAttribute("AarPending", fresh and aar.Seen ~= true)
	else
		publishAll(player, data)
	end
end

-- Loading ------------------------------------------------------------------------------------------------------------

-- One UpdateAsync that takes the lock. Returns data (table) | nil, "locked" | error.
local function tryLoad(userId, force)
	local loaded, why = nil, nil
	local ok, err = pcall(store.UpdateAsync, store, key(userId), function(old)
		old = type(old) == "table" and old or {}
		local lock = old.Lock
		if not force and type(lock) == "table" and lock.JobId ~= JOB and os.time() - (tonumber(lock.Time) or 0) < LOCK_AGE then
			why = "locked"
			return nil -- leave the record as it is
		end
		old.Lock = { JobId = JOB, Time = os.time() }
		loaded = old
		return old
	end)
	if not ok then
		return nil, tostring(err)
	end
	return loaded, why
end

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
		if why ~= "locked" and tries >= 4 then
			warn("Profile: couldn't load", player.Name, "- this session won't save", why)
			return {}, true
		end
		task.wait(if why == "locked" then 2 else tries)
	end
end

local CallbacksOnLoad = {}
-- fn(player, data) after a profile is loaded and published (Progression uses it for rollovers).
function Profile.OnLoaded(fn)
	table.insert(CallbacksOnLoad, fn)
end

-- The player's profile (loads once; callers wait for a load already running). nil if the player left.
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
		return nil
	end
	loading[id] = true
	local loaded, failed = loadData(player)
	if failed then
		noSave[id] = true
		if store then
			player:SetAttribute("ProfileFailed", true)
		end
	end
	data = loaded or {}
	data.Lock = nil
	data = Profile.Migrate(data)
	dirty[id] = true -- the first write goes out within THROTTLE seconds (a migrated or new profile, a fresh lock)
	cache[id] = data
	loading[id] = nil
	lastWrite[id] = os.clock()
	if player.Parent then
		publishAll(player, data)
		for _, fn in CallbacksOnLoad do
			task.spawn(fn, player, data)
		end
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
	if handedOff[userId] or noSave[userId] then
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

-- Mark the profile changed; the throttle writes it within THROTTLE seconds.
function Profile.Touch(player)
	dirty[player.UserId] = true
end

-- Writes now and waits. release = true before any teleport: the lock is released and this server stops saving.
function Profile.SaveNow(player, release)
	local data = Profile.Get(player)
	if not data then
		return false
	end
	local id = player.UserId
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

-- Scrip --------------------------------------------------------------------------------------------------------------

-- Adds (or with a negative amount takes) Scrip with no multipliers; returns the balance. reason is the analytics SKU
-- ("Product:Scrip2", "Level:12", "Pass:Free:9", "Shop:Card/Static", ...).
function Profile.AddScrip(player, amount, reason)
	local data = Profile.Get(player)
	if not data then
		return 0
	end
	amount = math.floor(tonumber(amount) or 0)
	local before = data.Scrip
	data.Scrip = math.max(0, before + amount)
	player:SetAttribute("Scrip", data.Scrip)
	dirty[player.UserId] = true
	logEconomy(player, data.Scrip - before, data.Scrip, reason or (if amount >= 0 then "Reward" else "Shop"))
	return data.Scrip
end

-- Timed boosters ------------------------------------------------------------------------------------------------------

-- Is a timed booster ("Xp" or "Gems") running for this player right now?
function Profile.TimedActive(player, kind)
	local data = cache[player.UserId]
	return data ~= nil and type(data.Timed) == "table" and (tonumber(data.Timed[kind]) or 0) > os.time()
end

-- Account XP multiplier from a running 2X XP booster (Progression.Add applies it to account XP only).
function Profile.XpMult(player)
	return if Profile.TimedActive(player, "Xp") then (C.Multipliers.XpBoost or 2) else 1
end

-- Adds `seconds` to a timed booster: from now if it had run out, else on top of what is left. Returns the new end.
function Profile.AddTimed(player, kind, seconds)
	local data = Profile.Get(player)
	if not data or (kind ~= "Xp" and kind ~= "Gems") then
		return 0
	end
	local now = os.time()
	data.Timed[kind] = math.max(now, tonumber(data.Timed[kind]) or 0) + math.max(0, math.floor(seconds))
	player:SetAttribute("Boost" .. kind .. "Until", data.Timed[kind])
	dirty[player.UserId] = true
	return data.Timed[kind]
end

-- The Scrip multiplier on match pay right now and its parts: VIP 1.2, Double Scrip 2, Squad Boost 1.5 (the player
-- attribute BoostActive, set for the match the boost was spent on), Roblox Premium 1.1; capped at x4.
function Profile.Multiplier(player)
	local M = C.Multipliers
	local parts = {}
	local m = 1
	if player:GetAttribute("Vip") then
		m *= M.Vip
		parts.Vip = true
	end
	if player:GetAttribute("DoubleScrip") then
		m *= M.DoubleScrip
		parts.DoubleScrip = true
	end
	if player:GetAttribute("BoostActive") then
		m *= M.Boost
		parts.Boost = true
	end
	if Profile.TimedActive(player, "Gems") then
		m *= M.GemBoost or 2
		parts.GemBoost = true
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		m *= M.Premium
		parts.Premium = true
	end
	return math.min(m, M.Cap), parts
end

local earnHook = nil
-- Progression registers fn(player, base, total, parts) so the AAR's Scrip line sees match pay.
function Profile.OnEarn(fn)
	earnHook = fn
end

-- Scrip earned by playing: the multipliers apply here and only here. Returns what went in.
function Profile.Earn(player, amount, reason)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	local m, parts = Profile.Multiplier(player)
	local total = math.floor(amount * m + 0.5)
	Profile.AddScrip(player, total, reason or "Match")
	if earnHook then
		task.spawn(earnHook, player, amount, total, parts)
	end
	return total
end

-- Takes Scrip; false (and takes nothing) if the player has not got it.
function Profile.SpendScrip(player, amount, reason)
	local data = Profile.Get(player)
	amount = math.floor(tonumber(amount) or 0)
	if not data or amount < 0 or data.Scrip < amount then
		return false
	end
	Profile.AddScrip(player, -amount, reason or "Shop")
	return true
end

-- Ownership, flags, counters -----------------------------------------------------------------------------------------

function Profile.Owns(player, item)
	local data = Profile.Get(player)
	return data ~= nil and data.Owned[item] == true
end

function Profile.Grant(player, item)
	local data = Profile.Get(player)
	if not data or type(item) ~= "string" then
		return
	end
	data.Owned[item] = true
	player:SetAttribute("Owned", json(data.Owned))
	dirty[player.UserId] = true
end

function Profile.Flag(player, name)
	local data = Profile.Get(player)
	return data ~= nil and data.Flags[name] == true
end

-- Sets a one-time flag; false if it was already set. value = false clears it.
function Profile.SetFlag(player, name, value)
	local data = Profile.Get(player)
	if not data then
		return false
	end
	if value == false then
		data.Flags[name] = nil
		dirty[player.UserId] = true
		return true
	end
	if data.Flags[name] then
		return false
	end
	data.Flags[name] = true
	dirty[player.UserId] = true
	return true
end

-- Stats.<stat> += n (default 1); returns the new count. Tokens is the revive-token count (top-level). The old
-- top-level counters (Matches, Deaths, EndlessBest, WarRuns) are kept in step for old readers.
function Profile.Count(player, stat, n)
	local data = Profile.Get(player)
	if not data then
		return 0
	end
	n = tonumber(n) or 1
	dirty[player.UserId] = true
	if stat == "Tokens" then
		data.Tokens = math.max(0, data.Tokens + n)
		player:SetAttribute("Tokens", data.Tokens)
		return data.Tokens
	end
	if stat == "WarRuns" then
		data.WarRuns = math.max(0, (tonumber(data.WarRuns) or 0) + n)
		stat = "CampaignClears"
	end
	data.Stats[stat] = math.max(0, (tonumber(data.Stats[stat]) or 0) + n)
	if LEGACY_TOP[stat] then
		data[stat] = data.Stats[stat]
	end
	player:SetAttribute("Stats", json(data.Stats))
	return data.Stats[stat]
end

-- Legacy setters ------------------------------------------------------------------------------------------------------

function Profile.SetAttire(player, name)
	local data = Profile.Get(player)
	if not data then
		return
	end
	data.Attire = name
	player:SetAttribute("Attire", name)
	dirty[player.UserId] = true
end

function Profile.SetEscaped(player)
	local data = Profile.Get(player)
	if not data then
		return
	end
	data.Escaped = true
	player:SetAttribute("Escaped", true)
	dirty[player.UserId] = true
end

function Profile.SetSettings(player, settings)
	local data = Profile.Get(player)
	if not data then
		return
	end
	data.Settings = settings
	dirty[player.UserId] = true
end

-- The class of the selected loadout (old StoreServer callers).
function Profile.SetClass(player, name)
	local data = Profile.Get(player)
	if not data or not P.Classes[name] then
		return
	end
	data.Loadouts[data.Selected].Class = name
	publishLoadouts(player, data)
	dirty[player.UserId] = true
end

function Profile.HasReceipt(player, purchaseId)
	local data = Profile.Get(player)
	return data ~= nil and table.find(data.PurchaseIds, purchaseId) ~= nil
end

function Profile.AddReceipt(player, purchaseId)
	local data = Profile.Get(player)
	if not data then
		return
	end
	table.insert(data.PurchaseIds, purchaseId)
	while #data.PurchaseIds > 50 do
		table.remove(data.PurchaseIds, 1)
	end
	dirty[player.UserId] = true
end

-- Rewards (levels, pass tiers, products) ------------------------------------------------------------------------------

-- Gives one reward {Kind, Id, Amount}. Gun, Gear, Class, Slot and Insignia rewards unlock by level alone (nothing to
-- store). Returns the unlock record {Kind, Id, Amount} for the AAR / "Unlocked" message.
function Profile.Reward(player, r, reason)
	local data = Profile.Get(player)
	if not data or type(r) ~= "table" then
		return nil
	end
	local kind = r.Kind
	if kind == "Scrip" then
		Profile.AddScrip(player, r.Amount or 0, reason or "Reward")
	elseif kind == "Boost" then
		data.Boosts += r.Amount or 1
		player:SetAttribute("Boosts", data.Boosts)
		dirty[player.UserId] = true
	elseif kind == "Token" then
		Profile.Count(player, "Tokens", r.Amount or 1)
	elseif kind == "Operator" or kind == "Card" or kind == "Camo" or kind == "Beam" then
		Profile.Grant(player, kind .. "/" .. r.Id)
	end
	return { Kind = kind, Id = r.Id, Amount = r.Amount }
end

-- Daily and weekly challenges, and the Night Pass season, rolled over to now. Publishes when anything changed.
function Profile.Rollover(player)
	local data = Profile.Get(player)
	if not data then
		return
	end
	local changed = false
	local day, week = P.Day(), P.Week()
	if data.Daily.Day ~= day then
		data.Daily = { Day = day, Ids = P.DailyIds(day), Progress = {}, Done = {}, Rerolled = false }
		changed = true
	end
	if data.Weekly.Week ~= week then
		data.Weekly = { Week = week, Ids = P.WeeklyIds(week), Progress = {}, Done = {} }
		changed = true
	end
	if changed then
		publishChallenges(player, data)
	end
	if data.Pass.Season ~= P.Pass.Season then
		-- every reached but unclaimed reward of the old season is granted, then the new season starts
		local old = P.Seasons[data.Pass.Season]
		if old then
			local reached = math.min(old.Tiers, 1 + data.Pass.Xp // old.TierXp)
			for tier = 1, reached do
				if old.Free[tier] and not data.Pass.Claimed.Free[tostring(tier)] then
					Profile.Reward(player, old.Free[tier], "Pass:Free:" .. tier)
				end
				if data.Pass.Premium and old.Premium[tier] and not data.Pass.Claimed.Premium[tostring(tier)] then
					Profile.Reward(player, old.Premium[tier], "Pass:Premium:" .. tier)
				end
			end
		end
		data.Pass = { Season = P.Pass.Season, Xp = 0, Premium = false, Claimed = { Free = {}, Premium = {} } }
		publishPass(player, data)
		changed = true
	end
	if changed then
		dirty[player.UserId] = true
	end
end

-- Seen (NEW pips) ----------------------------------------------------------------------------------------------------

function Profile.MarkSeen(player, ids)
	local data = Profile.Get(player)
	if not data or type(ids) ~= "table" then
		return
	end
	local n = 0
	for _, id in ids do
		if type(id) == "string" and #id <= 64 and not data.Seen[id] then
			data.Seen[id] = true
			n += 1
			if n >= 100 then
				break
			end
		end
	end
	if n > 0 then
		player:SetAttribute("Seen", json(data.Seen))
		dirty[player.UserId] = true
	end
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
