-- Client-side input type detection. Returns one of:
--   "KeyboardAndMouse", "Touch", "Gamepad"
-- Uses UserInputService.PreferredInput when the engine has it, otherwise falls back
-- to device flags plus the last input type. Switches live (e.g. a touchscreen laptop
-- that picks up the mouse) and fires Changed.
--
-- Testing: set the LocalPlayer attribute "DebugInputMode" to force a mode.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Platform = {}

local changedEvent = Instance.new("BindableEvent")
Platform.Changed = changedEvent.Event

local VALID = { KeyboardAndMouse = true, Touch = true, Gamepad = true }

local current: string? = nil
local detected: string = "KeyboardAndMouse"
local override: string? = nil

local function apply()
	local mode = override or detected
	if mode ~= current then
		current = mode
		changedEvent:Fire(mode)
	end
end

local function fromPreferredInput(): string?
	local ok, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if not ok or preferred == nil then
		return nil
	end
	if preferred == Enum.PreferredInput.Touch then
		return "Touch"
	elseif preferred == Enum.PreferredInput.KeyboardAndMouse then
		return "KeyboardAndMouse"
	end
	-- Gamepad and MicroGamepad
	return "Gamepad"
end

local function fromDeviceFlags(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "KeyboardAndMouse"
end

local GAMEPAD_TYPES = {}
for i = 1, 8 do
	GAMEPAD_TYPES[Enum.UserInputType["Gamepad" .. i]] = true
end

-- Fallback path only. MouseMovement is ignored because touch devices can emit
-- synthetic mouse moves; a real click, wheel or key press is needed to switch to PC.
local function fromInputType(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif GAMEPAD_TYPES[inputType] then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
		or inputType == Enum.UserInputType.MouseWheel then
		return "KeyboardAndMouse"
	end
	return nil
end

function Platform.Get(): string
	return current or detected
end

function Platform.IsTouch(): boolean
	return Platform.Get() == "Touch"
end

function Platform.IsGamepad(): boolean
	return Platform.Get() == "Gamepad"
end

function Platform.IsKeyboardAndMouse(): boolean
	return Platform.Get() == "KeyboardAndMouse"
end

-- Start detection ------------------------------------------------------------

local preferred = fromPreferredInput()
if preferred then
	detected = preferred
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		detected = fromPreferredInput() or detected
		apply()
	end)
else
	detected = fromDeviceFlags()
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local mode = fromInputType(inputType)
		if mode then
			detected = mode
			apply()
		end
	end)
end

local localPlayer = Players.LocalPlayer
if localPlayer then
	local function readOverride()
		local value = localPlayer:GetAttribute("DebugInputMode")
		override = if typeof(value) == "string" and VALID[value] then value else nil
		apply()
	end
	localPlayer:GetAttributeChangedSignal("DebugInputMode"):Connect(readOverride)
	readOverride()
end

apply()

return Platform
