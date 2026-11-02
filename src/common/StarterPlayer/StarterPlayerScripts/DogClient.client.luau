-- Every dog on this client (DogServer moves them): poses its bones (Shared.DogRig) from how fast it is going and
-- its Pose attribute, lunges for a moment on each bite (BiteAt), and blinks the police dog's blue marker
-- light (its MarkerLight part) in a double flash. Dogs far from the camera aren't posed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DogRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DogRig"))

local POSE_RANGE = 220
local BITE_TIME = 0.35
local BLUE = Color3.fromRGB(76, 166, 255)
local LENS = Color3.fromRGB(28, 52, 86) -- the marker light between flashes

type Entry = { Rig: any, Root: BasePart, Light: PointLight?, Marker: BasePart?, Lit: boolean? }
local dogs: { [Model]: Entry } = {}

local function add(model: Instance)
	if not model:IsA("Model") or dogs[model] then
		return
	end
	if not model:GetAttribute("Dog") then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 10)
	if not root or not model.Parent or dogs[model] then
		return
	end
	local entry: Entry = { Rig = DogRig.new(model, root :: BasePart), Root = root :: BasePart }
	local marker = model:FindFirstChild("MarkerLight", true)
	if marker and marker:IsA("BasePart") then
		local light = Instance.new("PointLight")
		light.Color = BLUE
		light.Range = 8
		light.Brightness = 0
		light.Shadows = false
		light.Parent = marker
		entry.Light, entry.Marker = light, marker
	end
	dogs[model] = entry
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			dogs[model] = nil
		end
	end)
end

local function watch(folder: Instance)
	for _, child in folder:GetChildren() do
		task.spawn(add, child)
	end
	folder.ChildAdded:Connect(function(child)
		task.spawn(add, child)
	end)
end

task.spawn(function()
	watch(workspace:WaitForChild("Dogs"))
end)
task.spawn(function()
	watch(workspace:WaitForChild("Zombies"))
end)

local clock = 0
RunService.RenderStepped:Connect(function(dt)
	clock += dt
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	local now = workspace:GetServerTimeNow()
	-- the marker light: two quick blue flashes every 1.2 s
	local t = clock % 1.2
	local flash = (t < 0.07) or (t > 0.16 and t < 0.23)
	for model, e in dogs do
		local root = e.Root
		if root.Parent and (root.Position - eye).Magnitude < POSE_RANGE then
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local pose = model:GetAttribute("Pose")
			local biteAt = model:GetAttribute("BiteAt")
			if typeof(biteAt) == "number" and now - biteAt < BITE_TIME then
				pose = "Bite"
			end
			e.Rig:Step(dt, speed, if typeof(pose) == "string" then pose else nil)
		end
		if e.Light and e.Marker and e.Lit ~= flash then
			e.Lit = flash
			e.Light.Brightness = if flash then 4 else 0
			e.Marker.Material = if flash then Enum.Material.Neon else Enum.Material.SmoothPlastic
			e.Marker.Color = if flash then BLUE else LENS
		end
	end
end)
