-- Play page (FRONT-A, 4 Nov 2026): the mode cards (locked ones show their rule), the picked mode's detail with chips,
-- the campaign's chapter tabs and the picked chapter's mission tiles, the squad slots (WIDE), FILL, DEPLOY and, for a
-- member who is not the leader, READY. During the countdown the leader's DEPLOY turns into CANCEL.
-- One DEPLOY for the campaign too (5 Nov 2026): every campaign deploy now gets a fresh server, so QUICK JOIN and
-- SQUAD DEPLOY did the same thing; SQUAD DEPLOY stays hidden (its handler is kept, harmless).
-- Chapters (4 Nov 2026): Detail/Chapters holds one ChapterTab per GameConfig.War.Chapters entry (Common.Chapters);
-- chapters that are not built yet show COMING SOON with a lock. Both deploys send the picked Chapter.
-- Missions are not picked (5 Nov 2026): a deploy from the lobby always starts the chapter from its first mission, so
-- the tiles only show what the chapter holds, in order.
-- Elements: notes/SCREENS-A.md (Play table). Server protocol: MenuServer header.

local Common = require(script.Parent:WaitForChild("TopBar"):WaitForChild("Common"))

local Page = { Name = "Play", Tab = "Play", Camera = "Home" }

local ctxRef = nil
local wired = {}
local shown = false
local mode = nil -- picked mode id
local chapter = 1 -- picked campaign chapter (a Common.Chapters index)
local modeCtls = {}
local chapterCtls = {}
local chapterTabs = {} -- [n] = the tab's Select button

-- Tab text colours: the picked tab's chip is solid amber, so its words go dark ink there.
local TAB_INK = Color3.fromRGB(9, 10, 12)
local TAB_AMBER = Color3.fromRGB(255, 176, 60)
local TAB_TEXT = Color3.fromRGB(236, 232, 222)

local function paintTab(select, picked)
	local num, name = select:FindFirstChild("Num"), select:FindFirstChild("Name")
	if num and num:IsA("TextLabel") then
		num.TextColor3 = if picked then TAB_INK else TAB_AMBER
	end
	if name and name:IsA("TextLabel") then
		name.TextColor3 = if picked then TAB_INK else TAB_TEXT
	end
end

-- The first chapter this player can play (chapter 1 today).
local function firstChapter(player)
	for n in Common.Chapters do
		if not Common.ChapterLocked(player, n) then
			return n
		end
	end
	return 1
end

local function wire(ctx)
	local E = {}
	for _, path in {
		"Modes", "Detail", "Detail/Title", "Detail/Line", "Detail/Chips", "Detail/Chapters", "Detail/MissionsHeader", "Detail/Tiles",
		"Detail/Map", "Detail/MapEdge", "Detail/Divider", "Detail/SquadHeader", "Detail/Count", "Detail/Squad",
		"Detail/Fill", "Detail/SquadDeploy", "Detail/Deploy", "Detail/Deploy/Label", "Detail/Ready",
	} do
		E[path] = ctx.el("Play", path)
	end
	local ui = ctx.ui
	local deploy = E["Detail/Deploy"]
	if deploy then
		-- DEPLOY and CANCEL share one image: the art keys are swapped and the button rewired when the state flips.
		E.DeployArt = {
			Idle = deploy:GetAttribute("ArtIdle"), Hover = deploy:GetAttribute("ArtHover"),
			Down = deploy:GetAttribute("ArtDown"), Disabled = deploy:GetAttribute("ArtDisabled"),
			Cancel = deploy:GetAttribute("ArtCancel"),
		}
	end
	-- FILL is hidden until fill matchmaking exists (Party: "FILL matchmaking is phase 1.5"); a toggle that did
	-- nothing confused players. Flip FILL_READY when it ships.
	local FILL_READY = false
	if E["Detail/Fill"] and not FILL_READY then
		(E["Detail/Fill"] :: GuiObject).Visible = false
	elseif E["Detail/Fill"] then
		E.FillCtl = ui.Button(E["Detail/Fill"], function()
			local s = ctx.partyState
			ctx.party("Fill", not (type(s) == "table" and s.Fill == true))
		end)
	end
	if E["Detail/SquadDeploy"] then
		E.SquadCtl = ui.Button(E["Detail/SquadDeploy"], function()
			if mode ~= "Campaign" or not Common.IsLeader(ctx) or Common.Squad(ctx).State ~= "Idle"
				or Common.ChapterLocked(ctx.player, chapter)
			then
				return
			end
			ctx.player:SetAttribute("MenuLastMode", mode)
			ctx.menu("Deploy", { Mode = "Campaign", Join = "Squad", Chapter = chapter })
		end, { Sound = "Deploy" })
	end
	if E["Detail/Ready"] then
		E.ReadyCtl = ui.Button(E["Detail/Ready"], function()
			ctx.menu("Ready", Common.MyStatus(ctx) ~= "READY")
		end, { Sound = "Beep" })
	end
	return E
