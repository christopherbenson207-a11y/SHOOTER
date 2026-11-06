-- Third-person guns (campaign, 4 Nov 2026; the block from the zombies GunClient). GunServer puts the gun in every
-- character's hands as character.WorldGun (held in front of the chest by GunRoot.GunJoint). Here every other player's
-- arms reach its RightGrip and LeftGrip (two-bone IK on the shoulders and elbows, after the animator has posed the
-- frame). Someone who is down, bandaging, inside, being eaten or dead lets go and the gun is hidden. Your own world gun
-- is always hidden (you see the viewmodel).
--
-- 5 Nov 2026:
--  * Player avatars use AnimationConstraints (the R15 joint upgrade), not Motor6Ds. The old code took Motor6Ds only,
--    so on every real player the arms were never solved and the gun floated in front of them. A joint is now read
--    the same way for both: C0/C1 are the Motor6D's, or the constraint's Attachment0/Attachment1 frames.
--  * Weapon animations (GameConfig.Squad.Anims): your own character plays the hold sway (it replicates, once per
--    spawn). Someone else's recoil plays here only, on their character, when their shot arrives (ShotFx), so it
--    costs no network however fast the gun fires.
--  * Pack guns (WorldGun "Pack" attribute; GunServer hangs them from the RightHand): no IK. Their upper-body clips
--    (Shared.PackAnims) play here on the other player's character: equip on a gun change, idle or run by speed,
--    reload from the character's "Reload" attribute (fitted to the gun's reload time), fire on ShotFx.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PackAnims = nil
do
	local m = Shared:WaitForChild("PackAnims", 5)
	local ok, mod = pcall(require, m)
	PackAnims = if m and ok and type(mod) == "table" then mod else {}
end

local player = Players.LocalPlayer
local poses = {} -- [character] = pose
local packs = {} -- [character] = pack anim state
local LET_GO = { "Downed", "Bandaging", "Inside", "Devoured", "Dead" }
local ANIMS = (GameConfig.Squad and GameConfig.Squad.Anims) or {}
local RUN_SPEED = 19 -- walk is 16, sprint 23
local LOCO_PRIORITY = Enum.AnimationPriority.Action2
local ACTION_PRIORITY = Enum.AnimationPriority.Action3

local function solveArm(origin, target, a, b)
	local localized = origin:PointToObjectSpace(target)
	local unit = localized.Unit
	local c = localized.Magnitude
	local axis = Vector3.new(0, 0, -1):Cross(unit)
	local angle = math.acos(math.clamp(-unit.Z, -1, 1))
	local plane = if axis.Magnitude > 1e-4 then origin * CFrame.fromAxisAngle(axis.Unit, angle) else origin
	if c < math.abs(a - b) then
		return plane, -math.pi / 2, math.pi
	elseif c > a + b then
		return plane, math.pi / 2, 0
	end
	local a1 = -math.acos(math.clamp((-(b * b) + a * a + c * c) / (2 * a * c), -1, 1))
	local a2 = math.acos(math.clamp((b * b - a * a + c * c) / (2 * b * c), -1, 1))
	return plane, a1 + math.pi / 2, a2 - a1
end

local function setGunVisible(holder, visible)
	local k = if visible then 0 else 1
	for _, d in holder:GetDescendants() do
		if d:IsA("BasePart") and d.LocalTransparencyModifier ~= k then
			d.LocalTransparencyModifier = k
		end
	end
end

local function readJoint(inst)
	if not inst then
		return nil
	end
	if inst:IsA("Motor6D") then
		return { Inst = inst, C0 = inst.C0, C1 = inst.C1, Motor = true }
	elseif inst:IsA("AnimationConstraint") and inst.Attachment0 and inst.Attachment1 then
		return { Inst = inst, C0 = inst.Attachment0.CFrame, C1 = inst.Attachment1.CFrame, Motor = false }
	end
	return nil
end

