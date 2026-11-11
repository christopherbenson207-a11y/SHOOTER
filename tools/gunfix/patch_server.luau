local DRY = false
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
			elseif kind == "block" then
				local b = find(op[3], a)
				if not b or b - a > (op[5] or 40) then error("op " .. n .. " block end not found :: " .. op[3]) end
				put(a, b - a + 1, expand(op[4], indent))
			end
		end
	end
	return table.concat(lines, "\n")
end

local ops = {
	{ "block", "-- R15: the arms are three parts. While a gun is held the shoulder drives from the animated rig arm and the elbow and", 'rig[a[2] .. "_w"].Enabled = held', [==[-- GUNFIX 9 Nov: the GunSystem clips animate two one-piece arm proxies in the WeaponRig. On R15 the real
-- three-piece arms follow them with IK (IKControl), so the hands land where the clips put them and the elbows
-- bend. R6 keeps the original proxy welds.
local ARMS = {
>{ "Left Arm", "law", "Left", -1 },
>{ "Right Arm", "raw", "Right", 1 },
}

local function BuildArmWelds(rig, char)
>local humanoid = char:WaitForChild("Humanoid")
>if humanoid.RigType == Enum.HumanoidRigType.R6 then
>>for _, a in ARMS do
>>>local weld = weldMod.BlankWeld(rig[a[1]], char:WaitForChild(a[1]))
>>>weld.Name = a[2]
>>>weld.Enabled = false
>>>weld.Parent = rig
>>>rig[a[1]].Transparency = 1
>>end
>>return
>end
>local torso = char:WaitForChild("UpperTorso")
>for _, a in ARMS do
>>local proxy, side = rig[a[1]], a[3]
>>local upper = char:WaitForChild(side .. "UpperArm")
>>char:WaitForChild(side .. "LowerArm")
>>local hand = char:WaitForChild(side .. "Hand")
>>-- the proxy's lower end is the hand of the one-piece arm; the real hand's far edge meets it
>>local target = Instance.new("Attachment")
>>target.Name = "HandTarget"
>>target.CFrame = CFrame.new(0, -proxy.Size.Y / 2 + hand.Size.Y / 2, 0)
>>target.Parent = proxy
>>-- elbows point down and out, never up through the shoulder
>>local pole = Instance.new("Attachment")
>>pole.Name = "SPH_Pole" .. side
>>pole.CFrame = CFrame.new(a[4] * 1.7, -2, 0.8)
>>pole.Parent = torso
>>local ik = Instance.new("IKControl")
>>ik.Name = "SPH_Arm" .. side
>>ik.Type = Enum.IKControlType.Transform
>>ik.ChainRoot = upper
>>ik.EndEffector = hand
>>ik.Target = target
>>ik.Pole = pole
>>ik.SmoothTime = 0
>>ik.Enabled = false
>>ik.Parent = humanoid
>>proxy.Transparency = 1
>end
end

local function SetArms(char, rig, held)
>local humanoid = char:FindFirstChildOfClass("Humanoid")
>if not humanoid then return end
>if rig:FindFirstChild("law") then -- R6: the one-piece arms ride the proxies
>>local torso = char:FindFirstChild("Torso")
>>if torso then
>>>torso["Left Shoulder"].Enabled = not held
>>>torso["Right Shoulder"].Enabled = not held
>>end
>>rig.law.Enabled = held
>>rig.raw.Enabled = held
>>return
>end
>for _, a in ARMS do
>>local ik = humanoid:FindFirstChild("SPH_Arm" .. a[3])
>>if ik then ik.Enabled = held end]==], 70 },

	{ "before", "local function HolsterWeapon(player,holsterPart,tool,holsterCFrame)", [==[-- GUNFIX 9 Nov: where a stowed gun sits. R6 uses the gun's own settings (a part called "Torso"). R15 soldiers have
-- no such part, so nothing was ever shown: they carry long guns across the back and sidearms on the right thigh.
local function HolsterMount(character, tool, wepStats)
>local part = character:FindFirstChild(wepStats.holsterPart or "Torso")
>if part then
>>if wepStats.holster == true then return part, wepStats.holsterPosition end
>>return nil
>end
>if type(wepStats.idleAnim) == "string" and wepStats.idleAnim:find("Pistol") then
>>local leg = character:FindFirstChild("RightUpperLeg")
>>if not leg then return nil end
>>-- muzzle down, flat against the outside of the leg
>>return leg, CFrame.new(leg.Size.X / 2 + 0.14, 0.1, 0.05) * CFrame.Angles(math.rad(-90), 0, 0)
>end
>local torso = character:FindFirstChild("UpperTorso")
>if not torso then return nil end
>-- flat against the back, muzzle up over the left shoulder
>return torso, CFrame.new(0, 0.1, torso.Size.Z / 2 + 0.38) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(55), 0, 0)
end

-- A stowed gun is only for show: no weight, no collisions, nothing for bullets to catch on.
local function QuietHolster(model)
>if not model then return end
>for _, part in model:GetDescendants() do
>>if part:IsA("BasePart") then
>>>part.CanCollide, part.CanQuery, part.CanTouch, part.Massless = false, false, false, true
>>elseif part:IsA("SurfaceGui") then
>>>part.Enabled = false
>>end
>end
end
]==] },
	{ "sub", "if not assets.WeaponModels.HolsterModels:FindFirstChild(tool.Name) then", 'if holsterPart.Name ~= "Torso" or not assets.WeaponModels.HolsterModels:FindFirstChild(tool.Name) then' },
	{ "sub", "if wepStats.holster then", 'if wepStats.holster or (player.Character and player.Character:FindFirstChild("UpperTorso")) then' },
	{ "sub", "local holsterPart = player.Character:FindFirstChild(wepStats.holsterPart)", "local holsterPart, holsterCFrame = HolsterMount(player.Character, tool, wepStats)" },
	{ "sub", "HolsterWeapon(player,holsterPart,tool,wepStats.holsterPosition)", 'HolsterWeapon(player,holsterPart,tool,holsterCFrame) local stowed = player.Character:FindFirstChild("Holster_"..tool.Name) QuietHolster(stowed) if stowed then pcall(bridge.ApplyCamo, stowed, player, bridge.Key(tool)) end' },
	{ "sub", "repLean:FireToAllExcept(player,player.Character,leanDirection)", "repLean:FireToAllExcept(player,player.Character,math.clamp(tonumber(leanDirection) or 0, -1, 1))" },
}

local target = game.ServerScriptService.SPH_Server
local src = target.Source
if src:find("GUNFIX 9 Nov", 1, true) then return "already patched" end
local new = applyOps(src, ops)
local fn, err = loadstring(new)
if not fn then return "COMPILE ERROR: " .. tostring(err) end
if DRY then return "dry ok: " .. #src .. " -> " .. #new .. " chars" end
local folder = game.ServerStorage:FindFirstChild("_ScriptBackup_GunFix_9Nov") or Instance.new("Folder")
folder.Name = "_ScriptBackup_GunFix_9Nov"
folder.Parent = game.ServerStorage
if not folder:FindFirstChild("SPH_Server") then
	local keep = Instance.new("ModuleScript")
	keep.Name = "SPH_Server"
	keep.Source = src
	keep.Parent = folder
end
game:GetService("ScriptEditorService"):UpdateSourceAsync(target, function() return new end)
return "patched SPH_Server: " .. #src .. " -> " .. #target.Source .. " chars"
