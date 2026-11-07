--!strict
-- Gyro aim for phones and tablets: turns the device's rotation readings
-- (UserInputService.DeviceRotationChanged) into camera yaw and pitch. TouchControls feeds it every
-- reading with Reading() and asks it each frame how far to turn with Step(). docs/GYRO-AIM.md has
-- the full write-up, and tools/gyro_sim.py tests this maths (keep the two in step).
--
-- The aiming method is Jibb Smart's (GyroWiki, JoyShockMapper), the one PC, Switch and Steam gyro
-- aim use:
-- * Yaw is "player space": the turn about world up, relaxed so that both turning your body and
--   twisting the phone in your hands turn the view.
-- * Pitch is the turn about the screen's own left-right edge.
-- * Tightening shrinks tiny movements (no shake while holding still), and soft tiered smoothing
--   smooths slow movements while fast ones pass straight through (no lag on a flick).
--
-- Roblox doesn't document the frame of its rotation CFrame, and phones differ (DevForum reports:
-- Android swaps axes and flips one against iPhone, tablets flip a sign against phones). So nothing
-- here assumes it. The gravity sensor's frame is the documented one: X toward the phone's left
-- edge, Y out of the screen, Z toward its top edge, gravity pointing at the ground. A self-check
-- (check()) tries all 48 ways the rotation CFrame could sit against that (24 ways its axes can map
-- onto gravity's, each device-to-world or world-to-device) and keeps the one under which gravity
-- stays put in the world. After that, up comes from the rotation itself, which has none of the
-- accelerometer's hand shake.

local GyroAim = {}
GyroAim.__index = GyroAim

local SCREEN_OUT = Vector3.yAxis
-- One reading turning further than this is the sensor re-centring or the screen rotating, not a hand.
local MAX_STEP = math.rad(45)
-- A reading this long (seconds) after the last one isn't measured against it (the game hitched).
local STALE = 0.25
-- Player space: a turn within about 45 degrees of world up counts in full as yaw.
local RELAX = 1.41

-- Self-check: how fast its running means move (per reading), readings before it decides, how many
-- times steadier the best convention must be than any other (plus a floor for sensor noise), how
-- many readings in a row a new verdict must hold, and how steady the chosen one must be before
-- world up follows it (1 - mean length).
local CHECK_RATE = 0.03
local CHECK_WARMUP = 30
local CHECK_RATIO = 3
local CHECK_FLOOR = 0.0003
local CHECK_HOLD = 15
local UP_STEADY = 0.01

-- The screen's left-right edge, learned while the phone is tilted at least EDGE_MIN out of flat
-- (sine of the tilt); until it is learned, any tilt over EDGE_ANY gives it straight away.
local EDGE_RATE = 0.05
local EDGE_MIN = 0.1
local EDGE_ANY = 0.02

-- Filtering, in radians per second.
local WINDOW = 1 / 30 -- the rate is averaged over this long, so readings and frames needn't line up
local HISTORY = 8
local TIGHTEN = math.rad(3)
local SMOOTH_HIGH = math.rad(8)
local SMOOTH_LOW = SMOOTH_HIGH / 2
local SMOOTH_TIME = 0.125

-- One way the rotation CFrame can be meant. map takes gravity-frame axes to the CFrame's own;
-- inverse means the CFrame maps world to phone. twin is the same convention turned half round the
-- phone's long edge: a phone held in landscape keeps that edge level, and then twins look equally
-- steady against gravity. They agree on pitch and disagree on the sign of yaw; only a twist of the
-- phone tells them apart.
type Candidate = {
	map: CFrame,
	inverse: boolean,
	twin: number,
	name: string,
}

local AXIS_NAMES = { "X", "Y", "Z" }
local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
local MAPS: { CFrame } = {}
local MAP_NAMES: { string } = {}
for _, perm in { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } } do
	for _, signs in { { 1, 1, 1 }, { 1, 1, -1 }, { 1, -1, 1 }, { 1, -1, -1 }, { -1, 1, 1 }, { -1, 1, -1 }, { -1, -1, 1 }, { -1, -1, -1 } } do
		local x, y, z = AXES[perm[1]] * signs[1], AXES[perm[2]] * signs[2], AXES[perm[3]] * signs[3]
		if x:Cross(y):Dot(z) > 0 then
			table.insert(MAPS, CFrame.fromMatrix(Vector3.zero, x, y, z))
			local parts = {}
			for i = 1, 3 do
				table.insert(parts, AXIS_NAMES[i] .. "=" .. (if signs[i] > 0 then "+" else "-") .. AXIS_NAMES[perm[i]])
			end
			table.insert(MAP_NAMES, table.concat(parts, " "))
		end
	end
end

