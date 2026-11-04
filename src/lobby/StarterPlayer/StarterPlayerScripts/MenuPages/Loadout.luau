--!nonstrict
-- MenuPages.Loadout (FRONT-B, 4 Nov 2026): the LOADOUT page. Three loadout slots (slot 3 opens at level 5), the five
-- loadout tiles plus OPERATOR, and the stats strip for the focused gun. Clicking a tile opens the Picker; the gun on
-- the stage turns with a drag or swipe (Turntable). Data: player attributes Loadouts, Selected, Kit, Owned, Level,
-- Stats, GunXp, Operator, Seen, InMatch; writes go through Store "Select". Art and names come from
-- StarterGui.Menu.<Variant>.Pages.Loadout (SCREENS-B); elements are found by name in Init and again in Layout.

local Kit = require(script:WaitForChild("LoadoutKit"))
local Turntable = require(script:WaitForChild("Turntable"))

local Page = { Name = "Loadout", Tab = "LOADOUT", Overlay = false, Camera = "Loadout" }

local S = {
	ctx = nil,
	reg = {}, -- button controllers and connections of the current variant
	slots = {}, -- Slot1..3 controllers
	edges = {}, -- tile -> Edge controller
	focus = "Primary",
	visible = false,
	dirty = true,
}

local function el(path)
	return S.ctx.el(Page.Name, path)
end

local function ui()
	return S.ctx.ui
end

-- refresh ------------------------------------------------------------------------------------------------------------

local function stageGun(gun)
	local model = Kit.Stage(S.ctx, "Gun", gun)
	Turntable.Target(model)
end

local function refreshStats(d, lo, time)
	local gun = lo[S.focus] or lo.Primary
	local info = Kit.GunInfo(gun)
	Kit.Text(el("Stats/GunName"), Kit.Upper(info.Name))
	Kit.Text(el("Stats/Category"), Kit.Upper(info.Category))
	Kit.Text(el("Stats/Role"), Kit.Upper(info.Role))
	-- on the Loadout page the ghost is the gun itself: no gain, no loss
	Kit.Stats(el("Stats"), gun, gun, time)
end

local function refresh(time)
	local ctx = S.ctx
	if not (ctx and ctx.frame(Page.Name)) then
		return
	end
	S.dirty = false
	local d = Kit.Data(ctx)
	local sel = d.Selected
	local lo = Kit.Loadout(d, sel)
	local ui_ = ui()

	-- slots
	for i = 1, 3 do
		local c = S.slots[i]
		if c then
			c.Selected(i == sel)
		end
	end
	local need3 = Kit.SlotLevel(3)
	local locked3 = d.Level < need3
	Kit.Show(el("Slot3/Lock"), locked3)
	Kit.Text(el("Slot3/Lock/LockLevel"), "LV " .. need3)
	if S.slots[3] then
		S.slots[3].Disabled(locked3)
	end
	Kit.Show(el("Slot3/New"), not locked3 and not Kit.IsSeen(d, "Slot/Slot3"))

	-- class
	local classId = lo.Class
	local cls = Kit.P and Kit.P.Classes[classId]
	Kit.Art(ui_, el("Class/Emblem"), "Emblem/" .. classId)
	Kit.Text(el("Class/ClassName"), cls and cls.Name or Kit.Upper(classId))
	Kit.Text(el("Class/Perk"), Kit.PERK[classId] or "")
	local field = cls and cls.Field
	if field then
		Kit.Art(ui_, el("Class/Field"), "Gear/" .. field)
		local g = Kit.Gear and Kit.Gear.Items[field]
		Kit.Text(el("Class/FieldName"), g and g.Name or Kit.Upper(field))
		Kit.Text(el("Class/FieldTime"), tostring(g and g.Cooldown or 90) .. " S")
	end

	-- guns
	for _, slot in { "Primary", "Secondary" } do
		local gun = lo[slot]
		local info = Kit.GunInfo(gun)
		Kit.Art(ui_, el(slot .. "/Gun"), "Gun/" .. tostring(gun))
		Kit.Text(el(slot .. "/Name"), Kit.Upper(info.Name))
		Kit.Text(el(slot .. "/Level"), "LV " .. Kit.WeaponLevel(d, gun))
	end

	-- gear
	for _, slot in { "Lethal", "Tactical" } do
		local key = lo[slot]
		Kit.Art(ui_, el(slot .. "/Gear"), "Gear/" .. tostring(key))
		Kit.Text(el(slot .. "/Name"), Kit.GearName(key))
		Kit.Text(el(slot .. "/Count"), "x" .. Kit.GearCount(key, classId))
	end

	-- operator
	local opId = "Operator/" .. tostring(d.Operator)
	local op = Kit.Item(opId)
	Kit.Text(el("Operator/Name"), op and op.Name or Kit.Upper(d.Operator))
	Kit.Art(ui_, el("Operator/Portrait"), "OperatorPortrait/" .. tostring(d.Operator))

	-- NEW pips and match lock
	for _, tile in Kit.TILES do
		Kit.Show(el(tile .. "/New"), Kit.NewFor(d, tile))
		local c = S.edges[tile]
		if c then
			c.Disabled(d.InMatch and tile ~= "Operator")
		end
	end

	refreshStats(d, lo, time)
	return lo
