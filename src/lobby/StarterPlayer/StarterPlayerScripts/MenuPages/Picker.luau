--!nonstrict
-- MenuPages.Picker (FRONT-B, 4 Nov 2026): one picker for the six loadout tiles. Show args {Slot, Index}: Slot is
-- Class, Primary, Secondary, Lethal, Tactical or Operator. Cards come from the Shared tables (GunStats.List,
-- Progression.Classes, Gear.Items, Catalogue operators) and are clones of the authored templates (Ui.Fill). A click
-- selects a card into Detail and previews it on the stage; EQUIP commits it through Store "Loadout" or "Operator".
-- For guns, the camo row lists every camo for the gun in Detail, with weapon-level locks; a camo click equips it at
-- once (Store "Camo"). Locked cards show LV, the veteran-class trial progress, or how the operator is earned.

local Kit = require(script.Parent:WaitForChild("Loadout"):WaitForChild("LoadoutKit"))
local Turntable = require(script.Parent:WaitForChild("Loadout"):WaitForChild("Turntable"))

local Page = { Name = "Picker", Tab = "LOADOUT", Overlay = false, Camera = "Loadout" }

local TITLES = {
	Class = "CLASS",
	Primary = "PRIMARY",
	Secondary = "SECONDARY",
	Lethal = "LETHAL",
	Tactical = "TACTICAL",
	Operator = "OPERATOR",
}
local GRIDS = { "GunGrid", "ClassGrid", "GearGrid", "OperatorGrid" }

local S = {
	ctx = nil,
	reg = {}, -- page buttons
	cards = {}, -- card controllers of the current grid: {ctl, item, clone}
	camos = {}, -- camo controllers
	slot = "Primary",
	index = 1,
	viewed = nil, -- item key in Detail
	visible = false,
	equipCtl = nil,
	busy = false,
}

local function el(path)
	return S.ctx.el(Page.Name, path)
end

local function ui()
	return S.ctx.ui
end

-- what is equipped in this slot ---------------------------------------------------------------------------------------

local function equippedOf(d)
	if S.slot == "Operator" then
		return "Operator/" .. tostring(d.Operator)
	end
	local lo = Kit.Loadout(d, S.index)
	return lo[S.slot]
end

-- the key that NEW pips and Seen use for an item in this slot
local function seenKey(item)
	if S.slot == "Class" then
		return "Class/" .. item
	elseif Kit.GUN_SLOTS[S.slot] then
		return "Gun/" .. item
	elseif Kit.GEAR_SLOTS[S.slot] then
		return "Gear/" .. item
	end
	return item -- operators use their catalogue id
end

-- unlocked?, rule text, trial {n, goal, label} or nil, store item id (for VIEW IN STORE) or nil
local function lockState(d, item)
	if S.slot == "Operator" then
		local ok = Kit.Available(d, item)
		local it = Kit.Item(item)
		local storeId = it and it.Source.Kind == "Store" and not ok and item or nil
		return ok, ok and "" or Kit.Rule(item), nil, storeId
	end
	local ok = Kit.CanEquip(d, S.slot, item)
	if ok then
		return true, "", nil, nil
	end
	local lvl = S.slot == "Class" and Kit.P and Kit.P.Classes[item] and Kit.P.Classes[item].Level or Kit.ItemLevel(item)
	local trial = nil
	if S.slot == "Class" and Kit.P and Kit.P.TrialProgress then
		local n, goal, stat = Kit.P.TrialProgress(item, d.Stats)
		if n then
			trial = { n = n, goal = goal, label = Kit.TRIAL[stat] or Kit.Upper(stat) }
		end
	end
	return false, "LV " .. tostring(lvl), trial, nil
end

local function items()
	if Kit.GUN_SLOTS[S.slot] then
		return Kit.GunList(S.slot)
	elseif Kit.GEAR_SLOTS[S.slot] then
		return Kit.GearList(S.slot)
	elseif S.slot == "Class" then
		local list = {}
		for i, id in (Kit.P and Kit.P.ClassOrder or {}) do
			list[i] = id
		end
		return list
	elseif S.slot == "Operator" then
		return Kit.Operators()
	end
	return {}
