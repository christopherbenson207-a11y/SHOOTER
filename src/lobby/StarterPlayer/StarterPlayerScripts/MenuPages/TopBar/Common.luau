-- Shared helpers for FRONT-A's pages (TopBar, Home, Play, Party, Loading) and MenuClient: mode cards, unlock rules,
-- the squad from the Party state, NEW pips. Pure reads of GameConfig, Shared.Progression and player attributes.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Progression = require(Shared:WaitForChild("Progression"))

local C = {}
C.Progression = Progression
C.GameConfig = GameConfig

function C.Decode(v)
	if type(v) == "string" and (v:sub(1, 1) == "{" or v:sub(1, 1) == "[") then
		local ok, t = pcall(HttpService.JSONDecode, HttpService, v)
		if ok then
			return t
		end
	end
	return if type(v) == "table" then v else nil
end

-- A JSON set that may arrive as {key = true} or as an array of keys.
function C.Set(v)
	local t = C.Decode(v) or {}
	local out = {}
	for k, x in t do
		if type(k) == "number" and type(x) == "string" then
			out[x] = true
		elseif x then
			out[k] = true
		end
	end
	return out
end

function C.Stats(p)
	return C.Decode(p:GetAttribute("Stats")) or {}
end

-- Modes -------------------------------------------------------------------------------------------------------------

local NAMES = { Campaign = "FRONTLINE" } -- the campaign place plays FRONTLINE since 6 Nov 2026
local WIDE_ART = { Outbreak = true, Defend = true, Campaign = true } -- Loading/<Mode> keys that exist

-- Campaign chapters (4 Nov 2026): GameConfig.War.Chapters, in play order. Chapter 1 is Operation Last Light; a chapter
-- that is not Ready shows as COMING SOON. C.Missions stays chapter 1's list for the pages that read it.
C.Chapters = (GameConfig.War and GameConfig.War.Chapters) or {
	{
		Name = "OPERATION LAST LIGHT", Line = "TAKE THE TOWN BACK", Ready = true,
		Missions = { { Id = "HotDrop", Name = "HOT DROP" }, { Id = "Signal", Name = "SIGNAL" }, { Id = "LastLight", Name = "LAST LIGHT" } },
	},
}
C.Missions = C.Chapters[1].Missions

function C.MissionsOf(chapter)
	local c = C.Chapters[tonumber(chapter) or 1]
	return (c and c.Missions) or {}
end

-- Locked for this player? Only chapters that are not built yet, for now.
function C.ChapterLocked(_p, chapter)
	local c = C.Chapters[tonumber(chapter) or 0]
	if not c or c.Ready ~= true then
		return true, "COMING SOON"
	end
	return false, nil
end

local function campaignChips()
	local chapters, missions = 0, 0
	for _, c in C.Chapters do
		if c.Ready == true then
			chapters += 1
			missions += #(c.Missions or {})
		end
	end
	return { "MULTIPLAYER", "12 V 12", missions .. " SECTORS" }
end

local CHIPS = {
	Outbreak = { "TUTORIAL", "1-4 SQUAD" }, -- 5 Nov 2026: Outbreak is the tutorial mode, the way into the harder ones
	Defend = { "1-4 SQUAD", "SOLDIERS" },
	Endless = { "1-4 SQUAD", "ROUNDS" },
	Nightmare = { "1-4 SQUAD", "5 NIGHTS", "HARD" },
	Campaign = campaignChips(),
}

-- FRONTLINE (the "Campaign" id, kept so saves, teleports and MenuServer need no change) is the game's multiplayer
-- mode: two teams of 12, public servers. Every other card is a 1-4 squad co-op mode.
function C.Multiplayer(id)
	return id == "Campaign"
end

-- PLAY cards: FRONTLINE first (the main mode of a war shooter, 6 Nov 2026), then GameConfig.Menu.Modes in order.
function C.Modes()
	local out = { "Campaign" }
	for _, m in GameConfig.Menu.Modes do
		if GameConfig.Modes[m] and m ~= "War" and m ~= "Extraction" then
			table.insert(out, m)
		end
	end
	return out
end

function C.Info(id)
	local rules = GameConfig.Modes[id] or {}
	local line = rules.Line
	if id == "Campaign" then
		line = "MULTIPLAYER. TWO TEAMS OF 12 PUSH AND HOLD THE LINE"
		-- The Front (ServerScriptService.FrontBoard): this week's sectors taken across every server.
		local week, goal = workspace:GetAttribute("FrontWeek"), workspace:GetAttribute("FrontWeekGoal")
		if type(week) == "number" and type(goal) == "number" then
			line = string.format("MULTIPLAYER. THE FRONT: %d / %d SECTORS TAKEN THIS WEEK", math.min(week, goal), goal)
		end
	end
	return {
		Id = id,
		Name = NAMES[id] or string.upper(id),
		Line = line or "",
		Chips = CHIPS[id] or { "1-4 SQUAD" },
		Art = "Mode/" .. id,
		Wide = "Loading/" .. (if WIDE_ART[id] then id else "Outbreak"),
	}
