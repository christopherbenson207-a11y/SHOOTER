-- Hiding, crouching, lying prone and sliding on this client (numbers: GameConfig.Evade; server: EvadeServer).
-- Crouch / prone / slide: C or Left Ctrl, gamepad B (unless a teammate is down nearby: then B is their
-- revive), or the touch Crouch button (TouchControls fires Evade.TouchCrouch with the touch).
--   Standing or walking, a press crouches: the view sinks as far as the head, you move at CrouchSpeed
--   (GunClient reads Crouching), and the Beacon sees and hears you less.
--   Holding it ProneHold seconds (from standing or crouched) lies you down flat on your front, rifle out in front:
--   the view sinks to the floor and you crawl at ProneSpeed. A prone player also carries Crouching, so everything
--   that reads a crouch (the Beacon, the jump button, sprint) treats them as low.
--   A press while crouched (let go before ProneHold) or while prone stands you up. You can't sprint while
--   crouched or prone (GunClient); holding sprint no longer stands you up (owner, 7 Nov 2026).
--   Moving fast (sprinting), a press slides: a burst along the way you're moving that eases off over
--   SlideTime with the view low and leaning into it, then leaves you crouched. You can shoot
--   through a slide.
--   Jumping stands you up instead of jumping.
-- The server is told (Remotes.Evade "Stance" / "Slide") and poses the body for everyone (Shared.CrouchPose) from
-- the character's Crouching, Prone and SlideUntil attributes; this client sets Crouching, Prone and Sliding on its
-- own copy at once so nothing waits for a round trip. Every client also runs CrouchPose.Crawl on prone bodies each
-- frame (the walk cycle off the legs, the arms turned to point ahead).
-- Hiding (the Hide prompt EvadeServer puts on each spot): the view sinks behind the cover and
-- you can't walk (GunClient reads Hiding); you can still look and shoot. A dumpster takes you
-- inside instead, with the camera outside watching the street (HideWatch) and no shooting.
-- The prompt on your own spot reads Leave, and jumping also gets you out.
-- The view moves through two humanoid attributes set before the camera runs: EvadeDrop
-- (studs, added to the CameraOffset by PlayerHealthClient) and EvadeTilt (radians: pitch, 0,
-- lean; added to the camera by GunClient).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Controls = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Controls"))
local CrouchPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CrouchPose"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local CFG = GameConfig.Evade
local player = Players.LocalPlayer

-- Duel pass (5 Nov 2026): with the crouch pose on (Shared.CrouchPose, EvadeServer) the view sinks exactly as far as
-- the body's head does, crouched, sliding or prone, measured from this character's body (the avatar can still change
-- after spawn, so it is measured while low rather than once).
local POSE = CrouchPose.Enabled()
local PRONE_HOLD = CFG.ProneHold or 0.35
local PRONE_TIME = CFG.ProneTime or 0.35
local function crouchDrop(character, fallback)
	return (POSE and CrouchPose.Drop(character)) or fallback
end
local function proneDrop(character)
	return (POSE and CrouchPose.ProneDrop(character)) or CFG.ProneDrop or 3
end

-- Duel pass: no jump for GameConfig.Movement.JumpCooldown after landing, so holding jump (or the touch button,
-- which re-jumps on landing) can't bunny-hop. The jump state is switched off on this client, which owns the
-- character's physics, and back on when the wait is up. Places without a JumpCooldown jump as before.
local JUMP_COOLDOWN = (GameConfig.Movement and GameConfig.Movement.JumpCooldown) or 0
local jumpToken = 0
local function onLanded(humanoid)
	if JUMP_COOLDOWN <= 0 then
		return
	end
	jumpToken += 1
	local token = jumpToken
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	task.delay(JUMP_COOLDOWN, function()
		if token == jumpToken and humanoid.Parent then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end)
end

local slide = nil -- { Start, Dir, Speed, Side }
local lastSlide = -10
local drop = 0
local holdToken = 0 -- bumps on every press and every stance change, so a pending hold only lies down for its own press
local keyDown = false -- the crouch key or pad button is held

local function parts()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil, nil, nil
end

local function flag(character, name)
	return character:GetAttribute(name) == true
end

local function stanceOf(character)
	if flag(character, "Prone") then
		return "Prone"
	elseif flag(character, "Crouching") then
		return "Crouch"
	end
	return "Stand"
end

-- A teammate down within reach: gamepad B is their revive, not a crouch.
local function teammateDownNear(root)
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if p ~= player and r and c:GetAttribute("Downed") and (r.Position - root.Position).Magnitude < 9 then
			return true
		end
	end
	return false
end

