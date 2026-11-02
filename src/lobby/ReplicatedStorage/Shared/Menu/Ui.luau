-- Shared.Menu.Ui: wiring helpers for the authored PNG menu (CORE, 2 Nov 2026).
-- Art comes from Shared.UiArt (key -> {Id, W, H, Slice}). Nothing here draws UI; it swaps authored images,
-- moves and fades authored instances, and clones authored templates. Contract: horror-shooter/menu/CONTRACTS.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiArt = require(ReplicatedStorage.Shared.UiArt)
local UiSound = require(script.Parent.UiSound)

local Ui = {}

local STATES = { "Idle", "Hover", "Down", "Selected", "Disabled" }

function Ui.Art(key)
	return key and UiArt[key]
end

function Ui.SetArt(img, key)
	if not key then
		return
	end
	local a = UiArt[key]
	img:SetAttribute("UiArt", key)
	if not a then
		return
	end
	img.Image = a.Id or ""
	if a.Slice then
		img.ScaleType = Enum.ScaleType.Slice
		img.SliceCenter = Rect.new(a.Slice[1], a.Slice[2], a.W - a.Slice[3], a.H - a.Slice[4])
	end
end

-- Set every image under root from its UiArt attribute (ids may have been uploaded after the layout was built).
function Ui.Apply(root)
	local function one(inst)
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			local key = inst:GetAttribute("UiArt")
			if key and UiArt[key] and inst.Image ~= UiArt[key].Id then
				Ui.SetArt(inst, key)
			end
		end
	end
	one(root)
	for _, d in root:GetDescendants() do
		one(d)
	end
end

function Ui.Tween(inst, time, props, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function scaleOf(gui)
	local s = gui:FindFirstChild("PressScale")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "PressScale"
		s.Parent = gui
	end
	return s
end

-- An authored ImageButton with ArtIdle/ArtHover/ArtDown/ArtSelected/ArtDisabled attributes (layerkit sets them).
-- Returns a controller: Selected(bool), Disabled(bool), Destroy().
function Ui.Button(btn, onClick, opts)
	opts = opts or {}
	local keys = {}
	for _, st in STATES do
		keys[st] = btn:GetAttribute("Art" .. st)
	end
	keys.Idle = keys.Idle or btn:GetAttribute("UiArt")
	local hovered, pressed, selected, disabled = false, false, false, false
	local scale = scaleOf(btn)
	local lastHover = 0

	local function refresh()
		local key = (disabled and keys.Disabled)
			or (pressed and keys.Down)
			or (selected and keys.Selected)
			or (hovered and keys.Hover)
			or keys.Idle
		if key then
			Ui.SetArt(btn, key)
		end
	end

	local conns = {}
	local function on(sig, fn)
		table.insert(conns, sig:Connect(fn))
	end
	local function hover(v)
		if v and not hovered and os.clock() - lastHover > 0.06 and not opts.Silent then
			lastHover = os.clock()
			UiSound.Play("Hover")
		end
		hovered = v
		if not v then
			pressed = false
			Ui.Tween(scale, 0.08, { Scale = 1 })
		end
		refresh()
	end
	on(btn.MouseEnter, function()
		hover(true)
	end)
	on(btn.MouseLeave, function()
		hover(false)
	end)
	on(btn.SelectionGained, function()
		hover(true)
	end)
	on(btn.SelectionLost, function()
		hover(false)
	end)
	on(btn.InputBegan, function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			pressed = true
			Ui.Tween(scale, 0.08, { Scale = 0.97 })
			refresh()
		end
	end)
	on(btn.InputEnded, function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			pressed = false
			Ui.Tween(scale, 0.08, { Scale = 1 })
			refresh()
		end
	end)
	on(btn.Activated, function()
		if disabled then
			UiSound.Play("Locked")
			return
		end
		if not opts.Silent then
			UiSound.Play(opts.Sound or "Click")
		end
		if onClick then
			task.spawn(onClick, btn)
		end
	end)
	refresh()

	local ctl = {}
	function ctl.Selected(v)
		selected = v and true or false
		refresh()
	end
	function ctl.Disabled(v)
		disabled = v and true or false
		refresh()
	end
	function ctl.Destroy()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
	end
	return ctl
end

function Ui.Money(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local neg = s:sub(1, 1) == "-"
	if neg then
		s = s:sub(2)
	end
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (neg and "-" or "") .. out
end

function Ui.Text(label, value)
	if label then
		label.Text = tostring(value == nil and "" or value)
	end
end

-- A layerkit bar: Frame { Track, Clip { Fill } }. frac 0..1.
function Ui.Bar(bar, frac, time)
	if not bar then
		return
	end
	local clip = bar:FindFirstChild("Clip")
	if not clip then
		return
	end
	frac = math.clamp(tonumber(frac) or 0, 0, 1)
	if time and time > 0 then
		return Ui.Tween(clip, time, { Size = UDim2.fromScale(frac, 1) })
	end
	clip.Size = UDim2.fromScale(frac, 1)
end

local function templateFor(list)
	local path = list:GetAttribute("Template")
	local gui = list:FindFirstAncestorWhichIsA("ScreenGui")
	if not (path and gui) then
		return nil
	end
	local node = gui:FindFirstChild("Templates")
	for _, part in string.split(path, "/") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

-- Fill a layerkit list with one template clone per item. fn(clone, item, index) wires each clone.
function Ui.Fill(list, items, fn)
	if not list then
		return {}
	end
	for _, c in list:GetChildren() do
		if c:GetAttribute("_Clone") then
			c:Destroy()
		end
	end
	local tpl = templateFor(list)
	if not tpl then
		warn("[Ui.Fill] no template for", list:GetFullName(), list:GetAttribute("Template"))
		return {}
	end
	local out = {}
	for i, item in items do
		local c = tpl:Clone()
		c:SetAttribute("_Clone", true)
		c.Name = tpl.Name .. i
		c.LayoutOrder = i
		c.Position = UDim2.new()
		c.Visible = true
		Ui.Apply(c)
		if fn then
			fn(c, item, i)
		end
		c.Parent = list
		out[i] = c
	end
	return out
end

-- Page and card motion: CanvasGroups fade, everything slides 24 px.
function Ui.Show(frame, visible, time)
	if not frame then
		return
	end
	time = time or 0.15
	local home = frame:GetAttribute("_Home")
	if not home then
		home = frame.Position
		frame:SetAttribute("_Home", home)
	end
	if visible then
		frame.Position = home + UDim2.fromOffset(0, 24)
		frame.Visible = true
		if frame:IsA("CanvasGroup") then
			frame.GroupTransparency = 1
			Ui.Tween(frame, time, { GroupTransparency = 0 })
		end
		Ui.Tween(frame, time, { Position = home })
	else
		if frame:IsA("CanvasGroup") then
			Ui.Tween(frame, time, { GroupTransparency = 1 })
		end
		local t = Ui.Tween(frame, time, { Position = home + UDim2.fromOffset(0, 24) })
		local token = (frame:GetAttribute("_HideToken") or 0) + 1
		frame:SetAttribute("_HideToken", token)
		t.Completed:Once(function()
			if frame:GetAttribute("_HideToken") == token then
				frame.Visible = false
				frame.Position = home
			end
		end)
	end
end

function Ui.Stagger(frames, dt)
	dt = dt or 0.03
	for i, f in frames do
		local home = f.Position
		f.Position = home + UDim2.fromOffset(0, 16)
		task.delay((i - 1) * dt, function()
			Ui.Tween(f, 0.15, { Position = home })
		end)
	end
end

return Ui
