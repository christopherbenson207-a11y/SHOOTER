--!strict
-- Shared.GunFeel (7 Nov 2026): the gun feel that is the same code for every gun, tuned per gun type. GunClient calls
-- it from fire() and from its per-frame update; every place's GunClient uses this one module.
--
--   GunFeel.Shot(gun, now)       this shot's recoil: pitch multiplier, yaw and roll (degrees), and the share of the
--                                pitch that stays (climb). A spray has a pattern: the first shots go straight up,
--                                then the gun wanders left and right on a smooth curve that is the same every spray
--                                with that gun, so players can learn to pull against it. A tap goes back to centre.
--   GunFeel.Climb(spring, kick)  holds the climb share of a kick on the camera spring while the trigger is held.
--   GunFeel.Recover(spring, dt, now, lookPitch)
--                                after the burst the held climb settles back, minus whatever the player already
--                                pulled down during the spray (no dropping under the target after a good pull).
--   GunFeel.ShotKick(rollDeg, aim)  the gun twists a little on each shot (viewmodel roll).
--   GunFeel.Motion(dt, humanoid, root, camCF, aim, sprint)
--                                the gun's weight in your hands: it leans into a strafe, lags when you fall, dips
--                                and the view thumps on a landing, bobs up on a jump, and settles with a small
--                                kick when you go in and out of aim. Returns the viewmodel offset (CFrame) and
--                                a camera offset (pitch, yaw, roll radians) to add to the recoil offset.
--   GunFeel.LowAmmo(feel, mag, magSize)  the last third of a mag rings a light mechanical tick over each shot.
--   GunFeel.Reset()              a new life or a new gun.
--
-- Per gun overrides go in GameConfig.Guns.X.Recoil: Climb, Roll, FirstShot, Wander, Jitter (see CLASS below).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spring = require(Shared:WaitForChild("Spring"))
local SoundKit = require(Shared:WaitForChild("SoundKit"))

local GunFeel = {}

type Tune = { Climb: number, Roll: number, FirstShot: number, Wander: number, Jitter: number }

-- By fire mode. Climb: share of each shot's pitch that stays while the trigger is held. Roll: degrees of camera roll
-- per shot. FirstShot: the first round of a burst kicks harder (it reads as the gun waking up). Wander: how far the
-- spray drifts sideways on its pattern. Jitter: random sideways on top of the pattern.
local CLASS: { [string]: Tune } = {
	Auto = { Climb = 0.45, Roll = 0.55, FirstShot = 1.25, Wander = 1.1, Jitter = 0.3 },
	Semi = { Climb = 0.2, Roll = 0.9, FirstShot = 1.1, Wander = 0.5, Jitter = 0.7 },
	Pump = { Climb = 0, Roll = 2.4, FirstShot = 1, Wander = 0.3, Jitter = 0.8 },
	Bolt = { Climb = 0, Roll = 1.8, FirstShot = 1, Wander = 0.3, Jitter = 0.8 },
}

local BURST_GAP = 0.32 -- seconds without a shot that end a burst
local HOLD_AFTER = 0.1 -- seconds after the last shot before the climb starts to settle
local RECOVER_RATE = 6.5 -- per second
local MAX_CLIMB = Vector2.new(math.rad(11), math.rad(4))

local burst = { n = 0, last = -math.huge, seed = 0, gun = nil :: any, pulled = 0 }

local function randomSigned(): number
	return math.random() * 2 - 1
end

local function tune(gun: any): Tune
	local base = CLASS[gun.FireMode] or CLASS.Semi
	local r = gun.Recoil or {}
	return {
		Climb = r.Climb or base.Climb,
		Roll = r.Roll or base.Roll,
		FirstShot = r.FirstShot or base.FirstShot,
		Wander = r.Wander or base.Wander,
		Jitter = r.Jitter or base.Jitter,
	}
end

-- A seed per gun (its sound folder names it), so every gun has its own spray shape and keeps it.
local function seedOf(gun: any): number
	local key = (gun.Feel and gun.Feel.Sounds) or tostring(gun.FireMode)
	local h = 0
	for i = 1, #key do
		h = (h * 31 + string.byte(key, i)) % 9973
	end
	return h / 97.3
end

function GunFeel.Shot(gun: any, now: number): (number, number, number, number)
	local t = tune(gun)
	if burst.gun ~= gun or now - burst.last > BURST_GAP then
		burst.n = 0
		burst.pulled = 0
		burst.gun = gun
		burst.seed = seedOf(gun)
	end
	burst.n += 1
	burst.last = now
	local n = burst.n
	local r = gun.Recoil
	local pitchMul = (if n == 1 then t.FirstShot else 1) * (0.94 + math.random() * 0.12)
	-- The pattern: math.noise is a smooth curve in [-0.5, 0.5]; it ramps in over the first shots.
	local ramp = math.clamp((n - 1) / 3, 0, 1)
	local pattern = math.noise(n * 0.29, burst.seed) * 2 * t.Wander * ramp
	local yaw = r.Yaw * (pattern + randomSigned() * t.Jitter) + (r.YawBias or 0)
	local roll = randomSigned() * t.Roll
	return pitchMul, yaw, roll, t.Climb
end

-- Holds part of a kick (radians, X pitch and Y yaw) as a raised rest point on the camera spring.
function GunFeel.Climb(spring: any, kick: Vector3)
	local target = spring.Target + Vector3.new(kick.X, kick.Y, 0)
	spring.Target = Vector3.new(
		math.clamp(target.X, -MAX_CLIMB.X, MAX_CLIMB.X),
		math.clamp(target.Y, -MAX_CLIMB.Y, MAX_CLIMB.Y),
		0
	)
