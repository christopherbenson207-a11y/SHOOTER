-- Outlines pickups near you (GameConfig.Pickups.HighlightRange): yellow ammo, green
-- medkits, softly pulsing so they catch the eye in the dark. Taken ones go dark.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local Settings = GameConfig.Pickups

local highlights = {} -- [model] = Highlight

local function colorOf(model)
	local kind = Settings[model:GetAttribute("Kind")]
	return kind and kind.Color or Color3.new(1, 1, 1)
end

local function remove(model)
	local h = highlights[model]
	if h then
		h:Destroy()
		highlights[model] = nil
	end
end

CollectionService:GetInstanceRemovedSignal("Pickup"):Connect(remove)

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	local here = workspace.CurrentCamera.CFrame.Position
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 4)
	for model, h in highlights do
		h.FillTransparency = 0.82 - 0.14 * pulse
		h.OutlineTransparency = 0.25 * (1 - pulse)
	end
	accum += dt
	if accum < 0.2 then
		return
	end
	accum = 0
	for _, model in CollectionService:GetTagged("Pickup") do
		local cf = model:IsDescendantOf(workspace) and model:GetPivot()
		local near = cf and not model:GetAttribute("Taken")
			and (cf.Position - here).Magnitude < Settings.HighlightRange
		if near and not highlights[model] then
			local h = Instance.new("Highlight")
			h.Name = "PickupHighlight"
			h.FillColor = colorOf(model)
			h.OutlineColor = colorOf(model)
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Adornee = model
			h.Parent = model
			highlights[model] = h
		elseif not near and highlights[model] then
			remove(model)
		end
	end
end)
