--!strict
-- Glows in the world instead of words on screen (HUD sim U4), all drawn on this client:
--   * a window being torn: when a board comes off (Barricades sets Torn on it), its
--     barricade glows amber through the walls for GameConfig.Hud.WindowGlow seconds;
--   * the radio tower while you carry a part (character CarryingPart): the cabinet glows
--     amber through everything, so you can find it from town;
--   * the part whose turn it is (PartOut: lying in town or being carried): its lamp on the
--     cabinet (Lamp1..Lamp4 in Parts.Order) glows solid amber and pulses;
--   * hiding spots once the Beacon is seeing you (player BeaconSeen): the nearest few within
--     HideGlowRange glow blue;
--   * Outbreak: the radio offering a contract glows amber, the nearest radio glows green while
--     you carry Scrip (bank it there), and a Hunt contract's pack (ContractTarget) glows red.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local HUD = GameConfig.Hud
local AMBER = HUD.Lull
local BLUE = Color3.fromRGB(90, 209, 255)
local HIDE_MAX = 3

local player = Players.LocalPlayer

local function glow(name: string, color: Color3): Highlight
	local h = Instance.new("Highlight")
	h.Name = name
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.Enabled = false
	h.Parent = workspace:FindFirstChild("Fx") or workspace
	return h
end

-- Windows -------------------------------------------------------------------------------------

local windowUntil: { [Instance]: number } = {}
local windowGlows: { [Instance]: Highlight } = {}

local function watchBoard(part: Instance)
	if not part:IsDescendantOf(workspace) then
		return
	end
	part:GetAttributeChangedSignal("Torn"):Connect(function()
		local barricade = part.Parent
		if part:GetAttribute("Torn") and barricade and barricade:IsA("Model") then
			windowUntil[barricade] = os.clock() + HUD.WindowGlow
		end
	end)
end
for _, part in CollectionService:GetTagged("Breakable") do
	watchBoard(part)
end
CollectionService:GetInstanceAddedSignal("Breakable"):Connect(watchBoard)

-- The tower and the hiding spots ------------------------------------------------------------

local towerGlow = glow("TowerGlow", AMBER)
local lampGlow = glow("LampGlow", AMBER)
local hideGlows: { Highlight } = {}
for i = 1, HIDE_MAX do
	hideGlows[i] = glow("HideGlow", BLUE)
end

-- Outbreak -------------------------------------------------------------------------------------

local GREEN = Color3.fromRGB(120, 230, 140)
local RED = Color3.fromRGB(255, 96, 70)
local TARGET_MAX = 6
local postGlow = glow("PostGlow", AMBER)
local bankGlow = glow("BankGlow", GREEN)
local targetGlows: { Highlight } = {}
for i = 1, TARGET_MAX do
	targetGlows[i] = glow("TargetGlow", RED)
end

