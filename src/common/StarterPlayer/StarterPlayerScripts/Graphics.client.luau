-- Graphics quality (Options "Graphics"): how much this screen draws, so a Core i3 laptop or a budget phone
-- holds its frame rate. Every change here is local to this client; nothing replicates.
--   High    everything as built.
--   Medium  only your own flashlight beam casts shadows (each shadowed light renders the scene again);
--           no depth of field or sun rays.
--   Low     no shadows from any light or the sun, no bloom.
--   Auto    starts on High (Medium on a phone or tablet, or when Roblox's own graphics slider sits low) and steps
--           down a tier whenever the frame rate stays under TARGET_FPS for SLOW_FOR seconds. It never steps back
--           up by itself: going up and down would flicker the lights.
-- The tier in use is the player's local GraphicsTier attribute, for any other script that wants to scale.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Options = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Options"))

local player = Players.LocalPlayer

local TIERS = { "High", "Medium", "Low" }
local TARGET_FPS = 40
local SLOW_FOR = 5
-- No judging the frame rate while the place is still streaming in, or right after a step down.
local SETTLE = 12
local COOLDOWN = 8

local tier = "High"
local autoTier = "High"

-- What each thing was before this script touched it (lights from the server or other scripts keep theirs).
local lightShadows: { [Light]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local effectEnabled: { [PostEffect]: boolean } = {}
local globalShadows = Lighting.GlobalShadows

-- Your own flashlight (StarterPlayerScripts.Flashlight parents its rig to the camera).
local function ownBeam(light: Light): boolean
	local rig = light.Parent
	return light.Name == "Beam" and rig ~= nil and rig.Name == "FlashlightRig" and rig.Parent == workspace.CurrentCamera
end

local function shadowsFor(light: Light): boolean
	if not lightShadows[light] then
		return false
	end
	if tier == "High" then
		return true
	elseif tier == "Medium" then
		return ownBeam(light)
	end
	return false
end

local function applyLight(light: Light)
	local want = shadowsFor(light)
	if light.Shadows ~= want then
		light.Shadows = want
	end
end

local function track(d: Instance)
	if d:IsA("Light") and lightShadows[d] == nil then
		local light = d :: Light
		lightShadows[light] = light.Shadows
		-- The server or another script switching it later (lamps at night, muzzle flashes) sets what it is on High.
		light:GetPropertyChangedSignal("Shadows"):Connect(function()
			if light.Shadows ~= shadowsFor(light) then
				lightShadows[light] = light.Shadows
				applyLight(light)
			end
		end)
		applyLight(light)
	end
end

local function effectOn(effect: PostEffect): boolean
	if effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") then
		return tier == "High"
	elseif effect:IsA("BloomEffect") then
		return tier ~= "Low"
	end
	return true
end

local function applyEffect(effect: Instance)
	if effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") or effect:IsA("BloomEffect") then
		if effectEnabled[effect] == nil then
			effectEnabled[effect] = effect.Enabled
		end
		effect.Enabled = effectEnabled[effect] and effectOn(effect)
	end
end

local function apply()
	local choice = Options.Get("Graphics")
	tier = if choice == "Auto" or not table.find(TIERS, choice) then autoTier else choice
	player:SetAttribute("GraphicsTier", tier)
	Lighting.GlobalShadows = globalShadows and tier ~= "Low"
	for _, effect in Lighting:GetChildren() do
		applyEffect(effect)
	end
	for light in lightShadows do
		applyLight(light)
	end
end

-- Auto's first guess: a phone or tablet starts on Medium, and so does anyone who set Roblox's slider low.
do
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		autoTier = "Medium"
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok and level ~= Enum.SavedQualitySetting.Automatic then
		if level.Value <= 3 then
			autoTier = "Low"
		elseif level.Value <= 6 then
			autoTier = "Medium"
		end
	end
end

for _, d in workspace:GetDescendants() do
	track(d)
end
workspace.DescendantAdded:Connect(track)
Lighting.ChildAdded:Connect(applyEffect)
Options.Changed:Connect(function(key)
	if key == "Graphics" then
		apply()
	end
end)
apply()

-- Auto: frames counted each second; SLOW_FOR slow seconds in a row step down one tier. Not while the window is
-- in the background (Roblox throttles it there).
local focused = true
UserInputService.WindowFocused:Connect(function()
	focused = true
end)
UserInputService.WindowFocusReleased:Connect(function()
	focused = false
end)

local frames, since = 0, os.clock()
local slowSeconds = 0
local judgeFrom = os.clock() + SETTLE
RunService.Heartbeat:Connect(function()
	frames += 1
	local now = os.clock()
	if now - since < 1 then
		return
	end
	local fps = frames / (now - since)
	frames, since = 0, now
	if Options.Get("Graphics") ~= "Auto" or not focused or now < judgeFrom or autoTier == "Low" then
		slowSeconds = 0
		return
	end
	slowSeconds = if fps < TARGET_FPS then slowSeconds + 1 else 0
	if slowSeconds >= SLOW_FOR then
		slowSeconds = 0
		judgeFrom = now + COOLDOWN
		autoTier = TIERS[table.find(TIERS, autoTier) :: number + 1]
		apply()
	end
end)
