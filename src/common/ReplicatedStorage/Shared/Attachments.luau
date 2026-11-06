--!nonstrict
-- Shared.Attachments (6 Nov 2026): scopes and gun attachments for every place (lobby, campaign/FRONTLINE, zombies).
-- One module owns the data (what each attachment does, which gun takes which, the weapon level that unlocks it,
-- where it sits on each gun) and the two jobs every place needs:
--   Attachments.Config(gunName, picks)       -> the gun's GameConfig table with the attachments' numbers applied
--                                               (a cached copy; never edit it). picks = {Optic = id, Muzzle = id, ...}
--   Attachments.Apply(model, gunName, picks, opts) -> fits the attachment models onto a gun model
--                                               opts.View = "VM" (Assets.ViewModels) | "World" (Assets.WorldGuns)
--                                               opts.Weld = true welds the new parts to the gun's Root (world guns)
-- and the glue around them:
--   Attachments.ForPlayer(player, gunName)   -> picks for that gun (saved Attach attribute + run-only RunAttach)
--   Attachments.ConfigFor(player, gunName)   -> Config(gunName, ForPlayer(player, gunName))
--   Attachments.Dress(model, gunName, player, view, weld) -> Apply + the player's camo (camo goes on after, so it
--                                               covers the attachments' Body parts too)
--   Attachments.Allowed(gunName, slot)       -> ordered list of ids that gun takes in that slot
--   Attachments.UnlockLevel(gunName, id)     -> the weapon level that unlocks it (nil if the gun never takes it)
--   Attachments.Lines(id)                    -> {pros = {...}, cons = {...}} short upper-case lines for the menu
--
-- Models: ReplicatedStorage.Assets.Attachments.<Model> (built by tools/attachments/install_attachments.luau from
-- Toolbox meshes, retextured). Each model's PrimaryPart "Mount" is the point that sits on the gun; optics carry a
-- "Sight" attachment (the aim line). Mount points per gun are in GUNS below, in each gun model's Root space.
-- Data: the player attribute "Attach" (JSON {gun = {slot = id}}), published by Profile in every place and set by
-- StoreServer "Attach" in the lobby. "RunAttach" (same shape, server-set) adds run-only attachments in zombies.
-- Obtainment: weapon levels (per gun, UNLOCKS below), plus the zombies Gunsmith (run-only, RunAttach).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = script.Parent
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local A = {}

A.Slots = { "Optic", "Muzzle", "Under", "Laser", "Mag" }
A.SlotNames = { Optic = "OPTIC", Muzzle = "MUZZLE", Under = "UNDERBARREL", Laser = "LASER", Mag = "MAGAZINE" }

