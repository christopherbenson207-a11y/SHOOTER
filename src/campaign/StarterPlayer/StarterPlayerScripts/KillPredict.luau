-- Kill prediction for the shooter (the lag fix, Call of Duty style): the moment a shot lands,
-- this client works out the damage with the server's own numbers (GunServer checkHit) against
-- the mob's replicated health. If the shot kills, the body goes limp and flies on this frame:
-- the real mob is hidden here and a local copy of it, posed exactly as it stood, is
-- ragdolled and thrown in workspace.Fx. Everyone else still sees the server's ragdoll.
-- Damage still in flight (an AK burst) counts toward the next shot until the server catches
-- up. If the server disagrees (the mob is still standing a moment later), the copy goes and
-- the real mob shows again. Limbs the server tears off afterwards leave the copy too.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Callout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Callout"))

local player = Players.LocalPlayer
local fxWorld = workspace:WaitForChild("Fx")

-- Matches MobReactions' ragdoll.
local RAG_SWING = 55
local RAG_TWIST = 50
local MAX_CORPSES = 10
local FADE = TweenInfo.new(1)

local KillPredict = {}

local pending = setmetatable({}, { __mode = "k" }) -- [model] = { Damage, Until }
local predicted = setmetatable({}, { __mode = "k" }) -- [model] = { Copy, Conns, At }
local corpses = {}

local function ping()
	local ok, p = pcall(function()
		return player:GetNetworkPing()
	end)
	return if ok and p then p else 0.1
end

-- Same formula as GunServer checkHit.
local function damageOf(gun, hit)
	local dist = hit.Dist
	local falloff = math.clamp((dist - gun.FalloffStart) / (gun.FalloffEnd - gun.FalloffStart), 0, 1)
	local multiplier = 1 - falloff * (1 - gun.FalloffMin)
	local part = hit.Part
	if part.Name == "Head" or part:GetAttribute("Limb") == "Head" then
		multiplier *= gun.HeadMultiplier
	end
	if hit.Index > 1 and gun.Penetration then
		multiplier *= gun.Penetration.DamageKeep ^ (hit.Index - 1)
	end
	return math.floor(gun.Damage * multiplier + 0.5)
end

local function hideOne(d)
	if d:IsA("BasePart") or d:IsA("Decal") then
		d.LocalTransparencyModifier = 1
	elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Beam") or d:IsA("Highlight") then
		d.Enabled = false
	end
end

local function showOne(d)
	if d:IsA("BasePart") or d:IsA("Decal") then
		d.LocalTransparencyModifier = 0
	end
end

local function ragdoll(model)
	local root = model.PrimaryPart
	for _, j in model:GetDescendants() do
		if j:IsA("Motor6D") and j.Part0 and j.Part1 and j.Part0 ~= root and j.Part1 ~= root then
			local a0 = Instance.new("Attachment")
			a0.CFrame = j.C0
			a0.Parent = j.Part0
			local a1 = Instance.new("Attachment")
			a1.CFrame = j.C1
			a1.Parent = j.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = RAG_SWING
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -RAG_TWIST
			socket.TwistUpperAngle = RAG_TWIST
			socket.Parent = j.Part0
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = j.Part0
			nc.Part1 = j.Part1
			nc.Parent = j.Part0
			j:Destroy()
		end
	end
end

local function fadeOut(copy)
	for _, p in copy:GetDescendants() do
		if p:IsA("BasePart") then
			TweenService:Create(p, FADE, { Transparency = 1 }):Play()
		end
	end
	task.delay(1.1, function()
		copy:Destroy()
	end)
end

local function release(model, restore)
	local entry = predicted[model]
	if not entry then
		return
	end
	predicted[model] = nil
	for _, c in entry.Conns do
		c:Disconnect()
	end
	if restore then
		entry.Copy:Destroy()
		for _, d in model:GetDescendants() do
			showOne(d)
		end
	end
end

-- The copy: the mob as it stands right now, limp, in Fx (which shots and mobs ignore).
local function buildCopy(model)
	local wasArchivable = model.Archivable
	model.Archivable = true
	local ok, copy = pcall(function()
		return model:Clone()
	end)
	model.Archivable = wasArchivable
	if not ok or not copy then
		return nil
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("Highlight") then
			d:Destroy()
		end
	end
	for _, tag in CollectionService:GetTags(copy) do
		CollectionService:RemoveTag(copy, tag)
	end
	copy.Name = "LocalCorpse"
	copy:SetAttribute("Dead", true)
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			animator:Destroy()
		end
	end
	local root = copy.PrimaryPart
	for _, p in copy:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = p ~= root and p.Size.Magnitude > 0.4
			p.CanQuery = false
			p.CanTouch = false
			p.CollisionGroup = "Debris"
			p.LocalTransparencyModifier = 0
		elseif p:IsA("Decal") then
			p.LocalTransparencyModifier = 0
		end
	end
	ragdoll(copy)
	return copy
