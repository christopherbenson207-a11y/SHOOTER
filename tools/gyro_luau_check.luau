-- Runs the real Shared.GyroAim module outside Roblox against simulated phone readings.
-- Run: luau tools/gyro_luau_check.luau   (luau from https://github.com/luau-lang/luau/releases)
-- Vector2, Vector3 and CFrame below are small stand-ins with Roblox's semantics, just enough for
-- GyroAim. tools/gyro_sim.py is the full simulation; this checks the Luau itself runs and agrees.

local V3 = {}
local V3mt = {}
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, V3mt)
end
V3mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return v3(v.X / m, v.Y / m, v.Z / m)
	end
	return V3[k]
end
V3mt.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	return v3(a.X / b, a.Y / b, a.Z / b)
end
V3mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	return a + (b - a) * t
end
function V3.FuzzyEq(a, b, eps)
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
local Vector3 = {
	new = v3,
	zero = v3(0, 0, 0),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

local V2 = {}
local V2mt = {}
local function v2(x, y)
	return setmetatable({ X = x, Y = y }, V2mt)
end
V2mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end
	return V2[k]
end
V2mt.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2mt.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2mt.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	end
	return v2(a.X * b, a.Y * b)
end
V2mt.__div = function(a, b)
	return v2(a.X / b, a.Y / b)
end
V2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
function V2.Lerp(a, b, t)
	return a + (b - a) * t
end
local Vector2 = { new = v2, zero = v2(0, 0) }

-- CFrame: rotation only, stored as its three column vectors.
local CF = {}
local CFmt = {}
local function cf(x, y, z)
	return setmetatable({ XVector = x, YVector = y, ZVector = z }, CFmt)
end
local function apply(c, v)
	return c.XVector * v.X + c.YVector * v.Y + c.ZVector * v.Z
end
CFmt.__index = function(c, k)
	if k == "Rotation" then
		return c
	end
	return CF[k]
end
CFmt.__mul = function(a, b)
	if getmetatable(b) == V3mt then
		return apply(a, b)
	end
	return cf(apply(a, b.XVector), apply(a, b.YVector), apply(a, b.ZVector))
end
function CF.Inverse(c)
	local x, y, z = c.XVector, c.YVector, c.ZVector
	return cf(v3(x.X, y.X, z.X), v3(x.Y, y.Y, z.Y), v3(x.Z, y.Z, z.Z))
end
function CF.VectorToWorldSpace(c, v)
	return apply(c, v)
end
function CF.VectorToObjectSpace(c, v)
	return apply(CF.Inverse(c), v)
end
function CF.ToAxisAngle(c)
	local x, y, z = c.XVector, c.YVector, c.ZVector
	local cos = math.clamp((x.X + y.Y + z.Z - 1) / 2, -1, 1)
	local angle = math.acos(cos)
	local axis = v3(y.Z - z.Y, z.X - x.Z, x.Y - y.X)
	if axis.Magnitude < 1e-12 then
		return v3(1, 0, 0), 0
	end
	return axis.Unit, angle
end
local function fromAxisAngle(axis, angle)
	local u = axis.Unit
	local function rotate(v)
		local c, s = math.cos(angle), math.sin(angle)
		return v * c + u:Cross(v) * s + u * (u:Dot(v) * (1 - c))
	end
	return cf(rotate(v3(1, 0, 0)), rotate(v3(0, 1, 0)), rotate(v3(0, 0, 1)))
end
local CFrame = {
	identity = cf(v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)),
	fromMatrix = function(_pos, x, y, z)
		return cf(x, y, z)
	end,
	fromAxisAngle = fromAxisAngle,
	Angles = function(rx, ry, rz)
		return fromAxisAngle(v3(1, 0, 0), rx) * fromAxisAngle(v3(0, 1, 0), ry) * fromAxisAngle(v3(0, 0, 1), rz)
	end,
}

-- GyroAim reads these as globals.
local env = getfenv(1)
env.Vector3 = Vector3
env.Vector2 = Vector2
env.CFrame = CFrame

