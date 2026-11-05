-- Shared.Menu.Router: page registry, navigation, WIDE/PHONE switching and the ctx every page gets (CORE, 2 Nov 2026).
-- MenuClient calls Router.Start{gui = PlayerGui.Menu, pages = PlayerScripts.MenuPages, stage = MenuStage,
-- camera = function(framing) end} and gets ctx back. Contract: horror-shooter/menu/CONTRACTS.md section 8.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Ui = require(script.Parent.Ui)
local Pad = require(script.Parent.Pad)
local UiSound = require(script.Parent.UiSound)

local Router = {}

Router.Variants = { Wide = Vector2.new(1920, 1080), Phone = Vector2.new(1688, 780) }
local HISTORY_MAX = 10

-- Fill any screen shape (4 Nov 2026). The canvas is authored at a fixed size (Variants); it scales to fit the short
-- side, then grows on the long side by `extra` canvas px, and every offset-authored panel keeps to its own edge:
-- panels left of 40 % stay, right of 60 % move by the whole extra, the middle moves by half; panels at least 90 %
-- of the canvas wide (rules, scrims, full-width rows) stretch instead. Full-canvas frames (pages, beats, tracks)
-- pass the same rule on to their children. Authored values live in _BasePos/_BaseSize, so refits never drift;
-- the fitted position goes to _FlexPos (and to _Home when Ui.Show cached one). Code-made clones are left alone.
local MAX_STRETCH = 0.6 -- at most this share of the canvas is added; wider screens centre what is left
local function zone(c, extra)
	return if c < 0.4 then 0 elseif c > 0.6 then extra else extra / 2
end
local GAP = 16 -- canvas px: panels this close side by side (tabs, slots, a card and its neighbour) move as one block
local function flex(container, base, extra)
	if container:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return
	end
	local items = {}
	for _, c in container:GetChildren() do
		if c:IsA("GuiObject") and not c:GetAttribute("_Clone") then
			local bp, bs = c:GetAttribute("_BasePos"), c:GetAttribute("_BaseSize")
			if bp == nil or bs == nil then
				bp, bs = c.Position, c.Size
				c:SetAttribute("_BasePos", bp)
				c:SetAttribute("_BaseSize", bs)
			end
			if bp.X.Scale == 0 and bp.Y.Scale == 0 and bs.X.Scale == 0 and bs.Y.Scale == 0 then
				local w, h = bs.X.Offset, bs.Y.Offset
				local x0 = bp.X.Offset - w * c.AnchorPoint.X
				local y0 = bp.Y.Offset - h * c.AnchorPoint.Y
				table.insert(items, {
					c = c, bp = bp, w = w, h = h, x0 = x0, y0 = y0, x1 = x0 + w, y1 = y0 + h,
					wide = w >= base.X * 0.9, tall = h >= base.Y * 0.9,
				})
			end
		end
	end
	-- group side-by-side panels (union-find over pairs that share a row and touch)
	local parent = {}
	for i in items do
		parent[i] = i
	end
	local function root(i)
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	for i, a in items do
		if not a.wide then
			for j = i + 1, #items do
				local b = items[j]
				if not b.wide then
					local overlapY = math.min(a.y1, b.y1) - math.max(a.y0, b.y0)
					local gapX = math.max(a.x0, b.x0) - math.min(a.x1, b.x1)
					if overlapY >= math.min(a.h, b.h) * 0.5 and gapX <= GAP then
						parent[root(i)] = root(j)
					end
				end
			end
		end
	end
	local box = {}
	for i, a in items do
		local g = root(i)
		local bx = box[g]
		if bx then
			bx[1] = math.min(bx[1], a.x0)
			bx[2] = math.max(bx[2], a.x1)
		else
			box[g] = { a.x0, a.x1 }
		end
	end
	for i, a in items do
		local c = a.c
		local dx, dy, dw, dh = 0, 0, 0, 0
		if a.wide then
			dw = extra.X
		else
			local bx = box[root(i)]
			dx = zone((bx[1] + bx[2]) / 2 / base.X, extra.X)
		end
		if a.tall then
			dh = extra.Y
		else
			dy = zone((a.y0 + a.y1) / 2 / base.Y, extra.Y)
		end
		local pos = UDim2.fromOffset(a.bp.X.Offset + dx, a.bp.Y.Offset + dy)
		c.Size = UDim2.fromOffset(a.w + dw, a.h + dh)
		c.Position = pos
		c:SetAttribute("_FlexPos", pos)
		if c:GetAttribute("_Home") ~= nil then
			c:SetAttribute("_Home", pos)
		end
		local full = a.w >= base.X * 0.98 and a.h >= base.Y * 0.98 and math.abs(a.bp.X.Offset) < 2
			and math.abs(a.bp.Y.Offset) < 2
		if (dw ~= 0 or dh ~= 0) and full and c:IsA("ImageLabel") and c.ScaleType == Enum.ScaleType.Stretch then
			c.ScaleType = Enum.ScaleType.Crop
		end
		-- a stretched panel passes its own stretch on to what is inside it (its art, the button on its far edge)
		if dw ~= 0 or dh ~= 0 then
			flex(c, Vector2.new(a.w, a.h), Vector2.new(dw, dh))
		end
	end
