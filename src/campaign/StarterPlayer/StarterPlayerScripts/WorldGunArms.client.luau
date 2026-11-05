-- Third-person guns (campaign, 4 Nov 2026; the block from the zombies GunClient). GunServer puts the gun in every
-- character's hands as character.WorldGun (held in front of the chest by GunRoot.GunJoint). Here every other player's
-- arms reach its RightGrip and LeftGrip (two-bone IK on the shoulders and elbows, after the animator has posed the
-- frame). Someone who is down, bandaging, inside, being eaten or dead lets go and the gun is hidden. Your own world gun
-- is always hidden (you see the viewmodel).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local poses = {} -- [character] = pose
local LET_GO = { "Downed", "Bandaging", "Inside", "Devoured", "Dead" }

local function solveArm(origin, target, a, b)
	local localized = origin:PointToObjectSpace(target)
	local unit = localized.Unit
	local c = localized.Magnitude
	local axis = Vector3.new(0, 0, -1):Cross(unit)
	local angle = math.acos(math.clamp(-unit.Z, -1, 1))
	local plane = if axis.Magnitude > 1e-4 then origin * CFrame.fromAxisAngle(axis.Unit, angle) else origin
	if c < math.abs(a - b) then
		return plane, -math.pi / 2, math.pi
	elseif c > a + b then
		return plane, math.pi / 2, 0
	end
	local a1 = -math.acos(math.clamp((-(b * b) + a * a + c * c) / (2 * a * c), -1, 1))
	local a2 = math.acos(math.clamp((b * b - a * a + c * c) / (2 * b * c), -1, 1))
	return plane, a1 + math.pi / 2, a2 - a1
end

local function setGunVisible(holder, visible)
	local k = if visible then 0 else 1
	for _, d in holder:GetDescendants() do
		if d:IsA("BasePart") and d.LocalTransparencyModifier ~= k then
			d.LocalTransparencyModifier = k
		end
	end
end

local function release(pose)
	for _, arm in pose.Arms do
		if arm.Shoulder.Parent then
			arm.Shoulder.C0 = arm.ShoulderC0
			arm.Elbow.C0 = arm.ElbowC0
		end
	end
	pose.Released = true
end

local function build(character, holder)
	local root = holder:FindFirstChild("GunRoot")
	local joint = root and root:FindFirstChild("GunJoint")
	local torso = joint and joint.Part0
	if not torso then
		return nil
	end
	local pose = { Holder = holder, Torso = torso, Arms = {}, Released = true }
	for side, gripName in { Right = "RightGrip", Left = "LeftGrip" } do
		local upper = character:FindFirstChild(side .. "UpperArm")
		local lower = character:FindFirstChild(side .. "LowerArm")
		local hand = character:FindFirstChild(side .. "Hand")
		local shoulder = upper and upper:FindFirstChild(side .. "Shoulder")
		local elbow = lower and lower:FindFirstChild(side .. "Elbow")
		local wrist = hand and hand:FindFirstChild(side .. "Wrist")
		local grip = root:FindFirstChild(gripName)
		if shoulder and elbow and wrist and grip and shoulder:IsA("Motor6D") and elbow:IsA("Motor6D") and wrist:IsA("Motor6D") then
			table.insert(pose.Arms, {
				Shoulder = shoulder,
				Elbow = elbow,
				Wrist = wrist,
				Grip = grip,
				ShoulderC0 = shoulder.C0,
				ElbowC0 = elbow.C0,
				Upper = (shoulder.C1.Position - elbow.C0.Position).Magnitude,
				Lower = (elbow.C1.Position - wrist.C0.Position).Magnitude + wrist.C1.Position.Magnitude * 0.6,
			})
		end
	end
	return pose
end

local function holding(character, holder)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0 and holder:GetAttribute("Gun")) then
		return false
	end
	if player:GetAttribute("Cutscene") then
		return false
	end
	for _, name in LET_GO do
		if character:GetAttribute(name) then
			return false
		end
	end
	return true
end

RunService.PreSimulation:Connect(function()
	local seen = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local holder = character and character:FindFirstChild("WorldGun")
		if not holder then
			continue
		end
		if other == player then
			setGunVisible(holder, false)
			continue
		end
		seen[character] = true
		local pose = poses[character]
		if pose and (pose.Holder ~= holder or not pose.Torso.Parent or (pose.Arms[1] and not pose.Arms[1].Shoulder.Parent)) then
			release(pose)
			pose = nil
		end
		if not pose then
			pose = build(character, holder)
			poses[character] = pose
			if not pose then
				continue
			end
		end
		if not holding(character, holder) then
			if not pose.Released then
				release(pose)
			end
			setGunVisible(holder, false)
			continue
		end
		if pose.Released then
			pose.Released = false
			setGunVisible(holder, true)
		end
		local torsoCF = pose.Torso.CFrame
		for _, arm in pose.Arms do
			local origin = torsoCF * arm.ShoulderC0
			local plane, bend1, bend2 = solveArm(origin, arm.Grip.WorldPosition, arm.Upper, arm.Lower)
			arm.Shoulder.C0 = torsoCF:ToObjectSpace(plane) * CFrame.Angles(bend1, 0, 0)
			arm.Elbow.C0 = arm.ElbowC0 * CFrame.Angles(bend2, 0, 0)
			arm.Shoulder.Transform = CFrame.identity
			arm.Elbow.Transform = CFrame.identity
			arm.Wrist.Transform = CFrame.identity
		end
	end
	for character in poses do
		if not seen[character] then
			poses[character] = nil
		end
	end
end)
