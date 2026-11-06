-- Kill rewards you pick up. A kill spills a few glowing amber gems that pop out of the
-- body and hover just off the floor in workspace.Drops, spinning and bobbing so they read as
-- pickups. Anyone alive who comes within Magnet studs pulls them in; once a gem has locked on
-- to someone it follows them until it reaches them, and pays its share into Points.
-- Shards blink near the end of their Life, then go. Numbers: GameConfig.Match.Glow.
-- Remotes.Match sends "Glow" (the amount) to whoever picked one up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Points = require(script.Parent.Points)

local CFG = GameConfig.Match.Glow
local AMBER = Color3.fromRGB(255, 176, 60)
local HOVER = 1.4
local POP_TIME = 0.45
local SPIN = math.rad(150) -- per second
local BOB = 0.3

local GlowDrops = {}

local folder = workspace:FindFirstChild("Drops")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Drops"
	folder.Parent = workspace
end

local shards = {} -- [part] = { Value, Born, From, To, Speed }

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function groundBelow(position)
	local ignore = { folder }
	for _, name in { "Zombies", "Fx" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position, Vector3.new(0, -40, 0), groundParams)
	return if hit then hit.Position else position - Vector3.new(0, 3, 0)
end

local function makeShard()
	local part = Instance.new("Part")
	part.Name = "GlowShard"
	part.Size = Vector3.new(0.7, 0.7, 0.7)
	part.Material = Enum.Material.Neon
	part.Color = AMBER
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = AMBER
	light.Range = 9
	light.Brightness = 1.8
	light.Shadows = false
	light.Parent = part
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(AMBER)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Transparency = NumberSequence.new(0.2)
	sparkle.Lifetime = NumberRange.new(0.5, 0.9)
	sparkle.Rate = 7
	sparkle.Speed = NumberRange.new(0.6, 1.4)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Acceleration = Vector3.new(0, 1.5, 0)
	sparkle.Parent = attachment
	return part
end

-- Spills shards worth `total` points between them at a body's position.
function GlowDrops.Spill(position, total, count)
	count = math.max(1, count or CFG.Shards)
	local each = math.max(1, math.floor(total / count))
	local now = os.clock()
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.8
		local reach = 1.5 + math.random() * 2
		local from = position + Vector3.new(0, 1, 0)
		local spot = position + Vector3.new(math.cos(angle) * reach, 2, math.sin(angle) * reach)
		local to = groundBelow(spot) + Vector3.new(0, HOVER, 0)
		local part = makeShard()
		part.CFrame = CFrame.new(from)
		part.Parent = folder
		shards[part] = {
			Value = if i == count then total - each * (count - 1) else each,
			Born = now,
			From = from,
			To = to,
			Speed = 0,
			Phase = math.random() * math.pi * 2,
			Target = nil, -- { player, root } once it has locked on
		}
	end
end

function GlowDrops.Clear()
	for part in shards do
		part:Destroy()
	end
	table.clear(shards)
end

local function collect(part, shard, player, root)
	shards[part] = nil
	part:Destroy()
	Points.Add(player, shard.Value)
	SoundKit.Play("Pickup/Ammo", { Parent = root, Speed = 1.7, Volume = 0.5 })
	local remote = ReplicatedStorage.Remotes:FindFirstChild("Match")
	if remote then
		remote:FireClient(player, "Glow", shard.Value)
	end
end

RunService.Heartbeat:Connect(function(dt)
	if next(shards) == nil then
		return
	end
	local now = os.clock()
	local roots = {}
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and humanoid and humanoid.Health > 0 and not character:GetAttribute("Devoured") then
			table.insert(roots, { p, root })
		end
	end
	for part, shard in shards do
		local age = now - shard.Born
		if age >= CFG.Life or not part.Parent then
			shards[part] = nil
			part:Destroy()
			continue
		end
		-- A gem stands on a corner and turns.
		local turn = CFrame.Angles(0, now * SPIN + shard.Phase, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35))
		-- Pop out of the body in an arc, then hover.
		if age < POP_TIME then
			local t = age / POP_TIME
			local pos = shard.From:Lerp(shard.To, t) + Vector3.new(0, math.sin(t * math.pi) * 2.2, 0)
			part.CFrame = CFrame.new(pos) * turn
			continue
		end
		-- The player it locked on to keeps it (while alive); otherwise the nearest in reach.
		local best, bestRoot, bestDist = nil, nil, CFG.Magnet
		local target = nil
		for _, entry in roots do
			if shard.Target and entry[2] == shard.Target[2] then
				target = entry
			end
		end
		if target then
			best, bestRoot, bestDist = target[1], target[2], (target[2].Position - part.Position).Magnitude
		else
			for _, entry in roots do
				local d = (entry[2].Position - part.Position).Magnitude
				if d < bestDist then
					best, bestRoot, bestDist = entry[1], entry[2], d
				end
			end
		end
		if best then
			shard.Target = { best, bestRoot }
			if bestDist <= CFG.Collect then
				collect(part, shard, best, bestRoot)
				continue
			end
			shard.Speed = math.min(shard.Speed + CFG.PullSpeed * dt * 3, CFG.PullSpeed)
			local step = math.min(shard.Speed * dt, bestDist)
			part.CFrame = CFrame.new(part.Position + (bestRoot.Position - part.Position).Unit * step) * turn
		else
			shard.Speed = 0
			part.CFrame = CFrame.new(shard.To + Vector3.new(0, math.sin(now * 3 + shard.Phase) * BOB, 0)) * turn
		end
		-- Blink before it goes.
		local left = CFG.Life - age
		part.Transparency = if left < CFG.BlinkAt and math.floor(now * 6) % 2 == 0 then 0.8 else 0
	end
end)

return GlowDrops
