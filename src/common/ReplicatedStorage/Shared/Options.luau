--!strict
-- This player's settings on the client (GameConfig.Settings). Options.Get(key) is the
-- current value; Options.Set(key, value) changes it (clamped, snapped to the option's Step),
-- fires Options.Changed(key, value) and sends the whole set to SettingsServer to save.
-- Saved values arrive once in the player's Settings attribute (Profile). Everything that
-- reads a setting (GunClient, TouchControls, Gore, CombatFx) requires this one module, so
-- they share the same table.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local CFG = GameConfig.Settings

local Options = {}

local values: { [string]: any } = {}
for _, key in CFG.Order do
	values[key] = CFG[key].Default
end

local changed = Instance.new("BindableEvent")
Options.Changed = changed.Event

local function fit(key: string, value: any): any
	local option = CFG[key]
	if not option then
		return nil
	end
	if option.Choices then
		return if table.find(option.Choices, value) then value else nil
	elseif type(option.Default) == "boolean" then
		return if type(value) == "boolean" then value else nil
	elseif type(value) == "number" and value == value then
		local v = math.clamp(value, option.Min, option.Max)
		return math.clamp(option.Min + math.round((v - option.Min) / option.Step) * option.Step, option.Min, option.Max)
	end
	return nil
end

function Options.Get(key: string): any
	return values[key]
end

local function send()
	local remote = ReplicatedStorage:FindFirstChild("Remotes")
	remote = remote and remote:FindFirstChild("Settings")
	if remote then
		(remote :: RemoteEvent):FireServer(values)
	end
end

function Options.Set(key: string, value: any)
	local v = fit(key, value)
	if v == nil or v == values[key] then
		return
	end
	values[key] = v
	changed:Fire(key, v)
	send()
end

-- Text values outside GameConfig.Settings.Order: only "Binds" (Shared.Controls' saved key bindings).
local RAW = { Binds = 2000 }
values.Binds = ""

function Options.SetRaw(key: string, value: string)
	local limit = RAW[key]
	if not limit or type(value) ~= "string" or #value > limit or value == values[key] then
		return
	end
	values[key] = value
	changed:Fire(key, value)
	send()
end

-- Back to every default.
function Options.Reset()
	for _, key in CFG.Order do
		if values[key] ~= CFG[key].Default then
			values[key] = CFG[key].Default
			changed:Fire(key, values[key])
		end
	end
	send()
end

-- The saved set, once Profile has loaded it.
local player = Players.LocalPlayer
if player then
	local function load()
		local raw = player:GetAttribute("Settings")
		if type(raw) ~= "string" then
			return false
		end
		local ok, saved = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(saved) == "table" then
			for _, key in CFG.Order do
				local v = fit(key, saved[key])
				if v ~= nil and v ~= values[key] then
					values[key] = v
					changed:Fire(key, v)
				end
			end
			for key, limit in RAW do
				local v = saved[key]
				if type(v) == "string" and #v <= limit and v ~= values[key] then
					values[key] = v
					changed:Fire(key, v)
				end
			end
		end
		return true
	end
	if not load() then
		local connection
		connection = player:GetAttributeChangedSignal("Settings"):Connect(function()
			if load() then
				connection:Disconnect()
			end
		end)
	end
end

return Options