end

-- lookPitch: this frame's look input pitch (radians, up is positive) from GunClient.
function GunFeel.Recover(spring: any, dt: number, now: number, lookPitch: number)
	local target = spring.Target
	if target.X == 0 and target.Y == 0 then
		burst.pulled = 0
		return
	end
	if now - burst.last < HOLD_AFTER then
		if lookPitch < 0 then
			burst.pulled += -lookPitch
		end
		return
	end
	-- What the player already pulled down comes off first, then the rest settles.
	local x = target.X
	if burst.pulled > 0 and x > 0 then
		local take = math.min(x, burst.pulled)
		x -= take
		burst.pulled = 0
	end
	local k = math.exp(-RECOVER_RATE * dt)
	x *= k
	local y = target.Y * k
	if math.abs(x) < 1e-4 and math.abs(y) < 1e-4 then
		x, y = 0, 0
	end
	spring.Target = Vector3.new(x, y, 0)
end

-- Motion -------------------------------------------------------------------------------------------------------------

local vmPos = Spring.new(12, 0.6) -- studs, viewmodel space
local vmRot = Spring.new(13, 0.55) -- radians: pitch, yaw, roll
local camKick = Spring.new(15, 0.72) -- radians: pitch, yaw, roll
local motion = { tilt = 0, lift = 0, wasAir = false, lastVy = 0, lastAim = 0, airTime = 0 }

local function smooth(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

function GunFeel.ShotKick(rollDeg: number, aim: number)
	vmRot:Kick(Vector3.new(0, 0, math.rad(rollDeg) * 1.6 * (1 - 0.5 * aim)))
end

function GunFeel.Motion(dt: number, humanoid: Humanoid, root: BasePart, camCF: CFrame, aim: number, sprint: number): (CFrame, Vector3)
	local v = root.AssemblyLinearVelocity
	local side = camCF.RightVector:Dot(v)
	local air = humanoid.FloorMaterial == Enum.Material.Air
	local steady = 1 - 0.75 * aim

	-- Strafe: the gun leans into the move and trails a hair behind it.
	motion.tilt = smooth(motion.tilt, math.clamp(side / 16, -1.4, 1.4), 9, dt)
	-- Falling: the gun floats up a little (it lags the body); rising, it sinks.
	motion.lift = smooth(motion.lift, if air then math.clamp(-v.Y * 0.0016, -0.045, 0.06) else 0, 10, dt)

	if air then
		motion.airTime += dt
		if not motion.wasAir and v.Y > 4 then
			-- Jump: a quick dip as the legs push, then it rides up.
			vmPos:Kick(Vector3.new(0, -0.035, 0.01) * steady)
			vmRot:Kick(Vector3.new(math.rad(2.5), 0, 0) * steady)
		end
	elseif motion.wasAir then
		-- Landing: harder the faster you came down (a step off a kerb is nothing, a roof drop thumps).
		local impact = math.clamp((-motion.lastVy - 10) / 38, 0, 1)
		if impact > 0 and motion.airTime > 0.15 then
			local side = if math.random() < 0.5 then -1 else 1
			vmPos:Kick(Vector3.new(0, -0.11 * impact, 0.05 * impact) * steady)
			vmRot:Kick(Vector3.new(math.rad(-7) * impact, 0, math.rad(3) * side * impact) * steady)
			camKick:Kick(Vector3.new(math.rad(-2.4) * impact, 0, math.rad(1.1) * side * impact))
		end
		motion.airTime = 0
	end
	motion.wasAir = air
	motion.lastVy = v.Y

	-- Going in and out of aim: the gun settles onto the eye with a small kick, and drops off it the same way.
	if aim > 0.02 and motion.lastAim <= 0.02 then
		vmRot:Kick(Vector3.new(math.rad(-1.2), math.rad(0.6), math.rad(2.2)))
		vmPos:Kick(Vector3.new(0, -0.012, 0.012))
	elseif aim < 0.98 and motion.lastAim >= 0.98 then
		vmRot:Kick(Vector3.new(math.rad(1), 0, math.rad(-1.6)))
	end
	motion.lastAim = aim

	local p = vmPos:Update(dt)
	local r = vmRot:Update(dt)
	local c = camKick:Update(dt)
	local lean = motion.tilt * steady * (1 - 0.4 * sprint)
	local vm = CFrame.new(p.X - lean * 0.022, p.Y + motion.lift * steady, p.Z)
		* CFrame.Angles(r.X, r.Y + lean * math.rad(-1.2), r.Z - lean * math.rad(4.5))
	return vm, c
end

-- Low ammo -----------------------------------------------------------------------------------------------------------

function GunFeel.LowAmmo(feel: any, mag: number, magSize: number?)
	if not magSize or magSize < 5 or not feel or not feel.Sounds then
		return
	end
	local from = math.max(2, math.ceil(magSize * 0.3))
	if mag > from then
		return
	end
	local k = 1 - mag / from -- 0 at the start of the low third, 1 on the last round
	SoundKit.Play(feel.Sounds .. "/DryFire", { Volume = 0.16 + 0.26 * k, Speed = 1.3 + 0.3 * k })
end

function GunFeel.Reset()
	burst.n = 0
	burst.last = -math.huge
	burst.pulled = 0
	burst.gun = nil
	vmPos:Reset()
	vmRot:Reset()
	camKick:Reset()
	motion.tilt = 0
	motion.lift = 0
	motion.wasAir = false
	motion.lastVy = 0
	motion.lastAim = 0
	motion.airTime = 0
end

return GunFeel
