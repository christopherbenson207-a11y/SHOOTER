--!strict
-- Poses the dog's skeleton: gaits (walk, trot, run) by speed, and still poses (sit, lie, flat, sniff, bark,
-- whimper, bite, howl) blended in and out. Same numbers as horror-shooter/blender/dog_pose.py, which renders them.
-- The model is moved by whoever owns it (DogServer); this only poses the bones, so it runs on the client.
-- A pose is {bone = {pitch, yaw, roll}} in degrees in the dog's own axes, plus Move = {right, up, forward} studs
-- for the Root bone. Each bone's rotation is turned into its own frame by its rest orientation
-- (local = rest^-1 * Q * rest), so a bone and its parent rotating about the same axis simply add up.

local DogRig = {}
DogRig.__index = DogRig

export type Spec = { [string]: { number } }

local POSES: { [string]: Spec } = {
	Stand = {},
	Sit = {
		Move = { 0, -0.5, 0.18 }, Root = { 28, 0, 0 },
		Neck = { -14, 0, 0 }, Head = { -12, 0, 0 },
		UpperArmL = { -28, 0, 0 }, UpperArmR = { -28, 0, 0 },
		ThighL = { 36, 0, 4 }, ThighR = { 36, 0, -4 }, ShinL = { -67.5, 0, 0 }, ShinR = { -67.5, 0, 0 },
		HockL = { 75.5, 0, 0 }, HockR = { 75.5, 0, 0 }, HindPawL = { -59, 0, 0 }, HindPawR = { -59, 0, 0 },
		Tail1 = { 12, 14, 0 }, Tail2 = { -40, 20, 0 }, Tail3 = { -25, 10, 0 },
	},
	Lie = {
		Move = { 0, -1.1, 0 },
		Neck = { 8, 0, 0 }, Head = { -8, 0, 0 },
		UpperArmL = { -28.7, 0, 0 }, UpperArmR = { -28.7, 0, 0 }, ForearmL = { 110.5, 0, 0 }, ForearmR = { 110.5, 0, 0 },
		FrontPawL = { -41.3, 0, 0 }, FrontPawR = { -41.3, 0, 0 },
		ThighL = { 36, 0, 8 }, ThighR = { 36, 0, -8 }, ShinL = { -64.5, 0, 0 }, ShinR = { -64.5, 0, 0 },
		HockL = { 100.5, 0, 0 }, HockR = { 100.5, 0, 0 }, HindPawL = { -59, 0, 0 }, HindPawR = { -59, 0, 0 },
		Tail1 = { -30, 22, 0 }, Tail2 = { 12, 18, 0 }, Tail3 = { 14, 12, 0 },
	},
	Flat = {
		Move = { 0, -1.12, 0 },
		Neck = { -24, 0, 0 }, Neck2 = { -14, 0, 0 }, Head = { 8, 0, 0 },
		UpperArmL = { -28.7, 0, 0 }, UpperArmR = { -28.7, 0, 0 }, ForearmL = { 110.5, 0, 0 }, ForearmR = { 110.5, 0, 0 },
		FrontPawL = { -41.3, 0, 0 }, FrontPawR = { -41.3, 0, 0 },
		ThighL = { 36, 0, 8 }, ThighR = { 36, 0, -8 }, ShinL = { -64.5, 0, 0 }, ShinR = { -64.5, 0, 0 },
		HockL = { 100.5, 0, 0 }, HockR = { 100.5, 0, 0 }, HindPawL = { -59, 0, 0 }, HindPawR = { -59, 0, 0 },
		EarL = { 55, 0, 10 }, EarR = { 55, 0, -10 }, Tail1 = { -22, 0, 0 }, Tail2 = { -28, 0, 0 },
	},
	Sniff = {
		Move = { 0, -0.08, 0 }, Chest = { -6, 0, 0 },
		Neck = { -38, 0, 0 }, Neck2 = { -18, 0, 0 }, Head = { -6, 0, 0 },
		UpperArmL = { 6, 0, 0 }, UpperArmR = { 6, 0, 0 },
		Tail1 = { -28, 0, 0 }, Tail2 = { -12, 0, 0 },
	},
	Bark = {
		Neck = { 10, 0, 0 }, Head = { 8, 0, 0 }, Jaw = { -24, 0, 0 },
		EarL = { -10, 0, 0 }, EarR = { -10, 0, 0 }, Tail1 = { -40, 0, 0 }, Tail2 = { -15, 0, 0 },
	},
	Whimper = {
		Move = { 0, -0.22, 0.1 }, Root = { -4, 0, 0 },
		Neck = { -20, 0, 0 }, Head = { -12, 0, 0 },
		ThighL = { 18, 0, 0 }, ThighR = { 18, 0, 0 }, ShinL = { -22, 0, 0 }, ShinR = { -22, 0, 0 },
		EarL = { 60, 0, 12 }, EarR = { 60, 0, -12 }, Tail1 = { 48, 0, 0 }, Tail2 = { 25, 0, 0 },
	},
	Bite = {
		Move = { 0, 0.3, 0.35 }, Root = { -16, 0, 0 }, Chest = { -4, 0, 0 },
		Neck = { 22, 0, 0 }, Head = { 6, 0, 0 }, Jaw = { -34, 0, 0 },
		UpperArmL = { 40, 0, 0 }, UpperArmR = { 34, 0, 0 }, ForearmL = { 30, 0, 0 }, ForearmR = { 36, 0, 0 },
		FrontPawL = { -50, 0, 0 }, FrontPawR = { -46, 0, 0 },
		ThighL = { -14, 0, 0 }, ThighR = { -14, 0, 0 },
		EarL = { 30, 0, 0 }, EarR = { 30, 0, 0 }, Tail1 = { -35, 0, 0 },
	},
	Howl = { -- its player is dead: sitting, muzzle to the sky, mouth round, ears back
		Move = { 0, -0.5, 0.18 }, Root = { 28, 0, 0 },
		Neck = { 12, 0, 0 }, Neck2 = { 10, 0, 0 }, Head = { 12, 0, 0 }, Jaw = { -16, 0, 0 },
		EarL = { 35, 0, 8 }, EarR = { 35, 0, -8 },
		UpperArmL = { -28, 0, 0 }, UpperArmR = { -28, 0, 0 },
		ThighL = { 36, 0, 4 }, ThighR = { 36, 0, -4 }, ShinL = { -67.5, 0, 0 }, ShinR = { -67.5, 0, 0 },
		HockL = { 75.5, 0, 0 }, HockR = { 75.5, 0, 0 }, HindPawL = { -59, 0, 0 }, HindPawR = { -59, 0, 0 },
		Tail1 = { 12, 14, 0 }, Tail2 = { -40, 20, 0 }, Tail3 = { -25, 10, 0 },
	},
}
DogRig.Poses = POSES

