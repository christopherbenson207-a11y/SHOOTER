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

local RS, SP = game.ReplicatedStorage, game.StarterPlayer
local jobs = {}

jobs[1] = { SP.StarterCharacterScripts.SPH_Character.CharacterClient, {
	{ "after", "local dryClicked, sprintBlockUntil, aimStart, thirdView, thirdWasActive, touchAimed = false, 0, 0, false, false, false", [==[-- GUNFIX 9 Nov: state for the aim latch, lean and third-person camera (one table: this script is near Luau's local limit)
local GF = { aimLatched = false, aimPressAt = nil, aimDroppedAt = -math.huge, firePressAt = -math.huge, AIM_TAP = 0.2, AIM_DROP_WINDOW = 0.05, thirdDist = 6.5, leanHeld = {}, leanX = 0, idleName = nil }]==] },
	{ "sub", "thirdView, thirdWasActive, touchAimed = false, 0, 0, false, false, false", 'thirdView, thirdWasActive, touchAimed = false, 0, 0, player:GetAttribute("GunFeelThird") == true, false, false' },
	{ "before", "local crouchIdleAnim:AnimationTrack = humanoid.Animator:LoadAnimation(assets.Animations.Crouch_Idle)", [==[-- GUNFIX: the stance clips are R6 clips owned by another account; they only load where the GunSystem stances are on
GF.Track = function(name)
>if config.canCrouch and isR6 then return humanoid.Animator:LoadAnimation(assets.Animations[name]) end
>return setmetatable({}, { __index = function() return function() end end })
end]==] },
	{ "sub", "humanoid.Animator:LoadAnimation(assets.Animations.Crouch_Idle)", 'GF.Track("Crouch_Idle")' },
	{ "sub", "humanoid.Animator:LoadAnimation(assets.Animations.Crouch_Move)", 'GF.Track("Crouch_Move")' },
	{ "sub", "humanoid.Animator:LoadAnimation(assets.Animations.Prone_Idle)", 'GF.Track("Prone_Idle")' },
	{ "sub", "humanoid.Animator:LoadAnimation(assets.Animations.Prone_Move)", 'GF.Track("Prone_Move")' },
	{ "after", "lean = newLean", "if not isR6 then bridge.SetLean(character, newLean) end" },
	{ "after", "local function IdleAnim()", [==[>if GF.idleName and GF.idleName ~= wepStats.idleAnim then StopAnimation(GF.idleName) end -- GUNFIX: one hold pose at a time
>GF.idleName = wepStats.idleAnim]==] },
	{ "before", "if firstPerson then viewmodelVisible = true end", "if not equipped or not wepStats then return end -- GUNFIX: put away during the wait" },
	{ "before", "humanoid.Died:Connect(function()", [==[-- GUNFIX 9 Nov ----------------------------------------------------------------------------------------------
GF.DropAim = function()
>GF.aimLatched = false
>GF.aimPressAt = nil
>aimHeld = false
>if aiming then ToggleAiming(false) end
end

-- The sights come up in the gun's own AimTime (GameConfig), whatever the frame rate.
GF.AimRate = function(dt)
>local t = (gunCfg and gunCfg.AimTime) or 0.25
>return 1 - math.exp(-dt * 4.5 / math.max(t, 0.05))
end

-- Lean: hold the key to lean out, let go to come back. A use prompt on screen takes the press instead.
GF.LeanInput = function(actionName, inputState, inputObject)
>local dir = if actionName == "SPH_LeanLeft" then -1 else 1
>if inputState == Enum.UserInputState.Begin then
>>if inputObject and Controls.PromptTakes(inputObject) then return Enum.ContextActionResult.Pass end
>>if not equipped or dead or sprinting or humanoid.Sit or bridge.ViewBlocked(player, character) then return Enum.ContextActionResult.Pass end
>>GF.leanHeld[dir] = true
>>ChangeLean(dir)
>elseif GF.leanHeld[dir] then
>>GF.leanHeld[dir] = nil
>>ChangeLean(if GF.leanHeld[-dir] then -dir else 0)
>end
>return Enum.ContextActionResult.Pass
end
]==] },
	{ "sub", "aimingOffset = aimingOffset:Lerp(aimTarget,(0.7 / wepStats.aimTime) * 0.3 * dt * 60)", "aimingOffset = aimingOffset:Lerp(aimTarget,GF.AimRate(dt))" },
	{ "sub", "aimingOffset = aimingOffset:Lerp(CFrame.new(),(0.7 / wepStats.aimTime) * 0.3 * dt * 60)", "aimingOffset = aimingOffset:Lerp(CFrame.new(),GF.AimRate(dt))" },
	{ "after", "sprintHeld = inputState == inputBegan", "if sprintHeld and GF.aimLatched and not (gunCfg and gunCfg.Scope) then GF.DropAim() end" },
	{ "after", "dryClicked = false", [==[GF.firePressAt = tick()
if tick() - GF.aimDroppedAt < GF.AIM_DROP_WINDOW and not aiming and not blocked then -- the aim release came a moment before this shot
>GF.aimLatched = true
>aimHeld = true
>ToggleAiming(true)
end]==] },
	{ "block", 'elseif actionName == "SPH_HoldAim" then -- Hold aiming', "if aiming then ToggleAiming(false) end", [==[elseif actionName == "SPH_HoldAim" then -- GUNFIX: hold to aim; a quick tap keeps the sights up until the next press
>if inputState == inputBegan then
>>if character:GetAttribute("GearReady") then return Enum.ContextActionResult.Pass end
>>if GF.aimLatched then
>>>GF.DropAim()
>>elseif not freeLook then
>>>GF.aimPressAt = tick()
>>>aimHeld = true
>>>ToggleSprint(false)
>>>if not blocked and not aiming then ToggleAiming(true) end
>>end
>elseif inputState == inputEnded and GF.aimPressAt then
>>-- Some mice report right-button-up the instant left goes down: a release that lands with a shot keeps the aim.
>>local pressAt = GF.aimPressAt
>>GF.aimPressAt = nil
>>if tick() - GF.firePressAt < GF.AIM_DROP_WINDOW or tick() - pressAt < GF.AIM_TAP then
>>>GF.aimLatched = true
>>else
>>>GF.DropAim()
>>>GF.aimDroppedAt = tick()
>>end]==] },
	{ "before", "-- Stop animations", [==[GF.aimLatched, GF.aimPressAt = false, nil
aimHeld = false
GF.leanHeld = {}
if lean ~= 0 then ChangeLean(0) end
]==] },
	{ "block", "EquipAnim()", 'gunAmmo = newChild:WaitForChild("Ammo")', [==[EquipAnim()
if equipped ~= newChild then return end -- GUNFIX: swapped again while the equip clip started
IdleAnim()

local ammoFolder = newChild:WaitForChild("Ammo", 5)
if equipped ~= newChild or not ammoFolder then return end
gunAmmo = ammoFolder]==] },
	{ "block", "if thirdActive then", "camera.CFrame = (view - view.Position) + from + gap * reach", [==[if thirdActive then
>-- GUNFIX: over the right shoulder. The shoulder offset and the distance are checked against walls separately,
>-- so backing into a wall brings the camera closer without sliding it onto the character's back.
>local view = camera.CFrame
>local rot = view - view.Position
>local head = character.Head.Position
>local side = rot.RightVector * 1.7 + rot.UpVector * 0.55
>local hitSide = workspace:Spherecast(head, 0.35, side, rayParams)
>local pivot = head + side * (if hitSide then math.max(hitSide.Distance - 0.15, 0) / side.Magnitude else 1)
>local hitBack = workspace:Spherecast(pivot, 0.35, rot.LookVector * -6.5, rayParams)
>local want = if hitBack then math.max(hitBack.Distance - 0.15, 0.8) else 6.5
>GF.thirdDist = if want < GF.thirdDist then want else GF.thirdDist + (want - GF.thirdDist) * math.min(dt * 6, 1)
>camera.CFrame = rot + (pivot - rot.LookVector * GF.thirdDist)]==] },
	{ "before", "cameraLeanRotation = LerpNumber(cameraLeanRotation,15 * -lean, 0.1)", [==[if not isR6 then -- GUNFIX: R15 leans the view sideways here (R6 does it through the root joint)
>GF.leanX += (xOffset * 0.95 - GF.leanX) * math.min(dt * 10, 1)
>if math.abs(GF.leanX) > 0.01 then
>>local hitLean = workspace:Spherecast(camera.CFrame.Position, 0.3, camera.CFrame.RightVector * GF.leanX, rayParams)
>>local shift = if hitLean then math.sign(GF.leanX) * math.max(hitLean.Distance - 0.1, 0) else GF.leanX
>>camera.CFrame *= CFrame.new(shift, -0.12 * math.abs(shift), 0)
>end
end]==] },
	{ "before", "if wantSprint ~= (sprinting == true) then", "if wantSprint and lean ~= 0 then GF.leanHeld = {} ChangeLean(0) end" },
	{ "after", 'Controls.Bind("SPH_Reload", "Reload", HandleInput, config.gunInputPriority)', [==[if config.canLean then
>Controls.Bind("SPH_LeanLeft", "LeanLeft", GF.LeanInput, config.gunInputPriority)
>Controls.Bind("SPH_LeanRight", "LeanRight", GF.LeanInput, config.gunInputPriority)
end]==] },
	{ "sub", "Enum.KeyCode.V, Enum.KeyCode.ButtonR3)", "Enum.KeyCode.V)" },
	{ "sub", 'Controls.Unbind("SPH_Reload")', 'Controls.Unbind("SPH_Reload") Controls.Unbind("SPH_LeanLeft") Controls.Unbind("SPH_LeanRight")', 2 },
	{ "sub", '{ "SPH_Trigger", "SPH_HoldAim", "SPH_Reload" }', '{ "SPH_Trigger", "SPH_HoldAim", "SPH_Reload", "SPH_LeanLeft", "SPH_LeanRight" }' },
	{ "after", "thirdView = not thirdView", 'player:SetAttribute("GunFeelThird", thirdView)' },
	{ "after", "bridge.SetNeck(character, nil)", [==[GF.leanHeld = {}
if lean ~= 0 and not dead then ChangeLean(0) end]==] },
	{ "sub", "local tempSpread = wepStats.spread * 100", "local tempSpread = math.floor(wepStats.spread * 100 + 0.5)" },
	{ "sub", 'if touchAimed then touchAimed = false HandleInput("SPH_HoldAim", End) end', "if touchAimed then touchAimed = false GF.DropAim() end", 2 },
	{ "sub", 'HandleInput("SPH_HoldAim", if aiming then End else Begin)', 'if aiming or aimHeld then GF.DropAim() else HandleInput("SPH_HoldAim", Begin) GF.aimPressAt = nil GF.aimLatched = true end' },
} }

jobs[2] = { RS.SPH_Assets.Modules.GunBridge, {
	{ "before", "function Bridge.StandUp(player)", [==[-- GUNFIX 9 Nov: lean. The upper body tips at the waist on top of whatever clip is playing (written after the
-- Animator, like SetNeck). dir is -1 (left), 0 or 1 (right).
local leans = {}
local leanStep = nil

function Bridge.SetLean(character, dir)
>local entry = leans[character]
>if not entry then
>>if dir == 0 then return end
>>local upper = character:FindFirstChild("UpperTorso")
>>local waist = upper and upper:FindFirstChild("Waist")
>>if not waist then return end
>>entry = { Joint = waist, Current = 0, Target = 0 }
>>leans[character] = entry
>end
>entry.Target = dir
>if leanStep then return end
>leanStep = RunService.PreSimulation:Connect(function(dt)
>>for model, e in leans do
>>>if model.Parent == nil or e.Joint.Parent == nil then
>>>>leans[model] = nil
>>>else
>>>>e.Current += (e.Target - e.Current) * (1 - math.exp(-9 * dt))
>>>>local base = e.Joint.Transform
>>>>if e.Wrote and base == e.Wrote then base = e.Base end -- no clip rewrote the joint this frame
>>>>if e.Target == 0 and math.abs(e.Current) < 0.01 then
>>>>>e.Joint.Transform = base
>>>>>leans[model] = nil
>>>>else
>>>>>e.Base = base
>>>>>e.Wrote = base * CFrame.new(0.35 * e.Current, -0.05 * math.abs(e.Current), 0) * CFrame.Angles(0, 0, math.rad(-20 * e.Current))
>>>>>e.Joint.Transform = e.Wrote
>>>>end
>>>end
>>end
>end)
end
]==] },
} }

jobs[3] = { SP.StarterPlayerScripts.SPH_Player.PlayerClient, {
	{ "after", 'if not character:FindFirstChild("HumanoidRootPart") then return end', 'if character:FindFirstChild("UpperTorso") then bridge.SetLean(character, leanDirection) return end -- GUNFIX 9 Nov: R15 lean' },
} }

jobs[4] = { RS.SPH_Assets.GameConfig, {
	{ "sub", "config.canLean = false", "config.canLean = true --[[ GUNFIX 9 Nov ]]" },
} }

jobs[5] = { RS.Shared.Controls, {
	{ "sub", 'Kb = { K.Q, K.T }, Pad = { K.ButtonL1 }, Requires = "Gear" },', 'Kb = { K.T }, Pad = { K.ButtonL1 }, Requires = "Gear" },' },
	{ "after", '{ Name = "Bandage", Label = "Bandage", Kb = { K.H }, Pad = { K.DPadDown } },', [==[-- GUNFIX 9 Nov: lean out of cover (GunSystem). E is shared with use prompts and getting up: those take the press.
{ Name = "LeanLeft", Label = "Lean left", Kb = { K.Q }, Pad = {} },
{ Name = "LeanRight", Label = "Lean right", Kb = { K.E }, Pad = {} },]==] },
	{ "sub", "Interact = { Reload = true, Revive = true },", "Interact = { Reload = true, Revive = true, LeanRight = true },\n\tLeanRight = { Interact = true, Revive = true }," },
	{ "sub", "Revive = { Crouch = true, Interact = true },", "Revive = { Crouch = true, Interact = true, LeanRight = true }," },
} }

local out = {}
local folder = game.ServerStorage:FindFirstChild("_ScriptBackup_GunFix_9Nov") or Instance.new("Folder")
folder.Name = "_ScriptBackup_GunFix_9Nov"
folder.Parent = game.ServerStorage
local SES = game:GetService("ScriptEditorService")
-- everything is checked before anything is written
local ready = {}
for i, job in jobs do
	local target, ops = job[1], job[2]
	local src = target.Source
	if src:find("GUNFIX", 1, true) then
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
