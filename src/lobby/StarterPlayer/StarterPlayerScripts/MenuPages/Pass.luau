--!strict
-- MenuPages.Pass (FRONT-C, 4 Nov 2026): the NIGHT PASS page, with CHALLENGES inside it.
-- Elements and binds: horror-shooter/menu/notes/SCREENS-C.md "PASS". Data: player attributes PassSeason, PassXp,
-- PassTier, PassPremium, PassClaimed, Daily, Weekly (DATA). Actions: Store "PassClaim", "Reroll", "Product".
-- The script only wires authored art: it fills the TierCol / DailyRow / WeeklyRow templates with Ui.Fill, swaps
-- states, moves the tier strip and writes dynamic text. Both variants are wired once in Init; every render looks the
-- elements up again by name in the current variant.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local P = require(Shared:WaitForChild("Progression"))
local C = require(Shared:WaitForChild("Catalogue"))
local Ui = require(Shared:WaitForChild("Menu"):WaitForChild("Ui")) :: any

local Page = { Name = "Pass", Tab = "PASS", Overlay = false }

local VARIANTS = { "Wide", "Phone" }
local TRACKS = { "Free", "Premium" }
local KIND_WORD = {
	Card = "CALLING CARD",
	Operator = "OPERATOR",
	Camo = "CAMO",
	Beam = "BEAM",
	Scrip = "GEMS",
	Boost = "BOOST",
	Token = "TOKEN",
}
local ITEM_NAME = { Boost = "SQUAD BOOST", Token = "REVIVE TOKEN" }
local WATCHED = { "PassXp", "PassTier", "PassPremium", "PassClaimed", "PassSeason", "Daily", "Weekly" }

type Reward = { Kind: string, Id: string?, Amount: number? }
type Focus = { tier: number, track: string }

local state = {
	shown = false,
	first = nil :: number?, -- first tier column in view (0-based)
	focus = nil :: Focus?,
	view = "Rewards", -- Phone only: "Rewards" | "Challenges"
	token = 0,
	queued = false,
	busy = false,
}
local statics: { [string]: { [string]: any } } = {} -- variant -> button name -> Ui.Button controller
local cells: { [string]: { [number]: any } } = {} -- variant -> tier -> {Free = cell, Premium = cell}
local prices: { [string]: number } = {}

-- lookup ---------------------------------------------------------------------------------------------------------

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

-- The unit word a comp sample carried ("2,140 / 6,500 XP" keeps " XP"), remembered before the first rewrite.
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

-- pure helpers ---------------------------------------------------------------------------------------------------

