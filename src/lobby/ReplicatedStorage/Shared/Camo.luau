-- Gun camos (GUNS, CONTRACTS.md section 9 palette). One pattern (a MaterialVariant made from the camo's art) per camo, put on the parts of a
-- gun model tagged "Body" (receiver, stock, handguard, slide): the metal bits, sights, grips and glass keep their
-- authored look, so every camo still reads as the same gun. Works on any copy of a gun: viewmodels
-- (Assets.ViewModels), world guns (Assets.WorldGuns: third person, pickups, hotbar and menu icons).
-- Which camos a player owns or has picked is DATA's (the player attribute Camos, JSON {gun = camo id}); this
-- module only knows what each camo looks like. Plain data and pure functions, no yields.
--   Camo.Order          -> the camo ids in menu order
--   Camo.Camos[id]      -> { Name, Color, Material, Rarity, Variant? }
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
	-- The pattern is a MaterialVariant (MaterialService.Camo_<id>, ColorMap = the camo's art, the same image the
	-- store shows), tinted white so the art shows true; without the variant the flat colour stays as a fallback.
	part.Material = entry.Material
	if entry.Variant then
		part.MaterialVariant = entry.Variant
		part.Color = entry.Tint or Color3.new(1, 1, 1)
	else
		part.MaterialVariant = ""
		part.Color = entry.Color
	end
end

-- Rarity (4 Nov 2026): how hard a camo is to get, shown on camo tiles, crate cards and the crate reveal. The names and
-- colours are the crate tiers' (Shared.Rewards.Tiers), so a Legendary camo and a Legendary crate share one colour.
-- Common: start and first levels. Rare: level 10 and the free pass. Epic: Store, crate pools and mastery. Legendary:
-- the two top mastery camos.
Camo.Rarity = {
	Gunmetal = "Common", Desert = "Common", Woodland = "Common",
	Arctic = "Rare", Moth = "Rare",
	Ash = "Epic", Rust = "Epic", Bone = "Epic", Night = "Epic", Signal = "Epic",
	Gold = "Legendary", LastLight = "Legendary",
}
for id, rarity in Camo.Rarity do
	if Camo.Camos[id] then
		Camo.Camos[id].Rarity = rarity
	end
end
-- Camo.RarityOf(id) -> "Common" | "Rare" | "Epic" | "Legendary" (Common for an unknown id)
function Camo.RarityOf(id)
	return Camo.Rarity[id] or "Common"
end

-- Tint (4 Nov 2026): multiplies each pattern (MaterialVariant Camo_<Id>, generated PBR maps) so bright patterns don't
-- bloom to white under the game's lights.
Camo.Tint = {
	Gunmetal = Color3.fromRGB(92, 94, 100), Woodland = Color3.fromRGB(230, 230, 220), Arctic = Color3.fromRGB(215, 222, 230),
	Moth = Color3.fromRGB(160, 148, 135), Ash = Color3.fromRGB(150, 150, 150), Rust = Color3.fromRGB(225, 215, 205),
	Bone = Color3.fromRGB(205, 196, 176), Night = Color3.fromRGB(235, 235, 235), Signal = Color3.fromRGB(190, 175, 175),
	LastLight = Color3.fromRGB(255, 240, 225),
}
for id, c in Camo.Tint do
	if Camo.Camos[id] then
		Camo.Camos[id].Tint = c
	end
end

-- Patterned camos: a MaterialVariant per camo (see paint). MaterialService replicates to every client.
do
	local MaterialService = game:GetService("MaterialService")
	for id, entry in Camo.Camos do
		if MaterialService:FindFirstChild("Camo_" .. id) then
			entry.Variant = "Camo_" .. id
		end
	end
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
