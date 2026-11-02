-- Small damped spring for recoil, sway and kick. Position settles on Target.

local Spring = {}
Spring.__index = Spring

local STEP = 1 / 120

function Spring.new(speed: number, damping: number)
	return setmetatable({
		Position = Vector3.zero,
		Velocity = Vector3.zero,
		Target = Vector3.zero,
		Speed = speed,
		Damping = damping,
	}, Spring)
end

-- Adds velocity so the spring peaks at roughly `peak` (exact when Damping = 1).
function Spring:Kick(peak: Vector3)
	self.Velocity += peak * math.exp(1) * self.Speed
end

function Spring:Update(dt: number): Vector3
	local steps = math.max(1, math.ceil(dt / STEP))
	local h = dt / steps
	local w = self.Speed
	for _ = 1, steps do
		local force = (self.Target - self.Position) * w * w - self.Velocity * 2 * self.Damping * w
		self.Velocity += force * h
		self.Position += self.Velocity * h
	end
	return self.Position
end

function Spring:Reset()
	self.Position = Vector3.zero
	self.Velocity = Vector3.zero
	self.Target = Vector3.zero
end

return Spring
