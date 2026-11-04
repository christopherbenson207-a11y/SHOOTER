-- Every tuning number for Last Light lives here. Scripts read from this table;
-- nothing gameplay-related should be hard-coded anywhere else.

local GameConfig = {}

local V0 = Vector3.zero

GameConfig.Debug = {
	-- Day 1 test range only: reloads never use up reserve ammo. Off since 29 Oct: ammo comes
	-- from pickups (GameConfig.Pickups).
	InfiniteReserve = false,
}

GameConfig.Camera = {
	HipFov = 74,
	SprintFovBonus = 6,
}

-- First-person arms are the player's own avatar arms (ViewArms): copied straight in their
-- rest pose and aimed so each hand closes on the gun's RightGrip / LeftGrip marker.
-- Positions are camera space in studs (x right, y up, z back).
GameConfig.ViewArms = {
	-- The viewmodel's scale (the pistol model was shrunk by this much).
	Scale = 0.33,
	-- Slims the arms so they don't swallow the gun (1 = the avatar's own build).
	WidthScale = 0.72,
	-- Each arm runs straight from its hand toward its shoulder point.
	-- A gun can set its own LeftShoulder: long guns bring the left arm up from below the
	-- screen to the forward grip instead of across the middle of it.
	RightShoulder = Vector3.new(0.8, -0.75, 0.1),
	LeftShoulder = Vector3.new(-0.7, -0.8, 0.1),
	-- Shoulders draw in toward the middle while aiming down sights.
	AimShoulderIn = 0.12,
}

GameConfig.Movement = {
	WalkSpeed = 16,
	SprintSpeed = 23,
	AimSpeed = 11,
	-- After firing, sprint is blocked for this long so you can't shoot-and-run.
	SprintBlockAfterShot = 0.35,
}