end

-- Locked for this player? Nightmare opens with the first escape (and any GameConfig Unlock rule). Endless is open
-- from the start (owner, 5 Nov 2026).
function C.Locked(p, id)
	if id == "Nightmare" then
		if p:GetAttribute("Escaped") ~= true then
			return true, "FINISH THE TUTORIAL"
		end
	end
	local rules = GameConfig.Modes[id]
	if rules and rules.Unlock and p:GetAttribute(rules.Unlock) ~= true then
		return true, "FINISH THE TUTORIAL"
	end
	return false, nil
end

-- HOME's play card: the last mode played this session if it is open, else the first card.
function C.Recommended(p)
	local last = p:GetAttribute("MenuLastMode") or p:GetAttribute("Mode")
	if type(last) == "string" and (last == "Campaign" or GameConfig.Modes[last]) and table.find(C.Modes(), last)
		and not C.Locked(p, last)
	then
		return last
	end
	return C.Modes()[1]
end

-- Squad ------------------------------------------------------------------------------------------------------------

-- The party as the menu shows it: members (the local player first when alone), leader id, state, count.
function C.Squad(ctx)
	local s = ctx.partyState
	local me = ctx.player
	if type(s) ~= "table" or type(s.Members) ~= "table" or #s.Members == 0 then
		return {
			Members = { {
				UserId = me.UserId, Name = me.DisplayName ~= "" and me.DisplayName or me.Name,
				Level = me:GetAttribute("Level") or 1, Class = me:GetAttribute("Class") or "Rifleman",
				Card = me:GetAttribute("Card") or "Default", Status = "IDLE",
			} },
			Leader = me.UserId, State = "Idle", Count = nil, Solo = true,
		}
	end
	return {
		Members = s.Members, Leader = s.Leader, State = s.State or "Idle", Count = s.Count, Mode = s.Mode,
		Chapter = s.Chapter, Join = s.Join, Solo = #s.Members <= 1,
	}
end

function C.IsLeader(ctx)
	local s = C.Squad(ctx)
	return s.Leader == ctx.player.UserId
end

function C.MyStatus(ctx)
	for _, m in C.Squad(ctx).Members do
		if m.UserId == ctx.player.UserId then
			return m.Status or "IDLE"
		end
	end
	return "IDLE"
end

-- READY (5 Nov 2026): squad mates mark READY (Party snapshot: Ready = true, Status "READY"); the leader never does.
function C.IsReady(member)
	return type(member) == "table" and (member.Ready == true or member.Status == "READY")
end

-- The mode HOME deploys: in a squad the leader's pick (Party Mode and Chapter, so HOME and PLAY agree and the mates
-- readied for it), else the recommended mode. Returns mode, chapter.
function C.DeployMode(ctx)
	local squad = C.Squad(ctx)
	local m = squad.Mode
	if not squad.Solo and type(m) == "string" and table.find(C.Modes(), m) and not C.Locked(ctx.player, m) then
		return m, if m == "Campaign" then tonumber(squad.Chapter) or 1 else nil
	end
	return C.Recommended(ctx.player), nil
end

-- The leader's one-line notice beside DEPLOY (an authored Notice frame: Plate + Text), e.g. WAITING ON MOTH_RUNNER
-- +1. One line at a time: a new one replaces the one showing; it goes after `seconds`.
local noticeToken = 0
function C.Notice(ctx, frame, label, text, seconds)
	if not (frame and label) then
		return
	end
	noticeToken += 1
	local token = noticeToken
	label.Text = text
	if not frame.Visible then
		ctx.ui.Show(frame, true)
	end
	task.delay(seconds or 3, function()
		if noticeToken == token and frame.Visible then
			ctx.ui.Show(frame, false)
		end
	end)
end

