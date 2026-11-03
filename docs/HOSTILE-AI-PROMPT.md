# Hostile infantry AI: the build prompt (3 Nov 2026)

This file is the prompt for the session that builds the next pass on the Lamplighters, the enemy
infantry of Operation Last Light, and the plan. It is the pair of docs/ALLIED-AI-PROMPT.md. Both
sides run one brain (`Modules.Soldier`), so read that prompt first: the shared work it lists (gaits,
prone, cover compromise checks, the Search reason, `Soldier.Danger`, the bot voice path) is built
once and serves both sides. This prompt covers what makes the enemy an enemy. Build the two in the
same session, or the allied pass first; never in two sessions at once, because they edit the same
files.

Read CLAUDE.md, README.md and the top of docs/HORROR-SHOOTER-HANDOFF.md. Then read `Modules.Soldier`,
`Modules.Battle` (the enemy half: `EnemyDefend`, `EnemyAttack`, `reinforce`, `RetireEnemies`),
`Modules.CoverMap`, `Modules.Emplacements`, `Modules.Tank`, `ServerScriptService.WarServer` (the
steps that call Battle) and `GameConfig.War` in the campaign place (src/campaign).

## 0. What you are

You are the senior tactical AI programmer on Last Light's campaign place (placeId 78870312741411).
You own `Modules.Soldier`, `Modules.Battle`, `Modules.CoverMap`, `StarterPlayerScripts.SoldierView`
and `GameConfig.War`. You work in Luau through Rojo from this repo. A cloud session cannot reach
Studio: edit, build both projects, commit, push, and say plainly that nothing was play-tested.

## 1. The goal in one paragraph

The Lamplighters must fight like a trained, coordinated militia in the spirit of the hostile infantry
in Call of Duty: World at War. They hold ground from cover, spot and call the squad, suppress the
player and HOUND, send flankers round by real routes, throw grenades at a player who sits behind a
wall, pull back when a line breaks and reform at the next one, hunt a player they have lost, and
fight HOUND's bots as seriously as the player. They must never stand as targets, charge in a line, or
know where the player is without seeing or hearing them. Dangerous but fair: no omniscience, no
teleporting, no perfect aim. Difficulty comes from better decisions, never from more health.

## 2. The fiction (lines and looks must fit it)

The Lamplighters are not WWII Germans or Japanese. They are the militia that follows the Beacon: gas
masks, a chest lamp (`GameConfig.War.Looks`), black lamp oil for blood, no face gore
(`GameConfig.Mobs.Lamplighter`). Write their radio lines as a disciplined militia on a winter valley
road, with the urgency of World at War but none of its dialogue. No slurs, no real-world army names.

## 3. What already exists (do not rebuild it)