-- "23D 14H", "7H 12M", "12M".
function Page.Left(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	if d > 0 then
		return string.format("%dD %dH", d, h)
	elseif h > 0 then
		return string.format("%dH %dM", h, m)
	end
	return string.format("%dM", m)
end

function Page.ArtKey(r: Reward): string?
	local kind, id = r.Kind, r.Id
	if kind == "Card" and id then
		return "Card/" .. id
	elseif kind == "Operator" and id then
		return "OperatorPortrait/" .. id
	elseif kind == "Camo" and id then
		return "Camo/" .. id
	elseif kind == "Beam" and id then
		return "Beam/" .. id
	elseif kind == "Scrip" then
		return "Kit/Scrip"
	elseif kind == "Boost" then
		return "Pass/Boost"
	elseif kind == "Token" then
		return "Pass/Token"
	end
	return nil
end

local function money(n: number?): string
	local s = tostring(math.floor(tonumber(n) or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function Page.RewardName(r: Reward): string
	if r.Id then
		local item = C.Items[r.Kind .. "/" .. r.Id]
		return item and item.Name or string.upper(r.Id)
	end
	if r.Kind == "Scrip" then
		return money(r.Amount) .. " GEMS"
	end
	return ITEM_NAME[r.Kind] or KIND_WORD[r.Kind] or string.upper(r.Kind)
end

function Page.AmountText(r: Reward): string
	if r.Kind == "Scrip" then
		return money(r.Amount)
	elseif r.Kind == "Boost" or r.Kind == "Token" then
		return "x" .. tostring(r.Amount or 1)
	end
	return ""
end

-- Which Robux offers the upsell shows (MENU-PLAN 3.9): without premium, NIGHT PASS and, while 10 or more tiers
-- remain, NIGHT PASS + 10 TIERS. Once premium is owned the upsell hides; +5 TIERS (only while 5 or more remain) and
-- +1 TIER are in STORE > PASSES.
function Page.Offers(premium: boolean, tier: number): { BuyPass: string?, BuyTiers: string? }
	if premium then
		return {}
	end
	local left = P.Pass.Tiers - tier
	return { BuyPass = "PassPremium", BuyTiers = if left >= 10 then "PassPremium10" else nil }
end

-- Claimed set from the PassClaimed attribute ({Free = {["2"] = true}, Premium = {...}}).
function Page.IsClaimed(claimedSet: any, track: string, tier: number): boolean
	local t = type(claimedSet) == "table" and claimedSet[track]
	return type(t) == "table" and (t[tostring(tier)] == true or t[tier] == true)
end

function Page.CanClaim(track: string, tier: number, reached: number, premium: boolean, claimedSet: any): boolean
	local r = P.Pass[track] and P.Pass[track][tier]
	return r ~= nil
		and tier <= reached
		and (track == "Free" or premium)
		and not Page.IsClaimed(claimedSet, track, tier)
end

-- Robux price for a product: the live price once its id is set, else the catalogue's.
local function priceOf(key: string): number
	local p = C.Products[key]
	if not p then
		return 0
	end
	if prices[key] then
		return prices[key]
	end
	if p.Id ~= 0 then
		prices[key] = p.Robux
		task.spawn(function()
			local infoType = if p.Type == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, p.Id, infoType)
			if ok and type(info) == "table" and tonumber(info.PriceInRobux) then
				prices[key] = tonumber(info.PriceInRobux) :: number
			end
		end)
		return p.Robux
	end
	return p.Robux
end

-- render ---------------------------------------------------------------------------------------------------------

local render: (any) -> ()

local function swapDone(img: Instance?, fromSuffix: string?)
	if not (img and (img:IsA("ImageLabel") or img:IsA("ImageButton"))) then
		return
	end
	local key = img:GetAttribute("UiArt")
	if type(key) ~= "string" or key:sub(-4) == "Done" then
		return
	end
	local done = if fromSuffix then (key:gsub(fromSuffix .. "$", "Done")) else key .. "Done"
	if Ui.Art(done) then
		Ui.SetArt(img, done)
	end
end

local function geometry(ctx: any): (any, any, number, number, number)
	local view = find(ctx.frame(Page.Name), "Rewards/TrackView")
	local tiers = view and view:FindFirstChild("Tiers")
	if not (view and tiers) then
		return nil, nil, 0, 0, 0
	end
	local layout = tiers:FindFirstChildOfClass("UIListLayout")
	local pad = layout and layout.Padding.Offset or 0
	local step = tiers.Size.X.Offset / P.Pass.Tiers
	local perPage = math.max(1, math.floor((view.Size.X.Offset + pad) / math.max(step, 1)))
	local maxFirst = math.max(0, P.Pass.Tiers - perPage)
	return view, tiers, step, perPage, maxFirst
end

local function scrollTo(ctx: any, first: number, animate: boolean)
	local _, tiers, step, _, maxFirst = geometry(ctx)
	if not tiers then
		return
	end
	first = math.clamp(math.floor(first), 0, maxFirst)
	state.first = first
	local goal = UDim2.fromOffset(-first * step, tiers.Position.Y.Offset)
	if animate then
		ctx.ui.Tween(tiers, 0.22, { Position = goal })
	else
		tiers.Position = goal
	end
	local s = statics[ctx.variant] or {}
	if s.Prev then
		s.Prev.Disabled(first <= 0)
	end
	if s.Next then
		s.Next.Disabled(first >= maxFirst)
	end
end

local function showFocus(ctx: any)
	local f = state.focus
	local frame = ctx.frame(Page.Name)
	local nameLabel = find(frame, "Rewards/FocusName")
	local kindLabel = find(frame, "Rewards/FocusKind")
	local r = f and P.Pass[f.track] and P.Pass[f.track][f.tier]
	if f and r then
		ctx.ui.Text(nameLabel, Page.RewardName(r))
		ctx.ui.Text(kindLabel, (KIND_WORD[r.Kind] or string.upper(r.Kind)) .. "  \u{00B7}  " .. string.upper(f.track) .. " TIER " .. f.tier)
	else
		ctx.ui.Text(nameLabel, "")
		ctx.ui.Text(kindLabel, "")
	end
	for tier, entry in cells[ctx.variant] or {} do
		for _, track in TRACKS do
			local c = entry[track]
			if c and c.plate then
				c.plate.Selected(f ~= nil and f.tier == tier and f.track == track)
			end
		end
	end
end

local function focus(ctx: any, tier: number, track: string)
	state.focus = { tier = tier, track = track }
	showFocus(ctx)
end

local function claimOne(ctx: any, tier: number, track: string)
	if state.busy then
		return
	end
	state.busy = true
	local res = ctx.store("PassClaim", { Tier = tier, Track = track })
	state.busy = false
	ctx.sound(if res.Ok then "Stamp" else "Error")
	if state.shown then
		render(ctx)
	end
end

local function claimAll(ctx: any)
	if state.busy then
		return
	end
	state.busy = true
	local res = ctx.store("PassClaim", { All = true })
	state.busy = false
	if res.Ok and type(res.Granted) == "table" and #res.Granted > 0 then
		ctx.sound("Stamp")
	elseif not res.Ok then
		ctx.sound("Error")
	end
	if state.shown then
		render(ctx)
	end
end

local function reroll(ctx: any, index: number)
	if state.busy then
		return
	end
	state.busy = true
	local res = ctx.store("Reroll", { Index = index })
	state.busy = false
	if not res.Ok then
		ctx.sound("Error")
	end
	if state.shown then
		render(ctx)
	end
end

local function buy(ctx: any, which: string)
	local premium = ctx.attr("PassPremium") == true
	local tier = P.PassTier(tonumber(ctx.attr("PassXp")) or 0)
	local key = Page.Offers(premium, tier)[which]
	if not key then
		return
	end
	local res = ctx.store("Product", { Key = key })
	if not res.Ok then
		ctx.sound("Error")
	end
end

local function setView(ctx: any, view: string)
	state.view = view
	local frame = ctx.frame(Page.Name)
	if not frame then
		return
	end
	local split = frame:FindFirstChild("ViewRewards") ~= nil -- Phone shows one view at a time
	setVisible(frame:FindFirstChild("Rewards"), not split or view == "Rewards")
	setVisible(frame:FindFirstChild("Challenges"), not split or view == "Challenges")
	local s = statics[ctx.variant] or {}
	if s.ViewRewards then
		s.ViewRewards.Selected(view == "Rewards")
	end
	if s.ViewChallenges then
		s.ViewChallenges.Selected(view == "Challenges")
	end
end

local function wireStatic(ctx: any, variant: string)
	local frame = frameOf(ctx, variant)
	if not frame then
		return
	end
	local s = {}
	local function wire(name: string, path: string, fn: () -> ())
		local b = find(frame, path)
		if b and b:IsA("GuiButton") then
			s[name] = ctx.ui.Button(b, fn)
		end
	end
	wire("ClaimAll", "Rewards/ClaimAll", function()
		claimAll(ctx)
	end)
	wire("Prev", "Rewards/Prev", function()
		local _, _, _, perPage = geometry(ctx)
		scrollTo(ctx, (state.first or 0) - perPage, true)
	end)
	wire("Next", "Rewards/Next", function()
		local _, _, _, perPage = geometry(ctx)
		scrollTo(ctx, (state.first or 0) + perPage, true)
	end)
	wire("BuyPass", "Rewards/Upsell/BuyPass", function()
		buy(ctx, "BuyPass")
	end)
	wire("BuyTiers", "Rewards/Upsell/BuyTiers", function()
		buy(ctx, "BuyTiers")
	end)
	wire("ViewRewards", "ViewRewards", function()
		setView(ctx, "Rewards")
	end)
	wire("ViewChallenges", "ViewChallenges", function()
		setView(ctx, "Challenges")
	end)
	statics[variant] = s
end

-- The 30 tier columns, cloned once per variant and refreshed in place (gamepad selection survives a refresh).
local function buildCells(ctx: any, variant: string)
	local list = find(frameOf(ctx, variant), "Rewards/TrackView/Tiers")
	if not list then
		return
	end
	local tiers = {}
	for t = 1, P.Pass.Tiers do
		tiers[t] = t
	end
	local out = {}
	ctx.ui.Fill(list, tiers, function(col: Instance, t: number)
		local entry = {}
		for _, track in TRACKS do
			local cell = col:FindFirstChild(track)
			if cell then
				local c: any = { cell = cell }
				local plate = cell:FindFirstChild("Plate")
				if plate and plate:IsA("GuiButton") then
					c.plate = ctx.ui.Button(plate, function()
						focus(ctx, t, track)
					end)
				end
				local claim = cell:FindFirstChild("Claim")
				if claim and claim:IsA("GuiButton") then
					c.claim = ctx.ui.Button(claim, function()
						claimOne(ctx, t, track)
					end)
				end
				entry[track] = c
			end
		end
		out[t] = entry
	end)
	cells[variant] = out
end

local function refreshCells(ctx: any, reached: number, premium: boolean, claimedSet: any): number
	local claimable = 0
	for t, entry in cells[ctx.variant] or {} do
		local col = entry.Free and entry.Free.cell.Parent or entry.Premium and entry.Premium.cell.Parent
		if col then
			ctx.ui.Text(col:FindFirstChild("Num"), t)
			setVisible(col:FindFirstChild("Here"), t == reached)
		end
		for _, track in TRACKS do
			local c = entry[track]
			if not c then
				continue
			end
			local cell = c.cell
			local r: Reward? = P.Pass[track][t]
			local isClaimed = r ~= nil and Page.IsClaimed(claimedSet, track, t)
			local can = Page.CanClaim(track, t, reached, premium, claimedSet)
			if can then
				claimable += 1
			end
			local art = cell:FindFirstChild("Art")
			setVisible(art, r ~= nil)
			if r and art then
				ctx.ui.SetArt(art, Page.ArtKey(r))
			end
			local amount = cell:FindFirstChild("Amount")
			ctx.ui.Text(amount, if r then Page.AmountText(r) else "")
			setVisible(amount, r ~= nil and not can)
			setVisible(cell:FindFirstChild("Veil"), r ~= nil and t > reached)
			setVisible(cell:FindFirstChild("Lock"), r ~= nil and track == "Premium" and not premium)
			setVisible(cell:FindFirstChild("Check"), isClaimed)
			setVisible(cell:FindFirstChild("Claim"), can)
			if c.plate then
				c.plate.Disabled(r == nil)
			end
		end
	end
	return claimable
end

local function fillChallenges(ctx: any, frame: Instance, which: string)
	local list = find(frame, "Challenges/" .. which .. "/Rows")
	if not list then
		return
	end
	local data = ctx.attr(which)
	data = if type(data) == "table" then data else {}
	local ids = if type(data.Ids) == "table" then data.Ids else {}
	local progress = if type(data.Progress) == "table" then data.Progress else {}
	local doneSet = if type(data.Done) == "table" then data.Done else {}
	local rerolled = data.Rerolled == true
	local ui = ctx.ui
	ui.Fill(list, ids, function(row: Instance, id: string, i: number)
		local c = P.Challenge(id)
		if not c then
			setVisible(row, false)
			return
		end
		local done = doneSet[id] == true
		local p = if done then c.Goal else math.clamp(tonumber(progress[id]) or 0, 0, c.Goal)
		ui.Text(row:FindFirstChild("Label"), c.Label)
		ui.Text(row:FindFirstChild("Reward"), "+" .. money(c.Xp) .. " XP")
		ui.Bar(row:FindFirstChild("Bar"), p / math.max(c.Goal, 1))
		local prog = row:FindFirstChild("Progress")
		ui.Text(prog, money(p) .. "/" .. money(c.Goal))
		setVisible(prog, not done)
		setVisible(row:FindFirstChild("Check"), done)
		if done then
			swapDone(row:FindFirstChild("Plate"), nil)
			swapDone(find(row, "Bar/Clip/Fill"), "_Fill")
		end
		local rr = row:FindFirstChild("Reroll")
		if rr and rr:IsA("GuiButton") then
			local b = ui.Button(rr, function()
				reroll(ctx, i)
			end)
			b.Disabled(rerolled or done)
		end
	end)
end

local function timers(ctx: any)
	local frame = ctx.frame(Page.Name)
	if not frame then
		return
	end
	local now = os.time()
	local seasonNo = tonumber(ctx.attr("PassSeason")) or P.Pass.Season
	local season = P.Seasons[seasonNo] or P.Pass
	ctx.ui.Text(find(frame, "Ends/TimeLeft"), Page.Left((season.Ends or now) - now))
	ctx.ui.Text(find(frame, "Challenges/Daily/DailyReset"), Page.Left(P.DayEnds(P.Day(now)) - now))
	ctx.ui.Text(find(frame, "Challenges/Weekly/WeeklyReset"), Page.Left(P.WeekEnds(P.Week(now)) - now))
end

render = function(ctx: any)
	local frame = ctx.frame(Page.Name)
	if not frame then
		return
	end
	local ui = ctx.ui
	local pass = P.Pass
	local xp = tonumber(ctx.attr("PassXp")) or 0
	local tier, into, need = P.PassTier(xp)
	local premium = ctx.attr("PassPremium") == true
	local claimedSet = ctx.attr("PassClaimed")
	local seasonNo = tonumber(ctx.attr("PassSeason")) or pass.Season
	local season = P.Seasons[seasonNo] or pass

	-- header
	ui.Text(frame:FindFirstChild("SeasonName"), season.Name)
	ui.Text(frame:FindFirstChild("SeasonNo"), "SEASON " .. seasonNo)
	ui.Text(frame:FindFirstChild("Tier"), tier)
	ui.Text(frame:FindFirstChild("TierMax"), "/ " .. pass.Tiers)
	local tierXp = frame:FindFirstChild("TierXp")
	local unit = suffix(tierXp, "XP")
	if need > 0 then
		ui.Text(tierXp, money(into) .. " / " .. money(need) .. unit)
	else
		ui.Text(tierXp, money(pass.TierXp) .. " / " .. money(pass.TierXp) .. unit)
	end
	ui.Bar(frame:FindFirstChild("TierBar"), if need > 0 then into / need else 1)
	setVisible(frame:FindFirstChild("PremiumChip"), premium)

	-- reward track
	if not cells[ctx.variant] then
		buildCells(ctx, ctx.variant)
	end
	local claimable = refreshCells(ctx, tier, premium, claimedSet)
	setVisible(find(frame, "Rewards/PremiumLabel/Lock"), not premium)
	local s = statics[ctx.variant] or {}
	if s.ClaimAll then
		s.ClaimAll.Disabled(claimable == 0)
	end
	if state.first == nil then
		scrollTo(ctx, tier - 2, false)
	else
		scrollTo(ctx, state.first, false)
	end
	if not state.focus then
		local track = if pass.Premium[tier] then "Premium" else "Free"
		for t = 1, tier do
			if Page.CanClaim("Free", t, tier, premium, claimedSet) then
				state.focus = { tier = t, track = "Free" }
				break
			elseif Page.CanClaim("Premium", t, tier, premium, claimedSet) then
				state.focus = { tier = t, track = "Premium" }
				break
			end
		end
		state.focus = state.focus or { tier = tier, track = track }
	end
	showFocus(ctx)

	-- upsell
	local offers = Page.Offers(premium, tier)
	setVisible(find(frame, "Rewards/Upsell"), not premium)
	local upArt = find(frame, "Rewards/Upsell/Art")
	if upArt then
		for t = pass.Tiers, 1, -1 do
			local r = pass.Premium[t]
			if r and r.Kind == "Operator" and r.Id then
				ui.SetArt(upArt, "Operator/" .. r.Id)
				break
			end
		end
	end
	for _, name in { "BuyPass", "BuyTiers" } do
		local btn = find(frame, "Rewards/Upsell/" .. name)
		local key = offers[name]
		setVisible(btn, key ~= nil)
		if btn and key then
			ui.Text(btn:FindFirstChild("Price"), "R$ " .. money(priceOf(key)))
			if s[name] then
				s[name].Disabled(not C.Live(key))
			end
		end
	end

	-- challenges
	fillChallenges(ctx, frame, "Daily")
	fillChallenges(ctx, frame, "Weekly")
	timers(ctx)
	setView(ctx, state.view)
end

local function schedule(ctx: any)
	if not state.shown or state.queued then
		return
	end
	state.queued = true
	task.defer(function()
		state.queued = false
		if state.shown then
			render(ctx)
		end
	end)
end

local function firstSelection(ctx: any)
	for _, entry in cells[ctx.variant] or {} do
		for _, track in TRACKS do
			local c = entry[track]
			local claim = c and c.cell:FindFirstChild("Claim")
			if claim and claim.Visible then
				return claim
			end
		end
	end
	local f = state.focus
	local entry = f and (cells[ctx.variant] or {})[f.tier]
	local c = entry and entry[f.track]
	return c and c.cell:FindFirstChild("Plate") or ctx.el(Page.Name, "Rewards/ClaimAll")
end

-- Page API -------------------------------------------------------------------------------------------------------

function Page.Init(ctx: any)
	for _, v in VARIANTS do
		wireStatic(ctx, v)
	end
	for _, name in WATCHED do
		ctx.onAttr(name, function()
			schedule(ctx)
		end)
	end
end

function Page.Layout(ctx: any)
	state.first = nil
	if state.shown then
		render(ctx)
	end
end

function Page.Show(ctx: any, args: any)
	state.shown = true
	state.first = nil
	if type(args) == "table" and (args.View == "Challenges" or args.View == "Rewards") then
		state.view = args.View
	end
	render(ctx)
	ctx.select(firstSelection(ctx))
	state.token += 1
	local token = state.token
	task.spawn(function()
		while state.shown and state.token == token do
			task.wait(20)
			if state.shown and state.token == token then
				timers(ctx)
			end
		end
	end)
end

function Page.Hide(_ctx: any)
	state.shown = false
	state.token += 1
	state.focus = nil
end

return Page
