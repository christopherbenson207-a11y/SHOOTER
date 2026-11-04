-- GearServer (MATCH, menu revamp 3 Nov 2026; CONTRACTS sections 2, 4, 5, 6; MENU-PLAN 4.6, 9.5, 9.10, 9.11).
-- Lethal, tactical and field items, all server-validated. Numbers live in ReplicatedStorage.Shared.Gear.
--   Remotes.Gear, client to server: "Throw", {Slot = "Lethal"|"Tactical", Origin, Direction, Id}
--                                   "Field", {Origin, Direction, Id}     "Detonate"
--   Server to all clients: "Fx", {Kind, Owner, Key, Origin, Velocity, Id, ...}. Kinds: Throw (an item in flight;
--   clients draw it along Shared.Gear.Simulate), Land, Blast, Flash, Fire, Smoke, Recon, Mark, Spray, Place, Heal,
--   Stim, Denied (to the owner only).
-- Each life the player carries the kit's lethal and tactical (Kit.Resolve). The counts live in Modules.Inventory (GUNS:
-- Gear, TakeGear, RefillGear; it publishes the player attributes GearKit {Lethal, Tactical} and GearCounts
-- {Lethal = n, Tactical = n}). GearServer only keeps counts of its own for gear Inventory does not hold (the Studio
-- GearTest kit, or a place without the new Inventory) and then publishes the merged GearKit and GearCounts itself.
-- GearServer writes GearField (the class field item key), FieldReadyAt (server time the field item is ready again;
-- 90 s cooldown) and ChargeOut (a placed Breaching Charge waits for the field key).
-- Effects go through MobReactions.Hit (gun-shaped Hit tables, ctx.GunName = the gear key, ctx.Gear = true, so kills
-- reach Progression through EnemyHit), WorldDamage.Hit and the Gunshot event (the Beacon and the sleepers hear frags
-- and flashbangs). A Flare and a Decoy lure common mobs (MobAI.Lure); a Flare also fires Events.BeaconLure(position,
-- 6) for the Beacon. A Molotov is a fire pool mobs avoid (MobAI.Hazard). Smoke clouds sit in workspace.GearSmoke as
-- invisible, non-query parts with a Radius attribute (Shared.Gear.SmokeBlocks / SmokeSpheres test sight through them).
-- ServerStorage.GearApi (BindableFunction): Invoke("Refill", player) puts lethal and tactical back to the kit count,
-- Invoke("Counts", player) returns {Lethal, Tactical}.
-- Studio only: workspace attribute GearTest = true gives Frag, Flare and the class field item to anyone whose kit
-- has none (for testing before the loadout screen exists).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local Gear = require(ReplicatedStorage.Shared.Gear)
local MobReactions = require(ServerStorage.Modules.MobReactions)
local MobAI = require(ServerStorage.Modules.MobAI)
local Remotes = ReplicatedStorage.Remotes
local Remote = Remotes:WaitForChild("Gear")
local Events = ServerStorage:WaitForChild("Events")
local Gunshot = Events:WaitForChild("Gunshot")
local GearAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Gear")

local function try(path)
	local ok, m = pcall(require, path)
	return if ok then m else nil
end
local WorldDamage = try(ServerStorage.Modules:FindFirstChild("WorldDamage"))
local Kit = try(ServerStorage.Modules:FindFirstChild("Kit"))
local Inventory = try(ServerStorage.Modules:FindFirstChild("Inventory"))
local invOk = type(Inventory) == "table" and type(Inventory.TakeGear) == "function" and type(Inventory.Gear) == "function"
local Classes = try(ReplicatedStorage.Shared:FindFirstChild("Classes"))
local SoundKit = try(ReplicatedStorage.Shared:FindFirstChild("SoundKit"))
local progression = nil
local function Progression()
	if progression == nil then
		progression = try(ServerStorage.Modules:FindFirstChild("Progression")) or false
	end
	return progression or nil
end

local T = Gear.Throw

-- Folders ---------------------------------------------------------------------------------------------------------

local function folder(name)
	local f = workspace:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
	end
	return f
