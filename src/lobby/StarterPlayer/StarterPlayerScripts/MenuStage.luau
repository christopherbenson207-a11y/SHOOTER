-- MenuStage (FRONT-A, 4 Nov 2026): the 3D side of the menu, client side only.
-- Workspace.Menu is the dark observation post on the right of the RoadCamera frame (props, Spots, Fx). This module
-- puts the local player's operator on Spot1 (a clone of Assets.Operators.<Operator attribute>) holding the selected
-- primary (Assets.WorldGuns, camo from Shared.Camo) and up to three party members on Spot2..4. Idle is procedural:
-- breathing, a slow weight shift and a head turn toward the Beacon now and then; when one of the Beacon's lamp beams
-- sweeps the stage the operators crouch and freeze for about two seconds. The floodlight stays off and flickers on
-- for a blink once in a while.
-- Camera framings (Frame): Home (the RoadCamera shot), Loadout (closer, operator on the right), Operator (full body,
-- the operator turns slowly) and Store. MenuClient reads the eased camera from Stage.Camera(dt) every frame.
-- ctx.stage API (CONTRACTS 8): Preview(kind, id) for "Operator", "Camo", "Beam", "Card", "Gun"; Reset();
-- Gun(gunKey) shows the gun on the turntable (nil hides it) and puts it in the operator's hands; Frame(name).
-- MenuClient also calls Start(), Stop(), SetBeacon(lamps) and SetSquad(userIds).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local function optional(name)
	local m = Shared:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, t = pcall(require, m)
	return if ok then t else nil
end
local Camo = optional("Camo")
local Catalogue = optional("Catalogue")
local Options = optional("Options")
local Progression = optional("Progression")
local UiMod = nil
do
	local menu = Shared:FindFirstChild("Menu")
	local m = menu and menu:FindFirstChild("Ui")
	if m then
		local ok, t = pcall(require, m)
		UiMod = if ok then t else nil
	end
end
local Lighting = game:GetService("Lighting")

local Stage = {}

local CFG = GameConfig.Menu
local player = Players.LocalPlayer
local ROAD = CFrame.lookAt(CFG.RoadCamera.From, CFG.RoadCamera.To)
local HOME = ROAD -- the Home camera of the current set (Cameras.Home), else the old road shot

-- Gun hold in the UpperTorso's frame (low ready: barrel forward and down, a little across the body).
local HOLD = {
	Rifle = CFrame.new(0.28, -0.42, -0.72) * CFrame.Angles(math.rad(-32), math.rad(34), math.rad(-12)),
	Pistol = CFrame.new(0.12, -0.72, -0.72) * CFrame.Angles(math.rad(-58), math.rad(22), 0),
}
local FLAT = Vector3.new(1, 0, 1)

local root = nil -- Workspace.Menu
local parked = false
local live = false
local folder = nil -- client-side folder for operators and the turntable
local actors = {} -- [slot] = actor
local squad = {} -- userIds of up to three party members (not the local player)
local watch = {} -- [userId] = {connections}
local preview = {}
local turntable = nil -- {Model, Key, Angle}
local lamps = nil -- {{Lens = part, Tip = part}}
local beaconRoot = nil
local framing = "Home"
local camCF = HOME
local stepConn = nil
local flickerAt = 0
local clock = 0

-- helpers -----------------------------------------------------------------------------------------------------------

local function decode(v)
	if type(v) == "string" and (v:sub(1, 1) == "{" or v:sub(1, 1) == "[") then
		local ok, t = pcall(HttpService.JSONDecode, HttpService, v)
		if ok then
			return t
		end
	end
	return nil
end

local function assets()
	return ReplicatedStorage:FindFirstChild("Assets")
end

local function strip(model)
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		else
			for _, tag in CollectionService:GetTags(d) do
				if tag ~= "Body" then
					CollectionService:RemoveTag(d, tag)
				end
			end
		end
	end
	for _, tag in CollectionService:GetTags(model) do
		CollectionService:RemoveTag(model, tag)
	end
end

local function quiet(part)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- What a player shows on the stage: operator id, gun key, camo id.
local function loadoutOf(p)
	local op = p:GetAttribute("Operator")
	local kit = decode(p:GetAttribute("Kit"))
	local gun = kit and (kit.Primary or kit.Secondary)
	if not gun then
		local loadouts = decode(p:GetAttribute("Loadouts"))
		local sel = loadouts and loadouts[p:GetAttribute("Selected") or 1]
		gun = sel and (sel.Primary or sel.Secondary)
	end
	local camos = decode(p:GetAttribute("Camos")) or {}
	gun = gun or "AK"
	return (type(op) == "string" and op ~= "") and op or "Woodland", gun, camos[gun]
end

local function groundAt(cf)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- the old road stage stands on the town; a backdrop set stands on its own floor
	local skip = if root and root.Name == "Menu" then root else (root and root:FindFirstChild("Spots"))
	params.FilterDescendantsInstances = { skip, folder }
	local p = cf.Position
	local hit = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
	local y = if hit then hit.Position.Y else p.Y
	return CFrame.new(p.X, y, p.Z) * cf.Rotation
end

local function spot(slot)
	local spots = root and root:FindFirstChild("Spots")
	local s = spots and spots:FindFirstChild("Spot" .. slot)
	return s and groundAt(s.CFrame)
end

-- backdrop sets ------------------------------------------------------------------------------------------------------
-- Workspace.MenuSets.<Settings Backdrop>: Spots (Spot1..4), Cameras (Home, Loadout, Operator, Store; attribute Fov)
-- and Lighting attributes held while the menu is up. Without sets the old road stage (Workspace.Menu) is used.

