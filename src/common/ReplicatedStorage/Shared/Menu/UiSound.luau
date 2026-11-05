-- Shared.Menu.UiSound: menu sounds (CORE, 2 Nov 2026). Ids are Roblox-licensed Creator Store audio (Roblox-made or
-- ProSoundEffects); an empty id is silent. Volume follows the Settings audio slider through the "Menu" SoundGroup if
-- one exists under SoundService. Same module in lobby, zombies and campaign.
-- 5 Nov 2026 ("UIs need change in all places"): one military-hardware set (metal toggles, relays, a lever pull for
-- deploy) instead of mixed whooshes; Equip added for loadout picks. Sounds heard many times in a row (Hover, Click,
-- Tick, Tab) get a small pitch wobble so they don't machine-gun; signature cues (Deploy, LevelUp, Error) never do.

local SoundService = game:GetService("SoundService")

local UiSound = {}

UiSound.Ids = {
	Hover = "rbxassetid://15675032796", -- Roblox_UI_Small_Click (Roblox)
	Click = "rbxassetid://9120093415", -- Toggle Switch Metal Industrial Equipment 124 (ProSoundEffects)
	Back = "rbxassetid://9117509492", -- Plastic Flashlight 16 (ProSoundEffects)
	Tab = "rbxassetid://15675037413", -- Roblox_UI_Paper_Swipe (Roblox)
	Locked = "rbxassetid://9120102194", -- Toggle Switch Metal Industrial Equipment 10 (ProSoundEffects)
	Deploy = "rbxassetid://9116259834", -- Lever Two Large Metal Pulls 1 (ProSoundEffects)
	Beep = "rbxassetid://15675085146", -- Indicator (Roblox)
	Stamp = "rbxassetid://9114026047", -- Date Stamp (ProSoundEffects)
	LevelUp = "rbxassetid://15675043410", -- Tonal_Stinger (Roblox)
	Tick = "rbxassetid://15675059323", -- Roblox_UI_Bright_Click (Roblox)
	Error = "rbxassetid://15675075163", -- Roblox_UI_Delete (Roblox)
	Equip = "rbxassetid://9118138693", -- Relay Clicks 15 (ProSoundEffects)
}
UiSound.Volume = { -- level-matched 5 Nov 2026 to the sounds they replaced (default 0.5)
	Hover = 0.25,
	Click = 0.63,
	Back = 0.34,
	Tab = 0.69,
	Locked = 0.18,
	Deploy = 0.4,
	Tick = 0.17,
	Equip = 0.33,
}
local WOBBLE = { Hover = 0.04, Click = 0.03, Tick = 0.04, Tab = 0.03, Equip = 0.03 }
local GAP = 0.03 -- seconds: the same sound twice inside this is one sound (hover sweeps across a list)

local cache = {}
local lastAt = {}

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
	if not s then
		return
	end
	local now = os.clock()
	if lastAt[name] and now - lastAt[name] < GAP then
		return
	end
	lastAt[name] = now
	local w = WOBBLE[name]
	s.PlaybackSpeed = if w then 1 + (math.random() * 2 - 1) * w else 1
	SoundService:PlayLocalSound(s)
end

return UiSound
