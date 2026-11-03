-- The Endless HUD. Owner rule: screens are authored PNG art, never built by script. So this script
-- builds nothing: it drives the zombie mode's authored HUD (StarterGui.HUD, copied from the lobby
-- place into this one) by the same names the lobby's MatchHud and GunClient use:
--   HUD.Match.Wave / HUD.Match.Sub   ROUND n; zombies left, or the time to the next round, and any
--                                    DOUBLE PAY / REAPER time left
--   HUD.Points.Value                 points, counting up; red when you can't afford something
--   HUD.Notice                       the one line for big moments (power, relics, power-ups)
--   HUD.Ammo.Mag/Reserve/Gun/MagBar.Fill   the gun in your hands
--   HUD.Crosshair, HUD.Hitmarker     shown when there's a gun / flashed on a hit
--   HUD.GameOver.Title/Waves         the end of a run
-- Elements of the lobby HUD this mode doesn't use (Clock, Hotbar, Scope, AmmoNote) are hidden.
-- Without a HUD in the place it warns once and the game plays on (prompts and the world carry the
-- rest); with no Crosshair the mouse shows Roblox's own locked-cursor cross.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Endless = ReplicatedStorage:WaitForChild("Endless")
local Config = require(Endless:WaitForChild("Config"))
local Weapons = require(Endless:WaitForChild("Weapons"))
local Net = require(Endless:WaitForChild("Net"))
local Sfx = require(Endless:WaitForChild("Sfx"))

local HUD = Config.Hud
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shownPoints = player:GetAttribute("Points") or 0
local brokeUntil = 0
local hitUntil = 0
local hitKill = false
local warned = false

-- StarterGui only reaches PlayerGui once a character loads, so the warning waits a few seconds past it.
local spawnedAt = if player.Character then os.clock() else nil
player.CharacterAdded:Connect(function()
	spawnedAt = spawnedAt or os.clock()
end)

local function hud()
	local gui = playerGui:FindFirstChild("HUD")
	if not gui and not warned and spawnedAt and os.clock() - spawnedAt > 3 then
		warned = true
		warn("Endless: no StarterGui.HUD in this place. Copy the lobby's HUD here to see rounds, points and ammo.")
	end
	return gui
end

local function find(root, ...)
	local node = root
	for _, name in { ... } do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function setText(label, text)
	if label and label:IsA("TextLabel") and label.Text ~= text then
		label.Text = text
	end
end

