# Last Light — Combat Feel, Mobs and Siege Spec

Owner direction, 2026-10-28 (after the Day 1 playtest). This file is the reference for how shooting, monsters and the building should feel. The brief ([HORROR-SHOOTER-BRIEF.md](HORROR-SHOOTER-BRIEF.md)) holds the loop and the plan. This file holds the feel.

---

## 1. Setting: one building under siege

- The game takes place in **a building**, and zombies try to **breach in** through windows, doors and weak walls.
- **The building gets ripped apart over time.** Boards get torn off windows, doors get smashed, and walls break open into new holes as the rounds go on. The safe space keeps shrinking unless players fix it.
- Repairing (boarding windows, patching walls) is the barricade part of the loop and earns points. Damage to the building should be visible and loud: splinters, dust, boards flying off, a wall section caving in.
- Rooms still open up by buying doors, but it's all one building (e.g. the camp lodge), not an open camp.

## 2. Mobs: zombies first, not zombies only

- **Zombies are the test mob.** The finished game has **several mob types.**
- Build everything mob-agnostic. A mob is data in `GameConfig`:
  - health, speed, which body parts can come off, stagger strength, attacks, sounds and how it breaches.
- No zombie-only code paths. Hit reactions, dismemberment, highlight and sounds are shared systems every mob plugs into.

## 3. Impact: every shot must feel heavy

Day 1 shooting is too light. Targets:
- **Gunshot:** layered sound (sharp crack + low boom + room tail), louder and punchier than now.
- **Camera:** stronger kick and a short screen shake on each shot, with a bigger shake on kills.
- **Gun:** casings eject with a small sound when they land, and the muzzle flash gets bigger with light that hits the walls.
- **Hits:** a bigger puff on the monster, a meaty hit sound, impact marks on walls.
- **Kills:** an extra punch. Kill sound, heavier hitmarker, the body reacting hard.

## 4. Reload animation

- Replace the Day 1 procedural tilt with a **proper animated reload**: mag release, mag out, new mag in and seated, slide rack (rack only on empty reloads).
- Every step has its own sound at the exact moment (mag click out, mag slide in, slap, slide rack).
- Two versions: tactical (rounds left) and empty (slower, with the slide rack).

## 5. Zombie hit reactions

- **Highlight on hit:** the monster flashes when shot, so every hit reads at a glance.
- **Stagger on every shot:** the body reacts in the direction of the hit and the zombie is briefly slowed. Headshots and leg shots stagger harder.
- **Body parts come off:** limbs have their own health. Enough damage to an arm, leg or head and **that part breaks off and falls to the floor** with physics, then stays a few seconds.
  - Lost leg → the zombie drops and crawls.
  - Lost arm → weaker or slower attack.
  - Lost head → dead.
- **They don't just die:** death is a reaction too (collapse, fall in the hit direction), never a pop-and-vanish.
- **Look of the damage:** stylized dark red-black splatter at the break, not realistic gore (see section 7 on splatter).

## 6. Sound list

**Gun:** layered shot, dry fire, casing drops, mag out, mag in, mag slap, slide rack, aim-in cloth rustle.

**Zombies (each mob type gets its own set):**
- idle groans (random, 3D, from the dark)
- an alert scream when it spots a player
- footsteps / running
- attack swipe and bite
- grunt when hit, with a different sound for headshots
- body part tearing off, and the part thudding on the floor
- death
- clawing at boards and smashing through windows and walls

**Building:** wood splintering when boards rip off, wall cracking and collapsing, hammering when repairing.

## 7. The method: "How to make gunfire punchy" (owner's reference video)

Source: EgorV's TikTok tutorial, sent by the owner on 2026-10-28 (https://www.tiktok.com/t/ZTfnuA5B9/). It shows the same shot first as "feels like nothing", then with 7 layers added. **Every gun and every mob in this game must have all 7.**

| # | Step | What the video does | What it means in our game |
|---|---|---|---|
| 1 | **The shot** | Kick the gun, flash the barrel, and **answer on the same frame** as the click. | The gun kicks, the muzzle flashes and the sound plays on the exact frame the button is pressed. Nothing waits on the server. |
| 2 | **Bullets** | Spread, a tail, sparks. Without them, "same bullets look like a laser". | Visible tracers with a glowing tail, a little spread so shots aren't one line, and sparks at the muzzle and where they land. |
| 3 | **The hit** | Flash, squash, knock back, "or you can't tell you hit". | The monster flashes white, squashes for a split second, and gets **knocked back / staggered** in the bullet's direction. |
| 4 | **Recoil** | Push the hero, kick the camera, so "the player feels it too". | A strong camera kick plus a small push back on the player, bigger for heavy guns. |
| 5 | **Blood & shells** | Spray it and **leave it on the floor**: "the fight leaves a mess". | Shell casings eject and **stay on the floor**. Splatter from hits stays on floors and walls. After a round, the room shows the fight. |
| 6 | **Sound** | Crack, whiz, thud, ping, using **a few samples with the pitch nudged**. | Layers: shot crack, tracer whiz, impact thud, casing ping, plus 2–4 variants of each with random pitch so nothing repeats. |
| 7 | **The kill** | **Freeze, then throw the body.** | On a kill the monster freezes for a split second (hit-stop), then the body is thrown in the shot direction with physics. Body parts that came off fly too. |

### Every gun type feels different (owner, 2026-10-28)

