--!strict
-- One objective marker for every mode and place (4 Nov 2026, marker consistency). The authored diamond
-- (ReplicatedStorage.Assets.ObjectiveMarker's Diamond image) over the objective, tinted per kind, breathing
-- slowly, with the objective's name and distance in metres under it. It fades out when you stand on it.
-- Used by WarClient (campaign) and EscapeHud (Outbreak escape run). Same file in both places: keep them equal.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local STUDS_PER_METRE = 3.5
local DIAMOND = 46
local WIDTH, HEIGHT = 180, DIAMOND + 34
local WHITE = Color3.fromRGB(235, 235, 230)

local template = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("ObjectiveMarker") :: BillboardGui
local diamondSource = template:WaitForChild("Diamond") :: ImageLabel

export type Marker = {
	Gui: BillboardGui,
	Diamond: ImageLabel,
	Name: TextLabel,
	Dist: TextLabel,
	SetAdornee: (self: Marker, adornee: BasePart?) -> (),
	SetLabel: (self: Marker, text: string) -> (),
	SetColor: (self: Marker, color: Color3) -> (),
	Destroy: (self: Marker) -> (),
}

local live: { [Marker]: true } = {}

local ObjectiveMarker = {}
ObjectiveMarker.StudsPerMetre = STUDS_PER_METRE

local function label(parent: Instance, y: number, size: number, font: Enum.Font, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, size + 4)
	t.Position = UDim2.fromOffset(0, y)
	t.Font = font
	t.TextSize = size
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.4
	t.Text = ""
	t.Parent = parent
	return t
end

function ObjectiveMarker.new(adornee: BasePart?, color: Color3?, parent: Instance?): Marker
	local gui = Instance.new("BillboardGui")
	gui.Name = "ObjectiveMarker"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = template.MaxDistance
	gui.ResetOnSpawn = false
	gui.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	gui.StudsOffsetWorldSpace = template.StudsOffsetWorldSpace
	-- keep the diamond's centre where the campaign's always was (the billboard's centre)
	gui.SizeOffset = Vector2.new(0, -((HEIGHT - DIAMOND) / 2) / HEIGHT)
	gui.Adornee = adornee
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(DIAMOND, DIAMOND)
	holder.Position = UDim2.new(0.5, -DIAMOND / 2, 0, 0)
	holder.Parent = gui
	local diamond = diamondSource:Clone()
	diamond.ImageColor3 = color or Color3.new(1, 1, 1)
	diamond.Parent = holder
	local name = label(gui, DIAMOND, 14, Enum.Font.GothamBlack, color or WHITE)
	local dist = label(gui, DIAMOND + 16, 12, Enum.Font.GothamBold, WHITE)
	local self = {
		Gui = gui,
		Diamond = diamond,
		Name = name,
		Dist = dist,
	} :: any
	function self:SetAdornee(a: BasePart?)
		gui.Adornee = a
	end
	function self:SetLabel(text: string)
		name.Text = text
	end
	function self:SetColor(c: Color3)
		diamond.ImageColor3 = c
		name.TextColor3 = c
	end
	function self:Destroy()
		live[self] = nil
		gui:Destroy()
	end
	gui.Parent = parent or (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	live[self] = true
	return self :: Marker
end

-- Breathing, the fade on arrival and the distance, for every marker, every frame.
RunService.RenderStepped:Connect(function()
	local character = (Players.LocalPlayer :: Player).Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local breathe = 1 + math.sin(os.clock() * 3) * 0.06
	for marker in live do
		local gui = marker.Gui
		local a = gui.Adornee :: BasePart?
		if not (gui.Enabled and a) then
			continue
		end
		local near = if root then (root.Position - a.Position).Magnitude else 999
		local fade = math.clamp(1 - (near - 6) / 14, 0, 0.85)
		marker.Diamond.Size = UDim2.fromScale(breathe, breathe)
		marker.Diamond.Position = UDim2.fromScale(0.5, 0.5)
		marker.Diamond.AnchorPoint = Vector2.new(0.5, 0.5)
		marker.Diamond.ImageTransparency = fade
		marker.Name.TextTransparency = fade
		marker.Dist.TextTransparency = fade
		marker.Dist.Text = if root then math.floor(near / STUDS_PER_METRE) .. "m" else ""
	end
end)

return ObjectiveMarker
