--!nocheck
-- StarterPlayer.StarterPlayerScripts.CrashIntroClient  (INTRO stream)
-- Source on disk: horror-shooter/war/intro/CrashIntroClient.client.lua
--
-- Plays the HOUND crash intro when the server fires Remotes.CrashIntro with
-- { Start = CFrame, Seat = n, Commander = "HALE" }, then fires Remotes.CrashIntro:FireServer("Done").
-- Everything it builds is local, lives in one folder under workspace.CurrentCamera and is destroyed
-- at the end. It never freezes the character (the server does that) and never builds UI.
--
-- The Kit section (up to the ModuleScript guard) is pure building/posing code, so an Edit-mode test
-- can copy this source into a ModuleScript, require it and call Kit.Build / Kit.Pose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local V3 = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local sin = math.sin
local clamp = math.clamp
local noise = math.noise

local Kit = {}

-- Timeline (seconds)
local T = {
	A2 = 2.8, -- high wide over the valley
	B1 = 5.2, -- cabin wide
	B2 = 8.4, -- POV from the player's seat
	HIT = 10.8, -- direct hit
	D1 = 13.4, -- chase cam on the burning wing
	D2 = 15.6, -- ground cam at the crash site
	IMPACT = 18.2, -- cut to black
	WAKE = 19.8, -- fade in, lying in the snow
	RISE = 22.6, -- get up
	END = 24.0,
}
Kit.T = T

local function hex(s)
	return Color3.fromHex(s)
end

local COL = {
	OLIVE = hex("4B5320"),
	OLIVE_D = hex("41471C"),
	OLIVE_L = hex("565E2A"),
	PATCH = hex("5E6532"),
	RADOME = hex("3E4137"),
	GREY = hex("5D6155"),
	GUN = hex("2F3133"),
	SOOT = hex("23231F"),
	GLASS = hex("14181C"),
	PROP = hex("6A6E66"),
	CABIN = hex("666955"),
	CABIN_D = hex("4C4F43"),
	FLOOR = hex("383A36"),
	WEB = hex("6E2620"),
	COYOTE = hex("7A6A4F"),
	COYOTE_D = hex("625540"),
	RANGER = hex("4A5038"),
	CLOTH = hex("5D6155"),
	CLOTH_2 = hex("6A6852"),
	BALA = hex("262725"),
	SKIN = hex("8E6E55"),
	BOOT = hex("2B2620"),
	WOOD = hex("6B4A2E"),
	SNOW_N = hex("C7CDD3"),
	ROCK_N = hex("4A4F55"),
	LAMP = Color3.fromRGB(190, 32, 24),
	LAMP_OFF = hex("3A1A18"),
	PORT = Color3.fromRGB(150, 34, 24),
	RED = hex("7A1E1A"),
}

local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local AZ = ANG(0, rad(90), 0) -- cylinder axis along Z
local AY = ANG(0, 0, rad(90)) -- cylinder axis along Y

local FIRE_TEX = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

local function smooth(x)
	x = clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerp(a, b, k)
	return a + (b - a) * k
end

local function newPart(className, shape)
	local p = Instance.new(className)
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Locked = true
	return p
end

local SHAPES = { Ball = Enum.PartType.Ball, Cyl = Enum.PartType.Cylinder }

-- A part that rides the plane: world CFrame = planeCF * groupCF[group] * localCF
local function add(rig, group, shape, size, cf, color, mat, small)
	local p = shape == "Wedge" and newPart("WedgePart") or newPart("Part", SHAPES[shape])
	p.Size = size
	p.Color = color
	p.Material = mat or SMOOTH
	p.CastShadow = not small
	p.CFrame = cf
	p.Parent = rig.model
	local n = #rig.parts + 1
	rig.parts[n] = p
	rig.locals[n] = cf
	rig.groups[n] = group
	return p
end

-- Right-angle wedge: corner P, leg U (length h), leg V (length d), thickness along U x V's normal
local function wedge(rig, group, P, U, h, Vd, d, thick, color, mat, small)
	local Y = U.Unit
	local Vu = Vd.Unit
	local Z = -Vu
	local X = Y:Cross(Z)
	return add(rig, group, "Wedge", V3(thick, h, d), CFrame.fromMatrix(P + Y * (h / 2) + Vu * (d / 2), X, Y, Z), color, mat, small)
end

-- Block from point a to point b (length along local Z)
local function limb(rig, group, a, b, w, t, color, mat, small)
	local dir = b - a
	local up = math.abs(dir.Unit.Y) > 0.9 and Vector3.zAxis or Vector3.yAxis
	return add(rig, group, "Block", V3(w, t, dir.Magnitude), CFrame.lookAt((a + b) / 2, b, up), color, mat, small)
end

-- Panel whose cross-section runs from (ax,ay) to (bx,by), extruded along Z
local function panelXY(rig, group, ax, ay, bx, by, zc, zlen, thick, color, mat, small)
	local a = V3(ax, ay, zc)
	local b = V3(bx, by, zc)
	local s = (b - a)
	local len = s.Magnitude
	s = s.Unit
	return add(rig, group, "Block", V3(thick, len, zlen), CFrame.fromMatrix((a + b) / 2, V3(s.Y, -s.X, 0), s), color, mat, small)
end

----------------------------------------------------------------------------------------------------
-- C-130 style transport. Local space: nose -Z, up +Y, right +X. Fuselage radius 6.
----------------------------------------------------------------------------------------------------

local WINDOWS = { -18, -8, 2, 10 }
local ENGINE_X = { -35, -19, 19, 35 }
local FIRE_ENGINE = 3 -- right inner engine