end

local function gridName()
	if Kit.GUN_SLOTS[S.slot] then
		return "GunGrid"
	elseif Kit.GEAR_SLOTS[S.slot] then
		return "GearGrid"
	elseif S.slot == "Class" then
		return "ClassGrid"
	end
	return "OperatorGrid"
end

-- stage --------------------------------------------------------------------------------------------------------------

local function preview(item)
	local model
	if Kit.GUN_SLOTS[S.slot] then
		model = Kit.Stage(S.ctx, "Gun", item)
	elseif S.slot == "Operator" then
		local _, id = string.match(item, "^(%a+)/(.+)$")
		model = Kit.Stage(S.ctx, "Preview", "Operator", id or item)
	end
	Turntable.Target(model)
end

-- detail ---------------------------------------------------------------------------------------------------------------

local refreshCamos -- forward

local function refreshDetail(time)
	local ctx = S.ctx
	local d = Kit.Data(ctx)
	local item = S.viewed
	if not item then
		return
	end
	local equipped = equippedOf(d)
	local ok, rule, _, storeId = lockState(d, item)
	local ui_ = ui()

	local isGun = Kit.GUN_SLOTS[S.slot] == true
	Kit.Show(el("Detail/Stats"), isGun)
	Kit.Show(el("Detail/Info"), S.slot == "Class" or Kit.GEAR_SLOTS[S.slot] == true)

	if isGun then
		local info = Kit.GunInfo(item)
		Kit.Text(el("Detail/Name"), Kit.Upper(info.Name))
		local sub = Kit.Upper(info.Category)
		if info.Role and info.Role ~= "" then
			sub = sub .. "  ·  " .. Kit.Upper(info.Role)
		end
		Kit.Text(el("Detail/Sub"), sub)
		Kit.Stats(el("Detail/Stats"), item, equipped, time, d.Attach[item], equipped and d.Attach[equipped])
	elseif S.slot == "Class" then
		local c = Kit.P and Kit.P.Classes[item]
		Kit.Text(el("Detail/Name"), c and c.Name or Kit.Upper(item))
		Kit.Text(el("Detail/Sub"), Kit.PERK[item] or "")
		local field = c and c.Field
		if field then
			Kit.Art(ui_, el("Detail/Info/Icon"), "Gear/" .. field)
			Kit.Text(el("Detail/Info/IconName"), Kit.GearName(field))
			local g = Kit.Gear and Kit.Gear.Items[field]
			Kit.Text(el("Detail/Info/Line"), tostring(g and g.Cooldown or 90) .. " S")
		end
	elseif Kit.GEAR_SLOTS[S.slot] then
		local lo = Kit.Loadout(d, S.index)
		Kit.Text(el("Detail/Name"), Kit.GearName(item))
		Kit.Text(el("Detail/Sub"), "x" .. Kit.GearCount(item, lo.Class))
		Kit.Art(ui_, el("Detail/Info/Icon"), "Gear/" .. item)
		Kit.Text(el("Detail/Info/IconName"), TITLES[S.slot])
		Kit.Text(el("Detail/Info/Line"), Kit.GEAR_LINE[item] or "")
	else
		local it = Kit.Item(item)
		Kit.Text(el("Detail/Name"), it and it.Name or item)
		Kit.Text(el("Detail/Sub"), "OPERATOR")
	end

	-- lock plate, store link, equip state; ATTACHMENTS (Gunsmith page) for a gun you can use that takes any
	Kit.Show(el("Detail/ViewStore"), storeId ~= nil)
	Kit.Show(el("Detail/Attach"), isGun and ok and Kit.Attachable(item))
	Kit.Show(el("Detail/Lock"), not ok and storeId == nil)
	Kit.Text(el("Detail/Lock/Rule"), rule)
	if S.equipCtl then
		local isEquipped = item == equipped
		S.equipCtl.Selected(isEquipped)
		S.equipCtl.Disabled(not ok or (d.InMatch and S.slot ~= "Operator"))
	end

	if isGun and refreshCamos then
		refreshCamos(d)
	end
