--!nonstrict
-- MenuPages.Confirm (FRONT-B, 4 Nov 2026): the Scrip purchase confirm overlay. Show args {ItemId} opens the panel
-- (render, name, Scrip price, BUY / CANCEL); {Reveal = itemId} goes straight to the reveal (used after a Robux
-- purchase grants an item). BUY calls Store "Buy"; the reveal plays when the Owned attribute holds the item, never on
-- the call's return alone. Short of Scrip: close and jump to SCRIP PACKS with the gap. Robux items never come here.

local Kit = require(script.Parent:WaitForChild("Loadout"):WaitForChild("LoadoutKit"))

local Page = { Name = "Confirm", Overlay = true }

local REVEAL_WAIT = 10 -- seconds to wait for Owned after a successful buy

local S = {
	ctx = nil,
	reg = {},
	buy = nil,
	itemId = nil,
	busy = false,
	revealed = false,
	token = 0,
}

local function el(path)
	return S.ctx.el(Page.Name, path)
end

local function fill(prefix, itemId)
	local it = Kit.Item(itemId)
	Kit.Art(S.ctx.ui, el(prefix .. "Art"), it and it.Art or itemId)
	Kit.Text(el(prefix .. "Kind"), it and (Kit.KIND_TEXT[it.Kind] or Kit.Upper(it.Kind)) or "")
	Kit.Text(el(prefix .. "Name"), it and it.Name or "")
end

-- Remember an element's authored size and position once, so the animations can return to them.
local function home(inst)
	if not inst:GetAttribute("_FbSize") then
		inst:SetAttribute("_FbSize", inst.Size)
		inst:SetAttribute("_FbPos", inst.Position)
	end
	return inst:GetAttribute("_FbSize"), inst:GetAttribute("_FbPos")
end

-- Scale an element about its centre: f = 1 is its authored size.
local function scaled(size, pos, f)
	local w, h = size.X.Offset, size.Y.Offset
	return UDim2.new(size.X.Scale * f, w * f, size.Y.Scale * f, h * f),
		UDim2.new(pos.X.Scale, pos.X.Offset - w * (f - 1) / 2, pos.Y.Scale, pos.Y.Offset - h * (f - 1) / 2)
end

local function restore()
	for _, path in { "Reveal/Card", "Reveal/Card/Stamp" } do
		local inst = el(path)
		if inst and inst:GetAttribute("_FbSize") then
			inst.Size = inst:GetAttribute("_FbSize")
			inst.Position = inst:GetAttribute("_FbPos")
			if inst:IsA("ImageLabel") then
				inst.ImageTransparency = 0
			end
		end
	end
end

