-- Doors and stair gates you buy (Call of Duty Zombies). Every run each price moves by up to
-- Config.Doors.Jitter from the layout's, in Step steps, so prices are learnt again each run. Hold
-- the prompt and pay: a door swings away from you, a gate sinks into the floor, and the zones on
-- both sides are open (their windows and hatches start sending zombies, see Director).
-- Opened fires (door, player).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Endless.Config)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)

local DOORS = Config.Doors

local Doors = {}
Doors.Opened = Util.Signal()

local house

local function jitter(cost: number): number
	if cost <= 0 then
		return 0
	end
	local steps = math.floor(DOORS.Jitter / DOORS.Step)
	return math.max(DOORS.Step, cost + math.random(-steps, steps) * DOORS.Step)
end

local function partsOf(door)
	local list = {}
	for _, p in door.Leaf:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(list, p)
		end
	end
	return list
end

-- The leaf swings 100 degrees on its hinge, away from `from`.
local function swing(door, from: Vector3?)
	local parts = partsOf(door)
	local start = {}
	for _, p in parts do
		start[p] = p.CFrame
		p.CanCollide = false
	end
	local hinge = CFrame.new(door.Center - door.Along * (door.Width / 2))
	local away = if from and (from - door.Center):Dot(door.Normal) > 0 then -door.Normal else door.Normal
	local function freeEnd(angle)
		return (CFrame.Angles(0, angle, 0) * door.Along) * door.Width
	end
	local angle = math.rad(100)
	if freeEnd(angle):Dot(away) < freeEnd(-angle):Dot(away) then
		angle = -angle
	end
	local t = 0
	while t < 1 do
		t = math.min(1, t + RunService.Heartbeat:Wait() / DOORS.OpenTime)
		local eased = 1 - (1 - t) ^ 3
		local turn = hinge * CFrame.Angles(0, angle * eased, 0) * hinge:Inverse()
		for _, p in parts do
			if p.Parent then
				p.CFrame = turn * start[p]
			end
		end
	end
end

local function sink(door)
	for _, p in partsOf(door) do
		p.CanCollide = false
		TweenService:Create(p, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = p.CFrame - Vector3.new(0, door.Height + 1, 0) }):Play()
	end
end

function Doors.Open(door, player: Player?)
	if door.Open then
		return
	end
	door.Open = true
	if door.Prompt then
		door.Prompt:Destroy()
		door.Prompt = nil
	end
	for _, zid in door.Zones do
		house.Zones[zid].Open = true
	end
	Sfx.Play("World/DoorCreak", { Position = door.Center })
	if door.Kind == "Gate" then
		sink(door)
	else
		Sfx.Play("World/WoodBreak", { Position = door.Center, Volume = 0.6 })
		local from = player and player.Character and player.Character:GetPivot().Position
		task.spawn(swing, door, from)
	end
	Doors.Opened:Fire(door, player)
end

function Doors.Setup(run, maid)
	house = run.House
	for _, door in house.Doors do
		door.Cost = jitter(door.BaseCost)
		local leaf = door.Leaf.PrimaryPart
		local action = if door.Kind == "Gate" then "Open Gate" else "Open Door"
		local prompt = Util.Prompt(leaf, action .. "  (" .. door.Cost .. ")", "", DOORS.HoldTime, 9)
		prompt:SetAttribute("Price", door.Cost)
		door.Prompt = prompt
		prompt.Triggered:Connect(function(player)
			if door.Open or not Survivors.IsStanding(player) then
				return
			end
			if Economy.Spend(player, door.Cost) then
				Doors.Open(door, player)
			end
		end)
	end
	if RunService:IsStudio() and workspace:GetAttribute("EndlessOpenAll") then
		for _, door in house.Doors do
			Doors.Open(door, nil)
		end
	end
end

return Doors
