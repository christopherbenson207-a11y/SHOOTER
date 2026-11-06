-- Holds players in the menu (StarterPlayerScripts.MenuClient) until they press PLAY: characters
-- don't load on join. PLAY (Remotes.Menu "Play", mode) spawns you in that mode and you
-- respawn there after dying (Players.RespawnTime, set by PlayerHealth), unless the match holds
-- respawns (workspace attribute HoldRespawns, set by MatchServer, which brings the dead back
-- at the next intermission). Each player's avatar
-- is built once into ReplicatedStorage.MenuAvatars/<UserId> for the menu room to show.
-- Player attributes: InMatch (bool), Mode (one of GameConfig.Menu.Modes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Uniform = require(game:GetService("ServerStorage").Modules.Uniform)
local Profile = require(game:GetService("ServerStorage").Modules.Profile)
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.Menu

Players.CharacterAutoLoads = false

local avatars = Instance.new("Folder")
avatars.Name = "MenuAvatars"
avatars.Parent = ReplicatedStorage

local function buildAvatar(player)
	-- In the police uniform, like the character they'll play.
	local ok, model = pcall(function()
		local description = Uniform.Description(player.UserId)
		if description then
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end
		return Players:CreateHumanoidModelFromUserId(player.UserId)
	end)
	if not ok or not model then
		warn("MenuServer: no avatar for", player.Name, model)
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	model.Name = tostring(player.UserId)
	model.Parent = avatars
end

local function onCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Once(function()
		task.delay(Players.RespawnTime, function()
			if player.Parent and player:GetAttribute("InMatch") and player.Character == character
				and not workspace:GetAttribute("HoldRespawns")
			then
				Uniform.Load(player)
			end
		end)
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	task.spawn(buildAvatar, player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	local model = avatars:FindFirstChild(tostring(player.UserId))
	if model then
		model:Destroy()
	end
end)

Remotes.Menu.OnServerEvent:Connect(function(player, action, mode)
	if action ~= "Play" or player:GetAttribute("InMatch") then
		return
	end
	-- A locked mode (GameConfig.Modes Unlock, a Profile flag) falls back to the first one. A
	-- run already going keeps its own mode: you join that.
	local rules = GameConfig.Modes[mode or ""]
	if not table.find(CFG.Modes, mode) or not rules or (rules.Unlock and not Profile.Get(player)[rules.Unlock]) then
		mode = CFG.Modes[1]
	end
	local running = workspace:GetAttribute("WaveState")
	if running and running ~= "Waiting" and workspace:GetAttribute("Mode") then
		mode = workspace:GetAttribute("Mode")
	end
	player:SetAttribute("Mode", mode)
	player:SetAttribute("InMatch", true)
	Uniform.Load(player)
end)