end

local function markCardSelected()
	for _, c in S.cards do
		if c.ctl then
			c.ctl.Selected(c.item == S.viewed)
		end
	end
end

local function view(item)
	if S.viewed == item then
		return
	end
	S.viewed = item
	markCardSelected()
	refreshDetail(0.15)
	preview(item)
	local d = Kit.Data(S.ctx)
	if not Kit.IsSeen(d, seenKey(item)) then
		Kit.MarkSeen(S.ctx, { seenKey(item) })
		for _, c in S.cards do
			if c.item == item then
				Kit.Show(c.clone:FindFirstChild("New"), false)
			end
		end
	end
end

-- cards ----------------------------------------------------------------------------------------------------------------

local function clearCards()
	for _, c in S.cards do
		if c.ctl then
			c.ctl.Destroy()
		end
	end
	table.clear(S.cards)
end

local function fillCard(d, clone, item, equipped)
	local ui_ = ui()
	local ok, rule, trial, _storeId = lockState(d, item)
	local isNew = ok and not Kit.IsSeen(d, seenKey(item))
	if S.slot == "Operator" then
		local it = Kit.Item(item)
		isNew = isNew and it ~= nil and it.Source.Kind ~= "Default"
	end
	Kit.Show(clone:FindFirstChild("New"), isNew)
	Kit.Show(clone:FindFirstChild("Equipped"), item == equipped)
	if Kit.GUN_SLOTS[S.slot] then
		local info = Kit.GunInfo(item)
		Kit.Art(ui_, clone:FindFirstChild("Gun"), "Gun/" .. item)
		Kit.Text(clone:FindFirstChild("Name"), Kit.Upper(info.Name))
		Kit.Text(clone:FindFirstChild("Level"), ok and ("LV " .. Kit.WeaponLevel(d, item)) or "")
		Kit.Show(clone:FindFirstChild("Lock"), not ok and item ~= equipped)
		Kit.Text(Kit.Child(clone, "Lock/Rule"), rule)
	elseif S.slot == "Class" then
		local c = Kit.P and Kit.P.Classes[item]
		Kit.Art(ui_, clone:FindFirstChild("Emblem"), "Emblem/" .. item)
		if c and c.Field then
			Kit.Art(ui_, clone:FindFirstChild("Field"), "Gear/" .. c.Field)
		end
		Kit.Text(clone:FindFirstChild("Name"), c and c.Name or Kit.Upper(item))
		Kit.Text(clone:FindFirstChild("Perk"), Kit.PERK[item] or "")
		local trialFrame = clone:FindFirstChild("Trial")
		Kit.Show(trialFrame, not ok and item ~= equipped)
		if trialFrame then
			Kit.Text(Kit.Child(trialFrame, "Lock/Rule"), rule)
			Kit.Show(trialFrame:FindFirstChild("TrialText"), trial ~= nil)
			Kit.Show(trialFrame:FindFirstChild("TrialBar"), trial ~= nil)
			if trial then
				Kit.Text(trialFrame:FindFirstChild("TrialText"), string.format("%s %d/%d", trial.label, trial.n, trial.goal))
				ui_.Bar(trialFrame:FindFirstChild("TrialBar"), trial.n / math.max(1, trial.goal))
			end
		end
	elseif Kit.GEAR_SLOTS[S.slot] then
		Kit.Art(ui_, clone:FindFirstChild("Gear"), "Gear/" .. item)
		Kit.Text(clone:FindFirstChild("Name"), Kit.GearName(item))
		Kit.Show(clone:FindFirstChild("Lock"), not ok and item ~= equipped)
		Kit.Text(Kit.Child(clone, "Lock/Rule"), rule)
	else
		local it = Kit.Item(item)
		local _, id = string.match(item, "^(%a+)/(.+)$")
		Kit.Art(ui_, clone:FindFirstChild("Operator"), item)
		Kit.Text(clone:FindFirstChild("Name"), it and it.Name or id)
		-- the lock plate and the EQUIPPED plate share a spot: equipped wins
		Kit.Show(clone:FindFirstChild("Lock"), not ok and item ~= equipped)
		Kit.Text(Kit.Child(clone, "Lock/Rule"), rule)
	end