-- Items ------------------------------------------------------------------------------------------------------------
-- Mods: multipliers unless the key says otherwise.
--   AimFov (absolute aimed FOV), AimTime, AimSensitivity, Pitch / Yaw (recoil), HipSpread (hip and
--   moving spread), MagMult / MagAdd, Reload (all reload times), Falloff (FalloffStart/End), Pellet (pellet cone),
--   Flash (muzzle flash size and light), Shake, Volume (shot sound, also what others hear), Noise (stat bar, absolute),
--   Scope = {...} replaces the gun's scope view; NoScope = true removes it (a red dot on a sniper).
A.Items = {
	Kobra = { Slot = "Optic", Name = "KOBRA REFLEX", Model = "Kobra", Weight = 0.2, Mods = { AimFov = 52, AimTime = 0.97 } },
	RedDot = { Slot = "Optic", Name = "RED DOT", Model = "RedDot", Weight = 0.25, Mods = { AimFov = 48, AimTime = 1.03 } },
	Holo = { Slot = "Optic", Name = "HOLOGRAPHIC", Model = "Holo", Weight = 0.3, Mods = { AimFov = 45, AimTime = 1.06 } },
	ACOG = { Slot = "Optic", Name = "ACOG 3X", Model = "ACOG",
		Weight = 0.5, Mods = { AimFov = 24, AimTime = 1.18, AimSensitivity = 0.7 } },
	MiniDot = { Slot = "Optic", Name = "MINI DOT", Model = "MiniDot", Weight = 0.1, Mods = { AimFov = 56, AimTime = 1.03 } },
	Recon8x = { Slot = "Optic", Name = "RECON 8X", Model = "Sniper8x",
		Weight = 0.7, Mods = { AimTime = 1.12, Scope = { At = 0.92, Fov = 8, Sensitivity = 0.14, Sway = 0.5, HoldBreath = 4, BreathRecover = 2.8 } } },

	Suppressor = { Slot = "Muzzle", Name = "SUPPRESSOR", Model = { Rifle = "SuppRifle", Pistol = "SuppPistol", Sniper = "SuppSniper" },
		Weight = 0.45, Mods = { Volume = 0.4, Flash = 0.15, Falloff = 0.85, AimTime = 1.04, Noise = 0.25 } },
	FlashHider = { Slot = "Muzzle", Name = "FLASH HIDER", Model = "FlashHider", Weight = 0.15, Mods = { Flash = 0.35, Pitch = 0.9, Shake = 0.85 } },
	Choke = { Slot = "Muzzle", Name = "CHOKE", Model = "Choke", Weight = 0.15, Mods = { Pellet = 0.72, Falloff = 1.15 } },

	VGrip = { Slot = "Under", Name = "VERTICAL GRIP", Model = "VGrip", Weight = 0.2, Mods = { Pitch = 0.82, Yaw = 0.85, AimTime = 1.05 } },

	Laser = { Slot = "Laser", Name = "TACTICAL LASER", Model = "Laser", Weight = 0.15, Mods = { HipSpread = 0.7, AimTime = 0.92 } },

	ExtMag = { Slot = "Mag", Name = "EXTENDED MAG", Weight = 0.4, Mods = { MagMult = 1.5, Reload = 1.12, AimTime = 1.03 } },
	FastMag = { Slot = "Mag", Name = "FAST MAG", Weight = 0.05, Mods = { Reload = 0.78 } },
}
for id, it in A.Items do
	it.Id = id
end

-- Weight ---------------------------------------------------------------------------------------------------------------
-- Every gun has a carry weight in kg; attachments add theirs (Items[id].Weight). The total sets how fast you move
-- with that gun out: walking and aiming at MoveSpeed, sprinting at SprintMult (heavier guns lose more when running).
-- Config() writes Weight, MoveSpeed and SprintMult onto every gun table, so the GameConfig MoveSpeed numbers are
-- replaced by this one scale in every place.
A.GunWeight = { Pistol = 0.9, HandCannon = 1.4, MP5 = 2.6, M4 = 3.1, AK = 3.6, Shotgun = 3.6, SR25 = 4.9, Sniper = 6.2, M60 = 10.5 }
local LIGHT = 1.0 -- kg carried at full speed
local PER_KG = 0.024 -- speed lost per kg over LIGHT
local MIN_SPEED = 0.7

function A.Mobility(weight)
	local move = math.clamp(1 - PER_KG * (weight - LIGHT), MIN_SPEED, 1)
	return move, move ^ 1.5
end

-- The weight class for the menu: "LIGHT" | "MEDIUM" | "HEAVY".
function A.WeightClass(weight)
	return if weight < 2 then "LIGHT" elseif weight < 4.5 then "MEDIUM" else "HEAVY"
end