local function buildExterior(rig)
	local g = "body"
	-- fuselage and nose
	add(rig, g, "Cyl", V3(40, 12, 12), CF(0, 0, -6) * AZ, COL.OLIVE)
	add(rig, g, "Cyl", V3(6, 11.2, 11.2), CF(0, -0.3, -29) * AZ, COL.OLIVE_L)
	add(rig, g, "Ball", V3(11.2, 11.2, 11.2), CF(0, -0.3, -32), COL.OLIVE_L)
	add(rig, g, "Ball", V3(8, 8, 8), CF(0, -1.9, -35.2), COL.RADOME)

	-- cockpit glass: panes on the nose sphere
	local noseC = V3(0, -0.3, -32)
	local function pane(az, el, w, h)
		local n = V3(math.sin(rad(az)) * math.cos(rad(el)), math.sin(rad(el)), -math.cos(rad(az)) * math.cos(rad(el)))
		local x = Vector3.yAxis:Cross(n)
		if x.Magnitude < 1e-3 then
			x = Vector3.xAxis
		end
		add(rig, g, "Block", V3(w, 0.25, h), CFrame.fromMatrix(noseC + n * 5.55, x.Unit, n), COL.GLASS, SMOOTH, true).Reflectance = 0.12
	end
	pane(0, 52, 2.4, 1.9)
	pane(-27, 50, 2.2, 1.8)
	pane(27, 50, 2.2, 1.8)
	pane(-62, 30, 2.0, 1.5)
	pane(62, 30, 2.0, 1.5)

	-- landing gear sponsons
	for _, s in { -1, 1 } do
		add(rig, g, "Cyl", V3(16, 4.6, 4.6), CF(s * 5.3, -4.0, -2) * AZ, COL.OLIVE_D)
		add(rig, g, "Ball", V3(4.6, 4.6, 4.6), CF(s * 5.3, -4.0, -10), COL.OLIVE_D)
		add(rig, g, "Ball", V3(4.6, 4.6, 4.6), CF(s * 5.3, -4.0, 6), COL.OLIVE_D)
	end

	-- upswept rear fuselage and cargo ramp
	add(rig, g, "Cyl", V3(8, 11.4, 11.4), CF(0, 0.3, 18) * AZ, COL.OLIVE)
	add(rig, g, "Cyl", V3(7, 9.6, 9.6), CF(0, 1.2, 25.5) * AZ, COL.OLIVE)
	add(rig, g, "Cyl", V3(6, 7.4, 7.4), CF(0, 2.3, 32) * AZ, COL.OLIVE_D)
	add(rig, g, "Cyl", V3(5, 5, 5), CF(0, 3.5, 37.5) * AZ, COL.OLIVE_D)
	add(rig, g, "Ball", V3(5, 5, 5), CF(0, 3.5, 40), COL.OLIVE_D)
	add(rig, g, "Block", V3(7, 0.6, 19.6), CF(0, -3.5, 23.5) * ANG(rad(-13.6), 0, 0), COL.OLIVE_D)

	-- high wing
	add(rig, g, "Block", V3(24, 1.6, 14), CF(0, 6.4, -6), COL.OLIVE)
	add(rig, g, "Block", V3(5, 1.1, 13), CF(0, 7.55, -6), COL.OLIVE_D)
	for _, s in { -1, 1 } do
		add(rig, g, "Block", V3(40, 1.3, 8), CF(s * 32, 6.4, -9), COL.OLIVE)
		wedge(rig, g, V3(s * 12, 6.4, -5), V3(s, 0, 0), 40, V3(0, 0, 1), 6, 1.3, COL.OLIVE)
		add(rig, g, "Cyl", V3(1.3, 8, 8), CF(s * 52, 6.4, -9) * AY, COL.OLIVE)
		local nav = add(rig, g, "Ball", V3(0.6, 0.6, 0.6), CF(s * 56, 6.4, -9), s < 0 and Color3.fromRGB(255, 40, 30) or Color3.fromRGB(40, 255, 90), NEON, true)
		nav.Transparency = 0.15
	end
	-- faded paint patches on the wing top
	for _, pz in { { -8, -9, 6, 4 }, { 27, -10, 7, 3.5 }, { -30, -8, 5, 3 }, { 41, -9, 4, 3 } } do
		add(rig, g, "Block", V3(pz[3], 0.06, pz[4]), CF(pz[1], 7.08 + (math.abs(pz[1]) < 12 and 0.15 or 0), pz[2]), COL.PATCH, SMOOTH, true)
	end

	-- four turboprops
	rig.engines = {}
	for i, ex in ENGINE_X do
		local y = 5.0
		add(rig, g, "Cyl", V3(12, 3.8, 3.8), CF(ex, y, -13) * AZ, COL.OLIVE)
		add(rig, g, "Cyl", V3(1.4, 4.3, 4.3), CF(ex, y, -18.6) * AZ, COL.OLIVE_D)
		add(rig, g, "Block", V3(1.7, 1.3, 4.5), CF(ex, y - 2.0, -16.2), COL.OLIVE_D, SMOOTH, true)
		add(rig, g, "Block", V3(1.0, 0.5, 0.4), CF(ex, y - 2.2, -18.45), COL.GUN, SMOOTH, true)
		add(rig, g, "Ball", V3(3.0, 3.0, 3.0), CF(ex, y - 0.2, -6.8), COL.OLIVE)
		add(rig, g, "Ball", V3(1.9, 1.9, 1.9), CF(ex, y, -19.6), COL.GUN, METAL, true)
		add(rig, g, "Block", V3(1.8, 0.12, 5), CF(ex, 7.08, -5), COL.SOOT, SMOOTH, true)
		local pg = "prop" .. i
		rig.groupCF[pg] = CFrame.identity
		local disc = add(rig, pg, "Cyl", V3(0.1, 13.5, 13.5), AZ, COL.PROP, SMOOTH, true)
		disc.Transparency = 0.86
		for k = 0, 1 do
			add(rig, pg, "Block", V3(0.32, 13.2, 0.75), ANG(0, 0, k * math.pi / 2) * ANG(0, rad(24), 0), COL.GUN, METAL, true)
		end
		rig.engines[i] = { hub = V3(ex, y, -20.1), disc = disc }
	end

	-- tail
	add(rig, g, "Block", V3(0.9, 13, 7), CF(0, 12.4, 36.5), COL.OLIVE)
	wedge(rig, g, V3(0, 5.9, 33), V3(0, 1, 0), 13, V3(0, 0, -1), 9, 0.9, COL.OLIVE)
	add(rig, g, "Block", V3(0.95, 0.5, 7.4), CF(0, 19.0, 36.5), COL.OLIVE_D, SMOOTH, true)
	add(rig, g, "Block", V3(0.95, 12, 0.15), CF(0, 12.4, 37.6), COL.OLIVE_D, SMOOTH, true)
	add(rig, g, "Block", V3(34, 0.7, 5.5), CF(0, 6.1, 37.8), COL.OLIVE)
	for _, s in { -1, 1 } do
		wedge(rig, g, V3(s * 2, 6.1, 35.05), V3(s, 0, 0), 15, V3(0, 0, -1), 2.5, 0.7, COL.OLIVE)
		add(rig, g, "Cyl", V3(0.7, 5.5, 5.5), CF(s * 17, 6.1, 37.8) * AY, COL.OLIVE)
	end

	-- portholes glowing with the red cabin light (hidden during interior shots)
	rig.ports = {}
	for _, s in { -1, 1 } do
		for _, z in WINDOWS do
			local p = add(rig, g, "Cyl", V3(0.2, 1.1, 1.1), CF(s * 5.97, 0.6, z), COL.PORT, NEON, true)
			table.insert(rig.ports, p)
		end
	end

	-- beacon and tail light
	rig.beacon = add(rig, g, "Block", V3(0.5, 0.4, 0.9), CF(0, 8.3, -1), Color3.fromRGB(255, 30, 20), NEON, true)
	add(rig, g, "Ball", V3(0.5, 0.5, 0.5), CF(0, 3.5, 42.6), Color3.fromRGB(255, 245, 230), NEON, true)
end

----------------------------------------------------------------------------------------------------
-- Cabin interior (seen from inside, the exterior shell is culled, so the window gaps are real windows)
----------------------------------------------------------------------------------------------------

