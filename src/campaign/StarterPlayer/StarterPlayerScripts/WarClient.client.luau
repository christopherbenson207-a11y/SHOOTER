-- WAR's objective on every client (MatchServer's War section sets workspace Objective, a point, and
-- WarObjective, the words): the shared diamond marker (Shared.ObjectiveMarker, the same one Outbreak uses)
-- stands over it, on top of everything, with the objective's name and metres; it breathes slowly, fades
-- when you are on it and is gone when there is none.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObjectiveMarker = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ObjectiveMarker"))

local player = Players.LocalPlayer

local anchor = Instance.new("Part")
anchor.Name = "ObjectiveAnchor"
anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
anchor.Transparency = 1
anchor.Size = Vector3.new(0.2, 0.2, 0.2)
local marker = ObjectiveMarker.new(anchor, Color3.new(1, 1, 1), player:WaitForChild("PlayerGui"))
marker.Gui.Enabled = false

local function refresh()
	local at = workspace:GetAttribute("Objective")
	if typeof(at) == "Vector3" and player:GetAttribute("InMatch") then
		anchor.Position = at
		anchor.Parent = workspace.CurrentCamera
		marker:SetLabel(string.upper(workspace:GetAttribute("WarObjective") or ""))
		marker.Gui.Enabled = true
	else
		marker.Gui.Enabled = false
		anchor.Parent = nil
	end
end
workspace:GetAttributeChangedSignal("Objective"):Connect(refresh)
workspace:GetAttributeChangedSignal("WarObjective"):Connect(refresh)
player:GetAttributeChangedSignal("InMatch"):Connect(refresh)
refresh()
