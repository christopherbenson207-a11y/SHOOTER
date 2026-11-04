--!strict
-- MenuPages.Record (FRONT-C, 4 Nov 2026): the SERVICE RECORD card, an overlay.
-- Elements and binds: horror-shooter/menu/notes/SCREENS-C.md "RECORD". Data: Store "Record" {UserId} -> Record
-- {UserId, Name, Level, Stars, Rank, Card, Operator, Class, Stats}. Opened with ctx.go("Record") or
-- ctx.open("Record", {UserId = n}) from the TopBar profile plate (your own) or an AAR squad plate. The scrim, CLOSE and
-- gamepad B close it. For your own record the XP bar and the gun level come from your attributes; for someone else
-- they show only when the server sends Xp / GunLevel (see FRONT-C notes, Contract requests).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local P = require(Shared:WaitForChild("Progression"))

local GunStats: any = nil
do
	local m = Shared:FindFirstChild("GunStats")
	if m then
		local ok, v = pcall(require, m)
		GunStats = if ok then v else nil
	end
end

local Page = { Name = "Record", Overlay = true }

local VARIANTS = { "Wide", "Phone" }
local STATS = { "Kills", "Elites", "Headshots", "Revives", "Escapes", "Matches", "EndlessBest", "NightmareEscapes",
	"CampaignClears" }

local state = {
	shown = false,
	userId = nil :: number?,
	record = nil :: any,
	token = 0,
}
local statics: { [string]: { [string]: any } } = {}

local function find(root: Instance?, path: string): any
	local node: Instance? = root
	for _, part in string.split(path, "/") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local function frameOf(ctx: any, variant: string): Instance?
	local root = ctx.gui:FindFirstChild(variant)
	local pages = root and root:FindFirstChild("Pages")
	return pages and pages:FindFirstChild(Page.Name)
end

local function setVisible(inst: Instance?, on: boolean)
	if inst and inst:IsA("GuiObject") then
		inst.Visible = on
	end
end

local function money(n: number?): string
	local s = tostring(math.floor(tonumber(n) or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function suffix(label: Instance?, word: string): string
	if not (label and label:IsA("TextLabel")) then
		return ""
	end
	local s = label:GetAttribute("_Suffix")
	if s == nil then
		s = if string.find(label.Text, word, 1, true) then " " .. word else ""
		label:SetAttribute("_Suffix", s)
	end
	return s :: string
end

function Page.GunName(key: string?): string
	if not key then
		return ""
	end
	if GunStats then
		local ok, info = pcall(GunStats.Info, key)
		if ok and type(info) == "table" and info.Name then
			return string.upper(info.Name)
		end
	end
	return string.upper(key)
end

-- XP into / need for a record: the server's when it sends them, else your own attributes, else none.
function Page.XpOf(rec: any, mine: boolean, attr: (string) -> any): (number?, number?)
	if type(rec.Xp) == "table" then
		return tonumber(rec.Xp.Into), tonumber(rec.Xp.Need)
	end
	if tonumber(rec.XpInto) and tonumber(rec.XpNeed) then
		return tonumber(rec.XpInto), tonumber(rec.XpNeed)
	end
	if type(rec.Xp) == "number" then
		local _, into, need = P.FromXp(rec.Xp)
		return into, need
	end
	if mine then
		return tonumber(attr("XpInto")), tonumber(attr("XpNeed"))
	end
	return nil, nil
end

function Page.GunLevelOf(rec: any, mine: boolean, attr: (string) -> any): number?
	if tonumber(rec.GunLevel) then
		return tonumber(rec.GunLevel)
	end
	local gun = type(rec.Stats) == "table" and rec.Stats.MostUsedGun or nil
	if mine and gun then
		local xp = attr("GunXp")
		if type(xp) == "table" then
			return (P.WeaponFromXp(tonumber(xp[gun]) or 0))
		end
	end
	return nil
end

local function render(ctx: any)
	local frame = ctx.frame(Page.Name)
	local rec = state.record
	if not frame then
		return
	end
	local ui = ctx.ui
	local card = frame:FindFirstChild("Card")
	if not rec then
		-- loading: clear the live text so a previous player's record never shows under a new name
		for _, d in (card and card:GetDescendants() or {}) do
			if d:IsA("TextLabel") then
				d.Text = ""
			end
		end
		setVisible(find(card, "Stars"), false)
		return
	end
	local mine = rec.UserId == nil or rec.UserId == ctx.player.UserId
	local level = tonumber(rec.Level) or 1
	ui.SetArt(find(card, "Rank"), "Rank/" .. tostring(rec.Rank or P.Rank(level)))
	ui.Text(find(card, "Level"), level)
	local stars = tonumber(rec.Stars) or 0
	setVisible(find(card, "Stars"), stars > 0)
	ui.Text(find(card, "Stars/Count"), stars)
	local nameLabel = find(card, "Name")
	ui.Text(nameLabel, string.upper(tostring(rec.Name or "")))
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	end
	local cc = find(card, "CallingCard")
	if cc then
		ui.SetArt(cc, "Card/" .. tostring(rec.Card or "Default"))
		cc.ScaleType = Enum.ScaleType.Crop
	end

	local into, need = Page.XpOf(rec, mine, ctx.attr)
	local xpText = find(card, "XpText")
	setVisible(find(card, "XpBar"), into ~= nil)
	setVisible(xpText, into ~= nil)
	if into and need then
		ui.Bar(find(card, "XpBar"), if need > 0 then into / need else 1)
		ui.Text(xpText, money(into) .. " / " .. money(need) .. suffix(xpText, "XP"))
	end

	local stats = if type(rec.Stats) == "table" then rec.Stats else {}
	for _, name in STATS do
		ui.Text(find(card, name .. "/Value"), money(stats[name]))
	end

	local gun = stats.MostUsedGun
	local most = find(card, "MostUsed")
	setVisible(find(most, "GunArt"), gun ~= nil)
	if gun then
		ui.SetArt(find(most, "GunArt"), "Gun/" .. tostring(gun))
	end
	ui.Text(find(most, "GunName"), Page.GunName(gun))
	local gl = if gun then Page.GunLevelOf(rec, mine, ctx.attr) else nil
	setVisible(find(most, "GunLevel"), gl ~= nil)
	ui.Text(find(most, "GunLevel"), if gl then "LV " .. gl else "")
end

local function close(ctx: any)
	if ctx.isOpen and ctx.isOpen(Page.Name) then
		ctx.close(Page.Name)
	else
		ctx.back()
	end
end

local function wireStatic(ctx: any, variant: string)
	local frame = frameOf(ctx, variant)
	if not frame then
		return
	end
	local s = {}
	local b = find(frame, "Card/Close")
	if b and b:IsA("GuiButton") then
		s.Close = ctx.ui.Button(b, function()
			close(ctx)
		end, { Sound = "Back" })
	end
	local scrim = frame:FindFirstChild("Scrim")
	if scrim and scrim:IsA("GuiObject") then
		scrim.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) and state.shown and ctx.variant == variant then
				ctx.sound("Back")
				close(ctx)
			end
		end)
	end
	-- the card itself takes clicks, so only the scrim around it closes
	local card = frame:FindFirstChild("Card")
	if card and card:IsA("GuiObject") then
		card.Active = true
	end
	statics[variant] = s