local function buildInterior(rig)
	local g = "body"
	local IW = 4.6
	add(rig, g, "Block", V3(9.0, 0.4, 38), CF(0, -3.8, -5), COL.FLOOR, METAL)
	for _, s in { -1, 1 } do
		add(rig, g, "Block", V3(0.5, 0.1, 37), CF(s * 1.5, -3.56, -5), COL.GUN, METAL, true)
	end

	for _, s in { -1, 1 } do
		add(rig, g, "Block", V3(0.4, 3.6, 38), CF(s * IW, -1.8, -5), COL.CABIN)
		local edges = { -24 }
		for _, z in WINDOWS do
			table.insert(edges, z - 0.55)
			table.insert(edges, z + 0.55)
		end
		table.insert(edges, 14)
		for k = 1, #edges, 2 do
			local a, b = edges[k], edges[k + 1]
			add(rig, g, "Block", V3(0.4, 1.2, b - a), CF(s * IW, 0.6, (a + b) / 2), COL.CABIN)
		end
		add(rig, g, "Block", V3(0.4, 1.8, 38), CF(s * IW, 2.1, -5), COL.CABIN)
		panelXY(rig, g, s * 4.6, 2.95, s * 2.7, 4.8, -5, 38, 0.4, COL.CABIN)
		-- ribs
		for z = -22, 13, 5 do
			add(rig, g, "Block", V3(0.25, 6.6, 0.35), CF(s * 4.33, -0.3, z), COL.CABIN_D, SMOOTH, true)
		end
		-- grab rails along the ceiling and the static line
		add(rig, g, "Cyl", V3(37, 0.3, 0.3), CF(s * 1.05, 4.45, -5) * AZ, COL.GREY, METAL, true)
		add(rig, g, "Block", V3(0.08, 0.08, 36), CF(s * 2.0, 3.7, -5), COL.GUN, SMOOTH, true)
		-- red webbing bench
		add(rig, g, "Block", V3(1.3, 0.14, 24), CF(s * 3.75, -2.07, -7), COL.WEB)
		add(rig, g, "Block", V3(0.12, 1.7, 24), CF(s * 4.33, -1.1, -7), COL.WEB)
		add(rig, g, "Block", V3(0.12, 0.12, 24), CF(s * 3.08, -2.07, -7), COL.GUN, METAL, true)
		add(rig, g, "Block", V3(0.12, 0.12, 24), CF(s * 4.3, -0.2, -7), COL.GUN, METAL, true)
		for z = -18, 4, 5.5 do
			add(rig, g, "Block", V3(0.12, 1.5, 0.12), CF(s * 3.12, -2.85, z), COL.GUN, METAL, true)
		end
	end
	add(rig, g, "Block", V3(5.6, 0.4, 38), CF(0, 4.85, -5), COL.CABIN_D)
	for z = -22, 13, 5 do
		add(rig, g, "Block", V3(5.4, 0.25, 0.35), CF(0, 4.6, z), COL.CABIN_D, SMOOTH, true)
	end

	-- front bulkhead with the doorway to the flight deck
	add(rig, g, "Block", V3(3.4, 6.7, 0.4), CF(-2.8, -0.35, -24), COL.CABIN_D)
	add(rig, g, "Block", V3(3.4, 6.7, 0.4), CF(2.8, -0.35, -24), COL.CABIN_D)
	add(rig, g, "Block", V3(2.2, 0.9, 0.4), CF(0, 2.55, -24), COL.CABIN_D)
	add(rig, g, "Block", V3(5.4, 1.9, 0.4), CF(0, 3.95, -24), COL.CABIN_D)
	add(rig, g, "Block", V3(5, 6, 0.4), CF(0, -0.3, -30), COL.GUN)
	add(rig, g, "Block", V3(4, 0.4, 6), CF(0, -3.8, -27), COL.FLOOR, METAL)
	for k = 1, 3 do
		add(rig, g, "Block", V3(2, 0.4, 1), CF(0, -3.8 + k * 0.8, -24.5 - k), COL.GUN, METAL, true)
	end
	local panel = add(rig, g, "Block", V3(1.6, 0.6, 0.1), CF(0, 0.8, -29.75), Color3.fromRGB(40, 90, 60), NEON, true)
	panel.Transparency = 0.3
	add(rig, g, "Block", V3(0.35, 0.35, 0.12), CF(1.9, 2.6, -23.76), Color3.fromRGB(255, 40, 30), NEON, true)
	add(rig, g, "Block", V3(0.35, 0.35, 0.12), CF(1.9, 2.1, -23.76), hex("1F3A22"), SMOOTH, true)
	add(rig, g, "Cyl", V3(1.0, 0.45, 0.45), CF(3.4, -1.0, -23.6) * AY, COL.RED, SMOOTH, true)
	add(rig, g, "Block", V3(1, 0.7, 0.3), CF(-3.6, 1.6, -23.7), COL.OLIVE, SMOOTH, true)

	-- closed cargo ramp door at the rear
	add(rig, g, "Block", V3(8.8, 6.6, 0.4), CF(0, -0.3, 13.8), COL.CABIN_D)
	add(rig, g, "Block", V3(5.4, 1.9, 0.4), CF(0, 3.95, 13.8), COL.CABIN_D)
	for _, y in { -2.2, 0.2, 2.4 } do
		add(rig, g, "Block", V3(7.6, 0.25, 0.2), CF(0, y, 13.5), COL.GUN, METAL, true)
	end
	-- a few rucksacks on the floor at the back
	add(rig, g, "Block", V3(1.3, 1.0, 1.6), CF(-1.1, -3.1, 9.5), COL.COYOTE, SMOOTH, true)
	add(rig, g, "Block", V3(1.3, 1.1, 1.5), CF(1.0, -3.05, 11.5) * ANG(0, rad(12), 0), COL.RANGER, SMOOTH, true)
	add(rig, g, "Block", V3(1.2, 0.9, 1.4), CF(-0.6, -3.15, 12.8) * ANG(0, rad(-20), 0), COL.COYOTE_D, SMOOTH, true)

	-- red cabin lamps (lights only on during interior shots)
	rig.lamps = {}
	for _, z in { -16, -4, 8 } do
		local l = add(rig, g, "Block", V3(1.0, 0.2, 0.6), CF(0, 4.55, z), COL.LAMP, NEON, true)
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 42, 28)
		pl.Brightness = 2.2
		pl.Range = 15
		pl.Shadows = false
		pl.Enabled = false
		pl.Parent = l
		table.insert(rig.lamps, { part = l, light = pl })
	end
end

----------------------------------------------------------------------------------------------------
-- Squad: 8 seated operators facing inward, and Captain HALE standing at the front
----------------------------------------------------------------------------------------------------

-- seat order: the player's Seat n picks one of these (rear seats first)
local SEATS = { { 1, 2 }, { -1, 2 }, { 1, -4 }, { -1, -4 }, { 1, -10 }, { -1, -10 }, { 1, -16 }, { -1, -16 } }
local VESTS = { COL.COYOTE, COL.RANGER, COL.COYOTE_D, COL.COYOTE, COL.RANGER, COL.COYOTE_D, COL.RANGER, COL.COYOTE }
local HELMETS = { COL.RANGER, COL.COYOTE, COL.OLIVE_D, COL.RANGER, COL.COYOTE_D, COL.RANGER, COL.COYOTE, COL.OLIVE_D }
local HEAD_POS = V3(0, 2.65, 0.12)

local function buildFigure(rig, g, i)
	local cloth = (i % 3 == 0) and COL.CLOTH_2 or COL.CLOTH
	for _, sx in { -0.42, 0.42 } do
		limb(rig, g, V3(sx, 0.1, 0.25), V3(sx, 0.1, -1.45), 0.66, 0.62, cloth)
		limb(rig, g, V3(sx, 0.08, -1.45), V3(sx * 1.05, -1.32, -1.55), 0.6, 0.6, cloth)
		add(rig, g, "Block", V3(0.68, 0.36, 1.0), CF(sx * 1.05, -1.45, -1.72), COL.BOOT, SMOOTH, true)
	end
	add(rig, g, "Block", V3(1.6, 0.5, 0.95), CF(0, 0.12, 0.1), cloth)
	add(rig, g, "Block", V3(1.6, 1.9, 0.9), CF(0, 1.25, 0.15), cloth)
	add(rig, g, "Block", V3(1.78, 1.35, 1.12), CF(0, 1.3, 0.12), VESTS[i])
	add(rig, g, "Block", V3(1.3, 0.45, 0.25), CF(0, 0.85, -0.5), COL.COYOTE_D, SMOOTH, true)
	local head = {}
	table.insert(head, add(rig, g, "Block", V3(0.85, 0.95, 0.85), CF(HEAD_POS), COL.BALA))
	table.insert(head, add(rig, g, "Ball", V3(1.15, 1.15, 1.15), CF(0, 2.88, 0.18), HELMETS[i]))
	table.insert(head, add(rig, g, "Block", V3(0.32, 0.28, 0.25), CF(0, 3.05, -0.42), COL.GUN, SMOOTH, true))
	-- arms resting on the rifle between the knees
	for _, sx in { -1, 1 } do
		limb(rig, g, V3(sx * 1.02, 2.05, 0.12), V3(sx * 1.05, 0.95, 0.0), 0.48, 0.5, cloth)
		limb(rig, g, V3(sx * 1.05, 0.95, 0.0), V3(sx * 0.22, 0.8, -1.2), 0.44, 0.44, cloth, SMOOTH, true)
	end
	-- AK standing between the knees, stock on the floor
	add(rig, g, "Block", V3(0.24, 1.5, 0.45), CF(0, 0.05, -1.45), COL.GUN, METAL, true)
	add(rig, g, "Block", V3(0.12, 1.1, 0.12), CF(0, 1.35, -1.45), COL.GUN, METAL, true)
	add(rig, g, "Block", V3(0.22, 0.9, 0.4), CF(0, -1.05, -1.45), COL.WOOD, Enum.Material.Wood, true)
	add(rig, g, "Block", V3(0.2, 0.6, 0.32), CF(0, -0.1, -1.78) * ANG(rad(-18), 0, 0), COL.GUN, METAL, true)
	return head
