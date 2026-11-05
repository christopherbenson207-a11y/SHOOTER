local hasToken, spendToken -- revive tokens, defined below standUp's helpers
-- Player health, going down, revives and the devour. Everything that hurts a player calls
-- PlayerHealth.Damage; nothing else changes a player Humanoid's health.
-- Health works like Call of Duty Zombies (back to full after RegenDelay out of harm) and
-- going down like Left 4 Dead: at 0 you drop to the floor with the pistol and bleed out
-- unless a teammate holds the revive prompt on you or you spend a self-revive. Bleeding
-- out, or being down while nobody is left standing and no self-revive remains, ends in the
-- devour: nearby zombies close in and pile on, then you die.
-- State lives on the character as attributes so every client can draw it:
--   Downed, Devoured, SelfReviving, BeingRevived, Taken (bool), BleedOutAt (server time),
--   SelfRevives (count left; a new life starts with the player's SelfRevivesStart if set)
-- Zombies that join a devour carry DevourTarget (the player's UserId) and DevourSlot; the
-- mob AI walks them to the body. Only mobs with the "Hunts" attribute are called in.
-- Remotes: PlayerHit (server -> the hit player), SelfRevive (client -> server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Bandages = require(script.Parent.Bandages)
local Classes = require(ReplicatedStorage.Shared.Classes)
local Remotes = ReplicatedStorage.Remotes

local CFG = GameConfig.Player
local DOWN = CFG.Downed
local DEVOUR = CFG.Devour

-- Placeholder downed pose until a real animation exists: the body drops and pitches
-- forward onto the floor on the root joint (the camera drop is done by the client).
local DOWN_POSE = CFrame.new(0, -2.1, 0) * CFrame.Angles(math.rad(-80), 0, 0)
local DOWN_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local UP_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Being down this long before the devour can start, so the fall reads first.
local DOWN_BEAT = 0.8

local PlayerHealth = {}

-- A mode can change the rules (FrontServer, 6 Nov 2026): HitGrace (seconds between hits that land, else
-- GameConfig.Player.HitGrace) and NoDown (0 health is death, no downed state and no revive).
PlayerHealth.Rules = { HitGrace = nil :: number?, NoDown = false }

-- player -> per-life state
local states = {}

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function isUp(s)
	return s.Humanoid.Health > 0 and not s.Character:GetAttribute("Downed")
end

local function anyoneStanding()
	for _, s in states do
		if isUp(s) then
			return true
		end
	end
	return false
end

local function poseRoot(s, down)
	if s.RootJoint and s.RootJoint.Parent then
		TweenService:Create(s.RootJoint, if down then DOWN_TWEEN else UP_TWEEN, {
			C0 = if down then DOWN_POSE * s.BaseC0 else s.BaseC0,
		}):Play()
	end
end

local function releaseDevourers(player)
	for _, mob in CollectionService:GetTagged("Enemy") do
		if mob:GetAttribute("DevourTarget") == player.UserId then
			mob:SetAttribute("DevourTarget", nil)
			mob:SetAttribute("DevourSlot", nil)
		end
	end
end

local function goDown(s)
	local character, humanoid = s.Character, s.Humanoid
	humanoid.Health = 1
	character:SetAttribute("Downed", true)
	character:SetAttribute("BleedOutAt", workspace:GetServerTimeNow() + DOWN.BleedOut)
	s.DownAt = os.clock()
	s.GraceUntil = os.clock() + DOWN.DownGrace
	s.Jump = { humanoid.JumpPower, humanoid.JumpHeight }
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	poseRoot(s, true)
	s.Prompt.Enabled = true
	SoundKit.Play("Player/Down", { Position = s.Root.Position })
end

-- Getting up shoves the zombies standing over you back and staggers them so you get a
-- breath. No knock-down: a humanoid thrown into FallingDown here could fly off the map or
-- stay on its back for good.
local function shoveMobs(from)
	for _, mob in CollectionService:GetTagged("Enemy") do
		local humanoid = mob:FindFirstChildOfClass("Humanoid")
		local root = mob.PrimaryPart
		if humanoid and humanoid.Health > 0 and root and not root.Anchored then
			local away = flat(root.Position - from)
			if away.Magnitude <= DOWN.ShoveRadius then
				local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
				root.AssemblyLinearVelocity += dir * DOWN.ShoveSpeed
				mob:SetAttribute("StaggerUntil", os.clock() + 1.2)
			end
		end
	end
end

-- Revive tokens (4 Nov 2026): the profile's Tokens (bought in the lobby or won in crates). Used only by holding the
-- revive key while down with no self-revive left; one token per get-up.
local profileModule = nil
local function profile()
	if profileModule == nil then
		local m = script.Parent:FindFirstChild("Profile")
		local ok, mod = pcall(require, m)
		profileModule = if m and ok and type(mod) == "table" then mod else false
	end
	return profileModule or nil
end

function hasToken(player)
	return (tonumber(player:GetAttribute("Tokens")) or 0) > 0
end

function spendToken(player)
	local P = profile()
	if not (P and hasToken(player)) then
		return false
	end
	P.Count(player, "Tokens", -1)
	return true
end

local function standUp(s)
	local character, humanoid = s.Character, s.Humanoid
	character:SetAttribute("Downed", false)
	character:SetAttribute("BleedOutAt", nil)
	character:SetAttribute("SelfReviving", false)
	character:SetAttribute("BeingRevived", false)
	s.SelfReviveStart = nil
	humanoid.Health = DOWN.ReviveHealth
	if s.Jump then
		humanoid.JumpPower, humanoid.JumpHeight = s.Jump[1], s.Jump[2]
	end
	poseRoot(s, false)
	s.Prompt.Enabled = false
	local now = os.clock()
	s.GraceUntil = now + DOWN.GetUpGrace
	s.LastHit = now
	shoveMobs(s.Root.Position)
	SoundKit.Play("Player/GetUp", { Position = s.Root.Position })
end

-- The zombies nearby close in on the body and pile on; the player dies when it ends.
local function devour(player, s)
	local character, humanoid = s.Character, s.Humanoid
	if character:GetAttribute("Devoured") then
		return
	end
	character:SetAttribute("Devoured", true)
	character:SetAttribute("SelfReviving", false)
	character:SetAttribute("BeingRevived", false)
	s.SelfReviveStart = nil
	s.Prompt.Enabled = false

	local near = {}
	for _, mob in CollectionService:GetTagged("Enemy") do
		local h = mob:FindFirstChildOfClass("Humanoid")
		local root = mob.PrimaryPart
		if mob:GetAttribute("Hunts") and not mob:GetAttribute("DevourTarget") and h and h.Health > 0 and root then
			local d = (root.Position - s.Root.Position).Magnitude
			if d <= DEVOUR.Radius then
				table.insert(near, { Mob = mob, Distance = d })
			end
		end
	end
	table.sort(near, function(a, b)
		return a.Distance < b.Distance
	end)
	for i = 1, math.min(DEVOUR.Count, #near) do
		near[i].Mob:SetAttribute("DevourSlot", i)
		near[i].Mob:SetAttribute("DevourTarget", player.UserId)
	end

	SoundKit.Play("Player/Devour", { Parent = s.Root })
	task.delay(DEVOUR.Time, function()
		if s.Character == character and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)
end

-- Public -----------------------------------------------------------------------------

-- Nothing hurts the player for the next `seconds` (a cutscene).
function PlayerHealth.Protect(player, seconds)
	local s = states[player]
	if s then
		s.GraceUntil = math.max(s.GraceUntil, os.clock() + seconds)
	end
end

-- Hurts a player (fromPos: where the hit came from; kind: nil for a zombie's claws, "Fall"
-- for a hard landing, which gets its own sound and screen effect). While down, a hit takes
-- bleed-out time instead. Returns whether it landed.
function PlayerHealth.Damage(player, amount, fromPos, kind)
	local s = states[player]
	if not s or s.Humanoid.Health <= 0 or s.Character:GetAttribute("Devoured") then
		return false
	end
	local now = os.clock()
	if now < s.GraceUntil then
		return false
	end
	s.GraceUntil = now + (PlayerHealth.Rules.HitGrace or CFG.HitGrace)
	s.LastHit = now
	-- Lead Belly (an Endless relic) takes a share off every hit.
	amount *= 1 - math.min(0.6, player:GetAttribute("RelicArmor") or 0)
	local character = s.Character
	if character:GetAttribute("Downed") then
		character:SetAttribute("BleedOutAt", (character:GetAttribute("BleedOutAt") or 0) - DOWN.HitCost)
	else
		local health = s.Humanoid.Health - amount
		if health <= 0 and PlayerHealth.Rules.NoDown then
			s.Prompt.Enabled = false
			s.Humanoid.Health = 0
		elseif health <= 0 then
			goDown(s)
		else
			s.Humanoid.Health = health
		end
	end
	Bandages.RecordWound(character, fromPos, if character:GetAttribute("Downed") then 0 else amount)
	local head = character:FindFirstChild("Head") or s.Root
	SoundKit.Play(if kind == "Fall" then "Player/Fall" elseif kind == "Bullet" then "Common/ImpactFlesh" else "Player/Claw", { Position = head.Position })
	SoundKit.Play("Player/Hurt", { Position = head.Position })
	Remotes.PlayerHit:FireClient(player, fromPos, amount, character:GetAttribute("Downed") == true, kind)
	return true
end

function PlayerHealth.IsDowned(player)
	local s = states[player]
	return s ~= nil and s.Character:GetAttribute("Downed") == true
end

-- Takes a player out at once, the way the Beacon does once it has seen you: no going down
-- and no revive. The character carries Taken. Returns whether it happened.
function PlayerHealth.Take(player)
	local s = states[player]
	if not s or s.Humanoid.Health <= 0 then
		return false
	end
	s.Character:SetAttribute("Taken", true)
	s.Prompt.Enabled = false
	s.Humanoid.Health = 0
	return true
end

-- Setup ------------------------------------------------------------------------------

local function rootJoint(character, root)
	for _, j in character:GetDescendants() do
		if j:IsA("Motor6D") and j.Part0 == root then
			return j
		end
	end
	return nil
end

local function onCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")
	if player.Character ~= character then
		return
	end
	-- Endless relics (ServerStorage.Modules.Relics): Thick Skin adds RelicHealth to every life.
	humanoid.MaxHealth = CFG.MaxHealth + (player:GetAttribute("RelicHealth") or 0)
	humanoid.Health = humanoid.MaxHealth
	-- The body stays whole under the pile.
	humanoid.BreakJointsOnDeath = false
	character:SetAttribute("Downed", false)
	character:SetAttribute("Devoured", false)
	-- MatchServer can give a run more (SelfRevivesStart on the player: playing alone in nights).
	character:SetAttribute("SelfRevives", player:GetAttribute("SelfRevivesStart") or DOWN.SelfRevives)

	local joint = rootJoint(character, root)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Revive"
	prompt.ActionText = "Revive"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = DOWN.ReviveTime
	prompt.MaxActivationDistance = DOWN.ReviveRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonB
	prompt.Enabled = false
	prompt.Parent = root

	local s = {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		RootJoint = joint,
		BaseC0 = if joint then joint.C0 else CFrame.identity,
		Prompt = prompt,
		LastHit = 0,
		GraceUntil = os.clock() + CFG.SpawnGrace,
		DownAt = 0,
		SelfReviveStart = nil,
		Jump = nil,
	}
	states[player] = s

	prompt.PromptButtonHoldBegan:Connect(function(reviver)
		if reviver ~= player then
			character:SetAttribute("BeingRevived", true)
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(reviver)
		if reviver ~= player then
			character:SetAttribute("BeingRevived", false)
		end
	end)
	prompt.Triggered:Connect(function(reviver)
		local rs = states[reviver]
		if reviver == player or not rs or not isUp(rs) then
			return
		end
		if not character:GetAttribute("Downed") or character:GetAttribute("Devoured") then
			return
		end
		if (rs.Root.Position - root.Position).Magnitude > DOWN.ReviveRange + 3 then
			return
		end
		standUp(s)
	end)

	humanoid.Died:Once(function()
		releaseDevourers(player)
		prompt.Enabled = false
		if states[player] == s then
			states[player] = nil
		end
	end)
end

local function step(dt)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local standing = anyoneStanding()
	for player, s in states do
		local character, humanoid = s.Character, s.Humanoid
		if humanoid.Health <= 0 or character:GetAttribute("Devoured") then
			continue
		end
		if character:GetAttribute("Downed") then
			local selfRevives = character:GetAttribute("SelfRevives") or 0
			if s.SelfReviveStart and now - s.SelfReviveStart >= DOWN.SelfReviveTime * Classes.Perk(player, "SelfReviveTime") then
				if selfRevives > 0 then
					character:SetAttribute("SelfRevives", selfRevives - 1)
					standUp(s)
				elseif hasToken(player) and spendToken(player) then
					standUp(s)
				else
					s.SelfReviveStart = nil
					character:SetAttribute("SelfReviving", false)
				end
			elseif serverNow >= (character:GetAttribute("BleedOutAt") or 0) then
				devour(player, s)
			elseif not standing and selfRevives <= 0 and not hasToken(player) and now - s.DownAt >= DOWN_BEAT then
				-- Nobody is left to pick you up.
				devour(player, s)
			end
		else
			-- Open wounds hold some health back until they're bandaged (Bandages.Trauma).
			local ceiling = humanoid.MaxHealth - Bandages.Trauma(character)
			-- Fast Mend (an Endless relic) shortens the wait.
			local delay = CFG.RegenDelay * (1 - math.min(0.75, player:GetAttribute("RelicRegen") or 0))
			if humanoid.Health < ceiling and now - s.LastHit >= delay then
				humanoid.Health = math.min(ceiling, humanoid.Health + CFG.RegenRate * dt)
			end
		end
	end
end

function PlayerHealth.Start()
	Players.RespawnTime = CFG.RespawnTime
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		releaseDevourers(player)
		states[player] = nil
	end)

	Remotes.SelfRevive.OnServerEvent:Connect(function(player, command)
		local s = states[player]
		if not s then
			return
		end
		local character = s.Character
		if command == "Start" then
			if character:GetAttribute("Downed") and not character:GetAttribute("Devoured") and ((character:GetAttribute("SelfRevives") or 0) > 0 or hasToken(player)) then
				s.SelfReviveStart = os.clock()
				character:SetAttribute("SelfReviving", true)
			end
		else
			s.SelfReviveStart = nil
			character:SetAttribute("SelfReviving", false)
		end
	end)

	RunService.Heartbeat:Connect(step)
end

return PlayerHealth
