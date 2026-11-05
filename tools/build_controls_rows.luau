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
-- Text chips (zombies, campaign) or authored image chips with a Word label (the lobby's PNG skin).
local chipTemplate = pickerRow.Control:FindFirstChildWhichIsA("GuiButton") :: GuiButton
assert(chipTemplate, "no chip in the Graphics row")
local out = {}

local function setChipText(chip: Instance, text: string)
	local word = chip:FindFirstChild("Word")
	if word and word:IsA("TextLabel") then
		word.Text = text
	elseif chip:IsA("TextButton") then
		chip.Text = text
	end
end

local card = StarterGui.Settings.Panel.Card
local upperLabels = sliderRow.Label.Text == sliderRow.Label.Text:upper()
local accent = if card.Close:IsA("TextButton") then card.Close.TextColor3 else Color3.fromRGB(255, 176, 60)

for _, child in list:GetChildren() do
	if child.Name == "PadSens" or child.Name == "AimAssist" or child.Name == "ControlsHead" or child.Name:match("^Bind_") then
		child:Destroy()
	end
end

-- PadSens
local pad = sliderRow:Clone()
pad.Name = "PadSens"
pad.Label.Text = if upperLabels then "CONTROLLER LOOK SPEED" else "Controller look speed"
pad.Parent = list

-- AimAssist
local assist = pickerRow:Clone()
assist.Name = "AimAssist"
assist.Label.Text = if upperLabels then "AIM ASSIST" else "Aim assist"
for _, b in assist.Control:GetChildren() do
	if b:IsA("TextButton") then
		b:Destroy()
	end
end
for i, choice in { "Standard", "Precision", "Off" } do
	local b = chipTemplate:Clone()
	b.Name = choice
	setChipText(b, choice:upper())
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
word.FontFace = card.Title.FontFace
word.TextSize = 24
word.TextColor3 = accent
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
		row.Size = sliderRow.Size -- same height as the authored rows
		local label = sliderRow.Label:Clone()
		-- Same case as the authored labels (the lobby's skin writes them in capitals).
		label.Text = if upperLabels then action.Label:upper() else action.Label
		label.Parent = row
		sliderRow.Divider:Clone().Parent = row
		local plate = sliderRow:FindFirstChild("Plate")
		if plate then
			plate:Clone().Parent = row
		end
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
			setChipText(chip, Controls.Glyph(action.Name, device))
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
				local word = chip:FindFirstChild("Word")
				if word and word:IsA("TextLabel") then
					word.TextTransparency = 0.5
				elseif chip:IsA("TextButton") then
					chip.TextTransparency = 0.5
				end
				if chip:IsA("ImageButton") then
					chip.ImageTransparency = 0.4
				end
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
