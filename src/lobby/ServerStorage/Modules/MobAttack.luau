-- Mob melee: stop, raise an arm, swing (Call of Duty Zombies' swipe). The server decides
-- whether a swing lands and hurts the player through PlayerHealth; every client poses the
-- mob's arms from Remotes.MobAttack (MobPose):
--   "Windup" (model, duration, style)  "Swing" (model, duration, style)  "Cancel" (model)
-- style: "Right" / "Left" (that arm swipes), "Bite" (no arms left: a lunge with the head).
-- A stagger during the windup (MobReactions sets StaggerUntil on every hit) breaks the
-- swing off, so shooting a zombie in your face saves you. Numbers: Mobs.<type>.Attack.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local PlayerHealth = require(ServerStorage.Modules.PlayerHealth)
local Remotes = ReplicatedStorage.Remotes
local Players = game:GetService("Players")

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.CollisionGroup = "Characters"

-- The mob turns to follow its target for this share of the windup, then commits, so a
-- late sidestep makes it miss.
local TRACK_SHARE = 0.6

local MobAttack = {}

local readyAt = setmetatable({}, { __mode = "k" })

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function armAttached(model, side)
	local upper = model:FindFirstChild(side .. "UpperArm")
	local joint = upper and upper:FindFirstChild(side .. "Shoulder")
	return joint ~= nil and joint:IsA("Motor6D") and joint.Enabled and joint.Part0 ~= nil
end

local function pickStyle(model)
	local arms = {}
	for _, side in { "Right", "Left" } do
		if armAttached(model, side) then
			table.insert(arms, side)
		end
	end
	if #arms == 0 then
		return "Bite"
	end
	return arms[math.random(#arms)]
end

local function staggered(model)
	return (model:GetAttribute("StaggerUntil") or 0) > os.clock()
end

local function gone(model, humanoid)
	return not model.Parent or humanoid.Health <= 0 or model:GetAttribute("Dead") == true
end

local function face(model, pos)
	local root = model.PrimaryPart
	local to = flat(pos - root.Position)
	if to.Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + to)
	end
end

-- Whether nothing solid stands between the mob and a target part (fences, walls,
-- barricades); mobs, characters and loose debris don't count.
function MobAttack.Sees(model, target)
	local root = model.PrimaryPart
	if not root or not target then
		return false
	end
	local ignore = { model.Parent }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	sightParams.FilterDescendantsInstances = ignore
	local from = root.Position + Vector3.new(0, 0.5, 0)
	local to = target.Position - from
	return workspace:Raycast(from, to, sightParams) == nil
end

-- Whether the mob may start a swing now (cooled down and not staggered).
function MobAttack.Ready(model)
	return os.clock() >= (readyAt[model] or 0) and not staggered(model)
end

-- One full swipe at a player, or at a WAR squad NPC (its model). Yields for the windup, swing and
-- recovery.
function MobAttack.Swing(model, humanoid, player, cfg)
	local attack = cfg.Attack
	local root = model.PrimaryPart
	local character = if player:IsA("Player") then player.Character else player
	local target = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not target then
		return
	end
	local style = pickStyle(model)
	humanoid:MoveTo(root.Position)
	face(model, target.Position)
	Remotes.MobAttack:FireAllClients(model, "Windup", attack.Windup, style)

	local t = 0
	while t < attack.Windup do
		t += task.wait(0.05)
		if gone(model, humanoid) or staggered(model) then
			Remotes.MobAttack:FireAllClients(model, "Cancel")
			readyAt[model] = os.clock() + attack.Cooldown
			return
		end
		if t < attack.Windup * TRACK_SHARE and target.Parent then
			face(model, target.Position)
		end
	end

	Remotes.MobAttack:FireAllClients(model, "Swing", attack.Swing, style)
	SoundKit.Play(cfg.Sounds .. "/Swing", { Position = root.Position })
	task.wait(attack.Swing)

	-- Someone who got into a dumpster mid-swing is out of reach (EvadeServer Inside).
	if not gone(model, humanoid) and target.Parent and not character:GetAttribute("Inside") then
		local crawling = model:GetAttribute("Crawling") == true
		local reach = if crawling then attack.CrawlRange + 1.5 else attack.Reach
		local to = target.Position - root.Position
		local flatTo = flat(to)
		local facing = flat(root.CFrame.LookVector)
		local inArc = flatTo.Magnitude < 0.5
			or facing.Unit:Dot(flatTo.Unit) >= math.cos(math.rad(attack.Arc / 2))
		if to.Magnitude <= reach and inArc and math.abs(to.Y) < 5 and MobAttack.Sees(model, target) then
			-- DamageScale: a per-mob multiplier a mode may set (only Endless does: its round pressure, EndlessRun)
			local damage = attack.Damage * (model:GetAttribute("DamageScale") or 1)
			if style == "Bite" then
				damage *= attack.Bite
			else
				damage *= attack.ArmLost ^ math.min(model:GetAttribute("ArmsLost") or 0, 1)
			end
			if crawling then
				damage *= attack.Crawl
			end
			if player:IsA("Player") then
				PlayerHealth.Damage(player, damage, root.Position)
			else
				local soldier = require(script.Parent.Soldier).FromModel(character)
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if soldier then
					soldier:Hurt(damage, root.Position)
				elseif humanoid and character:GetAttribute("Civilian") then
					-- Defend's survivors (MatchServer) take the swipe like a player would.
					humanoid:TakeDamage(damage)
				end
			end
		end
	end

	task.wait(attack.Recover)
	readyAt[model] = os.clock() + attack.Cooldown
end

-- A claw at something in the way (a fence or barricade boards): a quick swipe, no damage.
-- Yields for the windup and swing.
function MobAttack.Claw(model, humanoid, targetPos, cfg)
	local attack = cfg.Attack
	local root = model.PrimaryPart
	if not root then
		return
	end
	local style = pickStyle(model)
	humanoid:MoveTo(root.Position)
	face(model, targetPos)
	Remotes.MobAttack:FireAllClients(model, "Windup", 0.3, style)
	task.wait(0.3)
	if gone(model, humanoid) then
		return
	end
	Remotes.MobAttack:FireAllClients(model, "Swing", attack.Swing, style)
	SoundKit.Play(cfg.Sounds .. "/Swing", { Position = root.Position })
	task.wait(attack.Swing)
end

-- Feeding on a body during a devour: short claws, no damage (the devour timer kills).
function MobAttack.Maul(model, humanoid, targetPos, cfg)
	local attack = cfg.Attack
	local root = model.PrimaryPart
	if not root then
		return
	end
	local style = pickStyle(model)
	humanoid:MoveTo(root.Position)
	face(model, targetPos)
	Remotes.MobAttack:FireAllClients(model, "Windup", 0.18, style)
	task.wait(0.18)
	Remotes.MobAttack:FireAllClients(model, "Swing", attack.Swing, style)
	local gap = attack.MaulGap
	task.wait(attack.Swing + gap.Min + math.random() * (gap.Max - gap.Min))
end

return MobAttack
