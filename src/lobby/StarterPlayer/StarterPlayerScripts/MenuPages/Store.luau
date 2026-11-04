--!nonstrict
-- MenuPages.Store (FRONT-B, 4 Nov 2026): the STORE page. Sections FEATURED, OPERATORS, CAMOS, BEAMS, CARDS,
-- SCRIP PACKS and PASSES. FEATURED is the hero and three tiles from Store "Catalogue" (the Starter Pack is the hero
-- while its real 48 h deadline runs); every other section is a grid of ItemTile clones (Ui.Fill). Every tile shows one
-- price plate (Scrip, Scrip short, Robux) or OWNED, and previews on the stage when selected.
-- Selling rules: a Scrip item opens the Confirm overlay; a Robux item calls Store "Product" at once (the Roblox prompt
-- is the confirm); short of Scrip, BUY becomes GET SCRIP and jumps to SCRIP PACKS with the smallest pack that covers
-- the gap highlighted. No sale badges, no crossed-out prices, the only timer is the Starter Pack's real deadline (and
-- the time left on today's tiles). Products whose id is 0 are hidden. Show args: {Section, Item, Need} or a section
-- name. The client never opens this page by itself.

local MarketplaceService = game:GetService("MarketplaceService")

local Kit = require(script.Parent:WaitForChild("Loadout"):WaitForChild("LoadoutKit"))
local Turntable = require(script.Parent:WaitForChild("Loadout"):WaitForChild("Turntable"))

local Page = { Name = "Store", Tab = "STORE", Overlay = false, Camera = "Loadout" }

local SECTIONS = { "Featured", "Operators", "Camos", "Beams", "Cards", "Scrip", "Passes" }
local SECTION_KIND = { Operators = "Operator", Camos = "Camo", Beams = "Beam", Cards = "Card" }
local PASS_ATTR = { Vip = "Vip", DoubleScrip = "DoubleScrip", Beams = "Beams" }
local PASS_SECTIONS = { Featured = true, Passes = true, Pass = true, Extras = true }

local S = {
	ctx = nil,
	reg = {}, -- page buttons
	tabs = {}, -- section -> controller
	tiles = {}, -- {ctl, entry, clone}
	heroBuy = nil,
	heroScrip = nil,
	section = "Featured",
	selected = nil, -- entry id of the selected tile
	need = nil, -- Scrip short, while SCRIP PACKS shows a highlighted pack
	cat = nil, -- last Store "Catalogue" reply
	catAt = 0,
	visible = false,
	heroEntry = nil,
	pending = nil, -- {Key, Items} after a Robux prompt, for the reveal
	timerToken = 0,
}

local function el(path)
	return S.ctx.el(Page.Name, path)
end

-- entries --------------------------------------------------------------------------------------------------------------
-- entry = {Id, Type = "Item" | "Product" | "Premium", ItemId, Key, Art, KindText, Name, Scrip, Robux, Preview}

local function itemEntry(itemId)
	local it = Kit.Item(itemId)
	if not it then
		return nil
	end
	local e = {
		Id = itemId,
		Type = "Item",
		ItemId = itemId,
		Art = it.Art or itemId,
		KindText = Kit.KIND_TEXT[it.Kind] or Kit.Upper(it.Kind),
		Name = it.Name,
		Kind = it.Kind,
		Bare = it.Id,
		Preview = { it.Kind, it.Id },
	}
	if it.Source.Kind == "Store" then
		e.Scrip = it.Source.Scrip
	elseif it.Source.Kind == "Robux" then
		e.Key = it.Source.Key
	end
	return e
end

local PRODUCT_PREVIEW = {
	StarterPack = { "Operator", "Pathfinder" },
	Vip = { "Beam", "Gold" },
	Beams = { "Beam", "Red" },
}

local function productEntry(key)
	local p = Kit.C and Kit.C.Products[key]
	if not p then
		return nil
	end
	return {
		Id = "Product/" .. key,
		Type = "Product",
		Key = key,
		Art = p.Art,
		KindText = Kit.SECTION_TEXT[p.Section] or "",
		Name = p.Name,
		Robux = p.Robux,
		Preview = PRODUCT_PREVIEW[key],
	}
