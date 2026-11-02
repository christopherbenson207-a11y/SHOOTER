# Last Light: the road to 2,000 concurrent players (1 Nov 2026)

This answers one question: with what is built today, which modes do we add, and how do we let people play together, so the game can hold 2,000 players at once and keep them coming back?

Method: I read the whole build (handoff, brief, loop v2, full plan, escape spec, sim report), pulled the live Roblox zombie and shooter charts for 31 Oct / 1 Nov 2026 and the Steam Charts numbers for eleven co-op PvE shooters plus the 2026 mobile revenue rankings, listed every proven co-op PvE mode from Battlefield, Call of Duty, Left 4 Dead and the Roblox hits, mapped each onto our systems, and ran a 30-day cohort simulation of ten mode mixes (`last-light/sim/mode_sim.py`, results in `mode_results.json`). The sim's numbers are design assumptions written down; the ranking is what matters, not the decimals.

---

## 1. Where we are

**Built and working (Studio-tested, not yet live-tested):**
- Gunplay with the EgorV feel bar: Pistol, Shotgun, AK, Sniper, limb tearing, green blood, world damage, flashlight.
- **Defend**: 7 timed nights with 100 s lulls, a director that scales spawns to the team, parts and the radio tower, the helicopter escape, the Beacon hunter (streets only, lamps, grab = thrown to the yard), hiding (dumpsters, cars), the police dog, zombie dogs, runners.
- Quiet hybrid HUD (night ring, Seen eye, part icon, world glows, radio voice), CoD-style touch controls, settings, gore switch, profile saves.
- Endless and Nightmare, unlocked by escaping once.
- Menu with the Beacon walking the road.

**What stops it reaching 2k CCU as it stands:**
1. **One match per server, 1–4 players, no hub.** You cannot see other people, cannot party up, cannot join a friend mid-run, and a "4 players" server list reads as a dead game. Every game in the 2k–30k band on today's chart has a visible lobby or 8–16 player servers.
2. **One real mode.** Defend is a 23-minute set piece. The sim gives it D7 of about 3 %: people finish it twice and leave. Endless and Nightmare are the same match made harder, so they add almost nothing (X1 vs X0 below).
3. **No reason to come back tomorrow** beyond the first escape. Classes, Scrip, the dog's levels, daily quests and the store from `HORROR-SHOOTER-FULL-PLAN.md` are not built yet.

---

## 2. What the charts say (snapshot 31 Oct 2026, rblxdb zombie ranking + rowatcher)

| Game | Playing | Loop | Lesson for us |
|---|---|---|---|
| Dead Rails | 26,000 | Squad expedition: board the train, loot stops, reach the end; drop-in friends | Discrete 20–30 min runs with friends, a destination, loot that changes each run |
| BloxStrike (Zombies) | 24,400 | Competitive FPS with a zombies mode | A good shooter can carry a PvE mode |
| Survive a Million Monkeys | 14,700 | Horde-survive on one big server | Big servers feel alive |
| Survive the Apocalypse | 11,500 | Base by night, scavenge by day (our Defend source) | Our loop is on-chart |
| Zombie Rush Survival | 10,200 | Rounds, classes, respawn as a zombie, bosses | Classes and quick re-entry |
| Survive Zombie Arena | 7,000–27,000 | Hub, board a ship as a team, wave arena, credits, classes | **Hub → squad → match → hub** is the standard shape |
| Operation One | 5,800 | Military objective missions, zombies | Spec Ops style co-op works on Roblox |
| HUSH (Zombie Extraction) | 3,700 | Open quarantined town, loot, noise hunter, extract | Our Beacon town already is this map |
| Project Lazarus | 3,400 | CoD Zombies rounds, perks, revives | Pure rounds alone sit at 3k, not 20k |
| Realistic Home Defense, Last Stand, Defend Bunker | 1,700–1,900 | One-house wave defence | **Defend alone tops out around 2k** |

