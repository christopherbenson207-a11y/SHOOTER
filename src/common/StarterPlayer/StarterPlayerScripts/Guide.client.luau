-- Shows the way on this client, one thing at a time:
--   The stairs never glow (the owner wants the way out marked, not the way down).
--   Downstairs, between waves and during them, the cheapest debris pile you can afford to
--   clear (tag Debris, Cost, not yet Cleared) glows faintly, so points always point somewhere.
--   Once the doors can be broken open (workspace BreakoutReady, after wave
--   GameConfig.Breakout.BreakoutFrom), the ground-floor doors that have a Break out prompt
--   glow amber through the walls until someone breaks out.
--   During the breakout one hiding spot at a time glows: the nearest cover that gets you
--   closer to the landing zone (Map.Extraction). Reach it and the next one lights up; with none
--   left, the red flare on the zone glows. Each spot (tag HideSpot) points at the prop it stands
--   for with its Cover ObjectValue.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local AMBER = Color3.fromRGB(255, 176, 60)

local function newMark(name)
	local h = Instance.new("Highlight")
	h.Name = name
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.FillColor = AMBER
	h.OutlineColor = AMBER
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.Enabled = false
	h.Parent = workspace.CurrentCamera
	return h
end

local doorMarks = {} -- door model -> Highlight
local spotMark = newMark("NextCover")
local stairsMark = newMark("Stairs")
local debrisMark = newMark("NextDebris")

local function defendHouse()
	local map = workspace:FindFirstChild("Map")
	if map then
		for _, child in map:GetChildren() do
			if child:GetAttribute("DefendHouse") then
				return child
			end
		end
	end
	return nil
end

-- The cheapest pile still standing that you can pay for.
local function affordableDebris()
	local points = player:GetAttribute("Points") or 0
	local best, bestCost
	for _, pile in CollectionService:GetTagged("Debris") do
		local cost = pile:GetAttribute("Cost")
		if cost and cost <= points and not pile:GetAttribute("Cleared") and pile:IsDescendantOf(workspace) then
			if not bestCost or cost < bestCost then
				best, bestCost = pile, cost
			end
		end
	end
	return best
end
local target = nil
local reached = {}
local wasBreakout = false

local function root()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and hrp and player:GetAttribute("InMatch") then
		return hrp, character
	end
	return nil, nil
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function inBox(part, point, margin)
	local rel = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(rel.X) <= half.X + margin and math.abs(rel.Z) <= half.Z + margin
end

local function exitPoint()
	local map = workspace:FindFirstChild("Map")
	local extraction = map and map:FindFirstChild("Extraction")
	local zone = extraction and extraction:FindFirstChild("Zone")
	return zone and zone.Position
end

-- The next spot to make for: the nearest one not yet reached that is closer to the exit than
-- you are; with none left, the one nearest the exit.
local function pickSpot(hrp, exit)
	local mine = flatDistance(hrp.Position, exit)
	local best, bestD, last, lastD
	for _, spot in CollectionService:GetTagged("HideSpot") do
		local toExit = flatDistance(spot.Position, exit)
		if not lastD or toExit < lastD then
			last, lastD = spot, toExit
		end
		if not reached[spot] and toExit < mine - 8 then
			local d = flatDistance(spot.Position, hrp.Position)
			if not bestD or d < bestD then
				best, bestD = spot, d
			end
		end
	end
	return best or last
end

local function coverOf(spot)
	local value = spot and spot:FindFirstChild("Cover")
	return value and value.Value
end

-- The doors with a Break out prompt (MatchServer puts it on the frame's BreakoutPoint).
local function exitDoors()
	local list = {}
	local map = workspace:FindFirstChild("Map")
	if not map then
		return list
	end
	for _, d in map:GetDescendants() do
		if d:IsA("Attachment") and d.Name == "BreakoutPoint" and d.Parent and d.Parent.Parent then
			table.insert(list, d.Parent.Parent)
		end
	end
	return list
end

local doorCheckAt = 0
local doors = {}

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local pulse = 0.5 + 0.5 * math.sin(now * 4)
	local hrp, character = root()
	local ready = workspace:GetAttribute("BreakoutReady") == true
	local breakout = workspace:GetAttribute("Breakout") == true

	-- Down from the start room, then the next room to open.
	local house = defendHouse()
	local stairs = house and house:FindFirstChild("Stairs")
	local slab = house and house:FindFirstChild("U_Slab_A")
	local upstairs = hrp and slab and hrp.Position.Y > slab.Position.Y - 1
	if false and upstairs and stairs then
		stairsMark.Adornee = stairs
		stairsMark.Enabled = true
		stairsMark.OutlineTransparency = 0.15 * pulse
		stairsMark.FillTransparency = 0.6 + 0.3 * pulse
	else
		stairsMark.Enabled = false
	end
	local pile = hrp and not upstairs and not breakout and not ready and affordableDebris()
	if pile then
		debrisMark.Adornee = pile
		debrisMark.Enabled = true
		debrisMark.OutlineTransparency = 0.35 + 0.3 * pulse
		debrisMark.FillTransparency = 1
	else
		debrisMark.Enabled = false
	end

	-- The way out of the house.
	if now >= doorCheckAt then
		doorCheckAt = now + 1
		doors = if ready and not breakout then exitDoors() else {}
	end
	local showing = {}
	for _, door in doors do
		if hrp and door.Parent then
			local mark = doorMarks[door] or newMark("ExitDoor")
			doorMarks[door] = mark
			mark.Adornee = door
			mark.Enabled = true
			mark.OutlineTransparency = 0.15 * pulse
			mark.FillTransparency = 0.55 + 0.3 * pulse
			showing[door] = true
		end
	end
	for door, mark in doorMarks do
		if not showing[door] then
			mark:Destroy()
			doorMarks[door] = nil
		end
	end

	-- Cover to cover toward the roadblock.
	if breakout and not wasBreakout then
		table.clear(reached)
		target = nil
	end
	wasBreakout = breakout
	local exit = exitPoint()
	if breakout and hrp and exit and workspace:GetAttribute("WaveState") == "Breakout" then
		local here = target and (inBox(target, hrp.Position, 1)
			or (character:GetAttribute("Hiding") and character:GetAttribute("HideId") == target:GetAttribute("HideId")))
		local passed = target and flatDistance(target.Position, exit) > flatDistance(hrp.Position, exit) + 12
		if here or passed then
			reached[target] = true
			target = nil
		end
		target = target or pickSpot(hrp, exit)
		local cover = coverOf(target)
		if not cover or reached[target] or not cover:IsDescendantOf(workspace) then
			local extraction = workspace.Map:FindFirstChild("Extraction")
			cover = extraction and extraction:FindFirstChild("Flare")
		end
		if cover then
			spotMark.Adornee = cover
			spotMark.Enabled = true
			spotMark.OutlineTransparency = 0.1 * pulse
			spotMark.FillTransparency = 0.7 + 0.2 * pulse
		else
			spotMark.Enabled = false
		end
	else
		spotMark.Enabled = false
	end
end)
