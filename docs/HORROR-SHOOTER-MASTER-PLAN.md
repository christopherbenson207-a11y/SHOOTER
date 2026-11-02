# Last Light: the full game plan (1 Nov 2026)

One document for the whole game: what is wrong with today's build and how each thing is fixed, the modes and how each one plays second by second, the maps each mode needs, the HUD, the guns, the classes, the enemies, the meta, the money, the ads, and the path to 2,000 players at once. It replaces `HORROR-SHOOTER-MODES-2K.md` (which stays as the chart research) and updates `HORROR-SHOOTER-FULL-PLAN.md` where they differ.

**How it was tested.** Three simulators in `last-light/sim/`:
- `match_play_sim.py`: every mode played 10 seconds at a time on the prototype maps below by three players: an 18 year old on PC, a 6 year old on a phone, and the Roblox median, a 10 year old on a phone who skims, quits after 30 seconds of nothing and plays 25-minute sessions. 4,000 matches per cell, solo and with a friend, plus a sweep of 12 variants of Defend and Outbreak (match length, lull length, the opening, insertion, map density). Also the HUD moment check per mode.
- `mode_sim.py`: 30-day cohorts for 10 mode mixes (which modes, with or without a hub). The ranking that picked Outbreak and Operations.
- `money_sim.py`: the final plan's retention with the impatient kid added, four openings (the first 30 seconds), and a spending model with nine offers and their trigger moments.

The numbers are my assumptions written down so they can be argued with. The ranking and the knees are what to trust; the first ad test replaces the absolute values. Chart evidence is in `HORROR-SHOOTER-MODES-2K.md` sections 2 and 2b (Roblox, Steam, mobile).

---

## 0. The plan in ten lines

1. **Defend** becomes 5 nights with 75-second lulls (17 minutes), zombies at the windows within 5 seconds. Today's 7-night, 27-minute match loses the median kid every time.
2. **A hub** (the military safehouse) with squad pads replaces one-match-per-server. Friends meet, squads of 4 launch to reserved servers and come back together.
3. **Outbreak**, the open-town extraction mode: 12 players in 3 squads, hot drop into a fight, glowing contract boards, the Beacon wakes, a shared helicopter exfil. Open from day one.
4. **Operations**, a Left 4 Dead style 4-player push with safe rooms and a roof finale, as the first big update.
5. **Endless** stays as a door inside Defend's building. Horde Arena and Convoy Rush are not modes.
6. **First 30 seconds**: a new player's first PLAY lands them in Defend night 1 with the dog and a pistol, zombies at the windows in 5 seconds, no menu, no cutscene. The hub comes after the first match. This is also the ad.
7. **HUD**: the built "quiet hybrid" (ring, eye, 3 gun icons, heart monitor, ammo and points numbers, world glows, radio voice, dog) in every mode, with squad chevrons and a Scrip-banked tick added for Outbreak. No objective lists, no minimap, no overlay text.
8. **Guns**: 16 at launch (4 built), each with a Noise rating. **Classes**: 4 free, 4 paid and earnable. **Enemies**: walker, runner, zombie dog, Brute from night 4 and in Outbreak; screamer in Nightmare.
9. **Money**: dog breeds, classes and skin crates are 75 % of revenue in the model. Starter Pack after the first escape. Never pay to win.
10. **2k CCU** needs roughly 19,000 installs a day at the model's numbers with the final plan, against 21,000–24,000 for today's build. Ads bring them; the plan keeps them.

---

## 1. Today's build: weaknesses and fixes

Everything in this table is from the handoff, the sim report and the three simulators. "Fix" is the decision, not an option.

