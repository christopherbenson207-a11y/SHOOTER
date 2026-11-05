-- Shared.Gear (MATCH, menu revamp 3 Nov 2026; CONTRACTS section 2, MENU-PLAN 4.6, 9.5, 9.10).
-- Plain config for every lethal, tactical and field item plus small pure helpers. No instances, no yields.
-- Every damaging item carries a gun-shaped Hit table ({Damage, Feel = {...}, LimbDamage}) so MobReactions.Hit
-- treats it like a gun (ctx.Gun = item.Hit, ctx.GunName = the gear key, ctx.Gear = true).
-- Used by ServerScriptService.GearServer (server truth), StarterPlayerScripts.GearClient (input, arc, Fx) and
-- MobReactions (Mark bonus). Models: ReplicatedStorage.Assets.Gear.<Key> (copied from ServerStorage.ArtStaging.Gear).

local G = {}

-- Slot: Lethal | Tactical | Field. Level: account level that unlocks it (Shared.Progression owns unlocks; this is
-- the same number for cards). Count: carried per life (lethals x the LethalCount class perk). Art: Shared.UiArt key.
-- Kind: Throw (arc, lands, then acts), Use (on yourself), Place (dropped at your feet or on the aimed ground),
-- Aim (acts along your view at once).
G.Items = {
	Frag = {
		Slot = "Lethal", Name = "FRAG", Level = 1, Count = 1, Art = "Gear/Frag", Kind = "Throw",
		Speed = 72, Lift = 14, Fuse = 0, Bounce = false, Impact = true, -- goes off on the first thing it touches
		Radius = 14, Noise = 160,
		Hit = {
			Damage = 220, LimbDamage = 1.6,
			Feel = { Knockback = 60, KnockLift = 0.6, KnockDown = 0.35, Stagger = 2.5, LimbDamage = 1.6,
				BodyThrow = 60, BodyLift = 0.7, KillFreeze = 0.02 },
		},
		WorldDamage = 120,
	},
	Molotov = {
		Slot = "Lethal", Name = "MOLOTOV", Level = 8, Count = 1, Art = "Gear/Molotov", Kind = "Throw",
		Speed = 62, Lift = 12, Fuse = 0, Bounce = false, Impact = true,
		Radius = 10, Duration = 7, Dps = 25, Tick = 0.5,
		Hit = {
			Damage = 12.5, LimbDamage = 0.4,
			Feel = { Knockback = 0, Stagger = 0.5, LimbDamage = 0.4, BodyThrow = 12, BodyLift = 0.2 },
		},
	},
	Flare = {
		Slot = "Tactical", Name = "FLARE", Level = 1, Count = 2, Art = "Gear/Flare", Kind = "Throw",
		Speed = 58, Lift = 12, Fuse = 0, Bounce = true,
		Burn = 30, Light = 45, LightColor = Color3.fromRGB(255, 92, 70),
		LureTime = 8, LureRadius = 70, BeaconLure = 6,
	},
	Flashbang = {
		Slot = "Tactical", Name = "FLASHBANG", Level = 11, Count = 2, Art = "Gear/Flashbang", Kind = "Throw",
		Speed = 68, Lift = 13, Fuse = 1.5, Bounce = true,
		Radius = 16, Stun = 3, EliteStun = 1.5, Noise = 140, BlindRadius = 20,
	},
	Stim = {
		Slot = "Tactical", Name = "STIM", Level = 3, Count = 1, Art = "Gear/Stim", Kind = "Use",
		Heal = 50, Speed = 1.15, SpeedTime = 4,
	},

	-- Field items: one per class, 90 s cooldown (player attribute FieldReadyAt, server time).
	Smoke = {
		Slot = "Field", Name = "SMOKE", Class = "Rifleman", Cooldown = 90, Art = "Gear/Smoke", Kind = "Throw",
		Speed = 55, Lift = 12, Fuse = 1, Bounce = true,
		Radius = 14, Duration = 12, Slow = 0.5,
	},
	MedPouch = {
		Slot = "Field", Name = "MED POUCH", Class = "Medic", Cooldown = 90, Art = "Gear/MedPouch", Kind = "Place",
		Radius = 8, Heal = 40, HealTime = 5, Life = 8,
	},
	AmmoCrate = {
		Slot = "Field", Name = "AMMO CRATE", Class = "Engineer", Cooldown = 90, Art = "Gear/AmmoCrate", Kind = "Place",
		Radius = 7, Life = 45,
	},
	ReconFlare = {
		Slot = "Field", Name = "RECON FLARE", Class = "Scout", Cooldown = 90, Art = "Gear/ReconFlare", Kind = "Use",
		Duration = 12, Range = 220,
	},
	Mark = {
		Slot = "Field", Name = "MARK", Class = "Hunter", Cooldown = 90, Art = "Gear/Mark", Kind = "Aim",
		Range = 160, Cone = 0.93, Duration = 20, Bonus = 0.1,
	},
	Extinguisher = {
		Slot = "Field", Name = "EXTINGUISHER", Class = "Firefighter", Cooldown = 90, Art = "Gear/Extinguisher", Kind = "Aim",
		Range = 16, Cone = 0.55, PutsOut = 12,
		Hit = {
			Damage = 15, LimbDamage = 0.2,
			Feel = { Knockback = 95, KnockLift = 0.35, KnockDown = 0.2, Stagger = 3, LimbDamage = 0.2 },
		},
	},
	Decoy = {
		Slot = "Field", Name = "DECOY", Class = "Marksman", Cooldown = 90, Art = "Gear/Decoy", Kind = "Place",
		LureTime = 8, LureRadius = 70,
	},
	Charge = {
		Slot = "Field", Name = "BREACHING CHARGE", Class = "Demolition", Cooldown = 90, Art = "Gear/Charge", Kind = "Place",
		Detonate = true, Life = 60, Radius = 14, Noise = 170,
		Hit = {
			Damage = 300, LimbDamage = 1.8,
			Feel = { Knockback = 70, KnockLift = 0.7, KnockDown = 0.3, Stagger = 3, LimbDamage = 1.8,
				BodyThrow = 70, BodyLift = 0.8, KillFreeze = 0.02 },
		},
		WorldDamage = 200,
	},
}

