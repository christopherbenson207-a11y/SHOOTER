-- Progression (DATA, 2 Nov 2026; replaces CORE's stub): account XP and levels, weapon XP, challenges, Night Pass XP and
-- the after-action report. Contract: horror-shooter/menu/CONTRACTS.md sections 3, 6 and 7; numbers in
-- ReplicatedStorage.Shared.Progression; rules MENU-PLAN 4.2, 9.6, 9.9 and 9.10.
--
--   Progression.OpenLedger(player, mode, variant)  when the player enters a run (MatchServer). Opening again for the
--                                                  same mode and variant keeps the ledger; anything else starts one.
--   Progression.Add(player, reason, amount)        XP for one reason of Shared.Progression.Xp (amount overrides the
--                                                  table): account XP, pass XP and the ledger. For Revive, Board,
--                                                  Night, Wave, Contract, Objective and Escape it also counts the
--                                                  challenge event and the profile stat, so callers make ONE call.
--   Progression.AddCount(player, reason, n)        n times the table value (n nights, n boards).
--   Progression.Event(player, event, n)            challenge counters for everything else: Field, Bandage,
--                                                  Kill:<GearKey>, Mode:<Mode> ... (the names Add already counts are
--                                                  ignored here, so nothing counts twice).
--   Progression.EndMatch(player, result, info)     closes the ledger, first-match-of-the-day bonus, saves once,
--                                                  stores LastAar and sends Remotes.Menu "Aar". Returns the payload.
--   Progression.Ledger(player), LastAar(player), AarSeen(player)
--
-- Kills, elites, headshots and weapon XP come from ServerStorage.Events.EnemyHit (model, part, dealt, isHead, killed,
-- player, pos, dir, ctx?): ctx.GunName (gear passes its key), ctx.Headshot, ctx.Killed and the mob attribute Elite
-- are used when present; without them the kill still counts, with no weapon XP.
-- Account XP is never multiplied by anything paid. Pass XP = match XP + challenge XP, x1.5 while BoostActive (the
-- player attribute MenuServer sets for the match a Squad Boost was spent on). The first match of the UTC day doubles
-- the match's account XP (never pass XP).
-- Changes touch only the cached profile and attributes; EndMatch commits with one save (Profile.SaveNow).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local P = require(Shared:WaitForChild("Progression"))
local Profile = require(ServerStorage.Modules.Profile)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = ServerStorage:WaitForChild("Events")

local Progression = {}

local ledgers = {} -- [player] = ledger

local LEGACY_VARIANT = { Nightmare = "Nightmare", Endless = "Endless" }
-- reasons whose challenge event and stat Add counts by itself
local AUTO = { Revive = "Revives", Board = "Boards", Night = false, Wave = false, Contract = "Contracts",
	Objective = "Objectives", Escape = false }

local function newLedger(player, mode, variant)
	local data = Profile.Get(player)
	if not data then
		return nil
	end
	local level, into, need = P.FromXp(data.Xp)
	local tier, pInto, pNeed = P.PassTier(data.Pass.Xp)
	return {
		Mode = mode,
		Variant = variant,
		Opened = os.time(),
		Rows = {}, -- [reason] = {Value, Xp}
		Base = 0, -- account XP earned in this run from play (the first-match bonus doubles this)
		ChallengeXp = 0, -- account XP from challenges finished in this run (not doubled)
		Kills = 0, Elites = 0, Headshots = 0, Revives = 0, Objectives = 0,
		GunKills = {}, -- [gun] = kills this run
		GunXpFrom = table.clone(data.GunXp),
		XpFrom = data.Xp, LevelFrom = level, IntoFrom = into, NeedFrom = need,
		PassXpFrom = data.Pass.Xp, TierFrom = tier, PassIntoFrom = pInto, PassNeedFrom = pNeed,
		Unlocks = {},
		Touched = {}, -- [challengeId] = true when this run moved it
		ChallengeDone = {}, -- ids finished in this run
		Scrip = { Base = 0, Total = 0, Parts = {} },
	}
end

function Progression.OpenLedger(player, mode, variant)
	mode = mode or workspace:GetAttribute("MatchMode") or player:GetAttribute("Mode") or "Defend"
	variant = variant or workspace:GetAttribute("MatchVariant") or LEGACY_VARIANT[mode] or "Normal"
	local l = ledgers[player]
	if l and l.Mode == mode and l.Variant == variant then
		return l
	end
	Profile.Rollover(player)
	ledgers[player] = newLedger(player, mode, variant)
	return ledgers[player]
end

function Progression.Ledger(player)
	return ledgers[player]
end

local function ledgerFor(player)
	local l = ledgers[player]
	if not l and player:GetAttribute("InMatch") then
		l = Progression.OpenLedger(player)
	end
	return l
end

local function boostMult(player)
	return if player:GetAttribute("BoostActive") then P.BoostPassXp else 1
end

-- Account XP with level-ups and their rewards. Returns the unlock records it granted.
local function gainXp(player, data, amount)
	if amount <= 0 then
		return {}
	end
	local fromLevel, _, _, fromStars = P.FromXp(data.Xp)
	data.Xp += amount
	local toLevel, _, _, toStars = P.FromXp(data.Xp)
	local unlocks = {}
	for lvl = fromLevel + 1, toLevel do
		for _, r in P.Rewards[lvl] or {} do
			local u = Profile.Reward(player, r, "Level:" .. lvl)
			if u then
				u.Level = lvl
				table.insert(unlocks, u)
			end
		end
	end
	for _ = fromStars + 1, toStars do
		Profile.AddScrip(player, P.StarScrip, "Level:Star")
		table.insert(unlocks, { Kind = "Insignia", Id = "Star" })
		table.insert(unlocks, { Kind = "Scrip", Amount = P.StarScrip })
	end
	data.Stars = toStars
	Profile.Publish(player, "Level")
	if #unlocks > 0 then
		local l = ledgers[player]
		if l then
			for _, u in unlocks do
				table.insert(l.Unlocks, u)
			end
		end
		pcall(function()
			Remotes.Menu:FireClient(player, "Unlocked", unlocks)
		end)
	end
	Profile.Touch(player)
	return unlocks
end

local function gainPass(player, data, amount)
	if amount <= 0 then
		return
	end
	data.Pass.Xp += math.floor(amount * boostMult(player) + 0.5)
	Profile.Publish(player, "Pass")
end

-- Challenges ----------------------------------------------------------------------------------------------------------

local function bump(player, data, set, event, n)
	local changed = false
	for _, id in set.Ids or {} do
		local c = P.Challenge(id)
		if c and c.Event == event and not set.Done[id] then
			local now = math.min(c.Goal, (tonumber(set.Progress[id]) or 0) + n)
			set.Progress[id] = now
			changed = true
			local l = ledgers[player]
			if l then
				l.Touched[id] = true
			end
			if now >= c.Goal then
				set.Done[id] = true
				if l then
					table.insert(l.ChallengeDone, id)
					local row = l.Rows.Challenge or { Value = 0, Xp = 0 }
					row.Value += 1
					row.Xp += c.Xp
					l.Rows.Challenge = row
					l.ChallengeXp += c.Xp
				end
				gainXp(player, data, c.Xp)
				gainPass(player, data, c.Xp)
			end
		end
	end
	return changed
end

local function count(player, event, n)
	local data = Profile.Get(player)
	if not data then
		return
	end
	n = tonumber(n) or 1
	if n <= 0 then
		return
	end
	Profile.Rollover(player)
	local a = bump(player, data, data.Daily, event, n)
	local b = bump(player, data, data.Weekly, event, n)
	if a or b then
		Profile.Publish(player, "Challenges")
		Profile.Touch(player)
	end
end

-- Counts a challenge event (contract section 2 names). Names that Add counts by itself are ignored here.
function Progression.Event(player, event, n)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(event) ~= "string" then
		return
	end
	if AUTO[event] ~= nil then
		return
	end
	if event == "Bandage" then
		Profile.Count(player, "Bandages", tonumber(n) or 1)
	end
	count(player, event, n)
end

-- XP ------------------------------------------------------------------------------------------------------------------

-- XP for one reason (Shared.Progression.Xp). amount overrides the table value.
function Progression.Add(player, reason, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(reason) ~= "string" then
		return
	end
	local data = Profile.Get(player)
	if not data then
		return
	end
	amount = math.floor(tonumber(amount) or P.Xp[reason] or 0)
	local l = ledgerFor(player)
	if l then
		local row = l.Rows[reason] or { Value = 0, Xp = 0 }
		row.Value += 1
		row.Xp += math.max(0, amount)
		l.Rows[reason] = row
		l.Base += math.max(0, amount)
		if reason == "Objective" then
			l.Objectives += 1
		elseif reason == "Revive" then
			l.Revives += 1
		end
	end
	local stat = AUTO[reason]
	if stat then
		Profile.Count(player, stat, 1)
	end
	if AUTO[reason] ~= nil then
		count(player, reason, 1)
	end
	if amount > 0 then
		gainXp(player, data, amount)
		gainPass(player, data, amount)
	end
end

-- n times a reason's XP (n nights survived, n boards repaired).
function Progression.AddCount(player, reason, n)
	n = math.floor(tonumber(n) or 1)
	for _ = 1, n do
		Progression.Add(player, reason)
	end
end

-- Kills from EnemyHit -------------------------------------------------------------------------------------------------

local function onKill(player, model, isHead, ctx)
	local data = Profile.Get(player)
	if not data then
		return
	end
	local l = ledgerFor(player)
	if not l then
		return -- not in a run (test range, menu): no XP
	end
	local gun = type(ctx) == "table" and type(ctx.GunName) == "string" and ctx.GunName or nil
	local head = isHead == true or (type(ctx) == "table" and ctx.Headshot == true)
	local elite = (typeof(model) == "Instance" and model:GetAttribute("Elite") == true)
		or (type(ctx) == "table" and ctx.Elite == true)
	l.Kills += 1
	data.Stats.Kills += 1
	Progression.Add(player, "Kill")
	count(player, "Kill", 1)
	if head then
		l.Headshots += 1
		data.Stats.Headshots += 1
		Progression.Add(player, "Headshot")
		count(player, "Headshot", 1)
	end
	if elite then
		l.Elites += 1
		data.Stats.Elites += 1
		Progression.Add(player, "Elite")
		count(player, "Elite", 1)
	end
	local class = player:GetAttribute("Class")
	if type(class) == "string" then
		count(player, "Class:" .. class, 1)
	end
	if gun then
		count(player, "Kill:" .. gun, 1)
		if gun == "Frag" then
			data.Stats.FragKills += 1
		end
		l.GunKills[gun] = (l.GunKills[gun] or 0) + 1
		local gs = data.GunStats[gun] or { K = 0, H = 0, E = 0 }
		gs.K += 1
		if head then
			gs.H += 1
		end
		if elite then
			gs.E += 1
		end
		data.GunStats[gun] = gs
		if P.Slots[gun] == "Primary" or P.Slots[gun] == "Secondary" then
			local W = P.Weapon.Xp
			local wxp = W.Kill + (if head then W.Headshot else 0) + (if elite then W.Elite else 0)
			data.GunXp[gun] = (tonumber(data.GunXp[gun]) or 0) + wxp
			Profile.Publish(player, "Gun")
		end
	end
	Profile.Publish(player, "Stats")
	Profile.Touch(player)
end

Events:WaitForChild("EnemyHit").Event:Connect(function(model, _part, _dealt, isHead, killed, player, _pos, _dir, ctx)
	if type(ctx) == "table" and ctx.Killed ~= nil then
		killed = ctx.Killed
	end
	if not killed or typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return
	end
	task.spawn(onKill, player, model, isHead, ctx)
end)

-- Match Scrip goes into the ledger so the AAR shows it (Profile.Earn calls this).
Profile.OnEarn(function(player, base, total, parts)
	local l = ledgers[player]
	if l then
		l.Scrip.Base += base
		l.Scrip.Total += total
		for k in parts do
			l.Scrip.Parts[k] = true
		end
	end
end)

-- After-action report -------------------------------------------------------------------------------------------------

local ROW_ORDER = { "Kill", "Elite", "Headshot", "Revive", "Board", "Night", "Wave", "Contract", "Objective",
	"MissionComplete", "Escape", "Beacon", "Finished", "Challenge" }
local ROW_ID = { Kill = "Kills", Elite = "Elites", Headshot = "Headshots", Revive = "Revives", Board = "Boards",
	Night = "Nights", Wave = "Waves", Contract = "Contracts", Objective = "Objectives", Challenge = "Challenges" }

local function mostUsed(gunKills)
	local best, n = nil, 0
	for gun, k in gunKills do
		if k > n or (k == n and best and gun < best) then
			best, n = gun, k
		end
	end
	return best
end

local function challengeRows(data, l)
	local rows = {}
	local function add(set)
		for _, id in set.Ids or {} do
			local c = P.Challenge(id)
			if c and (not c.Weekly or l.Touched[id]) then
				table.insert(rows, {
					Id = id, Label = c.Label, Progress = tonumber(set.Progress[id]) or 0, Goal = c.Goal,
					Done = set.Done[id] == true, Xp = c.Xp, Weekly = c.Weekly,
				})
			end
		end
	end
	add(data.Daily)
	add(data.Weekly)
	return rows
end

local function squadEntry(member)
	local ml = ledgers[member]
	return {
		UserId = member.UserId,
		Name = member.DisplayName,
		Class = member:GetAttribute("Class"),
		Card = member:GetAttribute("Card"),
		Operator = member:GetAttribute("Operator"),
		Kills = ml and ml.Kills or 0,
		Revives = ml and ml.Revives or 0,
		Elites = ml and ml.Elites or 0,
		Objectives = ml and ml.Objectives or 0,
		Mvp = false,
	}
end

-- result: "Escaped" | "Survived" | "Overrun" | "MissionComplete" | "MissionFailed".
-- info: {Mode, Variant, Mission, Nights, Waves, Objectives, Squad = {players}}. Nights and Waves are credited here only
-- when the caller did not already Add them during the run.
function Progression.EndMatch(player, result, info)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	info = type(info) == "table" and info or {}
	local data = Profile.Get(player)
	if not data then
		return nil
	end
	local l = ledgers[player] or Progression.OpenLedger(player, info.Mode, info.Variant)
	if not l then
		return nil
	end
	local mode = info.Mode or l.Mode
	local variant = info.Variant or l.Variant or LEGACY_VARIANT[mode] or "Normal"
	if LEGACY_VARIANT[variant] == nil and LEGACY_VARIANT[mode] then
		variant = mode
	end
	-- Modes v3: Nightmare is a harder Outbreak (it counts for both); Endless is its own mode
	local baseMode = if mode == "Nightmare" then "Outbreak" else mode

	-- what the caller has not already credited
	if result == "Escaped" and not l.Rows.Escape then
		Progression.Add(player, "Escape")
	end
	if result == "MissionComplete" and not l.Rows.MissionComplete then
		Progression.Add(player, "MissionComplete")
	end
	if not l.Rows.Night and (tonumber(info.Nights) or 0) > 0 then
		Progression.AddCount(player, "Night", info.Nights)
	end
	if not l.Rows.Wave and (tonumber(info.Waves) or 0) > 0 then
		Progression.AddCount(player, "Wave", info.Waves)
	end
	if result ~= "MissionFailed" or (tonumber(info.Objectives) or 0) > 0 then
		Progression.Add(player, "Finished")
	end
	count(player, "Mode:" .. baseMode, 1)
	local extra = if LEGACY_VARIANT[variant] then variant elseif mode ~= baseMode then mode else nil
	if extra and extra ~= baseMode then
		count(player, "Mode:" .. extra, 1)
	end
	if result == "Escaped" then
		data.Stats.Escapes += 1
		if variant == "Nightmare" then
			data.Stats.NightmareEscapes += 1
		end
	end
	if result == "MissionComplete" and (info.Mission == nil or info.Mission == 3) then
		data.Stats.CampaignClears += 1
	end

	-- first match of the UTC day: the run's account XP once more (never pass XP)
	local bonus = 0
	local day = P.Day()
	if data.LastFirstMatch ~= day and l.Base > 0 then
		data.LastFirstMatch = day
		bonus = l.Base * (P.FirstMatchBonus - 1)
		gainXp(player, data, bonus)
	end

	local firstMatch = not data.Flags.FirstAar
	data.Flags.FirstAar = true

	-- most-used gun (this run, and over the profile for the service record)
	local gun = mostUsed(l.GunKills)
	local gunInfo = nil
	if gun and (P.Slots[gun] == "Primary" or P.Slots[gun] == "Secondary") then
		local from = tonumber(l.GunXpFrom[gun]) or 0
		local to = tonumber(data.GunXp[gun]) or 0
		gunInfo = { Key = gun, XpFrom = from, XpTo = to, LevelFrom = (P.WeaponFromXp(from)), LevelTo = (P.WeaponFromXp(to)) }
	end
	local all, allN = nil, 0
	for g, gs in data.GunStats do
		if (gs.K or 0) > allN and (P.Slots[g] == "Primary" or P.Slots[g] == "Secondary") then
			all, allN = g, gs.K
		end
	end
	data.Stats.MostUsedGun = all

	-- squad and MVP (revives, objectives and elites; never kills)
	local squad = {}
	local members = type(info.Squad) == "table" and info.Squad or { player }
	local best, bestScore = nil, 0
	for _, m in members do
		if typeof(m) == "Instance" and m:IsA("Player") then
			local e = squadEntry(m)
			table.insert(squad, e)
			local score = e.Revives * 3 + e.Objectives * 3 + e.Elites * 2
			if score > bestScore then
				best, bestScore = e, score
			end
		end
		if #squad >= 4 then
			break
		end
	end
	if best then
		best.Mvp = true
	end

	local rows = {}
	for _, reason in ROW_ORDER do
		local r = l.Rows[reason]
		if r then
			table.insert(rows, { Id = ROW_ID[reason] or reason, Value = r.Value, Xp = r.Xp })
		end
	end

	local levelTo, intoTo, needTo = P.FromXp(data.Xp)
	local tierTo, pInto, pNeed = P.PassTier(data.Pass.Xp)

	-- Scrip line: once a UTC day, a player without Double Scrip sees what it would have paid
	local withDouble = nil
	if l.Scrip.Base > 0 and not player:GetAttribute("DoubleScrip") and data.Flags.DoubleHintDay ~= day then
		data.Flags.DoubleHintDay = day
		local m = Profile.Multiplier(player)
		withDouble = math.floor(l.Scrip.Base * math.min(4, m * 2) + 0.5)
	end

	local payload = {
		Result = result,
		Mode = baseMode,
		Variant = variant,
		Mission = info.Mission,
		FirstMatch = firstMatch,
		Squad = squad,
		Rows = rows,
		Xp = {
			Base = l.Base + l.ChallengeXp, Bonus = bonus, Total = l.Base + l.ChallengeXp + bonus,
			LevelFrom = l.LevelFrom, LevelTo = levelTo, IntoFrom = l.IntoFrom, IntoTo = intoTo,
			NeedFrom = l.NeedFrom, NeedTo = needTo,
		},
		Unlocks = l.Unlocks,
		Gun = gunInfo,
		Pass = {
			TierFrom = l.TierFrom, TierTo = tierTo, IntoFrom = l.PassIntoFrom, IntoTo = pInto,
			NeedFrom = l.PassNeedFrom, NeedTo = pNeed, Boost = player:GetAttribute("BoostActive") == true,
		},
		Challenges = challengeRows(data, l),
		Scrip = { Base = l.Scrip.Base, Total = l.Scrip.Total, WithDouble = withDouble },
		At = os.time(),
	}

	data.LastAar = table.clone(payload)
	data.LastAar.Seen = false
	ledgers[player] = nil
	player:SetAttribute("BoostActive", nil)
	Profile.Publish(player, "Stats")
	Profile.Publish(player, "Aar")
	Profile.Publish(player, "Pass")
	Profile.Publish(player, "Challenges")
	pcall(function()
		Remotes.Menu:FireClient(player, "Aar", payload)
	end)
	task.spawn(Profile.SaveNow, player)
	return payload
end

-- The saved AAR (Store "Aar") and marking it seen (Store "AarSeen").
function Progression.LastAar(player)
	local data = Profile.Get(player)
	return data and data.LastAar
end

function Progression.AarSeen(player)
	local data = Profile.Get(player)
	if data and type(data.LastAar) == "table" and not data.LastAar.Seen then
		data.LastAar.Seen = true
		Profile.Publish(player, "Aar")
		Profile.Touch(player)
	end
end

Profile.OnLoaded(function(player)
	Profile.Rollover(player)
end)

Players.PlayerRemoving:Connect(function(player)
	ledgers[player] = nil
end)

return Progression
