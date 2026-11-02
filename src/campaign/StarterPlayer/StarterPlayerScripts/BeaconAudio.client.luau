-- The Beacon heard from indoors: every Beacon sound plays through SoundService.Beacon. Under
-- a roof its drone (Head.Siren) fades out altogether and the rest (steps, smashes, the alarm)
-- comes through dull and quiet, as through walls; outside it all plays as it is.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local group = SoundService:WaitForChild("Beacon")
local muffle = group:WaitForChild("Muffle")
local beacon = workspace:WaitForChild("Beacon")

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local indoors = false
local k = 0 -- 0 outside, 1 indoors, eased
local checkAt = 0
local sirenVolume = nil

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	if now >= checkAt then
		checkAt = now + 0.2
		-- A roof: any building (or the house) above the camera; trees and lamps don't count.
		local map = workspace:FindFirstChild("Map")
		local town = map and map:FindFirstChild("Town")
		local roofs = { town and town:FindFirstChild("Buildings") }
		for _, child in map and map:GetChildren() or {} do
			if child:GetAttribute("DefendHouse") then
				table.insert(roofs, child)
			end
		end
		if #roofs > 0 then
			params.FilterDescendantsInstances = roofs
			local at = workspace.CurrentCamera.CFrame.Position
			indoors = workspace:Raycast(at, Vector3.new(0, 60, 0), params) ~= nil
		end
	end
	k += ((if indoors then 1 else 0) - k) * math.min(1, dt * 4)
	group.Volume = 1 - 0.6 * k
	muffle.HighGain = -45 * k
	muffle.MidGain = -20 * k
	local head = beacon:FindFirstChild("Head")
	local siren = head and head:FindFirstChild("Siren")
	if siren then
		sirenVolume = sirenVolume or siren.Volume
		siren.Volume = sirenVolume * (1 - k)
	end
end)
