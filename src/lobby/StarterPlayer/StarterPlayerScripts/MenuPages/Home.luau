-- Home page (FRONT-A, 4 Nov 2026): the recommended mode's play card with DEPLOY, the Night Pass and FEATURED cards,
-- the squad slots from the Party state (INVITE opens the Party overlay) and the daily rows (WIDE).
-- FEATURED stays hidden until selling opens (first escape or level 3). Elements: notes/SCREENS-A.md (Home table).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Common = require(script.Parent:WaitForChild("TopBar"):WaitForChild("Common"))
local Progression = Common.Progression
local Catalogue = nil
pcall(function()
	Catalogue = require(ReplicatedStorage.Shared:WaitForChild("Catalogue", 5))
end)

local Page = { Name = "Home", Tab = "Home", Camera = "Home" }

local ctxRef = nil
local wired = {}
local shown = false
local featured = nil -- {Id, Name, Kind, Art, Price, Robux}
local featuredDay = nil
local clockConn = nil

local function wire(ctx)
	local ui = ctx.ui
	local E = {}
	for _, path in {
		"PlayCard", "PlayCard/Art", "PlayCard/ModeName", "PlayCard/Line", "PlayCard/Chips", "PlayCard/Open",
		"Deploy", "DeployGlow", "Pass", "Pass/Season", "Pass/Tier", "Pass/TierMax", "Pass/Bar",
		"Featured", "Featured/Render", "Featured/Name", "Featured/Kind", "Featured/PriceTag", "Featured/Price",
		"Daily", "Daily/Resets", "Daily/Rows", "Squad", "Squad/Count", "Squad/Slots", "Squad/Leave", "PlayShadow",
	} do
		E[path] = ctx.el("Home", path)
	end
	if E["PlayCard/Open"] then
		ui.Button(E["PlayCard/Open"], function()
			ctx.go("Play", { Mode = Common.Recommended(ctx.player) })
		end)
	end
	if E.Deploy then
		E.DeployCtl = ui.Button(E.Deploy, function()
			local mode = Common.Recommended(ctx.player)
			if not Common.IsLeader(ctx) or Common.Squad(ctx).State ~= "Idle" or Common.Locked(ctx.player, mode) then
				return
			end
			ctx.player:SetAttribute("MenuLastMode", mode)
			ctx.menu("Deploy", { Mode = mode, Join = if mode == "Campaign" then "Quick" else nil })
		end, { Sound = "Deploy" })
	end
	if E.Pass then
		ui.Button(E.Pass, function()
			if ctx.pages.Pass then
				ctx.go("Pass")
			end
		end)
	end
	if E.Featured then
		ui.Button(E.Featured, function()
			if ctx.pages.Store then
				ctx.go("Store", { Section = "Featured", Item = featured and featured.Id })
			end
		end)
	end
	if E["Squad/Leave"] then
		ui.Button(E["Squad/Leave"], function()
			ctx.party("Leave")
		end, { Sound = "Back" })
	end
	E.Home = {}
	for _, k in { "PlayShadow", "PlayCard", "Deploy", "DeployGlow", "Pass", "Featured", "Daily", "Squad" } do
		if E[k] then
			E.Home[k] = E[k].Position
		end
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

local function refreshMode()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local info = Common.Info(Common.Recommended(ctx.player))
	if E["PlayCard/Art"] and ui.Art(info.Wide) then
		ui.SetArt(E["PlayCard/Art"], info.Wide)
	end
	ui.Text(E["PlayCard/ModeName"], info.Name)
	ui.Text(E["PlayCard/Line"], info.Line)
	ui.Fill(E["PlayCard/Chips"], info.Chips, function(c, text)
		ui.Text(c:FindFirstChild("Label"), text)
	end)
end

local function refreshDeploy()
	local ctx = ctxRef
	local E = els(ctx)
	local squad = Common.Squad(ctx)
	if E.DeployCtl then
		E.DeployCtl.Disabled(not Common.IsLeader(ctx) or squad.State ~= "Idle")
	end
end