-- Player health, going down and getting back up. Health works like Call of Duty Zombies
-- (it comes back by itself after a few seconds out of harm; three swipes put you down) and
-- going down works like Left 4 Dead: you drop to the floor with the pistol and bleed out
-- unless a teammate picks you up. Bleeding out ends in the devour: the zombies pile on
-- and cover you, nothing gory shown.
GameConfig.Player = {
	MaxHealth = 100,
	-- Health comes back after this long without a hit, at RegenRate per second.
	RegenDelay = 4,
	RegenRate = 25,
	-- At or below this share of health the heartbeat plays and the screen closes in.
	LowHealth = 0.35,
	-- Hits closer together than this count once, so two swipes on the same beat don't
	-- take you from full to down.
	HitGrace = 0.3,
	RespawnTime = 5,
	-- Nothing can hurt you this long after spawning.
	SpawnGrace = 2.5,

	Downed = {
		-- Seconds until you bleed out. Every zombie hit while you're down takes HitCost off,
		-- so zombies standing over you finish you fast (two zombies: about 8 s), but not
		-- before a self-revive can be held. Nothing hurts you for DownGrace after you fall.
		BleedOut = 30,
		HitCost = 3,
		DownGrace = 2,
		-- Last stand: crawl with the pistol only, eyes near the floor.
		Speed = 4,
		Gun = "Pistol",
		CameraDrop = 2.4,
		-- Self-revives per life for now (the brief: one per solo match once matches exist).
		-- Hold the interact key for SelfReviveTime.
		SelfRevives = 1,
		SelfReviveTime = 3,
		-- A teammate holds the interact key next to you this long.
		ReviveTime = 4,
		ReviveRange = 7,
		ReviveHealth = 50,
		-- Getting up shoves zombies this close back (studs/s) and staggers them so you get a
		-- breath, and you can't be hit for GetUpGrace seconds.
		ShoveRadius = 9,
		ShoveSpeed = 30,
		GetUpGrace = 1.5,
	},

	-- Bleeding out (or going down alone with no self-revive left): zombies within Radius,
	-- at most Count of them, close in on the body and pile on for Time seconds.
	Devour = {
		Time = 4,
		Radius = 30,
		Count = 6,
	},

	-- Dying with the police dog at your side (DogServer's Partner is you): before the black, a
	-- few seconds over your body from outside while the dog sits beside it and howls. The camera
	-- stands off to one side of the pair, Distance studs away and Height up, creeping in by
	-- PushIn over the shot, and follows the body at Follow per second. After Time seconds the
	-- black comes up over Fade. Not after the Beacon takes you.
	DeathCam = {
		Time = 3.5,
		Fade = 1.2,
		Follow = 2.5,
		Distance = 11,
		PushIn = 0.8,
		Height = 2.5,
		Fov = 50,
	},
}

-- Every registered gun (GUNS, menu revamp 3 Nov 2026): the client builds animation tracks and ammo for these and
-- the server keeps gun state for them; each keeps its own ammo. A gun is registered once its viewmodel
-- (Assets.ViewModels) and world model (Assets.WorldGuns) exist. What a player carries at spawn comes only from
-- ServerStorage.Modules.Kit (the selected loadout, Shared.LoadoutRules), never from this order.
GameConfig.Arsenal = { "Pistol", "Shotgun", "AK", "Sniper", "MP5", "M4", "HandCannon", "SR25", "M60" }
-- Old name of the same list, for readers that have not moved to Arsenal.
GameConfig.Loadout = GameConfig.Arsenal

-- Lowering the old gun before the next one comes up (seconds).
GameConfig.SwitchLowerTime = 0.14

-- Spread and recoil angles are in degrees.
-- FireMode: "Semi" one shot per click, "Auto" while held, "Pump" / "Bolt" one shot per
-- click and then the Cycle animation chambers the next round.
-- Feel.Knockback shoves a hit mob (studs/s); KnockLift lifts it off its feet by that share;
-- KnockDown knocks it over when at least that share of the pellets landed.
-- Feel.BodyThrow / BodyLift fling the ragdoll on a kill. Feel.ExitSpray is blood drops
-- thrown out the back of each hit. Feel.Splat: close-range kills tear limbs and burst the body.
GameConfig.Guns = {
	Pistol = {
		DisplayName = "Pistol",
		-- Card data (Shared.GunStats.Info): the name on the card, category, loadout slot, unlock level, role line.
		-- WorldLength and Hold describe the world model (Assets.WorldGuns): its length in studs and the
		-- third-person hold ("Rifle" or "Pistol"). Noise (0-1) is how loud a shot is (the NOISE bar; GunServer
		-- passes it with the Gunshot event).
		Name = "SERVICE 9",
		Category = "Pistol",
		Slot = "Secondary",
		Level = 1,
		Role = "THE LAST RESORT",
		WorldLength = 1.3,
		Hold = "Pistol",
		Noise = 0.5,
		ViewModel = "Pistol",
		FireMode = "Semi",
		-- Touch Fire button: "Hip" shoots from the hip, "AimFire" raises the sights while
		-- held and fires, "AimRelease" aims while held and fires on release.
		TouchFire = "Hip",
		RPM = 420,
		Damage = 34,
		BreakRadius = 1.4, -- studs of wood/plastic a hit can knock out (WorldDamage)
		HeadMultiplier = 2.5,
		FalloffStart = 45,
		FalloffEnd = 120,
		FalloffMin = 0.6,
		Range = 400,

		MagSize = 12,
		Reserve = 60,
		ReloadTime = 1.55,
		ReloadEmptyTime = 1.85,

		Spread = {
			Hip = 1.3,
			Aim = 0.12,
			Move = 1.1,
			PerShot = 0.85,
			Max = 4,
			Recover = 7,
		},
		Recoil = {
			Pitch = 2.4,
			Yaw = 0.8,
			AimMultiplier = 0.6,
			-- How far the gun model jumps back toward the camera per shot (studs).
			KickBack = 0.09,
			KickPitch = 9,
		},

		AimTime = 0.15,
		AimFov = 58,
		AimSensitivity = 0.7,
		-- How far in front of the camera the rear sight sits when aiming down sights.
		AimDistance = 0.66,
		-- Where the grip sits at the hip (camera space, studs).
		HipOffset = Vector3.new(0.22, -0.27, -0.6),
		-- Pitch, yaw, roll in degrees so the muzzle angles slightly toward the crosshair.
		HipAngles = Vector3.new(0, 3, 0),
		-- How far the slide travels back on each shot (studs, viewmodel space).
		SlideTravel = 0.08,
		-- The slide stays back on an empty mag.
		LockOnEmpty = true,
		MoveSpeed = 1,
		EquipTime = 0.35,

		-- The 7 punch steps (HORROR-SHOOTER-FEEL.md). Every gun type tunes these differently.
		Feel = {
			-- Sound cues under Assets.Sounds: Crack, Body and Tail layer on each shot.
			Sounds = "Guns/Pistol",

			-- Shot and recoil: camera shake (degrees), FOV punch (degrees), shove on the shooter (studs/s).
			Shake = 0.55,
			FovKick = 1.4,
			PlayerPush = 2.5,
			FlashSize = 0.42,
			FlashTime = 0.05,
			LightBrightness = 6,
			LightRange = 16,
			MuzzleSparks = 4,
			MuzzleSmoke = 2,

			-- Bullets: tracer head width and tail length (studs), speed (studs/s).
			TracerWidth = 0.06,
			TracerLength = 11,
			TracerSpeed = 950,
			TracerColor = Color3.fromRGB(255, 205, 140),

			-- Casings that stay on the floor. Eject is right, up, forward in camera space (studs/s);
			-- keep forward positive or the brass flies into the camera.
			CasingSize = Vector3.new(0.07, 0.07, 0.16),
			CasingColor = Color3.fromRGB(196, 150, 72),
			CasingEject = Vector3.new(8, 5, 1.5),

			-- Hits on mobs: shove along the shot (studs/s), stagger multiplier, limb damage
			-- multiplier and how much the hit part squashes.
			Knockback = 7,
			Stagger = 1,
			LimbDamage = 1,
			Squash = 0.82,
			-- Instant visual reaction (MobImpact): how hard the hit part's joint kicks (x the mob's
			-- PartKick), how far the body pitches back (radians) and is shoved (studs).
			HitSnap = 1,
			BodyJolt = 0.2,
			BodyShove = 0.45,

			-- Kills: freeze (seconds), then throw the body (studs/s), plus a bigger camera shake.
			KillFreeze = 0.07,
			BodyThrow = 34,
			BodyLift = 0.3,
			KillShake = 1.1,
		},

		-- Reload animation keys over normalised time (0-1 of ReloadTime or ReloadEmptyTime).
		-- GunPos/GunRot move the whole gun, HandPos/HandRot move the left hand (studs, degrees,
		-- viewmodel space). Channels ease between the keys that set them. The arms follow.
		-- HandPos moves the left hand's grip point (the LeftGrip marker). A mag in the hand sits
		-- with its base in the palm, so HandPos (0.031, -0.075, 0.059) is a fully seated mag.
		-- Mag: "Drop" lets the old mag fall to the floor, "Hand" puts a new one in the left hand,
		-- "Gun" seats it. Slide: 0 forward, 1 locked back. Sound names are cues in Feel.Sounds.
		-- Kick bumps the gun like a recoil impulse (slaps and slide releases).
		ReloadAnim = {
			Tactical = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				-- Cant the gun so the mag well swings toward the left hand.
				{ T = 0.13, GunPos = Vector3.new(-0.08, 0.12, 0.03), GunRot = Vector3.new(22, 18, -32), HandPos = Vector3.new(0, -0.03, 0.015) },
				{ T = 0.16, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.21, HandPos = Vector3.new(-0.03, -0.12, 0.04), HandRot = Vector3.new(-18, 0, 0) },
				{ T = 0.36, HandPos = Vector3.new(-0.05, -0.38, 0.1), HandRot = Vector3.new(-40, 10, 0), Mag = "Hand" },
				-- New mag lined up under the well, then pushed in along the grip.
				{ T = 0.56, HandPos = Vector3.new(0.031, -0.22, 0.06), HandRot = Vector3.new(-4, 0, 0) },
				{ T = 0.63, Sound = "MagIn" },
				{ T = 0.65, HandPos = Vector3.new(0.031, -0.075, 0.059), HandRot = V0 },
				{ T = 0.67, Mag = "Gun" },
				{ T = 0.7, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0.031, -0.06, 0.055) },
				{ T = 0.75, HandPos = V0 },
				{ T = 0.8, GunPos = Vector3.new(-0.08, 0.12, 0.03), GunRot = Vector3.new(22, 18, -32) },
				{ T = 1, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0 },
			},
			Empty = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 1 },
				{ T = 0.11, GunPos = Vector3.new(-0.08, 0.12, 0.03), GunRot = Vector3.new(22, 18, -32), HandPos = Vector3.new(0, -0.03, 0.015) },
				{ T = 0.13, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.17, HandPos = Vector3.new(-0.03, -0.12, 0.04), HandRot = Vector3.new(-18, 0, 0) },
				{ T = 0.3, HandPos = Vector3.new(-0.05, -0.38, 0.1), HandRot = Vector3.new(-40, 10, 0), Mag = "Hand" },
				{ T = 0.46, HandPos = Vector3.new(0.031, -0.22, 0.06), HandRot = Vector3.new(-4, 0, 0) },
				{ T = 0.52, Sound = "MagIn" },
				{ T = 0.53, HandPos = Vector3.new(0.031, -0.075, 0.059), HandRot = V0 },
				{ T = 0.55, Mag = "Gun" },
				{ T = 0.57, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0.031, -0.06, 0.055) },
				{ T = 0.61, GunPos = Vector3.new(-0.08, 0.12, 0.03), GunRot = Vector3.new(22, 18, -32), HandPos = V0, HandRot = V0 },
				-- Keep the gun low and turn the slide's left side up, pinch its rear, pull and let it snap forward.
				{ T = 0.7, GunPos = Vector3.new(-0.03, -0.02, 0.02), GunRot = Vector3.new(8, 22, 28), HandPos = Vector3.new(-0.05, 0.22, 0.13), HandRot = Vector3.new(-40, 0, 0) },
				{ T = 0.76, Sound = "SlideBack", HandPos = Vector3.new(-0.05, 0.22, 0.14) },
				{ T = 0.8, HandPos = Vector3.new(-0.05, 0.22, 0.22), Slide = 1 },
				{ T = 0.81, Sound = "SlideRack", Kick = 0.8 },
				{ T = 0.83, Slide = 0 },
				{ T = 0.88, HandPos = Vector3.new(-0.1, 0.18, 0.28), HandRot = Vector3.new(-30, 0, 15) },
				{ T = 1, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0 },
			},
		},
	},

	-- Pump shotgun (Toolbox Ithaca 37). Ten pellets: everything at arm's length dies in one
	-- blast and flies; at range the pellets spread and fall off fast. Loads shell by shell.
	-- 10 x 17 = 170 up close (the zombie has 150); a limb catching 4 pellets comes off.
	Shotgun = {
		DisplayName = "Shotgun",
		Name = "PUMP 12",
		Category = "Shotgun",
		Slot = "Primary",
		Level = 1,
		Role = "CLEARS A DOORWAY",
		WorldLength = 3.3,
		Hold = "Rifle",
		Noise = 0.9,
		ViewModel = "Shotgun",
		FireMode = "Pump",
		TouchFire = "Hip",
		RPM = 80,
		Damage = 17,
		BreakRadius = 0.9,
		Pellets = 10,
		-- Pellet cone around the aim point (degrees), from the hip and aiming down sights.
		PelletSpread = 4.2,
		AimPelletSpread = 3.2,
		HeadMultiplier = 1.5,
		FalloffStart = 10,
		FalloffEnd = 32,
		FalloffMin = 0.3,
		Range = 140,

		MagSize = 6,
		Reserve = 36,
		ReloadStyle = "Shells",
		-- Start: tip the gun to the loading port. Shell: one shell in. End: back on the pump
		-- (EndEmpty also racks the pump to chamber a round). Firing stops it after the shell in hand.
		ShellReload = { StartTime = 0.4, ShellTime = 0.5, EndTime = 0.35, EndEmptyTime = 0.7 },

		Spread = { Hip = 1.2, Aim = 0.6, Move = 1, PerShot = 0, Max = 2, Recover = 6 },
		Recoil = { Pitch = 7.5, Yaw = 2.2, AimMultiplier = 0.8, KickBack = 0.26, KickPitch = 22 },

		AimTime = 0.2,
		AimFov = 62,
		AimSensitivity = 0.75,
		AimDistance = 0.3,
		HipOffset = Vector3.new(0.27, -0.33, -0.44),
		HipAngles = Vector3.new(0, 7, -4),
		LeftShoulder = Vector3.new(-0.5, -1.6, -0.2),
		PumpTravel = 0.16,
		MoveSpeed = 0.95,
		EquipTime = 0.5,

		Feel = {
			Sounds = "Guns/Shotgun",
			Shake = 2.4,
			FovKick = 6,
			-- The blast shoves the shooter back over PushTime seconds.
			PlayerPush = 20,
			PushTime = 0.14,
			FlashSize = 0.9,
			FlashTime = 0.06,
			LightBrightness = 9,
			LightRange = 22,
			MuzzleSparks = 12,
			MuzzleSmoke = 6,

			-- Wide, short and slower than a rifle round, so all ten pellets read as a spray.
			TracerWidth = 0.075,
			TracerLength = 4,
			TracerSpeed = 520,
			TracerColor = Color3.fromRGB(255, 200, 130),

			-- Red hulls drop out of the bottom when the pump comes back.
			EjectOnFire = false,
			CasingSize = Vector3.new(0.075, 0.075, 0.2),
			CasingColor = Color3.fromRGB(150, 32, 26),
			CasingEject = Vector3.new(1.5, -5, 1),

			Knockback = 46,
			KnockLift = 0.22,
			KnockDown = 0.55,
			Stagger = 2.6,
			LimbDamage = 1.5,
			Squash = 0.7,
			HitSnap = 1.4,
			BodyJolt = 0.22,
			BodyShove = 0.8,
			-- Each pellet's share of the instant hit kick.
			PelletImpact = 0.3,
			ExitSpray = 1,

			KillFreeze = 0.035,
			BodyThrow = 64,
			BodyLift = 0.42,
			KillShake = 2.8,
			-- A kill inside Range with at least MinShare of the pellets: the limbs that took
			-- pellets tear off (limb damage x LimbDamage), ExtraLimbs more go with them, the head
			-- bursts if hit, the torso bursts and the body is thrown Throw x harder.
			Splat = { Range = 8, MinShare = 0.5, LimbDamage = 3, ExtraLimbs = 1, Throw = 1.35 },
		},

		-- Pump after each shot (seconds after the shot, then length). Keys as in ReloadAnim;
		-- Pump 0 forward, 1 racked back. Eject drops the spent hull.
		Cycle = {
			Delay = 0.08,
			Time = 0.55,
			Anim = {
				{ T = 0, GunPos = V0, GunRot = V0, Pump = 0 },
				{ T = 0.12, Sound = "PumpBack" },
				{ T = 0.35, Pump = 1, GunPos = Vector3.new(0, -0.01, 0.02), GunRot = Vector3.new(3, 0, -4) },
				{ T = 0.38, Eject = true },
				{ T = 0.5, Sound = "PumpForward" },
				{ T = 0.62, Pump = 0, Kick = 0.3 },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
		},

		-- The left hand rides the pump. HandPos (0, 0.018, 0.451) holds a shell in the loading
		-- port under the receiver. Mag "Hand" shows a shell in the hand, "Gun" pushes it in.
		ReloadAnim = {
			Start = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0 },
				{ T = 0.6, GunPos = Vector3.new(-0.04, 0.07, 0.04), GunRot = Vector3.new(10, 6, 28), HandPos = Vector3.new(0, -0.05, 0.2) },
				{ T = 1, HandPos = Vector3.new(0, -0.08, 0.4) },
			},
			Shell = {
				{ T = 0, GunPos = Vector3.new(-0.04, 0.07, 0.04), GunRot = Vector3.new(10, 6, 28), HandPos = Vector3.new(0, -0.08, 0.4), HandRot = V0 },
				{ T = 0.25, HandPos = Vector3.new(-0.08, -0.32, 0.45), HandRot = Vector3.new(-25, 0, 20) },
				{ T = 0.3, Mag = "Hand" },
				{ T = 0.55, HandPos = Vector3.new(0, -0.06, 0.47), HandRot = Vector3.new(-5, 0, 0) },
				{ T = 0.68, Sound = "ShellIn" },
				{ T = 0.7, HandPos = Vector3.new(0, 0.018, 0.451), HandRot = V0 },
				{ T = 0.78, HandPos = Vector3.new(0, 0.02, 0.38), Mag = "Gun", Kick = 0.15 },
				{ T = 1, HandPos = Vector3.new(0, -0.08, 0.4) },
			},
			End = {
				{ T = 0, GunPos = Vector3.new(-0.04, 0.07, 0.04), GunRot = Vector3.new(10, 6, 28), HandPos = Vector3.new(0, -0.08, 0.4), HandRot = V0 },
				{ T = 0.7, GunPos = V0, GunRot = V0, HandPos = V0 },
				{ T = 1, GunPos = V0 },
			},
			EndEmpty = {
				{ T = 0, GunPos = Vector3.new(-0.04, 0.07, 0.04), GunRot = Vector3.new(10, 6, 28), HandPos = Vector3.new(0, -0.08, 0.4), HandRot = V0, Pump = 0 },
				{ T = 0.35, GunPos = Vector3.new(-0.02, 0.03, 0.02), GunRot = Vector3.new(4, 3, 10), HandPos = V0 },
				{ T = 0.4, Sound = "PumpBack" },
				{ T = 0.5, Pump = 1 },
				{ T = 0.58, Sound = "PumpForward" },
				{ T = 0.66, Pump = 0, Kick = 0.4 },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
		},
	},

	-- Assault rifle (Toolbox AK-47). Full auto, fast and flat, light pushback: bodies
	-- crumple where they stand instead of flying. 28 a bullet: 6 to the body, 2 to the head.
	AK = {
		DisplayName = "AK-47",
		Name = "AK-47",
		Category = "Assault rifle",
		Slot = "Primary",
		Level = 1,
		Role = "HITS HARD, RUNS LOUD",
		WorldLength = 3.1,
		Hold = "Rifle",
		Noise = 1,
		ViewModel = "AK",
		FireMode = "Auto",
		TouchFire = "AimFire",
		RPM = 600,
		Damage = 28,
		BreakRadius = 1.2,
		HeadMultiplier = 2.2,
		FalloffStart = 40,
		FalloffEnd = 120,
		FalloffMin = 0.65,
		Range = 500,

		MagSize = 30,
		Reserve = 180,
		ReloadTime = 2.1,
		ReloadEmptyTime = 2.6,

		Spread = { Hip = 2.4, Aim = 0.3, Move = 1.6, PerShot = 0.32, Max = 5.5, Recover = 8 },
		-- YawBias pulls the climb slightly right, so a long burst has a shape to learn.
		Recoil = { Pitch = 1.05, Yaw = 0.55, YawBias = 0.18, AimMultiplier = 0.6, KickBack = 0.035, KickPitch = 3.5 },

		AimTime = 0.22,
		AimFov = 55,
		AimSensitivity = 0.7,
		AimDistance = 0.53,
		HipOffset = Vector3.new(0.27, -0.33, -0.5),
		HipAngles = Vector3.new(0, 7, -4),
		LeftShoulder = Vector3.new(-0.5, -1.5, -0.15),
		-- The bolt carrier and charging handle run back on every shot.
		SlideTravel = 0.07,
		MoveSpeed = 0.94,
		EquipTime = 0.5,

		Feel = {
			Sounds = "Guns/AK",
			Shake = 0.38,
			FovKick = 0.7,
			PlayerPush = 0.8,
			FlashSize = 0.55,
			FlashTime = 0.035,
			LightBrightness = 7,
			LightRange = 18,
			MuzzleSparks = 3,
			MuzzleSmoke = 1,

			TracerWidth = 0.055,
			TracerLength = 18,
			TracerSpeed = 1600,
			TracerColor = Color3.fromRGB(255, 215, 150),

			CasingSize = Vector3.new(0.06, 0.06, 0.2),
			CasingColor = Color3.fromRGB(150, 132, 84),
			CasingEject = Vector3.new(9, 5, 1.5),

			Knockback = 4,
			Stagger = 0.8,
			LimbDamage = 1,
			Squash = 0.86,
			HitSnap = 0.85,
			BodyJolt = 0.16,
			BodyShove = 0.3,
			ExitSpray = 4,

			KillFreeze = 0.03,
			BodyThrow = 16,
			BodyLift = 0.12,
			KillShake = 0.9,
		},

		-- The mag well sits under the receiver: HandPos (0.001, -0.294, 0.222) is a seated mag.
		-- On an empty mag the left hand reaches over to the charging handle on the right.
		ReloadAnim = {
			Tactical = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.12, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28), HandPos = Vector3.new(0, -0.12, 0.15) },
				{ T = 0.2, HandPos = Vector3.new(0.001, -0.26, 0.21) },
				{ T = 0.25, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.42, HandPos = Vector3.new(-0.08, -0.42, 0.2), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.44, Mag = "Hand" },
				{ T = 0.62, HandPos = Vector3.new(0.001, -0.36, 0.18), HandRot = Vector3.new(-12, 0, 0) },
				{ T = 0.68, Sound = "MagIn" },
				{ T = 0.72, HandPos = Vector3.new(0.001, -0.294, 0.222), HandRot = V0 },
				{ T = 0.73, Mag = "Gun" },
				{ T = 0.76, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0.001, -0.28, 0.22) },
				{ T = 0.84, HandPos = V0, HandRot = V0 },
				{ T = 0.86, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28) },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
			Empty = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.1, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28), HandPos = Vector3.new(0, -0.12, 0.15) },
				{ T = 0.16, HandPos = Vector3.new(0.001, -0.26, 0.21) },
				{ T = 0.2, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.34, HandPos = Vector3.new(-0.08, -0.42, 0.2), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.36, Mag = "Hand" },
				{ T = 0.5, HandPos = Vector3.new(0.001, -0.36, 0.18), HandRot = Vector3.new(-12, 0, 0) },
				{ T = 0.54, Sound = "MagIn" },
				{ T = 0.57, HandPos = Vector3.new(0.001, -0.294, 0.222), HandRot = V0 },
				{ T = 0.58, Mag = "Gun" },
				{ T = 0.6, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0.001, -0.28, 0.22) },
				-- Roll the right side up, reach over and rack the charging handle.
				{ T = 0.68, GunPos = Vector3.new(-0.02, 0.04, 0.03), GunRot = Vector3.new(6, -8, 22), HandPos = Vector3.new(0.06, 0.1, 0.2), HandRot = Vector3.new(-20, 0, -70) },
				{ T = 0.73, Sound = "BoltBack", HandPos = Vector3.new(0.06, 0.09, 0.21) },
				{ T = 0.77, HandPos = Vector3.new(0.06, 0.09, 0.28), Slide = 1 },
				{ T = 0.78, Sound = "BoltRelease", Kick = 0.8 },
				{ T = 0.8, Slide = 0, HandPos = Vector3.new(0.09, 0.14, 0.32) },
				{ T = 0.88, HandPos = V0, HandRot = V0 },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
		},
	},

	-- Bolt-action sniper (Toolbox scoped Kar98k). One shot kills (175 against 150) and goes
	-- through up to 3 zombies; any limb it hits comes off; a headshot bursts the head.
	-- Inaccurate from the hip; the scope is dead on.
	Sniper = {
		DisplayName = "Sniper",
		Name = "BOLT .308",
		Category = "Sniper",
		Slot = "Primary",
		Level = 10,
		Role = "PIERCES A WHOLE LINE",
		WorldLength = 3.7,
		Hold = "Rifle",
		Noise = 0.95,
		ViewModel = "Sniper",
		FireMode = "Bolt",
		TouchFire = "AimRelease",
		RPM = 50,
		Damage = 175,
		BreakRadius = 2.6,
		HeadMultiplier = 3,
		FalloffStart = 600,
		FalloffEnd = 1000,
		FalloffMin = 1,
		Range = 1200,
		-- Each zombie the round passes through keeps DamageKeep of the damage for the next.
		Penetration = { Count = 3, DamageKeep = 0.75 },

		MagSize = 5,
		Reserve = 30,
		ReloadTime = 2.6,
		ReloadEmptyTime = 2.6,

		Spread = { Hip = 5, Aim = 0, Move = 3, PerShot = 0, Max = 7, Recover = 10 },
		Recoil = { Pitch = 6.5, Yaw = 1.2, AimMultiplier = 0.75, KickBack = 0.2, KickPitch = 16 },

		AimTime = 0.28,
		AimFov = 50,
		AimSensitivity = 0.6,
		AimDistance = 0.31,
		HipOffset = Vector3.new(0.27, -0.33, -0.44),
		HipAngles = Vector3.new(0, 7, -4),
		LeftShoulder = Vector3.new(-0.5, -1.6, -0.2),
		-- Bolt: Slide pulls it back SlideTravel studs, BoltLift turns the handle up this far.
		SlideTravel = 0.18,
		SlideKick = false,
		BoltLiftAngle = 80,
		MoveSpeed = 0.88,
		EquipTime = 0.6,
		-- Aiming past ScopeAt shows the scope view: FOV, look speed, idle sway (degrees) and
		-- how long Shift holds the breath steady before it runs out.
		Scope = { At = 0.92, Fov = 14, Sensitivity = 0.22, Sway = 0.35, HoldBreath = 4, BreathRecover = 2.5 },

		Feel = {
			Sounds = "Guns/Sniper",
			Shake = 1.8,
			FovKick = 3.5,
			PlayerPush = 6,
			PushTime = 0.08,
			FlashSize = 1,
			FlashTime = 0.06,
			LightBrightness = 10,
			LightRange = 26,
			MuzzleSparks = 10,
			MuzzleSmoke = 8,

			TracerWidth = 0.09,
			TracerLength = 40,
			TracerSpeed = 3200,
			TracerColor = Color3.fromRGB(255, 235, 190),

			EjectOnFire = false,
			CasingSize = Vector3.new(0.07, 0.07, 0.26),
			CasingColor = Color3.fromRGB(196, 150, 72),
			CasingEject = Vector3.new(6, 4, 1),

			Knockback = 22,
			KnockLift = 0.12,
			Stagger = 2.2,
			LimbDamage = 1,
			Squash = 0.7,
			HitSnap = 2.2,
			BodyJolt = 0.6,
			BodyShove = 1.2,
			ExitSpray = 14,

			KillFreeze = 0.1,
			BodyThrow = 42,
			BodyLift = 0.28,
			KillShake = 2.2,
			HeadPop = true,
		},

		-- After each shot: the right hand leaves the grip (RightHand 1), lifts and pulls the
		-- bolt, the case flies, then the bolt goes home.
		Cycle = {
			Delay = 0.2,
			Time = 0.9,
			Anim = {
				{ T = 0, RightHand = 0, BoltLift = 0, Slide = 0, GunPos = V0, GunRot = V0 },
				{ T = 0.14, RightHand = 1, GunPos = Vector3.new(0.01, 0.02, 0.02), GunRot = Vector3.new(2, 0, 8) },
				{ T = 0.2, Sound = "BoltUp" },
				{ T = 0.26, BoltLift = 1 },
				{ T = 0.32, Sound = "BoltBack" },
				{ T = 0.44, Slide = 1 },
				{ T = 0.46, Eject = true },
				{ T = 0.58, Sound = "BoltForward" },
				{ T = 0.62, Slide = 0 },
				{ T = 0.7, Sound = "BoltDown", Kick = 0.3 },
				{ T = 0.74, BoltLift = 0 },
				{ T = 0.9, RightHand = 0, GunPos = V0, GunRot = V0 },
			},
		},

		-- Bolt open, rounds pressed in from above with the left hand, bolt home.
		ReloadAnim = {
			Tactical = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, RightHand = 0, BoltLift = 0, Slide = 0 },
				{ T = 0.08, RightHand = 1, GunPos = Vector3.new(-0.03, 0.06, 0.04), GunRot = Vector3.new(8, 8, 16) },
				{ T = 0.1, Sound = "BoltUp" },
				{ T = 0.14, BoltLift = 1 },
				{ T = 0.18, Sound = "BoltBack" },
				{ T = 0.24, Slide = 1 },
				{ T = 0.3, HandPos = Vector3.new(0, 0.25, 0.47), HandRot = Vector3.new(-50, 0, 0) },
				{ T = 0.36, Sound = "RoundIn" },
				{ T = 0.38, HandPos = Vector3.new(0, 0.16, 0.47) },
				{ T = 0.44, HandPos = Vector3.new(0, 0.25, 0.46) },
				{ T = 0.48, Sound = "RoundIn" },
				{ T = 0.5, HandPos = Vector3.new(0, 0.16, 0.47) },
				{ T = 0.56, HandPos = Vector3.new(0, 0.25, 0.46) },
				{ T = 0.6, Sound = "RoundIn" },
				{ T = 0.62, HandPos = Vector3.new(0, 0.16, 0.47) },
				{ T = 0.68, HandPos = Vector3.new(0, 0.26, 0.45) },
				{ T = 0.76, HandPos = V0, HandRot = V0 },
				{ T = 0.8, Sound = "BoltForward" },
				{ T = 0.84, Slide = 0 },
				{ T = 0.88, Sound = "BoltDown", Kick = 0.4 },
				{ T = 0.9, BoltLift = 0 },
				{ T = 0.96, RightHand = 0, GunPos = V0, GunRot = V0 },
				{ T = 1, GunPos = V0 },
			},
		},
	},

	-- Menu revamp guns (GUNS, 3 Nov 2026). The MP5 and M4 use the AK's reload (keys moved to their own mag
	-- wells and charging handles) and the Hand Cannon the Pistol's. Their sound banks are retuned copies.
	MP5 = {
		DisplayName = "MP5",
		Name = "MP5",
		Category = "SMG",
		Slot = "Primary",
		Level = 2,
		Role = "QUICK AND QUIET",
		WorldLength = 2.35,
		Hold = "Rifle",
		Noise = 0.45,
		ViewModel = "MP5",
		FireMode = "Auto",
		TouchFire = "AimFire",
		RPM = 800,
		Damage = 20,
		BreakRadius = 1,
		HeadMultiplier = 2,
		FalloffStart = 22,
		FalloffEnd = 70,
		FalloffMin = 0.5,
		Range = 350,

		MagSize = 30,
		Reserve = 210,
		ReloadTime = 1.9,
		ReloadEmptyTime = 2.35,

		Spread = { Hip = 2, Aim = 0.4, Move = 1.1, PerShot = 0.22, Max = 4.8, Recover = 9 },
		Recoil = { Pitch = 0.7, Yaw = 0.45, YawBias = 0.1, AimMultiplier = 0.6, KickBack = 0.025, KickPitch = 2.4 },

		AimTime = 0.18,
		AimFov = 58,
		AimSensitivity = 0.72,
		-- The drum rear sight sits near the back of the gun, so the eye is closer to it than on the AK.
		AimDistance = 0.34,
		HipOffset = Vector3.new(0.27, -0.31, -0.5),
		HipAngles = Vector3.new(0, 7, -4),
		LeftShoulder = Vector3.new(-0.5, -1.5, -0.15),
		-- The cocking handle twitches on each shot (it does not run with the bolt on the real gun).
		SlideTravel = 0.035,
		MoveSpeed = 0.97,
		EquipTime = 0.42,

		Feel = {
			Sounds = "Guns/MP5",
			Shake = 0.28,
			FovKick = 0.5,
			PlayerPush = 0.5,
			FlashSize = 0.4,
			FlashTime = 0.03,
			LightBrightness = 5,
			LightRange = 14,
			MuzzleSparks = 2,
			MuzzleSmoke = 1,

			TracerWidth = 0.05,
			TracerLength = 14,
			TracerSpeed = 1300,
			TracerColor = Color3.fromRGB(255, 215, 150),

			CasingSize = Vector3.new(0.06, 0.06, 0.15),
			CasingColor = Color3.fromRGB(196, 150, 72),
			CasingEject = Vector3.new(8, 5, 1.5),

			Knockback = 3,
			Stagger = 0.7,
			LimbDamage = 0.9,
			Squash = 0.88,
			HitSnap = 0.75,
			BodyJolt = 0.13,
			BodyShove = 0.25,
			ExitSpray = 3,

			KillFreeze = 0.025,
			BodyThrow = 14,
			BodyLift = 0.1,
			KillShake = 0.8,
		},

		-- HandPos (0, -0.283, 0.224) is a seated mag; the cocking handle sits up front on the tube.
		ReloadAnim = {
			Tactical = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.12, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28), HandPos = Vector3.new(0, -0.114, 0.151) },
				{ T = 0.2, HandPos = Vector3.new(0, -0.248, 0.212) },
				{ T = 0.25, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.42, HandPos = Vector3.new(-0.08, -0.42, 0.2), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.44, Mag = "Hand" },
				{ T = 0.62, HandPos = Vector3.new(0, -0.348, 0.182), HandRot = Vector3.new(-12, 0, 0) },
				{ T = 0.68, Sound = "MagIn" },
				{ T = 0.72, HandPos = Vector3.new(0, -0.283, 0.224), HandRot = V0 },
				{ T = 0.73, Mag = "Gun" },
				{ T = 0.76, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0, -0.269, 0.222) },
				{ T = 0.84, HandPos = V0, HandRot = V0 },
				{ T = 0.86, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28) },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
			Empty = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.1, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28), HandPos = Vector3.new(0, -0.114, 0.151) },
				{ T = 0.16, HandPos = Vector3.new(0, -0.248, 0.212) },
				{ T = 0.2, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.34, HandPos = Vector3.new(-0.08, -0.42, 0.2), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.36, Mag = "Hand" },
				{ T = 0.5, HandPos = Vector3.new(0, -0.348, 0.182), HandRot = Vector3.new(-12, 0, 0) },
				{ T = 0.54, Sound = "MagIn" },
				{ T = 0.57, HandPos = Vector3.new(0, -0.283, 0.224), HandRot = V0 },
				{ T = 0.58, Mag = "Gun" },
				{ T = 0.6, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0, -0.269, 0.222) },
				-- Roll the gun, reach up to the cocking handle, pull it back and slap it home.
				{ T = 0.68, GunPos = Vector3.new(-0.02, 0.04, 0.03), GunRot = Vector3.new(6, -8, 22), HandPos = Vector3.new(0.05, 0.133, 0.342), HandRot = Vector3.new(-20, 0, -70) },
				{ T = 0.73, Sound = "BoltBack", HandPos = Vector3.new(0.05, 0.123, 0.352) },
				{ T = 0.77, HandPos = Vector3.new(0.05, 0.123, 0.422), Slide = 1 },
				{ T = 0.78, Sound = "BoltRelease", Kick = 0.8 },
				{ T = 0.8, Slide = 0, HandPos = Vector3.new(0.08, 0.173, 0.462) },
				{ T = 0.88, HandPos = V0, HandRot = V0 },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
		},
	},

	M4 = {
		DisplayName = "M4",
		Name = "M4",
		Category = "Assault rifle",
		Slot = "Primary",
		Level = 4,
		Role = "STEADY AND QUIET",
		WorldLength = 2.85,
		Hold = "Rifle",
		Noise = 0.75,
		ViewModel = "M4",
		FireMode = "Auto",
		TouchFire = "AimFire",
		RPM = 700,
		Damage = 24,
		BreakRadius = 1.1,
		HeadMultiplier = 2.2,
		FalloffStart = 45,
		FalloffEnd = 140,
		FalloffMin = 0.65,
		Range = 550,

		MagSize = 30,
		Reserve = 180,
		ReloadTime = 2,
		ReloadEmptyTime = 2.5,

		Spread = { Hip = 2.2, Aim = 0.22, Move = 1.4, PerShot = 0.24, Max = 4.6, Recover = 9 },
		Recoil = { Pitch = 0.75, Yaw = 0.35, YawBias = 0.1, AimMultiplier = 0.55, KickBack = 0.03, KickPitch = 2.8 },

		AimTime = 0.22,
		-- Aimed through the red dot (AimPoint is the lens centre), a little more zoom than iron sights.
		AimFov = 52,
		AimSensitivity = 0.66,
		AimDistance = 0.42,
		HipOffset = Vector3.new(0.27, -0.33, -0.5),
		HipAngles = Vector3.new(0, 7, -4),
		LeftShoulder = Vector3.new(-0.5, -1.5, -0.15),
		-- The bolt and charging handle nudge back on each shot.
		SlideTravel = 0.03,
		MoveSpeed = 0.95,
		EquipTime = 0.5,

		Feel = {
			Sounds = "Guns/M4",
			Shake = 0.32,
			FovKick = 0.6,
			PlayerPush = 0.65,
			FlashSize = 0.5,
			FlashTime = 0.035,
			LightBrightness = 6,
			LightRange = 16,
			MuzzleSparks = 3,
			MuzzleSmoke = 1,

			TracerWidth = 0.05,
			TracerLength = 18,
			TracerSpeed = 1700,
			TracerColor = Color3.fromRGB(255, 215, 150),

			CasingSize = Vector3.new(0.05, 0.05, 0.18),
			CasingColor = Color3.fromRGB(196, 150, 72),
			CasingEject = Vector3.new(9, 5, 1.5),

			Knockback = 3.5,
			Stagger = 0.75,
			LimbDamage = 1,
			Squash = 0.87,
			HitSnap = 0.8,
			BodyJolt = 0.15,
			BodyShove = 0.28,
			ExitSpray = 4,

			KillFreeze = 0.03,
			BodyThrow = 15,
			BodyLift = 0.12,
			KillShake = 0.85,
		},

		-- HandPos (0, -0.264, 0.239) is a seated mag; the left hand rests on the handguard just behind the
		-- foregrip. On an empty mag it reaches back to the T-handle over the grip and pulls it.
		ReloadAnim = {
			Tactical = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.12, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28), HandPos = Vector3.new(0, -0.105, 0.158) },
				{ T = 0.2, HandPos = Vector3.new(0, -0.23, 0.227) },
				{ T = 0.25, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.42, HandPos = Vector3.new(-0.08, -0.42, 0.2), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.44, Mag = "Hand" },
				{ T = 0.62, HandPos = Vector3.new(0, -0.33, 0.197), HandRot = Vector3.new(-12, 0, 0) },
				{ T = 0.68, Sound = "MagIn" },
				{ T = 0.72, HandPos = Vector3.new(0, -0.264, 0.239), HandRot = V0 },
				{ T = 0.73, Mag = "Gun" },
				{ T = 0.76, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0, -0.25, 0.237) },
				{ T = 0.84, HandPos = V0, HandRot = V0 },
				{ T = 0.86, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28) },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
			Empty = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.1, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28), HandPos = Vector3.new(0, -0.105, 0.158) },
				{ T = 0.16, HandPos = Vector3.new(0, -0.23, 0.227) },
				{ T = 0.2, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.34, HandPos = Vector3.new(-0.08, -0.42, 0.2), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.36, Mag = "Hand" },
				{ T = 0.5, HandPos = Vector3.new(0, -0.33, 0.197), HandRot = Vector3.new(-12, 0, 0) },
				{ T = 0.54, Sound = "MagIn" },
				{ T = 0.57, HandPos = Vector3.new(0, -0.264, 0.239), HandRot = V0 },
				{ T = 0.58, Mag = "Gun" },
				{ T = 0.6, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0, -0.25, 0.237) },
				{ T = 0.68, GunPos = Vector3.new(-0.02, 0.03, 0.03), GunRot = Vector3.new(10, -4, 10), HandPos = Vector3.new(0.03, 0.12, 0.519), HandRot = Vector3.new(-40, 0, -20) },
				{ T = 0.73, Sound = "BoltBack", HandPos = Vector3.new(0.03, 0.11, 0.529) },
				{ T = 0.77, HandPos = Vector3.new(0.03, 0.11, 0.599), Slide = 1 },
				{ T = 0.78, Sound = "BoltRelease", Kick = 0.8 },
				{ T = 0.8, Slide = 0, HandPos = Vector3.new(0.06, 0.16, 0.639) },
				{ T = 0.88, HandPos = V0, HandRot = V0 },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
		},
	},

	HandCannon = {
		DisplayName = "Hand Cannon",
		Name = "HAND CANNON",
		Category = "Pistol",
		Slot = "Secondary",
		Level = 6,
		Role = "EVERY ROUND COUNTS",
		WorldLength = 1.77,
		Hold = "Pistol",
		Noise = 0.85,
		ViewModel = "HandCannon",
		FireMode = "Semi",
		TouchFire = "Hip",
		RPM = 170,
		Damage = 72,
		BreakRadius = 1.8,
		HeadMultiplier = 2.4,
		FalloffStart = 40,
		FalloffEnd = 110,
		FalloffMin = 0.6,
		Range = 400,

		MagSize = 7,
		Reserve = 35,
		ReloadTime = 1.8,
		ReloadEmptyTime = 2.15,

		Spread = { Hip = 1.8, Aim = 0.15, Move = 1.4, PerShot = 1.6, Max = 5, Recover = 6 },
		Recoil = { Pitch = 5.2, Yaw = 1.4, AimMultiplier = 0.65, KickBack = 0.16, KickPitch = 18 },

		AimTime = 0.2,
		AimFov = 58,
		AimSensitivity = 0.7,
		AimDistance = 0.7,
		HipOffset = Vector3.new(0.22, -0.28, -0.62),
		HipAngles = Vector3.new(0, 3, 0),
		SlideTravel = 0.12,
		LockOnEmpty = true,
		MoveSpeed = 1,
		EquipTime = 0.45,

		Feel = {
			Sounds = "Guns/HandCannon",
			Shake = 1.1,
			FovKick = 2.4,
			PlayerPush = 4,
			FlashSize = 0.6,
			FlashTime = 0.06,
			LightBrightness = 8,
			LightRange = 18,
			MuzzleSparks = 6,
			MuzzleSmoke = 3,

			TracerWidth = 0.08,
			TracerLength = 12,
			TracerSpeed = 1000,
			TracerColor = Color3.fromRGB(255, 205, 140),

			CasingSize = Vector3.new(0.08, 0.08, 0.19),
			CasingColor = Color3.fromRGB(196, 150, 72),
			CasingEject = Vector3.new(8, 6, 1.5),

			Knockback = 12,
			Stagger = 1.4,
			LimbDamage = 1.3,
			Squash = 0.76,
			HitSnap = 1.3,
			BodyJolt = 0.3,
			BodyShove = 0.7,
			ExitSpray = 5,

			KillFreeze = 0.09,
			BodyThrow = 45,
			BodyLift = 0.4,
			KillShake = 1.5,
		},

		-- The Pistol's reload on a bigger frame: HandPos (0.031, -0.149, 0.055) is a seated mag.
		ReloadAnim = {
			Tactical = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.13, GunPos = Vector3.new(-0.08, 0.12, 0.03), GunRot = Vector3.new(22, 18, -32), HandPos = Vector3.new(0, -0.067, 0.013) },
				{ T = 0.16, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.21, HandPos = Vector3.new(-0.03, -0.157, 0.038), HandRot = Vector3.new(-18, 0, 0) },
				{ T = 0.36, HandPos = Vector3.new(-0.05, -0.38, 0.1), HandRot = Vector3.new(-40, 10, 0), Mag = "Hand" },
				{ T = 0.56, HandPos = Vector3.new(0.031, -0.294, 0.057), HandRot = Vector3.new(-4, 0, 0) },
				{ T = 0.63, Sound = "MagIn" },
				{ T = 0.65, HandPos = Vector3.new(0.031, -0.149, 0.055), HandRot = V0 },
				{ T = 0.67, Mag = "Gun" },
				{ T = 0.7, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0.031, -0.134, 0.052) },
				{ T = 0.75, HandPos = V0 },
				{ T = 0.8, GunPos = Vector3.new(-0.08, 0.12, 0.03), GunRot = Vector3.new(22, 18, -32) },
				{ T = 1, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0 },
			},
			Empty = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 1 },
				{ T = 0.11, GunPos = Vector3.new(-0.08, 0.12, 0.03), GunRot = Vector3.new(22, 18, -32), HandPos = Vector3.new(0, -0.067, 0.013) },
				{ T = 0.13, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.17, HandPos = Vector3.new(-0.03, -0.157, 0.038), HandRot = Vector3.new(-18, 0, 0) },
				{ T = 0.3, HandPos = Vector3.new(-0.05, -0.38, 0.1), HandRot = Vector3.new(-40, 10, 0), Mag = "Hand" },
				{ T = 0.46, HandPos = Vector3.new(0.031, -0.294, 0.057), HandRot = Vector3.new(-4, 0, 0) },
				{ T = 0.52, Sound = "MagIn" },
				{ T = 0.53, HandPos = Vector3.new(0.031, -0.149, 0.055), HandRot = V0 },
				{ T = 0.55, Mag = "Gun" },
				{ T = 0.57, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0.031, -0.134, 0.052) },
				{ T = 0.61, GunPos = Vector3.new(-0.08, 0.12, 0.03), GunRot = Vector3.new(22, 18, -32), HandPos = V0, HandRot = V0 },
				{ T = 0.7, GunPos = Vector3.new(-0.03, -0.02, 0.02), GunRot = Vector3.new(8, 22, 28), HandPos = Vector3.new(-0.05, 0.24, 0.16), HandRot = Vector3.new(-40, 0, 0) },
				{ T = 0.76, Sound = "SlideBack", HandPos = Vector3.new(-0.05, 0.24, 0.17) },
				{ T = 0.8, HandPos = Vector3.new(-0.05, 0.24, 0.25), Slide = 1 },
				{ T = 0.81, Sound = "SlideRack", Kick = 0.8 },
				{ T = 0.83, Slide = 0 },
				{ T = 0.88, HandPos = Vector3.new(-0.1, 0.2, 0.31), HandRot = Vector3.new(-30, 0, 15) },
				{ T = 1, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0 },
			},
		},
	},

	SR25 = {
		DisplayName = "SR-25",
		Name = "SR-25",
		Category = "Marksman rifle",
		Slot = "Primary",
		Level = 7,
		Role = "LONG REACH, NO BOLT",
		WorldLength = 3.5,
		Hold = "Rifle",
		Noise = 0.9,
		ViewModel = "SR25",
		FireMode = "Semi",
		TouchFire = "AimRelease",
		RPM = 240,
		Damage = 70,
		BreakRadius = 1.8,
		HeadMultiplier = 2.6,
		FalloffStart = 200,
		FalloffEnd = 500,
		FalloffMin = 0.8,
		Range = 900,
		Penetration = { Count = 1, DamageKeep = 0.6 },

		MagSize = 10,
		Reserve = 60,
		ReloadTime = 2.4,
		ReloadEmptyTime = 2.9,

		Spread = { Hip = 3.5, Aim = 0.05, Move = 2.2, PerShot = 0.6, Max = 6, Recover = 8 },
		Recoil = { Pitch = 3.2, Yaw = 0.8, YawBias = 0.1, AimMultiplier = 0.7, KickBack = 0.1, KickPitch = 9 },

		AimTime = 0.26,
		AimFov = 50,
		AimSensitivity = 0.62,
		AimDistance = 0.3,
		HipOffset = Vector3.new(0.27, -0.33, -0.46),
		HipAngles = Vector3.new(0, 7, -4),
		LeftShoulder = Vector3.new(-0.5, -1.55, -0.18),
		SlideTravel = 0.05,
		MoveSpeed = 0.9,
		EquipTime = 0.55,
		-- A lower-power scope than the bolt gun's.
		Scope = { At = 0.92, Fov = 24, Sensitivity = 0.32, Sway = 0.25, HoldBreath = 4, BreathRecover = 2.5 },

		Feel = {
			Sounds = "Guns/SR25",
			Shake = 0.7,
			FovKick = 1.6,
			PlayerPush = 2.5,
			FlashSize = 0.6,
			FlashTime = 0.05,
			LightBrightness = 8,
			LightRange = 18,
			MuzzleSparks = 4,
			MuzzleSmoke = 2,

			TracerWidth = 0.07,
			TracerLength = 24,
			TracerSpeed = 2200,
			TracerColor = Color3.fromRGB(255, 215, 150),

			CasingSize = Vector3.new(0.07, 0.07, 0.22),
			CasingColor = Color3.fromRGB(196, 150, 72),
			CasingEject = Vector3.new(9, 5, 1.5),

			Knockback = 9,
			Stagger = 1.3,
			LimbDamage = 1.3,
			Squash = 0.78,
			HitSnap = 1.2,
			BodyJolt = 0.28,
			BodyShove = 0.6,
			ExitSpray = 6,

			KillFreeze = 0.08,
			BodyThrow = 40,
			BodyLift = 0.35,
			KillShake = 1.3,
		},

		-- The M4's motions on a longer gun: HandPos (0, -0.204, 0.301) is a seated mag; the T-handle sits over the grip.
		ReloadAnim = {
			Tactical = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.12, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28), HandPos = Vector3.new(0, -0.075, 0.19) },
				{ T = 0.2, HandPos = Vector3.new(0, -0.169, 0.289) },
				{ T = 0.25, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.42, HandPos = Vector3.new(-0.08, -0.42, 0.2), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.44, Mag = "Hand" },
				{ T = 0.62, HandPos = Vector3.new(0, -0.269, 0.259), HandRot = Vector3.new(-12, 0, 0) },
				{ T = 0.68, Sound = "MagIn" },
				{ T = 0.72, HandPos = Vector3.new(0, -0.204, 0.301), HandRot = V0 },
				{ T = 0.73, Mag = "Gun" },
				{ T = 0.76, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0, -0.189, 0.299) },
				{ T = 0.84, HandPos = V0, HandRot = V0 },
				{ T = 0.86, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28) },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
			Empty = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.1, GunPos = Vector3.new(-0.06, 0.1, 0.04), GunRot = Vector3.new(18, 14, -28), HandPos = Vector3.new(0, -0.075, 0.19) },
				{ T = 0.16, HandPos = Vector3.new(0, -0.169, 0.289) },
				{ T = 0.2, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.34, HandPos = Vector3.new(-0.08, -0.42, 0.2), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.36, Mag = "Hand" },
				{ T = 0.5, HandPos = Vector3.new(0, -0.269, 0.259), HandRot = Vector3.new(-12, 0, 0) },
				{ T = 0.54, Sound = "MagIn" },
				{ T = 0.57, HandPos = Vector3.new(0, -0.204, 0.301), HandRot = V0 },
				{ T = 0.58, Mag = "Gun" },
				{ T = 0.6, Sound = "MagSeat", Kick = 0.6, HandPos = Vector3.new(0, -0.189, 0.299) },
				{ T = 0.68, GunPos = Vector3.new(-0.02, 0.03, 0.03), GunRot = Vector3.new(10, -4, 10), HandPos = Vector3.new(0.03, 0.12, 0.6), HandRot = Vector3.new(-40, 0, -20) },
				{ T = 0.73, Sound = "BoltBack", HandPos = Vector3.new(0.03, 0.11, 0.61) },
				{ T = 0.77, HandPos = Vector3.new(0.03, 0.11, 0.68), Slide = 1 },
				{ T = 0.78, Sound = "BoltRelease", Kick = 0.8 },
				{ T = 0.8, Slide = 0, HandPos = Vector3.new(0.06, 0.16, 0.72) },
				{ T = 0.88, HandPos = V0, HandRot = V0 },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
		},
	},

	M60 = {
		DisplayName = "M60",
		Name = "M60",
		Category = "Machine gun",
		Slot = "Primary",
		Level = 13,
		Role = "HOLDS A WHOLE STREET",
		WorldLength = 3.75,
		Hold = "Rifle",
		Noise = 1,
		ViewModel = "M60",
		FireMode = "Auto",
		TouchFire = "AimFire",
		RPM = 550,
		Damage = 30,
		BreakRadius = 1.5,
		HeadMultiplier = 2,
		FalloffStart = 50,
		FalloffEnd = 150,
		FalloffMin = 0.65,
		Range = 600,

		MagSize = 100,
		Reserve = 300,
		ReloadTime = 4.2,
		ReloadEmptyTime = 4.8,

		Spread = { Hip = 3.4, Aim = 0.5, Move = 2.4, PerShot = 0.28, Max = 6.5, Recover = 6 },
		Recoil = { Pitch = 1.2, Yaw = 0.7, YawBias = 0.2, AimMultiplier = 0.65, KickBack = 0.04, KickPitch = 3.6 },

		AimTime = 0.32,
		AimFov = 55,
		AimSensitivity = 0.62,
		AimDistance = 0.45,
		HipOffset = Vector3.new(0.28, -0.36, -0.5),
		HipAngles = Vector3.new(0, 7, -4),
		LeftShoulder = Vector3.new(-0.5, -1.55, -0.15),
		SlideTravel = 0.04,
		MoveSpeed = 0.82,
		EquipTime = 0.8,

		Feel = {
			Sounds = "Guns/M60",
			Shake = 0.45,
			FovKick = 0.8,
			PlayerPush = 1,
			FlashSize = 0.6,
			FlashTime = 0.035,
			LightBrightness = 8,
			LightRange = 20,
			MuzzleSparks = 3,
			MuzzleSmoke = 2,

			TracerWidth = 0.06,
			TracerLength = 20,
			TracerSpeed = 1600,
			TracerColor = Color3.fromRGB(255, 215, 150),

			CasingSize = Vector3.new(0.07, 0.07, 0.22),
			CasingColor = Color3.fromRGB(196, 150, 72),
			CasingEject = Vector3.new(6, -2, 1.5),

			Knockback = 5,
			Stagger = 0.9,
			LimbDamage = 1.1,
			Squash = 0.84,
			HitSnap = 0.9,
			BodyJolt = 0.18,
			BodyShove = 0.35,
			ExitSpray = 4,

			KillFreeze = 0.035,
			BodyThrow = 20,
			BodyLift = 0.15,
			KillShake = 1,
		},

		-- Box swap: the ammo box hangs on the left of the receiver with the belt running into the feed tray. The left
		-- hand pulls the box (Mag = "Drop"), fetches a new one from the belt pouch, seats it at HandPos (-0.153, -0.139,
		-- 0.419), then slaps the feed cover shut. On an empty gun it also pulls the charging handle on the right.
		ReloadAnim = {
			Tactical = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.08, GunPos = Vector3.new(-0.05, 0.08, 0.04), GunRot = Vector3.new(12, 16, 20), HandPos = Vector3.new(-0.08, -0.06, 0.28) },
				{ T = 0.14, HandPos = Vector3.new(-0.153, -0.12, 0.41), HandRot = Vector3.new(0, 0, 20) },
				{ T = 0.18, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.34, HandPos = Vector3.new(-0.2, -0.42, 0.35), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.37, Mag = "Hand" },
				{ T = 0.52, HandPos = Vector3.new(-0.153, -0.24, 0.4), HandRot = Vector3.new(-8, 0, 10) },
				{ T = 0.56, Sound = "MagIn" },
				{ T = 0.6, HandPos = Vector3.new(-0.153, -0.139, 0.419), HandRot = V0 },
				{ T = 0.61, Mag = "Gun" },
				{ T = 0.63, Sound = "MagSeat", Kick = 0.5, HandPos = Vector3.new(-0.15, -0.13, 0.415) },
				-- Up to the feed cover and slap it shut.
				{ T = 0.74, HandPos = Vector3.new(-0.008, 0.24, 0.6), HandRot = Vector3.new(-50, 0, 0) },
				{ T = 0.79, HandPos = Vector3.new(-0.008, 0.19, 0.619) },
				{ T = 0.8, Sound = "BoltRelease", Kick = 0.7 },
				{ T = 0.88, HandPos = V0, HandRot = V0 },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
			Empty = {
				{ T = 0, GunPos = V0, GunRot = V0, HandPos = V0, HandRot = V0, Slide = 0 },
				{ T = 0.07, GunPos = Vector3.new(-0.05, 0.08, 0.04), GunRot = Vector3.new(12, 16, 20), HandPos = Vector3.new(-0.08, -0.06, 0.28) },
				{ T = 0.12, HandPos = Vector3.new(-0.153, -0.12, 0.41), HandRot = Vector3.new(0, 0, 20) },
				{ T = 0.15, Sound = "MagOut", Mag = "Drop" },
				{ T = 0.29, HandPos = Vector3.new(-0.2, -0.42, 0.35), HandRot = Vector3.new(-30, 10, 0) },
				{ T = 0.31, Mag = "Hand" },
				{ T = 0.44, HandPos = Vector3.new(-0.153, -0.24, 0.4), HandRot = Vector3.new(-8, 0, 10) },
				{ T = 0.47, Sound = "MagIn" },
				{ T = 0.5, HandPos = Vector3.new(-0.153, -0.139, 0.419), HandRot = V0 },
				{ T = 0.51, Mag = "Gun" },
				{ T = 0.53, Sound = "MagSeat", Kick = 0.5, HandPos = Vector3.new(-0.15, -0.13, 0.415) },
				{ T = 0.62, HandPos = Vector3.new(-0.008, 0.24, 0.6), HandRot = Vector3.new(-50, 0, 0) },
				{ T = 0.66, HandPos = Vector3.new(-0.008, 0.19, 0.619) },
				{ T = 0.67, Sound = "BoltRelease", Kick = 0.6 },
				-- Over to the charging handle on the right, pull it back and let it go.
				{ T = 0.75, GunPos = Vector3.new(-0.02, 0.04, 0.03), GunRot = Vector3.new(6, -8, 22), HandPos = Vector3.new(0.105, 0.067, 0.513), HandRot = Vector3.new(-20, 0, -70) },
				{ T = 0.79, Sound = "BoltBack", HandPos = Vector3.new(0.105, 0.06, 0.52) },
				{ T = 0.83, HandPos = Vector3.new(0.105, 0.06, 0.6), Slide = 1 },
				{ T = 0.84, Sound = "BoltRelease", Kick = 0.8 },
				{ T = 0.86, Slide = 0, HandPos = Vector3.new(0.12, 0.1, 0.64) },
				{ T = 0.93, HandPos = V0, HandRot = V0 },
				{ T = 1, GunPos = V0, GunRot = V0 },
			},
		},
	},
}

