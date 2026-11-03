-- What each client does to the Endless world for its own player:
--   Zombies: the server's R6 blocks are posed here (no animation assets): arms reaching out, legs
--     walking with their speed, the swipe (model attribute SwingAt), the crawl (Crawling).
--   Blood is green (owner rule): drops on every hit (Fx "Blood"), a burst when a limb tears ("Gib").
--   Power-ups spin, bob and blink out; house lamps flicker until the power is on.
--   Prompts are worded for you: a wall gun you carry offers ammo, a perk shows your price (alone,
--     Lazarus Draught is cheaper), the altar names the gun in your hands and its cost, you never see
--     your own Revive prompt and Lazarus Draught halves the hold on others', sigils you can't take
--     (another player's altar boosts, a relic once you've picked this round's) go dark.
--   Screen: a red flash when hit, grey and red while down. Dead, you watch a standing teammate.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Endless = ReplicatedStorage:WaitForChild("Endless")
local Config = require(Endless:WaitForChild("Config"))
local Weapons = require(Endless:WaitForChild("Weapons"))
local Net = require(Endless:WaitForChild("Net"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local fxFolder = workspace:WaitForChild("Fx")
local ATTACK = Config.Zombie.Attack
local BLOOD = Config.Zombie.Blood

-- Zombies ---------------------------------------------------------------------------------------

local rigs = setmetatable({}, { __mode = "k" }) -- [model] = {joints, last, phase, speed}

local function rigOf(model)
	local r = rigs[model]
	if r then
		return r
	end
	local torso = model:FindFirstChild("Torso")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not torso or not root then
		return nil
	end
	r = {
		RS = torso:FindFirstChild("Right Shoulder"),
		LS = torso:FindFirstChild("Left Shoulder"),
		RH = torso:FindFirstChild("Right Hip"),
		LH = torso:FindFirstChild("Left Hip"),
		Neck = torso:FindFirstChild("Neck"),
		Root = root:FindFirstChild("RootJoint"),
		RootPart = root,
		Last = root.Position,
		Phase = math.random() * 6,
		Speed = 0,
		Offset = math.random() * 10,
	}
	rigs[model] = r
	return r
end

local function set(joint, cf)
	if joint and joint.Parent then
		joint.Transform = cf
	end
end

local function poseZombie(model, dt, now, serverNow)
	local r = rigOf(model)
	if not r then
		return
	end
	local pos = r.RootPart.Position
	local moved = Vector3.new(pos.X - r.Last.X, 0, pos.Z - r.Last.Z).Magnitude
	r.Last = pos
	r.Speed += (moved / math.max(dt, 1e-3) - r.Speed) * math.min(1, dt * 8)
	r.Phase += dt * (1.5 + r.Speed * 0.55)
	local crawling = model:GetAttribute("Crawling") == true
	local runner = model:GetAttribute("Kind") == "Runner"
	local stride = math.clamp(r.Speed / 12, 0, 1)

	-- Arms reach out, and the swipe: up through the windup, down hard on the swing.
	local arm = 1.45 + 0.08 * math.sin(now * 2 + r.Offset)
	local swingAt = model:GetAttribute("SwingAt")
	if swingAt then
		local t = serverNow - swingAt
		if t >= 0 and t < ATTACK.Windup then
			arm = 1.45 + 0.95 * (t / ATTACK.Windup)
		elseif t >= ATTACK.Windup and t < ATTACK.Windup + ATTACK.Swing then
			arm = 2.4 - 1.9 * ((t - ATTACK.Windup) / ATTACK.Swing)
		elseif t >= ATTACK.Windup + ATTACK.Swing and t < ATTACK.Windup + ATTACK.Swing + 0.35 then
			arm = 0.5 + 0.95 * ((t - ATTACK.Windup - ATTACK.Swing) / 0.35)
		end
	end
	if crawling then
		-- Dragging itself on its arms, the body flat to the floor.
		local pull = 0.5 * math.sin(r.Phase * 1.3)
		set(r.RS, CFrame.Angles(0, 0, arm + pull))
		set(r.LS, CFrame.Angles(0, 0, -(arm - pull)))
		set(r.RH, CFrame.Angles(0, 0, -0.2))
		set(r.LH, CFrame.Angles(0, 0, 0.2))
		set(r.Root, CFrame.new(0, 0, -1.9) * CFrame.Angles(math.rad(78), 0, 0))
		set(r.Neck, CFrame.Angles(math.rad(-50), 0, 0.1 * math.sin(now + r.Offset)))
		return
	end
	local swing = 0.7 * stride * math.sin(r.Phase)
	set(r.RS, CFrame.Angles(0, 0, arm + 0.12 * swing))
	set(r.LS, CFrame.Angles(0, 0, -arm + 0.12 * swing))
	set(r.RH, CFrame.Angles(0, 0, -swing))
	set(r.LH, CFrame.Angles(0, 0, -swing))
	set(r.Root, CFrame.Angles(math.rad(if runner then 16 else 7), 0, 0.06 * math.sin(r.Phase * 0.5)))
	set(r.Neck, CFrame.Angles(0.12 * math.sin(now * 0.8 + r.Offset), 0, 0.25 + 0.1 * math.sin(now * 0.5 + r.Offset)))
end

-- Blood (green) ---------------------------------------------------------------------------------

local function drops(at: Vector3, dir: Vector3, n: number, size: number)
	for _ = 1, n do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * size * (0.6 + math.random() * 0.8)
		p.Color = BLOOD:Lerp(Color3.new(0, 0, 0), math.random() * 0.35)
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Position = at
		p.Parent = fxFolder
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 16
		p.AssemblyLinearVelocity = dir * 10 + spread
		Debris:AddItem(p, 0.6)
	end
end

-- Power-ups ----------------------------------------------------------------------------------------

local dropBase = setmetatable({}, { __mode = "k" }) -- [model] = {center, {part = cframe}}

local function animateDrop(model, now, serverNow)
	local d = dropBase[model]
	if not d then
		local parts = {}
		local sum, n = Vector3.zero, 0
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				parts[p] = p.CFrame
				sum += p.Position
				n += 1
			end
		end
		if n == 0 then
			return
		end
		d = { Center = sum / n, Parts = parts }
		dropBase[model] = d
	end
	local turn = CFrame.new(d.Center + Vector3.new(0, 0.35 * math.sin(now * 3), 0)) * CFrame.Angles(0, now * 2, 0) * CFrame.new(-d.Center)
	local left = (model:GetAttribute("ExpiresAt") or math.huge) - serverNow
	local hidden = left < Config.PowerUps.Blink and math.floor(left * 4) % 2 == 0
	for p, base in d.Parts do
		if p.Parent then
			p.CFrame = turn * base
			p.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- Lamps flicker until the power is on ---------------------------------------------------------------

local function flickerLamps(now)
	if workspace:GetAttribute("Power") == true then
		return
	end
	local house = workspace:FindFirstChild("House")
	local lamps = house and house:FindFirstChild("Lamps")
	if not lamps then
		return
	end
	local off = Config.House.Lamps.Off
	for i, lamp in lamps:GetChildren() do
		local light = lamp:FindFirstChildOfClass("PointLight")
		if light then
			local n = math.noise(now * 3, i * 1.7)
			light.Brightness = if n < -0.35 then 0.05 else off.Brightness * (0.75 + n * 0.5)
		end
	end
end

-- Prompts worded for this player -------------------------------------------------------------------

local function myTools()
	local list = {}
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("Weapon") then
					list[t:GetAttribute("Weapon")] = t
				end
			end
		end
	end
	return list
end

local function inRunCount()
	local n = 0
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InRun") then
			n += 1
		end
	end
	return n
end

local function wordPrompt(prompt: ProximityPrompt, owned)
	local weapon = prompt:GetAttribute("Weapon")
	if weapon then
		local tool = owned[weapon]
		local name = Config.Weapons[weapon] and Config.Weapons[weapon].Name or weapon
		if tool then
			local price = if (tool:GetAttribute("Level") or 0) > 0 then prompt:GetAttribute("AscendedAmmo") else prompt:GetAttribute("AmmoPrice")
			prompt.ActionText = "Buy Ammo  (" .. tostring(price) .. ")"
		else
			prompt.ActionText = "Buy " .. name .. "  (" .. tostring(prompt:GetAttribute("Price")) .. ")"
		end
		return
	end
	local perk = prompt:GetAttribute("Perk")
	if perk then
		if player:GetAttribute("Perk_" .. perk) then
			prompt.ActionText = "Owned"
		elseif workspace:GetAttribute("Power") ~= true then
			prompt.ActionText = "Needs Power"
		else
			local price = if prompt:GetAttribute("SoloPrice") and inRunCount() <= 1 then prompt:GetAttribute("SoloPrice") else prompt:GetAttribute("Price")
			prompt.ActionText = "Buy  (" .. tostring(price) .. ")"
		end
		return
	end
	if prompt:GetAttribute("Altar") then
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		if workspace:GetAttribute("Power") ~= true then
			prompt.ActionText = "Needs Power"
		elseif not tool or not tool:GetAttribute("Weapon") then
			prompt.ActionText = "Hold a gun"
		elseif (tool:GetAttribute("Level") or 0) >= Config.Altar.MaxLevel then
			prompt.ActionText = "Can't grow"
		else
			prompt.ActionText = "Ascend " .. tool.Name .. "  (" .. Weapons.AscendCost(tool:GetAttribute("Level") or 0) .. ")"
		end
		return
	end
	if prompt.Name == "RevivePrompt" then
		if prompt:GetAttribute("For") == player.UserId then
			prompt.Enabled = false
		else
			prompt.HoldDuration = Config.Player.Downed.ReviveTime * (if player:GetAttribute("Perk_Lazarus") then Config.Perks.List.Lazarus.Revive else 1)
		end
		return
	end
	local forId = prompt:GetAttribute("For")
	if forId and forId ~= player.UserId and prompt.Enabled then
		prompt.Enabled = false
	end
end

local function shadeChoices()
	local folder = workspace:FindFirstChild("Choices")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		local forId = model:GetAttribute("For") or 0
		local dark = (forId ~= 0 and forId ~= player.UserId)
			or (model:GetAttribute("Group") == "Relic" and player:GetAttribute("RelicRound") == model:GetAttribute("Round"))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if dark then 1 else 0
			elseif d:IsA("PointLight") then
				d.Enabled = not dark
			elseif d:IsA("ProximityPrompt") then
				d.Enabled = not dark
			end
		end
	end
end

-- Every prompt in the house and on the floor sigils, kept as they come (the house is big).
local prompts = {}
local function track(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			prompts[d] = true
		end
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			prompts[d] = true
		end
	end)
end
for _, name in { "House", "Choices" } do
	local root = workspace:FindFirstChild(name)
	if root then
		track(root)
	end
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "House" or child.Name == "Choices" then
		track(child)
	end
end)

local function wordAll()
	local owned = myTools()
	for prompt in prompts do
		if prompt.Parent then
			wordPrompt(prompt, owned)
		else
			prompts[prompt] = nil
		end
	end
	for _, p in Players:GetPlayers() do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local prompt = root and root:FindFirstChild("RevivePrompt")
		if prompt then
			wordPrompt(prompt, owned)
		end
	end
	shadeChoices()
end

-- Screen ---------------------------------------------------------------------------------------

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "EndlessGrade"
grade.Parent = Lighting
local hurtAt = 0

-- Spectating -----------------------------------------------------------------------------------

local function spectate()
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		if camera.CameraSubject ~= hum then
			camera.CameraSubject = hum
		end
		return
	end
	local state = workspace:GetAttribute("WaveState")
	if state ~= "Wave" and state ~= "Intermission" then
		return
	end
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if p ~= player and h and h.Health > 0 and not c:GetAttribute("Downed") then
			if camera.CameraSubject ~= h then
				camera.CameraSubject = h
			end
			return
		end
	end
end

-- Loop -------------------------------------------------------------------------------------------

local slow = 0
RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local zombies = workspace:FindFirstChild("Zombies")
	if zombies then
		local eye = camera.CFrame.Position
		for _, model in zombies:GetChildren() do
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and not model:GetAttribute("Dead") and (root.Position - eye).Magnitude < 220 then
				poseZombie(model, dt, now, serverNow)
			end
		end
	end
	local dropsFolder = workspace:FindFirstChild("Drops")
	if dropsFolder then
		for _, model in dropsFolder:GetChildren() do
			animateDrop(model, now, serverNow)
		end
	end
	-- Screen grade: a red flash on a hit, grey and red while down.
	local character = player.Character
	local down = character and character:GetAttribute("Downed") == true
	local flash = math.max(0, 1 - (now - hurtAt) / 0.5)
	local tint = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 120, 110), math.max(flash * 0.6, if down then 0.5 else 0))
	grade.TintColor = tint
	grade.Saturation = if down then -0.7 else -0.15 * flash
	slow += dt
	if slow >= 0.25 then
		slow = 0
		flickerLamps(now)
		wordAll()
		spectate()
	end
end)

Net.Get("Fx").OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "Blood" then
		drops(a, if typeof(b) == "Vector3" then b else Vector3.zero, 4 * (c or 1), 0.3)
	elseif kind == "Gib" then
		drops(a, Vector3.zero, 14, 0.45)
	end
end)

Net.Get("Hud").OnClientEvent:Connect(function(cue)
	if cue == "Hurt" then
		hurtAt = os.clock()
	end
end)

-- Zombie models come and go; their pose state goes with them.
workspace:WaitForChild("Zombies").ChildRemoved:Connect(function(model)
	rigs[model] = nil
end)
