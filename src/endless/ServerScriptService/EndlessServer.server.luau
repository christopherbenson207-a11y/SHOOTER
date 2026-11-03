-- The Endless reference: Call of Duty Zombies rounds with Mortuus' roguelike layer, in a huge
-- code-built house (docs/ENDLESS-REFERENCE.md). This script boots the place and runs run after run:
--   1. A run starts once someone is in the server: the house is built fresh (HouseBuilder, a new
--      draw of the box, perks, wall guns, altar, switch and door prices), every system is set up
--      on it, and everyone spawns in the start room with Config.Run.StartPoints and the start gun.
--   2. Director plays rounds until nobody is standing.
--   3. Game over: GameOverTime on the end screen, then everything is taken down and it begins again.
-- It also joins the systems up: a hit from Arsenal goes to Horde.Damage and pays points (Economy),
-- a kill may drop a power-up (PowerUps) and heals Bloodthirst players.
-- Players.CharacterAutoLoads is off: characters only load through Survivors.Spawn.
-- Studio only: workspace attributes EndlessStartRound, EndlessStartPoints, EndlessPower, EndlessGod,
-- EndlessOpenAll (Config.Debug).

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Modules = ServerStorage.Endless
local Util = require(Modules.Util)
local HouseBuilder = require(Modules.HouseBuilder)
local HouseLayout = require(Modules.HouseLayout)
local Economy = require(Modules.Economy)
local Survivors = require(Modules.Survivors)
local Arsenal = require(Modules.Arsenal)
local Windows = require(Modules.Windows)
local Horde = require(Modules.Horde)
local Doors = require(Modules.Doors)
local Randomizer = require(Modules.Randomizer)
local WallBuys = require(Modules.WallBuys)
local Perks = require(Modules.Perks)
local Altar = require(Modules.Altar)
local Choices = require(Modules.Choices)
local Relics = require(Modules.Relics)
local PowerUps = require(Modules.PowerUps)
local Director = require(Modules.Director)

-- Boot -------------------------------------------------------------------------------------------

Players.CharacterAutoLoads = false

for _, group in { "Players", "Zombies", "Corpses", "PlayerBlock" } do
	pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, group)
