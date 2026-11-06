--!strict
-- The settings screen (StarterGui.Settings, authored PNG art from SCREENS-C: panel, title, row plates, slider track,
-- fill and knob, switch on and off, choice chips, BACK and RESET; one row per GameConfig.Settings key).
-- Opens from the menu's settings button (fires Open) or, in a match, from the gear in Roblox's top bar or the P key.
-- Sliders drag (and step with the gamepad D-pad when picked), switches flip, chips pick; every change goes through
-- Shared.Options, which applies and saves it. Rows that can't work on this device are hidden (Touch rows without a
-- touch screen, Gyro rows without a gyroscope). While open, the Modal button frees the mouse.
-- The audio slider also sets SoundService.Menu (the SoundGroup the menu's UiSound plays through).
-- Reskin: FRONT-C, 4 Nov 2026 (logic unchanged; backup ServerStorage._Backups.SettingsClient_2026-11-02_beforeMenuRevamp).
-- CONTROLS (4 Nov 2026): a keyboard and a controller chip per Shared.Controls action (rows built by
-- tools/build_controls_rows.luau from the authored rows); hidden on a touch-only phone.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Options = require(Shared:WaitForChild("Options"))
local Controls = require(Shared:WaitForChild("Controls"))

-- The menu's art helpers when this place has them (the lobby); without them the authored images stay as built.
local Ui: any = nil
do
	local menu = Shared:FindFirstChild("Menu")
	local m = menu and menu:FindFirstChild("Ui")
	if m then
		local ok, v = pcall(require, m)
		Ui = if ok then v else nil
	end
end

local CFG = GameConfig.Settings
local MUTED = Color3.fromRGB(164, 179, 237) -- kid palette (5 Nov)
local AMBER_INK = Color3.fromRGB(24, 20, 12)
local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- The slider that sets menu and UI sound volume: a dedicated MenuVol setting once GameConfig has one, else the voices.
local AUDIO_KEY = if CFG.MenuVol then "MenuVol" else "VoiceVol"

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
-- The lobby menu's controller focus (Shared.Menu.Pad) stays inside the panel while it is open and leaves B to us.
game:GetService("CollectionService"):AddTag(panel, "PadModal")
local list = card:WaitForChild("List") :: ScrollingFrame
local gear = gui:WaitForChild("Gear") :: ImageButton

local open = Instance.new("BindableEvent")
open.Name = "Open"
open.Parent = script

local rows: { [string]: Frame } = {}
for _, key in CFG.Order do
	rows[key] = list:WaitForChild(key) :: Frame
end

-- Art swaps by key (no-op without Shared.Menu.Ui).
local function setArt(img: Instance?, key: any)
	if Ui and img and type(key) == "string" then
		Ui.SetArt(img, key)
	end
end

-- Menu sound volume ---------------------------------------------------------------------------
local function menuGroup(): SoundGroup
	local g = SoundService:FindFirstChild("Menu")
	if g and g:IsA("SoundGroup") then
		return g
	end
	local made = Instance.new("SoundGroup")
	made.Name = "Menu"
	made.Volume = 1
	made.Parent = SoundService
	return made
end
local BASE_VOLUME = menuGroup():GetAttribute("Base")
if type(BASE_VOLUME) ~= "number" then
	BASE_VOLUME = 1
end
local function applyAudio()
	local v = tonumber(Options.Get(AUDIO_KEY)) or 1
	menuGroup().Volume = (BASE_VOLUME :: number) * v
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

-- Chip controllers (Ui.Button) per row, so Selected uses the authored ChipSelected art.
local chips: { [string]: { [string]: any } } = {}

-- Draw one row from its current value.
local function draw(key: string)
	local option = CFG[key]
	local row = rows[key]
	local value = Options.Get(key)
	local control = row:FindFirstChild("Control") :: GuiObject
	if option.Choices then
		for _, b in control:GetChildren() do
			if b:IsA("GuiButton") then
				local on = b.Name == value
				local ctl = chips[key] and chips[key][b.Name]
				if ctl then
					ctl.Selected(on)
				else
					setArt(b, if on then b:GetAttribute("ArtSelected") else b:GetAttribute("ArtIdle"))
				end
				local word = b:FindFirstChild("Word")
				if word and word:IsA("TextLabel") then
					word.TextColor3 = if on then AMBER_INK else MUTED
				end
			end
		end
	elseif type(option.Default) == "boolean" then
		local knob = control:FindFirstChild("Knob") :: GuiObject
		setArt(control, if value then control:GetAttribute("ArtOn") else control:GetAttribute("ArtOff"))
		local w = knob.Size.X.Offset
		TweenService:Create(knob, QUICK, { Position = if value then UDim2.new(1, -(w + 1), 0.5, 0) else UDim2.new(0, 1, 0.5, 0) }):Play()
	else
		local track = control:FindFirstChild("Track") :: GuiObject
		local f = fraction(key, value)
		local fill = track:FindFirstChild("Fill") :: GuiObject
		local knob = track:FindFirstChild("Knob") :: GuiObject
		local label = control:FindFirstChild("Value") :: TextLabel
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		label.Text = valueText(key, value)
	end
	if key == AUDIO_KEY then
		applyAudio()
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
		if option.Pad and not UserInputService.GamepadEnabled then
			show = false
		end
		if (option.Assist or option.Look) and not (UserInputService.GamepadEnabled or UserInputService.TouchEnabled) then
			show = false
		end
		rows[key].Visible = show
	end
	-- CONTROLS: a column per device this player has; nothing on a touch-only phone.
	local kb = UserInputService.KeyboardEnabled
	local pad = UserInputService.GamepadEnabled
	local head = list:FindFirstChild("ControlsHead")
	if head then
		head.Visible = kb or pad
		local kbHead, padHead = head:FindFirstChild("KbHead"), head:FindFirstChild("PadHead")
		if kbHead then
			local kbLabel = kbHead :: GuiObject
			kbLabel.Visible = kb
			-- Over the keyboard chips, which take the right edge when there's no controller column.
			kbLabel.Position = UDim2.new(1, if pad then -140 else 0, 1, -6)
		end
		if padHead then
			padHead.Visible = pad
		end
	end
	for _, row in list:GetChildren() do
		if row.Name:match("^Bind_") then
			(row :: Frame).Visible = kb or pad
			local control = row:FindFirstChild("Control")
			local kbChip = control and control:FindFirstChild("Kb")
			local padChip = control and control:FindFirstChild("Pad")
			if kbChip then
				(kbChip :: GuiObject).Visible = kb
			end
			if padChip then
				(padChip :: GuiObject).Visible = pad
			end
		end
	end
end

-- Row plates light on hover or gamepad selection.
local hoverRow: Frame? = nil
local function lightRow(row: Frame?)
	if row == hoverRow then
		return
	end
	for _, r in { hoverRow, row } do
		local plate = r and r:FindFirstChild("Plate")
		if plate then
			setArt(plate, if r == row then plate:GetAttribute("ArtHover") else plate:GetAttribute("ArtIdle"))
		end
	end
	hoverRow = row
end

-- Wiring ------------------------------------------------------------------------------------

local dragging: { key: string, track: GuiObject }? = nil

local function dragTo(x: number)
	local d = dragging
	if not d then
		return
	end
	local option = CFG[d.key]
	local f = math.clamp((x - d.track.AbsolutePosition.X) / math.max(d.track.AbsoluteSize.X, 1), 0, 1)
	Options.Set(d.key, option.Min + f * (option.Max - option.Min))
end

local function onPress(button: GuiButton, fn: () -> ()): any
	if Ui then
		return Ui.Button(button, fn)
	end
	button.Activated:Connect(fn)
	return nil
end

for _, key in CFG.Order do
	local option = CFG[key]
	local row = rows[key]
	local control = row:FindFirstChild("Control") :: GuiObject
	if option.Choices then
		chips[key] = {}
		for _, b in control:GetChildren() do
			if b:IsA("GuiButton") then
				chips[key][b.Name] = onPress(b, function()
					Options.Set(key, b.Name)
				end)
			end
		end
	elseif type(option.Default) == "boolean" then
		(control :: GuiButton).Activated:Connect(function()
			Options.Set(key, not Options.Get(key))
		end)
	else
		local track = control:FindFirstChild("Track") :: GuiObject
		local hit = control:FindFirstChild("Hit") :: GuiButton
		hit.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				dragging = { key = key, track = track }
				list.ScrollingEnabled = false
				dragTo(input.Position.X)
			end
		end)
	end
	row.MouseEnter:Connect(function()
		lightRow(row)
	end)
	row.MouseLeave:Connect(function()
		if hoverRow == row then
			lightRow(nil)
		end
	end)
	draw(key)
