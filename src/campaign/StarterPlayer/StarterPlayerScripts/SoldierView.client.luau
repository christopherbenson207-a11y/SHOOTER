-- WAR soldiers on this client (ServerStorage.Modules.Soldier, horror-shooter/war/WAR-V2-CONTRACTS.md).
-- On the server a soldier is two invisible parts; this draws its body: a copy of
-- ReplicatedStorage.WarRigs[Rig] (a trimmed SoldierRigs operator, about 26 parts, nothing collides
-- or stops a ray) that follows the hitbox, eased between the server's 20 writes a second. It walks
-- with the plain R15 walk and idle, keeps the rifle-ready arms, leans to AimPitch at the waist,
-- kneels while Stance is Crouch and, once Dead, falls where it stood and fades.
-- Detail by distance from the camera: near, posed every frame; mid, every other frame; past FAR the
-- body is put away (the hitbox still takes hits) and comes back when the camera nears again.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local RIGS = ReplicatedStorage:WaitForChild("WarRigs")
local battle = GameConfig.War and GameConfig.War.Battle or {}
local DROP = (battle.Crouch and battle.Crouch.Drop) or 0.65
local BODY_TIME = battle.BodyTime or 8
local NEAR, FAR = 120, 380
local FALL_TIME = 0.5

local ANIMS = {
	Idle = { Id = "rbxassetid://507766388", Priority = Enum.AnimationPriority.Idle },
	Walk = { Id = "rbxassetid://507777826", Priority = Enum.AnimationPriority.Movement },
}

-- The kneel: a Transform for each leg joint it bends (GameConfig.War.Battle.Kneel, degrees).
local KNEEL = {}
for name, degrees in battle.Kneel or {} do
	KNEEL[name] = CFrame.Angles(math.rad(degrees), 0, 0)
