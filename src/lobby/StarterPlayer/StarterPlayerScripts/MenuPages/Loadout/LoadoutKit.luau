--!nonstrict
-- MenuPages.Loadout.LoadoutKit (FRONT-B, 4 Nov 2026): data and wiring helpers shared by the Loadout, Picker, Store and
-- Confirm pages. It reads the Shared tables (Progression, Catalogue, GunStats, LoadoutRules, Gear, Camo) and the
-- player attributes through ctx.attr. It never creates UI: it swaps authored art, sets text on authored labels, moves
-- the clip frames of authored bars and toggles Visible.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local function optional(name)
	local m = Shared:FindFirstChild(name)
	if not (m and m:IsA("ModuleScript")) then
		return nil
	end
	local ok, t = pcall(require, m)
	if ok and type(t) == "table" then
		return t
	end
	warn("[LoadoutKit] could not load Shared." .. name, t)
	return nil
end

local K = {}
K.P = optional("Progression")
K.C = optional("Catalogue")
K.GunStats = optional("GunStats")
K.Rules = optional("LoadoutRules")
K.Gear = optional("Gear")
K.Camo = optional("Camo")
K.GameConfig = optional("GameConfig")
K.UiArt = optional("UiArt") or {}
K.Attach = optional("Attachments")

K.STATS = { "Damage", "FireRate", "Range", "Control", "Magazine", "Noise" }
K.TILES = { "Class", "Primary", "Secondary", "Lethal", "Tactical", "Operator" }
K.GUN_SLOTS = { Primary = true, Secondary = true }
K.GEAR_SLOTS = { Lethal = true, Tactical = true }
K.DEFAULT = { Class = "Rifleman", Primary = "AK", Secondary = "Pistol", Lethal = "Frag", Tactical = "Flare" }

-- One short line per class (no explainer text: the card shows one line).
K.PERK = {
	Rifleman = "FAST RELOAD",
	Medic = "FAST REVIVES",
	Engineer = "STRONG REPAIRS",
	Scout = "QUIET STEPS",
	Hunter = "+15% VS ELITES",
	Firefighter = "FAST SELF-REVIVE",
	Marksman = "STEADY AIM",
	Demolition = "TWO LETHALS",
}
K.GEAR_LINE = {
	Frag = "BLAST, KNOCKDOWN",
	Molotov = "FIRE POOL",
	Flare = "LIGHT, LURE",
	Flashbang = "STUN",
	Stim = "HEAL, SPEED",
}
K.TRIAL = { Elites = "ELITE KILLS", Escapes = "ESCAPES", Headshots = "HEADSHOTS", FragKills = "FRAG KILLS" }
K.KIND_TEXT = { Operator = "OPERATOR", Camo = "CAMO", Beam = "FLASHLIGHT", Card = "CALLING CARD" }
K.SECTION_TEXT = { Scrip = "", Passes = "GAME PASS", Pass = "NIGHT PASS", Extras = "EXTRA", Featured = "STARTER PACK" }
-- short: the camo card lock label holds about 6 characters
K.MASTERY = { Headshots100 = "100 HS", Elites25 = "25 ELT", AllGold = "GOLD", NightmareEscape = "ESCAPE" }

-- small helpers ------------------------------------------------------------------------------------------------------

function K.Upper(s)
	return string.upper(tostring(s or ""))
end

