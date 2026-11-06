-- First-person bandaging (ServerStorage.Modules.Bandages sets the character attributes
-- Bandaging, BandageDone and BandagePart, the limb being wrapped). GunClient puts the gun
-- down; this brings up your own arms (StarterPlayerScripts.ViewArms, dressed in your avatar's
-- shirt and skin). A forearm wound: that forearm comes up across the lower view, palm up, and
-- the other hand winds the roll round it while the wrap grows from wrist to elbow. Any other
-- wound: one hand pins the loose end low in front and the other winds the roll round the
-- wounded part just below the view. The finished wrap on the body is made by the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local ViewArms = require(script.Parent:WaitForChild("ViewArms"))

local Settings = GameConfig.Bandages
local Shoulders = { Left = GameConfig.ViewArms.LeftShoulder, Right = GameConfig.ViewArms.RightShoulder }
local player = Players.LocalPlayer

local RAISE_TIME = 0.3
local WRAP_TURNS = 5 -- turns of the roll over the whole ApplyTime
local WRAP_FROM = 0.15 -- along the forearm, 0 = wrist, 1 = elbow
local WRAP_TO = 0.8
local ROLL_DIAMETER = 0.15
local ROLL_WIDTH = 0.1
local LOWER = Vector3.new(0, -0.55, 0.12) -- where the hands start from (and go back to), camera space

-- Camera space (x right, y up, -z forward), drawn for a left-arm wound; a right one mirrors it.
-- The held forearm: the wrist near the middle of the view, the elbow out to the lower left.
local HELD_WRIST = Vector3.new(0.14, -0.17, -0.8)
local HELD_ALONG = Vector3.new(-1, -0.45, 0.45).Unit -- from the wrist toward the elbow
local HELD_PALM = Vector3.new(0, 0.35, 1).Unit -- the hand's back faces the camera side, palm up
-- Body, leg or head wound: the roll circles this point, around this axis, low in the view.
local LOW_CENTRE = Vector3.new(0.05, -0.3, -0.72)
local LOW_AXIS = Vector3.new(0, 1, 0.4).Unit
local LOW_RADIUS = 0.13
local PIN_HAND = Vector3.new(-0.12, -0.26, -0.74) -- the hand holding the loose end down

local rig -- { Model, Arms, Wrap, Strip, Roll }
local raise = 0