end

local function buildGrid(fromShow)
	local ctx = S.ctx
	if not ctx.frame(Page.Name) then
		return
	end
	local d = Kit.Data(ctx)
	local equipped = equippedOf(d)
	local list = items()
	local gname = gridName()
	for _, g in GRIDS do
		Kit.Show(el("Sheet/" .. g), g == gname)
	end
	local isGun = Kit.GUN_SLOTS[S.slot] == true
	Kit.Show(el("Sheet/CamoHeader"), isGun)
	Kit.Show(el("Sheet/CamoGrid"), isGun)
	Kit.Text(el("Sheet/Title"), TITLES[S.slot] or "")

	clearCards()
	local grid = el("Sheet/" .. gname)
	if not grid then
		return
	end
	ctx.ui.Fill(grid, list, function(clone, item)
		fillCard(d, clone, item, equipped)
		local entry = { item = item, clone = clone }
		local edge = clone:FindFirstChild("Edge")
		if edge and edge:IsA("GuiButton") then
			entry.ctl = ctx.ui.Button(edge, function()
				view(item)
			end)
			edge.MouseEnter:Connect(function()
				local dd = Kit.Data(ctx)
				local okNow = lockState(dd, item)
				if okNow and not Kit.IsSeen(dd, seenKey(item)) then
					Kit.MarkSeen(ctx, { seenKey(item) })
					Kit.Show(clone:FindFirstChild("New"), false)
				end
			end)
		end
		table.insert(S.cards, entry)
	end)
	if fromShow and grid:IsA("ScrollingFrame") then
		grid.CanvasPosition = Vector2.zero
	end
	if S.viewed == nil or not table.find(list, S.viewed) then
		S.viewed = table.find(list, equipped) and equipped or list[1]
	end
	markCardSelected()
	refreshDetail()
	if fromShow and ctx.select then
		for _, c in S.cards do
			if c.item == S.viewed then
				ctx.select(c.clone:FindFirstChild("Edge"))
			end
		end
	end
end

-- camos ----------------------------------------------------------------------------------------------------------------

local function clearCamos()
	for _, c in S.camos do
		c.Destroy()
	end
	table.clear(S.camos)
end

refreshCamos = function(d)
	local ctx = S.ctx
	local grid = el("Sheet/CamoGrid")
	clearCamos()
	if not (grid and Kit.GUN_SLOTS[S.slot] and S.viewed) then
		return
	end
	local gun = S.viewed
	local gunUnlocked = Kit.CanEquip(d, S.slot, gun)
	local current = d.Camos[gun] or "Gunmetal"
	ctx.ui.Fill(grid, Kit.CamoOrder(), function(clone, camoId)
		local itemId = "Camo/" .. camoId
		local ok = gunUnlocked and Kit.Available(d, itemId, gun)
		Kit.Art(ctx.ui, clone:FindFirstChild("Swatch"), itemId)
		Kit.Show(clone:FindFirstChild("Lock"), not ok)
		Kit.Text(Kit.Child(clone, "Lock/Rule"), gunUnlocked and Kit.Rule(itemId) or "")
		local it = Kit.Item(itemId)
		local isNew = ok and it and it.Source.Kind ~= "Default" and not Kit.IsSeen(d, itemId)
		Kit.Show(clone:FindFirstChild("New"), isNew)
		local edge = clone:FindFirstChild("Edge")
		if edge and edge:IsA("GuiButton") then
			local ctl = ctx.ui.Button(edge, function()
				Kit.Stage(ctx, "Preview", "Camo", camoId)
				if isNew then
					Kit.MarkSeen(ctx, { itemId })
					Kit.Show(clone:FindFirstChild("New"), false)
				end
				if not ok then
					ctx.sound("Locked")
					return
				end
				if camoId == current then
					return
				end
				local res = ctx.store("Camo", { Gun = gun, Id = camoId })
				if not res.Ok then
					ctx.sound("Error")
				end
			end)
			ctl.Selected(camoId == current)
			table.insert(S.camos, ctl)
		end
	end)