function K.Money(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

function K.Show(inst, v)
	if inst then
		inst.Visible = v and true or false
	end
end

function K.Text(label, v)
	if label and label:IsA("TextLabel") then
		label.Text = tostring(v == nil and "" or v)
	end
end

-- Set an authored image to an art key, only when the key exists (a missing render keeps the placeholder).
function K.Art(ui, img, key)
	if img and key and K.UiArt[key] then
		ui.SetArt(img, key)
		return true
	end
	return false
end

function K.Child(node, path)
	for _, part in string.split(path, "/") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

-- A set from an attribute value ({id = true} or {id, id}).
function K.Set(v)
	local s = {}
	if type(v) == "table" then
		for k, x in v do
			if type(k) == "string" then
				s[k] = x and true or nil
			elseif type(x) == "string" then
				s[x] = true
			end
		end
	end
	return s
end

-- A button registry per page: Wire() remembers each controller so Clear() can drop them on Layout.
function K.Wire(reg, ui, btn, fn, opts)
	if not (btn and btn:IsA("GuiButton")) then
		return nil
	end
	local ctl = ui.Button(btn, fn, opts)
	table.insert(reg, ctl)
	return ctl
end

function K.Clear(reg)
	for _, c in reg do
		if type(c) == "table" and c.Destroy then
			c.Destroy()
		elseif typeof(c) == "RBXScriptConnection" then
			c:Disconnect()
		end
	end
	table.clear(reg)
end

-- Call a MenuStage function if FRONT-A's stage has it (contract: stage.Preview(kind, id), Reset(), Gun(gunKey),
-- Frame(name)). Returns what it returns; never errors.
function K.Stage(ctx, name, ...)
	local st = ctx and ctx.stage
	local fn = st and st[name]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, res = pcall(fn, ...)
	if not ok then
		warn("[LoadoutKit] stage." .. name, res)
		return nil
	end
	return res
end

-- player data --------------------------------------------------------------------------------------------------------

-- One snapshot of every attribute these pages read.
function K.Data(ctx)
	local function a(name)
		return ctx.attr(name)
	end
	local d = {
		Level = tonumber(a("Level")) or 1,
		Stats = type(a("Stats")) == "table" and a("Stats") or {},
		Owned = K.Set(a("Owned")),
		Seen = K.Set(a("Seen")),
		GunXp = type(a("GunXp")) == "table" and a("GunXp") or {},
		Camos = type(a("Camos")) == "table" and a("Camos") or {},
		Attach = type(a("Attach")) == "table" and a("Attach") or {}, -- {gun = {slot = id}}, Shared.Attachments
		Loadouts = type(a("Loadouts")) == "table" and a("Loadouts") or {},
		Selected = tonumber(a("Selected")) or 1,
		Kit = type(a("Kit")) == "table" and a("Kit") or nil,
		Operator = a("Operator") or "Woodland",
		Beam = a("Beam") or "Warm",
		Card = a("Card") or "Default",
		Scrip = tonumber(a("Scrip")) or 0,
		InMatch = a("InMatch") == true,
		Beams = a("Beams") == true,
		Vip = a("Vip") == true,
		DoubleScrip = a("DoubleScrip") == true,
		Premium = a("Premium") == true,
		PassPremium = a("PassPremium") == true,
		PassTier = tonumber(a("PassTier")) or 1,
		StarterDeadline = tonumber(a("StarterDeadline")) or 0,
		Escaped = a("Escaped") == true,
	}
	d.Selected = math.clamp(math.floor(d.Selected), 1, 3)
	if d.Premium == false and ctx.player then
		d.Premium = ctx.player.MembershipType == Enum.MembershipType.Premium
	end
	-- the per-gun mastery counters are not published as an attribute; keep the slot so Catalogue.Available works
	d.GunStats = type(a("GunStats")) == "table" and a("GunStats") or {}
	return d
end

-- The level that opens a loadout slot (slot 3 opens at Progression.UnlockLevel("Slot3"), 5 today).
function K.SlotLevel(index)
	return (K.P and K.P.UnlockLevel and K.P.UnlockLevel("Slot" .. index)) or (index == 3 and 5 or 1)
end

function K.Clean(d, lo)
	if K.Rules and K.Rules.Clean then
		local ok, out = pcall(K.Rules.Clean, lo, d.Level, d.Stats, d.Owned)
		if ok and type(out) == "table" then
			return out
		end
	end
	local out = {}
	for slot, def in K.DEFAULT do
		out[slot] = type(lo) == "table" and lo[slot] or def
	end
	return out
end

-- The loadout shown for an index: the selected one is the resolved Kit (what you spawn with), the others are cleaned.
function K.Loadout(d, index)
	index = index or d.Selected
	if index == d.Selected and type(d.Kit) == "table" and d.Kit.Class then
		local out = {}
		for slot, def in K.DEFAULT do
			out[slot] = d.Kit[slot] or def
		end
		return out
	end
	return K.Clean(d, d.Loadouts[index])
end

function K.GunInfo(gun)
	local info = K.GunStats and gun and K.GunStats.Info(gun)
	return info or { Name = gun or "", Category = "", Slot = nil, Level = 1, Role = "" }