local LEG = 1.55 -- hip/shoulder to ground, studs
type Gait = { Duty: number, A: number, Lift: number, Bob: number, Flex: number, Offsets: { [string]: number } }
local GAITS: { [string]: Gait } = {
	Walk = { Duty = 0.62, A = 20, Lift = 1.0, Bob = 0.035, Flex = 0, Offsets = { BackL = 0.0, FrontL = 0.25, BackR = 0.5, FrontR = 0.75 } },
	Trot = { Duty = 0.48, A = 26, Lift = 1.25, Bob = 0.07, Flex = 0, Offsets = { FrontL = 0.0, BackR = 0.0, FrontR = 0.5, BackL = 0.5 } },
	Run = { Duty = 0.36, A = 40, Lift = 1.5, Bob = 0.12, Flex = 13, Offsets = { BackL = 0.0, BackR = 0.08, FrontL = 0.52, FrontR = 0.6 } },
}
-- speeds (studs/s) where each gait is fully in; between them the two neighbours blend
local GAIT_SPEEDS = { { "Walk", 4 }, { "Trot", 9 }, { "Run", 16 } }

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- ground covered per cycle: the stance sweep over the duty share
local function stride(g: Gait): number
	return 2 * LEG * math.sin(math.rad(g.A)) / g.Duty
end

local function leg(g: Gait, p: number, front: boolean, out: Spec, sd: string)
	local a, duty = g.A, g.Duty
	local sw, up
	if p < duty then
		sw, up = a * (1 - 2 * p / duty), 0
	else
		local t = (p - duty) / (1 - duty)
		sw, up = -a + 2 * a * smooth(t), math.sin(math.pi * t) * g.Lift
	end
	if front then
		out["UpperArm" .. sd] = { sw, 0, 0 }
		out["Forearm" .. sd] = { 22 * up, 0, 0 }
		out["FrontPaw" .. sd] = { -78 * up, 0, 0 }
	else
		out["Thigh" .. sd] = { sw, 0, 0 }
		out["Shin" .. sd] = { -42 * up, 0, 0 }
		out["Hock" .. sd] = { 34 * up, 0, 0 }
		out["HindPaw" .. sd] = { -24 * up, 0, 0 }
	end
end

local function gait(name: string, phase: number): Spec
	local g = GAITS[name]
	local spec: Spec = {}
	for key, off in g.Offsets do
		local p = (phase - off) % 1
		leg(g, p, string.sub(key, 1, 5) == "Front", spec, string.sub(key, -1))
	end
	local two = math.sin(phase * 4 * math.pi)
	spec.Move = { 0, g.Bob * two, 0 }
	local flex = g.Flex * math.sin(phase * 2 * math.pi)
	spec.Hips = { flex, 0, 0 }
	spec.Chest = { -flex * 0.6, 0, 0 }
	spec.Neck = { 3 * two - flex * 0.4, 0, 0 }
	spec.Tail1 = { -18 - flex * 0.5, 8 * math.sin(phase * 2 * math.pi), 0 }
	return spec
