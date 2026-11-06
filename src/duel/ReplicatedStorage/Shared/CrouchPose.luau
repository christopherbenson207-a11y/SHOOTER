--!strict
-- Shared.CrouchPose: the crouch other players see, so a crouched or sliding player's hitbox matches their camera
-- (5 Nov 2026 duel pass; numbers GameConfig.Evade.Pose). No crouch animation exists, so the pose is made from the R15
-- joints, the way PlayerHealth poses a downed body: thighs swing forward Thigh degrees, knees bend Knee degrees, the
-- feet turn back level, and the hips drop by exactly what the bent legs lose in height so the feet stay on the floor.
-- The server poses (EvadeServer, from the character's Crouching attribute) so the change replicates to everyone and
-- the server's own copy of the body (HitHistory, GunServer) crouches too. The owner's client asks Drop() for how far
-- its camera should sink: the same distance as the head.
-- Joints are Motor6Ds or, on avatars with the R15 joint upgrade, AnimationConstraints (as WorldGunArms reads them).
-- The animator owns each joint's Transform, so the pose goes in the other end: a Motor6D's C0, or the constraint's
-- Attachment0 frame (the same role). Animations still play on top, so walking crouched bends the legs further.
--   CrouchPose.Enabled() -> boolean
--   CrouchPose.Drop(character) -> studs the head sinks when crouched (nil when the rig has no R15 legs)
--   CrouchPose.Apply(character, on, time?) -> poses or stands the body (server)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local CrouchPose = {}

-- One joint: what to pose (the Motor6D, or the constraint's Attachment0), which property, and its two frames.
type Joint = { target: Instance, prop: string, c0: CFrame, c1: CFrame }
type Leg = { hip: Joint, knee: Joint, ankle: Joint? }

local function cfg(): any
	return GameConfig.Evade.Pose
end

function CrouchPose.Enabled(): boolean
	local c = cfg()
	return c ~= nil and c.Enabled == true
end

-- A joint's rest frame is kept on what gets posed the first time it is read (a fresh joint from the avatar loader
-- starts clean), so measuring and standing up always work from the rest pose.
local function rest(target: Instance, current: CFrame): CFrame
	local saved = target:GetAttribute("BaseC0")
	if typeof(saved) == "CFrame" then
		return saved
	end
	return current
end

local function joint(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	local inst = part and part:FindFirstChild(jointName)
	if not inst then
		return nil
	end
	if inst:IsA("Motor6D") then
		return { target = inst, prop = "C0", c0 = rest(inst, inst.C0), c1 = inst.C1 }
	elseif inst:IsA("AnimationConstraint") then
		local a0, a1 = inst.Attachment0, inst.Attachment1
		if a0 and a1 then
			return { target = a0, prop = "CFrame", c0 = rest(a0, a0.CFrame), c1 = a1.CFrame }
		end
	end
	return nil
end

local function legs(character: Model): { Leg }
	local list: { Leg } = {}
	for _, side in { "Left", "Right" } do
		local hip = joint(character, side .. "UpperLeg", side .. "Hip")
		local knee = joint(character, side .. "LowerLeg", side .. "Knee")
		if hip and knee then
			table.insert(list, { hip = hip, knee = knee, ankle = joint(character, side .. "Foot", side .. "Ankle") })
		end
	end
	return list
end

local function dropFor(list: { Leg }): number?
	if #list == 0 then
		return nil
	end
	local c = cfg()
	local thigh, knee = math.rad(c.Thigh), math.rad(c.Knee)
	local total = 0
	for _, leg in list do
		-- Hip to knee along the thigh, knee to ankle along the shin, from the joints' own frames.
		local upper = (leg.hip.c1.Position - leg.knee.c0.Position).Magnitude
		local lower = if leg.ankle then (leg.knee.c1.Position - leg.ankle.c0.Position).Magnitude else upper
		total += (upper + lower) - (upper * math.cos(thigh) + lower * math.cos(knee - thigh))
	end
	return total / #list
end

-- nil also when there is no root joint to lower: then the server can't pose this body either (Apply), and the camera
-- keeps the old fixed drop.
function CrouchPose.Drop(character: Model): number?
	if not joint(character, "LowerTorso", "Root") then
		return nil
	end
	return dropFor(legs(character))
end

function CrouchPose.Apply(character: Model, on: boolean, time: number?)
	local list = legs(character)
	local root = joint(character, "LowerTorso", "Root")
	local drop = dropFor(list)
	if not (root and drop) then
		return
	end
	local c = cfg()
	local thigh, knee = math.rad(c.Thigh), math.rad(c.Knee)
	local info = TweenInfo.new(time or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function set(j: Joint, posed: CFrame)
		j.target:SetAttribute("BaseC0", j.c0)
		TweenService:Create(j.target, info, { [j.prop] = if on then posed else j.c0 }):Play()
	end
	-- The root joint's frame is in the root part's space: lower the body straight down.
	set(root, CFrame.new(0, -drop, 0) * root.c0)
	for _, leg in list do
		set(leg.hip, leg.hip.c0 * CFrame.Angles(thigh, 0, 0))
		set(leg.knee, leg.knee.c0 * CFrame.Angles(-knee, 0, 0))
		if leg.ankle then
			set(leg.ankle, leg.ankle.c0 * CFrame.Angles(knee - thigh, 0, 0))
		end
	end
end

return CrouchPose
