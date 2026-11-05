--!strict
-- Shared.Controls: every game action the player can press, its mouse-and-keyboard and controller defaults, the
-- player's own bindings, and the helpers every input script uses instead of hard-coded keys.
--
--   Controls.Is(action, input)        does this InputObject press the action (either device)?
--   Controls.Inputs(actions)          every key of one or more actions, for ContextActionService
--   Controls.Bind(name, actions, fn, priority?) / Controls.Unbind(name)
--                                     a ContextActionService binding that follows rebinds by itself
--   Controls.Set(action, device, key) rebind (device "Kb" or "Pad"); a key another action holds swaps the two
--   Controls.Reset()                  back to the defaults
--   Controls.Glyph(action, device) / Controls.Image(key)   what to show on a key chip
--   Controls.PromptTakes(input)       a use prompt on screen owns this press (so X/E doesn't also reload)
--   Controls.Changed(action?)         fires after any rebind
--
-- Saving: the bindings that differ from the defaults go into Shared.Options under "Binds" (SettingsServer keeps
-- it in Profile with the other settings).
--
-- No two actions share a key, except where the game picks by situation (SHARED):
--   Reload + Interact   a use prompt in front of you takes the press, otherwise it reloads.
--   Crouch + Revive     while downed the press gets you up, otherwise it crouches.
--   Interact + Revive   while downed the press gets you up, otherwise it uses.
-- Movement (WASD / left stick), look (mouse / right stick) and Jump (Space / A) are fixed.

local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

export type Code = Enum.KeyCode | Enum.UserInputType
export type Device = "Kb" | "Pad"
export type Action = {
	Name: string,
	Label: string,
	Kb: { Code },
	Pad: { Code },
	Locked: boolean?,
	-- ProximityPrompts take only key codes, so these can't go on a mouse button.
	KeyOnly: boolean?,
	-- Shown and bound only when ReplicatedStorage.Shared has this module (the place has the feature).
	Requires: string?,
}

local K = Enum.KeyCode
local M = Enum.UserInputType

local Controls = {}

-- Defaults follow the Call of Duty controller layout (Default preset) and the usual PC shooter keys.
Controls.Actions = {
	{ Name = "Fire", Label = "Shoot", Kb = { M.MouseButton1 }, Pad = { K.ButtonR2 } },
	{ Name = "Aim", Label = "Aim down sights", Kb = { M.MouseButton2 }, Pad = { K.ButtonL2 } },
	{ Name = "Reload", Label = "Reload", Kb = { K.R }, Pad = { K.ButtonX } },
	{ Name = "Interact", Label = "Use / open", Kb = { K.E }, Pad = { K.ButtonX }, KeyOnly = true },
	{ Name = "SwitchWeapon", Label = "Next weapon", Kb = {}, Pad = { K.ButtonY } },
	{ Name = "Sprint", Label = "Sprint", Kb = { K.LeftShift }, Pad = { K.ButtonL3 } },
	{ Name = "Crouch", Label = "Crouch / slide", Kb = { K.C, K.LeftControl }, Pad = { K.ButtonB } },
	{ Name = "Revive", Label = "Get back up", Kb = { K.E }, Pad = { K.ButtonB }, KeyOnly = true },
	{ Name = "Jump", Label = "Jump", Kb = { K.Space }, Pad = { K.ButtonA }, Locked = true },
	{ Name = "Lethal", Label = "Lethal gear", Kb = { K.G }, Pad = { K.ButtonR1 }, Requires = "Gear" },
	{ Name = "Tactical", Label = "Tactical gear", Kb = { K.Q, K.T }, Pad = { K.ButtonL1 }, Requires = "Gear" },
	{ Name = "Field", Label = "Field gear", Kb = { K.X }, Pad = { K.DPadRight }, Requires = "Gear" },
	{ Name = "Flashlight", Label = "Flashlight", Kb = { K.F }, Pad = { K.DPadUp } },
	{ Name = "Bandage", Label = "Bandage", Kb = { K.H }, Pad = { K.DPadDown } },
	{ Name = "Slot1", Label = "Weapon slot 1", Kb = { K.One }, Pad = {} },
	{ Name = "Slot2", Label = "Weapon slot 2", Kb = { K.Two }, Pad = {} },
	{ Name = "Slot3", Label = "Weapon slot 3", Kb = { K.Three }, Pad = {} },
	{ Name = "Slot4", Label = "Weapon slot 4", Kb = { K.Four }, Pad = {} },
	{ Name = "Shop", Label = "Field shop", Kb = { K.B }, Pad = { K.ButtonSelect }, Requires = "FieldShop" },
	{ Name = "Settings", Label = "Settings", Kb = { K.P }, Pad = { K.DPadLeft } },
} :: { Action }

local SHARED: { [string]: { [string]: boolean } } = {
	Reload = { Interact = true },
	Interact = { Reload = true, Revive = true },
	Crouch = { Revive = true },
	Revive = { Crouch = true, Interact = true },
}

-- Keys Roblox or the fixed controls own.
local RESERVED: { [any]: boolean } = {}
for _, code in {
	K.Escape, K.Slash, K.Tab, K.Backquote, K.W, K.A, K.S, K.D, K.Up, K.Down, K.Left, K.Right,
	K.F9, K.F10, K.F11, K.F12, K.LeftSuper, K.RightSuper, K.LeftAlt, K.RightAlt, K.Menu, K.Unknown,
	K.ButtonStart, K.Thumbstick1, K.Thumbstick2,
} do
	RESERVED[code] = true
end

local byName: { [string]: Action } = {}
local binds: { [string]: { Kb: { Code }, Pad: { Code } } } = {}

local function defaults()
	for _, a in Controls.Actions do
		binds[a.Name] = { Kb = table.clone(a.Kb), Pad = table.clone(a.Pad) }
	end
end
for _, a in Controls.Actions do
	byName[a.Name] = a
end
defaults()

local changed = Instance.new("BindableEvent")
Controls.Changed = changed.Event

-- True while the settings screen waits for a key; every action reads as not pressed meanwhile.
Controls.Listening = false

-- Helpers -----------------------------------------------------------------------------------------------------------

local function shares(a: string, b: string): boolean
	local s = SHARED[a]
	return s ~= nil and s[b] == true
end

local function isPadCode(code: any): boolean
	if typeof(code) ~= "EnumItem" or code.EnumType ~= Enum.KeyCode then
		return false
	end
	local name = code.Name
	return name:sub(1, 6) == "Button" or name:sub(1, 4) == "DPad" or name:sub(1, 10) == "Thumbstick"
end

-- Which column an input belongs to: the controller's (any Gamepad input, or a controller button however it
-- arrives) or the keyboard and mouse.
function Controls.DeviceOf(input: InputObject): Device
	if input.UserInputType.Name:sub(1, 7) == "Gamepad" or isPadCode(input.KeyCode) then
		return "Pad"
	end
	return "Kb"
