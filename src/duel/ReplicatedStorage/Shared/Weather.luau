--!strict
-- Weather presets for every combat place (7 Nov 2026, FRONTLINE open-world plan phase 1). One copy of this file
-- ships to the campaign (FRONTLINE, the winter valley), the Multiplayer duel (desert) and the Zombies place
-- (Ashgrove Manor at night); the lobby keeps its own menu lighting (MenuStage).
--
-- How it runs:
--   ServerScriptService.WeatherServer picks a preset when a match starts (WaveState leaves one of the set's Idle
--   states) and may shift to a second one partway through. It only writes workspace attributes:
--     Weather       preset name now          WeatherFrom   the one before (nil: the place as saved)
--     WeatherStart  server time the blend began          WeatherBlend  seconds the blend takes
--     WeatherSight  the furthest a bot can see in it (studs), or nil
--   StarterPlayerScripts.WeatherClient blends Lighting, Atmosphere, Clouds, the place's grade, bloom, sun rays and
--   wind on each screen from those attributes (never tweened on the server), and drops the snow, dust or ice motes.
--   StarterPlayerScripts.BattleAmbience reads the set's Ambience block; Soldier caps its sight at WeatherSight.
-- A preset only changes what it names: anything it leaves out stays as the place was saved.
-- Studio: workspace attribute StudioWeather = "<preset>" forces one (StudioWeatherBlend seconds, default 0).

export type Fall = {
	Kind: string, -- "Snow", "Blizzard", "Motes" or "Dust"
	Rate: number, -- particles a second at High graphics
	Glow: number?, -- 0..1: how much the flakes light themselves (night snow is invisible lit only by the night)
}

export type Preset = {
	Weight: number,
	Clock: number?,
	Brightness: number?,
	Ambient: Color3?,
	Outdoor: Color3?,
	Exposure: number?,
	Atmo: { Density: number?, Offset: number?, Haze: number?, Glare: number?, Color: Color3?, Decay: Color3? }?,
	Clouds: { Cover: number?, Density: number?, Color: Color3? }?,
	Grade: { Brightness: number?, Contrast: number?, Saturation: number?, Tint: Color3? }?,
	Bloom: number?,
	SunRays: number?,
	Wind: Vector3?,
	Fall: Fall?,
	Gusts: boolean?, -- wind and snow surge and drop
	WindSound: number?, -- volume of a howling wind loop
	Flares: boolean?, -- illumination flares over the objective (BattleAmbience)
	Sight: number?, -- bots see no further than this
}

export type Ambience = {
	Artillery: NumberRange?, -- seconds between distant guns (flash on the horizon, a late thump)
	Tracers: NumberRange?, -- seconds between bursts of anti-aircraft tracers in the sky
	Planes: NumberRange?, -- seconds between bombers passing high over
	Smoke: boolean?, -- a smoke column over the objective
}

