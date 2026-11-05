-- The Defend match on the HUD (authored in StarterGui.HUD): the wave and what's left of it
-- top left (HUD.Match), points top right (HUD.Points, ticking up quietly, red flash when you
-- can't afford something), one line for big moments (HUD.Notice: doors open, breakout, evac,
-- the Beacon, a teammate taken) and the end of a lost run (HUD.GameOver; a run that gets out
-- ends in StarterPlayerScripts.RescueClient). During the breakout the
-- wave block shows the way out: the helicopter countdown and the distance to the landing
-- zone, then GRAB THE LADDER while it's there. State comes from MatchServer's workspace
-- attributes and Remotes.Match. In nights (workspace Nights) the block reads NIGHT n with the
-- time to dawn, and in a lull the time to dusk; "Return" is the lull's one line.
-- In nights the ring (HUD.Clock, GameConfig.Hud) takes the block's place: Night colour and the
-- night number, filling until dawn; Lull colour and the seconds, draining until dusk, beating
-- in the last ReturnWarn seconds; Last colour on the last night. The part you carry
-- (character CarryingPart) shows beside it. The block comes back for the breakout and for
-- wave modes.
-- Outbreak (WaveState Outbreak): the block reads the time to the last bird, and one line under it:
-- the contract, the helicopter, Scrip to bank, or where the radio is (outbreakText).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SoundKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundKit"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowerParts = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("TowerParts")

local HUDCFG = GameConfig.Hud
local NIGHTS = GameConfig.Nights

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local AMBER = Color3.fromRGB(255, 176, 60)
local WHITE = Color3.fromRGB(240, 238, 232)
local RED = Color3.fromRGB(230, 70, 60)

local shownPoints = player:GetAttribute("Points") or 0
local brokeUntil = 0
local pulseUntil = 0

local function hud()
	return playerGui:FindFirstChild("HUD")
end

local function evacLeft()
	local at = workspace:GetAttribute("EvacAt")
	return at and math.max(0, math.ceil(at - workspace:GetServerTimeNow()))
end

local function zoneDistance()
	local zone = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Extraction")
	zone = zone and zone:FindFirstChild("Zone")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	-- Outbreak's helicopter can go to any landing pad (EvacZone; every pad's zone is 44 across).
	local at = workspace:GetAttribute("EvacZone")
	local center = if typeof(at) == "Vector3" then at elseif zone then zone.Position else nil
	if not center or not root then
		return nil
	end
	local radius = if typeof(at) == "Vector3" or not zone then 22 else zone.Size.Y / 2
	local d = (center - root.Position) * Vector3.new(1, 0, 1)
	return math.max(0, math.floor(d.Magnitude - radius))
end