end
applyAudio()

-- Key bindings ------------------------------------------------------------------------------------------------
-- One Bind_<Action> row per Shared.Controls action: a keyboard chip and a controller chip. Pick a chip, then press
-- the new key or button (click the chip itself again to put a mouse button on it). A key another action holds
-- swaps over (Controls.Set keeps every action bound and never lets two clash). A reserved key, a click elsewhere
-- or 10 s of nothing cancels.

local bindRows: { [string]: Frame } = {}
local lockedAction: { [string]: boolean } = {}
for _, action in Controls.Actions do
	local row = list:FindFirstChild("Bind_" .. action.Name)
	if row then
		bindRows[action.Name] = row :: Frame
		lockedAction[action.Name] = action.Locked == true
	end
end

local listening: { action: string, device: string, chip: GuiButton, token: number }? = nil
local listenToken = 0
local lastCapture = 0

-- Text on a chip: the authored Word label on the lobby's image chips.
local function chipWord(chip: GuiButton): TextLabel?
	local word = chip:FindFirstChild("Word")
	return if word and word:IsA("TextLabel") then word else nil
end

local bindCtl: { [GuiButton]: any } = {}

local function drawChip(name: string, device: string)
	local row = bindRows[name]
	local control = row and row:FindFirstChild("Control")
	local chip = control and control:FindFirstChild(device) :: GuiButton?
	if not chip then
		return
	end
	local code = Controls.Get(name, device :: any)[1]
	local on = listening ~= nil and listening.action == name and listening.device == device
	local image = if device == "Pad" and not on then Controls.Image(code) else ""
	local glyph = chip:FindFirstChild("Glyph") :: ImageLabel?
	if glyph then
		glyph.Image = image
		glyph.Visible = image ~= ""
	end
	local word = chipWord(chip)
	local text = if on then "..." elseif image ~= "" then "" else Controls.CodeText(code)
	if word then
		word.Text = text
	end
	if not lockedAction[name] then
		-- Waiting for a key: the authored ChipSelected art, as a picked choice chip.
		local ctl = bindCtl[chip]
		if ctl then
			ctl.Selected(on)
		else
			setArt(chip, if on then chip:GetAttribute("ArtSelected") else chip:GetAttribute("ArtIdle"))
		end
		if word then
			word.TextColor3 = if on then AMBER_INK else MUTED
		end
	end