-- Short lines for the menu (pros first). Written by hand so they stay readable.
local LINES = {
	Kobra = { { "CLEAR VIEW", "FASTER AIM" }, {} },
	RedDot = { { "PRECISE DOT", "SLIGHT ZOOM" }, { "SLOWER AIM" } },
	Holo = { { "RING AND DOT", "MORE ZOOM" }, { "SLOWER AIM" } },
	ACOG = { { "3X ZOOM" }, { "MUCH SLOWER AIM", "HEAVIER" } },
	MiniDot = { { "PISTOL DOT", "CLEAR VIEW" }, { "SLOWER AIM" } },
	Recon8x = { { "8X ZOOM" }, { "SLOWER AIM", "HEAVIER" } },
	Suppressor = { { "QUIET SHOTS", "HIDDEN FLASH" }, { "LESS RANGE", "HEAVIER" } },
	FlashHider = { { "LESS FLASH", "LESS KICK" }, {} },
	Choke = { { "TIGHTER SPREAD", "MORE RANGE" }, {} },
	VGrip = { { "LESS RECOIL" }, { "SLOWER AIM" } },
	Laser = { { "TIGHTER HIP FIRE", "FASTER AIM" }, {} },
	ExtMag = { { "BIGGER MAGAZINE" }, { "SLOWER RELOAD", "HEAVIER" } },
	FastMag = { { "FASTER RELOAD" }, {} },
}
function A.Lines(id)
	local l = LINES[id]
	return if l then { pros = l[1], cons = l[2] } else { pros = {}, cons = {} }
end

-- Guns ---------------------------------------------------------------------------------------------------------------
-- Class picks the suppressor model and the unlock ladder. Mounts: per view, the rail point in the gun's Root space
-- (Optic on top, Under below the handguard, Laser on the right rail); Muzzle comes from the model's own "Muzzle"
-- attachment. VmScale: attachments are built at world-gun scale, viewmodels are drawn smaller. Hide: parts (by name)
-- an optic replaces, per view (iron sights, the M4's own sight, the sniper's own scope).
-- MagAdd overrides MagMult for guns where half again is too much or too little.

local V = Vector3.new
local GUNS = {
	AK = {
		Class = "Rifle",
		VmScale = 0.5,
		Mounts = {
			World = { Optic = V(0, 0.31, -0.2), Under = V(0, 0.07, -1.0), Laser = V(0.07, 0.2, -1.25) },
			VM = { Optic = V(0, 0.19, -0.12), Under = V(0, 0.07, -0.49), Laser = V(0.04, 0.13, -0.64) },
		},
		Hide = { Optic = { World = { "RearSight" }, VM = { "Rear Sight" } } },
	},
	M4 = {
		Class = "Rifle",
		VmScale = 0.5,
		Mounts = {
			-- no Under: the M4 already carries a foregrip
			World = { Optic = V(0, 0.39, -0.3), Laser = V(0.1, 0.3, -1.25) },
			VM = { Optic = V(0, 0.23, -0.15), Laser = V(0.05, 0.18, -0.64) },
		},
		Hide = { Optic = { World = { "Optic", "OpticLens", "RearSight" }, VM = { "Optic", "OpticLens", "RearSight" } } },
	},
	MP5 = {
		Class = "Rifle",
		SuppModel = "SuppPistol",
		VmScale = 0.5,
		Mounts = {
			World = { Optic = V(0, 0.53, -0.3), Under = V(0, 0.22, -0.95), Laser = V(0.09, 0.34, -1.15) },
			VM = { Optic = V(0, 0.3, -0.18), Under = V(0, 0.14, -0.47), Laser = V(0.04, 0.2, -0.6) },
		},
		Hide = {},
	},
	M60 = {
		Class = "Rifle",
		VmScale = 0.5,
		MagAdd = 30,
		Mounts = {
			World = { Optic = V(0, 0.56, -0.08), Under = V(0, 0.16, -1.08), Laser = V(0.1, 0.3, -1.2) },
			VM = { Optic = V(0, 0.31, -0.05), Under = V(0, 0.11, -0.53), Laser = V(0.05, 0.18, -0.6) },
		},
		Hide = { Optic = { World = { "RearSight", "RearAperture" }, VM = { "RearSight", "RearAperture" } } },
	},
	SR25 = {
		Class = "Sniper",
		VmScale = 0.5,
		MagAdd = 5,
		Mounts = {
			World = { Optic = V(0, 0.39, -0.5), Under = V(0, 0.18, -0.99), Laser = V(0.13, 0.25, -1.3) },
			VM = { Optic = V(0, 0.22, -0.25), Under = V(0, 0.12, -0.49), Laser = V(0.06, 0.16, -0.68) },
		},
		Hide = {
			Optic = {
				World = { "Scope", "ScopeEye", "ScopeCapRear", "ScopeCapFront", "ScopeLens", "RearSight" },
				VM = { "Scope", "ScopeEye", "ScopeCapRear", "ScopeCapFront", "ScopeLens", "RearSight" },
			},
		},
	},
	Sniper = {
		Class = "Sniper",
		VmScale = 0.5,
		MagAdd = 3,
		Mounts = {
			World = { Optic = V(0, 0.17, -0.9), Laser = V(0.09, 0.04, -1.4) },
			VM = { Optic = V(0, 0.11, -0.46), Laser = V(0.045, 0.03, -0.72) },
		},
		Hide = {
			Optic = {
				World = { "ScopeGlass", "ScopeTurret", "Scope", "ScopeMount" },
				VM = { "ScopeGlass", "Dist. Regulator", "Scope body", "Scope Support" },
			},
		},
	},
	Shotgun = {
		Class = "Shotgun",
		VmScale = 0.5,
		MagAdd = 2,
		MuzzleBack = { World = 0.15 }, -- the world model's Muzzle point sits ahead of its barrel
		Mounts = {
			World = { Optic = V(0, 0.24, -0.25), Laser = V(0.06, 0.1, -0.3) },
			VM = { Optic = V(0, 0.15, -0.12), Laser = V(0.03, 0.07, -0.15) },
		},
		Hide = {},
	},
	-- Pistols: the laser hangs under the frame (X = 0 flips it). In first person it takes the place of the built-in
	-- torch housing (a light-and-laser unit); the torch beam still comes from the gun's TorchPoint.
	Pistol = {
		Class = "Pistol",
		VmScale = 0.5,
		Mounts = {
			World = { Optic = V(0, 0.37, -0.12), Laser = V(0, 0.14, -0.55) },
			VM = { Optic = V(0, 0.22, -0.05), Laser = V(0, 0.08, -0.32) },
		},
		Hide = { Laser = { VM = { "TorchBody", "TorchMount", "TorchLens" } } },
	},
	HandCannon = {
		Class = "Pistol",
		VmScale = 0.5,
		NoMuzzle = true,
		Mounts = {
			World = { Optic = V(0, 0.51, -0.15), Laser = V(0, 0.24, -0.85) },
			VM = { Optic = V(0, 0.26, -0.07), Laser = V(0, 0.12, -0.42) },
		},
		Hide = { Laser = { VM = { "TorchBody", "TorchMount", "TorchLens" } } },
	},
}
A.Guns = GUNS

