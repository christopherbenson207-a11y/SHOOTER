-- What WAR's soldiers shout (docs/ALLIED-AI-PROMPT.md 3.5, docs/HOSTILE-AI-PROMPT.md 4.8). Numbers
-- and lines: GameConfig.War.Voice. Modules.Soldier calls Soldier.Voice(soldier, key, info) at the
-- moments that matter (first contact, reloading, pinned, hit, down, moving up, covering, flanking,
-- falling back); this decides whether it is said and by whom, then fires
-- Remotes.SoldierSay(model, text, key, radio, voiceId, speed, pitch) to every client, which speaks it
-- (StarterPlayerScripts.SoldierVoiceClient).
--   Discipline: each soldier has a cooldown per key and a chance; a fireteam has one speaker at a
--   time and TeamGap seconds between lines; a side has SideGap between lines. A higher-priority
--   line (ManDown, Pinned, Contact) cuts in on the team's lock. A contact is said once per
--   engagement (Soldier only calls it on a fresh one). ManDown is said by the nearest living
--   teammate, not the fallen.
-- Call SoldierVoice.Install() once (WarServer, WarTestScene); it is safe to call twice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Soldier = require(script.Parent.Soldier)

local CFG = GameConfig.War.Voice

local SoldierVoice = {}

local remote
local lastKey = {} -- [soldier] = { [key] = time }
local teamLock = {} -- [side .. team] = { Until, Priority }
local sideLast = {} -- [side] = time
local voiceOf = {} -- [model] = { VoiceId, Speed, Pitch }

local function between(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

local function direction(s, pos)
	if not pos then
		return "front"
	end
	local look = s:Facing()
	local to = Vector3.new(pos.X - s.Root.Position.X, 0, pos.Z - s.Root.Position.Z)
	if to.Magnitude < 0.1 then
		return "front"
	end
	to = to.Unit
	local fwd = look:Dot(to)
	local right = look:Cross(Vector3.yAxis):Dot(to)
	if fwd > 0.6 then
		return "front"
	elseif fwd < -0.6 then
		return "behind"
	end
	return if right > 0 then "right" else "left"
end

local function voice(model)
	local v = voiceOf[model]
	if not v then
		v = {
			Id = CFG.Voices[math.random(#CFG.Voices)],
			Speed = between(CFG.Speed),
			Pitch = between(CFG.Pitch),
		}
		voiceOf[model] = v
		model.Destroying:Once(function()
			voiceOf[model] = nil
		end)
	end
	return v
end

-- The nearest living teammate within Hear studs of s (who calls s down).
local function nearestMate(s)
	local best, bestD = nil, CFG.Hear
	for _, o in Soldier.All(s.Side) do
		if o ~= s then
			local d = (o.Root.Position - s.Root.Position).Magnitude
			if d < bestD then
				best, bestD = o, d
			end
		end
	end
	return best
end

local function speak(s, key, info)
	local rule = CFG.Keys[key]
	local side = s.Side
	local lines = CFG.Lines[side] and CFG.Lines[side][key]
	if not rule or not lines or #lines == 0 then
		return
	end
	if key == "ManDown" then
		s = nearestMate(s)
		if not s then
			return
		end
	end
	if not s.Alive or not s.Model.Parent then
		return
	end
	local now = os.clock()
	local mine = lastKey[s]
	if not mine then
		mine = {}
		lastKey[s] = mine
	end
	if now - (mine[key] or -math.huge) < rule.Cooldown then
		return
	end
	if math.random() > rule.Chance then
		return
	end
	local teamKey = side .. tostring(s.Team or 1)
	local lock = teamLock[teamKey]
	if lock and now < lock.Until and rule.Priority <= lock.Priority then
		return
	end
	if now - (sideLast[side] or -math.huge) < CFG.SideGap and rule.Priority < 3 then
		return
	end
	local text = lines[math.random(#lines)]
	text = text:gsub("{dir}", direction(s, info and info.Pos))
	mine[key] = now
	sideLast[side] = now
	-- About a fifth of a second a word, then the team's gap.
	local words = select(2, text:gsub("%S+", ""))
	teamLock[teamKey] = { Until = now + words * 0.22 + CFG.TeamGap, Priority = rule.Priority }
	local v = voice(s.Model)
	remote:FireAllClients(s.Model, text, key, rule.Radio == true, v.Id, v.Speed, v.Pitch)
end

function SoldierVoice.Install()
	if Soldier.Voice then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	remote = remotes:FindFirstChild("SoldierSay")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "SoldierSay"
		remote.Parent = remotes
	end
	Soldier.Voice = function(s, key, info)
		local ok, err = pcall(speak, s, key, info)
		if not ok then
			warn("SoldierVoice: " .. tostring(err))
		end
	end
end

-- A line said by a soldier now, outside the brain's own moments (e.g. the arena's "Clear").
function SoldierVoice.Say(s, key, info)
	if Soldier.Voice and s then
		Soldier.Voice(s, key, info)
	end
end

-- Forget the dead (call between rounds).
function SoldierVoice.Reset()
	table.clear(lastKey)
	table.clear(teamLock)
	table.clear(sideLast)
end

return SoldierVoice