Shooters: RIVALS holds about 210k, Hypershot 26k, Arsenal 4k (bloxquiz shooter ranking, Aug 2026 and today). RIVALS is PvP; we are not going there.

**The lesson:** games built around one house and waves plateau at about 2k. Games that add a town you roam with other people (Dead Rails, HUSH, Survive the Apocalypse) sit 3–10× higher. We already have the town, the hunter and the helicopter. We are missing the mode that uses them with more than four people, and the hub that lets people find each other.

---

## 2b. Steam, console and mobile: the same lesson at a bigger scale (Steam Charts, 1 Nov 2026)

| Game (platform) | Playing now | 30-day avg | Shape of a match | Lesson |
|---|---|---|---|---|
| ARC Raiders | 82,000 | 70,000 | Drop into a shared map with other squads, loot, extract before the timer; a shared world that changes week to week | Extraction is the biggest co-op shooter shape of 2026 |
| Delta Force | 64,000 | 64,000 | Battlefield-style modes plus an extraction mode plus a co-op campaign, one client | One shooter, several modes sharing guns and progression |
| Helldivers 2 | 43,000 | 40,000 | 4 players drop in, do 2–3 objectives, call the extraction ship, hold the pad until it lands; a shared Galactic War everyone fights | **Objectives → call extraction → hold the pad** is our Outbreak exfil, beat for beat |
| Arena Breakout: Infinite | 37,000 | 25,000 | Extraction, loot kept only if you get out | Banking what you carry is the tension |
| 7 Days to Die | 35,000 | 22,000 | Build by day, horde night every 7th day, scavenge the town between | **Our Defend loop**, 13 years on, still top 40 on Steam |
| Left 4 Dead 2 (2009) | 24,000 | 29,000 | 4 players push a campaign in 4–5 chapters with safe rooms, a finale and a rescue | **Our Operations mode**; 17 years old and still here because the director makes each run different |
| Space Marine 2 | 17,000 | 17,000 | A mode literally called **Operations**: 3 players, a linear mission with 2–3 set pieces and an extraction | The L4D shape sells today when the gunplay is good |
| Deep Rock Galactic | 8,700 | 5,400 | 4 classes, a mission with 1–2 objectives, call the drop pod and run for it | Mission → run for the ride out, again |
| Killing Floor 2 (2016) | 7,200 | 6,000 | Waves with a trader between them, a boss at the end | Waves plus a shop still hold a niche |
| Warhammer 40k: Darktide | 7,100 | 6,700 | L4D-style missions with classes | Same shape, same band |
| Back 4 Blood (2021) | 1,100 | 960 | L4D clone with a card deck | Shape alone isn't enough: needs a hook (director + feel) |
| **Killing Floor 3 (2025)** | **690** | **450** | Pure waves, new engine, big budget | **Pure wave survival is dead on arrival in 2025–26.** This is the Horde Arena the sim rejected |

**Mobile** (Sensor Tower / AppMagic via FoxData, Singular and PocketGamer, 2026): the top-grossing shooters are Tencent's extraction and Battlefield-style games (Delta Force, Arena Breakout, CrossFire, Call of Duty Mobile, whose Zombies mode returns as a limited event each season). The survival-shelter loop (Into the Dead: Our Darkest Days, Last War, Whiteout Survival) is the other proven mobile shape: a base you return to, raids between. Mobile sessions run 10–20 minutes, so a 20-minute Outbreak needs an early-exit at 12 minutes for phone players.

