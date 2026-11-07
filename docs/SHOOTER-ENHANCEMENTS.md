# Last Light: shooter enhancements reference

Research notes, November 2026 (written after the 7 Nov gun feel pass). Nothing in the game was changed while writing this.

This file lists ways to make shooting in Last Light feel better, checked against what the game already does, so the
owner and future Claude sessions can pick one and build it. Every idea says:

- **What** it is, in plain words.
- **From**: where the idea comes from (a GitHub repo, a DevForum post, a talk, a game), with a link.
- **Sketch**: a short strict-Luau sketch that fits our modules. Sketches are starting points, not drop-in code; nothing
  here was run.
- **Plugs into**: the file it would go in.
- **Priority**: do first / later / skip, with one line on why.

Status tags: **DONE** (already in the game; don't rebuild it), **PART** (some of it is in), **NEW**.

Read with: [HORROR-SHOOTER-FEEL.md](HORROR-SHOOTER-FEEL.md) (the feel spec and EgorV's 7 steps),
[HORROR-SHOOTER-HANDOFF.md](HORROR-SHOOTER-HANDOFF.md) (latest state, top section).

**Rules every idea keeps** (from the owner, see the repo's CLAUDE.md):
- No damage numbers over mobs, ever. Hit feedback is markers, sound, flinch and gore only.
- Mob blood is green; less gore on faces; limb tearing stays.
- PC (keyboard and mouse) gets no aim assist. Touch and controller do. Input comes from `Shared.Platform`
  (PreferredInput first, LastInputType as the fallback).
- UI is authored PNG art. A new marker or meter is drawn in the menu art pipeline, never built from script frames.
- Feel numbers live per gun in `GameConfig.Guns.X` (mostly `.Feel` and `.Recoil`), never hard-coded, so a pistol,
  a shotgun and an AK never feel like the same gun.
- Sounds are licensed only (APM, ProSoundEffects, or owned). New cues below are folder names the owner fills.
- Do not touch the gyro files (`Shared.GyroAim`, `TouchControls`, `docs/GYRO-AIM.md`) without checking with whoever
  is working on gyro aim. `Shared.AimAssist` is separate, but a change there affects gyro players too.

---

## Top 10 to build next

Ordered by what players will feel per hour of work. Sizes: S = an evening, M = a day or two.

| # | Idea | Why it's worth it | Where | Size |
|---|---|---|---|---|
| 1 | [Exact fire rate at any frame rate](#12-exact-fire-rate-at-any-frame-rate) | The AK's 600 RPM really fires anywhere from about 450 to 600 depending on frame rate, slowest on phones. | `GunClient` | S |
| 2 | [Zoom-matched aim sensitivity](#22-zoom-matched-aim-sensitivity) | Today the ACOG turns about 75% too fast for its zoom and the 8x about 50%; the formula fixes every optic at once. | `GunClient` | S |
| 3 | [Haptics on phones and controllers](#110-haptics-on-phones-and-controllers) | Roblox's `HapticEffect` now buzzes iPhones, Pixels and Galaxies; a shot you feel in your hand is the cheapest punch there is. | new `Shared.GunHaptics`, `GunClient` | S |
| 4 | [Bullet magnetism for touch and controller](#24-aim-assist-on-touch-and-controller) | Bends the round, not the camera, so a near miss lands without the view being dragged. Works for gyro too. | `Shared.AimAssist`, `GunClient` | M |
| 5 | [Gunshots by distance, with travel delay and room tails](#19-gunshots-by-distance) | Every shot sounds the same at 5 and 400 studs now. Distance layers are how big shooters sell space. | new `Shared.GunAudio`, `GunClient` ShotFx handler | M |
| 6 | [Surface table for impacts and brass](#32-surfaces-impacts-brass-and-terrain) | Snow, dirt, wood and glass have no sounds of their own, and Terrain hits read the wrong material. | `CombatFx`, `GunClient`, `GameConfig` | M |
| 7 | [One trauma value for screen shake](#13-one-trauma-value-for-screen-shake) | Shake from shots, hits, kills and blasts stacks into a buzz under fire; trauma keeps big moments big. | new `Shared.Trauma`, `GunClient` | S |
| 8 | [Sticky aim-assist target in a horde](#24-aim-assist-on-touch-and-controller) | The assist re-picks its target every 0.08 s, so in a crowd it hops between zombies. | `Shared.AimAssist` | S |
| 9 | [Bullets through wood](#33-bullets-through-walls) | Shooting a zombie through the boards it's tearing at is the siege loop's best moment; stone and metal still stop rounds. | `GunClient.castShot`, `GunServer`, `GameConfig` | M |
| 10 | [Cosmetic ShotFx on an unreliable remote](#53-cosmetic-shotfx-on-an-unreliable-remote) | Tracers and flashes of other players never queue behind a lost packet. | `GunServer`, `GunClient` | S |

---

## What the game already does (don't rebuild)

| Feel | Where it lives | Notes |
|---|---|---|
| Same-frame kick, flash and sound on the click | `GunClient.fire` | Step 1 of EgorV's method. Nothing waits on the server. |
| Springs for recoil, sway, shake, FOV punch | `Shared.Spring`, `GunClient` (`swaySpring`, `kickSpring`, `camSpring`, `shakeSpring`, `fovSpring`) | Fixed 1/120 s substeps. |
| Learnable recoil pattern, harder first shot, camera roll, held climb that settles minus what you pulled down | `Shared.GunFeel` (`Shot`, `Climb`, `Recover`) | Per fire mode (`CLASS`), overrides in `GameConfig.Guns.X.Recoil`. |
| Gun weight: strafe lean, jump lift, landing thump, ADS settle kick | `GunFeel.Motion` | |
| Look sway (lag), walk bob, idle breathing, sprint pose | `GunClient.update` | Bob scaled by the `Bob` option. |
| Per-gun muzzle flash styles, light on the walls, sparks and smoke | `Shared.MuzzleFx`, `CombatFx.MuzzleLight` | Others' shots flash too. |
| Brass and dropped mags that stay on the floor | `CombatFx.Casing`, `CombatFx.DroppedMag` | One landing sound for every surface (see 3.2). |
| Hitmarker for hit / head / kill (colour and pop), hit, head and kill sounds, kill crunch | `GunClient.showHitmarker`, `Remotes.HitConfirm` | No numbers, by the owner's rule. |
| Layered shot sound (Crack, Body, Tail) with variants and pitch nudges | `Shared.SoundKit.PlayLayers` | Same layers at every distance (see 1.9). |
| Beam tracers with tails and travel speed; whiz when someone else's round passes you | `CombatFx.Tracer` | |
| Material classes: glass shatters, wood breaks where it's hit, stone chips, metal dents | `WorldDamage`, `CombatFx.WorldImpact` | Siege-style holes per gun `BreakRadius`. |
| Penetration through mobs (sniper: 3 bodies at 100/75/56%) | `GunClient.castShot`, `Penetration` | Walls still stop every round (see 3.3). |
| ADS (`AimTime`, `AimFov`, `AimDistance`), scopes with sway, hold breath, blackout, zoom-scaled shake | `GunClient` (`setScoped`, `scopeSway`) | Optics change `AimFov` (`Shared.Attachments`). |
| Look, aim and controller sensitivity, invert, FOV options | `GameConfig.Settings`, `GunClient` | Per-gun `AimSensitivity` (see 2.2). |
| Touch and controller aim assist: slowdown, rotational tracking, magnet; presets; line of sight; none on PC | `Shared.AimAssist`, `GameConfig.AimAssist` | Duel has weaker PvP presets. |
| Mob reactions: hit flash, squash, joint jolt, stagger slow, knockback, limb health, tearing, crawling, swing interrupt | `CombatFx`, `MobImpact`, `MobReactions` | All data in `GameConfig.Mobs`. |
| Kill: freeze, then throw the body (on the shooter's screen at once) | `KillPredict` (local copy anchored for `KillFreeze`), `MobReactions` | Body hit-stop is done; shooter-side hit-stop is not (1.7). |
| Client hits, server validation (origin, ray miss, part offset, fire rate, cone) | `GunClient`, `GunServer`, `GameConfig.Validation` | |
| Duel lag compensation: body-part ring buffer, rewind to the client's shot time, capped | `src/duel` `HitHistory`, `GunServer.shotTiming` | Uses the client's shot time and ping. |
| Input buffer (a click 0.2 s early still fires), shell reload interrupt | `GunClient.tryFire` | |
| Gun weight slows walking | `Shared.Attachments.GunWeight` | |
| Third-person view, shots from the head to the crosshair point | `Shared.ViewMode` | |

---

## 1. Gunshot feel

### 1.1 Camera kick and recoil pattern — DONE

**What.** Each shot kicks the view; part of the climb holds while the trigger is down and comes back after the burst;
the spray drifts left and right on a pattern that is the same every time, so players learn to pull against it.

**From.**
- Phantom Forces, as reverse-engineered on the DevForum (not by StyLiS): a first-shot camera bump, recovery that
  starts after about 0.05 s and gives back about half the recoil, and a sideways pattern that resets after a 0.5 s
  gap. <https://devforum.roblox.com/t/recoil-implementations/225453>. Ours is close: `BURST_GAP` 0.32 s,
  `HOLD_AFTER` 0.1 s, recovery minus the player's pull-down.
- Rainbow Six Siege Y7S3 designer's notes: vertical recoil was raised on all ARs, SMGs and LMGs so they stop being
  "laser beams", the biggest magazines kick hardest under sustained fire, and recoil attachments became the counter.
  <https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/2vKaDckg5VPV1ViA4p8KM/y7s3-preseason-designers-notes>
- VALORANT Patch 3.0: walking and running inaccuracy raised to reward stopping before you shoot (our `Spread.Move`).
  <https://playvalorant.com/en-us/news/game-updates/valorant-patch-notes-3-0/>
- Jaime Griesemer, GDC 2010 (Halo 3): one number, the sniper's time between shots (0.5 to 0.7 s), changed the gun's
  whole role. Tune a gun's rate to its role first. <https://gdcvault.com/play/1012211>

**Still worth adding (later):** a recoil test board in the test range. Each shot leaves a dot, coloured by its place
in the spray, on a wall 20 studs away, so a gun's pattern can be seen and tuned in one spray.

```lua
-- A dev-only client script: mark where each round lands on the board.
local board = workspace:WaitForChild("TestRange"):WaitForChild("RecoilBoard") :: BasePart
local function markShot(index: number, at: Vector3)
	local dot = Instance.new("Part")
	dot.Anchored, dot.CanCollide, dot.CanQuery = true, false, false
	dot.Shape = Enum.PartType.Cylinder
	dot.Size = Vector3.new(0.05, 0.25, 0.25)
	dot.Color = Color3.fromHSV((index % 30) / 30, 0.8, 1) -- shot order reads as a colour ramp
	dot.CFrame = CFrame.lookAt(at, at + board.CFrame.LookVector) * CFrame.Angles(0, math.rad(90), 0)
	dot.Parent = workspace.Fx
end
```

**Plugs into:** a dev tool next to `TestRangeServer`; the client already knows `world.Position` per round in `fire()`.
**Priority:** later. Tuning aid only; the pattern itself is done.

### 1.2 Exact fire rate at any frame rate

**NEW.** **What.** `canShootNow` checks `now - state.lastShot >= 60 / gun.RPM`, and `fire()` sets `state.lastShot = now`.
A round can only leave on a frame, so every shot waits for the first frame after the interval and the leftover time is
thrown away. The AK's 0.1 s interval lands on 6 frames at 60 fps only when float noise allows; otherwise it takes 7.
At 45 fps it always takes 5 frames (0.111 s, 540 RPM), and on a 30 fps phone 3 or 4 (450 to 600 RPM). The fix is the
classic accumulator: keep the leftover, so the next round is due a little sooner after a late frame.

**From.** Glenn Fiedler, "Fix Your Timestep!": the leftover time "is passed on to the next frame via the accumulator
variable and is not thrown away". <https://gafferongames.com/post/fix_your_timestep/>

**Sketch.**

```lua
-- GunClient.fire(continuing: boolean?): replaces `state.lastShot = now`. `continuing` is true only for the
-- full-auto loop below; a click, a queued shot and the first round of a spray pass nothing.
local function stampShot(now: number, interval: number, continuing: boolean?)
	if continuing and now - state.lastShot < interval * 3 then
		state.lastShot += interval -- keep the leftover: a late frame makes the next round due sooner
	else
		state.lastShot = now -- first round, or after a hitch (never fire a backlog)
	end
end

-- GunClient.update(), full auto: one long frame may owe two rounds (a slow phone on a fast gun).
local fired = 0
while fired < 2 and state.triggerHeld and state.mag > 0 and canShootNow(now) do
	fire(true) -- the press itself fired through tryFire(); a stale lastShot resets inside stampShot
	fired += 1
end
```

Walk-through at 0.15 s frames and 600 RPM: rounds leave at 0, 0.15, then two at 0.30 (due at 0.2 and 0.3), so
four rounds by 0.3 s, as the gun's rate says. The cap of two per frame and the 3-interval reset stop a hitch from
dumping a backlog.

**Plugs into:** `GunClient.fire` (first lines) and the `gun.FireMode == "Auto"` block in `GunClient.update`. The server
already allows bunched shots (`Validation.FireRateTolerance` 0.75, `MaxShotsPerSecond` 15, and the duel shot bucket).
**Priority:** do first. A few lines, and every auto gun fires at its real rate on every device.

### 1.3 One trauma value for screen shake

**NEW.** **What.** Today `shake(degrees)` adds a random kick to `shakeSpring` on every call: each AK round, each hit,
each kill, each landing. Under sustained fire they pile into a constant buzz, and a kill's shake is lost in it.
Squirrel Eiserloh's "trauma" model instead keeps one number from 0 to 1. Events add to it, it drains at a steady rate,
and the shake is trauma squared times smooth noise, so small events barely show and big ones stand out. Rotation only;
moving the camera position makes aiming feel loose.

**From.**
- Squirrel Eiserloh, GDC 2016, "Math for Game Programmers: Juicing Your Cameras With Math":
  <https://www.youtube.com/watch?v=tu-Qe66AvtY> (Vault <https://gdcvault.com/play/1023557/Math-for-Game-Programmers-Juicing>).
  Bevy's example that follows the talk uses trauma 0 to 1 decaying 0.5 a second, shake = trauma², Perlin noise per
  channel, roll up to 10°: <https://bevy.org/examples/camera/2d-screen-shake/>. A gun adds trauma many times a second,
  so ours decays faster (1.6).
- Jan Willem Nijman (Vlambeer), "The art of screenshake": <https://www.youtube.com/watch?v=AJdEqssNZ-U>; write-up
  <https://www.gamedeveloper.com/design/vlambeer-co-founder-shares-advice-on-building-better-action-games>. One of his
  rules: shake *away from* the direction of fire. Our recoil kick already does that; trauma is for the rest.
- Roblox ports: Sleitnick's EZ Camera Shake port <https://github.com/Sleitnick/RbxCameraShaker> (presets such as
  Bump: magnitude 2.5, roughness 4, fade in 0.1 s, out 0.75 s) and the newer RbxUtil Shake with distance falloff
  <https://sleitnick.github.io/RbxUtil/api/Shake>.

**Sketch.**

```lua
--!strict
-- Shared.Trauma: one screen-shake value for shots, hits, kills and blasts.
local Trauma = {}

local MAX = Vector3.new(math.rad(2.2), math.rad(2.8), math.rad(3.5)) -- pitch, yaw, roll at full trauma
local DECAY = 1.6 -- trauma lost per second
local FREQ = 18 -- noise speed

local trauma = 0

function Trauma.Add(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

-- zoom: 1 at hip, smaller behind a scope (GunClient already scales shake by FOV / hip FOV).
function Trauma.Step(dt: number, now: number, zoom: number): Vector3
	trauma = math.max(0, trauma - DECAY * dt)
	if trauma <= 0 then
		return Vector3.zero
	end
	local s = trauma * trauma * zoom
	local t = now * FREQ
	return Vector3.new(
		MAX.X * s * math.clamp(math.noise(t, 0.31) * 2, -1, 1),
		MAX.Y * s * math.clamp(math.noise(t, 4.7) * 2, -1, 1),
		MAX.Z * s * math.clamp(math.noise(t, 9.1) * 2, -1, 1)
	)
end

function Trauma.Reset()
	trauma = 0
end

return Trauma
```

**Plugs into:** `GunClient.shake` becomes `Trauma.Add(degrees * k)` (k tuned so the AK's `Feel.Shake` 0.38 per shot
adds about 0.06); `GunClient.update` adds `Trauma.Step(...)` where it now adds `shakeSpring:Update(dt)`. Recoil stays on
`camSpring`, which is deterministic and learnable. A "Screen shake" slider would need an authored Settings row.
**Priority:** do first. Small, and it makes kills and explosions read again during a spray.

### 1.4 Viewmodel sway, bob and ADS settle — DONE

**What.** The gun lags the look, bobs with steps, breathes at rest, leans into strafes, lifts on jumps, thumps on
landings and settles with a small kick going into aim.

**From.** EgoMoose, "The First Person Element Of A First Person Shooter" (viewmodel on the camera, `Aim` part for ADS)
<https://devforum.roblox.com/t/the-first-person-element-of-a-first-person-shooter/160434>; BlackShibe, "Writing an
FPS framework (2020)" (three springs: sway from mouse delta, bob scaled by speed, recoil shove; order offset, bob,
sway, recoil) <https://devforum.roblox.com/t/writing-an-fps-framework-2020/503318>. Industry: Infinity Ward on
Modern Warfare (2019) animation, an "active idle" of quick small moves rather than a slow sway, the head leads a look
and the gun follows, weight per class (an LMG is stiffer than a rifle)
<https://blog.activision.com/call-of-duty/2019-07/Modern-Warfare-Initial-Intel-Detailing-Advancements-in-Animation-and-Authenticity>;
Matthew Boehm, "The First Person Animation of Overwatch" (GDC 2017) <https://www.gdcvault.com/play/1024319/>;
David Helsby, "The Art of First Person Animation for Destiny" (GDC 2015) <https://gdcvault.com/play/1022297/>.

**Priority:** skip. Done, and ours already goes further (strafe lean, landing thump, ADS settle).

### 1.5 Muzzle flash and light — DONE

`Shared.MuzzleFx` gives each gun family its own flash; `CombatFx.MuzzleLight` lights the walls; other players' and
soldiers' shots flash too. **Priority:** skip.

### 1.6 Brass and mags — DONE (sound by surface is 3.2)

Casings eject with the carrier's velocity and stay; mags drop and stay. Every casing lands with the same
`Common/Casing` cue, so it rings on snow the same as on concrete; the surface table in 3.2 fixes that.
**From** (for the throw numbers we already use): <https://devforum.roblox.com/t/shell-ejecting-for-guns/460933>.
**Priority:** skip here; build it as part of 3.2.

### 1.7 Hit-stop on the shooter's side — PART

**What.** The body hit-stop is done: on a kill the local copy of the mob freezes for the gun's `KillFreeze`
(0.03 to 0.1 s), then flies (`KillPredict`). What's missing is the shooter's own side: on a kill, the gun and the
camera springs hold for two or three frames and release with the kill sound, like a fighting game's hit pause. In a
multiplayer shooter only the local view may pause, never the world.

**From.** Masahiro Sakurai, "Stop for Big Moments!" <https://www.youtube.com/watch?v=OdVkEOzdCPw> and "Eight Hit
Stop Techniques" <https://www.youtube.com/watch?v=tycbMSjDDLg> (keep any slow-down brief, then snap back). Background,
with Street Fighter 2's roughly 10-frame freeze: <https://critpoints.net/2017/05/17/hitstophitfreezehitlaghitpausehitshit/>.
Quenty's Nevermore Spring reads its state from a clock you pass in, which is the cleanest way
to pause springs: <https://quenty.github.io/NevermoreEngine/api/Spring>.

**Sketch.**

```lua
-- GunClient: hold the gun and camera springs for a moment on a kill.
local holdUntil = 0

local function hitPause(seconds: number)
	holdUntil = math.max(holdUntil, os.clock() + seconds)
end

-- In update(), before the springs step: a held frame advances them by no time at all.
local springDt = if os.clock() < holdUntil then 0 else dt
-- kickSpring:Update(springDt), camSpring:Update(springDt), GunFeel.Motion(springDt, ...)
-- (the look input, the HUD and the world keep running on dt)
```

Call `hitPause(feel.KillPause or 0.04)` where `fire()` handles `predictedKill`.
**Plugs into:** `GunClient.fire` and `GunClient.update`; `KillPause` per gun in `GameConfig.Guns.X.Feel`.
**Priority:** later. Try 0.03 to 0.05 s once; if it reads as a hitch instead of weight, drop it.

### 1.8 Hit markers and kill confirm without numbers — DONE (small additions)

**What's in.** Hit, head and kill markers (white, amber, red, with a size pop), hit and kill sounds, a kill crunch for
headshots and multi-kills from one blast, and the server's `HitConfirm` covering kills the client did not predict.

**Additions.**
- **Multi-kill ladder (later).** Each kill within 4.5 s of the last plays the kill sound a step higher (cap 4 steps),
  so a good run sounds like one. Halo uses a 4.5 s window between kills for its multikills since Halo 4 (4 s before):
  <https://www.halopedia.org/Double_Kill>.
- **Authored marker art (later).** The marker is four authored Frame lines. A PNG set (hit tick, head tick, kill X)
  from the menu art pipeline would match the owner's UI rule and let the kill marker have its own shape.
- **Kill credit in co-op** if assists or shared points are added: keep a server ledger of who hurt each mob and settle
  credit once on death, so ten pellets never count ten times.
  <https://devforum.roblox.com/t/how-do-i-confirm-a-kill-consistently/328295>

```lua
-- GunClient: the kill sound climbs with a quick run of kills.
local streak, lastKill = 0, -math.huge
local function killSound()
	local now = os.clock()
	streak = if now - lastKill <= 4.5 then math.min(streak + 1, 4) else 0
	lastKill = now
	SoundKit.Play("Common/Kill", { Speed = 1 + 0.06 * streak })
end
```

**Plugs into:** `GunClient.fire` (predicted kills) and the `HitConfirm` handler.
**Priority:** later. The core is done; these are polish.

### 1.9 Gunshots by distance

**PART.** **What.** Our shot is three layers (Crack, Body, Tail) with variants, and someone else's shot plays the same
three layers at their position, cut off past 500 studs. Big shooters change *which* layers you hear with distance and
place:
- **Close** (under ~60 studs): sharp crack and body, plus the gun's mechanics.
- **Mid** (~40 to 300): body and tail, crack fading out.
- **Far** (~200 to 1,200): a dull, low "distant" boom only.
- **Late**: sound travels slower than light. The flash shows at once; the boom arrives `distance / speed` later
  (about a third of a second at 400 studs), which reads as distance more than volume does.
- **Room**: a short slap indoors, a long rolling echo outdoors, chosen by a roof check over the shooter.
Your own shots keep the full close set (2D, as now) with the room tail added.

**From.**
- Infinity Ward, Modern Warfare (2019) weapon sound: about 90 microphones per shot, separate hip and ADS takes, a
  contextual atmosphere layer on every shot, and reflections placed at nearby geometry and delayed at the speed of
  sound.
  <https://blog.activision.com/call-of-duty/2019-07/Modern-Warfare-Initial-Intel-Creating-an-Orchestra-of-Incredible-Audio-Effects-Weapon-Sounds-in-Call-of-Duty-Modern-Warfare>
- PUBG: the shot arrives late at 340 m/s, samples blend by distance, a suppressor changes the falloff; a near miss
  whizzes in a wide radius and cracks in a small one. <https://www.pcgamer.com/how-gunshot-sounds-work-in-playerunknowns-battlegrounds/>
- Hunt: Showdown (Crytek): an occlusion ray to the listener, more muffled through denser surfaces, and enemy guns in
  their own mix so distance can be judged. <https://www.huntshowdown.com/news/hunt-audio-readability-realism-and-consistency>
- DICE, "Adaptive Mixing in Frostbite" (HDR audio: the loudest sounds decide what stays audible, so a nearby blast
  ducks distant rifles): <https://www.slideshare.net/slideshow/adaptive-mixing-in-frostbite/3128152>
- Frontlines (Maximillian Studios) spent six months of one person on weapon audio, including how sound reflects off
  different surfaces (Roblox newsroom, 1 Jul 2026):
  <https://about.roblox.com/newsroom/2026/07/roblox-studio-fidelity-creator-interviews-twin-atlas-fluorlite-maximillian-ecos>
- Roblox's Audio API does distance curves per emitter: `AudioEmitter:SetDistanceAttenuation({ [10] = 1, [100] = 0.4,
  [300] = 0 })` <https://create.roblox.com/docs/reference/engine/classes/AudioEmitter>, and the docs now call
  `Sound` / `SoundGroup` "discouraged" in favour of audio objects <https://create.roblox.com/docs/audio/objects>.
  `AudioFilter`'s own sample drops a low-pass to 500 Hz when a raycast finds a wall
  <https://create.roblox.com/docs/reference/engine/classes/AudioFilter>.
- Acoustic Simulation left beta on 22 Sep 2026: occlusion, sound bending round corners and reverb from the level's
  geometry, Audio API only <https://devforum.roblox.com/t/full-release-acoustic-simulation-emit-audio-with-presence/4307121>.

**Sketch** (works with today's `SoundKit`, which multiplies `Volume` and returns nil for a missing cue, so a gun
without the new folders simply skips them):

```lua
--!strict
-- Shared.GunAudio: someone else's shot, heard by distance and place.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SoundKit = require(Shared:WaitForChild("SoundKit"))

local GunAudio = {}

local SOUND_SPEED = 1100 -- studs per second; a tuning number (about 343 m/s at roughly 0.3 m a stud)
local MAX_HEAR = 1200

type Band = { From: number, Full: number, Fade: number, To: number } -- fades in From..Full, out Fade..To
local BANDS: { [string]: Band } = {
	Crack = { From = 0, Full = 0, Fade = 40, To = 110 },
	Body = { From = 0, Full = 0, Fade = 120, To = 300 },
	Tail = { From = 0, Full = 0, Fade = 350, To = 700 },
	Distant = { From = 150, Full = 300, Fade = 900, To = MAX_HEAR },
}

local function weight(d: number, b: Band): number
	if d < b.From or d > b.To then
		return 0
	end
	local up = if b.Full > b.From then math.clamp((d - b.From) / (b.Full - b.From), 0, 1) else 1
	local down = if b.To > b.Fade then 1 - math.clamp((d - b.Fade) / (b.To - b.Fade), 0, 1) else 1
	return up * down
end

local roof = RaycastParams.new()
roof.FilterType = Enum.RaycastFilterType.Exclude

function GunAudio.UnderRoof(at: Vector3, ignore: { Instance }): boolean
	roof.FilterDescendantsInstances = ignore
	return workspace:Raycast(at, Vector3.new(0, 60, 0), roof) ~= nil
end

-- sounds: the gun's Feel.Sounds folder ("Guns/AK"). Layers: Crack, Body, TailIn / TailOut, Distant.
function GunAudio.Remote(sounds: string, from: Vector3, listener: Vector3, volume: number?, ignore: { Instance })
	local d = (from - listener).Magnitude
	if d > MAX_HEAR then
		return
	end
	local tail = if GunAudio.UnderRoof(from, ignore) then "TailIn" else "TailOut"
	task.delay(d / SOUND_SPEED, function()
		for name, band in BANDS do
			local w = weight(d, band)
			if w > 0.01 then
				local layer = if name == "Tail" then tail else name
				SoundKit.Play(sounds .. "/" .. layer, { Position = from, Volume = (volume or 1) * w })
			end
		end
	end)
end

return GunAudio
```

**Plugs into:** the `Remotes.ShotFx` handler in `GunClient` (replace its `SoundKit.PlayLayers` line; keep the 500-stud
cut-off for tracers, not for sound) and `fire()` for your own tail. New sound folders per gun in
`Assets.Sounds.Guns.<Gun>`: `Distant`, `TailIn`, `TailOut`, with `RollOffMaxDistance` raised on Distant and the tails
so Roblox's own rolloff doesn't silence them first. Long term, move `SoundKit` onto `AudioPlayer` / `AudioEmitter`
so each layer gets its own distance curve and Acoustic Simulation can do occlusion and reverb for us.
**Priority:** do first for the remote-shot layers and travel delay (the code is small; the owner needs to pick
`Distant` and tail sounds). Later for the move to the Audio API.

### 1.10 Haptics on phones and controllers

**NEW.** **What.** A short buzz in the hand on each shot (strength and length per gun), a heavier thump on a kill, a
long rumble for a shotgun blast or an explosion. Nothing on PC.

**From.** Roblox `HapticEffect`: "waveform-based haptic feedback (vibrations and rumbles) on supported controllers and
mobile devices", including "most iPhone, Pixel, and Samsung Galaxy devices", PlayStation and Xbox pads.
Custom waveforms are `FloatCurveKey`s (time in milliseconds, value 0 to 1).
<https://create.roblox.com/docs/reference/engine/classes/HapticEffect>

**Sketch.**

```lua
--!strict
-- Shared.GunHaptics: a buzz you feel on shots and kills (touch and controller only).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Platform = require(Shared:WaitForChild("Platform"))
local Options = require(Shared:WaitForChild("Options"))

local GunHaptics = {}

export type Pulse = { Peak: number, Length: number } -- 0..1, milliseconds

local cache: { [string]: HapticEffect } = {}

local function effectFor(key: string, pulse: Pulse): HapticEffect
	local found = cache[key]
	if found then
		return found
	end
	local e = Instance.new("HapticEffect")
	e.Type = Enum.HapticEffectType.Custom
	e:SetWaveformKeys({
		FloatCurveKey.new(0, pulse.Peak, Enum.KeyInterpolationMode.Linear),
		FloatCurveKey.new(pulse.Length, 0, Enum.KeyInterpolationMode.Linear),
	})
	e.Parent = workspace
	cache[key] = e
	return e
end

function GunHaptics.Play(key: string, pulse: Pulse?)
	if not pulse or Platform.Get() == "KeyboardAndMouse" or Options.Get("Vibration") == false then
		return
	end
	local e = effectFor(key, pulse)
	e:Stop()
	e:Play()
end

return GunHaptics
```

Config: `GameConfig.Guns.AK.Feel.Haptic = { Peak = 0.35, Length = 35 }`, Pistol `{ 0.45, 30 }`, Shotgun `{ 1, 90 }`,
Sniper `{ 0.9, 70 }`; `GameConfig.Haptics.Kill = { Peak = 0.8, Length = 60 }`.
**Plugs into:** `GunClient.fire` (`GunHaptics.Play(gunName, feel.Haptic)` next to the shot sound; the kill pulse where
`predictedKill` is handled). A "Vibration" option needs an entry in `GameConfig.Settings` and an authored Settings row.
**Priority:** do first. Small, and a phone shooter that buzzes on every shot feels twice as heavy.

---

## 2. Aiming

### 2.1 Aim down sights and scopes — DONE

ADS blends position, FOV and spread over each gun's `AimTime`; a scope swaps to the authored reticle with sway, held
breath and a blackout fade; shake is scaled down by zoom. Optics from `Shared.Attachments` change `AimFov`.

**Later ideas.**
- **A second sight on one gun** (a backup dot over a scope, toggled with a key), from Carbon Engine's several aim parts
  per gun ("Alternate Zoom (AimPart2)"). Carbon Engine itself is discontinued.
  <https://devforum.roblox.com/t/ce-carbon-engine-revolutionary-fps-combat-technology/872472>
- **Scope glint** in the duel: a small flare on a sniper's lens seen by the player it points at. Duel only.

**Priority:** later for both.

### 2.2 Zoom-matched aim sensitivity

**NEW.** **What.** While aiming, mouse look is `LookSens × gun.AimSensitivity × AimSens` (0.6 to 0.75), and behind a
scope `LookSens × scope.Sensitivity × AimSens`. Those numbers were picked by hand and don't follow the zoom, so optics
that zoom further turn too fast. Matching the zoom means one mouse movement turns the crosshair over the same part of
the screen at every zoom. With the default 74° FOV the 0%-match ratio is `tan(zoomFov / 2) / tan(hipFov / 2)`:

| Sight | FOV | Today | Matched | Today vs matched |
|---|---|---|---|---|
| AK irons | 55 | 0.70 | 0.69 | right |
| Holo on AK | 45 | 0.70 | 0.55 | 27% fast |
| ACOG 3x on AK | 24 | 0.49 | 0.28 | 74% fast |
| Sniper scope | 14 | 0.22 | 0.16 | 35% fast |
| Recon 8x | 8 | 0.14 | 0.09 | 51% fast |

It also follows the player's FOV option by itself. A `match` setting above 0 matches a point further out from the
crosshair (many players like a little faster at high zoom); `AimSens` stays as the player's own multiplier on top.

**From.**
- Battlefield ships this as "Uniform Soldier Aiming": zoomed sensitivity follows the zoom, with a coefficient (0 to
  300, default 133) that picks how far from the crosshair the match is made (EA's Battlefield 2042 settings page):
  <https://ea.com/able/resources/battlefield-2042/pc/mouse-and-keyboard>. Our `match` is that coefficient divided
  by 100 (so Battlefield's default is `match = 1.33`).
- Counter-Strike's well-known `zoom_sensitivity_ratio` of 0.818933 is the same 0% match for its sniper zoom:
  0.818933 × 40 / 90 = 0.364 = tan(20°) / tan(45°). (Checked by hand; the formula is the standard one the sensitivity
  converters use, with `atan(c · tan(fov / 2))` for a coefficient c above 0.)

**Sketch.**

```lua
-- GunClient (or Shared.GunFeel): sensitivity multiplier for a zoomed view.
-- match = 0 keeps the crosshair's speed the same at every zoom; 0.5 matches halfway to the screen edge.
local function zoomSensitivity(hipFov: number, fov: number, match: number): number
	local h = math.tan(math.rad(hipFov) / 2)
	local z = math.tan(math.rad(fov) / 2)
	if match <= 0 then
		return z / h
	end
	return math.atan(match * z) / math.atan(match * h)
end

-- In update(), replacing the AimSensitivity / scope.Sensitivity factors. Use the sight's FOV, not the camera's,
-- so the sprint FOV bonus and the FOV punch never change sensitivity.
local hipFov = Options.Get("Fov")
local sightFov = if state.scoped then scope.Fov else hipFov + (gun.AimFov * hipFov / CAM.HipFov - hipFov) * aim
local ratio = zoomSensitivity(hipFov, sightFov, CAM.ZoomMatch or 0)
local sensitivity = Options.Get("LookSens") * ratio * (1 + (Options.Get("AimSens") - 1) * math.max(aim, if state.scoped then 1 else 0))
```

**Plugs into:** the "Mouse look" block in `GunClient.update`; `GameConfig.Camera.ZoomMatch`. `AimAssist.Step` already
derives controller speed from `sensitivity / LookSens`, so pads follow too. `AimSensitivity` mods on optics in
`Shared.Attachments` (the ACOG's 0.7) become unnecessary.
**Priority:** do first. One function, and every scope and optic feels right on PC.

### 2.3 Controller stick curve and turn ramp

**NEW.** **What.** A deadzone, a response curve (small stick moves are fine, full stick is fast) and a turn ramp:
after the stick has been held fully sideways for a moment, the yaw speeds up so you can turn round in a fight.

**From.** Roblox's own Freecam uses `K_CURVATURE = 2.0` and `K_DEADZONE = 0.15` for its thumbstick curve (seen in the
copy shipped in Adonis): <https://github.com/Epix-Incorporated/Adonis/blob/master/MainModule/Server/Dependencies/Assets/Freecam/Freecam.client.lua>.
Apex Legends' Advanced Look Controls are the reference set: deadzone, outer threshold, response curve, extra yaw
at full stick, and a ramp-up time and delay before the extra yaw comes in (community guide, not Respawn's own page):
<https://gamersdecide.com/articles/apex-legends-best-alc-settings>.

**Sketch.**

```lua
-- A stick axis in -1..1 to a look rate in -1..1.
local function stickCurve(x: number, dead: number, expo: number): number
	local m = math.abs(x)
	if m <= dead then
		return 0
	end
	return math.sign(x) * ((m - dead) / (1 - dead)) ^ expo
end

-- Turn ramp: full sideways for RampDelay seconds adds up to RampBoost extra yaw over RampTime.
local held = 0
local function turnBoost(stickX: number, dt: number, cfg: { RampDelay: number, RampTime: number, RampBoost: number }): number
	held = if math.abs(stickX) > 0.95 then held + dt else 0
	return 1 + cfg.RampBoost * math.clamp((held - cfg.RampDelay) / cfg.RampTime, 0, 1)
end
```

**Plugs into:** `Shared.AimAssist.Step`, where controller speed is applied today. Roblox's camera module already
curves the stick before we see it, so measure what it does first (log raw `Thumbstick2` against the look delta) and
only undo or reshape it if needed.
**Priority:** later. Phones come first; controllers are a smaller share.

### 2.4 Aim assist on touch and controller

**DONE** (the base) — `Shared.AimAssist`: slowdown over a target, rotational tracking of its movement while you look
or move, a gentle pull toward the chest while steering, stronger when aimed, presets (Standard / Precision / Off),
line of sight, nothing with the stick still, nothing on PC. Duel has weaker PvP presets.

**From.**
- Nick Weihs (Insomniac), "Techniques for Building Aim Assist in Console Shooters" (GDC 2013): stick acceleration and
  deadzones first, then magnetism, centring and friction. <https://www.gdcvault.com/play/1017942/Techniques-for-Building-Aim-Assist>
- Adrian Chmielarz, "Aim Assist in Witchfire": rings on the gun, not bigger enemy hitboxes; two outer rings for
  friction, a magnetism ring that pulls the shot, a hit ring, an inner ring that prefers the head; strength grows to
  the gun's effective range and drops fast past it. <https://www.theastronauts.com/2019/02/witchfire-aim-assist/>
- Call of Duty: Black Ops 7 preseason notes: full rotational assist only while the right stick tracks the target;
  strafing with the left stick alone gets a reduced share.
  <https://www.callofduty.com/patchnotes/2025/11/call-of-duty-black-ops-7-preseason-patch-notes>
- Apex Legends "Shockwave" notes: assist cut for controller on PC, but it "will never be removed" because it is an
  accessibility feature. <https://www.ea.com/games/apex-legends/apex-legends/news/shockwave-patch-notes>
- Mobile: "UX Deep Dive: Painful reality of building FPS experiences on mobile" (acquire, lead, track; aim assist and
  auto-fire as the answers). <https://www.gamedeveloper.com/game-platforms/ux-deep-dive-painful-reality-of-building-fps-experiences-on-mobile-part-1>
- Gyro: Jibb Smart, "Good Gyro Controls Part 1: The Gyro is a Mouse", which advises turning aim assist off while gyro
  aiming. <https://gyrowiki.jibbsmart.com/blog:good-gyro-controls-part-1:the-gyro-is-a-mouse>. Worth raising with the
  gyro work: slowdown fights a gyro the way it would fight a mouse; bullet magnetism (2.4a) doesn't.

On Roblox: Redshift: Arena's 2018 write-up (a ring from `Camera:ViewportPointToRay`,
lower sensitivity on target, magnetism as a bigger hitbox)
<https://devforum.roblox.com/t/how-to-make-aim-assist-and-a-security-question-to-go-along-with-it/190783>.
`UserInputService.PreferredInput` is the right switch
<https://create.roblox.com/docs/reference/engine/classes/UserInputService#PreferredInput>, which `Shared.Platform`
already uses.

#### 2.4a Bullet magnetism (NEW, do first)

**What.** On touch and controller, a round fired within a small cone of a target's body goes to the nearest point of
that body instead. The camera never moves, so it doesn't fight the player's thumb or the gyro. The cone shrinks with
distance (the same `scaleFor` the bubbles use) and is a little bigger when aimed. Bend the aim line *before* spread,
so a hip-fired spray still scatters and a shotgun pattern is only re-centred.

**From.** Witchfire's magnetism ring, which "pulls the shot toward the target", and its head-preferring inner ring
(<https://www.theastronauts.com/2019/02/witchfire-aim-assist/>); magnetism in Weihs' GDC 2013 talk above. Witchfire
also fades assist past the gun's effective range; ours can use the gun's `FalloffEnd` the same way (the `range` line).

```lua
-- Shared.AimAssist: bend the aim line toward the current target's body (touch and controller only).
local function nearestOnBox(part: BasePart, origin: Vector3, dir: Vector3): Vector3
	local along = math.max(0, (part.Position - origin):Dot(dir))
	local p = part.CFrame:PointToObjectSpace(origin + dir * along)
	local h = part.Size / 2
	return part.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(p.X, -h.X, h.X),
		math.clamp(p.Y, -h.Y, h.Y),
		math.clamp(p.Z, -h.Z, h.Z)
	))
end

function AimAssist.Bend(origin: Vector3, dir: Vector3, ctx: Context): Vector3
	if ctx.mode == "KeyboardAndMouse" then
		return dir
	end
	local all = GameConfig.AimAssist
	local cfg = all[ctx.mode]
	local preset = all.Presets[ctx.preset or "Standard"]
	local t = current
	if not (cfg and cfg.Enabled and cfg.BulletCone and preset and t and t.humanoid.Health > 0) then
		return dir
	end
	local best, bestAngle = dir, math.huge
	for _, part in { t.part, t.head } do
		if part then
			local want = (nearestOnBox(part, origin, dir) - origin).Unit
			local a = math.acos(math.clamp(dir:Dot(want), -1, 1))
			if a < bestAngle then
				best, bestAngle = want, a
			end
		end
	end
	local dist = (t.part.Position - origin).Magnitude
	local scale = scaleFor(dist, cfg)
	-- range: fades to nothing over the last quarter before the gun's FalloffEnd (Witchfire's "drops fast" past range)
	local range = if ctx.falloffEnd then math.clamp((ctx.falloffEnd - dist) / (ctx.falloffEnd * 0.25), 0, 1) else 1
	local cone = math.rad(lerp(cfg.BulletCone, cfg.AdsBulletCone, math.clamp(ctx.aim, 0, 1))) * scale * preset.Magnet * range
	return if bestAngle <= cone then best else dir
end
```

Config: `GameConfig.AimAssist.Touch.BulletCone = 1.6`, `AdsBulletCone = 2.2` (degrees at `RefDistance`); Gamepad
1.0 / 1.5; leave the keys off `KeyboardAndMouse`. Precision preset (`Magnet = 0`) turns it off. Add
`falloffEnd: number?` to the `Context` type and pass `gun.FalloffEnd`.
**Plugs into:** `fireDirection` in `GunClient` (it returns `spreadAround(camera.CFrame.LookVector, spreadDeg)` today):
bend the look vector first, then spread the bent line. In third person `ViewMode.ShotFrom` casts along that line from
the camera and re-aims from the head to what it hits, so the bend carries over. `GunServer` needs no change: it checks each pellet against the shot's own mean direction and
each hit against its own reported ray, never against the camera. Gyro aim gets the help without touching gyro files.
**Priority:** do first. The biggest single lift for phone players, and invisible.

#### 2.4b Sticky target in a horde (NEW, do first)

**What.** `search` runs every `SearchGap` (0.08 s) and takes the best score, so when two zombies overlap on screen the
slowdown and pull flip between them. Keep the current target unless a new one scores clearly better.

```lua
-- Shared.AimAssist.Step, where `current = search(...)` is set today.
local found = search(pos, prevCF.LookVector, cfg, ctx.ignore)
if current and found and found.model ~= current.model and current.humanoid.Health > 0 and current.part.Parent
	and visible(pos, current, ctx.ignore)
then
	local keep = scoreOf(current, pos, prevCF.LookVector, cfg) -- the same formula search() sorts by
	if scoreOf(found, pos, prevCF.LookVector, cfg) > keep * 0.7 then
		found = current -- not 30% better: stay on the one we're on
	end
end
current = found
```

**Plugs into:** `Shared.AimAssist` (split the score line out of `search` into `scoreOf`, returning `math.huge` once
the target is outside its bubble, so a zombie the player has turned away from is always dropped).
**Priority:** do first. A few lines; hordes are the main case in Outbreak and Endless.

#### 2.4c Less rotation from strafing alone (NEW, later)

**What.** Rotational tracking runs at full strength when the player only moves (`engaged` is look input *or*
`ctx.moving`), so strafing past a target turns the view for you. Call of Duty's Black Ops 7 notes give full rotation
only while the look stick tracks the target and a reduced share for strafing alone (source in 2.4).

```lua
-- Shared.AimAssist.Step, the tracking block: full share while looking, a third while only moving.
local looking = math.abs(dy) + math.abs(dp) > 1e-4
local s = lerp(cfg.RotationStrength, cfg.AdsRotationStrength, ads) * preset.Rotation
	* (if looking then 1 else cfg.StrafeRotationShare or 0.35)
```

**Priority:** later, and duel first: in PvE on phones generous help is fine; against a player it decides fights.

---

## 3. Bullet feel

### 3.1 Tracers — DONE

Beam tracers with a tail, a per-gun width, length, colour and speed, and a whiz when another player's round passes
within 6 studs of you. **From** (whiz by closest distance between the bullet's path and your head, played relative to
the camera for stereo): <https://devforum.roblox.com/t/bullet-whiz-bullet-flying-near-players-head/2312503>.
**Priority:** skip. (Real tracer rounds are often one in four or five; for our own gun every round should keep its
tracer, because EgorV's step 2 is that bullets must be seen.)

### 3.2 Surfaces: impacts, brass and Terrain

**PART.** **What.** The visuals have four classes (shatter, break, chip, dent). Sounds have only metal and stone plus a
generic cue (`IMPACT_CUE` in `GunClient`), brass has one landing sound, and the class comes from `part.Material`. For
a Terrain hit that is the Terrain object's own property, not the voxel the round hit; `RaycastResult.Material` gives
the real one ("for Terrain this can vary depending on terrain data",
<https://create.roblox.com/docs/reference/engine/datatypes/RaycastResult>). The campaign is a snow map, so ground hits
should throw snow and make a soft thud, and a casing should land silently in snow.

**From.** Reading `RaycastResult.Material` and looking up a sound by its name:
<https://devforum.roblox.com/t/roblox-fps-template-add-bullet-hit-sounds/3147300>. Infinity Ward treats shell
casings as physics sounds of their own (Modern Warfare audio blog, linked in 1.9).

**Sketch.**

```lua
-- GameConfig.Surfaces: what a round and a dropped case do on each material (by Enum.Material name).
-- Class: the WorldDamage class, or "Soft" (ground that only puffs) / "Splash".
GameConfig.Surfaces = {
	Default = { Class = "Chip", Hit = "Common/ImpactWorld", Brass = "Common/Casing" },
	Snow = { Class = "Soft", Hit = "Common/ImpactSnow", Puff = Color3.fromRGB(232, 238, 246) }, -- no Brass: silent
	Ground = { Class = "Soft", Hit = "Common/ImpactDirt", Puff = Color3.fromRGB(92, 78, 60), Brass = "Common/CasingSoft" },
	Grass = { Class = "Soft", Hit = "Common/ImpactDirt", Puff = Color3.fromRGB(88, 96, 60), Brass = "Common/CasingSoft" },
	Wood = { Class = "Break", Hit = "Common/ImpactWood", Brass = "Common/CasingWood" },
	WoodPlanks = { Class = "Break", Hit = "Common/ImpactWood", Brass = "Common/CasingWood" },
	Concrete = { Class = "Chip", Hit = "Common/ImpactStone", Brass = "Common/Casing" },
	Metal = { Class = "Dent", Hit = "Common/ImpactMetal", Brass = "Common/CasingMetal" },
	Glass = { Class = "Shatter", Hit = "Common/ImpactGlass", Brass = "Common/Casing" },
	Water = { Class = "Splash", Hit = "Common/ImpactWater" },
}

-- GunClient / CombatFx: the surface of a hit, from the raycast (right for Terrain too).
local function surfaceOf(result: RaycastResult): { [string]: any }
	return GameConfig.Surfaces[result.Material.Name] or GameConfig.Surfaces.Default
end

-- CombatFx.dropPhysical: a case that lands asks what it landed on (Touched can't tell a Terrain voxel).
local down = RaycastParams.new()
down.FilterType = Enum.RaycastFilterType.Exclude
local function landCue(at: Vector3, ignore: { Instance }): string?
	down.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(at + Vector3.new(0, 0.3, 0), Vector3.new(0, -1.5, 0), down)
	local s = if hit then GameConfig.Surfaces[hit.Material.Name] else nil
	return (s or GameConfig.Surfaces.Default).Brass
end
```

The existing class logic (`worldClass`, WorldDamage) can read the same table, so there's one list of materials.
**Plugs into:** `GunClient.impactCue` and `fire()` (use the result's material), `CombatFx.WorldImpact` (a `Soft` puff:
a short burst of the existing Smoke emitter tinted `Puff`), `CombatFx.dropPhysical`, `GameConfig`. New sound cues the
owner fills: ImpactSnow, ImpactDirt, ImpactWood, ImpactGlass, ImpactWater, CasingSoft, CasingWood, CasingMetal.
**Priority:** do first. Most rounds that miss hit the ground, and on a snow map the ground is snow.

### 3.3 Bullets through walls

**PART** (rounds pass through mobs, never walls). **What.** A round that stops in a thin, soft part (boards, doors,
crates, plaster, glass) goes on through it with less damage; concrete, brick and metal still stop it. Each gun has a
power in wood-equivalent studs; each material costs power per stud of thickness, and each wall keeps a share of the
damage. Thickness comes from a raycast backwards from beyond the part, filtered to that part only.

**From.**
- Counter-Strike's model (the open-source ReGameDLL_CS reimplementation): each round has a penetration power
  (9 mm 21, 5.56 35, 7.62 39, .338 45), each material scales it (metal 0.15, concrete 0.25, tile 0.65, wood unchanged)
  and cuts damage (metal 0.2, tile 0.3, wood 0.6) per wall. <https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/cbase.cpp>
  (`FireBullets3`).
- Measuring thickness on Roblox by casting back toward the hit point, filtered to the hit part:
  <https://devforum.roblox.com/t/how-to-correctly-calculate-part-thickness-when-penetrated-by-a-raycast/2437695>
  (take the method; the posted code is untested).
- Battlefield V (DICE's Q&A): penetration is set by weapon class with heavily reduced damage behind cover; pistols
  and carbines go through doors, cloth, light foliage and glass, rifles further, snipers furthest. A hit shows a small
  hole on the shooter's side and chunky debris on the far side.
  <https://mp1st.com/news/battlefield-5-bullet-penetration-explained-by-dice-and-why-its-important>
- Arma 3's damage model (penetration from the round's calibre and the surface material, deflection at steep angles):
  <https://community.bistudio.com/wiki/Arma_3:_Damage_Description>

**Sketch.**

```lua
-- GameConfig.Penetration: cost per stud of thickness and damage kept per wall. Missing materials stop the round.
GameConfig.Penetration = {
	Wood = { Cost = 1, Keep = 0.6 },
	WoodPlanks = { Cost = 1, Keep = 0.6 },
	Plastic = { Cost = 1.2, Keep = 0.6 },
	Fabric = { Cost = 0.5, Keep = 0.8 },
	Cardboard = { Cost = 0.4, Keep = 0.85 },
	Glass = { Cost = 0.4, Keep = 0.85 },
}
-- Per gun: GameConfig.Guns.X.Penetration.Wall (studs of wood): Pistol 1.2, AK 2.5, Sniper 6, Shotgun 0.6 a pellet.

local thick = RaycastParams.new()
thick.FilterType = Enum.RaycastFilterType.Include

-- Studs of `part` along the ray from where the round went in. Shared by client and server (same geometry).
local function thickness(part: BasePart, enter: Vector3, dir: Vector3): number
	thick.FilterDescendantsInstances = { part }
	local beyond = enter + dir * (part.Size.Magnitude + 0.1)
	local back = workspace:Raycast(beyond, enter - beyond, thick)
	return if back then (back.Position - enter).Magnitude else math.huge
end

-- castShot: the ray stopped in the world. Returns the power left and the exit point, or nil if the round stops.
local function passThrough(result: RaycastResult, dir: Vector3, power: number): (number?, Vector3?, number)
	local rule = GameConfig.Penetration[result.Material.Name]
	local hit = result.Instance
	if not rule or not hit:IsA("BasePart") or hit:IsA("Terrain") or hit:GetAttribute("Indestructible") then
		return nil, nil, 0
	end
	local t = thickness(hit :: BasePart, result.Position, dir)
	local cost = t * rule.Cost
	if cost >= power then
		return nil, nil, 0
	end
	return power - cost, result.Position + dir * (t + 0.05), rule.Keep
end
```

**Plugs into:** `GunClient.castShot` (on a world hit, call `passThrough`; if it returns power, add the part to the
ignore list, carry on from the exit point and multiply the damage share by `Keep`; report every wall with the shot as
`Walls = { { Part, Pos } }`). `GunServer` repeats `thickness` for each reported wall (same parts, same numbers, so it
can't be faked) before it accepts a hit behind one, and `WorldDamage.Hit` damages each wall so a board still breaks.
`KillPredict.damageOf` multiplies the same `Keep`s so predicted kills stay right.
**Priority:** do first for wood and glass only. It fits the siege loop (shoot the zombie through the boards it's
tearing at). Ricochets off metal: skip, they'd mostly hit teammates in a co-op siege.

### 3.4 Real projectiles with bullet drop (FastCast and successors) — SKIP for now

**What.** Rounds as moving projectiles with gravity, travel time and pierce callbacks, instead of instant rays with a
travelling tracer.

**From.**
- FastCast (EtiTheSpirit): segment raycasts each Heartbeat, `Acceleration` for drop, `CanPierceFunction`, a cosmetic
  bullet pool. <https://devforum.roblox.com/t/making-a-combat-game-with-ranged-weapons-fastcast-may-be-the-module-for-you/133474>,
  API <https://etithespir.it/FastCastAPIDocs/fastcast-objects/fcbehavior/>. No longer maintained by its author.
  (Blood Engine, which our blood drops copy, runs on it: <https://github.com/rotntake/BloodEngine>.)
- FastCast2, the unofficial continuation (parallel Luau, Blockcast and Spherecast, typed, MIT):
  <https://github.com/weenachuangkud/FastCast2>.
- SwiftCast (Mar 2026, strictly typed, several pierces a step): <https://github.com/Brawldude2/SwiftCast>.
- SecureCast (archived 2024, MIT): server-authoritative projectiles with lag compensation in parallel Luau, hit tests
  against a rewind buffer in pure Lua. The best reference if the duel ever needs server-simulated rounds.
  <https://github.com/1Axen/Secure-Cast>

**Priority:** skip for now. Our fights are mostly under 150 studs, where an instant ray plus a travelling tracer looks
the same, and projectiles would make lag compensation and kill prediction much harder. Revisit for a long-range sniper
map in the duel.

### 3.5 Near misses and suppression — PART

The whiz is in (3.1). Suppression (a short vignette, a muffle and a little sway when rounds keep passing close) suits
the duel only. **From:** detect on the receiving client when the tracer arrives, 10 to 15 studs radius,
<https://devforum.roblox.com/t/suppression-effect-with-raycasts/2935317>. PUBG plays a whizz in a wide radius and
a sharper supersonic crack in a small one (linked in 1.9); a rifle-only `Crack` cue inside about 2 studs would add
that to our whiz.
**Priority:** later, duel only, and cosmetic only (no aim penalty in a 1v1, where it would just feel unfair).

---

## 4. Enemy reactions

### 4.1 Stagger, knockback, limb hits, crawling — DONE

Every hit flashes and squashes the mob, kicks the hit joint and jolts the body (`MobImpact`), slows it for a
stagger (`MobReactions`, `StaggerUntil`), knocks it back along the shot, and breaks off a swing in its windup. Limbs
have their own health: they loosen, hang, then tear; a lost leg makes it crawl, a lost arm weakens it, the head kills.
Heavy blasts knock it down. All per mob in `GameConfig.Mobs` and per gun in `Feel` (`Stagger`, `Knockback`,
`LimbDamage`, `KnockDown`).

**From.**
- id Software, "Embracing Push Forward Combat in DOOM" (GDC 2018) <https://www.youtube.com/watch?v=2KQNpQD8Ayo>, and
  a write-up of DOOM's AI: damage per second triggers pain reactions, and particular guns cause particular staggers
  (fodder staggers fast to shotguns) <https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016->.
- Killing Floor 2's M.E.A.T. system: 19 dismemberment points, ragdolls and knockback that follow the weapon and the
  direction of fire <https://www.pcgamer.com/killing-floor-2-gore-system/>.
- Alex Vlachos, "Rendering Wounds in Left 4 Dead 2" (GDC 2010): wounds where the round hit, sized by the weapon
  <https://cdn.cloudflare.steamstatic.com/apps/valve/2010/gdc2010_vlachos_l4d2wounds.pdf>.
- Dead Space's "strategic dismemberment" (limbs, not heads, are the target)
  <https://www.engadget.com/2008-06-23-dead-space-loses-limbs-thanks-to-strategic-dismemberment.html>.

**Priority:** skip (done).

### 4.2 Poise for big mobs and the boss

**NEW.** **What.** Small zombies flinch on every hit, which is right. A boss that flinches on every AK round looks
silly and is easy to lock down; one that never flinches feels like shooting a wall. Poise is the middle: hits fill a
hidden meter (heavier guns and headshots fill more), and when it's full the boss takes one big stagger and the meter
empties. It refills after a few seconds without hits, so focus fire is rewarded.

**From.** Elden Ring's poise: hits drain a hidden poise bar, the target staggers when it hits zero and it refills
after some seconds without being hit (6 to 15 s for enemies). <https://eldenring.wiki.fextralife.com/Poise>.
DOOM (2016) does the same with damage per second: pain reactions start once enough damage lands in a short time
(source in 4.1).

**Sketch.**

```lua
-- MobReactions: a mob with cfg.Poise only staggers when the meter fills.
type Poise = { Max: number, Regen: number, Delay: number, BreakTime: number } -- per second, seconds

local function poiseHit(s: any, cfg: { Poise: Poise? }, weight: number, now: number): boolean
	local p = cfg.Poise
	if not p then
		return true -- ordinary mobs: every hit staggers, as now
	end
	if now - (s.PoiseAt or 0) > p.Delay then
		s.Poise = math.max(0, (s.Poise or 0) - p.Regen * (now - (s.PoiseAt or 0) - p.Delay))
	end
	s.PoiseAt = now
	s.Poise = (s.Poise or 0) + weight -- weight: gun Feel.Stagger x zone multiplier (head 2, legs 1.3)
	if s.Poise >= p.Max then
		s.Poise = 0
		return true -- the big stagger: cfg.Stagger.Time * p.BreakTime
	end
	return false
end
```

**Plugs into:** `MobReactions` where it starts a stagger today; `GameConfig.Mobs.<Boss>.Poise`.
**Priority:** later. Build it with the round-5 boss; ordinary mobs keep flinching on every hit.

### 4.3 Hit-zone reactions — PART

`MobImpact` kicks whichever joint was hit, so the reaction is already by zone. Two zone-specific moves would read
better: a leg hit buckles the knee for a step (the mob dips), a head hit snaps the head back. Both are short C0 poses
in `MobPose`, which already layers poses on joints without fighting animations. **From:** Killing Floor 2's
per-zone reactions and Dead Space's limb targeting (sources in 4.1).
**Priority:** later. Nice, not needed; the jolt already reads.

### 4.4 Your own flinch when shot in the duel

**DONE** (one small split left). `Remotes.PlayerHit` kicks the view hard (3.5° pitch, 5.5° yaw, 7° roll, scaled by
damage), which is right for zombie swipes. In the duel a round from the other player (`kind == "Bullet"`) already
scales the whole reaction by `GameConfig.Pvp.Flinch` (0.3), so the first hit doesn't decide the fight by throwing the
victim's aim. Apex removed aim flinch from all weapons in its Shockwave update, and VALORANT slows movement
("tagging") instead of kicking the view (sources in 1.1 and 2.4).

**Later idea.** Today the 0.3 also shrinks the screen shake and FOV punch, so a bullet hit reads weakly. Split it: the
part that moves the crosshair stays small, the part that only shakes the picture comes back up.

```lua
-- Duel GunClient, Remotes.PlayerHit, replacing the `weight *= GameConfig.Pvp.Flinch` lines.
local aimShare, screenShare = 1, 1
if kind == "Bullet" then
	aimShare = GameConfig.Pvp.Flinch or 0.3 -- moves the aim: keep it small
	screenShare = GameConfig.Pvp.HitShake or 0.7 -- only shakes the picture: let the hit read
end
camSpring:Kick(Vector3.new(math.rad(-3.5), side * math.rad(5.5), -side * math.rad(7)) * weight * aimShare)
shake(3.5 * weight * screenShare) -- Trauma.Add once 1.3 is in
fovSpring:Kick(Vector3.new(-4 * weight * screenShare, 0, 0))
```

**Plugs into:** the `PlayerHit` handler in the duel's `GunClient`; a new `GameConfig.Pvp.HitShake`.
**Priority:** later. Decide after a few duel playtests.

---

## 5. Netcode feel

### 5.1 Hits on the client, checked on the server — DONE

The client raycasts and shows everything on the frame of the click (marker, sound, gore, a predicted kill that drops
the body at once); `GunServer` checks each report before any damage (origin near the head, the hit on the ray, the
part near where it really is, fire rate, ammo, pellet cone, penetration), and `KillPredict` puts the mob back if the
server disagrees. This is the same order as Roblox's own Laser Tag tutorial (types, angle against the server's own
directions, distance to the beam, line of sight):
<https://create.roblox.com/docs/tutorials/curriculums/gameplay-scripting/detect-hits>.

**From** (the industry background for 5.1 to 5.4):
- Yahn Bernier (Valve), "Latency Compensating Methods in Client/Server In-game Protocol Design and Optimization":
  predict firing on the client with shared weapon code, show others about 100 ms in the past, rewind on the server;
  being "shot around a corner" at high ping is the accepted cost, "a game design decision".
  <https://developer.valvesoftware.com/wiki/Latency_Compensating_Methods_in_Client/Server_In-game_Protocol_Design_and_Optimization>
- Valve, "Source Multiplayer Networking": command time = server time − latency − interpolation; only players are
  rewound, from a one-second history. <https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking>
- Riot, "Peeking into VALORANT's Netcode": the server rewinds to the shooter's view time, with a cap so a high-ping
  player can't kill someone already in cover. <https://www.riotgames.com/en/news/peeking-valorants-netcode>
- Gabriel Gambetta, "Fast-Paced Multiplayer": prediction and reconciliation, entity interpolation, lag compensation
  and its cost (hit just after reaching cover). <https://www.gabrielgambetta.com/lag-compensation.html>
- Blizzard, Overwatch "Let's Talk Netcode" (favour the shooter, and its exceptions)
  <https://www.youtube.com/watch?v=vTH2ZPgYujQ>; Tim Ford, "Overwatch Gameplay Architecture and Netcode" (GDC 2017)
  <https://www.youtube.com/watch?v=W3aieHjyNvw>.
**Priority:** skip (done).

### 5.2 Rewind to the shot time in the duel — DONE

`src/duel` `HitHistory` records every player's body parts on Heartbeat; `GunServer.shotTiming` takes the client's shot
time, subtracts Roblox's interpolation delay (`Pvp.Interp` 0.1 s) and the one-way trip, searches a small window around
that, and never rewinds further than ping + interp + slack or `MaxRewind`. Roblox's own Server Authority (full release
9 Jul 2026) has no built-in shooter rewind and says remotes run about 40 to 50 ms off its shared timeline, so keeping
our own buffer is right: <https://create.roblox.com/docs/projects/server-authority>.
**Later:** a counter in `GunServer` for rejected hits by reason, so tuning `Validation` is based on numbers.

### 5.3 Cosmetic ShotFx on an unreliable remote

**NEW.** **What.** `Remotes.ShotFx` (tracer ends and gun name for other players' shots) is a normal RemoteEvent, so a
lost packet holds up every later one until it is resent. These are cosmetic and short-lived, which is exactly what
`UnreliableRemoteEvent` is for: "ephemeral events", not resent, unordered, payloads over 1,000 bytes dropped. A shotgun
blast is 10 Vector3 ends plus a name, well under that. Kill confirms and hits stay reliable.

**From.** <https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent>. Our `Emplacements` module
already uses one for its effects.

**Sketch.**

```lua
-- GunServer: a second remote for the cosmetic part of a shot.
local shotFxFast = Instance.new("UnreliableRemoteEvent")
shotFxFast.Name = "ShotFxFast"
shotFxFast.Parent = Remotes

-- where it fires Remotes.ShotFx today:
shotFxFast:FireClient(other, player, ends, state.GunName)

-- GunClient: the same handler on both remotes (ShotFx stays for soldiers, tanks and old servers).
local function onShotFx(shooter: Player | Model, ends: { Vector3 } | Vector3, gunName: string) --[[ body as today ]] end
Remotes.ShotFx.OnClientEvent:Connect(onShotFx)
Remotes:WaitForChild("ShotFxFast").OnClientEvent:Connect(onShotFx)
```

**Plugs into:** `GunServer` (campaign and duel) and the `ShotFx` handler in `GunClient`; `Soldier` and `Tank` can move
over too.
**Priority:** do first. Ten lines; the visible gain is in busy fights on bad connections.

### 5.4 Rewind for fast mobs — SKIP unless numbers say otherwise

Mob hits are checked against where the mob is now (`MaxPartOffset` 6 studs). A zombie dog at its 21 studs a second
moves about 2 studs in Roblox's 0.1 s interpolation delay, so even at 250 ms ping it stays inside the allowance. If the
reject counter from 5.2 shows mob hits being thrown out, record mobs in a `HitHistory`-style buffer too. **Priority:** skip until the counter shows a problem.

---

## Sources

Roblox engine docs
- HapticEffect: <https://create.roblox.com/docs/reference/engine/classes/HapticEffect>
- UnreliableRemoteEvent: <https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent>
- Audio objects: <https://create.roblox.com/docs/audio/objects>; AudioEmitter: <https://create.roblox.com/docs/reference/engine/classes/AudioEmitter>;
  AudioFilter: <https://create.roblox.com/docs/reference/engine/classes/AudioFilter>; audio effects: <https://create.roblox.com/docs/audio/effects>
- Acoustic Simulation full release: <https://devforum.roblox.com/t/full-release-acoustic-simulation-emit-audio-with-presence/4307121>
- RaycastResult: <https://create.roblox.com/docs/reference/engine/datatypes/RaycastResult>
- Workspace:GetServerTimeNow: <https://create.roblox.com/docs/reference/engine/classes/Workspace>
- Player:GetNetworkPing: <https://create.roblox.com/docs/reference/engine/classes/Player#GetNetworkPing>
- UserInputService.PreferredInput: <https://create.roblox.com/docs/reference/engine/classes/UserInputService#PreferredInput>
- Laser Tag hit detection tutorial: <https://create.roblox.com/docs/tutorials/curriculums/gameplay-scripting/detect-hits>
- Server Authority: <https://create.roblox.com/docs/projects/server-authority>

Roblox community code
- Sleitnick RbxCameraShaker: <https://github.com/Sleitnick/RbxCameraShaker>; RbxUtil Shake: <https://sleitnick.github.io/RbxUtil/api/Shake>
- Quenty Nevermore Spring: <https://quenty.github.io/NevermoreEngine/api/Spring>; Fraktality spr: <https://github.com/Fraktality/spr>
- FastCast thread: <https://devforum.roblox.com/t/making-a-combat-game-with-ranged-weapons-fastcast-may-be-the-module-for-you/133474>;
  FastCast2: <https://github.com/weenachuangkud/FastCast2>; SwiftCast: <https://github.com/Brawldude2/SwiftCast>;
  SecureCast: <https://github.com/1Axen/Secure-Cast>; Blood Engine: <https://github.com/rotntake/BloodEngine>
- Carbon Engine (discontinued): <https://devforum.roblox.com/t/ce-carbon-engine-revolutionary-fps-combat-technology/872472>
- ACS (Advanced Combat System) docs thread: <https://devforum.roblox.com/t/acs-advanced-combat-system-robloxs-1-fps-combat-system/1285741>.
  Not used here: its release links are dead, players report the model being moderated, and its recoil and ballistics
  are not documented anywhere linkable.
- EgoMoose viewmodel tutorial: <https://devforum.roblox.com/t/the-first-person-element-of-a-first-person-shooter/160434>;
  BlackShibe FPS framework: <https://devforum.roblox.com/t/writing-an-fps-framework-2020/503318>
- Phantom Forces recoil (community reverse-engineering): <https://devforum.roblox.com/t/recoil-implementations/225453>
- Bullet whiz: <https://devforum.roblox.com/t/bullet-whiz-bullet-flying-near-players-head/2312503>;
  suppression: <https://devforum.roblox.com/t/suppression-effect-with-raycasts/2935317>;
  part thickness: <https://devforum.roblox.com/t/how-to-correctly-calculate-part-thickness-when-penetrated-by-a-raycast/2437695>;
  hit sounds by material: <https://devforum.roblox.com/t/roblox-fps-template-add-bullet-hit-sounds/3147300>;
  kill credit: <https://devforum.roblox.com/t/how-do-i-confirm-a-kill-consistently/328295>;
  shell ejection: <https://devforum.roblox.com/t/shell-ejecting-for-guns/460933>;
  Redshift aim assist: <https://devforum.roblox.com/t/how-to-make-aim-assist-and-a-security-question-to-go-along-with-it/190783>
- Roblox Freecam stick curve (Adonis copy): <https://github.com/Epix-Incorporated/Adonis/blob/master/MainModule/Server/Dependencies/Assets/Freecam/Freecam.client.lua>
- Frontlines audio (Roblox newsroom): <https://about.roblox.com/newsroom/2026/07/roblox-studio-fidelity-creator-interviews-twin-atlas-fluorlite-maximillian-ecos>

Industry
- Glenn Fiedler, "Fix Your Timestep!": <https://gafferongames.com/post/fix_your_timestep/>
- ReGameDLL_CS (Counter-Strike penetration): <https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/cbase.cpp>
- Halo multikill window: <https://www.halopedia.org/Double_Kill>
- Elden Ring poise: <https://eldenring.wiki.fextralife.com/Poise>
- Game feel: Steve Swink, "Game Feel: The Secret Ingredient" <https://www.gamedeveloper.com/design/game-feel-the-secret-ingredient>;
  Jonasson and Purho, "Juice it or lose it" <https://www.youtube.com/watch?v=Fy0aCDmgnxg> (a good checklist: switch
  each layer on and off to see what it adds); Nijman, "The art of screenshake" <https://www.youtube.com/watch?v=AJdEqssNZ-U>;
  Eiserloh, "Juicing Your Cameras With Math" <https://gdcvault.com/play/1023557/Math-for-Game-Programmers-Juicing>;
  Bevy's trauma shake example <https://bevy.org/examples/camera/2d-screen-shake/>
- Hit-stop: Sakurai <https://www.youtube.com/watch?v=OdVkEOzdCPw>, <https://www.youtube.com/watch?v=tycbMSjDDLg>;
  <https://critpoints.net/2017/05/17/hitstophitfreezehitlaghitpausehitshit/>
- Recoil and accuracy: Rainbow Six Siege Y7S3 notes <https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/2vKaDckg5VPV1ViA4p8KM/y7s3-preseason-designers-notes>;
  VALORANT 3.0 notes <https://playvalorant.com/en-us/news/game-updates/valorant-patch-notes-3-0/>;
  Griesemer, Halo 3 sniper (GDC 2010) <https://gdcvault.com/play/1012211>
- Gun sound: Modern Warfare (2019) audio <https://blog.activision.com/call-of-duty/2019-07/Modern-Warfare-Initial-Intel-Creating-an-Orchestra-of-Incredible-Audio-Effects-Weapon-Sounds-in-Call-of-Duty-Modern-Warfare>;
  PUBG <https://www.pcgamer.com/how-gunshot-sounds-work-in-playerunknowns-battlegrounds/>;
  Hunt: Showdown <https://www.huntshowdown.com/news/hunt-audio-readability-realism-and-consistency>;
  DICE adaptive mixing <https://www.slideshare.net/slideshow/adaptive-mixing-in-frostbite/3128152>
- First-person animation: Modern Warfare (2019) animation <https://blog.activision.com/call-of-duty/2019-07/Modern-Warfare-Initial-Intel-Detailing-Advancements-in-Animation-and-Authenticity>;
  Boehm, Overwatch (GDC 2017) <https://www.gdcvault.com/play/1024319/>; Helsby, Destiny (GDC 2015) <https://gdcvault.com/play/1022297/>;
  Duffin, "Giving Purpose to First-Person Animation" (GDC 2013) <https://gdcvault.com/play/1017633/Animation-Bootcamp-Giving-Purpose-to>
- Aim assist and sensitivity: Weihs (GDC 2013) <https://www.gdcvault.com/play/1017942/Techniques-for-Building-Aim-Assist>;
  Witchfire <https://www.theastronauts.com/2019/02/witchfire-aim-assist/>;
  Black Ops 7 preseason notes <https://www.callofduty.com/patchnotes/2025/11/call-of-duty-black-ops-7-preseason-patch-notes>;
  Apex Shockwave notes <https://www.ea.com/games/apex-legends/apex-legends/news/shockwave-patch-notes>;
  Apex Advanced Look Controls guide <https://gamersdecide.com/articles/apex-legends-best-alc-settings>;
  Battlefield Uniform Soldier Aiming <https://ea.com/able/resources/battlefield-2042/pc/mouse-and-keyboard>;
  mobile FPS UX <https://www.gamedeveloper.com/game-platforms/ux-deep-dive-painful-reality-of-building-fps-experiences-on-mobile-part-1>;
  Jibb Smart on gyro <https://gyrowiki.jibbsmart.com/blog:good-gyro-controls-part-1:the-gyro-is-a-mouse>
- Netcode: Bernier <https://developer.valvesoftware.com/wiki/Latency_Compensating_Methods_in_Client/Server_In-game_Protocol_Design_and_Optimization>;
  Source networking <https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking>;
  VALORANT netcode <https://www.riotgames.com/en/news/peeking-valorants-netcode>;
  Gambetta <https://www.gabrielgambetta.com/lag-compensation.html>;
  Overwatch <https://www.youtube.com/watch?v=vTH2ZPgYujQ>, <https://www.youtube.com/watch?v=W3aieHjyNvw>;
  Aldridge, "I Shot You First" (Halo: Reach, GDC 2011) <https://www.youtube.com/watch?v=h47zZrqjgLc>
- Enemy reactions: DOOM (GDC 2018) <https://www.youtube.com/watch?v=2KQNpQD8Ayo>, DOOM AI write-up
  <https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016->; Killing Floor 2 <https://www.pcgamer.com/killing-floor-2-gore-system/>;
  Left 4 Dead 2 wounds <https://cdn.cloudflare.steamstatic.com/apps/valve/2010/gdc2010_vlachos_l4d2wounds.pdf>;
  Dead Space <https://www.engadget.com/2008-06-23-dead-space-loses-limbs-thanks-to-strategic-dismemberment.html>
- Penetration: Battlefield V <https://mp1st.com/news/battlefield-5-bullet-penetration-explained-by-dice-and-why-its-important>;
  Arma 3 <https://community.bistudio.com/wiki/Arma_3:_Damage_Description>

Not covered by any source we could link, so not claimed above: how Arsenal, Bad Business and RIVALS do netcode or aim
assist (no developer posts found), Phantom Forces' own penetration numbers (its wiki blocks automated reading), an
official Halo or Destiny aim-assist explanation (fan wikis only), Counter-Strike's spray-pattern design, and
Escape from Tarkov's penetration tables.