end
-- Zombies walk through each other (no jams at windows and doors); corpses, torn boards and limbs
-- only rest on the house; window blockers stop players and nothing else.
PhysicsService:CollisionGroupSetCollidable("Zombies", "Zombies", false)
PhysicsService:CollisionGroupSetCollidable("Corpses", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Corpses", "Zombies", false)
PhysicsService:CollisionGroupSetCollidable("Corpses", "Corpses", false)
PhysicsService:CollisionGroupSetCollidable("PlayerBlock", "Zombies", false)
PhysicsService:CollisionGroupSetCollidable("PlayerBlock", "Corpses", false)
PhysicsService:CollisionGroupSetCollidable("PlayerBlock", "Default", false)

do
	local L = Config.Lighting
	Lighting.ClockTime = L.ClockTime
	Lighting.Brightness = L.Brightness
	Lighting.Ambient = L.Ambient
	Lighting.OutdoorAmbient = L.OutdoorAmbient
	Lighting.GlobalShadows = true
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = L.Atmosphere.Density
	atmosphere.Offset = L.Atmosphere.Offset
	atmosphere.Color = L.Atmosphere.Color
	atmosphere.Decay = L.Atmosphere.Decay
	atmosphere.Glare = L.Atmosphere.Glare
	atmosphere.Haze = L.Atmosphere.Haze
	atmosphere.Parent = Lighting
end

-- A bare place's baseplate and spawn would sit inside the yard.
for _, child in workspace:GetChildren() do
	if child:IsA("SpawnLocation") or (child:IsA("BasePart") and child.Name == "Baseplate") then
		child:Destroy()
	end
end

local fx = Instance.new("Folder")
fx.Name = "Fx"
fx.Parent = workspace

Net.Make()
Survivors.Start()
Arsenal.Start()
Horde.Start()

-- Joining the systems up --------------------------------------------------------------------------

local POINTS = Config.Points
local hud = Net.Get("Hud")

Arsenal.DamageZombie = function(player, zombie, part, amount, head, melee, direction, paysHit)
	local killed, dealt = Horde.Damage(zombie, amount, part, player, { Head = head, Melee = melee, Direction = direction })
	if dealt <= 0 then
		return
	end
	if killed then
		local kind = zombie:GetAttribute("Kind")
		local pay = if kind == "Brute" then Config.Specials.Brute.Points
			elseif melee then POINTS.MeleeKill
			elseif head then POINTS.HeadKill
			else POINTS.Kill
		Economy.Add(player, pay)
		Economy.Count(player, "Kills")
		if head then
			Economy.Count(player, "Headshots")
		end
	elseif paysHit then
		Economy.Add(player, POINTS.Hit)
	end
	hud:FireClient(player, "Hit", head, killed)
end

Horde.Killed:Connect(function(_, killer, info)
	if not info.Purge then
		PowerUps.OnKill(info.Position)
	end
	local leech = killer and killer:GetAttribute("RelicLeech") or 0
	if killer and leech > 0 then
		Survivors.Heal(killer, leech)
	end
end)

PowerUps.Purge = Horde.KillAll

-- Runs -------------------------------------------------------------------------------------------

local current = nil

local function studioNumber(name)
	local v = workspace:GetAttribute(name)
	return if RunService:IsStudio() and type(v) == "number" then v else nil
end

-- A player new to this run: clean slate.
local function enlist(player)
	Economy.Reset(player, studioNumber("EndlessStartPoints") or Config.Run.StartPoints)
	Perks.Reset(player)
	Relics.Reset(player)
end

local function spawnAt(player, at)
	if not Survivors.InRun(player) then
		enlist(player)
	end
	local character = Survivors.Spawn(player, at)
	if character then
		Arsenal.GiveStart(player)
	end
end

-- Everyone not standing in the house (dead, or new) comes in at the start room.
local function respawnDead(run)
	local waiting = {}
	for _, p in Players:GetPlayers() do
		if not Survivors.IsAlive(p) then
			table.insert(waiting, p)
		end
	end
	local points = run.House:StartPoints(#waiting)
	for i, p in waiting do
		task.spawn(spawnAt, p, points[i])
	end
end

local function startRun()
	local run = { Maid = Util.Maid(), State = "Waiting", Round = 0 }
	workspace:SetAttribute("WaveState", "Waiting")
	workspace:SetAttribute("Wave", 0)
	local house = HouseBuilder.Build(HouseLayout, workspace)
	run.House = house
	run.Maid:Add(house.Model)
	for _, setup in { Windows.Setup, Doors.Setup, Randomizer.Setup, WallBuys.Setup, Perks.Setup, Altar.Setup, PowerUps.Setup } do
		local ok, err = pcall(setup, run, run.Maid)
		if not ok then
			warn("Endless: a system failed to set up:", err)
		end
	end
	for _, p in Players:GetPlayers() do
		Survivors.Reset(p)
	end
	task.wait(Config.Run.SpawnSettle)
	run.RespawnDead = function()
		respawnDead(run)
	end
	respawnDead(run)
	-- Joining between rounds: straight in. During a round: at its end (Director).
	run.Maid:Add(Players.PlayerAdded:Connect(function(player)
		if run.State ~= "Wave" then
			spawnAt(player, house:StartPoints(1)[1])
		end
	end))
	return run
end

local function endRun(run, reached)
	run.State = "GameOver"
	workspace:SetAttribute("WaveState", "GameOver")
	workspace:SetAttribute("BestRound", math.max(workspace:GetAttribute("BestRound") or 0, reached))
	hud:FireAllClients("GameOver", reached)
	-- Hook for the zombie mode's port: save the best round on the profile here (Profile, never from
	-- a Studio test: owner rule, no live DataStore writes from tests).
	task.wait(Config.Run.GameOverTime)
	Relics.Clear()
	Choices.ClearAll()
	Horde.Clear()
	run.Maid:Clean()
	fx:ClearAllChildren()
	workspace:SetAttribute("Power", false)
	workspace:SetAttribute("ReaperUntil", nil)
	workspace:SetAttribute("DoublePayUntil", nil)
	for _, p in Players:GetPlayers() do
		if p.Character then
			p.Character:Destroy()
			p.Character = nil
		end
		for _, t in Arsenal.Tools(p) do
			t:Destroy()
		end
	end
end

while true do
	while #Players:GetPlayers() == 0 do
		task.wait(0.5)
	end
	current = startRun()
	local ok, reached = pcall(Director.Run, current)
	if not ok then
		warn("Endless: the run broke:", reached)
		reached = current.Round
	end
	endRun(current, reached or 0)
	current = nil
end