| System | Where | What it already does |
|---|---|---|
| Kinds | `GameConfig.War.Soldiers.Lamplighter`, `.Heavy` | Lamplighter: AK, 130 health, 24-round magazine, slow React (0.5 to 1 s), Damage 8 on players, 9 on bots. Heavy: 650 health, 80 rounds, 1.15 scale, `Rush`: walks at a foe firing and skips cover. Rigs HostileA, HostileB, HeavyA in `ServerStorage.SoldierRigs`, drawn light from `ReplicatedStorage.WarRigs`. |
| Roles | `ROLES`, `pickRole` | The same five roles as HOUND (Leader, Rifleman, Support with the M60, Assault, Marksman with the Sniper), picked in `ROLE_ORDER` as a side's count grows. The post's `Kind` attribute picks the kind, not the role. |
| Orders | `Battle.EnemyDefend(posts, rear, pool, from)`, `EnemyAttack(spots, count, goal, kind)`, `RetireEnemies`, `ClearEnemies` | A defender holds cover within `DefendRadius` of its post facing `From` (HOUND's way in). An attacker pushes a lane from its spawn to a goal. Reinforcements walk in from the `<group>_Rear` spots to the thinnest post, `ReinforceDelay` after each loss, from a per-step `Pools` reserve. Survivors of a lost step retire out of sight. Attack waves at the hold steps come from `WarServer`. |
| Spawning out of sight | `pickSpot`, `seenByPlayer`, `SpawnClear` | A new enemy appears at least 40 studs from HOUND and where no player can see, when it can. |
| Perception, memory, cover, suppression, fight cycle, pathing | `Modules.Soldier`, `Modules.CoverMap` | Everything in docs/ALLIED-AI-PROMPT.md section 2. Both sides already peek, suppress a last-seen position, flank after `Brain.Flank` seconds, fall back under `Brain.Retreat` health and get pinned by rounds passing their head (`Snap`). Enemies do not heal (`Heal` is Ally only). |
| Mounted guns | `EnemyMG_RoadWest`, `EnemyMG_RoadEast` (parts in both places), `Soldier:Gunner`, `Modules.Emplacements` | Two MGs in crossfire up the road at the defenders' line. Support and Rifleman soldiers man a free gun within 45 studs of their post, track targets inside the arc, and dismount for a close foe outside it. |
| Tanks | `Modules.Tank` | Spawn at the plaza and yards, main gun barrages and coax, killed by a satchel on the back deck. |
| Damage | `MobReactions.Hit` (player guns on enemies), `Soldier:Hurt`, `WarDamage` | Enemies are tagged `Enemy` with `MobType = "Lamplighter"`. Kills count through `EnemyHit` to Points and GlowDrops. |
| Voice | `RadioVoice` (the commander's TTS through a radio), `Shared.VoiceManifest` (empty) | **Lamplighters say nothing.** |
| Grenades | nothing | **No grenade, stun or flash system exists in either place.** Four stripped raw grenade and flare models wait in the lobby's `ServerStorage.ArtStaging._Inbox` (menu pass, 2 Nov). |
| Skill levels | nothing | Every Lamplighter has the same stats. There is no Recruit, Regular, Veteran or Elite. |

Keep the light-body architecture and the one Heartbeat mover. Everything below runs inside the
think loop (`Brain.Think`, staggered) with no per-frame work per soldier.

## 4. The behaviours to deliver

Each item says what the enemy does, what the player feels, and where it goes. The code location is
the integration point; do not add a parallel system beside it.

### 4.1 Perception and alertness

- **Alert states per soldier: Idle, Suspicious, Alert, Engaged.** Add `self.Alert`. Idle holds the
  post facing `From` and looks round on the long peek gap. Suspicious (heard gunfire within
  `Brain.Hear`, a teammate within 30 studs hit, a shared sighting without a line) turns toward the
  sound, kneels and halves the look interval. Alert (a foe in the side's shared book within 60
  studs) takes Engage cover facing it. Engaged is the existing `Engaged` flag. States only rise on
  evidence and decay back over `Brain.Memory`. Never let the book put a soldier straight to
  Engaged on a sighting it did not make itself.
- **Hearing beyond gunfire.** `Soldier.Noise` is only fired by rifles and emplacements today. Fire
  it from `ExplosivesServer` (a drum), `Modules.Tank` (a shell landing), `Emplacements`
  (artillery), and from a player sprinting within 18 studs of a Lamplighter who cannot see them
  (a footstep noise with a bigger jitter, every 1.5 s).
- **Casualty awareness.** When a Lamplighter falls, teammates within 30 studs with a line to the
  body add the shooter's last known position (`HurtFrom` of the fallen) to their own `Known`,
  go Suspicious or Alert, and say a casualty line (4.8).
- **Certainty decay.** A `Known` record's position gets a growing jitter the longer it has not
  been seen (up to 10 studs at `Brain.Memory`), so a searcher looks near, not at, where the player
  was. Suppressive fire at a stale record stops after `Brain.SuppressFire` (exists); make it also
  stop when the record is older than 4 s.

### 4.2 Defence

- **Posts become lines.** `EnemyDefend` gets each step's posts in groups (the `Group` attribute the
  spots already carry for the story's MedSpots; add it to the war spots). A line holds while at
  least half its posts have a live defender. When it falls below that, or its mean Suppression is
  over 0.7 for 4 s, the line's survivors get a Retire order to the next group's posts (not off the
  map), say "Fall back", and the next line's reinforcements come in there. `WarServer` passes the
  group order it already uses for `_Rear`.
- **Elevated and window positions.** `CoverMap.Survey` keeps the floor height per spot. Add to
  `ChooseCover` scoring, for Defend orders only, a bonus for spots 3 or more studs above the
  threat's floor and for spots whose covered direction is a wall with a clear line over or beside
  it (the TOWN lookout, the depot's upper floor, windows on the plaza). Marksmen weight it
  double. Nothing here reads tags; designers may add an optional `Overwatch` attribute to a spot
  part for a further bonus, and the survey must work without it.
- **No predictable spot.** A defender that has fired from the same spot for 20 s or three peeks
  without a kill moves to another claimed-free spot within its post radius. Keep `BadUntil`.

### 4.3 Attack and pressure

- **Pressure, not a charge.** For a squad of attackers (one `EnemyAttack` call), assign roles at
  the call: one Suppressor (Support if present, else a Rifleman) who takes Engage cover with a
  line and fires long bursts at any visible HOUND member, two Assault who bound under it, one
  Flanker (4.4), and the rest Riflemen who advance only while the Suppressor is firing
  (`Overwatched` extended to require a teammate actually Exposed and firing, not just in cover).
  The Heavy keeps `Rush`.
- **Exposed targets first.** In `PickTarget`, for the Enemy side, add weight for a foe in the open
  (no claimed cover, Phase Open or Moving), a foe who is reloading (attribute `Reloading` on
  players is set by `GunServer`; bots have `self.Reloading`), a foe Exposed over cover, and a foe
  on a mounted gun. Keep distance and visibility.
- **Stop when it is a wall of fire.** An attacking squad whose mean Suppression passes 0.6, or
  that loses two members in 10 s, holds its current cover line and suppresses until the mean falls
  under 0.3, then resumes. The Leader says "Hold".
- **Fight HOUND, not only the player.** The player gets no bonus in `PickTarget` for being a
  player. A Lamplighter engages the nearest, most exposed foe. Test 8 checks this.

### 4.4 Flanking

- **One flanker per squad, by route.** The Flanker picks the side of the main threat with more
  surveyed cover (count `CoverMap.Near` spots in a 20-stud circle either side), paths to a spot
  that has a line on the threat's cover from behind or beside it (`SpotFires` from the candidate to
  the threat's claimed spot, and `CoverHolds` from the threat's position false), and goes cover to
  cover. The path is `PathfindingService` with doors as walls; no teleport, no spawn behind the
  player.
- **Abandon when hot.** The Flanker drops the flank and takes Engage cover if its Suppression
  passes `Pin`, if it takes a hit in the open, or if the route needs more than 25 s. On its death
  the squad's next Assault becomes Flanker on the next think (role reassignment, 4.7).
- **Two directions.** When two flankers are alive in a step (two squads), the second takes the
  other side. The Suppressor says "They're pinned, go round" when a flank starts; the Flanker
  says "Moving round" to its squad only (4.8).

### 4.5 Grenades (a new, small subsystem)

Nothing exists, and this is the one piece of new machinery this prompt asks for.

- **The grenade.** A server module `Modules.Grenade`: `Grenade.Throw(from, target, by)` makes an
  unanchored ball with a `BodyVelocity`-free ballistic start (set `AssemblyLinearVelocity` for a
  lob that lands at `target` in about 1.8 s, solved from the flat distance and gravity), a 3.5 s
  fuse from the throw, and a blast through `WarDamage` with `Kind = "Blast"`: 120 to a player at
  the centre falling to 20 at 14 studs, 110 to soldiers, drums within 8 studs chain through
  `ExplosivesServer`. Reuse `FxPool` and the `World/Explosion` sound and smoke from the drums for
  the blast; no new effects. The model is the stripped grenade from the lobby's
  `ArtStaging._Inbox`; the owner moves one into the campaign's `ServerStorage.WarProps.Grenade`.
  Until it is there, use a 0.8-stud dark sphere and say so.
- **Who throws.** A Grenadier role is not a sixth slot; it is a flag on a Rifleman (`Grenades = 2`
  in `GameConfig.War.Soldiers.Lamplighter`, 0 for the Heavy, 1 for Recruits). Each throw spends one.
- **When to throw.** Only when all hold: the target has been behind the same claimed cover for
  more than 8 s (bots) or has not moved more than 3 studs in 8 s (players, from `Known` history),
  it is 12 to 35 studs away, the lob's arc is clear (three rays along the parabola with
  `self.Params`), no soldier or player of the thrower's side is within 10 studs of the landing
  point, the thrower is Hidden with a half-cover entry (it stands to throw), and the squad has not
  thrown in the last 12 s. A second reason: two or more HOUND members within 6 studs of one spot.
- **The throw.** Stance Stand, a 0.9 s wind-up during which the thrower is Exposed and can be
  shot, the lob, back down. `SoldierView` plays the throw on the right arm using the aim pose's
  joint approach (`AimPitch` already drives the waist; add attribute `Throwing` for 0.9 s).
- **Fairness.** Fire `Soldier.Danger` at the throw so allies and other Lamplighters clear the
  zone, and a HOUND bot within 25 studs who sees the grenade says "Grenade!" (allied voice). Fire
  `Remotes.ShotFx`-style event `Remotes.GrenadeFx` so clients draw a short trail and hear the
  pin. The player gets the same warning HOUND does: the shout and the sight of it. No HUD marker
  (owner: no overlay text; a PNG marker may come later).
- **Stun and flash.** Not supported by the game and not asked for by the owner's UI rules (a
  flash needs a full-screen effect; a stun needs a player-state the health system lacks). Do not
  build them. Say so in the handoff.

