--!strict
-- MenuPages.Aar (FRONT-C, 4 Nov 2026): the AFTER-ACTION REPORT.
-- Elements and binds: horror-shooter/menu/notes/SCREENS-C.md "AAR". Payload: CONTRACTS section 7, from the Menu
-- "Aar" event (live, at run end) or from Store "Aar" when the AarPending attribute is set (an AAR not yet seen).
-- Beat 1 is the squad (plates, MVP, showcase with VIEW ITEM); beat 2 is your progress (XP bar with ticks, level-up
-- stamp, weapon bar, unlock cards, pass bar, challenges, Scrip). A tap anywhere skips ahead. REDEPLOY (default focus)
-- and CONTINUE go to MenuServer; CONTINUE and VIEW ITEM mark the AAR seen (Store "AarSeen").
-- In a Match server the rest of the menu stays hidden: this page turns the menu on by itself when the AAR arrives,
-- hides the persistent chrome, and turns the menu off again when a REDEPLOY starts the next run.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local P = require(Shared:WaitForChild("Progression"))
local C = require(Shared:WaitForChild("Catalogue"))

local function optional(name: string): any
	local m = Shared:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, v = pcall(require, m)
	return if ok then v else nil
end
local GunStats = optional("GunStats")
local Gear = optional("Gear")

local Page = { Name = "Aar", Overlay = false }

local VARIANTS = { "Wide", "Phone" }
local ARROW = "  \u{203A}  "
local DOT = "  \u{00B7}  "
local BEAT1_WIDE = 2.0 -- seconds before beat 2 starts when both beats are on screen
local BEAT1_PHONE = 4.0 -- Phone shows one beat at a time
local MISSIONS = { "HOT DROP", "SIGNAL", "LAST LIGHT" }
local ROW_LABEL = {
	Kills = "KILLS",
	Elites = "ELITES",
	Headshots = "HEADSHOTS",
	Revives = "REVIVES",
	Boards = "BOARDS",
	Nights = "NIGHTS",
	Waves = "WAVES",
	Contracts = "CONTRACTS",
	Objectives = "OBJECTIVES",
	MissionComplete = "MISSION",
	Escape = "ESCAPED",
	Beacon = "BEACON DOWN",
	Finished = "COMPLETION",
	Challenges = "CHALLENGES",
	Bonus = "FIRST MATCH",
	Other = "OTHER",
}
local COUNTED = { Kills = true, Elites = true, Headshots = true, Revives = true, Boards = true, Nights = true,
	Waves = true, Contracts = true, Objectives = true }
local KIND_WORD = { Operator = "OPERATOR", Card = "CALLING CARD", Camo = "CAMO", Beam = "BEAM" }

type Step = { at: number, dur: number, fn: (number, boolean) -> (), done: boolean? }

local state = {
	shown = false,
	payload = nil :: any,
	live = false, -- the payload came from this server's run end (REDEPLOY / CONTINUE go to MenuServer)
	beat = 1,
	beat2At = nil :: number?, -- os.clock() when beat 2 started
	steps = {} :: { Step },
	token = 0,
	sentSeen = false,
	checked = false,
	conn = nil :: RBXScriptConnection?,
	lastTick = 0,
}
local statics: { [string]: { [string]: any } } = {}

-- helpers --------------------------------------------------------------------------------------------------------

local function find(root: Instance?, path: string): any
	local node: Instance? = root
	for _, part in string.split(path, "/") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local function frameOf(ctx: any, variant: string): Instance?
	local root = ctx.gui:FindFirstChild(variant)
	local pages = root and root:FindFirstChild("Pages")
	return pages and pages:FindFirstChild(Page.Name)
end

local function setVisible(inst: Instance?, on: boolean)
	if inst and inst:IsA("GuiObject") then
		inst.Visible = on
	end
end

local function money(n: number?): string
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(math.abs(v))
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (if v < 0 then "-" else "") .. s
end

local function suffix(label: Instance?, word: string): string
	if not (label and label:IsA("TextLabel")) then
		return ""
	end
	local s = label:GetAttribute("_Suffix")
	if s == nil then
		s = if string.find(label.Text, word, 1, true) then " " .. word else ""
		label:SetAttribute("_Suffix", s)
	end
	return s :: string
end

local function isMatch(): boolean
	return workspace:GetAttribute("ServerRole") == "Match" or workspace:GetAttribute("MatchServer") == true
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function tick(ctx: any, quiet: boolean)
	if quiet then
		return
	end
	local now = os.clock()
	if now - state.lastTick > 0.07 then
		state.lastTick = now
		ctx.sound("Tick")
	end
