local IDS = {XpBoost30 = 3729096090, XpBoost60 = 3729096292, XpBoost120 = 3729096317, GemBoost30 = 3729096341, GemBoost60 = 3729096444, GemBoost120 = 3729096457, Scrip1 = 3729096474, Scrip2 = 3729096574, Scrip3 = 3729096590, Scrip4 = 3729096609, Revive = 3729096682, Revive5 = 3729096704, SquadBoost = 3729096719, PassPremium = 3729096803, PassPremium10 = 3729096822, PassTiers5 = 3729096839, PassTier1 = 3729096939, StarterPack = 3729096959, CamoBundle = 3729098089, SpecialistBundle = 3729098111, Item_CamoRust = 3729098136, Item_CamoAsh = 3729098243, Item_CardStatic = 3729098278, Item_CardAshfall = 3729098294, Item_OperatorWarden = 3729098374, Item_OperatorRevenant = 3729098389, Item_OperatorLamplighter = 3729098408, Vip = 2075661062, DoubleScrip = 2075937113, Beams = 2074977093, K9 = 2075421085}

local LEGACY = { StarterPack = "Product", Vip = "Pass", Revive = "Product", K9 = "Pass" }
local SES = game:GetService("ScriptEditorService")
local report = {}
local function patch(m, fn)
	if not m then return end
	local s = m.Source
	local n2, total = s, 0
	n2, total = fn(n2)
	if n2 ~= s then SES:UpdateSourceAsync(m, function() return n2 end) end
	report[m.Name] = total
end
local shared = game.ReplicatedStorage:FindFirstChild("Shared")
patch(shared and shared:FindFirstChild("Catalogue"), function(s)
	local t = 0
	for key, id in IDS do
		local k
		s, k = s:gsub("(\n%s*" .. key .. " = { Type = \"%a+\", Id = )0,", "%1" .. id .. ",")
		t += k
		if key:sub(1, 5) == "Item_" then
			s, k = s:gsub("(" .. key .. " = )0([,%s])", "%1" .. id .. "%2")
			t += k
		end
	end
	return s, t
end)
patch(shared and shared:FindFirstChild("GameConfig"), function(s)
	local t = 0
	for key, field in LEGACY do
		local k
		s, k = s:gsub("(\n%s*" .. key .. " = { " .. field .. " = )0([,%s])", "%1" .. IDS[key] .. "%2")
		t += k
	end
	return s, t
end)
return report