local function release(pose)
	for _, arm in pose.Arms do
		if arm.Shoulder.Inst.Parent then
			if arm.Shoulder.Motor then
				arm.Shoulder.Inst.C0 = arm.Shoulder.C0
				arm.Elbow.Inst.C0 = arm.Elbow.C0
			else
				arm.Shoulder.Inst.Transform = CFrame.identity
				arm.Elbow.Inst.Transform = CFrame.identity
			end
		end
	end
	pose.Released = true
end

local function build(character, holder)
	local root = holder:FindFirstChild("GunRoot")
	local joint = root and root:FindFirstChild("GunJoint")
	local torso = joint and joint.Part0
	if not torso then
		return nil
	end
	local pose = { Holder = holder, Torso = torso, Arms = {}, Released = true }
	for side, gripName in { Right = "RightGrip", Left = "LeftGrip" } do
		local upper = character:FindFirstChild(side .. "UpperArm")
		local lower = character:FindFirstChild(side .. "LowerArm")
		local hand = character:FindFirstChild(side .. "Hand")
		local shoulder = readJoint(upper and upper:FindFirstChild(side .. "Shoulder"))
		local elbow = readJoint(lower and lower:FindFirstChild(side .. "Elbow"))
		local wrist = readJoint(hand and hand:FindFirstChild(side .. "Wrist"))
		local grip = root:FindFirstChild(gripName)
		if shoulder and elbow and wrist and grip then
			table.insert(pose.Arms, {
				Shoulder = shoulder,
				Elbow = elbow,
				Wrist = wrist,
				Grip = grip,
				Upper = (shoulder.C1.Position - elbow.C0.Position).Magnitude,
				Lower = (elbow.C1.Position - wrist.C0.Position).Magnitude + wrist.C1.Position.Magnitude * 0.6,
			})
		end
	end
	return pose
end

local function holding(character, holder)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Health > 0 and holder:GetAttribute("Gun")) then
		return false
	end
	if player:GetAttribute("Cutscene") then
		return false
	end
	for _, name in LET_GO do
		if character:GetAttribute(name) then
			return false
		end
	end
	return true
end

-- Pack gun clips -----------------------------------------------------------------------------------------------------

local function packTrack(state, clip, priority, looped)
	if not clip then
		return nil
	end
	local track = state.Tracks[clip.Id]
	if track == nil then
		local hum = state.Character:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			local anim = Instance.new("Animation")
			anim.AnimationId = clip.Id
			local ok, loaded = pcall(animator.LoadAnimation, animator, anim)
			track = if ok then loaded else false
		else
			track = false
		end
		state.Tracks[clip.Id] = track
	end
	if not track then
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

-- Plays clip so it lasts `seconds` (never slower than its own speed unless allowSlow).
local function packPlay(state, clip, seconds, fade, allowSlow)
	local track = packTrack(state, clip, ACTION_PRIORITY, false)
	if not track then
		return nil
	end
	local speed = if seconds and seconds > 0 then clip.Length / seconds else 1
	if not allowSlow then
		speed = math.max(speed, 1)
	end
	track:Play(fade or 0.1, 1, speed)
	return track
end

local function packStopActions(state, fade)
	state.ActionToken += 1
	for _, track in state.Tracks do
		if track and track.Priority == ACTION_PRIORITY and track.IsPlaying then
			track:Stop(fade)
		end
	end
end

local function packStopAll(state)
	state.ActionToken += 1
	for _, track in state.Tracks do
		if track then
			track:Stop(0.2)
		end
	end
	state.Loco = nil
end

