# Allied soldier AI: the build prompt (3 Nov 2026)

This file is the prompt for the session that builds the next pass on HOUND's bots, and the plan.
Read CLAUDE.md, README.md and the top of docs/HORROR-SHOOTER-HANDOFF.md first. Then read, in order,
`Modules.Soldier`, `Modules.CoverMap`, `Modules.Battle` and `GameConfig.War.Battle` in the campaign
place (src/campaign). Nothing in this prompt asks for a new AI from scratch. It asks for the existing
brain to be finished to the standard below.

## 0. What you are

You are the senior AI and gameplay programmer on Last Light's campaign place, Operation Last Light
(placeId 78870312741411). You own `Modules.Soldier`, `Modules.CoverMap`, `Modules.Battle`,
`StarterPlayerScripts.SoldierView` and `GameConfig.War` in the campaign. You work in Luau, through
Rojo, from this repo. A cloud session cannot reach Studio, so you edit files, build both projects to
check they still compile, commit, push, and say plainly that nothing was play-tested.

## 1. The goal in one paragraph

HOUND's twelve soldiers (REYES to VOSS, the slots players do not hold) must read as trained WWII
infantry fighting beside the player, in the spirit of Call of Duty: World at War's squad. The player
should catch an ally doing something smart on its own: covering a teammate's rush, shifting cover
when flanked, dropping as a shell lands, shouting a contact the player had not seen, and staying out
of the player's firing line. They must never read as followers, as a train of clones, or as fearless
machines. Believable judgement beats difficulty, animation count and raw damage.

## 2. What already exists (do not rebuild it)

Check these before writing anything, and extend them rather than replacing them.

| System | Where | What it already does |
|---|---|---|
| Soldier bodies | `Modules.Soldier` (build, stepBody), `SoldierView` | Two invisible anchored parts and a Humanoid on the server; one Heartbeat mover writes CFrames at 20 Hz; every client draws a trimmed R15 from `ReplicatedStorage.WarRigs` with walk, idle, kneel, waist aim, fall and fade, hidden past 380 studs. There is no prone pose yet. |
| Roles | `ROLES`, `ROLE_ORDER`, `pickRole` | Leader, Rifleman, Support (M60, long bursts, hangs back), Assault (faster hops, flanks sooner), Marksman (Sniper, single aimed shots, hangs back). Six to a fireteam, three fireteams. |
| Perception | `Soldier:Look`, `Sees`, `Foes`, `Known`, `Soldier.Spot`, `Soldier.Noise` | View cone and head rays on a stagger (`Brain.Look`, `LookRays`), a memory per foe (`Known`, `Brain.Memory`), the side's shared sightings (`Brain.Share`), heard gunfire within `Brain.Hear` with a jittered position. Soldiers already do not see through walls. |
| Threats and targets | `Threats`, `PickTarget` (has an `OnContact` hook), `Damaged` | Up to three threats, seen first then nearest; the order's `Facing` points stand in when nothing is known; a hit with nothing in sight guesses the shooter nearest `HurtFrom`. |
| Cover | `Modules.CoverMap`, `Soldier:ChooseCover`, `TakeCover`, `CoverHolds`, `SpotFires` | A ray survey on a 4-stud lattice: half cover (kneel to hide, stand to fire) and full cover with a peek spot to either side. Spots are claimed so two soldiers do not share one. Scoring covers protection from each threat, a line of fire, travel, crowding, the lane and the order's area, for the reasons Engage, Advance, Retreat, Flank and Hold. |
| Fight cycle | `Fight`, `Expose`, `Hide`, `Reload`, `Burst`, `Shoot`, `Snap` | Hidden, Exposing (settle), Exposed, back down. Bursts with a gap, reload at 40 % of the magazine when nothing is visible, suppressive fire at a last-seen position for `Brain.SuppressFire` seconds, fire on the move only inside `Brain.MoveFire`. Spread scales with range, role, movement, suppression and settling. |
| Suppression | `Suppress`, `Snap`, `Brain.Suppress` | Rounds passing within `Radius` add `Miss`, hits add `Hit`, it fades at `Fade` a second; past `Pin` the soldier goes down and will not peek; `Aim` widens spread. |
| Movement | `Decide`, `MoveTo`, `Steer`, `CheckStuck`, `Overwatched`, `GoOpen` | PathfindingService paths with doors as walls, hop timing per role, leapfrogging only while a teammate is in cover (`Overwatched`), flank after `Brain.Flank` seconds out of sight, fall back under `Brain.Retreat` health, heal out of the fight (`Heal`, `HealAfter`). |
| Orders | `Battle` (HoundAttack, HoundHold, EnemyDefend, EnemyAttack), `Soldier:SetOrder` | Attack along a lane to a goal, Defend or Hold within a radius facing given points, Retire. Three fireteams get the centre lane and one lane each side. Slot takeover by players, bot respawn, reserves. |
| Mounted guns | `Soldier:Gunner`, `Modules.Emplacements` | Support and Rifleman soldiers man a free gun of their side within 45 studs of their post. |
| Damage | `Soldier:Hurt`, `WarDamage`, `GunServer`, `MobReactions.Hit`, `PlayerHealth.Damage` | One API for shells, emplacements and tanks. Soldiers' rifles keep their own ray path in `Shoot`. |
| Explosives | `ExplosivesServer` (drums), `Modules.Tank` (shells, barrage), `Emplacements` (artillery) | These are the only explosive threats in the campaign today. **There is no grenade system in either place.** |
| Voice | `RadioVoice` (client, text-to-speech through a radio filter, driven by `Remotes.Match "Radio", text, key`), `WarServer` radio lines, `Callout` + `SquadVoiceClient` + `SquadVoiceServer` (player callouts only, `GameConfig.Voice.Keys`), `Shared.VoiceManifest` (empty until voices are recorded) | The commander talks. **Bots do not speak at all yet**, and the squad voice path only accepts lines from players. |

