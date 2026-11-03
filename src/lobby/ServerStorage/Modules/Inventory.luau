-- What each player carries (GameConfig.Inventory): Slots slots, each { Item, Count } or empty.
-- The server owns it; clients read the player attribute "Inventory", written as
-- "Item:Count|Item:Count|" with an empty field for an empty slot.
-- Every life starts from the kit (ServerStorage.Modules.Kit, menu revamp 3 Nov 2026): the primary in slot 1, the
-- secondary in slot 2 (a kit without a primary puts the secondary in slot 1), slot 3 free for a gun picked up,
-- and the bandage stack in BandageSlot (4). Lethal and tactical gear are counts, not slots: the player attributes
-- GearCounts (JSON {Lethal = n, Tactical = n}) and GearKit (JSON {Lethal = key, Tactical = key}).
-- In a place without Modules.Kit the old GameConfig.Inventory.Start kit is used instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local CFG = GameConfig.Inventory
local GUN_SLOTS = CFG.GunSlots or CFG.Slots
local BANDAGE_SLOT = CFG.BandageSlot

local Kit = nil
do
	local m = script.Parent:FindFirstChild("Kit")
	if m then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" and mod.Resolve then
			Kit = mod
		else
			warn("Inventory: Modules.Kit failed to load, using GameConfig.Inventory.Start", mod)
		end
	end
end

local Inventory = {}

local inventories = {} -- [player] = { [1..Slots] = { Item, Count } | false }
local gear = {} -- [player] = { Lethal = { Key, Count } | nil, Tactical = { Key, Count } | nil }
local kits = {} -- [player] = the kit this life started from

local function publish(player)
	local slots = inventories[player]
	local fields = {}
	for i = 1, CFG.Slots do
		local slot = slots[i]
		fields[i] = if slot then slot.Item .. ":" .. slot.Count else ""
	end
	player:SetAttribute("Inventory", table.concat(fields, "|"))
end

local function publishGear(player)
	local g = gear[player] or {}
	local counts, keys = {}, {}
	for _, slot in { "Lethal", "Tactical" } do
		counts[slot] = if g[slot] then g[slot].Count else 0
		keys[slot] = if g[slot] then g[slot].Key else nil
	end
	player:SetAttribute("GearCounts", HttpService:JSONEncode(counts))
	player:SetAttribute("GearKit", HttpService:JSONEncode(keys))
end

local function stackMax(item)
	return CFG.Stack[item] or 1
end

-- The slot an item always lives in (the bandage stack), or nil.
local function homeSlot(item)
	return if item == "Bandage" then BANDAGE_SLOT else nil
end

function Inventory.Slots(player)
	return inventories[player] or {}
end

function Inventory.IndexOf(player, item)
	local slots = inventories[player]
	for i = 1, CFG.Slots do
		if slots and slots[i] and slots[i].Item == item then
			return i
		end
	end
	return nil
end

function Inventory.Count(player, item)
	local i = Inventory.IndexOf(player, item)
	return if i then inventories[player][i].Count else 0
end

-- The first empty gun slot (the bandage slot is never offered).
function Inventory.FreeSlot(player)
	local slots = inventories[player]
	for i = 1, GUN_SLOTS do
		if slots and not slots[i] then
			return i
		end
	end
	return nil
end

-- Adds up to n of item: onto its stack, into its home slot, or into a free gun slot. Returns how many went in.
function Inventory.Add(player, item, n)
	local slots = inventories[player]
	if not slots then
		return 0
	end
	local i = Inventory.IndexOf(player, item)
	if not i then
		local home = homeSlot(item)
		if home and not slots[home] then
			i = home
		else
			i = Inventory.FreeSlot(player)
		end
		if not i then
			return 0
		end
		slots[i] = { Item = item, Count = 0 }
	end
	local add = math.min(n, stackMax(item) - slots[i].Count)
	if add <= 0 then
		if slots[i].Count <= 0 then
			slots[i] = false
		end
		return 0
	end
	slots[i].Count += add
	publish(player)
	return add
end