local function packReload(state, mark, was)
	local set, gun = state.Set, state.Config
	packStopActions(state, 0.15)
	if mark == "Shells" then
		local timing = gun.ShellReload or {}
		local token = state.ActionToken
		packPlay(state, set.ReloadStart, timing.StartTime, 0.1, true)
		task.delay(timing.StartTime or 0, function()
			if state.ActionToken == token and state.Reload == "Shells" and set.ShellInsert then
				local track = packTrack(state, set.ShellInsert, ACTION_PRIORITY, true)
				if track then
					track:Play(0.05, 1, set.ShellInsert.Length / (timing.ShellTime or set.ShellInsert.Length))
				end
			end
		end)
	elseif type(mark) == "string" and string.sub(mark, 1, 4) == "Mag:" then
		packPlay(state, state.Set.Reload, tonumber(string.sub(mark, 5)), 0.15, true)
	elseif was == "Shells" then
		packPlay(state, set.ReloadEnd, (gun.ShellReload or {}).EndTime, 0.1, false)
	end
end

local function packFire(character, gunName)
	local state = packs[character]
	if not (state and state.Gun == gunName) then
		return
	end
	local set, gun = state.Set, state.Config
	local interval = 60 / (gun.RPM or 600)
	packStopActions(state, 0.05)
	local fireLen = if set.Fire then set.Fire.Length else 0
	local total = fireLen + (if set.Pump then set.Pump.Length else 0)
	local scale = math.max(1, total / interval) -- the whole cycle fits before the next shot
	packPlay(state, set.Fire, fireLen / scale, 0.03, false)
	if set.Pump then
		local token = state.ActionToken
		task.delay(fireLen / scale, function()
			if state.ActionToken == token then
				packPlay(state, set.Pump, set.Pump.Length / scale, 0.05, false)
			end
		end)
	end
end

-- Runs every frame for another player holding a pack gun (or that just stopped holding one).
local function packTick(character, holder, holds)
	local gunName = holder:GetAttribute("Gun")
	local gun = gunName and GameConfig.Guns[gunName]
	-- The knife (6 Nov 2026) keeps its clips in its own GameConfig entry (PackClips): equip, idle, and the slash as
	-- Fire, played on every swing (each swing reaches GunServer as a Fire, so ShotFx arrives even on a miss).
	local set = gunName and (PackAnims[gunName] or (gun and gun.PackClips))
	local state = packs[character]
	if state and (not holds or state.Gun ~= gunName) then
		packStopAll(state)
		packs[character] = nil
		state = nil
	end
	if not (holds and set and gun) then
		return
	end
	if not state then
		state = {
			Character = character,
			Gun = gunName,
			Set = set,
			Config = gun,
			Tracks = {},
			ActionToken = 0,
			Loco = nil,
			Reload = nil,
		}
		packs[character] = state
		packPlay(state, set.Equip, (gun.EquipTime or 0.5) * 2, 0.1, false)
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local v = if root and root:IsA("BasePart") then root.AssemblyLinearVelocity else Vector3.zero
	local loco = if Vector3.new(v.X, 0, v.Z).Magnitude > RUN_SPEED and set.Run then "Run" else "Idle"
	if loco ~= state.Loco then
		local old = state.Loco and set[state.Loco]
		local oldTrack = old and state.Tracks[old.Id]
		if oldTrack then
			oldTrack:Stop(0.25)
		end
		local track = packTrack(state, set[loco], LOCO_PRIORITY, true)
		if track then
			track:Play(0.25)
		end
		state.Loco = loco
	end
	local mark = character:GetAttribute("Reload")
	if mark ~= state.Reload then
		local was = state.Reload
		state.Reload = mark
		packReload(state, mark, was)
	end
end

