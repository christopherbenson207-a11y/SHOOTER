-- Gun looks built from plain parts (no assets), one per Config.Weapons Look. The grip is the
-- origin: barrel along -Z, up is +Y, and the invisible "Handle" part sits where the hand holds it,
-- so a Tool made from it points forward with the default Grip. A "Muzzle" attachment in the Handle
-- marks the barrel's tip.
--   GunModel.Build(id, opts) -> Model
--     opts.Level: ascension level (tints the accent parts, Config.Altar.TierColors)
--     opts.Anchored: for display (the randomizer, a wall); otherwise parts are welded to Handle
--     opts.Chalk: drawn on a wall (one chalk colour)
--     opts.CFrame: where the grip goes (default: the origin)

local Config = require(script.Parent.Config)

local GunModel = {}

local METAL = Color3.fromRGB(46, 46, 50)
local DARK = Color3.fromRGB(30, 30, 34)
local WOOD = Color3.fromRGB(104, 70, 42)
local CHALK = Color3.fromRGB(232, 232, 222)

local LOOKS = {
	Pistol = { Body = Vector3.new(0.3, 0.42, 1.25), Barrel = 0.15, Bore = 0.16 },
	Revolver = { Body = Vector3.new(0.34, 0.5, 0.9), Barrel = 0.9, Bore = 0.22, Cylinder = true },
	Carbine = { Body = Vector3.new(0.32, 0.45, 1.9), Barrel = 1.3, Stock = 1.5, Mag = Vector3.new(0.24, 0.5, 0.35), Wood = true },
	BoltRifle = { Body = Vector3.new(0.3, 0.42, 2), Barrel = 2, Stock = 1.7, Wood = true, Bolt = true },
	SMG = { Body = Vector3.new(0.34, 0.55, 1.5), Barrel = 0.5, Stock = 0.8, Mag = Vector3.new(0.24, 0.85, 0.32) },
	Shotgun = { Body = Vector3.new(0.34, 0.45, 1.6), Barrel = 2, Bore = 0.26, Stock = 1.6, Pump = true, Wood = true },
	AK = { Body = Vector3.new(0.34, 0.55, 1.9), Barrel = 1.3, Stock = 1.5, Mag = Vector3.new(0.28, 0.85, 0.42), MagTilt = 18, Wood = true },
	M4 = { Body = Vector3.new(0.34, 0.6, 1.8), Barrel = 1.2, Stock = 1.3, Mag = Vector3.new(0.26, 0.75, 0.38), Rail = true },
	BattleRifle = { Body = Vector3.new(0.36, 0.6, 2.1), Barrel = 1.5, Stock = 1.5, Mag = Vector3.new(0.28, 0.6, 0.45), Scope = 1.3 },
	Sniper = { Body = Vector3.new(0.34, 0.5, 2.1), Barrel = 2.3, Stock = 1.7, Scope = 1.8, Wood = true },
	LMG = { Body = Vector3.new(0.5, 0.7, 2.1), Barrel = 1.7, Bore = 0.28, Stock = 1.5, Box = Vector3.new(0.6, 0.6, 0.7) },
	CoachGun = { Body = Vector3.new(0.34, 0.45, 1.1), Barrel = 2.1, Bore = 0.22, Double = true, Stock = 1.6, Wood = true },
	Lumen = { Body = Vector3.new(0.5, 0.6, 1.8), Barrel = 1.1, Bore = 0.3, Glow = Color3.fromRGB(150, 230, 255), Coils = 3 },
}

function GunModel.Look(id: string)
	local w = Config.Weapons[id]
	return LOOKS[w and w.Look or "Pistol"] or LOOKS.Pistol
end