end
local fxFolder = folder("GearFx") -- resting gear models, fire pools, lights
local smokeFolder = folder("GearSmoke") -- smoke volumes (sight blockers)

local function perk(player, key)
	if not Classes or not Classes.Perk then
		return 1
	end
	local ok, v = pcall(Classes.Perk, player, key)
	return if ok and tonumber(v) then tonumber(v) else 1
end

local function play(name, pos)
	if SoundKit and SoundKit.Play then
		pcall(SoundKit.Play, name, { Position = pos })
	end
end

-- State -----------------------------------------------------------------------------------------------------------

local states = {} -- [player] = {Field, Test = {[slot] = {Key, Count}}, Published, LastThrow, Charge}

-- key, count, isTest of the gear in slot ("Lethal" | "Tactical"): Inventory's first, else GearServer's own test count.
local function gearOf(player, slot)
	if invOk then
		local ok, key, n = pcall(Inventory.Gear, player, slot)
		if ok and key then
			return key, tonumber(n) or 0, false
		end
	end
	local s = states[player]
	local t = s and s.Test and s.Test[slot]
	if t then
		return t.Key, t.Count, true
	end
	return nil, 0, false
end

-- GearField always; GearKit and GearCounts only while GearServer holds test counts (and once more when they go),
-- since Inventory publishes those two for the kit's own gear.
local function publish(player, s)
	player:SetAttribute("GearField", s.Field)
	local hasTest = next(s.Test) ~= nil
	if not hasTest and not s.Published then
		return
	end
	s.Published = hasTest
	local kit, counts = {}, {}
	for _, slot in { "Lethal", "Tactical" } do
		local key, n = gearOf(player, slot)
		kit[slot] = key
		counts[slot] = n
	end
	player:SetAttribute("GearKit", HttpService:JSONEncode(kit))
	player:SetAttribute("GearCounts", HttpService:JSONEncode(counts))
end

local function resolve(player)
	local kit = nil
	if Kit and Kit.Resolve then
		local ok, k = pcall(Kit.Resolve, player)
		kit = ok and type(k) == "table" and k or nil
	end
	kit = kit or {}
	local class = kit.Class or player:GetAttribute("Class") or "Rifleman"
	local lethal = Gear.Items[kit.Lethal or ""] and Gear.Items[kit.Lethal].Slot == "Lethal" and kit.Lethal or nil
	local tactical = Gear.Items[kit.Tactical or ""] and Gear.Items[kit.Tactical].Slot == "Tactical" and kit.Tactical or nil
	local field = Gear.Items[kit.Field or ""] and Gear.Items[kit.Field].Slot == "Field" and kit.Field
		or Gear.FieldFor[class]
	if RunService:IsStudio() and workspace:GetAttribute("GearTest") then
		lethal = lethal or "Frag"
		tactical = tactical or "Flare"
	end
	-- The first match ever is pistol-only: no gear and no field item (LoadoutRules.FirstMatch).
	if player:GetAttribute("FirstMatch") and not kit.Lethal and not kit.Tactical and not workspace:GetAttribute("GearTest") then
		field = nil
	end
	return lethal, tactical, field
end

-- Called at spawn (after Inventory has rebuilt this life), at the run start, by ammo crates and by GearApi.
-- restock = true also fills Inventory's lethal and tactical back to the kit count.
local function refill(player, restock)
	local s = states[player]
	if not s then
		return
	end
	local lethal, tactical, field = resolve(player)
	s.Field = field
	if restock and invOk and Inventory.RefillGear then
		pcall(Inventory.RefillGear, player)
	end
	local test = {}
	for slot, key in { Lethal = lethal or false, Tactical = tactical or false } do
		local held = false
		if invOk then
			local ok, k = pcall(Inventory.Gear, player, slot)
			held = ok and k ~= nil
		end
		if key and not held then
			test[slot] = {
				Key = key,
				Count = if slot == "Lethal" then Gear.CountFor(key, perk(player, "LethalCount")) else Gear.CountFor(key),
			}
		end
	end
	s.Test = test
	publish(player, s)
end