end

-- equip ----------------------------------------------------------------------------------------------------------------

local function equip()
	local ctx = S.ctx
	local item = S.viewed
	if not item or S.busy then
		return
	end
	local d = Kit.Data(ctx)
	if item == equippedOf(d) then
		return
	end
	S.busy = true
	if S.equipCtl then
		S.equipCtl.Disabled(true)
	end
	local res
	if S.slot == "Operator" then
		local _, id = string.match(item, "^(%a+)/(.+)$")
		res = ctx.store("Operator", { Id = id or item })
	else
		res = ctx.store("Loadout", { Index = S.index, Slot = S.slot, Item = item })
	end
	S.busy = false
	if not res.Ok then
		ctx.sound("Error")
	end
	refreshDetail(0.15)
end

local function gunsmith()
	local item = S.viewed
	if item and Kit.GUN_SLOTS[S.slot] and Kit.Attachable(item) then
		S.ctx.go("Gunsmith", { Gun = item })
	end
end

local function viewStore()
	local item = S.viewed
	if item then
		S.ctx.go("Store", { Section = "Operators", Item = item })
	end
end

-- wiring ---------------------------------------------------------------------------------------------------------------

local function wire()
	Kit.Clear(S.reg)
	local ctx = S.ctx
	local ui_ = ui()
	Kit.Wire(S.reg, ui_, el("Sheet/Back"), function()
		ctx.back()
	end, { Silent = true })
	S.equipCtl = Kit.Wire(S.reg, ui_, el("Detail/Equip"), equip)
	Kit.Wire(S.reg, ui_, el("Detail/ViewStore"), viewStore)
	Kit.Wire(S.reg, ui_, el("Detail/Attach"), gunsmith)
end

local function refreshAll()
	if not S.visible then
		return
	end
	-- rebuild the cards (lock, equipped and new states) but keep the card in Detail
	buildGrid()
end

-- page API -------------------------------------------------------------------------------------------------------------

function Page.Init(ctx)
	S.ctx = ctx
	wire()
	for _, name in { "Loadouts", "Selected", "Kit", "Operator", "Camos", "Attach", "GunXp", "Level", "Owned", "Stats", "InMatch" } do
		ctx.onAttr(name, refreshAll)
	end
end

function Page.Layout(ctx)
	S.ctx = ctx
	wire()
	if S.visible then
		buildGrid(true)
	end
end

function Page.Show(ctx, args)
	S.ctx = ctx
	args = type(args) == "table" and args or {}
	local d = Kit.Data(ctx)
	S.slot = TITLES[args.Slot] and args.Slot or S.slot or "Primary"
	S.index = math.clamp(tonumber(args.Index) or d.Selected, 1, 3)
	S.visible = true
	ctx.menu("Status", "LOADOUT")
	S.viewed = nil
	buildGrid(true)
	if S.slot == "Operator" then
		Kit.Stage(ctx, "Frame", "Operator")
	end
	Turntable.Enable(ctx)
	if S.viewed then
		preview(S.viewed)
	end
end

function Page.Hide(ctx)
	S.visible = false
	Turntable.Disable()
	-- the stage goes back to the kit: Loadout's Show sets the gun again; anywhere else resets the preview
	task.defer(function()
		local cur = ctx.current
		if cur ~= "Loadout" and cur ~= "Gunsmith" then
			Kit.Stage(ctx, "Reset")
		end
		if cur ~= "Loadout" and cur ~= "Store" and cur ~= "Picker" and cur ~= "Gunsmith" then
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