local function outbreakGlows(root: BasePart?, pulse: number)
	local on = workspace:GetAttribute("WaveState") == "Outbreak" and player:GetAttribute("InMatch") == true
	local offer = if on then workspace:GetAttribute("OfferPost") else nil
	local carrying = on and (player:GetAttribute("Carried") or 0) > 0
	local offered: Model?, nearest: Model?, nearestD = nil, nil, math.huge
	for _, post in CollectionService:GetTagged("RadioPost") do
		if post:IsA("Model") and post:IsDescendantOf(workspace) and not post:GetAttribute("Reserve") then
			if offer and post:GetAttribute("Building") == offer then
				offered = post
			end
			if carrying and root then
				local d = (post:GetPivot().Position - root.Position).Magnitude
				if d < nearestD then
					nearest, nearestD = post, d
				end
			end
		end
	end
	postGlow.Enabled = offered ~= nil
	if offered then
		postGlow.Adornee = offered
		postGlow.OutlineTransparency = 0.15 + 0.4 * pulse
		postGlow.FillTransparency = 0.75 + 0.15 * pulse
	end
	bankGlow.Enabled = nearest ~= nil and nearest ~= offered
	if nearest and nearest ~= offered then
		bankGlow.Adornee = nearest
		bankGlow.OutlineTransparency = 0.25 + 0.4 * pulse
		bankGlow.FillTransparency = 0.85
	end
	local targets: { Model } = {}
	local zombies = if on then workspace:FindFirstChild("Zombies") else nil
	if zombies then
		for _, z in zombies:GetChildren() do
			local humanoid = z:FindFirstChildOfClass("Humanoid")
			if z:IsA("Model") and z:GetAttribute("ContractTarget") and humanoid and humanoid.Health > 0 and #targets < TARGET_MAX then
				table.insert(targets, z)
			end
		end
	end
	for i, h in targetGlows do
		local z = targets[i]
		h.Enabled = z ~= nil
		if z then
			h.Adornee = z
			h.OutlineTransparency = 0.2 + 0.4 * pulse
			h.FillTransparency = 0.8
		end
	end
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local pulse = 0.5 + 0.5 * math.sin(now * 5)

	for barricade, untilAt in windowUntil do
		local h = windowGlows[barricade]
		if now > untilAt or not barricade.Parent then
			windowUntil[barricade] = nil
			if h then
				h:Destroy()
				windowGlows[barricade] = nil
			end
		else
			if not h then
				h = glow("WindowGlow", AMBER)
				h.Adornee = barricade
				h.Enabled = true
				windowGlows[barricade] = h
			end
			local fade = math.clamp((untilAt - now) / 0.6, 0, 1)
			h.OutlineTransparency = 1 - fade * (0.35 + 0.55 * pulse)
			h.FillTransparency = 1 - fade * 0.25 * pulse
		end
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local carrying = character ~= nil and character:GetAttribute("CarryingPart") ~= nil
	local map = workspace:FindFirstChild("Map")
	local tower = map and map:FindFirstChild("RadioTower")
	local cabinet = tower and tower:FindFirstChild("RadioCabinet")
	towerGlow.Enabled = carrying and cabinet ~= nil
	if towerGlow.Enabled then
		towerGlow.Adornee = cabinet
		towerGlow.OutlineTransparency = 0.15 + 0.4 * pulse
		towerGlow.FillTransparency = 0.7 + 0.2 * pulse
	end
	local partOut = workspace:GetAttribute("PartOut")
	local index = if typeof(partOut) == "string" then table.find(GameConfig.Parts.Order, partOut) else nil
	local lamp = if index and cabinet then cabinet:FindFirstChild("Lamp" .. index, true) else nil
	lampGlow.Enabled = lamp ~= nil
	if lamp then
		lampGlow.Adornee = lamp
		lampGlow.OutlineTransparency = 0.3 * pulse
		lampGlow.FillTransparency = 0.05 + 0.35 * pulse
	end

	local seen = (player:GetAttribute("BeaconSeen") or 0) > 0.05 and player:GetAttribute("InMatch") == true
	local near = {}
	if seen and root then
		for _, spot in CollectionService:GetTagged("HideSpot") do
			if spot:IsA("BasePart") and spot:IsDescendantOf(workspace) then
				local d = (spot.Position - root.Position).Magnitude
				if d <= HUD.HideGlowRange then
					table.insert(near, { spot, d })
				end
			end
		end
		table.sort(near, function(a, b)
			return a[2] < b[2]
		end)
	end
	for i, h in hideGlows do
		local entry = near[i]
		h.Enabled = entry ~= nil
		if entry then
			-- The spot is an invisible box; its Cover is the dumpster or car you see.
			local cover = entry[1]:FindFirstChild("Cover") :: ObjectValue?
			h.Adornee = if cover and cover.Value then cover.Value else entry[1]
			h.OutlineTransparency = 0.2 + 0.4 * pulse
			h.FillTransparency = 0.8
		end
	end
	outbreakGlows(root, pulse)
end)
