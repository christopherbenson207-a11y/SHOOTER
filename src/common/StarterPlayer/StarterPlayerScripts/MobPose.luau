-- Mob attack poses, drawn on each client from Remotes.MobAttack (the server's MobAttack):
-- one arm rises past the head for the windup and rakes down across the body on the swing,
-- the torso coils and twists with it and the head follows; with no arms left the mob
-- lunges head first to bite; a "Vault" style puts both hands on a fence and pitches over. Offsets ride on the joints' C0 on top of the walk animation
-- (nothing else on the client touches shoulder, waist or neck C0; MobImpact and the
-- animations use Transform) and ease back to rest after the swing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local MobPose = {}

local RAD = math.rad

-- Pose per joint for each phase, as joint-space rotations on C0 (x = pitch: + raises an
-- arm forward and up, + leans a torso or head back; y = twist; z = + swings an arm out).
-- Written for a right-arm swipe; a left swipe mirrors y and z.
local POSES = {
	Arm = {
		Windup = Vector3.new(75, 0, 30),
		Swing = Vector3.new(-55, 0, -35),
	},
	Waist = {
		Windup = Vector3.new(8, -22, 0),
		Swing = Vector3.new(-14, 26, 0),
	},
	Neck = {
		Windup = Vector3.new(10, -8, 0),
		Swing = Vector3.new(-12, 10, 0),
	},
	BiteWaist = {
		Windup = Vector3.new(16, 0, 0),
		Swing = Vector3.new(-32, 0, 0),
	},
	BiteNeck = {
		Windup = Vector3.new(14, 0, 0),
		Swing = Vector3.new(-18, 0, 0),
	},
	-- Vaulting a fence: both hands reach forward onto the top and the body pitches over,
	-- then the arms push down and back as it drops off the far side.
	VaultArm = {
		Windup = Vector3.new(35, 0, 12),
		Swing = Vector3.new(-25, 0, 18),
	},
	VaultWaist = {
		Windup = Vector3.new(-28, 0, 0),
		Swing = Vector3.new(-12, 0, 0),
	},
	VaultNeck = {
		Windup = Vector3.new(16, 0, 0),
		Swing = Vector3.new(6, 0, 0),
	},
}
local REST_TIME = 0.4
local CANCEL_TIME = 0.2

local baseC0 = setmetatable({}, { __mode = "k" })
local tokens = setmetatable({}, { __mode = "k" })

local function joint(model, partName, jointName)
	local part = model:FindFirstChild(partName)
	local j = part and part:FindFirstChild(jointName)
	if j and j:IsA("Motor6D") and j.Enabled and j.Part0 then
		if not baseC0[j] then
			baseC0[j] = j.C0
		end
		return j
	end
	return nil
end

local function rotation(deg, mirror)
	local m = if mirror then -1 else 1
	return CFrame.Angles(RAD(deg.X), RAD(deg.Y) * m, RAD(deg.Z) * m)
end

-- The joints a style moves and the pose set each one uses.
local function rig(model, style)
	local list = {}
	local function add(j, pose, mirror)
		if j then
			table.insert(list, { Joint = j, Pose = pose, Mirror = mirror })
		end
	end
	if style == "Vault" then
		add(joint(model, "RightUpperArm", "RightShoulder"), POSES.VaultArm)
		add(joint(model, "LeftUpperArm", "LeftShoulder"), POSES.VaultArm, true)
		add(joint(model, "UpperTorso", "Waist"), POSES.VaultWaist)
		add(joint(model, "Head", "Neck"), POSES.VaultNeck)
	elseif style == "Bite" then
		add(joint(model, "UpperTorso", "Waist"), POSES.BiteWaist)
		add(joint(model, "Head", "Neck"), POSES.BiteNeck)
	else
		add(joint(model, style .. "UpperArm", style .. "Shoulder"), POSES.Arm)
		add(joint(model, "UpperTorso", "Waist"), POSES.Waist)
		add(joint(model, "Head", "Neck"), POSES.Neck)
	end
	return list
end

local function tweenTo(j, cf, time, style, direction)
	TweenService:Create(j, TweenInfo.new(time, style, direction), { C0 = cf }):Play()
end

local function rest(model, time)
	for _, name in { { "RightUpperArm", "RightShoulder" }, { "LeftUpperArm", "LeftShoulder" }, { "UpperTorso", "Waist" }, { "Head", "Neck" } } do
		local j = joint(model, name[1], name[2])
		if j then
			tweenTo(j, baseC0[j], time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end
end

function MobPose.Play(model, phase, duration, style)
	if typeof(model) ~= "Instance" or not model.Parent or model:GetAttribute("Dead") then
		return
	end
	tokens[model] = (tokens[model] or 0) + 1
	local token = tokens[model]
	if phase == "Cancel" then
		rest(model, CANCEL_TIME)
		return
	end
	local mirror = style == "Left"
	for _, entry in rig(model, style or "Right") do
		local pose = entry.Pose[phase]
		if pose then
			local cf = baseC0[entry.Joint] * rotation(pose, mirror ~= (entry.Mirror == true))
			if phase == "Windup" then
				tweenTo(entry.Joint, cf, duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			else
				tweenTo(entry.Joint, cf, duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
	end
	if phase == "Swing" then
		task.delay(duration + 0.08, function()
			if tokens[model] == token and model.Parent then
				rest(model, REST_TIME)
			end
		end)
	end
end

function MobPose.Start()
	Remotes:WaitForChild("MobAttack").OnClientEvent:Connect(MobPose.Play)
end

return MobPose