end

local function premiumEntry()
	return {
		Id = "Premium",
		Type = "Premium",
		Art = Kit.UiArt["Product/Premium"] and "Product/Premium" or "Kit/Scrip",
		KindText = "ROBLOX PREMIUM",
		Name = "+10% SCRIP",
	}
end

-- Is this entry already had? (owned cosmetic, owned game pass, the premium track this season, the Starter Pack)
local function owned(d, e)
	if e.Type == "Item" then
		return Kit.Available(d, e.ItemId)
	elseif e.Type == "Product" then
		local p = Kit.C.Products[e.Key]
		if p.Type == "Pass" then
			return d[PASS_ATTR[e.Key] or e.Key] == true
		elseif e.Key == "PassPremium" or e.Key == "PassPremium10" then
			return d.PassPremium
		elseif e.Key == "StarterPack" then
			return d.Owned.StarterPack == true
		elseif e.Key == "PassTier1" then
			return d.PassTier >= (Kit.P and Kit.P.Pass and Kit.P.Pass.Tiers or 30)
		end
		return false
	elseif e.Type == "Premium" then
		return d.Premium
	end
	return false
end

local function equipped(d, e)
	if e.Type ~= "Item" then
		return false
	end
	if e.Kind == "Operator" then
		return d.Operator == e.Bare
	elseif e.Kind == "Beam" then
		return d.Beam == e.Bare
	elseif e.Kind == "Card" then
		return d.Card == e.Bare
	elseif e.Kind == "Camo" then
		local lo = Kit.Loadout(d)
		return (d.Camos[lo.Primary] or "Gunmetal") == e.Bare
	end
	return false
end

local function sectionEntries(d, section)
	local list = {}
	local kind = SECTION_KIND[section]
	if kind then
		local ids = {}
		for itemId, it in (Kit.C and Kit.C.Items or {}) do
			if it.Kind == kind then
				local s = it.Source.Kind
				-- sold for Scrip, or through a live game pass, or the default beam (so it can be equipped again)
				if s == "Store" or (s == "Robux" and Kit.Live(it.Source.Key)) or (s == "Default" and kind == "Beam") then
					table.insert(ids, itemId)
				elseif s == "Robux" and Kit.Available(d, itemId) then
					table.insert(ids, itemId)
				end
			end
		end
		table.sort(ids, function(a, b)
			local pa, pb = Kit.C.Price(a) or 0, Kit.C.Price(b) or 0
			if pa ~= pb then
				return pa < pb
			end
			return a < b
		end)
		for _, id in ids do
			table.insert(list, itemEntry(id))
		end
	elseif section == "Scrip" then
		if not d.Premium then
			table.insert(list, premiumEntry())
		end
		for _, key in (Kit.C and Kit.C.ScripPacks or {}) do
			if Kit.Live(key) then
				table.insert(list, productEntry(key))
			end
		end
	elseif section == "Passes" then
		local keys = {}
		for key, p in (Kit.C and Kit.C.Products or {}) do
			if PASS_SECTIONS[p.Section] and Kit.Live(key) then
				table.insert(keys, key)
			end
		end
		table.sort(keys, function(a, b)
			local pa, pb = Kit.C.Products[a], Kit.C.Products[b]
			if pa.Section ~= pb.Section then
				return pa.Section < pb.Section
			end
			return pa.Robux < pb.Robux
		end)
		local tiersLeft = (Kit.P and Kit.P.Pass and Kit.P.Pass.Tiers or 30) - d.PassTier
		for _, key in keys do
			local p = Kit.C.Products[key]
			local hide = (p.MinLeft and tiersLeft < p.MinLeft) or (key == "StarterPack" and d.Owned.StarterPack)
			if not hide then
				table.insert(list, productEntry(key))
			end
		end
	end
	return list
end

