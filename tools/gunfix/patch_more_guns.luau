-- GUNFIX 11 Nov e + f: more GunSystem guns as guns of the place. Run in Multiplayer, campaign and Zombies (Edit).
--   e: AKM, AKS-74U (the AK's clips, which the group owns).
--   f: Thompson (UMP clips), M1014 (pump shotgun clips), Mosin M1891 (bolt rifle clips), Taurus revolver (pistol
--      clips). Their own GunSystem clips belong to another account and cannot load, so each borrows the nearest set.
-- Models are GunSystem's own (SPH_Assets.WeaponModels). Stats derive from an existing gun of the place.
local RS, SS, SP = game.ReplicatedStorage, game.ServerStorage, game.StarterPlayer
local function rep(s, old, new, count)
	local n = 0
	local out = s:gsub(old:gsub("%p", "%%%0"), function() n += 1 return new end)
	if n ~= (count or 1) then error("hits " .. n .. " for " .. old) end
	return out
end
local function beforeReturn(s, block)
	local at, from = nil, 1
	while true do
		local a = s:find("\nreturn GameConfig", from, true)
		if not a then break end
		at = a
		from = a + 1
	end
	if not at then error("no return") end
	return s:sub(1, at) .. block .. "\nreturn GameConfig\n"
end
local E = [==[
-- GUNFIX 11 Nov e: GunSystem's AKM and AKS-74U. Each is the AK with a few numbers changed; SphModel names the GunSystem
-- model (SPH_Assets.WeaponModels) that the hotbar shows. In Zombies they join the Endless deal and the mystery box.
do
	local function copy(t)
		local o = {}
		for k, v in t do
			o[k] = if type(v) == "table" then copy(v) else v
		end
		return o
	end
	local base = GameConfig.Guns.AK
	local list = GameConfig.Arsenal or GameConfig.Loadout
	local function add(key, change)
		if not base or not list or GameConfig.Guns[key] then
			return
		end
		local g = copy(base)
		change(g)
		GameConfig.Guns[key] = g
		table.insert(list, key)
	end
	add("AKM", function(g)
		g.DisplayName, g.Name, g.SphModel = "AKM", "AKM", "AKM"
		g.Role = "THE OLD HEAVY ROUND: SLOWER, AND IT HITS HARDER"
		g.RPM = math.floor(g.RPM * 0.92)
		g.Damage = math.floor(g.Damage * 1.18 + 0.5)
		g.Recoil.Pitch *= 1.2
		g.Recoil.Yaw *= 1.15
		g.MoveSpeed = (g.MoveSpeed or 1) * 0.97
	end)
	add("AKS74U", function(g)
		g.DisplayName, g.Name, g.SphModel = "AKS-74U", "AKS-74U", "AKS-74U"
		g.Role = "A SHORT AK FOR ROOMS AND STAIRS"
		g.RPM = math.floor(g.RPM * 1.2)
		g.Damage = math.floor(g.Damage * 0.86 + 0.5)
		g.FalloffStart *= 0.6
		g.FalloffEnd *= 0.7
		g.Spread.Hip *= 0.85
		g.Spread.Aim *= 1.6
		g.AimTime *= 0.82
		g.MoveSpeed = (g.MoveSpeed or 1) * 1.05
		g.EquipTime = (g.EquipTime or 0.5) * 0.85
	end)
	local endless = GameConfig.Endless
	if endless and endless.Guns and GameConfig.Guns.AKM then
		table.insert(endless.Guns, { Gun = "AKS74U", From = 1 })
		table.insert(endless.Guns, { Gun = "AKM", From = 6 })
		if endless.BoxGuns then
			endless.BoxGuns.AKM = 2
			endless.BoxGuns.AKS74U = 3
		end
	end
end
]==]
local F = [==[
-- GUNFIX 11 Nov f: four more GunSystem guns. Each starts from the nearest gun of the place (Base) and changes a few
-- numbers. Their own GunSystem clips cannot load here, so the Tools borrow the UMP, pump shotgun, bolt rifle and
-- pistol clips (ServerStorage.GunTools).
do
	local function copy(t)
		local o = {}
		for k, v in t do
			o[k] = if type(v) == "table" then copy(v) else v
		end
		return o
	end
	local G = GameConfig.Guns
	local list = GameConfig.Arsenal or GameConfig.Loadout
	local added = {}
	local function add(key, base, change)
		if not base or not list or G[key] then
			return
		end
		local g = copy(base)
		change(g)
		G[key] = g
		table.insert(list, key)
		added[key] = true
	end
	add("Thompson", G.MP5 or G.AK, function(g)
		g.DisplayName, g.Name, g.SphModel = "Thompson", "Thompson", "Thompson 1928"
		g.Category, g.Slot = "Submachine gun", "Primary"
		g.Role = "FIFTY ROUNDS, AND IT EMPTIES THEM FAST"
		g.FireMode = "Auto"
		g.RPM = 700
		g.MagSize = 50
		g.Reserve = 200
		g.Damage = math.floor(g.Damage * 0.92 + 0.5)
		g.ReloadTime *= 1.15
		g.ReloadEmptyTime *= 1.15
		g.MoveSpeed = (g.MoveSpeed or 1) * 0.95
	end)
	add("M1014", G.Shotgun, function(g)
		g.DisplayName, g.Name, g.SphModel = "M1014", "M1014", "Tactical M1014"
		g.Role = "NO PUMP: EVERY PULL IS ANOTHER SHELL"
		g.FireMode = "Semi"
		g.RPM = 230
		g.MagSize = 7
		g.Damage = math.floor(g.Damage * 0.85 + 0.5)
	end)
	add("Mosin", G.Sniper, function(g)
		g.DisplayName, g.Name, g.SphModel = "Mosin", "Mosin", "M1891"
		g.Role = "IRON SIGHTS AND A BOLT: FIVE ROUNDS THAT COUNT"
		g.Scope = nil
		g.AimFov = 42
		g.AimSensitivity = 0.6
		g.AimTime *= 0.7
		g.MagSize = 5
		g.MoveSpeed = math.min(1, (g.MoveSpeed or 1) * 1.08)
	end)
	add("Revolver", G.HandCannon or G.Pistol, function(g)
		g.DisplayName, g.Name, g.SphModel = "Revolver", "Revolver", "Taurus 82"
		g.Category, g.Slot = "Revolver", "Secondary"
		g.Role = "SIX SLOW ROUNDS THAT PUT THINGS DOWN"
		g.FireMode = "Semi"
		g.MagSize = 6
		g.RPM = math.floor(g.RPM * 0.75)
		g.Damage = math.floor(g.Damage * 1.3 + 0.5)
		g.ReloadTime *= 1.25
		g.ReloadEmptyTime *= 1.25
	end)
	local endless = GameConfig.Endless
	if endless and endless.Guns then
		for _, deal in { { "Thompson", 1 }, { "Revolver", 1 }, { "M1014", 6 }, { "Mosin", 6 } } do
			if added[deal[1]] then
				table.insert(endless.Guns, { Gun = deal[1], From = deal[2] })
				if endless.BoxGuns then
					endless.BoxGuns[deal[1]] = 2
				end
			end
		end
	end
end
]==]
local jobs = {
	{ RS.Shared.GameConfig, "GUNFIX 11 Nov e", function(s) return beforeReturn(s, E) end },
	{ RS.Shared.GameConfig, "GUNFIX 11 Nov f", function(s) return beforeReturn(s, F) end },
	{ RS.SPH_Assets.Modules.GunNameMap, "GUNFIX 11 Nov e", function(s)
		return rep(s, '["AK-74"] = "AK",', '["AK-74"] = "AK",\n\t["AKM"] = "AKM", -- GUNFIX 11 Nov e\n\t["AKS-74U"] = "AKS74U",')
	end },
	{ RS.SPH_Assets.Modules.GunNameMap, "GUNFIX 11 Nov f", function(s)
		return rep(s, '["AKS-74U"] = "AKS74U",', '["AKS-74U"] = "AKS74U",\n\t["Thompson 1928"] = "Thompson", -- GUNFIX 11 Nov f\n\t["Tactical M1014"] = "M1014",\n\t["M1891"] = "Mosin",\n\t["Taurus 82"] = "Revolver",')
	end },
	{ SP.StarterPlayerScripts.Hotbar, "GUNFIX 11 Nov e", function(s)
		s = rep(s, "local function iconSource(item)\n\tlocal gun = GameConfig.Guns[item]\n", "local function iconSource(item)\n\tlocal gun = GameConfig.Guns[item]\n\tif gun and gun.SphModel then -- GUNFIX 11 Nov e: a GunSystem gun shows its GunSystem model\n\t\tlocal sph = ReplicatedStorage.SPH_Assets.WeaponModels:FindFirstChild(gun.SphModel)\n\t\tif sph then\n\t\t\treturn sph\n\t\tend\n\tend\n")
		s = rep(s, "Attachments.Dress(model, gunKey, player, view)", "if not GameConfig.Guns[gunKey].SphModel then Attachments.Dress(model, gunKey, player, view) end")
		return s
	end },
	{ game.ServerScriptService.ToolGrant, "GUNFIX 11 Nov f", function(s)
		return rep(s, "\t\t\t\tchild:Destroy()\n", '\t\t\t\tlocal stowed = character:FindFirstChild("Holster_" .. child.Name) -- GUNFIX 11 Nov f: its stowed copy goes too\n\t\t\t\tif stowed then\n\t\t\t\t\tstowed:Destroy()\n\t\t\t\tend\n\t\t\t\tchild:Destroy()\n')
	end },
}
local out = {}
local SES = game:GetService("ScriptEditorService")
for _, job in jobs do
	local target, mark, fn = job[1], job[2], job[3]
	local src = target.Source
	if src:find(mark, 1, true) then
		table.insert(out, target.Name .. " [" .. mark .. "]: already")
	else
		local ok, new = pcall(fn, src)
		if not ok then return table.concat(out, "\n") .. "\nFAILED " .. target.Name .. " [" .. mark .. "]: " .. tostring(new) end
		local compiled, err = loadstring(new)
		if not compiled then return table.concat(out, "\n") .. "\nCOMPILE ERROR " .. target.Name .. ": " .. tostring(err) end
		SES:UpdateSourceAsync(target, function() return new end)
		table.insert(out, target.Name .. " [" .. mark .. "] -> " .. #target.Source)
	end
end
local tools = SS.GunTools
local models = RS.SPH_Assets.WeaponModels
local function tool(name, baseName, subs)
	local base = tools:FindFirstChild(baseName)
	if tools:FindFirstChild(name) or not base or not models:FindFirstChild(name) then
		return
	end
	local t = base:Clone()
	t.Name = name
	local ws = t.SPH_Weapon.WeaponStats
	local s = ws.Source
	for _, p in subs or {} do
		local ok, res = pcall(rep, s, p[1], p[2])
		if ok then s = res else table.insert(out, "  (" .. name .. ": no line '" .. p[1] .. "')") end
	end
	ws.Source = s
	t.Parent = tools
	table.insert(out, "tool " .. name .. " from " .. baseName)
end
tool("AKM", "AK-74", { { "wepStats.fireRate = 625", "wepStats.fireRate = 600" }, { "wepStats.muzzleVelocity = 900", "wepStats.muzzleVelocity = 715" } })
tool("AKS-74U", "AK-74", { { "wepStats.fireRate = 625", "wepStats.fireRate = 735" }, { "wepStats.gunLength = 3.5", "wepStats.gunLength = 2.5" }, { "wepStats.maxPushback = 0.8", "wepStats.maxPushback = 1" } })
tool("Thompson 1928", "AK-74", {
	{ 'wepStats.idleAnim = "Rifle_Idle"', 'wepStats.idleAnim = "UMP_Idle"' },
	{ 'wepStats.reloadAnim = "AK_Reload"', 'wepStats.reloadAnim = "UMP_Reload"' },
	{ 'wepStats.boltChamber = "AK_Chamber"', 'wepStats.boltChamber = "UMP_chamber"' },
	{ 'wepStats.boltClose = "AK_Close"', 'wepStats.boltClose = "UMP_Close"' },
	{ 'wepStats.rigParts = {"Mag","Bolt","ChargingHandle"}', 'wepStats.rigParts = {"Mag","Bolt"}' },
	{ "wepStats.viewmodelOffset = CFrame.new(0,0.2,-0.3)", "wepStats.viewmodelOffset = CFrame.new(0,0,-0.4)" },
})
tool("Tactical M1014", if tools:FindFirstChild("Mossberg 580") then "Mossberg 580" else "R870")
tool("M1891", "AWP")
tool("Taurus 82", "P320")
return table.concat(out, "\n")
