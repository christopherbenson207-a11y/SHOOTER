--!strict
-- Snowfall (4 Nov 2026): light snow over the campaign's winter town, client only. One anchored, invisible emitter
-- box rides 26 studs above the camera; flakes are the engine's built-in soft puff texture drawn tiny, drifting with a
-- slow wind. Graphics "Low" (Options) turns it off; Medium halves it; touch devices get 60%. Workspace attribute
-- Snow = false turns it off for the whole server (e.g. a mission indoors).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RATE = 110 -- flakes per second at High (about 750 alive; phones get 60%)
local BOX = Vector3.new(90, 1, 90)
local HEIGHT = 26
local WIND = Vector3.new(1.6, 0, 0.8)

local Options: any = nil
do
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	local m = shared and shared:FindFirstChild("Options")
	if m then
		local ok, t = pcall(require, m)
		if ok then
			Options = t
		end
	end
end

local box = Instance.new("Part")
box.Name = "SnowBox"
box.Size = BOX
box.Transparency = 1
box.Anchored = true
box.CanCollide = false
box.CanQuery = false
box.CanTouch = false
box.CastShadow = false

local flakes = Instance.new("ParticleEmitter")
flakes.Name = "Flakes"
flakes.Texture = "rbxasset://textures/particles/smoke_main.dds"
flakes.EmissionDirection = Enum.NormalId.Bottom
flakes.Shape = Enum.ParticleEmitterShape.Box
flakes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
flakes.Lifetime = NumberRange.new(5.5, 7.5)
flakes.Speed = NumberRange.new(4, 6.5)
flakes.Acceleration = WIND
flakes.SpreadAngle = Vector2.new(12, 12)
flakes.Rotation = NumberRange.new(0, 360)
flakes.RotSpeed = NumberRange.new(-40, 40)
flakes.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.16),
	NumberSequenceKeypoint.new(1, 0.1),
})
flakes.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.08, 0.15),
	NumberSequenceKeypoint.new(0.85, 0.25),
	NumberSequenceKeypoint.new(1, 1),
})
flakes.Color = ColorSequence.new(Color3.fromRGB(244, 246, 252))
flakes.LightInfluence = 1
flakes.LightEmission = 0
flakes.Brightness = 1.4
flakes.Rate = RATE
flakes.Parent = box
box.Parent = workspace

local function rate(): number
	if workspace:GetAttribute("Snow") == false then
		return 0
	end
	local g = Options and Options.Get and Options.Get("Graphics")
	local base = if UserInputService.TouchEnabled then RATE * 0.6 else RATE
	if g == "Low" then
		return base * 0.35 -- light snow even on Low: the winter look shouldn't vanish on weak phones
	elseif g == "Medium" then
		return base * 0.6
	end
	return base
end

local function refresh()
	local r = rate()
	flakes.Rate = r
	flakes.Enabled = r > 0
end
refresh()
workspace:GetAttributeChangedSignal("Snow"):Connect(refresh)
if Options and Options.Changed then
	Options.Changed:Connect(function(key: string)
		if key == "Graphics" then
			refresh()
		end
	end)
end

-- follow the camera (flakes already in the air stay where they are, so turning or running looks right)
RunService:BindToRenderStep("Snowfall", Enum.RenderPriority.Camera.Value + 10, function()
	local cam = workspace.CurrentCamera
	if cam then
		local p = cam.CFrame.Position
		box.CFrame = CFrame.new(p.X, p.Y + HEIGHT, p.Z)
	end
end)

Players.LocalPlayer.AncestryChanged:Connect(function()
	RunService:UnbindFromRenderStep("Snowfall")
	box:Destroy()
end)