-- What each class takes, slot by slot, and the weapon level that unlocks it (weapon levels 1-15, Shared.Progression;
-- camos are at 5, 10 and 15, so attachments fill the levels between).
local LADDERS = {
	Rifle = {
		Optic = { Kobra = 2, RedDot = 6, Holo = 11, ACOG = 13 },
		Muzzle = { Suppressor = 4, FlashHider = 9 },
		Under = { VGrip = 3 },
		Laser = { Laser = 8 },
		Mag = { ExtMag = 7, FastMag = 12 },
	},
	Sniper = {
		Optic = { RedDot = 3, ACOG = 6, Recon8x = 11 },
		Muzzle = { FlashHider = 2, Suppressor = 7 },
		Under = { VGrip = 9 },
		Laser = { Laser = 4 },
		Mag = { ExtMag = 8, FastMag = 12 },
	},
	Shotgun = {
		Optic = { Kobra = 2, RedDot = 8, Holo = 11 },
		Muzzle = { Choke = 4 },
		Under = { VGrip = 6 },
		Laser = { Laser = 3 },
		Mag = { ExtMag = 7, FastMag = 12 },
	},
	Pistol = {
		Optic = { MiniDot = 2 },
		Muzzle = { Suppressor = 4 },
		Laser = { Laser = 3 },
		Mag = { ExtMag = 6, FastMag = 8 },
	},
}