end
-- Arm joints held in the template's rifle-ready pose, so the walk only moves the legs.
local HOLD = { "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

-- Uniforms (GameConfig.War.Dress, the model's attribute Dress): the rig's clothing, textures and
-- gear come off and every region takes the nation's colour; the gun is left alone. A helmet of
-- the nation's shape, built from plain parts, sits on the head. Client-side only, like the body.
local DRESS = GameConfig.War and GameConfig.War.Dress or {}
local REGION = {
	UpperTorso = "Tunic", LeftUpperArm = "Tunic", RightUpperArm = "Tunic",
	LeftLowerArm = "Tunic", RightLowerArm = "Tunic",
	LeftHand = "Skin", RightHand = "Skin", Head = "Skin",
	LowerTorso = "Trousers", LeftUpperLeg = "Trousers", RightUpperLeg = "Trousers",
	LeftLowerLeg = "Lower", RightLowerLeg = "Lower",
	LeftFoot = "Boots", RightFoot = "Boots",
}
local GUN_WORDS = { "gun", "rifle", "weapon", "sniper", "m60", "mp5", "shotgun", "pistol", "muzzle", "barrel", "stock", "scope", "magazine" }

-- True if this part or accessory is (part of) the soldier's weapon.
local function isGun(inst)
	local node = inst
	while node and not node:IsA("Workspace") do
		local name = string.lower(node.Name)
		for _, w in GUN_WORDS do
			if string.find(name, w, 1, true) then
				return true
			end
		end
		if string.match(name, "^ak") or string.match(name, "^m4") or string.match(name, "^m1%a") then
			return true
		end
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
			break
		end
		node = node.Parent
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("Attachment") and (d.Name == "Muzzle" or d.Name == "Grip" or d.Name == "LeftHand") then
			return true
		end
	end
	return false
end

local function helmetPart(head, color, size, offset, mesh, scale)
	local p = Instance.new("Part")
	p.Name = "DressHelmet"
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
	p.Anchored = false
	if mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = mesh
		m.Scale = scale or Vector3.one
		m.Parent = p
	end
	p.CFrame = head.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = head, p
	w.Parent = p
	p.Parent = head
	return p
end

-- The helmet's pieces, sized from the head (h: the head's size).
local function helmet(head, shape, color)
	local h = head.Size
	local top = h.Y * 0.32
	local s = math.max(h.X, h.Z)
	local sphere = Enum.MeshType.Sphere
	local cyl = Enum.MeshType.Cylinder
	local flat = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder lies along X; stand it up
	if shape == "Stahlhelm" then
		helmetPart(head, color, Vector3.new(s * 1.12, h.Y * 0.62, s * 1.18), CFrame.new(0, top, 0.02 * s), sphere)
		-- The flared skirt over the ears and neck.
		helmetPart(head, color, Vector3.new(h.Y * 0.22, s * 1.32, s * 1.38), CFrame.new(0, top - h.Y * 0.2, 0.08 * s) * flat, cyl)
	elseif shape == "Brodie" then
		helmetPart(head, color, Vector3.new(s * 0.98, h.Y * 0.42, s * 1.02), CFrame.new(0, top + h.Y * 0.06, 0), sphere)
		helmetPart(head, color, Vector3.new(h.Y * 0.06, s * 1.7, s * 1.7), CFrame.new(0, top - h.Y * 0.04, 0) * flat, cyl)
	elseif shape == "SSh40" then
		helmetPart(head, color, Vector3.new(s * 1.1, h.Y * 0.7, s * 1.14), CFrame.new(0, top - h.Y * 0.02, 0), sphere)
		helmetPart(head, color, Vector3.new(h.Y * 0.08, s * 1.2, s * 1.22), CFrame.new(0, top - h.Y * 0.2, 0) * flat, cyl)
	elseif shape == "Type90" then
		helmetPart(head, color, Vector3.new(s * 1.04, h.Y * 0.56, s * 1.08), CFrame.new(0, top, 0), sphere)
		-- The cloth neck flap hanging at the back.
		helmetPart(head, color:Lerp(Color3.new(0.6, 0.55, 0.4), 0.4), Vector3.new(s * 0.9, h.Y * 0.55, 0.08), CFrame.new(0, top - h.Y * 0.35, s * 0.52))
	else -- M1
		helmetPart(head, color, Vector3.new(s * 1.12, h.Y * 0.64, s * 1.16), CFrame.new(0, top, 0), sphere)
		helmetPart(head, color, Vector3.new(h.Y * 0.06, s * 1.26, s * 1.3), CFrame.new(0, top - h.Y * 0.18, 0) * flat, cyl)
	end
end

local function dress(body, name)
	local d = DRESS[name]
	if not d then
		return
	end
	for _, inst in body:GetDescendants() do
		if inst:IsA("Clothing") or inst:IsA("ShirtGraphic") or inst:IsA("SurfaceAppearance") then
			inst:Destroy()
		end
	end
	for _, acc in body:GetChildren() do
		if acc:IsA("Accessory") and not isGun(acc) then
			acc:Destroy()
		end
	end
	for _, part in body:GetDescendants() do
		if part:IsA("BasePart") and part.Parent and not isGun(part) then
			local region = REGION[part.Name]
			if region then
				part.Color = d[region] or d.Tunic
				if part:IsA("MeshPart") and region ~= "Skin" then
					part.TextureID = ""
				end
			elseif part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
				-- Pouches, vests and straps: the nation's webbing.
				part.Color = d.Gear
				if part:IsA("MeshPart") then
					part.TextureID = ""
				end
			end
		end
	end
	local head = body:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		helmet(head, d.HelmetShape, d.Helmet)
	end
end

local views = {} -- [model] = view
local frame = 0

local function joint(body, name)
	local j = body:FindFirstChild(name, true)
	return if j and j:IsA("Motor6D") then j else nil
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
	local dressName = model:GetAttribute("Dress")
	if dressName then
		local ok, err = pcall(dress, body, dressName)
		if not ok then
			warn("SoldierView: dress " .. tostring(dressName) .. ": " .. tostring(err))
		end
	end
	local scale = model:GetAttribute("Scale") or 1
	if scale ~= 1 then
		body:ScaleTo(scale)
	end
	local bodyRoot = body.PrimaryPart
	local hum = body:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	local view = {
		Model = model,
		Root = root,
		Body = body,
		BodyRoot = bodyRoot,
		Lift = (template:GetAttribute("FeetToRoot") or 3) * scale,
		Scale = scale,
		Tracks = {},
		Hold = {},
		Legs = {},
		Waist = joint(body, "Waist"),
		Pitch = 0,
		Crouch = 0,
		Speed = 0,
		WalkWeight = -1,
		Shown = false,
		Phase = math.random(0, 1),
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
	if animator then
		for name, a in ANIMS do
			local anim = Instance.new("Animation")
			anim.AnimationId = a.Id
			local ok, track = pcall(animator.LoadAnimation, animator, anim)
			if ok and track then
				track.Priority = a.Priority
				track.Looped = true
				view.Tracks[name] = track
			end
		end
	end
	view.CF = root.CFrame * CFrame.new(0, -root.Size.Y / 2 + view.Lift, 0)
	bodyRoot.CFrame = view.CF
	views[model] = view
end

local function show(view, on)
	if view.Shown == on then
		return
	end
	view.Shown = on
	if on then
		view.Body.Parent = view.Model
		local idle, walk = view.Tracks.Idle, view.Tracks.Walk
		if idle and not idle.IsPlaying then
			idle:Play(0.1)
		end
		if walk and not walk.IsPlaying then
			walk:Play(0.1, 0.001)
			view.WalkWeight = 0
		end
	else
		view.Body.Parent = nil
	end
end

local function drop(model)
	local view = views[model]
	if view then
		views[model] = nil
		view.Body:Destroy()
	end
end

-- Down: the animation stops and the body tips over backward about its feet, lies, then fades.
local function fall(view)
	view.Fallen = os.clock()
	for _, t in view.Tracks do
		t:Stop(0.15)
	end
	task.delay(math.max(1, BODY_TIME - 1.2), function()
		if views[view.Model] ~= view then
			return
		end
		for i = 1, 10 do
			for _, d in view.Body:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = i / 10
				end
			end
			task.wait(0.08)
		end
		drop(view.Model)
	end)
end

local function step(dt)
	frame += 1
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
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
		-- Where the body's root goes: the hitbox's feet, up by the rig's own height, down by the kneel.
		local feet = root.CFrame * CFrame.new(0, -root.Size.Y / 2, 0)
		local want = feet * CFrame.new(0, view.Lift - view.Crouch * DROP * view.Scale, 0)
		if view.Fallen then
			local k = math.clamp((os.clock() - view.Fallen) / FALL_TIME, 0, 1)
			k = 1 - (1 - k) * (1 - k)
			local tip = CFrame.new(0, -view.Lift, 0) * CFrame.Angles(math.rad(84) * k, 0, 0) * CFrame.new(0, view.Lift, 0)
			view.CF = view.CF:Lerp(want, ease)
			view.BodyRoot.CFrame = view.CF * tip
			continue
		end
		local before = view.CF.Position
		view.CF = view.CF:Lerp(want, ease)
		view.BodyRoot.CFrame = view.CF
		local moved = view.CF.Position - before
		local speed = math.sqrt(moved.X * moved.X + moved.Z * moved.Z) / math.max(dt, 1e-3)
		view.Speed += (speed - view.Speed) * math.min(1, dt * 8)
		-- Mid distance: the pose every other frame.
		if dist > NEAR and (frame + view.Phase) % 2 == 0 then
			continue
		end
		local walk = view.Tracks.Walk
		if walk then
			local w = math.clamp(view.Speed / 4, 0, 1)
			if math.abs(w - view.WalkWeight) > 0.05 then
				view.WalkWeight = w
				walk:AdjustWeight(math.max(w, 0.001), 0.15)
				walk:AdjustSpeed(math.max(view.Speed, 1) / 14)
			end
		end
		local still = view.Speed < 3
		local wantCrouch = if model:GetAttribute("Stance") == "Crouch" and still then 1 else 0
		view.Crouch += (wantCrouch - view.Crouch) * math.min(1, dt * 10)
		local pitch = model:GetAttribute("AimPitch") or 0
		view.Pitch += (pitch - view.Pitch) * math.min(1, dt * 12)
		for _, j in view.Hold do
			j.Transform = CFrame.identity
		end
		if view.Waist then
			view.Waist.Transform = CFrame.Angles(view.Pitch, 0, 0)
		end
		if view.Crouch > 0.01 then
			for _, leg in view.Legs do
				leg.Joint.Transform = leg.Joint.Transform:Lerp(leg.Pose, view.Crouch)
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

-- After the animator has posed the frame, before it's drawn.
RunService.PreSimulation:Connect(step)