local GyroAim = require("../src/campaign/ReplicatedStorage/Shared/GyroAim")

-- A phone in landscape (top edge to the left), screen toward a player looking along -Z, tilted
-- back. Gravity-frame axes: X left edge, Y out of the screen, Z top edge.
local BASE = CFrame.fromMatrix(nil, v3(0, -1, 0), v3(0, 0, 1), v3(-1, 0, 0))
local X, Y, Z = Vector3.xAxis, Vector3.yAxis, Vector3.zAxis

local function smooth01(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- How the phone reports: map takes gravity-frame axes to the CFrame's own; inverse = world-to-phone.
local function scenario(label, map, inverse, motion)
	local gyro = GyroAim.new()
	local tilt = math.rad(35)
	local camYaw, camPitch = 0, 0
	local wantYaw, wantPitch = 0, 0
	local t = 0
	local warm = 6
	local mapInv = map:Inverse()
	while t < warm + 3 do
		t += 1 / 60
		local yaw, pitch, roll
		if t < warm then
			local f = smooth01(warm - t)
			yaw = f * (0.5 * math.sin(t * 1.3) + 0.2 * math.sin(t * 2.9))
			pitch = f * 0.25 * math.sin(t * 1.7 + 0.4)
			roll = f * 0.08 * math.sin(t * 2.3)
		else
			yaw, pitch, roll = motion(t - warm)
		end
		local D = fromAxisAngle(Y, yaw) * fromAxisAngle(X, pitch - tilt) * fromAxisAngle(Z, roll) * BASE
		local reported = D * mapInv
		if inverse then
			reported = reported:Inverse()
		end
		local gravity = D:VectorToObjectSpace(v3(0, -9.81, 0))
		gyro:Reading(reported, gravity, true)
		local turn = gyro:Step(1 / 60)
		camYaw += turn.X
		camPitch += turn.Y
		if t >= warm then
			wantYaw, wantPitch = yaw, pitch
		else
			camYaw, camPitch = 0, 0
		end
	end
	local err = math.sqrt((camYaw - wantYaw) ^ 2 + (camPitch - wantPitch) ^ 2)
	local peak = math.max(math.abs(wantYaw), math.abs(wantPitch), math.rad(1))
	print(
		string.format(
			"%-34s want yaw %6.1f pitch %6.1f  got yaw %6.1f pitch %6.1f  (%s)",
			label,
			math.deg(wantYaw),
			math.deg(wantPitch),
			math.deg(camYaw),
			math.deg(camPitch),
			gyro:Convention()
		)
	)
	return err / peak
end

local function turnLeft(t)
	return math.rad(40) * smooth01(t), 0, 0
end
local function lookUp(t)
	return 0, math.rad(15) * smooth01(t), 0
end
local function both(t)
	return math.rad(-30) * smooth01(t), math.rad(-10) * smooth01(t), 0
end

-- Android as reported on the DevForum: X and Y swapped, Z flipped (a proper rotation).
local SWAP = CFrame.fromMatrix(nil, v3(0, 1, 0), v3(1, 0, 0), v3(0, 0, -1))
local ODD = CFrame.fromMatrix(nil, v3(0, 0, 1), v3(-1, 0, 0), v3(0, -1, 0))
local worst = 0
for _, case in
	{
		{ "documented", CFrame.identity, false },
		{ "documented, world-to-phone", CFrame.identity, true },
		{ "Android swap", SWAP, false },
		{ "Android swap, world-to-phone", SWAP, true },
		{ "odd axes", ODD, false },
	}
do
	for _, m in { { "turn left", turnLeft }, { "look up", lookUp }, { "right and down", both } } do
		worst = math.max(worst, scenario(case[1] .. ", " .. m[1], case[2], case[3], m[2]))
	end
end
print(string.format("worst error %.1f%% of the motion", worst * 100))
if worst > 0.1 then
	error("GyroAim check failed")
end
