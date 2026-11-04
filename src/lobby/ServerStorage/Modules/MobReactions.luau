-- Hit reactions shared by every mob type: limb health and dismemberment, stagger,
-- knockback, hurt/idle/death sounds, and the kill: freeze, go limp (ragdoll), get thrown.
-- The instant visual kick, wounds and tearing are drawn on clients (MobImpact, Gore); this
-- module owns the physics and tells clients what happened through Remotes.MobFx:
--   "Hit"    every validated hit (the shooter's client already drew it and skips it)
--   "Loosen" a limb's joint gave way; it now hangs on a ball socket
--   "Sever"  a limb tore off; a spring holds it for Gore.TearHold while the flesh stretches
--   "Pop"    a head burst (sniper headshots, point-blank shotgun kills)
--   "Burst"  a point-blank shotgun kill burst the torso open
-- Mob numbers come from GameConfig.Mobs[model's "MobType"]; gun numbers from the gun's Feel.
-- GunServer calls Hit() for every validated hit; other systems listen on Events.EnemyHit.
-- EnemyHit:Fire(model, part, dealt, isHead, killed, player, pos, dir, ctx) where ctx carries GunName (a gun key,
-- or a Shared.Gear key for gear), Headshot, Killed and Elite (menu revamp, CONTRACTS section 6).
-- Elite mobs (Brutes, captains, bosses, heavies) carry the model attribute Elite = true (set on spawn and on the
-- first hit). A player's gun hits are multiplied by the Defend upgrade tier of that gun (player attribute Tiers,
-- JSON gun -> tier, GameConfig.Director.Tiers), and a mob marked by the Mark field item (attribute MarkedUntil)
-- takes Shared.Gear.Items.Mark.Bonus more. Stun(model, seconds) and Slow(model, mult, seconds) are used by
-- GearServer (Flashbang, Smoke).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local Remotes = ReplicatedStorage.Remotes
local EnemyHit = ServerStorage.Events.EnemyHit
local HttpService = game:GetService("HttpService")

-- Elite mobs. A mob type is elite when its GameConfig.Mobs entry says Elite = true, when its type is one of
-- these, or when the model carries Brute, Captain, Boss or Heavy.
local ELITE_TYPES = { Brute = true, Captain = true, Boss = true, Lamplighter = false }
local ELITE_FLAGS = { "Elite", "Brute", "Captain", "Boss", "Heavy" }

local function markElite(model, cfg)
	if model:GetAttribute("Elite") ~= nil then
		return model:GetAttribute("Elite") == true
	end
	local elite = (cfg and cfg.Elite == true) or ELITE_TYPES[model:GetAttribute("MobType") or ""] == true
	if not elite then
		for _, flag in ELITE_FLAGS do
			if model:GetAttribute(flag) then
				elite = true
				break
			end
		end
	end
	if not elite then
		local kind = model:GetAttribute("Kind") or model:GetAttribute("SoldierKind")
		elite = kind == "Heavy" or kind == "Brute" or kind == "Captain" or kind == "Boss"
	end
	if elite then
		model:SetAttribute("Elite", true)
	end
	return elite
end

-- The Defend upgrade tier multiplier of this player's gun (1 when not upgraded).
local function tierMult(player, gunName)
	if typeof(player) ~= "Instance" or type(gunName) ~= "string" then
		return 1
	end
	local raw = player:GetAttribute("Tiers")
	if type(raw) ~= "string" or raw == "" then
		return 1
	end
	local ok, tiers = pcall(HttpService.JSONDecode, HttpService, raw)
	local tier = ok and type(tiers) == "table" and tonumber(tiers[gunName]) or 1
	local list = GameConfig.Director and GameConfig.Director.Tiers
	local entry = list and list[math.clamp(math.floor(tier), 1, #list)]
	return entry and entry.Mult or 1
end

-- Class perks that act on hits (Shared.Classes.Perk): EliteDamage (Hunter), EliteStagger (Marksman headshots).
local classesModule = nil
local function perk(player, key)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return 1
	end
	if classesModule == nil then
		local ok, m = pcall(require, ReplicatedStorage.Shared:FindFirstChild("Classes"))
		classesModule = ok and type(m) == "table" and m.Perk and m or false
	end
	if not classesModule then
		return 1
	end
	local ok, v = pcall(classesModule.Perk, player, key)
	return ok and tonumber(v) or 1
end

local gearItems = nil
local function gearItem(key)
	if gearItems == nil then
		local ok, gear = pcall(require, ReplicatedStorage.Shared:FindFirstChild("Gear"))
		gearItems = ok and type(gear) == "table" and gear.Items or false
	end
	return gearItems and gearItems[key]
end

local CRAWL_DOWN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local CORPSE_FADE = TweenInfo.new(1)
-- Placeholder crawl: drop the torso and pitch it forward on the root joint. Tuned in the
-- R6 RootJoint's turned frame, then moved into root-part space so R15 crawls the same way.
-- Real mobs get a crawl animation instead.
local R6_ROOT = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local CRAWL_POSE = R6_ROOT * CFrame.new(0, -1.5, 0) * CFrame.Angles(math.rad(-70), 0, 0) * R6_ROOT:Inverse()
-- A loose limb swings in a cone around its hanging line, tipped away from the body so it
-- can swing far outward but only a little inward through the torso; it can roll a little
-- around its own length (degrees).
local LOOSE_SWING = 60
local LOOSE_TILT = 42
local LOOSE_TWIST = 35
-- A loose limb shot again swings this hard (studs/s per unit of gun Knockback).
local LOOSE_PUSH = 1.4
-- A dead body's joints become ball sockets this loose (degrees), so it folds as it flies.
local RAG_SWING = 55
local RAG_TWIST = 50

local MobReactions = {}

local states = setmetatable({}, { __mode = "k" })

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.zero
end

local function headOrRoot(model)
	local head = model:FindFirstChild("Head")
	return if head and head:IsDescendantOf(model) then head else model.PrimaryPart
end

local function gibFolder()
	local fx = workspace:FindFirstChild("Fx")
	local folder = fx:FindFirstChild("Gibs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Gibs"
		folder.Parent = fx
	end
	return folder
end

local function getConfig(model)
	return GameConfig.Mobs[model:GetAttribute("MobType") or ""]
end

local function getState(model, cfg, humanoid)
	local s = states[model]
	if s then
		return s
	end
	-- The motor that carries the body off the root part (RootJoint on R6, Root on R15).
	local root = model.PrimaryPart
	local joint
	for _, j in model:GetDescendants() do
		if j:IsA("Motor6D") and j.Part0 == root then
			joint = j
			break
		end
	end
	s = {
		LimbHealth = {},
		-- Limb groups that have lost something (their effect has been applied).
		Lost = {},
		-- Limb group -> the ball socket it hangs from once loosened.
		Loose = {},
		BaseSpeed = model:GetAttribute("BaseWalkSpeed") or humanoid.WalkSpeed,
		StaggerToken = 0,
		LastHurt = 0,
		Joint = joint,
		BaseC0 = if joint then joint.C0 else CFrame.identity,
		Crawling = false,
	}
	for key, limb in cfg.Limbs or {} do
		s.LimbHealth[key] = limb.Health
	end
	states[model] = s
	return s
end

-- Joints -------------------------------------------------------------------------------

-- The joint a part hangs from: its Motor6D, or the ball socket it was loosened onto.
local function parentJoint(model, part)
	for _, j in model:GetDescendants() do
		if j:IsA("Motor6D") and j.Part1 == part and j.Part0 then
			return j
		elseif j:IsA("BallSocketConstraint") and j.Name == "Loose" and j.Attachment1 and j.Attachment1.Parent == part then
			return j
		end
	end
	return nil
end

-- Where a hit on this part breaks the body: its own joint, or for bits welded onto a limb
-- (eyes, armour) the joint of the part they sit on. Returns the joint and the part below it.
local function breakPoint(model, part, key)
	local j = parentJoint(model, part)
	if j then
		return j, part
	end
	for _, w in model:GetDescendants() do
		if (w:IsA("WeldConstraint") or w:IsA("Weld")) and (w.Part0 == part or w.Part1 == part) then
			local host = if w.Part0 == part then w.Part1 else w.Part0
			if host and host:GetAttribute("Limb") == key then
				j = parentJoint(model, host)
				if j then
					return j, host
				end
			end
		end
	end
	return nil, nil
end

-- The body side of a joint, and the joint point in that part's and the limb's space.
local function jointEnds(joint)
	if joint:IsA("Motor6D") then
		return joint.Part0, joint.C0.Position, joint.C1.Position
	end
	return joint.Attachment0.Parent, joint.Attachment0.Position, joint.Attachment1.Position
end

-- Every part still joined to the mob's root if `cut` were gone.
local function joinedToRoot(model, cut)
	local links = {}
	local function link(a, b)
		if a and b then
			links[a] = links[a] or {}
			links[b] = links[b] or {}
			table.insert(links[a], b)
			table.insert(links[b], a)
		end
	end
	for _, j in model:GetDescendants() do
		if j == cut then
			continue
		elseif j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			link(j.Part0, j.Part1)
		elseif j:IsA("BallSocketConstraint") and j.Attachment0 and j.Attachment1 then
			link(j.Attachment0.Parent, j.Attachment1.Parent)
		end
	end
	local root = model.PrimaryPart
	local seen = { [root] = true }
	local queue = { root }
	while #queue > 0 do
		local p = table.remove(queue)
		for _, q in links[p] or {} do
			if not seen[q] then
				seen[q] = true
				table.insert(queue, q)
			end
		end
	end
	return seen
end

local function cutOff(model, cut)
	local kept = joinedToRoot(model, cut)
	local parts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and not kept[p] then
			table.insert(parts, p)
		end
	end
	return parts, kept
end

-- Loosen and tear ----------------------------------------------------------------------

-- The joint gives way: the limb now hangs on a ball socket, held by strands of flesh.
local function perpendicular(v, axis, fallback)
	local p = v - axis * v:Dot(axis)
	if p.Magnitude < 0.05 then
		p = fallback - axis * fallback:Dot(axis)
		return p.Unit, false
	end
	return p.Unit, true
end

-- Socket frames for a loose limb, in limb space and body space. The limb's X runs down it
-- (its longest axis, away from the joint); the body's X points straight down at the moment
-- it comes loose (not the joint's pose, which may hold the arm out), tipped LOOSE_TILT toward
-- the outside of the body. So the cone limits swing from hanging and the twist limit is roll.
local function hangFrames(joint, limbPart)
	local size = limbPart.Size
	local along = Vector3.yAxis
	if size.X > size.Y and size.X >= size.Z then
		along = Vector3.xAxis
	elseif size.Z > size.Y then
		along = Vector3.zAxis
	end
	if along:Dot(-joint.C1.Position) < 0 then
		along = -along
	end
	local hang = joint.Part0.CFrame:VectorToObjectSpace(-Vector3.yAxis)
	local out, outward = perpendicular(joint.C0.Position, hang, math.abs(hang.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis)
	local limbOut = perpendicular((joint.C0 * joint.C1:Inverse()):VectorToObjectSpace(out), along, math.abs(along.Y) < 0.9 and Vector3.yAxis or Vector3.zAxis)
	local tilt = if outward then math.rad(LOOSE_TILT) else 0
	return CFrame.fromMatrix(joint.C1.Position, along, limbOut),
		CFrame.fromMatrix(joint.C0.Position, hang, out) * CFrame.Angles(0, 0, tilt)
end

local function loosen(model, s, key, joint, limbPart, ctx)
	if not joint:IsA("Motor6D") then
		return
	end
	local body = joint.Part0
	local limbFrame, bodyFrame = hangFrames(joint, limbPart)
	local a0 = Instance.new("Attachment")
	a0.Name = "LooseBody"
	a0.CFrame = bodyFrame
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Name = "LooseLimb"
	a1.CFrame = limbFrame
	a1.Parent = limbPart
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "Loose"
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.LimitsEnabled = true
	socket.UpperAngle = LOOSE_SWING
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -LOOSE_TWIST
	socket.TwistUpperAngle = LOOSE_TWIST
	socket.Restitution = 0.05
	socket.Parent = body

	local hanging, kept = cutOff(model, joint)
	joint:Destroy()
	for _, p in hanging do
		p.Massless = false
		p.CanCollide = p.Size.Magnitude > 0.6
		-- It hangs off the body without snagging on it.
		for k in kept do
			if k:IsA("BasePart") then
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = p
				nc.Part1 = k
				nc.Parent = p
			end
		end
	end
	pcall(function()
		limbPart:SetNetworkOwner(nil)
	end)
	limbPart:ApplyImpulse(ctx.Dir * limbPart.AssemblyMass * 10)
	s.Loose[key] = socket
	-- Physics puts a limb on a still body to sleep mid-swing (it froze sticking out at 70
	-- degrees); an unnoticeable nudge while it is still keeps it hanging and swaying.
	task.spawn(function()
		while socket.Parent and limbPart.Parent do
			task.wait(0.4)
			if limbPart.AssemblyLinearVelocity.Magnitude < 0.05 and not limbPart.Anchored then
				limbPart:ApplyImpulse(Vector3.new(0, -0.001 * limbPart.AssemblyMass, 0))
			end
		end
	end)

	Remotes.MobFx:FireAllClients("Loosen", body, a0.Position, a0.WorldPosition, ctx.Dir, {
		Limb = limbPart,
		LimbLocal = a1.Position,
		MobType = model:GetAttribute("MobType"),
	})
end

-- The limb tears away: a spring holds it at the joint for TearHold while it pulls away
-- (clients stretch and snap flesh strands over that gap), then it flies.
local function tear(model, cfg, key, joint, limbPart, ctx, boost)
	boost = boost or 1
	local body, bodyLocal, limbLocal = jointEnds(joint)
	local parts = cutOff(model, joint)
	if joint:IsA("BallSocketConstraint") then
		joint.Attachment0:Destroy()
		joint.Attachment1:Destroy()
	end
	joint:Destroy()

	local gib = Instance.new("Model")
	gib.Name = model.Name .. "_" .. key
	for _, p in parts do
		p.Anchored = false
		p.CanCollide = p.Size.Magnitude > 0.6
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = false
		p.CollisionGroup = "Debris"
		for _, nc in p:GetChildren() do
			if nc:IsA("NoCollisionConstraint") then
				nc:Destroy()
			end
		end
		p.Parent = gib
	end
	gib.Parent = gibFolder()
	Debris:AddItem(gib, cfg.GibTime)
	pcall(function()
		limbPart:SetNetworkOwner(nil)
	end)

	local hold = cfg.Gore.TearHold
	local push = (flat(ctx.Dir) * 14 + Vector3.new((math.random() - 0.5) * 6, 11 + math.random() * 5, (math.random() - 0.5) * 6)) * boost
	local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 24 * boost

	local a0 = Instance.new("Attachment")
	a0.Name = "TearBody"
	a0.Position = bodyLocal
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Name = "TearLimb"
	a1.Position = limbLocal
	a1.Parent = limbPart
	-- Tuned so the stretch peaks just as the flesh lets go.
	local mass = limbPart.AssemblyMass
	local w = math.pi / (2 * hold)
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = a0
	spring.Attachment1 = a1
	spring.FreeLength = 0
	spring.Stiffness = mass * w * w
	spring.Damping = mass * w * 0.3
	spring.Parent = body
	limbPart.AssemblyLinearVelocity = push * 0.7
	limbPart.AssemblyAngularVelocity = spin * 0.3
	task.delay(hold, function()
		spring:Destroy()
		a0:Destroy()
		a1:Destroy()
		if limbPart.Parent then
			limbPart.AssemblyLinearVelocity = push
			limbPart.AssemblyAngularVelocity = spin
		end
	end)

	Remotes.MobFx:FireAllClients("Sever", body, bodyLocal, limbPart.Position, ctx.Dir, {
		Limb = limbPart,
		LimbLocal = limbLocal,
		Hold = hold,
		MobType = model:GetAttribute("MobType"),
		Gun = ctx.GunName,
	})
end

-- A head that bursts instead of coming off whole: it and everything on it are gone, and
-- clients draw the burst and the torn neck.
local function popHead(model, joint, ctx)
	local body, bodyLocal = jointEnds(joint)
	local head = if joint:IsA("Motor6D") then joint.Part1 else joint.Attachment1.Parent
	local center = head.Position
	local parts = cutOff(model, joint)
	if joint:IsA("BallSocketConstraint") then
		joint.Attachment0:Destroy()
		joint.Attachment1:Destroy()
	end
	joint:Destroy()
	for _, p in parts do
		p:Destroy()
	end
	Remotes.MobFx:FireAllClients("Pop", body, bodyLocal, center, ctx.Dir, {
		MobType = model:GetAttribute("MobType"),
	})
end

-- The joint a whole limb group hangs from (shoulder, hip), or its loose socket.
local function limbRoot(model, s, key)
	local loose = s.Loose[key]
	if loose and loose.Parent then
		return loose, loose.Attachment1.Parent
	end
	for _, j in model:GetDescendants() do
		if j:IsA("Motor6D") and j.Part0 and j.Part1 and j.Part1:GetAttribute("Limb") == key and j.Part0:GetAttribute("Limb") ~= key then
			return j, j.Part1
		end
	end
	return nil, nil
end

-- Point-blank shotgun kill: more limbs go with the ones the pellets took, and the torso
-- bursts open (drawn by clients).
local function burst(model, s, cfg, ctx)
	local splat = ctx.Splat
	local spare = {}
	for key, limb in cfg.Limbs or {} do
		if not limb.Kills and not s.Lost[key] then
			table.insert(spare, key)
		end
	end
	for _ = 1, math.min(splat.ExtraLimbs or 0, #spare) do
		local key = table.remove(spare, math.random(#spare))
		local joint, limbPart = limbRoot(model, s, key)
		if joint then
			s.Loose[key] = nil
			tear(model, cfg, key, joint, limbPart, ctx, splat.Throw)
			s.LimbHealth[key] = 0
			s.Lost[key] = true
		end
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model.PrimaryPart
	if torso then
		Remotes.MobFx:FireAllClients("Burst", torso, nil, torso.Position, ctx.Dir, {
			MobType = model:GetAttribute("MobType"),
		})
	end
end

-- A dead body goes limp: every joint but the root becomes a ball socket, and neighbouring
-- parts stop colliding with each other.
local function ragdoll(model)
	local root = model.PrimaryPart
	for _, j in model:GetDescendants() do
		if j:IsA("Motor6D") and j.Part0 and j.Part1 and j.Part0 ~= root and j.Part1 ~= root then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagBody"
			a0.CFrame = j.C0
			a0.Parent = j.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagLimb"
			a1.CFrame = j.C1
			a1.Parent = j.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "Ragdoll"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = RAG_SWING
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -RAG_TWIST
			socket.TwistUpperAngle = RAG_TWIST
			socket.Parent = j.Part0
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = j.Part0
			nc.Part1 = j.Part1
			nc.Parent = j.Part0
			j:Destroy()
		end
	end
end

-- Movement ----------------------------------------------------------------------------

local function startCrawl(model, s, cfg, humanoid)
	s.Crawling = true
	s.BaseSpeed *= cfg.CrawlSpeed
	humanoid.WalkSpeed = s.BaseSpeed
	model:SetAttribute("Crawling", true)
	if s.Joint then
		s.BaseC0 = CRAWL_POSE * s.BaseC0
		TweenService:Create(s.Joint, CRAWL_DOWN, { C0 = s.BaseC0 }):Play()
	end
end

-- The speed a mob walks at when nothing is staggering it: its base speed, times a Smoke slow while one lasts.
local function freeSpeed(s)
	return s.BaseSpeed * (if (s.SlowUntil or 0) > os.clock() then s.SlowMult or 1 else 1)
end

local function stagger(model, s, cfg, humanoid, mult)
	s.StaggerToken += 1
	local token = s.StaggerToken
	humanoid.WalkSpeed = s.BaseSpeed * cfg.Stagger.Slow
	-- MobAttack reads this: a stagger breaks off a swing that is still winding up.
	model:SetAttribute("StaggerUntil", math.max(model:GetAttribute("StaggerUntil") or 0, os.clock() + cfg.Stagger.Time * mult))
	task.delay(cfg.Stagger.Time * mult, function()
		if s.StaggerToken == token and humanoid.Health > 0 and (s.StunUntil or 0) <= os.clock() then
			humanoid.WalkSpeed = freeSpeed(s)
		end
	end)
end

local function knockback(model, humanoid, cfg, feel, ctx, mult)
	local root = model.PrimaryPart
	if not root or root.Anchored then
		return
	end
	local push = (feel.Knockback or 0) * cfg.KnockbackScale * mult
	root.AssemblyLinearVelocity += flat(ctx.Dir) * push + Vector3.new(0, push * (feel.KnockLift or 0), 0)
	-- A heavy enough blast takes the mob off its feet; it gets back up by itself.
	if feel.KnockDown and (ctx.Share or 1) >= feel.KnockDown then
		humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
	end
end

-- Freeze for a beat so the kill reads, then the body goes limp and is thrown along the shot.
local function kill(model, s, cfg, humanoid, feel, ctx)
	if model:GetAttribute("Dead") then
		return
	end
	model:SetAttribute("Dead", true)
	if humanoid.Health > 0 then
		humanoid.Health = 0
	end
	local root = model.PrimaryPart
	SoundKit.Play(cfg.Sounds .. "/Death", { Position = headOrRoot(model).Position })
	Remotes.MobFx:FireAllClients("Kill", nil, nil, ctx.HitPos, ctx.Dir)
	-- Nothing poses the corpse any more.
	local animate = model:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") then
		animate.Enabled = false
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
	if ctx.Splat then
		burst(model, s, cfg, ctx)
	end
	if not root then
		return
	end
	root.Anchored = true
	task.delay(feel.KillFreeze or 0.06, function()
		if not root.Parent then
			return
		end
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.CanCollide = p ~= root and p.Size.Magnitude > 0.4
				p.CollisionGroup = "Debris"
			end
		end
		ragdoll(model)
		root.Anchored = false
		local dir = flat(ctx.Dir)
		local throw = (feel.BodyThrow or 30) * cfg.ThrowScale * (if ctx.Splat then ctx.Splat.Throw else 1)
		local fling = dir * throw + Vector3.new(0, throw * (feel.BodyLift or 0.3), 0)
		local tumble = Vector3.yAxis:Cross(dir) * throw * 0.18
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and not p.Anchored then
				pcall(function()
					p:SetNetworkOwner(nil)
				end)
				-- Each piece flies a little differently, so the body folds as it goes.
				p.AssemblyLinearVelocity = fling * (0.85 + math.random() * 0.3)
				p.AssemblyAngularVelocity = tumble + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * throw * 0.05
			end
		end
		-- The part that was hit leads.
		local hit = ctx.HitPart
		if hit and hit:IsDescendantOf(model) and not hit.Anchored then
			hit.AssemblyLinearVelocity += dir * throw * 0.35
		end
		task.delay(0.45, function()
			if root.Parent then
				SoundKit.Play(cfg.Sounds .. "/BodyFall", { Position = root.Position })
			end
		end)
	end)
end

-- Limb damage: loosen at DangleAt, tear at zero. A limb torn partway (a forearm off the
-- elbow) keeps StumpLeft of its health and can be torn again further up.
local function damageLimb(model, s, cfg, humanoid, hitPart, key, limb, damage, ctx, killed)
	local before = s.LimbHealth[key] or 0
	if before <= 0 then
		return nil, killed
	end
	local after = before - damage * ((ctx.Gun.Feel or {}).LimbDamage or 1) * (if ctx.Splat then ctx.Splat.LimbDamage else 1)
	s.LimbHealth[key] = after

	local loose = s.Loose[key]
	if loose and not loose.Parent then
		loose = nil
		s.Loose[key] = nil
	end

	if after > 0 then
		local canDangle = not limb.Kills and limb.Dangles ~= false
		if canDangle and not loose and after <= limb.Health * cfg.Gore.DangleAt then
			local joint, limbPart = breakPoint(model, hitPart, key)
			if joint and joint:IsA("Motor6D") then
				loosen(model, s, key, joint, limbPart, ctx)
			end
		elseif loose and hitPart:IsDescendantOf(model) then
			-- Shooting a hanging limb swings it.
			local feel = ctx.Gun.Feel or {}
			hitPart:ApplyImpulse(ctx.Dir * hitPart.AssemblyMass * (feel.Knockback or 6) * LOOSE_PUSH)
		end
		return nil, killed
	end

	-- Tear at the loosened joint if there is one, else where the shot landed.
	local joint, limbPart
	if loose then
		joint, limbPart = loose, loose.Attachment1.Parent
		s.Loose[key] = nil
	else
		joint, limbPart = breakPoint(model, hitPart, key)
	end
	if not joint then
		return nil, killed
	end
	local body = jointEnds(joint)
	local whole = body:GetAttribute("Limb") ~= key
	if limb.Kills and whole and ((ctx.Gun.Feel or {}).HeadPop or ctx.Splat) then
		popHead(model, joint, ctx)
	else
		tear(model, cfg, key, joint, limbPart, ctx, if ctx.Splat then ctx.Splat.Throw else nil)
	end
	s.LimbHealth[key] = if whole then 0 else limb.Health * cfg.Gore.StumpLeft

	if limb.Kills and whole then
		humanoid.Health = 0
		killed = true
	elseif not s.Lost[key] then
		if limb.Crawls and not s.Crawling and not killed then
			startCrawl(model, s, cfg, humanoid)
		elseif limb.Weakens then
			model:SetAttribute("ArmsLost", (model:GetAttribute("ArmsLost") or 0) + 1)
		end
	end
	s.Lost[key] = true
	return key, killed
end

-- Public --------------------------------------------------------------------------------

-- Whether a mob is elite (Brute, captain, boss, heavy); also sets its Elite attribute.
function MobReactions.IsElite(model)
	return markElite(model, getConfig(model))
end

-- Flashbang: the mob stands dazed for `seconds` (MobAI holds it still and MobAttack sees StaggerUntil).
function MobReactions.Stun(model, seconds)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local cfg = getConfig(model)
	if not humanoid or humanoid.Health <= 0 or not cfg then
		return
	end
	local s = getState(model, cfg, humanoid)
	local untilClock = os.clock() + seconds
	s.StunUntil = math.max(s.StunUntil or 0, untilClock)
	s.StaggerToken += 1
	local token = s.StaggerToken
	humanoid.WalkSpeed = 0
	model:SetAttribute("StaggerUntil", math.max(model:GetAttribute("StaggerUntil") or 0, untilClock))
	model:SetAttribute("StunUntil", workspace:GetServerTimeNow() + seconds)
	task.delay(seconds, function()
		if s.StaggerToken == token and humanoid.Health > 0 then
			humanoid.WalkSpeed = freeSpeed(s)
		end
	end)
end

-- Smoke: the mob walks at mult x its speed for `seconds` (refreshed while it stays in the cloud).
function MobReactions.Slow(model, mult, seconds)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local cfg = getConfig(model)
	if not humanoid or humanoid.Health <= 0 or not cfg then
		return
	end
	local s = getState(model, cfg, humanoid)
	s.SlowMult = mult
	s.SlowUntil = os.clock() + seconds
	if (s.StunUntil or 0) <= os.clock() and humanoid.WalkSpeed > s.BaseSpeed * mult then
		humanoid.WalkSpeed = s.BaseSpeed * mult
	end
	local token = s.SlowUntil
	task.delay(seconds + 0.05, function()
		if s.SlowUntil == token and humanoid.Health > 0 and (s.StunUntil or 0) <= os.clock()
			and math.abs(humanoid.WalkSpeed - s.BaseSpeed * mult) < 0.01 then
			humanoid.WalkSpeed = s.BaseSpeed
		end
	end)
end

-- Call when a mob spawns: idle groans while alive, corpse cleanup after death.
function MobReactions.Spawned(model)
	local cfg = getConfig(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not cfg or not humanoid then
		return
	end
	-- Limbs come off one at a time, never all at once on death or with the neck.
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	-- Mobs never climb or swim: the Humanoid stops testing for ladders and water every physics step.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	task.spawn(function()
		local gap = cfg.IdleSoundGap
		task.wait(math.random() * gap.Max)
		while model.Parent and humanoid.Health > 0 do
			SoundKit.Play(cfg.Sounds .. "/Idle", { Position = headOrRoot(model).Position })
			task.wait(gap.Min + math.random() * (gap.Max - gap.Min))
		end
	end)
	markElite(model, cfg)
	humanoid.Died:Once(function()
		task.delay(cfg.CorpseTime, function()
			for _, p in model:GetDescendants() do
				if p:IsA("BasePart") then
					TweenService:Create(p, CORPSE_FADE, { Transparency = 1 }):Play()
				end
			end
			Debris:AddItem(model, 1.1)
		end)
	end)
end

-- Applies one shot's validated hits on a mob: hits = { { Part, Damage, Pos, IsHead } }, one
-- per bullet or pellet that landed. ctx = { Player, Gun, GunName, HitPos, Dir, Distance, Share }
-- (Share: the part of the shot's pellets that landed on this mob).
-- Returns killed, the limb group that lost a part (if one did), and the damage the shot did.
function MobReactions.Hit(model, hits, ctx)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or #hits == 0 then
		return false, nil, 0
	end
	local feel = ctx.Gun.Feel or {}
	local elite = markElite(model, getConfig(model))
	-- Damage multipliers: the Defend tier of a player's gun, and the squad's Mark on this mob.
	local dmgMult = 1
	if ctx.Player and not ctx.Gear then
		dmgMult *= tierMult(ctx.Player, ctx.GunName)
	end
	if elite and ctx.Player then
		dmgMult *= perk(ctx.Player, "EliteDamage")
	end
	if (model:GetAttribute("MarkedUntil") or 0) > workspace:GetServerTimeNow() then
		local mark = gearItem("Mark")
		dmgMult *= 1 + (mark and mark.Bonus or 0.1)
	end
	if dmgMult ~= 1 then
		for _, hit in hits do
			hit.Damage *= dmgMult
		end
	end
	local total = 0
	local isHead = false
	local parts, positions = {}, {}
	for i, hit in hits do
		total += hit.Damage
		isHead = isHead or hit.IsHead
		parts[i] = hit.Part
		positions[i] = hit.Pos
	end
	ctx.HitPart = hits[1].Part
	ctx.IsHead = isHead
	-- A close enough shotgun kill splats; decided before the limbs take their damage.
	local splat = feel.Splat
	if splat and humanoid.Health - total <= 0 and (ctx.Distance or math.huge) <= splat.Range and (ctx.Share or 1) >= splat.MinShare then
		ctx.Splat = splat
	end
	local dealt = math.min(total, humanoid.Health)
	humanoid.Health = math.max(0, humanoid.Health - total)
	local killed = humanoid.Health <= 0
	local severed = nil

	-- Everyone else sees the kicks and the wounds now; the shooter already has.
	Remotes.MobFx:FireAllClients("Hit", nil, nil, ctx.HitPos, ctx.Dir, {
		Shooter = ctx.Player,
		Gun = ctx.GunName,
		Parts = parts,
		Positions = positions,
	})

	local cfg = getConfig(model)
	if cfg then
		local s = getState(model, cfg, humanoid)
		local limbStagger = 1
		for _, hit in hits do
			local limbKey = hit.Part:GetAttribute("Limb")
			local limb = limbKey and cfg.Limbs[limbKey]
			-- A pellet behind one that already took this limb off hits nothing.
			if limb and hit.Part:IsDescendantOf(model) then
				limbStagger = math.max(limbStagger, limb.Stagger or 1)
				local lost
				lost, killed = damageLimb(model, s, cfg, humanoid, hit.Part, limbKey, limb, hit.Damage, ctx, killed)
				severed = severed or lost
			end
		end
		local mult = (feel.Stagger or 1) * limbStagger * (ctx.Share or 1)
		if elite and isHead and ctx.Player then
			mult *= perk(ctx.Player, "EliteStagger")
		end

		if killed then
			kill(model, s, cfg, humanoid, feel, ctx)
		else
			stagger(model, s, cfg, humanoid, mult)
			knockback(model, humanoid, cfg, feel, ctx, mult)
			local now = os.clock()
			if now - s.LastHurt > cfg.HurtSoundGap then
				s.LastHurt = now
				SoundKit.Play(cfg.Sounds .. "/Hurt", { Position = headOrRoot(model).Position })
			end
		end
	end

	EnemyHit:Fire(model, ctx.HitPart, dealt, isHead, killed, ctx.Player, ctx.HitPos, ctx.Dir, {
		GunName = ctx.GunName,
		Headshot = isHead,
		Killed = killed,
		Elite = elite,
		Gear = ctx.Gear == true,
	})
	return killed, severed, total
end

return MobReactions