local function onPlayer(player)
	states[player] = { Test = {}, LastThrow = 0 }
	player:SetAttribute("FieldReadyAt", 0)
	player.CharacterAdded:Connect(function()
		task.defer(refill, player) -- after Kit/Inventory have run for this life
	end)
	refill(player)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end
Players.PlayerRemoving:Connect(function(player)
	local s = states[player]
	if s and s.Charge and s.Charge.Model then
		s.Charge.Model:Destroy()
	end
	states[player] = nil
end)

-- Every new run: gear in the world goes, cooldowns reset, counts refill.
local startMatch = Events:FindFirstChild("StartMatch")
if startMatch then
	startMatch.Event:Connect(function()
		fxFolder:ClearAllChildren()
		smokeFolder:ClearAllChildren()
		for _, p in Players:GetPlayers() do
			p:SetAttribute("FieldReadyAt", 0)
			p:SetAttribute("ChargeOut", nil)
			local s = states[p]
			if s then
				s.Charge = nil
			end
			refill(p, true)
		end
	end)
end

local api = Instance.new("BindableFunction")
api.Name = "GearApi"
api.OnInvoke = function(action, player)
	if action == "Refill" then
		refill(player, true)
		return true
	elseif action == "Counts" then
		if not states[player] then
			return nil
		end
		local _, lethal = gearOf(player, "Lethal")
		local _, tactical = gearOf(player, "Tactical")
		return { Lethal = lethal, Tactical = tactical }
	end
	return nil
end
api.Parent = ServerStorage

-- Checks ----------------------------------------------------------------------------------------------------------