end

local function buildSquad(rig)
	rig.figs = {}
	for i, s in SEATS do
		local side, z = s[1], s[2]
		local g = "fig" .. i
		local jitter = ((i * 37) % 11 - 5) * 1.6
		local seat = CF(side * 3.55, -2.0, z) * ANG(0, side * rad(90) + rad(jitter), 0)
		rig.groupCF[g] = seat
		local head = buildFigure(rig, g, i)
		rig.figs[i] = { group = g, seat = seat, side = side, head = head }
	end
end

local HALE_HIP = CF(0, 3.6, 0)
local HALE_SHOULDER = CF(-1.15, 5.85, 0)

local function buildHale(rig)
	-- feet on the floor, facing aft toward the squad
	rig.haleBase = CF(-3.0, -3.6, -21.0) * ANG(0, math.pi, 0)
	local g = "hale"
	add(rig, g, "Block", V3(1.7, 0.5, 0.95), CF(0, 3.75, 0), COL.CLOTH)
	add(rig, g, "Block", V3(1.7, 2.0, 0.95), CF(0, 4.95, 0), COL.CLOTH)
	add(rig, g, "Block", V3(1.86, 1.4, 1.15), CF(0, 5.05, -0.03), COL.COYOTE)
	add(rig, g, "Block", V3(1.3, 0.45, 0.28), CF(0, 4.55, -0.68), COL.COYOTE_D, SMOOTH, true)
	add(rig, g, "Block", V3(0.55, 0.5, 0.25), CF(0.45, 5.45, -0.66), COL.GUN, SMOOTH, true)
	rig.haleHead = add(rig, g, "Block", V3(0.9, 1.0, 0.9), CF(0, 6.5, 0), COL.SKIN)
	add(rig, g, "Block", V3(0.94, 0.3, 0.94), CF(0, 7.12, 0), COL.RANGER)
	add(rig, g, "Block", V3(0.86, 0.1, 0.42), CF(0, 6.98, -0.62), COL.RANGER, SMOOTH, true)
	add(rig, g, "Block", V3(1.04, 0.36, 0.36), CF(0, 6.55, 0.06), COL.GUN, SMOOTH, true)
	add(rig, g, "Block", V3(0.7, 0.12, 0.05), CF(0, 6.62, -0.46), COL.BALA, SMOOTH, true)
	-- right arm down, hand on the radio
	limb(rig, g, V3(1.15, 5.85, 0), V3(1.2, 4.6, 0.05), 0.5, 0.5, COL.CLOTH)
	limb(rig, g, V3(1.2, 4.6, 0.05), V3(0.75, 4.9, -0.7), 0.45, 0.45, COL.CLOTH, SMOOTH, true)
	-- legs swing from the hip
	for _, sx in { -0.45, 0.45 } do
		add(rig, "haleLegs", "Block", V3(0.7, 1.7, 0.7), CF(sx, -0.85, 0), COL.CLOTH)
		add(rig, "haleLegs", "Block", V3(0.62, 1.6, 0.62), CF(sx, -2.45, 0), COL.CLOTH)
		add(rig, "haleLegs", "Block", V3(0.7, 0.4, 1.0), CF(sx, -3.4, -0.12), COL.BOOT, SMOOTH, true)
	end
	-- left arm raised to the ceiling rail, swings from the shoulder
	add(rig, "haleArm", "Block", V3(0.5, 1.2, 0.5), CF(0, 0.6, 0), COL.CLOTH)
	add(rig, "haleArm", "Block", V3(0.45, 1.1, 0.45), CF(0, 1.75, 0), COL.CLOTH, SMOOTH, true)
	add(rig, "haleArm", "Block", V3(0.42, 0.4, 0.42), CF(0, 2.45, 0), COL.SKIN, SMOOTH, true)
end

----------------------------------------------------------------------------------------------------
-- Fire on the right inner engine, fire glow at the right windows
----------------------------------------------------------------------------------------------------

local function buildFx(rig)
	local anchor = add(rig, "body", "Block", V3(0.2, 0.2, 0.2), CF(ENGINE_X[FIRE_ENGINE], 5.6, -11), COL.GUN, SMOOTH, true)
	anchor.Transparency = 1
	local att = Instance.new("Attachment")
	att.Parent = anchor

	local fire = Instance.new("ParticleEmitter")
	fire.Name = "Fire"
	fire.Texture = FIRE_TEX
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 140)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 120, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 30, 10)),
	})
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(0.4, 5), NumberSequenceKeypoint.new(1, 1.5) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.5, 0.9)
	fire.Rate = 30
	fire.Speed = NumberRange.new(4, 8)
	fire.SpreadAngle = Vector2.new(25, 25)
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.VelocityInheritance = 0.75
	fire.Rotation = NumberRange.new(0, 360)
	fire.RotSpeed = NumberRange.new(-90, 90)
	fire.EmissionDirection = Enum.NormalId.Back
	fire.Enabled = false
	fire.Parent = att

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = SMOKE_TEX
	smoke.Color = ColorSequence.new(Color3.fromRGB(38, 36, 34), Color3.fromRGB(70, 68, 66))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 14) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(2.5, 3.5)
	smoke.Rate = 14
	smoke.Speed = NumberRange.new(2, 4)
	smoke.SpreadAngle = Vector2.new(20, 20)
	smoke.LightInfluence = 0.5
	smoke.VelocityInheritance = 0.2
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.EmissionDirection = Enum.NormalId.Back
	smoke.Enabled = false
	smoke.Parent = att

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 130, 50)
	light.Brightness = 0
	light.Range = 28
	light.Shadows = false
	light.Parent = anchor

	local glowPart = add(rig, "body", "Block", V3(0.2, 0.2, 0.2), CF(7.4, 0.8, -12), COL.GUN, SMOOTH, true)
	glowPart.Transparency = 1
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 120, 40)
	glow.Brightness = 0
	glow.Range = 13
	glow.Shadows = false
	glow.Parent = glowPart

	rig.fx = { fire = fire, smoke = smoke, light = light, glow = glow, on = false }
end

function Kit.SetFire(rig, on)
	rig.fx.on = on
	rig.fx.fire.Enabled = on
	rig.fx.smoke.Enabled = on
	if not on then
		rig.fx.light.Brightness = 0
		rig.fx.glow.Brightness = 0
	end
end

----------------------------------------------------------------------------------------------------
-- World pieces: night filler beyond the terrain edge, searchlights
----------------------------------------------------------------------------------------------------

local function groundY(x, z, fallback)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(V3(x, 800, z), V3(0, -900, 0), params)
	return hit and hit.Position.Y or fallback
end
Kit.GroundY = groundY

