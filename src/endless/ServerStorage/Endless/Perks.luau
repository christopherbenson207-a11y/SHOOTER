-- Perk machines and the power switch (Call of Duty Zombies; our tonics, Config.Perks).
-- Every run the perks are dealt out to the House's Perk spots at random and the switch stands on one
-- of its Power spots. Until someone holds the switch, the machines are dark and the house is lit
-- only by dim red lamps; then the lamps come up, the machines light and the altar wakes (workspace
-- attribute Power, Perks.PowerOn signal).
-- Buying a perk sets the player attribute Perk_<Id>; the systems read it (Survivors: Bulwark,
-- Lazarus; Weapons: Quickhand, TwinFang; Arsenal: Packmule). At most Limit at once, all lost when
-- you go down. Lazarus Draught alone is SoloCost and a self-revive, SoloUses times a run (player
-- attribute LazarusBuys).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)

local PERKS = Config.Perks

local Perks = {}
Perks.PowerOn = Util.Signal()

local machines = {} -- list of {Id, Panel, Light, Prompt}
local lamps = {}

function Perks.Has(player: Player, id: string): boolean
	return player:GetAttribute("Perk_" .. id) == true
end

function Perks.Count(player: Player): number
	local n = 0
	for id in PERKS.List do
		if Perks.Has(player, id) then
			n += 1
		end
	end
	return n
end

function Perks.Price(player: Player, id: string): number
	local perk = PERKS.List[id]
	if perk.SoloCost and #Survivors.RunPlayers() <= 1 then
		return perk.SoloCost
	end
	return perk.Cost
end

function Perks.LoseAll(player: Player)
	for id in PERKS.List do
		player:SetAttribute("Perk_" .. id, nil)
	end
	Survivors.RefreshMaxHealth(player)
	Arsenal.Trim(player)
	Arsenal.Refresh(player)
end

-- Run start.
function Perks.Reset(player: Player)
	for id in PERKS.List do
		player:SetAttribute("Perk_" .. id, nil)
	end
	player:SetAttribute("LazarusBuys", nil)
end

local function notice(player, text)
	Net.Get("Hud"):FireClient(player, "Notice", text)
end

local function buy(player, id)
	local perk = PERKS.List[id]
	if not Survivors.IsStanding(player) then
		return
	end
	if workspace:GetAttribute("Power") ~= true then
		notice(player, "THE POWER IS OFF")
		return
	end
	if Perks.Has(player, id) then
		return
	end
	if Perks.Count(player) >= PERKS.Limit then
		notice(player, "YOU CAN'T HOLD ANOTHER PERK")
		return
	end
	local solo = #Survivors.RunPlayers() <= 1
	if id == "Lazarus" and solo and (player:GetAttribute("LazarusBuys") or 0) >= perk.SoloUses then
		notice(player, "THE MACHINE IS EMPTY")
		return
	end
	if not Economy.Spend(player, Perks.Price(player, id)) then
		return
	end
	if id == "Lazarus" and solo then
		player:SetAttribute("LazarusBuys", (player:GetAttribute("LazarusBuys") or 0) + 1)
	end
	player:SetAttribute("Perk_" .. id, true)
	if id == "Bulwark" then
		Survivors.RefreshMaxHealth(player)
	end
	Sfx.Play("Pickup/Bandage", { Parent = player.Character and player.Character:FindFirstChild("HumanoidRootPart") })
	notice(player, string.upper(perk.Name) .. "  \u{00B7}  " .. perk.Text)
end

