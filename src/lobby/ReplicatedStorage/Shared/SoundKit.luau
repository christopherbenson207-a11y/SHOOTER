-- Plays sound cues from ReplicatedStorage.Assets.Sounds, on the client or the server.
-- A cue is a path like "Guns/Pistol/Crack" naming a Sound or a Folder of Sound variants.
-- Each play picks a variant (never the same one twice in a row) and nudges the pitch
-- inside the "Pitch" NumberRange attribute on the sound or its folder.
-- Zombie and dog cues (Mobs/..., Dog/...) play in the SoundService "Mobs" SoundGroup (set on
-- the templates; a template missing it gets it here), so RadioVoice can duck them under a line.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local root = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds")
local MOB_FOLDERS = { "Mobs", "Dog" }

local SoundKit = {}

local lastVariant = setmetatable({}, { __mode = "k" })

local function resolve(cue)
	if typeof(cue) == "Instance" then
		return cue
	end
	local node = root
	for name in string.gmatch(cue, "[^/]+") do
		node = node:FindFirstChild(name)
		if not node then
			return nil
		end
	end
	return node
end

-- Returns the Sound template to play and the pitch range that applies to it.
function SoundKit.Pick(cue)
	local node = resolve(cue)
	if not node then
		return nil, nil
	end
	if node:IsA("Sound") then
		return node, node:GetAttribute("Pitch")
	end
	local variants = {}
	for _, child in node:GetChildren() do
		if child:IsA("Sound") then
			table.insert(variants, child)
		end
	end
	if #variants == 0 then
		return nil, nil
	end
	local index = math.random(#variants)
	if #variants > 1 and variants[index] == lastVariant[node] then
		index = index % #variants + 1
	end
	local pick = variants[index]
	lastVariant[node] = pick
	return pick, pick:GetAttribute("Pitch") or node:GetAttribute("Pitch")
end

local function isMobSound(template)
	for _, name in MOB_FOLDERS do
		local folder = root:FindFirstChild(name)
		if folder and template:IsDescendantOf(folder) then
			return true
		end
	end
	return false
end

-- opts.Position plays it in 3D at a point; opts.Parent plays it on an instance.
-- Without either it plays on the client's camera (2D-ish). Speed and Volume multiply.
-- opts.SoundGroup puts it in that SoundGroup instead of the template's.
function SoundKit.Play(cue, opts)
	local template, pitch = SoundKit.Pick(cue)
	if not template then
		return nil
	end
	opts = opts or {}
	local sound = template:Clone()
	local speed = opts.Speed or 1
	if typeof(pitch) == "NumberRange" then
		speed *= pitch.Min + math.random() * (pitch.Max - pitch.Min)
	end
	sound.PlaybackSpeed = template.PlaybackSpeed * speed
	sound.Volume = template.Volume * (opts.Volume or 1)
	if opts.SoundGroup then
		sound.SoundGroup = opts.SoundGroup
	elseif not sound.SoundGroup and isMobSound(template) then
		sound.SoundGroup = SoundService:FindFirstChild("Mobs")
	end

	local holder = sound
	if opts.Position then
		local a = Instance.new("Attachment")
		a.Name = "Sound"
		a.Parent = workspace.Terrain
		a.WorldPosition = opts.Position
		sound.Parent = a
		holder = a
	elseif opts.Parent then
		sound.Parent = opts.Parent
	elseif RunService:IsClient() then
		sound.Parent = workspace.CurrentCamera
	else
		sound:Destroy()
		return nil
	end
	sound:Play()
	local length = if template.TimeLength > 0 then template.TimeLength else 3
	Debris:AddItem(holder, length / sound.PlaybackSpeed + 0.3)
	return sound
end

-- Plays several cues on the same frame (e.g. a gunshot's crack, body and tail).
function SoundKit.PlayLayers(base, names, opts)
	for _, name in names do
		SoundKit.Play(base .. "/" .. name, opts)
	end
end

return SoundKit
