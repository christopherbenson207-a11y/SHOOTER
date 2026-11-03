-- A gun's numbers as they stand for one player: the gun's own (Config.Weapons), what the ascension
-- altar added to this copy (the tool's Boosts attribute, a comma list of Config.Altar.Boosts ids),
-- and the player's perks and relics. Server and clients use the same sums, so the client's fire
-- rate, magazine and reload match what the server allows.
--
-- Tool attributes (set by the server's Arsenal): Weapon (id), Mag, Reserve, Boosts, Level,
-- Reloading (bool), ReloadEnd (server time).

local Config = require(script.Parent.Config)

local Weapons = {}

function Weapons.Get(id: string)
	return Config.Weapons[id]
end

function Weapons.ParseBoosts(text: string?): { string }
	local list = {}
	if text and text ~= "" then
		for id in string.gmatch(text, "[^,]+") do
			if Config.Altar.Boosts[id] then
				table.insert(list, id)
			end
		end
	end
	return list
end

local function attr(player: Player?, name: string): number
	return if player then (player:GetAttribute(name) or 0) else 0
end

-- The numbers for gun `id` with these boosts, carried by player (nil: the bare gun).
function Weapons.Stats(id: string, boostText: string?, player: Player?)
	local base = Config.Weapons[id]
	if not base then
		return nil
	end
	local boosts = Weapons.ParseBoosts(boostText)
	local damage, mag, reserve, rpm, reload, pierce, head = 1, 1, 1, 1, 1, base.Pierce or 1, base.Head or 1
	for _, b in boosts do
		local boost = Config.Altar.Boosts[b]
		damage += boost.Damage or 0
		mag += boost.Mag or 0
		reserve += boost.Reserve or 0
		rpm += boost.Rpm or 0
		reload *= 1 - (boost.Reload or 0)
		pierce += boost.Pierce or 0
		head += boost.Head or 0
	end
	local perks = Config.Perks.List
	if player then
		damage *= 1 + attr(player, "RelicDamage")
		head = 1 + (head - 1) * (1 + attr(player, "RelicHead"))
		reserve += attr(player, "RelicReserve")
		reload *= 1 - attr(player, "RelicReload")
		if player:GetAttribute("Perk_TwinFang") then
			rpm *= perks.TwinFang.FireRate
		end
		if player:GetAttribute("Perk_Quickhand") then
			reload *= perks.Quickhand.Reload
		end
	end
	return {
		Id = id,
		Name = base.Name,
		Fire = base.Fire,
		Damage = base.Damage * damage,
		Pellets = base.Pellets or 1,
		Head = head,
		Rpm = base.Rpm * rpm,
		Mag = math.max(1, math.floor(base.Mag * mag + 0.5)),
		Reserve = math.floor(base.Reserve * reserve + 0.5),
		Reload = base.Reload * reload,
		Spread = base.Spread,
		Range = base.Range,
		Pierce = pierce,
		AimFov = base.AimFov,
		Sounds = base.Sounds,
		Beam = base.Beam,
		Level = #boosts,
	}
end

-- The same, read off a tool.
function Weapons.ForTool(tool: Instance, player: Player?)
	local id = tool:GetAttribute("Weapon")
	return id and Weapons.Stats(id, tool:GetAttribute("Boosts"), player) or nil
end

-- What the altar charges to ascend a gun that has ascended `level` times.
function Weapons.AscendCost(level: number): number
	return math.floor(Config.Altar.Cost * Config.Altar.Growth ^ level / 50 + 0.5) * 50
end

return Weapons
