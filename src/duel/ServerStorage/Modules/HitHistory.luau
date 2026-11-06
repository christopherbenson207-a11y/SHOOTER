--!strict
-- Lag compensation for player targets (5 Nov 2026 duel pass). Every living player character's hitbox parts (the
-- names in GameConfig.Pvp.Zones: the R15 body parts) are written into a ring buffer on Heartbeat, HistoryRate times a
-- second, HistoryLength seconds deep (GameConfig.Validation.Pvp). GunServer asks where a part was over a short span
-- of server time and checks a reported hit against that instead of against the part's present position.
-- Cheap by design: players only, about fifteen CFrame reads per character a frame, no tables made per frame.
-- Parts are kept by name, so a body part the avatar loader swaps after spawn keeps its history.
--   HitHistory.Start()
--   HitHistory.Distance(character, partName, point, tFrom, tTo) -> studs from the point to the part's box at its
--       closest over [tFrom, tTo] (0 inside), or nil when the character has no history yet
--   HitHistory.Ping(player) -> the player's smoothed network ping in seconds
--   HitHistory.Outside(cframe, size, point) -> studs from a point to a box (0 inside)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local CFG = GameConfig.Validation.Pvp
local ZONES: { [string]: string } = GameConfig.Pvp.Zones

local STEP = 1 / CFG.HistoryRate
local SIZE = math.ceil(CFG.HistoryLength * CFG.HistoryRate) + 2

local NAMES: { string } = {}
for name in ZONES do
	table.insert(NAMES, name)
end
table.sort(NAMES)

type Track = {
	character: Model,
	parts: { [string]: BasePart },
	frames: { [string]: { CFrame } },
	sizes: { [string]: Vector3 },
	times: { number },
	head: number, -- slot of the newest sample
	count: number,
	connections: { RBXScriptConnection },
}

local HitHistory = {}

local tracks: { [Model]: Track } = {}
local pings: { [Player]: number } = {}
local started = false

local function refreshParts(track: Track)
	table.clear(track.parts)
	for _, name in NAMES do
		local part = track.character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			track.parts[name] = part
			track.sizes[name] = part.Size
			if not track.frames[name] then
				track.frames[name] = table.create(SIZE, CFrame.identity)
			end
		end
	end
end

local function untrack(character: Model)
	local track = tracks[character]
	if not track then
		return
	end
	tracks[character] = nil
	for _, c in track.connections do
		c:Disconnect()
	end
end

local function trackCharacter(character: Model)
	if tracks[character] then
		return
	end
	local track: Track = {
		character = character,
		parts = {},
		frames = {},
		sizes = {},
		times = table.create(SIZE, -math.huge),
		head = 0,
		count = 0,
		connections = {},
	}
	refreshParts(track)
	local function onChange(child: Instance)
		if ZONES[child.Name] then
			task.defer(refreshParts, track)
		end
	end
	table.insert(track.connections, character.ChildAdded:Connect(onChange))
	table.insert(track.connections, character.ChildRemoved:Connect(onChange))
	table.insert(track.connections, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			untrack(character)
		end
	end))
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(track.connections, humanoid.Died:Connect(function()
			untrack(character)
		end))
	end
	tracks[character] = track
end

local function sample(now: number)
	for _, track in tracks do
		local slot = track.head % SIZE + 1
		track.head = slot
		track.count = math.min(track.count + 1, SIZE)
		track.times[slot] = now
		for name, part in track.parts do
			track.frames[name][slot] = part.CFrame
		end
	end
end

-- How far a point lies outside a box (0 inside).
local function outside(cf: CFrame, size: Vector3, point: Vector3): number
	local p = cf:PointToObjectSpace(point)
	local h = size / 2
	local dx = math.max(math.abs(p.X) - h.X, 0)
	local dy = math.max(math.abs(p.Y) - h.Y, 0)
	local dz = math.max(math.abs(p.Z) - h.Z, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The part's CFrame at server time t, between the two samples around it (clamped to the oldest and newest).
local function at(track: Track, frames: { CFrame }, t: number): CFrame
	local newest = track.head
	if t >= track.times[newest] then
		return frames[newest]
	end
	local slot = newest
	for _ = 1, track.count - 1 do
		local older = (slot - 2) % SIZE + 1
		local t0 = track.times[older]
		if t0 <= t then
			local t1 = track.times[slot]
			local a = if t1 > t0 then (t - t0) / (t1 - t0) else 0
			return frames[older]:Lerp(frames[slot], a)
		end
		slot = older
	end
	return frames[slot]
end

HitHistory.Outside = outside

function HitHistory.Distance(character: Model, partName: string, point: Vector3, tFrom: number, tTo: number): number?
	local track = tracks[character]
	local frames = track and track.frames[partName]
	local size = track and track.sizes[partName]
	if not (track and frames and size) or track.count == 0 then
		return nil
	end
	-- The two ends of the span, then every sample inside it.
	local best = math.min(outside(at(track, frames, tFrom), size, point), outside(at(track, frames, tTo), size, point))
	local slot = track.head
	for _ = 1, track.count do
		local t = track.times[slot]
		if t < tFrom then
			break
		end
		if t <= tTo then
			best = math.min(best, outside(frames[slot], size, point))
			if best == 0 then
				return 0
			end
		end
		slot = (slot - 2) % SIZE + 1
	end
	return best
end

function HitHistory.Ping(player: Player): number
	return pings[player] or 0.1
end

function HitHistory.Start()
	if started then
		return
	end
	started = true
	local function onPlayer(player: Player)
		local function onCharacter(character: Model)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and player.Character == character then
				trackCharacter(character)
			end
		end
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		pings[player] = nil
		if player.Character then
			untrack(player.Character)
		end
	end)

	local acc = 0
	local pingAt = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < STEP * 0.5 then
			return
		end
		acc = math.min(acc - STEP, STEP)
		local now = workspace:GetServerTimeNow()
		sample(now)
		-- Ping twice a second, smoothed so one spike doesn't open the rewind window wide.
		if now - pingAt >= 0.5 then
			pingAt = now
			for _, p in Players:GetPlayers() do
				local ok, raw = pcall(p.GetNetworkPing, p)
				if ok and type(raw) == "number" and raw == raw and raw >= 0 and raw < 5 then
					local old = pings[p]
					pings[p] = if old then old + (raw - old) * 0.3 else raw
				end
			end
		end
	end)
end

return HitHistory
