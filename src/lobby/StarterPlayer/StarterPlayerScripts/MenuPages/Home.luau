-- Home page (5 Nov 2026 kid reskin): the one landing page. PLAY is merged in: the mode cards (Common.Modes, the
-- picked one lit, locked ones show their rule), the picked mode's chips, DEPLOY (CANCEL n during the countdown,
-- DEPLOYING after) or READY for a squad mate, a one-line Notice beside it, and the squad as four slots side by side
-- (avatar face, leader star, ready tick; + opens the Party overlay) with LEAVE.
-- The NIGHT PASS, FEATURED and DAILY cards and the backdrop arrows were cut (owner: too many things on the menu);
-- PASS and STORE keep their tabs, the backdrop is in Settings.
-- Squads: the leader's pick goes to the server ("Pick") so every mate's HOME shows it, and READY means ready for that
-- pick. A DEPLOY while a mate is not ready shows WAITING ON NAME; MULTIPLAYER (Duel) answers "TooMany" for a squad of
-- 3 or more. Elements: horror-shooter/menu/art/screens/Home.py. Server protocol: MenuServer header.

local Common = require(script.Parent:WaitForChild("TopBar"):WaitForChild("Common"))

local Page = { Name = "Home", Tab = "Home", Camera = "Home" }

local ctxRef = nil
local wired = {}
local shown = false
local mode = nil -- picked mode id
local modeCtls = {}

local function wire(ctx)
	local ui = ctx.ui
	local E = {}
	for _, path in {
		"Modes", "Chips", "Deploy", "Deploy/Label", "DeployGlow", "Ready", "Notice", "Notice/Text", "Squad",
		"Squad/Slots", "Squad/Leave",
	} do
		E[path] = ctx.el("Home", path)
	end
	local deploy = E.Deploy
	if deploy then
		-- DEPLOY and CANCEL share one image: the art keys are swapped and the button rewired when the state flips.
		E.DeployArt = {
			Idle = deploy:GetAttribute("ArtIdle"), Hover = deploy:GetAttribute("ArtHover"),
			Down = deploy:GetAttribute("ArtDown"), Disabled = deploy:GetAttribute("ArtDisabled"),
			Cancel = deploy:GetAttribute("ArtCancel"),
		}
	end
	if E.Ready then
		E.ReadyCtl = ui.Button(E.Ready, function()
			ctx.menu("Ready", Common.MyStatus(ctx) ~= "READY")
		end, { Sound = "Beep" })
	end
	if E["Squad/Leave"] then
		ui.Button(E["Squad/Leave"], function()
			ctx.party("Leave")
		end, { Sound = "Back" })
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

local function chapterFor(id)
	return if id == "Campaign" then 1 else nil
end

-- The leader tells the squad what they picked (only in a squad, and only when it differs from the server's pick).
local function sendPick()
	local ctx = ctxRef
	local squad = Common.Squad(ctx)
	if not shown or not mode or squad.Solo or not Common.IsLeader(ctx) or squad.State ~= "Idle" then
		return
	end
	if squad.Mode == mode then
		return
	end
	ctx.menu("Pick", { Mode = mode, Chapter = chapterFor(mode) })
end

local function deploy(ctx)
	local squad = Common.Squad(ctx)
	if not Common.IsLeader(ctx) then
		return
	end
	if squad.State == "Countdown" then
		ctx.menu("Cancel")
		return
	end
	if squad.State ~= "Idle" or not mode or Common.Locked(ctx.player, mode) then
		return
	end
	ctx.player:SetAttribute("MenuLastMode", mode)
	ctx.menu("Deploy", { Mode = mode, Join = if mode == "Campaign" then "Quick" else nil, Chapter = chapterFor(mode) })
end

-- DEPLOY's art set: "Deploy" or "Cancel". Rewires the button so its hover/down states follow.
local function deployLook(E, cancel)
	local btn = E.Deploy
	if not btn or not E.DeployArt then
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
	btn:SetAttribute("ArtIdle", if want == "Cancel" then a.Cancel else a.Idle)
	btn:SetAttribute("ArtHover", if want == "Cancel" then a.Cancel else a.Hover)
	btn:SetAttribute("ArtDown", if want == "Cancel" then a.Cancel else a.Down)
	local ctx = ctxRef
	E.DeployCtl = ctx.ui.Button(btn, function()
		deploy(ctx)
	end, { Sound = if want == "Cancel" then "Back" else "Deploy" })
end

local function refreshDeploy()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local squad = Common.Squad(ctx)
	local leader = Common.IsLeader(ctx)
	local ready = Common.MyStatus(ctx) == "READY"
	local countdown = squad.State == "Countdown"
	if E.Deploy then
		E.Deploy.Visible = leader
		deployLook(E, leader and countdown)
		local label
		if countdown then
			label = "CANCEL" .. (if squad.Count then "  " .. tostring(squad.Count) else "")
		elseif squad.State == "Deploying" then
			label = "DEPLOYING"
		else
			label = "DEPLOY"
		end
		ui.Text(E["Deploy/Label"], label)
		if E.DeployCtl then
			E.DeployCtl.Disabled(not countdown and (squad.State ~= "Idle" or not mode or Common.Locked(ctx.player, mode)))
		end
	end
	if E.Ready then
		E.Ready.Visible = not leader
		if E.ReadyCtl then
			E.ReadyCtl.Selected(ready)
			E.ReadyCtl.Disabled(squad.State == "Deploying")
		end
	end
	-- the glow belongs to the button still waiting to be pressed
	if E.DeployGlow then
		E.DeployGlow.Visible = leader or not ready
	end
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
		local locked, rule = Common.Locked(ctx.player, id)
		local lock = card:FindFirstChild("Lock")
		if lock then
			lock.Visible = locked
			ui.Text(lock:FindFirstChild("Rule"), rule or "")
		end
		local select = card:FindFirstChild("Select")
		if select then
			local ctl = ui.Button(select, function()
				if mode ~= id and Common.IsLeader(ctx) then
					mode = id
					ctx.player:SetAttribute("MenuLastMode", id)
					Page.Refresh()
					sendPick()
				end
			end, { Sound = "Tick" })
			ctl.Disabled(locked or not Common.IsLeader(ctx))
			ctl.Selected(id == mode)
			modeCtls[id] = ctl
		end
	end)
	-- two chips at most: the mode in a few words, nothing longer
	local chips = {}
	for i, c in (Common.Info(mode or Common.Modes()[1]).Chips or {}) do
		if i <= 2 then
			table.insert(chips, c)
		end
	end
	ui.Fill(E.Chips, chips, function(chip, text)
		ui.Text(chip:FindFirstChild("Label"), text)
	end)