local function finite(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e5 and math.abs(v.Y) < 1e5 and math.abs(v.Z) < 1e5
end

-- The character if it can use gear now (standing, not downed, devoured or bandaging).
local function able(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not humanoid or humanoid.Health <= 0 or not head then
		return nil
	end
	if character:GetAttribute("Downed") or character:GetAttribute("Devoured") or character:GetAttribute("Bandaging")
		or character:GetAttribute("Aboard") then
		return nil
	end
	return character, humanoid, head
end

local function checkAim(head, origin, direction)
	if not finite(origin) or not finite(direction) then
		return nil
	end
	if (origin - head.Position).Magnitude > T.MaxOriginOffset then
		return nil
	end
	local len = direction.Magnitude
	if len < 0.5 or len > 1.5 then
		return nil
	end
	return direction / len
end

-- World queries ---------------------------------------------------------------------------------------------------

local function excludeList(extra)
	local list = { fxFolder, smokeFolder }
	for _, name in { "Zombies", "Fx", "Drops" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, e in extra or {} do
		table.insert(list, e)
	end
	return list
end

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true

local function arcCast(from, delta)
	return workspace:Raycast(from, delta, castParams)
end

-- Mobs: models with a Humanoid and a MobType that are not players.
local function mobOf(part)
	local node = part
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("MobType") and node:FindFirstChildOfClass("Humanoid") then
			if Players:GetPlayerFromCharacter(node) or CollectionService:HasTag(node, "Ally") then
				return nil
			end
			return node
		end
		node = node.Parent
	end
	return nil
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude

local function mobsNear(pos, radius)
	overlap.FilterDescendantsInstances = { fxFolder, smokeFolder }
	local found, list = {}, {}
	for _, part in workspace:GetPartBoundsInRadius(pos, radius, overlap) do
		local mob = mobOf(part)
		if mob and not found[mob] then
			local humanoid = mob:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not mob:GetAttribute("Dead") then
				found[mob] = true
				table.insert(list, mob)
			end
		end
	end
	return list
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.RespectCanCollide = true

-- Whether the blast at pos reaches this mob (nothing solid in between).
local function reaches(pos, mob)
	local root = mob.PrimaryPart or mob:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, nil
	end
	losParams.FilterDescendantsInstances = excludeList({ mob })
	local from = pos + Vector3.new(0, 0.6, 0)
	local hit = workspace:Raycast(from, root.Position - from, losParams)
	return hit == nil, root
end

-- The part of a mob nearest a point (limbs come off near a blast).
local function nearestPart(mob, pos)
	local best, bestD = nil, math.huge
	for _, p in mob:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local d = (p.Position - pos).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best or mob.PrimaryPart
end

-- Effects ---------------------------------------------------------------------------------------------------------

local function hitMob(player, key, item, mob, damage, from, share)
	local part = nearestPart(mob, from)
	if not part then
		return false
	end
	local dir = part.Position - from
	dir = if dir.Magnitude > 0.05 then dir.Unit else Vector3.yAxis
	local ok, killed = pcall(MobReactions.Hit, mob, { { Part = part, Damage = damage, Pos = part.Position, IsHead = false } }, {
		Player = player,
		Gun = item.Hit,
		GunName = key,
		HitPos = part.Position,
		Dir = dir,
		Distance = (part.Position - from).Magnitude,
		Share = share,
		Gear = true,
	})
	if not ok then
		warn("GearServer: MobReactions.Hit failed", killed)
		return false
	end
	if player and player.Parent then
		Remotes.HitConfirm:FireClient(player, mob, false, killed, nil)
	end
	return killed
end

local function blast(player, key, item, pos)
	local radius = (item.Radius or 12) * perk(player, "BlastRadius")
	Remote:FireAllClients("Fx", { Kind = "Blast", Key = key, Owner = player, Origin = pos, Radius = radius })
	play("Gear/Blast", pos)
	if item.Noise then
		Gunshot:Fire(player, pos)
	end
	for _, mob in mobsNear(pos, radius) do
		local clear, root = reaches(pos, mob)
		if clear and root then
			local d = (root.Position - pos).Magnitude
			local k = math.clamp(d / radius, 0, 1)
			hitMob(player, key, item, mob, item.Hit.Damage * (1 - 0.7 * k), pos, 1 - k)
		end
	end
	-- The world takes it too (glass, boards, props).
	if WorldDamage and WorldDamage.Hit and item.WorldDamage then
		losParams.FilterDescendantsInstances = excludeList()
		for _, dir in { Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
			local hit = workspace:Raycast(pos + Vector3.new(0, 0.5, 0), dir * radius * 0.6, losParams)
			if hit then
				pcall(WorldDamage.Hit, hit.Instance, hit.Position, dir, item.WorldDamage, radius * 0.35)
			end
		end
	end
end

local function rest(key, pos, normal, life)
	local template = GearAssets:FindFirstChild(key)
	if not template then
		return nil
	end
	local model = template:Clone()
	local base = model.PrimaryPart and model.PrimaryPart:FindFirstChild("Base")
	local up = if normal and normal.Y > 0.3 then normal else Vector3.yAxis
	local cf = CFrame.lookAt(pos, pos + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2 + Vector3.new(0.01, 0, 0), up)
	if base then
		cf *= base.CFrame:Inverse()
	end
	model:PivotTo(cf)
	model.PrimaryPart.Anchored = true
	model.Parent = fxFolder
	if life then
		Debris:AddItem(model, life)
	end
	return model
end

local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function anchorPart(name, pos, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = size or Vector3.one
	p.CFrame = CFrame.new(pos)
	return p
end

local effects = {}

function effects.Frag(player, key, item, pos)
	blast(player, key, item, pos)
end

function effects.Flashbang(player, key, item, pos)
	Remote:FireAllClients("Fx", { Kind = "Flash", Key = key, Owner = player, Origin = pos, Radius = item.BlindRadius })
	play("Gear/Flash", pos)
	if item.Noise then
		Gunshot:Fire(player, pos)
	end
	for _, mob in mobsNear(pos, item.Radius) do
		if reaches(pos, mob) then
			local elite = MobReactions.IsElite(mob)
			MobReactions.Stun(mob, if elite then item.EliteStun else item.Stun)
		end
	end
end

function effects.Flare(player, key, item, pos, normal)
	local model = rest(key, pos, normal, item.Burn)
	local holder = model and model.PrimaryPart or anchorPart("Flare", pos)
	if not model then
		holder.Parent = fxFolder
		Debris:AddItem(holder, item.Burn)
	end
	light(holder, item.LightColor, item.Light, 2.2)
	emitter(holder, {
		Color = ColorSequence.new(item.LightColor), LightEmission = 1, Rate = 40,
		Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
	})
	emitter(holder, {
		Color = ColorSequence.new(Color3.fromRGB(120, 110, 110)), Rate = 6, Transparency = NumberSequence.new(0.6, 1),
		Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(0, 2, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.5) }),
	})
	MobAI.Lure(pos, item.LureTime, item.LureRadius)
	local lure = Events:FindFirstChild("BeaconLure")
	if lure then
		lure:Fire(pos, item.BeaconLure)
	end
end

function effects.Molotov(player, key, item, pos)
	Remote:FireAllClients("Fx", { Kind = "Fire", Key = key, Owner = player, Origin = pos, Radius = item.Radius, Time = item.Duration })
	play("Gear/Fire", pos)
	local pool = anchorPart("FirePool", pos + Vector3.new(0, 0.2, 0), Vector3.new(item.Radius * 2, 0.4, item.Radius * 2))
	pool.Parent = fxFolder
	light(pool, Color3.fromRGB(255, 140, 60), item.Radius * 2.2, 1.6)
	for _ = 1, 4 do
		local a = anchorPart("Flames", pos + Vector3.new((math.random() - 0.5) * item.Radius, 0.3, (math.random() - 0.5) * item.Radius))
		a.Parent = pool
		local fire = Instance.new("Fire")
		fire.Size = 7
		fire.Heat = 9
		fire.Color = Color3.fromRGB(255, 120, 40)
		fire.SecondaryColor = Color3.fromRGB(255, 200, 80)
		fire.Parent = a
	end
	local hazard = MobAI.Hazard(pos, item.Radius, item.Duration)
	task.spawn(function()
		local t = 0
		while t < item.Duration and hazard.Until > os.clock() do
			t += task.wait(item.Tick)
			for _, mob in mobsNear(pos, item.Radius) do
				local root = mob.PrimaryPart
				if root and math.abs(root.Position.Y - pos.Y) < 6 then
					hitMob(player, key, item, mob, item.Dps * item.Tick, pos, 0)
				end
			end
		end
		pool:Destroy()
	end)
end

function effects.Smoke(player, key, item, pos)
	Remote:FireAllClients("Fx", { Kind = "Smoke", Key = key, Owner = player, Origin = pos, Radius = item.Radius, Time = item.Duration })
	local cloud = anchorPart("Smoke", pos + Vector3.new(0, item.Radius * 0.35, 0), Vector3.new(1, 1, 1))
	cloud:SetAttribute("Radius", item.Radius)
	cloud:SetAttribute("Owner", player.UserId)
	cloud:SetAttribute("Ends", workspace:GetServerTimeNow() + item.Duration)
	cloud.Parent = smokeFolder
	local source = anchorPart("SmokeSource", pos + Vector3.new(0, 1, 0), Vector3.new(item.Radius * 1.4, 2, item.Radius * 1.4))
	source.Parent = fxFolder
	emitter(source, {
		Color = ColorSequence.new(Color3.fromRGB(158, 156, 150)), Rate = 22,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.2, 0.2),
			NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(5, 7), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 30),
		Acceleration = Vector3.new(0, 0.8, 0), Drag = 0.6, RotSpeed = NumberRange.new(-15, 15),
		Rotation = NumberRange.new(0, 360), LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 11) }),
	})
	task.spawn(function()
		local t = 0
		while t < item.Duration do
			t += task.wait(0.5)
			for _, mob in mobsNear(cloud.Position, item.Radius) do
				if not MobReactions.IsElite(mob) then
					MobReactions.Slow(mob, item.Slow, 0.7)
				end
			end
		end
		cloud:Destroy()
		for _, e in source:GetChildren() do
			if e:IsA("ParticleEmitter") then
				e.Enabled = false
			end
		end
		Debris:AddItem(source, 7)
	end)
