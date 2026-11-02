-- Shared.Menu.UiSound: menu sounds (CORE, 2 Nov 2026). FRONT-A fills the ids with Roblox audio-library sounds
-- (Creator Store, Roblox-made or free-to-use); an empty id is silent. Volume follows the Settings audio slider through
-- the "Menu" SoundGroup if one exists under SoundService.

local SoundService = game:GetService("SoundService")

local UiSound = {}

UiSound.Ids = {
	Hover = "",
	Click = "",
	Back = "",
	Tab = "",
	Locked = "",
	Deploy = "",
	Beep = "",
	Stamp = "",
	LevelUp = "",
	Tick = "",
	Error = "",
}
UiSound.Volume = {
	Hover = 0.25,
	Tick = 0.35,
}

local cache = {}

local function get(name)
	local s = cache[name]
	if s then
		return s
	end
	local id = UiSound.Ids[name]
	if not id or id == "" then
		return nil
	end
	s = Instance.new("Sound")
	s.Name = "Ui" .. name
	s.SoundId = id
	s.Volume = UiSound.Volume[name] or 0.5
	s.SoundGroup = SoundService:FindFirstChild("Menu")
	s.Parent = SoundService
	cache[name] = s
	return s
end

function UiSound.Play(name)
	local s = get(name)
	if s then
		SoundService:PlayLocalSound(s)
	end
end

return UiSound