local function worldPart(parent, shape, size, cf, color, mat)
	local p = shape == "Wedge" and newPart("WedgePart") or newPart("Part", SHAPES[shape])
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or SMOOTH
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function buildFiller(rig, folder)
	-- the terrain stops at about x -400..200, z -400..450; fill the void the exterior shots can see
	worldPart(folder, "Block", V3(3000, 6, 1500), CF(-100, 137, 1180), COL.SNOW_N)
	worldPart(folder, "Block", V3(1200, 6, 1600), CF(-995, 137, -370), COL.SNOW_N)
	worldPart(folder, "Block", V3(1200, 6, 1600), CF(795, 137, -370), COL.SNOW_N)
	-- dark ridge silhouettes far to the south
	local ridges = { { -700, 1500, 300, 260 }, { -250, 1650, 420, 330 }, { 250, 1550, 360, 280 }, { 650, 1450, 280, 220 } }
	for _, r in ridges do
		local x, z, half, h = r[1], r[2], r[3], r[4]
		local base = V3(x, 140, z)
		local shape = Instance.new("Folder")
		shape.Parent = folder
		for _, s in { -1, 1 } do
			local P = base + V3(0, 0, 0)
			local Y = Vector3.yAxis
			local Vu = V3(s, 0, 0)
			local Z = -Vu
			local X = Y:Cross(Z)
			local w = worldPart(shape, "Wedge", V3(500, h, half), CFrame.fromMatrix(P + Y * (h / 2) + Vu * (half / 2), X, Y, Z), COL.ROCK_N)
			w.Name = "Ridge"
		end
	end
end

local LIGHTS = { { -130, 446 }, { 20, 446 }, { -80, 380 }, { 10, 330 } }
local GUNS = { { -105, 440 }, { -5, 440 }, { -60, 360 }, { 30, 300 } }

local function buildLights(rig, folder)
	rig.lights = {}
	for i, l in LIGHTS do
		local pos = V3(l[1], groundY(l[1], l[2], 110) + 1.6, l[2])
		local anchor = worldPart(folder, "Block", V3(0.2, 0.2, 0.2), CF(pos), COL.GUN)
		anchor.Transparency = 1
		worldPart(folder, "Block", V3(2.4, 1.6, 2.4), CF(pos - V3(0, 1.2, 0)), COL.GUN, METAL)
		local lamp = worldPart(folder, "Ball", V3(1.8, 1.8, 1.8), CF(pos), Color3.fromRGB(225, 235, 255), NEON)
		lamp.Transparency = 0.1
		local a0 = Instance.new("Attachment")
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Position = V3(0, 400, 0)
		a1.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 2
		beam.Width1 = 34
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(Color3.fromRGB(205, 220, 255))
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.6, 0.82), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = anchor
		rig.lights[i] = { pos = pos, a1 = a1 }
	end
	rig.guns = {}
	for i, gpos in GUNS do
		rig.guns[i] = V3(gpos[1], groundY(gpos[1], gpos[2], 110) + 1.5, gpos[2])
	end
end

----------------------------------------------------------------------------------------------------
-- Flight plan
----------------------------------------------------------------------------------------------------

local CRUISE = 55
local CRAWL = CRUISE * 0.15 -- the plane barely moves during the cabin shots

local function prehitPos(plan, t)
	local d = CRUISE * math.min(t, T.B1) + CRAWL * clamp(t - T.B1, 0, T.HIT - T.B1)
	return V3(plan.X + 6 * sin(t * 0.35), plan.ALT + 1.5 * sin(t * 0.8), plan.zHit + plan.distTotal - d)
end

local function bez(p, u)
	local v = 1 - u
	return p[1] * (v * v * v) + p[2] * (3 * v * v * u) + p[3] * (3 * v * u * u) + p[4] * (u * u * u)
end

local function bezD(p, u)
	local v = 1 - u
	return (p[2] - p[1]) * (3 * v * v) + (p[3] - p[2]) * (6 * v * u) + (p[4] - p[3]) * (3 * u * u)
end

function Kit.Plan(env)
	local plan = {}
	plan.start = env.Start
	local crash = env.Crash or (env.Start.Position + V3(-15.5, 0, -2.5))
	plan.X = -60
	plan.ALT = 300
	plan.zHit = 470
	plan.distTotal = CRUISE * T.B1 + CRAWL * (T.HIT - T.B1)
	local p0 = prehitPos(plan, T.HIT)
	local gy = groundY(crash.X, crash.Z, env.Start.Position.Y - 0.5)
	local p3 = V3(crash.X, gy + 5, crash.Z)
	plan.bez = { p0, p0 + V3(0, -8, -70), p3 + V3(-30, 45, 75), p3 }
	plan.crash = p3
	-- above the snow rim at the south edge, which rises behind the spot and would hide the plane
	local rim = groundY(-50, 447, 233)
	for z = 440, 470, 5 do
		rim = math.max(rim, groundY(-50, z, rim))
	end
	plan.G1 = V3(-50, rim + 8, 447)
	local gx, gz = crash.X + 40, crash.Z - 55
	plan.G2 = V3(gx, groundY(gx, gz, gy) + 4.5, gz)
	return plan
end

function Kit.PlaneCF(plan, t)
	if t < T.HIT then
		local p = prehitPos(plan, t)
		return CFrame.lookAt(p, p + V3(0, 0, -1)) * ANG(rad(0.8) * sin(t * 1.1), 0, rad(3) * sin(t * 0.6))
	end
	local th = t - T.HIT
	local u = clamp(th / (T.IMPACT - T.HIT), 0, 1) ^ 1.6
	local p = bez(plan.bez, u)
	local d = bezD(plan.bez, u)
	if d.Magnitude < 1e-3 then
		d = V3(0, 0, -1)
	end
	local k = smooth(th / 2.0)
	local roll = -rad(32) * k - rad(6) * k * sin(t * 2.1)
	local jolt = rad(7) * math.exp(-th * 4) * sin(th * 30)
	return CFrame.lookAt(p, p + d.Unit) * ANG(jolt * 0.5, jolt, roll)
end

-- near bursts outside the cabin (time, plane-local position)
local NEAR = {
	{ 6.2, V3(17, 3, -6) },
	{ 7.3, V3(-19, 1, 4) },
	{ 8.8, V3(15, -3, -15) },
	{ 9.9, V3(-16, 4, -11) },
}
Kit.NEAR = NEAR
Kit.HIT_POS = V3(ENGINE_X[FIRE_ENGINE] + 3, 4, -13)

local function joltAt(t)
	local j = 0
	for _, n in NEAR do
		local d = t - n[1]
		if d >= 0 and d < 1.5 then
			j += math.exp(-d * 5)
		end
	end
	return j
end

local function shake(t, ampDeg, freq)
	local a = rad(ampDeg)
	return ANG(a * noise(t * freq, 0.3, 1.7), a * noise(t * freq, 4.1, 2.3), a * 0.6 * noise(t * freq, 8.7, 3.1))
end

local function setInterior(rig, on)
	for _, p in rig.ports do
		p.Transparency = on and 1 or 0.35
	end
	for _, l in rig.lamps do
		l.light.Enabled = on
		l.part.Color = on and COL.LAMP or COL.LAMP_OFF
	end
end

local function setHeadHidden(rig, hidden)
	local f = rig.figs[rig.seat]
	if not f then
		return
	end
	for _, p in f.head do
		p.Transparency = hidden and 1 or 0
	end
end

----------------------------------------------------------------------------------------------------
-- Pose: places everything for time t and returns camera CFrame, FOV and the screen look
----------------------------------------------------------------------------------------------------

