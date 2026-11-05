-- Test range: spawns test mobs on Workspace.TestRange.DummySpots and respawns them.
-- Players wait in the menu (MenuServer) before they spawn, so the range only fills once the
-- first character is in, and walkers give that player Settings.WalkerDelay seconds first.
-- Static dummies stand idle until shot or approached, strafers walk side to side, walkers hunt the nearest player
-- with MobAI (pathing, fences, barricades, swipes, feeding during a devour). Hit
-- reactions, sounds and corpses are handled by MobReactions, player damage by PlayerHealth. Delete this script and the TestRange folder once real spawning exists.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local MobReactions = require(ServerStorage.Modules.MobReactions)
local MobAI = require(ServerStorage.Modules.MobAI)
local MobAttack = require(ServerStorage.Modules.MobAttack)
local Settings = GameConfig.TestRange

local range = workspace:WaitForChild("TestRange")
local spots = range:WaitForChild("DummySpots")
-- Toolbox R15 zombie ("Zombie" by Rzepert, scripts stripped) with one red and one green eye.
-- The old block dummy is in ServerStorage._Backups.
local template = ServerStorage:WaitForChild("TestZombie")
local mobConfig = GameConfig.Mobs[template:GetAttribute("MobType")]

local live = Instance.new("Folder")
live.Name = "Dummies"
live.Parent = range

local spawnDummy
local startedAt = os.clock()

local function facingSpawn(pos)
	local spawnPos = workspace:FindFirstChild("SpawnLocation") and workspace.SpawnLocation.Position or Vector3.new(0, 0, 20)
	return CFrame.lookAt(pos, Vector3.new(spawnPos.X, pos.Y, spawnPos.Z))
end

local function walkBetween(dummy, humanoid, a, b)
	task.spawn(function()
		local goal = b
		while dummy.Parent and humanoid.Health > 0 do
			humanoid:MoveTo(goal)
			humanoid.MoveToFinished:Wait()
			goal = if goal == b then a else b
		end
	end)
end

-- Static targets stand idle (free to be shot for testing guns) until they're hurt or a
-- player comes within WakeRange in plain sight; then they hunt like walkers.
local function idle(dummy, humanoid)
	local awake = false
	local function wake()
		if not awake and humanoid.Health > 0 then
			awake = true
			MobAI.Hunt(dummy, mobConfig, { AggroRange = Settings.WalkerAggroRange })
		end
	end
	humanoid.HealthChanged:Connect(function(health)
		if health < humanoid.MaxHealth then
			wake()
		end
	end)
	task.spawn(function()
		while not awake and dummy.Parent and humanoid.Health > 0 do
			-- Same head start as the walkers: nothing wakes on sight in your first seconds.
			local settled = os.clock() >= startedAt + Settings.WalkerDelay
			for _, p in Players:GetPlayers() do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if settled and root and (root.Position - dummy.PrimaryPart.Position).Magnitude < Settings.WakeRange
					and MobAttack.Sees(dummy, root)
				then
					wake()
				end
			end
			task.wait(0.3)
		end
	end)
end

function spawnDummy(spot)
	local dummy = template:Clone()
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	-- Stand the root at the rig's own height: R15 hip height, or R6's 2-stud legs.
	local rootHeight = if humanoid.RigType == Enum.HumanoidRigType.R15
		then humanoid.HipHeight + dummy.PrimaryPart.Size.Y / 2
		else 3
	dummy:PivotTo(facingSpawn(spot.Position + Vector3.new(0, rootHeight, 0)))

	humanoid.MaxHealth = mobConfig.Health
	humanoid.Health = mobConfig.Health

	local kind = spot:GetAttribute("Kind")
	local speed = if kind == "Strafer" then Settings.StraferSpeed else mobConfig.WalkSpeed
	humanoid.WalkSpeed = speed
	dummy:SetAttribute("BaseWalkSpeed", speed)
	dummy.Parent = live
	dummy.PrimaryPart:SetNetworkOwner(nil)

	if kind == "Static" then
		idle(dummy, humanoid)
	elseif kind == "Strafer" then
		walkBetween(dummy, humanoid, spot.Position, spot:GetAttribute("To") or spot.Position)
	elseif kind == "Walker" then
		task.delay(math.max(0, startedAt + Settings.WalkerDelay - os.clock()), function()
			if dummy.Parent and humanoid.Health > 0 then
				MobAI.Hunt(dummy, mobConfig, { AggroRange = Settings.WalkerAggroRange })
			end
		end)
	end

	MobReactions.Spawned(dummy)
	humanoid.Died:Once(function()
		task.delay(Settings.RespawnTime, spawnDummy, spot)
	end)
end

-- Wait for the first player to come out of the menu.
local function anyCharacter()
	for _, p in Players:GetPlayers() do
		if p.Character then
			return true
		end
	end
	return false
end
while not anyCharacter() do
	task.wait(0.25)
end
startedAt = os.clock()
for _, spot in spots:GetChildren() do
	spawnDummy(spot)
end
