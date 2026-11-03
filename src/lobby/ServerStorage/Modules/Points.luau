-- Match points (Call of Duty Zombies): earned by shooting zombies and repairing windows,
-- spent on debris, guns, supplies and the mystery crate. The server owns them; clients read
-- the player attribute "Points" (the HUD ticks it up quietly, no floating numbers). PointsEarned
-- adds up everything earned this match (MatchServer pays a share of it out as Scrip).
-- Numbers: GameConfig.Match.Points.
-- Upgrade stations (menu revamp, MENU-PLAN 9.4): Points.Start() also turns the Defend house stands into stations.
-- KitchenTable and BedroomTable get an "Upgrade" prompt that raises the held gun's tier for this run (player
-- attribute Tiers, JSON gun -> 1..5; prices and damage in GameConfig.Director.Tiers, MobReactions applies the
-- damage), and SupplyStand gets "Gear" (lethal and tactical back to the kit count, through ServerStorage.GearApi) and,
-- once PlayerHealth spends the character attribute Plate, "Armour" (Director.Supply.Armour.Live). Prompts carry the
-- attribute Station; GearClient writes each player's own price on the Upgrade prompt. Points.Reset clears Tiers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local CFG = GameConfig.Match.Points

local Points = {}

function Points.Get(player)
	return player:GetAttribute("Points") or 0
end

function Points.Add(player, amount)
	if amount > 0 and player.Parent then
		-- Scavenger (an Endless relic, ServerStorage.Modules.Relics) pays RelicPoints more.
		amount = math.floor(amount * (1 + (player:GetAttribute("RelicPoints") or 0)) + 0.5)
		player:SetAttribute("Points", Points.Get(player) + amount)
		player:SetAttribute("PointsEarned", (player:GetAttribute("PointsEarned") or 0) + amount)
	end
end

function Points.CanAfford(player, cost)
	return Points.Get(player) >= cost
end

-- Takes cost from the player. Returns false (and takes nothing) if they can't afford it.
function Points.Spend(player, cost)
	if not Points.CanAfford(player, cost) then
		return false
	end
	player:SetAttribute("Points", Points.Get(player) - cost)
	return true
end

function Points.Reset(player)
	player:SetAttribute("Points", CFG.Start)
	player:SetAttribute("PointsEarned", 0)
	player:SetAttribute("Tiers", nil)
end

-- Upgrade stations ----------------------------------------------------------------------------------------------

local function tiersOf(player)
	local raw = player:GetAttribute("Tiers")
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(t) == "table" then t else {}
end

-- The tier (1..5) of a gun for this player this run.
function Points.Tier(player, gun)
	return tonumber(tiersOf(player)[gun]) or 1
end

-- The highest tier this player bought on any gun this run (1 when none); the director scales by it.
function Points.MaxTier(player)
	local best = 1
	for _, n in tiersOf(player) do
		best = math.max(best, tonumber(n) or 1)
	end
	return best
end

local function broke(player)
	local match = ReplicatedStorage.Remotes:FindFirstChild("Match")
	if match then
		match:FireClient(player, "Broke")
	end
end

local function upgrade(player)
	local api = ServerStorage:FindFirstChild("GunsApi")
	local ok, gun = pcall(function()
		return api and api:Invoke("Current", player)
	end)
	if not ok or type(gun) ~= "string" or gun == "" then
		return
	end
	local list = GameConfig.Director.Tiers
	local tiers = tiersOf(player)
	local now = tonumber(tiers[gun]) or 1
	local nextTier = list[now + 1]
	if not nextTier then
		return
	end
	if not Points.Spend(player, nextTier.Cost) then
		broke(player)
		return
	end
	tiers[gun] = now + 1
	player:SetAttribute("Tiers", HttpService:JSONEncode(tiers))
	local gear = ReplicatedStorage.Remotes:FindFirstChild("Gear")
	if gear then
		gear:FireClient(player, "Fx", { Kind = "Upgrade", Gun = gun, Tier = now + 1, Owner = player })
	end
end

local function gearRefill(player)
	local cost = GameConfig.Director.Supply.Gear.Cost
	local api = ServerStorage:FindFirstChild("GearApi")
	if not api or not Points.CanAfford(player, cost) then
		broke(player)
		return
	end
	local before = api:Invoke("Counts", player) or {}
	api:Invoke("Refill", player)
	local after = api:Invoke("Counts", player) or {}
	if (after.Lethal or 0) ~= (before.Lethal or 0) or (after.Tactical or 0) ~= (before.Tactical or 0) then
		Points.Spend(player, cost)
	end
end

local function armour(player)
	local cfg = GameConfig.Director.Supply.Armour
	local character = player.Character
	if not character or (character:GetAttribute("Plate") or 0) >= cfg.Soak then
		return
	end
	if not Points.Spend(player, cfg.Cost) then
		broke(player)
		return
	end
	character:SetAttribute("Plate", cfg.Soak)
end

local function prompt(part, station, action, object, run)
	local p = Instance.new("ProximityPrompt")
	p.Name = "Station" .. station
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0.35
	p.MaxActivationDistance = 8
	p.RequiresLineOfSight = false
	p:SetAttribute("Station", station)
	p.Triggered:Connect(function(player)
		if player:GetAttribute("InMatch") ~= false then
			run(player)
		end
	end)
	p.Parent = part
	return p
end

local function tablePart(model)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			return d
		end
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local stationsBuilt = false
function Points.Stations()
	if stationsBuilt then
		return
	end
	local map = workspace:FindFirstChild("Map")
	local house = nil
	for _, child in map and map:GetChildren() or {} do
		if child:GetAttribute("DefendHouse") then
			house = child
		end
	end
	local shop = house and house:FindFirstChild("Shop")
	if not shop then
		return
	end
	stationsBuilt = true
	local supply = GameConfig.Director.Supply
	for _, name in { "KitchenTable", "BedroomTable" } do
		local model = shop:FindFirstChild(name)
		local part = model and tablePart(model)
		if part then
			prompt(part, "Upgrade", "Upgrade", "Held gun", upgrade)
		end
	end
	local stand = shop:FindFirstChild("SupplyStand")
	local part = stand and tablePart(stand)
	if part then
		prompt(part, "Gear", "Refill " .. supply.Gear.Cost, "Gear", gearRefill)
		if supply.Armour.Live then
			prompt(part, "Armour", "Buy " .. supply.Armour.Cost, "Armour", armour)
		end
	end
end

function Points.Start()
	Points.Stations()
	local function onPlayer(player)
		if player:GetAttribute("Points") == nil then
			Points.Reset(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

return Points
