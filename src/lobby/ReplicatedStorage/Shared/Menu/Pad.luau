--!nonstrict
-- Shared.Menu.Pad: controller navigation for the lobby menu (4 Nov 2026). Router.Start starts it; it is live while
-- Shared.Platform says the player is on a controller (PreferredInput), on console and on a PC with a pad alike.
--
-- Focus (left stick / D-pad, A presses, B goes back, LB/RB change tabs in the Router):
--   * The focused button wears Kit/Selection (amber corner brackets, a 9-slice PNG) as PlayerGui.SelectionImageObject,
--     and its own hover art through Ui.Button (SelectionGained).
--   * Focus stays inside what is on top: a PadModal-tagged panel (Settings), else the top Router overlay, else the
--     current page plus the persistent top bar. An open overlay or modal is a SelectionGroup that stops at its edges.
--   * Each of those remembers its last focused button: closing an overlay puts focus back where it was.
--   * When the focused button disappears (a list refilled, a page hid) focus moves to the remembered one, else to the
--     biggest button on screen (the page's main action).
-- Pointer (right stick), for the spatial screens (store grid, crate shelf, big cards):
--   * Kit/Pointer, an authored PNG, appears where focus was and moves with the right stick. Over a button it turns
--     into Kit/PointerHover, slows down, and that button takes focus, so A presses it and its hover art lights.
--   * Let go near a button and the pointer settles onto it. Pushed against the top or bottom of a list it scrolls it.
--   * The D-pad, the left stick or 4 s without the right stick hide it; focus carries on from the button under it.
--   * A page that needs the right stick for itself (the loadout turntable) claims it with ctx.pad.ClaimStick(true)
--     and the pointer stays away.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = require(script.Parent.Ui)
local Platform = require(ReplicatedStorage.Shared.Platform)

local Pad = {}

Pad.MODAL_TAG = "PadModal"

local SEL_MARGIN = 6 -- Kit/Selection is drawn this many px outside the element
local DEADZONE = 0.2
local SPEED = 1.1 -- screen heights per second at full tilt
local HOVER_SLOW = 0.55 -- speed share while over a button (soft magnet)
local SNAP_RADIUS = 0.07 -- screen heights: let go this close to a button and the pointer settles onto it
local SNAP_RATE = 16 -- per second
local POINTER_SIZE = 0.042 -- screen heights
local SCROLL_EDGE = 0.14 -- share of a list's height at its top and bottom that scrolls it
local SCROLL_SPEED = 1.2 -- list heights per second
local CHECK_EVERY = 0.15
local IDLE_HIDE = 4 -- seconds without the right stick before the pointer hands over to focus
local CANDIDATES_EVERY = 0.3

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ctx = nil
local started = false
local pointerOn = false
local stickClaims = 0
local stick = Vector2.zero
local stickAt = 0 -- os.clock() of the last right-stick push
local pos = Vector2.zero -- pointer, in GUI space (AbsolutePosition space: (0, 0) is just under the top bar)
local hover: GuiButton? = nil
local memory = setmetatable({}, { __mode = "k" }) -- scope root -> last focused button
local confined: GuiObject? = nil
local confinedWas = nil
local candidates = {}
local candidatesAt = 0

local selectionImg: ImageLabel
local pointerGui: ScreenGui
local pointerImg: ImageLabel

function Pad.PadMode(): boolean
	return Platform.IsGamepad()
end

-- Screen helpers ------------------------------------------------------------------------------------------------

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

-- Every layer's AbsolutePosition, and GetGuiObjectsAtPosition, share one space whose (0, 0) is just under the top
-- bar; a layer that ignores the inset simply starts above it. The whole screen in that space:
local function screenRect(): (Vector2, Vector2)
	local inset = GuiService:GetGuiInset()
	return -inset, viewport() - inset
end

local function rectOf(obj: GuiObject): (Vector2, Vector2)
	return obj.AbsolutePosition, obj.AbsolutePosition + obj.AbsoluteSize
end

local function centreOf(obj: GuiObject): Vector2
	local a, b = rectOf(obj)
	return (a + b) / 2
end

local function shown(obj: Instance?): boolean
	if not obj or not obj.Parent or not obj:IsDescendantOf(playerGui) then
		return false
	end
	local node: Instance? = obj
	while node and node ~= playerGui do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			if not node.Enabled then
				return false
			end
		end
		node = node.Parent
	end
	return true
end

local function usable(b: Instance): boolean
	if not b:IsA("GuiButton") or not b.Selectable then
		return false
	end
	local s = b.AbsoluteSize
	if s.X < 6 or s.Y < 6 then
		return false
	end
	local vp = viewport()
	-- a full-screen catcher or scrim is not a button anyone aims at
	if s.X > vp.X * 0.8 and s.Y > vp.Y * 0.8 then
		return false
	end
	return shown(b)
end

-- Scope -----------------------------------------------------------------------------------------------------------

local function modalRoot(): GuiObject?
	for _, m in CollectionService:GetTagged(Pad.MODAL_TAG) do
		if m:IsA("GuiObject") and shown(m) then
			return m
		end
	end
	return nil
end

function Pad.ModalOpen(): boolean
	return modalRoot() ~= nil
end

-- The root focus belongs to, and whether focus is held inside it.
local function scope(): (GuiObject?, boolean)
	local m = modalRoot()
	if m then
		return m, true
	end
	if not (ctx and ctx.active and ctx.gui.Enabled) then
		return nil, false
	end
	local list = ctx.overlays
	if list and #list > 0 then
		local f = ctx.frame(list[#list])
		if f then
			return f, true
		end
	end
	return ctx.current and ctx.frame(ctx.current), false
end

local function inChrome(obj: Instance): boolean
	if not ctx then
		return false
	end
	for name, p in ctx.pages do
		if p.Persistent then
			local f = ctx.frame(name)
			if f and obj:IsDescendantOf(f) then
				return true
			end
		end
	end
	return false
end

local function inScope(obj: Instance, root: GuiObject, held: boolean): boolean
	return obj:IsDescendantOf(root) or (not held and inChrome(obj))
end

local BEHAVIOURS = { "SelectionBehaviorUp", "SelectionBehaviorDown", "SelectionBehaviorLeft", "SelectionBehaviorRight" }
local function confine(root: GuiObject?)
	if root == confined then
		return
	end
	if confined and confinedWas then
		pcall(function()
			confined.SelectionGroup = confinedWas.Group
			for _, k in BEHAVIOURS do
				confined[k] = confinedWas[k]
			end
		end)
	end
	confined, confinedWas = root, nil
	if root then
		confinedWas = { Group = root.SelectionGroup }
		for _, k in BEHAVIOURS do
			confinedWas[k] = root[k]
			root[k] = Enum.SelectionBehavior.Stop
		end
		root.SelectionGroup = true
	end
end

local function buttonsIn(root: Instance): { GuiButton }
	local out = {}
	for _, d in root:GetDescendants() do
		if usable(d) then
			table.insert(out, d)
		end
	end
	return out
end

-- The page's main action: the biggest button (ties go to the one nearer the top left).
local function bestDefault(root: GuiObject): GuiButton?
	local best, score = nil, -math.huge
	for _, b in buttonsIn(root) do
		local s = b.AbsoluteSize
		local c = centreOf(b)
		local v = s.X * s.Y - (c.X + c.Y) * 0.01
		if v > score then
			best, score = b, v
		end
	end
	return best
end

local function focusFor(root: GuiObject): GuiButton?
	local m = memory[root]
	if m and m:IsDescendantOf(root) and usable(m) then
		return m
	end
	return bestDefault(root)
end

-- Every few frames on a controller: keep focus on something real, inside the right place.
local function check()
	local root, held = scope()
	confine(if held then root else nil)
	if not root or pointerOn or not Pad.PadMode() then
		return
	end
	local sel = GuiService.SelectedObject
	if sel and usable(sel) and inScope(sel, root, held) then
		memory[root] = sel
		return
	end
	local pick = focusFor(root)
	if pick then
		GuiService.SelectedObject = pick
	end
end

-- ctx.select: a page asks for focus on obj. A hidden or unselectable obj (a page asking before it laid out) falls
-- back to the usual pick instead of being refused by Roblox.
function Pad.Select(obj: GuiObject?)
	if not Pad.PadMode() or pointerOn then
		return
	end
	if obj and usable(obj) then
		GuiService.SelectedObject = obj
	else
		task.defer(check)
	end
end

-- Pointer ---------------------------------------------------------------------------------------------------------

local function scopeButtons(): { GuiButton }
	local now = os.clock()
	if now - candidatesAt < CANDIDATES_EVERY then
		return candidates
	end
	candidatesAt = now
	local root, held = scope()
	if root and held then
		candidates = buttonsIn(root)
	else
		candidates = {}
		for _, layer in playerGui:GetChildren() do
			if layer:IsA("ScreenGui") and layer.Enabled and layer ~= pointerGui then
				for _, b in buttonsIn(layer) do
					table.insert(candidates, b)
				end
			end
		end
	end
	return candidates
end

-- The front-most button at a screen point (what a mouse click there would hit), and the list under it.
local function hitAt(p: Vector2): (GuiButton?, ScrollingFrame?)
	local ok, list = pcall(playerGui.GetGuiObjectsAtPosition, playerGui, p.X, p.Y)
	if not ok then
		return nil, nil
	end
	local root, held = scope()
	local button, scroller = nil, nil
	for _, g in list do
		if g:IsDescendantOf(pointerGui) or not shown(g) then
			continue
		end
		if held and root and not g:IsDescendantOf(root) then
			continue
		end
		if not button and usable(g) then
			button = g
		end
		if not scroller and g:IsA("ScrollingFrame") and g.ScrollingEnabled then
			scroller = g
		end
		if button and scroller then
			break
		end
	end
	return button, scroller
end

local function setHover(b: GuiButton?)
	if b == hover then
		return
	end
	hover = b
	Ui.SetArt(pointerImg, if b then "Kit/PointerHover" else "Kit/Pointer")
	local s = pointerImg:FindFirstChildOfClass("UIScale")
	if s then
		s.Scale = if b then 1.12 else 1
		Ui.Tween(s, 0.12, { Scale = 1 })
	end
	GuiService.SelectedObject = b
end

local function place()
	local size = math.max(28, POINTER_SIZE * viewport().Y)
	pointerImg.Size = UDim2.fromOffset(size, size)
	local o = pointerGui.AbsolutePosition
	pointerImg.Position = UDim2.fromOffset(pos.X - o.X, pos.Y - o.Y)
end

local function showPointer(on: boolean)
	if on == pointerOn then
		return
	end
	pointerOn = on
	pointerImg.Visible = on
	selectionImg.ImageTransparency = if on then 1 else 0
	if on then
		local sel = GuiService.SelectedObject
		local a, b = screenRect()
		pos = if sel and shown(sel) then centreOf(sel) else (a + b) / 2
		hover = nil
		setHover((hitAt(pos)))
		place()
	else
		-- hand focus to the button under the pointer, else the nearest one, so the D-pad carries on from here
		local keep = hover
		if not keep then
			local best, dist = nil, math.huge
			for _, b in scopeButtons() do
				local d = (centreOf(b) - pos).Magnitude
				if d < dist and b.Parent then
					best, dist = b, d
				end
			end
			keep = best
		end
		hover = nil
		Ui.SetArt(pointerImg, "Kit/Pointer")
		if Pad.PadMode() and keep then
			GuiService.SelectedObject = keep
		end
	end
end

local function stepPointer(dt: number)
	local vp = viewport()
	local h = vp.Y
	local mag = stick.Magnitude
	if mag > DEADZONE then
		stickAt = os.clock()
		local k = math.clamp((mag - DEADZONE) / (1 - DEADZONE), 0, 1)
		local v = stick.Unit * (k ^ 1.7) * SPEED * h
		if hover then
			v *= HOVER_SLOW
		end
		pos += v * dt
	else
		-- settle onto the button under it, or a near one
		local target = hover
		if not target then
			local best, dist = nil, SNAP_RADIUS * h
			for _, b in scopeButtons() do
				if b.Parent then
					local a, c = rectOf(b)
					local q = Vector2.new(math.clamp(pos.X, a.X, c.X), math.clamp(pos.Y, a.Y, c.Y))
					local d = (q - pos).Magnitude
					if d < dist then
						best, dist = b, d
					end
				end
			end
			target = best
		end
		if target and target.Parent then
			local c = centreOf(target)
			pos += (c - pos) * (1 - math.exp(-SNAP_RATE * dt))
		end
	end
	local lo, hi = screenRect()
	pos = Vector2.new(math.clamp(pos.X, lo.X, hi.X), math.clamp(pos.Y, lo.Y, hi.Y))
	local button, scroller = hitAt(pos)
	setHover(button)
	-- pushed against the top or bottom of a list: scroll it
	if scroller and mag > DEADZONE and math.abs(stick.Y) > 0.4 then
		local a, c = rectOf(scroller)
		local edge = (c.Y - a.Y) * SCROLL_EDGE
		local dir = 0
		if stick.Y > 0 and pos.Y > c.Y - edge then
			dir = 1
		elseif stick.Y < 0 and pos.Y < a.Y + edge then
			dir = -1
		end
		if dir ~= 0 then
			local maxY = math.max(0, scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y)
			local y = math.clamp(scroller.CanvasPosition.Y + dir * SCROLL_SPEED * (c.Y - a.Y) * dt, 0, maxY)
			scroller.CanvasPosition = Vector2.new(scroller.CanvasPosition.X, y)
		end
	end
	place()
end

-- A page that turns something with the right stick (the loadout turntable) keeps the pointer away while it is up.
function Pad.ClaimStick(on: boolean)
	stickClaims = math.max(0, stickClaims + (if on then 1 else -1))
	if stickClaims > 0 then
		showPointer(false)
	end
end

function Pad.HidePointer()
	showPointer(false)
end

-- A stick moved (UserInputService.InputChanged). Also the Studio test hook: Studio's input simulator cannot tilt a
-- stick, so a Studio test invokes PlayerGui.MenuPointer.PadTest(x, y), which lands here.
function Pad._Stick(key: Enum.KeyCode, position: Vector3)
	if key == Enum.KeyCode.Thumbstick2 then
		stick = Vector2.new(position.X, -position.Y)
		stickAt = os.clock()
		if stickClaims == 0 and not pointerOn and stick.Magnitude > 0.35 and Pad.PadMode() then
			showPointer(true)
		end
	elseif key == Enum.KeyCode.Thumbstick1 and pointerOn then
		if Vector2.new(position.X, position.Y).Magnitude > 0.5 then
			showPointer(false)
		end
	end
end

-- Start -----------------------------------------------------------------------------------------------------------

local function build()
	selectionImg = Instance.new("ImageLabel")
	selectionImg.Name = "PadSelection"
	selectionImg.BackgroundTransparency = 1
	selectionImg.Size = UDim2.new(1, SEL_MARGIN * 2, 1, SEL_MARGIN * 2)
	selectionImg.Position = UDim2.fromOffset(-SEL_MARGIN, -SEL_MARGIN)
	Ui.SetArt(selectionImg, "Kit/Selection")
	playerGui.SelectionImageObject = selectionImg

	-- The pointer's own layer, above every menu, settings and crate screen. The art is the authored Kit/Pointer PNG.
	-- fwjelaa-ignore: findfirstchild-chain (nil-checked on the next line)
	pointerGui = playerGui:FindFirstChild("MenuPointer") :: ScreenGui
	if not pointerGui then
		pointerGui = Instance.new("ScreenGui")
		pointerGui.Name = "MenuPointer"
		pointerGui.ResetOnSpawn = false
		pointerGui.IgnoreGuiInset = true
		pointerGui.DisplayOrder = 10000
		pointerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		pointerGui.Parent = playerGui
	end
	-- fwjelaa-ignore: findfirstchild-chain (nil-checked on the next line)
	pointerImg = pointerGui:FindFirstChild("Pointer") :: ImageLabel
	if not pointerImg then
		pointerImg = Instance.new("ImageLabel")
		pointerImg.Name = "Pointer"
		pointerImg.BackgroundTransparency = 1
		pointerImg.AnchorPoint = Vector2.new(0.5, 0.5)
		pointerImg.Active = false
		pointerImg.Selectable = false
		pointerImg.Parent = pointerGui
		Instance.new("UIScale").Parent = pointerImg
	end
	pointerImg.Visible = false
	Ui.SetArt(pointerImg, "Kit/Pointer")
end

function Pad.Start(c)
	ctx = c
	if started then
		return Pad
	end
	started = true
	build()

	UserInputService.InputChanged:Connect(function(input)
		Pad._Stick(input.KeyCode, input.Position)
	end)
	UserInputService.InputBegan:Connect(function(input)
		local k = input.KeyCode
		if pointerOn and (k == Enum.KeyCode.DPadUp or k == Enum.KeyCode.DPadDown or k == Enum.KeyCode.DPadLeft
			or k == Enum.KeyCode.DPadRight) then
			showPointer(false)
		end
	end)
	Platform.Changed:Connect(function()
		if not Pad.PadMode() then
			showPointer(false)
			local sel = GuiService.SelectedObject
			if sel and sel:IsDescendantOf(playerGui) then
				GuiService.SelectedObject = nil
			end
		end
	end)
	-- an overlay closing hands focus back to what it had before it opened
	ctx.on("Overlay", function(_, open)
		if not open and Pad.PadMode() and not pointerOn then
			task.defer(check)
		end
	end)

	-- Studio only: the command bar loads its own copy of this module, so tests reach the live one through this.
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "PadTest"
		hook.OnInvoke = function(x: any, y: any)
			-- ("go" | "open" | "close" | "back", page) drives the Router the way a press would
			if x == "go" or x == "open" or x == "close" or x == "back" then
				ctx[x](y)
				return ctx.current, ctx.overlays[#ctx.overlays]
			end
			Pad._Stick(Enum.KeyCode.Thumbstick2, Vector3.new(x, y, 0))
			return pointerOn, hover and hover:GetFullName() or nil
		end
		hook.Parent = pointerGui
	end

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		if pointerOn then
			if not Pad.PadMode() or stickClaims > 0 or os.clock() - stickAt > IDLE_HIDE then
				showPointer(false)
			else
				stepPointer(dt)
			end
		end
		acc += dt
		if acc >= CHECK_EVERY then
			acc = 0
			check()
		end
	end)
	return Pad
end

return Pad
