-- WAR soldiers on this client (ServerStorage.Modules.Soldier, horror-shooter/war/WAR-V2-CONTRACTS.md).
-- On the server a soldier is two invisible parts; this draws its body: a copy of
-- ReplicatedStorage.WarRigs[Rig] (a trimmed SoldierRigs operator, about 26 parts, nothing collides
-- or stops a ray) that follows the hitbox, eased between the server's 20 writes a second.
--   Legs: the plain R15 idle, walk and run, blended by how fast the body moves. Crouched (Stance) and
--   still it kneels; crouched and moving, the knees bend over the walk.
--   Rifle and arms (v3, 3 Nov): the rifle rides a joint of its own on the chest and both hands hold it
--   with IK (IKControl), so it can be carried. Shouldered and level when the soldier is up to fire
--   (Phase Exposing / Exposed), has a foe in sight (Alert) or has just fired; low when walking; across
--   the chest when running; ready otherwise. Every shot it fires (Remotes.ShotFx) kicks it back.
--   Reloading (seconds) swaps the magazine with the left hand; Throwing winds up a grenade with the
--   right. A hit (the hitbox Humanoid's health) flinches it. The waist leans to AimPitch, into a run
--   and back with recoil; the head drops to the sights, and looks round when nothing is about.
--   Once Dead, it falls where it stood and lies there (Battle.BodyTime; sooner, and fewer at once,
--   when this client's frame rate drops under Battle.Bodies.LagFps), then fades.
-- Detail by distance from the camera: hands on the rifle within NEAR; past it the rifle and arms keep
-- the template's own carry; past FAR the body is put away (the hitbox still takes hits) and comes back
-- when the camera nears again.
-- Pack rifle (5 Nov 2026): when ReplicatedStorage.Assets.PackGuns has the AK, a soldier holds that
-- instead, hung from the right hand like a player's pack gun (GunServer), and its arms play the pack's
-- upper-body clips (Shared.PackAnims.AK): idle, run when it runs, the reload over the server's
-- Reloading seconds, a shot on every ShotFx. No arm IK then; the legs, kneel, waist aim, head and
-- ragdoll are unchanged. Without the folder, the IK rifle below is used.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RIGS = ReplicatedStorage:WaitForChild("WarRigs")
local battle = GameConfig.War and GameConfig.War.Battle or {}
local DROP = (battle.Crouch and battle.Crouch.Drop) or 0.65
local BODY_TIME = battle.BodyTime or 8
local BODIES = battle.Bodies or {}
local NEAR, FAR = 200, 380
local GUN_FAR = 45 -- past this the rifle is drawn as plain blocks
local LOW_GUN_FILL = 0.8 -- a block's share of its mesh's box
local FALL_TIME = 0.5
local WALK_FULL, RUN_FROM, RUN_FULL = 4, 9, 12 -- studs a second
local SHOT_HOLD = 1.4 -- seconds it stays shouldered after its last shot
local THROW_WIND, THROW_OUT, THROW_BACK = 0.6, 0.12, 0.45 -- seconds

local PACK_GUNS = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("PackGuns")
local PACK_GUN = "AK"
local PACK_SET = nil
do
	local m = ReplicatedStorage.Shared:FindFirstChild("PackAnims")
	local ok, mod = pcall(require, m)
	PACK_SET = if m and ok and type(mod) == "table" then mod[PACK_GUN] else nil
end
local PACK_CLIPS = { -- view.Tracks name, clip, priority, looped
	{ "PackIdle", "Idle", Enum.AnimationPriority.Action2, true },
	{ "PackRun", "Run", Enum.AnimationPriority.Action2, true },
	{ "PackReload", "Reload", Enum.AnimationPriority.Action3, false },
	{ "PackFire", "Fire", Enum.AnimationPriority.Action3, false },
}

local ANIMS = {
	Idle = { Id = "rbxassetid://507766388", Priority = Enum.AnimationPriority.Idle },
	Walk = { Id = "rbxassetid://507777826", Priority = Enum.AnimationPriority.Movement },
	Run = { Id = "rbxassetid://507767714", Priority = Enum.AnimationPriority.Movement },
}

-- The kneel: a Transform for each leg joint it bends (GameConfig.War.Battle.Kneel, degrees).
local KNEEL = {}
for name, degrees in battle.Kneel or {} do
	KNEEL[name] = CFrame.Angles(math.rad(degrees), 0, 0)
end
-- The crouched walk: knees bent over the walk (degrees), the body lower by CROUCH_DROP.
local CROUCH_WALK = { LeftHip = 38, RightHip = 38, LeftKnee = -62, RightKnee = -62, LeftAnkle = 24, RightAnkle = 24 }
local CROUCH_DROP = 0.42
-- Arm joints held in the template's own carry while the hands are off IK.
local HOLD = { "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

-- The rigs' rifle is long for their arms (the grip 2.4 studs from the butt, arms 2.2): drawn smaller,
-- about the right hand, so it can be shouldered; and the left hand at most this far ahead of the right.
local GUN_SCALE = 0.7
local SUPPORT_REACH = 0.4
-- Where the rifle sits for each carry, in the chest's space, in units of half the chest's width: the
-- butt (Pos) and the barrel's pitch, yaw and roll (radians). Aim is shouldered under the eye and
-- level, so the waist's AimPitch puts it on the target.
local CARRY = {
	Aim = { Pos = Vector3.new(0.14, 0.6, 0.15), Turn = Vector3.new(0, 0, 0) },
	Ready = { Pos = Vector3.new(0.3, 0.45, 0), Turn = Vector3.new(-0.4, 0.15, 0.1) },
	Low = { Pos = Vector3.new(0.35, 0.35, -0.1), Turn = Vector3.new(-0.6, 0.35, 0.2) },
	Sprint = { Pos = Vector3.new(0.3, 0.3, -0.1), Turn = Vector3.new(-0.75, 0.5, 0.3) },
	Reload = { Pos = Vector3.new(0.25, 0.35, 0), Turn = Vector3.new(0.15, 0.35, 0.6) },
}
-- The left hand's pouch for a fresh magazine, and the right hand's wind-up and release for a throw.
local POUCH = Vector3.new(-0.5, -1, -0.55)
local THROW_BACK_AT = Vector3.new(0.95, 1.35, 0.8)
local THROW_OUT_AT = Vector3.new(0.3, 0.95, -1.7)

local views = {} -- [model] = view
local now = os.clock()

local function joint(body, name)
	local j = body:FindFirstChild(name, true)
	return if j and j:IsA("Motor6D") then j else nil
end

local function approach(a, b, rate, dt)
	return a + (b - a) * (1 - math.exp(-rate * dt))
end

local function smooth(k)
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

-- Along keys ({ time 0-1, CFrame }) at t, eased between them.
local function along(keys, t)
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if t <= b[1] then
			return a[2]:Lerp(b[2], smooth((t - a[1]) / math.max(b[1] - a[1], 1e-3)))
		end
	end
	return keys[#keys][2]
end

-- The rifle (a model Gun welded to the right hand) moves onto a joint off the chest, and each arm gets
-- an IK chain onto its grip. False if the template has no rifle to hold.
local function rigRifle(view, body, hum)
	local torso = body:FindFirstChild("UpperTorso")
	local gun = body:FindFirstChild("Gun")
	local rh, lh = body:FindFirstChild("RightHand"), body:FindFirstChild("LeftHand")
	local ru, lu = body:FindFirstChild("RightUpperArm"), body:FindFirstChild("LeftUpperArm")
	local shoulder = joint(body, "RightShoulder")
	if not (torso and gun and gun:IsA("Model") and rh and lh and ru and lu and shoulder and hum) then
		return false
	end
	local parts = {}
	for _, d in gun:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local base = gun.PrimaryPart or gun:FindFirstChild("Upper") or parts[1]
	if not base then
		return false
	end
	-- Smaller about the right hand; the pivot keeps the rifle's own axes, which its box is measured on.
	local pivot = gun.WorldPivot
	gun.WorldPivot = rh.CFrame
	gun:ScaleTo(gun:GetScale() * GUN_SCALE)
	gun.WorldPivot = pivot.Rotation + rh.Position
	-- The bore: the long axis of the rifle's box, toward the muzzle; up: away from the magazine.
	local boxCF, size = gun:GetBoundingBox()
	local axes = { { boxCF.RightVector, size.X }, { boxCF.UpVector, size.Y }, { boxCF.LookVector, size.Z } }
	table.sort(axes, function(a, b)
		return a[2] > b[2]
	end)
	local muzzle = gun:FindFirstChild("Muzzle", true)
	local tip = if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else base.Position
	local bore = axes[1][1]
	if (tip - boxCF.Position):Dot(bore) < 0 then
		bore = -bore
	end
	local up = axes[2][1]
	local mag = gun:FindFirstChild("Mag")
	if (mag and (mag.Position - boxCF.Position):Dot(up) > 0) or (not mag and up.Y < 0) then
		up = -up
	end
	local right = bore:Cross(up).Unit
	up = right:Cross(bore).Unit
	local frame = CFrame.fromMatrix(boxCF.Position - bore * axes[1][2] / 2, right, up)

	-- Every piece welded to the base piece instead of the hand; the base on the chest joint.
	local baseCF = base.CFrame
	view.GripR = baseCF:ToObjectSpace(rh.CFrame)
	-- The left hand under the handguard, near enough in front of the right for these arms.
	local r = frame:PointToObjectSpace(rh.Position)
	local l = frame:PointToObjectSpace(lh.Position)
	l = Vector3.new(math.clamp(l.X, -0.15, 0.15), math.min(l.Y, r.Y + 0.15), math.max(l.Z, r.Z - SUPPORT_REACH))
	view.GripL = baseCF:ToObjectSpace(frame * CFrame.new(l) * frame:ToObjectSpace(lh.CFrame).Rotation)
	if mag then
		local below = baseCF:VectorToObjectSpace(-up) * mag.Size.Magnitude * 0.4
		view.MagGrip = CFrame.new(baseCF:PointToObjectSpace(mag.Position) + below) * view.GripL.Rotation
		view.Mag = mag
	end
	for _, d in gun:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	for _, p in parts do
		p.Anchored = false
		p.Massless = true
		if p ~= base then
			local w = Instance.new("Weld")
			w.Part0, w.Part1 = base, p
			w.C0 = baseCF:ToObjectSpace(p.CFrame)
			w.Parent = p
		end
	end
	local mount = Instance.new("Motor6D")
	mount.Name = "RifleMount"
	mount.Part0, mount.Part1 = torso, base
	mount.C0 = torso.CFrame:ToObjectSpace(baseCF)
	mount.Parent = torso
	view.Mount = mount
	view.MountInv = mount.C0:Inverse()
	view.FrameInv = baseCF:ToObjectSpace(frame):Inverse()

	local u = math.abs(shoulder.C0.X)
	view.Unit = u
	view.Carry = {}
	for name, c in CARRY do
		view.Carry[name] = CFrame.new(c.Pos * u) * CFrame.fromEulerAnglesYXZ(c.Turn.X, c.Turn.Y, c.Turn.Z)
	end
	view.Pouch = POUCH * u
	view.ThrowBack = THROW_BACK_AT * u
	view.ThrowOut = THROW_OUT_AT * u

	local function arm(side, upper, hand, pole)
		local target = Instance.new("Attachment")
		target.Name = side .. "Grip"
		target.Parent = torso
		local elbow = Instance.new("Attachment")
		elbow.Name = side .. "Elbow"
		elbow.Position = pole * u
		elbow.Parent = torso
		local ik = Instance.new("IKControl")
		ik.Name = side .. "Hand"
		-- The right hand takes the grip's angle; the left only its place, so its wrist stays natural.
		ik.Type = if side == "Right" then Enum.IKControlType.Transform else Enum.IKControlType.Position
		ik.ChainRoot = upper
		ik.EndEffector = hand
		ik.Target = target
		ik.Pole = elbow
		ik.SmoothTime = 0
		ik.Parent = hum
		return ik, target
	end
	view.IkR, view.TargetR = arm("Right", ru, rh, Vector3.new(1.8, -1.5, 0.4))
	view.IkL, view.TargetL = arm("Left", lu, lh, Vector3.new(-1.5, -1.6, -0.4))
	view.Hands = true

	-- The grenade in the right hand during a throw.
	local nade = Instance.new("Part")
	nade.Name = "Grenade"
	nade.Shape = Enum.PartType.Ball
	nade.Size = Vector3.one * 0.55 * u
	nade.Color = Color3.fromRGB(52, 62, 40)
	nade.Material = Enum.Material.Metal
	nade.CanCollide, nade.CanQuery, nade.CanTouch, nade.Massless = false, false, false, true
	nade.Transparency = 1
	nade.CFrame = rh.CFrame
	local w = Instance.new("Weld")
	w.Part0, w.Part1 = rh, nade
	w.C0 = CFrame.new(0, -0.35 * u, 0)
	w.Parent = nade
	nade.Parent = body
	view.Nade = nade
	return true
end

-- The pack rifle in the right hand (see the header). False if there is no pack rifle or no hand.
local function rigPack(view, body, scale)
	local source = PACK_GUNS and PACK_GUNS:FindFirstChild(PACK_GUN)
	local rh = body:FindFirstChild("RightHand")
	if not (PACK_SET and source and source.PrimaryPart and rh) then
		return false
	end
	local old = body:FindFirstChild("Gun")
	if old then
		old:Destroy()
	end
	local gun = source:Clone()
	gun.Name = "Gun"
	for _, d in gun:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.Massless = true
			d.CastShadow = d.Size.Magnitude > 0.3
		end
	end
	if scale ~= 1 then
		gun:ScaleTo(gun:GetScale() * scale)
	end
	local base = gun.PrimaryPart
	local c0 = source:GetAttribute("HandC0") or CFrame.identity
	local c1 = source:GetAttribute("HandC1") or CFrame.identity
	local grip = Instance.new("Motor6D")
	grip.Name = "PackGrip"
	grip.Part0, grip.Part1 = rh, base -- Part1 keeps the pack's part name, which the clips key
	grip.C0 = c0.Rotation + c0.Position * scale
	grip.C1 = c1.Rotation + c1.Position * scale
	grip.Parent = base
	gun:PivotTo(rh.CFrame * grip.C0 * grip.C1:Inverse() * base.CFrame:ToObjectSpace(gun:GetPivot()))
	gun.Parent = body
	view.Pack = PACK_SET
	view.Mount = grip -- ragdoll() destroys it: the rifle drops
	return true
end

-- The pack clips for this frame: idle or run, the reload while the server's Reloading lasts.
local function posePack(view, dt)
	local reload = view.Model:GetAttribute("Reloading")
	local track = view.Tracks.PackReload
	if type(reload) == "number" and reload > 0 then
		if not view.Reloaded then
			view.Reloaded = true
			if track and view.Pack.Reload then
				track:Play(0.15, 1, view.Pack.Reload.Length / reload)
			end
		end
	elseif view.Reloaded then
		view.Reloaded = nil
		if track and track.IsPlaying then
			track:Stop(0.2)
		end
	end
	view.Kick = approach(view.Kick, 0, 12, dt)
	local sprint = view.Speed >= RUN_FROM
	view.WSprint = approach(view.WSprint, if sprint then 1 else 0, 6, dt)
	local loco = if sprint then "PackRun" else "PackIdle"
	if loco ~= view.PackLoco then
		local old = view.PackLoco and view.Tracks[view.PackLoco]
		if old then
			old:Stop(0.25)
		end
		local track = view.Tracks[loco]
		if track then
			track:Play(0.25)
		end
		view.PackLoco = loco
	end
end

local function build(model)
	if views[model] or not model:GetAttribute("LightBody") then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not root or not model.Parent then
		return
	end
	local template = RIGS:FindFirstChild(model:GetAttribute("Rig") or "") or RIGS:FindFirstChildWhichIsA("Model")
	if not template then
		return
	end
	local body = template:Clone()
	body.Name = "View"
	local scale = model:GetAttribute("Scale") or 1
	if scale ~= 1 then
		body:ScaleTo(scale)
	end
	local bodyRoot = body.PrimaryPart
	local hum = body:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if hum then
		-- Nothing here is simulated: the body only follows the hitbox.
		hum.EvaluateStateMachine = false
	end
	local view = {
		Model = model,
		Root = root,
		Body = body,
		BodyRoot = bodyRoot,
		Lift = (template:GetAttribute("FeetToRoot") or 3) * scale,
		Stride = (template:GetAttribute("FeetToRoot") or 3) / 3,
		Scale = scale,
		Tracks = {},
		Hold = {},
		Legs = {},
		Bend = {},
		Waist = joint(body, "Waist"),
		Neck = joint(body, "Neck"),
		Pitch = 0,
		Crouch = 0,
		CrouchWalk = 0,
		Speed = 0,
		Weights = {},
		Shown = false,
		Seed = math.random() * 100,
		WAim = 0,
		WLow = 0,
		WSprint = 0,
		Kick = 0,
		KickYaw = 0,
		ShotAt = -math.huge,
		Flinch = 0,
		FlinchSide = 1,
		Twist = 0,
		Conns = {},
	}
	for _, name in HOLD do
		local j = joint(body, name)
		if j then
			table.insert(view.Hold, j)
		end
	end
	for name, pose in KNEEL do
		local j = joint(body, name)
		if j then
			table.insert(view.Legs, { Joint = j, Pose = pose })
		end
	end
	for name, degrees in CROUCH_WALK do
		local j = joint(body, name)
		if j then
			table.insert(view.Bend, { Joint = j, Angle = math.rad(degrees) })
		end
	end
	local packed, packErr = pcall(rigPack, view, body, scale)
	if not packed then
		warn("SoldierView: pack rifle: " .. tostring(packErr))
	end
	if not view.Pack then
		local ok, err = pcall(rigRifle, view, body, hum)
		if not ok then
			warn("SoldierView: rifle: " .. tostring(err))
		end
	end
	-- Detail that is only drawn up close (studs, at a 70 degree view). The rifle's meshes cost about
	-- 45k triangles a soldier; past GUN_FAR each one gives way to a plain block of its own size and
	-- colour. The magazine stays: it is cheap and the reload drives it.
	view.Lod = {}
	local gun = body:FindFirstChild("Gun")
	if gun then
		for _, d in gun:GetDescendants() do
			if d:IsA("MeshPart") and d ~= view.Mag and d.Name ~= "Mag" then
				local box = Instance.new("Part")
				box.Name = "Low" .. d.Name
				box.Size = d.Size * LOW_GUN_FILL
				box.CFrame = d.CFrame
				box.Color = d.Color
				box.Material = d.Material
				box.CanCollide, box.CanQuery, box.CanTouch = false, false, false
				box.Massless = true
				box.CastShadow = false
				box.LocalTransparencyModifier = 1
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = d, box
				weld.Parent = box
				box.Parent = d.Parent
				table.insert(view.Lod, { Part = d, Far = GUN_FAR, Hidden = false })
				table.insert(view.Lod, { Part = box, Far = GUN_FAR, Hidden = true, Low = true })
			end
		end
	end
	for _, d in body:GetDescendants() do
		local far = d:IsA("BasePart") and not (gun and d:IsDescendantOf(gun)) and d:GetAttribute("LodFar")
		if typeof(far) == "number" then
			table.insert(view.Lod, { Part = d, Far = far, Hidden = false })
		end
	end
	-- The tracks load in show(), once the body is in the world: a track loaded on an Animator
	-- outside the DataModel never gets its clip (Length stays 0), so the legs never move.
	view.Animator = animator
	-- A hit: a flinch, to one side or the other.
	local serverHum = model:FindFirstChildOfClass("Humanoid")
	if serverHum then
		local last = serverHum.Health
		table.insert(view.Conns, serverHum.HealthChanged:Connect(function(h)
			if h < last and h > 0 then
				view.Flinch = math.min(1, view.Flinch + 0.7)
				view.FlinchSide = if math.random() < 0.5 then -1 else 1
			end
			last = h
		end))
	end
	view.CF = root.CFrame * CFrame.new(0, -root.Size.Y / 2 + view.Lift, 0)
	bodyRoot.CFrame = view.CF
	views[model] = view
end

-- Load the idle, walk and run on the body's Animator. Only call this while the body is in the
-- world (see build).
local function loadTracks(view)
	local animator = view.Animator
	if view.TracksLoaded or not animator or not animator:IsDescendantOf(workspace) then
		return
	end
	view.TracksLoaded = true
	for name, a in ANIMS do
		local anim = Instance.new("Animation")
		anim.AnimationId = a.Id
		local loaded, track = pcall(animator.LoadAnimation, animator, anim)
		if loaded and track then
			track.Priority = a.Priority
			track.Looped = true
			view.Tracks[name] = track
		end
	end
	if view.Pack then
		for _, c in PACK_CLIPS do
			local clip = view.Pack[c[2]]
			if clip then
				local anim = Instance.new("Animation")
				anim.AnimationId = clip.Id
				local loaded, track = pcall(animator.LoadAnimation, animator, anim)
				if loaded and track then
					track.Priority = c[3]
					track.Looped = c[4]
					view.Tracks[c[1]] = track
				end
			end
		end
	end
end

local function show(view, on)
	if view.Shown == on then
		return
	end
	view.Shown = on
	if on and view.Fallen then
		view.Body.Parent = view.Model
	elseif on then
		view.Body.Parent = view.Model
		loadTracks(view)
		view.PackLoco = nil -- posePack starts the pack idle or run again
		local idle = view.Tracks.Idle
		if idle and not idle.IsPlaying then
			idle:Play(0.1)
		end
		for _, name in { "Walk", "Run" } do
			local t = view.Tracks[name]
			if t and not t.IsPlaying then
				t:Play(0.1, 0.001)
				view.Weights[name] = 0
			end
		end
	else
		view.Body.Parent = nil
	end
end

local function drop(model)
	local view = views[model]
	if view then
		views[model] = nil
		for _, c in view.Conns do
			c:Disconnect()
		end
		view.Body:Destroy()
	end
end

-- Down (4 Nov 2026): the body goes limp (a real ragdoll on this client, thrown away from where the
-- killing shot came from: the server's FallFrom), the rifle drops out of its hands, blood spreads
-- under it, and once it has settled it is frozen in place. If anything fails it tips over stiffly.
local RAG_SWING, RAG_TWIST = 60, 45
local LIMBS = {
	Head = true, UpperTorso = true, LowerTorso = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}
local BLOOD = Color3.fromRGB(62, 8, 8)

local function bloodPool(view, torso)
	task.delay(0.9, function()
		if views[view.Model] ~= view or not torso.Parent then
			return
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { view.Model }
		params.RespectCanCollide = true
		local hit = workspace:Raycast(torso.Position, Vector3.new(0, -6, 0), params)
		if not hit then
			return
		end
		local pool = Instance.new("Part")
		pool.Name = "Blood"
		pool.Shape = Enum.PartType.Cylinder
		pool.Anchored, pool.CanCollide, pool.CanQuery, pool.CanTouch = true, false, false, false
		pool.Material = Enum.Material.Glass
		pool.Color = BLOOD
		pool.Reflectance = 0.05
		local up = CFrame.lookAt(hit.Position, hit.Position + hit.Normal) * CFrame.Angles(0, math.rad(90), 0)
		pool.CFrame = up * CFrame.new(0.02, 0, 0)
		pool.Size = Vector3.new(0.05, 0.6, 0.6)
		pool.Parent = view.Body
		local r = 3.2 + math.random() * 1.6
		for i = 1, 30 do
			if not pool.Parent then
				return
			end
			local k = 1 - (1 - i / 30) ^ 2
			pool.Size = Vector3.new(0.05, 0.6 + r * k, 0.6 + r * 0.8 * k)
			task.wait(0.1)
		end
	end)
end

local function ragdoll(view)
	local body, root = view.Body, view.BodyRoot
	for _, d in body:GetDescendants() do
		if d:IsA("IKControl") then
			d.Enabled = false
		end
	end
	local gun = body:FindFirstChild("Gun")
	if view.Mount then
		view.Mount:Destroy() -- the rifle drops
		view.Mount = nil
	end
	for _, j in body:GetDescendants() do
		if j:IsA("Motor6D") and j.Part0 and j.Part1 then
			if j.Part0 == root or j.Part1 == root then
				j:Destroy()
			else
				local a0 = Instance.new("Attachment")
				a0.CFrame = j.C0
				a0.Parent = j.Part0
				local a1 = Instance.new("Attachment")
				a1.CFrame = j.C1
				a1.Parent = j.Part1
				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0, socket.Attachment1 = a0, a1
				socket.LimitsEnabled = true
				socket.UpperAngle = RAG_SWING
				socket.TwistLimitsEnabled = true
				socket.TwistLowerAngle, socket.TwistUpperAngle = -RAG_TWIST, RAG_TWIST
				socket.Parent = j.Part0
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0, nc.Part1 = j.Part0, j.Part1
				nc.Parent = j.Part0
				j:Destroy()
			end
		end
	end
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			p.Anchored = false
			p.CanQuery, p.CanTouch = false, false
			local gunPart = gun ~= nil and p:IsDescendantOf(gun)
			p.CanCollide = LIMBS[p.Name] == true or gunPart
			if LIMBS[p.Name] or gunPart then
				p.Massless = false
			end
		end
	end
	root.Anchored, root.CanCollide = true, false
	-- thrown away from the shot, a little up, and spun
	local torso = body:FindFirstChild("UpperTorso")
	if torso then
		local from = view.Model:GetAttribute("FallFrom")
		local away = if typeof(from) == "Vector3" then (torso.Position - from) * Vector3.new(1, 0, 1) else -view.CF.LookVector
		away = if away.Magnitude > 0.01 then away.Unit else -view.CF.LookVector
		local push = away * (9 + math.random() * 5) + Vector3.new(0, 4, 0)
		for _, p in body:GetDescendants() do
			if p:IsA("BasePart") and LIMBS[p.Name] then
				p.AssemblyLinearVelocity = push * (if p == torso or p.Name == "Head" then 1.15 else 0.8)
			end
		end
		torso.AssemblyAngularVelocity = away:Cross(Vector3.yAxis) * -7
		bloodPool(view, torso)
	end
	view.Ragdoll = true
	-- settled: freeze it (40 limp bodies tumbling forever is wasted physics). A body that came to rest
	-- sitting or kneeling (against a wall, on a step) is tipped over first, so every corpse reads as dead.
	local function settle(tries)
		if views[view.Model] ~= view then
			return
		end
		if torso and torso.Parent and not torso.Anchored and torso.CFrame.UpVector.Y > 0.6 and tries < 3 then
			local back = -torso.CFrame.LookVector * Vector3.new(1, 0, 1)
			back = if back.Magnitude > 0.01 then back.Unit else Vector3.xAxis
			torso.AssemblyLinearVelocity += back * 7 + Vector3.new(0, 2, 0)
			torso.AssemblyAngularVelocity = back:Cross(Vector3.yAxis) * -8
			task.delay(1.2, settle, tries + 1)
			return
		end
		for _, p in body:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
	end
	task.delay(3, settle, 0)
end

local function fall(view)
	view.Fallen = os.clock()
	for _, t in view.Tracks do
		t:Stop(0)
	end
	if view.Nade then
		view.Nade.Transparency = 1
	end
	for _, j in view.Body:GetDescendants() do
		if j:IsA("Motor6D") then
			j.Transform = CFrame.identity
		end
	end
end

-- Limp once it is on screen (a body that died out of view goes limp when the camera nears).
local function limp(view)
	if view.Ragdoll or view.RagTried then
		return
	end
	view.RagTried = true
	local ok, err = pcall(ragdoll, view)
	if not ok then
		warn("SoldierView: ragdoll: " .. tostring(err))
	end
end

-- The body fades out and goes (the server's model may lie on a while; nothing draws it here).
local function fade(view)
	view.Fading = true
	task.spawn(function()
		for i = 1, 10 do
			if views[view.Model] ~= view then
				return
			end
			for _, d in view.Body:GetDescendants() do
				-- Parts the distance detail has hidden stay hidden.
				if (d:IsA("BasePart") or d:IsA("Decal")) and d.LocalTransparencyModifier < 1 then
					d.LocalTransparencyModifier = i / 10
				end
			end
			task.wait(0.08)
		end
		if views[view.Model] == view then
			drop(view.Model)
		end
	end)
end

-- This client's frame rate (smoothed), and once a second the bodies past their time, or over the
-- cap, oldest first, fade.
local fps = 60
RunService.Heartbeat:Connect(function(dt)
	fps += (1 / math.max(dt, 1 / 240) - fps) * math.min(dt * 2, 1)
end)
task.spawn(function()
	while true do
		task.wait(1)
		local lag = fps < (BODIES.LagFps or 40)
		local life = if lag then BODIES.LagTime or 45 else BODY_TIME
		local cap = if lag then BODIES.LagCap or 15 else BODIES.Cap or 40
		local fallen = {}
		for _, view in views do
			if view.Fallen and not view.Fading then
				table.insert(fallen, view)
			end
		end
		table.sort(fallen, function(a, b)
			return a.Fallen < b.Fallen
		end)
		local now = os.clock()
		for i, view in fallen do
			if now - view.Fallen > life or #fallen - i >= cap then
				fade(view)
			end
		end
	end
end)

-- Hands on the rifle or off: off, the rifle and arms keep the template's own carry.
local function setHands(view, on)
	if view.Hands == on or not view.IkR then
		return
	end
	view.Hands = on
	view.IkR.Enabled = on
	view.IkL.Enabled = on
	if not on and view.Mount then
		view.Mount.Transform = CFrame.identity
	end
end

local function setWeight(view, name, w, rate)
	local t = view.Tracks[name]
	if not t then
		return
	end
	if math.abs(w - (view.Weights[name] or -1)) > 0.05 then
		view.Weights[name] = w
		t:AdjustWeight(math.max(w, 0.001), 0.15)
	end
	t:AdjustSpeed(rate)
end

-- The rifle and the hands for this frame, before the animator runs the IK.
local function poseRifle(view, dt)
	local model = view.Model
	local phase = model:GetAttribute("Phase")
	local reloading = view.ReloadAt ~= nil
	local throwing = view.ThrowAt ~= nil
	local fired = now - view.ShotAt < SHOT_HOLD
	local up = phase == "Exposing" or phase == "Exposed"
	local aim = not reloading and not throwing and phase ~= "Gun"
		and (up or fired or (model:GetAttribute("Alert") and phase ~= "Hidden" and view.Speed < RUN_FROM))
	local sprint = not aim and view.Speed >= RUN_FROM
	local low = not aim and not sprint and (view.Speed > 1.5 or phase == "Gun" or throwing)
	view.WAim = approach(view.WAim, if aim then 1 else 0, if aim then 14 else 7, dt)
	view.WLow = approach(view.WLow, if low then 1 else 0, 6, dt)
	view.WSprint = approach(view.WSprint, if sprint then 1 else 0, 6, dt)
	local c = view.Carry
	local gun = c.Ready:Lerp(c.Low, view.WLow):Lerp(c.Sprint, view.WSprint):Lerp(c.Aim, view.WAim)
	local t = 0
	if reloading then
		t = (now - view.ReloadAt) / view.ReloadLen
		if t >= 1 then
			view.ReloadAt, t, reloading = nil, 1, false
		end
		view.ReloadEnv = math.clamp(math.min(t / 0.12, (1 - t) / 0.15), 0, 1)
		gun = gun:Lerp(c.Reload, view.ReloadEnv)
	else
		view.ReloadEnv = 0
	end
	view.Kick = approach(view.Kick, 0, 12, dt)
	if view.Kick > 0.01 then
		local u = view.Unit
		gun = gun * CFrame.new(0, 0.02 * view.Kick * u, 0.18 * view.Kick * u) * CFrame.Angles(0.07 * view.Kick, view.KickYaw * view.Kick, 0)
	end
	local base = gun * view.FrameInv
	view.MountT = view.MountInv * base
	view.Mount.Transform = view.MountT

	local right = base * view.GripR
	local left = base * view.GripL
	if reloading and view.MagGrip then
		local magHand = base * view.MagGrip
		local pouch = CFrame.new(view.Pouch) * left.Rotation
		left = along({
			{ 0, left },
			{ 0.15, magHand },
			{ 0.3, pouch },
			{ 0.55, pouch },
			{ 0.72, magHand },
			{ 0.8, magHand * CFrame.new(0, 0.15 * view.Unit, 0) },
			{ 1, left },
		}, t)
		view.Mag.LocalTransparencyModifier = if t > 0.17 and t < 0.6 then 1 else 0
	elseif view.Mag and view.Mag.LocalTransparencyModifier > 0 and not view.Fallen then
		view.Mag.LocalTransparencyModifier = 0
	end
	view.Twist = 0
	if throwing then
		local back = CFrame.new(view.ThrowBack) * right.Rotation
		local out = CFrame.new(view.ThrowOut) * right.Rotation
		if not view.ReleaseAt then
			local k = smooth((now - view.ThrowAt) / THROW_WIND)
			right = right:Lerp(back, k)
			view.Twist = -0.45 * k
			view.Nade.Transparency = 0
		else
			local r = now - view.ReleaseAt
			if r < THROW_OUT then
				right = back:Lerp(out, r / THROW_OUT)
				view.Twist = -0.45 + 0.8 * (r / THROW_OUT)
			elseif r < THROW_OUT + THROW_BACK then
				local k = smooth((r - THROW_OUT) / THROW_BACK)
				right = out:Lerp(right, k)
				view.Twist = 0.35 * (1 - k)
			else
				view.ThrowAt, view.ReleaseAt = nil, nil
			end
			view.Nade.Transparency = 1
		end
	end
	view.TargetR.CFrame = right
	view.TargetL.CFrame = left
end

-- Reloads and throws start and end with the server's attributes.
local function readActions(view)
	local model = view.Model
	local reload = model:GetAttribute("Reloading")
	if type(reload) == "number" and reload > 0 then
		if not view.ReloadAt and not view.Reloaded then
			view.ReloadAt, view.ReloadLen, view.Reloaded = now, reload, true
		end
	else
		view.Reloaded = nil
	end
	if model:GetAttribute("Throwing") then
		if not view.ThrowAt then
			view.ThrowAt, view.ReleaseAt = now, nil
		end
	elseif view.ThrowAt and not view.ReleaseAt then
		view.ReleaseAt = now
	end
end

local function before(dt)
	now = os.clock()
	for _, view in views do
		if view.Shown and view.Pack and not view.Fallen then
			posePack(view, dt)
		elseif view.Shown and view.Hands and not view.Fallen then
			readActions(view)
			poseRifle(view, dt)
		end
	end
end

local function step(dt)
	now = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local zoom = if cam then cam.FieldOfView / 70 else 1
	local ease = 1 - math.exp(-dt * 14)
	for model, view in views do
		local root = view.Root
		if not model.Parent or not root.Parent then
			drop(model)
			continue
		end
		local dead = model:GetAttribute("Dead")
		if dead and not view.Fallen then
			fall(view)
		end
		local dist = (root.Position - camPos).Magnitude
		show(view, dist < FAR)
		if not view.Shown then
			continue
		end
		if view.Fallen then
			limp(view)
			if view.Ragdoll then
				continue
			end
		end
		setHands(view, dist < NEAR)
		if not view.Fallen then
			-- Zoomed in (a scope), things count as nearer.
			local seen = dist * zoom
			for _, l in view.Lod do
				local hide = (seen > l.Far) ~= (l.Low == true)
				if hide ~= l.Hidden then
					l.Hidden = hide
					l.Part.LocalTransparencyModifier = if hide then 1 else 0
				end
			end
		end
		if view.Hands and view.Mount then
			-- The animator may have reset the rifle's joint; it holds this frame's carry.
			view.Mount.Transform = view.MountT or CFrame.identity
		end
		-- Where the body's root goes: the hitbox's feet, up by the rig's own height, down by the kneel.
		local feet = root.CFrame * CFrame.new(0, -root.Size.Y / 2, 0)
		local low = view.Crouch * DROP + view.CrouchWalk * CROUCH_DROP
		local want = feet * CFrame.new(0, view.Lift - low * view.Scale, 0)
		if view.Ragdoll then
			continue
		end
		if view.Fallen then
			local k = math.clamp((os.clock() - view.Fallen) / FALL_TIME, 0, 1)
			k = 1 - (1 - k) * (1 - k)
			local tip = CFrame.new(0, -view.Lift, 0) * CFrame.Angles(math.rad(84) * k, 0, 0) * CFrame.new(0, view.Lift, 0)
			view.CF = view.CF:Lerp(want, ease)
			view.BodyRoot.CFrame = view.CF * tip
			continue
		end
		local was = view.CF.Position
		view.CF = view.CF:Lerp(want, ease)
		view.BodyRoot.CFrame = view.CF
		local moved = view.CF.Position - was
		local speed = math.sqrt(moved.X * moved.X + moved.Z * moved.Z) / math.max(dt, 1e-3)
		view.Speed += (speed - view.Speed) * math.min(1, dt * 8)

		-- Legs: walk into run by speed, the stride scaled to the rig's legs.
		local run = math.clamp((view.Speed - RUN_FROM) / (RUN_FULL - RUN_FROM), 0, 1)
		local walk = math.clamp(view.Speed / WALK_FULL, 0, 1) * (1 - run)
		local stride = view.Stride
		setWeight(view, "Walk", walk, math.max(view.Speed, 1) / (14 * stride))
		setWeight(view, "Run", run, math.max(view.Speed, 1) / (18 * stride))
		local still = view.Speed < 3
		local crouched = model:GetAttribute("Stance") == "Crouch"
		view.Crouch = approach(view.Crouch, if crouched and still then 1 else 0, 10, dt)
		view.CrouchWalk = approach(view.CrouchWalk, if crouched and not still then 1 else 0, 8, dt)
		if view.Crouch > 0.01 then
			for _, leg in view.Legs do
				leg.Joint.Transform = leg.Joint.Transform:Lerp(leg.Pose, view.Crouch)
			end
		end
		if view.CrouchWalk > 0.01 then
			for _, b in view.Bend do
				b.Joint.Transform = b.Joint.Transform * CFrame.Angles(b.Angle * view.CrouchWalk, 0, 0)
			end
		end

		-- Waist: the aim's pitch, a lean into the run, recoil, a flinch, breath; a twist to throw.
		local pitch = model:GetAttribute("AimPitch") or 0
		view.Pitch = approach(view.Pitch, pitch, 12, dt)
		view.Flinch = approach(view.Flinch, 0, 6, dt)
		local breath = math.sin(now * 1.7 + view.Seed) * 0.018 * (1 - view.WAim * 0.7)
		local lean = -0.14 * view.WSprint - 0.05 * view.WLow
		if view.Waist then
			view.Waist.Transform = view.Waist.Transform
				* CFrame.Angles(view.Pitch + lean + breath + 0.035 * view.Kick - 0.3 * view.Flinch, view.Twist, 0.22 * view.Flinch * view.FlinchSide)
		end
		-- Head: down to the sights when aiming, down at the rifle to reload, else a look round.
		if view.Neck then
			local idle = (1 - view.WAim) * (if model:GetAttribute("Alert") then 0.3 else 1)
			local look = math.sin(now * 0.35 + view.Seed) * 0.35 * idle
			local env = view.ReloadEnv or 0
			view.Neck.Transform = view.Neck.Transform
				* CFrame.Angles(-0.12 * view.WAim - 0.35 * env, look, -0.1 * view.WAim)
		end
		if not view.Hands and not view.Pack then
			for _, j in view.Hold do
				j.Transform = CFrame.identity
			end
		end
	end
end

local function added(model)
	task.spawn(build, model)
end

CollectionService:GetInstanceAddedSignal("Soldier"):Connect(added)
CollectionService:GetInstanceRemovedSignal("Soldier"):Connect(drop)
for _, model in CollectionService:GetTagged("Soldier") do
	added(model)
end

-- A soldier's shot: shouldered at once (the tracer leaves this rifle's muzzle) and held a moment,
-- and the rifle kicks.
Remotes:WaitForChild("ShotFx").OnClientEvent:Connect(function(shooter)
	local view = typeof(shooter) == "Instance" and views[shooter]
	if view then
		view.ShotAt = os.clock()
		view.WAim = math.max(view.WAim, 0.8)
		view.Kick = math.min(view.Kick + 0.8, 1.6)
		view.KickYaw = (math.random() - 0.5) * 0.08
		local fire = view.Pack and view.Tracks.PackFire
		if fire and not view.Fallen then
			fire:Play(0.03)
		end
	end
end)

-- The rifle's carry and the IK targets before the animator runs; the body after it has posed the
-- frame, before it's drawn.
RunService.PreAnimation:Connect(before)
RunService.PreSimulation:Connect(step)