local LIGHT_KEYS =
	{ "ClockTime", "Ambient", "OutdoorAmbient", "FogColor", "FogEnd", "FogStart", "Brightness", "ExposureCompensation" }
local savedLighting = nil
local setLighting = nil
local fov = 60

local function backdropName()
	local v = Options and Options.Get("Backdrop")
	return if type(v) == "string" then v else "Outpost"
end

local function findSet(name)
	local sets = workspace:FindFirstChild("MenuSets")
	if not sets then
		return nil
	end
	return sets:FindFirstChild(name) or sets:FindFirstChild("Outpost") or sets:FindFirstChildWhichIsA("Model")
end

local function cameraPart(name)
	local cams = root and root:FindFirstChild("Cameras")
	local p = cams and cams:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

local function applySetLighting()
	if savedLighting == nil then
		savedLighting = {}
		for _, k in LIGHT_KEYS do
			savedLighting[k] = Lighting[k]
		end
	end
	setLighting = {}
	if root and root.Name ~= "Menu" then
		for _, k in LIGHT_KEYS do
			local v = root:GetAttribute(k)
			if v ~= nil then
				setLighting[k] = v
			end
		end
	end
end

-- held every frame while the menu is live (the server's night cycle would otherwise win)
local function holdLighting()
	if not setLighting then
		return
	end
	for k, v in setLighting do
		if Lighting[k] ~= v then
			pcall(function()
				Lighting[k] = v
			end)
		end
	end
end

local function restoreLighting()
	if savedLighting then
		for k, v in savedLighting do
			pcall(function()
				Lighting[k] = v
			end)
		end
	end
	savedLighting = nil
	setLighting = nil
end

local function useSet(set)
	root = set or workspace:FindFirstChild("Menu")
	local home = cameraPart("Home")
	HOME = if home then home.CFrame else ROAD
	applySetLighting()
end

-- The squad mate's own face and skin on their operator (from their lobby character, when it has loaded).
local OPERATOR_SKIN = Color3.new(1, 0.8, 0.6)
local skinCache = {} -- [userId] = Color3 | false (fetching)

local function paintSkin(m, skin)
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local c = d:GetAttribute("BaseSkin") or d.Color
			if math.abs(c.R - OPERATOR_SKIN.R) + math.abs(c.G - OPERATOR_SKIN.G) + math.abs(c.B - OPERATOR_SKIN.B) < 0.03 then
				d:SetAttribute("BaseSkin", c)
				d.Color = skin
			end
		end
	end
end

local function personalize(m, userId)
	local p = Players:GetPlayerByUserId(userId)
	local ch = p and p.Character
	if not ch then
		-- in the menu nobody has a body: the skin tone comes from their avatar description (fetched once)
		local cached = skinCache[userId]
		if cached then
			paintSkin(m, cached)
		elseif cached == nil and userId and userId > 0 then
			skinCache[userId] = false
			task.spawn(function()
				local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
				if ok and desc then
					skinCache[userId] = desc.HeadColor
					for _, a in actors do
						if a.UserId == userId and a.Model then
							paintSkin(a.Model, desc.HeadColor)
						end
					end
				else
					skinCache[userId] = nil
				end
			end)
		end
		return
	end
	local srcHead = ch:FindFirstChild("Head")
	local bc = ch:FindFirstChildOfClass("BodyColors")
	local skin = (bc and bc.HeadColor3) or (srcHead and srcHead:IsA("BasePart") and srcHead.Color) or nil
	if skin then
		for _, d in m:GetChildren() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				local c = d.Color
				if math.abs(c.R - OPERATOR_SKIN.R) + math.abs(c.G - OPERATOR_SKIN.G) + math.abs(c.B - OPERATOR_SKIN.B) < 0.03 then
					d.Color = skin
				end
			end
		end
	end
	local face = srcHead and (srcHead:FindFirstChild("face") or srcHead:FindFirstChildOfClass("Decal"))
	local head = m:FindFirstChild("Head")
	if head and face and face:IsA("Decal") and face.Texture ~= "" then
		local f = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
		if not f then
			f = Instance.new("Decal")
			f.Name = "face"
			f.Face = Enum.NormalId.Front
			f.Parent = head
		end
		f.Texture = face.Texture
	end
end

-- Name plates are screen UI (ScreenGui SquadPlates, under the menu) that follow each soldier's head every frame.
local plateGui = nil
local platesOn = true -- MenuClient: on for the HOME page only
local function plateLayer()
	if plateGui and plateGui.Parent then
		return plateGui
	end
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	plateGui = Instance.new("ScreenGui")
	plateGui.Name = "SquadPlates"
	plateGui.DisplayOrder = 19
	plateGui.IgnoreGuiInset = true
	plateGui.ResetOnSpawn = false
	plateGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local s = Instance.new("UIScale")
	s.Name = "Scale"
	s.Parent = plateGui
	plateGui.Parent = pg
	return plateGui
end

-- The name plate over a soldier (Assets.SquadPlate, authored): rank, name and level; Home framing only.
local function plate(actor, userId)
	local a = assets()
	local tpl = a and a:FindFirstChild("SquadPlate")
	local head = actor.Model:FindFirstChild("Head")
	local p = Players:GetPlayerByUserId(userId)
	local demo = not p and userId and userId < -100 and RunService:IsStudio()
	if not (tpl and head and (p or demo)) then
		return
	end
	local layer = plateLayer()
	if not layer then
		return
	end
	local g = Instance.new("Frame")
	g.Name = "Plate" .. actor.Slot
	g.BackgroundTransparency = 1
	g.AnchorPoint = Vector2.new(0.5, 1)
	g.Size = tpl.Size
	g.Visible = false
	for _, c in tpl:GetChildren() do
		c:Clone().Parent = g
	end
	local level = if p then tonumber(p:GetAttribute("Level")) or 1 else 7 - userId % 5
	local name = g:FindFirstChild("PlayerName")
	if name then
		name.Text = if p then string.upper(p.DisplayName) else "SQUADMATE " .. tostring(-userId - 100)
	end
	local lv = g:FindFirstChild("Level")
	if lv then
		lv.Text = "LV " .. level
	end
	local rank = g:FindFirstChild("Rank")
	if rank and UiMod and Progression and Progression.Rank then
		local ok, r = pcall(Progression.Rank, level)
		if ok and r then
			UiMod.SetArt(rank, "Rank/" .. tostring(r))
		end
	end
	g.Parent = layer
	actor.Plate = g
	actor.PlateHead = head
end

-- Two-bone IK (law of cosines), the same solve as SoldierPose.
local function solve(origin, target, a, b)
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

-- guns ---------------------------------------------------------------------------------------------------------------

local function makeGun(key, camoId)
	local a = assets()
	local src = a and a:FindFirstChild("WorldGuns") and a.WorldGuns:FindFirstChild(key)
	if not src then
		return nil
	end
	local gun = src:Clone()
	strip(gun)
	for _, d in gun:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			quiet(d)
			d.CastShadow = true
		end
	end
	if not gun.PrimaryPart then
		gun.PrimaryPart = gun:FindFirstChild("Root") or gun:FindFirstChildWhichIsA("BasePart")
	end
	if Camo and camoId then
		pcall(Camo.Apply, gun, key, camoId)
	end
	return gun
end

local function beamColor(id)
	local item = Catalogue and Catalogue.Items and Catalogue.Items["Beam/" .. tostring(id)]
	return item and item.Color or Color3.fromRGB(255, 226, 170)
end

-- operators ----------------------------------------------------------------------------------------------------------

local JOINTS = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand",
	LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm", LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot",
	LeftHip = "LeftUpperLeg", LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot",
}

