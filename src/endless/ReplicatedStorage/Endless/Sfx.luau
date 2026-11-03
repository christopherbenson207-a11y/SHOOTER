-- Sound cues for the Endless reference, on the server or a client. A cue is a path like
-- "Guns/AK/Crack" under ReplicatedStorage.Assets.Sounds: the lobby's SoundKit layout, so copying
-- that folder from the lobby place gives this place the zombie mode's sounds. A cue that names a
-- Folder plays one of its Sounds. With no Assets.Sounds (a bare place) every cue is silent.
--   Sfx.Play(cue, { Position = Vector3 | Parent = Instance, Volume = n, Speed = n })

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Sfx = {}

local missing = {}

local function root()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Sounds")
end

local function resolve(cue: string)
	local node = root()
	if not node then
		return nil
	end
	for name in string.gmatch(cue, "[^/]+") do
		node = node:FindFirstChild(name)
		if not node then
			return nil
		end
	end
	if node:IsA("Folder") then
		local list = {}
		for _, s in node:GetChildren() do
			if s:IsA("Sound") then
				table.insert(list, s)
			end
		end
		return if #list > 0 then list[math.random(#list)] else nil
	end
	return if node:IsA("Sound") then node else nil
end

function Sfx.Play(cue: string, opts: { [string]: any }?)
	local template = resolve(cue)
	if not template then
		missing[cue] = true
		return nil
	end
	opts = opts or {}
	local sound = template:Clone()
	if opts.Volume then
		sound.Volume *= opts.Volume
	end
	if opts.Speed then
		sound.PlaybackSpeed *= opts.Speed
	end
	local holder
	if opts.Position then
		holder = Instance.new("Attachment")
		holder.WorldPosition = opts.Position
		holder.Parent = workspace.Terrain
		sound.Parent = holder
	else
		sound.Parent = opts.Parent or SoundService
	end
	sound:Play()
	local life = sound.TimeLength / math.max(0.05, sound.PlaybackSpeed) + 0.5
	Debris:AddItem(holder or sound, if life > 0.6 then life else 6)
	return sound
end

-- Cues asked for that this place has no sound for (for a check in the Command Bar).
function Sfx.Missing()
	return missing
end

return Sfx