| # | Area | Weakness | Evidence | Fix |
|---|---|---|---|---|
| 1 | Defend length | 7 nights, 27 minutes. The impatient 10 year old never finishes (0 % solo, 0 % with a friend); the 6 year old 55 % | match sim | **5 nights, 75 s lulls, parts in lulls 1–4, night 5 is the last** (17 min). Impatient kid 66 %, 6 yo 77 %, teen 100 %. Nightmare keeps 7 nights |
| 2 | Opening | Menu, PLAY, 15 s start, first kill at ~22 s. Impatient kid: 70 % still there at 30 s | money sim openings A–D | **First-ever PLAY goes straight into Defend night 1, zombies at the windows in 5 s** (first kill at 15 s). 86 % stay. Hub after the first match. Never a cutscene before the first shot (a 45 s cutscene halves the impatient kid's D1) |
| 3 | Lulls | 100 s lulls are 26–29 % idle for kids. Lull 1 has no part and is "follow the dog for ammo" | match sim idle share, worst phase "lull 6 (part)" | 75 s lulls, a part in every lull, 2–3 stray zombies on every route (strays cut idle by a quarter in Outbreak and do the same here) |
| 4 | Servers | One match per server, 1–4 players, no way to see or join others, "4 players" server list | mode sim X0 vs X2: hub alone +30 % CCU per install | **Hub + squad pads + reserved servers** (section 3) |
| 5 | Modes | Endless and Nightmare are Defend made harder; D7 about 3 % | mode sim X1 = X0 | Outbreak at launch, Operations next (sections 4–5) |
| 6 | Menu | Separate screen, Beacon walking the road. Pretty, but it is a wall between the player and the game, and the owner wants the safehouse rebuild | handoff 29 Oct, owner note | The safehouse **is** the hub. The Beacon on the road becomes the view out of the safehouse window. The menu screen goes; the only full-screen UI left is settings |
| 7 | Attire pick | One-time uniform screen after the first escape | handoff 30 Oct | Becomes the class lineup in the hub (section 8). Still one tap, still no words |
| 8 | HUD | Good (quiet hybrid, 5 % kid miss rate in Defend). But it has nothing for squads, Scrip banking or contracts | HUD moment check: Outbreak kid miss 9 %, impatient 11 % | Add squad chevrons (3 small marks over teammates only), a Scrip-banked tick on the points number, a contract glow colour (section 6) |
| 9 | Mobile | Aim assist numbers exist, code does not. Touch controls never checked on a real phone. Gyro axis is a guess | handoff 30–31 Oct | Aim assist is step 0 before any ad test (slowdown + gentle magnetism + optional auto-fire). One real phone session, recorded |
| 10 | Beacon fairness in a lull | A catch costs 15 % points and a trip to the yard. Fine. But with three squads it would hunt the nearest and ignore the rest | design read | Target rule: the **loudest** squad in the last 20 s, then the nearest. One rule, no new UI |
| 11 | Difficulty for squads | 4 teens escape 100 %; too easy | sim report #12 | Brute from night 4 (breaks a whole window), pressure per window scales with players; tune with the first squad test |
| 12 | Performance | Gore caps, 180 drops, splats, casings tuned for 4 players. Outbreak has 12 | handoff risks | Gore caps per server scale down with player count; streaming on; a 12-player phone test before Outbreak ships |
| 13 | Audio | Placeholder gun and zombie sounds, some ripped | handoff 6.6 | Replace before the ad test; music APM only |
| 14 | Test leftovers | TestRange, TestZombie, Loadout gives all guns, InfiniteReserve, DevTools, toolbox staging | handoff 6.2 | Delete or turn off before the ad test (one checklist in the build order) |
| 15 | Confusion on the kid's worst beats | Defend "night 7" and Outbreak "Beacon wakes" are where the 6 yo quits confused | match sim worst phases | The reveal cutscene already explains the Beacon. Add the dog's "lie flat" and the radio line "Hide. Don't shoot." at the first wake in every mode |
| 16 | Dead ends on the map | One strip, one road (fixed partly by alleys) | sim report #6 | Outbreak's map changes (section 4) give Defend the same back alleys and two more pads |

---

## 2. The game in one paragraph

A co-op PvE horror shooter for phone and PC, 1–4 in a squad and up to 12 in a town. At night you hold a house against zombies at the windows; between nights, and in the open-town mode, you raid a town the Beacon hunts with its lamps. Gunplay is the hook (the punchy-gunfire method, limb tearing, green blood), the Beacon is the star, the dog is the guide and the thing kids buy for. Every run is different, you can always bring a friend or find one, and the helicopter is always the way out.

**Pillars** (every decision checks against these):
1. Shooting in 5 seconds, never a wall of UI or story first.
2. One glance tells you what to do: glow, voice, dog, ring. No text to read.
3. Switch every few minutes: fight, then sneak, then run.
4. Friends make it better and the game makes friends for you.
5. Each run is new: director, random spots, 3 ways to end.

---

## 3. Structure: hub → squad → match → hub

**Hub: the safehouse (16 players).** One building interior (the owner's planned military safehouse rebuild, staging props already in `ServerStorage._MenuStaging`):
- Centre: the squad floor, three big painted pads, each lit the mode's colour: **DEFEND** (amber), **OUTBREAK** (blue), **OPERATIONS** (green, dark until update 1). Stand on a pad to queue. A padlock glow toggles friends-only.
- Left wall: the **class lineup**, six mannequins in uniform (the existing attire rigs); tap one to wear it. Locked ones stand behind glass.
- Right wall: the **kennel** (your dog, tap to pet, long-press to change breed), the **armoury wall** (gun skins), the **boards**: best runs, today's quest, **the Front** (the shared weekly meter).
- Back: a window onto the road where the Beacon walks (the current menu camera, now a view).
- Players and their dogs walk around. Emotes are Roblox default. No chat bubbles above the ambient.
- **Launch**: a pad launches when 4 stand on it or 20 s after the first, to a reserved server (`TeleportService:ReserveServer`). Outbreak pads fill 3 squads from across all hubs (`MemoryStoreService` queue) and can also send a squad into a running Outbreak with room (drop-in, until minute 10).
- **Return**: the match server teleports everyone back to the hub they came from, standing on their pad, squad intact for 30 s.
- **First-time player**: skips the hub entirely. Their first PLAY (one button on a black screen with the logo, the only screen they ever see) sends them straight to a Defend server. They see the hub after their first match.

**Solo**: every pad launches after 20 s whatever the count; Outbreak works with one squad (the director scales). Solo Defend keeps the 3 self-revives and the dog lift.

---

## 4. Mode 1: DEFEND (rebuilt flagship)

**Source**: Survive the Apocalypse and 99 Nights (out and back), CoD Zombies (points, wall buys, rounds), 7 Days to Die (horde night). 35k on Steam today for the same loop.

**Map (prototype, mostly built)**: the house (2 floors, 8 windows, 2 doors, basement later), the yard, the hill with the tower and the pad behind it, the town strip in front: Fuel Stop, Corner Shop, Apartments, Neighbour House, Burnt House, Abandoned House, plus Police Station, Hardware Store, Clinic and the Army Checkpoint from the full plan. Back alleys behind both rows. Six part spots, 15 hide spots, the Beacon's road. **Changes for this plan**: two more landing pads (Fuel Stop forecourt, Apartments roof) shared with Outbreak; 3 stray zombies per lull on the routes; the Shop always holds lull 1's part on a player's first ever match (a 20-second round trip).

**Match (17 minutes, 1–4 players):**

| Time | Beat | What the player learns, no reading |
|---|---|---|
| 0:00 | Downstairs, pistol, dog, zombies tearing a window **within 5 s** | Shoot the thing in the window; the glow is where to fix |
| Night 1, 90 s | Walkers. Points tick up in the corner. Gems fly to you | Kills pay |
| Lull 1, 75 s | Doors open, radio one line, dog's trail to the Shop, **part 1** is there. The Beacon wakes at the end of this lull (reveal) | Out and back; the ring draining is the clock |
| Night 2, 105 s | Runners. Kitchen shotgun glows when affordable | Buy on the wall |
| Lull 2 | Part 2, a far building; the Beacon's lamp sweeps; dumpster glows blue | Hide when the eye opens |
| Night 3, 120 s | Zombie dogs | — |
| Lull 3 | Part 3; alleys vs road is the choice | — |
| Night 4, 135 s | **Brute** breaks a window whole | Hold the stairs |
| Lull 4 | Part 4; tower lights; radio calls the bird | — |
| Night 5, 180 s | The last night: the Beacon comes for the house, roof comes off, helicopter at 45 s to go, GRAB | — |
| After | Escape tally, Scrip, class XP, dog XP; first time: Nightmare unlocked. **Back to the hub** | Hub |

**Simulated playthroughs (match sim, final settings):**

| Player | Solo finish | With a friend | Length | Idle share | First kill | Where they quit |
|---|---|---|---|---|---|---|
| 18 yo PC | 100 % | 100 % | 17.7 min | 14 % | 15 s | — |
| 6 yo phone | 74 % | 90 %+ | 15 min | 25 % | 16 s | Night 5 (confused by the Beacon at the house) |
| 10 yo impatient phone | 59–66 % | 80 %+ | 13.5 min | 28 % | 17 s | Lull 4 (idle walking) |

Against today's 7-night version: the impatient kid went from 0 % to 66 %, the 6 year old from 55 % to 77 %, and the teen lost nothing. Idle share is the remaining weakness: strays on routes and the dog's trail are what cut it.

**Significance**: the flagship and the ad. It teaches every system (shoot, buy, go out, hide, come back, grab) in one 17-minute run and feeds the meta. **Endless** is the same house without lulls (a door in the hub's Defend pad: hold to pick Endless). **Nightmare** is the 7-night version with brutes from night 2, screamers, the fast Beacon.

**Things to look out for**: the lull must never feel empty (strays, the dog, the glow on the part). The Beacon's first wake must be during lull 1 so the reveal cutscene lands before a kid meets it. Night 5 at the house is the kid's confused beat: the radio line "Shoot the lamps!" and lens glow carry it.

---

## 5. Mode 2: OUTBREAK (open-town extraction, 12 players)

**Source**: MW3 Zombies (Outbreak + DMZ contracts and exfil), Helldivers 2 (objectives, call the ship, hold the pad), HUSH and Dead Rails on Roblox, ARC Raiders and Arena Breakout on Steam (keep only what you bank). The top four co-op shooters on Steam are this shape.

**Map (prototype)**: the whole Defend town, used fully:
- **Three insertion pads**, one per squad, at the three road ends (west, east, the hill). Each pad has a wrecked vehicle with a glowing ammo box and **zombies already on it**: the hot drop.
- **Six contract boards** (retextured payphones / radio sets with an amber light): Fuel Stop forecourt, Shop, Apartments lobby, Police Station, Hardware yard, Clinic. Two more as reserves for the director.
- **Three landing pads**: the hilltop (built), the Fuel Stop forecourt, the Apartments roof. The roof is the "hard" pad: no Beacon can reach it, but it is the farthest.
- **Back alleys** both sides (sim report #6), 15 hide spots (built), the Beacon's road.
- **The house** is just another building here: its wall guns are buyable, its windows are a Hold contract room.
- **Tight town**: contract boards are never more than 120 studs apart; the sweep showed walk share matters less than strays, but long walks are where the 6 yo's confusion stacks.

**Match (15–20 minutes, 3 squads of 1–4, drop-in until 10:00):**

| Time | Beat | Channel |
|---|---|---|
| 0:00 | **Hot drop**: your pad, a wrecked truck, 4–6 zombies on you, an ammo box glowing | Sound, glow. First kill at 15 s |
| 0:30 | Radio: "Boards are live. Bank what you can." Nearest board glows amber; the dog trails to it | Voice, dog, glow |
| 0:30–7:00 | **Contracts 1–2** (3 min each, one per squad at a time): Fetch (carry a part to a crate), Hold (90 s in a marked room, zombies through its windows), Hunt (a Brute or a dog pack with a marker), Lure (place a Noise Maker, survive the sweep 60 s), Rescue (walk a sleeper to the Clinic). Each pays Scrip to your **carried** total and drops a crate. **Banking**: hold the board after a contract to bank. Banked Scrip is yours even if you die | The board's light turns green when banked; the points number gets a tick |
| 7:00 | **Beacon wakes**: reveal cutscene for everyone, it smashes the building nearest the most gunfire in the last 20 s. From here, loud is a choice | Sound, the Seen eye |
| 7:00–12:00 | Contract 3; runners and dog packs town-wide from 10:00; cross-squad revives pay both squads | — |
| 12:00 | **Small bird**: any squad can call it at any pad; it takes one squad, hovers 20 s. The phone-length run | Glow on pads, radio line |
| 15:00 | **Big bird**: any squad calls it; hovers 30 s at one pad; the Beacon turns for it, every zombie too. Other squads see the flare and run | Flare glow, rotor sound, the ring turns red |
| 20:00 | Last bird gone. Anyone on the ground is taken (left-behind path, carried Scrip lost, banked kept) | — |

**Downed**: anyone from any squad revives you. **Dead**: you spectate your squad; a teammate brings you back at a board for 200 carried Scrip (one body-bag prompt). Whole squad dead: back to the hub with banked Scrip.

**Simulated playthroughs (hot drop + strays, the picked variant):**

| Player | Solo finish | With a friend | Length | Idle share | First kill | Where they quit |
|---|---|---|---|---|---|---|
| 18 yo PC | 100 % | 100 % | 15 min | 24 % | 15 s | — |
| 6 yo phone | 78 % | 95 % | 13.5 min | 33 % | 16 s | The Beacon's wake, contract 3 (confusion) |
| 10 yo impatient phone | 80 % | 91 % | 13.6 min | 34 % | 16 s | Contract 1 (idle walking to it) |

The 40-second walk-in version had first kill at 57 s and the impatient kid at 71 %. The hot drop alone fixed first kill; strays on the streets cut idle from 42 % to 34 % and lifted the impatient kid to 80 %. The small bird costs 1 minute of average length and buys nothing in finish rate for the teen, but it is what lets a 25-minute-session phone player get two runs in, so it stays.

**Significance**: the retention mode. It is where friends are made (12 strangers, cross-squad revives, one bird), where runs differ most (which boards, which buildings the director opens, where the Beacon wakes), and where Scrip is earned. In the mode sim it is the single strongest add (+70 % CCU per install over today).

**Things to look out for**: the Beacon with three squads goes to the loudest, then the nearest. A squad that never shoots outside should rarely see it. The reveal cutscene freezes everyone for 5 s at 7:00; it has to be the same moment for all 12. Twelve players on a phone is untested. The HUD check says Outbreak is the kid's hardest mode to read (9 % miss): the two misses that matter are "which board is mine" (fix: only your squad's board glows for you) and "Scrip not banked" (fix: the points number pulses amber while unbanked, steady when banked).

---

## 6. Mode 3: OPERATIONS (Left 4 Dead push, update 1)

**Source**: Left 4 Dead 2 (24k on Steam, 17 years old), Space Marine 2's Operations (17k), Darktide, Deep Rock, MW3 Spec Ops, Battlefield 4 co-op. Back 4 Blood shows the shape fails without a director and good feel.

**Map (prototype)**: a route through the Defend town, three legs, safe rooms between (buildings with a barrable door, a wall gun, the crate):
1. Safe room 1: the Abandoned House → **Leg 1: the Fuel Stop**. Start the generator (a prompt), hold 90 s while the pumps run and zombies come over the forecourt, fill the jerry can.
2. Safe room 2: the Neighbour House → **Leg 2: the Police Station**. The armoury lock is timed (60 s of dialling, zombies through the cells), take the M4 and frags, free the sleeper, walk them out.
3. Safe room 3: the Clinic → **Leg 3: the Apartments roof**. Climb three floors while the Beacon tears the building from outside (its building smash aimed at the one you stand in; floors fall away behind you). Hold the roof 3 minutes, helicopter in low, GRAB.

The director randomises which rooms are open, where the crate is, which leg gets the Brute, which windows are broken. Difficulty is per squad (Recruit by default). No timer except the finale.

**Simulated playthroughs:**

| Player | Solo finish | With a friend | Length | Idle share | Where they quit |
|---|---|---|---|---|---|
| 18 yo PC | 100 % | 100 % | 12.5 min | 29 % | — |
| 6 yo phone | 81 % | 96 % | 11.3 min | 40 % | Leg 2 (the armoury lock) |
| 10 yo impatient phone | 81 % | 95 % | 11.2 min | 40 % | Leg 2 / leg 1 |

The kid's best mode and the one with the highest fun per minute for the teen (3.6 against 3.0 in Defend). Idle is walking between legs; strays and the glowing path handle it.

**Significance**: the mode kids finish and the mode chapters are built from (the Dam, the Hospital each add a route). It pushes teen D7 from 12 % to 14 % in the mode sim. Second update, 12 days.

---

## 7. Modes that were tested and are not in

| Mode | Match sim | Mode sim (30 days) | Verdict |
|---|---|---|---|
| **Horde Arena** (5-min rounds) | Everyone finishes, highest fun per minute (4.6) | **Lowers** minutes per day by 10 %, worst CCU of any add; Killing Floor 3 (pure waves, 2025) sits at 690 on Steam | Not a mode. Its lesson, action density, is why Defend's opening and Outbreak's hot drop changed |
| **Convoy Rush** (escort the truck) | Not simulated separately (same shape as Defend's last act) | Same as Operations, worse for kids, big Blender job | An Outbreak contract ("Escort", 200 studs) and later Defend's second ending |
| **PvP of any kind** | — | — | Not this game. RIVALS owns Roblox PvP |

---

## 8. The HUD: one decision for every mode

**Picked: the quiet hybrid (U4), already built, with three additions.** The sim report tested four HUDs across 13 Defend moments; U4 lost the 6 year old 5 % of the time against 38 % for the text HUD and 64 % for a typical Roblox objective-list HUD. The new per-mode check:

| Player | Defend miss | Outbreak miss | Operations miss |
|---|---|---|---|
| 18 yo PC | 1 % | 2 % | 1 % |
| 6 yo phone | 6 % | 9 % | 7 % |
| 10 yo impatient phone | 9 % | 11 % | 10 % |

**Always on screen (every mode):** heart-monitor health, ammo number, points/Scrip number, the 3 gun icons hotbar, the top-centre ring (night/lull in Defend, match clock in Outbreak that turns red when a bird is called, finale timer in Operations), the Seen eye under it.

**Additions for this plan:**
1. **Squad chevrons**: three small amber marks over your squad's heads only, through walls, fading when within 15 studs. Nothing over other squads.
2. **Scrip banked**: the points number pulses amber while carrying unbanked Scrip, steady white once banked, and the board you can bank at glows green.
3. **Your board**: only your squad's contract board glows for you; others are dark. The dog trails to yours.

**Everything else stays in the world**: amber glow on a breaking window, an affordable wall gun, a part, the tower, the helicopter; blue glow on hide spots when seen; the dog's trail; a red edge pulse when hurt; the radio voice, one line per phase. **Text**: one small Notice line at most once a phase, always also spoken. Prices only when standing at the thing. **No** minimap, objective list, kill feed, damage numbers, wave text, tutorial pop-ups.

**Touch**: the CoD-Mobile-style icon buttons (built). Fire follows the gun. **Aim assist** (slowdown, gentle magnetism, optional auto-fire; PC none) is step 0 of the build order.

**Ads and the HUD**: the ad is 15 seconds of the first 30 seconds of Defend: a window, a zombie, a shotgun, a limb comes off, the dog bites, the ring, no words. If the HUD needs explaining in the ad, it is wrong.

---

## 9. Guns (launch set: 16, 4 built)

Every gun has a **Noise** rating that the Beacon hears in a lull and in Outbreak. Rarity colours on the wall frame and the crate: grey, green, blue, purple, gold, amber Relic.

| Gun | Type | Rarity | Noise | Where | Job |
|---|---|---|---|---|---|
| Service Pistol (built) | Sidearm | Common | Med | Start | Teaches aiming |
| Knife | Melee | — | Silent | Everyone (V) | Quiet stray kills |
| Baseball Bat | Melee | Common | Silent | Shop, Burnt House | Kid favourite, big shove |
| Crowbar | Melee | Uncommon | Silent | Hardware | Opens lull doors faster |
| Compact SMG | SMG | Uncommon | Med | House hall wall | Easy on touch |
| Pump Shotgun (built) | Shotgun | Uncommon | High | House kitchen wall, 750 | The night-1 buy |
| Double-Barrel | Shotgun | Uncommon | High | Random floor spot | Two-shot burst |
| AK (built) | Rifle | Rare | High | Rifleman start, crate | Workhorse |
| M4 | Rifle | Rare | High | Police armoury, 1,500 | Operations leg 2 reward |
| Bolt Sniper (built) | Sniper | Rare | Very high | Apartments roof, 1,250 | Penetrates 3; the roof nest |
| Crossbow | Quiet | Rare | Silent | Scout start, Hunting cabin | Stealth gun; bolts recoverable |
| Nail Gun | Special | Uncommon | Low | Hardware wall | Weapon and board repair at range |
| Flare Pistol | Special | Rare | — | Fuel Stop wall | A flare pulls the Beacon's lamps to it |
| Frag Grenade | Throwable | — | Very high | Police, ammo boxes | Window clear |
| Noise Maker | Throwable | — | Lure | Shop, crate | Pulls zombies and the Beacon (Lure contract) |
| Lamp Breaker | Relic | Relic | Med | 3 parts across lulls (quest) | Stuns the Beacon 6 s |

Later with chapters: Revolver, Machine Pistol, Stinger SMG, Auto Shotgun, Burst Rifle, DMR, Belt LMG, Fire Axe, Flamethrower (green fire), Grenade Launcher, Flashbang, Molotov, Suppressor attachment. Guns and damage are never sold.

**Spread in a match**: start pistol + knife (class changes it), one random floor gun in the house, 2 wall buys at the house, 1 wall buy per town building, the crate in a random building (moves after 4 uses), the workbench for attachments and Rework.

---

## 10. Classes (the uniform is the class)

Picked by tapping a mannequin in the hub lineup. Each levels with play (XP from kills, revives, contracts, escapes), unlocking small perks and looks. Earnable with Scrip; four are also sold.

| Class | Start gun | Perk | Free / paid |
|---|---|---|---|
| Rifleman | AK | +10 % mag on rifles | Free (the default on the first match) |
| Medic | Machine Pistol | Faster revives, bandages heal more, 3 bandages | Free |
| Engineer | Nail Gun | Boards faster, stronger boards, builds the turret | Free |
| Scout | Crossbow | Quiet steps, slower Seen fill | Free |
| Demolition | Double-Barrel | Frags ×2, window clears | 199 R$ or 6,000 Scrip |
| Hunter | Bolt Sniper | Marks a Brute for the squad; dog bites harder | 199 R$ or 6,000 Scrip |
| Firefighter | Fire Axe | Breaks debris doors free, carries two parts | 199 R$ or 6,000 Scrip |
| Marksman | DMR | Headshots pay double | 199 R$ or 6,000 Scrip |

No class is required for anything. Perks are small on purpose: a class is a flavour and a uniform first.

---

## 11. Enemies

| Enemy | From | Job | Status |
|---|---|---|---|
| Walker | Night 1 | Bulk, tears boards | Built |
| Runner | Night 2 | Punishes slow reloads | Built |
| Zombie Dog | Night 3, packs of 3–5 | Flanks in lulls, jumps windows | Built (FBX to import) |
| **Brute** | Night 4, Outbreak Hunt contracts | Breaks a window whole, armoured head: the squad problem | New, launch |
| Screamer | Nightmare, Outbreak after 12:00 | Pulls the Beacon's lamps to you | Update 1 |
| Crawler | From limb tears | Comes under barricades | Free from the gore system |
| The Beacon | Lull 1 onward, 7:00 in Outbreak, the finale in Operations | The star. Streets only, lamps, grab = yard (Defend) or carried Scrip lost (Outbreak) | Built |

Soft horror by default (slow lamp sweep, the hum first, no jump scares); Nightmare brings the fast sweeps and the scream. Green blood, no face gore, dull skin, glowing eyes carry the read.

---

## 12. Meta: the reason to come back

| Hook | From | Ours |
|---|---|---|
| Scrip | Every survival hit | Earned in all modes, banked in Outbreak; buys classes, breeds (slowly), attachments |
| Class levels | Killing Floor, World War Z | Perks and looks per class |
| Dog levels and tricks | The full plan's biggest kid lever | Visible in the hub on everyone's dog |
| Daily quest | Every top Roblox game | One, on a hub board, spoken by the radio |
| **The Front** | Helldivers 2's Galactic War | A town-wide weekly meter across every server; reaching it unlocks next week's event for everyone (a building opens, a Beacon colour, a bandana) |
| Weekly event | L4D mutations | Fog week, power-cut week, dog-pack week in `GameConfig.Director.Event` |
| Badges | CoD, Dead Rails | Both Ways Out, Nobody Left Behind (12 on one bird), Quiet Run (no shots in Outbreak), Night 20 Endless |
| Best-run boards | CoD rounds | Hub wall, solo and squad |
| Chapters | L4D campaigns, CoD maps | The Dam (update 2): a new town, base, way out, hunter, for all three modes |

---

## 13. Money

**Rules**: never pay to win. Guns, damage, dog abilities and class perks are never Robux-only. Classes are always earnable.

**What the model says (money sim, final plan, opening C, per 1,000 installs):**

| Offer | Price | Trigger moment | R$ per 1,000 installs | Share |
|---|---|---|---|---|
| Dog breeds | 149 (also Scrip, slowly) | Seeing others' dogs in the hub; the kennel | 10,000 | 29 % |
| Classes | 199 or Scrip | The lineup, locked uniforms behind glass | 9,900 | 29 % |
| Gun skin crates | 99 | The armoury wall; a teammate's glowing gun | 6,500 | 19 % |
| Starter Pack (skin, 1,000 Scrip, collar) | 99, once | Right after the first escape | 2,000 | 6 % |
| Scrip pack | 149 | Standing at something you cannot afford | 1,800 | 5 % |
| Night Pass (season) | 399 | Day 7 | 1,800 | 5 % |
| VIP (+20 % Scrip, collar, name colour) | 299 | Day 3 | 1,200 | 4 % |
| Private server | Roblox standard | Three friends made | 600 | 2 % |
| Revive token | 25, one per match | Downed late in a match | 350 | 1 % |
| **Total** | | | **~34,000** | |

Today's build models at about 3,300 per 1,000 installs: the plan is roughly ten times, almost all of it from the hub (you see what others have) and the meta (there is something to want). Payer rates in the model are 6–12 %, which is optimistic for Roblox; halve everything above for a planning floor: about **17,000 R$ per 1,000 installs**, and at 2,000 CCU roughly **300,000–600,000 R$ a day** before Roblox's share. The first offer test replaces these.

**Order of monetisation work**: breeds and classes first (58 % of revenue, and both already have art pipelines), then skins, then the Starter Pack, then the pass. The revive token is nearly worthless and risks "pay to win" feelings: keep it one per match or drop it.

**Three rules from the model**: show the thing on other players before selling it (the hub does this), trigger at the moment of want (first escape, standing at the locked door), and never interrupt play with a shop.

---

## 14. Ads and the first 30 seconds

The ad is the game's first 30 seconds, uncut: zombies at the windows within 5 seconds, a shotgun, a limb off, the dog biting, the Beacon's lamp through the window. No logo card first, no text. Every top mobile ad shows the real first minute (Last War's ads are over half one simple readable mini loop).

**Opening variants tested (money sim):**

| Opening | Still there at 30 s (teen / kid / impatient) | Impatient D1 | CCU per 1k installs/day |
|---|---|---|---|
| A. Today: menu, PLAY, 15 s start, first kill ~22 s | 90 / 78 / 70 % | 29 % | 95 |
| B. Hub first, pick a door, lobby wait | 86 / 70 / 62 % | 26 % | 87 |
| **C. Straight into Defend, zombies in 5 s, hub after** | **94 / 88 / 86 %** | **37 %** | **107** |
| D. 45 s crash cutscene then the house | 85 / 66 / 50 % | 22 % | 82 |

**The rules**: no cutscene before the first shot; no hub before the first match; a kill in the first 15 seconds; the first lull's part is in the Shop, 20 seconds away; the Starter Pack never shows before the first escape.

**Test before scaling** (the 18 Oct rule): 3 ad creatives × 2 thumbnails, 5,000 installs each, measure stay-30 s, first-match finish, D1, CCU per 1k against the model's 107. Scale only the creative that beats 30 % D1.

---

## 15. The path to 2,000 CCU

CCU = installs per day × minutes per install over 30 days ÷ 1440 (steady state).

| Build | Minutes per install (30 d) | CCU per 1k installs/day | Installs/day for 2k CCU |
|---|---|---|---|
| Today | ~118 | 82–95 | 21,000–24,000 |
| Final plan (Defend 5 nights, hub, Outbreak, meta, opening C) | ~154 | 107 | 18,700 |
| + Operations | ~165 | 115 | 17,500 |

Honest reading: the plan makes each install worth 30–40 % more and each payer worth ten times more, but 2,000 CCU still needs about 18,000 installs a day at the model's numbers. Three things the model does not count all push the same way: friends inviting friends (the hub and Outbreak make this real), Roblox's own "friends playing" surfacing, and content updates (Operations, the Dam). A reasonable ambition with ads plus those is 2–3k CCU within 60 days of the Outbreak launch; the ad test tells us the real multiplier.

---

## 16. Build order (one thing at a time, playtested before the next)

| Step | Days | What | Gate |
|---|---|---|---|
| 0 | 2 | **Ship blockers**: mobile aim assist code, test leftovers off, placeholder audio replaced, gore caps by player count | A real phone session, recorded |
| 1 | 2 | **Defend to 5 nights / 75 s lulls**, zombies in 5 s, parts in every lull, strays on routes, Brute night 4, the Shop part on match 1, Beacon loudest-squad rule (`GameConfig.Nights`) | Impatient-kid tester finishes solo |
| 2 | 4 | **Hub + squad pads** in the safehouse, reserved servers, return, first-time straight-to-Defend | 4 friends launch and return together |
| 3 | 14 | **Outbreak**: squads + 12-player server (2), boards with Fetch and Hold (4), Beacon wake + exfil with 3 pads + small bird (3), Hunt/Lure/Rescue (3), drop-in + banking (2) | 12 strangers finish without reading |
| 4 | 5 | **Meta + store**: classes from the lineup, Scrip, dog levels, daily quest, the Front, breeds, Starter Pack, analytics funnel | D1 ≥ 30 % in the ad test |
| — | — | **Ad test** (section 14) | CCU per 1k against 107 |
| 5 | 12 | **Operations** chapter 1 | Mixed-age squad finishes |
| 6 | later | Brute art, Screamer, Lamp Breaker quest, Night Pass, the Dam | |

Steps 0–4 are 27 working days to the game the model calls 1.3× today's CCU per install and 10× its revenue per install.

---

## 17. Things to look out for (the risk list)

1. **Idle time is the kid killer.** Every mode's kid quits land on walking phases. Strays, the dog's trail and glows are not polish; they are the retention feature. Measure "seconds without input outside" in analytics.
2. **Confusion at the Beacon's first wake.** Both kids quit there. The reveal cutscene plus the dog lying flat plus one radio line, in every mode, the first time.
3. **Twelve players on a phone.** Untested. Gore caps by player count and streaming before Outbreak ships; a 12-phone test is the gate.
4. **The Beacon's targeting with three squads.** Loudest, then nearest. Watch for one squad farming it.
5. **Squads of four teens are too easy.** Brute and per-window pressure; tune on the first squad test, not in the sim.
6. **Payer rates in the model are high.** Plan on half.
7. **Ads alone carry growth.** The plan cuts the install need by a quarter, not by half. Do not scale ads before the test beats 30 % D1.
8. **No text, ever.** Every new feature will tempt an explainer. The HUD check numbers are the argument against it.
9. **The owner's rules stand**: no gimmick loops, no aim assist on PC, green blood, no face gore, no damage numbers, no overlay text, Toolbox stripped and retextured, authored UI, Studio Edit mode with backups, Ctrl+S.

---

## 18. Maps: how they should look and read

The three modes share one town, so the town has to work three ways: a ring around one house (Defend), a web of six boards and three pads (Outbreak), and a line with three set pieces (Operations). These are the rules, then the plan of the town, then each mode's overlay, then the hub.

### 18.1 Rules for every map
1. **Readable from the door.** Standing at any exit you can see the next landmark: a lit sign, the tower's red light, a flare, the Beacon's lamps. A kid never asks "where". The glow system does the rest.
2. **Three heights.** Street, roof, hill. Roofs are the safe-from-the-Beacon layer (indoors rule: a roof over you means the lamps can't see you); the hill is the overlook and the exit. Every building you can enter has a way up.
3. **Two routes everywhere.** The road (fast, lit, the Beacon's) and the alley (slow, dark, half as visible). Every pair of buildings is joined by both. The choice is the lull.
4. **Dark with islands of light.** Night stays (owner rule). Street lamps, lit shop signs, burning barrels and the Beacon's lamps make pools; between them you use the gun torch. Zombies read by their eyes. The house and the pads are always lit.
5. **Landmarks you can name without words.** The water tower, the burnt house, the red tower light, the church spire (a façade), the crashed helicopter from the opening. A squad can say "meet at the burnt house".
6. **Cover at kid height.** Cars, dumpsters, fences, planters every 25–40 studs on every route. Hide spots are things a six year old recognises as hiding places.
7. **No clutter.** Toolbox props only when vetted, stripped and retextured; nothing that is just trash. Each prop has a job: cover, hide, loot, landmark, or a line-of-sight blocker.
8. **Human-authored look.** Curved kerbs, broken fences that lean, overgrown lawns, one dead tree in the wrong place. No perfect grid, no repeated house three times in a row (vary colour, porch, roof pitch).
9. **Destruction is state.** The Beacon smashes buildings and they stay smashed for the match. A town that gets worse as the match goes on is a clock you can see.
10. **Everything placed by markers** (`PartSpot`, `LootSpot`, `WallBuy`, `CrateSpot`, `StraySpawn`, `HideSpot`, `Board`, `Pad`, `StreetBlock`, `FacadeSmash`), so the director can change a run without a build.

### 18.2 The town, "Hollow Creek" (one plan, all modes)

About 480 × 300 studs: the house at the back centre, the hill behind it, Main Street in front, a second row across the street, alleys behind both rows, woods at the two far ends.

```
   WOODS W            HILL: radio tower (red light), landing pad 1, deer edge           WOODS E
   insertion W   --------------------------------------------------------------   insertion E
                 back alley N (fences, bins, a ladder to each roof)
   Fuel Stop -- Corner Shop -- [THE HOUSE + yard] -- Neighbour House -- Abandoned House
   (pad 2)      (board)        (Defend base)         (board)             (board, relic part)
   ============================ MAIN STREET (the Beacon's road, lamps, wrecks) ================
   Police Stn -- Hardware -- Clinic -- Burnt House -- Apartments (3 floors, roof = pad 3, sniper nest)
   (board, M4)   (board)    (board)   (no roof: unsafe)  (board)
                 back alley S (garages, a drainage ditch, the hunting cabin at the E end)
   facades: church (spire landmark), diner, laundromat, school (never enterable), garages
```

- **The house** stays as built (2 floors, 8 windows, basement later). The yard faces the hill; the back door is the lull exit, the front door faces Main Street.
- **Main Street** is wide (40 studs), with 4 wrecked cars and 2 overturned buses as hide spots and street blocks the director can move. Street lamps every 60 studs, half of them flickering.
- **Alleys** are 12 studs wide, fenced, with one gap per building so you can cut through, dumpsters (hide) and roof ladders.
- **Ten enterable buildings** (the sim's knee), each with: one wall gun, one loot table, one part spot, one hide spot, one way to the roof, two doors (front to the street, back to the alley). Interiors from the 30-piece modular kit: rooms are rooms, not boxes (counters, shelves, a back office, a stairwell).
- **The hill** is the only big slope. The tower and the pad on top, the cabinet at the slope's foot, the sleeping Beacon's spot left of the yard, deer on the edge in lulls.
- **The woods** at both ends are 30 studs of dead trees and a fence: the edge, the insertion pads, zombie-dog spawns, the hunting cabin (crossbow).
- **Lighting**: moonlight 2.2 and the saved night values, plus warm pools (lamps), cold Beacon lamps, green fire, amber glows. The house interior is lit by the generator state (dark until Fuel comes back, then warm).
- **Sound**: wind, a loose sign banging, a dog far off, the Beacon's servo whir outdoors. Indoors muffles everything (built).

### 18.3 Defend's overlay
The house is the centre; everything is measured by round-trip time at a kid's pace (34–61 s for one trip, sim report). Lull 1's part is always in the Shop (20 s). Parts 2–4 come from any board building. The two far ones (Police, Hardware) are gun stops, not part spots on Recruit. The Beacon's road lies between you and the far row, so every far trip is a road-or-alley choice. Pads 2 and 3 are not used in Defend (the hilltop is the escape) but they are visible, so a Defend player learns the town for Outbreak.

### 18.4 Outbreak's overlay
Three insertion pads (W woods, E woods, hilltop), each with a wreck, an ammo box and zombies on it. Six boards, one per building-row position, so no two squads start nearer than 120 studs to the same board. Three landing pads: hilltop (open, far from the Beacon's road, the easy pad), Fuel Stop forecourt (on the road, the Beacon can reach it, the fast pad), Apartments roof (no Beacon, but three floors of zombies to climb, the hard pad). The director closes one street with a bus each run and opens 7 of the 10 buildings. Loot crates spawn on `LootSpot`s weighted toward buildings nobody has entered yet, so squads spread out.

### 18.5 Operations' overlay
A line: Abandoned House (safe 1) → Fuel Stop (leg 1) → Neighbour House (safe 2) → Police Station (leg 2) → Clinic (safe 3) → Apartments (leg 3, roof finale). Doors bar behind you as you pass so the route only goes forward (the L4D rule). The glow is on the next door only. The Beacon is scripted: it walks the road beside you from leg 2 and tears the Apartments from outside in leg 3 (floors fall away behind you as you climb). Chapter 2 (the Dam) adds a second line with its own three set pieces.

### 18.6 The hub: the safehouse
One room, about 60 × 40 studs, a converted fire station: a shutter door (closed), sandbags, a generator humming, cots, a map table (the daily quest board), the three squad pads painted on the concrete floor with a hanging lamp each, the class lineup along one wall in a row of lockers, the kennel in a corner with straw, the armoury wall with glass cases, the best-run chalkboards, and a big window onto Main Street where the Beacon walks at the far end. Warm inside, cold outside the glass. Sixteen people fit without crowding the pads. No text beyond the three pad names and prices on hover.

### 18.7 How the town gets built
Markers first, art second. The current town has 6 shells; the 4 new buildings and the 6 interiors come from the modular kit (about 1 day each). Façades are Toolbox shells retextured. The hill is done. Alleys are fences, gaps, dumpsters and ladders (2 days). Insertion wrecks and two pads are 1 day. The hub is the owner's planned safehouse rebuild with the pads added. **Review**: a heat map of where sim players walk (`town_heat.svg`) before art, and the orbit-viewer review for every hero prop.

---

## 19. Quests: yes, three kinds, none of them a list

Quests are the strongest between-match lever the model has. Sweeping the meta pull on the final plan (money sim, opening C):

| Meta layer | Impatient-kid D7 | Teen D7 | CCU per 1k installs/day | R$ per 1k installs |
|---|---|---|---|---|
| Classes and the dog only, no quests | 9 % | 8 % | 81 | 16,800 |
| + one daily quest | 12 % | 10 % | 96 | 29,200 |
| + the weekly Front (shared meter) | 14 % | 12 % | 107 | 34,100 |
| + story notes + the relic quest chain | 16 % | 13 % | 120 | 38,300 |

Each layer is worth 10–15 % CCU and a lot of revenue, because a quest is a reason to come back and a reason to want the thing it leads to. The condition from the HUD work still holds: **no quest log, no checklist, no text objective.** A quest is a thing in the world that glows, a radio line, and a board in the hub that fills.

### 19.1 Daily quest (one, everyone the same)
Picked from a short list by the day's seed: "Bank 500 Scrip in Outbreak", "Escape Defend with a squad of 4", "Finish a run without firing outside", "Revive 3 strangers", "Fit all 4 parts before night 4". Shown as a chalk drawing on the hub's map table (an icon and a count), spoken once by the radio when you enter the hub. Pays Scrip and class XP; a 7-day streak pays a dog treat (cosmetic). Cost: one config list, one board, one radio line a day.

### 19.2 The Front (the shared weekly war)
From Helldivers 2 and ARC Raiders. One meter across every server: this week "break 50,000 lenses", next week "bank 20 million Scrip" or "rescue 100,000 sleepers". The hub's big board fills during the week; the radio reports it at hub entry ("The Front is at seventy percent"). Reaching it unlocks next week's event for everyone: a boarded building opens, the Beacon's lamps turn green, fog week, the dog gets a bandana. Missing it means the harder event (the Beacon wakes earlier). Cost: one shared counter, one board, one line. It is the one proven hook the Roblox chart games do not have.

### 19.3 Story pieces and the relic chain (the long quest)
Left 4 Dead and CoD tell the story in pieces you find. Ours: **radio notes**, small cassette players in buildings (a glow within 10 studs, a prompt, a 10-second voice line through the radio filter). Twelve in chapter 1. They tell what the Beacon is, who the sleepers are, who flew the first helicopter. Finding all twelve lights a lamp on the hub board; all lamps across every chapter open the secret level (the Hollow). Alongside it, the **Lamp Breaker** relic: three parts in three hidden spot types (the cabinet's locked drawer, the Apartments roof tank, the cabin), Outbreak only, built at the house workbench; it stuns the Beacon 6 s and is the thing the teen grinds for. No text anywhere: the parts glow amber like everything else, the workbench shows three sockets.

### 19.4 Class and dog progression as quests
Each class level has a goal that is also a quest: "Engineer 3: repair 100 boards". Shown as a filling ring on the class's locker, no words. The dog's tricks unlock the same way (level 2: sit and spin, 3: fetch a gem, 4: howl at the Beacon). These are the quests kids actually do, because they are about their thing.

### 19.5 What is deliberately not here
No quest log screen, no objectives panel, no NPC quest-givers with dialogue boxes, no branching choices, no quests that are only walking, no quests that need reading. Every quest is visible as a thing in the world or a board in the hub, spoken once, and finished by playing normally.

---

## 20. The intricate parts that matter (the small things the sims kept pointing at)

1. **The first 15 seconds**: a zombie already tearing a window when you load, the dog already growling at it, the pistol already in your hands. The glow on the window, nothing else.
2. **The 20-second first trip**: lull 1's part is 20 seconds away on your first match, so "go out and come back" is learned before it is risky.
3. **Strays on every route**: 2–3 slow walkers between any two buildings. They cut idle by a quarter and are what the knife and bat are for.
4. **Gems fly to you** (built): never a loot screen.
5. **Prices only at the thing** (built).
6. **Only your board glows** in Outbreak. The dog trails to it.
7. **Banked vs carried Scrip** is a pulse on one number, not a second number.
8. **The reveal cutscene is the same moment for everyone**, and the dog lies flat, so the Beacon is introduced the same way in every mode.
9. **The Beacon goes to the loudest**, so quiet play is rewarded without a stealth meter.
10. **Roofs are safe from the lamps** (built): the vertical answer to "where do I hide" that a kid can see.
11. **Doors bar behind you in Operations**: you cannot get lost backwards.
12. **The small bird at 12:00**: a phone session fits two runs.
13. **Return to the same pad together**: the rematch is one step, and the squad stays a squad.
14. **The Front's radio line at hub entry**: the whole player base is on one team, said in one sentence.
15. **Everything is a marker**: the director can change where a thing is without anyone opening Studio.
