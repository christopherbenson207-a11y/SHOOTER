-- One way for everything in the war to hurt everything else (horror-shooter/war/WAR-V2-CONTRACTS.md):
-- soldiers (Modules.Soldier), players (PlayerHealth), zombies and other mobs (MobReactions) and
-- vehicles that register themselves (tanks). Emplaced guns, artillery and tanks call this; soldiers'
-- own rifles keep their own path in Soldier:Shoot.
--   by = { Side = "Ally" | "Enemy", Player = the player who did it (credit), Kind = "Bullet" |
--   "Blast" | "Shell", Gun = a GameConfig.Guns name (a player's emplaced gun: its Feel for hit
--   reactions), Model = the shooter's model (rays ignore it) }.
--   Sides: a player's is its attribute Side ("Ally" unless WarServer says otherwise), a soldier's or
--   vehicle's its model attribute Side, a mob is "Enemy". Nothing hurts its own side.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlayerHealth = require(script.Parent.PlayerHealth)
local MobReactions = require(script.Parent.MobReactions)
local Soldier = require(script.Parent.Soldier)

local WarDamage = {}

local vehicles = {} -- [model] = function(amount, fromPos, by) -> dealt, killed

function WarDamage.RegisterVehicle(model, hurt)
	vehicles[model] = hurt
end

function WarDamage.UnregisterVehicle(model)
	vehicles[model] = nil
end

-- The model a part belongs to: the nearest ancestor model with a Humanoid, or a registered vehicle.
function WarDamage.ModelOf(part)
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") and (vehicles[node] or node:FindFirstChildOfClass("Humanoid")) then
			return node
		end
		node = node.Parent
	end
	return nil
end

function WarDamage.PlayerSide(player)
	return player:GetAttribute("Side") or "Ally"
end

function WarDamage.SideOf(model)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return WarDamage.PlayerSide(player)
	end
	local side = model:GetAttribute("Side")
	if side then
		return side
	end
	if CollectionService:HasTag(model, "Enemy") then
		return "Enemy"
	end
	if CollectionService:HasTag(model, "Ally") then
		return "Ally"
	end
	return nil
end

function WarDamage.Hostile(a, b)
	return a ~= nil and b ~= nil and a ~= b
end

-- Hurts model by amount from fromPos, if it is on the other side from by.Side. part/hitPos: where
-- it was struck (a head part counts double for bullets). Returns dealt, killed.
function WarDamage.Apply(model, amount, fromPos, by, part, hitPos)
	if not model or not model.Parent or amount <= 0 then
		return 0, false
	end
	if not WarDamage.Hostile(by.Side, WarDamage.SideOf(model)) then
		return 0, false
	end
	local vehicle = vehicles[model]
	if vehicle then
		return vehicle(amount, fromPos, by)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or model:GetAttribute("Dead") then
		return 0, false
	end
	-- Kill credit (FRONTLINE reads it when the body falls).
	if by.Player then
		model:SetAttribute("LastHitBy", by.Player.UserId)
		model:SetAttribute("LastHitAt", workspace:GetServerTimeNow())
	end
	local isHead = part ~= nil and (part.Name == "Head" or part:GetAttribute("Limb") == "Head")
	if isHead and by.Kind == "Bullet" then
		amount *= 2
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		PlayerHealth.Damage(player, amount, fromPos, if by.Kind == "Bullet" then "Bullet" else "Blast")
		return amount, humanoid.Health <= 0
	end
	local soldier = Soldier.FromModel(model)
	if CollectionService:HasTag(model, "Enemy") and (by.Player or not soldier) then
		-- A player's shot (points, the kill feed) or a mob: MobReactions does the hit.
		local at = hitPos or (part and part.Position) or (model.PrimaryPart and model.PrimaryPart.Position) or fromPos
		local gunName = by.Gun or "AK"
		local killed, _, total = MobReactions.Hit(model, { { Part = part or model.PrimaryPart, Damage = amount, Pos = at, IsHead = isHead } }, {
			Player = by.Player,
			Gun = GameConfig.Guns[gunName] or GameConfig.Guns.AK,
			GunName = gunName,
			HitPos = at,
			Dir = (at - fromPos).Magnitude > 0.01 and (at - fromPos).Unit or Vector3.zAxis,
			Distance = (at - fromPos).Magnitude,
			Share = 1,
		})
		if soldier then
			soldier.HurtFrom = fromPos
		end
		return total or amount, killed
	end
	if soldier then
		soldier:Hurt(amount, fromPos)
		return amount, not soldier.Alive or humanoid.Health <= 0
	end
	humanoid:TakeDamage(amount)
	return amount, humanoid.Health <= 0
end

local function rayParams(by, ignore)
	local list = { workspace:FindFirstChild("Fx") }
	local map = workspace:FindFirstChild("Map")
	table.insert(list, map and map:FindFirstChild("War"))
	if by.Model then
		table.insert(list, by.Model)
	end
	for _, i in ignore or {} do
		table.insert(list, i)
	end
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = list
	p.IgnoreWater = true
	p.RespectCanCollide = false
	return p
end

-- A round from origin along dir (unit) for up to range studs. Returns the RaycastResult (or nil),
-- the model it struck (or nil), dealt and killed.
function WarDamage.Ray(origin, dir, range, amount, by, ignore)
	local hit = workspace:Raycast(origin, dir * range, rayParams(by, ignore))
	if not hit then
		return nil, nil, 0, false
	end
	local model = WarDamage.ModelOf(hit.Instance)
	if not model then
		return hit, nil, 0, false
	end
	local dealt, killed = WarDamage.Apply(model, amount, origin, by, hit.Instance, hit.Position)
	return hit, model, dealt, killed
end

-- A blast at center: full amount at the middle down to a quarter at radius, a third behind solid
-- cover. Every soldier, player, mob and vehicle of the other side in reach. Returns how many it hurt.
function WarDamage.Blast(center, radius, amount, by, opts)
	opts = opts or {}
	local params = rayParams(by)
	params.RespectCanCollide = true
	local count = 0
	local done = {}
	local function try(model, at)
		if done[model] or not model.Parent then
			return
		end
		done[model] = true
		local d = (at - center).Magnitude
		if d > radius then
			return
		end
		local k = 1 - 0.75 * (d / radius)
		local block = workspace:Raycast(center + Vector3.new(0, 0.5, 0), at - center, params)
		if block and not block.Instance:IsDescendantOf(model) and (block.Position - at).Magnitude > 2 then
			k *= 0.35
		end
		local scale = if vehicles[model] then (opts.Vehicles or 1) else 1
		local dealt = WarDamage.Apply(model, amount * k * scale, center, by, nil, at)
		if dealt > 0 then
			count += 1
		end
	end
	for _, s in Soldier.All() do
		try(s.Model, s.Root.Position)
	end
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if root then
			try(c, root.Position)
		end
	end
	for _, mob in CollectionService:GetTagged("Enemy") do
		local root = mob:IsA("Model") and mob.PrimaryPart
		if root then
			try(mob, root.Position)
		end
	end
	for model in vehicles do
		local root = model.PrimaryPart
		if root then
			try(model, root.Position)
		end
	end
	return count
end

return WarDamage