end

local function refreshIfShown()
	if S.visible then
		refresh(0.15)
	else
		S.dirty = true
	end
end

-- wiring -------------------------------------------------------------------------------------------------------------

local function select(index)
	local ctx = S.ctx
	local d = Kit.Data(ctx)
	if index == 3 then
		if d.Level < Kit.SlotLevel(3) then
			return
		end
		Kit.MarkSeen(ctx, { "Slot/Slot3" })
	end
	if index == d.Selected then
		return
	end
	local res = ctx.store("Select", { Index = index })
	if not res.Ok then
		ctx.sound("Error")
		return
	end
	-- the attribute change refreshes; move the stage gun now
	local lo = Kit.Loadout(Kit.Data(ctx), index)
	stageGun(lo[S.focus] or lo.Primary)
end

local function setFocus(slot)
	if S.focus == slot then
		return
	end
	S.focus = slot
	local d = Kit.Data(S.ctx)
	local lo = Kit.Loadout(d)
	refreshStats(d, lo, 0.12)
	stageGun(lo[slot] or lo.Primary)
end

local function wire()
	Kit.Clear(S.reg)
	table.clear(S.slots)
	table.clear(S.edges)
	local ctx = S.ctx
	local ui_ = ui()
	for i = 1, 3 do
		S.slots[i] = Kit.Wire(S.reg, ui_, el("Slot" .. i), function()
			select(i)
		end)
	end
	for _, tile in Kit.TILES do
		local edge = el(tile .. "/Edge")
		S.edges[tile] = Kit.Wire(S.reg, ui_, edge, function()
			local d = Kit.Data(ctx)
			ctx.go("Picker", { Slot = tile, Index = d.Selected })
		end)
		if edge and (tile == "Primary" or tile == "Secondary") then
			table.insert(S.reg, edge.MouseEnter:Connect(function()
				setFocus(tile)
			end))
			table.insert(S.reg, edge.SelectionGained:Connect(function()
				setFocus(tile)
			end))
			if tile == "Secondary" then
				table.insert(S.reg, edge.MouseLeave:Connect(function()
					setFocus("Primary")
				end))
			end
		end
	end
end

-- page API -----------------------------------------------------------------------------------------------------------

function Page.Init(ctx)
	S.ctx = ctx
	wire()
	for _, name in { "Loadouts", "Selected", "Kit", "Class", "Operator", "GunXp", "Level", "Seen", "Owned", "Stats", "InMatch" } do
		ctx.onAttr(name, refreshIfShown)
	end
	refresh()
end

function Page.Layout(ctx)
	S.ctx = ctx
	wire()
	refresh()
end

function Page.Show(ctx, _args)
	S.ctx = ctx
	S.visible = true
	ctx.menu("Status", "LOADOUT")
	S.focus = "Primary"
	local lo = refresh()
	Turntable.Enable(ctx)
	if lo then
		stageGun(lo.Primary)
	end
	if ctx.select then
		ctx.select(el("Primary/Edge"))
	end
end

function Page.Hide(ctx)
	S.visible = false
	Turntable.Disable()
	task.defer(function()
		local cur = ctx.current
		if cur ~= "Picker" and cur ~= "Store" and cur ~= "Loadout" then
			ctx.menu("Status", "IDLE")
		end
	end)
end

return Page