end

-- A thrown item lands: rest it (some items stay), then its fuse, then its effect.
local function land(player, key, item, pos, normal)
	Remote:FireAllClients("Fx", { Kind = "Land", Key = key, Owner = player, Origin = pos })
	local model = nil
	if key ~= "Flare" and (item.Fuse or 0) > 0 then
		model = rest(key, pos, normal, item.Fuse + 0.1)
	end
	if (item.Fuse or 0) > 0 then
		task.wait(item.Fuse)
	end
	if model then
		model:Destroy()
	end
	local effect = effects[key]
	if effect then
		local ok, err = pcall(effect, player, key, item, pos, normal)
		if not ok then
			warn("GearServer:", key, err)
		end
	end
end

local function throw(player, key, origin, dir, id)
	local item = Gear.Items[key]
	local velocity = Gear.Velocity(key, dir)
	if not item or not velocity then
		return
	end
	castParams.FilterDescendantsInstances = excludeList()
	local _, pos, normal, time = Gear.Simulate(origin, velocity, arcCast, item.Bounce)
	-- Everyone else draws it now; the thrower already did (same Id).
	Remote:FireAllClients("Fx", { Kind = "Throw", Key = key, Owner = player, Origin = origin, Velocity = velocity, Id = id })
	task.delay(time, land, player, key, item, pos, normal)
