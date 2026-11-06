--!nonstrict
-- MenuPages.Gunsmith (6 Nov 2026): scopes and attachments for one gun. Show args {Gun}. Opened from the Picker's
-- ATTACHMENTS button. Art: horror-shooter/menu/art/screens/Gunsmith.py (Sheet: Title, Gun, Back, SlotGrid,
-- AttachGrid; Detail: Name, Sub, Pros, Cons, Stats, Lock/Rule, Equip).
-- Slot tabs list only the slots this gun takes (Shared.Attachments.Allowed). The first card is NONE (clears the
-- slot). Each attachment unlocks at a weapon level of this gun (Attachments.UnlockLevel against GunXp). A click
-- previews the gun with that attachment on the stage and shows its stats against the gun as you have it now; EQUIP
-- saves it through Store "Attach". The gun line shows its weight with these picks, since heavy guns move slower.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent:WaitForChild("Loadout"):WaitForChild("LoadoutKit"))
local Turntable = require(script.Parent:WaitForChild("Loadout"):WaitForChild("Turntable"))
local Attachments = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attachments"))

local Page = { Name = "Gunsmith", Tab = "LOADOUT", Overlay = false, Camera = "Loadout" }

local NONE = "None"

local S = {
	ctx = nil,
	reg = {}, -- page buttons
	slots = {}, -- slot tab controllers: {ctl, slot, clone}
	cards = {}, -- attachment card controllers: {ctl, item, clone}
	gun = nil,
	slot = nil,
	viewed = nil, -- attachment id in Detail, or NONE
	visible = false,
	equipCtl = nil,
	busy = false,
}

local function el(path)
	return S.ctx.el(Page.Name, path)
end

-- data -----------------------------------------------------------------------------------------------------------------

local function picksOf(d)
	return Attachments.Clean(S.gun, d.Attach[S.gun])
end

local function slotsFor(gun)
	local out = {}
	for _, slot in Attachments.Slots do
		if #Attachments.Allowed(gun, slot) > 0 then
			table.insert(out, slot)
		end
	end
	return out
end

local function seenKey(item)
	return "Attach/" .. tostring(S.gun) .. "/" .. item
end

-- unlocked?, required weapon level
local function lockState(d, item)
	if item == NONE then
		return true, 0
	end
	local need = Attachments.UnlockLevel(S.gun, item) or math.huge
	return Kit.WeaponLevel(d, S.gun) >= need, need
end

local function isNew(d, item)
	return item ~= NONE and (lockState(d, item)) and not Kit.IsSeen(d, seenKey(item))
end

local function slotHasNew(d, slot)
	for _, id in Attachments.Allowed(S.gun, slot) do
		if isNew(d, id) then
			return true
		end
	end
	return false
end

local function weightOf(picks)
	local w = Attachments.GunWeight[S.gun] or 3
	for _, id in picks do
		local it = Attachments.Items[id]
		w += it and it.Weight or 0
	end
	return w
end

local function kg(w)
	return string.format("%.1f KG", w)
end

-- the picks with the viewed card in the current slot
local function withViewed(picks)
	local out = table.clone(picks)
	out[S.slot] = if S.viewed and S.viewed ~= NONE then S.viewed else nil
	return out
end

local function itemName(item)
	if item == NONE or item == nil then
		return "NONE"
	end
	local it = Attachments.Items[item]
	return it and it.Name or Kit.Upper(item)
end

local function joined(prefix, list)
	local parts = {}
	for _, s in list do
		table.insert(parts, prefix .. s)
	end
	return table.concat(parts, "  ")
end

-- stage ----------------------------------------------------------------------------------------------------------------

local function preview()
	local d = Kit.Data(S.ctx)
	local model = Kit.Stage(S.ctx, "Preview", "Attach", { Gun = S.gun, Picks = withViewed(picksOf(d)) })
	Turntable.Target(model)
end

-- header and detail ------------------------------------------------------------------------------------------------------

local function refreshHeader(d)
	local info = Kit.GunInfo(S.gun)
	local w = weightOf(picksOf(d))
	Kit.Text(el("Sheet/Title"), "ATTACHMENTS")
	Kit.Text(el("Sheet/Gun"), string.format("%s  ·  LV %d  ·  %s %s", Kit.Upper(info.Name), Kit.WeaponLevel(d, S.gun),
		kg(w), Attachments.WeightClass(w)))
