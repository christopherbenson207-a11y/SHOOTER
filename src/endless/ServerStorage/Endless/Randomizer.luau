-- The weapon randomizer (Call of Duty Zombies' mystery box; Config.Randomizer). A chest on one of
-- the House's Box spots, drawn every run, a pale beam of light over it. Hold the prompt and pay
-- Cost: the lid opens and guns flick past for RollTime seconds, slowing down, then it settles on
-- one (weighted by Config.Weapons Box, never a gun you already carry) and holds it OfferTime seconds
-- for you to take (prompt attribute For: only you). Take it and it's in your hands; with full hands
-- the gun you hold is swapped out.
-- After MinUses spins at one spot, every spin has MoveChance of turning up the skull instead: your
-- points come back, the chest shakes and rises away, and MoveTime later it stands on another Box
-- spot (HUD line: THE RANDOMIZER HAS MOVED).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Endless.Config)
local GunModel = require(ReplicatedStorage.Endless.GunModel)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)

local BOX = Config.Randomizer

local Randomizer = {}

local GLOW = Color3.fromRGB(150, 210, 255)

local function part(parent, name, cf, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ghost(p)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- The chest at a spot: body, lid (hinged at the back), inner glow, beam, and a display of every gun
-- it can give (all hidden; show() lets one be seen).
local function buildChest(spot, parent)
	local model = Instance.new("Model")
	model.Name = "Randomizer"
	local base = spot.CFrame * CFrame.new(0, 0, -1.6)
	local body = part(model, "Body", base * CFrame.new(0, 1.2, 0), Vector3.new(5.4, 2.4, 2.8), Color3.fromRGB(70, 46, 30), Enum.Material.Wood)
	for _, x in { -2.5, 2.5 } do
		ghost(part(model, "Band", base * CFrame.new(x, 1.2, 0), Vector3.new(0.25, 2.5, 2.9), Color3.fromRGB(150, 120, 60), Enum.Material.Metal))
	end
	local glow = ghost(part(model, "Glow", base * CFrame.new(0, 2.3, 0), Vector3.new(4.8, 0.2, 2.2), GLOW, Enum.Material.Neon))
	local hingeCf = base * CFrame.new(0, 2.4, 1.4)
	local lid = part(model, "Lid", hingeCf * CFrame.new(0, 0.2, -1.4), Vector3.new(5.4, 0.4, 2.8), Color3.fromRGB(80, 54, 34), Enum.Material.Wood)
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Brightness = 1.2
	light.Range = 16
	light.Parent = glow
	-- The beam: a column of light up from the chest.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.2, 0)
	a0.Parent = glow
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 9, 0)
	a1.Parent = glow
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 2.6
	beam.Width1 = 0.6
	beam.Color = ColorSequence.new(GLOW)
	beam.Transparency = NumberSequence.new(0.35, 1)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = glow

	local prompt = Util.Prompt(body, "Spin  (" .. BOX.Cost .. ")", "Weapon Randomizer", BOX.HoldTime, 8)
	prompt:SetAttribute("Price", BOX.Cost)

	-- Where a gun floats while it rolls and waits.
	local showAt = base * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, math.rad(90), 0)
	local displays = {}
	for id, w in Config.Weapons do
		if (w.Box or 0) > 0 then
			local m = GunModel.Build(id, { Anchored = true, CFrame = showAt })
			for _, p in m:GetDescendants() do
				if p:IsA("BasePart") then
					p:SetAttribute("Shown", p.Transparency)
					p.Transparency = 1
				end
			end
			m.Parent = model
			displays[id] = m
		end
	end
	local skull = Instance.new("Model")
	skull.Name = "Skull"
	local bone = Color3.fromRGB(222, 214, 196)
	ghost(part(skull, "Cranium", showAt, Vector3.new(1.3, 1.3, 1.3), bone, Enum.Material.SmoothPlastic, Enum.PartType.Ball))
	ghost(part(skull, "Jaw", showAt * CFrame.new(0, -0.6, 0.15), Vector3.new(0.9, 0.4, 0.8), bone))
	for _, x in { -0.28, 0.28 } do
		ghost(part(skull, "Socket", showAt * CFrame.new(x, 0.05, -0.55), Vector3.new(0.38, 0.38, 0.38), Color3.new(), Enum.Material.SmoothPlastic, Enum.PartType.Ball))
	end
	for _, p in skull:GetChildren() do
		p:SetAttribute("Shown", 0)
		p.Transparency = 1
	end
	skull.Parent = model
	displays.Skull = skull

	local takeAnchor = ghost(part(model, "TakePoint", showAt, Vector3.new(0.4, 0.4, 0.4), GLOW))
	takeAnchor.Transparency = 1
	local take = Util.Prompt(takeAnchor, "Take", "", 0.25, 8)
	take.Enabled = false

	model.Parent = parent
	return {
		Model = model,
		Body = body,
		Lid = lid,
		LidHome = lid.CFrame,
		Hinge = hingeCf,
		Glow = glow,
		Light = light,
		Prompt = prompt,
		Take = take,
		ShowAt = showAt,
		Displays = displays,
	}