function Kit.Pose(rig, t)
	local plan = rig.plan
	local G = rig.groupCF
	local planeCF = Kit.PlaneCF(plan, t)
	local th = t - T.HIT
	local jolt = joltAt(t)

	local interior = t >= T.B1 and t < T.D1
	if interior ~= rig.interior then
		rig.interior = interior
		setInterior(rig, interior)
	end
	local pov = t >= T.B2 and t < T.D1
	if pov ~= rig.pov then
		rig.pov = pov
		setHeadHidden(rig, pov)
	end

	-- propellers
	for i, e in rig.engines do
		local ang = t * 24
		if i == FIRE_ENGINE and th > 0 then
			ang = T.HIT * 24 + th * 3 -- windmilling
			if e.disc.Transparency < 1 then
				e.disc.Transparency = 1
			end
		end
		G["prop" .. i] = CF(e.hub) * ANG(0, 0, ang)
	end

	-- Captain HALE
	local base = rig.haleBase
	local body, armA, legA
	if th < 0 then
		body = base * ANG(rad(1.5) * sin(t * 1.3), 0, rad(2) * sin(t * 0.9))
		armA = rad(20)
		legA = 0
	else
		local a = smooth(th / 0.28)
		local b = smooth((th - 0.55) / 1.1)
		-- thrown back into the bulkhead, then slides down to sit against it
		body = base * HALE_HIP * CF(0, -3.05 * b, 1.75 * a - 0.65 * b) * ANG(rad(6) * a + rad(8) * b, 0, rad(10) * b) * HALE_HIP:Inverse()
		armA = rad(20) + rad(145) * smooth(th / 0.45)
		legA = rad(88) * b
	end
	G.hale = body
	G.haleArm = body * HALE_SHOULDER * ANG(0, 0, armA)
	G.haleLegs = body * HALE_HIP * ANG(legA, 0, 0)

	-- squad sway and lurch toward the front at the hit
	local lean = 0
	if th > 0 then
		lean = rad(16) * math.exp(-th * 2.2) + rad(4) * math.min(th * 3, 1)
	end
	for i, f in rig.figs do
		local wob = rad(1.4) * jolt * sin(t * 23 + i * 1.7) + rad(0.6) * sin(t * 1.1 + i)
		G[f.group] = f.seat * ANG(0, 0, -f.side * lean + wob)
	end

	-- move the plane
	if not rig.gone then
		local cfs = rig.cfs
		local parts, locals, groups = rig.parts, rig.locals, rig.groups
		for i = 1, #parts do
			cfs[i] = planeCF * G[groups[i]] * locals[i]
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	-- lights
	rig.beacon.Transparency = ((t * 1.1) % 1 < 0.12) and 0 or 0.85
	local p = planeCF.Position
	for i, l in rig.lights do
		local aim = p + V3(70 * sin(t * 0.6 + i * 1.9), 30 * sin(t * 0.9 + i), 90 * sin(t * 0.45 + i * 2.6))
		l.a1.Position = (aim - l.pos).Unit * 420
	end
	if th > 0 then
		for k, l in rig.lamps do
			local f = noise(t * 9, k * 3.1, 0.5)
			l.light.Brightness = f < -0.35 and 0.15 or (1.6 + f * 1.4)
		end
		if rig.fx.on then
			rig.fx.light.Brightness = 3.5 + 2 * noise(t * 7, 1.3, 0)
			rig.fx.glow.Brightness = interior and (1.8 + 1.2 * noise(t * 8, 2.2, 0)) or 0
		end
	end

	-- camera
	local look = { fade = 0, flash = 0, blur = 0 }
	local cam, fov
	if t < T.A2 then
		cam = CFrame.lookAt(plan.G1, p + V3(0, -4, 0)) * shake(t, 0.25, 1.3)
		fov = lerp(55, 44, t / T.A2)
	elseif t < T.B1 then
		local k = t - T.A2
		cam = CFrame.lookAt(p + V3(-50 + k * 3, 24 - k * 1.5, 105 - k * 4), p + V3(8, -30, -150)) * shake(t, 0.3, 1.1)
		fov = 62
	elseif t < T.B2 then
		local k = t - T.B1
		local camL = CFrame.lookAt(V3(0.5, 1.5, 12 - k * 0.9), V3(-0.6, -0.6, -22))
		cam = planeCF * camL * shake(t, 0.35 + jolt * 3, 9)
		fov = 72
	elseif t < T.D1 then
		local f = rig.figs[rig.seat]
		local eye = G[f.group] * V3(0, 2.7, -0.25)
		local target = G.hale * V3(0, 6.1, 0)
		local camL = CFrame.lookAt(eye, target)
		local amp = 0.4 + jolt * 3
		local roll = 0
		if th > 0 then
			amp += 7 * math.exp(-th * 1.6) + 1.2
			roll = -rad(10) * math.min(th * 2, 1)
		end
		cam = planeCF * camL * ANG(0, 0, roll) * shake(t, amp, 14)
		fov = th > 0 and 76 or 70
	elseif t < T.D2 then
		local k = t - T.D1
		local fwd = planeCF.LookVector
		local flat = V3(fwd.X, 0, fwd.Z)
		flat = flat.Magnitude > 1e-3 and flat.Unit or V3(0, 0, -1)
		local right = flat:Cross(Vector3.yAxis)
		local camPos = p + right * 34 + V3(0, 14 - k * 2, 0) - flat * (58 - k * 4)
		cam = CFrame.lookAt(camPos, planeCF * V3(14, 3, -16)) * shake(t, 0.8, 6)
		fov = 58
	elseif t < T.IMPACT then
		cam = CFrame.lookAt(plan.G2, p) * shake(t, 0.4 + 2.5 * clamp(t - 17.2, 0, 1), 10)
		fov = lerp(50, 60, (t - T.D2) / (T.IMPACT - T.D2))
	elseif t < T.WAKE then
		cam = rig.lastCam or CFrame.lookAt(plan.G2, plan.crash)
		fov = 60
		look.fade = 1
	else
		local w = rig.wake or Kit.WakeFrom(plan.start, nil)
		local r = smooth((t - T.RISE) / (T.END - T.RISE))
		local lie = w.lie * ANG(rad(1.2) * sin(t * 1.7), 0, rad(18) * (1 - r))
		cam = lie:Lerp(w.head, r)
		fov = 70
		local k = (t - T.WAKE) / 2.4
		look.fade = 1 - smooth(k)
		for _, b in { 21.25, 21.95 } do
			local d = t - b
			if d > 0 and d < 0.3 then
				look.fade = math.max(look.fade, sin(d / 0.3 * math.pi) * 0.9)
			end
		end
		look.blur = 22 * (1 - smooth((t - T.WAKE) / 4.0))
	end
	if t < T.IMPACT then
		rig.lastCam = cam
	end

	if t < 0.9 then
		look.fade = 1 - t / 0.9
	end
	if th >= 0 and th < 0.6 then
		look.flash = 1 - th / 0.6
	end
	look.flash = math.max(look.flash, jolt * 0.25)
	return cam, fov, look
end

-- Lying in the snow next to the character, then the head-height view it hands back
function Kit.WakeFrom(startCF, hrp)
	local pos = hrp and hrp.Position or (startCF.Position + V3(0, 2.5, 0))
	local lv = hrp and hrp.CFrame.LookVector or startCF.LookVector
	local flat = V3(lv.X, 0, lv.Z)
	flat = flat.Magnitude > 1e-3 and flat.Unit or V3(0, 0, -1)
	local gy = groundY(pos.X, pos.Z, pos.Y - 3)
	if gy > pos.Y + 1 then
		gy = pos.Y - 3
	end
	local low = V3(pos.X, gy + 0.7, pos.Z) - flat * 1.2
	local lie = CFrame.lookAt(low, low + flat * 0.5 + V3(0, 1, 0))
	local eye = pos + V3(0, 1.5, 0)
	return { lie = lie, head = CFrame.lookAt(eye, eye + flat) }
end

----------------------------------------------------------------------------------------------------
-- Flak, tracers
----------------------------------------------------------------------------------------------------