end

-- Per place: GameConfig.Controls = { Hide = { "Slot4" } } drops actions the place doesn't have (the campaign's
-- hotbar has three slots); ShowAll = true lists every action anyway (the lobby, where players set keys up before
-- they play). Bindings are kept for every action in every place, so a key set in one place is the same in all.
local placeConfig: any = nil
local function controlsConfig(): any
	if placeConfig == nil then
		local module = script.Parent:FindFirstChild("GameConfig")
		local ok, config = pcall(function()
			return module and (require(module) :: any).Controls
		end)
		placeConfig = if ok and type(config) == "table" then config else {}
	end
	return placeConfig
end

function Controls.Available(name: string): boolean
	local a = byName[name]
	if not a then
		return false
	end
	local config = controlsConfig()
	if config.Hide and table.find(config.Hide, name) then
		return false
	end
	if a.Requires and not config.ShowAll then
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		return shared ~= nil and shared:FindFirstChild(a.Requires) ~= nil
	end
	return true
end

function Controls.Get(name: string, device: Device): { Code }
	local b = binds[name]
	return if b then b[device] else {}
end

function Controls.IsReserved(code: Code): boolean
	return RESERVED[code] == true
end

-- Can `code` go on this action for this device at all?
function Controls.CanUse(name: string, device: Device, code: Code): boolean
	local a = byName[name]
	if not a or a.Locked or RESERVED[code] then
		return false
	end
	local isPadKey = isPadCode(code)
	if (code :: any).EnumType == Enum.UserInputType then
		if device ~= "Kb" or a.KeyOnly then
			return false
		end
		return code == M.MouseButton1 or code == M.MouseButton2 or code == M.MouseButton3
	end
	return if device == "Pad" then isPadKey else not isPadKey
end

-- Is this input one of the action's keys? (Also while the settings screen listens: use it for releases.)
function Controls.Matches(name: string, input: InputObject): boolean
	local b = binds[name]
	if not b then
		return false
	end
	for _, code in b[Controls.DeviceOf(input)] do
		if code == input.KeyCode or code == input.UserInputType then
			return true
		end
	end
	return false