-- the Featured hero and tiles from the catalogue reply (or today's rotation computed here until it arrives)
local function featured(d)
	local cat = S.cat
	if not cat and Kit.C and Kit.P then
		cat = Kit.C.Rotation(Kit.P.Day())
	end
	cat = cat or { Tiles = {} }
	local hero
	if cat.Hero == "Product/StarterPack" then
		if Kit.Live("StarterPack") and not d.Owned.StarterPack and os.time() < d.StarterDeadline then
			hero = productEntry("StarterPack")
		elseif Kit.C then
			hero = itemEntry(Kit.C.Rotation(Kit.P.Day()).Hero)
		end
	elseif cat.Hero then
		hero = itemEntry(cat.Hero)
	end
	local tiles = {}
	for _, id in cat.Tiles or {} do
		local e = itemEntry(id)
		if e then
			table.insert(tiles, e)
		end
	end
	return hero, tiles
end

-- price plates ---------------------------------------------------------------------------------------------------------

-- Show exactly one of PriceScrip / PriceShort / PriceRobux, or Owned with no price text.
local function applyPrice(node, d, e)
	if not node then
		return
	end
	local has = owned(d, e)
	local scrip = e.Scrip
	local robux = (e.Type == "Product" or (e.Type == "Item" and e.Key)) and true or false
	Kit.Show(node:FindFirstChild("Owned"), has)
	Kit.Show(node:FindFirstChild("PriceScrip"), not has and scrip ~= nil and d.Scrip >= scrip)
	Kit.Show(node:FindFirstChild("PriceShort"), not has and scrip ~= nil and d.Scrip < scrip)
	Kit.Show(node:FindFirstChild("PriceRobux"), not has and scrip == nil and robux)
	local label = node:FindFirstChild("PriceText")
	if has or e.Type == "Premium" then
		Kit.Text(label, "")
	elseif scrip then
		Kit.Text(label, Kit.Money(scrip))
	elseif robux then
		local key = e.Key
		local price = Kit.RobuxPrice(key, function(live)
			if label and label.Parent then
				Kit.Text(label, Kit.Money(live))
			end
		end)
		Kit.Text(label, Kit.Money(price))
	else
		Kit.Text(label, "")
	end
end

local function fillNode(node, d, e)
	local ui = S.ctx.ui
	Kit.Art(ui, node:FindFirstChild("Art"), e.Art)
	Kit.Text(node:FindFirstChild("Kind"), e.KindText)
	Kit.Text(node:FindFirstChild("Name"), e.Name)
	applyPrice(node, d, e)
	local isNew = e.Type == "Item" and owned(d, e) and not Kit.IsSeen(d, e.ItemId)
		and Kit.Item(e.ItemId).Source.Kind ~= "Default"
	Kit.Show(node:FindFirstChild("New"), isNew)
end

-- actions --------------------------------------------------------------------------------------------------------------

local setSection -- forward
local render -- forward

local function preview(e)
	local model
	if e and e.Preview then
		model = Kit.Stage(S.ctx, "Preview", e.Preview[1], e.Preview[2])
	else
		Kit.Stage(S.ctx, "Reset")
	end
	Turntable.Target(model)
end

local function equipEntry(e)
	local ctx = S.ctx
	local res
	if e.Kind == "Camo" then
		local lo = Kit.Loadout(Kit.Data(ctx))
		res = ctx.store("Camo", { Gun = lo.Primary, Id = e.Bare })
	elseif e.Kind == "Operator" or e.Kind == "Beam" or e.Kind == "Card" then
		res = ctx.store(e.Kind, { Id = e.Bare })
	end
	if res and not res.Ok then
		ctx.sound("Error")
	end
end

local function getScrip(need)
	S.need = need
	setSection("Scrip")
end

-- What BUY (or a second tile click) does for this entry.
local function act(e)
	local ctx = S.ctx
	local d = Kit.Data(ctx)
	if e.Type == "Premium" then
		if not d.Premium then
			pcall(MarketplaceService.PromptPremiumPurchase, MarketplaceService, ctx.player)
		end
		return
	end
	if owned(d, e) then
		if e.Type == "Item" and not equipped(d, e) then
			equipEntry(e)
		end
		return
	end
	if e.Scrip then
		if d.Scrip < e.Scrip then
			getScrip(e.Scrip - d.Scrip)
			return
		end
		ctx.open("Confirm", { ItemId = e.ItemId })
		return
	end
	local key = e.Key
	if key then
		local p = Kit.C.Products[key]
		S.pending = { Key = key, Items = (p and p.Items) or (e.ItemId and { e.ItemId }) or {} }
		local res = ctx.store("Product", { Key = key })
		if not res.Ok then
			S.pending = nil
			ctx.sound("Error")
		end
	end
end

local function markTileSelected()
	local pack = S.section == "Scrip" and S.need and Kit.C and Kit.C.PackFor(S.need) or nil
	for _, t in S.tiles do
		if t.ctl then
			local hi = t.entry.Id == S.selected
			if pack then
				hi = t.entry.Key == pack
			end
			t.ctl.Selected(hi)
		end
	end
end

local function clickTile(t)
	local e = t.entry
	local d = Kit.Data(S.ctx)
	if e.Type == "Item" and not Kit.IsSeen(d, e.ItemId) and owned(d, e) then
		Kit.MarkSeen(S.ctx, { e.ItemId })
		Kit.Show(t.clone:FindFirstChild("New"), false)
	end
	-- products and Premium act on the first click (the Roblox prompt is the confirm); cosmetics preview first
	if e.Type ~= "Item" or e.Key then
		S.selected = e.Id
		S.need = nil
		markTileSelected()
		preview(e)
		act(e)
		return
	end
	if S.selected ~= e.Id then
		S.selected = e.Id
		markTileSelected()
		preview(e)
		if owned(d, e) and not equipped(d, e) then
			equipEntry(e)
		end
		return
	end
	act(e)
end

-- hero -----------------------------------------------------------------------------------------------------------------

local function renderHero(d, e)
	S.heroEntry = e
	local hero = el("Hero")
	if not hero then
		return
	end
	if not e then
		Kit.Show(hero, false)
		return
	end
	Kit.Show(hero, true)
	fillNode(hero, d, e)
	local gives = e.Name
	if e.Type == "Product" and e.Key == "StarterPack" then
		local p = Kit.C.Products.StarterPack
		local parts = {}
		for _, itemId in p.Items or {} do
			local it = Kit.Item(itemId)
			if it then
				table.insert(parts, it.Kind == "Card" and (it.Name .. " CARD") or it.Name)
			end
		end
		table.insert(parts, math.min(2, #parts + 1), Kit.Money(p.Scrip) .. " SCRIP")
		table.insert(parts, math.min(3, #parts + 1), tostring(p.Tokens) .. " REVIVE TOKENS")
		gives = table.concat(parts, ", ")
		Kit.Text(hero:FindFirstChild("Kind"), "STARTER PACK")
		Kit.Text(hero:FindFirstChild("Name"), "FIRST NIGHT")
	elseif e.Type == "Item" then
		local it = Kit.Item(e.ItemId)
		if it.Kind == "Operator" then
			gives = "OPERATOR SKIN"
		elseif it.Kind == "Camo" then
			gives = "CAMO FOR EVERY GUN"
		elseif it.Kind == "Card" then
			gives = "CALLING CARD"
		elseif it.Kind == "Beam" then
			gives = "FLASHLIGHT COLOUR"
		end
	end
	Kit.Text(hero:FindFirstChild("Gives"), gives)
	local has = owned(d, e)
	local short = e.Scrip ~= nil and not has and d.Scrip < e.Scrip
	Kit.Show(hero:FindFirstChild("GetScrip"), short)
	Kit.Show(hero:FindFirstChild("Buy"), not short)
	if S.heroBuy then
		S.heroBuy.Disabled(has and not (e.Type == "Item" and not equipped(d, e)))
	end
	local starter = e.Type == "Product" and e.Key == "StarterPack" and os.time() < d.StarterDeadline
	Kit.Show(hero:FindFirstChild("Timer"), starter)
end

local function clock(sec)
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function tickTimers()
	local d = Kit.Data(S.ctx)
	local e = S.heroEntry
	if S.section == "Featured" and e and e.Type == "Product" and e.Key == "StarterPack" then
		local left = d.StarterDeadline - os.time()
		Kit.Text(el("Hero/Timer/TimerText"), clock(left))
		if left <= 0 then
			-- the real deadline passed: the hero goes back to the weekly operator
			S.cat = nil
			render()
		end
	end
	local ends = S.cat and S.cat.DayEnds
	if not ends and Kit.P and Kit.P.DayEnds then
		ends = Kit.P.DayEnds(Kit.P.Day())
	end
	if ends then
		local left = math.max(0, ends - os.time())
		Kit.Text(el("Rotation"), string.format("%dH %02dM", left // 3600, (left % 3600) // 60))
		if left <= 0 and S.cat then
			S.cat = nil
			render()
		end
	end
end

local function startTimers()
	S.timerToken += 1
	local token = S.timerToken
	task.spawn(function()
		while S.visible and token == S.timerToken do
			tickTimers()
			task.wait(1)
		end
	end)
end

-- render ---------------------------------------------------------------------------------------------------------------

local function clearTiles()
	for _, t in S.tiles do
		if t.ctl then
			t.ctl.Destroy()
		end
	end
	table.clear(S.tiles)
end

local function fillList(list, entries, d)
	S.ctx.ui.Fill(list, entries, function(clone, e)
		fillNode(clone, d, e)
		local t = { entry = e, clone = clone }
		local edge = clone:FindFirstChild("Edge")
		if edge and edge:IsA("GuiButton") then
			t.ctl = S.ctx.ui.Button(edge, function()
				clickTile(t)
			end)
		end
		table.insert(S.tiles, t)
	end)
end

local function sectionNew(d, section)
	if not SECTION_KIND[section] then
		return false
	end
	for _, e in sectionEntries(d, section) do
		if e.Type == "Item" and owned(d, e) and not Kit.IsSeen(d, e.ItemId) and Kit.Item(e.ItemId).Source.Kind ~= "Default" then
			return true
		end
	end
	return false
end

render = function(fromShow)
	local ctx = S.ctx
	if not (ctx and ctx.frame(Page.Name)) then
		return
	end
	local d = Kit.Data(ctx)
	-- FEATURED only once the player may be sold to (first escape or level 3, MENU-PLAN 9.3)
	local selling
	if S.cat and S.cat.Selling ~= nil then
		selling = S.cat.Selling == true
	else
		selling = d.Escaped or d.Level >= 3
	end
	Kit.Show(el("TabFeatured"), selling)
	if S.section == "Featured" and not selling then
		S.section = "Operators"
	end
	for _, sec in SECTIONS do
		local c = S.tabs[sec]
		if c then
			c.Selected(sec == S.section)
		end
		Kit.Show(el("Tab" .. sec .. "/New"), sectionNew(d, sec))
	end

	local isFeatured = S.section == "Featured"
	Kit.Show(el("Tiles"), isFeatured)
	Kit.Show(el("TodayHeader"), isFeatured)
	Kit.Show(el("Rotation"), isFeatured)
	Kit.Show(el("Items"), not isFeatured)
	clearTiles()
	if isFeatured then
		local hero, tiles = featured(d)
		renderHero(d, hero)
		fillList(el("Tiles"), tiles, d)
	else
		renderHero(d, nil)
		local items = el("Items")
		fillList(items, sectionEntries(d, S.section), d)
		if fromShow and items and items:IsA("ScrollingFrame") then
			items.CanvasPosition = Vector2.zero
		end
	end
	markTileSelected()
	if fromShow and ctx.select then
		local first = isFeatured and el("Hero/Buy") or (S.tiles[1] and S.tiles[1].clone:FindFirstChild("Edge"))
		ctx.select(first)
	end
end

setSection = function(sec)
	if not table.find(SECTIONS, sec) then
		return
	end
	if sec ~= "Scrip" then
		S.need = nil
	end
	if S.section ~= sec then
		S.selected = nil
	end
	S.section = sec
	render(true)
	if sec == "Featured" then
		preview(S.heroEntry)
	elseif not S.selected then
		Kit.Stage(S.ctx, "Reset")
	end
end

local function fetchCatalogue()
	task.spawn(function()
		local res = S.ctx.store("Catalogue")
		-- a reply without tiles keeps the client rotation
		if res and res.Ok and type(res.Tiles) == "table" then
			S.cat = res
			S.catAt = os.time()
			if S.visible then
				render()
			end
		end
	end)
end

-- wiring ---------------------------------------------------------------------------------------------------------------

local function wire()
	Kit.Clear(S.reg)
	table.clear(S.tabs)
	local ctx = S.ctx
	for _, sec in SECTIONS do
		S.tabs[sec] = Kit.Wire(S.reg, ctx.ui, el("Tab" .. sec), function()
			if S.section ~= sec then
				ctx.sound("Tab")
			end
			setSection(sec)
		end, { Silent = true })
	end
	S.heroBuy = Kit.Wire(S.reg, ctx.ui, el("Hero/Buy"), function()
		if S.heroEntry then
			act(S.heroEntry)
		end
	end)
	S.heroScrip = Kit.Wire(S.reg, ctx.ui, el("Hero/GetScrip"), function()
		local e = S.heroEntry
		local d = Kit.Data(ctx)
		getScrip(e and e.Scrip and math.max(1, e.Scrip - d.Scrip) or nil)
	end)
end

-- a reveal for things a Robux purchase grants (the Starter Pack's operator): it plays when Owned changes
local function onOwned()
	local p = S.pending
	if not p then
		return
	end
	local d = Kit.Data(S.ctx)
	for _, itemId in p.Items do
		if d.Owned[itemId] then
			S.pending = nil
			S.ctx.open("Confirm", { Reveal = itemId })
			return
		end
	end
end

local function refreshIfShown()
	if S.visible then
		render()
	end
end

-- page API -------------------------------------------------------------------------------------------------------------

function Page.Init(ctx)
	S.ctx = ctx
	wire()
	for _, name in { "Scrip", "Owned", "Operator", "Beam", "Card", "Camos", "Seen", "Vip", "DoubleScrip", "Beams",
		"PassPremium", "PassTier", "Premium", "StarterDeadline", "Level", "Escaped" } do
		ctx.onAttr(name, refreshIfShown)
	end
	ctx.onAttr("Owned", onOwned)
end

function Page.Layout(ctx)
	S.ctx = ctx
	wire()
	if S.visible then
		render(true)
	end
end

function Page.Show(ctx, args)
	S.ctx = ctx
	if type(args) == "string" then
		args = { Section = args }
	end
	args = type(args) == "table" and args or {}
	S.visible = true
	ctx.menu("Status", "STORE")
	if not S.cat or os.time() - S.catAt > 300 then
		fetchCatalogue()
	end
	S.need = tonumber(args.Need)
	S.selected = nil
	local sec = args.Section
	if not sec and args.Item then
		local it = Kit.Item(args.Item)
		for s, kind in SECTION_KIND do
			if it and it.Kind == kind then
				sec = s
			end
		end
	end
	S.section = table.find(SECTIONS, sec) and sec or "Featured"
	if args.Item then
		local id = tostring(args.Item)
		if not string.find(id, "/", 1, true) then
			id = "Product/" .. id
		end
		S.selected = id
	end
	render(true)
	Turntable.Enable(ctx)
	local shown = false
	if S.selected then
		for _, t in S.tiles do
			if t.entry.Id == S.selected then
				preview(t.entry)
				shown = true
			end
		end
	end
	if not shown then
		if S.section == "Featured" then
			preview(S.heroEntry)
		else
			Kit.Stage(ctx, "Reset")
		end
	end
	startTimers()
end

function Page.Hide(ctx)
	S.visible = false
	S.timerToken += 1
	Turntable.Disable()
	task.defer(function()
		if ctx.current ~= "Store" then
			Kit.Stage(ctx, "Reset")
		end
		local cur = ctx.current
		if cur ~= "Loadout" and cur ~= "Picker" and cur ~= "Store" then
			ctx.menu("Status", "IDLE")
		end
	end)
end

-- for the static preview and tests
Page._S = S
Page._sectionEntries = sectionEntries
Page._owned = owned
Page._render = function()
	render(true)
end
Page._click = function(index)
	local t = S.tiles[index]
	if t then
		clickTile(t)
	end
end
Page._act = function(e)
	act(e or S.heroEntry)
end
Page._section = function(sec)
	setSection(sec)
end

return Page
