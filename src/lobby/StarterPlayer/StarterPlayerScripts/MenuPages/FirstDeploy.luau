-- First deploy (FRONT-A, 4 Nov 2026; MENU-PLAN 9.3): a new player's first menu is the logo and one DEPLOY over the
-- scene, with no top bar. DEPLOY sends Remotes.Menu "FirstDeploy" (the server picks the first mode, solo). The full
-- menu is revealed after the first match's AAR (MenuClient). Elements: notes/SCREENS-A.md (FirstDeploy).

local RunService = game:GetService("RunService")

local Page = { Name = "FirstDeploy", Camera = "Home" }

local ctxRef = nil
local wired = {}
local sent = false
local conn = nil

local function wire(ctx)
	local E = {}
	for _, path in { "Logo", "DeployGlow", "Deploy" } do
		E[path] = ctx.el("FirstDeploy", path)
	end
	if E.Deploy then
		E.DeployCtl = ctx.ui.Button(E.Deploy, function()
			if sent then
				return
			end
			sent = true
			E.DeployCtl.Disabled(true)
			ctx.menu("FirstDeploy")
		end, { Sound = "Deploy" })
	end
	return E
end

local function els(ctx)
	local v = ctx.variant
	if not wired[v] then
		wired[v] = wire(ctx)
	end
	return wired[v]
end

local function rearm()
	sent = false
	for _, E in wired do
		if E.DeployCtl then
			E.DeployCtl.Disabled(false)
		end
	end
end

function Page.Init(ctx)
	ctxRef = ctx
	els(ctx)
	ctx.on("DeployFailed", rearm)
end

function Page.Layout(ctx)
	ctxRef = ctx
	els(ctx)
end

function Page.Show(ctx)
	ctxRef = ctx
	rearm()
	ctx.showChrome(false)
	local E = els(ctx)
	ctx.select(E.Deploy)
	if conn then
		conn:Disconnect()
	end
	local t = 0
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		local glow = els(ctx).DeployGlow
		if glow then
			glow.ImageTransparency = 0.3 + math.sin(t * 1.6) * 0.2
		end
	end)
end

function Page.Hide()
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

return Page
