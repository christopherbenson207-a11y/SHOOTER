--!strict
-- Picks the weather (Shared.Weather, 7 Nov 2026). Server side it only writes workspace attributes; every screen blends
-- the look itself (StarterPlayerScripts.WeatherClient), so nothing per frame runs here.
--   On boot: one preset at once, so the deploy screen already has weather.
--   A match starts (WaveState leaves one of the set's Idle states): a new preset, never the last one, blended in over
--   StartBlend seconds. The set's Shift block may then roll a second preset partway through (Shift.After), blended
--   in slowly (Shift.Blend), as long as that match is still on.
--   WeatherSight caps how far bots see (Soldier:Foes) in fog, snow and at night.
-- Studio: workspace StudioWeather = "<preset>" forces one (StudioWeatherBlend seconds, default 0).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Weather = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weather"))

local set = Weather.Set()
if not set then
	return
end

local rng = Random.new()
local current: string? = nil
local token = 0

local function apply(name: string, blend: number)
	local preset = set.Presets[name]
	if not preset then
		return
	end
	token += 1
	workspace:SetAttribute("WeatherFrom", current)
	workspace:SetAttribute("Weather", name)
	workspace:SetAttribute("WeatherBlend", math.max(0, blend))
	workspace:SetAttribute("WeatherSight", preset.Sight)
	current = name
	-- Last: WeatherClient starts a blend whenever this one changes.
	workspace:SetAttribute("WeatherStart", workspace:GetServerTimeNow())
end

local function idle(state: any): boolean
	return state == nil or set.Idle[state] == true
end

local function scheduleShift()
	local shift = set.Shift
	if not shift or rng:NextNumber() > shift.Chance then
		return
	end
	local from = current
	local options = from and shift.To[from]
	if not options or #options == 0 then
		return
	end
	local mine = token
	task.delay(rng:NextNumber(shift.After.Min, shift.After.Max), function()
		if token ~= mine or idle(workspace:GetAttribute("WaveState")) then
			return
		end
		apply(options[rng:NextInteger(1, #options)], shift.Blend)
	end)
end

local function startMatch()
	if RunService:IsStudio() and typeof(workspace:GetAttribute("StudioWeather")) == "string" then
		return
	end
	apply(Weather.Roll(set, current, rng), set.StartBlend)
	scheduleShift()
end

local lastState = workspace:GetAttribute("WaveState")
workspace:GetAttributeChangedSignal("WaveState"):Connect(function()
	local state = workspace:GetAttribute("WaveState")
	if idle(lastState) and not idle(state) then
		startMatch()
	end
	lastState = state
end)

local function studioForce(): boolean
	local forced = workspace:GetAttribute("StudioWeather")
	if RunService:IsStudio() and typeof(forced) == "string" and set.Presets[forced] then
		local blend = workspace:GetAttribute("StudioWeatherBlend")
		apply(forced, if typeof(blend) == "number" then blend else 0)
		return true
	end
	return false
end

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("StudioWeather"):Connect(studioForce)
end
if not studioForce() then
	apply(Weather.Roll(set, nil, rng), 0)
	if not idle(lastState) then
		scheduleShift()
	end
end