local function setStance(character, stance)
	if stanceOf(character) == stance then
		return
	end
	character:SetAttribute("Crouching", if stance ~= "Stand" then true else nil)
	character:SetAttribute("Prone", if stance == "Prone" then true else nil)
	Remotes.Evade:FireServer("Stance", stance)
end

local function stand()
	holdToken += 1
	local character = parts()
	if not character then
		return
	end
	if slide then
		slide = nil
		character:SetAttribute("Sliding", nil)
	end
	setStance(character, "Stand")
end

local function startSlide(character, humanoid, root)
	local now = os.clock()
	local v = root.AssemblyLinearVelocity
	local flatV = Vector3.new(v.X, 0, v.Z)
	local move = humanoid.MoveDirection
	local dir = if move.Magnitude > 0.2 then Vector3.new(move.X, 0, move.Z).Unit else flatV.Unit
	local right = workspace.CurrentCamera.CFrame.RightVector
	slide = {
		Start = now,
		Dir = dir,
		Speed = math.max(CFG.SlideSpeed, flatV.Magnitude),
		Side = dir:Dot(Vector3.new(right.X, 0, right.Z).Unit),
	}
	lastSlide = now
	character:SetAttribute("Sliding", true)
	character:SetAttribute("Crouching", true)
	Remotes.Evade:FireServer("Slide")
end

-- Lying down needs solid ground under you (not mid-air, not swimming).
local function canLieDown(humanoid)
	local state = humanoid:GetState()
	return humanoid.FloorMaterial ~= Enum.Material.Air
		and state ~= Enum.HumanoidStateType.Swimming
		and state ~= Enum.HumanoidStateType.Climbing
end

-- held() says whether the press that started this is still down.
local function press(fromGamepad, held)
	local character, humanoid, root = parts()
	if not character or not player:GetAttribute("InMatch") or player:GetAttribute("Cutscene") then
		return
	end
	if flag(character, "Downed") or flag(character, "Devoured") or flag(character, "Bandaging") or flag(character, "Hiding") then
		return
	end
	if fromGamepad and teammateDownNear(root) then
		return
	end
	if slide then
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local from = stanceOf(character)
	if grounded and speed >= CFG.SlideMinSpeed and from == "Stand" and os.clock() - lastSlide >= CFG.SlideCooldown then
		startSlide(character, humanoid, root)
		return
	end
	if from == "Prone" then
		stand()
		return
	end
	holdToken += 1
	local token = holdToken
	if from == "Stand" then
		setStance(character, "Crouch")
	end
	-- Held to ProneHold: lie down. Let go sooner from a crouch you were already in: stand up.
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < PRONE_HOLD do
			if token ~= holdToken then
				return
			end
			if not held() then
				local c = parts()
				if from == "Crouch" and c and stanceOf(c) == "Crouch" then
					stand()
				end
				return
			end
			task.wait()
		end
		if token ~= holdToken then
			return
		end
		local c, h = parts()
		if c and h and stanceOf(c) == "Crouch" and not slide and canLieDown(h) and not flag(c, "Downed") then
			holdToken += 1
			setStance(c, "Prone")
		end
	end)
end

-- Keys from Shared.Controls (C or Ctrl / B by default; follows rebinds). Touch uses TouchControls' Crouch.
-- The controller's crouch button also gets you up while downed (PlayerHealthClient); Pass lets it through.
local function keyHeld()
	return keyDown