local function render(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Fabric
	part.Color = Settings.Color
	return part
end

-- The roll in hand: a short fabric cylinder (axis along X) with a darker core.
local function buildRoll(model)
	local roll = Instance.new("Model")
	roll.Name = "Roll"
	local body = render(Instance.new("Part"))
	body.Name = "Body"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(ROLL_WIDTH, ROLL_DIAMETER, ROLL_DIAMETER)
	body.Parent = roll
	local core = render(Instance.new("Part"))
	core.Name = "Core"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(ROLL_WIDTH + 0.004, ROLL_DIAMETER * 0.38, ROLL_DIAMETER * 0.38)
	core.Color = Settings.Color:Lerp(Color3.new(0, 0, 0), 0.35)
	core.Parent = roll
	roll.PrimaryPart = body
	roll.Parent = model
	return roll
end

local function build(character)
	local model = Instance.new("Model")
	model.Name = "BandageView"
	local r = { Model = model }
	r.Arms = ViewArms.new(character, model)
	r.Wrap = render(Instance.new("Part"))
	r.Wrap.Name = "Wrap"
	r.Wrap.Shape = Enum.PartType.Cylinder
	r.Wrap.Parent = model
	r.Strip = render(Instance.new("Part"))
	r.Strip.Name = "Strip"
	r.Strip.Parent = model
	r.Roll = buildRoll(model)
	model.Parent = workspace.CurrentCamera
	return r
end

local function clear()
	if rig then
		rig.Arms:Destroy()
		rig.Model:Destroy()
		rig = nil
	end
end

-- A rotation whose Y (up) runs along `up`, turned so X follows `side` as closely as it can.
local function frame(up, side)
	local x = side - up * side:Dot(up)
	if x.Magnitude < 1e-4 then
		x = up:Cross(Vector3.zAxis)
	end
	x = x.Unit
	return CFrame.fromMatrix(Vector3.zero, x, up, x:Cross(up))
end

-- Lays a straight ViewArms arm (hand first; the arm runs up the hand's Y) from handCF.
local function place(arm, handCF, parts, cframes)
	for _, piece in arm.Pieces do
		table.insert(parts, piece.Part)
		table.insert(cframes, handCF * piece.Offset)
	end
end

-- A hand whose grip point sits at gripPos, its arm reaching back toward the shoulder.
local function gripHand(arm, gripPos, shoulder, side)
	local rotation = frame((shoulder - gripPos).Unit, side)
	return rotation + (gripPos - rotation * arm.Grip)
end

-- The roll's frame: its axis (X) along `axis`, spun as it unwinds.
local function rollFrame(pos, axis, radial, spin)
	return CFrame.fromMatrix(pos, axis, radial, axis:Cross(radial)) * CFrame.Angles(spin, 0, 0)
end

local function strip(from, to, up)
	local span = math.max((to - from).Magnitude, 0.01)
	rig.Strip.Size = Vector3.new(0.004, ROLL_WIDTH * 0.8, span)
	rig.Strip.CFrame = CFrame.lookAt((from + to) / 2, to, up)
end

RunService:BindToRenderStep("BandageView", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local character = player.Character
	local active = character and character:GetAttribute("Bandaging") and character:GetAttribute("Downed") ~= true
	raise = math.clamp(raise + (if active then dt else -dt) / RAISE_TIME, 0, 1)
	if raise <= 0 then
		clear()
		return
	end
	if not rig and character then
		rig = build(character)
	end
	if not rig then
		return
	end

	local done = character and character:GetAttribute("BandageDone")
	local k = 1
	if done then
		k = math.clamp(1 - (done - workspace:GetServerTimeNow()) / Settings.ApplyTime, 0, 1)
	end
	local up = 1 - (1 - raise) ^ 3
	local camera = workspace.CurrentCamera
	local bob = math.sin(os.clock() * 7) * 0.004
	-- Everything below is posed in camera space, then carried into the world by `base`.
	local base = camera.CFrame * CFrame.new(LOWER * (1 - up) + Vector3.new(0, bob, 0))
	local turn = k * WRAP_TURNS * math.pi * 2
	local spin = -turn * 2.5
	local parts, cframes = {}, {}

	local limb = character and character:GetAttribute("BandagePart") or ""
	local armSide = if limb:find("Arm") then (if limb:find("Left") then "Left" else "Right") else nil
	if armSide then
		local helper = if armSide == "Left" then "Right" else "Left"
		local m = if armSide == "Left" then 1 else -1
		local function mirror(v)
			return Vector3.new(v.X * m, v.Y, v.Z)
		end
		local held = rig.Arms[armSide]
		local handCF = base * (frame(mirror(HELD_ALONG), mirror(HELD_PALM)) + mirror(HELD_WRIST))
		place(held, handCF, parts, cframes)
		local forearm = held.Pieces[2] or held.Pieces[1]
		local fcf = handCF * forearm.Offset
		local fsize = forearm.Part.Size
		local radius = math.max(fsize.X, fsize.Z) / 2
		local half = fsize.Y / 2

		-- The wrap grows along the forearm from the wrist toward the elbow.
		local from = (WRAP_FROM - 0.5) * 2 * half
		local to = from + (WRAP_TO - WRAP_FROM) * 2 * half * k
		local length = math.max(to - from, 0.005)
		rig.Wrap.Transparency = 0
		rig.Wrap.Size = Vector3.new(length, radius * 2 + 0.02, radius * 2 + 0.02)
		rig.Wrap.CFrame = fcf * CFrame.new(0, (from + to) / 2, 0) * CFrame.Angles(0, 0, math.rad(90))

		-- The other hand carries the roll round the forearm at the wrap's leading edge.
		local axis = fcf.UpVector
		local edge = (fcf * CFrame.new(0, to, 0)).Position
		local function radialAt(a)
			return fcf.RightVector * math.cos(a) + fcf.LookVector * math.sin(a)
		end
		local radial = radialAt(turn * m)
		local rollPos = edge + radial * (radius + ROLL_DIAMETER * 0.5 + 0.01)
		rig.Roll:PivotTo(rollFrame(rollPos, axis, radial, spin))
		local shoulder = base * Shoulders[helper]
		local gripPos = rollPos + radial * (ROLL_DIAMETER * 0.5 + 0.02)
		place(rig.Arms[helper], gripHand(rig.Arms[helper], gripPos, shoulder, -radial), parts, cframes)
		-- The strip running off the roll onto the arm, a little behind the roll.
		local onArm = edge + radialAt((turn - 0.9) * m) * (radius + 0.012)
		strip(onArm, rollPos - radial * (ROLL_DIAMETER * 0.45), axis)
	else
		-- Leg, body or head: the wrap itself is out of view; the hands and roll show the work.
		rig.Wrap.Transparency = 1
		local axis = base:VectorToWorldSpace(LOW_AXIS)
		local centre = base * LOW_CENTRE
		local x0 = base.RightVector
		local z0 = axis:Cross(x0).Unit
		local radial = x0 * math.cos(turn) + z0 * math.sin(turn)
		local rollPos = centre + radial * LOW_RADIUS
		rig.Roll:PivotTo(rollFrame(rollPos, axis, radial, spin))
		local right, left = rig.Arms.Right, rig.Arms.Left
		local gripPos = rollPos + radial * (ROLL_DIAMETER * 0.5 + 0.02)
		place(right, gripHand(right, gripPos, base * Shoulders.Right, -radial), parts, cframes)
		local pin = base * PIN_HAND
		place(left, gripHand(left, pin, base * Shoulders.Left, base.RightVector), parts, cframes)
		strip(pin + axis * -0.02, rollPos - radial * (ROLL_DIAMETER * 0.45), axis)
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end)

player.CharacterRemoving:Connect(function()
	clear()
	raise = 0
end)
