# Horror Shooter — Core Loop, Plan and Checklist (v2)

Working title: **Last Light** (rename later; title and icon get tested in the ad).
Co-op PvE horror shooter for Roblox, 1–4 players, phone and PC.
v1 written 2026-10-28. **v2 the same day:** the owner rejected "monsters weak in light" as the core (a gimmick no proven hit uses) and rejected auto-aim on PC. The loop is now taken from round-based co-op zombie survival, and PC and mobile get separate aiming and controls.

---

## 1. Where the loop comes from

**Main source: round-based co-op zombie survival** (the Call of Duty Zombies loop, plus Left 4 Dead for co-op).
It's the most proven co-op horror shooter loop there is. It has run for 15+ years across Call of Duty games, and on Roblox it's carried hits like Zombie Uprising and Project Lazarus. We take the **loop**, not any game's maps, characters, names or items.

Why this loop and not a survivors-style auto-shooter:
- **You aim and shoot for real.** Skill matters, headshots feel good, and better players go further.
- **Instant fun.** You hold a gun and zombies are coming within seconds. There are no menus or tutorials first.
- **Every match has its own economy.** Kills earn points, and you spend them right away on doors, guns and upgrades. You're always making a small choice.
- **It never ends, it just gets harder.** "How far did you get?" is the brag and the reason to try again.
- **Built-in RNG moment.** The random weapon crate gives the same thrill as gacha games, during play.
- **Co-op is natural.** Reviving, sharing a choke point, and one person opening the next area while others hold.

