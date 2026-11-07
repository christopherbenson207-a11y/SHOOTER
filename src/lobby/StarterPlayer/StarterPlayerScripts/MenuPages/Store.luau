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
--
-- 6 Nov 2026 (owner's store reference): FEATURED, GEMS and PASSES are one scrolling Feed (art: Store.py + store_feed.py)
-- - the hero, four GEMS packs, the 2X XP and 2X GEMS booster rows (live time left from the BoostXpUntil /
-- BoostGemsUntil attributes) and six PASSES banners. The GEMS and PASSES tabs scroll the Feed to their header and the
-- tab underline follows the scroll. Every Feed card pops on hover (UIScale, corner brackets snapping in, a light
-- sweep) and a granted purchase bursts out of its card (gold rays, flash, sparks: the page's hidden Fx images).
-- Feed cards stay visible while a product id is 0 (their click answers NotForSale) so the layout never jumps.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local okConfig, GameConfig = pcall(require, ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
if not okConfig then
	GameConfig = {}
end

local Kit = require(script.Parent:WaitForChild("Loadout"):WaitForChild("LoadoutKit"))
local Turntable = require(script.Parent:WaitForChild("Loadout"):WaitForChild("Turntable"))

local Page = { Name = "Store", Tab = "STORE", Overlay = false, Camera = "Loadout" }

-- 5 Nov 2026 (kid reskin): seven tabs became five. CAMOS, BEAMS and CARDS are one COSMETICS grid (in that order),
-- and the Scrip section reads GEMS on its tab (the id stays "Scrip", so go:Store:Scrip still lands there). FEATURED
-- is always shown: hiding the shop confused players (owner).
local SECTIONS = { "Featured", "Operators", "Cosmetics", "Scrip", "Passes" }
local SECTION_KIND = { Operators = { Operator = 1 }, Cosmetics = { Camo = 1, Beam = 2, Card = 3 } }
local SECTION_ALIAS = { Camos = "Cosmetics", Beams = "Cosmetics", Cards = "Cosmetics", Gems = "Scrip" }
local PASS_ATTR = { Vip = "Vip", DoubleScrip = "DoubleScrip", Beams = "Beams" }
local PASS_SECTIONS = { Featured = true, Passes = true, Pass = true, Extras = true }
-- tabs that live in the Feed, and the Feed child each one scrolls to
local FEED_TABS = { Featured = "Hero", Scrip = "GemsHead", Passes = "PassesHead" }
local GEM_KEYS = { "Scrip1", "Scrip2", "Scrip3", "Scrip4" }
local BOOST_ROWS = { Xp = { "XpBoost30", "XpBoost60", "XpBoost120" }, Gems = { "GemBoost30", "GemBoost60", "GemBoost120" } }
local FEED_PASSES = { "Vip", "DoubleScrip", "K9", "Beams", "PassPremium", "Revive5" }
-- attributes a grant changes; while a purchase is pending, a change on one of these plays its card's burst
local GRANT_ATTRS = { "Scrip", "BoostXpUntil", "BoostGemsUntil", "Vip", "DoubleScrip", "Beams", "K9", "PassPremium",
	"Tokens", "PassTier" }
local TIMER_ON = Color3.fromRGB(255, 255, 255)
local TIMER_OFF = Color3.fromRGB(160, 176, 236)

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
	pending = nil, -- {Key, Items, Card, At} after a Robux prompt, for the reveal and the burst
	timerToken = 0,
	cards = {}, -- Feed cards: {key, card, edge, ctl, scale, kind, hover, pinned}
	tab = "Featured", -- the tab underline (follows the Feed scroll)
	scrolling = false, -- a tab click is tweening the Feed
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

-- SCRIP PACKS also shows the free ways to earn Scrip (4 Nov 2026: the top bar's + must never be a dead end).
-- The numbers come from GameConfig.Scrip (what MatchServer pays) and the Night Pass free track, never typed here.
-- Type "Earn": no price plate, the price line says what you get, a tap goes to that page.
local function earnEntries()
	local pay = GameConfig.Scrip or {}
	local list = {}
	if pay.PerNight then
		table.insert(list, {
			Id = "Earn/Run",
			Type = "Earn",
			Art = "Kit/Scrip",
			KindText = "EARN GEMS",
			Name = "PLAY A RUN",
			Action = string.format("+%d/NIGHT", pay.PerNight),
			Go = "Play",
		})
	end
	local free = Kit.P and Kit.P.Pass and Kit.P.Pass.Free
	local passScrip = 0
	for _, r in (type(free) == "table" and free or {}) do
		if type(r) == "table" and r.Kind == "Scrip" then
			passScrip += r.Amount or 0
		end
	end
	if passScrip > 0 then
		table.insert(list, {
			Id = "Earn/Pass",
			Type = "Earn",
			Art = Kit.UiArt["Product/PassPremium"] and "Product/PassPremium" or "Kit/Scrip",
			KindText = "EARN GEMS",
			Name = "NIGHT PASS",
			Action = string.format("%s FREE", Kit.Money(passScrip)),
			Go = "Pass",
			Args = { View = "Rewards" },
		})
	end
	return list
end

local function premiumEntry()
	return {
		Id = "Premium",
		Type = "Premium",
		Art = Kit.UiArt["Product/Premium"] and "Product/Premium" or "Kit/Scrip",
		KindText = "ROBLOX PREMIUM",
		Name = "+10% GEMS",
	}
end

-- Is this entry already had? (owned cosmetic, owned game pass, the premium track this season, the Starter Pack)
local function owned(d, e)
	if e.Type == "Item" then
		return Kit.Available(d, e.ItemId)
	elseif e.Type == "Product" then
		local p = Kit.C.Products[e.Key]
		if e.Key == "K9" then
			-- the pass writes "Pass"; a one-run rental ("Rental") is not ownership
			return S.ctx ~= nil and S.ctx.attr("K9") == "Pass"
		elseif p.Type == "Pass" then
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
	local kinds = SECTION_KIND[section]
	if kinds then
		local ids = {}
		for itemId, it in (Kit.C and Kit.C.Items or {}) do
			if kinds[it.Kind] then
				local s = it.Source.Kind
				-- sold for Scrip, or through a live game pass, or the default beam (so it can be equipped again)
				if s == "Store" or (s == "Robux" and Kit.Live(it.Source.Key)) or (s == "Default" and it.Kind == "Beam") then
					table.insert(ids, itemId)
				elseif s == "Robux" and Kit.Available(d, itemId) then
					table.insert(ids, itemId)
				end
			end
		end
		table.sort(ids, function(a, b)
			local ka, kb = kinds[Kit.C.Items[a].Kind] or 0, kinds[Kit.C.Items[b].Kind] or 0
			if ka ~= kb then
				return ka < kb
			end
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
		for _, e in earnEntries() do
			table.insert(list, e)
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
	if e.Type == "Earn" then
		for _, plate in { "Owned", "PriceScrip", "PriceShort", "PriceRobux" } do
			Kit.Show(node:FindFirstChild(plate), false)
		end
		Kit.Text(node:FindFirstChild("PriceText"), e.Action)
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
local scrollFeedTo -- forward

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

-- itemId: what they could not afford (the server remembers it for the HOME offer strip after the next match)
local function getScrip(need, itemId)
	S.need = need
	setSection("Scrip")
	if type(itemId) == "string" then
		task.spawn(S.ctx.store, "Want", { ItemId = itemId })
	end
end

-- What BUY (or a second tile click) does for this entry.
local function act(e)
	local ctx = S.ctx
	local d = Kit.Data(ctx)
	if e.Type == "Earn" then
		ctx.sound("Click")
		ctx.go(e.Go, e.Args)
		return
	end
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
			getScrip(e.Scrip - d.Scrip, e.ItemId)
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

-- feed -----------------------------------------------------------------------------------------------------------------
-- Every Feed card: Base (baked art), PricePill + PriceText, Owned (passes), Shine and Brackets (hidden effect layers)
-- and Edge (the click / hover button).

local POP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local EASE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function tween(inst, info, props)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function cardSize(c)
	return c.card.Size.X.Offset, c.card.Size.Y.Offset
end

local function showBrackets(c, on, snap)
	local br = c.card:FindFirstChild("Brackets")
	if not br then
		return
	end
	local w, h = cardSize(c)
	if on then
		if not br.Visible or snap then
			br.Position = UDim2.fromOffset(-22, -22)
			br.Size = UDim2.fromOffset(w + 44, h + 44)
			br.ImageTransparency = 1
		end
		br.Visible = true
		tween(br, EASE, { Position = UDim2.fromOffset(-8, -8), Size = UDim2.fromOffset(w + 16, h + 16), ImageTransparency = 0 })
	elseif br.Visible then
		local t = tween(br, EASE, { ImageTransparency = 1 })
		t.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and not (c.hover or c.pinned) then
				br.Visible = false
			end
		end)
	end
end

local function sweep(c)
	local base = c.card:FindFirstChild("Base")
	local sh = base and base:FindFirstChild("Shine")
	if not sh then
		return
	end
	local w = cardSize(c)
	sh.Visible = true
	sh.ImageTransparency = 0.15
	sh.Position = UDim2.fromOffset(-sh.Size.X.Offset - 10, 0)
	local t = tween(sh, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Position = UDim2.fromOffset(w + 10, 0) })
	t.Completed:Once(function()
		sh.Visible = false
	end)
end

local function setHover(c, on)
	if c.hover == on then
		return
	end
	c.hover = on
	c.card.ZIndex = if on then 5 else 1
	tween(c.scale, POP, { Scale = if on then 1.05 else 1 })
	showBrackets(c, on or c.pinned)
	if on then
		sweep(c)
		S.ctx.sound("Hover")
	end
end

-- The purchase burst: gold rays turning out of the card, a flash and sparks flying off; the card pops.
local function celebrate(c)
	local fx = el("Fx")
	if not (fx and c and c.card.Parent) then
		return
	end
	local w, h = cardSize(c)
	local cx, cy = w / 2, h / 2
	local made = {}
	local function clone(name, z)
		local src = fx:FindFirstChild(name)
		if not src then
			return nil
		end
		local im = src:Clone()
		im.AnchorPoint = Vector2.new(0.5, 0.5)
		im.Position = UDim2.fromOffset(cx, cy)
		im.Visible = true
		im.ZIndex = z
		im.Parent = c.card
		table.insert(made, im)
		return im
	end
	local burst = clone("Burst", 20)
	if burst then
		local s = math.max(w, h) * 1.9
		burst.Size = UDim2.fromOffset(s * 0.2, s * 0.2)
		burst.ImageTransparency = 0
		tween(burst, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(s, s), Rotation = 70, ImageTransparency = 1 })
	end
	local flash = clone("Flash", 21)
	if flash then
		flash.Size = UDim2.fromOffset(w * 1.3, w * 1.3)
		flash.ImageTransparency = 0.1
		tween(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 1 })
	end
	for i = 1, 10 do
		local sp = clone("Spark", 22)
		if sp then
			-- fwjelaa-ignore: paid-random-no-policy (cosmetic spark angles only; nothing paid is random here)
			local a = (i / 10) * math.pi * 2 + math.random() * 0.5
			local r = math.max(w, h) * (0.55 + math.random() * 0.35)
			local sz = 18 + math.random() * 22
			sp.Size = UDim2.fromOffset(sz, sz)
			tween(sp, TweenInfo.new(0.7 + math.random() * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(cx + math.cos(a) * r, cy + math.sin(a) * r),
				Size = UDim2.fromOffset(4, 4),
				Rotation = math.random(-180, 180),
				ImageTransparency = 1,
			})
		end
	end
	c.scale.Scale = 1.14
	tween(c.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = if c.hover then 1.05 else 1 })
	sweep(c)
	S.ctx.sound("LevelUp")
	task.delay(1.3, function()
		for _, im in made do
			im:Destroy()
		end
	end)
