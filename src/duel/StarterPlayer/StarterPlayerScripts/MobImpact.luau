-- Instant hit reactions on mobs, drawn on each client: the hit part's joint kicks away from
-- the bullet about its pivot and the whole body jolts back along the shot, then springs
-- settle with one overshoot. The shooter's client runs this the moment it fires; everyone
-- else gets it from the server through Remotes.MobFx "Hit".
-- Offsets ride on Motor6D.Transform on top of any animation (taken off before animations
-- run, put back after), so they never fight the server's joints or the mob's animations.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local MobImpact = {}

-- Velocity that makes a spring at rest peak at the given offset (damping ~0.4).
local PEAK_GAIN = 1.7
local SETTLED = 1e-3
local MAX_STEP = 1 / 60

local active = {}
local motorCache = setmetatable({}, { __mode = "k" })

local function mobConfig(model)
	return GameConfig.Mobs[model:GetAttribute("MobType") or ""]
end

-- The Motor6D that moves a part. Bits welded onto a part (eyes, armour) use their host's.
local function motorFor(model, part, depth)
	local cached = motorCache[part]
	if cached and cached.Parent and cached.Part1 == part then
		return cached
	end
	for _, j in model:GetDescendants() do
		if j:IsA("Motor6D") and j.Part1 == part then
			motorCache[part] = j
			return j
		end
	end
	if (depth or 0) < 2 then
		for _, w in model:GetDescendants() do
			if (w:IsA("WeldConstraint") or w:IsA("Weld")) and (w.Part0 == part or w.Part1 == part) then
				local host = if w.Part0 == part then w.Part1 else w.Part0
				local m = host and motorFor(model, host, (depth or 0) + 1)
				if m then
					return m
				end
			end
		end
	end
	return nil
end

-- The joint that carries the whole body (RootJoint on R6, Root on R15).
local function rootMotor(model)
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	for _, j in model:GetDescendants() do
		if j:IsA("Motor6D") and j.Part0 == root then
			return j
		end
	end
	return nil
end

-- Adds a rotation (axis * radians) and a shove (studs), both world space, to a joint.
local function kick(joint, cfg, rotWorld, shoveWorld)
	if not joint.Part0 then
		return
	end
	local frame = joint.Part0.CFrame * joint.C0
	local rot = frame:VectorToObjectSpace(rotWorld)
	local shove = frame:VectorToObjectSpace(shoveWorld)
	local s = active[joint]
	if not s then
		s = {
			Base = joint.Transform,
			Rot = Vector3.zero,
			RotVel = Vector3.zero,
			Pos = Vector3.zero,
			PosVel = Vector3.zero,
		}
		active[joint] = s
	end
	s.W, s.Z = cfg.Frequency, cfg.Damping
	local now, later = cfg.Snap, (1 - cfg.Snap) * cfg.Frequency * PEAK_GAIN
	s.Rot += rot * now
	s.RotVel += rot * later
	s.Pos += shove * now
	s.PosVel += shove * later
	-- Show the snap this frame, not next.
	joint.Transform = s.Base * CFrame.new(s.Pos) * (if s.Rot.Magnitude > 1e-5 then CFrame.fromAxisAngle(s.Rot.Unit, s.Rot.Magnitude) else CFrame.identity)
end

local function step(s, dt)
	local w, z = s.W, s.Z
	s.RotVel += (-s.Rot * w * w - s.RotVel * 2 * z * w) * dt
	s.Rot += s.RotVel * dt
	s.PosVel += (-s.Pos * w * w - s.PosVel * 2 * z * w) * dt
	s.Pos += s.PosVel * dt
end

-- Take the offsets off before animations write their pose for this frame...
RunService.PreAnimation:Connect(function()
	for joint, s in active do
		if joint.Parent then
			joint.Transform = s.Base
		end
	end
end)

-- ...then step the springs and lay the offsets back on top.
RunService.PreSimulation:Connect(function(dt)
	for joint, s in active do
		if not joint.Parent or not joint.Part0 or not joint.Part1 then
			active[joint] = nil
			continue
		end
		s.Base = joint.Transform
		local left = dt
		while left > 0 do
			local h = math.min(left, MAX_STEP)
			step(s, h)
			left -= h
		end
		if s.Rot.Magnitude < SETTLED and s.RotVel.Magnitude < SETTLED * 10 and s.Pos.Magnitude < SETTLED and s.PosVel.Magnitude < SETTLED * 10 then
			active[joint] = nil
			continue
		end
		local rot = if s.Rot.Magnitude > 1e-5 then CFrame.fromAxisAngle(s.Rot.Unit, s.Rot.Magnitude) else CFrame.identity
		joint.Transform = s.Base * CFrame.new(s.Pos) * rot
	end
end)

-- A bullet hit: part was struck at hitPos travelling along dir. feel is the gun's Feel;
-- scale multiplies everything (a tear hits harder).
function MobImpact.Hit(model, part, hitPos, dir, feel, scale)
	local mob = mobConfig(model)
	local cfg = mob and mob.Reaction
	if not cfg or model:GetAttribute("Dead") then
		return
	end
	scale = scale or 1
	local root = rootMotor(model)
	local joint = motorFor(model, part)

	-- The struck part twists about its joint: torque = lever x bullet direction.
	if joint and joint ~= root and joint.Part0 then
		local pivot = (joint.Part0.CFrame * joint.C0).Position
		local axis = (hitPos - pivot):Cross(dir)
		if axis.Magnitude > 1e-3 then
			local group = part:GetAttribute("Limb") or "Default"
			local angle = (cfg.PartKick[group] or cfg.PartKick.Default) * (feel.HitSnap or 1) * scale
			kick(joint, cfg, axis.Unit * angle, Vector3.zero)
		end
	end

	-- The body pitches back along the shot, turns with off-centre hits and is shoved.
	if root and root.Part0 then
		local flatDir = Vector3.new(dir.X, 0, dir.Z)
		if flatDir.Magnitude > 1e-3 then
			flatDir = flatDir.Unit
			local jolt = (feel.BodyJolt or 0.15) * scale * (if joint == root then cfg.TorsoJolt else 1)
			local twist = (hitPos - root.Part0.Position):Cross(flatDir).Y
			local rot = Vector3.yAxis:Cross(flatDir) * jolt + Vector3.yAxis * math.clamp(twist, -1, 1) * jolt * 0.8
			kick(root, cfg, rot, flatDir * (feel.BodyShove or 0.3) * scale)
		end
	end
end

return MobImpact
