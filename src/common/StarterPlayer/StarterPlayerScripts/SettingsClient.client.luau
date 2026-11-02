--!strict
-- The settings screen (StarterGui.Settings, authored; one row per GameConfig.Settings key).
-- Opens from the menu's SETTINGS word (MenuClient fires Open) or, in a match, from the gear
-- in Roblox's top bar or the P key. Sliders drag (and step with the gamepad D-pad when
-- picked), switches flip, pickers pick; every change goes through Shared.Options, which
-- applies and saves it. Rows that can't work on this device are hidden (Touch rows without a
-- touch screen, Gyro rows without a gyroscope). While open, the Modal button frees the mouse.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Options = require(Shared:WaitForChild("Options"))

local CFG = GameConfig.Settings
local AMBER = GameConfig.Hud.Lull
local TEXT = Color3.fromRGB(240, 238, 232)
local DIM = Color3.fromRGB(60, 64, 72)
local CHIP = Color3.fromRGB(40, 44, 52)
local DARK = Color3.fromRGB(16, 18, 22)
local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- No character on join means Roblox hasn't copied StarterGui yet; copy it in (like the menu)
-- and drop the copy Roblox adds at spawn.
local gui = playerGui:FindFirstChild("Settings") :: ScreenGui? or (StarterGui:WaitForChild("Settings") :: ScreenGui):Clone()
gui.Parent = playerGui
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "Settings" and child ~= gui then
		child:Destroy()
	end
end)

local panel = gui:WaitForChild("Panel") :: Frame
local card = panel:WaitForChild("Card") :: Frame
local list = card:WaitForChild("List") :: ScrollingFrame
local gear = gui:WaitForChild("Gear") :: ImageButton

local open = Instance.new("BindableEvent")
open.Name = "Open"
open.Parent = script

local rows: { [string]: Frame } = {}
for _, key in CFG.Order do
	rows[key] = list:WaitForChild(key) :: Frame
end

local function fraction(key: string, value: number): number
	local option = CFG[key]
	return (value - option.Min) / (option.Max - option.Min)
end

local function valueText(key: string, value: number): string
	local option = CFG[key]
	if option.Percent then
		return string.format("%d%%", math.round(value * 100))
	elseif option.Step >= 1 then
		return tostring(math.round(value))
	end
	return string.format("%.2f", value)
end

-- Draw one row from its current value.
local function draw(key: string)
	local option = CFG[key]
	local row = rows[key]
	local value = Options.Get(key)
	local control = row:FindFirstChild("Control") :: GuiObject
	if option.Choices then
		for _, b in control:GetChildren() do
			if b:IsA("TextButton") then
				local on = b.Name == value
				TweenService:Create(b, QUICK, { BackgroundColor3 = if on then AMBER else CHIP, TextColor3 = if on then DARK else TEXT }):Play()
			end
		end
	elseif type(option.Default) == "boolean" then
		local knob = control:FindFirstChild("Knob") :: Frame
		TweenService:Create(control, QUICK, { BackgroundColor3 = if value then AMBER else DIM }):Play()
		TweenService:Create(knob, QUICK, { Position = if value then UDim2.new(1, -25, 0.5, 0) else UDim2.new(0, 3, 0.5, 0) }):Play()
	else
		local track = control:FindFirstChild("Track") :: Frame
		local f = fraction(key, value)
		local fill = track:FindFirstChild("Fill") :: Frame
		local knob = track:FindFirstChild("Knob") :: Frame
		local label = control:FindFirstChild("Value") :: TextLabel
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		label.Text = valueText(key, value)
	end
end

-- Show only the rows this device can use.
local function layout()
	for _, key in CFG.Order do
		local option = CFG[key]
		local show = true
		if option.Touch and not UserInputService.TouchEnabled then
			show = false
		end
		if option.Gyro and not UserInputService.GyroscopeEnabled then
			show = false
		end
		rows[key].Visible = show
	end
end

-- Wiring ------------------------------------------------------------------------------------

