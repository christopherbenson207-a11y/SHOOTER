-- Players' lives in an Endless run (Call of Duty Zombies' rules; numbers: Config.Player).
-- Characters only load when the run says so (Players.CharacterAutoLoads is off): Spawn puts a
-- player in the house. Zombie swipes come through Damage; at no health you go down instead of
-- dying (character attribute Downed): you crawl, can't shoot, lose your perks (Survivors.Downed
-- fires, Perks clears them) and a share of your points. A teammate holds the Revive prompt on you
-- for ReviveTime (half with Lazarus Draught, set on their own client) to get you up. After BleedOut
-- you die and wait for the next intermission. Playing alone, Lazarus Draught (or a Second Wind
-- relic) gets you up by yourself after SelfReviveTime.
-- Health comes back RegenDelay seconds after the last hit (sooner with Fast Mend).
-- Player attribute InRun: this player is part of the run (set when they first spawn into it).
-- Character attributes: Downed, BleedOutAt (server time), SelfRevive (getting up alone).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Endless.Config)
local Net = require(ReplicatedStorage.Endless.Net)
local Sfx = require(ReplicatedStorage.Endless.Sfx)
local Util = require(ServerStorage.Endless.Util)
local Economy = require(ServerStorage.Endless.Economy)

local PLAYER = Config.Player
local DOWNED = PLAYER.Downed

local Survivors = {}
Survivors.Downed = Util.Signal() -- (player)
Survivors.Revived = Util.Signal() -- (player)
Survivors.Died = Util.Signal() -- (player)

local state = {} -- [player] = { LastHit, SpawnedAt, Prompt, Highlight, Loading, DownId }

local function get(player)
	local st = state[player]
	if not st then
		st = { LastHit = 0, SpawnedAt = 0 }
		state[player] = st
	end
	return st
end