end
Controls.Bind("Crouch", "Crouch", function(_, inputState, input)
	if inputState == Enum.UserInputState.Begin and not Controls.Listening then
		keyDown = true
		press(Controls.DeviceOf(input) == "Pad", keyHeld)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		keyDown = false
	end
	return Enum.ContextActionResult.Pass
end)
-- The touch Crouch button (TouchControls) fires this with the touch that pressed it, so holding the button lies you
-- down too (a TouchControls without the touch passed in gives taps only); game scripts can't call CallFunction.
local touchCrouch = Instance.new("BindableEvent")
touchCrouch.Name = "TouchCrouch"
touchCrouch.Parent = script
touchCrouch.Event:Connect(function(input)
	local function touchHeld()
		if typeof(input) ~= "Instance" or not input:IsA("InputObject") then
			return false
		end
		local s = input.UserInputState
		return s ~= Enum.UserInputState.End and s ~= Enum.UserInputState.Cancel
	end
	press(false, touchHeld)
end)
-- Stands you up (TouchControls' jump button while low; other scripts may fire it too).
local standEvent = Instance.new("BindableEvent")
standEvent.Name = "Stand"
standEvent.Parent = script
standEvent.Event:Connect(stand)

-- Jumping gets you out of a hiding spot, and up out of a crouch, prone or slide (instead of jumping).
UserInputService.JumpRequest:Connect(function()
	local character, humanoid = parts()
	if not character then
		return
	end
	if flag(character, "Hiding") then
		Remotes.Evade:FireServer("Leave")
	elseif flag(character, "Crouching") then
		humanoid.Jump = false
		stand()
	end
end)

-- The Hide prompt on the spot you're in reads Leave.
local function labelPrompts()
	local character = player.Character
	local mine = character and character:GetAttribute("Hiding") and character:GetAttribute("HideId")
	for _, part in CollectionService:GetTagged("HideSpot") do
		local point = part:FindFirstChild("HidePoint")
		local prompt = point and point:FindFirstChild("HidePrompt")
		if prompt then
			prompt.ActionText = if mine and part:GetAttribute("HideId") == mine then "Leave" else "Hide"
		end
	end
end

local function onCharacter(character)
	slide = nil
	drop = 0
	holdToken += 1
	jumpToken += 1
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			-- Only a landing from a jump: stepping off a kerb doesn't hold the next jump back.
			local jumped = false
			humanoid.StateChanged:Connect(function(_, new)
				if new == Enum.HumanoidStateType.Jumping then
					jumped = true
				elseif new == Enum.HumanoidStateType.Landed and jumped then
					jumped = false
					onLanded(humanoid)
				elseif new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.Swimming then
					jumped = false
				end
				-- Into deep water: up off your front first.
				if new == Enum.HumanoidStateType.Swimming and flag(character, "Prone") then
					stand()
				end
			end)
		end
	end)
	character:GetAttributeChangedSignal("Hiding"):Connect(function()
		labelPrompts()
		if flag(character, "Hiding") then
			slide = nil
			holdToken += 1
			character:SetAttribute("Sliding", nil)
			character:SetAttribute("Crouching", nil)
			character:SetAttribute("Prone", nil)
		end
	end)
	character:GetAttributeChangedSignal("HideId"):Connect(labelPrompts)
	character:GetAttributeChangedSignal("Downed"):Connect(function()
		if flag(character, "Downed") then
			stand()
		end
	end)
	labelPrompts()
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- The slide's push, before physics each step.
RunService.PreSimulation:Connect(function()
	if not slide then
		return
	end
	local character, _, root = parts()
	local t = (os.clock() - slide.Start) / CFG.SlideTime
	if not character or t >= 1 or flag(character, "Downed") then
		if character then
			character:SetAttribute("Sliding", nil)
		end
		slide = nil
		return
	end
	local ease = 1 - (1 - t) ^ 2
	local speed = slide.Speed + (CFG.SlideEndSpeed - slide.Speed) * ease
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(slide.Dir.X * speed, math.min(v.Y, 2), slide.Dir.Z * speed)
end)

-- Prone bodies, everyone's (Shared.CrouchPose.Crawl): after the animator, before physics. Arms bent onto a
-- chest-held gun belong to WorldGunArms; arms the animator poses (a pack gun, no gun) are turned to point ahead.
if POSE then
	RunService.PreSimulation:Connect(function()
		for _, p in Players:GetPlayers() do
			local character = p.Character
			if character and character:GetAttribute("Prone") == true and not character:GetAttribute("Downed") then
				local holder = character:FindFirstChild("WorldGun")
				local ik = holder ~= nil and holder:GetAttribute("Gun") ~= nil and holder:GetAttribute("Pack") ~= true
				CrouchPose.Crawl(character, not ik)
			end
		end
	end)
end

-- The view: down behind cover while hiding, low while crouched, on the floor prone, lower and leaning in a slide.
RunService:BindToRenderStep("LastLightEvade", Enum.RenderPriority.Camera.Value - 2, function(dt)
	local character, humanoid = parts()
	if not character then
		return
	end
	local tilt = Vector3.zero
	local target = 0
	local time = CFG.CrouchTime
	if flag(character, "Hiding") then
		target = CFG.HideDrop
	elseif slide then
		local t = math.clamp((os.clock() - slide.Start) / CFG.SlideTime, 0, 1)
		local arc = math.sin(math.pi * math.min(t * 1.6, 1))
		target = crouchDrop(character, CFG.SlideDrop)
		tilt = Vector3.new(math.rad(CFG.SlidePitch) * (1 - t), 0, -math.rad(CFG.SlideTilt) * arc * slide.Side)
	elseif flag(character, "Prone") then
		target = proneDrop(character)
		time = PRONE_TIME
	elseif flag(character, "Crouching") then
		target = crouchDrop(character, CFG.CrouchDrop)
	end
	-- Coming up off the floor takes as long as going down to it.
	if drop > CFG.CrouchDrop + 0.5 then
		time = PRONE_TIME
	end
	drop += (target - drop) * math.min(1, dt / time * 2.5)
	humanoid:SetAttribute("EvadeDrop", drop)
	humanoid:SetAttribute("EvadeTilt", tilt)
end)