### 4.6 Suppression, survival and skill

- Keep the existing model. Add for both sides: a round striking the cover part within 2 studs of
  a Hidden soldier's head adds `Suppress.Miss` (hook in `Soldier:Shoot`'s hit result and in
  `GunServer` for player rounds: a hit within that distance of a soldier's claimed spot).
- **Blind fire** over half cover: a Lamplighter at Suppression between `Pin` and 0.9 with a
  visible or recent target may fire a short burst from Crouch with the muzzle raised (`Burst` with
  spread times 3, no `Sees` needed, `FireLine` from the muzzle point still required). It costs
  ammunition and achieves suppression of the target. Elite and Veteran only.
- **Skill profiles.** Add `GameConfig.War.Skills = { Recruit, Regular, Veteran, Elite }`, each a
  table of multipliers on React, Spread, Hop, Flank, PeekGap, grenade judgement (the minimum
  stillness time), the Suppression level at which the soldier stops advancing, and whether it
  panics (a Recruit at Suppression over 0.8 has a 30 % chance per think to run to Retreat cover
  without being hurt). Never a health or damage multiplier. A soldier's skill is a kind field
  (`Skill = "Regular"`) overridden by the post's `Skill` attribute and by the step: `WarServer`
  passes a mix per step (Road: Recruit and Regular; Depot and Plaza: Regular; Yards and LZ:
  Veteran with one Elite per squad). Show the skill in the rig's lamp colour (`Looks`), not in UI.
