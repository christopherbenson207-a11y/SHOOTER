--!strict
-- Squad callouts (GameConfig.Voice; the lines and where they sit in the one uploaded file are
-- in Shared.VoiceManifest): short shouts at the moments that matter, like a squad on comms.
-- Gameplay scripts call Shared.Callout (GunClient: reload, last mag, out; KillPredict: kills).
-- This script watches the rest: hits, going down, being revived, a teammate down, the Beacon
-- seeing you, a window torn near you, carrying a part, the lull ending far from the house,
-- bandaging, buying a gun, a new kind of zombie, the last night and the helicopter.
-- Your own lines play quietly in your ears; teammates hear them from your head
-- (Remotes.Callout, checked by SquadVoiceServer). Silent until VoiceManifest has a SoundId.
-- The voices play in the SoundService "Radio" group, apart from the zombies and dogs ("Mobs").

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Options = require(Shared:WaitForChild("Options"))
local Callout = require(Shared:WaitForChild("Callout"))
local Manifest = require(Shared:WaitForChild("VoiceManifest"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = Remotes:WaitForChild("Callout") :: RemoteEvent

local CFG = GameConfig.Voice
local player = Players.LocalPlayer

local function inMatch(): boolean
	return player:GetAttribute("InMatch") == true
end

local function ready(): boolean
	return Manifest.SoundId ~= "" and Options.Get("VoiceVol") > 0
end

local function radioTalking(): boolean
	local radio = SoundService:FindFirstChild("RadioVoice")
	return radio ~= nil and radio:GetAttribute("Talking") == true
end

local function root(who: Player): BasePart?
	local character = who.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function standing(who: Player): boolean
	local character = who.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and not character:GetAttribute("Downed")
end

-- Playback ------------------------------------------------------------------------------

-- One Sound per speaker; a new line cuts their last one off.
local mouths: { [Player]: Sound } = {}

local function mouth(who: Player): Sound?
	local head = who.Character and who.Character:FindFirstChild("Head")
	if who ~= player and not head then
		return nil
	end
	local sound = mouths[who]
	if not sound or not sound.Parent then
		sound = Instance.new("Sound")
		sound.Name = "SquadVoice"
		sound.PlaybackRegionsEnabled = true
		sound.SoundGroup = SoundService:FindFirstChild("Radio") :: SoundGroup?
		if who ~= player then
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = 12
			sound.RollOffMaxDistance = CFG.Hear
		end
		mouths[who] = sound
	end
	sound.SoundId = Manifest.SoundId
	sound.Parent = if who == player then SoundService else head
	return sound
end

local function play(who: Player, key: string, index: number, voice: string): number?
	local lines = Manifest.Squad[voice] and Manifest.Squad[voice][key]
	local at = lines and lines[index]
	local sound = at and mouth(who)
	if not at or not sound then
		return nil
	end
	sound:Stop()
	sound.Volume = (if who == player then CFG.OwnVolume else CFG.Volume) * Options.Get("VoiceVol")
	sound.PlaybackRegion = NumberRange.new(at[1], at[1] + at[2])
	sound.TimePosition = at[1]
	sound:Play()
	return at[2]
end

remote.OnClientEvent:Connect(function(who: Player, key: string, index: number, voice: string)
	if ready() and inMatch() and typeof(who) == "Instance" and who:IsA("Player") then
		play(who, key, index, voice)
	end
end)

Players.PlayerRemoving:Connect(function(who)
	local sound = mouths[who]
	if sound then
		sound:Destroy()
		mouths[who] = nil
	end
end)

-- Saying a line -------------------------------------------------------------------------

local lastSaid: { [string]: number } = {}
local lastIndex: { [string]: number } = {}
local busyUntil, busyPriority = 0, 0

local function say(key: string)
	local rule = CFG.Keys[key]
	if not rule or not ready() or not inMatch() then
		return
	end
	local now = os.clock()
	if now - (lastSaid[key] or -math.huge) < rule.Cooldown then
		return
	end
	if now < busyUntil and rule.Priority <= busyPriority then
		return
	end
	if rule.Priority < 4 and radioTalking() then
		return
	end
	if math.random() > rule.Chance then
		return
	end
	local voice = Options.Get("MyVoice")
	local lines = Manifest.Squad[voice] and Manifest.Squad[voice][key]
	if not lines or #lines == 0 then
		return
	end
	-- Never the same take twice in a row.
	local index = math.random(1, #lines)
	if #lines > 1 and index == lastIndex[key] then
		index = index % #lines + 1
	end
	local length = play(player, key, index, voice)
	if length then
		lastSaid[key] = now
		lastIndex[key] = index
		busyUntil, busyPriority = now + length + CFG.Gap, rule.Priority
		remote:FireServer(key, index, voice)
	end
end

local kills: { number } = {}
Callout.Event:Connect(function(what: string, key: string)
	if what == "Say" then
		say(key)
	elseif what == "Note" and key == "Kill" then
		local now = os.clock()
		table.insert(kills, now)
		while kills[1] and now - kills[1] > CFG.MultiKillWindow do
			table.remove(kills, 1)
		end
		if #kills >= CFG.MultiKill then
			table.clear(kills)
			say("Kills")
		end
	end
end)

-- Watching the match --------------------------------------------------------------------

Remotes:WaitForChild("PlayerHit").OnClientEvent:Connect(function(_from, amount, downed)
	if not downed and typeof(amount) == "number" and amount >= CFG.HurtAt then
		say("Hurt")
	end
end)

local lastSeen = player:GetAttribute("BeaconSeen") or 0
player:GetAttributeChangedSignal("BeaconSeen"):Connect(function()
	local seen = player:GetAttribute("BeaconSeen") or 0
	if lastSeen < CFG.BeaconAt and seen >= CFG.BeaconAt then
		say("Beacon")
	end
	lastSeen = seen
end)

-- Buying: the inventory changes in the same moment the points drop.
local points = player:GetAttribute("Points") or 0
local spentAt = -math.huge
player:GetAttributeChangedSignal("Points"):Connect(function()
	local now = player:GetAttribute("Points") or 0
	if now < points then
		spentAt = os.clock()
	end
	points = now
end)
player:GetAttributeChangedSignal("Inventory"):Connect(function()
	if os.clock() - spentAt < 1 then
		say("Buy")
	end
end)

-- Characters: yours (down, revived, bandaging, a part) and your team's (down, being revived).
local carriedAt = -math.huge
local function watchOwn(character: Model)
	local wasDown = false
	character:GetAttributeChangedSignal("Downed"):Connect(function()
		local down = character:GetAttribute("Downed") == true
		if down and not wasDown then
			say("Down")
		elseif wasDown and not down and standing(player) then
			say("Revived")
		end
		wasDown = down
	end)
	character:GetAttributeChangedSignal("Bandaging"):Connect(function()
		if character:GetAttribute("Bandaging") then
			say("Bandage")
		end
	end)
	character:GetAttributeChangedSignal("CarryingPart"):Connect(function()
		if character:GetAttribute("CarryingPart") then
			say("PartGrab")
		else
			carriedAt = os.clock()
		end
	end)
end

-- Of the standing players, is this one the closest to `where`?
local function closestTo(where: Vector3): boolean
	local mine = root(player)
	if not mine or not standing(player) then
		return false
	end
	local myDist = (mine.Position - where).Magnitude
	if myDist > CFG.Hear then
		return false
	end
	for _, other in Players:GetPlayers() do
		local r = root(other)
		if other ~= player and r and standing(other) and (r.Position - where).Magnitude < myDist then
			return false
		end
	end
	return true
end

local function watchTeammate(who: Player, character: Model)
	character:GetAttributeChangedSignal("Downed"):Connect(function()
		local r = root(who)
		if character:GetAttribute("Downed") and r and closestTo(r.Position) then
			say("TeamDown")
		end
	end)
	character:GetAttributeChangedSignal("BeingRevived"):Connect(function()
		local r, mine = root(who), root(player)
		if character:GetAttribute("BeingRevived") and r and mine and (r.Position - mine.Position).Magnitude < 10 then
			say("Reviving")
		end
	end)
end

local function watchPlayer(who: Player)
	local function onCharacter(character: Model)
		if who == player then
			watchOwn(character)
		else
			watchTeammate(who, character)
		end
	end
	if who.Character then
		onCharacter(who.Character)
	end
	who.CharacterAdded:Connect(onCharacter)
end
for _, who in Players:GetPlayers() do
	watchPlayer(who)
end
Players.PlayerAdded:Connect(watchPlayer)

-- A window torn near you.
local function watchWindow(part: Instance)
	part:GetAttributeChangedSignal("Torn"):Connect(function()
		local mine = root(player)
		if part:GetAttribute("Torn") and mine and part:IsA("BasePart") and (part.Position - mine.Position).Magnitude < CFG.WindowRange then
			say("Window")
		end
	end)
end
for _, part in CollectionService:GetTagged("Breakable") do
	watchWindow(part)
end
CollectionService:GetInstanceAddedSignal("Breakable"):Connect(watchWindow)

-- Match cues: a part in, and the lull running out.
local function house(): Vector3?
	local map = workspace:FindFirstChild("Map")
	local model = map and map:FindFirstChild("DefendHouse")
	return if model and model:IsA("Model") then model:GetPivot().Position else nil
end
Remotes:WaitForChild("Match").OnClientEvent:Connect(function(cue)
	if cue == "PartIn" and os.clock() - carriedAt < 3 then
		task.delay(2.2, say, "PartIn")
	elseif cue == "Return" then
		local at, mine = house(), root(player)
		if at and mine and (mine.Position - at).Magnitude > CFG.HomeRange then
			task.delay(2.5, say, "GoHome")
		end
	end
end)

-- Nights: the first zombie close by, a new kind of zombie, and the last night.
local contactNight = -1
local kindsSeen: { [string]: boolean } = {}
local lastState = workspace:GetAttribute("WaveState")
workspace:GetAttributeChangedSignal("WaveState"):Connect(function()
	local state = workspace:GetAttribute("WaveState")
	if state == lastState then
		return
	end
	lastState = state
	if state == "Wave" and workspace:GetAttribute("LastNight") then
		task.delay(4, say, "LastNight")
	end
end)
player:GetAttributeChangedSignal("InMatch"):Connect(function()
	if inMatch() then
		table.clear(kindsSeen)
		contactNight = -1
	end
end)

-- The police dog taking a zombie down (DogServer sets KillAt on it).
task.spawn(function()
	local dogs = workspace:WaitForChild("Dogs")
	local function watchDog(dog: Instance)
		dog:GetAttributeChangedSignal("KillAt"):Connect(function()
			if inMatch() then
				say("GoodDog")
			end
		end)
	end
	for _, dog in dogs:GetChildren() do
		watchDog(dog)
	end
	dogs.ChildAdded:Connect(watchDog)
end)

-- The helicopter touching down.
workspace:GetAttributeChangedSignal("EvacAt"):Connect(function()
	local at = workspace:GetAttribute("EvacAt")
	if typeof(at) == "number" then
		task.delay(math.max(at - workspace:GetServerTimeNow(), 0) + 1, function()
			if workspace:GetAttribute("EvacAt") == at then
				say("Chopper")
			end
		end)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		local mine = root(player)
		local zombies = workspace:FindFirstChild("Zombies")
		if mine and zombies and inMatch() and workspace:GetAttribute("WaveState") == "Wave" then
			local night = workspace:GetAttribute("Wave") or 0
			for _, z in zombies:GetChildren() do
				local zr = z:IsA("Model") and z.PrimaryPart
				if zr and not z:GetAttribute("Dead") and (zr.Position - mine.Position).Magnitude < CFG.ContactRange then
					local kind = z:GetAttribute("Kind")
					local key = typeof(kind) == "string" and CFG.MobKeys[kind]
					if key and not kindsSeen[kind] then
						kindsSeen[kind] = true
						say(key)
						break
					elseif contactNight ~= night then
						contactNight = night
						say("Contact")
						break
					end
				end
			end
		end
	end
end)