end

-- Keep a chip just left of a right-aligned number ("BOOST" before "+4,180") so the two never overlap.
local function chipBefore(chip: Instance?, label: Instance?)
	if not (chip and chip:IsA("GuiObject") and label and label:IsA("TextLabel")) then
		return
	end
	if label.TextXAlignment ~= Enum.TextXAlignment.Right then
		return
	end
	local home = chip:GetAttribute("_HomeX")
	if type(home) ~= "number" then
		home = chip.Position.X.Offset
		chip:SetAttribute("_HomeX", home)
	end
	local scale = if label.Size.X.Offset > 0 then label.AbsoluteSize.X / label.Size.X.Offset else 1
	local textW = if scale > 0 then label.TextBounds.X / scale else 0
	local right = label.Position.X.Offset + label.Size.X.Offset - textW - 10
	local x = math.min(home :: number, right - chip.Size.X.Offset)
	chip.Position = UDim2.new(chip.Position.X.Scale, x, chip.Position.Y.Scale, chip.Position.Y.Offset)
end

-- How many template clones fit in a list along its layout direction.
local function capacity(ctx: any, list: Instance?): number
	if not (list and list:IsA("GuiObject")) then
		return 0
	end
	local path = list:GetAttribute("Template")
	local tpl: Instance? = ctx.gui:FindFirstChild("Templates")
	for _, part in string.split(if type(path) == "string" then path else "", "/") do
		tpl = tpl and tpl:FindFirstChild(part)
	end
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if not (tpl and tpl:IsA("GuiObject") and layout) then
		return 99
	end
	local pad = layout.Padding.Offset
	if layout.FillDirection == Enum.FillDirection.Horizontal then
		return math.max(1, math.floor((list.Size.X.Offset + pad) / math.max(1, tpl.Size.X.Offset + pad)))
	end
	return math.max(1, math.floor((list.Size.Y.Offset + pad) / math.max(1, tpl.Size.Y.Offset + pad)))
end

-- pure helpers (exposed for tests) -------------------------------------------------------------------------------

-- "OUTBREAK  ·  5 NIGHTS", "ENDLESS  ·  14 ROUNDS", "CAMPAIGN  ·  HOT DROP" (Endless counts rounds).
function Page.ModeLine(p: any): string
	local parts = { string.upper(tostring(p.Mode or "")) }
	if p.Mode == "Campaign" and MISSIONS[tonumber(p.Mission) or 0] then
		table.insert(parts, MISSIONS[tonumber(p.Mission) :: number])
	end
	for _, r in (if type(p.Rows) == "table" then p.Rows else {}) do
		if (r.Id == "Nights" or r.Id == "Waves") and (tonumber(r.Value) or 0) > 0 then
			local n = tonumber(r.Value) :: number
			local word = if r.Id == "Nights" then (if n == 1 then "NIGHT" else "NIGHTS") else (if p.Mode == "Endless" then (if n == 1 then "ROUND" else "ROUNDS") elseif n == 1 then "WAVE" else "WAVES")
			table.insert(parts, money(n) .. " " .. word)
		end
	end
	return table.concat(parts, DOT)
end

-- The XP rows that fit: the biggest first, the rest summed into OTHER, the first-match bonus kept.
function Page.XpRows(p: any, cap: number): { any }
	local rows = {}
	for _, r in (if type(p.Rows) == "table" then p.Rows else {}) do
		if (tonumber(r.Xp) or 0) > 0 then
			table.insert(rows, { Id = r.Id, Value = r.Value, Xp = tonumber(r.Xp) })
		end
	end
	local bonus = type(p.Xp) == "table" and tonumber(p.Xp.Bonus) or 0
	local reserve = if (bonus or 0) > 0 then 1 else 0
	table.sort(rows, function(a, b)
		return a.Xp > b.Xp
	end)
	local room = math.max(1, cap - reserve)
	if #rows > room then
		local other = 0
		for i = room, #rows do
			other += rows[i].Xp
		end
		for i = #rows, room, -1 do
			table.remove(rows, i)
		end
		table.insert(rows, { Id = "Other", Xp = other })
	end
	if reserve > 0 then
		table.insert(rows, { Id = "Bonus", Value = "x" .. tostring(P.FirstMatchBonus or 2), Xp = bonus })
	end
	return rows
end

