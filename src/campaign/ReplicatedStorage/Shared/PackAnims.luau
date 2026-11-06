--!strict
-- Third-person clips for the pack guns (ReplicatedStorage.Assets.PackGuns), 5 Nov 2026.
-- They are the BZ1 Tactical Combat pack clips, converted from R6 to R15 and cut to the upper body
-- (horror-shooter/anims/tools/make_upper.py: no leg keys, the hip lean moved to the waist), so the default walk and
-- run keep the legs. Owned by the Last Light group (964368511). WorldGunArms plays them on other players' characters.
-- Length is each clip's own length in seconds; WorldGunArms uses it to fit a clip to the gun's timing in GameConfig.
-- Clips from the pack that are not used here are listed in docs/ANIMATION-IDS-UNUSED.md.

export type Clip = { Id: string, Length: number }
export type Set = {
	Equip: Clip?,
	Idle: Clip?,
	Run: Clip?,
	Fire: Clip?,
	Pump: Clip?, -- after each shot (pump action)
	Reload: Clip?, -- magazine reload, fitted to ReloadTime / ReloadEmptyTime
	ReloadStart: Clip?, -- shell reload: lift the gun once,
	ShellInsert: Clip?, -- then one of these per shell (ShellReload.ShellTime),
	ReloadEnd: Clip?, -- then this when the tube is full or the reload is cut short
}

local function clip(id: number, length: number): Clip
	return { Id = "rbxassetid://" .. id, Length = length }
end

local PackAnims: { [string]: Set } = {
	-- AKM set
	AK = {
		Equip = clip(134686602891830, 1.00),
		Idle = clip(99910829897528, 2.00),
		Run = clip(110055618317469, 0.50),
		Fire = clip(92560798049728, 0.17),
		Reload = clip(106217539642726, 4.50),
	},
	-- Beretta 92 set
	Pistol = {
		Equip = clip(117917872414635, 1.00), -- "Beretta Equip 2" (the short draw)
		Idle = clip(94210001160523, 1.50),
		Run = clip(94307761110020, 0.47),
		Fire = clip(129103299313669, 0.62),
		Reload = clip(103537196856086, 3.08),
	},
	-- Shotgun set
	Shotgun = {
		Equip = clip(108622875285319, 2.37),
		Idle = clip(135418271684806, 2.00),
		Run = clip(95380230083148, 0.47),
		Fire = clip(107325330490582, 0.60),
		Pump = clip(80487067865875, 0.95),
		ReloadStart = clip(108807959247764, 0.35),
		ShellInsert = clip(135632892076914, 0.70),
		ReloadEnd = clip(80487067865875, 0.95), -- rack it once the shells are in
	},
}

return PackAnims
