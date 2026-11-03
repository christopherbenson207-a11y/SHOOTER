-- The Endless remotes, in ReplicatedStorage.Endless.Remotes. The server makes them at boot
-- (Net.Get creates what is missing); clients wait for them.
--   Weapon (client -> server): "Fire" (tool, origin, directions, claims), "Reload" (tool),
--     "Melee" ().
--   Fx (server -> clients): world effects: "Shot" (userId, weaponId, origin, ends), "Blood"
--     (position, normal, amount), "Gib" (position), "Swing" (zombie), "Box" (state...).
--   Hud (server -> clients): screen cues: "Notice" (text), "Broke", "Round" (n), "RoundOver" (n),
--     "GameOver" (round), "Hit" (head, killed), "Hurt", "PowerUp" (kind), "Down" (name).

local RunService = game:GetService("RunService")

local Net = {}

local root = script.Parent
local NAMES = { "Weapon", "Fx", "Hud" }

local function container()
	local f = root:FindFirstChild("Remotes")
	if not f and RunService:IsServer() then
		f = Instance.new("Folder")
		f.Name = "Remotes"
		f.Parent = root
	end
	return f or root:WaitForChild("Remotes")
end

function Net.Get(name: string): RemoteEvent
	local f = container()
	local r = f:FindFirstChild(name)
	if not r then
		if RunService:IsServer() then
			r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = f
		else
			r = f:WaitForChild(name)
		end
	end
	return r
end

-- Server: make every remote before any client asks.
function Net.Make()
	for _, name in NAMES do
		Net.Get(name)
	end
end

return Net
