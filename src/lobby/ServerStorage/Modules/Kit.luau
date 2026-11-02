-- STUB by CORE (2 Nov 2026). GUNS replaces this module. Signature frozen in horror-shooter/menu/CONTRACTS.md
-- section 3. Until then it returns today's start kit (pistol, no gear).
local Kit = {}

function Kit.Resolve(player)
	return {
		Class = player:GetAttribute("Class") or "Rifleman",
		Primary = nil,
		Secondary = "Pistol",
		Lethal = nil,
		Tactical = nil,
		Field = nil,
	}
end

return Kit
