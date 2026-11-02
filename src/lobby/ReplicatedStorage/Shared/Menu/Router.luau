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
local UiSound = require(script.Parent.UiSound)

local Router = {}

Router.Variants = { Wide = Vector2.new(1920, 1080), Phone = Vector2.new(1688, 780) }
local HISTORY_MAX = 10

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
				local s = root:FindFirstChild("VariantScale")
				if not s then
					s = Instance.new("UIScale")
					s.Name = "VariantScale"
					s.Parent = root
				end
				s.Scale = math.max(0.1, math.min(size.X / ref.X, size.Y / ref.Y))
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
	function ctx.select(obj)
		local last = UserInputService:GetLastInputType()
		if obj and last.Name:find("Gamepad") then
			GuiService.SelectedObject = obj
		end
	end
	local function onPad(action, state)
		if state ~= Enum.UserInputState.Begin then
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
