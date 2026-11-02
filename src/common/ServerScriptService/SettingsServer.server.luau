--!strict
-- Saves each player's settings (GameConfig.Settings) to their Profile. Clients send the whole
-- set on Remotes.Settings when they change something; every value is checked against the
-- option's kind and range, unknown keys are dropped, and saves are spaced SaveGap apart (the
-- latest set wins). Shared.Options on the client applies them; nothing here changes gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Profile = require(ServerStorage.Modules.Profile)

local CFG = GameConfig.Settings
local remote = ReplicatedStorage.Remotes.Settings

local lastSave: { [Player]: number } = {}
local pending: { [Player]: { [string]: any } } = {}

local function clean(input: any): { [string]: any }?
	if type(input) ~= "table" then
		return nil
	end
	local out = {}
	for _, key in CFG.Order do
		local option = CFG[key]
		local value = input[key]
		if option.Choices then
			if type(value) == "string" and table.find(option.Choices, value) then
				out[key] = value
			end
		elseif type(option.Default) == "boolean" then
			if type(value) == "boolean" then
				out[key] = value
			end
		elseif type(value) == "number" and value == value and math.abs(value) ~= math.huge then
			out[key] = math.clamp(value, option.Min, option.Max)
		end
	end
	return out
end

local function flush(player: Player)
	local settings = pending[player]
	if not settings or not player.Parent then
		return
	end
	pending[player] = nil
	lastSave[player] = os.clock()
	Profile.SetSettings(player, settings)
end

remote.OnServerEvent:Connect(function(player, input)
	local settings = clean(input)
	if not settings then
		return
	end
	local waiting = pending[player] ~= nil
	pending[player] = settings
	if waiting then
		return
	end
	local wait = CFG.SaveGap - (os.clock() - (lastSave[player] or -math.huge))
	if wait <= 0 then
		flush(player)
	else
		task.delay(wait, flush, player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	flush(player)
	lastSave[player] = nil
	pending[player] = nil
end)