local dragging: { key: string, track: Frame }? = nil

local function dragTo(x: number)
	local d = dragging
	if not d then
		return
	end
	local option = CFG[d.key]
	local f = math.clamp((x - d.track.AbsolutePosition.X) / math.max(d.track.AbsoluteSize.X, 1), 0, 1)
	Options.Set(d.key, option.Min + f * (option.Max - option.Min))
end

for _, key in CFG.Order do
	local option = CFG[key]
	local control = rows[key]:FindFirstChild("Control") :: GuiObject
	if option.Choices then
		for _, b in control:GetChildren() do
			if b:IsA("TextButton") then
				b.Activated:Connect(function()
					Options.Set(key, b.Name)
				end)
			end
		end
	elseif type(option.Default) == "boolean" then
		(control :: TextButton).Activated:Connect(function()
			Options.Set(key, not Options.Get(key))
		end)
	else
		local track = control:FindFirstChild("Track") :: Frame
		local hit = control:FindFirstChild("Hit") :: TextButton
		hit.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				dragging = { key = key, track = track }
				list.ScrollingEnabled = false
				dragTo(input.Position.X)
			end
		end)
	end
	draw(key)
end

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		dragTo(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		dragging = nil
		list.ScrollingEnabled = true
	end
end)

Options.Changed:Connect(function(key)
	if rows[key] then
		draw(key)
	end
end)

-- Open and close ----------------------------------------------------------------------------

local iconWas = true
local isOpen = false

local function setOpen(on: boolean)
	if on == isOpen then
		return
	end
	isOpen = on
	panel.Visible = on
	if on then
		layout()
		iconWas = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true
		list.CanvasPosition = Vector2.zero
		if UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:find("Gamepad") then
			GuiService.SelectedObject = card:FindFirstChild("Close") :: GuiObject
		end
	else
		dragging = nil
		list.ScrollingEnabled = true
		UserInputService.MouseIconEnabled = iconWas
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
	end
end

open.Event:Connect(function()
	setOpen(true)
end)
gear.Activated:Connect(function()
	setOpen(not isOpen)
end)
local close = card:WaitForChild("Close") :: TextButton
close.Activated:Connect(function()
	setOpen(false)
end)
close.MouseEnter:Connect(function()
	close.TextColor3 = AMBER
end)
close.MouseLeave:Connect(function()
	close.TextColor3 = TEXT
end)
local reset = card:WaitForChild("Reset") :: TextButton
reset.Activated:Connect(function()
	Options.Reset()
end)

-- P toggles in a match; gamepad B closes; D-pad left/right steps a picked slider.
UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.ButtonB and isOpen then
		setOpen(false)
		return
	end
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.P and (isOpen or gear.Visible) then
		setOpen(not isOpen)
	elseif isOpen and (input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.DPadRight) then
		local picked = GuiService.SelectedObject
		for key, row in rows do
			local option = CFG[key]
			if picked and picked:IsDescendantOf(row) and option.Step then
				local dir = if input.KeyCode == Enum.KeyCode.DPadRight then 1 else -1
				Options.Set(key, Options.Get(key) + option.Step * dir)
			end
		end
	end
end)
-- The gear shows in a match (the HUD is up), in the top bar right after Roblox's buttons.
local function placeGear()
	local inset = GuiService.TopbarInset
	local size = math.max(32, inset.Height - 12)
	gear.Size = UDim2.fromOffset(size, size)
	gear.Position = UDim2.fromOffset(inset.Min.X + 8, inset.Min.Y + (inset.Height - size) / 2)
end
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(placeGear)
placeGear()

game:GetService("RunService").Heartbeat:Connect(function()
	local hud = playerGui:FindFirstChild("HUD") :: ScreenGui?
	local menu = playerGui:FindFirstChild("Menu") :: ScreenGui?
	local inGame = hud ~= nil and hud.Enabled and not (menu and menu.Enabled)
	gear.Visible = inGame and not player:GetAttribute("Cutscene")
end)
