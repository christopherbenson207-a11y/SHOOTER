-- Power-ups (Call of Duty Zombies' drops, our names; Config.PowerUps). A kill drops one with Chance,
-- at most PerRound a round, the kinds coming out of a shuffled bag so each turns up once before any
-- repeats. A drop floats where the zombie fell for Life seconds (blinking the last Blink seconds,
-- EndlessFx) and anyone standing who walks within Reach takes it for the whole squad:
--   RESUPPLY      every gun's reserve full
--   REAPER        Duration seconds of one-hit kills (workspace ReaperUntil; Horde.Damage)
--   DOUBLE PAY    Duration seconds of double points (workspace DoublePayUntil; Economy)
--   PURGE         every zombie standing dies, Points each for everyone
--   HAMMER AND NAILS  every board back up, Points each for everyone
-- Drop attributes for clients: Kind, ExpiresAt (server time).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)
local Windows = require(ServerStorage.Endless.Windows)

local POWER = Config.PowerUps

local PowerUps = {}
-- Set by EndlessServer: kills every zombie (Horde.KillAll), kept out of here to avoid a loop.
PowerUps.Purge = nil

local folder
local bag = {}
local dropped = 0
local drops = {} -- [model] = {Kind, At, ExpiresAt}

local function draw()
	if #bag == 0 then
		for kind in POWER.Kinds do
			table.insert(bag, kind)
		end
		table.sort(bag)
		Util.Shuffle(bag)
	end
	return table.remove(bag)
end

local function shape(kind, at: Vector3)
	local info = POWER.Kinds[kind]
	local model = Instance.new("Model")
	model.Name = kind
	local function part(name, size, offset, partShape, color)
		local p = Instance.new("Part")
		p.Name = name
		if partShape then
			p.Shape = partShape
		end
		p.Size = size
		p.CFrame = CFrame.new(at + offset)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Neon
		p.Color = color or info.Color
		p.Parent = model
		return p
	end
	local core
	if kind == "Resupply" then
		core = part("Crate", Vector3.new(1.6, 1.1, 1.1), Vector3.zero)
		part("Lid", Vector3.new(1.7, 0.2, 1.2), Vector3.new(0, 0.6, 0), nil, Color3.fromRGB(120, 100, 40))
	elseif kind == "Reaper" then
		core = part("Skull", Vector3.new(1.4, 1.4, 1.4), Vector3.zero, Enum.PartType.Ball)
		part("Jaw", Vector3.new(0.9, 0.4, 0.8), Vector3.new(0, -0.65, 0))
	elseif kind == "DoublePay" then
		core = part("Coin", Vector3.new(0.25, 1.5, 1.5), Vector3.new(-0.3, 0, 0), Enum.PartType.Cylinder)
		part("Coin2", Vector3.new(0.25, 1.5, 1.5), Vector3.new(0.3, 0, 0), Enum.PartType.Cylinder)
	elseif kind == "Purge" then
		core = part("Bomb", Vector3.new(1.5, 1.5, 1.5), Vector3.zero, Enum.PartType.Ball)
		part("Fuse", Vector3.new(0.2, 0.6, 0.2), Vector3.new(0, 0.95, 0), nil, Color3.fromRGB(255, 240, 200))
	else
		core = part("Head", Vector3.new(1.5, 0.6, 0.6), Vector3.new(0, 0.5, 0))
		part("Handle", Vector3.new(0.3, 1.6, 0.3), Vector3.new(0, -0.4, 0), nil, Color3.fromRGB(120, 86, 50))
	end
	local light = Instance.new("PointLight")
	light.Color = info.Color
	light.Brightness = 2
	light.Range = 12
	light.Parent = core
	model.PrimaryPart = core
	model:SetAttribute("Kind", kind)
	model:SetAttribute("ExpiresAt", workspace:GetServerTimeNow() + POWER.Life)
	model.Parent = folder
	return model
end

local function apply(kind, run)
	local info = POWER.Kinds[kind]
	local now = workspace:GetServerTimeNow()
	if kind == "Resupply" then
		Arsenal.ResupplyAll()
	elseif kind == "Reaper" then
		workspace:SetAttribute("ReaperUntil", now + POWER.Duration)
	elseif kind == "DoublePay" then
		workspace:SetAttribute("DoublePayUntil", now + POWER.Duration)
	elseif kind == "Purge" then
		if PowerUps.Purge then
			PowerUps.Purge()
		end
		for _, p in Survivors.RunPlayers() do
			Economy.Bonus(p, info.Points)
		end
	elseif kind == "Nails" then
		Windows.RepairAll()
		for _, p in Survivors.RunPlayers() do
			Economy.Bonus(p, info.Points)
		end
	end
	Net.Get("Hud"):FireAllClients("PowerUp", kind, info.Name)
end

-- A kill at `at` (the zombie's root): maybe a drop, on the floor under it.
function PowerUps.OnKill(at: Vector3)
	if dropped >= POWER.PerRound or math.random() >= POWER.Chance then
		return
	end
	dropped += 1
	local kind = draw()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local house = workspace:FindFirstChild("House")
	params.FilterDescendantsInstances = if house then { house } else {}
	local hit = workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	local floor = if hit then hit.Position else at - Vector3.new(0, 3, 0)
	local model = shape(kind, floor + Vector3.new(0, 2.2, 0))
	drops[model] = { Kind = kind, At = floor + Vector3.new(0, 2.2, 0) }
end

function PowerUps.NewRound()
	dropped = 0
end

function PowerUps.Setup(run, maid)
	folder = workspace:FindFirstChild("Drops")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Drops"
		folder.Parent = workspace
	end
	folder:ClearAllChildren()
	table.clear(drops)
	table.clear(bag)
	dropped = 0
	workspace:SetAttribute("ReaperUntil", nil)
	workspace:SetAttribute("DoublePayUntil", nil)
	maid:Add(task.spawn(function()
		while true do
			task.wait(0.1)
			local now = workspace:GetServerTimeNow()
			for model, d in drops do
				if not model.Parent or now >= model:GetAttribute("ExpiresAt") then
					drops[model] = nil
					model:Destroy()
				else
					for _, p in Survivors.StandingPlayers() do
						local _, _, root = Survivors.Parts(p)
						if root and (root.Position - d.At).Magnitude <= POWER.Reach + 2 then
							drops[model] = nil
							model:Destroy()
							Sfx.Play("Pickup/Ammo", { Position = d.At })
							apply(d.Kind, run)
							break
						end
					end
				end
			end
		end
	end))
	maid:Add(function()
		folder:ClearAllChildren()
		table.clear(drops)
	end)
end

return PowerUps
