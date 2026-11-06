-- Gun card numbers (GUNS, CONTRACTS.md section 2): every stat bar comes from GameConfig.Guns through one formula
-- per bar, so a card can never disagree with how the gun plays. Plain tables and pure functions: no instances,
-- no yields. Bars are 0..1: DAMAGE, FIRE RATE, RANGE, CONTROL, MAGAZINE, NOISE (MENU-PLAN 9.8; no mobility).

local Shared = script.Parent
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local S = {}

S.Order = { "Damage", "FireRate", "Range", "Control", "Magazine", "Noise" }

local function clamp(x)
	return math.clamp(x, 0.05, 1)
end

-- Damage: one trigger pull (all pellets), on a log scale from 8 (0) to 200 (1), so a rifle's 28 and an SMG's 22
-- still read apart while the shotgun and the sniper sit near the top.
local function damage(g)
	local d = g.Damage * (g.Pellets or 1)
	return clamp(math.log(d / 8) / math.log(200 / 8))
end

-- Fire rate: rounds a minute, 900 = full.
local function fireRate(g)
	return clamp(g.RPM / 900)
end

-- Range: the middle of the falloff, on a log scale from 10 studs (0) to 800 (1).
local function range(g)
	local mid = (g.FalloffStart + g.FalloffEnd) / 2
	return clamp(math.log(math.max(mid, 10) / 10) / math.log(80))
end

-- Control: less climb, side kick and bloom per shot is more control; the class perk is not included.
local function control(g)
	local r, s = g.Recoil, g.Spread
	local kick = r.Pitch + 0.5 * r.Yaw + 2 * s.PerShot
	return clamp(1 - kick / 9)
end

-- Magazine: square root of the rounds in one magazine, 100 = full.
local function magazine(g)
	return clamp(math.sqrt(g.MagSize / 100))
end

local function noise(g)
	return clamp(g.Noise or 0.8)
end

-- {Damage, FireRate, Range, Control, Magazine, Noise}, each 0..1, or nil for an unknown gun. picks (optional,
-- {slot = id}): the gun with those attachments on (Shared.Attachments), so the Gunsmith shows what each one changes.
function S.Bars(gunKey, picks)
	local g = GameConfig.Guns[gunKey]
	if g and picks and next(picks) then
		local m = Shared:FindFirstChild("Attachments")
		local ok, A = pcall(require, m)
		if ok and type(A) == "table" then
			g = A.Config(gunKey, picks) or g
		end
	end
	if not g then
		return nil
	end
	return {
		Damage = damage(g),
		FireRate = fireRate(g),
		Range = range(g),
		Control = control(g),
		Magazine = magazine(g),
		Noise = noise(g),
	}
end

-- {Name, Category, Slot, Level, Role}, or nil for an unknown gun. Level is the account level that unlocks it
-- (Shared.Progression when it has the gun, else the gun's own Level).
function S.Info(gunKey)
	local g = GameConfig.Guns[gunKey]
	if not g then
		return nil
	end
	local level = g.Level or 1
	local m = Shared:FindFirstChild("Progression")
	if m then
		local ok, P = pcall(require, m)
		if ok and type(P) == "table" and P.UnlockLevel then
			level = P.UnlockLevel(gunKey) or level
		end
	end
	return {
		Name = g.Name or g.DisplayName or gunKey,
		Category = g.Category,
		Slot = g.Slot,
		Level = level,
		Role = g.Role,
	}
end

-- The registered guns for one slot ("Primary" or "Secondary"; nil for all), in unlock order then name.
function S.List(slot)
	local list = {}
	for _, key in GameConfig.Arsenal or GameConfig.Loadout or {} do
		local g = GameConfig.Guns[key]
		if g and (slot == nil or g.Slot == slot) then
			table.insert(list, key)
		end
	end
	table.sort(list, function(a, b)
		local la, lb = S.Info(a).Level, S.Info(b).Level
		if la ~= lb then
			return la < lb
		end
		return a < b
	end)
	return list
end

return S