Keep the light-body architecture. The owner saw the physics cost of full rigs and will not accept
it again. Everything below has to run inside the existing think loop (`Brain.Think`, 0.25 s, staggered
per soldier), the look stagger and the one Heartbeat mover, with no per-frame work per soldier.

## 3. The behaviours to deliver

Each item says what the soldier does, what the player sees, and where it goes in the code. Treat the
code locations as the integration point, not as a suggestion to add a parallel system.

### 3.1 Movement and stance

- **Three gaits, chosen per leg of a move.** Sprint across open ground that a known or expected
  threat can see (`CoverHolds` from the threat is false along the leg); walk when no threat is
  known and the area is quiet; crouch-walk the last stretch into cover and whenever Suppression
  is above `Pin`. The gait sets WalkSpeed in `MoveTo` and an attribute `Gait` that `SoldierView`
  reads to pick the walk animation and its speed. Do not add a third animation set if the rig
  has none. Scale the existing walk.
- **Prone.** Add stance "Prone" beside Stand and Crouch: hitbox height about 1.2 studs, head
  behind it, no fire except from a Marksman. Use it when Suppression hits 1.0 in the open, when a
  shell or barrage lands within 12 studs, and for a Marksman holding a long line. `SoldierView`
  needs a lying pose built from the kneel pose's joint table approach (`Battle.Kneel`); write a
  `Prone` joint table in `GameConfig.War.Battle` the same way.
- **Indirect routes.** When `ChooseCover` picks a spot and the straight path crosses a lane that
  a visible threat fires down, add waypoints through the nearest surveyed cover (`CoverMap.Near`)
  so the soldier hops cover to cover instead of running the diagonal. This belongs in `MoveTo`
  as a pre-pass over the path, not in a new mover.
- **No train.** When a fireteam moves, each member picks its own spot (`ChooseCover` already
  penalises crowding; raise the penalty for spots within 6 studs of another ally's claimed spot
  or destination, and add a small random offset to `GoOpen` goals). Members must never share a
  destination point.
- **Bounding by fireteam.** Make the existing `Overwatched` check explicit: a soldier advances
  only while at least one teammate in its fireteam is in cover with a line of fire toward the
  main threat and not reloading. The watcher fires suppressive bursts at the threat's last
  position while the mover is in the open (`StartBurst` with suppressing true). When the mover
  arrives, roles swap on the next hop. Assault moves first, Support watches first, Leader goes
  last. Stop bounding and hold when two of the six are down or the fireteam's mean Suppression is
  above 0.6.

