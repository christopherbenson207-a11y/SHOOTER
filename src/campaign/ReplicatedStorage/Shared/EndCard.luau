--!nonstrict
-- Shared.EndCard (5 Nov 2026, kid reskin): the end-of-match card in the lobby menu's style, for the places that are
-- not the lobby (Zombies, the campaign, the 1v1 duel). Owner: the old end screens were "archaic and do not conform to
-- the lobby ui style". Every piece is authored PNG art (horror-shooter/menu/art/screens/EndCard.py); only the words
-- that change (star names, the stats line, the note, mode names) are live text.
--
--   local card = EndCard.Show(parentGui, {
--       Result = "Escaped" | "Survived" | "Overrun" | "TowerLost" | "Victory" | "Defeat" | "Complete" | "Failed",
--       Stars = { {Name = "ESCAPED", Hint = "Got out on the helicopter", Got = true}, ... } or nil (row hidden),
--       Stats = "REACHED ROUND 12  ·  BEST 14  ·  +350 POINTS",
--       Note = "",                       -- one small line under the buttons
--       Modes = { {Name = "ENDLESS", Locked = false, Click = fn}, ... } or nil (SWITCH MODE hidden),
--       PlayAgain = fn or nil (button hidden), Lobby = fn or nil (button hidden),
--       ZIndex = 50,
--   })
--   card.SetNote(text); card.Destroy()
-- Design size 880 x 600; a UIScale shrinks it on small screens (a phone gets about 0.6).

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local EndCard = {}

local ART = {
	["Banner/Complete"] = { Id = "rbxassetid://120268102969760", W = 1000, H = 150 },
	["Banner/Defeat"] = { Id = "rbxassetid://124578559724928", W = 1000, H = 150 },
	["Banner/Escaped"] = { Id = "rbxassetid://109425399355079", W = 1000, H = 150 },
	["Banner/Failed"] = { Id = "rbxassetid://107491700629137", W = 1000, H = 150 },
	["Banner/Overrun"] = { Id = "rbxassetid://100935354220882", W = 1000, H = 150 },
	["Banner/Survived"] = { Id = "rbxassetid://125852604443103", W = 1000, H = 150 },
	["Banner/TowerLost"] = { Id = "rbxassetid://107139260229910", W = 1000, H = 150 },
	["Banner/Victory"] = { Id = "rbxassetid://119922636552987", W = 1000, H = 150 },
	["Base"] = { Id = "rbxassetid://102622411107517", W = 880, H = 600 },
	["Lobby_Disabled"] = { Id = "rbxassetid://97631754552946", W = 230, H = 56 },
	["Lobby_Down"] = { Id = "rbxassetid://140537972310660", W = 230, H = 56 },
	["Lobby_Hover"] = { Id = "rbxassetid://87472945078028", W = 230, H = 56 },
	["Lobby_Idle"] = { Id = "rbxassetid://107203236054751", W = 230, H = 56 },
	["Lobby_Selected"] = { Id = "rbxassetid://94792850692680", W = 230, H = 56 },
	["ModePill_Disabled"] = { Id = "rbxassetid://137789239983694", W = 196, H = 48 },
	["ModePill_Down"] = { Id = "rbxassetid://111252840497766", W = 196, H = 48 },
	["ModePill_Hover"] = { Id = "rbxassetid://115173215048051", W = 196, H = 48 },
	["ModePill_Idle"] = { Id = "rbxassetid://120416776142856", W = 196, H = 48 },
	["ModePill_Selected"] = { Id = "rbxassetid://102686790478690", W = 196, H = 48 },
	["PlayAgain_Disabled"] = { Id = "rbxassetid://122725317336462", W = 300, H = 72 },
	["PlayAgain_Down"] = { Id = "rbxassetid://89050263226813", W = 300, H = 72 },
	["PlayAgain_Hover"] = { Id = "rbxassetid://95602582160428", W = 300, H = 72 },
	["PlayAgain_Idle"] = { Id = "rbxassetid://128645128539846", W = 300, H = 72 },
	["StarOff"] = { Id = "rbxassetid://85904148107897", W = 76, H = 76 },
	["StarOn"] = { Id = "rbxassetid://133651161186833", W = 76, H = 76 },
	["Switch_Disabled"] = { Id = "rbxassetid://76437134685093", W = 230, H = 56 },
	["Switch_Down"] = { Id = "rbxassetid://134664576244818", W = 230, H = 56 },
	["Switch_Hover"] = { Id = "rbxassetid://76397133598499", W = 230, H = 56 },
	["Switch_Idle"] = { Id = "rbxassetid://92329697530023", W = 230, H = 56 },
	["Switch_Selected"] = { Id = "rbxassetid://80463171331467", W = 230, H = 56 },
	["Scrim"] = { Id = "rbxassetid://83896641339858", W = 256, H = 144 },
}
EndCard.Art = ART

