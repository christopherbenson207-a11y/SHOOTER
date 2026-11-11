-- GUNFIX 11 Nov 2026: the GunSystem Medkit on the place's bandage job, slow walk and green motes while healing,
-- and the semi/auto fire mode switch. Run in Multiplayer, campaign and Zombies (Edit). Everything is checked and
-- compiled before anything is written; old sources go to ServerStorage._ScriptBackup_GunFix_11Nov.
local MARK = "GUNFIX 11 Nov"
local function applyOps(src, ops)
	src = src:gsub("\r\n", "\n")
	local lines = src:split("\n")
	local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	local function find(text, from)
		for i = from or 1, #lines do
			if trim(lines[i]) == text then return i end
		end
		return nil
	end
	local function countOf(text)
		local n = 0
		for i = 1, #lines do if trim(lines[i]) == text then n += 1 end end
		return n
	end
	local function expand(text, indent)
		local out = {}
		for _, line in text:split("\n") do
			local marks, rest = line:match("^(>*)(.*)$")
			table.insert(out, if rest == "" then "" else indent .. string.rep("\t", #marks) .. rest)
		end
		return out
	end
	local function put(at, removeCount, new)
		for _ = 1, removeCount do table.remove(lines, at) end
		for k = #new, 1, -1 do table.insert(lines, at, new[k]) end
	end
	for n, op in ops do
		local kind = op[1]
		if kind == "sub" then
			local hits = 0
			for i = 1, #lines do
				local s, e = lines[i]:find(op[2], 1, true)
				if s then
					lines[i] = lines[i]:sub(1, s - 1) .. op[3] .. lines[i]:sub(e + 1)
					hits += 1
				end
			end
			if hits ~= (op[4] or 1) then error("op " .. n .. " sub hits=" .. hits .. " :: " .. op[2]) end
		else
			local c = countOf(op[2])
			if c ~= 1 then error("op " .. n .. " anchor count=" .. c .. " :: " .. op[2]) end
			local a = find(op[2])
			local indent = lines[a]:match("^%s*")
			if kind == "after" then
				put(a + 1, 0, expand(op[3], indent))
			elseif kind == "before" then
				put(a, 0, expand(op[3], indent))
			end
		end
	end
	return table.concat(lines, "\n")
end

local RS, SP, SS = game.ReplicatedStorage, game.StarterPlayer, game.ServerStorage
-- A life starts with this many medkits: none in a duel (kits there are meant to be even).
local START = if game.PlaceId == 75051098491738 then 0 else 1
local jobs = {}

jobs[1] = { RS.Shared.GameConfig, {
	{ "after", "GameConfig.Bandages = {", ">-- " .. MARK .. [==[: the GunSystem Medkit. It rides the bandage job: ApplyTime seconds, heals Heal, closes every open
>-- wound. A life starts with Start, you carry at most Max. The Bandage key picks it by itself when you are missing
>-- UseBelow health or more (or have no bandage). HealWalkSpeed: how fast you walk while a bandage or medkit goes on.
>Medkit = { ApplyTime = 3.3, Heal = 60, Start = ]==] .. START .. [==[, Max = 2, UseBelow = 50 },
>HealWalkSpeed = 7,]==] },
} }

jobs[2] = { SS.Modules.Bandages, {
	{ "after", "local CFG = GameConfig.Bandages", "-- " .. MARK .. [==[: the GunSystem Medkit (Remotes.Bandage:FireServer("Medkit")), carried as the player attribute "Medkits".
local MED = CFG.Medkit or { ApplyTime = 3.3, Heal = 60, Start = 0, Max = 2 }
local function medkits(player)
>return player:GetAttribute("Medkits") or 0
end
local function takeMedkit(player)
>if medkits(player) <= 0 then return false end
>player:SetAttribute("Medkits", medkits(player) - 1)
>return true
end
-- Green motes round whoever is healing, for everyone to see.
local function healGlow(character, on)
>local root = character:FindFirstChild("HumanoidRootPart")
>local old = root and root:FindFirstChild("HealGlow")
>if old then old:Destroy() end
>if not on or not root then return end
>local holder = Instance.new("Attachment")
>holder.Name = "HealGlow"
>local motes = Instance.new("ParticleEmitter")
>motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
>motes.Color = ColorSequence.new(Color3.fromRGB(64, 255, 64))
>motes.LightEmission = 0.6
>motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
>motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
>motes.Lifetime = NumberRange.new(0.8, 1.3)
>motes.Rate = 14
>motes.Speed = NumberRange.new(1.5, 3)
>motes.SpreadAngle = Vector2.new(180, 180)
>motes.Acceleration = Vector3.new(0, 3, 0)
>motes.Parent = holder
>holder.Parent = root
end]==] },
	{ "sub", "count(player) <= 0 then", '(if action == "Medkit" then medkits(player) else count(player)) <= 0 then' },
	{ "before", 'character:SetAttribute("Bandaging", true)', [==[local med = action == "Medkit"
local applyTime = if med then MED.ApplyTime else CFG.ApplyTime]==] },
	{ "sub", "workspace:GetServerTimeNow() + CFG.ApplyTime)", "workspace:GetServerTimeNow() + applyTime)" },
	{ "after", 'character:SetAttribute("BandagePart", wound.Part)', [==[character:SetAttribute("HealTime", applyTime)
healGlow(character, true)]==] },
	{ "sub", "task.delay(CFG.ApplyTime, function()", "task.delay(applyTime, function()" },
	{ "sub", 'not Inventory.Take(player, "Bandage", 1)', 'not (if med then takeMedkit(player) else Inventory.Take(player, "Bandage", 1))' },
	{ "after", "local open = wounds[character]", "if med and open then table.clear(open) end -- a medkit closes every wound" },
	{ "sub", "humanoid.Health + CFG.Heal", "humanoid.Health + (if med then MED.Heal else CFG.Heal)" },
	{ "after", 'character:SetAttribute("BandagePart", nil)', [==[character:SetAttribute("HealTime", nil)
healGlow(character, false)]==] },
	{ "after", 'character:SetAttribute("Trauma", 0)', [==[local owner = Players:GetPlayerFromCharacter(character)
if owner then owner:SetAttribute("Medkits", MED.Start or 0) end]==] },
	{ "before", "function Bandages.Start()", [==[-- Hands the player n medkits (a pickup, a shop, a reward). Returns how many fitted.
function Bandages.GiveMedkit(player, n)
>local have = medkits(player)
>local add = math.clamp(n or 1, 0, (MED.Max or 2) - have)
>if add > 0 then player:SetAttribute("Medkits", have + add) end
>return add
end
]==] },
} }

jobs[3] = { SP.StarterPlayerScripts.Hotbar, {
	{ "before", "local function useBandage()", "-- " .. MARK .. [==[: the Medkit shares the Bandage key. It is used when you carry one and are missing a lot of
-- health (GameConfig.Bandages.Medkit.UseBelow), or have no bandage left.
local function medkits()
>return player:GetAttribute("Medkits") or 0
end
local function medText(item)
>return if item == "Bandage" and medkits() > 0 then " +" .. medkits() else ""
end
local function wantsMedkit()
>local character = player.Character
>local humanoid = character and character:FindFirstChildOfClass("Humanoid")
>if medkits() <= 0 or not humanoid or character:GetAttribute("Bandaging") or character:GetAttribute("Downed") then
>>return false
>end
>local missing = humanoid.MaxHealth - humanoid.Health
>local hasBandage = string.find("|" .. (player:GetAttribute("Inventory") or ""), "|Bandage:", 1, true) ~= nil
>local med = GameConfig.Bandages.Medkit
>return missing >= (med and med.UseBelow or 50) or (not hasBandage and missing > 0)
end
]==] },
	{ "after", "local function useBandage()", '>if wantsMedkit() then Remotes.Bandage:FireServer("Medkit") return end' },
	{ "sub", 'then "x" .. content.Count else ""', 'then "x" .. content.Count .. medText(item) else ""' },
	{ "sub", "/ GameConfig.Bandages.ApplyTime", '/ ((character and character:GetAttribute("HealTime")) or GameConfig.Bandages.ApplyTime)' },
	{ "after", 'player:GetAttributeChangedSignal("Inventory"):Connect(refresh)', 'player:GetAttributeChangedSignal("Medkits"):Connect(function() if #slots > 0 then refresh() end end)' },
} }

jobs[4] = { SP.StarterPlayerScripts.BandageView, {
	{ "sub", "/ Settings.ApplyTime", '/ ((character and character:GetAttribute("HealTime")) or Settings.ApplyTime) --[[ ' .. MARK .. " ]]" },
} }

jobs[5] = { RS.SPH_Assets.Modules.GunBridge, {
	{ "before", "local mult = if sprinting then gun.SprintMult or gun.MoveSpeed or 1 else gun.MoveSpeed or 1", "if flag(character, \"Bandaging\") then -- " .. MARK .. [==[: healing slows you (GunSystem)
>base = math.min(base, (GameConfig.Bandages and GameConfig.Bandages.HealWalkSpeed) or 7)
end]==] },
	{ "sub", "stats.fireSwitch = { mode == 1, mode == 2, mode == 3, mode == 4 }", "stats.fireSwitch = { mode == 1 or mode == 2, mode == 2, mode == 3, mode == 4 } -- an automatic can be set to single shots" },
} }

jobs[6] = { SP.StarterCharacterScripts.SPH_Character.CharacterClient, {
	{ "before", "local function BindGunInputs() -- Keys follow the player's own bindings (Shared.Controls)", "-- " .. MARK .. [==[: single shots or automatic, on guns that have both.
GF.FireMode = function(actionName, inputState, inputObject)
>if inputState ~= Enum.UserInputState.Begin or not equipped or not wepStats then return Enum.ContextActionResult.Pass end
>local modes = 0
>for _, on in wepStats.fireSwitch do
>>if on then modes += 1 end
>end
>if modes < 2 then return Enum.ContextActionResult.Pass end
>return HandleInput("SPH_SwitchFireMode", inputState, inputObject)
end
]==] },
	{ "after", 'Controls.Bind("SPH_Reload", "Reload", HandleInput, config.gunInputPriority)', 'Controls.Bind("SPH_FireMode", "FireMode", GF.FireMode, config.gunInputPriority)' },
	{ "sub", 'Controls.Unbind("SPH_LeanRight")', 'Controls.Unbind("SPH_LeanRight") Controls.Unbind("SPH_FireMode")', 2 },
	{ "sub", '"SPH_LeanLeft", "SPH_LeanRight" }', '"SPH_LeanLeft", "SPH_LeanRight", "SPH_FireMode" }' },
	{ "sub", "if curFireMode > 4 then curFireMode = 0 break end", "if curFireMode > 4 then curFireMode = 0 end -- wraps round without stopping on the safety" },
} }

jobs[7] = { RS.Shared.Controls, {
	{ "after", '{ Name = "LeanRight", Label = "Lean right", Kb = { K.E }, Pad = {} },', "-- " .. MARK .. [==[: single shots or automatic (GunSystem), on guns that have both.
{ Name = "FireMode", Label = "Fire mode", Kb = { K.N }, Pad = {} },]==] },
} }

local out = {}
local folder = SS:FindFirstChild("_ScriptBackup_GunFix_11Nov") or Instance.new("Folder")
folder.Name = "_ScriptBackup_GunFix_11Nov"
folder.Parent = SS
local SES = game:GetService("ScriptEditorService")
local ready = {}
for i, job in jobs do
	local target, ops = job[1], job[2]
	local src = target.Source
	if src:find(MARK, 1, true) then
		table.insert(out, target.Name .. ": already patched")
	else
		local ok, new = pcall(applyOps, src, ops)
		if not ok then return "FAILED " .. target.Name .. ": " .. tostring(new) end
		local fn, err = loadstring(new)
		if not fn then return "COMPILE ERROR " .. target.Name .. ": " .. tostring(err) end
		ready[i] = { target, src, new }
	end
end
for _, r in ready do
	local target, src, new = r[1], r[2], r[3]
	if not folder:FindFirstChild(target.Name) then
		local keep = Instance.new("ModuleScript")
		keep.Name = target.Name
		keep.Source = src
		keep.Parent = folder
	end
	SES:UpdateSourceAsync(target, function() return new end)
	table.insert(out, target.Name .. ": " .. #src .. " -> " .. #target.Source)
end
return table.concat(out, "\n")