end

-- Does this input press the action? Never while the settings screen waits for a new key.
function Controls.Is(name: string, input: InputObject): boolean
	if Controls.Listening then
		return false
	end
	local b = binds[name]
	if not b then
		return false
	end
	for _, code in b[Controls.DeviceOf(input)] do
		if code == input.KeyCode or code == input.UserInputType then
			return true
		end
	end
	return false
end

function Controls.Inputs(names: string | { string }): { Code }
	local list = if type(names) == "table" then names else { names }
	local out: { Code } = {}
	for _, name in list do
		if Controls.Available(name) then
			local b = binds[name]
			if b then
				for _, device in { "Kb", "Pad" } do
					for _, code in (b :: any)[device] do
						if not table.find(out, code) then
							table.insert(out, code)
						end
					end
				end
			end
		end
	end
	return out
end

-- Every pair of actions that shares a key it shouldn't (empty when the bindings are clean).
function Controls.Conflicts(): { string }
	local out = {}
	for i, a in Controls.Actions do
		for j = i + 1, #Controls.Actions do
			local b = Controls.Actions[j]
			if Controls.Available(a.Name) and Controls.Available(b.Name) and not shares(a.Name, b.Name) then
				for _, device in { "Kb", "Pad" } do
					for _, code in (binds[a.Name] :: any)[device] do
						if table.find((binds[b.Name] :: any)[device], code) then
							table.insert(out, string.format("%s/%s %s %s", a.Name, b.Name, device, (code :: any).Name))
						end
					end
				end
			end
		end
	end
	return out
end

-- Saving ------------------------------------------------------------------------------------------------------------

local function codeName(code: Code): string
	return (if (code :: any).EnumType == Enum.UserInputType then "M." else "K.") .. (code :: any).Name
end

local function parseCode(text: string): Code?
	local kind, name = text:match("^([KM])%.(%w+)$")
	if not kind or not name then
		return nil
	end
	local ok, item = pcall(function()
		return if kind == "K" then (Enum.KeyCode :: any)[name] else (Enum.UserInputType :: any)[name]
	end)
	return if ok then item else nil
end

local function sameList(a: { Code }, b: { Code }): boolean
	if #a ~= #b then
		return false
	end
	for i, code in a do
		if b[i] ~= code then
			return false
		end
	end
	return true
end

-- Only what differs from the defaults: "Reload.Pad=K.ButtonY;SwitchWeapon.Pad=K.ButtonX".
function Controls.Encode(): string
	local parts = {}
	for _, a in Controls.Actions do
		for _, device in { "Kb", "Pad" } do
			local list = (binds[a.Name] :: any)[device]
			if not sameList(list, (a :: any)[device]) then
				local names = {}
				for _, code in list do
					table.insert(names, codeName(code))
				end
				table.insert(parts, a.Name .. "." .. device .. "=" .. table.concat(names, "+"))
			end
		end
	end
	return table.concat(parts, ";")
end

local function decode(text: string)
	defaults()
	for entry in text:gmatch("[^;]+") do
		local name, device, rest = entry:match("^(%w+)%.(%a+)=(.*)$")
		local a = name and byName[name]
		if a and not a.Locked and (device == "Kb" or device == "Pad") then
			local list = {}
			for piece in rest:gmatch("[^+]+") do
				local code = parseCode(piece)
				if code and Controls.CanUse(a.Name, device :: Device, code) and not table.find(list, code) then
					table.insert(list, code)
				end
			end
			-- An empty entry is a deliberate unbind; one whose keys are all unreadable keeps the default.
			if #list > 0 or rest == "" then
				(binds[a.Name] :: any)[device] = list
			end
		end
	end
	-- A saved set that clashes (old save, new defaults): the later action in the list gives the key up.
	for i, a in Controls.Actions do
		for j = i + 1, #Controls.Actions do
			local b = Controls.Actions[j]
			if not shares(a.Name, b.Name) then
				for _, device in { "Kb", "Pad" } do
					local lb = (binds[b.Name] :: any)[device]
					for _, code in (binds[a.Name] :: any)[device] do
						local at = table.find(lb, code)
						if at then
							table.remove(lb, at)
						end
					end
				end
			end
		end
	end
end

local Options: any = nil
local function save()
	if Options and Options.SetRaw then
		Options.SetRaw("Binds", Controls.Encode())
	end
end

-- Rebinding ---------------------------------------------------------------------------------------------------------

