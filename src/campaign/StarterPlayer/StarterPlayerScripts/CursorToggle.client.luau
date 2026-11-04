--!strict
-- Left Alt frees the mouse in a match so players can click the gear, the hotbar and other UI;
-- Alt again locks it back for aiming. While free, a full-screen Modal catcher behind every
-- other ScreenGui keeps the first-person camera from re-locking the cursor and swallows clicks
-- on empty screen, so a stray click doesn't fire the gun (GunClient skips processed input).
-- Sets the player attribute CursorFree while the cursor is out.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local KEYS = { [Enum.KeyCode.LeftAlt] = true, [Enum.KeyCode.RightAlt] = true }
local FONT = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local TEXT = Color3.fromRGB(240, 238, 232)
local DARK = Color3.fromRGB(16, 18, 22)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "Cursor"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = -50 -- under every other screen, so their buttons still take the click
gui.Parent = playerGui

local catcher = Instance.new("TextButton")
catcher.Name = "Catcher"
catcher.Size = UDim2.fromScale(1, 1)
catcher.BackgroundTransparency = 1
catcher.Text = ""
catcher.AutoButtonColor = false
catcher.Selectable = false
catcher.Modal = true
catcher.Visible = false
catcher.Parent = gui

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -96)
hint.AutomaticSize = Enum.AutomaticSize.X
hint.Size = UDim2.fromOffset(0, 28)
hint.BackgroundColor3 = DARK
hint.BackgroundTransparency = 0.25
hint.FontFace = FONT
hint.TextSize = 16
hint.TextColor3 = TEXT
hint.Text = "CURSOR FREE  ·  ALT TO LOCK"
hint.Visible = false
hint.Parent = gui
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = hint
Instance.new("UICorner", hint).CornerRadius = UDim.new(0, 6)

local free = false

local function inMatch(): boolean
	local hud = playerGui:FindFirstChild("HUD") :: ScreenGui?
	local menu = playerGui:FindFirstChild("Menu") :: ScreenGui?
	return hud ~= nil and hud.Enabled and not (menu and menu.Enabled) and not player:GetAttribute("Cutscene")
end

local function setFree(on: boolean)
	if on == free then
		return
	end
	free = on
	catcher.Visible = on
	hint.Visible = on
	player:SetAttribute("CursorFree", on or nil)
	if on then
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseIconEnabled = false
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
	end
end

UserInputService.InputBegan:Connect(function(input)
	-- Not gated on processed: Alt should work even with a text box or button under the mouse.
	if KEYS[input.KeyCode] and UserInputService.MouseEnabled then
		setFree(not free and inMatch())
	end
end)

-- Back to aiming when the match ends, a cutscene starts or the character dies.
RunService.Heartbeat:Connect(function()
	if free and not inMatch() then
		setFree(false)
	end
end)
player.CharacterAdded:Connect(function()
	setFree(false)
end)
