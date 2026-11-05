-- One-off Studio build (Edit mode): adds the controller rows and the CONTROLS section to the authored settings
-- screen StarterGui.Settings, styled from its own existing rows (same fonts, chip colours, sizes). Re-runnable: it
-- replaces the rows it made before. Run it BEFORE GameConfig.Settings.Order lists PadSens and AimAssist, because
-- SettingsClient waits for one row per listed key.
--   PadSens   slider (copy of LookSens)
--   AimAssist picker STANDARD / PRECISION / OFF (copy of Graphics)
--   ControlsHead, then Bind_<Action> per Shared.Controls action: label, keyboard chip (Kb), controller chip (Pad
--   with a Glyph image for Roblox's own button picture).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Controls = require(ReplicatedStorage.Shared.Controls)

local list = StarterGui.Settings.Panel.Card.List
local sliderRow = list:FindFirstChild("LookSens")
local pickerRow = list:FindFirstChild("Graphics")
assert(sliderRow and pickerRow, "settings rows LookSens / Graphics not found")
local chipTemplate = pickerRow.Control:FindFirstChildWhichIsA("TextButton")
local out = {}

for _, child in list:GetChildren() do
	if child.Name == "PadSens" or child.Name == "AimAssist" or child.Name == "ControlsHead" or child.Name:match("^Bind_") then
		child:Destroy()
	end
end

-- PadSens
local pad = sliderRow:Clone()
pad.Name = "PadSens"
pad.Label.Text = "Controller look speed"
pad.Parent = list

-- AimAssist
local assist = pickerRow:Clone()
assist.Name = "AimAssist"
assist.Label.Text = "Aim assist"
for _, b in assist.Control:GetChildren() do
	if b:IsA("TextButton") then
		b:Destroy()
	end
end
for i, choice in { "Standard", "Precision", "Off" } do
	local b = chipTemplate:Clone()
	b.Name = choice
	b.Text = choice:upper()
	b.LayoutOrder = i
	b.Size = UDim2.fromOffset(if choice == "Off" then 60 else 104, 32)
	b.Parent = assist.Control
end
assist.Parent = list

-- CONTROLS header: the section word on the left, the two column names over the chips.
local head = Instance.new("Frame")
head.Name = "ControlsHead"
head.BackgroundTransparency = 1
head.Size = UDim2.new(1, 0, 0, 64)
local word = sliderRow.Label:Clone()
word.Name = "Label"
word.Text = "CONTROLS"
word.FontFace = StarterGui.Settings.Panel.Card.Title.FontFace
word.TextSize = 24
word.TextColor3 = StarterGui.Settings.Panel.Card.Close.TextColor3
word.Size = UDim2.new(0.5, 0, 0, 36)
word.Position = UDim2.new(0, 0, 1, -40)
word.Parent = head
for _, col in { { "KbHead", "KEYBOARD", -140 }, { "PadHead", "CONTROLLER", 0 } } do
	local l = sliderRow.Control.Value:Clone()
	l.Name = col[1]
	l.Text = col[2]
	l.TextSize = 12
	l.TextColor3 = sliderRow.Label.TextColor3
	l.TextTransparency = 0.45
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.AnchorPoint = Vector2.new(1, 1)
	l.Size = UDim2.fromOffset(136, 20)
	l.Position = UDim2.new(1, col[3], 1, -6)
	l.Parent = head
end
local headDivider = sliderRow.Divider:Clone()
headDivider.Parent = head
head.Parent = list

-- One row per action
local made = 0
for _, action in Controls.Actions do
	if Controls.Available(action.Name) then
		local row = Instance.new("Frame")
		row.Name = "Bind_" .. action.Name
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 50)
		local label = sliderRow.Label:Clone()
		label.Text = action.Label
		label.Parent = row
		sliderRow.Divider:Clone().Parent = row
		local control = Instance.new("Frame")
		control.Name = "Control"
		control.BackgroundTransparency = 1
		control.AnchorPoint = Vector2.new(1, 0.5)
		control.Position = UDim2.fromScale(1, 0.5)
		control.Size = UDim2.fromOffset(276, 32)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = control
		for i, device in { "Kb", "Pad" } do
			local chip = chipTemplate:Clone()
			chip.Name = device
			chip.LayoutOrder = i
			chip.Size = UDim2.fromOffset(136, 32)
			chip.Text = Controls.Glyph(action.Name, device)
			if device == "Pad" then
				local glyph = Instance.new("ImageLabel")
				glyph.Name = "Glyph"
				glyph.BackgroundTransparency = 1
				glyph.AnchorPoint = Vector2.new(0.5, 0.5)
				glyph.Position = UDim2.fromScale(0.5, 0.5)
				glyph.Size = UDim2.fromOffset(26, 26)
				glyph.ScaleType = Enum.ScaleType.Fit
				glyph.Visible = false
				glyph.Parent = chip
			end
			if action.Locked then
				chip.AutoButtonColor = false
				chip.Selectable = false
				chip.TextTransparency = 0.5
			end
			chip.Parent = control
		end
		control.Parent = row
		row.Parent = list
		made += 1
	end
end

-- Layout order: settings keys first (in the order GameConfig will list them), then the CONTROLS section.
local order = { "LookSens", "AimSens", "PadSens", "AimAssist", "InvertY", "Gyro", "GyroSens", "GyroFlip", "ButtonSize",
	"Graphics", "Fov", "Bob", "Gore", "VoiceVol", "MenuVol", "MyVoice", "Backdrop" }
for i, key in order do
	local row = list:FindFirstChild(key)
	if row then
		row.LayoutOrder = i * 10
	end
end
head.LayoutOrder = 1000
for i, action in Controls.Actions do
	local row = list:FindFirstChild("Bind_" .. action.Name)
	if row then
		row.LayoutOrder = 1000 + i
	end
end
table.insert(out, "rows: PadSens, AimAssist, ControlsHead, " .. made .. " bind rows")
return table.concat(out, "\n")