function Kit.Flak(rig, pos, scale, static)
	scale = scale or 1
	local folder = rig.fxFolder
	local core = worldPart(folder, "Ball", V3(4, 4, 4) * scale, CF(pos), Color3.fromRGB(255, 214, 150), NEON)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Brightness = 7
	light.Range = math.min(60, 45 * scale)
	light.Shadows = false
	light.Parent = core
	local puff = worldPart(folder, "Ball", V3(3, 3, 3) * scale, CF(pos + V3(0, 0.5, 0)), Color3.fromRGB(34, 32, 30))
	puff.Transparency = 0.25
	if static then
		core.Size = V3(7, 7, 7) * scale
		puff.Size = V3(10, 10, 10) * scale
		puff.CFrame = CF(pos + V3(1.5, 1, 1.5) * scale)
		return
	end
	local att = Instance.new("Attachment")
	att.Parent = puff
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEX
	smoke.Color = ColorSequence.new(Color3.fromRGB(30, 29, 27))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4 * scale), NumberSequenceKeypoint.new(1, 13 * scale) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.8, 2.8)
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Drag = 1.5
	smoke.LightInfluence = 0.4
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Rate = 0
	smoke.Parent = att
	smoke:Emit(5)
	TweenService:Create(core, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V3(10, 10, 10) * scale, Transparency = 1 }):Play()
	TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	TweenService:Create(puff, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V3(11, 11, 11) * scale, Transparency = 1 }):Play()
	Debris:AddItem(core, 0.6)
	Debris:AddItem(puff, 3.2)
end

function Kit.Tracers(rig, from, to, count)
	for k = 1, count do
		task.delay((k - 1) * 0.07, function()
			if not rig.fxFolder.Parent then
				return
			end
			local spread = V3((k * 13 % 7) - 3, (k * 5 % 5) - 2, (k * 11 % 9) - 4) * 3
			local a = from
			local b = to + spread
			local tr = worldPart(rig.fxFolder, "Block", V3(0.3, 0.3, 7), CFrame.lookAt(a, b), Color3.fromRGB(255, 196, 96), NEON)
			local dur = 1.3
			TweenService:Create(tr, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(b, b + (b - a)) }):Play()
			Debris:AddItem(tr, dur + 0.05)
		end)
	end
end

