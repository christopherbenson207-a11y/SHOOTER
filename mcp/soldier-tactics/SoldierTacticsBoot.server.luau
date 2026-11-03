-- Turns on SoldierTactics (ServerStorage.Modules.SoldierTactics) once the server starts.
-- Delete or disable this Script to turn the tactics off; nothing else changes.
-- Install guide: mcp/soldier-tactics/INSTALL.md in the SHOOTER repo.

local ServerStorage = game:GetService("ServerStorage")

local modules = ServerStorage:WaitForChild("Modules", 30)
local tactics = modules and modules:WaitForChild("SoldierTactics", 30)
if not tactics then
	warn("SoldierTacticsBoot: ServerStorage.Modules.SoldierTactics not found")
	return
end

local ok, err = pcall(function()
	require(tactics).Install()
end)
if not ok then
	warn("SoldierTacticsBoot: " .. tostring(err))
end