end

local function refreshDetail(time)
	local d = Kit.Data(S.ctx)
	local item = S.viewed
	if not item then
		return
	end
	local picks = picksOf(d)
	local ok, need = lockState(d, item)
	Kit.Text(el("Detail/Name"), itemName(item))

	-- the weight change shows next to the slot, so a heavy scope reads as heavy before you equip it
	local sub = Attachments.SlotNames[S.slot] or Kit.Upper(S.slot)
	if item ~= NONE then
		local it = Attachments.Items[item]
		sub ..= string.format("  ·  +%.2f KG", it and it.Weight or 0)
		if not ok then
			sub ..= "  ·  UNLOCKS AT WEAPON LEVEL " .. need
		end
	end
	local after = weightOf(withViewed(picks))
	sub ..= "  ·  GUN " .. kg(after) .. " " .. Attachments.WeightClass(after)
	Kit.Text(el("Detail/Sub"), sub)

	local lines = if item == NONE then { pros = {}, cons = {} } else Attachments.Lines(item)
	Kit.Text(el("Detail/Pros"), joined("+ ", lines.pros))
	Kit.Text(el("Detail/Cons"), joined("- ", lines.cons))
	Kit.Stats(el("Detail/Stats"), S.gun, S.gun, time, withViewed(picks), picks)

	Kit.Show(el("Detail/Lock"), not ok)
	Kit.Text(el("Detail/Lock/Rule"), ok and "" or ("LV " .. need))
	if S.equipCtl then
		local current = picks[S.slot] or NONE
		S.equipCtl.Selected(item == current)
		S.equipCtl.Disabled(not ok or d.InMatch)
	end
end

-- cards ----------------------------------------------------------------------------------------------------------------

local function markSelected()
	for _, c in S.cards do
		if c.ctl then
			c.ctl.Selected(c.item == S.viewed)
		end
	end
	for _, c in S.slots do
		if c.ctl then
			c.ctl.Selected(c.slot == S.slot)
		end
	end
end

local function view(item)
	if S.viewed == item then
		return
	end
	S.viewed = item
	markSelected()
	refreshDetail(0.15)
	preview()
	local d = Kit.Data(S.ctx)
	if isNew(d, item) then
		Kit.MarkSeen(S.ctx, { seenKey(item) })
		for _, c in S.cards do
			if c.item == item then
				Kit.Show(c.clone:FindFirstChild("New"), false)
			end
		end
	end
end

local function clear(list)
	for _, c in list do
		if c.ctl then
			c.ctl.Destroy()
		end
	end
	table.clear(list)
end

local buildCards -- forward

local function buildSlots(d)
	local grid = el("Sheet/SlotGrid")
	clear(S.slots)
	if not grid then
		return
	end
	local picks = picksOf(d)
	S.ctx.ui.Fill(grid, slotsFor(S.gun), function(clone, slot)
		Kit.Text(clone:FindFirstChild("Name"), Attachments.SlotNames[slot] or Kit.Upper(slot))
		Kit.Text(clone:FindFirstChild("Pick"), itemName(picks[slot]))
		Kit.Show(clone:FindFirstChild("New"), slotHasNew(d, slot))
		local entry = { slot = slot, clone = clone }
		local edge = clone:FindFirstChild("Edge")
		if edge and edge:IsA("GuiButton") then
			entry.ctl = S.ctx.ui.Button(edge, function()
				if S.slot == slot then
					return
				end
				S.slot = slot
				S.viewed = nil
				buildCards(true)
				preview()
			end)
		end
		table.insert(S.slots, entry)
	end)
end