local function clock(at)
	local t = math.max(0, math.ceil((at or 0) - workspace:GetServerTimeNow()))
	return string.format("%d:%02d", t // 60, t % 60)
end

-- The one line.
local noticeToken = 0
local function notice(text)
	local label = find(hud(), "Notice")
	if not label or not label:IsA("TextLabel") then
		return
	end
	noticeToken += 1
	local token = noticeToken
	label.Text = text
	label.Visible = true
	label.TextTransparency = 0
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0.4
	end
	task.delay(HUD.NoticeTime, function()
		if token == noticeToken then
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			end
		end
	end)
end

local function timers()
	local now = workspace:GetServerTimeNow()
	local parts = {}
	local pay = workspace:GetAttribute("DoublePayUntil")
	if pay and pay > now then
		table.insert(parts, "DOUBLE PAY " .. math.ceil(pay - now))
	end
	local reaper = workspace:GetAttribute("ReaperUntil")
	if reaper and reaper > now then
		table.insert(parts, "REAPER " .. math.ceil(reaper - now))
	end
	return table.concat(parts, "  \u{00B7}  ")
end

local function update(dt)
	local gui = hud()
	if not gui then
		return
	end
	for _, name in { "Clock", "Hotbar", "Scope", "AmmoNote" } do
		local e = gui:FindFirstChild(name)
		if e and e:IsA("GuiObject") and e.Visible then
			e.Visible = false
		end
	end
	-- The round.
	local state = workspace:GetAttribute("WaveState") or "Waiting"
	local wave = workspace:GetAttribute("Wave") or 0
	local match = gui:FindFirstChild("Match")
	if match then
		match.Visible = state ~= "GameOver"
		setText(match:FindFirstChild("Wave"), if wave > 0 then "ROUND " .. wave else "GET READY")
		local sub = ""
		if state == "Wave" then
			sub = (workspace:GetAttribute("ZombiesLeft") or 0) .. " LEFT"
		elseif state == "Intermission" then
			sub = (if wave > 0 then "NEXT ROUND " else "FIRST ROUND ") .. clock(workspace:GetAttribute("NextWaveAt"))
		end
		local extra = timers()
		if extra ~= "" then
			sub = if sub ~= "" then sub .. "  \u{00B7}  " .. extra else extra
		end
		setText(match:FindFirstChild("Sub"), sub)
	end
	-- Points, counting up.
	local points = gui:FindFirstChild("Points")
	if points then
		local target = player:GetAttribute("Points") or 0
		if shownPoints < target then
			shownPoints = math.min(target, shownPoints + math.max(1, (target - shownPoints) * dt * 8))
		else
			shownPoints = target
		end
		local value = points:FindFirstChild("Value")
		setText(value, tostring(math.floor(shownPoints + 0.5)))
		if value and value:IsA("TextLabel") then
			value.TextColor3 = if os.clock() < brokeUntil then HUD.Red else HUD.White
		end
	end
	-- The gun in hand.
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local stats = tool and tool:GetAttribute("Weapon") and Weapons.ForTool(tool, player)
	local ammo = gui:FindFirstChild("Ammo")
	if ammo then
		ammo.Visible = stats ~= nil
		if stats then
			local mag = tool:GetAttribute("Mag") or 0
			local reserve = tool:GetAttribute("Reserve") or 0
			local level = tool:GetAttribute("Level") or 0
			local magLabel = ammo:FindFirstChild("Mag")
			setText(magLabel, tostring(mag))
			if magLabel and magLabel:IsA("TextLabel") then
				magLabel.TextColor3 = if mag <= math.ceil(stats.Mag * 0.25) then HUD.Red else HUD.White
				magLabel.TextTransparency = if tool:GetAttribute("Reloading") then 0.5 else 0
			end
			setText(ammo:FindFirstChild("Reserve"), tostring(reserve))
			setText(ammo:FindFirstChild("Gun"), string.upper(stats.Name) .. (if level > 0 then "  \u{2726}" .. level else ""))
			local fill = find(ammo, "MagBar", "Fill")
			if fill and fill:IsA("GuiObject") then
				fill.Size = UDim2.new(math.clamp(mag / stats.Mag, 0, 1), 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
			end
		end
	end
	local crosshair = gui:FindFirstChild("Crosshair")
	if crosshair and crosshair:IsA("GuiObject") then
		crosshair.Visible = stats ~= nil and not (character and character:GetAttribute("Downed"))
	end
	local hitmarker = gui:FindFirstChild("Hitmarker")
	if hitmarker and hitmarker:IsA("GuiObject") then
		hitmarker.Visible = os.clock() < hitUntil
		if hitmarker:IsA("ImageLabel") then
			hitmarker.ImageColor3 = if hitKill then HUD.Red else HUD.White
		end
	end
	local over = gui:FindFirstChild("GameOver")
	if over and over:IsA("GuiObject") then
		over.Visible = state == "GameOver"
	end
end

RunService.RenderStepped:Connect(update)

-- The mouse: the authored crosshair, or Roblox's own cross when the HUD has none.
RunService.Heartbeat:Connect(function()
	local hasCross = find(playerGui, "HUD", "Crosshair") ~= nil
	if hasCross then
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
	elseif UserInputService.MouseIcon ~= "rbxasset://textures/MouseLockedCursor.png" then
		UserInputService.MouseIcon = "rbxasset://textures/MouseLockedCursor.png"
	end
end)

player:GetAttributeChangedSignal("Points"):Connect(function()
	if (player:GetAttribute("Points") or 0) < shownPoints then
		shownPoints = player:GetAttribute("Points") or 0
	end
end)

Net.Get("Hud").OnClientEvent:Connect(function(cue, a, b)
	if cue == "Notice" then
		notice(a)
	elseif cue == "Broke" then
		brokeUntil = os.clock() + 0.6
		Sfx.Play("Common/Empty")
	elseif cue == "Hit" then
		hitUntil = os.clock() + (if b then 0.25 else 0.12)
		hitKill = b == true
		Sfx.Play(if b then "Common/Kill" elseif a then "Common/HitHead" else "Common/Hit", { Volume = 0.7 })
	elseif cue == "Round" then
		notice("ROUND " .. a)
	elseif cue == "RoundOver" then
		Sfx.Play("Common/WaveClear")
	elseif cue == "PowerUp" then
		notice(b)
	elseif cue == "Down" then
		notice(string.upper(a) .. " IS DOWN")
	elseif cue == "GameOver" then
		local over = find(hud(), "GameOver")
		setText(find(over, "Title"), "YOU FELL")
		setText(find(over, "Waves"), if a == 1 then "SURVIVED 1 ROUND" else "SURVIVED " .. a .. " ROUNDS")
		if not over then
			notice("GAME OVER  \u{00B7}  ROUND " .. a)
		end
	end
end)