local function destroyActor(slot)
	local a = actors[slot]
	if a then
		if a.Plate then
			a.Plate:Destroy()
		end
		if a.Model then
			a.Model:Destroy()
		end
		if a.Gun then
			a.Gun:Destroy()
		end
		actors[slot] = nil
	end
end

local function setGun(a, key, camoId)
	if a.Gun then
		a.Gun:Destroy()
		a.Gun = nil
	end
	a.GunKey = key
	local gun = makeGun(key, camoId)
	if not gun then
		return
	end
	gun.Name = "HeldGun"
	a.Hold = HOLD[gun:GetAttribute("Hold") or "Rifle"] or HOLD.Rifle
	local r = gun.PrimaryPart
	a.GripR = r and r:FindFirstChild("Grip")
	a.GripL = r and r:FindFirstChild("LeftGrip")
	gun.Parent = folder
	a.Gun = gun
end

local function buildActor(slot, userId, opId, gunKey, camoId)
	destroyActor(slot)
	local at = spot(slot)
	local a = assets()
	local ops = a and a:FindFirstChild("Operators")
	local src = ops and (ops:FindFirstChild(opId) or ops:FindFirstChild("Woodland"))
	if not (at and src and folder) then
		return nil
	end
	local m = src:Clone()
	strip(m)
	m.Name = "Operator" .. slot
	personalize(m, userId)
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		pcall(function()
			hum.EvaluateStateMachine = false
		end)
	end
	local hrp = m:FindFirstChild("HumanoidRootPart")
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			quiet(d)
			d.Anchored = d == hrp
			d.Massless = true
		end
	end
	if not hrp then
		m:Destroy()
		return nil
	end
	-- the rig is stored with its root 3 studs over the ground
	local place = at * CFrame.new(0, 3, 0)
	m:PivotTo(place * hrp.CFrame:ToObjectSpace(m:GetPivot()))
	local actor = {
		Slot = slot, UserId = userId, Model = m, Root = hrp, Home = place, Yaw = 0,
		Operator = opId, Joints = {}, Rest = {},
		Phase = math.random() * 10, Crouch = 0, CrouchUntil = 0,
		LookAt = 0, NextLook = clock + 3 + math.random() * 5, LookUntil = 0, HeadYaw = 0,
		NextAct = clock + 1.5 + slot * 1.3 + math.random() * 3, ActT = 0, ActSide = 1,
	}
	for joint, partName in JOINTS do
		local part = m:FindFirstChild(partName)
		local j = part and part:FindFirstChild(joint)
		if j and j:IsA("Motor6D") then
			actor.Joints[joint] = j
			actor.Rest[joint] = j.C0
		end
	end
	actor.Arms = {}
	for _, side in { "Right", "Left" } do
		local sh, el, wr = actor.Joints[side .. "Shoulder"], actor.Joints[side .. "Elbow"], actor.Joints[side .. "Wrist"]
		if sh and el and wr then
			actor.Arms[side] = {
				Shoulder = sh, Elbow = el, Wrist = wr, ShoulderC0 = sh.C0, ElbowC0 = el.C0,
				Upper = (sh.C1.Position - el.C0.Position).Magnitude,
				Lower = (el.C1.Position - wr.C0.Position).Magnitude + wr.C1.Position.Magnitude * 0.6,
			}
		end
	end
	m.Parent = folder
	setGun(actor, gunKey, camoId)
	plate(actor, userId)
	actors[slot] = actor
	return actor