**Does any of this change the picks? No, it confirms them, and adds two things:**
1. **Outbreak first** is what the top four Steam co-op shooters all are (extract, keep what you bank). Helldivers' "call the ship, hold the pad" is the exfil we already built.
2. **Operations second** is the shape of L4D2, Space Marine 2, Darktide and Deep Rock, all in the 7k–24k band for years. Back 4 Blood shows it fails without the director and good feel; we have both.
3. **Horde Arena dropped** is right: Killing Floor 3's launch shows pure waves no longer draw.
4. **New, from Helldivers 2 and ARC Raiders: a shared weekly war.** One town-wide meter in the hub ("the Front": contracts banked, Beacon lenses broken, players rescued, counted across every server). Hitting it unlocks next week's event for everyone (a new building opens, the Beacon changes colour, a dog bandana). It costs a DataStore counter and a hub board. It is the only proven retention hook the Roblox chart games don't have yet.
5. **New, from mobile: early exfil.** In Outbreak a pad can be called from 12 minutes with a smaller bird that takes one squad; the 15-minute bird takes everyone. Phone players get a 12–14 minute run, PC players a 20-minute one, in the same match.

---

## 3. The CCU maths

CCU = players active per day × minutes per player per day ÷ 1440.
Players active per day at steady state = installs per day × active days per install (the area under the retention curve).

So there are only three levers: **bring more people in** (ads), **keep them longer per day** (session length, sessions per day), and **keep them more days** (D1, D7, D30). Modes move the second and third. The sim measures those two per 1,000 installs a day and reports the installs needed for 2,000 CCU.

---

## 4. Proven co-op PvE modes, mapped onto our systems

| Mode | Taken from | What it is | Fits our build | Verdict |
|---|---|---|---|---|
| **Outbreak extraction** | MW3 Zombies (Outbreak + DMZ), HUSH, Dead Rails | Drop into the open town with other squads, take contracts, loot, call the helicopter and get out before the timer; the hunter roams | Town, Beacon, hiding, parts, helicopter, radio, dog, part spots, loot spots: **all built.** Needs a 12-player server, contracts, loot tables, extract timer, drop-in | **Build first** |
| **Operations** | Left 4 Dead campaign, MW3 Spec Ops, Battlefield 4 co-op missions | 4 players push through a linear chain of objectives (clear the station, restore power, hold the roof) ending in a finale and a rescue | Town buildings, doors, director, Beacon as the campaign's Tank-moment, helicopter finale. Needs objective markers, a route, 2–3 set pieces per chapter | **Build second** |
| Horde Arena | Survive Zombie Arena, Zombie Rush, Killing Floor | 5-minute rounds, respawn, score | Easy to build, but the sim says it **lowers** minutes per day (short rounds bore the teen; the kid bounces between modes). Also fights the horror tone | Drop |
| Convoy Rush | Battlefield Rush / Payload, Dead Rails, the full plan's army-truck escape | Escort the truck out of town against the Beacon | Mostly the same as Defend's last act with a moving base. Sim: same as Operations but worse for kids, and the truck is a big Blender job | Later, as an Outbreak contract and a second Defend ending, not a mode |
| Battlefield Conquest / Breakthrough | BF4 | Large PvP sector control | PvP, 32+ players: not our game, not our scale | No |
| Round-based Zombies | CoD Zombies, Project Lazarus | Endless rounds in one building | Already built as Endless; charts put it at 3k alone | Keep as is |
| Horde (Gears), Firefight (Halo) | | Wave defence with bought defences | That is Defend's night half | Covered |

---

## 5. The simulation (10 mixes, 6,000 players of each type, 30 days)

Two player types: an 18 year old on PC (45 % of installs) and a 6 year old on a phone (55 %). Each day they play matches from the modes on offer until bored, frustrated, confused or out of time; the chance of coming back tomorrow depends on the meta pull, the friends they have made (only possible with a hub), fun, and those three pushes.