end

local function fieldUsed(player, item)
	player:SetAttribute("FieldReadyAt", workspace:GetServerTimeNow() + (item.Cooldown or 90))
	local P = Progression()
	if P and P.Event then
		pcall(P.Event, player, "Field", 1)
	end
end

-- The ground a placed item goes on: where the player aims within PlaceRange, else at their feet.
local function placeSpot(character, origin, dir)
	castParams.FilterDescendantsInstances = excludeList()
	local root = character:FindFirstChild("HumanoidRootPart")
	local aim = workspace:Raycast(origin, dir * T.PlaceRange, castParams)
	local at = if aim and aim.Normal.Y > 0.6 then aim.Position
		else (root and root.Position or origin) + Vector3.new(dir.X, 0, dir.Z).Unit * 2.5
	local ground = workspace:Raycast(at + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), castParams)
	if ground then
		return ground.Position, ground.Normal
	end
	return nil
end

local function squadNear(pos, radius)
	local list = {}
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and (root.Position - pos).Magnitude <= radius then
			table.insert(list, { Player = p, Character = character, Humanoid = humanoid })
		end
	end
	return list
end

local function highlight(model, color, seconds)
	local h = Instance.new("Highlight")
	h.Name = "GearHighlight"
	h.FillTransparency = 1
	h.OutlineColor = color
	h.OutlineTransparency = 0.1
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = model
	h.Parent = model
	Debris:AddItem(h, seconds)
	return h
end

local fields = {}

function fields.Smoke(player, item, character, origin, dir, id)
	throw(player, "Smoke", origin, dir, id)
	return true
end

function fields.MedPouch(player, item, character, origin, dir)
	local pos, normal = placeSpot(character, origin, dir)
	if not pos then
		return false
	end
	local model = rest("MedPouch", pos, normal, item.Life)
	Remote:FireAllClients("Fx", { Kind = "Place", Key = "MedPouch", Owner = player, Origin = pos })
	local healed = {}
	local perTick = item.Heal / item.HealTime * 0.5
	task.spawn(function()
		local t = 0
		while t < item.Life and (not model or model.Parent) do
			t += task.wait(0.5)
			for _, m in squadNear(pos, item.Radius) do
				local h = m.Humanoid
				local done = healed[m.Player] or 0
				if done < item.Heal and not m.Character:GetAttribute("Downed") and h.Health < h.MaxHealth then
					local add = math.min(perTick, item.Heal - done, h.MaxHealth - h.Health)
					h.Health += add
					healed[m.Player] = done + add
				end
			end
		end
	end)
	return true
end

function fields.AmmoCrate(player, item, character, origin, dir)
	local pos, normal = placeSpot(character, origin, dir)
	if not pos then
		return false
	end
	local model = rest("AmmoCrate", pos, normal, item.Life)
	Remote:FireAllClients("Fx", { Kind = "Place", Key = "AmmoCrate", Owner = player, Origin = pos })
	local used = {}
	local gunsApi = ServerStorage:FindFirstChild("GunsApi")
	task.spawn(function()
		local t = 0
		while t < item.Life and (not model or model.Parent) do
			t += task.wait(0.5)
			for _, m in squadNear(pos, item.Radius) do
				if not used[m.Player] then
					used[m.Player] = true
					if gunsApi then
						pcall(gunsApi.Invoke, gunsApi, "GiveAmmo", m.Player)
					end
					refill(m.Player, true)
					play("Pickup/Ammo", pos)
				end
			end
		end
	end)
	return true
