--!strict
-- Shared.ViewMode (7 Nov 2026): first or third person for the player holding a gun.
--
-- The camera stays in Roblox's LockFirstPerson mode, so the mouse lock, Modal menus (CursorToggle), controller look,
-- touch look and aim assist all work exactly as in first person. In third person this module moves the finished
-- view back over the right shoulder every frame (after the camera module and GunClient have built it, RenderPriority
-- Camera + 2), keeps it out of walls with a spherecast, and shows your own body. The camera module rebuilds the next
-- frame from the look direction alone, so the move never feeds back into aiming.
--
--   GunClient: hides the viewmodel while ViewMode.IsThird(); shoots from the head toward what the crosshair covers
--   (ViewMode.ShotFrom, so GunServer's head-distance rule is unchanged); flashes and throws brass from your own world
--   gun (ViewMode.Muzzle / MuzzleFire / EjectAt); tells WorldGunArms about each shot (ViewMode.FireShot); and calls
--   ViewMode.Frame(aim, sprint, forceFirst) every frame it owns the view.
--   WorldGunArms: shows, poses and tilts your own world gun while ViewMode.IsThird(), and plays its recoil on
--   ViewMode.Shot.
--
-- Switch: the "View" action in Shared.Controls (V by default) or the Camera row in Settings (Options "View", saved).
-- A scoped gun goes to first person while it aims (forceFirst), so the scope picture is the same in both views.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Options = require(Shared:WaitForChild("Options"))
local MuzzleFx = require(Shared:WaitForChild("MuzzleFx"))

local ViewMode = {}

local THIRD = "Third"
local FIRST = "First"

local CFG = {
	-- Studs from the eyes: over the right shoulder, a little up, back. Aiming pulls in tight; sprinting eases out.
	Right = 1.75,
	Up = 0.4,
	Back = 6,
	AimRight = 1.35,
	AimUp = 0.28,
	AimBack = 3.2,
	SprintBack = 6.6,
	Radius = 0.4, -- the camera's collision sphere
	Margin = 0.15, -- kept clear of a wall it stops at
	SwitchRate = 6.5, -- blend per second, first <-> third
	ForceRate = 16, -- blend per second into first person for a scope
	OutRate = 9, -- studs per second the view eases back out after a wall pulled it in
}
ViewMode.Config = CFG

local player = Players.LocalPlayer
local picked = false -- the player's choice
local blend = 0 -- 0 = at the eyes, 1 = over the shoulder
local isThird = false
local lastFrame = -math.huge
local frameAim, frameSprint, frameForce = 0, 0, false
local reach = 0 -- current pulled-in distance behind the shoulder
local bodyShown = false

local changed = Instance.new("BindableEvent")
ViewMode.Changed = changed.Event -- (third: boolean) when IsThird() flips
local shot = Instance.new("BindableEvent")
ViewMode.Shot = shot.Event -- (gunName: string) your own shot, in third person

local function readOption()
	local v = Options.Get("View")
	if v ~= nil then
		picked = v == THIRD
	end
end
readOption()
Options.Changed:Connect(function(key)
	if key == "View" then
		readOption()
	end
end)

function ViewMode.Picked(): boolean
	return picked
end

-- The view is out of the eyes (the viewmodel is hidden and shots leave from the head).
function ViewMode.IsThird(): boolean
	return isThird
end

function ViewMode.Set(third: boolean)
	picked = third
	-- Saved with the other settings where the place has the option (GameConfig.Settings.View).
	Options.Set("View", if third then THIRD else FIRST)
end

function ViewMode.Toggle()
	ViewMode.Set(not picked)
end

-- GunClient, every frame the gun owns the view. aim and sprint are 0..1; forceFirst holds first person.
function ViewMode.Frame(aim: number, sprint: number, forceFirst: boolean)
	lastFrame = os.clock()
	frameAim, frameSprint, frameForce = aim, sprint, forceFirst
end

function ViewMode.FireShot(gunName: string)
	if isThird then
		shot:Fire(gunName)
	end
end

local function character(): Model?
	return player.Character
end

local function head(): BasePart?
	local c = character()
	local h = c and c:FindFirstChild("Head")
	return if h and h:IsA("BasePart") then h else nil
end

-- The eyes the shots start from (inside GunServer's MaxOriginOffset of the head).
function ViewMode.HeadPos(): Vector3?
	local h = head()
	return h and h.Position
end

-- Where a shot starts and which way it goes in third person: the crosshair's ray from the camera finds the point it
-- covers (starting level with the head, so nothing between the camera and you counts), then the shot goes from the
-- head to that point.
function ViewMode.ShotFrom(camCF: CFrame, dir: Vector3, params: RaycastParams, range: number): (Vector3, Vector3)
	local h = head()
	if not h then
		return camCF.Position, dir
	end
	local origin = h.Position
	local camPos = camCF.Position
	local along = math.max(0, (origin - camPos):Dot(dir))
	local start = camPos + dir * along
	local result = workspace:Raycast(start, dir * range, params)
	local target = if result then result.Position else start + dir * range
	local to = target - origin
	if to.Magnitude < 0.75 or to.Unit:Dot(dir) < 0.2 then
		return origin, dir
	end
	return origin, to.Unit
end

-- Your own world gun's muzzle (GunServer's WorldGun model), while third person shows it.
local muzzleCache = setmetatable({}, { __mode = "k" }) :: { [Instance]: Attachment }
local function worldMuzzle(): Attachment?
	local c = character()
	local holder = c and c:FindFirstChild("WorldGun")
	if not holder then
		return nil
	end
	local cached = muzzleCache[holder]
	if cached and cached.Parent and cached:IsDescendantOf(holder) then
		return cached
	end
	-- GunRoot's Muzzle sits on the barrel for every hold (a pack gun's GunRoot rides on the gun).
	local root = holder:FindFirstChild("GunRoot")
	local found = root and root:FindFirstChild("Muzzle")
	if not (found and found:IsA("Attachment")) then
		found = holder:FindFirstChild("Muzzle", true)
	end
	if found and found:IsA("Attachment") then
		muzzleCache[holder] = found
		return found
	end
	return nil