| Mix | T D1 | T D7 | K D1 | K D7 | min/day T | min/day K | **CCU per 1k installs/day** | **Installs/day for 2k CCU** | Build days |
|---|---|---|---|---|---|---|---|---|---|
| X0 Today: Defend only, one match per server | 29 % | 3 % | 25 % | 3 % | 72 | 54 | 82 | 24,400 | 0 |
| X1 Today + Endless/Nightmare (built) | 30 % | 4 % | 27 % | 3 % | 69 | 52 | 81 | 24,600 | 0 |
| X2 Defend + hub with squads | 35 % | 7 % | 31 % | 8 % | 68 | 53 | 108 | 18,400 | 4 |
| **X3 + Outbreak (extraction)** | 41 % | 12 % | 34 % | 10 % | 71 | 52 | **139** | **14,400** | 18 |
| X4 + Operations (L4D push) | 39 % | 10 % | 36 % | 11 % | 66 | 50 | 126 | 15,800 | 16 |
| X5 + Horde Arena | 37 % | 9 % | 35 % | 9 % | 60 | 44 | 104 | 19,300 | 10 |
| X6 + Convoy Rush | 40 % | 10 % | 34 % | 10 % | 67 | 50 | 125 | 16,000 | 14 |
| X7 Defend + Outbreak + Horde | 41 % | 13 % | 37 % | 11 % | 66 | 46 | 136 | 14,700 | 24 |
| **X8 Defend + Outbreak + Operations** | 42 % | 14 % | 36 % | 12 % | 69 | 50 | **148** | **13,600** | 30 |
| X9 Everything | 42 % | 14 % | 36 % | 12 % | 66 | 46 | 142 | 14,000 | 46 |

**What it says:**
1. **The hub alone is worth +30 % CCU** for 4 days of work (X2). Friends are the strongest day-7 lever in the model, and no mode can give them without a place to meet.
2. **Outbreak is the best single mode by a clear gap** (X3): it is the only one with high variety, drop-in and 12 people, so it fixes boredom, the dead-server look and "play with others" at once.
3. **Operations is the best second mode** (X8). It is the one the kid likes most (a clear path, a team of four, no timer pressure) and it pushes the teen's D7 to 14 %.
4. **Horde Arena is a trap**: more modes is not more play. Five-minute rounds cut minutes per day by 10 % and the horror tone with it.
5. **Everything (X9) is worse than X8**: a sixth mode splits the player base and buys nothing.
6. **Even X8 needs about 13,600 installs a day for 2,000 CCU**, so ads still carry the growth. The modes cut the ad bill by 45 % against today; they do not replace it.

What the sim does not model: friend invites bringing in new players (k-factor), Roblox's own "friends playing" surfacing, and content updates. All three favour the hub and Outbreak further.

---

## 6. The decisions

### 6.1 Server shape: hub → squad → match → hub (Survive Zombie Arena, Dead Rails)

- **Hub server, 16 players.** The military safehouse the owner already wants for the menu becomes a walkable room: your dog at your feet, other players and their dogs, three doors with a glow each: **DEFEND**, **OUTBREAK**, **OPERATIONS** (later), plus the kennel, the class lineup and the store wall. No text beyond the door names.
- **Squads of up to 4.** Stand on a door's pad; friends step onto the same pad. The pad fills from the hub with anyone else waiting (toggle: "friends only" as a padlock icon). When the pad is full or 20 s pass, the squad teleports to a reserved match server (`TeleportService:ReserveServer`). Match servers return everyone to the hub at the end, keeping the squad together on the pad for a rematch.
- **Drop-in**: Outbreak servers hold 12 (3 squads); a squad can join a running Outbreak until the last 5 minutes. Roblox's "join friend" lands you in their hub server, and a **JOIN** glow on their squad's pad or a "following" marker puts you in their running Outbreak as a late squad if there is room.
- **Solo is always fine**: an empty pad still launches after 20 s; Outbreak with one squad still works (the director scales).
- One hub plus reserved servers keeps the "players online" number visible on the Roblox page and in the hub.

### 6.2 Mode 2: OUTBREAK (open-town extraction)

Taken from MW3 Zombies' Outbreak/DMZ loop, HUSH's noise hunter and Dead Rails' squad run. Our own town, hunter and systems, no names or assets from them.

