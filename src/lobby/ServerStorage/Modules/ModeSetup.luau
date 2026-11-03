-- One mode per server (horror-shooter/MODES-V3.md). A match server plays one mode for its whole
-- life: MenuServer calls Apply with the mode of the first player in (a live match server gets it
-- from the teleport; Studio from the first PLAY). Every map piece whose Modes attribute
-- ("Outbreak,Endless") doesn't name this mode's GameConfig.Modes Map is taken out of the world
-- into ServerStorage.ModeStripped, so no mode's props, prompts, glows or guides reach another.
-- They're moved, not destroyed, so scripts that hold a reference to them at load still work.
-- A piece without the attribute is in every mode. workspace attribute ServerMode is the mode.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ModeSetup = {}

local function keeps(list, key)
	for word in string.gmatch(list, "[^,%s]+") do
		if word == key then
			return true
		end
	end
	return false
end

-- Locks the server to modeName (once) and strips the map. Returns the server's mode.
function ModeSetup.Apply(modeName)
	local locked = workspace:GetAttribute("ServerMode")
	if locked then
		return locked
	end
	local rules = GameConfig.Modes[modeName]
	if not rules then
		modeName = GameConfig.Menu.Modes[1]
		rules = GameConfig.Modes[modeName]
	end
	workspace:SetAttribute("ServerMode", modeName)
	local key = rules.Map or modeName
	local stripped = ServerStorage:FindFirstChild("ModeStripped") or Instance.new("Folder")
	stripped.Name = "ModeStripped"
	stripped.Parent = ServerStorage
	local doomed = {}
	for _, d in workspace:GetDescendants() do
		local list = d:GetAttribute("Modes")
		if typeof(list) == "string" and not keeps(list, key) then
			table.insert(doomed, d)
		end
	end
	for i, d in doomed do
		-- An outer piece already took its inner ones along.
		if d:IsDescendantOf(workspace) then
			d.Parent = stripped
		end
		if i % 50 == 0 then
			task.wait()
		end
	end
	return modeName
end

-- Whether a piece is in this server's world (it wasn't stripped).
function ModeSetup.InPlay(instance)
	return instance ~= nil and instance:IsDescendantOf(workspace)
end

return ModeSetup