function Survivors.Parts(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, root
end

function Survivors.IsAlive(player: Player): boolean
	local _, humanoid, root = Survivors.Parts(player)
	return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

function Survivors.IsDowned(player: Player): boolean
	return Survivors.IsAlive(player) and player.Character:GetAttribute("Downed") == true
end

function Survivors.IsStanding(player: Player): boolean
	return Survivors.IsAlive(player) and not player.Character:GetAttribute("Downed")
end

function Survivors.InRun(player: Player): boolean
	return player:GetAttribute("InRun") == true
end

function Survivors.RunPlayers(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if Survivors.InRun(p) then
			table.insert(list, p)
		end
	end
	return list
end

function Survivors.StandingPlayers(): { Player }
	local list = {}
	for _, p in Survivors.RunPlayers() do
		if Survivors.IsStanding(p) then
			table.insert(list, p)
		end
	end
	return list
end

-- Whether the run goes on: someone is standing, down but sure to get up alone, or still loading in
-- (Spawn yields in LoadCharacter; a run must not end before its players have arrived).
function Survivors.AnyoneUp(): boolean
	for _, p in Survivors.RunPlayers() do
		local st = state[p]
		if (st and st.Loading) or Survivors.IsStanding(p) or (Survivors.IsDowned(p) and p.Character:GetAttribute("SelfRevive")) then
			return true
		end
	end
	return false
end

local function studioFlag(name)
	return RunService:IsStudio() and workspace:GetAttribute(name) == true
end

function Survivors.MaxHealthFor(player: Player): number
	local base = if player:GetAttribute("Perk_Bulwark") then Config.Perks.List.Bulwark.Health else PLAYER.MaxHealth
	return base + (player:GetAttribute("RelicHealth") or 0)
end

function Survivors.RefreshMaxHealth(player: Player)
	local _, humanoid = Survivors.Parts(player)
	if humanoid and humanoid.Health > 0 then
		local max = Survivors.MaxHealthFor(player)
		local gained = max - humanoid.MaxHealth
		humanoid.MaxHealth = max
		if gained > 0 and not player.Character:GetAttribute("Downed") then
			humanoid.Health = math.min(max, humanoid.Health + gained)
		end
	end
end

function Survivors.WalkSpeed(player: Player): number
	return PLAYER.WalkSpeed + (player:GetAttribute("RelicSpeed") or 0)
end

-- Loads a character for player standing at `at` (a floor point). Yields until it stands there.
function Survivors.Spawn(player: Player, at: Vector3)
	local st = get(player)
	player:SetAttribute("InRun", true)
	st.Loading = true
	-- With streaming on (a new place's default), get the house round the spot to the client first.
	if workspace.StreamingEnabled then
		pcall(player.RequestStreamAroundAsync, player, at, 10)
	end
	local loaded = pcall(player.LoadCharacter, player)
	local character = player.Character
	local humanoid = loaded and character and character:WaitForChild("Humanoid", 10)
	local root = loaded and character and character:WaitForChild("HumanoidRootPart", 10)
	st.Loading = nil
	if not humanoid or not root then
		return nil
	end
	character:PivotTo(CFrame.new(at + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	humanoid.MaxHealth = Survivors.MaxHealthFor(player)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = Survivors.WalkSpeed(player)
	humanoid.BreakJointsOnDeath = false
	st.SpawnedAt = os.clock()
	st.LastHit = 0
	humanoid.Died:Once(function()
		if st.Prompt then
			st.Prompt:Destroy()
			st.Prompt = nil
		end
		if st.Highlight then
			st.Highlight:Destroy()
			st.Highlight = nil
		end
		character:SetAttribute("Downed", nil)
		Survivors.Died:Fire(player)
	end)
	return character
end

function Survivors.Heal(player: Player, amount: number)
	local _, humanoid = Survivors.Parts(player)
	if humanoid and Survivors.IsStanding(player) then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

-- A zombie's swipe (or anything else that hurts a player).
function Survivors.Damage(player: Player, amount: number)
	if studioFlag("EndlessGod") or not Survivors.IsStanding(player) then
		return
	end
	local st = get(player)
	local now = os.clock()
	if now - st.SpawnedAt < PLAYER.SpawnGrace or now - st.LastHit < PLAYER.HitGrace then
		return
	end
	st.LastHit = now
	local armor = math.min(player:GetAttribute("RelicArmor") or 0, Config.Relics.Pool.LeadBelly.Cap)
	amount *= 1 - armor
	local _, humanoid, root = Survivors.Parts(player)
	Sfx.Play("Player/Hurt", { Position = root.Position })
	Net.Get("Hud"):FireClient(player, "Hurt")
	if humanoid.Health - amount <= 0.5 then
		Survivors.Down(player)
	else
		humanoid.Health -= amount
	end
end

function Survivors.Down(player: Player)
	local character, humanoid, root = Survivors.Parts(player)
	if not Survivors.IsStanding(player) then
		return
	end
	local st = get(player)
	-- This fall's number: the timers below only act on the fall that started them.
	st.DownId = (st.DownId or 0) + 1
	local downId = st.DownId
	-- Getting up alone: Lazarus Draught when alone, else a Second Wind relic.
	local selfRevive = false
	if #Survivors.RunPlayers() == 1 and player:GetAttribute("Perk_Lazarus") then
		selfRevive = true
	elseif (player:GetAttribute("RelicSelfRevives") or 0) > 0 then
		player:SetAttribute("RelicSelfRevives", player:GetAttribute("RelicSelfRevives") - 1)
		selfRevive = true
	end

	character:SetAttribute("Downed", true)
	character:SetAttribute("SelfRevive", selfRevive)
	character:SetAttribute("BleedOutAt", workspace:GetServerTimeNow() + DOWNED.BleedOut)
	humanoid.Health = 1
	humanoid.WalkSpeed = DOWNED.Speed
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:UnequipTools()
	Economy.Lose(player, DOWNED.PointsLost)
	Economy.Count(player, "Downs")
	Sfx.Play("Player/Down", { Position = root.Position })
	Net.Get("Hud"):FireAllClients("Down", player.DisplayName)
	Survivors.Downed:Fire(player)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(200, 30, 30)
	highlight.OutlineColor = Color3.fromRGB(255, 80, 70)
	highlight.FillTransparency = 0.75
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
	st.Highlight = highlight

	local prompt = Util.Prompt(root, "Revive", player.DisplayName, DOWNED.ReviveTime, DOWNED.ReviveRange)
	prompt.Name = "RevivePrompt"
	prompt:SetAttribute("For", player.UserId)
	prompt.Triggered:Connect(function(by)
		if by ~= player and Survivors.IsStanding(by) and Survivors.IsDowned(player) then
			Economy.Count(by, "Revives")
			Survivors.Revive(player)
		end
	end)
	st.Prompt = prompt

	if selfRevive then
		task.delay(DOWNED.SelfReviveTime, function()
			if st.DownId == downId and character.Parent and Survivors.IsDowned(player) then
				Survivors.Revive(player)
			end
		end)
	else
		task.delay(DOWNED.BleedOut, function()
			if st.DownId == downId and character.Parent and Survivors.IsDowned(player) then
				humanoid.Health = 0
			end
		end)
	end
end

function Survivors.Revive(player: Player)
	local character, humanoid, root = Survivors.Parts(player)
	if not Survivors.IsDowned(player) then
		return
	end
	local st = get(player)
	if st.Prompt then
		st.Prompt:Destroy()
		st.Prompt = nil
	end
	if st.Highlight then
		st.Highlight:Destroy()
		st.Highlight = nil
	end
	character:SetAttribute("Downed", nil)
	character:SetAttribute("SelfRevive", nil)
	character:SetAttribute("BleedOutAt", nil)
	humanoid.MaxHealth = Survivors.MaxHealthFor(player)
	humanoid.Health = humanoid.MaxHealth * DOWNED.ReviveHealth
	humanoid.WalkSpeed = Survivors.WalkSpeed(player)
	humanoid.JumpPower = 50
	humanoid.JumpHeight = 7.2
	st.SpawnedAt = os.clock() - PLAYER.SpawnGrace + 1.5 -- a breath before the next hit
	Sfx.Play("Player/GetUp", { Position = root.Position })
	Survivors.Revived:Fire(player)
end

-- Run start: forget last run's state (attributes from perks and relics are cleared by their owners).
function Survivors.Reset(player: Player)
	local st = get(player)
	st.LastHit, st.SpawnedAt = 0, 0
	player:SetAttribute("InRun", nil)
end

function Survivors.Start()
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, st in state do
			local _, humanoid = Survivors.Parts(player)
			if humanoid and Survivors.IsStanding(player) and humanoid.Health < humanoid.MaxHealth then
				local delay = PLAYER.RegenDelay * (1 - math.min(player:GetAttribute("RelicRegen") or 0, Config.Relics.Pool.FastMend.Cap))
				if now - st.LastHit >= delay then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + PLAYER.RegenRate * dt)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)
	-- Every character part in the Players collision group (window blockers stop players only).
	local function setGroup(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
	local function onCharacter(character)
		for _, d in character:GetDescendants() do
			setGroup(d)
		end
		character.DescendantAdded:Connect(setGroup)
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

return Survivors
