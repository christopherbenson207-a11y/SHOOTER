-- Gun camos (GUNS, CONTRACTS.md section 9 palette). One flat colour and material per camo, put on the parts of a
-- gun model tagged "Body" (receiver, stock, handguard, slide): the metal bits, sights, grips and glass keep their
-- authored look, so every camo still reads as the same gun. Works on any copy of a gun: viewmodels
-- (Assets.ViewModels), world guns (Assets.WorldGuns: third person, pickups, hotbar and menu icons).
-- Which camos a player owns or has picked is DATA's (the player attribute Camos, JSON {gun = camo id}); this
-- module only knows what each camo looks like. Plain data and pure functions, no yields.
--   Camo.Order          -> the camo ids in menu order
--   Camo.Camos[id]      -> { Name, Color, Material, Texture = nil }
--   Camo.Get(id)        -> that entry, or nil
--   Camo.Apply(model, gunKey, camoId) -> true if it recoloured anything. A nil or unknown camo leaves the model
--     as authored. gunKey is unused today (kept so a camo can later differ per gun).
--   Camo.ForPlayer(player, gunKey) -> the camo id the player picked for that gun, or nil

local HttpService = game:GetService("HttpService")

local Camo = {}

Camo.Order = {
	"Gunmetal", "Desert", "Woodland", "Arctic", "Bone", "Ash", "Moth", "Night", "Rust", "Signal", "Gold", "LastLight",
}

Camo.Camos = {
	Gunmetal = { Name = "GUNMETAL", Color = Color3.fromRGB(42, 44, 47), Material = Enum.Material.Metal },
	Desert = { Name = "DESERT", Color = Color3.fromRGB(170, 146, 104), Material = Enum.Material.Plastic },
	Woodland = { Name = "WOODLAND", Color = Color3.fromRGB(70, 80, 50), Material = Enum.Material.Plastic },
	Arctic = { Name = "ARCTIC", Color = Color3.fromRGB(205, 210, 212), Material = Enum.Material.Plastic },
	Gold = { Name = "GOLD", Color = Color3.fromRGB(212, 170, 70), Material = Enum.Material.Metal },
	Bone = { Name = "BONE", Color = Color3.fromRGB(214, 204, 182), Material = Enum.Material.Plastic },
	Night = { Name = "NIGHT", Color = Color3.fromRGB(24, 28, 40), Material = Enum.Material.SmoothPlastic },
	LastLight = { Name = "LAST LIGHT", Color = Color3.fromRGB(230, 150, 50), Material = Enum.Material.Metal },
	Rust = { Name = "RUST", Color = Color3.fromRGB(122, 66, 40), Material = Enum.Material.CorrodedMetal },
	Ash = { Name = "ASH", Color = Color3.fromRGB(110, 110, 106), Material = Enum.Material.Slate },
	Signal = { Name = "SIGNAL", Color = Color3.fromRGB(150, 40, 36), Material = Enum.Material.Metal },
	Moth = { Name = "MOTH", Color = Color3.fromRGB(126, 112, 92), Material = Enum.Material.Fabric },
}

Camo.Default = "Gunmetal"

function Camo.Get(id)
	return if type(id) == "string" then Camo.Camos[id] else nil
end

local function paint(part, entry)
	-- A texture or surface appearance would hide the colour: the camo replaces them on body parts.
	if part:IsA("MeshPart") then
		part.TextureID = ""
	elseif part:IsA("UnionOperation") then
		part.UsePartColor = true
	end
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceAppearance") or child:IsA("Texture") or child:IsA("Decal") then
			child:Destroy()
		elseif child:IsA("SpecialMesh") then
			child.TextureId = ""
		end
	end
	part.Color = entry.Color
	part.Material = entry.Material
	part.MaterialVariant = ""
end

function Camo.Apply(model, _gunKey, camoId)
	local entry = Camo.Get(camoId)
	if not (entry and typeof(model) == "Instance") then
		return false
	end
	local any = false
	local function visit(d)
		if d:IsA("BasePart") and d:HasTag("Body") then
			paint(d, entry)
			any = true
		end
	end
	visit(model)
	for _, d in model:GetDescendants() do
		visit(d)
	end
	return any
end

function Camo.ForPlayer(player, gunKey)
	local raw = player and player:GetAttribute("Camos")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, map = pcall(HttpService.JSONDecode, HttpService, raw)
	local id = if ok and type(map) == "table" then map[gunKey] else nil
	return if Camo.Camos[id] then id else nil
end

return Camo