end

local function feedEntry(key)
	return productEntry(key)
end

-- price text or OWNED on one card
local function renderCard(d, c)
	local e = feedEntry(c.key)
	if not e then
		return
	end
	local has = owned(d, e)
	local node = c.card
	Kit.Show(node:FindFirstChild("Owned"), has)
	Kit.Show(node:FindFirstChild("PricePill"), not has)
	local label = node:FindFirstChild("PriceText")
	Kit.Show(label, not has)
	if not has then
		local price = Kit.RobuxPrice(c.key, function(live)
			if label and label.Parent then
				Kit.Text(label, Kit.Money(live))
			end
		end)
		Kit.Text(label, Kit.Money(price))
	end
	if c.ctl then
		c.ctl.Disabled(false)
	end
end

local function renderFeed(d)
	local pack = S.need and Kit.C and Kit.C.PackFor(S.need) or nil
	for _, c in S.cards do
		renderCard(d, c)
		local pin = pack ~= nil and c.key == pack
		if pin ~= (c.pinned == true) then
			c.pinned = pin
			showBrackets(c, pin or c.hover, true)
		end
	end
end

local function clickCard(c)
	S.need = nil
	local e = feedEntry(c.key)
	if not e then
		return
	end
	local d = Kit.Data(S.ctx)
	if owned(d, e) then
		S.ctx.sound("Error")
		return
	end
	preview(e)
	act(e)
	if S.pending then
		S.pending.Card = c
		S.pending.At = os.clock()
	end
