--!strict
-- MULTIPLAYER: the duel's end screen and cue sounds (7 Nov 2026). DuelServer runs the match; MatchHud shows the
-- score and clock; this script owns HUD.DuelEnd, the authored panel with the REMATCH and LOBBY buttons (PNG art from
-- horror-shooter/menu/art/duel_buttons.py, ids on the buttons' ArtIdle / ArtHover / ArtDown / ArtWaiting attributes).
--   The panel comes up when WaveState turns "DuelEnd" and goes when it leaves.
--   REMATCH toggles your vote (Remotes.Duel "Rematch"); while you wait for the other player it shows the waiting art.
--   LOBBY sends you back (Remotes.Duel "Lobby").
--   Keys: R / gamepad X = rematch, gamepad Y = lobby. A gamepad also gets REMATCH selected for the D-pad.
-- Sounds for the server's cues (Remotes.Duel to the client): Found, Countdown, Go, RoundWon, RoundLost, Draw, Won, Lost.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SoundKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundKit"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local duelRemote = Remotes:WaitForChild("Duel") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local AMBER = Color3.fromRGB(255, 176, 60)
local WHITE = Color3.fromRGB(240, 238, 232)
local ACTION = "DuelEndButtons"

local function panel(): Frame?
	local hud = playerGui:FindFirstChild("HUD")
	local f = hud and hud:FindFirstChild("DuelEnd")
	return if f and f:IsA("Frame") then f else nil
end

local function opponent(): Player?
	local mine = player:GetAttribute("DuelSlot")
	for _, p in Players:GetPlayers() do
		local slot = p:GetAttribute("DuelSlot")
		if p ~= player and slot and slot ~= mine then
			return p
		end
	end
	return nil
end

-- Buttons ------------------------------------------------------------------------------------------------------------

local function art(button: ImageButton, waiting: boolean)
	local idle = button:GetAttribute("ArtIdle")
	local hover = button:GetAttribute("ArtHover")
	local down = button:GetAttribute("ArtDown")
	local wait = button:GetAttribute("ArtWaiting")
	if waiting and wait then
		button.Image, button.HoverImage, button.PressedImage = wait, wait, wait
	elseif idle then
		button.Image, button.HoverImage, button.PressedImage = idle, hover or idle, down or idle
	end
end

local function ask(action: string)
	if workspace:GetAttribute("WaveState") ~= "DuelEnd" then
		return
	end
	duelRemote:FireServer(action)
end

local wired: { [Instance]: boolean } = {}
local function wire(f: Frame)
	if wired[f] then
		return
	end
	wired[f] = true
	local row = f:FindFirstChild("Buttons")
	local rematch = row and row:FindFirstChild("Rematch")
	local lobby = row and row:FindFirstChild("Lobby")
	if rematch and rematch:IsA("ImageButton") then
		rematch.Activated:Connect(function()
			ask("Rematch")
		end)
	end
	if lobby and lobby:IsA("ImageButton") then
		lobby.Activated:Connect(function()
			ask("Lobby")
		end)
	end
end

local function refreshRematch()
	local f = panel()
	local row = f and f:FindFirstChild("Buttons")
	local rematch = row and row:FindFirstChild("Rematch")
	if rematch and rematch:IsA("ImageButton") then
		art(rematch, player:GetAttribute("Rematch") == true)
	end
end
player:GetAttributeChangedSignal("Rematch"):Connect(refreshRematch)

-- Phones get the buttons a little smaller so both fit side by side on a narrow screen.
local function fitPhone(f: Frame)
	local row = f:FindFirstChild("Buttons")
	local scale = row and row:FindFirstChildOfClass("UIScale")
	local camera = workspace.CurrentCamera
	if scale and camera then
		scale.Scale = math.clamp(camera.ViewportSize.X / 680, 0.7, 1)
	end
end

-- The screen ---------------------------------------------------------------------------------------------------------

local shown = false

local function onKey(_: string, state: Enum.UserInputState, input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonX then
		ask("Rematch")
	elseif input.KeyCode == Enum.KeyCode.ButtonY then
		ask("Lobby")
	end
	return Enum.ContextActionResult.Sink
end

local function show()
	local f = panel()
	if not f or shown then
		return
	end
	shown = true
	wire(f)
	fitPhone(f)
	refreshRematch()
	local won = workspace:GetAttribute("DuelWinner") == player.UserId
	-- fwjelaa-ignore: findfirstchild-chain (a type cast, nil-checked below)
	local title = f:FindFirstChild("Title") :: TextLabel?
	-- fwjelaa-ignore: findfirstchild-chain (a type cast, nil-checked below)
	local line = f:FindFirstChild("Line") :: TextLabel?
	if title then
		title.Text = if won then "VICTORY" else "DEFEAT"
		title.TextColor3 = if won then AMBER else WHITE
		title.TextTransparency = 1
	end
	if line then
		local other = opponent()
		local mine = player:GetAttribute("DuelScore") or 0
		local theirs = (other and other:GetAttribute("DuelScore")) or 0
		if workspace:GetAttribute("DuelReason") == "Left" then
			line.Text = "YOUR OPPONENT LEFT"
		else
			line.Text = ("YOU %d  ·  %d %s"):format(mine, theirs, string.upper(if other then other.DisplayName else "OPPONENT"))
		end
		line.TextTransparency = 1
	end
	f.BackgroundTransparency = 1
	f.Visible = true
	TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 0.25 }):Play()
	if title then
		TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	end
	if line then
		TweenService:Create(line, TweenInfo.new(0.9), { TextTransparency = 0 }):Play()
	end
	ContextActionService:BindActionAtPriority(ACTION, onKey, false, Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.R, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY)
	if UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:find("Gamepad") then
		local row = f:FindFirstChild("Buttons")
		-- fwjelaa-ignore: findfirstchild-chain (guarded by row and; nil clears the selection)
		GuiService.SelectedObject = row and row:FindFirstChild("Rematch") :: GuiObject?
	end
