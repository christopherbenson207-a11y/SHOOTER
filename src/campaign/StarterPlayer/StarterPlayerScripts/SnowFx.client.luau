-- Snowfall over the war map (Operation Last Light only). A wide, invisible cloud rides above the
-- camera and sheds flakes in world space, drifting with a light wind; nothing on the HUD.
local RunService = game:GetService("RunService")

local HEIGHT = 28
local SPAN = 140

local cloud = Instance.new("Part")
cloud.Name = "SnowCloud"
cloud.Anchored = true
cloud.CanCollide = false
cloud.CanQuery = false
cloud.CanTouch = false
cloud.CastShadow = false
cloud.Transparency = 1
cloud.Size = Vector3.new(SPAN, 1, SPAN)

local flakes = Instance.new("ParticleEmitter")
flakes.Texture = "rbxasset://textures/particles/smoke_main.dds"
flakes.Rate = 420
flakes.Lifetime = NumberRange.new(6, 8)
flakes.Speed = NumberRange.new(5, 8)
flakes.EmissionDirection = Enum.NormalId.Bottom
flakes.SpreadAngle = Vector2.new(12, 12)
flakes.Acceleration = Vector3.new(1.6, -0.6, 0.7)
flakes.Size = NumberSequence.new(0.22)
flakes.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.08, 0.15),
	NumberSequenceKeypoint.new(0.85, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
flakes.Color = ColorSequence.new(Color3.fromRGB(236, 240, 246))
flakes.LightEmission = 0.25
flakes.LightInfluence = 0.6
flakes.Rotation = NumberRange.new(0, 360)
flakes.RotSpeed = NumberRange.new(-60, 60)
flakes.Shape = Enum.ParticleEmitterShape.Box
flakes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
flakes.LockedToPart = false
flakes.Parent = cloud

cloud.Parent = workspace

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if camera then
		cloud.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, HEIGHT, 0))
	end
end)
