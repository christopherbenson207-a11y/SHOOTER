-- Watching your team while you wait (GameConfig.Lives). After a death mid-run the screen used
-- to stay black until the next lull; now, once the devour black (and the death cam,
-- PlayerHealthClient) is done, the black lifts on a living teammate and the camera follows them.
-- Click, tap or press the jump button to watch the next one. A new body (a respawn, or the next
-- run) takes the camera back. Nothing to watch (nobody standing): the black stays.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WAIT = 3.6 -- seconds after the death before the watch starts

local watching = nil -- the teammate's Player
local active = false

local function standing(p)
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and p:GetAttribute("InMatch") == true
end

local function teammates()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and standing(p) then
			table.insert(list, p)
		end
	end
	return list
end

local function notice(text)
	local hud = playerGui:FindFirstChild("HUD")
	local label = hud and hud:FindFirstChild("Notice")
	if label then
		label.Text = text
		label.TextTransparency = 0
		task.delay(3, function()
			if label.Text == text then
				TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
			end
		end)
	end
end

local function watch(p)
	watching = p
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	notice("WATCHING " .. string.upper(p.DisplayName))
end

-- The next standing teammate after the one watched (or the first).
local function nextOne()
	local list = teammates()
	if #list == 0 then
		return nil
	end
	local i = table.find(list, watching) or 0
	return list[i % #list + 1]
end

local function setBlack(on)
	local hud = playerGui:FindFirstChild("HUD")
	local blackout = hud and hud:FindFirstChild("Blackout")
	if blackout then
		TweenService:Create(blackout, TweenInfo.new(0.8), { BackgroundTransparency = if on then 0 else 1 }):Play()
	end
end

local function start(character)
	task.wait(WAIT)
	while player:GetAttribute("DeathCam") do
		task.wait(0.1)
	end
	if player.Character ~= character or not player:GetAttribute("InMatch") then
		return
	end
	active = true
	while active and player.Character == character do
		if not watching or not standing(watching) then
			local p = nextOne()
			if p then
				watch(p)
				setBlack(false)
			elseif watching then
				watching = nil
				setBlack(true)
			end
		end
		task.wait(0.5)
	end
end

local function onCharacter(character)
	active = false
	watching = nil
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Once(function()
		task.spawn(start, character)
	end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not active or not watching or processed then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA
		or input.KeyCode == Enum.KeyCode.Space
	then
		local p = nextOne()
		if p and p ~= watching then
			watch(p)
		end
	end
end)

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)