end

local function els(ctx)
	local v = ctx.variant
	if not wired[v] then
		wired[v] = wire(ctx)
	end
	return wired[v]
end

local refreshDeploy

-- DEPLOY's art set: "Deploy" or "Cancel". Rewires the button so its hover/down states follow.
local function deployLook(E, cancel)
	local deploy = E["Detail/Deploy"]
	if not deploy or not E.DeployArt then
		return
	end
	local want = if cancel and E.DeployArt.Cancel then "Cancel" else "Deploy"
	if E.DeployLook == want and E.DeployCtl then
		return
	end
	E.DeployLook = want
	if E.DeployCtl then
		E.DeployCtl.Destroy()
	end
	local a = E.DeployArt
	if want == "Cancel" then
		deploy:SetAttribute("ArtIdle", a.Cancel)
		deploy:SetAttribute("ArtHover", a.Cancel)
		deploy:SetAttribute("ArtDown", a.Cancel)
	else
		deploy:SetAttribute("ArtIdle", a.Idle)
		deploy:SetAttribute("ArtHover", a.Hover)
		deploy:SetAttribute("ArtDown", a.Down)
	end
	local ctx = ctxRef
	E.DeployCtl = ctx.ui.Button(deploy, function()
		local squad = Common.Squad(ctx)
		if not Common.IsLeader(ctx) then
			return
		end
		if squad.State == "Countdown" then
			ctx.menu("Cancel")
			return
		end
		if squad.State ~= "Idle" or not mode or Common.Locked(ctx.player, mode)
			or (mode == "Campaign" and Common.ChapterLocked(ctx.player, chapter))
		then
			return
		end
		ctx.player:SetAttribute("MenuLastMode", mode)
		local campaign = mode == "Campaign"
		ctx.menu("Deploy", { Mode = mode, Join = if campaign then "Quick" else nil, Chapter = if campaign then chapter else nil })
	end, { Sound = if want == "Cancel" then "Back" else "Deploy" })
end

local function refreshModes()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	table.clear(modeCtls)
	ui.Fill(E.Modes, Common.Modes(), function(card, id)
		local info = Common.Info(id)
		local art = card:FindFirstChild("Art")
		if art and ui.Art(info.Art) then
			ui.SetArt(art, info.Art)
		end
		ui.Text(card:FindFirstChild("Name"), info.Name)
		ui.Text(card:FindFirstChild("Line"), info.Line)
		local locked, rule = Common.Locked(ctx.player, id)
		local lock = card:FindFirstChild("Lock")
		if lock then
			lock.Visible = locked
			ui.Text(lock:FindFirstChild("Rule"), rule or "")
		end
		local select = card:FindFirstChild("Select")
		if select then
			local ctl = ui.Button(select, function()
				if mode ~= id then
					mode = id
					chapter = firstChapter(ctx.player)
					Page.Refresh()
				end
			end, { Sound = "Tick" })
			ctl.Disabled(locked)
			ctl.Selected(id == mode)
			modeCtls[id] = ctl
		end
	end)