buildCards = function(fromShow)
	local ctx = S.ctx
	local d = Kit.Data(ctx)
	local grid = el("Sheet/AttachGrid")
	clear(S.cards)
	if not grid then
		return
	end
	local picks = picksOf(d)
	local current = picks[S.slot] or NONE
	local list = { NONE }
	for _, id in Attachments.Allowed(S.gun, S.slot) do
		table.insert(list, id)
	end
	ctx.ui.Fill(grid, list, function(clone, item)
		local ok, need = lockState(d, item)
		local icon = clone:FindFirstChild("Icon")
		Kit.Show(icon, item ~= NONE and Kit.Art(ctx.ui, icon, "Attach/" .. item))
		Kit.Text(clone:FindFirstChild("Name"), itemName(item))
		Kit.Show(clone:FindFirstChild("Equipped"), item == current)
		-- the lock plate and the EQUIPPED chip share a spot: equipped wins
		Kit.Show(clone:FindFirstChild("Lock"), not ok and item ~= current)
		Kit.Text(Kit.Child(clone, "Lock/Rule"), ok and "" or ("LV " .. need))
		Kit.Show(clone:FindFirstChild("New"), isNew(d, item))
		local entry = { item = item, clone = clone }
		local edge = clone:FindFirstChild("Edge")
		if edge and edge:IsA("GuiButton") then
			entry.ctl = ctx.ui.Button(edge, function()
				view(item)
			end)
		end
		table.insert(S.cards, entry)
	end)
	if fromShow and grid:IsA("ScrollingFrame") then
		grid.CanvasPosition = Vector2.zero
	end
	if S.viewed == nil or not table.find(list, S.viewed) then
		S.viewed = current
	end
	markSelected()
	refreshDetail()
	if fromShow and ctx.select then
		for _, c in S.cards do
			if c.item == S.viewed then
				ctx.select(c.clone:FindFirstChild("Edge"))
			end
		end
	end
end

local function rebuild(fromShow)
	if not (S.ctx.frame(Page.Name) and S.gun and S.slot) then
		return
	end
	local d = Kit.Data(S.ctx)
	refreshHeader(d)
	buildSlots(d)
	buildCards(fromShow)
end

-- equip ----------------------------------------------------------------------------------------------------------------

local function equip()
	local ctx = S.ctx
	local item = S.viewed
	if not item or S.busy then
		return
	end
	local d = Kit.Data(ctx)
	if item == (picksOf(d)[S.slot] or NONE) then
		return
	end
	if not (lockState(d, item)) then
		ctx.sound("Locked")
		return
	end
	S.busy = true
	if S.equipCtl then
		S.equipCtl.Disabled(true)
	end
	local res = ctx.store("Attach", { Gun = S.gun, Slot = S.slot, Id = if item == NONE then nil else item })
	S.busy = false
	if not res.Ok then
		ctx.sound("Error")
	end
	refreshDetail(0.15)
end

-- wiring ---------------------------------------------------------------------------------------------------------------

local function wire()
	Kit.Clear(S.reg)
	local ctx = S.ctx
	Kit.Wire(S.reg, ctx.ui, el("Sheet/Back"), function()
		ctx.back()
	end, { Silent = true })
	S.equipCtl = Kit.Wire(S.reg, ctx.ui, el("Detail/Equip"), equip)
end

local function refreshAll()
	if S.visible then
		rebuild()
	end
end

-- page API -------------------------------------------------------------------------------------------------------------

function Page.Init(ctx)
	S.ctx = ctx
	wire()
	for _, name in { "Attach", "GunXp", "Seen", "InMatch" } do
		ctx.onAttr(name, refreshAll)
	end
end

function Page.Layout(ctx)
	S.ctx = ctx
	wire()
	if S.visible then
		rebuild(true)
	end
end

function Page.Show(ctx, args)
	S.ctx = ctx
	args = type(args) == "table" and args or {}
	local gun = args.Gun or S.gun
	local slots = gun and slotsFor(gun) or {}
	if #slots == 0 then
		-- a gun with nothing to fit (or none given): nothing to show here
		task.defer(ctx.back)
		return
	end
	if gun ~= S.gun or not table.find(slots, S.slot) then
		S.slot = slots[1]
	end
	S.gun = gun
	S.viewed = nil
	S.visible = true
	ctx.menu("Status", "LOADOUT")
	rebuild(true)
	Turntable.Enable(ctx)
	preview()
end

function Page.Hide(ctx)
	S.visible = false
	Turntable.Disable()
	-- back to the saved picks on the stage; the page you go to sets its own stage
	Kit.Stage(ctx, "Preview", "Attach", nil)
	task.defer(function()
		local cur = ctx.current
		if cur ~= "Loadout" and cur ~= "Picker" then
			Kit.Stage(ctx, "Reset")
		end
		if cur ~= "Loadout" and cur ~= "Store" and cur ~= "Picker" then
			ctx.menu("Status", "IDLE")
		end
	end)
end

-- for the static preview and tests
Page._S = S
Page._view = function(item)
	view(item)
end
Page._equip = function()
	equip()
end

return Page
