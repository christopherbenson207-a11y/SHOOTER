-- GUNFIX 11 Nov g: the RPG-7 and the kill feed. Run in Multiplayer, campaign and Zombies (Edit).
--   RPG-7: GunSystem's model and rocket. Its own clips cannot load, so it is held and reloaded with the rifle clips.
--     The rocket flies on the client (GunSystem); where it lands, SPH_Server asks GearServer for a blast
--     (ServerStorage.GearApi "Blast"), so the damage is the place's own grenade blast, a little bigger.
--   Kill feed: GunSystem's layout (StarterGui.KillFeed), fed by Remotes.KillFeed from FrontServer and DuelServer.
local MARK = "GUNFIX 11 Nov g"
local RS, SS, SP, SSS = game.ReplicatedStorage, game.ServerStorage, game.StarterPlayer, game.ServerScriptService
local function rep(s, old, new, count)
	local n = 0
	local out = s:gsub(old:gsub("%p", "%%%0"), function() n += 1 return new end)
	if n ~= (count or 1) then error("hits " .. n .. " for " .. old) end
	return out
end
local RPG = [==[
-- GUNFIX 11 Nov g: the RPG-7. One rocket, a slow reload. Damage and Range here are only the direct hit the gun code
-- checks; the blast is GearServer's (ServerStorage.GearApi "Blast").
do
	local G = GameConfig.Guns
	local list = GameConfig.Arsenal or GameConfig.Loadout
	local function copy(t)
		local o = {}
		for k, v in t do
			o[k] = if type(v) == "table" then copy(v) else v
		end
		return o
	end
	if G.AK and list and not G.RPG then
		local g = copy(G.AK)
		g.DisplayName, g.Name, g.SphModel = "RPG-7", "RPG-7", "RPG-7"
		g.Category, g.Slot = "Launcher", "Primary"
		g.Role = "ONE ROCKET: MAKE THE ROOM EMPTY"
		g.FireMode = "Semi"
		g.RPM = 30
		g.MagSize = 1
		g.Reserve = 4
		g.Damage = 1
		g.Range = 3
		g.Penetration = nil
		g.ReloadTime = 3.2
		g.ReloadEmptyTime = 3.2
		g.AimTime *= 1.5
		g.MoveSpeed = (g.MoveSpeed or 1) * 0.85
		G.RPG = g
		table.insert(list, "RPG")
		local endless = GameConfig.Endless
		if endless and endless.Guns then
			table.insert(endless.Guns, { Gun = "RPG", From = 11 })
			if endless.BoxGuns then
				endless.BoxGuns.RPG = 1
			end
		end
	end
end
]==]
local jobs = {
	{ RS.Shared.GameConfig, function(s)
		local at, from = nil, 1
		while true do
			local a = s:find("\nreturn GameConfig", from, true)
			if not a then break end
			at = a
			from = a + 1
		end
		if not at then error("no return") end
		return s:sub(1, at) .. RPG .. "\nreturn GameConfig\n"
	end },
	{ RS.SPH_Assets.Modules.GunNameMap, function(s)
		return rep(s, '["Taurus 82"] = "Revolver",', '["Taurus 82"] = "Revolver",\n\t["RPG-7"] = "RPG", -- ' .. MARK)
	end },
	{ SSS.GearServer, function(s)
		s = rep(s, 'local api = Instance.new("BindableFunction")', 'local rocketBlast = nil -- ' .. MARK .. ': set below, once blast exists\nlocal api = Instance.new("BindableFunction")')
		s = rep(s, '\tif action == "Refill" then', '\tif action == "Blast" then -- a rocket landed at `slot` (a position); SPH_Server has checked it\n\t\tif rocketBlast and typeof(slot) == "Vector3" then\n\t\t\trocketBlast(player, slot)\n\t\tend\n\t\treturn true\n\telseif action == "Refill" then')
		s = rep(s, "local function rest(key, pos, normal, life)", '-- The RPG-7 rocket: the frag blast, wider and harder.\ndo\n\tlocal frag = Gear.Items.Frag\n\tif frag and frag.Hit then\n\t\tlocal rocket = table.clone(frag)\n\t\trocket.Radius = (frag.Radius or 12) * 1.3\n\t\trocket.Hit = table.clone(frag.Hit)\n\t\trocket.Hit.Damage = frag.Hit.Damage * 1.6\n\t\trocket.WorldDamage = (frag.WorldDamage or 100) * 2\n\t\trocketBlast = function(player, pos)\n\t\t\tlocal ok, err = pcall(blast, player, "Frag", rocket, pos)\n\t\t\tif not ok then\n\t\t\t\twarn("GearServer: rocket", err)\n\t\t\tend\n\t\tend\n\tend\nend\n\nlocal function rest(key, pos, normal, life)')
		return s
	end },
	{ SSS.SPH_Server, function(s)
		return rep(s, "\t\texplosionMod(raycastResult.Position, wepStats.explosionRadius, wepStats.explosionEffect)", '\t\t-- ' .. MARK .. ': the blast and its damage are the place\'s own (GearServer). One rocket every 1.5 s at most, from\n\t\t-- the launcher in the hands, within reach.\n\t\tlocal pos = raycastResult and raycastResult.Position\n\t\tlocal root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")\n\t\tbridge.RocketAt = bridge.RocketAt or {}\n\t\tlocal now = os.clock()\n\t\tif typeof(pos) == "Vector3" and root and tool.Parent == player.Character and now - (bridge.RocketAt[player] or 0) > 1.5 and (pos - root.Position).Magnitude < 1500 then\n\t\t\tbridge.RocketAt[player] = now\n\t\t\tlocal gearApi = game:GetService("ServerStorage"):FindFirstChild("GearApi")\n\t\t\tif gearApi then\n\t\t\t\tgearApi:Invoke("Blast", player, pos)\n\t\t\tend\n\t\tend')
	end },
}
local front = SSS:FindFirstChild("FrontServer")
if front then
	table.insert(jobs, { front, function(s)
		s = rep(s, "\t\taddKill(killer, PTS.Kill + (if head then PTS.Headshot else 0))", '\t\taddKill(killer, PTS.Kill + (if head then PTS.Headshot else 0))\n\t\tRemotes.KillFeed:FireAllClients(killer.DisplayName, player.DisplayName, head == true, killer.UserId, player.UserId) -- ' .. MARK)
		s = rep(s, "\t\taddKill(killer, PTS.BotKill)", '\t\taddKill(killer, PTS.BotKill)\n\t\tRemotes.KillFeed:FireAllClients(killer.DisplayName, "ENEMY SOLDIER", soldier.Model:GetAttribute("LastHitHead") == true, killer.UserId, 0)')
		return s
	end })