end

-- The picked chapter's missions, in play order (refilled when the chapter changes). Display only: a run always
-- starts at the first one, so the tiles are not buttons and show no locks.
local function refreshTiles()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local campaign = mode == "Campaign"
	local missions = if campaign then Common.MissionsOf(chapter) else {}
	if E["Detail/Tiles"] then
		ui.Fill(E["Detail/Tiles"], missions, function(tile, m, n)
			local art = tile:FindFirstChild("Art")
			if art and ui.Art("Mission/" .. m.Id) then
				ui.SetArt(art, "Mission/" .. m.Id)
			end
			ui.Text(tile:FindFirstChild("Name"), n .. "  " .. m.Name)
			local lock = tile:FindFirstChild("Lock")
			if lock then
				lock.Visible = false
			end
			local select = tile:FindFirstChild("Select")
			if select and select:IsA("GuiButton") then
				-- keep the frame art, drop the button: no hover, no click, skipped by gamepad selection
				select.Active = false
				select.Selectable = false
				select.Interactable = false
			end
		end)
	end
end

-- One tab per chapter: CHAPTER n over its name, or COMING SOON with a lock while it is not built.
local function refreshChapters()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local row = E["Detail/Chapters"]
	table.clear(chapterCtls)
	table.clear(chapterTabs)
	if not row then
		return
	end
	local campaign = mode == "Campaign"
	row.Visible = campaign
	ui.Fill(row, if campaign then Common.Chapters else {}, function(tab, c, n)
		local select = tab:FindFirstChild("Select")
		if not select then
			return
		end
		local locked, rule = Common.ChapterLocked(ctx.player, n)
		ui.Text(select:FindFirstChild("Num"), "CHAPTER " .. n)
		ui.Text(select:FindFirstChild("Name"), if locked then (rule or "COMING SOON") else (c.Name or ""))
		for _, k in { "Num", "Name" } do
			local l = select:FindFirstChild(k)
			if l and l:IsA("TextLabel") then
				l.TextTransparency = if locked then 0.45 else 0
			end
		end
		local lock = select:FindFirstChild("Lock")
		if lock then
			lock.Visible = locked
		end
		local ctl = ui.Button(select, function()
			if chapter == n then
				return
			end
			chapter = n
			for i, other in chapterCtls do
				other.Selected(i == n)
				if chapterTabs[i] then
					paintTab(chapterTabs[i], i == n)
				end
			end
			local info = Common.Info(mode)
			ui.Text(E["Detail/Line"], (c.Name and c.Line) and (c.Name .. ". " .. c.Line) or info.Line)
			refreshTiles()
			refreshDeploy()
		end, { Sound = "Tick" })
		ctl.Disabled(locked)
		ctl.Selected(n == chapter)
		paintTab(select, n == chapter)
		chapterCtls[n] = ctl
		chapterTabs[n] = select
	end)
end

local function refreshDetail()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local info = Common.Info(mode)
	local campaign = mode == "Campaign"
	local c = if campaign then Common.Chapters[chapter] else nil
	ui.Text(E["Detail/Title"], info.Name)
	ui.Text(E["Detail/Line"], if c and c.Name and c.Line then c.Name .. ". " .. c.Line else info.Line)
	ui.Fill(E["Detail/Chips"], info.Chips, function(chip, text)
		ui.Text(chip:FindFirstChild("Label"), text)
	end)
	for _, k in { "Detail/MissionsHeader", "Detail/Tiles" } do
		if E[k] then
			E[k].Visible = campaign
		end
	end
	refreshChapters()
	refreshTiles()
end

