-- Measures each fall from its highest point to where you land and tells the server
-- (ServerScriptService.FallDamage), which decides the damage. Being carried, climbed or
-- anchored by a cutscene doesn't count.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local SAFE = GameConfig.Match.FallDamage.Safe
local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fall")

local peak = nil
local lastPos = root.Position

local function excused()
	return root.Anchored or character:GetAttribute("Grabbed") or player:GetAttribute("Cutscene")
end

humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Freefall or new == Enum.HumanoidStateType.Jumping then
		peak = math.max(peak or root.Position.Y, root.Position.Y)
	elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
		if peak and not excused() then
			local drop = peak - root.Position.Y
			if drop > SAFE then
				remote:FireServer(drop)
			end
		end
		peak = nil
	elseif new ~= Enum.HumanoidStateType.FallingDown then
		peak = nil
	end
end)

-- A jump of more than TELEPORT studs in one frame is a teleport, not a fall.
local TELEPORT = 30
RunService.Heartbeat:Connect(function()
	local pos = root.Position
	local moved = (pos - lastPos).Magnitude
	lastPos = pos
	if peak then
		if excused() or moved > TELEPORT then
			peak = nil
		else
			peak = math.max(peak, root.Position.Y)
		end
	end
end)
