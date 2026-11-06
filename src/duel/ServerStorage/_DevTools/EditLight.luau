-- Bright light for building in Studio, and back to the game's night.
-- Command bar:  require(game.ServerStorage._DevTools.EditLight)()
-- Run it once for daylight, again to put the night back exactly as it was. The night is kept
-- on Lighting attributes while it's bright, and ServerScriptService.LightingGuard puts it back
-- whenever the game runs, so a forgotten toggle never ships a daytime game.

local Lighting = game:GetService("Lighting")

local KEYS = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation" }

local EditLight = {}

function EditLight.Restore()
	if not Lighting:GetAttribute("EditBright") then
		return false
	end
	for _, key in KEYS do
		local saved = Lighting:GetAttribute("Night_" .. key)
		if saved ~= nil then
			Lighting[key] = saved
		end
		Lighting:SetAttribute("Night_" .. key, nil)
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and Lighting:GetAttribute("Night_Density") then
		atmosphere.Density = Lighting:GetAttribute("Night_Density")
	end
	Lighting:SetAttribute("Night_Density", nil)
	Lighting:SetAttribute("EditBright", nil)
	return true
end

function EditLight.Bright()
	if Lighting:GetAttribute("EditBright") then
		return
	end
	for _, key in KEYS do
		Lighting:SetAttribute("Night_" .. key, Lighting[key])
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		Lighting:SetAttribute("Night_Density", atmosphere.Density)
		atmosphere.Density = 0.1
	end
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(120, 120, 125)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 155)
	Lighting.ExposureCompensation = 0
	Lighting:SetAttribute("EditBright", true)
end

return setmetatable(EditLight, {
	__call = function()
		if Lighting:GetAttribute("EditBright") then
			EditLight.Restore()
			print("EditLight: night is back")
		else
			EditLight.Bright()
			print("EditLight: bright for editing (run again to put the night back)")
		end
	end,
})