local function refreshPass()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local pass = Progression.Pass
	local tier, into, need = Progression.PassTier(ctx.player:GetAttribute("PassXp") or 0)
	tier = ctx.player:GetAttribute("PassTier") or tier
	ui.Text(E["Pass/Season"], "SEASON " .. tostring(pass.Season) .. "  ·  " .. tostring(pass.Name))
	ui.Text(E["Pass/Tier"], "TIER " .. tostring(tier))
	ui.Text(E["Pass/TierMax"], "/ " .. tostring(pass.Tiers))
	ui.Bar(E["Pass/Bar"], if need > 0 then into / need else 1)
end

local function refreshFeatured()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local f = E.Featured
	if not f then
		return
	end
	if not featured or not Common.Selling(ctx.player) then
		f.Visible = false
		return
	end
	f.Visible = true
	if E["Featured/Render"] and ui.Art(featured.Art) then
		ui.SetArt(E["Featured/Render"], featured.Art)
	end
	ui.Text(E["Featured/Name"], featured.Name)
	ui.Text(E["Featured/Kind"], featured.Kind)
	local priced = featured.Robux ~= nil or featured.Price ~= nil
	for _, k in { "Featured/PriceTag", "Featured/Price" } do
		if E[k] then
			E[k].Visible = priced
		end
	end
	if not priced then
		return
	end
	if featured.Robux then
		Common.SwapArt(ui, E["Featured/PriceTag"], "PriceTag%a*", "PriceTagRobux")
		ui.Text(E["Featured/Price"], ui.Money(featured.Robux))
	else
		Common.SwapArt(ui, E["Featured/PriceTag"], "PriceTag%a*", "PriceTag")
		ui.Text(E["Featured/Price"], ui.Money(featured.Price or 0))
	end
end

-- Today's hero from the store (StoreServer "Catalogue"), fetched once a day.
local function fetchFeatured()
	local ctx = ctxRef
	local day = Progression.Day()
	if featuredDay == day then
		return
	end
	featuredDay = day
	task.spawn(function()
		local res = ctx.store("Catalogue", {})
		if type(res) ~= "table" or not res.Ok or not res.Hero or res.Selling == false or not Catalogue then
			featured = nil
			if type(res) ~= "table" or not res.Ok then
				featuredDay = nil -- try again next time
			end
			refreshFeatured()
			return
		end
		local id = res.Hero
		local kind, key = Catalogue.Split(id)
		if kind == "Product" then
			local p = Catalogue.Products[key]
			featured = p and { Id = id, Name = p.Name, Kind = "PACK", Art = p.Art, Robux = p.Robux } or nil
		else
			local item = Catalogue.Items[id]
			featured = item and {
				Id = id, Name = item.Name, Kind = string.upper(item.Kind or ""),
				Art = if item.Kind == "Operator" and ctx.ui.Art("OperatorPortrait/" .. item.Id) then "OperatorPortrait/" .. item.Id
					else item.Art,
				Price = Catalogue.Price(id),
			} or nil
		end
		refreshFeatured()
	end)
end

local function refreshDaily()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	if not E["Daily/Rows"] then
		return
	end
	local daily = Common.Decode(ctx.player:GetAttribute("Daily")) or {}
	local rows = {}
	for _, id in daily.Ids or {} do
		local c = Progression.Challenge(id)
		if c then
			local progress = tonumber((daily.Progress or {})[id]) or 0
			local done = (daily.Done or {})[id] == true or progress >= c.Goal
			table.insert(rows, { Label = c.Label, Xp = c.Xp, Goal = c.Goal, Progress = math.min(progress, c.Goal), Done = done })
		end
	end
	ui.Fill(E["Daily/Rows"], rows, function(row, r)
		ui.Text(row:FindFirstChild("Label"), r.Label)
		ui.Text(row:FindFirstChild("Reward"), "+" .. ui.Money(r.Xp) .. " XP")
		ui.Text(row:FindFirstChild("Progress"), r.Progress .. "/" .. r.Goal)
		local bar = row:FindFirstChild("Bar")
		ui.Bar(bar, r.Progress / math.max(1, r.Goal))
		if r.Done then
			Common.SwapArt(ui, row:FindFirstChild("Plate"), "DailyRow%a*", "DailyRowDone")
			local fill = bar and bar:FindFirstChild("Clip") and bar.Clip:FindFirstChild("Fill")
			Common.SwapArt(ui, fill, "DailyBar_Fill", "DailyBarDone")
		end
	end)
