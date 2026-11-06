--!strict
-- Shared.AimAssist: controller (and touch) aim assist for GunClient. Mouse and keyboard never get any.
-- It only bends the look the player is already giving: with the stick still and the player standing still it does
-- nothing, so it never aims for you.
--   Slowdown: the view turns slower while the crosshair is over an enemy, so staying on target is easier.
--   Tracking: while you look or move, the view follows part of the enemy's movement across the screen (the
--             rotational assist Call of Duty and Apex use on controller).
--   Pull:     a gentle drift toward the enemy's chest while you steer, stronger aiming down sights.
-- Controller look speed (Options PadSens, with the gun's aim and scope factors) and Invert look (Options InvertY) are
-- applied here too, since the Roblox camera has no gamepad sensitivity or invert of its own.
-- Targets: CollectionService "Enemy" models with a living Humanoid, in range and in line of sight. With workspace
-- Front set (FRONTLINE and the duel) the targets are instead the other side, as the guns see it (GunClient
-- getEnemyModel): other players whose Side differs from yours, and Enemy/Ally-tagged bots whose Side differs.
-- Numbers: GameConfig.AimAssist[input type]; strength preset from Options "AimAssist" (Standard / Precision / Off).
-- Against a player, GameConfig.AimAssist.Pvp[input type] scales the preset (less pull; 5 Nov 2026 duel pass).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

export type Context = {
	mode: string, -- Shared.Platform: "KeyboardAndMouse" | "Touch" | "Gamepad"
	preset: string?, -- "Standard" | "Precision" | "Off"
	aim: number, -- 0 hip .. 1 fully aimed
	moving: boolean,
	sens: number, -- look-speed factor for controller input
	invert: boolean?, -- Options InvertY: flips controller up/down look (touch drag flips in TouchControls)
	ignore: { Instance },
}

type Target = { model: Model, part: BasePart, head: BasePart?, humanoid: Humanoid }

local AimAssist = {}

local current: Target? = nil
local lastSearch = 0
local lastDir: Vector3? = nil
local lastModel: Model? = nil

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true
losParams.RespectCanCollide = true

local function yawPitch(look: Vector3): (number, number)
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function angleTo(look: Vector3, origin: Vector3, point: Vector3): number
	local dir = point - origin
	local m = dir.Magnitude
	if m < 0.01 then
		return 0
	end
	return math.acos(math.clamp(look:Dot(dir / m), -1, 1))
end

-- Bubbles are sized for a target RefDistance away and shrink (or grow) with distance, within MinScale..MaxScale.
local function scaleFor(dist: number, cfg: any): number
	return math.clamp(cfg.RefDistance / math.max(dist, 1), cfg.MinScale, cfg.MaxScale)
end

local function bodyOf(model: Model): (BasePart?, BasePart?)
	local part = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
	local head = model:FindFirstChild("Head")
	return if part and part:IsA("BasePart") then part else nil, if head and head:IsA("BasePart") then head else nil
end

local function offAngle(t: Target, look: Vector3, origin: Vector3): number
	local a = angleTo(look, origin, t.part.Position)
	if t.head then
		a = math.min(a, angleTo(look, origin, t.head.Position))
	end
	return a
end

-- Invisible parts (map boundaries, trigger volumes) aren't cover: look past up to a few of them.
local function visible(origin: Vector3, t: Target, ignore: { Instance }): boolean
	local filter = table.clone(ignore)
	for _ = 1, 4 do
		losParams.FilterDescendantsInstances = filter
		local hit = workspace:Raycast(origin, t.part.Position - origin, losParams)
		if hit == nil or hit.Instance:IsDescendantOf(t.model) then
			return true
		end
		if hit.Instance.Transparency < 0.9 then
			return false
		end
		table.insert(filter, hit.Instance)
	end
	return false
end

-- Who can be assisted onto right now (see the header).
local function candidates(): { Instance }
	if not workspace:GetAttribute("Front") then
		return CollectionService:GetTagged("Enemy")
	end
	local me = Players.LocalPlayer
	local mine = (me and me:GetAttribute("Side")) or "Ally"
	local list: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p ~= me and p.Character and (p:GetAttribute("Side") or "Ally") ~= mine then
			table.insert(list, p.Character)
		end
	end
	for _, tag in { "Enemy", "Ally" } do
		for _, model in CollectionService:GetTagged(tag) do
			local side = model:GetAttribute("Side")
			if side and side ~= mine and not Players:GetPlayerFromCharacter(model) then
				table.insert(list, model)
			end
		end
	end
	return list
end

local function search(origin: Vector3, look: Vector3, cfg: any, ignore: { Instance }): Target?
	local reach = math.rad(math.max(cfg.SlowdownRadius, cfg.MagnetRadius, cfg.TrackRadius))
	local found: { { t: Target, score: number } } = {}
	for _, model in candidates() do
		if model:IsA("Model") and model.Parent then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local part, head = bodyOf(model)
			if humanoid and humanoid.Health > 0 and part then
				local dist = (part.Position - origin).Magnitude
				if dist <= cfg.Range then
					local t = { model = model, part = part, head = head, humanoid = humanoid }
					local limit = reach * scaleFor(dist, cfg)
					local off = offAngle(t, look, origin)
					if off <= limit then
						table.insert(found, { t = t, score = off / limit + 0.25 * dist / cfg.Range })
					end
				end
			end
		end
	end
	table.sort(found, function(a, b)
		return a.score < b.score
	end)
	for i = 1, math.min(#found, 3) do
		if visible(origin, found[i].t, ignore) then
			return found[i].t
		end
	end
	return nil
end

-- prevCF: last frame's camera (without roll). inputCF: this frame's camera from the camera module, i.e. last frame
-- plus the player's look input. Returns the camera to use instead.
function AimAssist.Step(dt: number, prevCF: CFrame, inputCF: CFrame, ctx: Context): CFrame
	if ctx.mode == "KeyboardAndMouse" then
		current, lastDir, lastModel = nil, nil, nil
		return inputCF
	end
	local pos = inputCF.Position
	local py, pp = yawPitch(prevCF.LookVector)
	local iy, ip = yawPitch(inputCF.LookVector)
	local dy, dp = wrap(iy - py), ip - pp
	local rawDy, rawDp = dy, dp
	-- A jump this big in one frame is a camera cut (respawn, cutscene, teleport), never stick input.
	if math.abs(dy) + math.abs(dp) > 0.6 then
		current, lastDir, lastModel = nil, nil, nil
		return inputCF
	end
	local touched = false
	if ctx.mode == "Gamepad" and math.abs(ctx.sens - 1) > 0.001 then
		dy *= ctx.sens
		dp *= ctx.sens
		touched = true
	end
	if ctx.mode == "Gamepad" and ctx.invert and dp ~= 0 then
		dp = -dp
		touched = true
	end

	local all: any = GameConfig.AimAssist
	local cfg = all and all[ctx.mode]
	local preset: any = all and all.Presets and all.Presets[ctx.preset or "Standard"]
	if cfg and cfg.Enabled and preset then
		local now = os.clock()
		if now - lastSearch >= cfg.SearchGap then
			lastSearch = now
			current = search(pos, prevCF.LookVector, cfg, ctx.ignore)
		end
		local t = current
		if t and t.humanoid.Health > 0 and t.part.Parent then
			-- Against a player the preset is scaled down (GameConfig.AimAssist.Pvp): same slowdown, less pull.
			local scaleBy = all.Pvp and all.Pvp[ctx.mode]
			if scaleBy and Players:GetPlayerFromCharacter(t.model) then
				preset = {
					Slowdown = preset.Slowdown * scaleBy.Slowdown,
					Rotation = preset.Rotation * scaleBy.Rotation,
					Magnet = preset.Magnet * scaleBy.Magnet,
				}
			end
			local point = t.part.Position
			local dir = (point - pos).Unit
			local scale = scaleFor((point - pos).Magnitude, cfg)
			local off = offAngle(t, prevCF.LookVector, pos)
			local engaged = math.abs(dy) + math.abs(dp) > 1e-4 or ctx.moving
			local ads = math.clamp(ctx.aim, 0, 1)

			-- Slowdown: full strength over the body, fading out to the bubble's edge.
			local slowRadius = math.rad(cfg.SlowdownRadius) * scale
			if off < slowRadius then
				local k = math.min(1, (1 - off / slowRadius) * 1.6)
				local floor = lerp(cfg.SlowdownMultiplier, cfg.AdsSlowdownMultiplier, ads)
				local mult = math.clamp(1 - (1 - floor) * preset.Slowdown * k, 0.15, 1)
				dy *= mult
				dp *= mult
				touched = true
			end

			-- Tracking: follow a share of the target's own angular motion this frame.
			if engaged and lastModel == t.model and lastDir and off < math.rad(cfg.TrackRadius) * scale then
				local ty, tp = yawPitch(dir)
				local ly, lp = yawPitch(lastDir)
				local tdy, tdp = wrap(ty - ly), tp - lp
				if math.abs(tdy) + math.abs(tdp) < math.rad(15) then
					local s = lerp(cfg.RotationStrength, cfg.AdsRotationStrength, ads) * preset.Rotation
					dy += tdy * s
					dp += tdp * s
					touched = true
				end
			end

			-- Pull toward the chest while steering.
			local magnetRadius = math.rad(cfg.MagnetRadius) * scale
			if engaged and preset.Magnet > 0 and off < magnetRadius and off > math.rad(0.25) then
				local ty, tp = yawPitch(dir)
				local rate = cfg.MagnetStrength * preset.Magnet * (0.4 + 0.6 * ads)
				local f = 1 - math.exp(-rate * 10 * dt)
				dy += wrap(ty - (py + dy)) * f
				dp += (tp - (pp + dp)) * f
				touched = true
			end
			lastDir, lastModel = dir, t.model
		else
			current, lastDir, lastModel = nil, nil, nil
		end
	end

	-- Nothing actually bent (e.g. the stick is still): hand back the camera module's own frame untouched.
	if not touched or (dy == rawDy and dp == rawDp) then
		return inputCF
	end
	local pitch = math.clamp(pp + dp, -math.rad(85), math.rad(85))
	return CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(pitch, py + dy, 0)
end

return AimAssist