end

-- The local player's operator, with any preview on top.
local function rebuildLocal()
	if not live or not player then
		return
	end
	local op, gun, camo = loadoutOf(player)
	op = preview.Operator or op
	gun = preview.Gun or gun
	if preview.Gun then
		local camos = decode(player:GetAttribute("Camos")) or {}
		camo = camos[gun]
	end
	camo = preview.Camo or camo
	local a = buildActor(1, player.UserId, op, gun, camo)
	if a and preview.Beam then
		Stage._torch(a, preview.Beam)
	end
end

function Stage._torch(a, beamId)
	if not (a and a.Gun) then
		return
	end
	local r = a.Gun.PrimaryPart
	if not r then
		return
	end
	local old = r:FindFirstChild("PreviewTorch")
	if old then
		old:Destroy()
	end
	if not beamId then
		return
	end
	local muzzle = r:FindFirstChild("Muzzle")
	local att = Instance.new("Attachment")
	att.Name = "PreviewTorch"
	att.Position = muzzle and muzzle.Position or Vector3.new(0, 0.2, -1.5)
	att.Parent = r
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 45
	light.Range = 20
	light.Brightness = 3
	light.Shadows = false
	light.Color = beamColor(beamId)
	light.Parent = att
end

-- Studio only: workspace attribute MenuDemoSquad = true fills slots 2-4 with stand-ins (negative ids) to check the lineup.
local DEMO_OPS = { [-101] = { "Desert", "M4" }, [-102] = { "Ghillie", "Sniper" }, [-103] = { "SWAT", "Shotgun" } }

local function rebuildMember(slot, userId)
	local p = Players:GetPlayerByUserId(userId)
	if not p and DEMO_OPS[userId] and RunService:IsStudio() then
		local d = DEMO_OPS[userId]
		buildActor(slot, userId, d[1], d[2], nil)
		return
	end
	if not p then
		destroyActor(slot)
		return
	end
	local op, gun, camo = loadoutOf(p)
	buildActor(slot, userId, op, gun, camo)
end

local WATCHED = { "Operator", "Kit", "Camos", "Selected", "Loadouts", "Level" }

local function unwatchAll()
	for _, conns in watch do
		for _, c in conns do
			c:Disconnect()
		end
	end
	table.clear(watch)
end

local function watchPlayer(p, onChange)
	local conns = {}
	local pending = false
	for _, name in WATCHED do
		table.insert(conns, p:GetAttributeChangedSignal(name):Connect(function()
			-- one rebuild for a burst of attribute changes
			if pending then
				return
			end
			pending = true
			task.delay(0.15, function()
				pending = false
				if live then
					onChange()
				end
			end)
		end))
	end
	-- their face and skin come from their character: rebuild once it has its look
	table.insert(conns, p.CharacterAppearanceLoaded:Connect(function()
		if live then
			onChange()
		end
	end))
	watch[p.UserId] = conns
end

local function rebuildSquad()
	unwatchAll()
	if not live then
		return
	end
	if player then
		watchPlayer(player, rebuildLocal)
	end
	for slot = 2, 4 do
		local id = squad[slot - 1]
		if id then
			rebuildMember(slot, id)
			local p = Players:GetPlayerByUserId(id)
			if p then
				watchPlayer(p, function()
					rebuildMember(slot, id)
				end)
			end
		else
			destroyActor(slot)
		end
	end
end

-- turntable ----------------------------------------------------------------------------------------------------------

local function clearTurntable()
	if turntable then
		turntable.Model:Destroy()
		turntable = nil
	end
end

-- framings -----------------------------------------------------------------------------------------------------------

-- The camera for a framing, from the local operator's spot (it faces the camera).
local function framingCF(name)
	local authored = cameraPart(name)
	if authored then
		return authored.CFrame
	end
	local at = spot(1)
	if name == "Home" or not at then
		return HOME
	end
	-- relative to the line from the operator back to the home camera (the operators stand turned three-quarters)
	local p = (at * CFrame.new(0, 3, 0)).Position
	local look = ((HOME.Position - p) * FLAT).Unit
	local right = look:Cross(Vector3.yAxis).Unit
	if name == "Loadout" then
		return CFrame.lookAt(p + look * 7.5 + Vector3.new(0, 0.5, 0), p + right * 3.0 + Vector3.new(0, 0.1, 0))
	elseif name == "Operator" then
		return CFrame.lookAt(p + look * 9.5 + Vector3.new(0, -0.2, 0), p + right * 3.4 + Vector3.new(0, -0.4, 0))
	elseif name == "Store" then
		return CFrame.lookAt(p + look * 10.5 + right * -0.5 + Vector3.new(0, 0, 0), p + right * 3.8 + Vector3.new(0, -0.3, 0))
	end
	return HOME
end

-- per frame ----------------------------------------------------------------------------------------------------------

