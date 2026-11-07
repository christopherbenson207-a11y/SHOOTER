-- ViewModeServer (7 Nov 2026): who is in third person (Shared.ViewMode), as the player attribute ThirdPerson.
-- A player in third person plays their own body's gun clips (pack clips, recoil); those replicate, so every other
-- client's WorldGunArms stops playing its own local copy on that player while the attribute is true.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = remotes:FindFirstChild("ViewMode")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "ViewMode"
	remote.Parent = remotes
end

local last = {}

remote.OnServerEvent:Connect(function(player, third)
	if type(third) ~= "boolean" then
		return
	end
	-- At most 12 changes a second per player (a real switch is a few a second at most); past that it's spam.
	local now = os.clock()
	local bucket = last[player]
	if not bucket or now - bucket.Start > 1 then
		bucket = { Start = now, Count = 0 }
		last[player] = bucket
	end
	bucket.Count += 1
	if bucket.Count > 12 then
		return
	end
	player:SetAttribute("ThirdPerson", third)
end)

Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)
