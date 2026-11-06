-- TopBar page (FRONT-A, 4 Nov 2026; kid reskin 5 Nov): always on in the lobby menu. Tabs HOME GUNS STORE PASS (PLAY
-- is part of HOME now; the Loadout tab's art reads GUNS) with the underline sliding to the current one (WIDE; PHONE's
-- selected tab art carries the mark), NEW pips for unseen unlocks, the profile plate (rank insignia, name, level, XP
-- bar; opens the service record), the framed GEMS wallet (gem, count, +; the whole frame opens the Store's gem packs)
-- and the settings gear (SettingsClient's Open event). LB/RB cycle the tabs.
-- Elements: horror-shooter/menu/art/screens/TopBar.py. Gems are the Scrip currency under a kid-friendly name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = require(script:WaitForChild("Common"))
local Progression = Common.Progression

local Page = { Name = "TopBar", Persistent = true }

local TABS = { "Home", "Loadout", "Store", "Pass" }
-- which tab a page lights
local TAB_OF = {
	Home = "Home", Play = "Home", Loadout = "Loadout", Picker = "Loadout", Gunsmith = "Loadout", Store = "Store",
	Confirm = "Store", Pass = "Pass",
}

local ctxRef = nil
local wired = {} -- [variant] = elements and controllers
local current = "Home"

local function openSettings()
	local scripts = script.Parent and script.Parent.Parent
	local sc = scripts and scripts:FindFirstChild("SettingsClient")
	local ev = sc and sc:FindFirstChild("Open")
	if ev and ev:IsA("BindableEvent") then
		ev:Fire()
	end
end

local function wire(ctx)
	local E = { Tabs = {}, Ctl = {} }
	local ui = ctx.ui
	for _, tab in TABS do
		local btn = ctx.el("TopBar", "Tabs/" .. tab)
		if btn then
			E.Tabs[tab] = btn
			E.Ctl[tab] = ui.Button(btn, function()
				if ctx.pages[tab] then
					ctx.go(tab)
				end
			end, { Sound = "Tab" })
		end
	end
	E.TabsFrame = ctx.el("TopBar", "Tabs")
	E.Underline = ctx.el("TopBar", "Underline")
	E.Profile = ctx.el("TopBar", "Profile")
	E.Insignia = ctx.el("TopBar", "Profile/Insignia")
	E.Name = ctx.el("TopBar", "Profile/Name")
	E.Level = ctx.el("TopBar", "Profile/Level")
	E.Xp = ctx.el("TopBar", "Profile/Xp")
	E.Wallet = ctx.el("TopBar", "Wallet")
	E.Scrip = ctx.el("TopBar", "Wallet/Scrip")
	E.Plus = ctx.el("TopBar", "Wallet/Plus")
	E.Settings = ctx.el("TopBar", "Settings")
	if E.Profile then
		E.ProfileCtl = ui.Button(E.Profile, function()
			if ctx.pages.Record then
				ctx.go("Record", { UserId = ctx.player.UserId })
			end
		end)
	end
	local function gems()
		if ctx.pages.Store then
			ctx.go("Store", { Section = "Scrip" })
		end
	end
	if E.Wallet then
		E.WalletCtl = ui.Button(E.Wallet, gems)
	end
	if E.Plus then
		E.PlusCtl = ui.Button(E.Plus, gems)
	end
	if E.Settings then
		E.SettingsCtl = ui.Button(E.Settings, openSettings)
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

local function placeUnderline(E, instant)
	local line, frame, btn = E.Underline, E.TabsFrame, E.Tabs[current]
	if not (line and frame) then
		return
	end
	if not btn then
		line.Visible = false
		return
	end
	line.Visible = true
	local x = frame.Position.X.Offset + btn.Position.X.Offset + 22
	local w = math.max(8, btn.Size.X.Offset - 44)
	local pos = UDim2.new(line.Position.X.Scale, x, line.Position.Y.Scale, line.Position.Y.Offset)
	local size = UDim2.new(line.Size.X.Scale, w, line.Size.Y.Scale, line.Size.Y.Offset)
	if instant then
		line.Position, line.Size = pos, size
	else
		ctxRef.ui.Tween(line, 0.18, { Position = pos, Size = size })
	end
end

local function refreshTabs(instant)
	local E = els(ctxRef)
	for tab, ctl in E.Ctl do
		ctl.Selected(tab == current)
	end
	placeUnderline(E, instant)
end

local function refreshProfile()
	local ctx = ctxRef
	local E = els(ctx)
	local p = ctx.player
	local level = p:GetAttribute("Level") or 1
	local stars = p:GetAttribute("Stars") or 0
	if E.Insignia then
		local key = if stars > 0 then "Rank/Star" else "Rank/" .. Progression.Rank(level)
		ctx.ui.SetArt(E.Insignia, key)
	end
	ctx.ui.Text(E.Name, string.upper(p.DisplayName ~= "" and p.DisplayName or p.Name))
	ctx.ui.Text(E.Level, "LV " .. level)
	local into, need = p:GetAttribute("XpInto") or 0, p:GetAttribute("XpNeed") or 0
	ctx.ui.Bar(E.Xp, if need > 0 then into / need else 1)
	ctx.ui.Text(E.Scrip, ctx.ui.Money(p:GetAttribute("Scrip") or 0))
	-- the + always shows (owner: the gems frame and + are how you reach the shop)
	if E.Plus then
		E.Plus.Visible = true
	end
end

local function refreshPips()
	local ctx = ctxRef
	local E = els(ctx)
	local new = Common.NewTabs(ctx.player)
	for tab, btn in E.Tabs do
		local pip = btn:FindFirstChild("New")
		if pip then
			pip.Visible = new[tab] == true and tab ~= current
		end
	end
end

function Page.Init(ctx)
	ctxRef = ctx
	els(ctx)
	ctx.on("Page", function(name, tab)
		local t = TAB_OF[name]
		if not t and type(tab) == "string" then
			for _, k in TABS do
				if k:lower() == tab:lower() then
					t = k
				end
			end
		end
		if t and t ~= current then
			current = t
			refreshTabs(false)
			refreshPips()
		end
	end)
	ctx.on("TabCycle", function(dir)
		local i = table.find(TABS, current) or 1
		for _ = 1, #TABS do
			i = (i - 1 + dir) % #TABS + 1
			if ctx.pages[TABS[i]] then
				ctx.sound("Tab")
				ctx.go(TABS[i])
				return
			end
		end
	end)
	ctx.on("Unlocked", refreshPips)
	for _, name in { "Level", "XpInto", "XpNeed", "Stars", "Scrip", "Escaped" } do
		ctx.onAttr(name, refreshProfile)
	end
	for _, name in { "Seen", "Owned", "Level", "PassTier", "PassClaimed", "PassPremium" } do
		ctx.onAttr(name, refreshPips)
	end
end

function Page.Layout(ctx)
	ctxRef = ctx
	els(ctx)
	refreshTabs(true)
	refreshProfile()
	refreshPips()
end

function Page.Show(ctx)
	ctxRef = ctx
	refreshTabs(true)
	refreshProfile()
	refreshPips()
end

function Page.Hide() end

-- For MenuClient's first-session reveal: the elements of the current variant in reading order.
function Page.Parts(ctx)
	local E = els(ctx)
	local out = {}
	for _, k in { "Logo", "Tabs", "Underline", "Rule", "Profile", "Wallet", "Settings" } do
		local e = ctx.el("TopBar", k)
		if e then
			table.insert(out, e)
		end
	end
	return out, E
end

return Page
