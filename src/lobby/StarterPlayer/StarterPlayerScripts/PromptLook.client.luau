--!strict
-- Every ProximityPrompt in one look (HUD sim U4: "a hand button appears only next to
-- something"): a round smoky button where the prompt is, a hand on touch, the key on PC
-- (E) and on a gamepad (X), with the action under it in small letters (prices show only
-- here, standing at the thing). A ring around the button fills while a hold is in. Tapping
-- or clicking the button works the prompt. Prompts keep their own keys, ranges and rules;
-- this only draws them (each prompt's Style is set to Custom on this client).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local HUD = GameConfig.Hud
local AMBER = HUD.Lull
local TEXT = Color3.fromRGB(240, 238, 232)
local HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local SIZE = 52

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function restyle(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and prompt.Style == Enum.ProximityPromptStyle.Default then
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end
end
for _, d in workspace:GetDescendants() do
	restyle(d)
end
workspace.DescendantAdded:Connect(restyle)

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	i.Parent = parent
	return i
end

-- A ring of two clipped halves (as on the HUD clock); returns a setter for 0..1.
local function ring(parent: GuiObject): (number) -> ()
	local arcs = {}
	for _, side in { "Right", "Left" } do
		local half = new("Frame", {
			Name = side, BackgroundTransparency = 1, ClipsDescendants = true,
			Position = if side == "Right" then UDim2.fromScale(0.5, 0) else UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(0.5, 1),
		}, parent)
		local arc = new("Frame", {
			BackgroundTransparency = 1,
			Position = if side == "Right" then UDim2.new(-1, 3, 0, 3) else UDim2.fromOffset(3, 3),
			Size = UDim2.new(2, -6, 1, -6),
		}, half)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, arc)
		local stroke = new("UIStroke", { Thickness = 3, Color = AMBER }, arc)
		local gradient = new("UIGradient", { Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1), NumberSequenceKeypoint.new(1, 1),
		}) }, stroke)
		arcs[side] = gradient
	end
	return function(p: number)
		arcs.Right.Rotation = math.clamp(p, 0, 0.5) * 360
		arcs.Left.Rotation = 180 + math.clamp(p - 0.5, 0, 0.5) * 360
	end
end

local function keyName(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return (prompt.GamepadKeyCode.Name:gsub("^Button", ""))
	end
	local name = prompt.KeyboardKeyCode.Name
	return if #name <= 2 then name else name:sub(1, 3):upper()
end

local shown: { [ProximityPrompt]: () -> () } = {}

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom or shown[prompt] then
		return
	end
	local board = new("BillboardGui", {
		Name = "Prompt", AlwaysOnTop = true, Active = true, ResetOnSpawn = false,
		Size = UDim2.fromOffset(160, SIZE + 30), Adornee = prompt.Parent,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local button = new("TextButton", {
		Name = "Button", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
	}, board)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, button)
	new("UIStroke", { Color = TEXT, Transparency = 0.5, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	local pop = new("UIScale", {}, button)
	if inputType == Enum.ProximityPromptInputType.Touch then
		new("ImageLabel", {
			Name = "Hand", BackgroundTransparency = 1, Image = HUD.Icons.Hand, ImageColor3 = AMBER,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.52, 0.52),
		}, button)
	else
		new("TextLabel", {
			Name = "Key", BackgroundTransparency = 1, Text = keyName(prompt, inputType), FontFace = HEAVY,
			TextSize = 20, TextColor3 = TEXT, Size = UDim2.fromScale(1, 1),
		}, button)
	end
	local setFill = ring(button)
	setFill(0)
	local action = new("TextLabel", {
		Name = "Action", BackgroundTransparency = 1, FontFace = BOLD, TextSize = 14, TextColor3 = TEXT,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, SIZE + 6), Size = UDim2.new(1, 0, 0, 18),
		Text = string.upper(prompt.ActionText),
	}, board)
	new("UIStroke", { Transparency = 0.4 }, action)
	board.Parent = playerGui

	local holdStart: number? = nil
	local connections = {}
	local function track(c: RBXScriptConnection)
		table.insert(connections, c)
	end
	track(prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		action.Text = string.upper(prompt.ActionText)
	end))
	track(button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end))
	track(button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end))
	track(prompt.PromptButtonHoldBegan:Connect(function()
		holdStart = os.clock()
	end))
	track(prompt.PromptButtonHoldEnded:Connect(function()
		holdStart = nil
		setFill(0)
	end))
	track(prompt.Triggered:Connect(function()
		holdStart = nil
		setFill(0)
		pop.Scale = 1.15
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end))
	track(RunService.RenderStepped:Connect(function()
		if holdStart and prompt.HoldDuration > 0 then
			setFill((os.clock() - holdStart) / prompt.HoldDuration)
		end
		button.BackgroundTransparency = if holdStart then 0.3 else 0.45
	end))

	shown[prompt] = function()
		for _, c in connections do
			c:Disconnect()
		end
		board:Destroy()
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	local close = shown[prompt]
	if close then
		shown[prompt] = nil
		close()
	end
end)
