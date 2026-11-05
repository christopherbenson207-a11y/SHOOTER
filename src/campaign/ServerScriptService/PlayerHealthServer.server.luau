-- Starts player health, going down, revives and the devour (ServerStorage.Modules.PlayerHealth),
-- what players carry (ServerStorage.Modules.Inventory) and bandages
-- (ServerStorage.Modules.Bandages).

local ServerStorage = game:GetService("ServerStorage")

require(ServerStorage.Modules.PlayerHealth).Start()
require(ServerStorage.Modules.Inventory).Start()
require(ServerStorage.Modules.Bandages).Start()