local function playReveal(itemId)
	if S.revealed then
		return
	end
	S.revealed = true
	local ui = S.ctx.ui
	fill("Reveal/Card/", itemId)
	Kit.Show(el("Panel"), false)
	local reveal = el("Reveal")
	Kit.Show(reveal, true)
	local it = Kit.Item(itemId)
	local d = Kit.Data(S.ctx)
	-- EQUIP for things that equip (operators, beams, cards, camos); hidden when already equipped
	local isEquipped = it
		and ((it.Kind == "Operator" and d.Operator == it.Id) or (it.Kind == "Beam" and d.Beam == it.Id)
			or (it.Kind == "Card" and d.Card == it.Id))
	Kit.Show(el("Reveal/Equip"), it ~= nil and not isEquipped)

	-- the card flips in (width 0 -> full about its centre), then the stamp lands with the Stamp sound
	local card = el("Reveal/Card")
	if card then
		local size, pos = home(card)
		card.Size = UDim2.new(0, 0, size.Y.Scale, size.Y.Offset)
		card.Position = UDim2.new(pos.X.Scale, pos.X.Offset + size.X.Offset / 2, pos.Y.Scale, pos.Y.Offset)
		ui.Tween(card, 0.22, { Size = size, Position = pos }, Enum.EasingStyle.Back)
	end
	local stamp = el("Reveal/Card/Stamp")
	if stamp then
		local size, pos = home(stamp)
		local s1, p1 = scaled(size, pos, 1.4)
		stamp.Size, stamp.Position = s1, p1
		stamp.ImageTransparency = 1
		task.delay(0.28, function()
			if not stamp.Parent then
				return
			end
			S.ctx.sound("Stamp")
			ui.Tween(stamp, 0.12, { Size = size, Position = pos, ImageTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
	end
	if it then
		Kit.Stage(S.ctx, "Preview", it.Kind, it.Id)
	end
	if S.ctx.select then
		S.ctx.select(el("Reveal/Equip"))
	end
end

-- Wait for the Owned attribute to hold the item, then reveal.
local function revealWhenOwned(itemId)
	S.token += 1
	local token = S.token
	local function check()
		return Kit.Data(S.ctx).Owned[itemId] == true
	end
	if check() then
		playReveal(itemId)
		return
	end
	local conn
	conn = S.ctx.onAttr("Owned", function()
		if token ~= S.token then
			conn:Disconnect()
			return
		end
		if check() then
			conn:Disconnect()
			playReveal(itemId)
		end
	end)
	task.delay(REVEAL_WAIT, function()
		if conn.Connected then
			conn:Disconnect()
		end
		if token == S.token and not S.revealed then
			-- the grant never showed up: give the panel back (or close a reveal-only open)
			local panel = el("Panel")
			if not (panel and panel.Visible) then
				S.ctx.close(Page.Name)
				return
			end
			S.busy = false
			if S.buy then
				S.buy.Disabled(false)
			end
			S.ctx.sound("Error")
		end
	end)
end

local function buy()
	local ctx = S.ctx
	local itemId = S.itemId
	if not itemId or S.busy then
		return
	end
	S.busy = true
	if S.buy then
		S.buy.Disabled(true)
	end
	local res = ctx.store("Buy", { ItemId = itemId })
	if res.Ok then
		revealWhenOwned(itemId)
		return
	end
	S.busy = false
	if S.buy then
		S.buy.Disabled(false)
	end
	if res.Reason == "Short" then
		ctx.close(Page.Name)
		ctx.go("Store", { Section = "Scrip", Need = tonumber(res.Need) or 1 })
	elseif res.Reason == "Owned" then
		ctx.close(Page.Name)
	else
		ctx.sound("Error")
	end
end

local function equip()
	local ctx = S.ctx
	local it = Kit.Item(S.itemId)
	if not it then
		ctx.close(Page.Name)
		return
	end
	local res
	if it.Kind == "Camo" then
		local lo = Kit.Loadout(Kit.Data(ctx))
		res = ctx.store("Camo", { Gun = lo.Primary, Id = it.Id })
	else
		res = ctx.store(it.Kind, { Id = it.Id })
	end
	if not res.Ok then
		ctx.sound("Error")
		return
	end
	ctx.close(Page.Name)
end

local function wire()
	Kit.Clear(S.reg)
	local ctx = S.ctx
	-- every page is authored at ZIndex 1, so the overlay could draw under the page it covers: lift it
	local root = ctx.frame(Page.Name)
	if root and root.ZIndex < 10 then
		root.ZIndex = 10
	end
	-- the scrim is the variant's size: stretch it past the edges so it dims ultrawide and tall screens too (INTEGRATION)
	local scrim = root and root:FindFirstChild("Scrim")
	if scrim and scrim:IsA("GuiObject") then
		scrim.AnchorPoint = Vector2.new(0.5, 0.5)
		scrim.Position = UDim2.fromScale(0.5, 0.5)
		scrim.Size = UDim2.fromScale(3, 3)
	end
	Kit.Wire(S.reg, ctx.ui, el("Panel/Cancel"), function()
		ctx.close(Page.Name)
	end, { Sound = "Back" })
	S.buy = Kit.Wire(S.reg, ctx.ui, el("Panel/Buy"), buy)
	Kit.Wire(S.reg, ctx.ui, el("Reveal/Equip"), equip)
	Kit.Wire(S.reg, ctx.ui, el("Reveal/Close"), function()
		ctx.close(Page.Name)
	end, { Sound = "Back" })
end

local function showPanel()
	local price = Kit.C and Kit.C.Price(S.itemId) or 0
	fill("Panel/", S.itemId)
	Kit.Text(el("Panel/PriceText"), Kit.Money(price))
	Kit.Show(el("Panel"), true)
	Kit.Show(el("Reveal"), false)
end

-- page API -------------------------------------------------------------------------------------------------------------

function Page.Init(ctx)
	S.ctx = ctx
	wire()
end

function Page.Layout(ctx)
	S.ctx = ctx
	wire()
	if S.itemId and ctx.isOpen and ctx.isOpen(Page.Name) then
		-- the other variant's copy shows the same step
		if S.revealed then
			S.revealed = false
			playReveal(S.itemId)
		else
			showPanel()
			if S.buy then
				S.buy.Disabled(S.busy)
			end
		end
	end
end

function Page.Show(ctx, args)
	S.ctx = ctx
	args = type(args) == "table" and args or {}
	S.token += 1
	S.busy = false
	S.revealed = false
	if S.buy then
		S.buy.Disabled(false)
	end
	restore()
	if args.Reveal then
		S.itemId = args.Reveal
		Kit.Show(el("Panel"), false)
		Kit.Show(el("Reveal"), false)
		revealWhenOwned(args.Reveal)
		return
	end
	S.itemId = args.ItemId
	if not (Kit.C and Kit.C.Price(S.itemId)) then
		-- not a Scrip item: this overlay is only for Scrip buys
		task.defer(ctx.close, Page.Name)
		return
	end
	showPanel()
	local it = Kit.Item(S.itemId)
	if it then
		Kit.Stage(ctx, "Preview", it.Kind, it.Id)
	end
	if ctx.select then
		ctx.select(el("Panel/Buy"))
	end
end

function Page.Hide(_ctx)
	S.token += 1
	S.busy = false
	restore()
end

-- for the static preview and tests
Page._S = S
Page._playReveal = playReveal
Page._buy = function()
	buy()
end
Page._equip = function()
	equip()
end

return Page