**One match (20 minutes, 12 players in 3 squads, drop-in):**
1. **Insertion.** Each squad walks in from a different edge of town (the three road ends). Night, the Beacon asleep at its spot, lamps off. Radio: one line, "Exfil in twenty. Get what you can."
2. **Contracts.** Six contract boards (Toolbox payphones or radio sets, retextured) glow amber across town. A squad takes one by holding the prompt; it is theirs for 3 minutes:
   - **Fetch**: carry a part (the existing part system) from a building to a drop crate.
   - **Hold**: defend a marked room for 90 s while the director sends zombies through its windows (Defend's night code, in a town building).
   - **Hunt**: kill a marked Brute or a zombie dog pack (`Kind` tag).
   - **Lure**: set a Noise Maker and survive the Beacon's sweep for 60 s without being grabbed.
   - **Rescue**: find the sleeper NPC in a building and walk them to a safe house (uses the follow code of the dog).
   Each contract pays Scrip and drops a loot crate: ammo, a bandage, a throwable, sometimes a wall-gun ticket.
3. **The town gets worse.** At 7 minutes the Beacon wakes (its reveal, smashing the building nearest the most gunfire). At 12 minutes runners and dog packs spawn town-wide. The director uses the sum of all alive players' guns, so three squads together meet three squads' worth of zombies.
4. **Exfil.** From 12 minutes a squad can call a small bird that takes only that squad (the phone-length run). From 15 minutes any squad can call the big helicopter at one of three pads (the hilltop pad plus two new ones). The call is heard: the Beacon turns for that pad, every zombie nearby too. Hover 30 s, ladder, GRAB. The other squads see the flare and can run for the same bird or call their own. At 20:00 the last bird leaves; anyone on the ground is taken (the existing left-behind path).
5. **Downed and dead.** Down → revive by anyone, any squad (cross-squad revives make strangers friends). Dead → spectate your squad; a teammate can bring you back at a contract board (costs Scrip). A whole squad dead = out; back to the hub with the Scrip they had banked at boards.
6. **Banking.** Scrip you carry is lost if you die un-revived; Scrip banked at a board is kept. This is the extraction tension, and it is one number on the HUD (the existing points corner).

**Why it is not confusing:** the whole mode is "amber thing: go to it, hold the button, shoot what comes, get on the helicopter". Boards glow, the radio says one line per phase, the dog's trail leads to your contract, the night ring is the exfil timer (already drawn), and the Seen eye already warns of the Beacon. No objective list, no minimap, no text beyond the one Notice line, as the owner rules say.

**Why it is fun:** every run is different (which boards, which buildings open, where the Beacon wakes), 12 players make the town alive, the second half is a scramble to a shared helicopter with the Beacon chasing (the best moment of Defend, now every run), and squads can help or race each other without PvP.

**Reuse:** PartsServer (fetch), MatchServer night code (hold), DogServer, BeaconServer (wake, hear, chase, grab), EvacPath/EvacClient (call, ladder, GRAB), GlowDrops, Profile (Scrip). New: ContractServer, loot tables, 2 landing pads, squad tags, drop-in join, HUD squad markers (three small chevrons over teammates' heads only).

**Build: 14 days** after the hub. Order: squads and 12-player server (2), contract boards with Fetch and Hold (4), Beacon wake and exfil timer with 3 pads (3), Hunt/Lure/Rescue (3), drop-in and banking (2).

### 6.3 Mode 3: OPERATIONS (Left 4 Dead campaign push), second update

Four players, 13 minutes, a fixed route through the town in three legs with a safe room between each (a building with a barrable door, where the wall guns and the crate are):
1. **Leg 1, the Fuel Stop**: restore power to the pumps (Hold while the generator runs), refuel the truck.
2. **Leg 2, the Police Station**: open the armoury (a timed lock, zombies pour in), take the M4, free the sleeper NPC.
3. **Leg 3, the Apartments roof**: the finale. Hold the roof for 3 minutes while the Beacon tears the building from outside (its building smash, aimed at the one you stand on). The helicopter comes in low, GRAB.

The director randomises which rooms are open, where the crate is, which leg gets the Brute. Difficulty is per squad (Recruit by default). It is the kid's mode in the sim: no timer, a glowing path (the existing Guide glow on doors), a team that waits for you at the safe room. **Build: 12 days**, mostly markers and the three set pieces. Chapters later add more routes (the Dam, the Hospital) as the full plan says.

### 6.4 Keep, drop, defer

- **Keep Defend** as the flagship, unchanged. Its first escape still unlocks Nightmare; Outbreak should be open from the start so a new player has two doors on day one.
- **Keep Endless** as a door inside Defend's building, not a hub door.
- **Drop Horde Arena.**
- **Defer Convoy Rush** to an Outbreak contract (escort the truck 200 studs) and later Defend's second ending.
- **Build the meta from the full plan with the hub**: classes from the attire lineup, Scrip, dog levels, daily quests (one line in the hub, read by the radio), the Starter Pack. The sim's `meta` lever is worth as much as a whole mode.

---

## 7. Retention mechanics that ride on top (all proven, all cheap)

| Mechanic | From | Our version |
|---|---|---|
| Daily quest | Every top Roblox game | One per day, shown as a glowing board in the hub, spoken by the radio: "Bank 500 Scrip in Outbreak", "Escape Defend with a friend" |
| Squad rematch | Dead Rails, Survive Zombie Arena | Back on the same pad after the match; the pad stays theirs for 30 s |
| Shared helicopter | MW3 Zombies exfil | Strangers end up on one bird; the escape cutscene shows everyone in the door |
| Cross-squad revive | DMZ, Outbreak | Reviving a stranger gives both a Scrip bonus and a "Helped" tally |
| Dog levels and breeds | The full plan, 6 yo spend lever | Visible on everyone's dog in the hub |
| Weekly night event | Left 4 Dead mutations, Fortnite | Fog week, power-cut week, dog-pack week, set in `GameConfig.Director.Event` |
| Best-run boards | CoD Zombies rounds | Hub wall: best Defend escape time, most Scrip banked in one Outbreak, highest Endless night |
| The Front (shared weekly war) | Helldivers 2 Galactic War, ARC Raiders' changing world | One meter across all servers; reaching it unlocks next week's event for everyone |

---

## 8. Build order and gates

| Step | Days | What | Gate |
|---|---|---|---|
| 1 | 4 | **Hub + squads**: safehouse hub, 3 door pads, reserved servers, return to hub, friends-only padlock | 4 friends can meet, launch Defend together, come back together |
| 2 | 14 | **Outbreak** (section 6.2) | 12 strangers finish a run without reading anything; the exfil scramble is the best moment |
| 3 | 5 | **Meta**: classes, Scrip, daily quest, dog levels, store, analytics funnel (`ANALYTICS-FUNNEL.md`) | D1 measured ≥ 30 % in the ad test |
| — | — | **Ad test** (the brief's rule: test before scaling) | CCU per 1k installs/day measured against the sim's 139 |
| 4 | 12 | **Operations** chapter 1 | Kids' D7 rises; squads of mixed ages finish it |
| 5 | later | Chapter 2 map (both modes get it), Convoy contract, weekly events, Night Pass | |

Steps 1–3 are 23 working days to the game that the sim says is 1.7× today's CCU per install, with Operations taking it to 1.8×.

---

## 9. Honest limits

- The sim's D1/D7 are calibrated to usual Roblox bands, not measured. The first ad test replaces them.
- Twelve players plus the Beacon plus the gore caps is a performance question on phones that nobody has tested. Outbreak should ship with the gore caps halved per server and streaming on.
- Three squads in one town means the Beacon needs one more target rule: it goes to the loudest squad, not the nearest, or one squad farms it while another never sees it.
- Drop-in into a running Outbreak needs the director to re-read the alive gun total on every join (it already recomputes per spawn, so this is small).
- 2,000 CCU still needs about 14,000 installs a day at the sim's numbers. The modes make each install worth 70 % more; the ad budget decides the rest.