end

-- picks (optional): {slot = id} attachments on the gun (Shared.Attachments)
function K.Bars(gun, picks)
	local b = K.GunStats and gun and K.GunStats.Bars(gun, picks)
	if type(b) ~= "table" then
		b = {}
	end
	return b
end

-- Does this gun take any attachment (the Picker's ATTACHMENTS button, the Gunsmith page)?
function K.Attachable(gun)
	if not (K.Attach and gun) then
		return false
	end
	for _, slot in K.Attach.Slots do
		if #K.Attach.Allowed(gun, slot) > 0 then
			return true
		end
	end
	return false
end

function K.GunList(slot)
	if K.GunStats and K.GunStats.List then
		return K.GunStats.List(slot)
	end
	local out = {}
	if K.P then
		for _, g in K.P.Guns do
			if K.P.Slots[g] == slot then
				table.insert(out, g)
			end
		end
	end
	return out
end

function K.GearList(slot)
	local out = {}
	local items = K.Gear and K.Gear.Items or {}
	for key, it in items do
		if it.Slot == slot then
			table.insert(out, key)
		end
	end
	table.sort(out, function(a, b)
		local la, lb = K.ItemLevel(a), K.ItemLevel(b)
		if la ~= lb then
			return la < lb
		end
		return a < b
	end)
	return out
end

function K.ItemLevel(item)
	local lvl = K.P and K.P.UnlockLevel and K.P.UnlockLevel(item)
	if lvl then
		return lvl
	end
	local g = K.Gear and K.Gear.Items and K.Gear.Items[item]
	if g and g.Level then
		return g.Level
	end
	local info = K.GunStats and K.GunStats.Info(item)
	return info and info.Level or 1
end

function K.WeaponLevel(d, gun)
	if K.P and K.P.WeaponFromXp then
		return (K.P.WeaponFromXp(d.GunXp[gun]))
	end
	return 1
end

-- ok, reason for a loadout slot (Class, Primary, Secondary, Lethal, Tactical).
function K.CanEquip(d, slot, item)
	if K.Rules and K.Rules.CanEquip then
		local ok, good, reason = pcall(K.Rules.CanEquip, slot, item, d.Level, d.Stats, d.Owned)
		if ok then
			return good, reason
		end
	end
	if slot == "Class" and K.P then
		return K.P.ClassUnlocked(item, d.Level, d.Stats, d.Owned), "Locked"
	end
	return d.Level >= K.ItemLevel(item), "Locked"
end

function K.LethalPerk(classId)
	local c = K.P and K.P.Classes and K.P.Classes[classId]
	return c and c.Perks and c.Perks.LethalCount or 1
end

function K.GearCount(key, classId)
	if K.Gear and K.Gear.CountFor then
		return K.Gear.CountFor(key, K.LethalPerk(classId))
	end
	return 1
end

function K.GearName(key)
	local g = K.Gear and K.Gear.Items and K.Gear.Items[key]
	return g and g.Name or K.Upper(key)
end

-- catalogue ----------------------------------------------------------------------------------------------------------

function K.Item(itemId)
	return K.C and K.C.Items and K.C.Items[itemId]
end

function K.CatCtx(d, gun)
	return {
		Level = d.Level,
		Owned = d.Owned,
		GunXp = d.GunXp,
		GunStats = d.GunStats,
		Stats = d.Stats,
		Beams = d.Beams,
		Vip = d.Vip,
		Gun = gun,
	}
end

function K.Available(d, itemId, gun)
	if not (K.C and K.C.Available) then
		return false
	end
	return (K.C.Available(itemId, K.CatCtx(d, gun)))
end

-- Short rule text for a locked item ("LV 25", "4,500", "PASS 10", "STARTER", "LV 15" for weapon levels).
function K.Rule(itemId)
	local it = K.Item(itemId)
	local s = it and it.Source
	if not s then
		return ""
	end
	if s.Kind == "Level" or s.Kind == "WeaponLevel" then
		return "LV " .. tostring(s.Level)
	elseif s.Kind == "Store" then
		return K.Money(s.Scrip)
	elseif s.Kind == "Pass" then
		return "PASS " .. tostring(s.Tier)
	elseif s.Kind == "Starter" then
		return "STARTER"
	elseif s.Kind == "Mastery" then
		return K.MASTERY[s.Rule] or "MASTERY"
	elseif s.Kind == "Robux" then
		local p = K.C.Products[s.Key]
		return p and p.Name or "R$"
	elseif s.Kind == "Group" then
		return "GROUP"
	end
	return ""
end

-- Operators in card order: default, level, starter, store (by price), pass.
function K.Operators()
	local list = {}
	local order = { Default = 1, Level = 2, Starter = 3, Store = 4, Pass = 5, Robux = 6, Group = 7, Mastery = 8 }
	for itemId, it in (K.C and K.C.Items or {}) do
		if it.Kind == "Operator" then
			table.insert(list, itemId)
		end
	end
	table.sort(list, function(a, b)
		local sa, sb = K.C.Items[a].Source, K.C.Items[b].Source
		local oa, ob = order[sa.Kind] or 9, order[sb.Kind] or 9
		if oa ~= ob then
			return oa < ob
		end
		local va = sa.Level or sa.Scrip or sa.Tier or 0
		local vb = sb.Level or sb.Scrip or sb.Tier or 0
		if va ~= vb then
			return va < vb
		end
		return a < b
	end)
	return list
end

-- Camo ids in menu order.
function K.CamoOrder()
	if K.Camo and K.Camo.Order then
		return K.Camo.Order
	end
	local list = {}
	for _, it in (K.C and K.C.Items or {}) do
		if it.Kind == "Camo" then
			table.insert(list, it.Id)
		end
	end
	table.sort(list)
	return list
end

-- products -----------------------------------------------------------------------------------------------------------

-- The product id the server would prompt: the catalogue id, or the old GameConfig.Store id (StoreServer.productId).
function K.ProductId(key)
	local p = K.C and K.C.Products and K.C.Products[key]
	if not p then
		return 0
	end
	if p.Id ~= 0 then
		return p.Id
	end
	local legacy = K.GameConfig and K.GameConfig.Store
	if legacy then
		if key == "Vip" and legacy.Vip then
			return legacy.Vip.Pass or 0
		elseif key == "StarterPack" and legacy.StarterPack then
			return legacy.StarterPack.Product or 0
		elseif key == "Revive" and legacy.Revive then
			return legacy.Revive.Product or 0
		end
	end
	return 0
end

function K.Live(key)
	return K.ProductId(key) ~= 0
end

local priceCache = {}
-- The live Robux price (async; calls back once it is known). Falls back to the planned price at once.
function K.RobuxPrice(key, cb)
	local p = K.C and K.C.Products and K.C.Products[key]
	if not p then
		return 0
	end
	if priceCache[key] then
		return priceCache[key]
	end
	local id = K.ProductId(key)
	if id ~= 0 and cb then
		task.spawn(function()
			local info = p.Type == "Pass" and Enum.InfoType.GamePass or Enum.InfoType.Product
			local ok, res = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, info)
			if ok and type(res) == "table" and tonumber(res.PriceInRobux) then
				priceCache[key] = res.PriceInRobux
				cb(res.PriceInRobux)
			end
		end)
	end
	return p.Robux or 0
