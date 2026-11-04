-- Invite toast (FRONT-A, 4 Nov 2026): a squad invite from another player, with ACCEPT, DECLINE and a 20 s timer bar.
-- Opens on Remotes.Party "Invited" {PartyId, FromUserId, FromName} while the menu is up (not during the first
-- deploy or the loading screen). A newer invite replaces the one showing. Elements: notes/SCREENS-A.md (Invite).

local RunService = game:GetService("RunService")

local Page = { Name = "Invite", Overlay = true }

local SHOW_TIME = 20

local ctxRef = nil
local wired = {}
local invite = nil -- the payload showing
local shownAt = 0
local conn = nil

local function close()
	if ctxRef and ctxRef.isOpen("Invite") then
		ctxRef.close("Invite")
	end
end

local function wire(ctx)
	local E = {}
	for _, path in { "Panel", "Panel/From", "Panel/Accept", "Panel/Decline", "Panel/Timer" } do
		E[path] = ctx.el("Invite", path)
	end
	local ui = ctx.ui
	if E["Panel/Accept"] then
		ui.Button(E["Panel/Accept"], function()
			if invite then
				ctx.party("Accept", invite.PartyId)
			end
			invite = nil
			close()
		end, { Sound = "Deploy" })
	end
	if E["Panel/Decline"] then
		ui.Button(E["Panel/Decline"], function()
			if invite then
				ctx.party("Decline", invite.PartyId)
			end
			invite = nil
			close()
		end, { Sound = "Back" })
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

local function fill()
	local ctx = ctxRef
	local E = els(ctx)
	ctx.ui.Text(E["Panel/From"], string.upper(tostring(invite and invite.FromName or "")))
end

function Page.Init(ctx)
	ctxRef = ctx
	els(ctx)
	-- the toast draws above every page and overlay (pages are siblings under ZIndexBehavior Sibling)
	for _, v in { "Wide", "Phone" } do
		local f = ctx.gui:FindFirstChild(v) and ctx.gui[v]:FindFirstChild("Pages") and ctx.gui[v].Pages:FindFirstChild("Invite")
		if f then
			f.ZIndex = 50
		end
	end
	ctx.on("Invited", function(p)
		if type(p) ~= "table" or not p.PartyId then
			return
		end
		if not ctx.active or ctx.player:GetAttribute("InMatch") == true
			or ctx.current == "FirstDeploy" or ctx.current == "Loading" or ctx.current == "Aar"
		then
			return
		end
		ctx.open("Invite", p)
	end)
	ctx.on("Deploying", close)
	ctx.on("Active", function(on)
		if not on then
			close()
		end
	end)
end

function Page.Layout(ctx)
	ctxRef = ctx
	els(ctx)
	if invite then
		fill()
	end
end

function Page.Show(ctx, p)
	ctxRef = ctx
	if type(p) == "table" then
		invite = p
	end
	shownAt = os.clock()
	fill()
	ctx.sound("Beep")
	local E = els(ctx)
	ctx.select(E["Panel/Accept"])
	if conn then
		conn:Disconnect()
	end
	conn = RunService.Heartbeat:Connect(function()
		local left = 1 - (os.clock() - shownAt) / SHOW_TIME
		ctx.ui.Bar(els(ctx)["Panel/Timer"], left)
		if left <= 0 then
			invite = nil
			close()
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
