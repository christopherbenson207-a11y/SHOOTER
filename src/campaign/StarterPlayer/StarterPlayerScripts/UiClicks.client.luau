--!strict
-- UiClicks (5 Nov 2026, "UIs need change in all places"): in-match menus and HUD buttons get the same UI sounds as
-- the lobby menu, from Shared.Menu.UiSound. Any GuiButton under PlayerGui plays "Click" when pressed and "Hover" when
-- the mouse moves onto it or a gamepad selects it. Silent: guis that play their own sounds or must stay quiet
-- (SKIP_GUIS), invisible input catchers, and anything under an instance with the attribute NoUiSound = true.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SKIP_GUIS = {
	TouchControls = true, -- fire / aim / jump: a click on every shot would be noise
	FieldShop = true, -- already plays its own UiSound cues
	CrateOpen = true, -- same
}

local UiSound: any = nil
do
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	local menu = shared and shared:WaitForChild("Menu", 10)
	local mod = menu and menu:WaitForChild("UiSound", 10)
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok and type(m) == "table" and type(m.Play) == "function" then
			UiSound = m
		end
	end
end
if not UiSound then
	warn("[UiClicks] Shared.Menu.UiSound missing; HUD buttons stay silent")
	return
end

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local hooked: { [GuiButton]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Checked when the sound would play, since a button can change look or move between guis after it is made.
local function silent(b: GuiButton): boolean
	local x: Instance? = b
	while x and x ~= playerGui do
		if x:GetAttribute("NoUiSound") == true then
			return true
		end
		if x:IsA("ScreenGui") and SKIP_GUIS[x.Name] then
			return true
		end
		x = x.Parent
	end
	local shown = b.BackgroundTransparency < 1
		or (b:IsA("TextButton") and b.Text ~= "" and b.TextTransparency < 1)
		or (b:IsA("ImageButton") and b.Image ~= "" and b.ImageTransparency < 1)
		or b:FindFirstChildWhichIsA("GuiObject") ~= nil
	return not shown -- an invisible full-screen catcher is not a button the player sees
end

local function hook(b: GuiButton)
	if hooked[b] then
		return
	end
	hooked[b] = true
	b.Activated:Connect(function()
		if not silent(b) then
			UiSound.Play("Click")
		end
	end)
	b.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() == Enum.UserInputType.MouseMovement and b.Active and not silent(b) then
			UiSound.Play("Hover")
		end
	end)
	b.SelectionGained:Connect(function()
		if not silent(b) then
			UiSound.Play("Hover")
		end
	end)
end

for _, d in playerGui:GetDescendants() do
	if d:IsA("GuiButton") then
		hook(d)
	end
end
playerGui.DescendantAdded:Connect(function(d)
	if d:IsA("GuiButton") then
		hook(d)
	end
end)