-- "WAITING ON NAME" for the first mate the deploy waits on, "+N" for the rest.
function C.WaitingLine(names)
	local list = if type(names) == "table" then names else {}
	local first = string.upper(tostring(list[1] or "SQUAD"))
	return "WAITING ON " .. first .. (if #list > 1 then "  +" .. (#list - 1) else "")
end

-- Swap the last word of an image's art key: "Home/StatusReady" -> "Home/StatusLoadout" (PHONE keys too).
function C.SwapArt(ui, img, from, to)
	if not img then
		return
	end
	local key = img:GetAttribute("UiArt")
	if type(key) ~= "string" then
		return
	end
	local base = img:GetAttribute("_BaseArt")
	if not base then
		base = key
		img:SetAttribute("_BaseArt", base)
	end
	local new = base:gsub(from .. "$", to)
	if ui.Art(new) then
		ui.SetArt(img, new)
	end
end

-- Fill a squad slot clone (Home and Play share the template shape). member nil = an empty slot (INVITE).
function C.FillSlot(ctx, slot, member, leaderId, onInvite)
	local ui = ctx.ui
	local filled = slot:FindFirstChild("Filled")
	local invite = slot:FindFirstChild("Invite")
	if not member then
		if filled then
			filled.Visible = false
		end
		if invite then
			invite.Visible = true
			ui.Button(invite, onInvite)
		end
		return
	end
	if invite then
		invite.Visible = false
	end
	if not filled then
		return
	end
	filled.Visible = true
	local card = filled:FindFirstChild("Card")
	if card and ui.Art("Card/" .. tostring(member.Card or "Default")) then
		ui.SetArt(card, "Card/" .. tostring(member.Card or "Default"))
	end
	local emblem = filled:FindFirstChild("Emblem")
	if emblem and ui.Art("Emblem/" .. tostring(member.Class or "Rifleman")) then
		ui.SetArt(emblem, "Emblem/" .. tostring(member.Class or "Rifleman"))
	end
	local isLeader = member.UserId == leaderId
	local lead = filled:FindFirstChild("Leader")
	if lead then
		lead.Visible = isLeader
	end
	ui.Text(filled:FindFirstChild("Name"), string.upper(tostring(member.Name or "")))
	ui.Text(filled:FindFirstChild("Level"), "LV " .. tostring(member.Level or 1))
	local status = filled:FindFirstChild("Status")
	if status then
		local st = tostring(member.Status or "IDLE")
		local word = if st == "READY" then "Ready" elseif st == "LOADOUT" then "Loadout" elseif st == "STORE" then "Store"
			elseif isLeader then "Leader" else nil
		status.Visible = word ~= nil
		if word then
			C.SwapArt(ui, status, "Status%a+", "Status" .. word)
		end
	end
end

-- NEW pips and the store ----------------------------------------------------------------------------------------------

-- Selling opens with the first escape or level 3 (DATA's Store "Catalogue" says the same as Selling).
function C.Selling(p)
	return p:GetAttribute("Escaped") == true or (p:GetAttribute("Level") or 1) >= 3
end

local LOADOUT_KINDS = { Gun = true, Gear = true, Class = true, Slot = true }

-- Which tabs have something unlocked or owned that the player has not looked at yet.
function C.NewTabs(p)
	local out = {}
	local seen = C.Set(p:GetAttribute("Seen"))
	if next(seen) == nil and p:GetAttribute("Seen") == nil then
		return out -- no profile yet
	end
	local level = p:GetAttribute("Level") or 1
	for lv = 1, math.min(level, Progression.LevelCap or 50) do
		for _, r in (Progression.Rewards and Progression.Rewards[lv]) or {} do
			if LOADOUT_KINDS[r.Kind] and r.Id and not seen[r.Kind .. "/" .. tostring(r.Id)] then
				out.Loadout = true
			end
		end
	end
	for key in C.Set(p:GetAttribute("Owned")) do
		if type(key) == "string" and key:find("/") and not seen[key] then
			local kind = key:match("^(%a+)/")
			if kind == "Operator" or kind == "Camo" or kind == "Card" or kind == "Beam" then
				out.Store = true
			end
		end
	end
	local pass = Progression.Pass
	local tier = p:GetAttribute("PassTier") or 0
	local claimed = C.Decode(p:GetAttribute("PassClaimed")) or {}
	local function taken(track, t)
		local set = claimed[track]
		return type(set) == "table" and (set[t] or set[tostring(t)])
	end
	if pass then
		for t = 1, math.min(tier, pass.Tiers or 30) do
			if pass.Free and pass.Free[t] and not taken("Free", t) then
				out.Pass = true
			end
			if p:GetAttribute("PassPremium") and pass.Premium and pass.Premium[t] and not taken("Premium", t) then
				out.Pass = true
			end
		end
	end
	return out
end

-- Seconds -> "7H 12M" / "12M 30S".
function C.Left(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
	if h > 0 then
		return string.format("%dH %02dM", h, m)
	end
	return string.format("%dM %02dS", m, s)
end

return C