end

-- Tab underline follows the Feed: the last header scrolled past the top third of the Feed wins.
local function followScroll()
	local feed = el("Feed")
	if S.scrolling or not (feed and feed:IsA("ScrollingFrame")) or not FEED_TABS[S.section] then
		return
	end
	local top = feed.AbsolutePosition.Y + feed.AbsoluteSize.Y * 0.3
	local pick = "Featured"
	for _, sec in { "Scrip", "Passes" } do
		-- phones have no GemsHead (the packs sit beside the hero): the boosters count as GEMS there
		local h = feed:FindFirstChild(FEED_TABS[sec]) or (sec == "Scrip" and feed:FindFirstChild("XpBoostHead"))
		if h and h.AbsolutePosition.Y <= top then
			pick = sec
		end
	end
	if pick ~= S.tab then
		S.tab = pick
		S.section = pick
		for _, sec in SECTIONS do
			local ctl = S.tabs[sec]
			if ctl then
				ctl.Selected(sec == pick)
			end
		end
	end
end

scrollFeedTo = function(sec, instant)
	local feed = el("Feed")
	if not (feed and feed:IsA("ScrollingFrame")) then
		return
	end
	local target = feed:FindFirstChild(FEED_TABS[sec] or "Hero")
	-- on phones the GEMS packs sit beside the hero (no GemsHead): the top of the Feed shows them
	local y = 0
	if target and sec ~= "Featured" then
		y = math.max(0, target.AbsolutePosition.Y - feed.AbsolutePosition.Y + feed.CanvasPosition.Y - 8)
	end
	local maxY = math.max(0, feed.AbsoluteCanvasSize.Y - feed.AbsoluteWindowSize.Y)
	local goal = Vector2.new(0, math.min(y, maxY))
	if instant then
		feed.CanvasPosition = goal
		return
	end
	S.scrolling = true
	local t = tween(feed, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = goal })
	t.Completed:Once(function()
		S.scrolling = false
	end)