function GunModel.Build(id: string, opts: { [string]: any }?): Model
	opts = opts or {}
	local look = GunModel.Look(id)
	local at = opts.CFrame or CFrame.new()
	local level = opts.Level or 0
	local tier = if level > 0 then Config.Altar.TierColors[math.min(level, #Config.Altar.TierColors)] else nil

	local model = Instance.new("Model")
	model.Name = id

	local function part(name, size, cf, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = at * cf
		p.Color = if opts.Chalk then CHALK else color
		p.Material = if opts.Chalk then Enum.Material.SmoothPlastic elseif material then material else Enum.Material.Metal
		p.Transparency = if opts.Chalk then 0.15 else 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = not opts.Chalk
		p.Anchored = opts.Anchored == true
		p.Parent = model
		return p
	end

	local handle = part("Handle", Vector3.new(0.4, 0.4, 0.4), CFrame.new(), METAL)
	handle.Transparency = 1

	local body = look.Body
	local front = 0.55 - body.Z
	local wood = if look.Wood then WOOD else METAL
	local accent = if tier then tier else METAL
	local accentMat = if tier then Enum.Material.Neon else Enum.Material.Metal

	part("Grip", Vector3.new(0.28, 0.85, 0.42), CFrame.new(0, -0.3, 0.12) * CFrame.Angles(math.rad(-18), 0, 0), wood, if look.Wood then Enum.Material.Wood else Enum.Material.SmoothPlastic)
	part("Body", body, CFrame.new(0, 0.3, 0.55 - body.Z / 2), METAL)
	part("Accent", Vector3.new(body.X + 0.04, 0.08, body.Z * 0.75), CFrame.new(0, 0.32, 0.55 - body.Z / 2), accent, accentMat)

	local bore = look.Bore or 0.18
	local barrelY = 0.36
	local function barrel(x)
		part("Barrel", Vector3.new(look.Barrel, bore, bore), CFrame.new(x, barrelY, front - look.Barrel / 2) * CFrame.Angles(0, math.rad(90), 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	if look.Double then
		barrel(-0.1)
		barrel(0.1)
	else
		barrel(0)
	end
	if look.Wood and look.Stock then
		part("Handguard", Vector3.new(body.X + 0.06, 0.3, math.min(look.Barrel * 0.6, 1.4)), CFrame.new(0, 0.2, front - math.min(look.Barrel * 0.6, 1.4) / 2), WOOD, Enum.Material.Wood)
	end
	if look.Stock then
		part("Stock", Vector3.new(0.28, 0.5, look.Stock), CFrame.new(0, 0.15, 0.55 + look.Stock / 2) * CFrame.Angles(math.rad(-6), 0, 0), wood, if look.Wood then Enum.Material.Wood else Enum.Material.SmoothPlastic)
	end
	if look.Mag then
		local m = look.Mag
		local cf = CFrame.new(0, 0.3 - body.Y / 2 - m.Y / 2 + 0.12, front + 0.45 + m.Z / 2) * CFrame.Angles(math.rad(look.MagTilt or 0), 0, 0)
		part("Mag", m, cf, DARK)
	end
	if look.Box then
		part("Box", look.Box, CFrame.new(0.05, 0.3 - body.Y / 2 - look.Box.Y / 2 + 0.1, front + 0.8), Color3.fromRGB(70, 74, 54))
	end
	if look.Pump then
		part("Pump", Vector3.new(0.34, 0.28, 0.8), CFrame.new(0, barrelY - 0.24, front - 0.6), WOOD, Enum.Material.Wood)
	end
	if look.Cylinder then
		part("Cylinder", Vector3.new(0.5, 0.46, 0.46), CFrame.new(0, 0.32, front + 0.3) * CFrame.Angles(0, math.rad(90), 0), METAL, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	if look.Scope then
		part("Scope", Vector3.new(look.Scope, 0.32, 0.32), CFrame.new(0, 0.3 + body.Y / 2 + 0.24, 0.55 - body.Z / 2) * CFrame.Angles(0, math.rad(90), 0), DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	if look.Rail then
		part("Rail", Vector3.new(0.2, 0.1, body.Z * 0.8), CFrame.new(0, 0.3 + body.Y / 2 + 0.05, 0.55 - body.Z / 2), DARK)
	end
	if look.Bolt then
		part("Bolt", Vector3.new(0.3, 0.1, 0.1), CFrame.new(0.22, 0.42, 0.25), METAL)
	end
	if look.Glow then
		for i = 1, look.Coils or 2 do
			part("Coil", Vector3.new(0.12, bore + 0.25, bore + 0.25), CFrame.new(0, barrelY, front - i * look.Barrel / ((look.Coils or 2) + 1)) * CFrame.Angles(0, math.rad(90), 0), look.Glow, Enum.Material.Neon, Enum.PartType.Cylinder)
		end
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, barrelY, front - look.Barrel - 0.05)
	muzzle.Parent = handle

	if not opts.Anchored then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end
	model.PrimaryPart = handle
	return model
end

return GunModel
