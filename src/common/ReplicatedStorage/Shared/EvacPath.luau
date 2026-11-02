-- The pickup helicopter's flight, worked out from time alone, so the server (who's in reach of
-- the ladder, the climb) and every client (drawing it) agree without moving any parts over
-- the network. t is seconds since it reached the zone (workspace attribute EvacAt, server
-- time); leaveAt (EvacLeaveAt - EvacAt) is when it stops crawling and climbs away, which the
-- server brings forward once everyone is aboard. Numbers: GameConfig.Breakout.Evac.

local GameConfig = require(script.Parent.GameConfig)

local CFG = GameConfig.Breakout.Evac
local FROM = CFG.From.Unit
local TO = CFG.To.Unit

local EvacPath = {}

EvacPath.DefaultLeave = CFG.Hover + CFG.Crawl

local function bezier(a, b, c, u)
	local v = 1 - u
	return a * (v * v) + b * (2 * v * u) + c * (u * u)
end

local function yawOf(dir)
	return math.atan2(-dir.X, -dir.Z)
end

local function lerpAngle(a, b, u)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * u
end

-- Where it is while pulling away, s seconds into the crawl.
local function crawlPos(hover, s)
	return hover + TO * (CFG.CrawlSpeed * s) + Vector3.new(0, CFG.CrawlRise * math.clamp(s / CFG.Crawl, 0, 1), 0)
end

-- "Inbound", "Hover", "Crawl", "Leave" or "Gone".
function EvacPath.Phase(t, leaveAt)
	leaveAt = leaveAt or EvacPath.DefaultLeave
	if t < 0 then
		return "Inbound"
	elseif t < math.min(CFG.Hover, leaveAt) then
		return "Hover"
	elseif t < leaveAt then
		return "Crawl"
	elseif t < leaveAt + CFG.Leave then
		return "Leave"
	end
	return "Gone"
end

-- The helicopter root's CFrame (its nose is -Z, the open door on its -X side).
function EvacPath.Pose(zonePos, t, leaveAt)
	leaveAt = leaveAt or EvacPath.DefaultLeave
	local hover = zonePos + Vector3.new(0, CFG.Height, 0)
	local start = hover + FROM * 260 + Vector3.new(0, 90, 0)
	local mid = hover + FROM * 90 + Vector3.new(0, 40, 0)
	local bob = Vector3.new(math.sin(t * 0.9) * 0.6, math.sin(t * 1.3) * 0.7, math.sin(t * 0.7) * 0.5)
	local pos, yaw, pitch, roll
	if t < 0 then
		local e = 1 - (1 - math.clamp((t + CFG.Inbound) / CFG.Inbound, 0, 1)) ^ 2.4
		pos = bezier(start, mid, hover, e) + bob * e
		yaw = lerpAngle(yawOf(-FROM), yawOf(TO), math.clamp((e - 0.7) / 0.3, 0, 1))
		pitch = -0.18 * (1 - e) + 0.12 * math.sin(math.clamp((e - 0.75) / 0.25, 0, 1) * math.pi)
		roll = 0.15 * math.sin(e * math.pi)
	else
		local crawled = math.max(0, math.min(t, leaveAt) - math.min(CFG.Hover, leaveAt))
		local base = crawlPos(hover, crawled)
		yaw = yawOf(TO)
		if t < leaveAt then
			pos = base + bob
			pitch = if crawled > 0 then -0.06 else 0
			roll = 0
		else
			local u = math.clamp((t - leaveAt) / CFG.Leave, 0, 1)
			local e = u ^ 1.8
			pos = bezier(base, base + TO * 60 + Vector3.new(0, 80, 0), base + TO * 340 + Vector3.new(0, 280, 0), e) + bob * (1 - e)
			pitch = -0.22 * math.sin(math.min(u * 2, 1) * math.pi / 2)
			roll = 0
		end
	end
	return CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
end

-- The cabin door (top of the ladder) and the ladder's foot, swinging a little and trailing
-- behind while it moves.
function EvacPath.Ladder(pose, t, leaveAt)
	local door = pose:PointToWorldSpace(CFG.Door)
	local moving = EvacPath.Phase(t, leaveAt) ~= "Hover"
	local sway = Vector3.new(math.sin(t * 1.7) * 1.1, 0, math.cos(t * 1.3) * 0.8)
	local trail = if moving then -TO * 3.5 else Vector3.zero
	return door, door - Vector3.new(0, CFG.Ladder, 0) + sway + trail
end

return EvacPath
