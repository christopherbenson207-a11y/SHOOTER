--!strict
-- Suppression and shell shock (7 Nov 2026, FRONTLINE open-world plan phase 1). The same script runs in every combat
-- place (campaign, Multiplayer duel, Zombies). Screen effects are Lighting post effects only (no new UI).
--   Near misses: an enemy round (Remotes.ShotFx from another side's player, soldier or tank) passing within NEAR studs
--   of your head adds suppression. Suppression blurs and greys the view, darkens it a touch and sways the camera a
--   little; it holds for HOLD seconds after the last round, then drains. Friendly fire and your own rounds never
--   suppress (CombatFx still plays the whiz).
--   Blasts: a shell, grenade, tank round or exploding drum close by shakes the view and flashes the screen; a close
--   one rings your ears (Intro/Tinnitus) and muffles every other sound for RING_TIME seconds, then the world comes
--   back. Blasts reach this script from:
--     * anything SoundKit.Play puts in the world with a blast cue (Shared.SoundKit tags the sound's attachment
--       "Blast" with a BlastPower attribute: tanks, explosive drums, the Beacon),
--     * Remotes.Gear "Fx" Kind Blast (grenades, charges),
--     * Remotes.Emplacement "Shell" (artillery, which lands Lead seconds later).
-- Camera bob (Options "Bob") scales the shake and sway; nothing here changes aim or damage.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundKit = require(Shared:WaitForChild("SoundKit"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Options: any = nil
do
	local m = Shared:FindFirstChild("Options")
	if m then
		local ok, t = pcall(require, m)
		if ok then
			Options = t
		end
	end
end

local player = Players.LocalPlayer

local NEAR = 6 -- studs from your head a round still counts as a near miss
local NEAR_ADD = 0.24 -- suppression one round adds when it grazes you (less the further it passes)
local HOLD = 1.1 -- seconds suppression holds after the last round
local DRAIN = 0.55 -- suppression lost a second after that
local SHAKE_RANGE = 36 -- studs (times the blast's power) the view still shakes
local RING_RANGE = 13 -- studs (times power) your ears ring and the world muffles
local RING_TIME = 3
local SAME_BLAST = 4 -- studs and ...
local SAME_TIME = 0.35 -- ... seconds within which two blast reports are one blast

-- Post effects (local to this screen).
local blur = Instance.new("BlurEffect")
blur.Name = "ShockBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "ShockGrade"
grade.Enabled = false
grade.Parent = Lighting

-- The muffle: a low-pass on every mix group but the ringing and the menus.
local MUFFLED_GROUPS = { "SFX", "Mobs", "Ambience", "Beacon" }
local muffles: { EqualizerSoundEffect } = {}
for _, name in MUFFLED_GROUPS do
	local group = SoundService:FindFirstChild(name)
	if group and group:IsA("SoundGroup") then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.Name = "ShellShock"
		eq.LowGain = 0
		eq.MidGain = 0
		eq.HighGain = 0
		eq.Priority = 10
		eq.Enabled = false
		eq.Parent = group
		table.insert(muffles, eq)
	end
end
local ears = Instance.new("SoundGroup")
ears.Name = "Ears"
ears.Volume = 1
ears.Parent = SoundService

local suppression = 0
local lastNear = -math.huge
local flash = 0 -- 1 right after a blast, fading
local shakes: { { Amp: number, T0: number, Dur: number } } = {}
local ringUntil = 0
local ringStart = 0
local ringPower = 0
local ringSound: Sound? = nil
local recent: { { At: Vector3, T: number } } = {}

local function alive(): (Model?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if humanoid and humanoid.Health > 0 and head and head:IsA("BasePart") then
		return character, head
	end
	return nil, nil
end

local function motion(): number
	local bob = Options and Options.Get and Options.Get("Bob")
	return 0.4 + 0.6 * (if typeof(bob) == "number" then bob else 1)
end

local function mySide(): string
	local s = player:GetAttribute("Side")
	return if typeof(s) == "string" then s else "Ally"
end

-- Near misses -----------------------------------------------------------------------------------------------------
local function sideOf(shooter: any): string?
	if typeof(shooter) ~= "Instance" then
		return nil
	end
	if shooter:IsA("Player") then
		local s = shooter:GetAttribute("Side")
		return if typeof(s) == "string" then s else "Ally"
	end
	local s = shooter:GetAttribute("Side")
	return if typeof(s) == "string" then s else nil
end

local function originOf(shooter: Instance): Vector3?
	local model = if shooter:IsA("Player") then shooter.Character else shooter
	if not model then
		return nil
	end
	local muzzle = model:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	local pivot = (model :: Model):GetPivot()
	return pivot.Position
end

local function nearMiss(from: Vector3, to: Vector3, headPos: Vector3)
	local offset = to - from
	local dist = offset.Magnitude
	if dist < 4 then
		return
	end
	local dir = offset / dist
	local along = (headPos - from):Dot(dir)
	if along < 4 or along > dist + NEAR then
		return
	end
	local closest = from + dir * math.min(along, dist)
	local miss = (headPos - closest).Magnitude
	if miss > NEAR then
		return
	end
	suppression = math.min(1, suppression + NEAR_ADD * (1 - miss / NEAR) ^ 0.7 + 0.04)
	lastNear = os.clock()
end

-- Remotes a place may not have (or that its server makes a moment after start).
local function listen(name: string, handler: (...any) -> ())
	task.spawn(function()
		local remote = Remotes:WaitForChild(name, 30)
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(handler)
		end
	end)
end

listen("ShotFx", function(shooter: any, ends: any)
	if shooter == player or typeof(shooter) ~= "Instance" then
		return
	end
	local character, head = alive()
	if not character or not head or (shooter :: Instance) == character then
		return
	end
	local side = sideOf(shooter)
	if side == nil or side == mySide() then
		return
	end
	local from = originOf(shooter)
	if not from then
		return
	end
	if typeof(ends) == "Vector3" then
		ends = { ends }
	end
	if typeof(ends) ~= "table" then
		return
	end
	for _, at in ends do
		if typeof(at) == "Vector3" then
			nearMiss(from, at, head.Position)
		end
	end
end)

-- Blasts ----------------------------------------------------------------------------------------------------------
local function blast(at: Vector3, power: number)
	if typeof(at) ~= "Vector3" or typeof(power) ~= "number" or power <= 0 then
		return
	end
	local now = os.clock()
	for i = #recent, 1, -1 do
		local r = recent[i]
		if now - r.T > SAME_TIME then
			table.remove(recent, i)
		elseif (r.At - at).Magnitude < SAME_BLAST then
			return
		end
	end
	table.insert(recent, { At = at, T = now })

	local character, head = alive()
	if not character or not head then
		return
	end
	local d = (head.Position - at).Magnitude
	local shakeRange = SHAKE_RANGE * math.sqrt(power)
	if d > shakeRange then
		return
	end
	local k = 1 - d / shakeRange
	table.insert(shakes, { Amp = k ^ 1.4 * math.min(power, 1.6), T0 = now, Dur = 0.5 + 0.5 * k })
	flash = math.max(flash, k ^ 2 * 0.9)
	suppression = math.min(1, suppression + k * 0.45)
	lastNear = now

	local ringRange = RING_RANGE * math.sqrt(power)
	if d <= ringRange then
		local r = 1 - d / ringRange
		ringPower = math.max(if now < ringUntil then ringPower else 0, 0.45 + 0.55 * r)
		ringStart = now
		ringUntil = now + RING_TIME * (0.6 + 0.4 * r)
		if not ringSound or not ringSound.Parent then
			ringSound = SoundKit.Play("Intro/Tinnitus", { Volume = 0.4 + 0.6 * r, SoundGroup = ears })
		elseif ringSound then
			ringSound.TimePosition = 0
			ringSound.Volume = math.max(ringSound.Volume, 0.25 + 0.4 * r)
		end
	end
end

local function onTagged(holder: Instance)
	-- Deferred: a blast this screen plays itself is tagged before SoundKit has moved it into place.
	task.defer(function()
		local power = holder:GetAttribute("BlastPower")
		local at = if holder:IsA("Attachment") then holder.WorldPosition elseif holder:IsA("BasePart") then holder.Position else nil
		if at and typeof(power) == "number" then
			blast(at, power)
		end
	end)
end
CollectionService:GetInstanceAddedSignal("Blast"):Connect(onTagged)

listen("Gear", function(msg: any, fx: any)
	if msg == "Fx" and type(fx) == "table" and fx.Kind == "Blast" and typeof(fx.Origin) == "Vector3" then
		local radius = if typeof(fx.Radius) == "number" then fx.Radius else 12
		blast(fx.Origin, math.clamp(radius / 12, 0.6, 1.6))
	end
end)

listen("Emplacement", function(kind: any, at: any, lead: any)
	if kind == "Shell" and typeof(at) == "Vector3" then
		task.delay(tonumber(lead) or 1.2, blast, at, 1.4)
	end
end)

-- A mounted machine gun's rounds (Remotes.EmplacementFx: the gun's model carries its side).
listen("EmplacementFx", function(model: any, origin: any, ends: any)
	if typeof(origin) ~= "Vector3" or type(ends) ~= "table" then
		return
	end
	local side = if typeof(model) == "Instance" then model:GetAttribute("Side") else nil
	if typeof(side) ~= "string" or side == mySide() then
		return
	end
	local _, head = alive()
	if not head then
		return
	end
	for _, at in ends do
		if typeof(at) == "Vector3" then
			nearMiss(origin, at, head.Position)
		end
	end
end)

-- Each frame ------------------------------------------------------------------------------------------------------
local shakeBase: CFrame? = nil
local shakeWrote: CFrame? = nil

local function smooth(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * math.min(1, rate * dt)
end

RunService:BindToRenderStep("CombatShock", Enum.RenderPriority.Last.Value - 2, function(dt: number)
	local now = os.clock()
	local character = alive()
	if not character then
		suppression = 0
		flash = 0
		table.clear(shakes)
		ringUntil = 0
	end

	if now - lastNear > HOLD then
		suppression = math.max(0, suppression - DRAIN * dt)
	end
	flash = math.max(0, flash - dt * 2.2)

	-- Ringing: muffled hard at first, the world comes back over the last two thirds.
	local muffle = 0
	if now < ringUntil then
		local span = math.max(0.01, ringUntil - ringStart)
		local t = (now - ringStart) / span
		muffle = ringPower * (if t < 0.33 then 1 else 1 - (t - 0.33) / 0.67)
	end
	for _, eq in muffles do
		eq.Enabled = muffle > 0.01
		eq.HighGain = -42 * muffle
		eq.MidGain = -20 * muffle
		eq.LowGain = 2 * muffle
	end
	if ringSound and ringSound.Parent and now >= ringUntil then
		ringSound.Volume = smooth(ringSound.Volume, 0, 4, dt)
	end

	local s = suppression
	local low = player:GetAttribute("GraphicsTier") == "Low"
	local blurSize = (s * 6 + flash * 10) * (if low then 0.6 else 1)
	blur.Size = blurSize
	blur.Enabled = blurSize > 0.2
	grade.Brightness = flash * 0.18 - s * 0.06
	grade.Contrast = s * 0.12 + flash * 0.1
	grade.Saturation = -0.38 * s - 0.2 * flash
	grade.Enabled = s > 0.01 or flash > 0.01

	-- Camera: undo last frame's offset if nothing else rewrote the camera since, then shake and sway.
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if shakeWrote and shakeBase and cam.CFrame == shakeWrote then
		cam.CFrame = shakeBase
	end
	shakeWrote, shakeBase = nil, nil
	local total = 0
	for i = #shakes, 1, -1 do
		local sh = shakes[i]
		local k = 1 - (now - sh.T0) / sh.Dur
		if k <= 0 then
			table.remove(shakes, i)
		else
			total += sh.Amp * k * k
		end
	end
	local m = motion()
	local t = now * 22
	local sway = s * 0.35
	if total <= 0.001 and sway <= 0.001 then
		return
	end
	local rx = (math.noise(t, 1.3) * 2.6 * total + math.noise(now * 1.7, 11.1) * sway) * m
	local ry = (math.noise(t, 5.9) * 2.6 * total + math.noise(now * 1.5, 23.4) * sway) * m
	local rz = math.noise(t, 9.2) * 1.4 * total * m
	local offset = CFrame.new(math.noise(t, 3.1) * 0.25 * total * m, math.noise(t, 7.7) * 0.25 * total * m, 0)
		* CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
	shakeBase = cam.CFrame
	shakeWrote = cam.CFrame * offset
	cam.CFrame = shakeWrote :: CFrame
end)
