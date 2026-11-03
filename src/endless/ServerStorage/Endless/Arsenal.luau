-- Guns on the server: what each player carries, their ammo, and whether a shot a client reports
-- counts. A gun is a Tool built from GunModel (attributes: Weapon, Mag, Reserve, Boosts, Level,
-- Reloading, ReloadEnd; Shared Weapons does the sums). You carry Config.Arsenal.Slots guns (three
-- with Packmule Tonic); taking another with full hands swaps out the one you hold.
--
-- The client shoots (StarterPlayerScripts.EndlessClient) and sends Weapon "Fire" with where from,
-- the direction of each pellet and the zombie part it saw each one hit (or false). The server checks
-- the ammo, the rate (a token bucket: the gun's rate on average, a couple of shots of slack for
-- bunched-up packets), that nothing solid stands between the head and the origin, and that the
-- pellets keep to the gun's cone; it casts every pellet again, and takes the client's word for a hit
-- its own cast missed only if the part is close to the ray and no wall is in between (lag). Hits go
-- to Arsenal.DamageZombie (EndlessServer wires it to Horde.Damage and the points).
-- Melee is Call of Duty's knife (Config.Arsenal.Melee).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Weapons = require(ReplicatedStorage.Endless.Weapons)
local GunModel = require(ReplicatedStorage.Endless.GunModel)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Survivors = require(ServerStorage.Endless.Survivors)

local ARSENAL = Config.Arsenal
local CHECK = ARSENAL.Validation

local Arsenal = {}
-- (player, zombie model, part, damage, head, melee, direction, paysHit): set by EndlessServer.
Arsenal.DamageZombie = nil

local budget = {} -- [player] = {Credit, At}: shots the player may fire right now
local lastMelee = {} -- [player] = os.clock()
local BURST = 2

-- Tools ------------------------------------------------------------------------------------------

function Arsenal.MakeTool(id: string, boosts: string?): Tool
	local cfg = Config.Weapons[id]
	local tool = Instance.new("Tool")
	tool.Name = cfg.Name
	tool.ToolTip = cfg.Name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	local level = #Weapons.ParseBoosts(boosts)
	local model = GunModel.Build(id, { Level = level })
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()
	local stats = Weapons.Stats(id, boosts, nil)
	tool:SetAttribute("Weapon", id)
	tool:SetAttribute("Boosts", boosts or "")
	tool:SetAttribute("Level", level)
	tool:SetAttribute("Mag", stats.Mag)
	tool:SetAttribute("Reserve", stats.Reserve)
	return tool
end

-- Every gun the player carries, in slot order (backpack and hand).
function Arsenal.Tools(player: Player): { Tool }
	local list = {}
	local function scan(container)
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("Weapon") then
					table.insert(list, t)
				end
			end
		end
	end
	scan(player.Character)
	scan(player:FindFirstChildOfClass("Backpack"))
	table.sort(list, function(a, b)
		return (a:GetAttribute("Slot") or 0) < (b:GetAttribute("Slot") or 0)
	end)
	return list
end

