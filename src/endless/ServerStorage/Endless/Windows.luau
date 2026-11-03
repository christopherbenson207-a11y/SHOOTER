-- Boarded windows (Call of Duty Zombies' barriers). Each window of the House has Config.Windows.Boards
-- boards on the outside; zombies tear them off one at a time (Rip) and climb in once none is left.
-- Inside, a player holds the Repair prompt: one hold nails every missing board back, a board at a
-- time, paying Config.Points.Repair a board up to RepairCap boards a round (Call of Duty's cap).
-- HAMMER AND NAILS (RepairAll) puts every board in the house back at once.
-- Window fields used here: Boards (parts with a Home attribute), RepairAt, Load (zombies on their
-- way to it), ClimbFreeAt (os.clock() when the next zombie may climb through).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Endless.Config)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)
local Survivors = require(ServerStorage.Endless.Survivors)

local Windows = {}

local house
local repairs = {} -- [player] = boards paid for this round

local function fx()
	return workspace:FindFirstChild("Fx") or workspace
end

function Windows.Torn(window): number
	local n = 0
	for _, b in window.Boards do
		if b:GetAttribute("Torn") then
			n += 1
		end
	end
	return n
end

function Windows.Broken(window): boolean
	return Windows.Torn(window) >= #window.Boards
end

-- One board off, thrown toward the zombie. False if there was none left.
function Windows.Rip(window, fromPos: Vector3): boolean
	for i = #window.Boards, 1, -1 do
		local board = window.Boards[i]
		if not board:GetAttribute("Torn") then
			board:SetAttribute("Torn", true)
			local loose = board:Clone()
			loose:SetAttribute("Torn", nil)
			loose.Anchored = false
			loose.CanCollide = true
			loose.CollisionGroup = "Corpses"
			loose.Parent = fx()
			local away = Util.Flat(fromPos - board.Position)
			away = if away.Magnitude > 0.1 then away.Unit else window.Normal
			loose.AssemblyLinearVelocity = away * (10 + math.random() * 8) + Vector3.new(0, 8, 0)
			loose.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12
			Debris:AddItem(loose, 8)
			board.Transparency = 1
			Sfx.Play("World/WoodBreak", { Position = board.Position, Volume = 0.7 })
			return true
		end
	end
	return false
end

local function nail(board)
	board:SetAttribute("Torn", nil)
	local home = board:GetAttribute("Home")
	board.CFrame = home * CFrame.new(0, 0, -0.6)
	board.Transparency = 0
	TweenService:Create(board, TweenInfo.new(0.1), { CFrame = home }):Play()
	Sfx.Play("World/PlankDrop", { Position = board.Position })
end

function Windows.RepairAll()
	for _, window in house.Windows do
		for _, b in window.Boards do
			if b:GetAttribute("Torn") then
				nail(b)
			end
		end
	end
end

function Windows.NewRound()
	table.clear(repairs)
end

function Windows.Setup(run, maid)
	house = run.House
	table.clear(repairs)
	for _, window in house.Windows do
		window.Load = 0
		window.ClimbFreeAt = 0
		local anchor = Instance.new("Part")
		anchor.Name = "RepairPoint"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Position = window.RepairAt
		anchor.Parent = house.Model
		local prompt = Util.Prompt(anchor, "Repair", "Window", Config.Windows.HoldTime, Config.Windows.Range)
		prompt.Enabled = false
		window.Prompt = prompt
		local repairing = false
		prompt.Triggered:Connect(function(player)
			if repairing or not Survivors.IsStanding(player) then
				return
			end
			repairing = true
			prompt.Enabled = false
			for _, b in window.Boards do
				if not Survivors.IsStanding(player) then
					break
				end
				if b:GetAttribute("Torn") then
					nail(b)
					local done = repairs[player] or 0
					if run.State == "Wave" and done < Config.Points.RepairCap then
						repairs[player] = done + 1
						Economy.Add(player, Config.Points.Repair)
					end
					task.wait(0.12)
				end
			end
			repairing = false
		end)
		maid:Add(task.spawn(function()
			while anchor.Parent do
				local torn = Windows.Torn(window)
				prompt.Enabled = torn > 0 and not repairing
				prompt.HoldDuration = Config.Windows.HoldTime + 0.15 * torn
				task.wait(0.25)
			end
		end))
	end
end

return Windows