end

local function hide()
	if not shown then
		return
	end
	shown = false
	ContextActionService:UnbindAction(ACTION)
	local f = panel()
	if not f then
		return
	end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(f) then
		GuiService.SelectedObject = nil
	end
	local fade = TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
	for _, name in { "Title", "Line" } do
		local label = f:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		end
	end
	fade:Play()
	fade.Completed:Once(function()
		if not shown then
			f.Visible = false
		end
	end)
end

local function onState()
	if workspace:GetAttribute("WaveState") == "DuelEnd" then
		-- The winner attribute lands in the same frame as the state; a beat lets both replicate.
		task.delay(0.1, function()
			if workspace:GetAttribute("WaveState") == "DuelEnd" then
				show()
			end
		end)
	else
		hide()
	end
end
workspace:GetAttributeChangedSignal("WaveState"):Connect(onState)
onState()

-- Cue sounds ---------------------------------------------------------------------------------------------------------

local SOUNDS: { [string]: { string } } = {
	Found = { "War/Whistle" },
	Go = { "War/Whistle" },
	RoundWon = { "Common/WaveClear" },
	RoundLost = { "Player/Down" },
	Draw = { "Common/MagDrop" },
	Won = { "Common/WaveClear", "Night/Stinger" },
	Lost = { "Night/Stinger" },
}

-- One tick a second through the countdown, timed off the server clock.
local counting = 0
local function countdown()
	counting += 1
	local mine = counting
	local endsAt = workspace:GetAttribute("DuelEndsAt")
	if typeof(endsAt) ~= "number" then
		return
	end
	while counting == mine do
		local left = endsAt - workspace:GetServerTimeNow()
		if left <= 0.05 or workspace:GetAttribute("WaveState") ~= "DuelCount" then
			break
		end
		SoundKit.Play("Night/FlashlightClick", { Volume = 1.2 })
		task.wait(left - math.floor(left - 0.001))
	end
end

duelRemote.OnClientEvent:Connect(function(cue)
	if typeof(cue) ~= "string" then
		return
	end
	if cue == "Countdown" then
		task.spawn(countdown)
		return
	end
	for _, name in SOUNDS[cue] or {} do
		SoundKit.Play(name)
	end
end)

player.AncestryChanged:Connect(function()
	ContextActionService:UnbindAction(ACTION)
end)
