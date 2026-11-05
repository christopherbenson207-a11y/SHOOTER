-- Endless relics (ServerStorage.Modules.Relics): the candles flicker, and once you've taken this
-- round's relic the three sigils go dark for you alone (the others still see theirs). Your pick is
-- the player attribute RelicRound; it's this round's when it matches workspace Wave.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local dark = {} -- [model] = true while darkened for us

local function setDark(model, on)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if on then 1 else 0
		elseif d:IsA("PointLight") then
			d.Enabled = not on
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = not on
		end
	end
end

RunService.Heartbeat:Connect(function()
	local folder = workspace:FindFirstChild("Relics")
	if not folder then
		return
	end
	local picked = player:GetAttribute("RelicRound") ~= nil and player:GetAttribute("RelicRound") == workspace:GetAttribute("Wave")
	local t = os.clock()
	for i, model in folder:GetChildren() do
		if (dark[model] == true) ~= picked then
			dark[model] = if picked then true else nil
			setDark(model, picked)
		end
		if not picked then
			local flame = model:FindFirstChild("Flame")
			local light = flame and flame:FindFirstChildOfClass("PointLight")
			if light then
				light.Brightness = 1.4 + 0.5 * math.noise(t * 7, i * 3.1)
			end
		end
	end
end)