end
local duelServer = SSS:FindFirstChild("DuelServer")
if duelServer then
	table.insert(jobs, { duelServer, function(s)
		return rep(s, '\t\tstat(killer, "Kills").Value += 1', '\t\tstat(killer, "Kills").Value += 1\n\t\tgame:GetService("ReplicatedStorage").Remotes.KillFeed:FireAllClients(killer.DisplayName, player.DisplayName, character:GetAttribute("LastHitHead") == true, killer.UserId, player.UserId) -- ' .. MARK)
	end })
	table.insert(jobs, { RS.Shared.Duel, function(s)
		return rep(s, '\t{ Name = "MOSINS", Items = { "Mosin", "Revolver" }, Weight = 1 },', '\t{ Name = "MOSINS", Items = { "Mosin", "Revolver" }, Weight = 1 },\n\t{ Name = "ROCKETS", Items = { "RPG", "Pistol" }, Weight = 1 }, -- ' .. MARK)
	end })
end
local out, ready = {}, {}
for i, job in jobs do
	local src = job[1].Source
	if src:find(MARK, 1, true) then
		table.insert(out, job[1].Name .. ": already")
	else
		local ok, new = pcall(job[2], src)
		if not ok then return "FAILED " .. job[1].Name .. ": " .. tostring(new) end
		local fn, err = loadstring(new)
		if not fn then return "COMPILE ERROR " .. job[1].Name .. ": " .. tostring(err) end
		ready[i] = { job[1], new }
	end