| Proven hit | What we borrow |
|---|---|
| **CoD Zombies** | Rounds, points per hit/kill, buying doors to open the map, wall guns, random weapon crate, perks, weapon upgrade machine, round counter as score |
| **Left 4 Dead** | Downed + revive, special enemies that punish players who split up |
| **Deep Rock Galactic / Risk of Rain 2** | Meta progression between matches that never makes the core shooting irrelevant |
| **Roblox RNG games** (Sol's RNG, Anime Dice) | Gun skins/rarity collection outside matches as the thing to buy and show off |

**What's ours:** the setting (Pinecrest Camp at night), our own monsters and items, and camp-themed perks and machines. The loop stays the proven one. We don't invent a gimmick.

---

## 2. The core loop

### Inside a match (the part that has to be fun in 10 seconds)
1. **Spawn (0:00).** 1–4 players in the camp's starting area (around the campfire) with a starter pistol. Round 1 monsters are already walking out of the trees.
2. **Shoot → points.** Every hit gives a few points and a kill gives more. Headshots give a bonus. Points show as small numbers flying up.
3. **Spend points (the decisions):**
   - **Barricades:** board up windows and fences between rounds for points. Monsters tear them down.
   - **Doors/gates:** open the next part of the camp (cabins → mess hall → lake dock → floodlight tower). More space, more guns, more danger.
   - **Wall guns:** fixed guns on walls at a set price, always the same.
   - **Mystery crate:** a random gun for a high price. It sometimes moves to another spot in the camp.
   - **Perks:** 4 camp-themed buffs (more health, faster reload, faster revive, faster fire). You lose them when you go down.
   - **Upgrade bench:** in the last area. Spend a lot to upgrade the gun you're holding (damage, mag, a special effect).
4. **Rounds get harder.** More monsters, faster monsters, tougher monsters. Every 5th round is a special round (a swarm or a pack of fast runners) with a reward drop.
5. **Specials** (from round 8 or so): a **grabber** that pins one player until a teammate shoots it, and a **brute** that charges and breaks barricades. These punish players who wander off alone.
6. **Downed → revive.** Teammates revive you within 30s or you're out until the next round. In solo you get 1 self-revive per match.
7. **Game over.** Everyone down. You see the round reached, kills and headshots, and get Cash based on the round reached. **Play Again** is one tap.

### Horror layer (v3, added 2026-10-28 — v2 had turned arcade)
All taken from proven hits, layered on the same loop:
1. **Power is out at the start** (CoD Zombies). The camp is near-black, with only flashlights and the campfire. Reach the generator to turn on lights, perks and the upgrade bench.
2. **Director pacing** (Left 4 Dead). Tracks team stress and times the pushes: quiet stretches with noises in the trees, then hard hits.
3. **The stalker** (Left 4 Dead's Witch). Roams the camp and can't be killed early, only driven off. Disturb it and it hunts you.
4. **Quiet UI.** No floating point numbers. Points tick up quietly in a corner, and prices show only when you're right next to something.
5. **Sound tells.** Every monster type has its own sound before you see it.
6. **Dread round starts.** Fog thickens, the radio crackles and the lights flicker before each round, with no loud sting.

### Between matches (the reason to come back)
- **Cash** from matches buys **gun skins** and **starting loadout** options (start with a different pistol or a knife). These don't change balance much, so match skill still matters most.
- **Weapon mastery:** kills with a gun raise its level and unlock skins and camo for that gun. This is the long-term grind players can see.
- **Daily challenge** (e.g. "reach round 10 with only wall guns") for bonus Cash.
- **Best-round leaderboard** per server size (solo, duo, squad).
- **Later maps:** gas station, hospital, ski lodge. Same loop, new layouts and a new special enemy each.

### Monetization (test with only the first two)
1. Gun skin crates (Robux), with rarity colours.
2. A revive token, usable once per match.
3. Later: a VIP server and a "starting points" pass (small, never pay-to-win).

---

## 3. PC and mobile: two real versions, one game

This isn't a scaled-down mobile UI. Each platform gets controls, aiming and a HUD made for it, and the game picks the right one automatically.

### Detecting the platform
- Use `UserInputService.PreferredInput` (Touch / KeyboardAndMouse / Gamepad) as the main signal, and listen for it to change.
- Fall back to `TouchEnabled`, `KeyboardEnabled`, `GamepadEnabled` and `GetLastInputType()` if needed.
- **Switch live.** A laptop with a touchscreen that starts using the mouse switches to the PC layout immediately, and back again if the player touches the screen.
- Store the current mode on the player (attribute) so the server knows which aim assist rules apply and analytics can split numbers by platform.

### PC (keyboard and mouse): no auto-aim
- WASD, mouse aim, right-click to aim down sights, left-click to fire, R reload, E interact, Shift sprint, number keys or scroll to swap guns.
- **No aim assist at all.** Skill decides. Headshots matter most here.
- Crosshair spread, recoil you can control, and hit markers.
- HUD in the corners, with smaller text, because the screen is bigger and closer.

### Mobile (touch): aim assist built for thumbs
- Joystick left, drag-to-look on the right side. Big **fire** button, **aim** button, reload, interact (appears only when near something to buy), swap gun.
- **Aim assist (not full auto-aim):**
  - **Slowdown:** the camera turns slower when the crosshair is over a monster, so it's easy to stay on target.
  - **Gentle magnetism:** when you aim down sights, the crosshair snaps gently toward the nearest monster's chest if one is close to the crosshair.
  - **Optional auto-fire** (setting, on by default): fires when the crosshair is on a monster, so you only need to aim.
- Slightly more forgiving headshot zones are allowed, but damage stays the same as PC.
- HUD: bigger buttons where thumbs reach, fewer things on screen.

### Gamepad
Moderate aim assist like console shooters (slowdown plus mild magnetism, no auto-fire). The layout is like the PC HUD with button prompts.

### Fairness
It's PvE, so players are never shooting at each other, and assist differences don't make anyone lose to someone else. Leaderboards are split by platform anyway, to be safe.

---

## 4. Style (decided 2026-10-28)

### Game style: "stylized realistic"
Not blocky and not photoreal. Real Roblox materials (wood, grass, concrete) on smooth, rounded shapes with clean silhouettes, like a polished mobile game. Looks good on a cheap phone, reads in an icon, quick to build.

### Owner direction (2026-10-28): one building under siege
The match happens **in a building** that monsters try to breach (windows, doors, weak walls). **The building gets ripped apart over time** and players repair it. **Zombies are only the test mob**; the game will have several mob types. Full spec: [HORROR-SHOOTER-FEEL.md](HORROR-SHOOTER-FEEL.md). The camp layout below becomes the **camp lodge building** and its rooms, with the forest outside as where mobs come from.

### Map: Pinecrest Camp, an abandoned summer camp in a pine forest

> **Under review (29 Oct):** the owner asked "Backrooms or a haunted mall?". The recommendation is a **haunted mall** as the main map with the **Backrooms as a secret level**, or a thumbnail ad test of both first. The full comparison and the mall layout are in [HORROR-SHOOTER-HANDOFF.md](HORROR-SHOOTER-HANDOFF.md) section 3. Rewrite this section once the owner picks.
- **Why:** a camp works all year, everyone knows it, and its areas split naturally into buyable sections.
- **Layout** (built for the door-buying loop): start at the **campfire clearing** with 2 cabins → buy a gate into the **cabin row** → the **mess hall** (perks, mystery crate spot) → the **lake dock** → the **floodlight tower** (upgrade bench). Each area has windows/fences to barricade, a choke point, and one or two wall guns. The tree line around everything is where monsters come from. No clutter.
- **Night lighting:** blue moonlight (dark, never black), warm amber campfire and porch lights, fog toward the trees, a flashlight on each player for atmosphere. Players can always read the ground near them.

### Palette
| Use | Colour |
|---|---|
| Night ambient | Deep navy / teal |
| Light, points, UI accent | Warm amber |
| Normal monster eyes | Red |
| Special monsters | Purple |
| Teammates | Cyan outline, visible through walls |

### UI style: flat dark, amber accent
- Dark, slightly see-through panels, squared corners with a slight rounding, a thin amber edge on what matters. One bold font, no cartoon bevels.
- **HUD:** round number big in a corner (the main score), points total, ammo, health, perks you own as small icons, teammates' health. Price prompts ("Open Gate — 750") pop up only when you're near something.
- No helper or explainer text anywhere.

### Feel
- **Camera:** first person for aiming accuracy and horror closeness (PC and mobile). Hands and gun on screen.
- **Pace:** each round starts quiet (growls in the trees, eyes in the fog), builds to a crowded fight, and ends with a short breather to barricade and buy.
- **Horror:** from sound, darkness and being swarmed, not jump scares. At most one scripted scare per match.
- **Shooting:** hit markers, headshot pop, monster flinch and stagger, punchy heavy gun sounds, shell casings, light camera kick. This has to feel great before anything else is built.
- **Sound:** half the horror. Distant growls, a heartbeat when you're low, a round-start sting. Music is APM only.
- **Monsters:** strong silhouettes with glowing eyes. Walker (basic), runner (fast), grabber and brute (specials). Creepy, not gory.

---

## 5. How we model it

| Asset | Route | Notes |
|---|---|---|
| Map | Hand-built layout plus **vetted Toolbox** trees, cabins and props | Strip scripts from every Toolbox model (hidden "Roblox Studio" payloads). Map quality bar applies. |
| Monsters (walker, runner, grabber, brute) | Toolbox/Creator Store rigged creatures if good ones exist, otherwise **Blender** with simple rigs | One model at a time in an orbit viewer. Glowing eyes on all. |
| Guns (pistol + 5 wall guns + 6 crate guns) | Toolbox gun meshes | First-person view models need good hands and animations. |
| Animations | Reload, fire, swap and monster attack animations | Priority list: gun animations first, since they're on screen all the time. |
| Effects | Built in Studio | Muzzle flash, hit sparks, blood-free monster hit puff, barricade breaking. |
| Icon/thumbnail | Rendered in Blender or a styled screenshot | Most polish here, since it's what the ad tests. |

Rule: Toolbox first for props, Blender only where Toolbox fails. No free-model scripts ever.

---

## 6. Timeline (target: ad-ready in ~8 working days)

| Day | Build | Done when |
|---|---|---|
| **1** | Place set up, platform detection, first-person camera, PC gun controls, server-side hit checks | Shooting a dummy on PC feels good. |
| **2** | Mobile controls + aim assist, gamepad basics, live switching | Shooting feels good on a real phone too. |
| **3** | Monsters (walker, runner) with pooled server AI, rounds, points per hit/kill | A solo match is playable to round 10. |
| **4** | Barricades, doors/gates, wall guns, mystery crate | The map opens up as you buy. |
| **5** | Perks, upgrade bench, grabber + brute specials, downed/revive, 4-player servers | A full co-op match works. |
| **6** | Game over screen, Cash, weapon mastery, skin crate, DataStore (Studio separate from live), 2 Robux products | Progress is saved and you can buy. |
| **7** | Art pass: map, monsters, gun view models, effects, sound, HUD per platform | Screenshots look like a real game. |
| **8** | Bug pass, low-end phone performance, analytics, icon + thumbnail + ad creative | Ready to spend on ads. |

Not in the test: second map, daily challenges, leaderboards, VIP server.

---

## 7. The ad test

- **Budget:** small, about 2–3 days of Sponsored ads.
- **What we read** (split by PC vs mobile):
  - Ad click-through rate (icon/title)
  - Day-1 retention: target **≥ 15%**, great if ≥ 25%
  - Average session: target **≥ 15 min**
  - Average round reached, % who press Play Again
  - Payer conversion: target **≥ 2%**
  - Likes: target **≥ 85%**
- **Decision:** targets hit → scale ads and build the Later list. Clicks fine but retention bad → fix the first rounds and the shooting feel. Clicks bad → change the icon/title first. One platform much worse than the other → fix that platform's controls before anything else.

---

## 8. Master checklist

### Foundation
- [x] New place created: placeId **79455872202749** (universe 10773529574, still named "Untitled Game")
- [ ] Studio DataStore separate from live
- [ ] All numbers in one `GameConfig` module (guns, monsters, rounds, prices, perks as data)
- [ ] Analytics events tagged with platform: join, match start, round reached, down, revive, purchase in-match, game over, play again, Robux purchase

### Platform split
- [x] Detection via `PreferredInput` with fallbacks (`ReplicatedStorage.Shared.Platform`; server stores it as the `InputMode` player attribute)
- [x] Live switching between touch, mouse/keyboard and gamepad (in code; not yet tested on a real phone or pad)
- [x] PC: no aim assist; full keyboard and mouse controls
- [ ] Mobile: slowdown + gentle magnetism + optional auto-fire; thumb layout
- [ ] Gamepad: moderate assist; button prompts
- [ ] Each HUD tested on its own device

### Shooting
- [x] All 7 punch steps from HORROR-SHOOTER-FEEL.md section 7 on every gun (same-frame kick, tracers with tails, hit flash/squash/knockback, recoil push, casings and splatter that stay, layered pitched sounds, kill freeze + body throw). Pistol, shotgun, AK and sniper, 29 Oct; placeholder sounds.
- [x] Animated reload with timed sounds (tactical and empty), plus shell-by-shell shotgun, AK charging handle and sniper bolt (29 Oct)
- [x] Mob hit reactions: highlight, stagger, limbs that break off and fall, crawling, death reaction (ragdoll, shotgun splat, sniper head pop)
- [ ] Mob sounds (idle, alert, attack, hit, limb off, death, breaching)
- [ ] Building damage over time + repairs
- [x] First-person camera, view model, recoil, spread, aim down sights (Day 1; placeholder pistol model until the art pass)
- [x] Server-checked hits; headshot multiplier
- [x] Hit markers, headshot pop, flinch/stagger, punchy sounds

### Match loop
- [ ] Rounds that scale; special round every 5th
- [ ] Points per hit/kill/headshot/barricade repair
- [ ] Barricades, buyable doors/gates, wall guns, mystery crate (moves)
- [ ] 4 perks, upgrade bench
- [ ] Walker, runner, grabber, brute
- [x] Downed + revive; 1 solo self-revive (29 Oct, pass B; per life until matches exist; teammate revive untested with 2 players)
- [ ] Game over screen with round reached; one-tap Play Again

### Horror layer
- [ ] Power out at start; generator turns on lights, perks, bench
- [ ] Director pacing (quiet stretches, timed pushes)
- [ ] Stalker: roams, can't be killed early, hunts if disturbed
- [ ] Sound tell per monster type
- [ ] Dread round start (fog, radio, flicker); quiet points UI

### Meta and money
- [ ] Cash from round reached
- [ ] Weapon mastery levels + skins
- [ ] Skin crate (Robux) and revive token

### Look and sound
- [ ] Pinecrest Camp map, readable at night, no clutter
- [ ] Flat HUD with amber accent; price prompts only when near
- [ ] Gun, monster, ambience and round sounds; APM music

### Ship
- [ ] Runs smoothly on a low-end phone with 4 players and a full round
- [ ] Icon, thumbnail, title, description
- [ ] Ad creative (2 variants)
- [ ] Owner playtest on PC and phone, then ad test, then read the numbers
