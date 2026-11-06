--!strict
-- MULTIPLAYER: the duel's HUD bar, end card and cue sounds (7 Nov 2026; lobby look 5 Nov 2026, kid
-- reskin). DuelServer runs the match; this script owns:
--   HUD.DuelBar: the score bar, top centre (PNG art from horror-shooter/menu/art/screens/DuelBar.py). Your score in
--     the amber well, theirs in the red one; the middle says the round and its clock, the countdown, the round's
--     result, GET BACK IN THE YARD, or WAITING FOR AN OPPONENT. MatchHud hides its wave block and points in the duel.
--   No round banner (owner, 6 Nov 2026: "no need for round 2 shotgun ui"); MatchHud trims the server's
--     "ROUND n · KIT" notice to just ROUND n.
--   The end card (Shared.EndCard) when WaveState turns "DuelEnd": VICTORY / DEFEAT, the score, PLAY AGAIN (your
--     rematch vote, Remotes.Duel "Rematch"; the note says who is waiting) and LOBBY (Remotes.Duel "Lobby").
--   Keys: R / gamepad X = rematch, gamepad Y = lobby. A gamepad gets PLAY AGAIN selected.
-- Sounds for the server's cues (Remotes.Duel to the client): Found, Countdown, Go, RoundWon, RoundLost, Draw, Won, Lost.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundKit = require(Shared:WaitForChild("SoundKit"))
local EndCard = require(Shared:WaitForChild("EndCard")) :: any
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local duelRemote = Remotes:WaitForChild("Duel") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ACTION = "DuelEndButtons"

local function hud(): Instance?
	return playerGui:FindFirstChild("HUD")
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