local function clock(at)
	local t = math.max(0, math.ceil((at or 0) - workspace:GetServerTimeNow()))
	return string.format("%d:%02d", t // 60, t % 60)
end

-- Outbreak's one line: the contract, the helicopter, Scrip to bank, or where the radio is.
local OUT = GameConfig.Outbreak
local function outbreakText()
	local kind = workspace:GetAttribute("Contract")
	if kind == "Hold" then
		local left = math.ceil(workspace:GetAttribute("ContractLeft") or 0)
		return if workspace:GetAttribute("ContractHolding") then "HOLD THE RADIO " .. left else "GET TO THE RADIO"
	elseif kind == "Hunt" then
		return "HUNT  ·  " .. (workspace:GetAttribute("ContractLeft") or 0) .. " LEFT"
	end
	local evac = evacLeft()
	local leaveAt = workspace:GetAttribute("EvacLeaveAt")
	if evac and not (leaveAt and workspace:GetServerTimeNow() > leaveAt) then
		local d = zoneDistance()
		if evac > 0 then
			return "HELI " .. evac .. (if d and d > 0 then "  ·  " .. d .. "M" else "")
		end
		return "GRAB THE LADDER"
	end
	local carried = player:GetAttribute("Carried") or 0
	if carried > 0 then
		return "BANK " .. carried .. " SCRIP"
	end
	local post = workspace:GetAttribute("OfferPost")
	if post then
		return "RADIO  ·  " .. (OUT.Posts[post] or string.upper(post))
	end
	if workspace:GetServerTimeNow() >= (workspace:GetAttribute("BirdAt") or math.huge) then
		return "CALL THE BIRD AT A PAD"
	end
	return ""
end

-- FRONTLINE (ServerScriptService.FrontServer, Shared.Front): the big line is the sector and its clock, the small one
-- this player's side of it: TAKE / HOLD, the flag's progress, the attackers' tickets, and SPAWNING IN while dead.
local function frontAttacking()
	return (player:GetAttribute("Side") or "Ally") == workspace:GetAttribute("FrontAttack")
end

local function frontWave(state)
	if state == "FrontEnd" then
		local won = workspace:GetAttribute("FrontWinner") == (player:GetAttribute("Side") or "Ally")
		return if won then "VICTORY" else "DEFEAT"
	end
	local name = workspace:GetAttribute("WarMission") or "FRONTLINE"
	local endsAt = workspace:GetAttribute("FrontEndsAt")
	return if endsAt then name .. "   " .. clock(endsAt) else name
end

local function frontText(state)
	if state == "FrontEnd" then
		local nextAt = workspace:GetAttribute("FrontNextAt")
		return if nextAt then "NEXT MATCH " .. clock(nextAt) else ""
	end
	local spawnAt = player:GetAttribute("FrontSpawnAt")
	if spawnAt and spawnAt > workspace:GetServerTimeNow() then
		return "SPAWNING IN " .. math.max(0, math.ceil(spawnAt - workspace:GetServerTimeNow()))
	end
	local attacking = frontAttacking()
	local progress = math.floor((workspace:GetAttribute("FrontProgress") or 0) * 100)
	local contest = workspace:GetAttribute("FrontContest")
	local words = if attacking then "TAKE THE FLAG" else "HOLD THE FLAG"
	if contest == "Contested" then
		words = "CONTESTED"
	elseif contest == "Attack" and not attacking then
		words = "THEY'RE TAKING IT"
	elseif contest == "Defend" and attacking then
		words = "THEY'RE PUSHING YOU OFF"
	end
	local tickets = workspace:GetAttribute("FrontTickets") or 0
	local streak = player:GetAttribute("StreakReady")
	local parts = { words, progress .. "%", "TICKETS " .. tickets }
	if type(streak) == "string" then
		table.insert(parts, string.upper(streak) .. " READY")
	end
	return table.concat(parts, "  ·  ")
end

local function subText(state, left)
	if state == "Outbreak" then
		return outbreakText()
	elseif state == "Front" or state == "FrontEnd" then
		return frontText(state)
	elseif state == "War" then
		-- The campaign: the objective's words (WarServer), and the mast's progress while it sends.
		local progress = workspace:GetAttribute("WarProgress")
		local words = workspace:GetAttribute("WarObjective") or ""
		if progress then
			return words .. "  ·  " .. math.floor(progress * 100) .. "%"
		end
		-- How far the marker is, so nobody wonders which way to go.
		local at = workspace:GetAttribute("Objective")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if words ~= "" and typeof(at) == "Vector3" and root then
			local d = math.floor(((at - root.Position) * Vector3.new(1, 0, 1)).Magnitude / 3.5) -- metres, as on the marker
			if d > 12 then
				return words .. "  ·  " .. d .. "M"
			end
		end
		return words
	end
	local nights = workspace:GetAttribute("Nights") == true
	if nights and state == "Wave" then
		return "DAWN " .. clock(workspace:GetAttribute("NightEndsAt"))
	elseif nights and state == "Intermission" then
		return "DUSK " .. clock(workspace:GetAttribute("NextWaveAt"))
	elseif state == "Breakout" then
		local evac = evacLeft()
		local d = zoneDistance()
		if evac and evac > 0 then
			return "HELI " .. evac .. (if d and d > 0 then "  ·  " .. d .. "M" else "")
		end
		return "GRAB THE LADDER"
	elseif state == "Escaped" then
		return ""
	elseif state == "Intermission" then
		local t = math.max(0, math.ceil((workspace:GetAttribute("NextWaveAt") or 0) - workspace:GetServerTimeNow()))
		return "NEXT WAVE " .. t
	elseif state == "Wave" then
		return left .. " LEFT"
	elseif state == "GameOver" then
		return ""
	end
	return "GET READY"
end

-- How long this night or lull is, for the ring. The plan (GameConfig.Nights, scaled by
-- DebugTimeScale) covers a player who joined part way; a longer time left wins.
local phaseEnd, phaseLength = nil, 1
local function phaseTotal(state, wave, endsAt)
	if endsAt ~= phaseEnd then
		phaseEnd = endsAt
		local planned = if state == "Wave"
			then (if workspace:GetAttribute("LastNight") then NIGHTS.LastTime else math.min(NIGHTS.Base + NIGHTS.Step * (wave - 1), NIGHTS.Cap))
			elseif wave == 0 then NIGHTS.FirstDelay
			else NIGHTS.LullTime
		planned *= workspace:GetAttribute("DebugTimeScale") or 1
		phaseLength = math.max(planned, endsAt - workspace:GetServerTimeNow(), 1)
	end
	return phaseLength
end

-- The ring's arc: the right half sweeps first, then the left (each half is a clipped full
-- ring whose stroke gradient hides everything past the angle).
local function setRing(ring, p, color)
	local a = math.clamp(p, 0, 0.5) * 360
	local b = math.clamp(p - 0.5, 0, 0.5) * 360
	local r = ring.Right.Arc.UIStroke
	local l = ring.Left.Arc.UIStroke
	r.UIGradient.Rotation = a
	l.UIGradient.Rotation = 180 + b
	r.Color = color
	l.Color = color