RunService.PreSimulation:Connect(function()
	local seen = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local holder = character and character:FindFirstChild("WorldGun")
		if not holder then
			continue
		end
		if other == player then
			setGunVisible(holder, false)
			continue
		end
		seen[character] = true
		if holder:GetAttribute("Pack") or packs[character] then
			-- Pack gun: the clips pose the arms and the gun. Drop any IK pose left from a chest-held gun.
			local old = poses[character]
			if old then
				if not old.Released then
					release(old)
				end
				poses[character] = nil
			end
			local holds = holding(character, holder) and holder:GetAttribute("Pack") == true
			packTick(character, holder, holds)
			if holder:GetAttribute("Pack") then
				setGunVisible(holder, holds)
				continue
			end
		end
		local pose = poses[character]
		if pose and (pose.Holder ~= holder or not pose.Torso.Parent or (pose.Arms[1] and not pose.Arms[1].Shoulder.Inst.Parent)) then
			release(pose)
			pose = nil
		end
		if not pose then
			pose = build(character, holder)
			poses[character] = pose
			if not pose then
				continue
			end
		end
		if not holding(character, holder) then
			if not pose.Released then
				release(pose)
			end
			setGunVisible(holder, false)
			continue
		end
		if pose.Released then
			pose.Released = false
			setGunVisible(holder, true)
		end
		local torsoCF = pose.Torso.CFrame
		for _, arm in pose.Arms do
			local origin = torsoCF * arm.Shoulder.C0
			local plane, bend1, bend2 = solveArm(origin, arm.Grip.WorldPosition, arm.Upper, arm.Lower)
			local shoulderAt = plane * CFrame.Angles(bend1, 0, 0)
			if arm.Shoulder.Motor then
				arm.Shoulder.Inst.C0 = torsoCF:ToObjectSpace(shoulderAt)
				arm.Elbow.Inst.C0 = arm.Elbow.C0 * CFrame.Angles(bend2, 0, 0)
				arm.Shoulder.Inst.Transform = CFrame.identity
				arm.Elbow.Inst.Transform = CFrame.identity
			else
				-- a constraint's frame stays at its attachment: the bend goes in its Transform
				arm.Shoulder.Inst.Transform = origin:ToObjectSpace(shoulderAt)
				arm.Elbow.Inst.Transform = CFrame.Angles(bend2, 0, 0)
			end
			arm.Wrist.Inst.Transform = CFrame.identity
		end
	end
	for character in poses do
		if not seen[character] then
			poses[character] = nil
		end
	end
	for character, state in packs do
		if not seen[character] then
			packStopAll(state)
			packs[character] = nil
		end
	end
end)

-- Weapon animations ------------------------------------------------------------------------------------------------

local function loadOn(character, name)
	local id = ANIMS[name]
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(animator.LoadAnimation, animator, anim)
	return if ok then track else nil
end

-- Your own hold sway: played on your character, so everyone else sees it.
local function onCharacter(character)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum or not hum:WaitForChild("Animator", 5) then
		return
	end
	local hold = loadOn(character, "Hold")
	if hold then
		hold.Looped = true
		hold:Play(0.3)
	end
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- Someone else's recoil, played here only.
local observed = setmetatable({}, { __mode = "k" }) -- [character] = { [name] = track }
local shotFx = Remotes:WaitForChild("ShotFx", 10)
if shotFx then
	shotFx.OnClientEvent:Connect(function(shooter, _, shooterGun)
		if typeof(shooter) ~= "Instance" or not shooter:IsA("Player") or shooter == player then
			return
		end
		local character = shooter.Character
		local holder = character and character:FindFirstChild("WorldGun")
		if not holder then
			return
		end
		if holder:GetAttribute("Pack") then
			packFire(character, shooterGun)
			return
		end
		local gun = GameConfig.Guns[shooterGun]
		local hold = gun and gun.Hold
		if hold == "Axe" or (gun and gun.Melee) then
			return -- the axe swings on the swinger's own body (GunClient plays Squad.Anims.AxeSwing; it replicates)
		end
		local name = if hold == "Pistol" then "FirePistol" else "FireRifle"
		local set = observed[character]
		if not set then
			set = {}
			observed[character] = set
		end
		local track = set[name]
		if track == nil then
			track = loadOn(character, name) or false
			set[name] = track
		end
		if track then
			track:Play(0)
		end
	end)
end
