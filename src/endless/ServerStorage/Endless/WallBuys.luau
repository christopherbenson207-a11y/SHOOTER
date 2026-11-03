-- Guns drawn on the walls (Call of Duty Zombies' wall buys). Each Wall spot of the House shows a gun
-- in chalk: the layout's Weapon, or one drawn from Config.WallBuys.Pool each run. Hold the prompt
-- to buy the gun for its Price, or, carrying it already, its ammo for AmmoShare of the price
-- (Config.Arsenal.AscendedAmmo once it has been through the altar). Prompt attributes Weapon,
-- Price and AmmoPrice let each client word the prompt for its own player (EndlessFx).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Weapons = require(ReplicatedStorage.Endless.Weapons)
local GunModel = require(ReplicatedStorage.Endless.GunModel)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)
local Arsenal = require(ServerStorage.Endless.Arsenal)

local WallBuys = {}

function WallBuys.Setup(run, maid)
	local house = run.House
	local folder = Instance.new("Folder")
	folder.Name = "WallBuys"
	folder.Parent = house.Model
	maid:Add(folder)
	local pool = Util.Shuffle(table.clone(Config.WallBuys.Pool))
	local nextFromPool = 0
	for _, spot in house.Spots.Wall do
		local id = spot.Weapon
		if not id or not Config.Weapons[id] then
			nextFromPool = nextFromPool % #pool + 1
			id = pool[nextFromPool]
		end
		local cfg = Config.Weapons[id]
		local price = cfg.Price or 1000
		local ammoPrice = math.floor(price * Config.Arsenal.AmmoShare / 10 + 0.5) * 10
		-- The chalk drawing, flat on the wall, on a dark board.
		local wallCf = spot.CFrame * CFrame.new(0, 5.2, 0)
		local board = Instance.new("Part")
		board.Name = "ChalkBoard"
		board.Anchored = true
		board.CanCollide = false
		board.CanQuery = false
		board.Size = Vector3.new(5.6, 2.6, 0.1)
		board.CFrame = wallCf * CFrame.new(0, 0, -0.06)
		board.Color = Color3.fromRGB(30, 32, 30)
		board.Material = Enum.Material.Slate
		board.Parent = folder
		local drawing = GunModel.Build(id, { Anchored = true, Chalk = true, CFrame = wallCf * CFrame.new(0.8, -0.1, -0.4) * CFrame.Angles(0, math.rad(90), 0) })
		drawing.Parent = folder
		local prompt = Util.Prompt(board, "Buy " .. cfg.Name .. "  (" .. price .. ")", "", Config.WallBuys.HoldTime, 7)
		prompt:SetAttribute("Weapon", id)
		prompt:SetAttribute("Price", price)
		prompt:SetAttribute("AmmoPrice", ammoPrice)
		prompt:SetAttribute("AscendedAmmo", Config.Arsenal.AscendedAmmo)
		prompt.Triggered:Connect(function(player)
			if not Survivors.IsStanding(player) then
				return
			end
			local tool = Arsenal.Find(player, id)
			if tool then
				local stats = Weapons.ForTool(tool, player)
				local full = (tool:GetAttribute("Reserve") or 0) >= stats.Reserve and (tool:GetAttribute("Mag") or 0) >= stats.Mag
				if full then
					return
				end
				local cost = if (tool:GetAttribute("Level") or 0) > 0 then Config.Arsenal.AscendedAmmo else ammoPrice
				if Economy.Spend(player, cost) then
					Arsenal.Fill(player, tool)
					Sfx.Play("Pickup/Ammo", { Position = board.Position })
				end
			elseif Economy.Spend(player, price) then
				Arsenal.Give(player, id)
				Sfx.Play("Pickup/Ammo", { Position = board.Position })
			end
		end)
	end
end

return WallBuys