### 3.2 Cover

- **Compromise checks.** Once a second while Hidden, test the current spot against each known
  threat with `CoverHolds`. If the main threat can see the soldier kneeling, choose Engage cover
  again (this exists for `Facing`; extend it to the ray test).
- **Peek discipline.** A peek ends early when `Snap` registers two rounds in a second. Vary peek
  length by role (Marksman longer, Assault shorter). After three peeks from the same spot without a
  shot fired, change spot.
- **Destroyed cover.** Breakable parts (wood, crates, anything not marked `Indestructible`) can be
  removed by `WorldDamage`. When a claimed spot's cover part is gone, `CoverMap` must drop the spot
  and the soldier must choose again. Listen for the part's `AncestryChanged` at claim time, or
  re-probe the spot's covered directions when `CoverHolds` fails.
- **MeshProxy.** `CoverMap.solid` must accept parts named or tagged `MeshProxy` (the hidden
  collision boxes under FARM's Blender meshes), or the farm has no cover.

### 3.3 Combat

- **Engagement ranges by weapon.** Read the soldier's `Gun` and use `GameConfig.Guns[Gun]`'s
  range and rate where the soldier stats do not override them. Support opens at long range with
  long bursts; Rifleman inside 120 studs; Assault inside 60 and prefers to close; Marksman waits
  for a settled single shot past 80 studs and does not fire inside 20 unless pressed.
- **Target priority.** In `PickTarget`, add weight for: a foe shooting at this soldier or at the
  player (use `HurtFrom` and the player's `PlayerHealth` last-damage position, which you add as a
  player attribute `HurtFrom` if it is not there), a foe within 15 studs, a foe on a mounted gun,
  and a foe the fireteam has not yet engaged. Keep the existing visibility and distance terms.
- **Investigate, do not forget.** When the target has been out of sight for `Brain.Memory`
  seconds and no other threat is known, a Rifleman or Assault soldier moves to cover that looks
  at the last known position (`ChooseCover("Flank")` already finds a new angle; add a reason
  "Search" that prefers spots within 20 studs of `rec.Pos` with a line of fire to it), peeks, and
  only then clears the record. Marksman and Support hold and watch that position instead.
- **Reload rules.** Never reload while Exposed with a visible target and rounds left. Reload at
  40 % when Hidden (exists). When the magazine runs dry mid-burst in the open, finish the move to
  cover first, then reload. Say "Reloading" (3.5).
- **No cheating.** Keep every shot on `Sees` and `FireLine`. Suppressive fire at a remembered
  position is the only fire without a visible target, and it must still pass `FireLine`.

### 3.4 Protecting the player

The player is one of the fireteam, not its centre. Each think, a soldier within 40 studs of a
player of its side does these checks, and acts only if it is not already in a fight for its life
(Suppression under `Pin` and health above `Retreat`):

- **Flank watch.** A known threat whose bearing from the player is more than 70 degrees off the
  player's facing, and that is closer to the player than to any other ally, becomes this soldier's
  target with a bonus in `PickTarget`, and the soldier says "Watch your flank" (3.5).
- **Cover the player's move.** A player who has been sprinting in the open for over 1.5 s with a
  visible threat gets suppressive fire from the nearest Hidden ally with a line (`StartBurst`
  suppressing), and "Covering you".
- **Pressure.** A player who has taken more than 40 damage in 5 s has at most two allies choose
  Engage cover within 18 studs of them. Not the whole squad.
- **Do not block.** `ChooseCover` and `GoOpen` reject destinations within 5 studs in front of a
  player's facing and inside the player's aim line (a ray from the player's head along its look,
  checked flat). A soldier already standing there steps aside on its next hop.
- **Grenade warning.** Only if a grenade system exists (see 3.6).

### 3.5 Radio and shouts

Bots have no voice today. Build it on what exists:

- **Lines.** Write original lines in the World at War register: short, urgent, no copied dialogue.
  Put them in `GameConfig.War.Voice` as keys with variants, cooldown, chance and priority, the same
  shape as `GameConfig.Voice.Keys`: Contact, ContactSide (left, right, front, building), Moving,
  Covering, Reloading, Pinned, Flank, Grenade (only if 3.6 lands), ManDown, Falling back, Hold,
  Push, Clear, Acknowledge. Examples to write around, not to copy from any game: "Contact,
  front!", "Taking fire, get down!", "Moving up!", "Got you covered!", "They're in that building!",
  "I'm hit, falling back!", "Hold here!", "They're breaking, push!"
- **Playback.** Until recorded voices land in `Shared.VoiceManifest`, drive lines the way
  `RadioVoice` already does, through Roblox text-to-speech, but positional: a per-soldier
  `AudioTextToSpeech` into an `AudioEmitter` on the soldier's drawn head (client side, in
  `SoldierView`), with the radio chain from `RadioVoice` as a second path for lines marked
  `Radio = true` (Contact, ManDown, Pinned, Hold, Push). The server decides who says what and
  fires one event, `Remotes.SoldierSay (model, key, variant)`. Clients play it. When
  `VoiceManifest.Squad` has entries, play the clip instead of TTS. Do not block on ElevenLabs.