end

local function wireFeed()
	for _, c in S.cards do
		if c.scale and c.scale.Parent then
			c.scale.Scale = 1
		end
	end
	table.clear(S.cards)
	local ctx = S.ctx
	local feed = el("Feed")
	if not feed then
		return
	end
	local function add(path, key, kind)
		local card = Kit.Child(feed, path)
		local edge = card and card:FindFirstChild("Edge")
		if not (card and edge) then
			return
		end
		local scale = card:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = card
		-- the light sweep is clipped by the card art
		local base = card:FindFirstChild("Base")
		local shine = card:FindFirstChild("Shine") or (base and base:FindFirstChild("Shine"))
		if base and shine then
			shine.Parent = base
			shine.Visible = false
			base.ClipsDescendants = true
		end
		local c = { key = key, card = card, edge = edge, scale = scale, kind = kind, hover = false, pinned = false }
		c.ctl = Kit.Wire(S.reg, ctx.ui, edge, function()
			clickCard(c)
		end, { Silent = true })
		for _, sig in { edge.MouseEnter, edge.SelectionGained } do
			table.insert(S.reg, sig:Connect(function()
				setHover(c, true)
			end))
		end
		for _, sig in { edge.MouseLeave, edge.SelectionLost } do
			table.insert(S.reg, sig:Connect(function()
				setHover(c, false)
			end))
		end
		table.insert(S.cards, c)
	end
	for _, key in GEM_KEYS do
		add("Gems/" .. key, key, "Gem")
	end
	for kind, keys in BOOST_ROWS do
		for _, key in keys do
			add("Boost" .. kind .. "/" .. key, key, "Boost")
		end
	end
	for _, key in FEED_PASSES do
		add("Passes/" .. key, key, "Pass")
	end
	if feed:IsA("ScrollingFrame") then
		table.insert(S.reg, feed:GetPropertyChangedSignal("CanvasPosition"):Connect(followScroll))
	end