end

-- Hits from one shot on one mob: { Part, Pos, Dist, Index } each. dir is the shot's
-- direction, share the part of the pellets that landed. Returns true if this predicts a kill
-- (and the body is already flying on this screen).
function KillPredict.Shot(model, hits, gun, dir, share)
	if predicted[model] or model:GetAttribute("Dead") or #hits == 0 then
		return predicted[model] ~= nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local now = os.clock()
	local total, closest = 0, math.huge
	for _, hit in hits do
		total += damageOf(gun, hit)
		closest = math.min(closest, hit.Dist)
	end
	local p = pending[model]
	if p and now > p.Until then
		p = nil
	end
	local already = if p then p.Damage else 0
	pending[model] = { Damage = already + total, Until = now + ping() * 2 + 0.25 }
	if humanoid.Health - already - total > 0 then
		return false
	end

	local mob = GameConfig.Mobs[model:GetAttribute("MobType") or ""]
	local copy = buildCopy(model)
	if not mob or not copy then
		return false
	end
	local feel = gun.Feel or {}
	local splat = feel.Splat
	local splatThrow = if splat and closest <= splat.Range and (share or 1) >= splat.MinShare then splat.Throw else 1

	-- Hide the real body here, now and as parts change.
	local conns = {}
	for _, d in model:GetDescendants() do
		hideOne(d)
	end
	table.insert(conns, model.DescendantAdded:Connect(hideOne))
	-- A limb the server tears off leaves the copy too (the real one flies off from there).
	table.insert(conns, model.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") and d.Parent ~= nil then
			task.defer(function()
				if d.Parent and not d:IsDescendantOf(model) then
					local mine = copy:FindFirstChild(d.Name, true)
					if mine and mine:IsA("BasePart") and mine ~= copy.PrimaryPart then
						mine:Destroy()
					end
					d.LocalTransparencyModifier = 0
				end
			end)
		end
	end))
	table.insert(conns, model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			release(model, false)
			if copy.Parent then
				fadeOut(copy)
			end
		end
	end))
	predicted[model] = { Copy = copy, Conns = conns, At = now }
	Callout.Note("Kill")

	copy.Parent = fxWorld
	table.insert(corpses, copy)
	while #corpses > MAX_CORPSES do
		local old = table.remove(corpses, 1)
		if old.Parent then
			fadeOut(old)
		end
	end

	-- A beat of stillness so the kill reads, then limp and thrown along the shot.
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	flatDir = if flatDir.Magnitude > 1e-3 then flatDir.Unit else Vector3.zAxis
	local throw = (feel.BodyThrow or 30) * (mob.ThrowScale or 1) * splatThrow
	local fling = flatDir * throw + Vector3.new(0, throw * (feel.BodyLift or 0.3), 0)
	local tumble = Vector3.yAxis:Cross(flatDir) * throw * 0.18
	local lead = hits[1].Part.Name
	task.delay(feel.KillFreeze or 0.06, function()
		if not copy.Parent then
			return
		end
		for _, part in copy:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end
		for _, part in copy:GetDescendants() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = fling * (0.85 + math.random() * 0.3)
				part.AssemblyAngularVelocity = tumble + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * throw * 0.05
			end
		end
		local hitPart = copy:FindFirstChild(lead, true)
		if hitPart and hitPart:IsA("BasePart") then
			hitPart.AssemblyLinearVelocity += flatDir * throw * 0.35
		end
	end)

	-- The server has the last word: still standing after a round trip means it lived.
	task.delay(ping() * 2 + 0.6, function()
		if predicted[model] and predicted[model].Copy == copy and model.Parent
			and humanoid.Health > 0 and not model:GetAttribute("Dead")
		then
			release(model, true)
		end
	end)
	task.delay((mob.CorpseTime or 12), function()
		if copy.Parent then
			fadeOut(copy)
		end
	end)
	return true
end

function KillPredict.IsPredicted(model)
	return predicted[model] ~= nil
end

return KillPredict