-- The class's field item key.
G.FieldFor = {
	Rifleman = "Smoke", Medic = "MedPouch", Engineer = "AmmoCrate", Scout = "ReconFlare",
	Hunter = "Mark", Firefighter = "Extinguisher", Marksman = "Decoy", Demolition = "Charge",
}

-- Throws: one arc simulation for client preview and server truth.
G.Throw = {
	Gravity = 120, -- studs/s^2 (heavier than workspace gravity for a snappy readable arc)
	Step = 1 / 30,
	MaxTime = 3.5,
	MaxOriginOffset = 8, -- origin must be this close to the thrower's head
	Gap = 0.8, -- seconds between two throws of anything
	BounceKeep = 0.35, -- speed kept after a bounce
	MaxBounces = 2,
	PlaceRange = 10, -- Place items land on the ground within this many studs of the player
}

-- Input (GearClient). Tactical is Q unless Q is taken, then T.
G.Keys = {
	Lethal = { Key = Enum.KeyCode.G, Pad = Enum.KeyCode.ButtonR1 },
	Tactical = { Key = Enum.KeyCode.Q, Alt = Enum.KeyCode.T, Pad = Enum.KeyCode.ButtonL1 },
	Field = { Key = Enum.KeyCode.X, Pad = Enum.KeyCode.DPadRight },
}

-- Helpers ---------------------------------------------------------------------------------------------------------

function G.Item(key)
	return if type(key) == "string" then G.Items[key] else nil
end

