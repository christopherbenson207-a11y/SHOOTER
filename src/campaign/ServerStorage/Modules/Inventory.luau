-- What each player carries (GameConfig.Inventory): Slots slots, each { Item, Count } or empty.
-- The server owns it; clients read the player attribute "Inventory", written as
-- "Item:Count|Item:Count|" with an empty field for an empty slot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local CFG = GameConfig.Inventory

local Inventory = {}

local inventories = {} -- [player] = { [1..Slots] = { Item, Count } | false }

local function publish(player)
	local slots = inventories[player]
	local fields = {}
	for i = 1, CFG.Slots do
		local slot = slots[i]
		fields[i] = if slot then slot.Item .. ":" .. slot.Count else ""
	end
	player:SetAttribute("Inventory", table.concat(fields, "|"))
end

local function stackMax(item)
	return CFG.Stack[item] or 1
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

function Inventory.FreeSlot(player)
	local slots = inventories[player]
	for i = 1, CFG.Slots do
		if slots and not slots[i] then
			return i
		end
	end
	return nil
end

-- Adds up to n of item: onto its stack, or into a free slot. Returns how many went in.
function Inventory.Add(player, item, n)
	local slots = inventories[player]
	if not slots then
		return 0
	end
	local i = Inventory.IndexOf(player, item)
	if not i then
		i = Inventory.FreeSlot(player)
		if not i then
			return 0
		end
		slots[i] = { Item = item, Count = 0 }
	end
	local add = math.min(n, stackMax(item) - slots[i].Count)
	if add <= 0 then
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

local function reset(player)
	local slots = {}
	for i = 1, CFG.Slots do
		local start = CFG.Start[i]
		slots[i] = if start then { Item = start[1], Count = start[2] } else false
	end
	inventories[player] = slots
	publish(player)
end

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
	end)
end

return Inventory
