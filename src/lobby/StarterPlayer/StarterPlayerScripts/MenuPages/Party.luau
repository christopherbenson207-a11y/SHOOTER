-- Party overlay (FRONT-A, 4 Nov 2026): every player in this server who is not in your squad, friends first, each with
-- INVITE (sent once per 30 s per player); FRIENDS opens Roblox's game invite prompt; CLOSE or B closes it.
-- Elements: notes/SCREENS-A.md (Party table). Remotes.Party "Invite", userId.

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local Common = require(script.Parent:WaitForChild("TopBar"):WaitForChild("Common"))

local Page = { Name = "Party", Overlay = true }

local INVITE_COOLDOWN = 30

local ctxRef = nil
local wired = {}
local shown = false
local sentAt = {} -- [userId] = os.clock() of the last invite
local friends = {} -- [userId] = bool (cached IsFriendsWith)
local thumbs = {} -- [userId] = content id

local function wire(ctx)
	local E = {}
	for _, path in { "Scrim", "Panel", "Panel/Close", "Panel/Players", "Panel/Friends" } do
		E[path] = ctx.el("Party", path)
	end
	local ui = ctx.ui
	if E["Panel/Close"] then
		ui.Button(E["Panel/Close"], function()
			ctx.close("Party")
		end, { Sound = "Back" })
	end
	if E.Scrim and E.Scrim:IsA("GuiObject") then
		-- stretch past the variant's edges so ultrawide and tall screens are dimmed too (INTEGRATION)
		E.Scrim.AnchorPoint = Vector2.new(0.5, 0.5)
		E.Scrim.Position = UDim2.fromScale(0.5, 0.5)
		E.Scrim.Size = UDim2.fromScale(3, 3)
	end
	if E.Scrim and E.Scrim:IsA("GuiButton") then
		E.Scrim.Activated:Connect(function()
			ctx.close("Party")
		end)
	end
	if E["Panel/Friends"] then
		ui.Button(E["Panel/Friends"], function()
			local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, ctx.player)
			if ok and can then
				pcall(SocialService.PromptGameInvite, SocialService, ctx.player)
			else
				ctx.sound("Error")
			end
		end)
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

local function inSquad(ctx, userId)
	for _, m in Common.Squad(ctx).Members do
		if m.UserId == userId then
			return true
		end
	end
	return false
end

local refresh

-- Friend flags and head shots arrive asynchronously; each one refreshes the list once.
local function lookUp(ctx, p)
	local id = p.UserId
	if friends[id] == nil then
		friends[id] = false
		task.spawn(function()
			local ok, yes = pcall(ctx.player.IsFriendsWith, ctx.player, id)
			friends[id] = ok and yes == true
			if friends[id] and shown then
				refresh()
			end
		end)
	end
	if thumbs[id] == nil then
		thumbs[id] = ""
		task.spawn(function()
			local ok, img = pcall(Players.GetUserThumbnailAsync, Players, id, Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150)
			if ok and img then
				thumbs[id] = img
				if shown then
					refresh()
				end
			end
		end)
	end
end

refresh = function()
	local ctx = ctxRef
	if not ctx then
		return
	end
	local E = els(ctx)
	local ui = ctx.ui
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= ctx.player and not inSquad(ctx, p.UserId) and p:GetAttribute("InMatch") ~= true then
			lookUp(ctx, p)
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		local fa, fb = friends[a.UserId] == true, friends[b.UserId] == true
		if fa ~= fb then
			return fa
		end
		return a.DisplayName < b.DisplayName
	end)
	local full = #Common.Squad(ctx).Members >= 4
	local rows = ui.Fill(E["Panel/Players"], list, function(row, p)
		local avatar = row:FindFirstChild("Avatar")
		if avatar and thumbs[p.UserId] and thumbs[p.UserId] ~= "" then
			avatar.Image = thumbs[p.UserId]
		end
		local emblem = row:FindFirstChild("Emblem")
		local class = p:GetAttribute("Class") or "Rifleman"
		if emblem and ui.Art("Emblem/" .. class) then
			ui.SetArt(emblem, "Emblem/" .. class)
		end
		ui.Text(row:FindFirstChild("Name"), string.upper(p.DisplayName ~= "" and p.DisplayName or p.Name))
		ui.Text(row:FindFirstChild("Level"), "LV " .. tostring(p:GetAttribute("Level") or 1))
		local friend = row:FindFirstChild("Friend")
		if friend then
			friend.Visible = friends[p.UserId] == true
		end
		local invite = row:FindFirstChild("Invite")
		if invite then
			local id = p.UserId
			local ctl
			ctl = ui.Button(invite, function()
				if sentAt[id] and os.clock() - sentAt[id] < INVITE_COOLDOWN then
					return
				end
				sentAt[id] = os.clock()
				ctx.party("Invite", id)
				ctl.Selected(true)
				task.delay(INVITE_COOLDOWN, function()
					if shown then
						refresh()
					end
				end)
			end, { Sound = "Beep" })
			local sent = sentAt[id] and os.clock() - sentAt[id] < INVITE_COOLDOWN
			ctl.Selected(sent == true)
			ctl.Disabled(full)
		end
	end)
	local scroll = E["Panel/Players"]
	if scroll and scroll:IsA("ScrollingFrame") then
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
	end
	return rows
end

function Page.Init(ctx)
	ctxRef = ctx
	els(ctx)
	-- overlays draw above the page under them (pages are siblings under ZIndexBehavior Sibling)
	for _, v in { "Wide", "Phone" } do
		local f = ctx.gui:FindFirstChild(v) and ctx.gui[v]:FindFirstChild("Pages") and ctx.gui[v].Pages:FindFirstChild("Party")
		if f then
			f.ZIndex = 40
		end
	end
	ctx.on("Party", function()
		if shown then
			refresh()
		end
	end)
	local function changed()
		if shown then
			task.defer(refresh)
		end
	end
	Players.PlayerAdded:Connect(changed)
	Players.PlayerRemoving:Connect(function(p)
		sentAt[p.UserId] = nil
		changed()
	end)
end

function Page.Layout(ctx)
	ctxRef = ctx
	els(ctx)
	if shown then
		refresh()
	end
end

function Page.Show(ctx)
	ctxRef = ctx
	shown = true
	local rows = refresh()
	local E = els(ctx)
	local first = rows and rows[1]
	ctx.select(if first and first:FindFirstChild("Invite") then first.Invite else E["Panel/Close"])
end

function Page.Hide()
	shown = false
end

return Page
