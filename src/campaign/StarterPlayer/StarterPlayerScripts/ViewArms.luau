-- First-person arms made from the local player's own avatar, built the way most Roblox
-- shooters do it (after EgoMoose's FPS viewmodel tutorial): the avatar's arm is copied in
-- its rest pose, kept straight, slimmed a little, and aimed so the hand closes on the gun
-- exactly where Roblox puts a held tool (the hand's GripAttachment).
-- A Humanoid in the viewmodel dresses the copies in the avatar's shirt and skin colour.
-- Guns mark the hands with RightGrip / LeftGrip attachments on the viewmodel Root.
-- Layered (3D) clothing is not copied; an avatar wearing only a layered top shows bare arms.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local CFG = GameConfig.ViewArms

local R15_NAMES = {
	Right = { "RightUpperArm", "RightLowerArm", "RightHand" },
	Left = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
}
local R6_NAMES = { Right = "Right Arm", Left = "Left Arm" }
local SKIN_FALLBACK = Color3.fromRGB(204, 142, 105)

local ViewArms = {}
ViewArms.__index = ViewArms

local function cloneArchivable(source)
	local was = source.Archivable
	source.Archivable = true
	local copy = source:Clone()
	source.Archivable = was
	return copy
end

-- Copies a body part (or makes a plain skin block when the rig has none) as a
-- render-only viewmodel part. Joints, attachments and cages stay behind.
local function copyPart(source, name, parent)
	local part
	if source then
		part = cloneArchivable(source)
		for _, child in part:GetChildren() do
			if not child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
	else
		part = Instance.new("Part")
		part.Material = Enum.Material.SmoothPlastic
		part.Color = SKIN_FALLBACK
	end
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Transparency = 0
	part.LocalTransparencyModifier = 0
	part.Parent = parent
	return part
end

-- Bandages wrapped on the real arm (ServerStorage.Modules.Bandages) go on the copy too, at
-- the same spot along it and scaled with it.
local function copyBandages(source, part)
	if not source then
		return
	end
	for _, band in source:GetChildren() do
		if band:IsA("BasePart") and band.Name == "Bandage" then
			local copy = cloneArchivable(band)
			copy:ClearAllChildren()
			local grow = math.max(part.Size.X, part.Size.Z) / math.max(source.Size.X, source.Size.Z)
			local height = band.Size.X * part.Size.Y / source.Size.Y
			local d = band.Size.Y * grow
			copy.Size = Vector3.new(height, d, d)
			copy.CFrame = part.CFrame * CFrame.new(0, (band:GetAttribute("Along") or 0) * part.Size.Y, 0)
				* CFrame.Angles(0, 0, math.rad(90))
			copy.Anchored = false
			copy.Massless = true
			copy.CastShadow = false
			copy.LocalTransparencyModifier = 0
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = copy
			weld.Part1 = part
			weld.Parent = copy
			copy.Parent = part
		end
	end
end

local function attachmentPosition(part, name, fallback)
	local a = part and part:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else fallback
end

-- One straight arm in its rest pose: the parts and where each sits relative to the hand,
-- plus the grip point on the hand. Lengths keep the avatar's own proportions.
local function buildArm(character, side, parent)
	local s = CFG.Scale
	local w = CFG.Scale * CFG.WidthScale
	local function scaled(size)
		return Vector3.new(size.X * w, size.Y * s, size.Z * w)
	end
	local arm = { Pieces = {} }
	local names = R15_NAMES[side]
	local upperSrc = character:FindFirstChild(names[1])
	local lowerSrc = character:FindFirstChild(names[2])
	local handSrc = character:FindFirstChild(names[3])
	if upperSrc and lowerSrc and handSrc then
		-- At rest each part's joint attachment meets the matching one on its neighbour.
		local wristOnHand = attachmentPosition(handSrc, side .. "WristRigAttachment", Vector3.new(0, handSrc.Size.Y / 2, 0))
		local wristOnLower = attachmentPosition(lowerSrc, side .. "WristRigAttachment", Vector3.new(0, -lowerSrc.Size.Y / 2, 0))
		local elbowOnLower = attachmentPosition(lowerSrc, side .. "ElbowRigAttachment", Vector3.new(0, lowerSrc.Size.Y / 2, 0))
		local elbowOnUpper = attachmentPosition(upperSrc, side .. "ElbowRigAttachment", Vector3.new(0, -upperSrc.Size.Y / 2, 0))
		local lowerOffset = wristOnHand - wristOnLower
		local upperOffset = lowerOffset + elbowOnLower - elbowOnUpper
		arm.Grip = attachmentPosition(handSrc, side .. "GripAttachment", Vector3.new(0, -handSrc.Size.Y / 2, 0)) * s
		for _, piece in { { handSrc, names[3], Vector3.zero }, { lowerSrc, names[2], lowerOffset }, { upperSrc, names[1], upperOffset } } do
			local part = copyPart(piece[1], piece[2], parent)
			part.Size = scaled(piece[1].Size)
			copyBandages(piece[1], part)
			table.insert(arm.Pieces, { Part = part, Offset = CFrame.new(piece[3] * s) })
		end
	else
		-- R6 or a custom rig: one block with the hand at its lower end.
		local src = character:FindFirstChild(R6_NAMES[side])
		local size = if src then src.Size else Vector3.new(1, 2, 1)
		local part = copyPart(src, R6_NAMES[side], parent)
		part.Size = scaled(size)
		copyBandages(src, part)
		arm.Grip = attachmentPosition(src, side .. "GripAttachment", Vector3.new(0, -size.Y / 2 + 0.25, 0)) * s
		table.insert(arm.Pieces, { Part = part, Offset = CFrame.identity })
	end
	return arm
end

-- Points the straight arm from the grip toward the shoulder, rolled to the grip's right
-- vector, with the hand's grip point on the gun's marker.
local function poseArm(arm, gripCF, shoulder, parts, cframes)
	local up = (shoulder - gripCF.Position).Unit
	local x = gripCF.RightVector - up * gripCF.RightVector:Dot(up)
	if x.Magnitude < 1e-4 then
		x = up:Cross(Vector3.zAxis)
	end
	x = x.Unit
	local rotation = CFrame.fromMatrix(Vector3.zero, x, up, x:Cross(up))
	local handCF = rotation + (gripCF.Position - rotation * arm.Grip)
	for _, piece in arm.Pieces do
		table.insert(parts, piece.Part)
		table.insert(cframes, handCF * piece.Offset)
	end
end

-- Builds both arms inside viewModel from character's current appearance.
function ViewArms.new(character: Model, viewModel: Model)
	local self = setmetatable({ Parts = {}, CFrames = {}, Made = {} }, ViewArms)

	-- A Humanoid next to the copied arms makes Roblox dress them in the avatar's shirt.
	local source = character:FindFirstChildOfClass("Humanoid")
	local dresser = Instance.new("Humanoid")
	dresser.Name = "ArmsDresser"
	dresser.RigType = if source then source.RigType else Enum.HumanoidRigType.R15
	dresser.EvaluateStateMachine = false
	dresser.RequiresNeck = false
	dresser.BreakJointsOnDeath = false
	dresser.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	dresser.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	dresser.Parent = viewModel
	table.insert(self.Made, dresser)
	for _, item in character:GetChildren() do
		if item:IsA("Shirt") or item:IsA("BodyColors") then
			local copy = cloneArchivable(item)
			copy.Parent = viewModel
			table.insert(self.Made, copy)
		end
	end

	self.Right = buildArm(character, "Right", viewModel)
	self.Left = buildArm(character, "Left", viewModel)
	for _, arm in { self.Right, self.Left } do
		for _, piece in arm.Pieces do
			table.insert(self.Made, piece.Part)
		end
	end
	return self
end

-- base: the camera frame the shoulders hang from. rightGrip / leftGrip: world CFrames of
-- the gun's hand markers. aim: 0 hip to 1 aiming down sights. leftShoulder: the gun's own
-- left shoulder point, if it has one.
function ViewArms:Update(base: CFrame, rightGrip: CFrame, leftGrip: CFrame, aim: number, leftShoulder: Vector3?)
	local inward = Vector3.new(CFG.AimShoulderIn * aim, 0, 0)
	local parts, cframes = self.Parts, self.CFrames
	table.clear(parts)
	table.clear(cframes)
	poseArm(self.Right, rightGrip, base * (CFG.RightShoulder - inward), parts, cframes)
	poseArm(self.Left, leftGrip, base * ((leftShoulder or CFG.LeftShoulder) + inward), parts, cframes)
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function ViewArms:Destroy()
	for _, instance in self.Made do
		instance:Destroy()
	end
	table.clear(self.Made)
end

return ViewArms
