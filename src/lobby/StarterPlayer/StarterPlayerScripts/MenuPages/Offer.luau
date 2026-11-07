-- Offer strip (6 Nov 2026): one Robux offer under DEPLOY on HOME, picked by the server from the player's profile
-- (ServerStorage.Modules.Offers through Store "Offers"). Art: horror-shooter/menu/art/screens/Offer.py.
--   Panel { Plate, ArtBase, Art, Title, Line, Buy { Price }, Hide }   Tab (the ">" left while it is tucked away)
-- It asks the server each time HOME comes up; the server answers at most once per match, so asking is cheap. The
-- strip stays for the rest of the visit (on every return to HOME) until it is bought or tucked away with "<"; the
-- ">" tab brings a tucked strip back. Overlays close on every page change (Router), so it only ever shows on HOME.
-- Prices are live (GetProductInfo); the Starter Pack line counts down its real deadline.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalogue"))

local Page = { Name = "Offer", Overlay = true }

local ctxRef = nil
local wired = {}
local offer = nil -- the server's offer table while there is one
local tucked = false
local prices = {}
local clock = nil

local function els(ctx)
	local v = ctx.variant
	if wired[v] then
		return wired[v]
	end
	local E = {}
	for _, path in { "Panel", "Panel/Art", "Panel/Title", "Panel/Line", "Panel/Buy", "Panel/Buy/Price", "Panel/Hide", "Tab" } do
		E[path] = ctx.el("Offer", path)
	end
	wired[v] = E
	return E
end