end
local SES = game:GetService("ScriptEditorService")
for _, r in ready do
	SES:UpdateSourceAsync(r[1], function() return r[2] end)
	table.insert(out, r[1].Name .. " -> " .. #r[1].Source)
end
-- the Tool: the AK-74 Tool with the launcher's settings
local tools = SS.GunTools
if not tools:FindFirstChild("RPG-7") and RS.SPH_Assets.WeaponModels:FindFirstChild("RPG-7") then
	local t = tools["AK-74"]:Clone()
	t.Name = "RPG-7"
	local ws = t.SPH_Weapon.WeaponStats
	local s = ws.Source
	local function set(key, value)
		local n
		s, n = s:gsub("\nwepStats%." .. key .. "%s*=[^\n]*", function() return "\nwepStats." .. key .. " = " .. value end, 1)
		if n == 0 then
			s = rep(s, "\nreturn wepStats", "\nwepStats." .. key .. " = " .. value .. "\n\nreturn wepStats")
		end
	end
	for _, kv in {
		{ "projectile", '"Rocket"' }, { "fireRate", "100" }, { "muzzleVelocity", "300" }, { "aimSpeed", "0.2" }, { "maxPushback", "0.4" },
		{ "fireMode", "1" }, { "aimFovMin", "40" }, { "aimTime", "1" }, { "suppressionLevel", "0" }, { "tracers", "false" },
		{ "ammoType", '"Default"' }, { "shellEject", "false" }, { "magazineCapacity", "1" }, { "startAmmoPool", "4" }, { "maxAmmoPool", "4" },
		{ "bulletForce", "600" }, { "viewmodelOffset", "CFrame.new(0.45,-0.35,-1.1)" }, { "reloadAnim", '"Rifle_Reload"' },
		{ "boltChamber", '"Rifle_Chamber"' }, { "boltClose", '"Rifle_Close"' }, { "switchAnim", "nil" }, { "rigParts", '{"Rocket"}' },
		{ "fireMoveParts", "{}" }, { "boltDist", "0.2" }, { "emptyLockBolt", "false" }, { "explosiveAmmo", "true" },
		{ "explosionEffect", '"Default"' }, { "explosionRadius", "30" }, { "holster", "true" },
	} do
		set(kv[1], kv[2])
	end
	if not loadstring(s) then return table.concat(out, "\n") .. "\nRPG WeaponStats does not compile" end
	ws.Source = s
	t.Parent = tools
	table.insert(out, "tool RPG-7")
end
-- kill feed: remote, gui, client
local remotes = RS.Remotes
if not remotes:FindFirstChild("KillFeed") then
	local r = Instance.new("RemoteEvent")
	r.Name = "KillFeed"
	r.Parent = remotes
end
if not game.StarterGui:FindFirstChild("KillFeed") then
	local gui = Instance.new("ScreenGui")
	gui.Name = "KillFeed"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.1, 0.6)
	holder.Size = UDim2.fromScale(0.175, 0.325)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 0.6787)
	list.BackgroundTransparency = 1
	list.Parent = holder
	local layout = Instance.new("UIListLayout")
	layout.Name = "UIList"
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0.02, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local template = Instance.new("Frame")
	template.Name = "Template"
	template.Size = UDim2.fromScale(1.8025, 0.1352)
	template.BackgroundTransparency = 1
	template.Visible = false
	template.Parent = holder
	local function label(name, x, text, color, family, style)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Position = UDim2.fromScale(x, 0)
		l.Size = UDim2.fromScale(0.33, 1)
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.6
		l.FontFace = Font.new(family, Enum.FontWeight.Bold, style or Enum.FontStyle.Normal)
		l.Parent = template
	end
	label("Killer", 0, "Player", Color3.new(1, 1, 1), "rbxasset://fonts/families/GothamSSm.json")
	label("Action", 0.33, "killed", Color3.fromRGB(230, 60, 60), "rbxasset://fonts/families/GothamSSm.json", Enum.FontStyle.Italic)
	label("Victim", 0.67, "Player", Color3.new(1, 1, 1), "rbxasset://fonts/families/GothamSSm.json")
	gui.Parent = game.StarterGui
	table.insert(out, "KillFeed gui")
end
local sps = SP.StarterPlayerScripts
if not sps:FindFirstChild("KillFeedClient") then
	local c = Instance.new("LocalScript")
	c.Name = "KillFeedClient"
	c.Source = [==[
-- GUNFIX 11 Nov g: the kill feed (GunSystem's layout, StarterGui.KillFeed). Rows come from Remotes.KillFeed:
-- (killer name, victim name, headshot, killer user id, victim user id). Your own name shows amber. A row stays 7 s,
-- five rows at most.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local feed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("KillFeed")
local gui = player:WaitForChild("PlayerGui"):WaitForChild("KillFeed")
local holder = gui:WaitForChild("Holder")
local template = holder:WaitForChild("Template")
local list = holder:WaitForChild("List")

local MINE = Color3.fromRGB(255, 190, 70)
local MAX_ROWS = 5
local LIFE = 7
local order = 0

feed.OnClientEvent:Connect(function(killer, victim, headshot, killerId, victimId)
	if type(killer) ~= "string" or type(victim) ~= "string" then
		return
	end
	local rows = {}
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #rows >= MAX_ROWS do
		table.remove(rows, 1):Destroy()
	end
	order += 1
	local row = template:Clone()
	row.Name = "Message"
	row.LayoutOrder = order
	row.Killer.Text = killer
	row.Victim.Text = victim
	row.Action.Text = if headshot then "headshot" else "killed"
	if killerId == player.UserId then
		row.Killer.TextColor3 = MINE
	end
	if victimId == player.UserId then
		row.Victim.TextColor3 = MINE
	end
	row.Visible = true
	row.Parent = list
	Debris:AddItem(row, LIFE)
end)
]==]
	c.Parent = sps
	table.insert(out, "KillFeedClient")
end
return table.concat(out, "\n")
