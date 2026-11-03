-- Guns on the client (the server's side is ServerStorage.Endless.Arsenal). First person; you see
-- and hear your own shots at once and the server checks them.
--   PC: left mouse fires, right mouse aims, R reloads, V knifes, 1-3 / Q / wheel change guns.
--   Gamepad: R2 fires, L2 aims, B reloads, R3 knifes, Y changes guns (X is for prompts).
--   Touch: on-screen FIRE, AIM, RELOAD, SWAP and KNIFE buttons (ContextActionService's own buttons).
-- Aim assist only on touch and gamepad, none on PC (owner rule; Config.AimAssist), picked by
-- UserInputService.PreferredInput: a shot leaving close to a zombie bends onto it.
-- Each shot sends Weapon "Fire" with the origin, the pellets' directions and the zombie part each
-- pellet hit here (the server's lag allowance). The magazine count is predicted on the tool (the
-- server's own count replaces it as it arrives).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Endless = ReplicatedStorage:WaitForChild("Endless")
local Config = require(Endless:WaitForChild("Config"))
local Weapons = require(Endless:WaitForChild("Weapons"))
local Net = require(Endless:WaitForChild("Net"))
local Sfx = require(Endless:WaitForChild("Sfx"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local weaponRemote = Net.Get("Weapon")
local fxRemote = Net.Get("Fx")

local ARSENAL = Config.Arsenal

player.CameraMode = Enum.CameraMode.LockFirstPerson
task.spawn(function()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
			break
		end
		task.wait(0.5)
	end
end)

-- Input mode ------------------------------------------------------------------------------------

local function inputMode(): string
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if ok and preferred then
		if preferred == Enum.PreferredInput.Touch then
			return "Touch"
		elseif preferred == Enum.PreferredInput.KeyboardAndMouse then
			return "KeyboardAndMouse"
		end
		return "Gamepad"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "KeyboardAndMouse"
end

-- State -----------------------------------------------------------------------------------------

local triggerHeld = false
local wantsShot = false -- a click for semi, pump and bolt guns
local aiming = false
local lastShot = 0
local lastMelee = 0
local recoil = 0 -- radians of kick still on the camera

local function character()
	return player.Character
end

local function humanoid()
	local c = character()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function downed()
	local c = character()
	return c ~= nil and c:GetAttribute("Downed") == true
end

local function held(): Tool?
	local c = character()
	local tool = c and c:FindFirstChildOfClass("Tool")
	return if tool and tool:GetAttribute("Weapon") then tool else nil
end

local function tools(): { Tool }
	local list = {}
	local function scan(container)
		if container then
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and t:GetAttribute("Weapon") then
					table.insert(list, t)
				end
			end
		end
	end
	scan(character())
	scan(player:FindFirstChildOfClass("Backpack"))
	table.sort(list, function(a, b)
		return (a:GetAttribute("Slot") or 0) < (b:GetAttribute("Slot") or 0)
	end)
	return list
end

local function equip(index: number)
	local h = humanoid()
	local list = tools()
	local t = list[index]
	if h and t and not downed() and t.Parent ~= character() then
		aiming = false
		h:EquipTool(t)
	end
end

local function cycle(step: number)
	local list = tools()
	if #list < 2 then
		return
	end
	local current = table.find(list, held()) or 1
	equip((current - 1 + step) % #list + 1)
end

-- Effects ---------------------------------------------------------------------------------------

local fxFolder = workspace:WaitForChild("Fx")

local function flash(at: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.6, 0.6, 0.6)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Position = at
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3
	light.Range = 12
	light.Parent = p
	p.Parent = fxFolder
	Debris:AddItem(p, 0.05)
end

local function tracer(from: Vector3, to: Vector3, color: Color3, width: number)
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.35
	p.Size = Vector3.new(width, width, length)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = fxFolder
	Debris:AddItem(p, 0.06)
end

local function muzzleOf(tool: Tool?): Vector3?
	local handle = tool and tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	return if muzzle then muzzle.WorldPosition else nil
end

local TRACER = Color3.fromRGB(255, 220, 150)

local function shotFx(weaponId: string, origin: Vector3, ends: { Vector3 }, from: Vector3?)
	local w = Config.Weapons[weaponId]
	if not w then
		return
	end
	local start = from or origin
	flash(start, Color3.fromRGB(255, 196, 110))
	for _, e in ends do
		tracer(start, e, w.Beam or TRACER, if w.Beam then 0.35 else 0.08)
	end
end

-- Aim assist ------------------------------------------------------------------------------------

local assistParams = RaycastParams.new()
assistParams.FilterType = Enum.RaycastFilterType.Exclude

local function assist(origin: Vector3, dir: Vector3): Vector3
	local a = Config.AimAssist[inputMode()]
	if not a or not a.Enabled then
		return dir
	end
	local zombies = workspace:FindFirstChild("Zombies")
	if not zombies then
		return dir
	end
	assistParams.FilterDescendantsInstances = { character(), fxFolder }
	local best, bestAngle = nil, a.MagnetAngle
	for _, z in zombies:GetChildren() do
		local hum = z:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not z:GetAttribute("Dead") then
			for _, name in { "Head", "Torso" } do
				local part = z:FindFirstChild(name)
				if part and part.Transparency < 1 then
					local to = part.Position - origin
					if to.Magnitude < a.Range then
						local angle = math.deg(math.acos(math.clamp(dir:Dot(to.Unit), -1, 1)))
						if angle < bestAngle then
							local hit = workspace:Raycast(origin, to, assistParams)
							if hit and hit.Instance:IsDescendantOf(z) then
								best, bestAngle = part.Position, angle
							end
						end
					end
				end
			end
		end
	end
	if best then
		return dir:Lerp((best - origin).Unit, a.Strength).Unit
	end
	return dir
end

-- Shooting --------------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function spread(dir: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return dir
	end
	local r = math.rad(degrees) * math.sqrt(math.random())
	local a = math.random() * math.pi * 2
	local frame = CFrame.lookAt(Vector3.zero, dir)
	return (frame * CFrame.Angles(math.sin(a) * r, math.cos(a) * r, 0)).LookVector
end

local function zombiePart(inst: Instance): BasePart?
	local zombies = workspace:FindFirstChild("Zombies")
	if zombies and inst:IsDescendantOf(zombies) and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function reload(tool: Tool?)
	tool = tool or held()
	if not tool or downed() or tool:GetAttribute("Reloading") then
		return
	end
	local stats = Weapons.ForTool(tool, player)
	if not stats or (tool:GetAttribute("Mag") or 0) >= stats.Mag or (tool:GetAttribute("Reserve") or 0) <= 0 then
		return
	end
	weaponRemote:FireServer("Reload", tool)
	Sfx.Play(stats.Sounds .. "/MagOut")
	task.delay(stats.Reload * 0.7, function()
		Sfx.Play(stats.Sounds .. "/MagIn")
	end)
end

local function fire(tool: Tool)
	local stats = Weapons.ForTool(tool, player)
	if not stats or downed() or tool:GetAttribute("Reloading") then
		return
	end
	local now = os.clock()
	if now - lastShot < 60 / stats.Rpm then
		return
	end
	local mag = tool:GetAttribute("Mag") or 0
	if mag <= 0 then
		Sfx.Play("Common/Empty")
		reload(tool)
		return
	end
	lastShot = now
	local origin = camera.CFrame.Position
	local aim = assist(origin, camera.CFrame.LookVector)
	local cone = if aiming then stats.Spread.Aim else stats.Spread.Hip
	rayParams.FilterDescendantsInstances = { character(), fxFolder, workspace:FindFirstChild("Drops") }
	local dirs, claims, ends = {}, {}, {}
	for i = 1, stats.Pellets do
		local dir = spread(aim, cone)
		dirs[i] = dir
		local hit = workspace:Raycast(origin, dir * stats.Range, rayParams)
		claims[i] = hit and zombiePart(hit.Instance) or false
		ends[i] = if hit then hit.Position else origin + dir * stats.Range
	end
	tool:SetAttribute("Mag", mag - 1)
	weaponRemote:FireServer("Fire", tool, origin, dirs, claims)
	shotFx(stats.Id, origin, ends, muzzleOf(tool))
	Sfx.Play(stats.Sounds .. "/Crack")
	Sfx.Play(stats.Sounds .. "/Body", { Volume = 0.8 })
	recoil = math.min(recoil + math.rad(ARSENAL.Recoil.Kick) * (if aiming then 0.5 else 1) * math.clamp(stats.Damage / 80, 0.5, 2.2), math.rad(8))
	if mag - 1 <= 0 then
		task.delay(0.15, reload, tool)
	end
end

local function melee()
	local now = os.clock()
	if downed() or now - lastMelee < ARSENAL.Melee.Cooldown or not character() then
		return
	end
	lastMelee = now
	weaponRemote:FireServer("Melee")
end

-- Input -----------------------------------------------------------------------------------------

local function setTrigger(down: boolean)
	triggerHeld = down
	if down then
		wantsShot = true
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local t, k = input.UserInputType, input.KeyCode
	if t == Enum.UserInputType.MouseButton1 or k == Enum.KeyCode.ButtonR2 then
		setTrigger(true)
	elseif t == Enum.UserInputType.MouseButton2 or k == Enum.KeyCode.ButtonL2 then
		aiming = true
	elseif k == Enum.KeyCode.R or k == Enum.KeyCode.ButtonB then
		reload()
	elseif k == Enum.KeyCode.V or k == Enum.KeyCode.ButtonR3 then
		melee()
	elseif k == Enum.KeyCode.One then
		equip(1)
	elseif k == Enum.KeyCode.Two then
		equip(2)
	elseif k == Enum.KeyCode.Three then
		equip(3)
	elseif k == Enum.KeyCode.Q or k == Enum.KeyCode.ButtonY then
		cycle(1)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local t, k = input.UserInputType, input.KeyCode
	if t == Enum.UserInputType.MouseButton1 or k == Enum.KeyCode.ButtonR2 then
		setTrigger(false)
	elseif t == Enum.UserInputType.MouseButton2 or k == Enum.KeyCode.ButtonL2 then
		aiming = false
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
		cycle(if input.Position.Z > 0 then -1 else 1)
	end
end)

-- Touch: the engine's own context buttons (no screens built here).
local touchBound = false
local function bindTouch(on: boolean)
	if on == touchBound then
		return
	end
	touchBound = on
	if not on then
		for _, name in { "EndlessFire", "EndlessAim", "EndlessReload", "EndlessSwap", "EndlessKnife" } do
			ContextActionService:UnbindAction(name)
		end
		return
	end
	ContextActionService:BindAction("EndlessFire", function(_, state)
		if state == Enum.UserInputState.Begin then
			setTrigger(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setTrigger(false)
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:BindAction("EndlessAim", function(_, state)
		if state == Enum.UserInputState.Begin then
			aiming = not aiming
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:BindAction("EndlessReload", function(_, state)
		if state == Enum.UserInputState.Begin then
			reload()
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:BindAction("EndlessSwap", function(_, state)
		if state == Enum.UserInputState.Begin then
			cycle(1)
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:BindAction("EndlessKnife", function(_, state)
		if state == Enum.UserInputState.Begin then
			melee()
		end
		return Enum.ContextActionResult.Sink
	end, true)
	ContextActionService:SetTitle("EndlessFire", "FIRE")
	ContextActionService:SetTitle("EndlessAim", "AIM")
	ContextActionService:SetTitle("EndlessReload", "R")
	ContextActionService:SetTitle("EndlessSwap", "SWAP")
	ContextActionService:SetTitle("EndlessKnife", "KNIFE")
	ContextActionService:SetPosition("EndlessFire", UDim2.new(0.05, 0, 0.15, 0))
	ContextActionService:SetPosition("EndlessAim", UDim2.new(-0.35, 0, 0.3, 0))
	ContextActionService:SetPosition("EndlessReload", UDim2.new(0.45, 0, -0.25, 0))
	ContextActionService:SetPosition("EndlessSwap", UDim2.new(0.75, 0, 0.15, 0))
	ContextActionService:SetPosition("EndlessKnife", UDim2.new(-0.35, 0, -0.15, 0))
end

local function refreshMode()
	bindTouch(inputMode() == "Touch")
end
refreshMode()
pcall(function()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refreshMode)
end)
UserInputService.LastInputTypeChanged:Connect(refreshMode)

-- Every frame -----------------------------------------------------------------------------------

RunService:BindToRenderStep("EndlessRecoil", Enum.RenderPriority.Camera.Value + 1, function(dt)
	-- The kick sits on top of the camera and settles back.
	if recoil > 0 then
		camera.CFrame *= CFrame.Angles(recoil, 0, 0)
		recoil = math.max(0, recoil - recoil * math.min(1, ARSENAL.Recoil.Recover * dt) - math.rad(0.5) * dt)
	end
	local tool = held()
	local stats = tool and Weapons.ForTool(tool, player)
	local fov = Config.Player.Fov
	if aiming and stats and not downed() then
		fov = stats.AimFov or ARSENAL.AimFov
	end
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, dt * 14)
	-- Reloading: the gun dips (local only).
	if tool then
		local dip = 0
		local ends = tool:GetAttribute("ReloadEnd")
		if tool:GetAttribute("Reloading") and ends and stats then
			local left = ends - workspace:GetServerTimeNow()
			local t = 1 - math.clamp(left / stats.Reload, 0, 1)
			dip = math.sin(t * math.pi)
		end
		local grip = CFrame.Angles(math.rad(35) * dip, 0, 0)
		if tool.Grip ~= grip then
			tool.Grip = grip
		end
	end
	local h = humanoid()
	if h then
		h.CameraOffset = if downed() then Vector3.new(0, -2.2, 0) else Vector3.zero
	end
end)

RunService.Heartbeat:Connect(function()
	local tool = held()
	if not tool then
		wantsShot = false
		return
	end
	local w = Config.Weapons[tool:GetAttribute("Weapon")]
	if not w then
		return
	end
	if w.Fire == "Auto" then
		if triggerHeld then
			fire(tool)
		end
	elseif wantsShot then
		wantsShot = false
		fire(tool)
	end
end)

-- Other players' shots.
fxRemote.OnClientEvent:Connect(function(kind, userId, weaponId, origin, ends)
	if kind ~= "Shot" or userId == player.UserId then
		return
	end
	local shooter = Players:GetPlayerByUserId(userId)
	local tool = shooter and shooter.Character and shooter.Character:FindFirstChildOfClass("Tool")
	shotFx(weaponId, origin, ends, muzzleOf(tool))
	local w = Config.Weapons[weaponId]
	if w then
		Sfx.Play(w.Sounds .. "/Crack", { Position = origin })
	end
end)

player.CharacterAdded:Connect(function()
	aiming, triggerHeld, wantsShot, recoil = false, false, false, 0
end)