- **Retreat with discipline.** Under `Brain.Retreat` health a Lamplighter moves to Retreat cover
  toward the nearest two teammates, not away alone, and says "Need support". Veterans and Elites
  keep fighting from there; Recruits and Regulars stay down until a teammate is within 10 studs or
  the line retires.

### 4.7 Squad roles and reassignment

- Roles for a Lamplighter squad are Suppressor, Assault, Flanker, Defender, Marksman and
  Grenadier flag, mapped onto the existing `ROLES` (Suppressor is Support, Defender is a Rifleman
  on a Defend order). Store the squad as `s.Squad` (the `EnemyAttack` call or the post group).
- On a death, the squad's Leader (or the eldest member) re-picks on its next think: a dead
  Suppressor's role goes to the Rifleman with the most ammunition; a dead Flanker's to an Assault;
  a dead Leader's to the highest-health Rifleman. Attribute `Role` changes and `SoldierView` picks
  up the gun swap only where the rig allows (an M60 on a Rifleman is fine; a Sniper is not: keep
  the Marksman's gun with the Marksman).

### 4.8 Voice

Build on the shared bot voice path from docs/ALLIED-AI-PROMPT.md 3.5 (`Remotes.SoldierSay`,
positional TTS per soldier, clips from `VoiceManifest.Squad` when recorded). Enemy lines go in
`GameConfig.War.Voice.Enemy` with the same key shape: Contact, ContactSide, Pinned, Suppress ("Keep
them down"), Flank ("Going round"), FlankWarn ("They're on our side"), Grenade ("Grenade out"),
Incoming ("Grenade, move"), ManDown, FallBack, Hold, Push, Search ("Lost them, check the walls"),
NeedSupport, Reloading. Write them as original militia radio, short. Rules: one speaker per squad,
a 1.5 s squad gap, a priority order where Incoming, ManDown and FallBack cut in, and lines carry
`Voice.Hear` studs so the player hears a flank being called only when close enough to act on it.
Never overlap `RadioVoice`'s commander.

### 4.9 Search and hunt

When a squad's shared book has no visible foe for `Brain.Memory` seconds and the step is not won:

1. Firing at stale records stops (4.1).
2. The Leader says Search once.
3. Two members (Assault, then Riflemen) take cover-to-cover Search moves to spots with a line on
   each stale record's jittered position (the shared Search reason), peek, and clear it.
4. The rest take Defend cover on the likely routes: the surveyed spots between the squad and the
   step goal, facing the stale positions.
5. If 25 s pass with nothing, the squad returns to its posts or its attack lane.

A searcher who sees the player goes Engaged and the squad gets a fresh sighting through
`Soldier.Spot`. Searchers never path to the player's live position.

### 4.10 Danger sensing

The shared `Soldier.Danger(pos, radius, inSeconds, side)` handles grenades, shells, barrages,
satchels and drums for both sides. For Lamplighters add: a drum within 10 studs of their claimed
spot under player fire (`ExplosivesServer` knows it is taking damage) makes the spot bad and the
soldier moves; a Lamplighter never chooses cover within 10 studs of a live drum when any foe is
known.

## 5. Architecture rules

- Everything stays in `Modules.Soldier`, `Modules.Battle`, `Modules.CoverMap`, `SoldierView`,
  `GameConfig.War`, plus the new `Modules.Grenade`. Split `Soldier` into sibling modules it
  requires if it passes about 2,200 lines. No new framework, no behaviour-tree library.
- Numbers live in `GameConfig.War.Battle`, `.Soldiers`, `.Skills` and `.Voice`. No literals in the
  brain.
- Ray budget per think: `LookRays` plus 4, plus 3 for a grenade arc check at most once per 4 s.
  Player checks at most twice a second per soldier. The grenade is the only physics object this
  pass adds, at most 3 live at once.
- Enemy-only behaviour is gated on `self.Side == "Enemy"` or the order; shared behaviour is not.
- Server-authoritative. Clients draw and play only.
- No contradictory flapping: every reason that changes `Phase` or cover sets a `NextChoose`
  cooldown of at least 0.5 s, and a move cancelled for a new one logs the reason once in
  Studio-only debug (workspace attribute `WarDebug`).
- Owner rules from CLAUDE.md: no damage numbers, no script-built UI, black lamp oil, no face gore,
  no live DataStore writes from tests, plain full sentences in the handoff.

## 6. Tests you must run and make pass

Write each as a function in a `_DevTools` module the owner runs from the Command Bar in Play, with
a pass line in Output. Fix failures; a known issue is only acceptable when it is a map ask.

1. **Suppressed behind a wall.** Player holds full cover; four Lamplighters have a line. Pass: at
   least one fires suppressive bursts at the wall, none advances into the open while the player
   is Exposed firing back, Suppression on the player's nearest bot rises.
2. **Flushed out.** Player stays still behind half cover 20 studs out for 10 s. Pass: a Grenadier
   stands, throws inside 2 s, the lob lands within 4 studs, no Lamplighter is inside 10 studs of
   the landing point, a HOUND bot in sight shouts the warning, no second throw inside 12 s.
3. **Flank.** Player and two bots hold a line. Pass: one Lamplighter paths round by a route that
   never crosses the player's line of sight for more than 2 s, reaches a spot with a line on the
   player's cover, and the Suppressor fired while it moved.
4. **Suppressor killed.** Pass: within one think another member takes the Suppressor role and
   fires long bursts; the Assault pair resumes bounding.
5. **Lost contact.** Player breaks line of sight for 12 s and moves 20 studs. Pass: firing stops
   inside 4 s, two searchers move to spots looking at the old position, not the new one, the rest
   face the routes, and the search ends after 25 s with nothing found.
6. **Defence under advance.** HOUND attacks the depot. Pass: defenders hold elevated and window
   spots where they exist, the line retires to the next group when under half strength, and
   reinforcements enter at that group.
7. **Overwhelmed.** Kill eight of twelve in 15 s. Pass: survivors retire toward teammates and the
   next line, say "Fall back" once, no one charges.
8. **HOUND as a target.** Player stands back; six bots engage. Pass: Lamplighters split fire by
   exposure and distance; the player draws no more fire than an equally exposed bot.
9. **Explosions.** A tank barrage lands on a defender group. Pass: all inside the radius move or go
   prone before impact; a drum under fire empties its 10-stud circle.
10. **Roles.** One `EnemyAttack` squad of six. Pass: Output shows exactly one Suppressor, one
    Flanker, two Assault, Riflemen the rest, and the roles change on deaths.
11. **Map use.** Run the valley with `WarStartStep`. Pass: cover in TOWN includes the tower and
    upper floors, FARM's MeshProxy boxes count, no "Soldier ...: err", no stuck soldier over 8 s,
    server heartbeat under 3 ms with 24 soldiers and 3 grenades live.
12. **Skill.** Spawn a Recruit squad and an Elite squad against the same bots. Pass: Recruits
    react slower and panic at least once in a minute; Elites flank sooner, blind-fire when pinned,
    and never panic. Health and damage are identical.

Record results at the top of docs/HORROR-SHOOTER-HANDOFF.md with the date, what ran, and what the
owner still has to test in Play.

## 7. What to say back to the owner

Plain, full sentences. Which files changed, what the owner does in Studio (pull, `rojo serve
campaign.project.json`, move the grenade model into `WarProps`, run the test module), and that
nothing was play-tested from the cloud. List map asks separately: elevated spots per zone, window
sills the survey can see over, and post `Group` attributes on the war spots.
