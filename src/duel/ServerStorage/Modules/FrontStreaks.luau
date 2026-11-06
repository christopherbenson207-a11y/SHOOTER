-- FRONTLINE's killstreaks (Shared.Front.Streaks, FRONTLINE-PLAN.md section 3). Kills in one life earn them: SPOTTER at 3,
-- MORTARS at 5, ARMOUR at 8. Each one earned waits until it is used or the player dies; the player attribute
-- StreakReady names the best one waiting, and one key (Controls "Streak", FrontClient) calls it through
-- Remotes.FrontStreak with the point the player is looking at.
--   SPOTTER: every foe within Radius of the caller is marked for the caller's side for Time seconds (model attribute
--     Spotted<Side> = the server time it ends; FrontClient outlines them).
--   MORTARS: Shells shells over Duration seconds round the point looked at (Emplacements.Barrage, WarDamage, kill
--     credit to the caller), if it is within Range.
--   ARMOUR: a tank for the caller's side from its spawn toward the flag (Modules.Tank: a satchel on its back deck
--     kills it), gone after Time seconds. One per side on the field.
--   FrontStreaks.Install(api): api = { Running = fn -> bool, Flag = fn -> Vector3?, Spawn = fn(side) -> CFrame,
--     Radio = fn(side, text), Notice = fn(player, text), Sound = fn(side, cue) }.
--   FrontStreaks.OnKill(player) / OnDeath(player) / Clear(): FrontServer's hooks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Front = require(ReplicatedStorage.Shared.Front)
local Emplacements = require(script.Parent.Emplacements)
local Tank = require(script.Parent.Tank)

local FrontStreaks = {}

local api = nil
local used = {} -- [player] = { [key] = true } this life
local lastCall = {} -- [player] = os.clock()
local tanks = {} -- [side] = tank

local function sideOf(player)
	return player:GetAttribute("Side") or "Ally"
end

local function alive(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

-- The best streak earned and not used this life, or nil.
local function best(player)
	local kills = player:GetAttribute("Streak") or 0
	local mine = used[player] or {}
	local pick = nil
	for _, s in Front.Streaks do
		if kills >= s.Kills and not mine[s.Key] then
			pick = s
		end
	end
	return pick
end

local function refresh(player)
	local s = best(player)
	local was = player:GetAttribute("StreakReady")
	player:SetAttribute("StreakReady", s and s.Key or nil)
	if s and was ~= s.Key and api then
		api.Notice(player, s.Name .. " READY")
		ReplicatedStorage.Remotes.Match:FireClient(player, "FrontSound", "StreakReady")
	end
end

function FrontStreaks.OnKill(player)
	refresh(player)
end

function FrontStreaks.OnDeath(player)
	used[player] = nil
	player:SetAttribute("StreakReady", nil)
end

function FrontStreaks.Clear()
	table.clear(used)
	for side, tank in tanks do
		if tank.Alive then
			tank:Remove()
		end
		tanks[side] = nil
	end
	for _, p in Players:GetPlayers() do
		p:SetAttribute("StreakReady", nil)
	end
end

-- Foes of side, as { Model, Position }: players of the other side and its bots.
local function foesOf(side)
	local list = {}
	for _, p in Players:GetPlayers() do
		local root = p:GetAttribute("InMatch") and sideOf(p) ~= side and alive(p) and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(list, { Model = p.Character, Position = root.Position })
		end
	end
	local folder = workspace:FindFirstChild(if side == "Ally" then "Hostiles" else "Squad")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and not m:GetAttribute("Dead") and m.PrimaryPart and m:GetAttribute("Side") ~= side then
				table.insert(list, { Model = m, Position = m.PrimaryPart.Position })
			end
		end
	end
	return list
end

local CALLS = {}

function CALLS.Spotter(player, s, _aim)
	local side = sideOf(player)
	local root = player.Character.HumanoidRootPart
	local untilAt = workspace:GetServerTimeNow() + s.Time
	local n = 0
	for _, f in foesOf(side) do
		if (f.Position - root.Position).Magnitude <= s.Radius then
			f.Model:SetAttribute("Spotted" .. side, untilAt)
			n += 1
		end
	end
	api.Radio(side, Front.Lines.Spotter)
	return true
end

function CALLS.Mortars(player, s, aim)
	local root = player.Character.HumanoidRootPart
	if typeof(aim) ~= "Vector3" or aim ~= aim or (aim - root.Position).Magnitude > s.Range then
		api.Notice(player, "OUT OF MORTAR RANGE")
		return false
	end
	local side = sideOf(player)
	Emplacements.Barrage(aim, s.Spread, s.Shells, side, {
		Player = player, Duration = s.Duration, BlastRadius = s.BlastRadius, Damage = s.Damage,
	})
	api.Radio(side, Front.Lines.Mortars)
	return true
end

function CALLS.Armour(player, s, _aim)
	local side = sideOf(player)
	local out = tanks[side]
	if out and out.Alive then
		api.Notice(player, "YOUR ARMOUR IS ALREADY OUT")
		return false
	end
	local flag = api.Flag()
	if not flag then
		return false
	end
	local at = api.Spawn(side).Position
	local ok, tank = pcall(Tank.Spawn, side, at, { Goal = flag, Health = s.Health, Stop = 18 })
	if not ok then
		warn("FrontStreaks: tank: " .. tostring(tank))
		return false
	end
	tanks[side] = tank
	task.delay(s.Time, function()
		if tanks[side] == tank then
			tanks[side] = nil
		end
		if tank.Alive then
			tank:Remove()
		end
	end)
	api.Radio(side, Front.Lines.Armour)
	return true
end

local function onCall(player, aim)
	local now = os.clock()
	if now - (lastCall[player] or 0) < 0.5 then
		return
	end
	lastCall[player] = now
	if not (api and api.Running() and player:GetAttribute("InMatch") and alive(player)) then
		return
	end
	local s = best(player)
	if not s or player:GetAttribute("StreakReady") ~= s.Key then
		return
	end
	local ok, done = pcall(CALLS[s.Key], player, s, aim)
	if not ok then
		warn("FrontStreaks: " .. s.Key .. ": " .. tostring(done))
		return
	end
	if done then
		used[player] = used[player] or {}
		used[player][s.Key] = true
		ReplicatedStorage.Remotes.Match:FireClient(player, "FrontSound", "StreakCall")
		refresh(player)
	end
end

function FrontStreaks.Install(hooks)
	api = hooks
	local remotes = ReplicatedStorage.Remotes
	local remote = remotes:FindFirstChild("FrontStreak")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "FrontStreak"
		remote.Parent = remotes
	end
	remote.OnServerEvent:Connect(onCall)
	Players.PlayerRemoving:Connect(function(p)
		used[p] = nil
		lastCall[p] = nil
	end)
end

return FrontStreaks