end

-- Elites and the Beacon (or, in the campaign, hostiles) seen through walls by everyone for Duration.
function fields.ReconFlare(player, item, character, origin)
	Remote:FireAllClients("Fx", { Kind = "Recon", Key = "ReconFlare", Owner = player, Origin = origin, Time = item.Duration })
	play("Gear/Recon", origin)
	local count = 0
	for _, mob in mobsNear(origin, item.Range) do
		if count >= 25 then
			break
		end
		if MobReactions.IsElite(mob) then
			highlight(mob, Color3.fromRGB(230, 150, 50), item.Duration)
			count += 1
		end
	end
	local beacon = workspace:FindFirstChild("Beacon", true)
	if beacon and beacon:IsA("Model") and count < 30 then
		highlight(beacon, Color3.fromRGB(230, 150, 50), item.Duration)
	end
	for _, hostile in CollectionService:GetTagged("Hostile") do
		if count >= 28 then
			break
		end
		if hostile:IsA("Model") and hostile:IsDescendantOf(workspace) then
			highlight(hostile, Color3.fromRGB(230, 150, 50), item.Duration)
			count += 1
		end
	end
	return true
end

-- The elite nearest the aim line in view gets marked: the squad sees it and deals Bonus more.
function fields.Mark(player, item, character, origin, dir)
	local best, bestScore = nil, -math.huge
	for _, mob in mobsNear(origin, item.Range) do
		if MobReactions.IsElite(mob) then
			local root = mob.PrimaryPart
			if root then
				local to = root.Position - origin
				local dot = to.Unit:Dot(dir)
				if dot >= item.Cone then
					losParams.FilterDescendantsInstances = excludeList({ mob })
					if not workspace:Raycast(origin, to, losParams) then
						local score = dot * 2 - to.Magnitude / item.Range
						if score > bestScore then
							best, bestScore = mob, score
						end
					end
				end
			end
		end
	end
	if not best then
		return false
	end
	best:SetAttribute("MarkedUntil", workspace:GetServerTimeNow() + item.Duration)
	highlight(best, Color3.fromRGB(230, 150, 50), item.Duration)
	Remote:FireAllClients("Fx", { Kind = "Mark", Key = "Mark", Owner = player, Origin = origin, Target = best })
	return true
end

function fields.Extinguisher(player, item, character, origin, dir)
	Remote:FireAllClients("Fx", { Kind = "Spray", Key = "Extinguisher", Owner = player, Origin = origin, Direction = dir })
	play("Gear/Spray", origin)
	MobAI.ClearHazards(origin + dir * item.Range * 0.5, item.PutsOut)
	for _, f in fxFolder:GetChildren() do
		if f.Name == "FirePool" and (f.Position - origin).Magnitude <= item.PutsOut + 6 then
			f:Destroy()
		end
	end
	for _, mob in mobsNear(origin, item.Range) do
		local root = mob.PrimaryPart
		if root then
			local to = root.Position - origin
			if to.Magnitude > 0.1 and to.Unit:Dot(dir) >= item.Cone and reaches(origin, mob) then
				hitMob(player, "Extinguisher", item, mob, item.Hit.Damage, origin, 1 - to.Magnitude / item.Range)
			end
		end
	end
	return true
end

function fields.Decoy(player, item, character, origin, dir)
	local pos, normal = placeSpot(character, origin, dir)
	if not pos then
		return false
	end
	local model = rest("Decoy", pos, normal, item.LureTime + 1)
	if model then
		local lamp = model.PrimaryPart
		light(lamp, Color3.fromRGB(230, 150, 50), 6, 1)
	end
	Remote:FireAllClients("Fx", { Kind = "Place", Key = "Decoy", Owner = player, Origin = pos, Time = item.LureTime })
	MobAI.Lure(pos, item.LureTime, item.LureRadius)
	return true
