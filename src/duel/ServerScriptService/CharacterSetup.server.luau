-- Puts every player character in the "Characters" collision group, which never collides
-- with "Debris" (casings, dropped mags, severed limbs, corpses).
-- Hitboxes (5 Nov 2026 duel pass): a character's gear is not part of its hitbox. Every part inside an Accessory
-- (hats, hair, the operator's helmet and plate carrier) and inside the held gun (WorldGun) stops being seen by
-- raycasts and touches, so a helmet can't swallow a headshot as a body hit and a big hat can't widen anyone.
-- Set here on the server, so it replicates to every client's raycasts too. The hit zones are GameConfig.Pvp.Zones.

local Players = game:GetService("Players")

local function isGear(part, character)
	local node = part.Parent
	while node and node ~= character do
		if node:IsA("Accessory") or node.Name == "WorldGun" then
			return true
		end
		node = node.Parent
	end
	return false
end

local function setup(part, character)
	if not part:IsA("BasePart") then
		return
	end
	part.CollisionGroup = "Characters"
	if isGear(part, character) then
		part.CanCollide = false -- CanQuery can only go off on a part that doesn't collide
		part.CanQuery = false
		part.CanTouch = false
	end
end

local function onCharacter(character)
	for _, d in character:GetDescendants() do
		setup(d, character)
	end
	character.DescendantAdded:Connect(function(d)
		setup(d, character)
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