-- the lobby palette (horror-shooter/menu/art/recolour.py)
local COLOR = {
	TEXT = Color3.fromRGB(255, 255, 255),
	MUTED = Color3.fromRGB(164, 179, 237),
	AMBER = Color3.fromRGB(255, 212, 38),
	INK = Color3.fromRGB(16, 21, 62),
}
EndCard.Color = COLOR

local OSWALD = "rbxasset://fonts/families/Oswald.json"
local CONDENSED = "rbxasset://fonts/families/RobotoCondensed.json"

local CARD_W, CARD_H = 880, 600
local L = {
	banner = { 40, 26, 800, 120 },
	stars = { x = 40, y = 168, cell = 266, star = 76, nameY = 82, nameH = 30, hintY = 112, hintH = 26 },
	stats = { 40, 330, 800, 34 },
	playAgain = { 40, 392, 300, 72 },
	switch = { 364, 400, 230, 56 },
	lobby = { 610, 400, 230, 56 },
	modes = { 40, 482, 800, 48 },
	note = { 40, 544, 800, 30 },
}

local function image(name, key, rect, parent, z)
	local a = ART[key]
	local i = Instance.new("ImageLabel")
	i.Name = name
	i.BackgroundTransparency = 1
	i.Image = a and a.Id or ""
	i.Position = UDim2.fromOffset(rect[1], rect[2])
	i.Size = UDim2.fromOffset(rect[3], rect[4])
	i.ZIndex = z
	i.Parent = parent
	return i
end

local function text(name, rect, s, size, color, face, parent, z, align)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(rect[1], rect[2])
	t.Size = UDim2.fromOffset(rect[3], rect[4])
	t.FontFace = Font.new(face or CONDENSED, Enum.FontWeight.Bold)
	t.TextSize = size
	t.TextColor3 = color or COLOR.TEXT
	t.Text = s or ""
	t.TextXAlignment = align or Enum.TextXAlignment.Center
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.ZIndex = z
	t.Parent = parent
	return t
end

-- An art button: Idle / Hover / Down / Disabled images swap with the pointer. Returns the button and setDisabled.
local function button(name, prefix, rect, parent, z, onClick)
	local b = Instance.new("ImageButton")
	b.Name = name
	b.BackgroundTransparency = 1
	b.AutoButtonColor = false
	b.Position = UDim2.fromOffset(rect[1], rect[2])
	b.Size = UDim2.fromOffset(rect[3], rect[4])
	b.ZIndex = z
	b.Parent = parent
	local hover, down, disabled, selected = false, false, false, false
	local function paint()
		local st = if disabled then "Disabled" elseif down then "Down" elseif hover then "Hover"
			elseif selected and ART[prefix .. "_Selected"] then "Selected" else "Idle"
		local a = ART[prefix .. "_" .. st] or ART[prefix .. "_Idle"]
		b.Image = a and a.Id or ""
	end
	paint()
	b.MouseEnter:Connect(function()
		hover = true
		paint()
	end)
	b.MouseLeave:Connect(function()
		hover, down = false, false
		paint()
	end)
	b.MouseButton1Down:Connect(function()
		down = true
		paint()
	end)
	b.MouseButton1Up:Connect(function()
		down = false
		paint()
	end)
	b.Activated:Connect(function()
		if not disabled and onClick then
			onClick()
		end
	end)
	return b, function(on)
		disabled = on
		paint()
	end, function(on)
		selected = on
		paint()
	end
end