local function buildMachine(spot, id, parent)
	local perk = PERKS.List[id]
	local model = Instance.new("Model")
	model.Name = "Perk_" .. id
	local base = spot.CFrame * CFrame.new(0, 0, -1.7)
	local function part(name, cf, size, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local dark = perk.Color:Lerp(Color3.new(0, 0, 0), 0.55)
	local body = part("Body", base * CFrame.new(0, 3.6, 0), Vector3.new(3.8, 7.2, 3), dark, Enum.Material.Metal)
	local panel = part("Panel", base * CFrame.new(0, 4.4, -1.52), Vector3.new(3, 3.2, 0.1), perk.Color:Lerp(Color3.new(), 0.7), Enum.Material.Neon)
	panel.CanCollide = false
	local sign = part("Sign", base * CFrame.new(0, 6.7, -1.52), Vector3.new(3.4, 0.6, 0.12), perk.Color:Lerp(Color3.new(), 0.7), Enum.Material.Neon)
	sign.CanCollide = false
	local slot = part("Slot", base * CFrame.new(0, 1.6, -1.52), Vector3.new(1.4, 0.9, 0.1), Color3.fromRGB(16, 16, 18))
	slot.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = perk.Color
	light.Brightness = 0
	light.Range = 14
	light.Parent = panel
	local prompt = Util.Prompt(body, "Needs Power", perk.Name, PERKS.HoldTime, 7)
	prompt:SetAttribute("Perk", id)
	prompt:SetAttribute("Price", perk.Cost)
	prompt:SetAttribute("SoloPrice", perk.SoloCost)
	prompt.Triggered:Connect(function(player)
		buy(player, id)
	end)
	model.Parent = parent
	return { Id = id, Panel = panel, Sign = sign, Light = light, Prompt = prompt, Color = perk.Color }
end

local function setLamps(on: boolean)
	local s = if on then Config.House.Lamps.On else Config.House.Lamps.Off
	for _, lamp in lamps do
		lamp.Light.Color = s.Color
		lamp.Light.Brightness = s.Brightness
		lamp.Light.Range = s.Range
		lamp.Part.Color = s.Color
	end
end

function Perks.TurnOnPower()
	if workspace:GetAttribute("Power") then
		return
	end
	workspace:SetAttribute("Power", true)
	setLamps(true)
	for _, m in machines do
		m.Panel.Color = m.Color
		m.Sign.Color = m.Color
		TweenService:Create(m.Light, TweenInfo.new(1.5), { Brightness = 1.3 }):Play()
		m.Prompt.ActionText = "Buy  (" .. PERKS.List[m.Id].Cost .. ")"
	end
	Net.Get("Hud"):FireAllClients("Notice", "THE POWER IS ON")
	Perks.PowerOn:Fire()
end

function Perks.Setup(run, maid)
	local house = run.House
	machines = {}
	lamps = house.Lamps
	workspace:SetAttribute("Power", false)
	setLamps(false)
	local folder = Instance.new("Folder")
	folder.Name = "Perks"
	folder.Parent = house.Model
	maid:Add(folder)
	local spots = Util.Shuffle(table.clone(house.Spots.Perk))
	for i, id in PERKS.Order do
		if spots[i] then
			table.insert(machines, buildMachine(spots[i], id, folder))
		else
			warn("Endless: no Perk spot left for", id)
		end
	end
	-- The switch: a lever box on the wall.
	local powerSpots = house.Spots.Power
	if #powerSpots > 0 then
		local spot = powerSpots[math.random(#powerSpots)]
		local box = Instance.new("Part")
		box.Name = "PowerSwitch"
		box.Anchored = true
		box.Size = Vector3.new(2.4, 3.2, 0.8)
		box.CFrame = spot.CFrame * CFrame.new(0, 5, -0.45)
		box.Color = Color3.fromRGB(70, 74, 64)
		box.Material = Enum.Material.CorrodedMetal
		box.Parent = folder
		local lever = Instance.new("Part")
		lever.Name = "Lever"
		lever.Anchored = true
		lever.CanCollide = false
		lever.Size = Vector3.new(0.3, 1.6, 0.3)
		lever.CFrame = box.CFrame * CFrame.new(0, 0.3, -0.6) * CFrame.Angles(math.rad(-35), 0, 0)
		lever.Color = Color3.fromRGB(160, 40, 30)
		lever.Material = Enum.Material.Metal
		lever.Parent = folder
		local prompt = Util.Prompt(box, "Turn On", "Power", Config.Power.HoldTime, 7)
		prompt.Triggered:Connect(function(player)
			if Survivors.IsStanding(player) then
				prompt:Destroy()
				TweenService:Create(lever, TweenInfo.new(0.3), { CFrame = box.CFrame * CFrame.new(0, -0.3, -0.6) * CFrame.Angles(math.rad(35), 0, 0) }):Play()
				Sfx.Play("World/DoorCreak", { Position = box.Position, Speed = 0.6 })
				Perks.TurnOnPower()
			end
		end)
	end
	if RunService:IsStudio() and workspace:GetAttribute("EndlessPower") then
		Perks.TurnOnPower()
	end
	-- Going down costs every perk (Call of Duty).
	maid:Add(Survivors.Downed:Connect(function(player)
		Perks.LoseAll(player)
	end))
end

return Perks
