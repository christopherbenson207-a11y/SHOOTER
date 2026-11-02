# Last Light: the full plan (31 Oct 2026)

Builds on `HORROR-SHOOTER-LOOP-V2.md` (why the current game feels weak, and the research). This file is the full game: the plan I picked and why, the simulation stats, then every weapon, building, enemy, animal, house feature, how to build it, and the funnel that keeps players 30–60 minutes and gets them paying.

---

## 1. The plan I picked

**Plan P3: Night and Lull, with a director, two escapes, classes, a companion dog and chapters.**

You defend a house at night. Between waves (the lull) you raid the town to repair a radio tower (helicopter escape) or an army truck (roadblock escape) while the Beacon hunts the streets. Classes, a dog that levels with you, curses and chapters keep you coming back.

**Why this one:**
- **It wins the simulation on time played.** Average session 68 min (18 year old) and 61 min (6 year old), against 21 and 19 for the current build. More than half of the 18 year olds and 46 % of the 6 year olds pass an hour.
- **It wins on money by a long way.** About 824 and 608 Robux per 100 players, against 34 and 29 now. That's 14–24× the current build, and 1.6× the next best (the journey plan).
- **It costs about half the build time of the only plan that comes close.** The Dead Rails-style journey (P4) is 60 days for less play time and less money. P3 is 34 days.
- **It keeps everything already built.** Every system has a job: the house, the town, the Beacon, the helicopter, the gore, the hiding.

**What the simulation taught me:**
1. **The meta layer is what matters most, not the loop on its own.** Night and Lull alone (P2, 46 min) only beats the CoD acts plan (P1, 43 min) by a little. Adding the director, the second escape, classes and the dog on top takes it to 68 min and ×14 the money.
2. **The dog is worth ~280 Robux per 100 kids on its own.** It barely changes play time, but 6 year olds buy dogs. Build it.
3. **Ten enterable town buildings is the knee of the curve.** Going 6→10 adds 3 minutes and +72 Robux per 100 teens; 10→14 adds only 0.5 minute for 8 more days of work.
4. **Three enemy types at launch, not five.** Five types gives the 18 year old almost nothing (+0.1 min) and pushes the 6 year old out (−3.6 min, scared quits 12 % → 17 %). Brutes and screamers come later, on deep nights and Nightmare only.
5. **Soft horror by default.** Going from "current" to "soft" (no jump scares, a slower Beacon) changes nothing for the 18 year old and takes the 6 year old from 61 to 68 minutes, with scared quits from 12 % to under 1 %. Full horror loses 15 minutes of the kid and a third of them quit scared. Real scares go behind Nightmare mode, for those who want them.
6. **For 6 year olds, confusion is still the top reason to quit** (30 % of their sessions end that way, even in P3). Guidance by voice and glow, not text, is the most important kid feature after the dog.

---

## 2. The simulation