-- Soldier moves now and then (procedural, one at a time per soldier): each has a length, an optional gun offset in
-- the hold frame, an optional left-hand target, and head/waist turns. ActSide mirrors the look moves.
local rad = math.rad
local ACTS = {
	{ -- inspect the rifle: tilt it up and turn it over
		Name = "Check", Dur = 3.4,
		Hold = function(t)
			return CFrame.new(-0.05, 0.36, 0.05) * CFrame.Angles(rad(36), rad(-32) + math.sin(t * 1.5) * 0.28, rad(26))
		end,
		Neck = Vector3.new(-0.32, -0.32, 0),
	},
	{ -- tap the magazine
		Name = "Mag", Dur = 2.4,
		Hold = function()
			return CFrame.new(0, 0.1, 0) * CFrame.Angles(rad(10), rad(-8), 0)
		end,
		Left = function(a, torso, head, grip, t)
			local r = a.Gun and a.Gun.PrimaryPart
			if not r then
				return nil
			end
			return grip - r.CFrame.UpVector * (0.42 + math.max(0, math.sin(t * 8)) * 0.08) + r.CFrame.LookVector * 0.35
		end,
		Neck = Vector3.new(-0.36, -0.22, 0),
	},
	{ -- set the helmet straight
		Name = "Helmet", Dur = 2.3,
		Hold = function()
			return CFrame.new(0.12, -0.12, 0.12) * CFrame.Angles(rad(-14), rad(14), 0)
		end,
		Left = function(a, torso, head, grip, t)
			return head and (head.CFrame * CFrame.new(-0.62, 0.38 + math.sin(t * 5) * 0.04, -0.12)).Position or nil
		end,
		Neck = Vector3.new(0.06, 0.12, 0.14),
	},
	{ -- look back over the shoulder
		Name = "Look", Dur = 3.0,
		Neck = Vector3.new(0.05, 0.95, 0), Waist = Vector3.new(0, 0.3, 0), Mirror = true,
	},
	{ -- bring the rifle up to high ready for a moment
		Name = "Ready", Dur = 2.6,
		Hold = function()
			return CFrame.new(-0.1, 0.42, -0.12) * CFrame.Angles(rad(46), rad(-24), rad(6))
		end,
		Neck = Vector3.new(-0.1, -0.12, 0),
	},
	{ -- roll the neck, shift the weight
		Name = "Stretch", Dur = 2.2,
		Neck = Vector3.new(0.08, 0, 0.32), Waist = Vector3.new(0, 0, 0.06), Mirror = true,
	},
}

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Is a Beacon lamp lighting this spot? (its ground tip near the operator, or the beam passing close by)
local function lit(pos)
	if not lamps then
		return false
	end
	for _, l in lamps do
		local lens, tip = l.Lens, l.Tip
		if lens and tip and lens.Parent and tip.Parent then
			local a, b = lens.Position, tip.Position
			if ((b - pos) * FLAT).Magnitude < 6 then
				return true
			end
			local ab = b - a
			local t = math.clamp((pos - a):Dot(ab) / math.max(ab:Dot(ab), 1e-3), 0, 1)
			if (a + ab * t - pos).Magnitude < 3.5 then
				return true
			end
		end
	end
	return false
end