The 7 steps are the same for every gun, but **how strong each one is gets tuned per gun type**, and **each gun type has its own reload animation**. A pistol, a shotgun and an LMG must never feel like the same gun with different numbers.

All of this lives per gun in `GameConfig.Guns`. No hard-coded feel values in scripts.

| Gun type | Shot / recoil | Bullets / hit | Sound | Reload animation |
|---|---|---|---|---|
| **Pistol** | Snappy flick up, fast recovery, small camera kick | Thin tracer, light knockback | Sharp, short crack | Mag out, mag in, slide rack only when empty |
| **SMG** | Fast shake that climbs, small kick each shot | Many thin tracers, light stagger per bullet that adds up | Fast rattle, lighter crack | Quick mag swap, charging handle when empty |
| **Assault rifle** | Steady climb you can pull down, medium kick | Medium tracers, solid stagger | Mid crack with a punchy body | Mag swap with a slap, bolt release when empty |
| **Shotgun** | Huge single kick, player pushed back, big shake | Pellet spread, big knockback, limbs come off easily | Deep boom plus pump/shell sounds | Shells one by one (can be interrupted to fire), pump at the end |
| **LMG** | Heavy, slower climb, constant small shake, slower to aim | Thick tracers, steady stagger | Heavy thump with a long tail | Long: lid open, belt/box out and in, lid slam |
| **Sniper / bolt** | Big kick, slow recovery | Bright tracer, knockback and limb removal | Loud crack with a long echo | Bolt cycle after every shot, plus mag reload |
| **Wonder / special guns** (crate) | Unique per gun | Unique effects | Unique | Unique |

Per-gun knobs in config: camera kick, viewmodel kick, shake, player push, tracer size/colour/tail, spread, hit knockback, stagger strength, limb damage multiplier, kill-freeze length, body-throw force, sound set (samples + pitch range), and a reload animation set (tactical and empty, with timed sound events).

**Splatter colour:** the video uses red. We use a stylized dark red-black splatter (not realistic gore), so it stays a "mess" without pushing the maturity label high. Fill Roblox's maturity questionnaire honestly once it's in.

**Dismemberment and stagger** build on steps 3 and 7: every hit staggers, limb damage pops limbs off with physics, and the kill freezes then throws.

## 8. Order of work

1. Impact pass on the pistol using the 7 steps in section 7: same-frame kick and flash, tracers with tails, layered pitched sounds, casings and splatter that stay, recoil push. **Done 28 Oct** (placeholder art, sounds unheard by me; see section 10).
2. Animated reload with timed sounds. **Done 28 Oct** (tactical + empty with slide rack, keys in `GameConfig.Guns.Pistol.ReloadAnim`).
3. Real zombie rig (R15-style limbs so parts can come off), using the video's method.
4. Hit highlight, stagger and limb damage, then dismemberment and crawling. **Systems done 28 Oct** on the block test dummy (`MobReactions`); move onto the real rig in step 3.
5. Zombie sounds. **Done 28 Oct** (placeholders).
6. Breaching AI: zombies path to windows and walls, tear boards off and climb in.
7. Building damage over time, plus player repairs.

## 9. Owner direction, 28 Oct (second batch): zombies, the building, dying

The owner's next asks for the feel phase. Each pass is done slowly and in detail ("it's a test game so details have to be intricate").

**Models**
- **Pistol from the Toolbox, retextured** so it can't be recognised during the test phase (scripts stripped). The hold must look right: two hands visibly on the gun, not a floating gun.
- **Low-poly zombie from the Toolbox**: scary, with separate parts that can be rigged (R15-style), so **whatever part you shoot comes off or splits** (hand, forearm, upper arm, head, legs, chunks of torso).

**Zombie behaviour**
- Zombies **actively move toward the player** (pathfinding, not straight-line walking).
- When blocked they **act dumb** for a while (bump, mill, claw at the obstacle), but not too dumb: **after some time they climb over fences**, and they **hit wood and break it**.
- They **tear the building apart** to get to you.
- When you **run out of ammo or fail**, they **gather on you and rip you apart**. Nothing gory is shown: they pile on and cover you completely, like a devouring cutscene.
- In co-op they **finish you, then go for your friends**. With a **self-revive** you are not finished instantly.

**Player health**
- An **HP bar**: you lose HP when hit. It must look like a horror HP bar (not a game-show bar), consistent with the quiet UI.

**The building**
- **Breakable house** with **breakable map physics like Jujutsu Shenanigans**: walls, boards and furniture break into physical chunks.
- Zombies break the build to reach you; players hold their ground and repair.

**Atmosphere**
- **Flickering room light bulbs** (and a flashlight in dark rooms).
- An intense feeling of fear and of **holding your ground**.

**Guns**
- **Each gun has its own shot speed** (fire rate, and bullet/tracer travel speed), on top of the per-gun feel in section 7.

**Boss**
- **Round 5: a boss mob**, very deadly. Beating it needs upgrades, teamwork or extreme skill.

**After the ad test picks a winner:** more game modes and content.

### Pass order (my call)