### How it works
`last-light/sim/sim_plans.py`: a Monte Carlo model, 20,000 sessions per plan per player, played minute by minute.
- **Per minute:** a chance to get lost (higher with less guidance, more text, a weaker reader); fear spikes (if the scare is above the player's tolerance); fun from action and switching modes; a death chance (it rises with depth and difficulty, and falls with aim and help); a quit chance (it grows with frustration and boredom).
- **Between matches:** boredom grows when runs feel the same; the chance to play again depends on meta goals, an escape, boredom and frustration.
- **Spending:** each thing for sale has an appeal per player type, scaled by how long they've played. The 6 year old has less access to Robux than the 18 year old (22 % vs 35 %) and loves pets and looks; the 18 year old likes classes, camos and a starter pack.

**Be clear about what this is.** It turns my judgement into numbers so the plans can be compared fairly and the knees (buildings, enemy types, scare) can be found. It is not a forecast of real revenue. The real numbers come from the first playtests and the analytics funnel (section 10), and the model should be re-tuned to them.

### The two players
| | 18 year old | 6 year old |
|---|---|---|
| Aim | 0.70 | 0.25 |
| Finds the way alone | 0.80 | 0.30 |
| Reads | yes | barely (0.10) |
| Takes scares | 0.90 | 0.40 |
| Bored by repeats | fast (0.80) | slowly (0.30) |
| Loves collecting, pets and looks | 0.45 | 0.90 |
| Has Robux (own or a parent's) | 35 % | 22 % |

### All six plans
| Plan | Build days | Player | Avg min | Median | ≥30 min | ≥60 min | Matches | Escaped | Payers | R$ / 100 players | Quit scared | Quit lost | Quit bored |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **P0** Current build | 0 | 18 | 20.6 | 19.7 | 26 % | 2 % | 2.2 | 89 % | 0.3 % | 34 | 0 % | 0 % | 100 % |
| | | 6 | 19.0 | 13.7 | 21 % | 2 % | 2.1 | 78 % | 0.3 % | 29 | 11 % | 45 % | 44 % |
| **P1** CoD build-your-escape acts | 14 | 18 | 43.2 | 36.6 | 54 % | 26 % | 2.3 | 76 % | 0.7 % | 57 | 0 % | 0 % | 98 % |
| | | 6 | 35.5 | 24.0 | 44 % | 18 % | 2.1 | 60 % | 0.5 % | 47 | 16 % | 49 % | 34 % |
| **P2** Night and Lull, one chapter | 12 | 18 | 45.6 | 36.6 | 54 % | 28 % | 2.2 | 75 % | 0.8 % | 60 | 0 % | 0 % | 97 % |
| | | 6 | 37.2 | 25.6 | 44 % | 19 % | 2.1 | 58 % | 0.5 % | 42 | 16 % | 41 % | 41 % |
| **P3 Night and Lull + director, escapes, classes, dog, chapters** | 34 | 18 | **68.2** | **67.2** | 73 % | **53 %** | 3.3 | 83 % | **6.1 %** | **824** | 0 % | 5 % | 77 % |
| | | 6 | **61.0** | 52.6 | 66 % | **46 %** | 3.2 | 73 % | **4.4 %** | **608** | 12 % | 30 % | 42 % |
| **P4** Dead Rails-style truck journey | 60 | 18 | 60.4 | 54.7 | 77 % | 47 % | 2.3 | 66 % | 2.6 % | 506 | 0 % | 0 % | 92 % |
| | | 6 | 54.4 | 42.7 | 68 % | 39 % | 2.4 | 51 % | 2.2 % | 417 | 11 % | 30 % | 49 % |
| **P5** Endless CoD rounds | 10 | 18 | 49.9 | 38.6 | 71 % | 36 % | 2.1 | 67 % | 1.6 % | 129 | 0 % | 1 % | 97 % |
| | | 6 | 46.6 | 33.0 | 63 % | 31 % | 2.2 | 54 % | 0.8 % | 72 | 5 % | 36 % | 55 % |

### Sweeps on P3 (the four questions)
| Question | Option | 18 yo min | 18 yo ≥60 | 18 yo R$/100 | 6 yo min | 6 yo ≥60 | 6 yo R$/100 | 6 yo scared |
|---|---|---|---|---|---|---|---|---|
| **Town buildings** | 6 (now, +0 days) | 65.2 | 51 % | 752 | 60.1 | 45 % | 593 | 11 % |
| | 8 (+4 days) | 66.8 | 52 % | 790 | 60.6 | 46 % | 600 | 11 % |
| | **10 (+8 days) ← pick** | 68.2 | 53 % | 824 | 61.0 | 46 % | 608 | 12 % |
| | 14 (+16 days) | 68.7 | 54 % | 837 | 61.2 | 46 % | 607 | 12 % |
| **Enemy types** | 1: zombie only | 66.7 | 52 % | 765 | 63.4 | 48 % | 649 | 7 % |
| | **3: walker, runner, dog ← pick** | 68.2 | 53 % | 824 | 61.0 | 46 % | 608 | 12 % |
| | 5: + brute, screamer | 68.3 | 53 % | 839 | 57.4 | 42 % | 538 | 17 % |
| **Companion dog** | none | 68.5 | 54 % | 686 | 60.8 | 46 % | 326 | 12 % |
| | **dog (sniffs parts, buyable breeds) ← pick** | 68.2 | 53 % | 824 | 61.0 | 46 % | 608 | 12 % |
| **Scare level** | full horror | 68.2 | 53 % | 824 | 46.2 | 30 % | 402 | 36 % |
| | as planned | 68.2 | 53 % | 824 | 61.0 | 46 % | 608 | 12 % |
| | **soft by default ← pick** (scares in Nightmare) | 68.2 | 53 % | 825 | 67.6 | 53 % | 697 | 1 % |

---

## 3. A simulated playthrough of the picked plan

### The 18 year old (PC, plays solo, then with a friend)
- **0:00** Menu: the Beacon walks the road at the camera. Picks the **Rifleman** class and gets the AK. The **Shepherd pup** (the free starter dog) sits at their feet.
- **0:30** Short crash cutscene; they crawl into the house. The radio voice: "Get the tower running. We'll send another bird."
- **1:00 Night 1.** Walkers at the windows. Headshots, dents and limbs coming off. 640 points. Buys boards (Engineer would be faster). Finds a random floor gun upstairs: a **double-barrel**.
- **3:00 Lull 1 (2:00 countdown).** The doors unbar. The dog sniffs and points toward the **Hardware Store**. Gunfire outside makes the Beacon turn, so they switch to the knife on a stray walker. Buys the store door (750) and gets the **Nail Gun** off the wall plus the **Cable** part. Back with 15 s left.
- **5:30 Night 2** adds runners. **Lull 2:** Police Station (1,500 points), with the M4 on the wall and the **Battery**. The Beacon's lamp sweeps them; they hide in a dumpster and the dog lies flat.
- **12:00 Night 3** adds **zombie dogs** in a pack of 4 from the woods. The night event is fog. They go down once and their friend joins by invite (drop-in co-op).
- **18:00** Antenna (Apartments roof) and Fuel (Fuel Stop) are found. Fuel also fits the **army truck**: they choose the tower, the helicopter.
- **24:00 The last night.** The Beacon comes for the house. They break 2 lenses with the AK and the house loses half its roof. The ladder GRAB, and they escape.
- **25:00** +Scrip, Rifleman level 3 (unlocks a suppressor), dog level 2. Unlocks Nightmare. A **Starter Pack** offer (99 R$) shows once: they buy it (skin + Scrip + collar).
- **26:00 Match 2:** they want the other ending, so the **truck escape**. The director moves the parts, blocks Main Street with a wreck, and the event is a power cut. **50:00** escaped by truck: the "Both Ways Out" badge.
- **52:00 Match 3**, Nightmare with the "No Guide" curse, ×1.5 Scrip. Dies on night 5 to a brute. **68:00** logs off with a daily quest half done (a reason to come back tomorrow).

### The 6 year old (phone, plays with an older sibling)
- **0:00** Doesn't read the menu; taps the big glowing PLAY. Picks a class by tapping the uniform that looks coolest (the attire lineup), which is the Medic.
- **0:30** Loves the puppy. Taps it: it barks and wags.
- **1:00 Night 1.** Aim help plus auto-fire on touch means kills happen. The amber glow shows the window to fix. Soft mode means no screams in the face.
- **3:00 Lull 1.** Can't read "LULL 2:00", but the **radio voice says "Go! Find the parts, the dog knows where!"** and the dog runs ahead with a glowing trail. Follows the dog. Finds the Cable.
- **6:00** Gets lost behind the shop; the **dog barks and runs back to the house** when the timer is low (the dog is the guide home). Makes it in.
- **10:00** Spooked by the Beacon's lamp but not scared away (soft mode: its lamp is slower, and the hum warns them first). Hides in a dumpster: the best moment of the session for them.
- **15:00** Downed 3 times; their sibling revives them each time. Medic heals quickly.
- **24:00** Escape. Sees a friend's **golden retriever** in the lobby. Asks a parent for **149 R$** for the retriever: the purchase happens here, if it's going to.
- **25:00–60:00** Two more matches, mostly for the dog: it levels up and earns a new trick (sit and spin). The session ends when a parent says so, not when they're bored.

---

## 4. Weapons: the full list (free scope)

**Every gun has a Noise rating.** Loud guns turn the Beacon toward you in the lull; quiet ones let you sneak. That makes the gun choice a real decision and ties the guns to the Beacon.

**Rarity colours** (on the wall frame and the crate): grey Common, green Uncommon, blue Rare, purple Epic, gold Legendary, amber **Relic** (chapter wonder weapons).

| Type | Gun | Rarity | Noise | Where you get it | Notes |
|---|---|---|---|---|---|
| Sidearm | **Service Pistol** | Common | Med | Everyone starts with it | Built |
| Sidearm | Revolver | Uncommon | High | Neighbour House wall | 6 shots, big hits |
| Sidearm | Machine Pistol | Rare | Med | Crate, Police Station locker | Full auto |
| Sidearm | **Flare Pistol** | Rare | — | Fuel Stop wall | Lights an area; a flare shot away from you **pulls the Beacon's lamps to it** (a sneak tool) |
| Melee | **Knife** (quick melee, V) | — | Silent | Everyone | Quiet kills on strays |
| Melee | Baseball Bat | Common | Silent | Shop, Burnt House | Kid favourite, big shove |
| Melee | Crowbar | Uncommon | Silent | Hardware Store | Opens locked lull doors faster |
| Melee | Fire Axe | Rare | Silent | Firehouse (chapter 2) / crate | Tears limbs in one swing |
| SMG | Compact SMG | Uncommon | Med | House hall wall | Fast, easy |
| SMG | Stinger SMG | Rare | Med | Apartments wall | |
| Shotgun | **Pump Shotgun** | Uncommon | High | House kitchen wall | Built |
| Shotgun | Double-Barrel | Uncommon | High | Random floor spot | Two-shot burst |
| Shotgun | Auto Shotgun | Epic | High | Crate, upgrade | |
| Rifle | **AK** | Rare | High | Rifleman start, crate | Built |
| Rifle | M4 Carbine | Rare | High | Police Station armoury wall | |
| Rifle | Burst Rifle | Epic | High | Crate | |
| Rifle | Marksman DMR | Epic | High | Apartments roof | |
| Heavy | Belt LMG | Epic | Very high | Army Checkpoint (truck route) | Holds a whole window |
| Sniper | **Bolt Sniper** | Rare | Very high | Apartments roof wall | Built; penetrates 3 |
| Quiet | **Crossbow** | Rare | Silent | Hunting cabin / Scout class start | Bolts can be picked back up; the stealth gun |
| Quiet | Suppressor (attachment) | — | −2 noise | Workbench (Scrip in match) | On pistols, SMGs and rifles |
| Special | Nail Gun | Uncommon | Low | Hardware Store wall | Weapon **and** board repair from range (the Engineer's toy) |
| Special | Flamethrower | Legendary | Med | Crate only | Clears a window; green fire |
| Special | Grenade Launcher | Legendary | Very high | Crate only | |
| Throwable | Frag Grenade | — | Very high | Police Station, ammo boxes | |
| Throwable | **Noise Maker** (wind-up radio) | — | Lure | Shop, crate | Pulls zombies **and** the Beacon to it (the CoD monkey-bomb idea, our own item) |
| Throwable | Flashbang | — | High | Police Station | Stuns zombies; the Beacon's lens flinches |
| Throwable | Molotov | — | Med | Fuel Stop | Green fire wall |
| Relic | **Lamp Breaker** (chapter 1 wonder weapon) | Relic | Med | **Built from 3 parts** found across lulls (quest) | Fires a lens shard beam that **stuns the Beacon** for 6 s; chains through zombies |

**How guns spread through a match:**
1. **Start:** Service Pistol + Knife (Rifleman: AK; Scout: Crossbow; Engineer: Nail Gun; Medic: Machine Pistol).
2. **House:** one random floor gun, plus 2 wall buys (Pump in the kitchen, Compact SMG in the hall).
3. **Town buildings:** each has 1 wall buy plus a loot table (ammo, bandages, throwables).
4. **The crate:** in a random town building each match. It moves after 4 uses.
5. **The workbench** (house): attachments and **Rework** (upgrade the held gun: damage, mag, a coloured glow).
6. **The relic:** a quest across lulls.

**Launch set** (to keep the build sane): Pistol, Knife, Bat, Crowbar, Compact SMG, Pump, Double-Barrel, AK, M4, Sniper, Crossbow, Nail Gun, Flare Pistol, Frag, Noise Maker, plus the Lamp Breaker: 16 items, with 4 already built. The rest arrive with chapters and seasons.

---

## 5. Buildings

### Chapter 1, "Hollow Creek": 10 enterable buildings (the sim's knee)

| # | Building | Status | Floors | What's inside |
|---|---|---|---|---|
| — | **The house** (base) | Built | 2 + basement | Barricades, workbench, radio, kennel, stash |
| 1 | **Fuel Stop** | Exists, needs interior | 1 + forecourt | Fuel part spot, Flare Pistol wall, Molotovs |
| 2 | **Corner Shop** | Exists, needs interior | 1 | Bandages, Noise Makers, Bat, crate spot |
| 3 | **Apartments** | Exists, needs interior | 3 + roof | Antenna part spot (roof), Stinger SMG, Sniper on the roof (sniper nest over the town) |
| 4 | **Neighbour House** | Exists | 2 | Revolver wall, story note, crate spot |
| 5 | **Burnt House** | Exists | 1 (open roof) | **No roof, so not safe from the lamps**; crate spot, rare loot |
| 6 | **Abandoned House** | Exists | 2 | Part spot, relic part spot |
| 7 | **Police Station** | New | 1 + cells | M4 armoury (1,500 pts), frags, flashbangs, Battery part spot |
| 8 | **Hardware Store** | New | 1 + yard | Nail Gun, Crowbar, boards (carry 4 back for free repairs), Cable part spot |
| 9 | **Clinic / Pharmacy** | New | 1 | Bandages ×3 buy, a "perk" fridge (fast revive), Medic tie-in |
| 10 | **Army Checkpoint** (the roadblock) | New | Outdoor + tent | **The truck escape**: the truck needs Fuel + Battery; Belt LMG wall |
| T | **The radio tower** | New structure on the hill | Climbable | The 4 part sockets light up |

**Plus 8–10 façades you can't enter** (cheap: Toolbox shells retextured): a diner, a laundromat, a church, the school, garages. They block streets so the town reads as a town, give the Beacon things to smash, and give the director streets to close.

### Later chapters (free scope, one per big update)
| Chapter | Setting | Base to defend | Way out | New hunter |
|---|---|---|---|---|
| 2 | **Blackwater Dam** | Power station | Boat down the spillway | The Diver (rises from the reservoir) |
| 3 | **St. Agnes Hospital** | Ward floor | Rooftop helipad | The Orderly (wheels down halls; you hear its trolley) |
| 4 | **Ridgeline Mall** | Food court | Freight elevator to the car park | The Mannequin (only moves while the lights are out) |
| 5 | **Fort Kessel** (army base) | Bunker | Plane from the airfield | Final chapter: the Beacon's maker |
| Secret | **The Hollow** (liminal rooms) | none | Find the door | Unlocked by collecting every radio note |

---

## 6. Enemies and animals

### Launch: 3 types (sim pick)
| Enemy | From | Look (all ages: green blood, no face gore) | Job |
|---|---|---|---|
| **Walker** | Night 1 | Built (TestZombie) | Bulk; tears boards |
| **Runner** | Night 2 | Thinner, faster animation, eyes brighter | Punishes slow reloads |
| **Zombie Dog** | Night 3, in packs of 3–5 | Gaunt hound, glowing eyes, patchy fur, **no exposed gore** | Fast and low: flanks you in the lull, jumps through broken windows. The CoD hellhound idea (proven), our own creature |

### Later (night 6+, Nightmare and chapter 2; not at launch)
- **Brute**: big, breaks a whole window at once, armoured head.
- **Screamer**: a scream that calls the Beacon's lamps to you.
- **Crawler**: legless after limb tears (already possible from the gore system); comes under barricades.
- **Riot Zombie**: police shield from the front; the Police Station's own enemy.
- **Bloater**: pops into a green cloud.

### The Beacon
It stays the star. New for this plan:
- It **hears outdoor gunfire** in the lull and turns toward it.
- It **comes for the house** on the last night.
- It can be **stunned** by the Lamp Breaker and by flashbangs to its lens.
- **Soft by default:** its lamp sweeps slower, a hum warns you first, and there are no jump scares. **Nightmare** brings back the fast sweeps and the scream.

### Animals
| Animal | Role | Why |
|---|---|---|
| **Companion dog** | Every player has one. It **sniffs out parts** (a glowing trail), **barks at zombie dogs and when the Beacon is near**, leads you home when the lull ends, and lies down when you hide. It can't die: it whimpers and hides. It levels with you and learns tricks. | The sim's biggest money lever for kids (+280 R$/100), and it's the kid's guide |
| Zombie dog | Enemy (above) | |
| **Crows** | Ambient: they **burst off rooftops when the Beacon is near** (a warning you can see) | A cheap, readable warning |
| Rats | Ambient in basements | Life |
| Deer (alive) | Ambient on the hill edge in the lull; they bolt from the Beacon | Calm moments |

**Dog breeds for sale** (looks only; every breed does the same job): Shepherd pup (free starter), Golden Retriever, Husky, Dalmatian, Black Lab, Corgi, plus a seasonal one (a Halloween hound with a pumpkin bandana). Collars, vests and bandanas as cheap extras.

### How to model the animals
- **Blender**, matching the house and Beacon pipeline (`last-light/blender`).
  - One **base dog mesh** (about 3–4k tris, low-poly realistic, rounded and bevelled) with a quadruped rig: spine ×4, neck ×2, head, jaw, tail ×3, 4 legs ×3, ears.
  - **Breeds are shape keys plus textures** on the same rig, so every animation works on every breed.
  - **Zombie dog** is the same rig with a gaunt shape key, a patchy texture and glowing eyes.
- **Animations** in Blender: idle, sit, lie, walk, trot, run, sniff (head down), bark, whimper, spin trick, leap and bite (zombie).
  - Imported as a Roblox **skinned mesh**; animations uploaded as KeyframeSequences.
- **Movement:** the dog walks with `Humanoid:MoveTo` (the same pathfinding as MobAI), with an **IK foot plant** on slopes.
- **Crows, rats, deer:** Toolbox models first (owner rule, 24 Oct). Strip the scripts, retexture, and check them in the orbit viewer.
- **Review rules:** one model at a time in the orbit viewer; nothing floating or clipping; close-up checks.

---

## 7. House features (the base you return to)

Things you improve **during** a match (Into the Dead and Survive the Apocalypse do this; you spend what you bring back from the lull):
1. **Barricades**: built. Upgrades: boards → metal sheets (Hardware Store) → a reinforced shutter.
2. **Workbench**: attachments (suppressor, extended mag, scope), **Rework** upgrades, building the Lamp Breaker.
3. **Generator**: bring Fuel back and the lights come on. The house is brighter and the zombies are easier to see; it also powers the perk fridge.
4. **Radio**: shows the part marks; plays the story messages you find.
5. **Kennel**: the dog's spot. Tap it to change the dog's look.
6. **Stash locker**: keeps one gun safe when you go down.
7. **Turret slots** (2): build a nail-gun turret from Hardware Store parts. It covers a window while you're out in the lull.
8. **Trap door** to the basement: a last-stand room.
9. **Lookout window** (attic): see the Beacon's lamps across town and plan your lull route.

The house takes visible damage over the match: the roof comes off on the last night. It's rebuilt every match (that already works).

---

## 8. How to build it (the fastest good way)

1. **Everything is placed by markers, never by hand-coded positions.** Small invisible parts tagged with CollectionService, which the director picks from each match:
   - `PartSpot`, `LootSpot`, `WallBuy`, `CrateSpot`, `StraySpawn`, `DogSpawn`, `StreetBlock`, `FacadeSmash`.
   - New buildings only need markers dropped in; there's no code to write per building.
   - Numbers live in `GameConfig.Nights`, `.Director`, `.Guns`, `.Classes` and `.Dogs`.
2. **Buildings come from a modular interior kit:** about 30 Blender pieces (wall, door wall, window wall, floor, stair, counter, shelf, locker), rounded and bevelled, with LL_* materials.
   - Each of the 4 new buildings and the 6 interiors is assembled from the kit in Studio. That's about 1 day each instead of 3.
3. **Toolbox first for props** (shelves, cars, signs, lamps): strip every script, including inside SurfaceAppearance, Decals and Lights; retexture until unrecognizable; rename. All ages: no text graffiti, blood or bodies.
4. **Blender for hero assets:** the tower, the army truck, the dogs, the Lamp Breaker, and the new gun viewmodels (or retextured Toolbox guns if they pass review).
5. **One system at a time, playtested before the next**, as the passes so far have run. Studio edits with a backup first (`ServerStorage._Backups`).

---

## 9. The funnel: 30–60 minutes and paying

| Stage | Target | What makes it happen |
|---|---|---|
| **First 10 s** | 95 % stay | PLAY is the only big button. No class screen the first time (you get the Rifleman; the class pick opens after the first match). The dog is beside you on the menu. |
| **First minute** | Shooting zombies by 0:45 | A 20 s crash cutscene, skippable. Zombies at the windows at once. |
| **First 5 minutes** | Understands the loop without reading | Radio **voice** lines, the dog's trail, amber glow. The first lull has a short route (a part is always in the shop on match 1). |
| **First match (25 min)** | 70 % reach the last night | Soft horror; aim help and auto-fire on touch; the friend invite on the first down. |
| **After the first match** | 60 % start a second | The class pick opens; "Both Ways Out" shows as the next goal; the dog levels up (with a trick). |
| **Session (30–60 min)** | Match 2 (the other escape), match 3 (curses or Nightmare) | The director makes each run different; a daily quest; class levels. |
| **Coming back (day 1 / day 7)** | D1 25 %+, D7 8 %+ | Daily quests; a login dog treat (a cosmetic every 7 days); weekly events (the night event of the week); chapter 2 teased by the radio notes. |

### What's for sale (never pay to win)
| Item | Price | When it's shown |
|---|---|---|
| **Starter Pack** (gun skin, 1,000 Scrip, dog collar) | 99 R$, once | After the first escape or the third death, once |
| **Dog breeds** | 149 R$ each (Scrip too, slowly) | In the lobby, where others' dogs show; at the kennel |
| **Classes** (Demolition, Hunter, Firefighter, Marksman) | 199 R$ or Scrip | The class pick: locked uniforms in the lineup |
| **Gun skins / camo crates** | 99 R$ | In the lobby; mastery camos are earned, crate skins are bought |
| **Revive token** | 25 R$, one per match | When downed after the halfway point of a match |
| **VIP pass** | 299 R$ | +20 % Scrip, VIP dog collar, name colour |
| **Night Pass** (season, later) | 399 R$ | Free and paid tracks of looks; from the first season |
| **Private server** | Roblox standard | |

Guns, damage and dog abilities are never sold. Classes are always earnable with Scrip.

**Analytics to add** (Roblox Funnel Events, as in `ANALYTICS-FUNNEL.md`): menu → match start → night 1 end → first lull part → night 3 → last night → escape → match 2 start → offer shown → offer bought. Plus quit reason guesses: last lull timer, confusion (stood still for over 20 s outside), death count.

---

## 10. Build order (34 working days total)

| Phase | Days | What | Playtest gate |
|---|---|---|---|
| 1 | 5 | **Night and lull cycle**, doors that bar and unbar, the countdown, voice lines (placeholder), the Notice line | Can a newcomer go out and come back with no text? |
| 2 | 5 | **Parts and tower + truck escape**; director markers and the part/loot spawner | Full match, both escapes |
| 3 | 4 | **Companion dog** (Blender base mesh, rig, 8 animations, trail, bark warnings) | Does the 6 year old follow the dog? |
| 4 | 5 | **Runner + zombie dog enemy**; the Beacon hears gunfire; the last night at the house | Night 3 difficulty on phone and PC |
| 5 | 8 | **4 new buildings + 6 interiors** from the modular kit; façades | Does the lull route feel different each match? |
| 6 | 4 | **Guns:** the launch set (Crossbow, Nail Gun, Flare Pistol, M4, Bat, Crowbar, Double-Barrel, Noise Maker), Noise ratings, wall buys, the crate move | |
| 7 | 3 | **Classes + Scrip + store** (Starter Pack, breeds, revive token) + analytics funnel | Ad test |
| — | later | Lamp Breaker relic, curses, house turrets and generator, Night Pass, chapter 2 | |

After phase 2 the game is already the new loop. Phases 3–7 are what the sim says turns 46 minutes into 60+, and 60 Robux per 100 players into 600–800.

---

## 11. Owner rules this plan keeps
- No damage numbers. No big overlay text; one small line, on the existing Notice label.
- Green blood only; no face gore; all-ages map (no blood, bodies or graffiti text).
- The Beacon never lasers; it never walks through buildings; you can't hear it indoors.
- PC has no aim assist; touch and gamepad get assist.
- Toolbox props are stripped of scripts and retextured until unrecognizable.
- Rounded, hand-built-looking models; no clutter.
- The loop is taken from proven hits (Survive the Apocalypse, 99 Nights, Left 4 Dead, CoD Zombies, Into the Dead, Killing Floor), not invented.
