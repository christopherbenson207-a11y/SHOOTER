-- Play page (FRONT-A, 4 Nov 2026): the mode cards (locked ones show their rule), the picked mode's detail with chips,
-- the campaign's mission tiles, the squad slots (WIDE), FILL, DEPLOY / QUICK JOIN, SQUAD DEPLOY (campaign) and, for a
-- member who is not the leader, READY. During the countdown the leader's DEPLOY turns into CANCEL.
-- Elements: notes/SCREENS-A.md (Play table). Server protocol: MenuServer header.

local Common = require(script.Parent:WaitForChild("TopBar"):WaitForChild("Common"))

local Page = { Name = "Play", Tab = "Play", Camera = "Home" }

local ctxRef = nil
local wired = {}
local shown = false
local mode = nil -- picked mode id
local mission = 1 -- picked campaign mission
local modeCtls = {}
local tileCtls = {}

local function wire(ctx)
	local E = {}
	for _, path in {
		"Modes", "Detail", "Detail/Title", "Detail/Line", "Detail/Chips", "Detail/MissionsHeader", "Detail/Tiles",
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
				or Common.MissionLocked(ctx.player, mission)
			then
				return
			end
			ctx.player:SetAttribute("MenuLastMode", mode)
			ctx.menu("Deploy", { Mode = "Campaign", Join = "Squad", Mission = mission })
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
		if squad.State ~= "Idle" or not mode or Common.Locked(ctx.player, mode) then
			return
		end
		ctx.player:SetAttribute("MenuLastMode", mode)
		ctx.menu("Deploy", { Mode = mode, Join = if mode == "Campaign" then "Quick" else nil })
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
					mission = 1
					Page.Refresh()
				end
			end, { Sound = "Tick" })
			ctl.Disabled(locked)
			ctl.Selected(id == mode)
			modeCtls[id] = ctl
		end
	end)
end

local function refreshDetail()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local info = Common.Info(mode)
	ui.Text(E["Detail/Title"], info.Name)
	ui.Text(E["Detail/Line"], info.Line)
	ui.Fill(E["Detail/Chips"], info.Chips, function(c, text)
		ui.Text(c:FindFirstChild("Label"), text)
	end)
	local campaign = mode == "Campaign"
	for _, k in { "Detail/MissionsHeader", "Detail/Tiles" } do
		if E[k] then
			E[k].Visible = campaign
		end
	end
	table.clear(tileCtls)
	if E["Detail/Tiles"] then
		ui.Fill(E["Detail/Tiles"], if campaign then Common.Missions else {}, function(tile, m)
			local n = table.find(Common.Missions, m)
			local art = tile:FindFirstChild("Art")
			if art and ui.Art("Mission/" .. m.Id) then
				ui.SetArt(art, "Mission/" .. m.Id)
			end
			ui.Text(tile:FindFirstChild("Name"), m.Name)
			local locked, rule = Common.MissionLocked(ctx.player, n)
			local lock = tile:FindFirstChild("Lock")
			if lock then
				lock.Visible = locked == true
				ui.Text(lock:FindFirstChild("Rule"), rule or "")
			end
			local select = tile:FindFirstChild("Select")
			if select then
				local ctl = ui.Button(select, function()
					mission = n
					for i, c in tileCtls do
						c.Selected(i == n)
					end
					refreshDeploy()
				end, { Sound = "Tick" })
				ctl.Disabled(locked == true)
				ctl.Selected(n == mission)
				tileCtls[n] = ctl
			end
		end)
	end
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
			label = if campaign then "QUICK JOIN" else "DEPLOY"
		end
		ui.Text(E["Detail/Deploy/Label"], label)
		if E.DeployCtl then
			E.DeployCtl.Disabled(not countdown and (squad.State ~= "Idle" or Common.Locked(ctx.player, mode)))
		end
	end
	if E["Detail/SquadDeploy"] then
		E["Detail/SquadDeploy"].Visible = campaign and leader
		if E.SquadCtl then
			E.SquadCtl.Disabled(squad.State ~= "Idle" or Common.MissionLocked(ctx.player, mission) == true)
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
		if type(s) == "table" and s.Leader ~= ctx.player.UserId and type(s.Mode) == "string" and s.Mode ~= mode
			and table.find(Common.Modes(), s.Mode)
		then
			mode = s.Mode
			mission = tonumber(s.Mission) or 1
			Page.Refresh()
			return
		end
		refreshSquad()
		refreshDeploy()
	end)
	for _, name in { "Escaped", "Stats", "Missions" } do
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
		mission = 1
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
