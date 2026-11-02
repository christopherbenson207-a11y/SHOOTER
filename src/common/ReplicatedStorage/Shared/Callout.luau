--!strict
-- Client-side signal for squad callouts: gameplay scripts say what happened, SquadVoiceClient
-- decides whether it's spoken (cooldowns, chance, the Voice settings) and sends it to the team.
--   Callout.Say(key)   a line from GameConfig.Voice.Keys
--   Callout.Note(kind) something that counts toward a line ("Kill" toward "Kills")

local Callout = {}

local event = Instance.new("BindableEvent")
Callout.Event = event.Event

function Callout.Say(key: string)
	event:Fire("Say", key)
end

function Callout.Note(kind: string)
	event:Fire("Note", kind)
end

return Callout