end

-- The carried part, turned a little, in the box beside the ring.
local shownPart, shownRing = nil, nil
local function showPart(ring, name)
	shownPart, shownRing = name, ring
	local box = ring.Part
	local view = box.View
	view:ClearAllChildren()
	local template = name and TowerParts:FindFirstChild(name)
	box.Visible = template ~= nil
	if not template then
		return
	end
	local model = template:Clone()
	model.Parent = view
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local dist = size.Magnitude / 2 / math.tan(math.rad(15)) * 1.05
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(1, 0.7, 1.2).Unit * dist, cf.Position)
	cam.Parent = view
	view.CurrentCamera = cam
end

RunService.RenderStepped:Connect(function(dt)
	local gui = hud()
	if not gui then
		return
	end
	local match, points = gui:FindFirstChild("Match"), gui:FindFirstChild("Points")
	if not match or not points then
		return
	end
	local state = workspace:GetAttribute("WaveState") or "Waiting"
	local wave = workspace:GetAttribute("Wave") or 0
	match.Wave.Text = if state == "Outbreak" then clock(workspace:GetAttribute("OutbreakEndsAt"))
		elseif state == "Breakout" then "GET OUT"
		elseif state == "Escaped" then "OUT"
		elseif state == "War" then workspace:GetAttribute("WarMission") or "WAR"
		elseif state == "Front" or state == "FrontEnd" then frontWave(state)
		elseif wave > 0 and workspace:GetAttribute("LastNight") then "LAST NIGHT"
		elseif wave > 0 and workspace:GetAttribute("Nights") then "NIGHT " .. wave
		elseif wave > 0 then "WAVE " .. wave
		else "DEFEND"
	match.Sub.Text = subText(state, workspace:GetAttribute("ZombiesLeft") or 0)
	-- Phones (TouchHud, 4 Nov 2026): smaller type that shrinks to fit, so a long mission name or objective never
	-- spills past the block; PC keeps the authored 30 / 15.
	local touch = player:GetAttribute("TouchHud") == true
	for l, sizes in { [match.Wave] = { 30, 20 }, [match.Sub] = { 15, 11 } } do
		l.TextScaled = touch
		if touch then
			local limit = l:FindFirstChild("PhoneLimit") or Instance.new("UITextSizeConstraint")
			limit.Name = "PhoneLimit"
			limit.MaxTextSize = sizes[2]
			limit.MinTextSize = 8
			limit.Parent = l
		else
			local limit = l:FindFirstChild("PhoneLimit")
			if limit then
				limit:Destroy()
			end
			l.TextSize = sizes[1]
		end
	end
	-- A new wave lights the wave number amber for a moment.
	local now = os.clock()
	match.Wave.TextColor3 = if now < pulseUntil then AMBER else WHITE
	match.Bar.Size = UDim2.new(0, if now < pulseUntil then 120 else 36, 0, 2)

	-- The ring, in nights.
	local ring = gui:FindFirstChild("Clock")
	if ring then
		local ringOn = workspace:GetAttribute("Nights") == true and (state == "Wave" or state == "Intermission")
		ring.Visible = ringOn
		match.Visible = not ringOn
		if ringOn then
			local night = state == "Wave"
			local endsAt = workspace:GetAttribute(if night then "NightEndsAt" else "NextWaveAt") or 0
			local total = phaseTotal(state, wave, endsAt)
			local left = math.max(0, endsAt - workspace:GetServerTimeNow())
			local color = if not night then HUDCFG.Lull
				elseif workspace:GetAttribute("LastNight") then HUDCFG.Last
				else HUDCFG.Night
			setRing(ring, if night then 1 - left / total else left / total, color)
			ring.Value.Text = if night then tostring(wave) else clock(endsAt)
			ring.Value.TextSize = if night then 20 else 14
			-- A new night swells it once; the last seconds of a lull make it beat.
			local swell = if now < pulseUntil then 0.12 * math.sin(math.clamp((pulseUntil - now) / 2.5, 0, 1) * math.pi) else 0
			local beat = if not night and wave > 0 and left <= NIGHTS.ReturnWarn then 0.07 * math.abs(math.sin(now * 4)) else 0
			ring.Pulse.Scale = 1 + math.max(swell, beat)
		end
		local character = player.Character
		local carrying = character and character:GetAttribute("CarryingPart") or nil
		if carrying ~= shownPart or ring ~= shownRing then
			showPart(ring, carrying)
		end
	end

	-- Points tick toward the real value.
	local target = player:GetAttribute("Points") or 0
	if target < shownPoints then
		shownPoints = target
	else
		shownPoints += math.max(1, (target - shownPoints) * math.min(1, dt * 10))
		shownPoints = math.min(shownPoints, target)
	end
	points.Value.Text = tostring(math.floor(shownPoints + 0.5))
	if now < brokeUntil then
		points.Value.TextColor3 = RED
		points.Value.Position = UDim2.new(0, math.sin(now * 60) * 3, 0, 0)
	else
		points.Value.TextColor3 = AMBER
		points.Value.Position = UDim2.new(0, 0, 0, 0)
	end
end)