- **Discipline.** One speaker per fireteam at a time, a squad-wide gap of 1.2 s, per-key
  cooldowns, and a priority that lets ManDown, Grenade and Pinned cut in. A Contact is said once
  per engagement per fireteam (use `Engaged`), by the soldier who saw it first (`OnContact`).
  Acknowledgements ("Copy", "On it") follow a Leader's Hold or Push line with 50 % chance from one
  other member. Never let the commander's `RadioVoice` and a bot line overlap: `RadioVoice` sets
  the folder attribute `Talking`, and bot lines wait on it.

### 3.6 Explosive awareness

- **What exists.** Drums (`ExplosivesServer`), tank shells and barrages (`Modules.Tank`) and
  artillery (`Emplacements`). None of these warn soldiers today. Add a server call
  `Soldier.Danger(pos, radius, inSeconds, side)` that every one of these fires when a threat is
  known in advance: a shell in flight, a barrage marker, a drum under fire, a satchel fuse. A
  soldier inside the radius leaves it along the direction away from the centre, preferring a
  surveyed spot outside the radius with cover from the main threat, and goes Prone if it cannot
  make it in time. Allies must not path into a danger zone of their own side (satchels on tanks).
- **Grenades.** Players and soldiers have no grenades in the campaign. Do not invent them in this
  pass. If the owner adds thrown grenades later, they call `Soldier.Danger` on the throw and the
  Grenade line comes on. Say this clearly in the handoff.

### 3.7 Suppression and injury

Keep the existing model and extend it:

- Above 0.6 Suppression, a soldier stops advancing, will not volunteer as the bounding mover, and
  says "Pinned" once. Above `Pin` it does not peek (exists). Above 0.9 in the open it goes Prone.
- A pinned soldier regains confidence only as `Fade` brings it down, and the first hop after
  being pinned waits an extra `Hop` roll.
- Below `Retreat` health (exists), the soldier chooses Retreat cover, then holds there and heals
  (`HealAfter`), and says "Falling back". A Leader or the nearest Rifleman takes its place in the
  bounding pair.
- The whole fireteam stops bounding and holds when its mean Suppression is over 0.6 or two of six
  are down. It resumes when the mean drops under 0.3.

### 3.8 Squad coordination and roles

- **Role reassignment.** When a Leader dies, the Rifleman with the highest health becomes Leader
  (attribute `Role`, `RoleStats`). When a Support dies, the next respawn in that fireteam is
  Support. `Battle.spawnBot` already picks by slot; make the pick look at who is alive.
- **Casualty awareness.** On a teammate's `Fall`, members within 30 studs who saw it (a `Sees`
  check against the body's last position) say "Man down", and the nearest one with no visible
  target chooses Engage cover facing the shooter's last known position.
- **Shared knowledge stays partial.** `Soldier.Spot` shares sightings within `Brain.Share`. Keep
  that radius; do not make it global.

### 3.9 Objectives

Orders already come from `Battle` and `WarServer`. Add:

- **Secure on arrival.** When a fireteam's Attack goal is reached and no threat is known for 6 s,
  the fireteam spreads to Hold cover facing the next objective (the next step's goal, which
  `WarServer` can expose as the order's `Facing`), and one member looks over the ground behind.
- **Do not push into a wall of fire.** If the fireteam's mean Suppression exceeds 0.6 or three
  members fell inside 20 s, the order becomes Hold at the last cover line until two think
  cycles of calm pass. `Battle` keeps the Attack goal; the soldiers decide when to resume.

## 4. Architecture rules

- Everything stays in `Modules.Soldier`, `Modules.CoverMap`, `Modules.Battle`, `SoldierView` and
  `GameConfig.War`. If `Soldier` grows past about 2,200 lines, split it into sibling modules it
  requires (`SoldierVoice`, `SoldierDanger`) rather than a new framework.
- All numbers go in `GameConfig.War.Battle` or `GameConfig.War.Voice`. No literals in the brain.
- Per-soldier work stays inside the think loop and the look stagger. Checks against players run at
  most twice a second per soldier. Ray budgets: no more than `LookRays` plus 4 rays per think.
- Every new behaviour has an `Order.Mode` or role gate, so Enemy soldiers (Lamplighters) get the
  cover, suppression and danger behaviour but not the player-protection behaviour.
- Server-authoritative. Clients only draw and play. `SoldierView` reads attributes (`Stance`,
  `Gait`, `AimPitch`) and events (`Remotes.ShotFx`, `Remotes.SoldierSay`).
- Follow the owner's rules in CLAUDE.md: no damage numbers, no script-built UI, no live DataStore
  writes from tests, plain full sentences in the handoff.

## 5. Tests you must run and make pass

A cloud session cannot play. Write each scenario as a function in a `_DevTools` module the owner
runs from the Command Bar in a Play test, with a pass line printed to Output, plus the Studio checks
listed. Fix what fails; do not document a failure as a known issue unless it is a map ask.

1. **Independent cover moves.** Six bots advance up the road with the player. Pass: no two bots
   claim spots within 6 studs, no bot's destination equals another's, at least one leapfrog with
   a watcher firing while a mover is in the open.
2. **Pinned player.** Spawn four Lamplighters on the player. Pass: at most two allies move to
   within 18 studs of the player, one says "Covering you", the rest hold their lane.
3. **Suppress and advance.** Pass: a Support bot's burst at a threat's last position overlaps an
   Assault bot's move, logged with timestamps.
4. **Flank detection.** Spawn a Lamplighter 90 degrees off the player's facing, 25 studs out.
   Pass: an ally retargets it inside 1.5 s and says "Watch your flank".
5. **Explosive threat.** Fire a tank barrage at a holding fireteam. Pass: every soldier inside
   the radius leaves it or goes Prone before impact; none moves toward a second known threat.
6. **Lost contact.** A Lamplighter breaks line of sight for 12 s. Pass: a Rifleman moves to a spot
   with a line on the last known position, peeks, and clears the record only after looking.
7. **Crowded cover.** Send a fireteam into a four-spot area. Pass: four take spots, two find
   cover elsewhere or kneel in the open at an offset; nobody stacks.
8. **Injury.** Damage a bot to 30 %. Pass: it chooses Retreat cover, says "Falling back", heals,
   and rejoins only above 70 %.
9. **Casualty and roles.** Kill a Leader. Pass: a Rifleman becomes Leader within one think, the
   fireteam keeps bounding, "Man down" is said once.
10. **Complex ground.** Run the whole valley (CRASH to BASIN) with `WarStartStep`. Pass: no
    "Soldier ...: err" lines, no bot stuck more than 8 s (`CheckStuck`), FARM's MeshProxy boxes
    count as cover, server heartbeat stays under 3 ms with 24 soldiers.

Record results in the top section of docs/HORROR-SHOOTER-HANDOFF.md with the date, what was run,
and what the owner still has to test in Play.

## 6. What to say back to the owner

Plain, full sentences. Say what changed in which files, what the owner must do in Studio (pull,
`rojo serve campaign.project.json`, run the test module), and that nothing was play-tested from
the cloud. List any map asks (cover counts per zone, a prone-safe floor height) separately.
