-- Swinging doors. A door is a model tagged "Door" holding a "Leaf" model (the part that
-- moves; its PrimaryPart is the slab) and anything else (the frame), which stays put.
-- The leaf turns on the slab's edge, picked by the door's HingeSide attribute (-1 left,
-- 1 right, from the slab's own X axis), and always swings away from whoever opens it.
-- Bullet holes cut into the slab live inside the leaf, so they swing with it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)

local Settings = GameConfig.Doors

local Doors = {}

local doors = {} -- [model] = { Leaf, Slab, Hinge, Offset, Angle, Open, Token, Prompt }

local function setAngle(door, angle)
	door.Angle = angle
	door.Leaf:PivotTo(door.Hinge * CFrame.Angles(0, math.rad(angle), 0) * door.Offset)
end

local function swing(door, target, time)
	door.Token += 1
	local token = door.Token
	local from = door.Angle
	SoundKit.Play("World/DoorCreak", { Position = door.Slab.Position })
	task.spawn(function()
		local t = 0
		while t < time do
			t += RunService.Heartbeat:Wait()
			if door.Token ~= token then
				return
			end
			local k = math.min(t / time, 1)
			k = 1 - (1 - k) * (1 - k) -- ease out
			setAngle(door, from + (target - from) * k)
		end
		setAngle(door, target)
	end)
end

-- A door shot to bits can't be opened or closed any more.
local function wrecked(door)
	if door.Slab.Transparency < 1 then
		return false
	end
	for _, d in door.Leaf:GetDescendants() do
		if d:IsA("BasePart") and d.Anchored and d.Transparency < 1 then
			return false
		end
	end
	return true
end

function Doors.IsOpen(model)
	local door = doors[model]
	return door == nil or door.Open or wrecked(door)
end

-- Swings the door open away from fromPos.
function Doors.Open(model, fromPos)
	local door = doors[model]
	if not door or door.Open or wrecked(door) then
		return
	end
	local side = (fromPos - door.Hinge.Position):Dot(door.Hinge.LookVector)
	-- A positive angle swings the leaf towards the hinge's LookVector side.
	local target = (if side > 0 then -Settings.OpenAngle else Settings.OpenAngle) * door.Side
	door.Open = true
	door.Prompt.ActionText = "Close"
	swing(door, target, Settings.OpenTime)
end

function Doors.Close(model)
	local door = doors[model]
	if not door or not door.Open or wrecked(door) then
		return
	end
	door.Open = false
	door.Prompt.ActionText = "Open"
	swing(door, 0, Settings.CloseTime)
end

function Doors.Toggle(model, fromPos)
	local door = doors[model]
	if door and door.Open then
		Doors.Close(model)
	else
		Doors.Open(model, fromPos)
	end
end

local function setup(model)
	local leaf = model:FindFirstChild("Leaf")
	local slab = leaf and leaf.PrimaryPart
	if doors[model] or not slab then
		return
	end
	local side = model:GetAttribute("HingeSide") or -1
	local hinge = slab.CFrame * CFrame.new(side * slab.Size.X / 2, 0, 0)
	hinge = CFrame.lookAlong(hinge.Position, hinge.LookVector, Vector3.yAxis)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DoorPrompt"
	prompt.ActionText = "Open"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = Settings.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = slab

	-- Zombies path through closed doors (they shove them open), at a small extra cost.
	local modifier = Instance.new("PathfindingModifier")
	modifier.Label = "Door"
	modifier.PassThrough = true
	modifier.Parent = slab

	local door = {
		Leaf = leaf,
		Slab = slab,
		Hinge = hinge,
		Offset = hinge:Inverse() * leaf:GetPivot(),
		Side = -side,
		Angle = 0,
		Open = false,
		Token = 0,
		Prompt = prompt,
	}
	doors[model] = door

	prompt.Triggered:Connect(function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		if wrecked(door) then
			prompt.Enabled = false
			return
		end
		Doors.Toggle(model, root.Position)
	end)
end

function Doors.Start()
	CollectionService:GetInstanceAddedSignal("Door"):Connect(setup)
	for _, model in CollectionService:GetTagged("Door") do
		setup(model)
	end
end

return Doors