end

local function refreshSquad()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local squad = Common.Squad(ctx)
	local members = squad.Members
	local slots = {}
	for i = 1, 4 do
		slots[i] = members[i] or false
	end
	ui.Fill(E["Squad/Slots"], slots, function(slot, m)
		local filled = slot:FindFirstChild("Filled")
		local invite = slot:FindFirstChild("Invite")
		if not m then
			if filled then
				filled.Visible = false
			end
			if invite then
				invite.Visible = true
				ui.Button(invite, function()
					ctx.go("Party")
				end)
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
		local head = filled:FindFirstChild("Head")
		if head and head:IsA("ImageLabel") and tonumber(m.UserId) and m.UserId > 0 then
			head.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", m.UserId)
		end
		local lead = filled:FindFirstChild("Leader")
		if lead then
			lead.Visible = not squad.Solo and m.UserId == squad.Leader
		end
		local tick = filled:FindFirstChild("Ready")
		if tick then
			tick.Visible = not squad.Solo and m.UserId ~= squad.Leader and Common.IsReady(m)
		end
	end)
	if E["Squad/Leave"] then
		E["Squad/Leave"].Visible = #members >= 2 and squad.Leader ~= ctx.player.UserId
	end
end

function Page.Refresh()
	if not ctxRef then
		return
	end
	refreshModes()
	refreshSquad()
	refreshDeploy()
end

-- The mode HOME opens on: the squad's pick for a mate, else the last one played if it is open, else the first card.
local function pickMode(ctx, want)
	if not Common.IsLeader(ctx) then
		local squad = Common.Squad(ctx)
		if type(squad.Mode) == "string" and table.find(Common.Modes(), squad.Mode) then
			return squad.Mode
		end
	end
	if want and table.find(Common.Modes(), want) and not Common.Locked(ctx.player, want) then
		return want
	end
	if mode and table.find(Common.Modes(), mode) and not Common.Locked(ctx.player, mode) then
		return mode
	end
	return (Common.DeployMode(ctx))
end

function Page.Init(ctx)
	ctxRef = ctx
	els(ctx)
	ctx.on("Party", function(s)
		if not shown then
			return
		end
		-- a mate follows the leader's pick
		if type(s) == "table" and s.Leader ~= ctx.player.UserId and type(s.Mode) == "string" and s.Mode ~= mode
			and table.find(Common.Modes(), s.Mode)
		then
			mode = s.Mode
		end
		Page.Refresh()
		sendPick()
	end)
	-- one line beside DEPLOY: a mate who is not READY, or a squad too big for MULTIPLAYER
	ctx.on("NotReady", function(names)
		if not shown then
			return
		end
		local E = els(ctx)
		ctx.sound("Error")
		Common.Notice(ctx, E.Notice, E["Notice/Text"], Common.WaitingLine(names), 3)
	end)
	ctx.on("DeployFailed", function(reason)
		if not shown then
			return
		end
		local E = els(ctx)
		local line = if reason == "TooMany" then "1 V 1: A SQUAD OF 2 AT MOST"
			elseif reason == "Studio" then "TELEPORTS DON'T WORK IN STUDIO"
			else nil
		if line then
			ctx.sound("Error")
			Common.Notice(ctx, E.Notice, E["Notice/Text"], line, 3)
		end
	end)
	for _, name in { "Escaped", "Level", "Stats" } do
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

-- args.Mode picks a card. args.Reveal (the first menu after the first match): the pieces come in one at a time.
function Page.Show(ctx, args)
	ctxRef = ctx
	shown = true
	local want = type(args) == "table" and args.Mode or nil
	mode = pickMode(ctx, want)
	Page.Refresh()
	local E = els(ctx)
	local list = {}
	for _, c in (E.Modes and E.Modes:GetChildren()) or {} do
		if c:IsA("GuiObject") and c:GetAttribute("_Clone") then
			table.insert(list, c)
		end
	end
	for _, k in { "Deploy", "Ready", "Squad" } do
		if E[k] and E[k].Visible then
			table.insert(list, E[k])
		end
	end
	if type(args) == "table" and args.Reveal then
		task.spawn(function()
			for _, g in list do
				ctx.sound("Tick")
				ctx.ui.Stagger({ g })
				task.wait(0.18)
			end
		end)
	else
		ctx.ui.Stagger(list)
	end
	ctx.select(if Common.IsLeader(ctx) then E.Deploy else E.Ready)
	sendPick()
end

function Page.Hide()
	shown = false
	for _, E in wired do
		if E.Notice then
			E.Notice.Visible = false
		end
	end
end

return Page