end

local function show(chest, id, at: CFrame?)
	for key, m in chest.Displays do
		local on = key == id
		if at and on then
			m:PivotTo(at)
		end
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = if on then p:GetAttribute("Shown") or 0 else 1
			end
		end
	end
end

local function lid(chest, open: boolean)
	local goal = if open
		-- (+105 about the hinge's X: the front edge, at -Z from the hinge, swings up and back.)
		then chest.Hinge * CFrame.Angles(math.rad(105), 0, 0) * chest.Hinge:Inverse() * chest.LidHome
		else chest.LidHome
	TweenService:Create(chest.Lid, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = goal }):Play()
end

local function roll(player)
	return Util.Weighted(
		(function()
			local weights = {}
			for id, w in Config.Weapons do
				weights[id] = w.Box or 0
			end
			return weights
		end)(),
		function(id)
			return Arsenal.Find(player, id) ~= nil
		end
	)
end

function Randomizer.Setup(run, maid)
	local house = run.House
	local spots = house.Spots.Box
	if #spots == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "RandomizerSpot"
	folder.Parent = house.Model
	maid:Add(folder)

	local current = math.random(#spots)
	local uses = 0
	local busy = false
	local chest

	local function place(index)
		if chest then
			chest.Model:Destroy()
		end
		current = index
		uses = 0
		chest = buildChest(spots[index], folder)
		chest.Prompt.Triggered:Connect(function(player)
			if busy or not Survivors.IsStanding(player) then
				return
			end
			if not Economy.Spend(player, BOX.Cost) then
				return
			end
			busy = true
			chest.Prompt.Enabled = false
			uses += 1
			local result = if uses > BOX.MinUses and math.random() < BOX.MoveChance then "Skull" else roll(player)
			if not result then
				-- They carry every gun there is.
				Economy.Bonus(player, BOX.Cost)
				chest.Prompt.Enabled = true
				busy = false
				return
			end
			lid(chest, true)
			Sfx.Play("Night/Stinger", { Position = chest.Body.Position, Volume = 0.6 })
			chest.Light.Brightness = 3
			-- Guns flick past, slowing, rising out of the chest.
			local t, gap = 0, 0.08
			local pool = {}
			for id in chest.Displays do
				if id ~= "Skull" then
					table.insert(pool, id)
				end
			end
			while t < BOX.RollTime do
				local rise = math.min(t / BOX.RollTime, 1) * 1.8
				show(chest, pool[math.random(#pool)], chest.ShowAt * CFrame.new(0, rise, 0))
				task.wait(gap)
				t += gap
				gap = math.min(0.35, gap * 1.09)
			end
			local at = chest.ShowAt * CFrame.new(0, 1.8, 0)
			show(chest, result, at)
			if result == "Skull" then
				Sfx.Play(Config.Zombie.Sounds .. "/Aggro", { Position = chest.Body.Position })
				task.wait(1.6)
				show(chest, nil)
				Economy.Bonus(player, BOX.Cost)
				-- Shake, rise, gone; then it lands somewhere else.
				for _, p in chest.Model:GetDescendants() do
					if p:IsA("BasePart") then
						TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = p.CFrame + Vector3.new(0, 10, 0), Transparency = 1 }):Play()
					end
				end
				task.wait(1.7)
				chest.Model:Destroy()
				chest = nil
				task.wait(BOX.MoveTime)
				if not folder.Parent then
					return
				end
				local others = {}
				for i = 1, #spots do
					if i ~= current then
						table.insert(others, i)
					end
				end
				place(if #others > 0 then others[math.random(#others)] else current)
				Net.Get("Hud"):FireAllClients("Notice", "THE RANDOMIZER HAS MOVED")
				busy = false
				return
			end
			-- Offer it to the buyer.
			local name = Config.Weapons[result].Name
			chest.Take.ActionText = "Take " .. name
			chest.Take:SetAttribute("For", player.UserId)
			chest.Take.Enabled = true
			local taken = false
			local conn = chest.Take.Triggered:Connect(function(who)
				if who == player and not taken and Survivors.IsStanding(who) then
					taken = true
					Arsenal.Give(who, result)
					Sfx.Play("Pickup/Ammo", { Position = chest.Body.Position })
				end
			end)
			local waited = 0
			while waited < BOX.OfferTime and not taken and chest and chest.Model.Parent do
				waited += task.wait(0.1)
				-- The gun sinks back as its time runs out.
				show(chest, result, at * CFrame.new(0, -1.6 * waited / BOX.OfferTime, 0))
			end
			conn:Disconnect()
			if not chest or not chest.Model.Parent then
				return
			end
			chest.Take.Enabled = false
			chest.Take:SetAttribute("For", nil)
			show(chest, nil)
			lid(chest, false)
			chest.Light.Brightness = 1.2
			task.wait(0.5)
			chest.Prompt.Enabled = true
			busy = false
		end)
	end
	place(current)
	maid:Add(function()
		if chest then
			chest.Model:Destroy()
			chest = nil
		end
	end)
end

return Randomizer