end

-- Scale `root` (a variant frame authored at `ref`) to fill `view` (px). Returns the scale.
function Router.Fit(root, ref, view)
	local s = math.max(0.1, math.min(view.X / ref.X, view.Y / ref.Y))
	local extra = Vector2.new(
		math.clamp(view.X / s - ref.X, 0, ref.X * MAX_STRETCH),
		math.clamp(view.Y / s - ref.Y, 0, ref.Y * MAX_STRETCH)
	)
	local scale = root:FindFirstChild("VariantScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "VariantScale"
		scale.Parent = root
	end
	scale.Scale = s
	root.Size = UDim2.fromOffset(ref.X + extra.X, ref.Y + extra.Y)
	local pages = root:FindFirstChild("Pages")
	if pages then
		flex(pages, ref, extra)
	end
	root:SetAttribute("Canvas", ref + extra)
	return s
end

local function decode(v)
	if type(v) == "string" then
		local c = v:sub(1, 1)
		if c == "{" or c == "[" then
			local ok, t = pcall(HttpService.JSONDecode, HttpService, v)
			if ok then
				return t
			end
		end
	end
	return v
end

function Router.Start(opts)
	local player = Players.LocalPlayer
	local gui = opts.gui
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	local ctx = {
		player = player,
		gui = gui,
		variant = "Wide",
		stage = opts.stage,
		ui = Ui,
		sound = UiSound.Play,
		current = nil,
		active = false,
	}
	local pages = {}
	local overlays = {}
	local history = {}
	local listeners = {}

	-- events ------------------------------------------------------------------------------------------------------
	function ctx.on(event, fn)
		listeners[event] = listeners[event] or {}
		table.insert(listeners[event], fn)
		return {
			Disconnect = function()
				local i = table.find(listeners[event], fn)
				if i then
					table.remove(listeners[event], i)
				end
			end,
		}
	end
	function ctx.emit(event, ...)
		for _, fn in listeners[event] or {} do
			task.spawn(fn, ...)
		end
	end

	-- lookup ------------------------------------------------------------------------------------------------------
	function ctx.frame(screen)
		local root = gui:FindFirstChild(ctx.variant)
		local p = root and root:FindFirstChild("Pages")
		return p and p:FindFirstChild(screen)
	end
	function ctx.el(screen, path)
		local node = ctx.frame(screen)
		for _, part in string.split(path, "/") do
			node = node and node:FindFirstChild(part)
		end
		return node
	end

	-- data --------------------------------------------------------------------------------------------------------
	function ctx.attr(name)
		return decode(player:GetAttribute(name))
	end
	function ctx.onAttr(name, fn)
		return player:GetAttributeChangedSignal(name):Connect(function()
			fn(ctx.attr(name))
		end)
	end

	local function remote(name)
		return remotes:FindFirstChild(name)
	end
	function ctx.store(action, payload)
		local r = remote("Store")
		if not (r and r:IsA("RemoteFunction")) then
			return { Ok = false, Reason = "NoStore" }
		end
		local ok, res = pcall(r.InvokeServer, r, action, payload or {})
		if not ok or type(res) ~= "table" then
			return { Ok = false, Reason = "Error" }
		end
		return res
	end
	function ctx.menu(msg, payload)
		local r = remote("Menu")
		if r then
			r:FireServer(msg, payload)
		end
	end
	function ctx.party(msg, payload)
		local r = remote("Party")
		if r then
			r:FireServer(msg, payload)
		end
	end

	task.spawn(function()
		remotes:WaitForChild("Menu").OnClientEvent:Connect(function(msg, payload)
			ctx.emit(msg, payload)
		end)
	end)
	task.spawn(function()
		remotes:WaitForChild("Party").OnClientEvent:Connect(function(msg, payload)
			if msg == "State" then
				ctx.partyState = payload
				ctx.emit("Party", payload)
			else
				ctx.emit(msg, payload)
			end
		end)
	end)

	-- auto-bound text: TextLabels with Bind = "attr:Name" or "attr:Name.Field" -------------------------------------
	local bound = {}
	local function bindText(label)
		local b = label:GetAttribute("Bind")
		if type(b) ~= "string" or b:sub(1, 5) ~= "attr:" then
			return
		end
		local name, field = b:sub(6):match("^([^%.]+)%.?(.*)$")
		local function set()
			local v = ctx.attr(name)
			if field ~= "" and type(v) == "table" then
				v = v[field]
			end
			label.Text = type(v) == "number" and Ui.Money(v) or tostring(v == nil and "" or v)
		end
		set()
		if not bound[name] then
			bound[name] = {}
			player:GetAttributeChangedSignal(name):Connect(function()
				for _, f in bound[name] do
					f()
				end
			end)
		end
		table.insert(bound[name], set)
	end

	-- variants and scale ------------------------------------------------------------------------------------------
	local function pickVariant()
		local size = gui.AbsoluteSize
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		if size.Y < 560 or (touchOnly and size.X < 1000) then
			return "Phone"
		end
		return "Wide"
	end
	local function applyScale()
		local size = gui.AbsoluteSize
		for name, ref in Router.Variants do
			local root = gui:FindFirstChild(name)
			if root then
				-- only the live variant is fitted (the hidden one keeps its last fit until it is picked)
				if name == ctx.variant then
					Router.Fit(root, ref, size)
				end
				root.Visible = name == ctx.variant
			end
		end
	end

	-- navigation --------------------------------------------------------------------------------------------------
	local function call(name, fn, ...)
		local p = pages[name]
		if p and p[fn] then
			local ok, err = pcall(p[fn], ctx, ...)
			if not ok then
				warn("[Menu]", name, fn, err)
			end
		end
	end
	local function setVisible(name, v, instant)
		local f = ctx.frame(name)
		if not f then
			return
		end
		if instant then
			f.Visible = v
		else
			Ui.Show(f, v)
		end
	end
	local function frameCamera(p)
		if opts.camera and p and p.Camera then
			opts.camera(p.Camera)
		end
	end
	local function switchTo(name, args)
		local p = pages[name]
		if ctx.current and ctx.current ~= name then
			call(ctx.current, "Hide")
			setVisible(ctx.current, false)
		end
		ctx.current = name
		setVisible(name, true)
		call(name, "Show", args)
		frameCamera(p)
		ctx.emit("Page", name, p.Tab)
	end

	function ctx.go(name, args)
		local p = pages[name]
		if not p then
			warn("[Menu] no page", name)
			return
		end
		if p.Overlay then
			return ctx.open(name, args)
		end
		while #overlays > 0 do
			ctx.close(overlays[#overlays])
		end
		if ctx.current == name then
			call(name, "Show", args)
			return
		end
		if name == "Home" then
			table.clear(history)
		elseif ctx.current then
			table.insert(history, ctx.current)
			if #history > HISTORY_MAX then
				table.remove(history, 1)
			end
		end
		switchTo(name, args)
	end
	function ctx.open(name, args)
		if not pages[name] then
			warn("[Menu] no overlay", name)
			return
		end
		if table.find(overlays, name) then
			call(name, "Show", args)
			return
		end
		table.insert(overlays, name)
		setVisible(name, true)
		call(name, "Show", args)
		ctx.emit("Overlay", name, true)
	end
	function ctx.close(name)
		local i = table.find(overlays, name)
		if not i then
			return
		end
		table.remove(overlays, i)
		call(name, "Hide")
		setVisible(name, false)
		ctx.emit("Overlay", name, false)
	end
	function ctx.back()
		UiSound.Play("Back")
		if #overlays > 0 then
			ctx.close(overlays[#overlays])
			return
		end
		local prev = table.remove(history) or "Home"
		if prev ~= ctx.current and pages[prev] then
			switchTo(prev)
		end
	end
	function ctx.isOpen(name)
		return ctx.current == name or table.find(overlays, name) ~= nil
	end

	-- gamepad -----------------------------------------------------------------------------------------------------
	-- Focus, the selection frame and the right-stick pointer live in Shared.Menu.Pad (started below).
	function ctx.select(obj)
		Pad.Select(obj)
	end
	local function onPad(action, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		-- a screen on top of the menu (Settings, the crate opener) handles its own B and bumpers
		if not gui.Enabled or Pad.ModalOpen() then
			return Enum.ContextActionResult.Pass
		end
		if action == "MenuBack" then
			ctx.back()
		elseif action == "MenuTabPrev" then
			ctx.emit("TabCycle", -1)
		elseif action == "MenuTabNext" then
			ctx.emit("TabCycle", 1)
		end
		return Enum.ContextActionResult.Sink
	end

	-- show / hide the whole menu (MenuClient decides when) ---------------------------------------------------------
	function ctx.setActive(on)
		ctx.active = on
		gui.Enabled = on
		local back = gui.Parent and gui.Parent:FindFirstChild("MenuBack")
		if back then
			back.Enabled = on
		end
		if on then
			ContextActionService:BindActionAtPriority("MenuBack", onPad, false, 3000, Enum.KeyCode.ButtonB)
			ContextActionService:BindActionAtPriority("MenuTabPrev", onPad, false, 3000, Enum.KeyCode.ButtonL1)
			ContextActionService:BindActionAtPriority("MenuTabNext", onPad, false, 3000, Enum.KeyCode.ButtonR1)
		else
			ContextActionService:UnbindAction("MenuBack")
			ContextActionService:UnbindAction("MenuTabPrev")
			ContextActionService:UnbindAction("MenuTabNext")
			GuiService.SelectedObject = nil
			Pad.HidePointer()
		end
		ctx.emit("Active", on)
	end
	-- persistent pages (TopBar) can be hidden, e.g. in a match server where only the AAR shows
	function ctx.showChrome(on)
		for name, p in pages do
			if p.Persistent then
				setVisible(name, on, true)
			end
		end
	end

	-- start -------------------------------------------------------------------------------------------------------
	for _, m in opts.pages:GetChildren() do
		if m:IsA("ModuleScript") then
			local ok, p = pcall(require, m)
			if ok and type(p) == "table" then
				pages[p.Name or m.Name] = p
			else
				warn("[Menu] page failed to load", m.Name, p)
			end
		end
	end
	ctx.pages = pages
	ctx.overlays = overlays

	ctx.variant = pickVariant()
	applyScale()
	for v in Router.Variants do
		local root = gui:FindFirstChild(v)
		local holder = root and root:FindFirstChild("Pages")
		if holder then
			for _, f in holder:GetChildren() do
				if f:IsA("GuiObject") then
					f.Visible = false
				end
			end
		end
	end
	Ui.Apply(gui)
	for _, d in gui:GetDescendants() do
		if d:IsA("TextLabel") and not d:FindFirstAncestor("Templates") then
			bindText(d)
		end
	end
	for name in pages do
		call(name, "Init")
	end
	ctx.pad = Pad.Start(ctx)
	for name, p in pages do
		if p.Persistent then
			setVisible(name, true, true)
			call(name, "Show")
		end
	end

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local v = pickVariant()
		if v ~= ctx.variant then
			ctx.variant = v
			applyScale()
			for name in pages do
				call(name, "Layout")
			end
			for name, p in pages do
				local f = ctx.frame(name)
				if f then
					f.Visible = name == ctx.current or p.Persistent or table.find(overlays, name) ~= nil
				end
			end
		else
			applyScale()
		end
	end)

	return ctx
end

return Router
