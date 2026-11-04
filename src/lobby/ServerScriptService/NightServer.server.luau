-- Gives every character a head flashlight the other players see. The owner's client hides
-- its own copy and draws a camera-mounted light instead (StarterPlayerScripts.Flashlight).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = ReplicatedStorage.Remotes

local Settings = GameConfig.Night.Flashlight

local function lightOf(character)
	local head = character and character:FindFirstChild("Head")
	return head and head:FindFirstChild("TeamFlashlight")
end

-- The player's chosen beam colour (attribute Beam, Shared.Catalogue "Beam/<Id>".Color); Warm keeps GameConfig's.
local function beamColor(player)
	local id = player and player:GetAttribute("Beam")
	if type(id) ~= "string" or id == "" or id == "Warm" then
		return Settings.Color
	end
	local ok, Catalogue = pcall(require, ReplicatedStorage.Shared:FindFirstChild("Catalogue"))
	local item = ok and type(Catalogue) == "table" and type(Catalogue.Items) == "table" and Catalogue.Items["Beam/" .. id]
	return if item and typeof(item.Color) == "Color3" then item.Color else Settings.Color
end

local function setup(character)
	local head = character:WaitForChild("Head", 10)
	if not head then
		return
	end
	local light = Instance.new("SpotLight")
	light.Name = "TeamFlashlight"
	light.Face = Enum.NormalId.Front
	light.Angle = Settings.TeamAngle
	light.Range = Settings.TeamRange
	light.Brightness = Settings.TeamBrightness
	light.Color = beamColor(Players:GetPlayerFromCharacter(character))
	light.Shadows = true
	light.Enabled = Settings.StartOn
	light.Parent = head
	character:SetAttribute("Flashlight", Settings.StartOn)
end

local function watchBeam(player)
	player:GetAttributeChangedSignal("Beam"):Connect(function()
		local light = lightOf(player.Character)
		if light then
			light.Color = beamColor(player)
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	watchBeam(player)
	player.CharacterAdded:Connect(setup)
	if player.Character then
		setup(player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	watchBeam(player)
	player.CharacterAdded:Connect(setup)
	if player.Character then
		task.spawn(setup, player.Character)
	end
end

Remotes.Flashlight.OnServerEvent:Connect(function(player, on)
	if typeof(on) ~= "boolean" then
		return
	end
	local character = player.Character
	local light = lightOf(character)
	if light then
		light.Enabled = on
		character:SetAttribute("Flashlight", on)
	end
end)