-- allowed[gun][slot] = ordered ids (unlock order); unlock[gun][id] = level
local allowed, unlock = {}, {}
for gunName, g in GUNS do
	local ladder = LADDERS[g.Class]
	allowed[gunName], unlock[gunName] = {}, {}
	for _, slot in A.Slots do
		local list = {}
		local mounts = g.Mounts.World
		local fits = (slot == "Muzzle" and not g.NoMuzzle) or slot == "Mag" or (mounts[slot] ~= nil)
		if fits and ladder[slot] then
			for id, level in ladder[slot] do
				-- the 8x scope only on guns built for a scope view
				if id ~= "Recon8x" or (GameConfig.Guns[gunName] and GameConfig.Guns[gunName].Scope) then
					table.insert(list, id)
					unlock[gunName][id] = level
				end
			end
		end
		table.sort(list, function(a, b)
			return unlock[gunName][a] < unlock[gunName][b]
		end)
		allowed[gunName][slot] = list
	end
end

function A.Allowed(gunName, slot)
	return (allowed[gunName] and allowed[gunName][slot]) or {}
end

function A.UnlockLevel(gunName, id)
	return unlock[gunName] and unlock[gunName][id] or nil
end

function A.Fits(gunName, slot, id)
	local it = A.Items[id]
	return it ~= nil and it.Slot == slot and A.UnlockLevel(gunName, id) ~= nil
end

-- Picks ----------------------------------------------------------------------------------------------------------------

local function decode(raw)
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(t) == "table" then t else nil
end

-- Only picks that fit the gun survive (a bad save or an old id is dropped, never an error).
function A.Clean(gunName, picks)
	local out = {}
	if type(picks) ~= "table" then
		return out
	end
	for _, slot in A.Slots do
		local id = picks[slot]
		if type(id) == "string" and A.Fits(gunName, slot, id) then
			out[slot] = id
		end
	end
	return out
end

function A.ForPlayer(player, gunName)
	if not player then
		return {}
	end
	local saved = decode(player:GetAttribute("Attach"))
	local picks = table.clone((saved and saved[gunName]) or {})
	local run = decode(player:GetAttribute("RunAttach"))
	if run and type(run[gunName]) == "table" then
		for slot, id in run[gunName] do
			picks[slot] = id
		end
	end
	return A.Clean(gunName, picks)
end

-- A stable key for a set of picks ("" = none).
function A.Key(picks)
	local parts = {}
	for _, slot in A.Slots do
		if picks and picks[slot] then
			table.insert(parts, slot .. "=" .. picks[slot])
		end
	end
	return table.concat(parts, ",")
end

-- Numbers ----------------------------------------------------------------------------------------------------------------

local cache = {}

local function mulField(t, key, k)
	if type(t[key]) == "number" then
		t[key] *= k
	end
end