end

-- a pending Robux purchase: the first grant attribute that changes plays its card's burst
local function onGrant()
	local p = S.pending
	if not (p and p.Card and S.visible) then
		return
	end
	if os.clock() - (p.At or 0) > 120 then
		return
	end
	local c = p.Card
	p.Card = nil
	celebrate(c)
end

-- hero -----------------------------------------------------------------------------------------------------------------

local function renderHero(d, e)
	S.heroEntry = e
	local hero = el("Feed/Hero")
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
		table.insert(parts, math.min(2, #parts + 1), Kit.Money(p.Scrip) .. " GEMS")
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
	if FEED_TABS[S.section] and e and e.Type == "Product" and e.Key == "StarterPack" then
		local left = d.StarterDeadline - os.time()
		Kit.Text(el("Feed/Hero/Timer/TimerText"), clock(left))
		if left <= 0 then
			-- the real deadline passed: the hero goes back to the weekly operator
			S.cat = nil
			render()
		end
	end
	-- booster rows: time left on each running booster (00:00:00 when none runs)
	for kind in BOOST_ROWS do
		local label = el("Feed/Boost" .. kind .. "/TimerText")
		if label then
			local left = (tonumber(S.ctx.attr("Boost" .. kind .. "Until")) or 0) - os.time()
			Kit.Text(label, clock(left))
			label.TextColor3 = if left > 0 then TIMER_ON else TIMER_OFF
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
	Kit.Show(el("TabFeatured"), true)
	for _, sec in SECTIONS do
		local c = S.tabs[sec]
		if c then
			c.Selected(sec == (if FEED_TABS[S.section] then S.tab else S.section))
		end
		Kit.Show(el("Tab" .. sec .. "/New"), sectionNew(d, sec))
	end

	local isFeatured = FEED_TABS[S.section] ~= nil
	Kit.Show(el("Feed"), isFeatured)
	Kit.Show(el("Items"), not isFeatured)
	clearTiles()
	if isFeatured then
		local hero = featured(d)
		renderHero(d, hero)
		renderFeed(d)
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
		local first = isFeatured and el("Feed/Hero/Buy") or (S.tiles[1] and S.tiles[1].clone:FindFirstChild("Edge"))
		ctx.select(first)
	end
end

setSection = function(sec)
	sec = SECTION_ALIAS[sec] or sec
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
	if FEED_TABS[sec] then
		S.tab = sec
	end
	render(true)
	if FEED_TABS[sec] then
		scrollFeedTo(sec)
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
	S.heroBuy = Kit.Wire(S.reg, ctx.ui, el("Feed/Hero/Buy"), function()
		if S.heroEntry then
			act(S.heroEntry)
		end
	end)
	S.heroScrip = Kit.Wire(S.reg, ctx.ui, el("Feed/Hero/GetScrip"), function()
		local e = S.heroEntry
		local d = Kit.Data(ctx)
		getScrip(e and e.Scrip and math.max(1, e.Scrip - d.Scrip) or nil, e and e.ItemId)
	end)
	wireFeed()
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
	for _, name in GRANT_ATTRS do
		ctx.onAttr(name, onGrant)
	end
	for _, name in { "K9", "BoostXpUntil", "BoostGemsUntil" } do
		ctx.onAttr(name, refreshIfShown)
	end
	-- a cancelled prompt drops the pending burst
	local function cancelled(_, _, bought)
		if not bought and S.pending then
			S.pending.Card = nil
		end
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(cancelled)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(cancelled)
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
		for s, kinds in SECTION_KIND do
			if it and kinds[it.Kind] then
				sec = s
			end
		end
	end
	sec = SECTION_ALIAS[sec] or sec
	S.section = table.find(SECTIONS, sec) and sec or "Featured"
	if FEED_TABS[S.section] then
		S.tab = S.section
		task.defer(scrollFeedTo, S.section, true)
	end
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
		if FEED_TABS[S.section] then
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