end

local function drawBinds()
	for name in bindRows do
		drawChip(name, "Kb")
		drawChip(name, "Pad")
	end
end

local function sinkAll()
	return Enum.ContextActionResult.Sink
end

local function stopListening()
	local l = listening
	listening = nil
	listenToken += 1
	Controls.Listening = false
	ContextActionService:UnbindAction("SettingsListen")
	if l then
		drawChip(l.action, l.device)
	end
end

local function startListening(name: string, device: string, chip: GuiButton)
	stopListening()
	local token = listenToken
	-- Next frame, so the click or A press that picked the chip isn't taken as the new key.
	task.defer(function()
		if token ~= listenToken then
			return
		end
		listening = { action = name, device = device, chip = chip, token = token }
		Controls.Listening = true
		-- Keep the press from also doing its old job in the game underneath.
		ContextActionService:BindActionAtPriority("SettingsListen", sinkAll, false, 5000, Enum.UserInputType.Keyboard,
			Enum.UserInputType.Gamepad1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3)
		drawChip(name, device)
		task.delay(10, function()
			if listening and listening.token == token then
				stopListening()
			end
		end)
	end)
end

local MOUSE = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

local function over(gui: GuiObject, pos: Vector3): boolean
	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	local y = pos.Y + GuiService:GetGuiInset().Y
	return pos.X >= p.X and pos.X <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end