local function refreshSquad()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local squad = Common.Squad(ctx)
	ui.Text(E["Detail/Count"], #squad.Members .. "/4")
	if E["Detail/Squad"] then
		local slots = {}
		for i = 1, 4 do
			slots[i] = squad.Members[i] or false
		end
		ui.Fill(E["Detail/Squad"], slots, function(slot, m)
			Common.FillSlot(ctx, slot, m or nil, squad.Leader, function()
				ctx.go("Party")
			end)
		end)
	end
	if E.FillCtl then
		local s = ctx.partyState
		E.FillCtl.Selected(type(s) == "table" and s.Fill == true)
		E.FillCtl.Disabled(not Common.IsLeader(ctx))
	end
end

refreshDeploy = function()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local squad = Common.Squad(ctx)
	local leader = Common.IsLeader(ctx)
	local countdown = squad.State == "Countdown"
	local campaign = mode == "Campaign"
	local deploy = E["Detail/Deploy"]
	if deploy then
		deploy.Visible = leader
		deployLook(E, leader and countdown)
		local label
		if countdown then
			label = "CANCEL" .. (if squad.Count then "  " .. tostring(squad.Count) else "")
		elseif squad.State == "Deploying" then
			label = "DEPLOYING"
		else
			label = "DEPLOY"
		end
		ui.Text(E["Detail/Deploy/Label"], label)
		if E.DeployCtl then
			E.DeployCtl.Disabled(not countdown and (squad.State ~= "Idle" or Common.Locked(ctx.player, mode)
				or (campaign and Common.ChapterLocked(ctx.player, chapter))))
		end
	end
	if E["Detail/SquadDeploy"] then
		E["Detail/SquadDeploy"].Visible = false
		if E.SquadCtl then
			E.SquadCtl.Disabled(squad.State ~= "Idle" or Common.ChapterLocked(ctx.player, chapter))
		end
	end
	if E["Detail/Ready"] then
		E["Detail/Ready"].Visible = not leader
		if E.ReadyCtl then
			E.ReadyCtl.Selected(Common.MyStatus(ctx) == "READY")
		end
	end
end

function Page.Refresh()
	if not ctxRef then
		return
	end
	refreshModes()
	refreshDetail()
	refreshSquad()
	refreshDeploy()
end

function Page.Init(ctx)
	ctxRef = ctx
	els(ctx)
	ctx.on("Party", function(s)
		if not shown then
			return
		end
		-- a member follows the leader's pick
		if type(s) == "table" and s.Leader ~= ctx.player.UserId and type(s.Mode) == "string"
			and (s.Mode ~= mode or (tonumber(s.Chapter) or 1) ~= chapter) and table.find(Common.Modes(), s.Mode)
		then
			mode = s.Mode
			chapter = if Common.Chapters[tonumber(s.Chapter) or 1] then tonumber(s.Chapter) or 1 else 1
			Page.Refresh()
			return
		end
		refreshSquad()
		refreshDeploy()
	end)
	for _, name in { "Escaped", "Stats" } do
		ctx.onAttr(name, function()
			if shown then
				Page.Refresh()
			end
		end)
	end
end

function Page.Layout(ctx)
	ctxRef = ctx
	els(ctx)
	if shown then
		Page.Refresh()
	end
end

-- args.Mode picks a card (HOME's play card opens PLAY on its mode).
function Page.Show(ctx, args)
	ctxRef = ctx
	shown = true
	local want = type(args) == "table" and args.Mode or nil
	if want and table.find(Common.Modes(), want) and not Common.Locked(ctx.player, want) then
		mode = want
		chapter = firstChapter(ctx.player)
	elseif not mode or Common.Locked(ctx.player, mode) then
		mode = Common.Recommended(ctx.player)
	end
	Page.Refresh()
	local E = els(ctx)
	local list = {}
	for _, c in (E.Modes and E.Modes:GetChildren()) or {} do
		if c:IsA("GuiObject") and c:GetAttribute("_Clone") then
			table.insert(list, c)
		end
	end
	ctx.ui.Stagger(list)
	ctx.select(if Common.IsLeader(ctx) then E["Detail/Deploy"] else E["Detail/Ready"])
end

function Page.Hide()
	shown = false
end

return Page