function A.Config(gunName, picks)
	local base = GameConfig.Guns[gunName]
	if not base then
		return nil
	end
	picks = A.Clean(gunName, picks)
	local key = gunName .. "|" .. A.Key(picks)
	if cache[key] then
		return cache[key]
	end
	local weight = (A.GunWeight[gunName] or base.Weight or 3) :: number
	for _, id in picks do
		weight += A.Items[id].Weight or 0
	end
	local g = table.clone(base)
	g.Weight = weight
	g.MoveSpeed, g.SprintMult = A.Mobility(weight)
	if next(picks) == nil then
		cache[key] = g
		return g
	end
	g.Spread = table.clone(base.Spread)
	g.Recoil = table.clone(base.Recoil)
	g.Feel = table.clone(base.Feel)
	if base.ShellReload then
		g.ShellReload = table.clone(base.ShellReload)
	end
	g.Attachments = picks
	local def = GUNS[gunName]
	for _, slot in A.Slots do
		local id = picks[slot]
		local m = id and A.Items[id].Mods or nil
		if m then
			if m.AimFov then
				g.AimFov = math.min(g.AimFov, m.AimFov)
			end
			if m.AimTime then
				g.AimTime *= m.AimTime
			end
			if m.AimSensitivity then
				g.AimSensitivity *= m.AimSensitivity
			end
			if m.Pitch then
				g.Recoil.Pitch *= m.Pitch
				mulField(g.Recoil, "KickPitch", m.Pitch)
			end
			if m.Yaw then
				g.Recoil.Yaw *= m.Yaw
				mulField(g.Recoil, "YawBias", m.Yaw)
			end
			if m.HipSpread then
				g.Spread.Hip *= m.HipSpread
				g.Spread.Move *= m.HipSpread
			end
			if m.MagMult then
				if def and def.MagAdd then
					g.MagSize = base.MagSize + def.MagAdd
				else
					g.MagSize = math.floor(base.MagSize * m.MagMult + 0.5)
				end
			end
			if m.Reload then
				mulField(g, "ReloadTime", m.Reload)
				mulField(g, "ReloadEmptyTime", m.Reload)
				if g.ShellReload then
					for k, v in g.ShellReload do
						if type(v) == "number" then
							g.ShellReload[k] = v * m.Reload
						end
					end
				end
			end
			if m.Falloff then
				g.FalloffStart *= m.Falloff
				g.FalloffEnd *= m.Falloff
			end
			if m.Pellet and g.PelletSpread then
				g.PelletSpread *= m.Pellet
				mulField(g, "AimPelletSpread", m.Pellet)
			end
			if m.Flash then
				mulField(g.Feel, "FlashSize", m.Flash)
				mulField(g.Feel, "LightBrightness", m.Flash)
				mulField(g.Feel, "MuzzleSparks", m.Flash)
			end
			if m.Shake then
				mulField(g.Feel, "Shake", m.Shake)
			end
			if m.Volume then
				g.Feel.ShotVolume = (g.Feel.ShotVolume or 1) * m.Volume
				g.Suppressed = true
			end
			if m.Noise then
				g.Noise = m.Noise
			end
			if m.Scope then
				g.Scope = table.clone(m.Scope)
			end
		end
	end
	-- An optic that isn't a scope takes the scope view off a scoped gun (the sniper's own scope is removed).
	if picks.Optic and not A.Items[picks.Optic].Mods.Scope and base.Scope then
		g.Scope = nil
	end
	cache[key] = g
	return g
end

function A.ConfigFor(player, gunName)
	return A.Config(gunName, A.ForPlayer(player, gunName))
end

-- Models ---------------------------------------------------------------------------------------------------------------

local library = nil
local function lib()
	if library and library.Parent then
		return library
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	library = assets and assets:FindFirstChild("Attachments")
	return library
end

local function modelName(gunName, id)
	local it = A.Items[id]
	local m = it and it.Model
	if type(m) == "table" then
		local def = GUNS[gunName]
		if def and def.SuppModel and it.Slot == "Muzzle" then
			return def.SuppModel
		end
		return m[def and def.Class or "Rifle"] or m.Rifle
	end
	return m
end
A.ModelName = modelName

local function rootOf(model)
	return model:FindFirstChild("Root") or model.PrimaryPart
end

local function prep(p, view, weld, root)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	if weld then
		p.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
	else
		p.Anchored = view == "VM" or p.Anchored
	end
end

-- The largest axis of a part as a unit vector in its own frame.
local function longAxis(p)
	local s = p.Size
	if s.X >= s.Y and s.X >= s.Z then
		return Vector3.xAxis, s.X
	elseif s.Y >= s.Z then
		return Vector3.yAxis, s.Y
	end
	return Vector3.zAxis, s.Z
end

local function isMagPart(p, view)
	if view == "VM" then
		return p:GetAttribute("VmGroup") == "Mag" and p.Name ~= "Bullets"
	end
	local n = string.lower(p.Name)
	return n == "mag" or n == "magazine"
end

-- A longer magazine: the mag parts grow along their long axis, downward from the mag well.
local function stretchMag(model, view, root)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and isMagPart(p, view) then
			local axis, len = longAxis(p)
			local k = 1.3
			local dirWorld = p.CFrame:VectorToWorldSpace(axis)
			if dirWorld:Dot(-root.CFrame.UpVector) < 0 then
				dirWorld = -dirWorld
			end
			p.Size += axis * len * (k - 1)
			p.CFrame += dirWorld * len * (k - 1) / 2
		end
	end