-- Mob types. Every mob runs through the same hit reactions (MobReactions); only these
-- numbers differ. A mob model carries a "MobType" attribute naming its entry here, and
-- each body part that can come off carries a "Limb" attribute naming its group.
GameConfig.Mobs = {
	TestZombie = {
		Health = 150,
		WalkSpeed = 7,
		Sounds = "Mobs/TestZombie",
		-- Limb health. Kills: losing it is death. Crawls: losing it drops the mob to a crawl.
		-- Weakens: losing it weakens attacks. Stagger multiplies the hit stagger on that part.
		-- With the pistol (34): an arm or leg wounds on shot 1, hangs loose on shot 2 (Gore.DangleAt)
		-- and tears off on shot 3.
		Limbs = {
			Head = { Health = 120, Kills = true, Stagger = 1.6 },
			LeftArm = { Health = 80, Weakens = true, Stagger = 1 },
			RightArm = { Health = 80, Weakens = true, Stagger = 1 },
			LeftLeg = { Health = 90, Crawls = true, Stagger = 1.4 },
			RightLeg = { Health = 90, Crawls = true, Stagger = 1.4 },
		},
		-- Each hit slows the mob to Slow x speed for Time seconds (times the gun's Stagger).
		Stagger = { Time = 0.3, Slow = 0.25 },
		KnockbackScale = 1,
		ThrowScale = 1,
		CrawlSpeed = 0.4,
		HurtSoundGap = 0.45,
		IdleSoundGap = NumberRange.new(4, 9),
		CorpseTime = 12,
		GibTime = 15,

		-- Melee (Call of Duty Zombies' swipe): stop, raise one arm, swing. The swing starts
		-- inside Range and connects if you're still inside Reach and within Arc degrees of
		-- where it faces when it lands. A hit during the windup (any stagger) breaks the
		-- swing off. Each lost arm scales Damage by ArmLost; with no arms left it lunges to
		-- bite for Damage x Bite. Crawlers reach CrawlRange and hit for Damage x Crawl.
		Attack = {
			Range = 4,
			Reach = 5.5,
			Arc = 90,
			Windup = 0.55,
			Swing = 0.14,
			Recover = 0.5,
			Cooldown = 0.35,
			Damage = 34,
			ArmLost = 0.65,
			Bite = 0.5,
			Crawl = 0.7,
			CrawlRange = 3,
			-- Feeding on a body: a short claw every MaulGap seconds (no damage, it's the devour).
			MaulGap = NumberRange.new(0.35, 0.7),
		},

		-- Getting to the player (Call of Duty Zombies / Left 4 Dead hordes). Close and in
		-- plain sight they walk straight at you; otherwise they follow a path, which may run
		-- through fences (Vaultable) and plank barricades (Breakable) at a cost, so they come
		-- over or through rather than walk all the way around. At an obstacle they act dumb
		-- first for DumbTime (bump into it, shuffle along it, claw at it), then vault it in
		-- VaultTime or tear its boards off one by one, BreakDelay apart. A mob that makes
		-- under StuckDistance of headway in StuckTime shuffles aside for MillTime and repaths.
		Navigation = {
			DirectRange = 40,
			RepathTime = 1,
			RepathMove = 3,
			DumbTime = NumberRange.new(2, 4.5),
			BreakDelay = NumberRange.new(1, 2),
			VaultTime = 0.8,
			-- Taller than this (studs above the ground) is a wall, not a fence.
			MaxVault = 5,
			ClawGap = NumberRange.new(0.9, 1.4),
			StuckTime = 1,
			StuckDistance = 0.8,
			MillTime = NumberRange.new(0.5, 1.1),
			-- Extra path cost per stud through each kind of obstacle.
			Costs = { Vault = 8, Break = 15, Door = 4 },
		},

		-- Instant hit reactions, drawn on every client (the shooter's client predicts them).
		-- Each hit kicks the hit part's joint away from the bullet and jolts the body back.
		Reaction = {
			-- Spring speed (rad/s) and damping; below 1 overshoots once, like flesh settling.
			Frequency = 24,
			Damping = 0.4,
			-- Share of each kick shown on the same frame as the hit; the rest follows as speed.
			Snap = 0.6,
			-- Joint kick in radians per limb group (gun HitSnap 1). Torso hits jolt the body harder.
			PartKick = { Head = 0.8, LeftArm = 1.1, RightArm = 1.1, LeftLeg = 0.5, RightLeg = 0.5, Default = 0.4 },
			TorsoJolt = 1.5,
		},

		-- Wounds and tearing. Colours are per mob so other mob types can bleed differently.
		-- Zombie blood is green (owner, 28 Oct): it reads as zombie ichor and keeps the
		-- experience out of the realistic-blood maturity rating. Keep mob blood non-red.
		Gore = {
			BloodColor = Color3.fromRGB(70, 104, 24),
			FleshColor = Color3.fromRGB(112, 138, 60),
			WoundColor = Color3.fromRGB(20, 30, 8),
			BoneColor = Color3.fromRGB(214, 200, 172),
			-- Bullet holes kept per body part (oldest goes first).
			WoundsPerPart = 6,
			-- A limb hangs loose once its health falls to this share, then tears off at zero.
			DangleAt = 0.45,
			-- When a limb tears, flesh holds it this long (s) while strands stretch and snap.
			TearHold = 0.14,
			Strands = NumberRange.new(4, 7),
			-- Studs a strand stretches before it snaps.
			StrandBreak = NumberRange.new(0.4, 2.4),
			-- Heartbeat spurts from a fresh stump, then a drip for DripTime seconds.
			SpurtPulses = 7,
			DripTime = 6,
			-- Flesh chunks thrown from a tear.
			Chunks = NumberRange.new(4, 8),
			-- After part of a limb comes off, what's left keeps this share of the limb's health.
			StumpLeft = 0.6,
		},
	},
	-- The Lamplighters (WAR's human enemies, ServerStorage.Modules.Soldier). Hit like mobs (stagger,
	-- knockback, ragdoll and fade) but nothing tears: every limb has health no gun reaches, so a
	-- body stays whole (owner: less gore on faces). They bleed black lamp oil, never red.
	Lamplighter = {
		Health = 130,
		WalkSpeed = 13,
		Sounds = "Mobs/Lamplighter",
		Limbs = {
			Head = { Health = 1e6, Dangles = false, Stagger = 1.4 },
			LeftArm = { Health = 1e6, Dangles = false, Stagger = 0.8 },
			RightArm = { Health = 1e6, Dangles = false, Stagger = 0.8 },
			LeftLeg = { Health = 1e6, Dangles = false, Stagger = 1.1 },
			RightLeg = { Health = 1e6, Dangles = false, Stagger = 1.1 },
		},
		Stagger = { Time = 0.2, Slow = 0.5 },
		KnockbackScale = 0.5,
		ThrowScale = 0.8,
		CrawlSpeed = 0.4,
		HurtSoundGap = 0.6,
		IdleSoundGap = NumberRange.new(5, 11),
		CorpseTime = 12,
		GibTime = 10,
		Reaction = {
			Frequency = 22,
			Damping = 0.45,
			Snap = 0.6,
			PartKick = { Head = 0.6, LeftArm = 0.8, RightArm = 0.8, LeftLeg = 0.4, RightLeg = 0.4, Default = 0.35 },
			TorsoJolt = 1.2,
		},
		Gore = {
			BloodColor = Color3.fromRGB(26, 24, 21),
			FleshColor = Color3.fromRGB(58, 52, 44),
			WoundColor = Color3.fromRGB(12, 10, 8),
			BoneColor = Color3.fromRGB(200, 190, 170),
			WoundsPerPart = 4,
			DangleAt = 0.45,
			TearHold = 0.14,
			Strands = NumberRange.new(0, 0),
			StrandBreak = NumberRange.new(0.4, 1),
			SpurtPulses = 2,
			DripTime = 3,
			Chunks = NumberRange.new(0, 0),
			StumpLeft = 0.6,
		},
	},
}

-- Aim assist per input type. PC (KeyboardAndMouse) never gets any.
-- Radii are in degrees from the crosshair.
GameConfig.AimAssist = {
	KeyboardAndMouse = {
		Enabled = false,
	},
	Touch = {
		Enabled = true,
		SlowdownRadius = 6,
		SlowdownMultiplier = 0.45,
		MagnetRadius = 7,
		MagnetStrength = 0.35,
		AutoFireDefault = true,
	},
	Gamepad = {
		Enabled = true,
		SlowdownRadius = 5,
		SlowdownMultiplier = 0.6,
		MagnetRadius = 5,
		MagnetStrength = 0.2,
		AutoFireDefault = false,
	},
}

-- Server-side checks on what clients report. Loose enough for 250 ms ping.
GameConfig.Validation = {
	MaxOriginOffset = 7,
	MaxRayMiss = 2.5,
	MaxPartOffset = 6,
	FireRateTolerance = 0.75,
	MaxShotsPerSecond = 15,
	-- Pellets may leave this many degrees wider than the gun's own cone.
	ConeSlack = 3,
}

-- Plank barricades (tag "Breakable"): mobs tear the boards (Wood or WoodPlanks parts) off,
-- BoardsPerRip per pull; once none are left the rest of it collapses. Torn boards fly toward
-- the mob and fade after DebrisTime. Players hold E at a window to nail boards back on
-- (GameConfig.Match.Repair).
GameConfig.Barricades = {
	-- Gunfire a board soaks before it's blown off (about three pistol shots).
	BoardHealth = 90,
	DebrisTime = 12,
	ThrowSpeed = 14,
	BoardsPerRip = 2,
}

-- Shooting the world (Battlefield / Rainbow Six Siege soft cover, scaled down). What a
-- bullet does depends on the material it hits:
--   Shatter: glass breaks on the first hit into falling shards.
--   Break: wood and plastic take damage and split into chunks when it runs out. Health is
--     HealthPerVolume per cubic stud (at least MinHealth), so a plank goes in a few shots
--     and a crate takes most of a magazine.
--   Chip (stone, concrete, brick) and Dent (metal): marks and dust or sparks, never break.
-- Glass is also any see-through part named like glass (GlassNames). Loose props are pushed
-- by every bullet and break the same way. Plank barricade boards come off one by one when
-- shot (Barricades). Parts bigger than MaxBreakVolume and parts with the Indestructible
-- attribute take marks only.
GameConfig.WorldDamage = {
	Materials = {
		Glass = "Shatter", Ice = "Shatter",
		Wood = "Break", WoodPlanks = "Break", Plastic = "Break", SmoothPlastic = "Break",
		Fabric = "Break", Cardboard = "Break",
		Metal = "Dent", DiamondPlate = "Dent", CorrodedMetal = "Dent", Foil = "Dent",
		Concrete = "Chip", Brick = "Chip", Rock = "Chip", Slate = "Chip", Cobblestone = "Chip",
		Granite = "Chip", Marble = "Chip", Pavement = "Chip", Asphalt = "Chip",
		Limestone = "Chip", Basalt = "Chip", Sandstone = "Chip", Plaster = "Chip",
	},
	-- Any see-through part whose name has one of these in it is glass, whatever its material.
	GlassNames = { "glass", "window", "pane" },
	-- Loose (unanchored) props are knocked along the shot: impulse per point of damage.
	PushPerDamage = 0.5,
	-- Small things (under SmallVolume cubic studs) take HealthPerVolume per cubic stud
	-- (at least MinHealth) and then break whole.
	HealthPerVolume = 3,
	MinHealth = 20,
	SmallVolume = 6,
	-- Bigger things (doors, crates, plank walls) break where they're hit, Siege style: each
	-- hit cuts a patch of cells about CellSize studs across round itself (the rest of the
	-- part stays whole, so the grain only breaks up round the damage), each with CellHealth. A bullet hurts the cells within its gun's BreakRadius of the hit, less
	-- with distance, so a pistol knocks out a hole, a shotgun blast a patch and a sniper
	-- round a big one. Once under CollapseShare of the cells are left, the rest falls.
	CellSize = 1,
	CellHealth = 15,
	CollapseShare = 0.3,
	MaxBreakVolume = 300,
	-- Broken pieces lie where they fell this long before fading.
	DebrisTime = 25,
	-- Shove on the pieces nearest the hit; the far side just collapses.
	ThrowSpeed = 9,
	MaxPieces = 12,
	Shards = NumberRange.new(14, 20),
}

GameConfig.TestRange = {
	WalkerDelay = 6, -- seconds after the first player spawns before walkers start hunting
	RespawnTime = 2.5,
	StraferSpeed = 9,
	-- Walkers head for the nearest player still standing or down (not one being eaten),
	-- and swipe once in range (Mobs.<type>.Attack).
	WalkerAggroRange = 150,
	-- Static targets wake up and hunt when hurt or when a player comes this close in sight.
	WakeRange = 18,
}

-- Night: the player's flashlight, the range lamps and the ambience (pass E).
-- Flashlight: F / D-pad up / the touch button. Your own light rides the camera; everyone
-- else sees a light on your head (Team*). Lamps tagged "Lamp" with Faulty = true flicker
-- in bursts and sometimes go dark. Stinger: one sting when a mob gets within Near studs
-- after no mob was within CalmRange for CalmTime seconds.
GameConfig.Night = {
	Flashlight = {
		StartOn = true,
		Color = Color3.fromRGB(255, 244, 226),
		Angle = 42,
		Range = 60,
		Brightness = 4,
		SpillAngle = 100,
		SpillRange = 22,
		SpillBrightness = 0.6,
		Offset = Vector3.new(0.4, -0.35, -1.2), -- ahead of the head so your own body never shadows it
		Sway = 14,
		TeamAngle = 40,
		TeamRange = 45,
		TeamBrightness = 2.5,
	},
	Lamps = {
		BurstGap = NumberRange.new(2, 6),
		BurstFlicks = NumberRange.new(3, 8),
		FlickTime = NumberRange.new(0.04, 0.12),
		DarkChance = 0.3,
		DarkTime = NumberRange.new(0.6, 2.5),
	},
	Ambience = {
		WindVolume = 0.35,
	},
	Stinger = {
		Near = 10,
		CalmRange = 20,
		CalmTime = 15,
		Cooldown = 30,
	},
}
-- Doors tagged "Door": a "Leaf" model swings on its left edge (HingeSide attribute -1 or 1),
-- away from whoever opens it. Players press E; a zombie at a closed door shoves it open
-- after a short struggle (Mobs.<type>.Navigation, kind "Door").
GameConfig.Doors = {
	OpenAngle = 100,
	OpenTime = 0.45,
	CloseTime = 0.55,
	PromptDistance = 8,
	ShoveDumbShare = 0.35, -- share of the normal dumb time a zombie fumbles before shoving
}

-- Pickups tagged "Pickup" with Kind = "Ammo", "Bandage" or "Gun" (attribute Gun; Mag and
-- Reserve if it was dropped). Within HighlightRange they get an outline; E takes them. An ammo
-- can fills the guns you carry back to their full Reserve (a zombie drop gives Drop.Magazines
-- mags instead); bandages and guns go in the hotbar (GameConfig.Inventory).
-- Placed pickups come back after Respawn seconds; zombie drops (Drop.Chance per kill) vanish
-- after Drop.Life.
GameConfig.Pickups = {
	PromptDistance = 7,
	HighlightRange = 24,
	Ammo = { Respawn = 30, Color = Color3.fromRGB(255, 196, 64) },
	Gun = { Respawn = 30, Color = Color3.fromRGB(235, 235, 240) },
	Bandage = { Respawn = 40, Color = Color3.fromRGB(150, 240, 170) },
	Drop = { Chance = 0.25, Magazines = 1, Life = 40 },
}
-- Bandages: carried in the hotbar (GameConfig.Inventory; its slot key, D-pad down, or a tap uses
-- one). Applying takes ApplyTime seconds, during which you can't shoot, then heals Heal. Each zombie hit leaves a
-- wound on a limb (WoundWeights: where hits land); a bandage wraps the oldest open wound, and
-- the wrap stays on the body (and on your first-person arms) for the rest of that life.
-- Trauma (Back 4 Blood's trauma damage): TraumaShare of every hit stays locked out of
-- regeneration until that wound is bandaged, at most TraumaMax in all.
GameConfig.Bandages = {
	ApplyTime = 2.4,
	Heal = 40,
	TraumaShare = 0.35,
	TraumaMax = 60,
	Color = Color3.fromRGB(214, 186, 150), -- tan elastic crepe, like the roll
	WoundWeights = { Arm = 45, Torso = 30, Leg = 15, Head = 10 },
}

-- What you carry (GUNS, menu revamp 3 Nov 2026): Slots slots (keys 1-4), each one item. Slots 1..GunSlots hold
-- guns: the kit's primary in 1 and its secondary in 2 (a kit with no primary puts the secondary in 1), and a gun
-- picked up goes in the first free gun slot. BandageSlot holds the bandage stack: Bandages at spawn, at most
-- Stack.Bandage. Lethal and tactical gear are counts, not slots (player attribute GearCounts). The kit comes
-- from ServerStorage.Modules.Kit; Start is the old spawn kit, used only in a place without that module.
-- Ammo never takes a slot: an ammo can refills the guns you carry (GameConfig.Pickups). A gun picked up with no
-- free gun slot swaps with the gun in your hands, which drops with its ammo. The downed pistol
-- (Player.Downed.Gun) is always there while you're down, carried or not.
GameConfig.Inventory = {
	Slots = 4,
	GunSlots = 3,
	BandageSlot = 4,
	Bandages = 1,
	Start = { { "Pistol", 1 }, { "Bandage", 1 } },
	Stack = { Bandage = 3 }, -- owner 31 Oct: bandages stack to 3
}

-- Hotbar: one tile per inventory slot, bottom centre.
GameConfig.Hotbar = {
	SlotSize = Vector2.new(78, 56),
	Gap = 6,
	Accent = Color3.fromRGB(255, 176, 60),
}

-- The Defend match (ServerScriptService.MatchServer), Call of Duty Zombies' Nacht der Untoten
-- loop in the house (Workspace.Map.DefendHouse with DefendHouse = true):
--   Waves: Count(wave, players) zombies spawn at Map.ZombieSpawns, at most MaxAlive at once,
--   SpawnGap apart. Before the house opens they walk to a boarded ground window, tear the
--   boards off and climb in; then they hunt (MobAI). Health and runners grow every wave.
--   Intermission seconds between waves. At OpenAtWave the boarded front and back doors burst
--   open and zombies also come from Map.ZombieSpawns.Town.
--   Points (Call of Duty): Hit per damaging hit, Kill or HeadKill per kill, Repair per board
--   nailed back (at most RepairCap boards' worth per wave). Spent on debris (Debris tag, Cost),
--   guns and supplies (GunSpawn markers or Pickup models with Cost; carried guns refill ammo
--   for AmmoShare of the price) and the mystery crate (Crate).
--   Dead players come back at the next intermission. When nobody is left alive the run ends:
--   GameOverTime seconds on the wave reached, then everything resets and everyone respawns.
GameConfig.Match = {
	-- Time from spawning upstairs to wave 1: enough to come down and clear the zombies inside.
	FirstWaveDelay = 22,
	Intermission = 12,
	GameOverTime = 9,
	-- Waves after this burst the doors in if nobody has broken out by then.
	OpenAtWave = 8,
	-- Debris piles are shot down (MatchServer): DebrisHealth of bullet damage brings one down
	-- (8 pistol rounds, 2 shotgun blasts), and SHOOT IT DOWN shows within DebrisHint studs.
	DebrisHealth = 260,
	DebrisHint = 16,
	MaxAlive = 24,
	-- Zombies already standing downstairs when a run starts (Map.ZombieSpawns.Inside); they wake
	-- when a player on their floor comes within InsideWakeRange, or on a nearby shot.
	InsideAtStart = 3,
	InsideWakeRange = 26,
	SpawnGap = NumberRange.new(0.6, 1.8),
	-- Zombies in a wave: Base + PerWave x wave, x (1 + PerPlayer per extra player).
	Count = { Base = 4, PerWave = 3, PerPlayer = 0.6 },
	-- More players, harder match: each player past the first adds these (the wave count
	-- above already grows with Count.PerPlayer). Health: zombie health x (1 + Health each);
	-- MaxAlive: more zombies up at once; SpawnGap: the gaps between spawns x this each;
	-- Runners: added to the runner share; InsideAtStart: more zombies waiting downstairs.
	PerPlayer = { Health = 0.15, MaxAlive = 4, SpawnGap = 0.88, Runners = 0.05, InsideAtStart = 1 },
	-- Zombie health: Base + PerWave x (wave - 1), then x Late per wave after wave 10.
	Health = { Base = 150, PerWave = 40, Late = 1.1 },
	-- Share of runners (RunSpeed) from RunnersFrom on, growing RunnerStep a wave up to RunnerMax.
	WalkSpeed = 7,
	RunSpeed = 15,
	RunnersFrom = 3,
	RunnerStep = 0.12,
	RunnerMax = 0.6,
	-- Once inside, a zombie notices players this far away.
	AggroRange = 400,
	-- A zombie on its way to a window goes for a player in plain sight this close instead.
	DistractRange = 14,
	ClimbTime = 0.9,
	Points = { Start = 500, Hit = 10, Kill = 60, HeadKill = 100, Repair = 10, RepairCap = 40 },
	-- A kill pays nothing straight away: the zombie spills glowing shards (ServerStorage.Modules
	-- .GlowDrops) worth Points.Kill (HeadKill for a headshot) between them. Anyone who comes
	-- within Magnet studs pulls them in and they follow until collected; they blink for the last BlinkAt seconds of Life.
	Glow = { Shards = 3, HeadShards = 5, Life = 30, BlinkAt = 6, Magnet = 20, Collect = 3, PullSpeed = 70 },
	-- One hold puts every torn board back: HoldTime plus PerBoard for each board missing.
	Repair = { HoldTime = 0.5, PerBoard = 0.2, Range = 9 },
	AmmoShare = 0.5,
	-- Falls further than Safe studs hurt: PerStud damage for every stud past it (the upper
	-- floor's windows are about 19 studs up, so jumping out costs about a fifth of your health).
	FallDamage = { Safe = 14, PerStud = 4 },
	-- Everyone plays as police SWAT (the SWAT set from Workspace.MilitaryRigs): shirt and pants
	-- replace the avatar's own clothing; layered clothing comes off so it can't cover them.
	Uniform = { Shirt = 1455700999, Pants = 1455701482 },
	Crate = {
		Cost = 950,
		RollTime = 2.6,
		OfferTime = 10,
		-- Weight of each gun in a roll.
		Guns = { Shotgun = 4, AK = 3, Sniper = 3, MP5 = 3, M4 = 2, HandCannon = 2, SR25 = 2, M60 = 1 },
	},
}

-- Nights and lulls (MatchServer; owner 31 Oct, HORROR-SHOOTER-SIM-REPORT.md). With Enabled the
-- Defend match is LastNight timed nights in the house with a lull between each, instead of
-- counted waves and the breakout door:
--   Players start downstairs (house.NightStart). FirstDelay seconds, then night 1.
--   A night lasts Base seconds, Step more each night, at most Cap; zombies come from the
--   director (GameConfig.Director) through the windows, with HealthPerNight more health a night
--   (instead of Match.Health.PerWave). The doors are barred; a player caught outside holds E on
--   a door to get in.
--   A lull lasts LullTime seconds: the doors stand open, a few zombies roam the town (at most
--   LullAlive, plus PerPlayer.LullAlive each extra player, LullGap apart) and the Beacon walks
--   it (it wakes at the first lull). ReturnWarn seconds before the night, the one line calls
--   everyone home (Remotes.Match "Return").
--   The last night is the one after the radio tower is complete (GameConfig.Parts; LastNight
--   when parts are off). It lasts LastTime: the Beacon comes for the house, and the
--   helicopter is called Breakout.EvacTime before the end; then it's the breakout (town
--   zombies, GRAB the ladder) as before.
--   Playing alone you get SoloSelfRevives instead of Player.Downed.SelfRevives.
--   A Beacon catch takes you (a death: one of GameConfig.Lives). With CatchThrows it would drop
--   you in the yard behind the house (Map.Yard) for CaughtCost of your points instead (off since
--   2 Nov: testers came back behind the house with all their loot, so it cost nothing).
--   The dead come back at the next lull while they have a life left (GameConfig.Lives).
GameConfig.Nights = {
	CatchThrows = false,
	Enabled = true,
	FirstDelay = 15,
	Base = 90,
	Step = 15,
	Cap = 180,
	LastNight = 7,
	LastTime = 210,
	LullTime = 100,
	ReturnWarn = 20,
	-- After the night's time is up, it waits this long at most for the last zombies to fall.
	DawnGrace = 15,
	HealthPerNight = 30,
	LullAlive = 3,
	LullGap = NumberRange.new(6, 10),
	PerPlayer = { LullAlive = 1, Strays = 1 },
	-- Strays (Map.StraySpawns): slow walkers asleep on the streets each lull, picked along the
	-- way from the house to the part, that wake when someone comes near or shoots close by. Any
	-- still asleep at dusk wander off.
	Strays = 3,
	SoloSelfRevives = 3,
	CaughtCost = 0.15,
	-- Holding E on a barred door from outside.
	DoorHold = 1.2,
}

-- The night director (MatchServer, Nights only): zombies come at a share of the rate the team
-- can kill them, instead of a set number. Kill rate: the Dps of each standing player's best gun
-- (DefaultDps with none), summed, over the night's zombie health. Share: Pressure, PerNight more
-- each night after the first and PerPlayer more each player past the first, at most Max, x
-- LastNight on the last night. Spawns are never closer together than Match.SpawnGap. At most
-- AliveSolo x (1 + AlivePerPlayer each extra player) + AlivePerNight x night zombies up at once
-- (AliveLast more on the last night). Nothing spawns in the last QuietEnd seconds of a night.
-- Menu revamp (MENU-PLAN 9.4): the director no longer reads the base gun. Every gun counts as BaseDps (the
-- pistol's number, so night 1 stays fair for a pistol-only first match and a rifle start feels strong), and
-- each Defend upgrade tier on the best upgraded gun a player carries adds TierDps of that (Tiers below;
-- MatchServer's killRate reads it once the modes session applies the MATCH contract request).
-- Tiers: the house upgrade stations (Points.Stations) raise the held gun's tier for this run (player
-- attribute Tiers, JSON gun -> tier); MobReactions multiplies a player's gun damage by Mult. Supply: what the
-- stations also sell (Points): Ammo (full reserve of the held gun), Gear (lethal and tactical back to the kit
-- count), Armour (a plate that soaks Armour.Soak damage, character attribute Plate).
GameConfig.Director = {
	Pressure = 0.5,
	PerNight = 0.05,
	PerPlayer = 0.15,
	Max = 0.95,
	LastNight = 1.25,
	AliveSolo = 6,
	AlivePerPlayer = 0.6,
	AlivePerNight = 0.5,
	AliveLast = 4,
	QuietEnd = 8,
	BaseDps = 60,
	TierDps = 0.3,
	Dps = { Pistol = 60, Shotgun = 60, AK = 60, Sniper = 60, MP5 = 60, M4 = 60, HandCannon = 60, SR25 = 60, M60 = 60 },
	DefaultDps = 60,
	Tiers = {
		{ Name = "I", Mult = 1, Cost = 0, Color = Color3.fromRGB(150, 150, 150) },
		{ Name = "II", Mult = 1.25, Cost = 500, Color = Color3.fromRGB(96, 178, 92) },
		{ Name = "III", Mult = 1.55, Cost = 1500, Color = Color3.fromRGB(80, 140, 220) },
		{ Name = "IV", Mult = 1.9, Cost = 3000, Color = Color3.fromRGB(160, 96, 210) },
		{ Name = "V", Mult = 2.3, Cost = 5000, Color = Color3.fromRGB(230, 170, 60) },
	},
	Supply = {
		Ammo = { Cost = 300 },
		Gear = { Cost = 600 },
		-- Live once PlayerHealth.Damage spends the character attribute Plate before health (MATCH contract request).
		Armour = { Cost = 900, Soak = 60, Live = true },
	},
}

-- The radio tower's parts (ServerScriptService.PartsServer, Nights only). The tower stands on the
-- hill behind the house (Map.RadioTower) and needs the parts in Order. One part comes out in
-- each lull in Lulls (any later lull brings the next one still missing), never a second while
-- one is out. It lies at a random spot in an open building (Map.PartSpots, a spot not used yet
-- this match when there is one) with an amber glow; a player picks it up (the prompt) and
-- carries it on their back. Reaching the cabinet at the tower's foot (InstallRadius) puts it
-- in: its lamp turns LampOn and the part takes its slot. A Beacon catch, dying or leaving
-- puts the part back on its spot; carried home for the night, it stays carried.
-- When every part is in, the tower's top light comes on and the next night is the last.
GameConfig.Parts = {
	Enabled = true,
	Order = { "Battery", "Fuel", "Cable", "Dish" },
	Lulls = { 2, 3, 5, 6 },
	InstallRadius = 9,
	PickupRange = 10,
	-- Where the part rides on the carrier's back (from the HumanoidRootPart).
	CarryOffset = Vector3.new(0, 0.3, 1.3),
	Glow = Color3.fromRGB(255, 176, 60),
	LampOff = Color3.fromRGB(150, 30, 25),
	LampOn = Color3.fromRGB(90, 255, 130),
	TopLight = Color3.fromRGB(255, 50, 40),
}

-- The quiet HUD (HORROR-SHOOTER-SIM-REPORT.md sec 4, "U4"). MatchHud draws a ring at the top
-- centre: Night colour during a night (the night number in the middle, filling until dawn),
-- Lull colour in a lull (draining, the seconds in the middle), Last colour on the last night.
-- ReturnWarn seconds before dusk the ring pulses. Next to it, the part you carry. Under it,
-- the Seen eye (BeaconClient). WorldGlow lights things in the world instead of writing text:
-- a window being torn, the radio tower while you carry a part, hiding spots once you're being
-- seen. PromptLook draws every ProximityPrompt as one round button (a hand on touch, the key
-- on PC and gamepad) with the action under it.
GameConfig.Hud = {
	Night = Color3.fromRGB(122, 167, 255),
	Lull = Color3.fromRGB(255, 176, 60),
	Last = Color3.fromRGB(230, 70, 60),
	Track = Color3.fromRGB(40, 44, 52),
	Icons = { Gear = "rbxassetid://78749640810501", Hand = "rbxassetid://135680222520165" },
	WindowGlow = 3, -- seconds a window glows after a board is torn
	HideGlowRange = 45, -- hiding spots this close glow while the Beacon is seeing you
}

-- The radio voice (StarterPlayerScripts.RadioVoice): Roblox text-to-speech through a radio
-- filter, at the moments the HUD sim gave to the voice. Placeholder until recorded lines.
-- {where} is the spot's name from Spots, {left} the parts still missing.
GameConfig.Radio = {
	Voice = "1",
	Speed = 1.05,
	Volume = 1.6,
	Spots = {
		Apartments = "the apartments",
		AbandonedHouse = "the old house",
		NeighbourHouse = "the house next door",
		FuelStop = "the gas station",
		PoliceStation = "the police station",
		HardwareStore = "the hardware store",
		Clinic = "the clinic",
		Shop = "the shop",
	},
	Lines = {
		Lull = "It's quiet. Grab what you need, and stay out of the light.",
		PartOut = "There's a part at {where}. Bring it to the tower on the hill.",
		Return = "Get back to the house!",
		PartIn = "Got it. {left} to go.",
		TowerDone = "Tower's live. The chopper comes at the end of the night. Hold the house.",
		LastNight = "This is it. Last night. Hold on.",
	},
}

-- Player settings (StarterGui.Settings, opened from the menu or the gear at the top left;
-- Shared.Options holds them on the client, Profile saves them). Sliders have Min/Max/Step,
-- pickers Choices, switches a true/false Default. Touch-only and gyro-only rows hide where
-- they can't work.
GameConfig.Settings = {
	Order = { "LookSens", "AimSens", "InvertY", "Gyro", "GyroSens", "GyroFlip", "ButtonSize", "Graphics", "Fov", "Bob", "Gore", "VoiceVol", "MenuVol", "MyVoice", "Backdrop" },
	LookSens = { Label = "Look sensitivity", Default = 1, Min = 0.2, Max = 3, Step = 0.05 },
	AimSens = { Label = "Aiming sensitivity", Default = 1, Min = 0.2, Max = 2, Step = 0.05 },
	InvertY = { Label = "Invert look", Default = false, Touch = true },
	Gyro = { Label = "Gyro aim", Default = "Off", Choices = { "Off", "Aiming", "Always" }, Gyro = true },
	GyroSens = { Label = "Gyro sensitivity", Default = 1, Min = 0.2, Max = 3, Step = 0.05, Gyro = true },
	GyroFlip = { Label = "Flip gyro", Default = false, Gyro = true },
	ButtonSize = { Label = "Button size", Default = 1, Min = 0.8, Max = 1.3, Step = 0.05, Touch = true },
	-- StarterPlayerScripts.Graphics: Auto starts on High (Medium on a phone or tablet) and steps down while the frame rate stays low.
	Graphics = { Label = "Graphics", Default = "Auto", Choices = { "Auto", "High", "Medium", "Low" } },
	Fov = { Label = "Field of view", Default = 74, Min = 60, Max = 90, Step = 1 },
	Bob = { Label = "Camera bob", Default = 1, Min = 0, Max = 1, Step = 0.05, Percent = true },
	Gore = { Label = "Blood and gore", Default = true },
	VoiceVol = { Label = "Squad voices", Default = 1, Min = 0, Max = 1, Step = 0.05, Percent = true },
	MenuVol = { Label = "Menu sounds", Default = 1, Min = 0, Max = 1, Step = 0.05, Percent = true },
	MyVoice = { Label = "Your voice", Default = "Sarge", Choices = { "Sarge", "Rook" } },
	-- Which Workspace.MenuSets set the menu squad stands in (MenuStage reads it live).
	Backdrop = { Label = "Menu backdrop", Default = "Outpost", Choices = { "Outpost", "Hangar", "Rooftop", "Woods" } },
	-- Touch look: degrees of turn per pixel dragged at sensitivity 1.
	TouchLook = 0.3,
	-- Saves at most this often (seconds).
	SaveGap = 2,
}

-- The menu on join (StarterGui.Menu, StarterPlayerScripts.MenuClient, ServerScriptService.MenuServer):
-- the camera stands on the town road at night (RoadCamera) while the Beacon (a local copy,
-- ReplicatedStorage.MenuBeacon) walks the road along BeaconRoute, and heavy words sit on the left. Hovered words
-- turn Accent. Players don't spawn until they press PLAY. Modes lists the playable modes.
-- Breaking out (MatchServer): once wave BreakoutFrom is cleared, players can hold E on the
-- front or back door to break out. The Beacon wakes (GameConfig.Beacon), the town fills with
-- zombies, and the way home is the police roadblock at the east end of the road
-- (Workspace.Map.Extraction): call on its radio, then hold out EvacTime seconds near it.
-- Everyone alive when the timer runs out makes it out.
GameConfig.Breakout = {
	BreakoutFrom = 3,
	DoorHold = 1.5,
	MaxAlive = 16,
	SpawnGap = NumberRange.new(1.4, 2.6),
	-- Town zombies spawn at least this far from every player, and not further than Far.
	Near = 60,
	Far = 170,
	-- The Beacon reveal right after the doors blow: players held still and safe this long.
	RevealTime = 5,
	-- Seconds from the end of the reveal until the helicopter is over the landing zone.
	EvacTime = 45,
	-- During the last part of the countdown zombies come a little faster.
	EvacGap = NumberRange.new(0.9, 1.6),
	EscapePoints = 1500,
	WinTime = 10,
	-- The pickup (Shared.EvacPath, MatchServer, EvacClient; HORROR-SHOOTER-ESCAPE.md). Times in
	-- seconds from the moment it's over the zone. Inbound: flying in before that. Hover: hanging
	-- with the ladder down. Crawl: pulling away down the road at CrawlSpeed (studs/s) with the
	-- ladder still in reach, climbing CrawlRise studs. Leave: climbing out over the town.
	-- Height: hover height over the zone. Ladder: rope length. Door: the open cabin door in the
	-- helicopter's own space (the ladder hangs from it). Grab: how close (studs, flat) the
	-- ladder's foot must be to press GRAB. Climb: seconds up the ladder.
	Evac = {
		Inbound = 10,
		Hover = 9,
		Crawl = 11,
		CrawlSpeed = 9,
		CrawlRise = 8,
		Leave = 9,
		Height = 44,
		Ladder = 40,
		Door = Vector3.new(-5.2, -6.5, -3),
		Grab = 7,
		Climb = 3.4, -- the ride camera's pull-out
		-- You climb it yourself (MatchServer's pickup): ClimbTime s of holding forward from the foot
		-- to the door. The first grab starts it climbing away GrabLeave s later.
		ClimbTime = 7,
		GrabLeave = 5,
		-- Where it comes from and where it leaves to, flat directions from the zone.
		From = Vector3.new(-1, 0, 0.15),
		To = Vector3.new(-0.8, 0, 0.6),
	},
	-- Each player past the first: more town zombies up at once, and they come quicker.
	PerPlayer = { MaxAlive = 4, SpawnGap = 0.85 },
}

-- The way out (MatchServer, StarterPlayerScripts.RescueClient): when the evac timer runs out
-- with someone at the roadblock, a military helicopter (ReplicatedStorage.Assets.EvacHeli)
-- comes in low over the rooftops, hangs over the road, takes everyone aboard and climbs away
-- over the town. Then, once in each player's life, the uniform pick (Attire; AttireTime runs
-- out on the first uniform), and back to the menu. Players who already have a uniform go
-- straight back to the menu.
--   Hover: where it hangs, from the roadblock zone's centre. Approach / Leave: where it comes
--   from and flies off to, from the same point. Time: the whole cutscene, seconds.
GameConfig.Rescue = {
	-- The escape cutscene (RescueClient), now played on the live helicopter: from the door
	-- looking down at the Beacon reaching up, then wide as it climbs away.
	EscapeTime = 10,
	Time = 15,
	Hover = Vector3.new(-6, 15, -26),
	Approach = Vector3.new(-260, 80, 30),
	Leave = Vector3.new(-380, 140, 180),
	AttireTime = 30,
}

-- The uniforms you can pick after your first rescue (StarterGui.Attire, RescueClient), shown
-- on the rigs in ReplicatedStorage.Assets.AttireLineup (Rig names the model) and on a copy of you. The pick is saved
-- (ServerStorage.Modules.Profile) and Uniform puts it on from the next spawn on; until then
-- everyone plays in GameConfig.Match.Uniform (police SWAT).
GameConfig.Attire = {
	{ Name = "Woodland", Rig = "WoodlandSoldier", Shirt = 9958476757, Pants = 9958477344 },
	{ Name = "Desert", Rig = "DesertSoldier", Shirt = 10934858481, Pants = 10934862919 },
	{ Name = "Arctic", Rig = "ArcticSoldier", Shirt = 5188807105, Pants = 5188810938 },
	{ Name = "Ghillie", Rig = "GhillieSoldier", Shirt = 16593023062, Pants = 16593040882 },
}

-- The Beacon (Workspace.Beacon, BeaconServer): a giant that walks the town during the
-- breakout. Its two lamps are its eyes; they never hurt you. Each sweeps the ground on its
-- own, and standing in a beam, in its line of sight and not hiding, fills your Seen meter
-- (HUD.Detect, top of the screen) while that lamp slows and follows you at TrackSpeed
-- (walking can't outrun it; a sprint or a roll can). Out of every beam the meter drains
-- again after DrainDelay. A full meter: it has seen you. It screams and runs at you
-- (Caught.Sprint), the screen goes black over Caught.Time, and you're taken.
--   Seen.Fill is the meter per second in the open at mid range, x Moving (how you move),
--   x the Range scale (near is faster), x Cover when you're crouched by cover without
--   hiding (or just fired from a hiding spot), x Touch on phones.
-- It hears noise (walking carries Walk studs, sprinting Sprint, gunshots Shot) and walks to
-- the last noise; hearing never fills the meter. Every VentEvery seconds its lamps overheat:
-- it stands still with them dim and smoking for VentTime, blind. That is when the lenses
-- (LensL, LensR) can be shot; the rest of the time bullets spark off their shutters. Shoot
-- both out to bring it down.
GameConfig.Beacon = {
	WalkSpeed = 10,
	TurnSpeed = 1.6, -- radians a second
	-- Smashing the town: it often picks a building to walk to and swings both arms down through
	-- it (Radius studs around the point it hits, up to MaxParts pieces), and anything its body
	-- walks through breaks too (TouchRadius). Pieces fly, then settle as rubble after Settle
	-- seconds (they don't block players). Every match puts the town back. TargetChance: how
	-- often a wander goal is a building.
	Smash = { Radius = 17, MaxParts = 70, Settle = 7, TargetChance = 0.6, Time = 1.4, HitAt = 0.6 },
	-- The pickup: from EvacStart seconds before the helicopter is over the zone, it drops
	-- everything, sweeps both lamps over the zone and comes for it at EvacSpeed (from EvacFrom
	-- studs away on the far side if it's further off). In the escape it runs after the
	-- helicopter at RescueSpeed and reaches up at it.
	EvacStart = 4,
	EvacSpeed = 16,
	EvacFrom = 150,
	RescueSpeed = 24,
	StepEvery = 1.5,
	Start = Vector3.new(105, 0, 300),
	Bounds = { Min = Vector2.new(-200, 120), Max = Vector2.new(200, 370) },
	-- Asleep in a nights match (before the first lull) it walks this far-off line past the north
	-- treeline with its lamps dark, a shape on the horizon, until it wakes for the reveal.
	Roam = { Speed = 5, From = Vector3.new(-260, 0, 482), To = Vector3.new(260, 0, 482) },
	Sweep = math.rad(42), -- either side of straight ahead
	SweepSpeed = 0.9,
	BeamReach = 120,
	BeamWidth = 7, -- studs either side of a beam's centre line at its far end that count as "in the beam"
	TrackSpeed = 18, -- studs a second a lamp that found someone follows them
	Seen = {
		-- 0.55 until 31 Oct; the nights plan sends players out every lull (sim report).
		Fill = 0.4,
		Drain = 0.3,
		DrainDelay = 1.2,
		Moving = { Still = 0.55, Walk = 1, Sprint = 1.7, Crouch = 0.6 },
		Range = { Near = 25, NearScale = 1.5, Far = 110, FarScale = 0.6 },
		Cover = 0.5,
		-- In a back alley (parts tagged Alley, Map.Alleys.Zones): the lamps make you out half as well.
		Alley = 0.5,
		Touch = 0.8,
		-- A lamp that loses you stays on the spot this long before sweeping on.
		Linger = 1.6,
		-- Firing from a hiding spot shows you (as Cover) for this long.
		ShotReveal = 1.5,
	},
	-- Seen: it runs at you for Time seconds, then (within GrabReach studs) bends down, closes a
	-- hand round you and lifts you to its lamps for Grab seconds before the dark.
	Caught = { Sprint = 55, Time = 1.6, Grab = 2.2, GrabReach = 34 },
	-- Building footprints are kept this far clear of its body as it walks the streets.
	BodyRadius = 6,
	VentEvery = NumberRange.new(22, 30),
	VentTime = 7,
	Hearing = { Walk = 30, Sprint = 95, Shot = 160, SprintSpeed = 19, WalkSpeed = 3 },
	LensHealth = 360,
	KillPoints = 2000,
	-- Each player past the first: the lenses take this much more to break (x (1 + LensHealth)).
	PerPlayer = { LensHealth = 0.6 },
}

-- Hiding, crouching and sliding (StarterPlayerScripts.Evade, EvadeServer). The roll was
-- removed 31 Oct. Ctrl / C, gamepad B or the touch Crouch button: standing or walking
-- toggles a crouch (the view CrouchDrop studs lower, CrouchSpeed, quieter and harder for the
-- Beacon to see); moving faster than SlideMinSpeed slides instead: SlideSpeed easing to
-- SlideEndSpeed over SlideTime, ending in a crouch. Jumping or sprinting stands you up.
GameConfig.Evade = {
	HideDrop = 2.4, -- camera drop while hiding
	HideRange = 4, -- how far outside a spot's box you can still duck into it
	CrouchDrop = 1.5,
	CrouchSpeed = 8,
	CrouchTime = 0.16, -- seconds the view takes to go down or come up
	SlideMinSpeed = 18,
	SlideTime = 0.7,
	SlideSpeed = 36,
	SlideEndSpeed = 10,
	SlideCooldown = 0.9,
	SlideDrop = 2.0,
	SlidePitch = 5, -- degrees the view tips back at the start of a slide
	SlideTilt = 6, -- degrees it leans into a sideways slide
	-- Dumpsters (EvadeServer): zombies can't see or reach you inside, but you climb out after
	-- InsideMax seconds and can't climb back in for InsideCooldown, so a wave can't be stalled.
	InsideMax = 40,
	InsideCooldown = 20,
	-- Hiding in the open (behind a car): the Beacon can't see you, but a zombie within
	-- OpenNotice studs with a clear line to you can. Firing shows you to zombies for ShotReveal s.
	OpenNotice = 10,
	ShotReveal = 2,
}

-- Match modes (MatchServer; horror-shooter/MODES-V3.md). Unlock: the Profile flag a player needs
-- first ("Escaped": they got out on the helicopter once). The numbers multiply GameConfig.Match /
-- Breakout / Beacon. NoBreakout: no doors to break, no helicopter, waves until everyone falls.
-- Line: the one line under the mode's name in the menu. Map: the name ModeSetup matches against
-- each map piece's Modes attribute (a piece without one is in every mode).
--   Outbreak: the house through the nights, tower parts in the lulls, the helicopter out (this was
--     called Defend before 2 Nov).
--   Defend: save the survivors with the soldiers, then kill the Beacon (the tank or the airstrike).
--   Extraction: the old hot-drop run with radio contracts. Out of the menu; kept for its code.
GameConfig.Modes = {
	Outbreak = { Line = "HOLD THE HOUSE FOR 5 NIGHTS, THEN REACH THE HELICOPTER", Map = "Outbreak" },
	Defend = { Defend = true, NoBreakout = true, Line = "SAVE THE SURVIVORS. FIX THE TANK. KILL THE BEACON", Map = "Defend" },
	Extraction = { Extraction = true, NoBreakout = true, Map = "Extraction" },
	Nightmare = {
		Line = "OUTBREAK, BUT THEY HIT HARDER",
		Map = "Outbreak",
		Unlock = "Escaped",
		Health = 1.5,
		Count = 1.3,
		RunnersFrom = 2,
		BreakoutFrom = 5,
		SeenFill = 1.4,
		LensHealth = 1.5,
	},
	Endless = { NoBreakout = true, Relics = true, Unlock = "Escaped", Line = "ROUNDS THAT NEVER STOP. PICK A CARD AFTER EACH ONE", Map = "Endless" },
	War = { War = true, NoBreakout = true, Map = "Defend" },
}

-- Lives (every mode): a run gives each player Extra lives on top of the first. A death with one
-- left brings you back at the next lull or round (Defend: after DefendRespawn s, near the squad)
-- with only the starting kit; the guns you carried drop where you fell. With none left you
-- watch your team (the camera follows a teammate) until the run ends, unless you spend a
-- revive token (StoreServer counts them).
GameConfig.Lives = {
	Extra = 1,
	DefendRespawn = 20,
}

-- Match servers (MenuServer, ModeSetup). Public servers of the place are the lobby: the menu
-- only. PLAY reserves a private server and sends you into it with your mode; QUICK JOIN looks
-- up an open match of that mode (MemoryStore map OpenMap, refreshed every Refresh s while it has
-- room) and only then reserves a new one. MaxPlayers caps a match.
GameConfig.Matchmaking = {
	OpenMap = "LL_OpenMatches_v1",
	Refresh = 20,
	MaxPlayers = 4,
}

-- Endless (mode Endless; MatchServer's Endless branch; HORROR-SHOOTER-ENDLESS.md): Call of Duty
-- Zombies rounds in the house with a roguelike twist (the owner's reference, 1 Nov: Mortuus). No
-- nights, no breakout: rounds until everyone falls. After every round three relics from Relics stand
-- on floor sigils for Intermission seconds (ServerStorage.Modules.Relics); each player takes one
-- (hold E) and keeps it for the run.
--   Stat / Add: the share added to the player attribute Relic<Stat> (GunServer, PlayerHealth and
--   Points read them); Cap stops a stack; Health adds flat health; SelfRevives adds revives.
-- Every run draws new debris costs (DebrisCost, in 50s) and a new door round (OpenAtWave), so you
-- learn the game, not the house. From TwistFrom a round has TwistChance of one twist (Twists:
-- Count and Health multiply the round, Points its hit pay, Runners makes every zombie run), called
-- out on the HUD's one line as it starts.
GameConfig.Endless = {
	Intermission = 18,
	Offer = 3,
	OpenAtWave = NumberRange.new(6, 10),
	DebrisCost = NumberRange.new(500, 1000),
	TwistFrom = 4,
	TwistChance = 0.35,
	Relics = {
		IronRounds = { Name = "Iron Rounds", Text = "+15% DAMAGE", Stat = "Damage", Add = 0.15, Color = Color3.fromRGB(255, 140, 50) },
		Headhunter = { Name = "Headhunter", Text = "+50% HEADSHOT", Stat = "Head", Add = 0.5, Color = Color3.fromRGB(230, 60, 60) },
		ThickSkin = { Name = "Thick Skin", Text = "+25 HEALTH", Stat = "Health", Add = 25, Color = Color3.fromRGB(90, 200, 120) },
		LeadBelly = { Name = "Lead Belly", Text = "-15% DAMAGE TAKEN", Stat = "Armor", Add = 0.15, Cap = 0.6, Color = Color3.fromRGB(120, 150, 210) },
		FastMend = { Name = "Fast Mend", Text = "HEAL 30% SOONER", Stat = "Regen", Add = 0.3, Cap = 0.75, Color = Color3.fromRGB(200, 240, 150) },
		Scavenger = { Name = "Scavenger", Text = "+30% POINTS", Stat = "Points", Add = 0.3, Color = Color3.fromRGB(255, 200, 80) },
		SecondWind = { Name = "Second Wind", Text = "+1 SELF-REVIVE", SelfRevives = 1, Color = Color3.fromRGB(240, 240, 250) },
	},
	Twists = {
		Runners = { Text = "THEY'RE ALL RUNNING", Runners = true },
		ThickHide = { Text = "THICK HIDE", Health = 1.4, Points = 2 },
		Swarm = { Text = "SWARM", Count = 2, Health = 0.5 },
	},
}

-- WAR, Operation Last Light (mode War; MatchServer's War section; ServerStorage.Modules.Soldier;
-- HORROR-SHOOTER-WAR.md). A squad of four, HOUND: the players plus NPC soldiers in Squad's slots
-- (players take them from the last one up). Three missions in the town: HOT DROP (Main Street to
-- the police station, the tower codes), SIGNAL (the codes into the radio tower, hold it while it
-- transmits), LAST LIGHT (the Beacon wakes; call the bird on Main Street and get on it).
--   Soldiers[kind]: Side, Rig (an AttireLineup model), Gun, Health, WalkSpeed, Damage per round,
--   RPM, Mag, Reload (s), Burst (rounds), BurstGap (s), Spread (degrees at 50 studs), Range,
--   React (s from first sight to first shot). Allies: HeadChance, DownTime (s sat down hurt before
--   they get up), ReviveHold. Enemies: Leash, Strafe (studs side to side), StrafeTime, Rush (a
--   foe farther than this gets charged), Scale.
--   Looks[kind]: Mask (gas mask colour), Lamp (the chest lamp's colour); Lamplighters bleed lamp
--   oil (GameConfig.Mobs.Lamplighter).
--   GunReach: studs from the right grip to the muzzle (the view model is scaled to it). GunHold:
--   the right grip's place in the UpperTorso's frame.
--   Formation: where each NPC slot stands from the player it keeps near (X right, Z behind; minus
--   is ahead, toward the objective).
--   Zombies: how many may be awake per phase (plus ZombiesPerPlayer per extra player).
GameConfig.War = {
	Squad = {
		{ Callsign = "REYES", Rig = "OperatorB", Gun = "AK" },
		{ Callsign = "OKAFOR", Rig = "OperatorA", Gun = "AK" },
		{ Callsign = "HASKINS", Rig = "OperatorC", Gun = "Shotgun" },
	},
	Missions = { "HOT DROP", "SIGNAL", "LAST LIGHT" },
	Formation = { Vector3.new(-7, 0, -5), Vector3.new(7, 0, -5), Vector3.new(0, 0, -10) },
	GunReach = { AK = 1.6, Shotgun = 1.7, Sniper = 2, Pistol = 0.6 },
	GunHold = CFrame.new(0.5, -0.1, -1.05),
	Soldiers = {
		Ally = {
			Side = "Ally", Rig = "OperatorA", Gun = "AK",
			Health = 300, WalkSpeed = 15, Damage = 30, HeadChance = 0.3,
			RPM = 450, Mag = 30, Reload = 2.2,
			Burst = NumberRange.new(3, 6), BurstGap = NumberRange.new(0.25, 0.7),
			Spread = 2, Range = 160, React = NumberRange.new(0.15, 0.4),
			DownTime = 14, ReviveHold = 1.5,
		},
		Lamplighter = {
			Side = "Enemy", MobType = "Lamplighter", Rig = { "HostileA", "HostileB" }, Gun = "AK",
			Health = 130, WalkSpeed = 13, Damage = 8,
			RPM = 420, Mag = 24, Reload = 2.6,
			Burst = NumberRange.new(2, 5), BurstGap = NumberRange.new(0.8, 1.8),
			Spread = 3.2, Range = 150, React = NumberRange.new(0.5, 1),
			Leash = 10, Strafe = 6, StrafeTime = NumberRange.new(1.2, 2.6),
		},
		Heavy = {
			Side = "Enemy", MobType = "Lamplighter", Rig = "HeavyA", Gun = "AK", Scale = 1.15,
			Health = 650, WalkSpeed = 9, Damage = 7,
			RPM = 700, Mag = 80, Reload = 4,
			Burst = NumberRange.new(10, 18), BurstGap = NumberRange.new(1.2, 2.2),
			Spread = 4.5, Range = 140, React = NumberRange.new(0.6, 1.2),
			Leash = 30, Strafe = 2, StrafeTime = NumberRange.new(2, 4), Rush = 40,
		},
	},
	Looks = {},
	RespawnTime = 10,
	FailWait = 5,
	ContactGap = 25,
	Strays = 6,
	CodesHold = 2.5,
	PatchHold = 3,
	PadId = 2, -- Main Street
	ZombiesPerPlayer = 1,
	ZombieGap = NumberRange.new(2.5, 5),
	Zombies = { Drop = 3, Walk = 5, Beacon = 8, Pad = 12 },
	-- The tower hold: Time seconds of transmitting (only while someone is within Radius),
	-- Lamplighter squads from M2_Road at these seconds in, the heavy at HeavyAt, Zombies awake.
	Hold = { Time = 120, Radius = 40, Squads = { 8, 45, 85 }, HeavyAt = 60, Zombies = 7 },
	-- The radio (RadioVoice, text-to-speech until recorded). Nightjar is command; Reyes the sergeant.
	Lines = {
		Drop = "Hound, Nightjar. You're on the ground. Push east up Main Street to the police station.",
		Contact = "Contact! Lamplighters!",
		Clinic = "Street's clear. Keep moving, they're dug in at the clinic.",
		Station = "Army checkpoint by the police station, dead ahead. Clear it out.",
		Codes = "The tower codes are in the checkpoint booth. Grab them.",
		GotCodes = "Got the codes. Nightjar, Hound is moving to the tower.",
		Tower = "Get up that hill and patch the codes into the tower.",
		Hold = "We're transmitting. Hold the tower, stay close to it!",
		Wave = "More of them coming up the road!",
		Heavy = "Heavy! Big lamp, coming up the hill! Focus fire!",
		Sent = "Signal's out. Nightjar has us. And something else heard it too.",
		Beacon = "That's the Beacon. Main Street pad, now! Call the bird!",
		Missed = "Bird's gone. Call it again!",
		Failed = "Hound is down. Back to the last position.",
	},
	-- Operation Last Light, its own place (ServerScriptService.WarServer there). PlaceId: the
	-- campaign place the lobby's CAMPAIGN sends a party to; LobbyPlaceId: where it goes when it is
	-- over (the experience's start place); ZombiesPlaceId: the place every zombie mode runs in.
	-- Reward: Scrip for each mission done, Complete on top for getting out. AmmoGap: seconds
	-- before a supply crate refills the same player again. Hold: the relay mast transmits for Time
	-- seconds while anyone is within Radius; Squad soldiers come from M2_Road at the seconds in
	-- Waves, the heavy at HeavyAt. LZ: the bird is Inbound seconds out after the call; Squad
	-- soldiers from M3_Road at Waves (seconds since the call), the heavy at HeavyAt.
	Campaign = {
		PlaceId = 78870312741411,
		LobbyPlaceId = 79455872202749,
		ZombiesPlaceId = 121963671263674,
		Reward = { 150, 200, 300, Complete = 250 },
		OutroTime = 6,
		AmmoGap = 20,
		PatchHold = 3,
		CallHold = 1.5,
		Hold = { Time = 90, Radius = 40, Waves = { 4, 25, 50, 70 }, Squad = 4, HeavyAt = 40 },
		LZ = { Inbound = 45, Waves = { 3, 16, 30 }, Squad = 4, HeavyAt = 22 },
		Lines = {
			Drop = "Hound, Nightjar. Your bird is down but you're breathing. Push north to the depot.",
			Depot = "Lamplighters in the depot. Clear it out.",
			DepotClear = "Depot's clear. The relay mast is in the plaza. Move.",
			Plaza = "They're dug in round the mast. Take the plaza.",
			Mast = "Plaza's ours. Patch into the relay, we'll cover you.",
			Hold = "We're transmitting. Hold the mast, stay close to it!",
			Wave = "More of them, coming down the north road!",
			Heavy = "Heavy! Big lamp! Focus fire!",
			Sent = "Signal's out. Nightjar has us. LZ is the basin, north past the yards.",
			Push = "Push through the yards. Keep it tight.",
			LZ = "The LZ is crawling with them. Clear the pad.",
			Call = "Pad's clear. Throw the call, get the bird in.",
			Called = "Nightjar, Hound. Pad is marked, bring it in!",
			Inbound = "Bird's inbound. Hold the pad till it's down!",
			Board = "Bird's down! Grab the ladder, go, go!",
			Missed = "We missed it. Call it again!",
			Complete = "Hound is aboard. Nightjar, we're coming home.",
		},
	},
}

-- Outbreak (HORROR-SHOOTER-MASTER-PLAN.md section 5; MatchServer's Outbreak section), first
-- playable, one squad: the whole town. A hot drop on one of Map.Outbreak.Insertions (zombies
-- awake on the wreck, an ammo crate), strays asleep on the streets (Map.StraySpawns), contracts
-- at the radio posts (Map.Outbreak.RadioPosts) that pay Scrip you carry until you bank it at any
-- radio, the Beacon awake from BeaconAt, and from BirdFrom a helicopter you call to any landing
-- pad (tag LandingPad: the hilltop, Main Street, the Apartments roof). Whoever grabs the ladder
-- gets out with what they carry; at Length the last bird has gone and anyone left is taken.
-- Times in seconds from the drop (DebugTimeScale shortens them in Studio).
GameConfig.Outbreak = {
	Length = 1200,
	BeaconAt = 420,
	BirdFrom = 720,
	LastCall = 120, -- the radio's warning before the end
	WaveEvery = 240, -- zombies toughen up (the wave number) this often
	-- Delay: seconds before the drop's zombies come for you (the menu fade, a look around).
	HotDrop = { Base = 4, PerPlayer = 1, Delay = 5 },
	Town = { Base = 5, PerPlayer = 2, Late = 3, LateFrom = 600, Gap = NumberRange.new(3, 6) },
	Strays = 9,
	StrayRefill = 20,
	StrayClear = 60, -- a new stray stands at least this far from everyone
	RespawnTime = 12,
	LandGrace = 4, -- seconds untouchable after landing on an insertion
	CrateRefill = 60, -- seconds before the same crate gives you ammo again
	BoardsAt = 20, -- the first contract lights up
	ContractGap = 8,
	ContractTime = 180, -- a contract not done by then is lost
	Hold = { Time = 60, Radius = 22, Alive = 5, Gap = NumberRange.new(2, 4), Pay = 150 },
	Hunt = { Count = 5, Health = 1.8, Near = 60, Far = 150, Pay = 150 },
	EscapePay = 100,
	HeliInbound = 40, -- from the call until it's over the pad
	HeliCooldown = 45,
	PadHold = 1.5,
	BankHold = 1.2,
	-- Names on the HUD and in the radio, by post Building and pad PadId.
	Posts = {
		FuelStop = "GAS STATION",
		Shop = "SHOP",
		Clinic = "CLINIC",
		Police = "POLICE STATION",
		Hardware = "HARDWARE STORE",
		Apartments = "APARTMENTS",
		AbandonedHouse = "OLD HOUSE",
		NeighbourHouse = "HOUSE NEXT DOOR",
	},
	Pads = { "HILLTOP", "MAIN STREET", "ROOF" },
	-- The radio (RadioVoice, text-to-speech until recorded). {where} is a post or pad name.
	Lines = {
		Drop = "You're on the ground. Clear the wreck, then find a radio.",
		Boards = "Radio's live at the {where}. Take the contract.",
		Hold = "Hold the radio. Don't let them push you off it.",
		Hunt = "There's a pack out there. Find them and put them down.",
		Done = "Contract done. Bank it at any radio before something takes it off you.",
		Failed = "Contract's gone. Next one's coming up.",
		Beacon = "Something big just woke up. Stay out of its light.",
		Birds = "Birds are flying. Call one at any landing pad.",
		Called = "Bird's inbound to the {where}. Hold the pad.",
		Missed = "Bird's gone. Call another when you're ready.",
		LastCall = "Two minutes. Last bird. Get to a pad.",
	},
}

GameConfig.Menu = {
	-- "Defend" goes back in (second) once MatchServer's playDefend is built (MODES-V3.md).
	Modes = { "Outbreak", "Endless", "Nightmare" },
	RoadCamera = { From = Vector3.new(-58, 6, 266), To = Vector3.new(40, 16, 254) },
	-- Where the menu Beacon walks: weaving across the street toward the camera until it towers
	-- over it, then back off down the road. A stop with Hold would stand there that long.
	BeaconRoute = {
		{ At = Vector3.new(150, 0.75, 263) },
		{ At = Vector3.new(85, 0.75, 249) },
		{ At = Vector3.new(30, 0.75, 252) },
		{ At = Vector3.new(-20, 0.75, 271) },
		{ At = Vector3.new(35, 0.75, 262) },
		{ At = Vector3.new(95, 0.75, 265) },
	},
	BeaconSpeed = 5.5,
	Accent = Color3.fromRGB(255, 176, 60),
	Drift = 0.12, -- how far the camera sways, studs
	Parallax = 0.35, -- how far it leans toward the mouse, studs
	FadeTime = 0.45,
}
-- Squad callouts (SquadVoiceClient, SquadVoiceServer) and the recorded radio (RadioVoice).
-- The lines live in one uploaded file; Shared.VoiceManifest holds its id and where each line
-- sits (made by horror-shooter/voice/gen_voices.py). Until it has an id the squad is silent and
-- the radio falls back to text-to-speech.
GameConfig.Voice = {
	Voices = { "Sarge", "Rook" },
	Volume = 1.6, -- a teammate, from their head
	OwnVolume = 0.75, -- your own lines
	Hear = 140, -- studs a teammate's shout carries
	Gap = 1.6, -- seconds between any two lines from one player
	-- Per line: seconds before it can repeat, the chance it's said, and priority (a higher one
	-- cuts a lower one off).
	Keys = {
		Reload = { Cooldown = 10, Chance = 0.6, Priority = 1 },
		LowAmmo = { Cooldown = 15, Chance = 1, Priority = 2 },
		NoAmmo = { Cooldown = 8, Chance = 1, Priority = 3 },
		Contact = { Cooldown = 0, Chance = 1, Priority = 2 },
		Window = { Cooldown = 25, Chance = 0.8, Priority = 1 },
		Beacon = { Cooldown = 12, Chance = 1, Priority = 4 },
		Hurt = { Cooldown = 7, Chance = 0.8, Priority = 2 },
		Down = { Cooldown = 0, Chance = 1, Priority = 5 },
		TeamDown = { Cooldown = 6, Chance = 1, Priority = 4 },
		Reviving = { Cooldown = 8, Chance = 1, Priority = 3 },
		Revived = { Cooldown = 0, Chance = 1, Priority = 3 },
		Kills = { Cooldown = 12, Chance = 1, Priority = 1 },
		PartGrab = { Cooldown = 0, Chance = 1, Priority = 3 },
		PartIn = { Cooldown = 0, Chance = 1, Priority = 3 },
		GoHome = { Cooldown = 0, Chance = 1, Priority = 3 },
		Bandage = { Cooldown = 10, Chance = 1, Priority = 1 },
		Buy = { Cooldown = 5, Chance = 1, Priority = 2 },
		Runners = { Cooldown = 0, Chance = 1, Priority = 2 },
		Dogs = { Cooldown = 0, Chance = 1, Priority = 2 },
		GoodDog = { Cooldown = 30, Chance = 0.7, Priority = 1 },
		LastNight = { Cooldown = 0, Chance = 1, Priority = 3 },
		Chopper = { Cooldown = 0, Chance = 1, Priority = 4 },
	},
	MultiKill = 3, -- kills inside MultiKillWindow seconds for "Kills"
	MultiKillWindow = 3,
	HurtAt = 15, -- one hit this big says "Hurt"
	BeaconAt = 0.35, -- BeaconSeen past this says "Beacon"
	ContactRange = 45, -- the first zombie this close in a night says "Contact"
	WindowRange = 35, -- a window torn this close says "Window"
	HomeRange = 70, -- farther than this from the house at "Return" says "GoHome"
	-- A zombie's "Kind" attribute: the first one of a kind seen in a match is called out.
	MobKeys = { Runner = "Runners", Dog = "Dogs" },
}

-- The squad's police dog (ServerScriptService.DogServer moves it, StarterPlayerScripts.DogClient
-- poses its bones). One per match; it walks at the heel of the player it follows, goes for any
-- zombie that gets close to them, lies flat while they hide, barks at the Beacon and howls over
-- them when they die. It can't die.
-- The model is the imported Dog (horror-shooter/blender/out_dog), kept in ServerStorage.Dogs.
GameConfig.Dog = {
	Heel = 6, -- studs behind the player it follows
	WalkSpeed = 9, -- trotting to keep up
	RunSpeed = 20, -- running to catch up or to a zombie
	CatchUp = 16, -- farther than this from its spot it runs
	Teleport = 90, -- farther than this (or stuck StuckTime seconds) it is brought back behind them
	StuckTime = 3,
	Guard = 22, -- a zombie this close to the player it follows gets chased
	Leash = 40, -- it gives up a chase this far from that player
	BiteRange = 4.5,
	BiteDamage = 25,
	BiteGap = 0.9,
	BarkRange = 60, -- it barks at the Beacon this close
	BarkGap = { Min = 1.2, Max = 2.6 },
	SitAfter = 4, -- the player still this long: it sits
	HowlTime = 8, -- the player it follows dies: this long sitting by the body, howling every HowlGap seconds
	HowlGap = 3.8,
	-- Further than this from the body when its player dies (the death cam frames the pair from
	-- within it): brought beside the body at once, while the devour's black still covers it.
	HowlReach = 12,
	HipHeight = 1.3,
}

-- Zombie dogs (DogServer): from night FromNight on, a pack comes out of the town every Gap
-- seconds while a night runs. They run down the nearest player who isn't hiding and bite; guns
-- kill them like any zombie (tag Enemy, Kind Dog). Model: the imported ZombieDog.
GameConfig.ZombieDogs = {
	FromNight = 3,
	Pack = { Min = 3, Max = 5 },
	Gap = { Min = 55, Max = 90 },
	MaxAlive = 8,
	Health = 70,
	Speed = 21,
	BiteRange = 4,
	BiteDamage = 10,
	BiteGap = 1.1,
	SpawnAway = 70, -- spawn at a town spot at least this far from every player
	CorpseTime = 5,
}

-- Runners: the fast zombies (RunSpeed). Their eyes burn brighter so you can pick them out.
GameConfig.Runner = {
	EyeColor = Color3.fromRGB(255, 120, 60),
	EyeBrightness = 2.2, -- times the walker's eye light
	EyeRange = 1.6,
}

-- Scrip: what a player earns and keeps between matches (Profile), spent on classes. Paid when a
-- match ends (MatchServer): every night survived (waves in Endless), a share of the points
-- earned that match, and the escape. The VIP pass adds VipBonus on top.
GameConfig.Scrip = {
	PerNight = 30,
	PerWave = 15,
	PointsShare = 0.025,
	Escape = 150,
	VipBonus = 0.2,
}

-- Classes: one perk each, picked on the menu's CLASSES page (SHOP, CLASSES). Rifleman is everyone's from the
-- start; the rest cost Price Scrip (or Robux, once GameConfig.Store.Classes has their ids).
-- Perks are multipliers the game reads through Shared.Classes.Perk(player, key), 1 = untouched:
-- Noise (footsteps the Beacon hears), SeenFill (how fast its Seen meter fills on you),
-- SelfReviveTime, FallDamage, Recoil, RepairPoints (points per board nailed back).
-- Guns and damage are never a perk. Perk is the one line the menu shows for the class.
GameConfig.Classes = {
	Default = "Rifleman",
	Price = 2500,
	-- Menu revamp (DATA, 2 Nov 2026): the eight classes; Shared.Progression.Classes is the source of truth
	-- (Shared.Classes reads it) and this list is the fallback. Classes are unlocked by level or trial, never sold.
	Order = { "Rifleman", "Medic", "Engineer", "Scout", "Hunter", "Firefighter", "Marksman", "Demolition" },
	List = {
		Rifleman = { Perk = "FASTER RELOAD", Perks = { Reload = 0.8 } },
		Medic = { Perk = "FASTER REVIVES, STRONGER BANDAGES", Perks = { ReviveTime = 0.6, BandageHeal = 1.5 } },
		Engineer = { Perk = "FASTER BOARDS, MORE POINTS FOR BOARDS", Perks = { RepairPoints = 1.5, RepairTime = 0.7 } },
		Scout = { Perk = "QUIETER, SLOWER TO BE SEEN", Perks = { Noise = 0.7, SeenFill = 0.8, Sprint = 1.08 } },
		Hunter = { Perk = "MORE DAMAGE TO ELITES", Perks = { EliteDamage = 1.15 } },
		Firefighter = { Perk = "FAST SELF-REVIVE, HALF FALL DAMAGE", Perks = { SelfReviveTime = 0.6, FallDamage = 0.5 } },
		Marksman = { Perk = "LESS RECOIL", Perks = { Recoil = 0.8, EliteStagger = 2 } },
		Demolition = { Perk = "TWO LETHALS, BIGGER BLASTS", Perks = { LethalCount = 2, BlastRadius = 1.25 } },
	},
}

-- The Robux store (StoreServer; the menu's SHOP and CLASS pages; the token row on the downed
-- readout). Products and passes are made on the Creator Dashboard (Monetization) and their ids go
-- here; while an id is 0 its button stays hidden. Guns, damage and dog abilities are never sold,
-- and every class stays earnable with Scrip.
--   StarterPack: once per player. The SHOP opens on it once, after the first escape or the
--     OfferDeaths-th death. Gives Scrip and marks the pack as owned.
--   Vip: game pass: VipBonus more Scrip and a tag in chat.
--   Revive: get up on your own while down with the bleed-out running and no self-revive left,
--     once a match, from night (or wave) FromWave on. If it can't be used when the purchase
--     lands it is kept as a token for the next time.
--   Classes: a product per class (ClassPrice Robux), the other way to unlock one.
GameConfig.Store = {
	StarterPack = { Product = 0, Robux = 99, Scrip = 1000, OfferDeaths = 3 },
	Vip = { Pass = 0, Robux = 299 },
	Revive = { Product = 0, Robux = 25, FromWave = 4 },
	Classes = { Hunter = 0, Firefighter = 0, Marksman = 0, Demolition = 0 },
	ClassPrice = 199,
}

-- Analytics (ServerStorage.Modules.Analytics): the onboarding funnel's steps in order, and how
-- long a player can stand still outside the house in a lull before it's logged as StoodStill.
GameConfig.Analytics = {
	Funnel = { "Menu", "MatchStart", "Night1End", "FirstPart", "Night3", "LastNight", "Escape", "Match2Start" },
	StillTime = 20,
}
return GameConfig
