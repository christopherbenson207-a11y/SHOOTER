--!strict
-- Shared.CrouchPose: the stance other players see (crouched, sliding or lying prone), so a player's hitbox matches
-- their camera (5 Nov 2026 duel pass; prone 7 Nov 2026; numbers GameConfig.Evade.Pose). No stance animations exist,
-- so the poses are made from the R15 joints, the way PlayerHealth poses a downed body.
--   Crouch: thighs swing forward Thigh degrees, knees bend Knee degrees, the feet turn back level, and the hips drop by
--   exactly what the bent legs lose in height so the feet stay on the floor.
--   Prone: the body tips forward Body degrees about the hips and lies on the floor, the chest raised Chest degrees on
--   the elbows, the head tipped back Head degrees to look ahead, the legs straight and a little apart with the toes
--   pointed. The body slides back so the head sits HeadForward studs in front of the root part, where the camera is;
--   the drop is measured from this avatar's own parts so the lowest of them clears the floor by Clearance. A chest-held
--   gun (GunJoint on the UpperTorso) turns back level and points ahead, Gun studs off its standing hold.
-- The server poses (EvadeServer, from the character's Crouching and Prone attributes) so the change replicates to
-- everyone and the server's own copy of the body (HitHistory, GunServer) moves too. The owner's client asks Drop() or
-- ProneDrop() for how far its camera should sink: the same distance as the head.
-- Joints are Motor6Ds or, on avatars with the R15 joint upgrade, AnimationConstraints (as WorldGunArms reads them).
-- The animator owns each joint's Transform, so the pose goes in the other end: a Motor6D's C0, or the constraint's
-- Attachment0 frame (the same role). Animations still play on top; Crawl() (every client, each frame) takes the walk
-- cycle off a prone body's legs and root and turns animated arms to point ahead.
--   CrouchPose.Enabled() -> boolean
--   CrouchPose.Drop(character) -> studs the head sinks when crouched (nil when the rig has no R15 legs)
--   CrouchPose.ProneDrop(character) -> studs the head sinks lying prone (nil when the rig can't lie down)
--   CrouchPose.Apply(character, stance, time?, keepRoot?) -> poses the body: "Stand", "Crouch", "Prone" (or true /
--     false for crouch / stand). keepRoot leaves the root joint alone (PlayerHealth owns it while downed). Server.
--   CrouchPose.GunChanged(character) -> GunServer set a new hold on GunJoint: forget the old rest and re-pose. Server.
--   CrouchPose.Crawl(character, armsFree) -> the per-frame touch-up on a prone body. Client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local CrouchPose = {}

export type Stance = "Stand" | "Crouch" | "Prone"

-- One joint: what to pose (the Motor6D, or the constraint's Attachment0), which property, and its two frames.
type Joint = { target: Instance, prop: string, c0: CFrame, c1: CFrame }
type Leg = { side: string, hip: Joint, knee: Joint, ankle: Joint? }

local function cfg(): any
	return GameConfig.Evade.Pose
end

local function proneCfg(): any
	local c = cfg()
	return c and c.Prone
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

local function readJoint(inst: Instance?): Joint?
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

local function joint(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	return readJoint(part and part:FindFirstChild(jointName))
end

local function legs(character: Model): { Leg }
	local list: { Leg } = {}
	for _, side in { "Left", "Right" } do
		local hip = joint(character, side .. "UpperLeg", side .. "Hip")
		local knee = joint(character, side .. "LowerLeg", side .. "Knee")
		if hip and knee then
			table.insert(list, { side = side, hip = hip, knee = knee, ankle = joint(character, side .. "Foot", side .. "Ankle") })
		end
	end
	return list
end

-- The chest-held gun's joint (GunServer): a pack gun hangs from the hand instead (Part0 is not the torso), and
-- follows the arm.
local function gunJoint(character: Model): Joint?
	local holder = character:FindFirstChild("WorldGun")
	local root = holder and holder:FindFirstChild("GunRoot")
	local inst = root and root:FindFirstChild("GunJoint")
	if inst and inst:IsA("Motor6D") and inst.Part0 == character:FindFirstChild("UpperTorso") then
		return readJoint(inst)
	end
	return nil
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

-- Prone --------------------------------------------------------------------------------------------------------------

type Prone = {
	root: Joint,
	waist: Joint,
	neck: Joint,
	legs: { Leg },
	rootPosed: CFrame,
	waistPosed: CFrame,
	neckPosed: CFrame,
	hips: { [Leg]: CFrame },
	ankles: { [Leg]: CFrame },
	headRest: CFrame, -- the head's centre standing, in root part space
	headPosed: CFrame, -- and lying down
	lift: number, -- radians the chest is pitched down from upright (what turns the gun and arms back level)
}

-- The lowest point of a part's box at cf, in that space's Y.
local function bottom(cf: CFrame, part: Instance?): number
	if not (part and part:IsA("BasePart")) then
		return math.huge
	end
	local s = part.Size / 2
	return cf.Y
		- (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z)
end

-- Everything the prone pose needs, measured from this avatar's joints and parts (all frames in root part space).
local function prone(character: Model): Prone?
	local c = proneCfg()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = joint(character, "LowerTorso", "Root")
	local waist = joint(character, "UpperTorso", "Waist")
	local neck = joint(character, "Head", "Neck")
	if not (c and hrp and hrp:IsA("BasePart") and humanoid and root and waist and neck) then
		return nil
	end
	local body, chest, head = math.rad(c.Body), math.rad(c.Chest), math.rad(c.Head)
	local spread, toes = math.rad(c.Spread), math.rad(c.Toes)

	local headRest = root.c0 * root.c1:Inverse() * waist.c0 * waist.c1:Inverse() * neck.c0 * neck.c1:Inverse()

	local rootTurned = root.c0 * CFrame.Angles(-body, 0, 0)
	local waistPosed = waist.c0 * CFrame.Angles(chest, 0, 0)
	local neckPosed = neck.c0 * CFrame.Angles(head, 0, 0)
	local lower = rootTurned * root.c1:Inverse()
	local upper = lower * waistPosed * waist.c1:Inverse()
	local headCF = upper * neckPosed * neck.c1:Inverse()

	local lowest = math.min(
		bottom(lower, character:FindFirstChild("LowerTorso")),
		bottom(upper, character:FindFirstChild("UpperTorso")),
		bottom(headCF, character:FindFirstChild("Head"))
	)
	local list = legs(character)
	local hips: { [Leg]: CFrame } = {}
	local ankles: { [Leg]: CFrame } = {}
	for _, leg in list do
		local hipPosed = leg.hip.c0 * CFrame.Angles(0, 0, if leg.side == "Right" then spread else -spread)
		hips[leg] = hipPosed
		local thighCF = lower * hipPosed * leg.hip.c1:Inverse()
		local shinCF = thighCF * leg.knee.c0 * leg.knee.c1:Inverse()
		lowest = math.min(
			lowest,
			bottom(thighCF, character:FindFirstChild(leg.side .. "UpperLeg")),
			bottom(shinCF, character:FindFirstChild(leg.side .. "LowerLeg"))
		)
		if leg.ankle then
			ankles[leg] = leg.ankle.c0 * CFrame.Angles(toes, 0, 0)
		end
	end
	if lowest == math.huge then
		return nil
	end
	-- The floor under the root part (HipHeight is from its bottom to the ground).
	local floor = -(hrp.Size.Y / 2 + humanoid.HipHeight)
	local down = lowest - floor - c.Clearance
	-- Forward is -Z: slide the body back until the head is HeadForward in front of the root part.
	local back = -c.HeadForward - headCF.Z
	local shift = CFrame.new(0, -down, back)
	return {
		root = root,
		waist = waist,
		neck = neck,
		legs = list,
		rootPosed = shift * rootTurned,
		waistPosed = waistPosed,
		neckPosed = neckPosed,
		hips = hips,
		ankles = ankles,
		headRest = headRest,
		headPosed = shift * headCF,
		lift = body - chest,
	}
end

function CrouchPose.ProneDrop(character: Model): number?
	local p = prone(character)
	return p and p.headRest.Y - p.headPosed.Y
end

-- The gun held level and ahead again: turned back up by the chest's tilt about the shoulders, then moved by Gun.
local function gunPosed(character: Model, gun: Joint, lift: number): CFrame
	local c = proneCfg()
	local pivotY = 0.5
	local shoulder = joint(character, "RightUpperArm", "RightShoulder")
	if shoulder then
		pivotY = shoulder.c0.Y
	end
	local pivot = Vector3.new(0, pivotY, 0)
	local offset = c.Gun or Vector3.zero
	return CFrame.new(pivot) * CFrame.Angles(lift, 0, 0) * CFrame.new(offset) * CFrame.new(-pivot) * gun.c0
end

-- Apply ---------------------------------------------------------------------------------------------------------------

local function tweenTo(j: Joint, posed: CFrame, info: TweenInfo)
	j.target:SetAttribute("BaseC0", j.c0)
	TweenService:Create(j.target, info, { [j.prop] = posed }):Play()
end

function CrouchPose.Apply(character: Model, stance: Stance | boolean, time: number?, keepRoot: boolean?)
	local want: Stance = if stance == true then "Crouch" elseif stance == false then "Stand" else stance :: Stance
	local list = legs(character)
	local root = joint(character, "LowerTorso", "Root")
	local crouchDrop = dropFor(list)
	if not (root and crouchDrop) then
		return
	end
	local p = if want == "Prone" then prone(character) else nil
	if want == "Prone" and not p then
		want = "Crouch" -- a rig that can't lie down crouches instead
	end
	local c = cfg()
	local thigh, knee = math.rad(c.Thigh), math.rad(c.Knee)
	local info = TweenInfo.new(time or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Root and legs: crouched, prone or at rest.
	if not keepRoot then
		local target = if p then p.rootPosed elseif want == "Crouch" then CFrame.new(0, -crouchDrop, 0) * root.c0 else root.c0
		tweenTo(root, target, info)
	end
	for _, leg in list do
		local hip, kneeTo, ankle = leg.hip.c0, leg.knee.c0, if leg.ankle then leg.ankle.c0 else nil
		if p then
			hip = p.hips[leg] or hip
			ankle = p.ankles[leg] or ankle
		elseif want == "Crouch" then
			hip = leg.hip.c0 * CFrame.Angles(thigh, 0, 0)
			kneeTo = leg.knee.c0 * CFrame.Angles(-knee, 0, 0)
			if leg.ankle then
				ankle = leg.ankle.c0 * CFrame.Angles(knee - thigh, 0, 0)
			end
		end
		tweenTo(leg.hip, hip, info)
		tweenTo(leg.knee, kneeTo, info)
		if leg.ankle and ankle then
			tweenTo(leg.ankle, ankle, info)
		end
	end

	-- Chest, head and gun: only prone moves them; anything else puts them back (only once they have been posed, so a
	-- plain crouch never touches joints it doesn't use).
	local function restore(j: Joint?)
		if j and typeof(j.target:GetAttribute("BaseC0")) == "CFrame" then
			tweenTo(j, j.c0, info)
		end
	end
	local gun = gunJoint(character)
	if p then
		tweenTo(p.waist, p.waistPosed, info)
		tweenTo(p.neck, p.neckPosed, info)
		if gun then
			tweenTo(gun, gunPosed(character, gun, p.lift), info)
		end
	else
		restore(joint(character, "UpperTorso", "Waist"))
		restore(joint(character, "Head", "Neck"))
		restore(gun)
	end
end

-- GunServer just put a new hold on GunJoint (a gun switch): that is the new rest. Lying prone, turn it ahead now.
function CrouchPose.GunChanged(character: Model)
	local holder = character:FindFirstChild("WorldGun")
	local root = holder and holder:FindFirstChild("GunRoot")
	local inst = root and root:FindFirstChild("GunJoint")
	if not inst then
		return
	end
	inst:SetAttribute("BaseC0", nil)
	if character:GetAttribute("Prone") ~= true or not CrouchPose.Enabled() then
		return
	end
	local gun = gunJoint(character)
	local p = prone(character)
	if gun and p and gun.target:IsA("Motor6D") then
		gun.target:SetAttribute("BaseC0", gun.c0)
		gun.target.C0 = gunPosed(character, gun, p.lift)
	end
end

-- Crawl ---------------------------------------------------------------------------------------------------------------
-- Every client, every frame (after the animator, before physics) for each prone body: the walk and idle cycles
-- would swing straight legs up and down through the floor, so the root and legs lose them and get a small crawl
-- instead (the legs sweep apart in turn and the knee of the drawn-up leg bends) while the body moves. Arms the
-- animator poses (a pack gun's clips, or no gun) are turned up by the chest's tilt so the clip's hold points ahead;
-- arms WorldGunArms bends onto a chest-held gun are left to it (armsFree false).

local CRAWL_RATE = 1.6 -- leg cycles a second at ProneSpeed
local turned = setmetatable({}, { __mode = "k" }) :: { [Instance]: { written: CFrame, base: CFrame } }

local function same(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-4
		and a.LookVector:Dot(b.LookVector) > 0.999999
		and a.UpVector:Dot(b.UpVector) > 0.999999
end

local function jointInst(character: Model, partName: string, jointName: string): Instance?
	local part = character:FindFirstChild(partName)
	local inst = part and part:FindFirstChild(jointName)
	if inst and (inst:IsA("Motor6D") or inst:IsA("AnimationConstraint")) then
		return inst
	end
	return nil
end

local function setTransform(inst: Instance?, cf: CFrame)
	if inst then
		(inst :: any).Transform = cf
	end
end

function CrouchPose.Crawl(character: Model, armsFree: boolean)
	local c = proneCfg()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (c and hrp and hrp:IsA("BasePart")) then
		return
	end
	local v = hrp.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local moving = math.clamp(speed / math.max(GameConfig.Evade.ProneSpeed or 4, 1), 0, 1)
	local phase = os.clock() * CRAWL_RATE * math.pi * 2
	local sweep = math.rad(c.CrawlSweep or 14) * moving
	local bend = math.rad(c.CrawlKnee or 40) * moving
	setTransform(jointInst(character, "LowerTorso", "Root"), CFrame.identity)
	for i, side in { "Left", "Right" } do
		local s = math.sin(phase + (i - 1) * math.pi)
		local out = if side == "Right" then 1 else -1
		setTransform(jointInst(character, side .. "UpperLeg", side .. "Hip"), CFrame.Angles(0, 0, out * sweep * math.max(s, 0)))
		setTransform(jointInst(character, side .. "LowerLeg", side .. "Knee"), CFrame.Angles(-bend * math.max(s, 0), 0, 0))
		setTransform(jointInst(character, side .. "Foot", side .. "Ankle"), CFrame.identity)
	end
	if not armsFree then
		return
	end
	local lift = math.rad(c.Body - c.Chest)
	for _, side in { "Left", "Right" } do
		local inst = jointInst(character, side .. "UpperArm", side .. "Shoulder")
		if inst then
			local current = (inst :: any).Transform :: CFrame
			local last = turned[inst]
			-- The animator wrote this frame: its value is the base. Otherwise the base is what was under the last turn.
			local base = if last and same(current, last.written) then last.base else current
			local t = CFrame.Angles(lift, 0, 0) * base
			;(inst :: any).Transform = t
			turned[inst] = { written = t, base = base }
		end
	end
end

return CrouchPose