end

function ViewMode.Muzzle(): Vector3?
	if not isThird then
		return nil
	end
	local m = worldMuzzle()
	return m and m.WorldPosition
end

-- Brass in third person: just behind the muzzle, out of the right side of the gun.
function ViewMode.EjectAt(look: Vector3): Vector3?
	local at = ViewMode.Muzzle()
	if not at then
		return nil
	end
	local right = look:Cross(Vector3.yAxis)
	right = if right.Magnitude > 0.01 then right.Unit else Vector3.xAxis
	return at - look * 1.4 + right * 0.15 + Vector3.yAxis * 0.05
end

-- Your own gun's flash (Shared.MuzzleFx) on your world gun's barrel.
function ViewMode.MuzzleFire(gunName: string, gun: any, dir: Vector3)
	if not isThird then
		return
	end
	MuzzleFx.Fire(worldMuzzle(), gunName, gun, dir, 1.2)
end

-- Your own world gun follows the look up and down in third person (other players' guns stay level, as before).
-- GunJoint's Transform turns about the upper chest; WorldGunArms (or the zombies GunClient's third-person block)
-- calls this for your character before it bends the arms onto the grips. If the animator wrote the joint this
-- frame its value is the base; otherwise the base is what was under the last tilt.
local TILT_PIVOT = Vector3.new(0, 0.45, 0) -- upper chest, in torso space
local tilts = setmetatable({}, { __mode = "k" }) :: { [Motor6D]: { written: CFrame, base: CFrame } }

local function near(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-4
		and a.LookVector:Dot(b.LookVector) > 0.999999
		and a.UpVector:Dot(b.UpVector) > 0.999999
end

function ViewMode.TiltGun(holder: Instance)
	if not isThird or holder:GetAttribute("Pack") then
		return
	end
	local root = holder:FindFirstChild("GunRoot")
	local joint = root and root:FindFirstChild("GunJoint")
	local camera = workspace.CurrentCamera
	if not (joint and joint:IsA("Motor6D") and camera) then
		return
	end
	local pitch = math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))
	pitch = math.clamp(pitch, math.rad(-70), math.rad(70)) * 0.9
	local current = joint.Transform
	local last = tilts[joint]
	local base = if last and near(current, last.written) then last.base else current
	local c0 = joint.C0
	local turn = CFrame.new(TILT_PIVOT) * CFrame.Angles(pitch, 0, 0) * CFrame.new(-TILT_PIVOT)
	local t = c0:Inverse() * turn * c0 * base
	joint.Transform = t
	tilts[joint] = { written = t, base = base }
end

local function untilt()
	for joint, last in tilts do
		if joint.Parent and near(joint.Transform, last.written) then
			joint.Transform = last.base
		end
	end
	table.clear(tilts)
end

-- Body ---------------------------------------------------------------------------------------------------------------