export type Set = {
	Grade: string?, -- the ColorCorrectionEffect in Lighting this set grades (nil: leave the grade alone)
	Idle: { [string]: boolean }, -- WaveState values between matches; leaving one starts a match
	StartBlend: number,
	Shift: { Chance: number, After: NumberRange, Blend: number, To: { [string]: { string } } }?,
	Ambience: Ambience?,
	Presets: { [string]: Preset },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Weather = {}

Weather.Sets = {
	-- FRONTLINE: the winter valley, late Cold War Eastern Europe.
	Valley = {
		Grade = "NightGrade",
		Idle = { FrontEnd = true, Waiting = true, GameOver = true },
		StartBlend = 6,
		Shift = {
			Chance = 0.4,
			After = NumberRange.new(300, 480),
			Blend = 90,
			To = {
				["Clear Morning"] = { "Overcast" },
				["Overcast"] = { "Snowfall" },
				["Snowfall"] = { "Blizzard" },
				["Blizzard"] = { "Snowfall" },
				["Freezing Fog"] = { "Clear Morning" },
				["Golden Dusk"] = { "Night Battle" },
			},
		},
		Ambience = {
			Artillery = NumberRange.new(5, 12),
			Tracers = NumberRange.new(7, 16),
			Planes = NumberRange.new(55, 110),
			Smoke = true,
		},
		Presets = {
			["Clear Morning"] = {
				Weight = 1,
				Clock = 8.5,
				Brightness = 2.4,
				Ambient = rgb(88, 92, 104),
				Outdoor = rgb(150, 154, 168),
				Exposure = 0.1,
				Atmo = { Density = 0.28, Offset = 0.12, Haze = 0.6, Glare = 0.35, Color = rgb(206, 214, 226), Decay = rgb(150, 128, 110) },
				Clouds = { Cover = 0.45, Density = 0.4, Color = rgb(236, 236, 240) },
				Grade = { Contrast = 0.1, Saturation = -0.05, Tint = rgb(255, 246, 236) },
				Bloom = 0.4,
				SunRays = 0.08,
				Wind = Vector3.new(4, 0, 2),
				Fall = { Kind = "Snow", Rate = 25 },
			},
			["Overcast"] = {
				Weight = 1,
				Clock = 13,
				Brightness = 1.6,
				Ambient = rgb(86, 90, 100),
				Outdoor = rgb(124, 128, 140),
				Exposure = 0.05,
				Atmo = { Density = 0.38, Offset = 0.08, Haze = 1.4, Glare = 0, Color = rgb(186, 192, 202), Decay = rgb(110, 114, 124) },
				Clouds = { Cover = 0.92, Density = 0.7, Color = rgb(150, 156, 166) },
				Grade = { Contrast = 0.08, Saturation = -0.18, Tint = rgb(236, 240, 248) },
				Bloom = 0.25,
				SunRays = 0,
				Wind = Vector3.new(6, 0, 3),
			},
			["Snowfall"] = {
				Weight = 1.2,
				Clock = 15,
				Brightness = 1.9,
				Ambient = rgb(78, 84, 98),
				Outdoor = rgb(122, 130, 148),
				Exposure = 0.05,
				Atmo = { Density = 0.45, Offset = 0.1, Haze = 1.8, Glare = 0.1, Color = rgb(192, 202, 216), Decay = rgb(96, 104, 122) },
				Clouds = { Cover = 0.85, Density = 0.6, Color = rgb(170, 178, 190) },
				Grade = { Contrast = 0.1, Saturation = -0.2, Tint = rgb(228, 238, 255) },
				Bloom = 0.3,
				SunRays = 0.02,
				Wind = Vector3.new(8, 0, 4),
				Fall = { Kind = "Snow", Rate = 150 },
				Sight = 260,
			},
			["Blizzard"] = {
				Weight = 0.7,
				Clock = 16,
				Brightness = 1.5,
				Ambient = rgb(84, 90, 104),
				Outdoor = rgb(120, 128, 144),
				Exposure = 0.12,
				Atmo = { Density = 0.62, Offset = 0.04, Haze = 2.6, Glare = 0, Color = rgb(200, 208, 220), Decay = rgb(120, 128, 144) },
				Clouds = { Cover = 1, Density = 0.85, Color = rgb(150, 156, 168) },
				Grade = { Contrast = 0.06, Saturation = -0.3, Tint = rgb(226, 236, 255) },
				Bloom = 0.2,
				SunRays = 0,
				Wind = Vector3.new(30, 0, 12),
				Fall = { Kind = "Blizzard", Rate = 600 },
				Gusts = true,
				WindSound = 0.55,
				Sight = 140,
			},
			["Freezing Fog"] = {
				Weight = 0.8,
				Clock = 7,
				Brightness = 1.2,
				Ambient = rgb(82, 88, 100),
				Outdoor = rgb(110, 118, 132),
				Exposure = 0.15,
				Atmo = { Density = 0.58, Offset = 0.04, Haze = 1.2, Glare = 0, Color = rgb(178, 186, 198), Decay = rgb(120, 126, 138) },
				Clouds = { Cover = 1, Density = 0.5, Color = rgb(160, 166, 176) },
				Grade = { Contrast = 0.05, Saturation = -0.35, Tint = rgb(232, 240, 250) },
				Bloom = 0.3,
				SunRays = 0,
				Wind = Vector3.new(1, 0, 0.5),
				Fall = { Kind = "Motes", Rate = 60 },
				Sight = 160,
			},
			["Golden Dusk"] = {
				Weight = 1,
				Clock = 17.4,
				Brightness = 2,
				Ambient = rgb(92, 78, 80),
				Outdoor = rgb(146, 124, 118),
				Exposure = 0.05,
				Atmo = { Density = 0.33, Offset = 0.18, Haze = 1.2, Glare = 0.5, Color = rgb(214, 186, 160), Decay = rgb(150, 96, 80) },
				Clouds = { Cover = 0.55, Density = 0.45, Color = rgb(230, 180, 150) },
				Grade = { Contrast = 0.12, Saturation = 0.05, Tint = rgb(255, 240, 226) },
				Bloom = 0.45,
				SunRays = 0.1,
				Wind = Vector3.new(3, 0, 1.5),
			},
			["Night Battle"] = {
				Weight = 0.8,
				Clock = 22.5,
				Brightness = 0.6,
				Ambient = rgb(56, 64, 92),
				Outdoor = rgb(78, 90, 128),
				Exposure = 0.25,
				Atmo = { Density = 0.4, Offset = 0, Haze = 0.6, Glare = 0, Color = rgb(70, 80, 106), Decay = rgb(40, 46, 66) },
				Clouds = { Cover = 0.6, Density = 0.5, Color = rgb(60, 66, 84) },
				Grade = { Contrast = 0.12, Saturation = -0.1, Tint = rgb(210, 222, 255) },
				Bloom = 0.5,
				SunRays = 0,
				Wind = Vector3.new(4, 0, 2),
				Flares = true,
				Sight = 220,
			},
		},
	} :: Set,

	-- Multiplayer duel: the desert town.
	Desert = {
		Grade = "DesertGrade",
		Idle = { DuelWait = true, DuelEnd = true },
		StartBlend = 4,
		Ambience = {
			Artillery = NumberRange.new(14, 30),
			Tracers = NumberRange.new(25, 45),
			Planes = NumberRange.new(80, 160),
		},
		Presets = {
			["High Noon"] = {
				Weight = 1.2,
				Clock = 13.6,
				Brightness = 3.2,
				Ambient = rgb(88, 88, 92),
				Outdoor = rgb(136, 140, 150),
				Exposure = 0,
				Atmo = { Density = 0.33, Offset = 0.12, Haze = 2.5, Glare = 0.35, Color = rgb(184, 208, 234), Decay = rgb(196, 186, 166) },
				Clouds = { Cover = 0.35, Density = 0.4, Color = rgb(255, 255, 255) },
				Grade = { Contrast = 0.1, Saturation = -0.1, Tint = rgb(255, 249, 238) },
				Bloom = 0.35,
				SunRays = 0.04,
				Wind = Vector3.new(3, 0, 1),
			},
			["Hazy Heat"] = {
				Weight = 1,
				Clock = 15.2,
				Brightness = 2.8,
				Ambient = rgb(96, 92, 88),
				Outdoor = rgb(146, 140, 132),
				Exposure = 0,
				Atmo = { Density = 0.42, Offset = 0.1, Haze = 3.4, Glare = 0.25, Color = rgb(214, 200, 176), Decay = rgb(196, 170, 130) },
				Clouds = { Cover = 0.2, Density = 0.3, Color = rgb(255, 250, 240) },
				Grade = { Contrast = 0.08, Saturation = -0.04, Tint = rgb(255, 244, 226) },
				Bloom = 0.35,
				SunRays = 0.03,
				Wind = Vector3.new(6, 0, 2),
				Fall = { Kind = "Dust", Rate = 20 },
			},
			["Blue Dawn"] = {
				Weight = 0.8,
				Clock = 6.6,
				Brightness = 1.6,
				Ambient = rgb(80, 86, 104),
				Outdoor = rgb(120, 130, 156),
				Exposure = 0.1,
				Atmo = { Density = 0.36, Offset = 0.15, Haze = 1.2, Glare = 0.3, Color = rgb(170, 186, 214), Decay = rgb(196, 160, 140) },
				Clouds = { Cover = 0.45, Density = 0.4, Color = rgb(220, 200, 196) },
				Grade = { Contrast = 0.08, Saturation = -0.06, Tint = rgb(236, 240, 255) },
				Bloom = 0.4,
				SunRays = 0.08,
				Wind = Vector3.new(2, 0, 1),
			},
			["Golden Dusk"] = {
				Weight = 1,
				Clock = 17.6,
				Brightness = 2.2,
				Ambient = rgb(96, 80, 76),
				Outdoor = rgb(156, 122, 104),
				Exposure = 0.05,
				Atmo = { Density = 0.35, Offset = 0.2, Haze = 1.6, Glare = 0.6, Color = rgb(224, 190, 158), Decay = rgb(170, 104, 78) },
				Clouds = { Cover = 0.5, Density = 0.45, Color = rgb(236, 178, 140) },
				Grade = { Contrast = 0.12, Saturation = 0.06, Tint = rgb(255, 234, 208) },
				Bloom = 0.45,
				SunRays = 0.1,
				Wind = Vector3.new(3, 0, 1),
			},
			["Dust Storm"] = {
				Weight = 0.6,
				Clock = 14.5,
				Brightness = 2.2,
				Ambient = rgb(110, 96, 80),
				Outdoor = rgb(150, 130, 104),
				Exposure = 0.1,
				Atmo = { Density = 0.58, Offset = 0.02, Haze = 3.8, Glare = 0, Color = rgb(196, 164, 122), Decay = rgb(160, 128, 90) },
				Clouds = { Cover = 1, Density = 0.7, Color = rgb(176, 150, 118) },
				Grade = { Contrast = 0.06, Saturation = -0.12, Tint = rgb(255, 236, 206) },
				Bloom = 0.2,
				SunRays = 0,
				Wind = Vector3.new(26, 0, 8),
				Fall = { Kind = "Dust", Rate = 160 },
				Gusts = true,
				WindSound = 0.5,
			},
		},
	} :: Set,

	-- Zombies: Ashgrove Manor at night. The manor's own night lighting stays; only the air changes.
	Manor = {
		Grade = nil,
		Idle = { Waiting = true, GameOver = true },
		StartBlend = 5,
		Presets = {
			["Still Night"] = { Weight = 1.2 },
			["Mist"] = {
				Weight = 1,
				Atmo = { Density = 0.3, Haze = 2 },
				Wind = Vector3.new(2, 0, 1),
			},
			["Snow"] = {
				Weight = 1,
				Atmo = { Density = 0.18, Haze = 1.6 },
				Wind = Vector3.new(5, 0, 2),
				Fall = { Kind = "Snow", Rate = 90, Glow = 0.6 },
			},
			["Freezing Fog"] = {
				Weight = 0.7,
				Atmo = { Density = 0.42, Haze = 1 },
				Wind = Vector3.new(1, 0, 0.5),
				Fall = { Kind = "Motes", Rate = 50, Glow = 0.6 },
			},
		},
	} :: Set,
}

-- Which set each place uses (workspace attribute WeatherSet overrides, e.g. in a test copy).
Weather.Places = {
	[78870312741411] = "Valley",
	[75051098491738] = "Desert",
	[121963671263674] = "Manor",
}

function Weather.SetName(): string?
	local forced = workspace:GetAttribute("WeatherSet")
	if typeof(forced) == "string" and Weather.Sets[forced] then
		return forced
	end
	return Weather.Places[game.PlaceId]
end

function Weather.Set(): Set?
	local name = Weather.SetName()
	return if name then (Weather.Sets :: any)[name] else nil
end

function Weather.Preset(name: any): Preset?
	local set = Weather.Set()
	if not set or typeof(name) ~= "string" then
		return nil
	end
	return set.Presets[name]
end

-- A preset by weight, never the one named in `last` when there is another.
function Weather.Roll(set: Set, last: string?, rng: Random?): string
	local r = rng or Random.new()
	local names, total = {}, 0
	for name, preset in set.Presets do
		if name ~= last then
			table.insert(names, name)
			total += preset.Weight
		end
	end
	table.sort(names)
	if #names == 0 then
		return last :: string
	end
	local roll = r:NextNumber() * total
	for _, name in names do
		roll -= set.Presets[name].Weight
		if roll <= 0 then
			return name
		end
	end
	return names[#names]
end

-- The furthest a bot can see right now (math.huge when the weather doesn't limit it).
function Weather.Sight(): number
	local s = workspace:GetAttribute("WeatherSight")
	return if typeof(s) == "number" and s > 0 then s else math.huge
end

return Weather
