-- FRONTLINE on each client (Shared.Front, ServerScriptService.FrontServer), while workspace Front is set:
--   Teammates: other players on your side get an outline in the side's colour (seen through walls) and keep their
--   name tags; players on the other side lose theirs.
--   Spotted: anything of the other side with the attribute Spotted<your side> still running (the SPOTTER streak) is
--   outlined red, through walls, until it runs out.
--   The killstreak: the key Controls "Streak" (5 / right stick, rebindable) or the touch button calls the ready one
--   (player attribute StreakReady) through Remotes.FrontStreak, with the point the camera looks at (MORTARS land
--   there). The authored slot plates StarterGui.HUD.Gear.Streak and StarterGui.TouchControls.Streak (copies of the
--   Field plate) show while one is ready, with its short name.
-- At most 11 teammates and 12 spotted foes are outlined, under Roblox's 31 Highlight limit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
if not Shared:FindFirstChild("Front") then
	return
end
local Front = require(Shared.Front)
local Controls = require(Shared:WaitForChild("Controls"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SPOTTED = Color3.fromRGB(235, 70, 60)
local SHORT = { Spotter = "SPOT", Mortars = "MORT", Armour = "TANK" }
-- Stand-in icons from the authored gear art (UiArt) until the streaks have their own.
local ICON = { Spotter = "Gear/Mark", Mortars = "Gear/ReconFlare", Armour = "Gear/Charge" }

local uiArt = nil
local function setArt(img, key)
	if uiArt == nil then
		local ok, m = pcall(require, Shared:FindFirstChild("UiArt"))
		uiArt = ok and type(m) == "table" and m or false
	end
	local entry = uiArt and uiArt[key]
	local id = if type(entry) == "table" then entry.Id or entry.Image else entry
	if type(id) == "number" then
		id = "rbxassetid://" .. id
	end
	if type(id) ~= "string" then
		img.Image = ""
		return
	end
	local r = type(entry) == "table" and entry.Rect or nil
	img.Image = id
	img.ImageRectOffset = if r then Vector2.new(r[1], r[2]) else Vector2.zero
	img.ImageRectSize = if r then Vector2.new(r[3], r[4]) else Vector2.zero
end

local function on()
	return workspace:GetAttribute("Front") == true and player:GetAttribute("InMatch") == true
end

local function mySide()
	return player:GetAttribute("Side") or "Ally"
end

-- Outlines ---------------------------------------------------------------------------------------------------------

local marks = {} -- [model] = Highlight

local function mark(model, color)
	local h = marks[model]
	if not h then
		h = Instance.new("Highlight")
		h.Name = "FrontMark"
		h.FillTransparency = 1
		h.OutlineTransparency = 0.1
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Adornee = model
		h.Parent = model
		marks[model] = h
	end
	h.OutlineColor = color
end

local function refreshMarks()
	local keep = {}
	if on() then
		local side = mySide()
		local now = workspace:GetServerTimeNow()
		local key = "Spotted" .. side
		local ownColor = Front.Sides[side].Color
		for _, p in Players:GetPlayers() do
			local c = p.Character
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			if p ~= player and c and hum and hum.Health > 0 then
				local same = (p:GetAttribute("Side") or "Ally") == side
				hum.DisplayDistanceType = if same then Enum.HumanoidDisplayDistanceType.Viewer else Enum.HumanoidDisplayDistanceType.None
				if same then
					mark(c, ownColor)
					keep[c] = true
				elseif (c:GetAttribute(key) or 0) > now then
					mark(c, SPOTTED)
					keep[c] = true
				end
			end
		end
		local foes = workspace:FindFirstChild(if side == "Ally" then "Hostiles" else "Squad")
		if foes then
			for _, m in foes:GetChildren() do
				if m:IsA("Model") and not m:GetAttribute("Dead") and (m:GetAttribute(key) or 0) > now then
					mark(m, SPOTTED)
					keep[m] = true
				end
			end
		end
	end
	for model, h in marks do
		if not keep[model] or not model.Parent then
			h:Destroy()
			marks[model] = nil
		end
	end
end

-- The killstreak -----------------------------------------------------------------------------------------------------

local remote = nil
task.spawn(function()
	remote = Remotes:WaitForChild("FrontStreak", 60)
end)

local function aimPoint()
	local cam = workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { cam, player.Character, workspace:FindFirstChild("Fx") }
	params.IgnoreWater = true
	local origin, dir = cam.CFrame.Position, cam.CFrame.LookVector
	local hit = workspace:Raycast(origin, dir * 600, params)
	return if hit then hit.Position else origin + dir * 200
end

local function call()
	if remote and on() and type(player:GetAttribute("StreakReady")) == "string" then
		remote:FireServer(aimPoint())
	end
end

Controls.Bind("FrontStreak", "Streak", function(_, state)
	if state == Enum.UserInputState.Begin and type(player:GetAttribute("StreakReady")) == "string" and on() then
		call()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end)

-- The plates: shown while a streak is ready.
local touchButton = nil
local function plates()
	local hud = playerGui:FindFirstChild("HUD")
	local gear = hud and hud:FindFirstChild("Gear")
	local touch = playerGui:FindFirstChild("TouchControls")
	return gear and gear:FindFirstChild("Streak"), touch and touch:FindFirstChild("Streak")
end

local function paintPlate(plate, ready)
	if not plate then
		return
	end
	plate.Visible = ready ~= nil
	local icon = plate:FindFirstChild("Icon")
	if ready and icon and icon:IsA("ImageLabel") then
		setArt(icon, ICON[ready] or "")
	end
	local count = plate:FindFirstChild("Count")
	if count and count:IsA("TextLabel") then
		count.Text = if ready then SHORT[ready] or string.upper(ready) else ""
	end
	local key = plate:FindFirstChild("Key")
	if key and key:IsA("TextLabel") then
		key.Text = Controls.ShortText(Controls.Get("Streak", "Kb")[1])
	end
end

local function refreshPlates()
	local ready = player:GetAttribute("StreakReady")
	ready = if on() and type(ready) == "string" then ready else nil
	local hudPlate, touchPlate = plates()
	paintPlate(hudPlate, ready)
	paintPlate(touchPlate, ready)
	if touchPlate and touchPlate:IsA("GuiButton") and touchButton ~= touchPlate then
		touchButton = touchPlate
		touchPlate.Activated:Connect(call)
	end
end

player:GetAttributeChangedSignal("StreakReady"):Connect(refreshPlates)
player:GetAttributeChangedSignal("InMatch"):Connect(refreshPlates)
Controls.Changed:Connect(refreshPlates)
playerGui.ChildAdded:Connect(function()
	task.defer(refreshPlates)
end)
refreshPlates()

local nextMarks = 0
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	if t >= nextMarks then
		nextMarks = t + 0.25
		refreshMarks()
	end
end)