end

-- Fits the picks onto a gun model (a clone you own: parts are destroyed and added). Returns the set of slots fitted.
function A.Apply(model, gunName, picks, opts)
	opts = opts or {}
	local view = opts.View or "World"
	local def = GUNS[gunName]
	local folder = lib()
	local root = typeof(model) == "Instance" and rootOf(model)
	if not (def and folder and root) then
		return {}
	end
	picks = A.Clean(gunName, picks)
	local mounts = def.Mounts[model:GetAttribute("MountSet") or view] or def.Mounts[view] or def.Mounts.World
	local scale = if view == "VM" then def.VmScale else 1
	local fitted = {}
	for _, slot in A.Slots do
		local id = picks[slot]
		if id then
			if slot == "Mag" then
				if id == "ExtMag" then
					stretchMag(model, view, root)
				end
				fitted[slot] = id
				continue
			end
			local src = folder:FindFirstChild(modelName(gunName, id) or "")
			local at
			if slot == "Muzzle" then
				local m = model:FindFirstChild("Muzzle", true)
				if m and m:IsA("Attachment") then
					-- sink the device a little onto the barrel (and onto guns whose Muzzle point floats ahead of it)
					local back = 0.03 * scale + ((def.MuzzleBack and def.MuzzleBack[view]) or 0)
					at = CFrame.new(root.CFrame:PointToObjectSpace(m.WorldPosition) + Vector3.new(0, 0, back))
				end
			else
				local p = mounts[slot]
				at = p and CFrame.new(p) or nil
				if at and slot == "Laser" then
					-- on the right rail, its base toward the gun; on the centre line it hangs under the frame
					at *= if p.X ~= 0 then CFrame.Angles(0, 0, -math.pi / 2) else CFrame.Angles(0, 0, math.pi)
				end
			end
			if src and at then
				local c = src:Clone()
				if scale ~= 1 then
					c:ScaleTo(c:GetScale() * scale) -- ScaleTo is absolute; library models are already scaled
				end
				c:PivotTo(root.CFrame * at)
				local group = Instance.new("Model")
				group.Name = "Att_" .. slot
				for _, d in c:GetChildren() do
					if d:IsA("BasePart") then
						if d.Name == "Mount" then
							local sight = d:FindFirstChild("Sight")
							if sight and slot == "Optic" then
								local a = Instance.new("Attachment")
								a.Name = "OpticSight"
								a.CFrame = root.CFrame:ToObjectSpace(sight.WorldCFrame)
								a.Parent = root
							end
						else
							prep(d, view, opts.Weld, root)
							d.Parent = group
						end
					end
				end
				c:Destroy()
				group.Parent = model
				-- the muzzle moves to the end of the can
				if slot == "Muzzle" then
					local m = model:FindFirstChild("Muzzle", true)
					local len = (src:GetAttribute("Length") or 0) * scale
					local back = 0.03 * scale + ((def.MuzzleBack and def.MuzzleBack[view]) or 0)
					if m and m:IsA("Attachment") then
						m.WorldPosition = m.WorldPosition + root.CFrame.LookVector * (len - back)
					end
				end
				-- what the optic replaces
				local hide = def.Hide and def.Hide[slot] and def.Hide[slot][view]
				if hide then
					for _, name in hide do
						for _, d in model:GetDescendants() do
							if d:IsA("BasePart") and d.Name == name then
								d:Destroy()
							end
						end
					end
				end
				fitted[slot] = id
			end
		end
	end
	return fitted
end

-- Attachments then the player's camo (Shared.Camo), so the camo covers both.
function A.Dress(model, gunName, player, view, weld)
	local fitted = A.Apply(model, gunName, A.ForPlayer(player, gunName), { View = view, Weld = weld })
	local m = Shared:FindFirstChild("Camo")
	if m then
		local ok, Camo = pcall(require, m)
		if ok and type(Camo) == "table" and Camo.Apply and Camo.ForPlayer then
			pcall(Camo.Apply, model, gunName, Camo.ForPlayer(player, gunName))
		end
	end
	return fitted
end

return A