local function poseActor(a, dt)
	local j = a.Joints
	if not a.Model.Parent then
		return
	end
	a.Phase += dt
	local t = a.Phase
	-- yaw: the local operator turns on the Operator and Store framings and sways on Loadout
	local wantYaw = 0
	if a.Slot == 1 then
		if framing == "Operator" or framing == "Store" then
			a.Spin = (a.Spin or 0) + dt * 0.35
			wantYaw = a.Spin
		elseif framing == "Loadout" then
			a.Spin = 0
			wantYaw = math.sin(clock * 0.3) * 0.35
		else
			a.Spin = 0
		end
	end
	local dy = (wantYaw - a.Yaw + math.pi) % (2 * math.pi) - math.pi
	a.Yaw += dy * math.min(1, dt * 3)
	a.Root.CFrame = a.Home * CFrame.Angles(0, a.Yaw, 0)

	-- crouch and freeze while a lamp beam is on the stage
	if lit(a.Root.Position) then
		a.CrouchUntil = clock + 2
	end
	local want = if clock < a.CrouchUntil then 1 else 0
	a.Crouch += (want - a.Crouch) * math.min(1, dt * (if want > a.Crouch then 9 else 2.5))
	local c = a.Crouch
	local calm = 1 - c

	-- the current soldier move and its weight (eases in and out; the leader keeps still on close framings)
	local act, w = nil, 0
	if a.Act then
		a.ActT += dt
		local d = a.Act.Dur
		if a.ActT >= d then
			a.Act = nil
			a.NextAct = clock + 4 + math.random() * 6
		else
			act = a.Act
			w = smooth(math.min(a.ActT / 0.45, (d - a.ActT) / 0.55)) * calm
		end
	elseif clock > a.NextAct and c < 0.1 and not (a.Slot == 1 and framing ~= "Home") then
		local pick = ACTS[math.random(#ACTS)]
		if pick == a.LastAct then
			pick = ACTS[(table.find(ACTS, pick) % #ACTS) + 1]
		end
		a.Act, a.LastAct, a.ActT = pick, pick, 0
		a.ActSide = if math.random() < 0.5 then 1 else -1
	end
	local side = if act and act.Mirror then a.ActSide else 1
	local aNeck = if act and act.Neck then act.Neck * w else Vector3.zero
	local aWaist = if act and act.Waist then act.Waist * w else Vector3.zero

	local breathe = math.sin(t * 1.7) * 0.014 * calm
	local shift = math.sin(t * 0.33) * calm
	if j.Root then
		j.Root.Transform = CFrame.new(shift * 0.07, -1.05 * c, 0.15 * c) * CFrame.Angles(0, 0, shift * 0.025)
	end
	if j.Waist then
		j.Waist.Transform = CFrame.Angles(breathe + 0.32 * c + aWaist.X, aWaist.Y * side, -shift * 0.02 + aWaist.Z * side)
	end
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local hip, knee, ankle = j[side .. "Hip"], j[side .. "Knee"], j[side .. "Ankle"]
		local stance = shift * 0.03 * s
		if hip then
			hip.Transform = CFrame.Angles(1.15 * c + stance, 0, -0.06 * s * c)
		end
		if knee then
			knee.Transform = CFrame.Angles(-1.75 * c - math.max(0, stance) * 2, 0, 0)
		end
		if ankle then
			ankle.Transform = CFrame.Angles(0.6 * c, 0, 0)
		end
	end

	-- head: now and then toward the Beacon
	if clock > a.NextLook then
		a.LookUntil = clock + 2.5 + math.random() * 1.5
		a.NextLook = clock + 6 + math.random() * 4
	end
	local headYaw, headPitch = 0, 0
	local head = a.Model:FindFirstChild("Head")
	if root and root.Name == "Menu" and beaconRoot and beaconRoot.Parent and head and (clock < a.LookUntil or c > 0.5) then
		local torso = a.Model:FindFirstChild("UpperTorso")
		if torso then
			local rel = torso.CFrame:PointToObjectSpace(beaconRoot.Position)
			headYaw = math.clamp(math.atan2(-rel.X, -rel.Z), -1.1, 1.1)
			headPitch = math.clamp(math.atan2(rel.Y, (rel * FLAT).Magnitude) * 0.5, -0.2, 0.35)
		end
	end
	a.HeadYaw += (headYaw - a.HeadYaw) * math.min(1, dt * 2.2)
	a.HeadPitch = (a.HeadPitch or 0) + (headPitch - (a.HeadPitch or 0)) * math.min(1, dt * 2.2)
	if j.Neck then
		j.Neck.Transform = CFrame.Angles(a.HeadPitch + breathe * 0.6 + aNeck.X, a.HeadYaw + aNeck.Y * side, aNeck.Z * side)
	end

	-- the gun hangs off the chest at low ready; both hands reach its grips
	local torso = a.Model:FindFirstChild("UpperTorso")
	if a.Gun and a.Gun.PrimaryPart and torso then
		local extra = CFrame.identity
		if act and act.Hold then
			extra = CFrame.identity:Lerp(act.Hold(a.ActT), w)
		end
		a.Gun:PivotTo(torso.CFrame * a.Hold * extra * CFrame.Angles(breathe * 0.5, 0, 0))
		for armSide, arm in a.Arms do
			local grip = if armSide == "Right" then a.GripR else a.GripL
			if grip then
				local origin = torso.CFrame * arm.ShoulderC0
				local target = grip.WorldPosition
				if armSide == "Left" and act and act.Left and w > 0 then
					local to = act.Left(a, torso, head, target, a.ActT)
					if to then
						target = target:Lerp(to, w)
					end
				end
				local plane, b1, b2 = solve(origin, target, arm.Upper, arm.Lower)
				arm.Shoulder.C0 = torso.CFrame:ToObjectSpace(plane) * CFrame.Angles(b1, 0, 0)
				arm.Elbow.C0 = arm.ElbowC0 * CFrame.Angles(b2, 0, 0)
				arm.Shoulder.Transform = CFrame.identity
				arm.Elbow.Transform = CFrame.identity
				arm.Wrist.Transform = CFrame.identity
			end
		end
	end
end

local function flicker()
	local flood = root and root:FindFirstChild("Props") and root.Props:FindFirstChild("Floodlight")
	if not flood then
		return
	end
	local lights, lenses = {}, {}
	for _, d in flood:GetDescendants() do
		if d:IsA("SurfaceLight") or d:IsA("SpotLight") then
			table.insert(lights, d)
		elseif d:IsA("BasePart") and d.Name == "Lens" then
			table.insert(lenses, { Part = d, Material = d.Material, Color = d.Color })
		end
	end
	local function set(on)
		for i, l in lights do
			l.Enabled = on and i == 1
		end
		for _, l in lenses do
			l.Part.Material = if on then Enum.Material.Neon else l.Material
			l.Part.Color = if on then Color3.fromRGB(255, 236, 205) else l.Color
		end
	end
	task.spawn(function()
		for _, step in { { true, 0.06 }, { false, 0.11 }, { true, 0.04 }, { false, 0 } } do
			if not live then
				break
			end
			set(step[1])
			if step[2] > 0 then
				task.wait(step[2])
			end
		end
		set(false)
	end)
end

-- A soft fill light from beside the camera on the close framings, so your soldier reads in every set.
local fill = nil
local function updateFill()
	if not folder then
		return
	end
	if not (fill and fill.Parent) then
		fill = Instance.new("Part")
		fill.Name = "MenuFill"
		fill.Anchored = true
		fill.Transparency = 1
		fill.Size = Vector3.new(0.2, 0.2, 0.2)
		quiet(fill)
		fill.CastShadow = false
		local l = Instance.new("SpotLight")
		l.Angle = 45
		l.Range = 24
		l.Brightness = 1.6
		l.Shadows = false
		l.Color = Color3.fromRGB(255, 236, 214)
		l.Parent = fill
		fill.Parent = folder
	end
	local at = spot(1)
	local light = fill:FindFirstChildOfClass("SpotLight")
	if light then
		light.Enabled = framing ~= "Home" and at ~= nil
	end
	if at then
		local chest = at.Position + Vector3.new(0, 3.6, 0)
		local from = camCF.Position + camCF.RightVector * -2.5 + Vector3.new(0, 2.5, 0)
		fill.CFrame = CFrame.lookAt(from, chest)
	end
end

-- A soft fill light from beside the camera on the close framings, so your soldier reads in every set.
local fill = nil
local function updateFill()
	if not folder then
		return
	end
	if not (fill and fill.Parent) then
		fill = Instance.new("Part")
		fill.Name = "MenuFill"
		fill.Anchored = true
		fill.Transparency = 1
		fill.Size = Vector3.new(0.2, 0.2, 0.2)
		quiet(fill)
		fill.CastShadow = false
		local l = Instance.new("SpotLight")
		l.Angle = 45
		l.Range = 24
		l.Brightness = 1.6
		l.Shadows = false
		l.Color = Color3.fromRGB(255, 236, 214)
		l.Parent = fill
		fill.Parent = folder
	end
	local at = spot(1)
	local light = fill:FindFirstChildOfClass("SpotLight")
	if light then
		light.Enabled = framing ~= "Home" and at ~= nil
	end
	if at then
		local chest = at.Position + Vector3.new(0, 3.6, 0)
		local from = camCF.Position + camCF.RightVector * -2.5 + Vector3.new(0, 2.5, 0)
		fill.CFrame = CFrame.lookAt(from, chest)
	end
end

local function step(dt)
	clock += dt
	holdLighting()
	updateFill()
	updateFill()
	if plateGui then
		local sc = plateGui:FindFirstChild("Scale")
		if sc then
			sc.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 1000, 0.55, 1.15)
		end
	end
	for _, a in actors do
		-- squad mates stand in the Home shot only; the close framings are about your own soldier
		if a.Slot > 1 then
			local want = if framing == "Home" then folder else nil
			if a.Model.Parent ~= want then
				a.Model.Parent = want
				if a.Gun then
					a.Gun.Parent = want
				end
			end
		end
		poseActor(a, dt)
		if a.Plate then
			local show = platesOn and framing == "Home" and a.Model.Parent ~= nil and a.PlateHead ~= nil
			if show then
				local cam = workspace.CurrentCamera
				local v, onScreen = cam:WorldToViewportPoint(a.PlateHead.Position + Vector3.new(0, 1.55, 0))
				show = onScreen
				if onScreen then
					local sc = plateGui and plateGui:FindFirstChild("Scale")
					local k = if sc then sc.Scale else 1
					a.Plate.Position = UDim2.fromOffset(v.X / k, v.Y / k)
				end
			end
			a.Plate.Visible = show
		end
	end
	if turntable then
		turntable.Angle += dt * 0.45
		local cam = framingCF(framing)
		turntable.Model:PivotTo(cam * CFrame.new(1.25, -0.35, -4.4) * CFrame.Angles(0, turntable.Angle, 0)
			* CFrame.new(0, 0, (turntable.Length or 3) * 0.35))
	end
	if clock > flickerAt then
		flickerAt = clock + 18 + math.random() * 24
		flicker()
	end
end

-- API ----------------------------------------------------------------------------------------------------------------

function Stage.Start()
	if live then
		return
	end
	-- the sets stream in (Persistent) a moment after the folder: wait for the chosen one, else any set
	local sets = workspace:FindFirstChild("MenuSets") or workspace:WaitForChild("MenuSets", 8)
	local set = nil
	if sets then
		set = sets:FindFirstChild(backdropName()) or sets:WaitForChild(backdropName(), 6) or findSet(backdropName())
		if not sets:GetAttribute("_StageWatch") then
			sets:SetAttribute("_StageWatch", true)
			sets.ChildAdded:Connect(function(child)
				-- a late set: move onto it if we are still on the road stage, or it is the chosen one
				if live and child:IsA("Model") and (root == nil or root.Name == "Menu" or child.Name == backdropName()) then
					task.defer(Stage.SetBackdrop, backdropName())
				end
			end)
		end
	end
	if set then
		useSet(set)
	else
		root = (parked and root and root.Name == "Menu" and root) or workspace:WaitForChild("Menu", 10)
		if root and parked then
			root.Parent = workspace
			parked = false
		end
		if not root then
			warn("[MenuStage] no Workspace.MenuSets or Workspace.Menu")
		end
		useSet(root)
	end
	live = true
	folder = Instance.new("Folder")
	folder.Name = "MenuSquad"
	folder.Parent = workspace
	clock = 0
	flickerAt = 8 + math.random() * 10
	camCF = framingCF(framing)
	rebuildLocal()
	rebuildSquad()
	stepConn = RunService.PreSimulation:Connect(step)
end

function Stage.Stop()
	if not live then
		return
	end
	live = false
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
	unwatchAll()
	clearTurntable()
	for slot in actors do
		destroyActor(slot)
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	restoreLighting()
	if plateGui then
		plateGui:Destroy()
		plateGui = nil
	end
	-- the old road props stay in the town; while you play they are taken out of your view
	if root and root.Name == "Menu" and root.Parent then
		root.Parent = nil
		parked = true
	end
	table.clear(preview)
	framing = "Home"
end

function Stage.IsLive()
	return live
end

-- lampList: {{Lens = part, Tip = part}} from MenuClient's Beacon; model: its root part (for the head turn).
function Stage.SetBeacon(lampList, beaconPart)
	lamps = lampList
	beaconRoot = beaconPart
end

-- Up to three party members besides the local player (userIds).
function Stage.SetSquad(userIds)
	local list = {}
	for _, id in userIds or {} do
		if (not player or id ~= player.UserId) and #list < 3 then
			table.insert(list, id)
		end
	end
	local same = #list == #squad
	for i, id in list do
		if squad[i] ~= id then
			same = false
		end
	end
	if same then
		return
	end
	squad = list
	if live then
		rebuildSquad()
	end
end

function Stage.Frame(name)
	if name == "Home" or name == "Loadout" or name == "Operator" or name == "Store" then
		framing = name
	end
end

-- The eased camera CFrame for this frame (MenuClient adds drift and parallax).
function Stage.Camera(dt)
	local target = framingCF(framing)
	local k = 1 - math.exp(-(dt or 0) * 3.2)
	camCF = camCF:Lerp(target, k)
	local part = cameraPart(framing)
	local want = part and tonumber(part:GetAttribute("Fov")) or 60
	fov += (want - fov) * k
	return camCF
end

-- The eased field of view for this frame (the set's camera part attribute Fov, else 60).
function Stage.Fov()
	return fov
end

-- Name plates over the squad: MenuClient turns them on for the HOME page only.
function Stage.SetPlates(on)
	platesOn = on == true
end

-- Where the camera should focus: the lineup (Roblox renders local lights near Camera.Focus).
function Stage.FocusPoint()
	local at = spot(1)
	return if at then at.Position + Vector3.new(0, 3, 0) else nil
end

-- Switch the backdrop set while the menu is up (Settings > Menu backdrop): a cut to the new set's camera.
function Stage.SetBackdrop(name)
	local set = findSet(name or backdropName())
	if not set or set == root then
		return
	end
	useSet(set)
	if live then
		clearTurntable()
		for slot in actors do
			destroyActor(slot)
		end
		rebuildLocal()
		rebuildSquad()
		camCF = framingCF(framing)
		local part = cameraPart(framing)
		fov = part and tonumber(part:GetAttribute("Fov")) or 60
		if preview.Gun then
			Stage.Gun(preview.Gun)
		end
	end
end

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("MenuDemoSquad"):Connect(function()
		if workspace:GetAttribute("MenuDemoSquad") then
			Stage.SetSquad({ -101, -102, -103 })
		else
			Stage.SetSquad({})
		end
	end)
end

if Options and Options.Changed then
	Options.Changed:Connect(function(key, value)
		if key == "Backdrop" and live then
			Stage.SetBackdrop(value)
		end
	end)
end

function Stage.Gun(gunKey)
	clearTurntable()
	preview.Gun = gunKey
	if not live then
		return
	end
	rebuildLocal()
	if gunKey then
		local camos = player and decode(player:GetAttribute("Camos")) or {}
		local gun = makeGun(gunKey, preview.Camo or camos[gunKey])
		if gun and folder then
			gun.Name = "Turntable"
			gun.Parent = folder
			turntable = { Model = gun, Key = gunKey, Angle = math.rad(-70), Length = gun:GetAttribute("Length") }
			return gun
		end
	end
	return nil
end

-- The picker turntable (FRONT-B's Turntable input): turn the gun on the turntable, else the local operator on the
-- Operator and Store framings, by `degrees` about the vertical axis. The slow idle spin carries on from there.
function Stage.Turn(degrees)
	local r = math.rad(tonumber(degrees) or 0)
	if r == 0 then
		return
	end
	if turntable then
		turntable.Angle += r
		return
	end
	local a = actors[1]
	if a then
		if framing == "Operator" or framing == "Store" then
			a.Spin = (a.Spin or 0) + r
		else
			a.Yaw += r
		end
	end
end

function Stage.Preview(kind, id)
	if kind == "Gun" then
		return Stage.Gun(id)
	elseif kind == "Operator" then
		if type(id) == "string" then
			id = id:gsub("^Operator/", "")
		end
		preview.Operator = id
		rebuildLocal()
	elseif kind == "Camo" then
		if type(id) == "string" then
			id = id:gsub("^Camo/", "")
		end
		preview.Camo = id
		local a = actors[1]
		if a and a.Gun and Camo then
			pcall(Camo.Apply, a.Gun, a.GunKey, id)
		end
		if turntable and Camo then
			pcall(Camo.Apply, turntable.Model, turntable.Key, id)
		end
	elseif kind == "Beam" then
		if type(id) == "string" then
			id = id:gsub("^Beam/", "")
		end
		preview.Beam = id
		Stage._torch(actors[1], id)
	elseif kind == "Card" then
		-- calling cards show on the page itself; nothing on the stage
		preview.Card = id
	end
end

function Stage.Reset()
	local had = next(preview) ~= nil or turntable ~= nil
	table.clear(preview)
	clearTurntable()
	if had then
		rebuildLocal()
	end
end

-- For static checks in Edit (no LocalPlayer): build the stage with given operators and pose it once.
function Stage._Static(list)
	root = workspace:FindFirstChild("Menu")
	folder = Instance.new("Folder")
	folder.Name = "_FA_StageStatic"
	folder.Parent = workspace
	live = true
	for slot, e in list do
		buildActor(slot, 0, e[1], e[2], e[3])
	end
	for _ = 1, 3 do
		for _, a in actors do
			poseActor(a, 1 / 30)
		end
	end
	live = false
	local f = folder
	actors = {}
	folder = nil
	return f
end

return Stage
