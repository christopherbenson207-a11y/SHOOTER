-- WAR soldiers on every client (ServerStorage.Modules.Soldier). A posed rig (attribute Rifle) keeps
-- its arms in the rifle-ready pose and leans its upper body to AimPitch at the waist. An unposed rig:
-- the rifle tilts to AimPitch on its GunJoint, and both arms reach the gun's grips (two-bone IK on
-- the shoulders and elbows). Both are set after the walk animation each frame, so the legs walk.
-- A soldier who is down (Downed) or dead lets go and the animation has the arms back.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SIDES = { Right = "RightGrip", Left = "LeftGrip" }
local rigs = {} -- [model] = rig

-- Two-bone IK (law of cosines) in the plane from the shoulder to the target. Returns the plane's
-- frame and the shoulder and elbow bends.
local function solve(origin, target, a, b)
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

-- Arm joints a posed rig (attribute Rifle) holds still, so the walk animation only moves the legs.
local HOLD = { "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

local function setup(model)
	local torso = model:WaitForChild("UpperTorso", 5)
	if model:GetAttribute("Rifle") then
		local joints = {}
		for _, name in HOLD do
			local j = model:FindFirstChild(name, true)
			if j and j:IsA("Motor6D") then
				table.insert(joints, j)
			end
		end
		local waist = torso and torso:FindFirstChild("Waist")
		rigs[model] = { Model = model, Hold = joints, Waist = waist, Pitch = 0 }
		return
	end
	local joint = torso and torso:WaitForChild("GunJoint", 5)
	if not joint then
		return
	end
	local rig = { Model = model, Torso = torso, Joint = joint, Arms = {}, Pitch = 0 }
	for side, gripName in SIDES do
		local upper = model:FindFirstChild(side .. "UpperArm")
		local lower = model:FindFirstChild(side .. "LowerArm")
		local hand = model:FindFirstChild(side .. "Hand")
		local shoulder = upper and upper:FindFirstChild(side .. "Shoulder")
		local elbow = lower and lower:FindFirstChild(side .. "Elbow")
		local wrist = hand and hand:FindFirstChild(side .. "Wrist")
		local grip = joint.Part1 and joint.Part1:FindFirstChild(gripName)
		-- Only Motor6D joints can be posed by C0 (an AnimationConstraint rig keeps its animation).
		if shoulder and elbow and wrist and grip and shoulder:IsA("Motor6D") and elbow:IsA("Motor6D") and wrist:IsA("Motor6D") then
			table.insert(rig.Arms, {
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
	rigs[model] = rig
end

local function release(rig)
	if rig.Hold then
		rig.Released = true
		return
	end
	for _, arm in rig.Arms do
		arm.Shoulder.C0 = arm.ShoulderC0
		arm.Elbow.C0 = arm.ElbowC0
	end
	rig.Released = true
end

local function step(dt)
	for model, rig in rigs do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local holding = hum and hum.Health > 0 and not model:GetAttribute("Downed") and not model:GetAttribute("Dead")
		if not holding then
			if not rig.Released then
				release(rig)
			end
			continue
		end
		rig.Released = false
		local want = model:GetAttribute("AimPitch") or 0
		rig.Pitch += (want - rig.Pitch) * math.min(1, dt * 12)
		if rig.Hold then
			for _, j in rig.Hold do
				j.Transform = CFrame.identity
			end
			if rig.Waist and rig.Waist:IsA("Motor6D") then
				rig.Waist.Transform = CFrame.Angles(rig.Pitch, 0, 0)
			end
			continue
		end
		rig.Joint.Transform = CFrame.Angles(rig.Pitch, 0, 0)
		local torso = rig.Torso
		for _, arm in rig.Arms do
			local origin = torso.CFrame * arm.ShoulderC0
			local plane, bend1, bend2 = solve(origin, arm.Grip.WorldPosition, arm.Upper, arm.Lower)
			arm.Shoulder.C0 = torso.CFrame:ToObjectSpace(plane) * CFrame.Angles(bend1, 0, 0)
			arm.Elbow.C0 = arm.ElbowC0 * CFrame.Angles(bend2, 0, 0)
			arm.Shoulder.Transform = CFrame.identity
			arm.Elbow.Transform = CFrame.identity
			arm.Wrist.Transform = CFrame.identity
		end
	end
end

CollectionService:GetInstanceAddedSignal("Soldier"):Connect(function(model)
	task.spawn(setup, model)
end)
CollectionService:GetInstanceRemovedSignal("Soldier"):Connect(function(model)
	rigs[model] = nil
end)
for _, model in CollectionService:GetTagged("Soldier") do
	task.spawn(setup, model)
end

-- After the animator has posed the frame, before it's drawn.
RunService.PreSimulation:Connect(step)
