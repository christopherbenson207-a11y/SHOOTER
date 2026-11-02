-- Your flashlight: a torch under the barrel of the gun in your hands. With no gun out it
-- rides the camera instead, with a little lag when you turn.
-- F, D-pad up or the touch button toggles it; the server's head light (NightServer)
-- shows it to everyone else, so this client removes its own copy of that one.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SoundKit = require(Shared:WaitForChild("SoundKit"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Settings = GameConfig.Night.Flashlight
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local rig = Instance.new("Part")
rig.Name = "FlashlightRig"
rig.Size = Vector3.new(0.2, 0.2, 0.2)
rig.Transparency = 1
rig.Anchored = true
rig.CanCollide = false
rig.CanQuery = false
rig.CanTouch = false
rig.CastShadow = false

local beam = Instance.new("SpotLight")
beam.Name = "Beam"
beam.Face = Enum.NormalId.Front
beam.Angle = Settings.Angle
beam.Range = Settings.Range
beam.Brightness = Settings.Brightness
beam.Color = Settings.Color
beam.Shadows = true
beam.Parent = rig

local spill = Instance.new("SpotLight")
spill.Name = "Spill"
spill.Face = Enum.NormalId.Front
spill.Angle = Settings.SpillAngle
spill.Range = Settings.SpillRange
spill.Brightness = Settings.SpillBrightness
spill.Color = Settings.Color
spill.Shadows = true
spill.Parent = rig

local on = Settings.StartOn
local aim = nil

local lens = nil

local function apply()
	beam.Enabled = on
	spill.Enabled = on
	if lens then
		lens.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		lens.Color = if on then Settings.Color else Color3.fromRGB(70, 70, 66)
	end
end

-- The torch point on whatever gun model is in front of the camera right now.
local function torchPoint()
	for _, child in camera:GetChildren() do
		if child:IsA("Model") and child.PrimaryPart then
			local point = child.PrimaryPart:FindFirstChild("TorchPoint")
			if point then
				local childLens = child:FindFirstChild("TorchLens")
				if childLens ~= lens then
					lens = childLens
					apply()
				end
				return point
			end
		end
	end
	return nil
end

local function toggle()
	on = not on
	apply()
	SoundKit.Play("Night/FlashlightClick")
	Remotes.Flashlight:FireServer(on)
end

ContextActionService:BindAction("Flashlight", function(_, state)
	if state == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.F, Enum.KeyCode.DPadUp) -- touch uses TouchControls' Light

-- The head light is for everyone else; drop this client's copy of it.
local function hideHeadLight(character)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	local function check(child)
		if child.Name == "TeamFlashlight" then
			child:Destroy()
		end
	end
	head.ChildAdded:Connect(check)
	for _, child in head:GetChildren() do
		check(child)
	end
	-- A new life starts with the light in its default state.
	on = Settings.StartOn
	apply()
end

player.CharacterAdded:Connect(hideHeadLight)
if player.Character then
	task.spawn(hideHeadLight, player.Character)
end

apply()
rig.Parent = camera

RunService:BindToRenderStep("Flashlight", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if rig.Parent ~= camera then
		camera = workspace.CurrentCamera
		rig.Parent = camera
	end
	local target = camera.CFrame
	if not aim then
		aim = target
	end
	-- The beam trails the view a touch when you turn, like a light held in the hand.
	local look = aim.LookVector:Lerp(target.LookVector, 1 - math.exp(-Settings.Sway * dt)).Unit
	aim = CFrame.lookAt(target.Position, target.Position + look, target.UpVector)
	local point = torchPoint()
	local origin = if point then point.WorldPosition else target:PointToWorldSpace(Settings.Offset)
	rig.CFrame = CFrame.new(origin) * aim.Rotation
end)