local function sameRotation(a: CFrame, b: CFrame): boolean
	return a.XVector:FuzzyEq(b.XVector, 1e-4) and a.YVector:FuzzyEq(b.YVector, 1e-4) and a.ZVector:FuzzyEq(b.ZVector, 1e-4)
end

local FLIP_LONG_EDGE = CFrame.Angles(0, 0, math.pi)
local CANDIDATES: { Candidate } = {}
local DEFAULT = 0 -- the documented guess: identity, device-to-world
for m, map in MAPS do
	local twinMap = 0
	for t, other in MAPS do
		if sameRotation(other, map * FLIP_LONG_EDGE) then
			twinMap = t
		end
	end
	-- Candidate 2m - 1 is device-to-world, 2m world-to-device; the twin keeps the same direction.
	for _, inverse in { false, true } do
		table.insert(CANDIDATES, {
			map = map,
			inverse = inverse,
			twin = twinMap * 2 - (if inverse then 0 else 1),
			name = (if inverse then "world-to-phone, " else "phone-to-world, ") .. MAP_NAMES[m],
		})
	end
	if sameRotation(map, CFrame.identity) then
		DEFAULT = m * 2 - 1
	end
end
assert(#MAPS == 24 and DEFAULT > 0, "GyroAim: axis maps")

type Fields = {
	last: CFrame?,
	lastTime: number,
	pending: Vector2,
	choice: number,
	verdict: number,
	votes: number,
	samples: number,
	means: { Vector3 },
	mapped: { Vector3 },
	up: Vector3?,
	edge: Vector3,
	angles: { Vector2 },
	steps: { number },
	smoothed: Vector2,
}

export type GyroAim = typeof(setmetatable({} :: Fields, GyroAim))

function GyroAim.new(): GyroAim
	local means = table.create(#CANDIDATES, Vector3.zero)
	local fields: Fields = {
		last = nil,
		lastTime = 0,
		pending = Vector2.zero, -- (yaw, pitch) radians since the last Step
		choice = DEFAULT,
		verdict = DEFAULT,
		votes = 0,
		samples = 0,
		means = means,
		mapped = table.create(#MAPS, Vector3.zero),
		up = nil, -- world up in the chosen convention's world frame, once it is steady
		edge = Vector3.zero, -- the screen's left-right edge in the phone's frame (zero until learned)
		angles = {},
		steps = {},
		smoothed = Vector2.zero,
	}
	return setmetatable(fields, GyroAim)
end

-- The phone's rotation as device-to-world in the gravity sensor's axes, read the candidate's way.
local function toWorld(cf: CFrame, candidate: Candidate): CFrame
	return (if candidate.inverse then cf:Inverse() else cf) * candidate.map
end

-- Which convention the rotation CFrame uses. Carried into the world the right way, up (from the
-- gravity sensor) points the same way every reading however the phone moves; carried a wrong way,
-- it swings about. A running mean of unit vectors keeps length 1 only while they agree, so the
-- steadiest mean shows the convention. Twins are told apart by a twist when there was one, else by
-- which one puts world up along +Y or +Z of the sensor's frame (Roblox's and the phones' own world
-- frames are level with up positive).
local function check(self: GyroAim, cf: CFrame, upInPhone: Vector3)
	-- The means start from the first reading: started from zero they'd look unsteady for seconds.
	local rate = if self.samples == 0 then 1 else CHECK_RATE
	local means, mapped = self.means, self.mapped
	for m, map in MAPS do
		mapped[m] = map:VectorToWorldSpace(upInPhone)
	end
	for k, candidate in CANDIDATES do
		local v = mapped[(k + 1) // 2]
		local w = if candidate.inverse then cf:VectorToObjectSpace(v) else cf:VectorToWorldSpace(v)
		means[k] = means[k]:Lerp(w, rate)
	end
	self.samples += 1
	if self.samples < CHECK_WARMUP then
		return
	end

	local best, bestMiss = DEFAULT, math.huge
	for k, mean in means do
		local miss = 1 - mean.Magnitude
		if miss < bestMiss then
			best, bestMiss = k, miss
		end
	end
	local twin = CANDIDATES[best].twin
	local rivalMiss = math.huge
	for k, mean in means do
		if k ~= best and k ~= twin then
			rivalMiss = math.min(rivalMiss, 1 - mean.Magnitude)
		end
	end
	local verdict = self.choice
	local bar = bestMiss * CHECK_RATIO + CHECK_FLOOR
	if bar < rivalMiss then
		verdict = best
		if bar >= 1 - means[twin].Magnitude then
			local a, b = means[best], means[twin]
			if math.max(b.Y, b.Z) > math.max(a.Y, a.Z) then
				verdict = twin
			end
		end
	end

	if verdict == self.choice then
		self.votes = 0
	elseif verdict == self.verdict then
		self.votes += 1
	else
		self.verdict = verdict
		self.votes = 1
	end
	if verdict ~= self.choice and self.votes >= CHECK_HOLD then
		self.choice = verdict
		self.votes = 0
		-- Relearn up and the screen edge the new way.
		self.up = nil
		self.edge = Vector3.zero
		print(`[GyroAim] this device's gyro reads {CANDIDATES[verdict].name}`)
	end
	local chosen = means[self.choice]
	if 1 - chosen.Magnitude < UP_STEADY then
		self.up = chosen.Unit
	end
end

-- Forget the last reading and the filters (the gyro was switched off or paused). The self-check
-- and the learned screen edge stay.
function GyroAim.Reset(self: GyroAim)
	self.last = nil
	self.pending = Vector2.zero
	table.clear(self.angles)
	table.clear(self.steps)
	self.smoothed = Vector2.zero
end

-- One rotation reading. gravity is the latest UserInputService gravity Position (nil without an
-- accelerometer). While active is false only the self-check runs, so it's ready when the gyro is.
function GyroAim.Reading(self: GyroAim, cf: CFrame, gravity: Vector3?, active: boolean)
	cf = cf.Rotation
	local upFromGravity: Vector3? = nil
	if gravity and gravity.Magnitude > 1e-3 then
		upFromGravity = -gravity.Unit
		check(self, cf, -gravity.Unit)
	end
	if not active then
		if self.last then
			self:Reset()
		end
		return
	end
	local now = os.clock()
	local last, lastTime = self.last, self.lastTime
	self.last, self.lastTime = cf, now
	if not last or now - lastTime > STALE then
		return
	end

	local candidate = CANDIDATES[self.choice]
	local world = toWorld(cf, candidate)
	local axis, angle = (toWorld(last, candidate):Inverse() * world):ToAxisAngle()
	if angle ~= angle or angle < 1e-7 or angle > MAX_STEP then
		return
	end
	local turn = axis * angle -- in the phone's frame
	local worldUp = self.up
	local up = if worldUp
		then world:VectorToObjectSpace(worldUp)
		elseif upFromGravity then upFromGravity
		else world:VectorToObjectSpace(Vector3.yAxis)

	-- The screen's level left-right line (up x screen normal points to the screen's right). Learn it
	-- while the phone is tilted; snap to it when it reverses (the phone turned to the other landscape).
	local side = up:Cross(SCREEN_OUT)
	local level = side.Magnitude
	local learned = self.edge.Magnitude > 0.5
	if level > EDGE_MIN or (not learned and level > EDGE_ANY) then
		local unit = side / level
		if not learned or unit:Dot(self.edge) < -0.5 then
			self.edge = unit
		else
			self.edge = self.edge:Lerp(unit, EDGE_RATE).Unit
		end
	end
	local edge = self.edge
	if edge.Magnitude < 0.5 then
		return
	end

	-- Pitch: the turn about the screen's left-right edge (positive tilts the top toward you: look up).
	-- Yaw: what's left, measured against up and relaxed (positive turns left).
	local pitch = turn:Dot(edge)
	local rest = turn - edge * pitch
	local upRest = up - edge * up:Dot(edge)
	local worldYaw = rest:Dot(upRest)
	local yaw = math.sign(worldYaw) * math.min(math.abs(worldYaw) * RELAX, rest.Magnitude)
	self.pending += Vector2.new(yaw, pitch)
end

-- How far to turn the camera this frame, as (yaw, pitch) in radians, before the player's
-- sensitivity. Positive yaw turns left, positive pitch looks up.
function GyroAim.Step(self: GyroAim, dt: number): Vector2
	if dt <= 0 then
		return Vector2.zero
	end
	local angles, steps = self.angles, self.steps
	table.insert(angles, self.pending)
	table.insert(steps, dt)
	self.pending = Vector2.zero
	if #angles > HISTORY then
		table.remove(angles, 1)
		table.remove(steps, 1)
	end

	-- Rate over the last WINDOW: a frame that got no reading and one that got two even out.
	local sum, span = Vector2.zero, 0
	for i = #angles, 1, -1 do
		sum += angles[i]
		span += steps[i]
		if span >= WINDOW then
			break
		end
	end
	local rate = sum / span
	local speed = rate.Magnitude
	if speed < TIGHTEN then
		rate *= speed / TIGHTEN
	end
	local direct = math.clamp((speed - SMOOTH_LOW) / (SMOOTH_HIGH - SMOOTH_LOW), 0, 1)
	self.smoothed = self.smoothed:Lerp(rate * (1 - direct), 1 - math.exp(-dt / SMOOTH_TIME))
	local turn = (rate * direct + self.smoothed) * dt
	if turn.Magnitude < 1e-8 then
		return Vector2.zero
	end
	return turn
end

-- The convention the self-check has settled on, for debugging (the console also prints it once).
function GyroAim.Convention(self: GyroAim): string
	return CANDIDATES[self.choice].name
end

return GyroAim