function EndCard.Show(parent, o)
	o = o or {}
	local z = o.ZIndex or 50
	local root = Instance.new("Frame")
	root.Name = "EndCard"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = z
	local scrim = image("Scrim", "Scrim", { 0, 0, 0, 0 }, root, z)
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.ScaleType = Enum.ScaleType.Stretch
	scrim.ImageTransparency = 1

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.ZIndex = z + 1
	card.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = card
	image("Base", "Base", { 0, 0, CARD_W, CARD_H }, card, z + 1)

	local banner = image("Banner", "Banner/" .. tostring(o.Result or "Overrun"), L.banner, card, z + 2)
	if not ART["Banner/" .. tostring(o.Result)] then
		banner.Image = ART["Banner/Overrun"].Id
	end

	local starsRow = Instance.new("Frame")
	starsRow.Name = "Stars"
	starsRow.BackgroundTransparency = 1
	starsRow.Size = UDim2.fromOffset(CARD_W, 150)
	starsRow.ZIndex = z + 2
	starsRow.Visible = type(o.Stars) == "table" and #o.Stars > 0
	starsRow.Parent = card
	local S = L.stars
	local starImgs = {}
	for i, s in o.Stars or {} do
		local x = S.x + (i - 1) * S.cell
		local st = image("Star" .. i, "StarOff", { x + (S.cell - S.star) // 2, S.y, S.star, S.star }, starsRow, z + 2)
		st:SetAttribute("Got", s.Got == true)
		table.insert(starImgs, st)
		text("Name" .. i, { x, S.y + S.nameY, S.cell, S.nameH }, s.Name, 22, if s.Got then COLOR.TEXT else COLOR.MUTED,
			OSWALD, starsRow, z + 2)
		text("Hint" .. i, { x + 8, S.y + S.hintY, S.cell - 16, S.hintH }, s.Hint, 18, COLOR.MUTED, CONDENSED, starsRow, z + 2)
	end

	-- without stars, the stats line moves up under the banner
	local statsRect = table.clone(L.stats)
	if not starsRow.Visible then
		statsRect[2] = 200
	end
	text("Stats", statsRect, o.Stats or "", 24, COLOR.TEXT, CONDENSED, card, z + 2)

	local hasModes = type(o.Modes) == "table" and #o.Modes > 0
	local modesRow = Instance.new("Frame")
	modesRow.Name = "Modes"
	modesRow.BackgroundTransparency = 1
	modesRow.Position = UDim2.fromOffset(L.modes[1], L.modes[2])
	modesRow.Size = UDim2.fromOffset(L.modes[3], L.modes[4])
	modesRow.ZIndex = z + 2
	modesRow.Visible = false
	modesRow.Parent = card
	for i, m in o.Modes or {} do
		local b, setDis = button("Mode" .. i, "ModePill", { (i - 1) * (196 + 12), 0, 196, 48 }, modesRow, z + 2, m.Click)
		setDis(m.Locked == true)
		text("Label", { 0, 0, 196, 48 }, m.Name, 20,
			if m.Locked then COLOR.MUTED else COLOR.TEXT, OSWALD, b, z + 3)
	end

	local handles = { Root = root, Card = card }
	if o.PlayAgain then
		handles.PlayAgain, handles.SetPlayAgainDisabled = button("PlayAgain", "PlayAgain", L.playAgain, card, z + 2, o.PlayAgain)
	end
	if hasModes then
		local sw, _, setSel
		sw, _, setSel = button("Switch", "Switch", L.switch, card, z + 2, function()
			modesRow.Visible = not modesRow.Visible
			setSel(modesRow.Visible)
		end)
		handles.Switch = sw
	end
	if o.Lobby then
		-- with no SWITCH MODE, LOBBY takes its place beside PLAY AGAIN; alone, it sits in the middle
		local r = if hasModes then L.lobby elseif o.PlayAgain then L.switch else { (CARD_W - 230) // 2, 400, 230, 56 }
		handles.Lobby = button("Lobby", "Lobby", r, card, z + 2, o.Lobby)
	end
	local note = text("Note", L.note, o.Note or "", 20, COLOR.MUTED, CONDENSED, card, z + 2)
	handles.Note = note
	function handles.SetNote(s)
		note.Text = s or ""
	end

	-- fit the screen
	local function fit()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		local inset = GuiService:GetGuiInset()
		local h = vp.Y - inset.Y
		scale.Scale = math.min(1, (vp.X * 0.94) / CARD_W, (h * 0.94) / CARD_H)
	end
	fit()
	local conns = {}
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(conns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit))
	end

	root.Parent = parent

	-- in: the dim, the card rises a little, then the stars light one by one
	TweenService:Create(scrim, TweenInfo.new(0.25), { ImageTransparency = 0 }):Play()
	card.Position = UDim2.new(0.5, 0, 0.5, 24)
	TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	for i, st in starImgs do
		if st:GetAttribute("Got") then
			task.delay(0.35 + 0.3 * i, function()
				if st.Parent then
					st.Image = ART.StarOn.Id
					st.Size = UDim2.fromOffset(S.star * 1.3, S.star * 1.3)
					st.Position -= UDim2.fromOffset(S.star * 0.15, S.star * 0.15)
					TweenService:Create(st, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
						Size = UDim2.fromOffset(S.star, S.star),
						Position = st.Position + UDim2.fromOffset(S.star * 0.15, S.star * 0.15),
					}):Play()
				end
			end)
		end
	end

	function handles.Destroy()
		for _, c in conns do
			c:Disconnect()
		end
		root:Destroy()
	end
	return handles
end

return EndCard