end

-- seen (NEW pips) ----------------------------------------------------------------------------------------------------

local pendingSeen, flushQueued, localSeen = {}, false, {}
-- Mark keys seen with one Store "Seen" call per half second.
function K.MarkSeen(ctx, ids)
	for _, id in ids do
		if type(id) == "string" and not localSeen[id] then
			localSeen[id] = true
			table.insert(pendingSeen, id)
		end
	end
	if #pendingSeen == 0 or flushQueued then
		return
	end
	flushQueued = true
	task.delay(0.5, function()
		flushQueued = false
		local batch = pendingSeen
		pendingSeen = {}
		if #batch > 0 then
			ctx.store("Seen", { Ids = batch })
		end
	end)
end

function K.IsSeen(d, key)
	return d.Seen[key] == true or localSeen[key] == true
end

-- NEW: unlocked (or owned) and not yet seen.
function K.NewFor(d, slot)
	if slot == "Class" then
		for id in (K.P and K.P.Classes or {}) do
			if not K.IsSeen(d, "Class/" .. id) and K.P.ClassUnlocked(id, d.Level, d.Stats, d.Owned) then
				return true
			end
		end
	elseif K.GUN_SLOTS[slot] then
		for _, g in K.GunList(slot) do
			if not K.IsSeen(d, "Gun/" .. g) and d.Level >= K.ItemLevel(g) then
				return true
			end
		end
	elseif K.GEAR_SLOTS[slot] then
		for _, g in K.GearList(slot) do
			if not K.IsSeen(d, "Gear/" .. g) and d.Level >= K.ItemLevel(g) then
				return true
			end
		end
	elseif slot == "Operator" then
		for _, itemId in K.Operators() do
			local it = K.Item(itemId)
			if it.Source.Kind ~= "Default" and not K.IsSeen(d, itemId) and K.Available(d, itemId) then
				return true
			end
		end
	end
	return false