| Pass | What | Why this order |
|---|---|---|
| A | Toolbox pistol + proper two-hand hold; Toolbox zombie rig with per-part break-off | Everything after this is judged on these two models |
| B | Player HP, horror HP bar, zombie attacks and hit feedback, downed state, the devour finish, self-revive, retarget friends | Makes zombies a threat; needed before AI tuning means anything |
| C | Zombie navigation: pathfind to the player, "dumb when blocked" milling, then vault fences and smash wood after a delay | Needs pass B's attacks |
| D | Breakable building: chunked walls/boards/furniture with physics, zombies tearing builds, player repairs | Needs pass C's "smash" behaviour |
| E | Atmosphere: flickering bulbs, flashlight, ambience, fear stingers, holding-ground pacing | Tuned once the fights exist |
| F | Round 5 boss | Needs everything above |

## 10. What was built in the first feel pass (28 Oct)

- **Config:** `GameConfig.Guns.Pistol.Feel` (all 7 punch steps as numbers), `ReloadAnim` (tactical + empty keyframes with sound/mag/kick events), `GameConfig.Mobs.TestZombie` (limb health, stagger, crawl, sounds, corpse/gib times).
- **Sounds:** `Assets.Sounds` is now cue folders (`Guns/Pistol/{Crack,Body,Tail,MagOut,MagIn,MagSeat,SlideBack,SlideRack,DryFire}`, `Common/...`, `Mobs/TestZombie/...`). `Shared.SoundKit` picks a variant (never the same twice) and nudges the pitch inside each folder's `Pitch` attribute.
- **Client:** `CombatFx` (beam tracers with tails, whiz when a teammate's bullet passes you, muzzle light on the walls, muzzle sparks/smoke, casings and dropped mags that stay, bullet holes, dark red-black splatter on walls and floors, hit flash, squash, gore on limb loss and kills). `GunClient` adds camera shake, an FOV punch, a player shove and the keyframed reload. The player attribute `DebugReloadT` (0-1) freezes a reload frame for screenshots, and `DebugReloadEmpty` picks the empty reload.
- **Server:** `ServerStorage.Modules.MobReactions` (limb health → the part breaks off and flies; head = kill; leg = crawl; arm = weaker; stagger slow, knockback, flinch, hurt sounds; kill = freeze, then throw the body; idle groans; corpse fade). `CharacterSetup` puts players in the `Characters` collision group, which never collides with `Debris`.
- **Test range:** two `Walker` zombies head for the nearest player.
- **Audio warning:** several placeholder sounds look ripped from other games (names like `wpfoly_`, `fn57_`, `m1911_`). Swap them for ProSoundEffects or owned audio before any public release.

## 11. Gore and aim pass (28–29 Oct)

- **Green blood (rating):** all mob blood, splats, pools, drops and emitters are green ichor (`GameConfig` Gore colours, `Assets.Fx` emitters, `CombatFx` SPLAT colours). The "dark red-black splatter" in section 10 is gone. Keep mob blood non-red so the game stays out of the realistic-blood maturity rating.
- **Blood drops:** `CombatFx.BloodDrops` simulates drops that fall, stretch and land. On landing they make pools that grow and merge or run down walls. Modelled on Blood Engine (devforum.roblox.com/t/blood-engine-a-blood-engine-system/2545682).
- **Dents:** `StarterPlayerScripts.Dents` swaps a shot part for an EditableMesh copy and pushes a crater in, and `Gore.Wound` adds the hole, rim and run. The pool holds about 6 parts per client and evicts the oldest first, because the engine budget is about 8 meshes. A dent only works on parts we build or meshes we own; a Toolbox zombie's meshes won't dent unless re-uploaded by us. A published game may need Mesh/Image APIs enabled in Game Settings.
- **Tearing:** arms take 3 pistol shots: wound, then loosen, then tear. Loosening turns the joint into a ball socket: the limb hangs, torn faces show on both sides, flesh strands stretch, a spurt fires and the limb swings when shot. Tearing holds the limb on a spring for `Gore.TearHold` while strands stretch and snap, then it flies with a drop trail. The stump shows bone, and gibs scatter.
- **Loose socket:** the cone is centred on straight down (gravity when the limb comes loose), not on the joint's pose, and tipped 42° outward. That gives about 18° inward swing (no clipping through the chest), about 100° outward and ±35° roll. A small nudge loop stops physics sleep freezing a limb mid-swing.
- **Aim:** right mouse is hold-or-tap-toggle. Some mice and touchpads report the right button released the instant left goes down. A release within 0.05 s of a shot latches aim until the next right press (owner confirmed fixed).
- **Not yet done:** the Toolbox zombie with one red and one green eye; placeholder Tear sounds; touch controls (Day 2).

## 12. Test zombie from the Toolbox (29 Oct)

- **Model:** `ServerStorage.TestZombie` is the R15 "Zombie" by Rzepert from the Toolbox. Its seven old scripts were read and deleted (touch damage, basic chase, respawn loop, regen, moans). Only `Animate` stays, playing Roblox's zombie walk and idle. The humanoid is renamed `Humanoid`, with the name and health bar hidden. Limb groups: Head; LeftArm/RightArm (upper arm, lower arm, hand); LeftLeg/RightLeg (upper leg, lower leg, foot). `MobType=TestZombie`, `Enemy` tag.
- **Look (owner: fit the dark night, less gore on the face):** dull grey-green skin, darker tinted clothes, the calm "Angry Zombie Face" (brows and a plain dark mouth; no teeth, red or drool), and two neon eyes, red on its right and green on its left.
- **R15 gore:** an arm can tear at the shoulder or at the elbow (the upper arm stays as a stump). Leg loss now finds the R15 `Root` motor, so R15 crawls too.
- **Dents:** skipped on this zombie, because its clothes are painted onto the body parts and the head is a custom mesh. Shots still leave the wound, hole and green blood. Block mobs still dent.
- The old block dummy is in `ServerStorage._Backups`. `TestRangeServer` stands each rig at its own height.

## 13. Shotgun, AK and sniper (29 Oct)

Owner asked for three more guns that each feel like the real thing: a shotgun that shoves the player back, throws zombies far into a ragdoll and splatters them; a fast AK with less ragdoll; and a proper sniper. All numbers live in `GameConfig.Guns`.

- **Loadout:** `GameConfig.Loadout = { "Pistol", "Shotgun", "AK", "Sniper" }`. Keys 1–4, the scroll wheel or gamepad Y switch guns. The old gun drops away for `SwitchLowerTime`, then the new one comes up over its `EquipTime`. Each gun keeps its own ammo. The HUD shows the gun's `DisplayName` above the ammo count.
- **Models (Toolbox, scripts stripped):** Ithaca 37 shotgun, ACS AK-47, Kar98k with scope, in `Assets.ViewModels`. Moving parts are marked with the `VmGroup` attribute (Pump, Mag, Slide, Bolt, Shell).
- **Hold:** the three long guns sit lower right and turned so their side shows (`HipOffset` about (0.27, -0.33, -0.44), `HipAngles` (0, 7, -4)). Each sets its own `LeftShoulder`, so the left arm comes up from below the screen to the front grip instead of lying across the middle. Player attributes `DebugHipOffset`, `DebugHipAngles` and `DebugLeftShoulder` override these live for tuning.
- **Shotgun (pump):**
  - 10 pellets of 17 damage, full damage to 10 studs, down to 30% by 32 studs.
  - Big kick, shake and FOV punch, and the blast pushes the shooter back (`PlayerPush` 20 over 0.14 s).
  - Pellet hits stack into one heavy shove: zombies fall down (`KnockDown`) and dead ones fly far as ragdolls.
  - A point-blank kill (8 studs or less, at least half the pellets hit) splats: the torso bursts, a spare limb or two tear off, the head pops, and gore covers the floor and walls.
  - It pumps after every shot and the red shell flies out. It reloads one shell at a time; a click during the reload finishes the shell in hand and fires.
- **AK (full auto, 600 RPM):**
  - 28 damage (62 to the head) and fast, thin tracers.
  - Climbing recoil that pulls right; bloom builds while you hold the trigger.
  - Small shove and short ragdoll throw; exit spray on every hit.
  - Reload drops the real curved mag, and an empty reload also racks the charging handle.
- **Sniper (bolt action):**
  - 175 damage, 525 to the head. One shot kills.
  - The round passes through up to 3 zombies at 100%, 75% and 56% damage.
  - Any limb it hits tears off and a head hit pops the head.
  - Scope: a round lens with a German post reticle and a lit red tip; the gun hides when the sights are up.
  - Scope sway: holding Shift steadies it for 4 seconds; once that runs out the sway is worse until your breath recovers.
  - Bolt cycle: the right hand leaves the grip, lifts and pulls the bolt, the case flies, then the bolt goes home.
  - Reload: the bolt opens, three rounds are pressed in, and the bolt closes.
- **Server:**
  - `Fire(origin, gunName, shots)` sends every pellet with its hits in order. The server checks the gun, fire rate, ammo, cone and penetration.
  - Hits are grouped per zombie, so a shotgun blast is one heavy hit.
  - `Reload("Stop")` ends a shell reload early, and `Remotes.Equip` switches guns.
  - Ragdoll turns the joints into ball sockets.
- **Removed by the owner:** damage numbers over mobs ("no damage counters"). Don't add them back.
- **Backups:** `ServerStorage._Backups/*_2026-10-29_beforeGuns`.
- **Still to do:** the owner's own feel pass on each gun, real audio instead of the placeholders, and touch controls (Day 2).

## 14. Pass B: player health, zombie attacks, going down, the devour (29 Oct)

Where each piece comes from: health that comes back by itself and three swipes to go down is Call of Duty Zombies; going down with a pistol, bleeding out and teammate revive is Left 4 Dead; the ECG health readout is Resident Evil.

- **Health:** 100 HP. It comes back at 25/s after 4 s without a hit. Hits within 0.3 s of each other count once. Nothing can hurt you for 2.5 s after spawning. All numbers are in `GameConfig.Player`.
- **Zombie swipe** (`GameConfig.Mobs.TestZombie.Attack`, `ServerStorage.Modules.MobAttack`):
  - Inside 4 studs the zombie stops and raises one arm for 0.55 s, then swings. The hit lands if you are still within 5.5 studs and inside its 90° front arc.
  - It follows you for the first 60% of the windup and then commits, so a late sidestep makes it miss.
  - Shooting it during the windup staggers it and breaks off the swing (`MobReactions` now sets `StaggerUntil`).
  - 34 damage. Losing one arm makes it 0.65×. With no arms it lunges to bite at 0.5×. Crawlers do 0.7× with a shorter reach.
  - Clients pose the swing (`StarterPlayerScripts.MobPose`): the arm rises past the head, rakes across the body, and the torso and head twist with it. This is done on joint C0, so it doesn't fight the animations or `MobImpact`.
- **Hit feedback:** the camera snaps away from the side the swipe came from, with shake and an FOV punch (`GunClient`). Three dark claw streaks flash on that side and the screen edges darken. At low health (35% or less) the edges stay, colour drains (`Lighting.HurtColor`) and an APM heartbeat plays. Nothing on screen is red.
- **Health readout** (`StarterGui.HUD.Health`, bottom left, mirroring the ammo block): a heart-monitor trace over a thin bar, labelled FINE, CAUTION or DANGER. The beat quickens from 72 to 128 BPM as health drops, and the damage chunk on the bar drains after a beat. Roblox's own health bar is hidden.
- **Down** (`ServerStorage.Modules.PlayerHealth`):
  - At 0 HP you drop to the floor (placeholder root-joint pose) with eyes about 2.4 studs lower. You crawl at speed 4 with the pistol only, which the server enforces.
  - The bar becomes the 30 s bleed-out. Every zombie hit while you're down takes 3 s off, and you can't be hit for 2 s after you fall.
  - The trace slows to about 46 BPM and the beats stumble.
- **Getting up:**
  - **Self-revive:** hold E (B on gamepad, or press and hold the on-screen key on touch) for 3 s. You get one per life for now; the brief says one per solo match once matches exist.
  - **Teammate revive:** a teammate holds the `Revive` ProximityPrompt on you for 4 s. The prompt is hidden on your own screen.
  - You stand up at 50 HP. Zombies within 9 studs are shoved back and staggered, and you can't be hit for 1.5 s.
- **The devour:**
  - It starts when the bleed-out runs out, or when you're down with no self-revive left and nobody standing who could pick you up.
  - Up to 6 hunting zombies within 30 studs walk to spots around the body and claw it. The claws do no damage and only drive the screen.
  - Every claw flashes on screen and shakes the view. The view sinks and fades to black over 4 s, then you die, and you respawn after 5 s.
  - Other zombies ignore a player being eaten and go for the friends.
- **Test range AI:** walkers hunt the nearest player who is standing or down, and the whole zombie AI is in `TestRangeServer.hunt`. Two engine traps were fixed. `Humanoid:MoveTo` gives up after 8 s and doesn't restart for the same point, so the goal is nudged on every call. A shove with `FallingDown` threw zombies off the map or left them on their backs, so the get-up shove is velocity plus a stagger only.
- **Sounds** (ProSoundEffects and APM; Roblox-licensed): `Player/{Hurt,Claw,Down,GetUp,Devour,Heartbeat}` and `Mobs/TestZombie/Swing`.
- **Tested in Play:**
  - Three swipes take you down.
  - Hits while down drain the bleed-out.
  - The self-revive works: back up at 50 HP with the charge spent.
  - The devour, death and respawn run in order.
  - Hit, down and devour screens were checked in screenshots, and there were no script errors.
- **Not tested yet:**
  - Teammate revive, because it needs two players. Use Studio's Test > Clients and Servers with 2 players.
  - The touch self-revive key.
- **Backups:** `ServerStorage._Backups/*_2026-10-29_beforeHealth` (GameConfig, GunServer, TestRangeServer, MobReactions, GunClient, HUD).

## 15. Pass C: zombie navigation (29 Oct)

Proven model: Call of Duty Zombies and Left 4 Dead hordes. Zombies come over and through things, not around them, and they look stupid doing it.

- **`ServerStorage.Modules.MobAI`** now owns the hunt loop. `TestRangeServer` only spawns.
  - Close (under `Navigation.DirectRange`) and in plain sight: walk straight at the target.
  - Otherwise: a PathfindingService path (agent radius 1.6, height 5.5, no jumping). It repaths when the target moves more than `RepathMove`.
  - Fences and barricades carry `PathfindingModifier`s with PassThrough on and the labels "Vault" and "Break". Paths may run through them at a cost (`Navigation.Costs`), so the horde comes straight over.
- **Dumb first.** At a tagged obstacle a zombie bumps into it, shuffles along it and claws at it for `DumbTime` (half that at a barricade). Then:
  - **`Vaultable`** (tag): an anchored-root curve over the top in `VaultTime`, with a two-handed "Vault" pose (MobPose). Anything taller than `MaxVault` above the ground counts as a wall.
  - **`Breakable`** (tag, plank barricades): claw, tear one WoodPlanks board off (`Barricades.Rip`), wait `BreakDelay`, repeat. When no board is left the rest collapses and the path cost drops to nothing. Torn boards fly at the zombie and fade after 12 s. `Barricades.Repair` puts them back (for pass D).
- **Stuck:** under `StuckDistance` of headway in `StuckTime`, the zombie shuffles aside for `MillTime` and repaths.
- **No hits through walls:** a swing only starts with a clear line (`MobAttack.Sees`), and it only lands if the line is still clear.
- **Static targets** in the range now stand unanchored and wake up to hunt when shot or when a player comes within `TestRange.WakeRange` (18). The owner had read the anchored ones as stuck zombies.
- **Test layout:** a fence line on the left and a concrete wall with a plank barricade (Toolbox, Shadow_Spb) in a doorway at z = -16. Spare Toolbox copies are in `ServerStorage._ToolboxStaging`.
- **Tested in Play:**
  - Two walkers tore the barricade down in about 10 s and came through.
  - Zombies also vaulted the fence.
  - No script errors.

## 16. Shooting the world by material (29 Oct, start of pass D)

Proven model: Battlefield props and Rainbow Six Siege soft walls, scaled down. What a bullet does depends on the part it stops in (`GameConfig.WorldDamage`):

| Class | What counts | Effect |
|---|---|---|
| Shatter | Glass and Ice material, or any see-through part named like glass, window or pane | Breaks on the first hit into 14–20 wedge shards that drop at the window |
| Break | Wood, WoodPlanks, Plastic, SmoothPlastic, Fabric, Cardboard | Small things (under 6 cubic studs) break whole. Bigger ones (doors, crates, fence rails) break **where they're hit**: see below |
| Chip | Concrete, Brick, Rock and the other stones | Dark hole, grey dust and a few sparks; never breaks |
| Dent | Metal, DiamondPlate, CorrodedMetal, Foil | Bright ring round a dark pit, with lots of sparks; never breaks |

- **Siege-style holes (owner, 29 Oct: "whole door broke when I shot only a small").**
  - Each hit cuts a patch of anchored cells (about 1 stud, `CellHealth` 15) round itself, snapped to the part's own grid. The rest of the part stays as up to six whole blocks. The wood grain only breaks up round the damage, not across the whole door (owner asked for the grid fix, 29 Oct).
  - **Hole size is per gun** (owner, 29 Oct: "the breaking is too small"): each gun has `BreakRadius` in `GameConfig.Guns`. Pistol 1.4, AK 1.2, shotgun 0.9 per pellet (ten pellets make a patch), sniper 2.6 studs. A bullet hurts the cells inside that radius, falling off as 1 - (d/r)², so the ring round the hit goes too. A pistol shot now knocks out about a 2 × 2 stud hole.
  - Knocked-out cells drop as loose pieces.
  - Under `CollapseShare` (30%) of the cells left, the rest falls.
- **Pieces stay:** broken pieces lie where they fell for about 45 s, then fade (`DebrisTime`). Every hit on something breakable also knocks a splinter off, so you see it wearing down.
- **Fixed bug (owner: "items should break not disappear"):** the pieces were being made after the part was hidden, so they copied its invisibility. Pieces are now made first.
- **Plank barricades:** gunfire blows a board off along the shot after `Barricades.BoardHealth` (90, about three pistol shots). The rest falls once no board is left.
- **Loose props** (unanchored) get pushed along the shot (`PushPerDamage`) and break the same way.
- **Never break:** parts over `MaxBreakVolume` (300 cubic studs: walls and floors) and parts with the `Indestructible` attribute.
- **How a hit flows:**
  - The client reports `World = { Part, Pos }` with each bullet.
  - GunServer checks it: on the ray, within range, the first thing along the line, and not a character or mob.
  - Then `WorldDamage.Hit` runs with the bullet's falloff damage.
  - The client draws the marks and dust (`CombatFx.WorldImpact`). Marks on a part or cell vanish when it breaks.
- **Restore:** `WorldDamage.Restore(part)` and `Barricades.Repair(model)` put things back (for repairs and round resets).
- **Sounds:** World/WoodBreak, World/PlankDrop, World/GlassBreak, World/StoneChunk (unused so far).
- **Test props:**
  - `TestRange.Facade`: a concrete front wall at z = -8 with a Toolbox wooden door (Sheep678, clean) and a two-pane wood window built by hand.
  - `TestRange.ShootProps`: a diamond-plate sheet, a plastic crate and a loose wooden crate.
- **Toolbox trap:** the Toolbox window "Window Glass Pane Frame House Decor Windows" (124158210649315) hides a fake Studio "troubleshoot" GUI and a `Runtime` script. It was deleted on insert. Never use it.
- **Tested in Play:**
  - The window pane shatters with shards on the sill.
  - The wood crate chips, then breaks into pieces that stay.
  - The door gets a hole where it's shot, not the whole door.
  - Metal dents.
  - A barricade board comes off when shot.
  - No script errors.
- **Look:** faint texture seams show only round the holes, where they read as splintered wood.

## 17. Pass E: night atmosphere (29 Oct)

The owner likes night with lights, so the night is dark blue but readable, and the light comes from lamps and your flashlight, not from a brighter sky.

- **Lighting:**
  - ClockTime 0.5, Brightness 2, a cool Ambient (34, 38, 48) and OutdoorAmbient (78, 86, 108), ExposureCompensation 0.25.
  - Atmosphere: density 0.36 with a blue-grey haze. SunRays are off.
  - `NightGrade` colour correction: saturation -0.22, contrast 0.12 and a cool tint. `HurtColor` is untouched.
  - The daytime look is backed up in `ServerStorage._Backups.Lighting_2026-10-29_beforeNight` (its properties are stored as attributes).
  - A first try at a lower ambient came out pitch black, so it was raised.
- **Lamps (`TestRange.Lights`):**
  - Five curved street lights from the Toolbox ("Realistic Street Lamp", 116732677444326). Each has a downward SpotLight (85°, range 30, shadows), a small glow light and its two light-cone beams, toned down.
  - A small bunker wall light (128497707322556) hangs over the test door.
  - Templates `StreetLight` and `WallLight` are in `ServerStorage._ToolboxStaging`.
  - Lamps carry the `Lamp` tag. The ones with `Faulty = true` (StreetLight3 and DoorLight) buzz, flicker in bursts and sometimes go dark for a second or two (`GameConfig.Night.Lamps`).
- **Toolbox trap again:** all three lamp inserts, and a lantern that was deleted, hid the same fake "Runtime" script with a Studio-looking GUI. Every script, GUI, remote and sound in them was stripped. Expect this on most new Toolbox models.
- **Flashlight** (`StarterPlayerScripts.Flashlight`, `ServerScriptService.NightServer`):
  - It's on at spawn. Toggle it with F, D-pad up, or the "Light" touch button (ContextActionService), which plays a click.
  - Your own light is a part on the camera, 1.2 studs ahead so your own body never shadows it. It has a narrow beam (42°, range 60) and a wide soft spill, and it trails the view slightly when you turn.
  - Everyone else sees a SpotLight on your head (`TeamFlashlight`), switched by the `Flashlight` remote. Your client deletes its own copy of it.
- **Ambience** (`StarterPlayerScripts.NightAmbience`):
  - A wind loop under everything (PSE 9114057128) and a bulb buzz on faulty lamps (PSE 9116264824).
  - **Fear sting:** one sting from `Night/Stinger` (four PSE metal and piano stings) when a mob gets within 10 studs after no mob was within 20 for 15 s, at most once per 30 s.
- **Tested in Play:**
  - The flashlight rig follows the camera and lights the door.
  - The head-light copy is removed locally.
  - Wind plays and there are no script errors.
- **Streaming fix (applied and tested):** with StreamingEnabled the lamps had no parts yet when the script first read them, so the faulty lamps never buzzed or flickered.
  - Lamp models now stream in whole (ModelStreamingMode Atomic). The script also waits for their parts, with each lamp in its own thread.
  - In Play both faulty lamps buzz, and StreetLight3 swings between full brightness and off.
  - **Rule:** any map model a client script reads must be Atomic.

## 18. Doors and pickups (29 Oct)

The owner asked for opening doors and highlighted ammo on the ground to pick up ("etc"). I added medkits and zombie ammo drops as the "etc".

- **Doors** (`ServerStorage.Modules.Doors`, started by `ServerScriptService.InteractServer`):
  - A door is a model tagged `Door`. Its `Leaf` model holds the slab as PrimaryPart; everything else is the frame.
  - The leaf turns on the slab's edge (`HingeSide` attribute: -1 left, 1 right).
  - E (or gamepad X) opens and closes it, with a creak (PSE 9114135682). It eases out over 0.45 s and always swings away from whoever opens it.
  - Bullet holes are cut inside the leaf, so they swing with it. A door shot to bits can't be opened any more.
  - The test door (`TestRange.Facade.Door`) was split into Frame and Leaf.
- **Zombies and doors** (`MobAI`):
  - A closed door is an obstacle of kind "Door". The zombie fumbles at it for 35% of the usual dumb time, then shoves it open away from itself.
  - Paths go through doors at cost 4 (PathfindingModifier "Door" on the slab).
  - **Not seen in Play yet:** the door was open while the zombies ran.
- **Pickups** (`GameConfig.Pickups`, templates in `ServerStorage.Pickups`):
  - Models tagged `Pickup` with `Kind` "Ammo" or "Medkit". E takes them.
  - **Ammo** gives 2 magazines to every gun, capped at each gun's starting reserve (the `GiveAmmo` BindableFunction in GunServer). If you're full, the box stays.
  - **Medkit** heals 50 if you're hurt. Nothing is picked up while you're down.
  - Placed pickups come back after `Respawn` seconds. They are in `TestRange.Pickups`: three ammo cans and one medkit.
  - Zombies drop a 1-magazine ammo can 25% of the time when they die. It vanishes after 40 s (`workspace.Drops`).
  - **Outline:** the `StarterPlayerScripts.Pickups` client script adds a pulsing Highlight to pickups within 24 studs (yellow for ammo, green for medkits, hidden behind walls).
- **Infinite reserve is off** (`GameConfig.Debug.InfiniteReserve = false`), so ammo matters. The HUD shows the real reserve.
- **Toolbox trap, worse this time:** the medkit (82215467333631) hid its "Runtime" payload *inside its SurfaceAppearance*, which I had kept.
  - In Studio Play it showed a fake "Disconnected… Recover" Studio dialog over the game, a lure to click. It returns at once outside Studio. Nobody clicked it.
  - It was deleted, and a sweep found no other copies.
  - **Rule:** strip children of SurfaceAppearances, Decals, Lights and Welds too, not just scripts in plain view.
- **Collateral:** that clean-up sweep also stripped joints, the Humanoid and saved animations from the unused `ServerStorage._ToolboxStaging.DeagleViewmodel`. No script uses it. Reinsert it from the Toolbox if it's wanted.
- **Tested in Play:**
  - The door opens away from the player.
  - Ammo goes 56 → 60 from a can, which then hides to respawn.
  - The medkit shows its green outline.
  - No script errors with seven zombies running.

## 19. Bandages and the hotbar (29 Oct)

Owner: "bandages instead of medkit and the bandages should show on body appropriately when used. I am unable to pick em up and apply. Also make a nice fitting hotbar for the weapons, and things u pick."

- **Why the medkit couldn't be picked up:** it only worked when you were hurt, and health regenerates. Bandages are now carried items, so you can always pick one up unless you're full.
- **Bandages** (`ServerStorage.Modules.Bandages`, `GameConfig.Bandages`):
  - You start each life with 1 and can carry up to 4 (player attribute `Bandages`). E takes a roll off the ground.
  - Key 5, D-pad down or tapping slot 5 applies one when you're hurt. It takes 2.4 s with a rip and a wrap sound, and you can't shoot meanwhile (character attribute `Bandaging`; GunClient and GunServer both check it). Then it heals 40.
  - Going down cancels it, and the bandage isn't used up.
- **On the body:**
  - Every zombie hit that lands records a wound (from `PlayerHealth.Damage`): arm 45%, torso 30%, leg 15%, head 10%, on the side the hit came from.
  - A bandage wraps the oldest open wound with an off-white fabric band, slightly stained: a cylinder round a limb, a band round the torso, a strip round the head.
  - The band is a part named "Bandage" welded inside the limb, so everyone sees it. It stays for the rest of that life.
  - Arm wraps are copied onto the first-person arms (`ViewArms.copyBandages`, at the same spot along the arm and scaled with it). GunClient rebuilds the arms when one lands.
- **Pickup model:** a bandage roll I built in Studio (`ServerStorage.Pickups.Bandage`, icon copy at `ReplicatedStorage.Assets.Icons.Bandage`). No Toolbox, so no payload risk. Two are placed in `TestRange.Pickups` with a pale green outline. Medkits are gone.
- **Hotbar** (`StarterGui.HUD.Hotbar`, authored; `StarterPlayerScripts.Hotbar`):
  - Five flat tiles at the bottom centre in the HUD's style: dark at 0.35, a 1 px hairline, the key number top-left, GothamSSm.
  - Slots 1–4 show the real gun models side-on in ViewportFrames. Slot 5 shows the bandage roll with an "x2" count, dimmed when empty.
  - The equipped gun gets an amber underline and a darker tile (GunClient sets the local player attribute `EquippedGun`).
  - Tapping or clicking a gun slot equips it (`GunClient.HotbarEquip`). Slot 5 fills amber from the bottom while a bandage is going on, and flashes red if you can't use one (full health, none left, down).
- **Tested in Play:** the hotbar renders all five icons and marks the pistol.
  - A bandage applied from the client went from about 49% fill halfway to healed, and the count dropped.
  - Wraps appeared on LeftUpperArm and RightUpperArm, and both were copied onto the first-person arms.
  - Not checked by eye: the wrap from a third-person view.
- **Known noise:** Hotbar logs an "Infinite yield possible" warning for `GunClient.HotbarEquip` because GunClient makes it late. It resolves a moment later.

## 20. Bandage fix: trauma and a readable wrap (29 Oct, late)

Owner: "the bandage anim or use is flawed fix it".

**What was wrong**
- **Use:** health regenerates to full a few seconds after a hit (Call of Duty style), and a bandage refused at full health. So it was almost never usable, and when it was, waiting was faster.
- **Animation:** the first-person forearm pointed almost straight at the camera, so it showed as one big block at the bottom of the screen, and the roll (scaled to 11%) and the wrap were lost behind it and the hotbar.

**The fix**
- **Trauma, from Back 4 Blood's trauma damage.** Each zombie hit leaves a wound holding back `Bandages.TraumaShare` (35%) of the damage. Health only regenerates to MaxHealth minus the open trauma, which is capped at `TraumaMax` (60).
  - The character attribute `Trauma` holds the total. `PlayerHealth` caps regen with `Bandages.Trauma(character)`. Hits taken while down leave a wound with no trauma.
  - A bandage wraps the oldest wound, clears its trauma, then heals `Heal` up to the new ceiling. It can be used whenever you're below max health or have any trauma.
  - The health bar has a new authored `HUD.Health.Bar.Trauma` strip: dark red, right-aligned, showing the part that won't come back.
- **Arm wounds are forearm only** (`LeftLowerArm` / `RightLowerArm`), since that's the part you see in first person; the finished wrap then shows on the gun arms too.
- **Cancel:** picking a gun slot during a bandage sends `Remotes.Bandage:FireServer("Cancel")`, and the bandage isn't used up. Going down still cancels too. Each application is a job token on the server, so a quick cancel and re-apply can't finish early.
- **BandageView rewrite** (`StarterPlayerScripts.BandageView`; the server sets `BandagePart` to the limb):
  - **Forearm wound:** that forearm comes up across the lower-middle view, wrist near the centre and elbow out to the side, palm up. The other hand carries a code-built roll (fabric cylinder with a dark core, 0.15 studs) round it at the wrap's leading edge, the roll spins as it unwinds, a strip runs from the roll onto the arm, and the wrap grows from wrist toward elbow. A right-arm wound mirrors the pose.
  - **Leg, body or head wound:** the left hand pins the loose end low in front and the right hand circles the roll round a point low in view.
  - The arms are posed directly from the ViewArms pieces (no shoulder aiming), so the pose is exact. The pose numbers are constants at the top of the script.
- **Tested in Play:** two zombie hits left 23.8 trauma, and health regenerated to 76.2 and stopped. Trauma survived going down. A bandage started on `RightLowerArm`, was used up, and the wrap was copied onto the first-person arms. The frozen forearm pose (k = 0.5) shows the wrist, the half-done wrap and the sleeve above the hotbar. No new errors.
  - **Not checked by eye:** the leg/body pose, and the frame with the roll passing in front of the arm. The owner came back to the PC mid-test, so I stopped.
- **Backups:** `{Bandages, PlayerHealth, BandageView, Hotbar, PlayerHealthClient, GameConfig, HUD}_2026-10-29_beforeBandageFix`.
