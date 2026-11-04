-- Shared.Menu.UiSound: menu sounds (CORE, 2 Nov 2026). FRONT-A fills the ids with Roblox audio-library sounds
-- (Creator Store, Roblox-made or free-to-use); an empty id is silent. Volume follows the Settings audio slider through
-- the "Menu" SoundGroup if one exists under SoundService.

local SoundService = game:GetService("SoundService")

local UiSound = {}

-- FRONT-A, 4 Nov 2026: Roblox audio library (Creator Store) sounds, names as listed there.
UiSound.Ids = {
	Hover = "rbxassetid://15675032796", -- Roblox_UI_Small_Click
	Click = "rbxassetid://9120098454", -- toggle switch (ProSoundEffects)
	Back = "rbxassetid://15675028888", -- Whoosh_02
	Tab = "rbxassetid://15674975792", -- Whoosh_03
	Locked = "rbxassetid://9119386959", -- Hull Buckle 7
	Deploy = "rbxassetid://9119387638", -- Hull Buckle 15
	Beep = "rbxassetid://15675085146", -- Indicator
	Stamp = "rbxassetid://9114026047", -- Date Stamp
	LevelUp = "rbxassetid://15675043410", -- Tonal_Stinger
	Tick = "rbxassetid://9117028600", -- Moviola switch click
	Error = "rbxassetid://15675075163", -- Roblox_UI_Delete
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