end

function fields.Charge(player, item, character, origin, dir)
	local s = states[player]
	local pos, normal = placeSpot(character, origin, dir)
	if not pos then
		return false
	end
	local model = rest("Charge", pos, normal, item.Life)
	Remote:FireAllClients("Fx", { Kind = "Place", Key = "Charge", Owner = player, Origin = pos })
	local charge = { Model = model, Pos = pos }
	s.Charge = charge
	player:SetAttribute("ChargeOut", true)
	task.delay(item.Life, function()
		if s.Charge == charge then
			s.Charge = nil
			player:SetAttribute("ChargeOut", nil)
		end
	end)
	return true
end

local function detonate(player)
	local s = states[player]
	local charge = s and s.Charge
	if not charge then
		return
	end
	s.Charge = nil
	player:SetAttribute("ChargeOut", nil)
	if charge.Model then
		charge.Model:Destroy()
	end
	local item = Gear.Items.Charge
	local ok, err = pcall(blast, player, "Charge", item, charge.Pos + Vector3.new(0, 0.5, 0))
	if not ok then
		warn("GearServer: Charge", err)
	end
end

local function stim(player, item, character, humanoid)
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + item.Heal)
	character:SetAttribute("StimUntil", workspace:GetServerTimeNow() + item.SpeedTime)
	character:SetAttribute("StimSpeed", item.Speed)
	Remote:FireAllClients("Fx", { Kind = "Stim", Key = "Stim", Owner = player, Origin = character:GetPivot().Position })
end

-- Remote ----------------------------------------------------------------------------------------------------------

local function deny(player, slot)
	Remote:FireClient(player, "Fx", { Kind = "Denied", Slot = slot, Owner = player })
end

Remote.OnServerEvent:Connect(function(player, action, payload)
	local s = states[player]
	if not s then
		return
	end
	if action == "Detonate" then
		detonate(player)
		return
	end
	if type(payload) ~= "table" then
		return
	end
	local character, humanoid, head = able(player)
	if not character then
		deny(player, payload.Slot)
		return
	end
	local now = os.clock()
	if now - s.LastThrow < T.Gap then
		return
	end
	local id = if type(payload.Id) == "number" or type(payload.Id) == "string" then payload.Id else nil

	if action == "Throw" then
		local slot = payload.Slot
		if slot ~= "Lethal" and slot ~= "Tactical" then
			return
		end
		local key, have, isTest = gearOf(player, slot)
		local item = Gear.Items[key or ""]
		if not item or item.Slot ~= slot or have <= 0 then
			deny(player, slot)
			return
		end
		local origin = payload.Origin
		local dir = if item.Kind == "Use" then Vector3.zAxis else checkAim(head, origin, payload.Direction)
		if not dir then
			deny(player, slot)
			return
		end
		if isTest then
			s.Test[slot].Count -= 1
		else
			local ok, taken = pcall(Inventory.TakeGear, player, slot)
			if not ok or taken ~= key then
				deny(player, slot)
				return
			end
		end
		s.LastThrow = now
		publish(player, s)
		if item.Kind == "Use" then
			stim(player, item, character, humanoid)
		else
			throw(player, key, origin, dir, id)
		end
	elseif action == "Field" then
		local key = s.Field
		local item = Gear.Items[key or ""]
		if not item then
			deny(player, "Field")
			return
		end
		if key == "Charge" and s.Charge then
			detonate(player)
			return
		end
		if (player:GetAttribute("FieldReadyAt") or 0) > workspace:GetServerTimeNow() + 0.25 then
			deny(player, "Field")
			return
		end
		local origin = payload.Origin
		local dir = checkAim(head, origin, payload.Direction)
		if not dir then
			deny(player, "Field")
			return
		end
		local use = fields[key]
		if not use then
			return
		end
		s.LastThrow = now
		local ok, used = pcall(use, player, item, character, origin, dir, id)
		if not ok then
			warn("GearServer: field", key, used)
		elseif used then
			fieldUsed(player, item)
		else
			deny(player, "Field")
		end
	end
end)