-- Long lines shrink a point at a time until they fit the authored width, never under the readable minimum (then
-- they cut off with "..."). Measured in canvas px (the menu's UIScale breaks TextScaled).
local function setFitted(ctx, label, text)
	if not label then
		return
	end
	local base = label:GetAttribute("_BaseTextSize")
	if not base then
		base = label.TextSize
		label:SetAttribute("_BaseTextSize", base)
	end
	label.Text = text
	local min = if ctx.variant == "Phone" then 28 else 22
	local width = label.Size.X.Offset
	local size = base
	while size > min do
		local p = Instance.new("GetTextBoundsParams")
		p.Text = text
		p.Font = label.FontFace
		p.Size = size
		p.Width = 100000
		local ok, b = pcall(TextService.GetTextBoundsAsync, TextService, p)
		if not ok or b.X <= width then
			break
		end
		size -= 1
	end
	label.TextSize = size
end

local function product()
	return offer and C.Products[offer.Key]
end

local function priceText()
	local p = product()
	if not p then
		return ""
	end
	return "R$ " .. tostring(prices[offer.Key] or p.Robux or "")
end

local function lineText()
	if not offer then
		return ""
	end
	local line = offer.Line or ""
	local untilAt = tonumber(offer.Until)
	if untilAt then
		local left = untilAt - os.time()
		if left <= 0 then
			return line
		end
		local h = left // 3600
		local m = (left % 3600) // 60
		line ..= if h > 0 then string.format("  ·  %dH %02dM LEFT", h, m) else string.format("  ·  %dM LEFT", math.max(1, m))
	end
	return line
end

local function fetchPrice(key)
	local p = C.Products[key]
	if not p or p.Id == 0 or prices[key] then
		return
	end
	task.spawn(function()
		local info = if p.Type == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		local ok, res = pcall(MarketplaceService.GetProductInfo, MarketplaceService, p.Id, info)
		if ok and type(res) == "table" and tonumber(res.PriceInRobux) then
			prices[key] = res.PriceInRobux
			if offer and offer.Key == key and ctxRef then
				ctxRef.ui.Text(els(ctxRef)["Panel/Buy/Price"], priceText())
			end
		end
	end)
end

local function fill()
	local ctx = ctxRef
	local E = els(ctx)
	if not offer then
		return
	end
	if E["Panel/Art"] then
		ctx.ui.SetArt(E["Panel/Art"], offer.Art)
	end
	setFitted(ctx, E["Panel/Title"], offer.Title)
	setFitted(ctx, E["Panel/Line"], lineText())
	ctx.ui.Text(E["Panel/Buy/Price"], priceText())
end

-- Where the panel sits on screen (Router.Fit's fitted spot) and where it hides (just past the left edge).
local function homePos(panel)
	return panel:GetAttribute("_FlexPos") or panel:GetAttribute("_BasePos") or panel.Position
end
local function awayPos(panel)
	local home = homePos(panel)
	return home - UDim2.fromOffset(home.X.Offset + panel.Size.X.Offset + 12, 0)
end

local function place(animate)
	local ctx = ctxRef
	local E = els(ctx)
	local panel, tab = E["Panel"], E["Tab"]
	if not panel then
		return
	end
	local to = if tucked then awayPos(panel) else homePos(panel)
	if animate then
		ctx.ui.Tween(panel, 0.25, { Position = to }, Enum.EasingStyle.Quart)
	else
		panel.Position = to
	end
	if tab then
		tab.Visible = tucked
	end
end

local function stopClock()
	if clock then
		task.cancel(clock)
		clock = nil
	end
end

local function startClock()
	stopClock()
	if not (offer and offer.Until) then
		return
	end
	clock = task.spawn(function()
		while offer and offer.Until do
			if os.time() >= offer.Until then
				offer = nil
				if ctxRef then
					ctxRef.close("Offer")
				end
				return
			end
			setFitted(ctxRef, els(ctxRef)["Panel/Line"], lineText())
			task.wait(20)
		end
	end)
end

local function wire(ctx)
	local E = els(ctx)
	local ui = ctx.ui
	if E["Panel/Buy"] and not E._buy then
		E._buy = ui.Button(E["Panel/Buy"], function()
			if not offer then
				return
			end
			local res = ctx.store("Product", { Key = offer.Key })
			if not res.Ok then
				ctx.sound("Error")
				if res.Reason == "Owned" then
					offer = nil
					ctx.close("Offer")
				end
			end
		end)
	end
	if E["Panel/Hide"] and not E._hide then
		E._hide = ui.Button(E["Panel/Hide"], function()
			if not offer or tucked then
				return
			end
			tucked = true
			place(true)
			task.spawn(ctx.store, "OfferHide", { Id = offer.Id })
		end, { Sound = "Back" })
	end
	if E["Tab"] and not E._tab then
		E._tab = ui.Button(E["Tab"], function()
			if not offer then
				return
			end
			tucked = false
			place(true)
		end)
	end
end

local function done(key)
	if offer and offer.Key == key then
		offer = nil
		stopClock()
		if ctxRef then
			ctxRef.sound("Tick")
			ctxRef.close("Offer")
		end
	end
end

local asking = false
local function ask(ctx)
	if asking then
		return
	end
	if offer then
		if ctx.current == "Home" and ctx.active then
			ctx.open("Offer")
		end
		return
	end
	asking = true
	local res = ctx.store("Offers", { Moment = "Home" })
	asking = false
	if res.Ok and type(res.Offer) == "table" and C.Products[res.Offer.Key] then
		offer = res.Offer
		tucked = false
		fetchPrice(offer.Key)
		if ctx.current == "Home" and ctx.active and ctx.player:GetAttribute("InMatch") ~= true then
			ctx.open("Offer")
		end
	end
end

function Page.Init(ctx)
	ctxRef = ctx
	wire(ctx)
	-- above HOME (pages are siblings under ZIndexBehavior Sibling), below the invite toast (50)
	for _, v in { "Wide", "Phone" } do
		local f = ctx.gui:FindFirstChild(v) and ctx.gui[v]:FindFirstChild("Pages") and ctx.gui[v].Pages:FindFirstChild("Offer")
		if f then
			f.ZIndex = 40
		end
	end
	ctx.on("Page", function(name)
		if name == "Home" then
			-- let HOME's own entrance (and a first-match reveal) land first
			task.delay(0.6, function()
				if ctx.current == "Home" and ctx.active then
					ask(ctx)
				end
			end)
		end
	end)
	ctx.on("Deploying", function()
		ctx.close("Offer")
	end)
	ctx.on("Active", function(on)
		if not on then
			ctx.close("Offer")
		end
	end)
	local function byId(id, isPass)
		for key, p in C.Products do
			if p.Id == id and (p.Type == "Pass") == isPass then
				return key
			end
		end
		return nil
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, bought)
		if bought and userId == Players.LocalPlayer.UserId then
			local key = byId(productId, false)
			if key then
				done(key)
			end
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		if bought and player == Players.LocalPlayer then
			local key = byId(passId, true)
			if key then
				done(key)
			end
		end
	end)
end

function Page.Layout(ctx)
	ctxRef = ctx
	wire(ctx)
	if offer then
		fill()
		place(false)
	end
end

function Page.Show(ctx)
	ctxRef = ctx
	wire(ctx)
	if not offer then
		ctx.close("Offer")
		return
	end
	fill()
	place(false)
	startClock()
end

function Page.Hide()
	stopClock()
end

return Page
