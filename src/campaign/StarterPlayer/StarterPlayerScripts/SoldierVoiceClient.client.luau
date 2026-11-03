-- Speaks WAR soldiers' shouts (Remotes.SoldierSay from Modules.SoldierVoice; lines in
-- GameConfig.War.Voice). Roblox text-to-speech until recorded voices exist.
--   A shout is heard within Voice.Hear studs of the camera, quieter with distance. A line marked
--   radio from your own side is heard anywhere, through the same radio crunch as RadioVoice.
--   At most three lines at once; the commander's radio (SoundService.RadioVoice, attribute
--   Talking) holds radio shouts back so the two never talk over each other.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local CFG = GameConfig.War and GameConfig.War.Voice
if not CFG then
	return
end
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SoldierSay", 60)
if not remote then
	return
end

local player = Players.LocalPlayer
local MAX_LINES = 3

local folder = Instance.new("Folder")
folder.Name = "SoldierVoice"
folder.Parent = SoundService

local playing = 0

local function make(class, props, parent)
	local i = Instance.new(class)
	for k, v in props do
		pcall(function()
			i[k] = v
		end)
	end
	i.Parent = parent
	return i
end

local function wire(a, b, parent)
	make("Wire", { SourceInstance = a, TargetInstance = b }, parent)
end

local function commanderTalking()
	local radio = SoundService:FindFirstChild("RadioVoice")
	return radio ~= nil and radio:GetAttribute("Talking") == true
end

local function speak(model, text, radio, voiceId, speed, pitch)
	local head = model:FindFirstChild("Head")
	local cam = workspace.CurrentCamera
	if not head or not cam then
		return
	end
	local dist = (head.Position - cam.CFrame.Position).Magnitude
	local mySide = player:GetAttribute("Side") or "Ally"
	local overRadio = radio and model:GetAttribute("Side") == mySide and dist > CFG.Hear * 0.5
	if not overRadio and dist > CFG.Hear then
		return
	end
	if overRadio then
		local waited = 0
		while commanderTalking() and waited < 4 do
			waited += task.wait(0.2)
		end
	end
	if playing >= MAX_LINES then
		return
	end
	playing += 1
	local box = Instance.new("Folder")
	box.Name = model.Name
	box.Parent = folder
	local tts = make("AudioTextToSpeech", { Text = text, VoiceId = voiceId or "1", Speed = speed or 1.1, Pitch = pitch or 1 }, box)
	local volume = CFG.Volume
	if not overRadio then
		local k = math.clamp(1 - dist / CFG.Hear, 0, 1)
		volume *= 0.15 + 0.85 * k * k
	end
	local fader = make("AudioFader", { Volume = volume }, box)
	local out = make("AudioDeviceOutput", {}, box)
	if overRadio then
		local high = make("AudioFilter", { FilterType = Enum.AudioFilterType.Highpass24dB, Frequency = 420 }, box)
		local low = make("AudioFilter", { FilterType = Enum.AudioFilterType.Lowpass24dB, Frequency = 3000 }, box)
		local crunch = make("AudioDistortion", { Level = 0.25 }, box)
		wire(tts, high, box)
		wire(high, low, box)
		wire(low, crunch, box)
		wire(crunch, fader, box)
	else
		wire(tts, fader, box)
	end
	wire(fader, out, box)
	local ok = pcall(function()
		tts:LoadAsync()
	end)
	if ok and model.Parent then
		tts:Play()
		task.wait(math.min(6, tts.TimeLength / math.max(tts.Speed, 0.1)) + 0.2)
	end
	box:Destroy()
	playing -= 1
end

remote.OnClientEvent:Connect(function(model, text, _key, radio, voiceId, speed, pitch)
	if typeof(model) ~= "Instance" or type(text) ~= "string" then
		return
	end
	task.spawn(speak, model, text, radio, voiceId, speed, pitch)
end)
