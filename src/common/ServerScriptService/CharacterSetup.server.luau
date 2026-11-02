-- Puts every player character in the "Characters" collision group, which never collides
-- with "Debris" (casings, dropped mags, severed limbs, corpses).

local Players = game:GetService("Players")

local function setGroup(part)
	if part:IsA("BasePart") then
		part.CollisionGroup = "Characters"
	end
end

local function onCharacter(character)
	for _, d in character:GetDescendants() do
		setGroup(d)
	end
	character.DescendantAdded:Connect(setGroup)
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
