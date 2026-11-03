-- Gun ascension (Mortuus' altar, Call of Duty's Pack-a-Punch; Config.Altar). A stone altar on one
-- of the House's Altar spots, drawn every run, dark until the power is on. Hold the gun you want to
-- ascend and hold the prompt: you pay Cost x Growth ^ (times it has ascended), the altar takes the
-- gun, and three boosts rise round it for you alone (Choices, For = you). Take one (within
-- ChoiceTime, or the first is taken for you) and the gun comes back into the same slot with that
-- boost added (the tool's Boosts), a full load and a brighter tint. One gun on the altar at a time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Endless.Config)
local Weapons = require(ReplicatedStorage.Endless.Weapons)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)
local Choices = require(ServerStorage.Endless.Choices)
local Perks = require(ServerStorage.Endless.Perks)

local ALTAR = Config.Altar

local Altar = {}

local function notice(player, text)
	Net.Get("Hud"):FireClient(player, "Notice", text)
end

function Altar.Setup(run, maid)
	local house = run.House
	local spots = house.Spots.Altar
	if #spots == 0 then
		return
	end
	local spot = spots[math.random(#spots)]
	local model = Instance.new("Model")
	model.Name = "Altar"
	local base = spot.CFrame * CFrame.new(0, 0, -2.2)
	local function part(name, cf, size, color, material, shape)
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
		p.Parent = model
		return p
	end
	local stone = Color3.fromRGB(92, 90, 88)
	part("Base", base * CFrame.new(0, 0.6, 0), Vector3.new(6, 1.2, 4), stone, Enum.Material.Slate)
	local block = part("Block", base * CFrame.new(0, 2.2, 0), Vector3.new(4.6, 2, 3), stone, Enum.Material.Slate)
	part("Top", base * CFrame.new(0, 3.35, 0), Vector3.new(5.2, 0.3, 3.4), Color3.fromRGB(70, 68, 66), Enum.Material.Slate)
	local rune = part("Rune", base * CFrame.new(0, 2.2, -1.52), Vector3.new(3, 1.2, 0.08), Color3.fromRGB(40, 30, 50), Enum.Material.Neon)
	rune.CanCollide = false
	local circle = part("Circle", base * CFrame.new(0, 0.04, -3.2) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.06, 7, 7), Color3.fromRGB(40, 30, 50), Enum.Material.Neon, Enum.PartType.Cylinder)
	circle.CanCollide = false
	circle.CanQuery = false
	circle.Transparency = 0.6
	for _, x in { -2.2, 2.2 } do
		part("Candle", base * CFrame.new(x, 3.9, 0.8), Vector3.new(0.4, 0.9, 0.4), Color3.fromRGB(220, 210, 186))
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(180, 120, 255)
	light.Brightness = 0
	light.Range = 18
	light.Parent = rune
	local prompt = Util.Prompt(block, "Ascend", "Gun Ascension", ALTAR.HoldTime, 8)
	prompt:SetAttribute("Altar", true)
	model.Parent = house.Model
	maid:Add(model)

	local function wake()
		rune.Color = Color3.fromRGB(180, 120, 255)
		circle.Color = Color3.fromRGB(180, 120, 255)
		TweenService:Create(light, TweenInfo.new(1.5), { Brightness = 1.6 }):Play()
	end
	if workspace:GetAttribute("Power") then
		wake()
	end
	maid:Add(Perks.PowerOn:Connect(wake))

	local busy = false
	local offer = nil
	maid:Add(function()
		if offer then
			offer:Clear()
		end
	end)

	prompt.Triggered:Connect(function(player)
		if busy or not Survivors.IsStanding(player) then
			return
		end
		if workspace:GetAttribute("Power") ~= true then
			notice(player, "THE ALTAR NEEDS POWER")
			return
		end
		local tool = Arsenal.Held(player)
		if not tool then
			notice(player, "HOLD THE GUN YOU WANT TO ASCEND")
			return
		end
		local level = tool:GetAttribute("Level") or 0
		if level >= ALTAR.MaxLevel then
			notice(player, "IT CAN'T GROW ANY STRONGER")
			return
		end
		if not Economy.Spend(player, Weapons.AscendCost(level)) then
			return
		end
		busy = true
		local id, boosts, slot = tool:GetAttribute("Weapon"), tool:GetAttribute("Boosts") or "", tool:GetAttribute("Slot")
		tool:Destroy()
		Sfx.Play("Night/Stinger", { Position = block.Position })
		-- Three different boosts, round the front of the altar.
		local ids = {}
		for b in ALTAR.Boosts do
			table.insert(ids, b)
		end
		table.sort(ids)
		Util.Shuffle(ids)
		local options = {}
		for i = 1, 3 do
			local boost = ALTAR.Boosts[ids[i]]
			table.insert(options, { Id = ids[i], Name = boost.Name, Text = boost.Text, Color = boost.Color })
		end
		local front = base * CFrame.new(0, 0, -4.2)
		local points = {
			(front * CFrame.new(-3.2, 0, 0.6)).Position,
			front.Position,
			(front * CFrame.new(3.2, 0, 0.6)).Position,
		}
		local done = false
		local function finish(option)
			if done then
				return
			end
			done = true
			offer = nil
			local newBoosts = if boosts == "" then option.Id else boosts .. "," .. option.Id
			if player.Parent and Survivors.InRun(player) then
				-- Bought the same gun again while this one was on the altar: the ascended one replaces it.
				local dup = Arsenal.Find(player, id)
				if dup then
					slot = dup:GetAttribute("Slot") or slot
					dup:Destroy()
				end
				local given = Arsenal.Give(player, id, newBoosts, slot)
				if given then
					notice(player, string.upper(Config.Weapons[id].Name) .. "  \u{2726}" .. (level + 1) .. "  \u{00B7}  " .. option.Text)
				end
			end
			busy = false
		end
		offer = Choices.Offer({
			Points = points,
			Options = options,
			For = player,
			Group = "Altar",
			Hold = 0.4,
			OnPick = function(_, option)
				finish(option)
				return true
			end,
			Expires = ALTAR.ChoiceTime,
			OnExpire = function()
				finish(options[1])
			end,
		})
		notice(player, "CHOOSE HOW IT GROWS")
	end)
end

return Altar