end

function Page.Init(ctx: any)
	for _, v in VARIANTS do
		wireStatic(ctx, v)
	end
	-- your own record follows your attributes while it is open
	for _, name in { "Level", "XpInto", "Stats", "Card", "Stars" } do
		ctx.onAttr(name, function()
			if state.shown and (state.userId == nil or state.userId == ctx.player.UserId) then
				local token = state.token
				task.delay(0.2, function()
					if state.shown and state.token == token then
						local res = ctx.store("Record", {})
						if res.Ok and type(res.Record) == "table" and state.token == token then
							state.record = res.Record
							render(ctx)
						end
					end
				end)
			end
		end)
	end
end

function Page.Layout(ctx: any)
	if state.shown then
		render(ctx)
	end
end

function Page.Show(ctx: any, args: any)
	state.shown = true
	state.token += 1
	local token = state.token
	local userId = if type(args) == "table" then tonumber(args.UserId) else nil
	if userId == ctx.player.UserId then
		userId = nil
	end
	state.userId = userId
	state.record = nil
	local frame = ctx.frame(Page.Name)
	if frame and frame:IsA("GuiObject") then
		frame.ZIndex = 20 -- above every page (all pages are siblings)
		-- the scrim is the variant's size; on a wider or taller screen stretch it past the edges so it covers all
		local scrim = frame:FindFirstChild("Scrim")
		if scrim and scrim:IsA("GuiObject") then
			scrim.AnchorPoint = Vector2.new(0.5, 0.5)
			scrim.Position = UDim2.fromScale(0.5, 0.5)
			scrim.Size = UDim2.fromScale(3, 3)
		end
	end
	render(ctx)
	ctx.select(ctx.el(Page.Name, "Card/Close"))
	task.spawn(function()
		local res = ctx.store("Record", if userId then { UserId = userId } else {})
		if state.token ~= token or not state.shown then
			return
		end
		if res.Ok and type(res.Record) == "table" then
			state.record = res.Record
			render(ctx)
		else
			ctx.sound("Error")
			close(ctx)
		end
	end)
end

function Page.Hide(_ctx: any)
	state.shown = false
	state.token += 1
end

return Page