-- Put `code` on the action. Any other action holding it (unless they share by design) takes this action's old key,
-- if that key is free for it; otherwise it's left unbound. Returns whether it took.
function Controls.Set(name: string, device: Device, code: Code): boolean
	if not Controls.CanUse(name, device, code) then
		return false
	end
	local mine = (binds[name] :: any)[device] :: { Code }
	local old = mine[1]
	for _, other in Controls.Actions do
		if other.Name ~= name and not shares(name, other.Name) then
			local list = (binds[other.Name] :: any)[device] :: { Code }
			if other.Locked and table.find(list, code) then
				return false
			end
		end
	end
	for _, other in Controls.Actions do
		if other.Name ~= name and not shares(name, other.Name) then
			local list = (binds[other.Name] :: any)[device] :: { Code }
			local at = table.find(list, code)
			if at then
				table.remove(list, at)
				if #list == 0 and old and old ~= code and Controls.CanUse(other.Name, device, old) then
					-- The swap only lands if nobody else (who doesn't share with `other`) keeps `old`.
					local free = true
					for _, third in Controls.Actions do
						if third.Name ~= name and third.Name ~= other.Name and not shares(other.Name, third.Name)
							and table.find((binds[third.Name] :: any)[device], old) then
							free = false
						end
					end
					if free then
						table.insert(list, old)
					end
				end
				changed:Fire(other.Name)
			end
		end
	end
	;(binds[name] :: any)[device] = { code }
	changed:Fire(name)
	save()
	return true
end

function Controls.Reset()
	defaults()
	changed:Fire(nil)
	save()
end

-- Labels ------------------------------------------------------------------------------------------------------------

local PAD_TEXT: { [string]: string } = {
	ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y",
	ButtonR1 = "RB", ButtonL1 = "LB", ButtonR2 = "RT", ButtonL2 = "LT", ButtonR3 = "RS", ButtonL3 = "LS",
	DPadUp = "D-PAD UP", DPadDown = "D-PAD DOWN", DPadLeft = "D-PAD LEFT", DPadRight = "D-PAD RIGHT",
	ButtonSelect = "VIEW",
}
local KB_TEXT: { [string]: string } = {
	MouseButton1 = "LEFT CLICK", MouseButton2 = "RIGHT CLICK", MouseButton3 = "MIDDLE CLICK",
	LeftShift = "SHIFT", RightShift = "R-SHIFT", LeftControl = "CTRL", RightControl = "R-CTRL",
	Return = "ENTER", CapsLock = "CAPS", Backspace = "BACKSPACE", Space = "SPACE",
}

function Controls.CodeText(code: Code?): string
	if code == nil then
		return "—"
	end
	local name = (code :: any).Name
	if PAD_TEXT[name] then
		return PAD_TEXT[name]
	elseif KB_TEXT[name] then
		return KB_TEXT[name]
	end
	if (code :: any).EnumType == Enum.KeyCode then
		local ok, text = pcall(UserInputService.GetStringForKeyCode, UserInputService, code :: Enum.KeyCode)
		if ok and type(text) == "string" and text ~= "" and #text <= 3 then
			return text:upper()
		end
	end
	return name:upper()
end

function Controls.Glyph(name: string, device: Device): string
	return Controls.CodeText(Controls.Get(name, device)[1])
end

-- Short form for small HUD key plates (gear slots, hotbar, revive, shop chip): at most about four characters.
local SHORT: { [string]: string } = {
	MouseButton1 = "LMB", MouseButton2 = "RMB", MouseButton3 = "MMB",
	LeftShift = "SHFT", RightShift = "SHFT", LeftControl = "CTRL", RightControl = "CTRL", Space = "SPC",
	Return = "ENT", CapsLock = "CAPS", Backspace = "BKSP",
	DPadUp = "D^", DPadDown = "Dv", DPadLeft = "D<", DPadRight = "D>", ButtonSelect = "VIEW",
}

function Controls.ShortText(code: Code?): string
	if code == nil then
		return ""
	end
	return SHORT[(code :: any).Name] or Controls.CodeText(code)
end

function Controls.Short(name: string, device: Device): string
	return Controls.ShortText(Controls.Get(name, device)[1])
end

-- The column the player is playing with right now (Shared.Platform): "Pad" on a controller, else "Kb".
local platform: any = nil
function Controls.ActiveDevice(): Device
	if platform == nil then
		local module = script.Parent:FindFirstChild("Platform")
		platform = if module then require(module) else false
	end
	return if platform and platform.IsGamepad() then "Pad" else "Kb"
end

-- Roblox's own controller button picture (Xbox or PlayStation, whichever is plugged in); "" when there is none.
function Controls.Image(code: Code?): string
	if code == nil or (code :: any).EnumType ~= Enum.KeyCode then
		return ""
	end
	local ok, image = pcall(UserInputService.GetImageForKeyCode, UserInputService, code :: Enum.KeyCode)
	return if ok and type(image) == "string" then image else ""
end

-- ContextActionService bindings that follow rebinds -----------------------------------------------------------------

type Live = { names: string | { string }, handler: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult?, priority: number? }
local live: { [string]: Live } = {}

local function apply(casName: string, entry: Live)
	ContextActionService:UnbindAction(casName)
	local codes = Controls.Inputs(entry.names)
	if #codes == 0 then
		return
	end
	if entry.priority then
		ContextActionService:BindActionAtPriority(casName, entry.handler, false, entry.priority, table.unpack(codes :: { any }))
	else
		ContextActionService:BindAction(casName, entry.handler, false, table.unpack(codes :: { any }))
	end
end

function Controls.Bind(casName: string, names: string | { string }, handler: any, priority: number?)
	local entry = { names = names, handler = handler, priority = priority }
	live[casName] = entry
	apply(casName, entry)
end

function Controls.Unbind(casName: string)
	live[casName] = nil
	ContextActionService:UnbindAction(casName)
end

Controls.Changed:Connect(function()
	for casName, entry in live do
		apply(casName, entry)
	end
end)

-- Use prompts -------------------------------------------------------------------------------------------------------
-- Server prompts are made with E / X (Revive prompts with E / B). On this client they take the player's own
-- Interact (or Revive) keys, and Controls remembers which prompts are on screen.

local shown: { [ProximityPrompt]: boolean } = {}
local known: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function remap(prompt: ProximityPrompt)
	if prompt:GetAttribute("BaseKb") == nil then
		prompt:SetAttribute("BaseKb", prompt.KeyboardKeyCode.Name)
		prompt:SetAttribute("BasePad", prompt.GamepadKeyCode.Name)
	end
	known[prompt] = true
	local baseKb, basePad = prompt:GetAttribute("BaseKb"), prompt:GetAttribute("BasePad")
	local action = if basePad == "ButtonB" then "Revive" elseif baseKb == "E" or basePad == "ButtonX" then "Interact" else nil
	if not action then
		return
	end
	local kb = Controls.Get(action, "Kb")[1]
	local pad = Controls.Get(action, "Pad")[1]
	if baseKb == "E" and kb and (kb :: any).EnumType == Enum.KeyCode then
		prompt.KeyboardKeyCode = kb :: Enum.KeyCode
	end
	if (basePad == "ButtonX" or basePad == "ButtonB") and pad and (pad :: any).EnumType == Enum.KeyCode then
		prompt.GamepadKeyCode = pad :: Enum.KeyCode
	end
end

-- A use prompt is on screen and listens for exactly this press.
function Controls.PromptTakes(input: InputObject): boolean
	local pad = Controls.DeviceOf(input) == "Pad"
	for prompt in shown do
		if not prompt.Parent or not prompt.Enabled then
			shown[prompt] = nil
		elseif (pad and prompt.GamepadKeyCode == input.KeyCode) or (not pad and prompt.KeyboardKeyCode == input.KeyCode) then
			return true
		end
	end
	return false
end

if RunService:IsClient() and RunService:IsRunning() then
	ProximityPromptService.PromptShown:Connect(function(prompt)
		remap(prompt)
		shown[prompt] = true
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		shown[prompt] = nil
	end)
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			task.defer(remap, d)
		end
	end)
	task.defer(function()
		for _, d in workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				remap(d)
			end
		end
	end)
	Controls.Changed:Connect(function()
		for prompt in known do
			if prompt.Parent then
				remap(prompt)
			end
		end
	end)

	-- Load the saved set once Options has it, and follow later loads.
	local shared = script.Parent
	local optionsModule = shared:FindFirstChild("Options")
	if optionsModule then
		Options = require(optionsModule) :: any
		local function load()
			local raw = Options.Get("Binds")
			if type(raw) == "string" and raw ~= Controls.Encode() then
				decode(raw)
				changed:Fire(nil)
			end
		end
		Options.Changed:Connect(function(key)
			if key == "Binds" then
				load()
			end
		end)
		load()
	end
end

return Controls