-- The press that lands while a chip waits. Returns true when it was taken.
local function capture(input: InputObject): boolean
	local l = listening
	if not l then
		return false
	end
	local t = input.UserInputType
	local device = Controls.DeviceOf(input)
	local code: any = if MOUSE[t] then t else input.KeyCode
	if code == Enum.KeyCode.Thumbstick1 or code == Enum.KeyCode.Thumbstick2 or code == Enum.KeyCode.Unknown and not MOUSE[t] then
		return false
	end
	if t == Enum.UserInputType.MouseButton1 and not over(l.chip, input.Position) then
		stopListening()
		return true
	end
	if device ~= l.device then
		return false
	end
	lastCapture = os.clock()
	if not Controls.IsReserved(code) then
		Controls.Set(l.action, l.device :: any, code)
	end
	stopListening()
	if device == "Pad" and l.chip.Parent then
		GuiService.SelectedObject = l.chip
	end
	return true
end

for name, row in bindRows do
	if not lockedAction[name] then
		for _, device in { "Kb", "Pad" } do
			local chip = row:FindFirstChild("Control") and (row :: any).Control:FindFirstChild(device) :: GuiButton?
			if chip then
				local pickedChip = chip :: GuiButton
				bindCtl[pickedChip] = onPress(pickedChip, function()
					if os.clock() - lastCapture < 0.35 then
						return
					end
					if listening and listening.action == name and listening.device == device then
						stopListening()
					else
						startListening(name, device, pickedChip)
					end
				end)
			end
		end
	end
	row.MouseEnter:Connect(function()
		lightRow(row)
	end)
	row.MouseLeave:Connect(function()
		if hoverRow == row then
			lightRow(nil)
		end
	end)
end
Controls.Changed:Connect(drawBinds)
drawBinds()

GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
	local picked = GuiService.SelectedObject
	if picked and picked:IsDescendantOf(list) then
		for _, row in rows do
			if picked:IsDescendantOf(row) then
				lightRow(row)
				return
			end
		end
	end
end)

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
	elseif key == AUDIO_KEY then
		applyAudio()
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
	stopListening()
	if on then
		layout()
		drawBinds()
		iconWas = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true
		-- A first-person camera locks the mouse every frame; free it every frame after the camera while open.
		RunService:BindToRenderStep("SettingsCursor", Enum.RenderPriority.Camera.Value + 2, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
		list.CanvasPosition = Vector2.zero
		if UserInputService.GamepadEnabled and UserInputService:GetLastInputType().Name:find("Gamepad") then
			GuiService.SelectedObject = card:FindFirstChild("Close") :: GuiObject
		end
	else
		dragging = nil
		list.ScrollingEnabled = true
		lightRow(nil)
		RunService:UnbindFromRenderStep("SettingsCursor")
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
local close = card:WaitForChild("Close") :: GuiButton
onPress(close, function()
	setOpen(false)
end)
local reset = card:WaitForChild("Reset") :: GuiButton
onPress(reset, function()
	stopListening()
	Options.Reset()
	Controls.Reset()
end)

-- The Settings key (Controls: P / D-pad left) toggles in a match; gamepad B closes; D-pad left/right steps a
-- picked slider. While a key chip waits, the press goes to the chip and nothing else.
UserInputService.InputBegan:Connect(function(input, processed)
	if listening then
		capture(input)
		return
	end
	if input.KeyCode == Enum.KeyCode.ButtonB and isOpen then
		setOpen(false)
		return
	end
	if processed then
		return
	end
	if isOpen and (input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.DPadRight) then
		local picked = GuiService.SelectedObject
		for key, row in rows do
			local option = CFG[key]
			if picked and picked:IsDescendantOf(row) and option.Step then
				local dir = if input.KeyCode == Enum.KeyCode.DPadRight then 1 else -1
				Options.Set(key, Options.Get(key) + option.Step * dir)
				return
			end
		end
	end
	if Controls.Is("Settings", input) and (isOpen or gear.Visible) then
		setOpen(not isOpen)
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
