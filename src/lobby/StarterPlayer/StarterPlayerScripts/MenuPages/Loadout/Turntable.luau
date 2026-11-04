--!nonstrict
-- MenuPages.Loadout.Turntable (FRONT-B, 4 Nov 2026): drag, swipe or right stick to turn the gun or operator on the
-- menu stage. The input lives here; the model belongs to FRONT-A's MenuStage. Turning goes through stage.Turn(degrees)
-- when the stage has it, else this module turns the model the page handed it (the return of stage.Gun or
-- stage.Preview) around its own pivot on the world Y axis. A drag only starts on the open stage area: never on an
-- authored image or button of the menu.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local T = {}

local DEG_PER_PIXEL = 0.35
local STICK_DEG_PER_SEC = 140
local DAMPING = 5 -- per second, for the spin that carries on after a flick

local ctxRef = nil
local target = nil
local active = false
local dragInput = nil
local lastX = 0
local lastT = 0
local velocity = 0 -- degrees per second
local stickX = 0
local started = false

local function turn(deg)
	if deg == 0 then
		return
	end
	local st = ctxRef and ctxRef.stage
	if st and type(st.Turn) == "function" then
		pcall(st.Turn, deg)
		return
	end
	if target and target.Parent then
		local ok, pivot = pcall(target.GetPivot, target)
		if ok then
			local pos = pivot.Position
			target:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(deg), 0) * (CFrame.new(-pos) * pivot))
		end
	end
end
T.Turn = turn

local function overMenuArt(pos)
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return false
	end
	local ok, list = pcall(pg.GetGuiObjectsAtPosition, pg, pos.X, pos.Y)
	if not ok then
		return false
	end
	for _, g in list do
		local sg = g:FindFirstAncestorWhichIsA("ScreenGui")
		if sg and sg.Enabled and sg.Name ~= "MenuBack" and g.Visible then
			if g:IsA("GuiButton") then
				return true
			end
			if g:IsA("ImageLabel") and g.Image ~= "" and g.ImageTransparency < 0.95 then
				local s = g.AbsoluteSize
				local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
				-- a full-screen scrim or vignette is not "art under the finger"
				if s.X < vp.X * 0.9 or s.Y < vp.Y * 0.9 then
					return true
				end
			end
		end
	end
	return false
end

local function start()
	if started then
		return
	end
	started = true
	UserInputService.InputBegan:Connect(function(input, processed)
		if not active or processed or dragInput then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			if overMenuArt(input.Position) then
				return
			end
			dragInput = input
			lastX = input.Position.X
			lastT = os.clock()
			velocity = 0
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stickX = math.abs(input.Position.X) > 0.2 and input.Position.X or 0
			return
		end
		if not dragInput then
			return
		end
		local t = input.UserInputType
		local mine = (t == Enum.UserInputType.MouseMovement and dragInput.UserInputType == Enum.UserInputType.MouseButton1)
			or input == dragInput
		if mine then
			local x = input.Position.X
			local dx = x - lastX
			lastX = x
			local deg = dx * DEG_PER_PIXEL
			turn(deg)
			local now = os.clock()
			local dt = math.clamp(now - lastT, 1 / 240, 0.1)
			lastT = now
			velocity = deg / dt * 0.5 + velocity * 0.5
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragInput and (input == dragInput or input.UserInputType == dragInput.UserInputType) then
			dragInput = nil
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if not active then
			return
		end
		if stickX ~= 0 then
			turn(stickX * STICK_DEG_PER_SEC * dt)
		end
		if not dragInput and math.abs(velocity) > 1 then
			turn(velocity * dt)
			velocity *= math.exp(-DAMPING * dt)
		elseif not dragInput then
			velocity = 0
		end
	end)
end

-- Turn on for a page. model: what stage.Gun / stage.Preview returned (optional).
function T.Enable(ctx, model)
	ctxRef = ctx
	if typeof(model) == "Instance" and (model:IsA("Model") or model:IsA("BasePart")) then
		target = model
	end
	active = true
	start()
end

function T.Target(model)
	if typeof(model) == "Instance" and (model:IsA("Model") or model:IsA("BasePart")) then
		target = model
	end
end

function T.Disable()
	active = false
	dragInput = nil
	velocity = 0
	stickX = 0
end

function T.Active()
	return active
end

return T
