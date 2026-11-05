--!strict
-- The radio voice (GameConfig.Radio; HUD sim U4): the recorded dispatcher (Shared.VoiceManifest
-- Radio, made with ElevenLabs) or, until that's uploaded, Roblox text-to-speech, through a radio
-- (band-passed, a little crunch, a click either side), at the moments the voice carries:
--   a lull starts: where the part is (PartOut), or the plain lull line;
--   ReturnWarn before dusk (Remotes.Match "Return"): get back to the house;
--   a part goes in (PartIn): how many are left; the tower is done (TowerDone);
--   the last night starts;
--   Outbreak's lines (Remotes.Match "Radio", text, key: MatchServer's Outbreak section).
-- One line at a time; a new one waits for the last (at most two waiting). The folder's
-- "Talking" attribute is true while it speaks, so the squad voices hold off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local SoundKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundKit"))
local Manifest = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VoiceManifest"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local CFG = GameConfig.Radio
local WORDS = { "One", "Two", "Three", "Four", "Five" }

local player = Players.LocalPlayer

-- The chain: voice -> high-pass -> low-pass -> crunch -> fader -> speakers.
local folder = Instance.new("Folder")
folder.Name = "RadioVoice"
folder.Parent = SoundService
local function make(class: string, props: { [string]: any }): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	i.Parent = folder
	return i
end
-- Clarity first (4 Nov 2026: players could not make the words out): a wide, gentle radio band and only a touch of
-- crunch, and the text-to-speech never faster than 0.92 so kids can follow it.
local voice = make("AudioTextToSpeech", { Name = "Voice", VoiceId = CFG.Voice, Speed = math.min(CFG.Speed or 1, 0.92) })
local high = make("AudioFilter", { Name = "High", FilterType = Enum.AudioFilterType.Highpass12dB, Frequency = 180 })
local low = make("AudioFilter", { Name = "Low", FilterType = Enum.AudioFilterType.Lowpass12dB, Frequency = 6500 })
local crunch = make("AudioDistortion", { Name = "Crunch", Level = 0.04 })
local fader = make("AudioFader", { Name = "Fader", Volume = CFG.Volume })
local out = make("AudioDeviceOutput", { Name = "Out" })
local chain = { voice, high, low, crunch, fader, out }
for i = 1, #chain - 1 do
	make("Wire", { SourceInstance = chain[i], TargetInstance = chain[i + 1] })
end
-- The recorded lines go through the same radio.
local recorded = make("AudioPlayer", { Name = "Recorded", Volume = 1 })
make("Wire", { SourceInstance = recorded, TargetInstance = high })

type Line = { Text: string, Key: string }
local queue: { Line } = {}
local talking = false

local function inMatch(): boolean
	return player:GetAttribute("InMatch") == true
end

local function talk()
	if talking then
		return
	end
	talking = true
	folder:SetAttribute("Talking", true)
	while #queue > 0 do
		local line = table.remove(queue, 1) :: Line
		local at = if Manifest.SoundId ~= "" then Manifest.Radio[line.Key] else nil
		local length
		if at then
			recorded.AssetId = Manifest.SoundId
			local waited = 0
			while not recorded.IsReady and waited < 3 do
				waited += task.wait(0.1)
			end
			if recorded.IsReady then
				recorded.PlaybackRegion = NumberRange.new(at[1], at[1] + at[2])
				recorded.TimePosition = at[1]
				length = at[2]
			end
		end
		if not length then
			voice.Text = line.Text
			local ok = pcall(function()
				voice:LoadAsync()
			end)
			length = if ok then voice.TimeLength / math.max(voice.Speed, 0.1) else nil
			at = nil
		end
		if length and inMatch() then
			SoundKit.Play("Night/FlashlightClick", { Volume = 0.7, Speed = 0.8 })
			task.wait(0.12)
			if at then
				recorded:Play()
			else
				voice:Play()
			end
			task.wait(length + 0.15)
			SoundKit.Play("Night/FlashlightClick", { Volume = 0.5, Speed = 0.7 })
			task.wait(0.6)
		end
	end
	folder:SetAttribute("Talking", false)
	talking = false
end

local function say(text: string, key: string)
	if not inMatch() then
		return
	end
	if #queue >= 2 then
		table.remove(queue, 1)
	end
	table.insert(queue, { Text = text, Key = key })
	task.spawn(talk)
end

-- The part's spot: the PartSpots child nearest workspace PartAt, and how it's said.
local function partPlace(): (string, string)
	local at = workspace:GetAttribute("PartAt")
	local spots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("PartSpots")
	local best, bestD = nil, math.huge
	if typeof(at) == "Vector3" and spots then
		for _, spot in spots:GetChildren() do
			if spot:IsA("BasePart") then
				local d = (spot.Position - at).Magnitude
				if d < bestD then
					best, bestD = spot.Name, d
				end
			end
		end
	end
	return best or "", best and CFG.Spots[best] or "the edge of town"
end

local lastPartOut = -math.huge
Remotes:WaitForChild("Match").OnClientEvent:Connect(function(cue, a, b, c)
	if cue == "Radio" and typeof(a) == "string" then
		say(a, if typeof(b) == "string" then b else a)
	elseif cue == "Return" then
		say(CFG.Lines.Return, "Return")
	elseif cue == "PartOut" then
		lastPartOut = os.clock()
		task.delay(0.3, function()
			local spot, spoken = partPlace()
			say((CFG.Lines.PartOut:gsub("{where}", spoken)), "PartOut_" .. spot)
		end)
	elseif cue == "PartIn" and typeof(b) == "number" and typeof(c) == "number" and b < c then
		local left = c - b
		say((CFG.Lines.PartIn:gsub("{left}", WORDS[left] or tostring(left))), "PartIn_" .. left)
	elseif cue == "TowerDone" then
		say(CFG.Lines.TowerDone, "TowerDone")
	end
end)

local lastState = workspace:GetAttribute("WaveState")
workspace:GetAttributeChangedSignal("WaveState"):Connect(function()
	local state = workspace:GetAttribute("WaveState")
	if state == lastState then
		return
	end
	lastState = state
	if workspace:GetAttribute("Nights") ~= true then
		return
	end
	local wave = workspace:GetAttribute("Wave") or 0
	if state == "Intermission" and wave >= 1 then
		-- A part coming out this lull gets its own line instead.
		local started = os.clock()
		task.delay(1.5, function()
			if lastPartOut < started - 0.5 and workspace:GetAttribute("WaveState") == "Intermission" then
				say(CFG.Lines.Lull, "Lull")
			end
		end)
	elseif state == "Wave" then
		task.delay(0.5, function()
			if workspace:GetAttribute("LastNight") then
				say(CFG.Lines.LastNight, "LastNight")
			end
		end)
	end
end)