local function clock(at: any): string
	if typeof(at) ~= "number" then
		return ""
	end
	local left = math.max(0, math.ceil(at - workspace:GetServerTimeNow()))
	return ("%d:%02d"):format(left // 60, left % 60)
end

-- The bar is drawn at 640 px but shown smaller (owner, 6 Nov 2026: "too big"); narrow screens shrink it further.
local BAR_MAX = 0.62

local function fitWidth(gui: GuiObject, width: number, max: number): number
	local scale = gui:FindFirstChildOfClass("UIScale")
	local camera = workspace.CurrentCamera
	local s = max
	if camera then
		s = math.clamp(camera.ViewportSize.X * 0.6 / width, 0.4, max)
	end
	if scale then
		scale.Scale = s
	end
	return s
end

-- The bar's top edge: under the Roblox buttons and the Settings gear (top left) when the screen is too narrow for
-- the bar to sit clear of them beside its centre.
local function topY(): number
	local camera = workspace.CurrentCamera
	return if camera and camera.ViewportSize.X < 1100 then 84 else 14
end

local function setText(parent: Instance, name: string, text: string)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- The bar ---------------------------------------------------------------------------------------------------------

local function midText(state: string): string
	local round = workspace:GetAttribute("DuelRound") or 0
	if state == "DuelWait" then
		return "WAITING FOR AN OPPONENT"
	elseif state == "DuelCount" then
		local left = math.max(0, math.ceil((workspace:GetAttribute("DuelEndsAt") or 0) - workspace:GetServerTimeNow()))
		return if round > 0 then ("ROUND %d  ·  %d"):format(round, left) else tostring(left)
	elseif state == "DuelRound" then
		local w = workspace:GetAttribute("DuelRoundWinner")
		return if w == 0 then "DRAW" elseif w == player.UserId then "ROUND WON" else "ROUND LOST"
	elseif state == "DuelEnd" then
		return if workspace:GetAttribute("DuelWinner") == player.UserId then "VICTORY" else "DEFEAT"
	elseif state == "Duel" then
		local outAt = player:GetAttribute("DuelOutAt")
		if type(outAt) == "number" then
			local left = math.ceil(outAt - workspace:GetServerTimeNow())
			return if left > 0 then "BACK IN THE YARD  ·  " .. left else "BACK IN THE YARD"
		end
		return ("ROUND %d  ·  %s"):format(round, clock(workspace:GetAttribute("DuelEndsAt")))
	end
	return "1 V 1"
end

local function updateBar()
	local gui = hud()
	local bar = gui and gui:FindFirstChild("DuelBar")
	if not bar or not bar:IsA("GuiObject") then
		return
	end
	local on = workspace:GetAttribute("Duel") == true
	bar.Visible = on
	if not on then
		return
	end
	fitWidth(bar, 640, BAR_MAX)
	bar.Position = UDim2.new(0.5, 0, 0, topY())
	local them = opponent()
	setText(bar, "You", tostring(player:GetAttribute("DuelScore") or 0))
	setText(bar, "Them", tostring(if them then them:GetAttribute("DuelScore") or 0 else 0))
	setText(bar, "ThemName", string.upper(if them then them.DisplayName else "OPPONENT"))
	local mid = bar:FindFirstChild("Mid")
	if mid and mid:IsA("TextLabel") then
		local state = workspace:GetAttribute("WaveState") or ""
		mid.Text = midText(state)
		mid.TextColor3 = if state == "Duel" and type(player:GetAttribute("DuelOutAt")) == "number"
			then EndCard.Color.AMBER
			else EndCard.Color.TEXT
	end
end

task.spawn(function()
	while true do
		updateBar()
		task.wait(0.2)
	end
end)

-- The end card -----------------------------------------------------------------------------------------------------

local function ask(action: string)
	if workspace:GetAttribute("WaveState") ~= "DuelEnd" then
		return
	end
	duelRemote:FireServer(action)
end

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

local card: any = nil

local function cardNote(): string
	if workspace:GetAttribute("DuelReason") == "Left" then
		return ""
	end
	local them = opponent()
	local name = string.upper(if them then them.DisplayName else "OPPONENT")
	local closes = clock(workspace:GetAttribute("DuelEndsAt"))
	if player:GetAttribute("Rematch") == true then
		return "WAITING FOR " .. name .. "  ·  " .. closes
	elseif them and them:GetAttribute("Rematch") == true then
		return name .. " WANTS A REMATCH  ·  " .. closes
	end
	return "REMATCH CLOSES IN " .. closes
end

local function show()
	local gui = hud()
	if card or not gui then
		return
	end
	local won = workspace:GetAttribute("DuelWinner") == player.UserId
	local left = workspace:GetAttribute("DuelReason") == "Left"
	local them = opponent()
	local stats = if left
		then "YOUR OPPONENT LEFT"
		else ("YOU %d  ·  %d %s"):format(player:GetAttribute("DuelScore") or 0,
			(if them then them:GetAttribute("DuelScore") else 0) or 0,
			string.upper(if them then them.DisplayName else "OPPONENT"))
	local mine
	mine = EndCard.Show(gui, {
		Result = if won then "Victory" else "Defeat",
		Stats = stats,
		Note = cardNote(),
		PlayAgain = function()
			ask("Rematch")
		end,
		Lobby = function()
			ask("Lobby")
		end,
		ZIndex = 60,
	})
	card = mine
	if mine.PlayAgain then
		mine.PlayAgain.Modal = true -- frees the mouse in first person
		if left and mine.SetPlayAgainDisabled then
			mine.SetPlayAgainDisabled(true)
		end
	end
	ContextActionService:BindActionAtPriority(ACTION, onKey, false, Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.R, Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY)
	if UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:find("Gamepad") then
		GuiService.SelectedObject = mine.PlayAgain
	end
	task.spawn(function()
		while card == mine do
			mine.SetNote(cardNote())
			task.wait(0.25)
		end
	end)
end

local function hide()
	if not card then
		return
	end
	local mine = card
	card = nil
	ContextActionService:UnbindAction(ACTION)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(mine.Root) then
		GuiService.SelectedObject = nil
	end
	mine.Destroy()
end

local function onState()
	updateBar()
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