end
DogRig.Gait = gait

-- add w * b into acc
local function accumulate(acc: Spec, b: Spec, w: number)
	if w <= 0 then
		return
	end
	for bone, v in b do
		local a = acc[bone]
		if not a then
			a = { 0, 0, 0 }
			acc[bone] = a
		end
		a[1] += v[1] * w
		a[2] += v[2] * w
		a[3] += v[3] * w
	end
end

-- root: the part whose CFrame is the dog's own frame (LookVector = the way the dog faces, UpVector = up).
function DogRig.new(model: Model, root: BasePart)
	local self = setmetatable({
		Model = model,
		Root = root,
		Bones = {} :: { [string]: Bone },
		Rest = {} :: { [string]: CFrame },
		Weights = { Stand = 1 } :: { [string]: number },
		Phase = 0,
		Speed = 0,
		Time = 0,
		Pant = 0,
	}, DogRig)
	self:_collect()
	return self
end

-- rest orientations in the dog's frame, read with every Transform cleared
function DogRig:_collect()
	for _, d in self.Model:GetDescendants() do
		if d:IsA("Bone") and not self.Bones[d.Name] then
			self.Bones[d.Name] = d
		end
	end
	for _, b in self.Bones do
		b.Transform = CFrame.identity
	end
	local inv = self.Root.CFrame:Inverse()
	for name, b in self.Bones do
		self.Rest[name] = (inv * b.WorldCFrame).Rotation
	end
end

-- speed: studs/s over the ground. pose: nil (moving or standing), or a POSES name to settle into.
function DogRig:Step(dt: number, speed: number, pose: string?)
	self.Time += dt
	self.Speed += (speed - self.Speed) * math.min(1, dt * 6)
	local target = if pose and POSES[pose] then pose else "Stand"
	for name in POSES do
		local w = self.Weights[name] or 0
		local goal = if name == target then 1 else 0
		self.Weights[name] = w + (goal - w) * math.min(1, dt * (if goal > w then 5 else 7))
	end

	local spec: Spec = {}
	-- locomotion, faded out as a still pose takes over
	local still = 1 - (self.Weights.Stand or 0)
	local move = math.clamp(self.Speed / 2.5, 0, 1) * (1 - still)
	if move > 0.01 then
		local lo, hi, t = GAIT_SPEEDS[1], GAIT_SPEEDS[1], 0
		for i = 1, #GAIT_SPEEDS - 1 do
			local a, b = GAIT_SPEEDS[i], GAIT_SPEEDS[i + 1]
			if self.Speed >= a[2] then
				lo, hi, t = a, b, math.clamp((self.Speed - a[2]) / (b[2] - a[2]), 0, 1)
			end
		end
		-- the phase advances so the paws keep pace with the ground (blended stride length)
		local len = stride(GAITS[lo[1]]) * (1 - t) + stride(GAITS[hi[1]]) * t
		self.Phase = (self.Phase + dt * math.max(self.Speed, 1.2) / len) % 1
		accumulate(spec, gait(lo[1], self.Phase), move * (1 - t))
		accumulate(spec, gait(hi[1], self.Phase), move * t)
	end
	for name, w in self.Weights do
		accumulate(spec, POSES[name], w)
	end
	-- never a statue: breathing, a slow tail sway, panting after a run
	self.Pant += ((if self.Speed > 8 then 1 else 0) - self.Pant) * math.min(1, dt * 0.4)
	accumulate(spec, {
		Chest = { 1.2 * math.sin(self.Time * (2 + 4 * self.Pant)), 0, 0 },
		Jaw = { -6 * self.Pant * (0.6 + 0.4 * math.sin(self.Time * 9)), 0, 0 },
		Tail2 = { 0, 6 * math.sin(self.Time * 1.3), 0 },
	}, 1)
	self:Apply(spec)
end

local RIGHT, UP, FWD = Vector3.xAxis, Vector3.yAxis, -Vector3.zAxis

function DogRig:Apply(spec: Spec)
	for name, b in self.Bones do
		local v = spec[name]
		local rest = self.Rest[name]
		if v and rest then
			local q = CFrame.fromAxisAngle(UP, math.rad(v[2])) * CFrame.fromAxisAngle(RIGHT, math.rad(v[1]))
				* CFrame.fromAxisAngle(FWD, math.rad(v[3]))
			b.Transform = rest:Inverse() * q * rest
		else
			b.Transform = CFrame.identity
		end
	end
	local m = spec.Move
	local rb = self.Bones.Root
	if m and rb and self.Rest.Root then
		local off = RIGHT * m[1] + UP * m[2] + FWD * m[3]
		rb.Transform = CFrame.new(self.Rest.Root:Inverse() * off) * rb.Transform
	end
end

return DogRig