function Kit.Build(parent, env)
	local rig = {
		parts = {},
		locals = {},
		groups = {},
		cfs = {},
		groupCF = { body = CFrame.identity, hale = CFrame.identity, haleArm = CFrame.identity, haleLegs = CFrame.identity },
	}
	rig.plan = Kit.Plan(env)
	rig.seat = ((math.max(1, math.floor(tonumber(env.Seat) or 1)) - 1) % #SEATS) + 1

	local model = Instance.new("Folder")
	model.Name = "Plane"
	rig.model = model
	buildExterior(rig)
	buildInterior(rig)
	buildSquad(rig)
	buildHale(rig)
	buildFx(rig)

	local world = Instance.new("Folder")
	world.Name = "World"
	buildFiller(rig, world)
	buildLights(rig, world)
	local fx = Instance.new("Folder")
	fx.Name = "Fx"
	rig.fxFolder = fx

	rig.interior = nil
	rig.pov = nil
	model.Parent = parent
	world.Parent = parent
	fx.Parent = parent
	Kit.Pose(rig, 0)
	return rig
end

if script:IsA("ModuleScript") then
	return Kit
end

----------------------------------------------------------------------------------------------------
-- Runtime
----------------------------------------------------------------------------------------------------

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CrashIntro")

local GRADE = Color3.fromRGB(222, 232, 255)
local playing = false

local function soundTemplate(path)
	local node = ReplicatedStorage:FindFirstChild("Assets")
	node = node and node:FindFirstChild("Sounds")
	for name in string.gmatch(path, "[^%.]+") do
		if not node then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	if node and node:IsA("Sound") then
		return node
	end
	return nil
end

local function crashPoint(startCF)
	local map = workspace:FindFirstChild("Map")
	local dressing = map and map:FindFirstChild("WarDressing")
	local bird = dressing and dressing:FindFirstChild("DownedBird")
	if bird and bird:IsA("Model") then
		return bird:GetPivot().Position
	end
	return startCF.Position + V3(-15.5, 0, -2.5)
end

local function runIntro(data, cleanups)
	local cam = workspace.CurrentCamera
	local startCF = (typeof(data) == "table" and typeof(data.Start) == "CFrame") and data.Start or CFrame.new(-4, 102.5, 292)
	local seat = (typeof(data) == "table" and tonumber(data.Seat)) or 1
	local canSkip = player:GetAttribute("SeenIntro") == true

	player:SetAttribute("InCutscene", true)
	table.insert(cleanups, function()
		player:SetAttribute("InCutscene", false)
	end)

	local bpWas = true
	pcall(function()
		bpWas = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
	end)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	table.insert(cleanups, function()
		if bpWas then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
			end)
		end
	end)

	-- hide every character locally while the cutscene runs
	local hidden = {}
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if char then
			for _, d in char:GetDescendants() do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = 1
					table.insert(hidden, d)
				end
			end
		end
	end
	table.insert(cleanups, function()
		for _, d in hidden do
			if d.Parent then
				d.LocalTransparencyModifier = 0
			end
		end
	end)

	-- camera; the handback is a cleanup so it also runs on error or skip
	local oldFov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	local root = Instance.new("Folder")
	root.Name = "CrashIntro"
	root.Parent = cam
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "CrashIntroGrade"
	cc.TintColor = Color3.new(0, 0, 0)
	cc.Contrast = 0.12
	cc.Saturation = -0.15
	cc.Parent = cam
	local blur = Instance.new("BlurEffect")
	blur.Name = "CrashIntroBlur"
	blur.Size = 0
	blur.Parent = cam
	table.insert(cleanups, function()
		root:Destroy()
		cc:Destroy()
		blur:Destroy()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		cam.FieldOfView = oldFov
		if hrp then
			local w = Kit.WakeFrom(startCF, hrp)
			cam.CFrame = w.head
		end
		cam.CameraType = Enum.CameraType.Custom
		if hum then
			cam.CameraSubject = hum
		end
	end)

	-- sounds: one folder, a mix group that gets muffled after the impact
	local sfxFolder = Instance.new("Folder")
	sfxFolder.Name = "Sfx"
	sfxFolder.Parent = root
	local mix = Instance.new("SoundGroup")
	mix.Name = "CrashIntroMix"
	mix.Volume = 1
	mix.Parent = sfxFolder
	local eq = Instance.new("EqualizerSoundEffect")
	eq.HighGain = -40
	eq.MidGain = -18
	eq.LowGain = 0
	eq.Enabled = false
	eq.Parent = mix

	local function sfx(path, vol, opts)
		local tpl = soundTemplate(path)
		if not tpl then
			return nil
		end
		local s = tpl:Clone()
		s.Volume = vol
		s.Looped = opts ~= nil and opts.loop == true
		s.PlaybackSpeed = (opts and opts.speed) or 1
		if not (opts and opts.dry) then
			s.SoundGroup = mix
		end
		s.Parent = sfxFolder
		s:Play()
		if not s.Looped then
			local len = tpl.TimeLength > 0 and tpl.TimeLength or 8
			Debris:AddItem(s, len / s.PlaybackSpeed + 0.5)
		end
		return s
	end
	local function fadeOut(s, dur)
		if s and s.Parent then
			TweenService:Create(s, TweenInfo.new(dur), { Volume = 0 }):Play()
			Debris:AddItem(s, dur + 0.1)
		end
	end
	local function fadeTo(s, vol, dur)
		if s and s.Parent then
			TweenService:Create(s, TweenInfo.new(dur), { Volume = vol }):Play()
		end
	end

	local rig = Kit.Build(root, { Start = startCF, Seat = seat, Crash = crashPoint(startCF) })
	local plan = rig.plan

	local loops = {}
	local function flakAt(tb, pos, scale, loud)
		Kit.Flak(rig, pos, scale)
		local d = (cam.CFrame.Position - pos).Magnitude
		sfx("Intro.Flak", loud or clamp(90 / math.max(d, 1), 0.08, 0.8), { speed = 0.9 + (tb * 7 % 3) * 0.08 })
	end

	-- cue list
	local cues = {}
	local function cue(time, fn)
		table.insert(cues, { time, fn })
	end
	cue(0, function()
		loops.engine = sfx("Intro.EngineDrone", 0.25, { loop = true })
		loops.siren = sfx("Beacon.Alarm", 0.35)
		loops.wind = sfx("Night.Wind", 0.2, { loop = true })
	end)
	local rnd = Random.new(7)
	for i = 0, 15 do
		local tb = 0.25 + i * 0.31 + rnd:NextNumber(0, 0.1)
		local off = V3(rnd:NextNumber(-70, 70), rnd:NextNumber(-30, 35), rnd:NextNumber(-170, 40))
		local sc = rnd:NextNumber(0.8, 1.4)
		cue(tb, function()
			flakAt(tb, Kit.PlaneCF(plan, tb).Position + off, sc)
		end)
	end
	for _, tb in { 0.15, 0.9, 1.7, 2.5, 3.3, 4.1, 4.8, 13.8, 14.9, 16.2 } do
		cue(tb, function()
			local gun = rig.guns[(math.floor(tb * 10) % #rig.guns) + 1]
			local aim = Kit.PlaneCF(plan, tb + 1.0).Position + V3(rnd:NextNumber(-40, 40), rnd:NextNumber(-20, 20), rnd:NextNumber(-40, 40))
			Kit.Tracers(rig, gun, aim, 6)
		end)
	end
	for _, tb in { 1.2, 3.9 } do
		cue(tb, function()
			sfx("Intro.Artillery", 0.4)
		end)
	end
	cue(T.B1, function()
		fadeTo(loops.engine, 0.6, 0.3)
		fadeOut(loops.siren, 0.4)
		fadeTo(loops.wind, 0.08, 0.3)
	end)
	for _, n in NEAR do
		cue(n[1], function()
			flakAt(n[1], Kit.PlaneCF(plan, n[1]) * n[2], 1.2, 0.9)
			sfx("Intro.MetalCreak", 0.6, { speed = 1 + (n[1] % 1) * 0.2 })
		end)
	end
	cue(T.HIT, function()
		flakAt(T.HIT, Kit.PlaneCF(plan, T.HIT) * Kit.HIT_POS, 1.8, 1)
		sfx("Intro.Artillery", 1)
		sfx("World.GlassBreak", 0.5)
		Kit.SetFire(rig, true)
		loops.roar = sfx("Intro.Roar", 0, { loop = true })
		fadeTo(loops.roar, 0.7, 2)
	end)
	cue(T.HIT + 0.15, function()
		loops.bell = sfx("Intro.AlarmBell", 0.45, { loop = true })
	end)
	cue(T.HIT + 0.4, function()
		sfx("Intro.MetalCreak", 0.8, { speed = 0.85 })
	end)
	cue(T.D1, function()
		fadeTo(loops.engine, 0.3, 0.3)
		fadeTo(loops.bell, 0.2, 0.3)
		fadeTo(loops.wind, 0.3, 0.3)
	end)
	for i = 0, 7 do
		local tb = 13.6 + i * 0.5
		local off = V3(rnd:NextNumber(-60, 60), rnd:NextNumber(-25, 30), rnd:NextNumber(-120, 40))
		cue(tb, function()
			flakAt(tb, Kit.PlaneCF(plan, tb).Position + off, 1)
		end)
	end
	cue(14.5, function()
		sfx("Intro.MetalCreak", 0.5, { speed = 0.8 })
	end)
	cue(T.IMPACT, function()
		for _, s in loops do
			if s and s.Parent then
				s:Destroy()
			end
		end
		table.clear(loops)
		sfx("Beacon.Collapse", 1)
		sfx("World.StoneChunk", 0.8)
		sfx("Intro.Artillery", 1, { speed = 0.8 })
		sfx("Intro.Flak", 1, { speed = 0.6 })
		rig.gone = true
		rig.model:Destroy()
		rig.fxFolder:ClearAllChildren()
	end)
	cue(T.IMPACT + 0.35, function()
		eq.Enabled = true
		loops.tinnitus = sfx("Intro.Tinnitus", 0.55, { dry = true })
		fadeOut(loops.tinnitus, T.END - T.IMPACT)
	end)
	cue(T.WAKE - 0.4, function()
		local char = player.Character
		rig.wake = Kit.WakeFrom(startCF, char and char:FindFirstChild("HumanoidRootPart"))
		loops.wind2 = sfx("Night.Wind", 0.35, { loop = true })
	end)
	cue(T.WAKE + 0.6, function()
		sfx("Player.Heartbeat", 0.5)
	end)
	cue(T.WAKE + 1.2, function()
		TweenService:Create(eq, TweenInfo.new(T.END - T.WAKE - 1.2), { HighGain = -4, MidGain = -2 }):Play()
	end)
	table.sort(cues, function(a, b)
		return a[1] < b[1]
	end)

	-- skip (only for players who have already seen it)
	local skipAt = nil
	local t0 = os.clock()
	if canSkip then
		local conn = UserInputService.InputBegan:Connect(function(input)
			local kc = input.KeyCode
			if kc == Enum.KeyCode.Space or kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.ButtonA or kc == Enum.KeyCode.ButtonB or input.UserInputType == Enum.UserInputType.Touch then
				if not skipAt then
					skipAt = os.clock() - t0
				end
			end
		end)
		table.insert(cleanups, function()
			conn:Disconnect()
		end)
	end

	local done = false
	local failed = nil
	local ci = 1
	local rconn = RunService.RenderStepped:Connect(function()
		if done then
			return
		end
		local ok, err = pcall(function()
			local t = os.clock() - t0
			while cues[ci] and cues[ci][1] <= t do
				local fn = cues[ci][2]
				ci += 1
				local okc, errc = pcall(fn)
				if not okc then
					warn("[CrashIntro] cue failed: " .. tostring(errc))
				end
			end
			local camCF, fov, look = Kit.Pose(rig, math.min(t, T.END))
			cam.CFrame = camCF
			cam.FieldOfView = fov
			local fade = look.fade
			if skipAt then
				fade = math.max(fade, clamp((t - skipAt) / 0.35, 0, 1))
				if t - skipAt >= 0.4 then
					done = true
				end
			end
			cc.TintColor = Color3.new(0, 0, 0):Lerp(GRADE, 1 - fade)
			cc.Brightness = look.flash * 0.6
			blur.Size = look.blur
			if t >= T.END then
				done = true
			end
		end)
		if not ok then
			failed = err
			done = true
		end
	end)
	table.insert(cleanups, function()
		rconn:Disconnect()
	end)

	while not done and os.clock() - t0 < 28 do
		task.wait()
	end
	if failed then
		error(failed)
	end
end

remote.OnClientEvent:Connect(function(data)
	if playing then
		return
	end
	playing = true
	task.spawn(function()
		local cleanups = {}
		local ok, err = xpcall(runIntro, debug.traceback, data, cleanups)
		if not ok then
			warn("[CrashIntro] " .. tostring(err))
		end
		for i = #cleanups, 1, -1 do
			local okc, errc = pcall(cleanups[i])
			if not okc then
				warn("[CrashIntro] cleanup: " .. tostring(errc))
			end
		end
		pcall(function()
			remote:FireServer("Done")
		end)
		playing = false
	end)
end)