function Page.UnlockArt(u: any): string?
	local k, id = u.Kind, u.Id
	if k == "Gun" then
		return "Gun/" .. tostring(id)
	elseif k == "Gear" then
		return "Gear/" .. tostring(id)
	elseif k == "Class" then
		return "Emblem/" .. tostring(id)
	elseif k == "Operator" then
		return "OperatorPortrait/" .. tostring(id)
	elseif k == "Card" or k == "Camo" or k == "Beam" then
		return k .. "/" .. tostring(id)
	elseif k == "Insignia" then
		return "Rank/" .. tostring(id)
	elseif k == "Scrip" then
		return "Kit/Scrip"
	elseif k == "Boost" then
		return "Pass/Boost"
	elseif k == "Token" then
		return "Pass/Token"
	elseif k == "Slot" then
		return "Tab/Loadout"
	end
	return nil
end

function Page.UnlockName(u: any): string
	local k, id = u.Kind, u.Id
	if k == "Gun" and GunStats then
		local ok, info = pcall(GunStats.Info, id)
		if ok and type(info) == "table" and info.Name then
			return string.upper(info.Name)
		end
	elseif k == "Gear" and Gear and Gear.Items and Gear.Items[id] then
		return string.upper(Gear.Items[id].Name or id)
	elseif k == "Scrip" then
		return money(u.Amount) .. " GEMS"
	elseif k == "Slot" then
		return "LOADOUT " .. (tostring(id):match("%d+") or "")
	elseif k == "Insignia" then
		return if id == "Star" then "STAR" else "INSIGNIA"
	elseif k == "Boost" then
		return "SQUAD BOOST"
	elseif k == "Token" then
		return "REVIVE TOKEN"
	elseif id then
		local item = C.Items[k .. "/" .. tostring(id)]
		if item and item.Name then
			return item.Name
		end
	end
	return string.upper(tostring(id or k))
end