end

local function refreshClock()
	local ctx = ctxRef
	local E = els(ctx)
	if E["Daily/Resets"] then
		ctx.ui.Text(E["Daily/Resets"], "RESETS IN " .. Common.Left(Progression.DayEnds(Progression.Day()) - os.time()))
	end
end

local function refreshSquad()
	local ctx = ctxRef
	local E = els(ctx)
	local ui = ctx.ui
	local squad = Common.Squad(ctx)
	local members = squad.Members
	ui.Text(E["Squad/Count"], #members .. "/4")
	local slots = {}
	for i = 1, 4 do
		slots[i] = members[i] or false
	end
	ui.Fill(E["Squad/Slots"], slots, function(slot, m)
		Common.FillSlot(ctx, slot, m or nil, squad.Leader, function()
			ctx.go("Party")
		end)
	end)
	if E["Squad/Leave"] then
		E["Squad/Leave"].Visible = #members >= 2 and squad.Leader ~= ctx.player.UserId
	end
	refreshDeploy()
end

local function refreshAll()
	refreshMode()
	refreshPass()
	refreshFeatured()
	refreshDaily()
	refreshClock()
	refreshSquad()
end

-- The deploy glow breathes while HOME is up.
local function breathe()
	if clockConn then
		clockConn:Disconnect()
	end
	local t, last = 0, 0
	clockConn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		local E = els(ctxRef)
		if E.DeployGlow then
			E.DeployGlow.ImageTransparency = 0.35 + math.sin(t * 1.8) * 0.15
		end
		if t - last >= 1 then
			last = t
			refreshClock()
		end
	end)
end

function Page.Init(ctx)
	ctxRef = ctx
	els(ctx)
	ctx.on("Party", function()
		if shown then
			refreshSquad()
		end
	end)
	for _, name in { "PassXp", "PassTier" } do
		ctx.onAttr(name, function()
			if shown then
				refreshPass()
			end
		end)
	end
	ctx.onAttr("Daily", function()
		if shown then
			refreshDaily()
		end
	end)
	for _, name in { "Escaped", "Level" } do
		ctx.onAttr(name, function()
			if shown then
				refreshMode()
				fetchFeatured()
				refreshFeatured()
			end
		end)
	end
end

function Page.Layout(ctx)
	ctxRef = ctx
	els(ctx)
	if shown then
		refreshAll()
	end
end

-- args.Reveal: the first menu after the first match; the panels appear one at a time with a tick.
function Page.Show(ctx, args)
	ctxRef = ctx
	shown = true
	local E = els(ctx)
	refreshAll()
	fetchFeatured()
	breathe()
	if type(args) == "table" and args.Reveal then
		local order = { "PlayShadow", "PlayCard", "Deploy", "DeployGlow", "Pass", "Featured", "Daily", "Squad" }
		local wasVisible = {}
		for _, k in order do
			if E[k] then
				wasVisible[k] = E[k].Visible
				E[k].Visible = false
			end
		end
		task.spawn(function()
			local i = 0
			for _, k in order do
				if E[k] and wasVisible[k] then
					i += 1
					task.wait(if k == "DeployGlow" or k == "PlayShadow" then 0 else 0.22)
					E[k].Visible = true
					if k ~= "DeployGlow" and k ~= "PlayShadow" then
						ctx.sound("Tick")
						ctx.ui.Stagger({ E[k] })
					end
				end
			end
		end)
	else
		local list = {}
		for _, k in { "PlayCard", "Deploy", "Pass", "Featured", "Squad" } do
			if E[k] and E[k].Visible then
				table.insert(list, E[k])
			end
		end
		for k, home in E.Home do
			if E[k] then
				-- Router.Fit moves panels to the screen edges; its fitted spot wins over the one cached at Init
				E[k].Position = E[k]:GetAttribute("_FlexPos") or home
			end
		end
		ctx.ui.Stagger(list)
	end
	ctx.select(E.Deploy)
end

function Page.Hide()
	shown = false
	if clockConn then
		clockConn:Disconnect()
		clockConn = nil
	end
end

return Page