end

-- stat bars ----------------------------------------------------------------------------------------------------------

-- Place one authored bar's clip over [a, b] of the track (fractions). The Fill inside keeps its place on the track.
local function segment(bar, a, b, time)
	if not bar then
		return
	end
	local clip = bar:FindFirstChild("Clip")
	if not clip then
		return
	end
	local fill = clip:FindFirstChild("Fill")
	a = math.clamp(a, 0, 1)
	b = math.clamp(b, a, 1)
	local w = (fill and fill.Size.X.Offset > 0 and fill.Size.X.Offset) or bar.Size.X.Offset
	local props = { Position = UDim2.fromScale(a, 0), Size = UDim2.fromScale(b - a, 1) }
	if time and time > 0 then
		local TweenService = game:GetService("TweenService")
		TweenService:Create(clip, TweenInfo.new(time, Enum.EasingStyle.Quad), props):Play()
		if fill then
			TweenService:Create(fill, TweenInfo.new(time, Enum.EasingStyle.Quad), { Position = UDim2.fromOffset(-a * w, 0) }):Play()
		end
	else
		clip.Position = props.Position
		clip.Size = props.Size
		if fill then
			fill.Position = UDim2.fromOffset(-a * w, 0)
		end
	end
end
K.Segment = segment

-- One stat row: Ghost = equipped, Value = the shared part, Gain or Loss = the difference (MW style).
function K.StatRow(row, viewed, equipped, time)
	if not row then
		return
	end
	viewed = math.clamp(tonumber(viewed) or 0, 0, 1)
	equipped = math.clamp(tonumber(equipped) or viewed, 0, 1)
	-- only the ghost keeps its track, so the other three bars never cover each other's fill
	for _, n in { "Value", "Gain", "Loss" } do
		local t = K.Child(row, n .. "/Track")
		if t then
			t.Visible = false
		end
	end
	segment(row:FindFirstChild("Ghost"), 0, equipped, time)
	if viewed > equipped + 1e-3 then
		segment(row:FindFirstChild("Value"), 0, equipped, time)
		segment(row:FindFirstChild("Gain"), equipped, viewed, time)
		segment(row:FindFirstChild("Loss"), 0, 0, time)
	elseif viewed < equipped - 1e-3 then
		segment(row:FindFirstChild("Value"), 0, viewed, time)
		segment(row:FindFirstChild("Loss"), viewed, equipped, time)
		segment(row:FindFirstChild("Gain"), 0, 0, time)
	else
		segment(row:FindFirstChild("Value"), 0, viewed, time)
		segment(row:FindFirstChild("Gain"), 0, 0, time)
		segment(row:FindFirstChild("Loss"), 0, 0, time)
	end
end

-- All six rows under a stats frame, viewed gun against the equipped gun.
-- viewedPicks / equippedPicks (optional): attachments on each gun, so the bars show the guns as they play.
function K.Stats(frame, viewedGun, equippedGun, time, viewedPicks, equippedPicks)
	if not frame then
		return
	end
	local v = K.Bars(viewedGun, viewedPicks)
	local e = K.Bars(equippedGun or viewedGun, if equippedGun then equippedPicks else viewedPicks)
	for _, stat in K.STATS do
		K.StatRow(frame:FindFirstChild(stat), v[stat] or 0, e[stat] or v[stat] or 0, time)
	end
end

return K
