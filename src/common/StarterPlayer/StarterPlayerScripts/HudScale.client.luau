-- Phone layout for StarterGui.HUD. On PC the HUD stays exactly as authored. While the touch
-- controls are up (player attribute TouchHud, set by TouchControls):
--   the wave and zombie count (or the night ring, Clock) sit at the top centre, health at the
--   top left, points and ammo at the top right (out from under the thumbs), and the Beacon's
--   Seen meter just under the ring;
--   every block shrinks to fit the screen (UIScale), margins included, from REF_HEIGHT down.
-- On both, a block in a top corner that would sit under Roblox's own buttons (GuiService
-- TopbarInset) moves down below them.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Screen height (and width) the HUD is laid out for; smaller screens scale it down.
local REF_HEIGHT = 620
local REF_WIDTH = 1180
local MIN_SCALE = 0.5

-- Touch spots, in unscaled pixels: { AnchorPoint, Position }.
local TOUCH = {
	Match = { Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 10) },
	Clock = { Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 10) },
	Health = { Vector2.new(0, 0), UDim2.new(0, 24, 0, 14) },
	Points = { Vector2.new(1, 0), UDim2.new(1, -24, 0, 10) },
	Ammo = { Vector2.new(1, 0), UDim2.new(1, -24, 0, 92) },
	Detect = { Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 74) },
	Hotbar = { Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -10) },
	Notice = { Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.3, 0) },
}
-- Text that lines up with the block's side on PC and centres at the top centre.
local CENTRED = { Match = { "Wave", "Sub" } }

local authored = {} -- [frame] = { AnchorPoint, Position, { [label] = alignment } }
local current = nil

local function scaled(p, s)
	return UDim2.new(p.X.Scale, math.round(p.X.Offset * s), p.Y.Scale, math.round(p.Y.Offset * s))
end

local function uiScale(frame)
	local scale = frame:FindFirstChild("HudScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "HudScale"
		scale.Parent = frame
	end
	return scale
end

local function apply()
	local hud = playerGui:FindFirstChild("HUD")
	local camera = workspace.CurrentCamera
	if not hud or not camera then
		return
	end
	local touch = player:GetAttribute("TouchHud") == true
	local view = camera.ViewportSize
	local s = if touch then math.clamp(math.min(view.Y / REF_HEIGHT, view.X / REF_WIDTH), MIN_SCALE, 1) else 1
	local inset = GuiService.TopbarInset
	local key = tostring(touch) .. ":" .. s .. ":" .. tostring(inset)
	if key == current then
		return
	end
	current = key
	for name, spot in TOUCH do
		local frame = hud:FindFirstChild(name)
		if frame then
			local base = authored[frame]
			if not base then
				base = { frame.AnchorPoint, frame.Position, {} }
				for _, label in CENTRED[name] or {} do
					local l = frame:FindFirstChild(label)
					if l then
						base[3][l] = l.TextXAlignment
					end
				end
				authored[frame] = base
			end
			if touch then
				frame.AnchorPoint = spot[1]
				frame.Position = scaled(spot[2], s)
			else
				frame.AnchorPoint, frame.Position = base[1], base[2]
			end
			-- Clear of Roblox's buttons: the left ones end at inset.Min.X, the right ones start
			-- at inset.Max.X.
			local p = frame.Position
			if p.Y.Scale == 0 and frame.AnchorPoint.Y == 0 and p.Y.Offset < inset.Height then
				local left = p.X.Scale == 0 and frame.AnchorPoint.X == 0 and inset.Min.X > p.X.Offset
				local right = p.X.Scale == 1 and inset.Max.X < view.X - 2
				if left or right then
					frame.Position = p + UDim2.fromOffset(0, inset.Height)
				end
			end
			for label, alignment in base[3] do
				label.TextXAlignment = if touch then Enum.TextXAlignment.Center else alignment
			end
			local bar = name == "Match" and frame:FindFirstChild("Bar")
			if bar then
				bar.AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.zero
				bar.Position = if touch then UDim2.new(0.5, 0, 0, 62) else UDim2.new(0, 0, 0, 62)
			end
			uiScale(frame).Scale = s
		end
	end
end

player:GetAttributeChangedSignal("TouchHud"):Connect(apply)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(apply)
local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
	apply()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUD" then
		current = nil
		apply()
	end
end)