local function notice(text)
	local gui = hud()
	local label = gui and gui:FindFirstChild("Notice")
	if not label then
		return
	end
	label.Text = text
	local stroke = label:FindFirstChildOfClass("UIStroke")
	TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 0.55 }):Play()
	end
	task.delay(3, function()
		if label.Text == text then
			TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
			end
		end
	end)
end

local function gameOver(wave, escaped)
	if not escaped then
		-- Dying with the dog beside you: the death cam (PlayerHealthClient, player attribute
		-- DeathCam) plays out first, and the screen only comes if the run is still over.
		task.wait(0.25)
		while player:GetAttribute("DeathCam") do
			task.wait(0.1)
		end
		if workspace:GetAttribute("WaveState") ~= "GameOver" then
			return
		end
	end
	local gui = hud()
	local frame = gui and gui:FindFirstChild("GameOver")
	if not frame then
		return
	end
	frame.Title.Text = if escaped then "YOU MADE IT OUT" else "YOU FELL"
	frame.Title.TextColor3 = if escaped then AMBER else WHITE
	if workspace:GetAttribute("Nights") then
		local survived = if escaped then wave else math.max(0, wave - 1)
		frame.Waves.Text = (if escaped then "AFTER " else "SURVIVED ") .. survived .. (if survived == 1 then " NIGHT" else " NIGHTS")
	elseif escaped then
		frame.Waves.Text = "AFTER " .. wave .. (if wave == 1 then " WAVE" else " WAVES")
	else
		frame.Waves.Text = if wave == 1 then "SURVIVED 1 WAVE" else "SURVIVED " .. math.max(0, wave - 1) .. " WAVES"
	end
	if workspace:GetAttribute("Mode") == "Outbreak" then
		frame.Title.Text = "THE LAST BIRD IS GONE"
		frame.Title.TextColor3 = WHITE
		frame.Waves.Text = "BANKED " .. (player:GetAttribute("Banked") or 0) .. " SCRIP"
	end
	frame.BackgroundTransparency = 1
	frame.Title.TextTransparency = 1
	frame.Waves.TextTransparency = 1
	frame.Visible = true
	TweenService:Create(frame, TweenInfo.new(1.2), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(frame.Title, TweenInfo.new(1.2), { TextTransparency = 0 }):Play()
	TweenService:Create(frame.Waves, TweenInfo.new(1.6), { TextTransparency = 0 }):Play()
	SoundKit.Play("Night/Stinger")
end

-- The run is over once the state leaves GameOver: lift the dark.
workspace:GetAttributeChangedSignal("WaveState"):Connect(function()
	local state = workspace:GetAttribute("WaveState")
	if state ~= "GameOver" and state ~= "Escaped" then
		local gui = hud()
		local frame = gui and gui:FindFirstChild("GameOver")
		if frame and frame.Visible then
			local fade = TweenService:Create(frame, TweenInfo.new(0.8), { BackgroundTransparency = 1 })
			TweenService:Create(frame.Title, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			TweenService:Create(frame.Waves, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			fade:Play()
			fade.Completed:Once(function()
				frame.Visible = false
			end)
		end
	end
end)

Remotes:WaitForChild("Match").OnClientEvent:Connect(function(cue, value)
	if cue == "Broke" then
		brokeUntil = os.clock() + 0.45
	elseif cue == "Full" then
		notice("BANDAGES FULL")
	elseif cue == "FrontSound" and typeof(value) == "string" then
		-- FRONTLINE's stingers (Assets.Sounds.Front, from the 6 Nov sound overhaul; silent until installed).
		SoundKit.Play("Front/" .. value)
	elseif cue == "Wave" then
		pulseUntil = os.clock() + 2.5
		SoundKit.Play("Night/Stinger")
	elseif cue == "Return" then
		notice("GET BACK TO THE HOUSE")
	elseif cue == "Open" then
		notice("THE DOORS ARE OPEN")
	elseif cue == "Ready" then
		notice("THE DOORS CAN BE BROKEN OPEN")
	elseif cue == "Breakout" then
		SoundKit.Play("Night/Stinger")
		task.delay(GameConfig.Breakout.RevealTime, function()
			notice("GET TO THE RED FLARE")
		end)
	elseif cue == "Evac" then
		notice("HELICOPTER INBOUND")
	elseif cue == "Ladder" then
		notice("GRAB THE LADDER")
	elseif cue == "HeliLeft" then
		notice("THE HELICOPTER LEFT")
	elseif cue == "Unlocked" then
		task.delay(GameConfig.Rescue.EscapeTime - 3, function()
			notice("NIGHTMARE AND ENDLESS UNLOCKED")
		end)
	elseif cue == "LensOut" then
		notice("ONE LAMP LEFT")
	elseif cue == "BeaconDown" then
		notice("THE BEACON IS DOWN")
	elseif cue == "Taken" then
		-- A teammate seen by the Beacon (you see your own through the black).
		if value ~= player.DisplayName then
			notice(string.upper(tostring(value)) .. " WAS TAKEN")
		end
	elseif cue == "ContractDone" then
		pulseUntil = os.clock() + 2.5
		notice("CONTRACT DONE  +" .. tostring(value))
	elseif cue == "Banked" then
		notice("BANKED " .. tostring(value) .. " SCRIP")
	elseif cue == "Lost" then
		notice("CARRIED SCRIP LOST")
	elseif cue == "Notice" and typeof(value) == "string" then
		notice(value)
	elseif cue == "Escaped" then
		gameOver(value or 1, true)
	elseif cue == "GameOver" then
		gameOver(value or 1)
	end
end)