-- Unlock cards that fit: Scrip lines merged into one card, the rest in order.
function Page.Unlocks(p: any, cap: number): { any }
	local out, scrip = {}, 0
	for _, u in (if type(p.Unlocks) == "table" then p.Unlocks else {}) do
		if u.Kind == "Scrip" then
			scrip += tonumber(u.Amount) or 0
		elseif Page.UnlockArt(u) then
			table.insert(out, u)
		end
	end
	if scrip > 0 then
		table.insert(out, { Kind = "Scrip", Amount = scrip })
	end
	while #out > cap do
		table.remove(out, if out[#out].Kind == "Scrip" and #out > 1 then #out - 1 else #out)
	end
	return out
end

-- The run's challenge rows that fit: finished ones first, then by progress.
function Page.Challenges(p: any, cap: number): { any }
	local rows = {}
	for _, c in (if type(p.Challenges) == "table" then p.Challenges else {}) do
		table.insert(rows, c)
	end
	local function frac(c: any): number
		return (tonumber(c.Progress) or 0) / math.max(1, tonumber(c.Goal) or 1)
	end
	table.sort(rows, function(a, b)
		if (a.Done == true) ~= (b.Done == true) then
			return a.Done == true
		end
		return frac(a) > frac(b)
	end)
	while #rows > cap do
		table.remove(rows)
	end
	return rows
end

-- Progress through levels as one number (level + fraction), and back.
local function levelPos(level: number, into: number, need: number): number
	return level + (if need > 0 then math.clamp(into / need, 0, 1) else 1)
end

-- Pass XP gained this run (the payload carries tiers and the XP into them).
function Page.PassGain(pass: any): number
	if type(pass) ~= "table" then
		return 0
	end
	local tx = P.Pass.TierXp
	local from = ((tonumber(pass.TierFrom) or 1) - 1) * tx + (tonumber(pass.IntoFrom) or 0)
	local to = ((tonumber(pass.TierTo) or 1) - 1) * tx + (tonumber(pass.IntoTo) or 0)
	return math.max(0, to - from)
end

-- beats ------------------------------------------------------------------------------------------------------------

local function stopDriver()
	if state.conn then
		state.conn:Disconnect()
		state.conn = nil
	end
end

-- Run every step whose time has come; `finish` runs them all to their end at once (the skip).
local function drive(finish: boolean)
	local start = state.beat2At
	if not start then
		return
	end
	local elapsed = if finish then math.huge else os.clock() - start
	local left = false
	for _, s in state.steps do
		if s.done then
			continue
		end
		if elapsed >= s.at then
			local t = if s.dur > 0 then math.min(1, (elapsed - s.at) / s.dur) else 1
			s.fn(t, finish)
			if t >= 1 then
				s.done = true
			else
				left = true
			end
		else
			left = true
		end
	end
	if not left then
		stopDriver()
	end
end

local function setBeat(ctx: any, beat: number)
	state.beat = beat
	local frame = ctx.frame(Page.Name)
	if not frame then
		return
	end
	local split = frame:FindFirstChild("ViewSquad") ~= nil -- Phone shows one beat at a time
	setVisible(frame:FindFirstChild("Beat1"), not split or beat == 1)
	setVisible(frame:FindFirstChild("Beat2"), not split or beat == 2)
	local s = statics[ctx.variant] or {}
	if s.ViewSquad then
		s.ViewSquad.Selected(beat == 1)
	end
	if s.ViewReport then
		s.ViewReport.Selected(beat == 2)
	end
end

local function startBeat2(ctx: any)
	if state.beat2At then
		return
	end
	state.beat2At = os.clock()
	setBeat(ctx, 2)
	stopDriver()
	state.conn = RunService.RenderStepped:Connect(function()
		drive(false)
	end)
end

local function skip(ctx: any)
	if not state.shown or not state.payload then
		return
	end
	if not state.beat2At then
		startBeat2(ctx)
	else
		drive(true)
	end
end

-- Reveal a list's clones one after another (they sit in a layout, so their children slide, not the clone).
local function reveal(ctx: any, clones: { GuiObject }, quiet: boolean, gap: number?)
	for i, c in clones do
		local function go()
			if not c.Parent then
				return
			end
			c.Visible = true
			if not quiet then
				local kids = {}
				for _, k in c:GetChildren() do
					if k:IsA("GuiObject") then
						table.insert(kids, k)
					end
				end
				ctx.ui.Stagger(kids, 0)
				tick(ctx, false)
			end
		end
		if quiet then
			go()
		else
			task.delay((i - 1) * (gap or 0.12), go)
		end
	end
end

-- Fill everything for this payload in the current variant and build the beat-2 steps.
local function build(ctx: any)
	local frame = ctx.frame(Page.Name)
	local p = state.payload
	if not (frame and p) then
		return
	end
	local ui = ctx.ui
	stopDriver()
	state.steps = {}

	-- header
	local banner = frame:FindFirstChild("Banner")
	if banner and p.Result then
		ui.SetArt(banner, "Aar/Banner/" .. tostring(p.Result))
	end
	ui.Text(frame:FindFirstChild("ModeLine"), Page.ModeLine(p))

	-- beat 1: squad plates and showcase
	local squad = if type(p.Squad) == "table" then p.Squad else {}
	local plates = ui.Fill(find(frame, "Beat1/Squad"), squad, function(c: GuiObject, m: any)
		ui.SetArt(c:FindFirstChild("Card"), "Card/" .. tostring(m.Card or "Default"))
		ui.SetArt(c:FindFirstChild("Emblem"), "Emblem/" .. tostring(m.Class or "Rifleman"))
		ui.Text(c:FindFirstChild("Name"), string.upper(tostring(m.Name or "")))
		ui.Text(c:FindFirstChild("Kills"), money(m.Kills))
		ui.Text(c:FindFirstChild("Revives"), money(m.Revives))
		ui.Text(c:FindFirstChild("Elites"), money(m.Elites))
		setVisible(c:FindFirstChild("Mvp"), m.Mvp == true)
		c.Active = true
		c.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) and m.UserId then
				ctx.sound("Click")
				ctx.open("Record", { UserId = m.UserId })
			end
		end)
		c.Visible = false
	end)
	local showcase = ui.Fill(find(frame, "Beat1/Showcase"), squad, function(c: GuiObject, m: any)
		local op = tostring(m.Operator or "Woodland")
		local itemId = "Operator/" .. op
		local item = C.Items[itemId]
		ui.SetArt(c:FindFirstChild("Portrait"), "OperatorPortrait/" .. op)
		ui.Text(c:FindFirstChild("ItemName"), item and item.Name or string.upper(op))
		ui.Text(c:FindFirstChild("ItemKind"), KIND_WORD.Operator)
		local view = c:FindFirstChild("ViewItem")
		if view and view:IsA("GuiButton") then
			local b = ui.Button(view, function()
				if not state.sentSeen then
					state.sentSeen = true
					task.spawn(ctx.store, "AarSeen", {})
				end
				ctx.go("Store", { Section = "Operators", Item = itemId })
			end)
			local none = item == nil or item.Source.Kind == "Default"
			b.Disabled(none)
			-- Phone bakes "VIEW ITEM ›" into ViewWords over a clear button: hide both for an item the store never shows
			local words = c:FindFirstChild("ViewWords")
			if words then
				setVisible(words, not none)
				setVisible(view, not none)
			end
		end
		c.Visible = false
	end)
	reveal(ctx, plates, false, 0.1)
	reveal(ctx, showcase, false, 0.1)

	-- beat 2: start values
	local xp = if type(p.Xp) == "table" then p.Xp else {}
	local lvFrom, lvTo = tonumber(xp.LevelFrom) or 1, tonumber(xp.LevelTo) or 1
	local posFrom = levelPos(lvFrom, tonumber(xp.IntoFrom) or 0, tonumber(xp.NeedFrom) or 1)
	local posTo = levelPos(lvTo, tonumber(xp.IntoTo) or 0, tonumber(xp.NeedTo) or 1)
	local account = find(frame, "Beat2/Account")
	local rank = find(account, "Rank")
	local levelLabel = find(account, "Level")
	local gain = find(account, "XpGain")
	local xpText = find(account, "XpText")
	local xpBar = find(account, "XpBar")
	local gainUnit = suffix(gain, "XP")
	local total = tonumber(xp.Total) or 0
	local levelUp = find(frame, "Beat2/LevelUp")
	setVisible(levelUp, false)

	local function showLevel(pos: number, final: boolean)
		local lvl = math.min(math.floor(pos), lvTo)
		local frac = pos - math.floor(pos)
		if final then
			lvl, frac = lvTo, if (tonumber(xp.NeedTo) or 0) > 0 then (tonumber(xp.IntoTo) or 0) / xp.NeedTo else 1
		end
		ui.Text(levelLabel, lvl)
		if rank then
			ui.SetArt(rank, "Rank/" .. tostring(P.Rank(lvl)))
		end
		ui.Bar(xpBar, frac)
		local need = if lvl == lvFrom then tonumber(xp.NeedFrom) or 0 elseif lvl == lvTo then tonumber(xp.NeedTo) or 0 else P.XpToNext(lvl)
		if final then
			ui.Text(xpText, money(xp.IntoTo) .. " / " .. money(xp.NeedTo))
		else
			ui.Text(xpText, money(frac * need) .. " / " .. money(need))
		end
	end
	showLevel(posFrom, false)
	ui.Text(gain, "+0" .. gainUnit)

	local rowsList = find(account, "Rows")
	local rows = ui.Fill(rowsList, Page.XpRows(p, capacity(ctx, rowsList)), function(c: GuiObject, r: any)
		ui.Text(c:FindFirstChild("Label"), ROW_LABEL[r.Id] or string.upper(tostring(r.Id)))
		local v = if type(r.Value) == "string" then r.Value elseif COUNTED[r.Id] then money(r.Value) else ""
		ui.Text(c:FindFirstChild("Value"), v)
		ui.Text(c:FindFirstChild("Xp"), "+" .. money(r.Xp))
		c.Visible = false
	end)

	local scrip = if type(p.Scrip) == "table" then p.Scrip else {}
	local scripLabel = find(account, "Scrip")
	ui.Text(scripLabel, "+0")
	local double = find(account, "Double")
	setVisible(double, false)
	ui.Text(find(double, "Amount"), "+" .. money(scrip.WithDouble))

	-- weapon
	local weapon = find(frame, "Beat2/Weapon")
	local gun = if type(p.Gun) == "table" and p.Gun.Key then p.Gun else nil
	for _, n in { "Gun", "GunName", "GunLevel", "GunBar", "GunXp" } do
		setVisible(find(weapon, n), gun ~= nil)
	end
	local gunFrom, gunTo = 0, 0
	if gun then
		ui.SetArt(find(weapon, "Gun"), "Gun/" .. tostring(gun.Key))
		ui.Text(find(weapon, "GunName"), Page.UnlockName({ Kind = "Gun", Id = gun.Key }))
		local lf, inf, nf = P.WeaponFromXp(tonumber(gun.XpFrom) or 0)
		local lt, it, nt = P.WeaponFromXp(tonumber(gun.XpTo) or 0)
		gunFrom, gunTo = levelPos(lf, inf, nf), levelPos(lt, it, nt)
		ui.Text(find(weapon, "GunLevel"), if lt > lf then "LV " .. lf .. ARROW .. lt else "LV " .. lt)
		ui.Text(find(weapon, "GunXp"), "+0" .. suffix(find(weapon, "GunXp"), "XP"))
		ui.Bar(find(weapon, "GunBar"), gunFrom - math.floor(gunFrom))
	end
	local unlockList = find(weapon, "Unlocks")
	local unlockItems = Page.Unlocks(p, capacity(ctx, unlockList))
	setVisible(find(weapon, "UnlocksWord"), #unlockItems > 0)
	setVisible(unlockList, #unlockItems > 0)
	local cards = ui.Fill(unlockList, unlockItems, function(c: GuiObject, u: any)
		ui.SetArt(c:FindFirstChild("Art"), Page.UnlockArt(u))
		ui.Text(c:FindFirstChild("Name"), Page.UnlockName(u))
		c.Visible = false
	end)

	-- pass
	local passPanel = find(frame, "Beat2/PassPanel")
	local pass = if type(p.Pass) == "table" then p.Pass else {}
	local tFrom, tTo = tonumber(pass.TierFrom) or 1, tonumber(pass.TierTo) or 1
	local passFrom = levelPos(tFrom, tonumber(pass.IntoFrom) or 0, tonumber(pass.NeedFrom) or P.Pass.TierXp)
	local passTo = levelPos(tTo, tonumber(pass.IntoTo) or 0, tonumber(pass.NeedTo) or 0)
	local passGain = Page.PassGain(pass)
	local passXpLabel = find(passPanel, "PassXp")
	local passUnit = suffix(passXpLabel, "XP")
	ui.Text(find(passPanel, "PassTier"), if tTo > tFrom then tFrom .. ARROW .. tTo else tostring(tTo))
	ui.Text(passXpLabel, "+0" .. passUnit)
	setVisible(find(passPanel, "Boost"), pass.Boost == true)
	ui.Text(passXpLabel, "+" .. money(passGain) .. passUnit)
	chipBefore(find(passPanel, "Boost"), passXpLabel)
	ui.Bar(find(passPanel, "PassBar"), passFrom - math.floor(passFrom))
	local chList = find(passPanel, "Challenges")
	local chRows = ui.Fill(chList, Page.Challenges(p, capacity(ctx, chList)), function(c: GuiObject, ch: any)
		local goal = math.max(1, tonumber(ch.Goal) or 1)
		local prog = if ch.Done then goal else math.clamp(tonumber(ch.Progress) or 0, 0, goal)
		ui.Text(c:FindFirstChild("Label"), ch.Label or "")
		ui.Text(c:FindFirstChild("Progress"), money(prog) .. "/" .. money(goal))
		ui.Bar(c:FindFirstChild("Bar"), prog / goal)
		ui.Text(c:FindFirstChild("Xp"), "+" .. money(ch.Xp) .. " XP")
		setVisible(c:FindFirstChild("Progress"), not ch.Done)
		setVisible(c:FindFirstChild("Xp"), ch.Done == true)
		setVisible(c:FindFirstChild("Check"), ch.Done == true)
		if ch.Done then
			local plate = c:FindFirstChild("Plate")
			local key = plate and plate:GetAttribute("UiArt")
			if type(key) == "string" and ui.Art(key .. "Done") then
				ui.SetArt(plate, key .. "Done")
			end
			local fill = find(c, "Bar/Clip/Fill")
			local fkey = fill and fill:GetAttribute("UiArt")
			if type(fkey) == "string" then
				local dkey = fkey:gsub("_Fill$", "Done")
				if ui.Art(dkey) then
					ui.SetArt(fill, dkey)
				end
			end
		end
		c.Visible = false
	end)

	-- beat 2 steps (seconds after beat 2 starts) ----------------------------------------------------------------
	local steps = state.steps
	table.insert(steps, { at = 0, dur = 1.6, fn = function(t: number, quiet: boolean)
		local e = 1 - (1 - t) ^ 2
		showLevel(lerp(posFrom, posTo, e), t >= 1)
		ui.Text(gain, "+" .. money(total * e) .. gainUnit)
		if t < 1 then
			tick(ctx, quiet)
		end
	end })
	table.insert(steps, { at = 0.15, dur = 0, fn = function(_t: number, quiet: boolean)
		reveal(ctx, rows, quiet, 0.08)
	end })
	table.insert(steps, { at = 1.6, dur = 0, fn = function(_t: number, _quiet: boolean)
		if lvTo > lvFrom and levelUp then
			ui.Text(levelUp:FindFirstChild("Number"), lvTo)
			levelUp.Visible = true
			local punch = levelUp:FindFirstChild("Punch") :: UIScale?
			if not punch then
				local s = Instance.new("UIScale")
				s.Name = "Punch"
				s.Parent = levelUp
				punch = s
			end
			if punch then
				punch.Scale = 1.35
				ui.Tween(punch, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			ctx.sound("LevelUp")
		end
	end })
	if gun then
		table.insert(steps, { at = 0.4, dur = 1.0, fn = function(t: number, quiet: boolean)
			local pos = if t >= 1 then gunTo else lerp(gunFrom, gunTo, 1 - (1 - t) ^ 2)
			local frac = if t >= 1 and gunTo - math.floor(gunTo) == 0 and gunTo > gunFrom then 1 else pos - math.floor(pos)
			ui.Bar(find(weapon, "GunBar"), frac)
			local gx = (tonumber(gun.XpTo) or 0) - (tonumber(gun.XpFrom) or 0)
			ui.Text(find(weapon, "GunXp"), "+" .. money(gx * t) .. suffix(find(weapon, "GunXp"), "XP"))
			if t < 1 then
				tick(ctx, quiet)
			end
		end })
	end
	table.insert(steps, { at = 1.0, dur = 0, fn = function(_t: number, quiet: boolean)
		reveal(ctx, cards, quiet, 0.15)
		if not quiet and #cards > 0 then
			ctx.sound("Stamp")
		end
	end })
	table.insert(steps, { at = 0.6, dur = 1.0, fn = function(t: number, quiet: boolean)
		local e = 1 - (1 - t) ^ 2
		local pos = lerp(passFrom, passTo, e)
		local frac = pos - math.floor(pos)
		if t >= 1 then
			frac = if (tonumber(pass.NeedTo) or 0) > 0 then (tonumber(pass.IntoTo) or 0) / pass.NeedTo else 1
		end
		ui.Bar(find(passPanel, "PassBar"), frac)
		ui.Text(passXpLabel, "+" .. money(passGain * e) .. passUnit)
		if t < 1 then
			tick(ctx, quiet)
		else
			chipBefore(find(passPanel, "Boost"), passXpLabel)
		end
	end })
	table.insert(steps, { at = 1.3, dur = 0, fn = function(_t: number, quiet: boolean)
		reveal(ctx, chRows, quiet, 0.1)
	end })
	table.insert(steps, { at = 1.8, dur = 0.8, fn = function(t: number, quiet: boolean)
		ui.Text(scripLabel, "+" .. money((tonumber(scrip.Total) or 0) * t))
		if t < 1 then
			tick(ctx, quiet)
		else
			setVisible(double, scrip.WithDouble ~= nil and (tonumber(scrip.WithDouble) or 0) > 0)
		end
	end })
end

local function buttons(ctx: any)
	local s = statics[ctx.variant] or {}
	local canRedeploy = state.live and isMatch()
	if s.Redeploy then
		s.Redeploy.Disabled(not canRedeploy)
		s.Redeploy.Selected(false)
	end
	if s.Continue then
		s.Continue.Disabled(false)
	end
	ctx.select(if canRedeploy then ctx.el(Page.Name, "Redeploy") else ctx.el(Page.Name, "Continue"))
end

local function onRedeploy(ctx: any)
	if not (state.live and isMatch()) then
		return
	end
	ctx.menu("Redeploy")
	local s = statics[ctx.variant] or {}
	if s.Redeploy then
		s.Redeploy.Selected(true) -- waiting for the squad (a member's REDEPLOY marks them READY)
	end
end

local function onContinue(ctx: any)
	if not state.sentSeen then
		state.sentSeen = true
		task.spawn(ctx.store, "AarSeen", {})
	end
	if state.live and isMatch() then
		local s = statics[ctx.variant] or {}
		if s.Continue then
			s.Continue.Disabled(true)
		end
		if s.Redeploy then
			s.Redeploy.Disabled(true)
		end
		ctx.menu("Continue")
	else
		ctx.go("Home")
	end
end

local function wireStatic(ctx: any, variant: string)
	local frame = frameOf(ctx, variant)
	if not frame then
		return
	end
	local s = {}
	local function wire(name: string, fn: () -> (), opts: any?)
		local b = frame:FindFirstChild(name)
		if b and b:IsA("GuiButton") then
			s[name] = ctx.ui.Button(b, fn, opts)
		end
	end
	wire("Redeploy", function()
		onRedeploy(ctx)
	end, { Sound = "Deploy" })
	wire("Continue", function()
		onContinue(ctx)
	end)
	wire("ViewSquad", function()
		setBeat(ctx, 1)
	end)
	wire("ViewReport", function()
		if state.beat2At then
			setBeat(ctx, 2)
		else
			startBeat2(ctx)
		end
	end)
	local zone = frame:FindFirstChild("SkipZone")
	if zone and zone:IsA("GuiObject") then
		zone.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) and ctx.variant == variant then
				skip(ctx)
			end
		end)
	end
	statics[variant] = s
end

local function open(ctx: any, payload: any, live: boolean)
	if type(payload) ~= "table" then
		return
	end
	if isMatch() and not ctx.active then
		ctx.setActive(true)
	end
	-- the report is full screen: the top bar would sit on its SQUAD / REPORT buttons
	ctx.showChrome(false)
	ctx.go("Aar", { Payload = payload, Live = live })
end

-- Page API -------------------------------------------------------------------------------------------------------

function Page.Init(ctx: any)
	for _, v in VARIANTS do
		wireStatic(ctx, v)
	end
	-- live AAR at run end (also in a Match server, where the menu is otherwise off)
	ctx.on("Aar", function(payload: any)
		open(ctx, payload, true)
	end)
	-- an AAR not yet seen (the run ended in another server, or the player left before CONTINUE)
	local function pending()
		if state.checked or isMatch() or not ctx.active or ctx.attr("AarPending") ~= true then
			return
		end
		state.checked = true
		local res = ctx.store("Aar", {})
		if res.Ok and type(res.Payload) == "table" and not state.shown then
			open(ctx, res.Payload, false)
		end
	end
	ctx.on("Active", function(on: boolean)
		if on then
			pending()
		end
	end)
	ctx.onAttr("AarPending", function()
		task.defer(pending)
	end)
	task.defer(pending)
	-- REDEPLOY started the next run: the match server drops the player back into their body
	ctx.onAttr("InMatch", function(v: any)
		if v and state.shown and state.live and isMatch() and ctx.current == Page.Name then
			ctx.setActive(false)
		end
	end)
end

function Page.Layout(ctx: any)
	if state.shown and state.payload then
		local wasBeat2 = state.beat2At ~= nil
		build(ctx)
		buttons(ctx)
		if wasBeat2 then
			state.beat2At = os.clock()
			drive(true)
			setBeat(ctx, 2)
		else
			setBeat(ctx, 1)
		end
	end
end

function Page.Show(ctx: any, args: any)
	local payload = type(args) == "table" and args.Payload or nil
	local live = type(args) == "table" and args.Live == true
	if type(args) == "table" and args.Result then
		payload = args -- a bare payload also works
	end
	if payload and state.shown and state.payload and payload.At ~= nil and payload.At == state.payload.At then
		return -- the same AAR again (two listeners): keep the running beats
	end
	local instant = false
	if not payload then
		if state.shown and state.payload then
			return
		end
		if state.payload then
			-- back from STORE (VIEW ITEM) or RECORD: the same report, already played
			payload, live, instant = state.payload, state.live, true
		else
			local res = ctx.store("Aar", {})
			payload = res.Ok and res.Payload or nil
			live = false
		end
	end
	if type(payload) ~= "table" then
		ctx.go("Home")
		return
	end
	state.token += 1
	state.shown = true
	state.payload = payload
	state.live = live
	if not instant then
		state.sentSeen = false
	end
	state.beat2At = nil
	local frame = ctx.frame(Page.Name)
	if frame and frame:IsA("GuiObject") then
		frame.ZIndex = 5
	end
	ctx.showChrome(false)
	build(ctx)
	setBeat(ctx, 1)
	buttons(ctx)
	if instant then
		startBeat2(ctx)
		drive(true)
		return
	end
	local token = state.token
	local split = frame ~= nil and frame:FindFirstChild("ViewSquad") ~= nil
	task.delay(if split then BEAT1_PHONE else BEAT1_WIDE, function()
		if state.shown and state.token == token then
			startBeat2(ctx)
		end
	end)
end

function Page.Hide(ctx: any)
	state.shown = false
	state.token += 1
	stopDriver()
	if not isMatch() then
		ctx.showChrome(true)
	end
end

return Page
