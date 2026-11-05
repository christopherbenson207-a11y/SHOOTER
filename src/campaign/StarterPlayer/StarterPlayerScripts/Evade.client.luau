-- Hiding, crouching and sliding on this client (numbers: GameConfig.Evade; server: EvadeServer).
-- Crouch / slide: C or Left Ctrl, gamepad B (unless a teammate is down nearby: then B is their
-- revive), or the touch Crouch button (TouchControls fires Evade.TouchCrouch).
--   Standing or walking, it toggles a crouch: the view sinks CrouchDrop, you move at
--   CrouchSpeed (GunClient reads Crouching), and the Beacon sees and hears you less.
--   Moving fast (sprinting), it slides: a burst along the way you're moving that eases off over
--   SlideTime with the view low and leaning into it, then leaves you crouched. You can shoot
--   through a slide.
--   Jumping or sprinting stands you up (GunClient fires Evade.Stand).
-- The server is told (Remotes.Evade "Crouch" / "Slide") so teammates (TeamPose) and the Beacon
-- see it on the character's Crouching and SlideUntil attributes; this client sets Crouching
-- and Sliding on its own copy at once so nothing waits for a round trip.
-- Hiding (the Hide prompt EvadeServer puts on each spot): the view sinks behind the cover and
-- you can't walk (GunClient reads Hiding); you can still look and shoot. A dumpster takes you
-- inside instead, with the camera outside watching the street (HideWatch) and no shooting.
-- The prompt on your own spot reads Leave, and jumping also gets you out.
-- The view moves through two humanoid attributes set before the camera runs: EvadeDrop
-- (studs, added to the CameraOffset by PlayerHealthClient) and EvadeTilt (radians: pitch, 0,
-- lean; added to the camera by GunClient).

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Controls = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Controls"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local CFG = GameConfig.Evade
local player = Players.LocalPlayer

local slide = nil -- { Start, Dir, Speed, Side }
local lastSlide = -10
local drop = 0

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

local function setCrouch(character, on)
	if flag(character, "Crouching") == on then
		return
	end
	character:SetAttribute("Crouching", if on then true else nil)
	Remotes.Evade:FireServer("Crouch", on)
end

local function stand()
	local character = parts()
	if not character then
		return
	end
	if slide then
		slide = nil
		character:SetAttribute("Sliding", nil)
	end
	setCrouch(character, false)
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

local function press(fromGamepad)
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
	if grounded and speed >= CFG.SlideMinSpeed and not flag(character, "Crouching")
		and os.clock() - lastSlide >= CFG.SlideCooldown
	then
		startSlide(character, humanoid, root)
	else
		setCrouch(character, not flag(character, "Crouching"))
	end
end

-- Keys from Shared.Controls (C or Ctrl / B by default; follows rebinds). Touch uses TouchControls' Crouch.
-- The controller's crouch button also gets you up while downed (PlayerHealthClient); Pass lets it through.
Controls.Bind("Crouch", "Crouch", function(_, inputState, input)
	if inputState == Enum.UserInputState.Begin and not Controls.Listening then
		press(Controls.DeviceOf(input) == "Pad")
	end
	return Enum.ContextActionResult.Pass
end)
-- The touch Crouch button (TouchControls) fires this; game scripts can't call CallFunction.
local touchCrouch = Instance.new("BindableEvent")
touchCrouch.Name = "TouchCrouch"
touchCrouch.Parent = script
touchCrouch.Event:Connect(function()
	press(false)
end)
-- GunClient fires this when you start sprinting.
local standEvent = Instance.new("BindableEvent")
standEvent.Name = "Stand"
standEvent.Parent = script
standEvent.Event:Connect(stand)

-- Jumping gets you out of a hiding spot, and up out of a crouch or slide (instead of jumping).
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
	character:GetAttributeChangedSignal("Hiding"):Connect(function()
		labelPrompts()
		if flag(character, "Hiding") then
			slide = nil
			character:SetAttribute("Sliding", nil)
			character:SetAttribute("Crouching", nil)
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

-- The view: down behind cover while hiding, low while crouched, lower and leaning in a slide.
RunService:BindToRenderStep("LastLightEvade", Enum.RenderPriority.Camera.Value - 2, function(dt)
	local character, humanoid = parts()
	if not character then
		return
	end
	local tilt = Vector3.zero
	local target = 0
	if flag(character, "Hiding") then
		target = CFG.HideDrop
	elseif slide then
		local t = math.clamp((os.clock() - slide.Start) / CFG.SlideTime, 0, 1)
		local arc = math.sin(math.pi * math.min(t * 1.6, 1))
		target = CFG.SlideDrop
		tilt = Vector3.new(math.rad(CFG.SlidePitch) * (1 - t), 0, -math.rad(CFG.SlideTilt) * arc * slide.Side)
	elseif flag(character, "Crouching") then
		target = CFG.CrouchDrop
	end
	drop += (target - drop) * math.min(1, dt / CFG.CrouchTime * 2.5)
	humanoid:SetAttribute("EvadeDrop", drop)
	humanoid:SetAttribute("EvadeTilt", tilt)
end)
