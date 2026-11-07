# Gyro aim (7 Nov 2026)

Status: **built in the repo (campaign and duel), not on a phone yet.** It passes a simulation of every way a
phone can report its rotation (see "Tests"). Nothing has been played on a real phone, and this session had no
Roblox Studio connection (the Studio MCP failed with "Server's protocol version is not supported"), so the places
in Studio still run the old gyro until it is installed (see "Install").

## Where it lives

| What | File |
|---|---|
| The gyro maths (one module, same file in both places) | `src/campaign/ReplicatedStorage/Shared/GyroAim.luau`, `src/duel/...` |
| Feeding it and turning the camera | `StarterPlayerScripts/TouchControls.client.luau` (campaign and duel, identical) |
| Settings `Gyro` (Off / Aiming / Always), `GyroSens`, `GyroFlip` | `GameConfig.Settings` (lobby, campaign, duel); rows are authored UI |
| "Aiming" attribute for gyro mode Aiming | `GunClient.client.luau` |
| Simulation (Python port of GyroAim, kept in step) | `tools/gyro_sim.py` |
| The real Luau module run outside Roblox | `tools/gyro_luau_check.luau` |
| Studio installer for places without Rojo (Zombies) | `tools/install_gyro.luau`, built by `tools/make_gyro_install.py` |

The lobby has gyro settings rows but no gyro aiming (no TouchControls), so nothing changes there.

## Why the old gyro was wrong

1. **It assumed one convention.** The 3 Nov code took each reading's turn as `last:ToObjectSpace(cf)`, which is
   only right if the rotation CFrame maps the phone to the world in the same axes as the gravity sensor. Roblox
   doesn't document the CFrame's frame, and phones differ (DevForum: an iPhone 7 and a Pixel 1 differ by swapped
   X/Y and a flipped Z; OnePlus values change with screen orientation; phones and tablets differ by a sign). On any
   other convention, left/right leaks into up/down and the other way round. In the simulation the old code tracked
   correctly on 5% of the 48 possible conventions.
2. **It only connected when `GyroscopeEnabled` was true**, which some phones report wrongly (DevForum, 2024).
3. **No filtering:** readings and frames don't line up one to one, so turns stuttered; hand tremor went straight
   to the camera.

## What I looked at

- **Roblox:** the `UserInputService` docs (no frame given for the CFrame; gravity axes are documented: upright
  portrait (0, 0, -9.81), left side down (9.81, 0, 0), screen up (0, -9.81, 0)). Roblox's old "gyroscopic camera"
  sample uses Euler angles of `rotCFrame * last:Inverse()` with per-device sign hacks.
- **GitHub** (via grep.app): no Roblox gyro aim script. The only real use is A-Chassis's tilt steering
  (`rotation.Position.Z * 2`), which is a tilt, not an aim.
- **Toolbox / Creator Store** (search "gyro aim", "gyroscope camera", "mobile gyro" and more): only security
  cameras and props, no gyro aim script.
- **Top Roblox shooters:** no evidence that RIVALS, Arsenal, Phantom Forces, Frontlines, Bad Business or others
  ship gyro aim. Two devs on the DevForum built their own and didn't share the method.
- **Jibb Smart's GyroWiki** (the method behind JoyShockMapper, Steam Input and good Switch gyro): player space yaw
  with a relax factor (1.15 to 2; we use 1.41), pitch about the device's own left-right axis, tightening below a
  small speed, soft tiered smoothing (lower threshold half the upper, about 0.125 s), sensitivity 1 = a real turn.

## How it works now

1. **Self-check (which convention this phone uses).** Gravity's frame is the documented one. The module tries all
   48 ways the rotation CFrame could sit against it (the 24 ways its axes can map onto gravity's, each
   phone-to-world or world-to-phone). Under the right one, "up" carried into the world points the same way every
   reading; under a wrong one it swings. Running means show the steady one. It has to be 3 times steadier than
   any other and hold for 15 readings before it's used. In the simulation it locks on in about 1 s of normal
   handling (90% within 1.7 s, never a wrong pick). It runs even while the gyro is off, so it's ready.
