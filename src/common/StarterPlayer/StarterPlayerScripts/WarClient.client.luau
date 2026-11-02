-- WAR's objective on every client (MatchServer's War section sets workspace Objective, a point):
-- the authored diamond (ReplicatedStorage.Assets.ObjectiveMarker) stands over it, on top of
-- everything, breathing slowly; it fades when you are on it and is gone when there is none.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("ObjectiveMarker")

local anchor = Instance.new("Part")
anchor.Name = "ObjectiveAnchor"
anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
anchor.Transparency = 1
anchor.Size = Vector3.new(0.2, 0.2, 0.2)
local marker = template:Clone()
marker.Adornee = anchor
marker.Enabled = false
marker.Parent = player:WaitForChild("PlayerGui")
local diamond = marker:WaitForChild("Diamond")

local function refresh()
	local at = workspace:GetAttribute("Objective")
	if typeof(at) == "Vector3" and player:GetAttribute("InMatch") then
		anchor.Position = at
		anchor.Parent = workspace.CurrentCamera
		marker.Enabled = true
	else
		marker.Enabled = false
		anchor.Parent = nil
	end
end
workspace:GetAttributeChangedSignal("Objective"):Connect(refresh)
player:GetAttributeChangedSignal("InMatch"):Connect(refresh)
refresh()

RunService.RenderStepped:Connect(function()
	if not marker.Enabled then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local near = root and (root.Position - anchor.Position).Magnitude or 999
	local breathe = 1 + math.sin(os.clock() * 3) * 0.06
	diamond.Size = UDim2.fromScale(breathe, breathe)
	diamond.ImageTransparency = math.clamp(1 - (near - 6) / 14, 0, 0.85)
end)
