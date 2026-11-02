-- Starts the mounted guns and artillery (ServerStorage.Modules.Emplacements, the GUNS stream).
-- WarServer may call Emplacements.Start() too; it only runs once.
local ServerStorage = game:GetService("ServerStorage")

local Emplacements = require(ServerStorage:WaitForChild("Modules"):WaitForChild("Emplacements"))
Emplacements.Start()