function Arsenal.Held(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return if tool and tool:GetAttribute("Weapon") then tool else nil
end

function Arsenal.Find(player: Player, id: string): Tool?
	for _, t in Arsenal.Tools(player) do
		if t:GetAttribute("Weapon") == id then
			return t
		end
	end
	return nil
end

function Arsenal.SlotCount(player: Player): number
	return if player:GetAttribute("Perk_Packmule") then Config.Perks.List.Packmule.Slots else ARSENAL.Slots
end

-- Fills a tool's magazine and reserve to this player's sizes.
function Arsenal.Fill(player: Player, tool: Tool)
	local stats = Weapons.ForTool(tool, player)
	if stats then
		tool:SetAttribute("Mag", stats.Mag)
		tool:SetAttribute("Reserve", stats.Reserve)
	end
end

-- Puts a gun in the player's hands. With every slot full, the gun in hand (or the last) goes.
-- slot: keep this slot number (a gun coming back from the altar).
function Arsenal.Give(player: Player, id: string, boosts: string?, slot: number?): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or not Config.Weapons[id] then
		return nil
	end
	local tools = Arsenal.Tools(player)
	slot = slot or #tools + 1
	if #tools >= Arsenal.SlotCount(player) then
		local out = Arsenal.Held(player) or tools[#tools]
		slot = out:GetAttribute("Slot") or #tools
		out:Destroy()
	end
	local tool = Arsenal.MakeTool(id, boosts)
	tool:SetAttribute("Slot", slot)
	Arsenal.Fill(player, tool)
	tool.Parent = backpack
	local _, humanoid = Survivors.Parts(player)
	if humanoid and Survivors.IsStanding(player) then
		humanoid:EquipTool(tool)
	end
	return tool
end

-- A fresh life: just the starting gun.
function Arsenal.GiveStart(player: Player)
	for _, t in Arsenal.Tools(player) do
		t:Destroy()
	end
	Arsenal.Give(player, ARSENAL.Start)
end

-- Going down without Packmule any more: the gun past the second slot is lost (Call of Duty).
function Arsenal.Trim(player: Player)
	local tools = Arsenal.Tools(player)
	for i = Arsenal.SlotCount(player) + 1, #tools do
		tools[i]:Destroy()
	end
end

-- RESUPPLY: every gun of every player in the run gets a full reserve.
function Arsenal.ResupplyAll()
	for _, p in Survivors.RunPlayers() do
		for _, t in Arsenal.Tools(p) do
			local stats = Weapons.ForTool(t, p)
			if stats then
				t:SetAttribute("Reserve", stats.Reserve)
			end
		end
	end
end

-- Relic or perk changes the sizes: top up so nothing reads over its new maximum.
function Arsenal.Refresh(player: Player)
	for _, t in Arsenal.Tools(player) do
		local stats = Weapons.ForTool(t, player)
		if stats then
			t:SetAttribute("Mag", math.min(t:GetAttribute("Mag") or 0, stats.Mag))
			t:SetAttribute("Reserve", math.min(t:GetAttribute("Reserve") or 0, stats.Reserve))
		end
	end
end

-- Shots -----------------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function ignoreList(extra)
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local fx = workspace:FindFirstChild("Fx")
	if fx then
		table.insert(list, fx)
	end
	local drops = workspace:FindFirstChild("Drops")
	if drops then
		table.insert(list, drops)
	end
	for _, m in extra do
		table.insert(list, m)
	end
	return list
end

local function zombieOf(part: Instance?)
	local zombies = workspace:FindFirstChild("Zombies")
	local node = part
	while node and node.Parent and node.Parent ~= zombies do
		node = node.Parent
	end
	if node and node.Parent == zombies and node:IsA("Model") then
		local hum = node:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return node
		end
	end
	return nil
end

-- One pellet: up to `pierce` zombies along the ray. Returns {zombie, part, position} and the end point.
local function castPellet(origin, dir, range, pierce, claim)
	local hits = {}
	local skip = {}
	local from = origin
	local left = range
	local stop = origin + dir * range
	while left > 0 and #hits < pierce do
		rayParams.FilterDescendantsInstances = ignoreList(skip)
		local result = workspace:Raycast(from, dir * left, rayParams)
		if not result then
			break
		end
		local zombie = zombieOf(result.Instance)
		if not zombie then
			stop = result.Position
			break
		end
		table.insert(hits, { Zombie = zombie, Part = result.Instance, Position = result.Position })
		table.insert(skip, zombie)
		left -= (result.Position - from).Magnitude
		from = result.Position
	end
	-- Lag: the client saw this zombie part on the ray; the server's copy has moved a little.
	if #hits == 0 and typeof(claim) == "Instance" and claim:IsA("BasePart") then
		local zombie = zombieOf(claim)
		if zombie then
			local to = claim.Position - origin
			local along = to:Dot(dir)
			local off = (to - dir * along).Magnitude
			local wallAt = (stop - origin).Magnitude
			if along > 0 and along <= range and along <= wallAt + 2 and off <= claim.Size.Magnitude / 2 + CHECK.ClaimSlack then
				table.insert(hits, { Zombie = zombie, Part = claim, Position = origin + dir * along })
				stop = origin + dir * along
			end
		end
	end
	if #hits > 0 then
		stop = hits[#hits].Position
	end
	return hits, stop
end

local function onFire(player, tool, origin, directions, claims)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or tool.Parent ~= player.Character then
		return
	end
	if typeof(origin) ~= "Vector3" or type(directions) ~= "table" or not Survivors.IsStanding(player) then
		return
	end
	local stats = Weapons.ForTool(tool, player)
	if not stats or tool:GetAttribute("Reloading") then
		return
	end
	-- The rate: credit fills at the gun's rate, up to BURST shots banked; a shot needs RateSlack of one.
	local now = os.clock()
	local b = budget[player]
	if not b then
		b = { Credit = BURST, At = now }
		budget[player] = b
	end
	b.Credit = math.min(BURST, b.Credit + (now - b.At) * stats.Rpm / 60)
	b.At = now
	if b.Credit < CHECK.RateSlack then
		return
	end
	local mag = tool:GetAttribute("Mag") or 0
	if mag <= 0 then
		return
	end
	local head = player.Character:FindFirstChild("Head")
	if not head or (origin - head.Position).Magnitude > CHECK.MaxOriginOffset then
		return
	end
	-- Not from the far side of a wall or a shut door.
	rayParams.FilterDescendantsInstances = ignoreList({})
	if workspace:Raycast(head.Position, origin - head.Position, rayParams) then
		return
	end
	b.Credit -= 1
	tool:SetAttribute("Mag", mag - 1)
	player.Character:SetAttribute("FiredAt", workspace:GetServerTimeNow())

	local ends = {}
	local dealt = {} -- [zombie] = true: one points payout per zombie per shot
	local first = nil
	local cone = math.rad(2 * stats.Spread.Hip + CHECK.ConeSlack)
	for i = 1, math.min(#directions, stats.Pellets) do
		local dir = directions[i]
		if typeof(dir) == "Vector3" and dir.Magnitude > 0.5 then
			dir = dir.Unit
			-- Every pellet keeps to the gun's cone round the first one.
			first = first or dir
			if math.acos(math.clamp(dir:Dot(first), -1, 1)) > cone then
				continue
			end
			local claim = type(claims) == "table" and claims[i] or nil
			local hits, stop = castPellet(origin, dir, stats.Range, stats.Pierce, claim)
			table.insert(ends, stop)
			for _, h in hits do
				local isHead = h.Part.Name == "Head"
				local amount = stats.Damage * (if isHead then stats.Head else 1)
				if Arsenal.DamageZombie then
					Arsenal.DamageZombie(player, h.Zombie, h.Part, amount, isHead, false, dir, not dealt[h.Zombie])
				end
				dealt[h.Zombie] = true
			end
		end
	end
	-- The shooter hears and sees their own shot at once (EndlessClient); everyone else from this.
	Net.Get("Fx"):FireAllClients("Shot", player.UserId, stats.Id, origin, ends)
end

local function onReload(player, tool)
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or tool.Parent ~= player.Character or not Survivors.IsStanding(player) then
		return
	end
	local stats = Weapons.ForTool(tool, player)
	if not stats or tool:GetAttribute("Reloading") then
		return
	end
	local mag, reserve = tool:GetAttribute("Mag") or 0, tool:GetAttribute("Reserve") or 0
	if mag >= stats.Mag or reserve <= 0 then
		return
	end
	tool:SetAttribute("Reloading", true)
	tool:SetAttribute("ReloadEnd", workspace:GetServerTimeNow() + stats.Reload)
	local character = player.Character
	task.delay(stats.Reload, function()
		if not tool.Parent then
			return
		end
		tool:SetAttribute("Reloading", nil)
		-- Put away, or the player went down, mid-reload: nothing goes in (Call of Duty).
		if tool.Parent ~= character or not Survivors.IsStanding(player) then
			return
		end
		local now = Weapons.ForTool(tool, player)
		local m, r = tool:GetAttribute("Mag") or 0, tool:GetAttribute("Reserve") or 0
		local take = math.min(now.Mag - m, r)
		tool:SetAttribute("Mag", m + take)
		tool:SetAttribute("Reserve", r - take)
	end)
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

local function onMelee(player)
	if not Survivors.IsStanding(player) then
		return
	end
	local now = os.clock()
	if now - (lastMelee[player] or 0) < ARSENAL.Melee.Cooldown * CHECK.RateSlack then
		return
	end
	lastMelee[player] = now
	local _, _, root = Survivors.Parts(player)
	local zombies = workspace:FindFirstChild("Zombies")
	if not root or not zombies then
		return
	end
	local look = Util.Flat(root.CFrame.LookVector).Unit
	local best, bestD = nil, ARSENAL.Melee.Range
	for _, z in zombies:GetChildren() do
		local zr = z:FindFirstChild("HumanoidRootPart")
		local hum = z:FindFirstChildOfClass("Humanoid")
		if zr and hum and hum.Health > 0 then
			local to = zr.Position - root.Position
			local d = to.Magnitude
			local flat = Util.Flat(to)
			local inArc = flat.Magnitude < 0.5 or look:Dot(flat.Unit) >= math.cos(math.rad(ARSENAL.Melee.Arc / 2))
			if d < bestD and inArc and math.abs(to.Y) < 5 then
				best, bestD = z, d
			end
		end
	end
	Sfx.Play("Common/Whiz", { Position = root.Position, Speed = 0.8 })
	if best and Arsenal.DamageZombie then
		local torso = best:FindFirstChild("Torso") or best.PrimaryPart
		local damage = ARSENAL.Melee.Damage * (1 + (player:GetAttribute("RelicDamage") or 0))
		Arsenal.DamageZombie(player, best, torso, damage, false, true, look, true)
	end
end

function Arsenal.Start()
	local remote = Net.Get("Weapon")
	remote.OnServerEvent:Connect(function(player, action, ...)
		if action == "Fire" then
			onFire(player, ...)
		elseif action == "Reload" then
			onReload(player, ...)
		elseif action == "Melee" then
			onMelee(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		budget[player] = nil
		lastMelee[player] = nil
	end)
end

return Arsenal
