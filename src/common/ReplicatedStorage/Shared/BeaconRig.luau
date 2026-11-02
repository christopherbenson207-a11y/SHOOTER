-- Walks the Beacon's skeleton in place: legs stride, arms swing against them, the body sways.
-- The model itself is moved by whoever owns it (BeaconServer in the match, MenuClient in the
-- menu); this only poses the bones, so it runs on the client. Bones hinge on their local X.
-- Optional modes: "Vent" (lamps cooling: the head hangs and the chest sags), "Chase"
-- (running at someone: a faster, longer stride and a forward lean), "Smash" (both arms
-- swing down through a building in front of it), "Reach" (arms straight up at the
-- helicopter, head thrown back) and "Grab" (with grabK 0..1: it bends and reaches down with
-- its right hand, then lifts what it caught up in front of its lamps and holds it there).

local BeaconRig = {}
BeaconRig.__index = BeaconRig

local STRIDE = 3 -- seconds for a full left-right step cycle (BeaconServer steps every 1.5)

function BeaconRig.new(model)
	local self = setmetatable({ Bones = {}, Phase = 0, Walk = 0, Time = 0, Vent = 0, Chase = 0, Smash = 0, Reach = 0, Grab = 0, GrabK = 0 }, BeaconRig)
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			self.Bones[d.Name] = d
		end
	end
	-- With streaming the bones can arrive after this is made (or come back after streaming out).
	model.DescendantAdded:Connect(function(d)
		if d:IsA("Bone") then
			self.Bones[d.Name] = d
		end
	end)
	return self
end

local function pose(bone, cf)
	if bone then
		bone.Transform = cf
	end
end

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- moving: whether the model is walking this frame. mode: nil, "Vent", "Chase", "Smash",
-- "Reach" or "Grab" (grabK: how far through the grab, 0..1).
function BeaconRig:Step(dt, moving, mode, grabK)
	local b = self.Bones
	self.Time += dt
	self.Walk += ((if moving then 1 else 0) - self.Walk) * math.min(1, dt * 3)
	self.Vent += ((if mode == "Vent" then 1 else 0) - self.Vent) * math.min(1, dt * 2.5)
	self.Chase += ((if mode == "Chase" then 1 else 0) - self.Chase) * math.min(1, dt * 5)
	self.Smash += ((if mode == "Smash" then 1 else 0) - self.Smash) * math.min(1, dt * 6)
	self.Reach += ((if mode == "Reach" then 1 else 0) - self.Reach) * math.min(1, dt * 3)
	self.Grab += ((if mode == "Grab" then 1 else 0) - self.Grab) * math.min(1, dt * 8)
	if mode == "Grab" and grabK then
		self.GrabK = math.clamp(grabK, 0, 1)
	end
	local run = self.Chase
	local smash, reach = self.Smash, self.Reach
	-- The grab: down and forward (bent at the waist) by 0.3, then up in front of the lamps by
	-- 0.65, the forearm folding in.
	local grab = self.Grab
	local down = smooth(self.GrabK / 0.3)
	local lift = smooth((self.GrabK - 0.3) / 0.35)
	local grabArm = (-1.05 * down - 0.85 * lift) * grab
	local grabFore = (-0.25 * down - 0.75 * lift) * grab
	local grabLean = (0.5 * down - 0.4 * lift) * grab
	-- A smash: arms up and back, then down hard (a fast swing on the smash's own clock).
	local swing = math.sin(self.Time * 5) * smash
	self.Phase += dt * (2 * math.pi / STRIDE) * (0.25 + 0.75 * self.Walk) * (1 + 1.6 * run)
	local w = self.Walk * (1 + 0.5 * run)
	local s, c = math.sin(self.Phase), math.cos(self.Phase)
	local v = self.Vent
	pose(b.ThighL, CFrame.Angles(s * 0.34 * w, 0, 0))
	pose(b.ThighR, CFrame.Angles(-s * 0.34 * w, 0, 0))
	pose(b.ShinL, CFrame.Angles(-math.max(0, c) * 0.5 * w, 0, 0))
	pose(b.ShinR, CFrame.Angles(-math.max(0, -c) * 0.5 * w, 0, 0))
	local tremble = 0.05 * math.sin(self.Time * 9) * reach
	pose(b.UpperArmL, CFrame.Angles(-s * 0.2 * w - 0.25 * run - (1.3 + swing * 0.8) * smash - 2.6 * reach + tremble, 0, 0.03 * math.sin(self.Time * 0.7) + 0.2 * reach))
	pose(b.UpperArmR, CFrame.Angles(s * 0.2 * w - 0.25 * run - (1.3 - swing * 0.8) * smash - 2.6 * reach - tremble + grabArm, 0, -0.03 * math.sin(self.Time * 0.7) - 0.2 * reach - 0.25 * lift * grab))
	pose(b.LowerArmL, CFrame.Angles(-0.12 - math.max(0, -s) * 0.15 * w - 0.4 * smash, 0, 0))
	pose(b.LowerArmR, CFrame.Angles(-0.12 - math.max(0, s) * 0.15 * w - 0.4 * smash + grabFore, 0, 0))
	pose(b.Spine, CFrame.Angles(0.02 * math.sin(self.Time * 0.5) + 0.16 * run + 0.3 * smash - 0.22 * reach + grabLean, 0, s * 0.035 * w))
	-- Breathing, so it's never a statue when it stops.
	pose(b.Chest, CFrame.Angles(0.12 * v + 0.03 * math.sin(self.Time * 1.1), 0, 0))
	pose(b.Neck, CFrame.Angles(0.3 * v + 0.04 * v * math.sin(self.Time * 1.3) - 0.5 * reach + 0.25 * down * grab, 0, 0))
	pose(b.Neck2, CFrame.Angles(0.22 * v, 0, 0))
	pose(b.Root, CFrame.new(0, -math.abs(c) * 0.5 * w - 0.8 * v, 0))
end

return BeaconRig