-- In first person the camera's transparency controller hides your body; it only writes when its own value changes,
-- so this sets the body back to hidden when the view comes in, and fades it while the camera is near the head.
local function setBody(k: number)
	local c = character()
	if not c then
		return
	end
	local gun = c:FindFirstChild("WorldGun")
	for _, d in c:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Decal")) and not (gun and d:IsDescendantOf(gun)) then
			if d.LocalTransparencyModifier ~= k then
				d.LocalTransparencyModifier = k
			end
		end
	end
end

-- Camera ------------------------------------------------------------------------------------------------------------

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.IgnoreWater = true
castParams.RespectCanCollide = true

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- How far the sphere can go from `from` along `dir` (unit) up to `length` before it touches something solid.
local function clear(from: Vector3, dir: Vector3, length: number): number
	if length <= 0.01 then
		return length
	end
	local result = workspace:Spherecast(from, CFG.Radius, dir * length, castParams)
	if not result then
		return length
	end
	return math.max(0, result.Distance - CFG.Margin)
end

local function setThird(value: boolean)
	if value ~= isThird then
		isThird = value
		if not value then
			untilt()
		end
		changed:Fire(value)
		-- ServerScriptService.ViewModeServer sets the ThirdPerson player attribute: in third person this client
		-- plays your body's clips (they replicate), so other clients stop playing their own copy.
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes and remotes:FindFirstChild("ViewMode")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer(value)
		end
	end
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	local c = character()
	local h = head()
	local humanoid = c and c:FindFirstChildOfClass("Humanoid")
	local owned = os.clock() - lastFrame < 0.25
	local usable = owned
		and camera ~= nil
		and camera.CameraType == Enum.CameraType.Custom
		and h ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and player.CameraMode == Enum.CameraMode.LockFirstPerson

	if not usable then
		-- Something else owns the view (a menu, a cutscene, a death cam, a mounted gun): straight back to the eyes.
		blend = 0
		reach = 0
		setThird(false)
		if bodyShown then
			bodyShown = false
			setBody(1)
		end
		return
	end

	local want = if picked and not frameForce then 1 else 0
	local rate = if frameForce then CFG.ForceRate else CFG.SwitchRate
	if blend < want then
		blend = math.min(want, blend + rate * dt)
	elseif blend > want then
		blend = math.max(want, blend - rate * dt)
	end
	setThird(blend > 0.08)

	if blend <= 0 then
		reach = 0
		if bodyShown then
			bodyShown = false
			setBody(1)
		end
		return
	end

	local cam = camera :: Camera
	local cf = cam.CFrame
	local e = ease(blend)
	local aim = frameAim
	local right = lerp(CFG.Right, CFG.AimRight, aim) * e
	local up = lerp(CFG.Up, CFG.AimUp, aim) * e
	local back = lerp(lerp(CFG.Back, CFG.SprintBack, frameSprint), CFG.AimBack, aim) * e

	castParams.FilterDescendantsInstances = { c :: Instance, cam }

	-- Eyes -> shoulder, then shoulder -> back, each stopped short of anything solid.
	local eyes = cf.Position
	local side = cf.RightVector * right + Vector3.yAxis * up
	local sideLen = side.Magnitude
	local shoulder = eyes
	if sideLen > 0.01 then
		shoulder = eyes + side.Unit * clear(eyes, side.Unit, sideLen)
	end
	local backDir = -cf.LookVector
	local free = clear(shoulder, backDir, back)
	-- A wall pulls the view in at once; it eases back out.
	if free < reach then
		reach = free
	else
		reach = math.min(free, reach + CFG.OutRate * dt)
	end
	cam.CFrame = CFrame.new(shoulder + backDir * reach) * cf.Rotation

	-- The body fades in as the view leaves the head (so the head never fills the screen mid-switch).
	local dist = (shoulder + backDir * reach - eyes).Magnitude
	local k = math.clamp(1 - (dist - 0.9) / 1.4, 0, 1)
	setBody(k)
	bodyShown = true
end

if RunService:IsClient() and player then
	RunService:BindToRenderStep("LastLightView", Enum.RenderPriority.Camera.Value + 2, step)

	-- The switch key (Shared.Controls "View"), where the place's Controls has the action.
	task.spawn(function()
		local module = Shared:FindFirstChild("Controls")
		if not module then
			return
		end
		local ok, Controls = pcall(require, module)
		if not ok or type(Controls) ~= "table" or not Controls.Bind then
			return
		end
		local found = false
		for _, a in Controls.Actions do
			if a.Name == "View" then
				found = true
			end
		end
		if not found then
			return
		end
		Controls.Bind("LastLightView", "View", function(_, inputState)
			if inputState == Enum.UserInputState.Begin and not Controls.Listening then
				ViewMode.Toggle()
			end
			return Enum.ContextActionResult.Pass
		end)
	end)
end

return ViewMode