2. **One thing it can't always tell:** a convention and the same one turned half round the phone's long edge look
   equally steady while that edge stays level (it does, in landscape). They agree on up/down and disagree on
   left/right. A twist of the phone settles it; until then it takes the one that puts world up along +Y or +Z of
   the sensor's frame (true of Roblox's and the phones' frames). If left/right is ever backwards, `GyroFlip`
   fixes it. Up/down should never be backwards.
3. **Up comes from the rotation itself** once the convention is known: no accelerometer hand shake, no lag.
4. **Pitch** is the turn about the screen's left-right edge (learned from how the phone is held; works nearly flat,
   and either landscape side). **Yaw** is player space: the turn about world up, relaxed 1.41, so turning your body
   and twisting the phone both turn the view.
5. **Filters per frame:** the rate is averaged over 1/30 s (frames with no reading don't stutter); tightening below
   3 degrees per second (still hands don't shake the view); smoothing below 4, straight through above 8, blended in
   between (0.125 s).
6. The console prints one line when the self-check settles, e.g. `[GyroAim] this device's gyro reads
   phone-to-world, X=+X Y=+Y Z=+Z`. Type `/console` in chat on the phone to see it.

## Tests (no phone, no Studio)

- `python tools/gyro_sim.py` (about 3 minutes): a simulated player turns, tilts and twists a phone in either
  landscape at 25 and 55 degrees tilt, with hand tremor, hand acceleration in the gravity reading, sensor lag and
  readings out of step with frames, on all 48 conventions. Last run: new code median error 2.2% of the motion,
  every run within 15% (worst 7%); old code median 91%, 5% of runs within 15%. On the documented convention both
  are about 2%. Holding still: crosshair wobble about 0.37 degrees (old 0.46). An 8 deg/s pan is smooth and
  reaches 99%; a very slow 2 deg/s pan reaches about 70% (the tightening, by design).
- `tools/gyro_luau_check.luau` runs the real module with stand-in Vector3/CFrame types:
  `luau tools/gyro_luau_check.luau` (Luau from https://github.com/luau-lang/luau/releases). **Not run yet**: this
  session's sandbox wouldn't run a downloaded interpreter. All the new Luau files pass `luau-compile`.
- `rojo build` passes for lobby, campaign and duel.

## Install

- **Campaign and Multiplayer (duel):** Rojo sync from this repo, or run the installer below in each.
- **Zombies place (121963671263674, not in git), or any place without Rojo:** open the place in Studio (Edit, not
  Play), paste all of `tools/install_gyro.luau` into the command bar, press Enter, read the Output, then save and
  publish. It creates or updates `ReplicatedStorage.Shared.GyroAim`, backs up TouchControls to
  `ServerStorage._Backups`, and patches only the gyro parts (3 exact hunks). If that place's gyro code differs from
  the 3 Nov version it changes nothing in TouchControls and says so.
- After changing `GyroAim.luau` or the gyro part of TouchControls: copy GyroAim to duel, run
  `python tools/make_gyro_install.py` and `python tools/gyro_sim.py`.

## Phone test checklist

Settings: Gyro aim = Always, Gyro sensitivity = 1. Hold the phone in landscape, tilted back a little. Move it around
for a couple of seconds first (the self-check), then:

1. Turn your whole body left: the view turns left by about the same amount and doesn't tilt.
2. Tilt the top of the phone toward you: the view looks up. Away: it looks down.
3. Hold still: the crosshair doesn't drift or shake.
4. Fast flick left and back: no lag, and the view comes back to where it started.
5. Slow pan across a wall: smooth, no stepping.
6. Turn the phone to the other landscape side and repeat 1 and 2.
7. If left/right is backwards, turn on "Flip gyro". If up/down is ever backwards, note the phone model and the
   `[GyroAim]` console line: that means the self-check picked wrong.