-- Uses up n of item. Returns false if there weren't enough. An emptied slot frees up.
function Inventory.Take(player, item, n)
	local i = Inventory.IndexOf(player, item)
	local slots = inventories[player]
	if not i or slots[i].Count < n then
		return false
	end
	slots[i].Count -= n
	if slots[i].Count <= 0 then
		slots[i] = false
	end
	publish(player)
	return true
end

-- Puts item (count) in slot i, replacing whatever was there.
function Inventory.Set(player, i, item, count)
	local slots = inventories[player]
	if not slots then
		return
	end
	slots[i] = if item then { Item = item, Count = count or 1 } else false
	publish(player)
end

-- Gear (lethal and tactical) ----------------------------------------------------------------------------------

-- The kit this life started from ({Class, Primary, Secondary, Lethal, Tactical, Field}), or nil.
function Inventory.Kit(player)
	return kits[player]
end

-- key, count of the gear in slot ("Lethal" | "Tactical"); nil, 0 when there is none.
function Inventory.Gear(player, slot)
	local g = gear[player] and gear[player][slot]
	if not g then
		return nil, 0
	end
	return g.Key, g.Count
end

-- Uses one of the gear in slot. Returns its key, or nil if there was none left.
function Inventory.TakeGear(player, slot)
	local g = gear[player] and gear[player][slot]
	if not g or g.Count <= 0 then
		return nil
	end
	g.Count -= 1
	publishGear(player)
	return g.Key
end

-- Gives n more of the gear in slot (at most the kit count; nil n fills it). Returns how many went in.
function Inventory.AddGear(player, slot, n)
	local g = gear[player] and gear[player][slot]
	local kit = kits[player]
	if not g or not kit or not Kit then
		return 0
	end
	local max = Kit.GearCount(kit, slot)
	local add = math.min(n or max, max - g.Count)
	if add <= 0 then
		return 0
	end
	g.Count += add
	publishGear(player)
	return add
end

-- Fills lethal and tactical back to the kit count (ammo crates, supply drops, the house stations).
-- Returns true if anything went in.
function Inventory.RefillGear(player)
	local a = Inventory.AddGear(player, "Lethal")
	local b = Inventory.AddGear(player, "Tactical")
	return a + b > 0
end

-- Spawn --------------------------------------------------------------------------------------------------------

local function legacySlots()
	local slots = {}
	for i = 1, CFG.Slots do
		local start = CFG.Start[i]
		slots[i] = if start then { Item = start[1], Count = start[2] } else false
	end
	return slots
end

local function reset(player)
	local slots
	local kit = nil
	if Kit then
		local ok, resolved = pcall(Kit.Resolve, player)
		if ok and type(resolved) == "table" then
			kit = resolved
		else
			warn("Inventory: Kit.Resolve failed for", player.Name, resolved)
		end
	end
	if kit then
		slots = {}
		for i = 1, CFG.Slots do
			slots[i] = false
		end
		local n = 0
		for _, key in { kit.Primary, kit.Secondary } do
			if key and n < GUN_SLOTS then
				n += 1
				slots[n] = { Item = key, Count = 1 }
			end
		end
		if BANDAGE_SLOT and (CFG.Bandages or 0) > 0 then
			slots[BANDAGE_SLOT] = { Item = "Bandage", Count = CFG.Bandages }
		end
		gear[player] = {}
		for _, slot in { "Lethal", "Tactical" } do
			if kit[slot] then
				gear[player][slot] = { Key = kit[slot], Count = Kit.GearCount(kit, slot) }
			end
		end
	else
		slots = legacySlots()
		gear[player] = {}
	end
	kits[player] = kit
	inventories[player] = slots
	publish(player)
	publishGear(player)
end

-- Rebuilds this life's inventory from the kit now (Inventory.Start does it on every spawn).
Inventory.Reset = reset

function Inventory.Start()
	local function onPlayer(player)
		player.CharacterAdded:Connect(function()
			reset(player)
		end)
		reset(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		inventories[player] = nil
		gear[player] = nil
		kits[player] = nil
	end)
end

return Inventory