-- The starting velocity of a throw of `key` along `direction` (a unit vector).
function G.Velocity(key, direction)
	local item = G.Items[key]
	if not item or typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then
		return nil
	end
	local d = direction.Unit
	return d * (item.Speed or 60) + Vector3.new(0, item.Lift or 10, 0)
end

-- Steps an arc from origin with velocity under G.Throw.Gravity. cast(from, delta) must return a RaycastResult-like
-- table or nil ({Position, Normal, Instance}). Returns the list of points (for drawing), where it came to rest,
-- the surface normal there, the time it took, and whether it hit anything.
function G.Simulate(origin, velocity, cast, bounce)
	local T = G.Throw
	local points = { origin }
	local pos, vel = origin, velocity
	local t = 0
	local bounces = 0
	local normal = Vector3.yAxis
	local landed = false
	while t < T.MaxTime do
		local nextVel = vel - Vector3.new(0, T.Gravity * T.Step, 0)
		local delta = (vel + nextVel) * 0.5 * T.Step
		local hit = cast(pos, delta)
		if hit then
			pos = hit.Position + hit.Normal * 0.15
			normal = hit.Normal
			table.insert(points, pos)
			landed = true
			if bounce and bounces < T.MaxBounces and nextVel.Magnitude > 12 then
				bounces += 1
				local reflected = nextVel - 2 * nextVel:Dot(hit.Normal) * hit.Normal
				vel = reflected * T.BounceKeep
				if hit.Normal.Y > 0.7 and vel.Magnitude < 10 then
					break
				end
			else
				break
			end
		else
			pos += delta
			vel = nextVel
			table.insert(points, pos)
		end
		t += T.Step
	end
	return points, pos, normal, t, landed
end

-- Folders that hold mobs; Impact items stop on anything in them.
G.MobFolders = { "Zombies" }

-- An arc cast for Impact items (Item.Impact): the world as usual (world(from, delta)), and also the first living mob in
-- the way. mobParams: an Include RaycastParams over the mob folders with RespectCanCollide off (mob limbs often do not
-- collide). Dead bodies are ignored.
function G.ImpactCast(world, mobParams)
	return function(from, delta)
		local hit = world(from, delta)
		local mob = workspace:Raycast(from, delta, mobParams)
		if mob then
			local model = mob.Instance:FindFirstAncestorOfClass("Model")
			if model and model:GetAttribute("Dead") then
				mob = nil
			end
		end
		if mob and (not hit or (mob.Position - from).Magnitude < (hit.Position - from).Magnitude) then
			return mob
		end
		return hit
	end
end

-- Whether the segment from a to b passes through a sphere (center, radius).
function G.SegmentHitsSphere(a, b, center, radius)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp((center - a):Dot(ab) / len2, 0, 1) else 0
	return ((a + ab * t) - center).Magnitude <= radius
end

-- Whether any smoke cloud blocks the line from a to b. spheres: list of {Position, Radius} (GearServer keeps the
-- live clouds as parts in workspace.GearSmoke with a Radius attribute; see G.SmokeSpheres).
function G.SmokeBlocks(a, b, spheres)
	for _, s in spheres or {} do
		if G.SegmentHitsSphere(a, b, s.Position, s.Radius) then
			return true
		end
	end
	return false
end

-- The live smoke clouds as spheres, read from a folder of parts (pass workspace:FindFirstChild("GearSmoke")).
function G.SmokeSpheres(folder)
	local list = {}
	if folder then
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(list, { Position = p.Position, Radius = p:GetAttribute("Radius") or 12 })
			end
		end
	end
	return list
end

-- The count a player carries per life: Count, times the LethalCount perk for lethals (Demolition 2).
function G.CountFor(key, lethalPerk)
	local item = G.Items[key]
	if not item or item.Slot == "Field" then
		return 0
	end
	local n = item.Count or 1
	if item.Slot == "Lethal" then
		n *= math.max(1, math.floor(lethalPerk or 1))
	end
	return n
end

return G
