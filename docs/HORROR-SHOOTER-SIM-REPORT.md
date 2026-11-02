# Last Light: full-match simulation, weaknesses and the restructured plan (31 Oct 2026)

This replaces the match numbers in `HORROR-SHOOTER-FULL-PLAN.md`. The guns, buildings, enemies, dog, store and chapters in that plan still stand, except where this report changes them.

**How it was tested.** I pulled the real map and the real `GameConfig` out of Studio: building positions, the 8 house windows, 15 hide spots, the landing zone, start points, kill points, gun damage, zombie health per wave, and the Beacon's sight and hearing. Simulated players then played whole matches on that map, second by second:
- walking the real distances, earning and spending points, buying doors, guns and ammo;
- fetching parts, hiding from the Beacon, going down, reviving and escaping.

That's 5 team types (solo 18 year old, solo 6 year old, an 18 + 6 year old duo, 4 × 18 year olds, and 2 of each) × 20+ versions of the rules × 100–500 matches each, plus a 216-combination grid search.

Code: `last-light/sim/match_sim.py` (the match), `tune.py` (the grid search), `final_check.py` (finalists) and `ui_sim.py` (the HUD). Pictures: `town_heat.svg` (where players walk and where the Beacon walks) and `hud_mockups.svg`.

**What it can and can't tell you.** It finds where the plan breaks: dead ends, things you can't afford, timings that don't fit the map, rules that end runs unfairly. Its skill numbers (aim, speed, hiding) are my estimates. The first real playtests should be checked against it and the numbers re-tuned.

---

## 1. Every weakness found, and the fix

| # | Weakness (what the sim saw) | Proof | Fix | After the fix |
|---|---|---|---|---|
| 1 | **The match is still too short.** Four parts with fixed waves is a 5–7 minute match: nights clear in 15–70 s. | Plan as written: 3.5–6.6 min | **Timed nights**: night 1 lasts 90 s, +15 s each night (night 6 = 165 s, last night 210 s). Lulls are 100 s. **Parts only in lulls 2, 3, 5 and 6**: lull 1 teaches going out, and lull 4 is a free scavenge. | 23–25 min for every team size |
| 2 | **You start upstairs and the stairs cost 1,000**, but you have ~940–1,060 points after night 1, so the first lull is wasted. | 74–92 % of first lulls blocked | Start downstairs (or the stairs debris costs 250) | 0 % blocked |
| 3 | **Door prices beat your points**: Police 1,500, Hardware and Clinic 1,000. If the part is in there, you're stuck. | 60–70 % of lulls blocked | **The building with the part is always open.** Gun-only doors are 500 / 750 / 1,000. | 0–3 % blocked |
| 4 | **A Beacon catch is instant death** (`PlayerHealth.Take`: no down, no revive). Solo, that ends the run. | 50–80 % of all losses | **Caught = thrown back to the house yard.** You lose the part you carried and 15 % of your points; the black-out stays. | Lull losses mostly gone |
| 5 | **The tower and helicopter are far away.** Planned tower at the north edge; the landing zone at the east end (184, 256), across the Beacon's road. | Escapes: solo 18 yo 1 %, 4 × 18 yo 31 % | **Tower on the hill right behind the house; the helicopter lands in the back yard** | 11 % → 60 % at that step |
| 6 | **The town is one strip with one road, and the Beacon walks it.** Every route uses it, so hiding is luck, not a choice. | Heat map | **Back alleys behind both rows of buildings**: slower, half as visible. The fast road or the safe alley is now the lull's decision. | Catches 0.4–0.9 → 0.05–0.25 per lull, tense but fair |
| 7 | **Fixed-size waves:** squads clear them in seconds, and solo players get swamped. | Solo 0 % escape in every fixed-wave version | **Director**: zombies come at 50 % of the rate the team can kill them, +5 % per night, +15 % per extra player | Solo becomes winnable |
| 8 | **One player can't hold 8 windows.** | Solo 18 yo 18 %, 6 yo 0 % | **The dog fights at night** (bites zombies at the windows) and **drags a solo player back up once a night**; solo gets 3 self-revives | Solo 18 yo 42 %, 6 yo 11 % (Recruit: 69 % / 36 %) |
| 9 | **Big teams got 2 parts a lull**, so 13-minute matches, and kids slowed squads: late home 48 %. | Mixed squad late 48 % | **One part per lull for every team** | 23–25 min; late home 8 % |
| 10 | **The pistol runs dry.** It holds 72 rounds; the 6 year old needs ~100 on night 2 and ~170 on night 3. | Hand check of the economy | Ammo in town buildings; the Shotgun wall buy (750) at the house | Nearly every player has the Shotgun after night 1; about half get the M4, a third the Sniper |
| 11 | **A 75 s lull is too short for a kid.** Round trips are 34–61 s at a kid's pace, plus a fight and a search. | Late home 50–97 % | **Lull 100 s**, and the dog leads you home at 0:20 | Late home 7–15 % |
| 12 | **Squads win too easily** (98–100 %). The director can't fix it here, because the model pools a squad's firepower. | Crescendo tests changed nothing for squads | Special enemies that split a squad (brute through a wall, a screamer pulling the lamps) from night 5, and pressure per window. **Tune with the first real squad playtests.** | Open |
| 13 | **A solo 6 year old rarely escapes**, even with every fix (11 %). | | **Recruit** difficulty (zombie hits 22, slower Beacon) as the default until the first escape; kids mostly play with others (the duo escapes 95 %) | 36 % on Recruit |
| 14 | **Today's HUD loses the 6 year old.** Eight of the 13 things you must know are told in text. | They miss 38 % of what they need | **The quiet hybrid HUD** (section 4) | They miss 5 % |

**Note:** another session edited `MatchServer` and `GameConfig` today (new backups `_beforePickupFix`, `_beforeInstantShots`, `_beforeFallFx`). The build has to start from those versions.

---

## 2. The rules the simulation settled on

Everything goes in `GameConfig` (new `Nights` and `Director` blocks).

| Lever | Value | Was |
|---|---|---|
| Start | Downstairs, 500 points, pistol + 1 bandage | Upstairs behind 1,000-point stairs |
| Night length | 90 s, +15 s per night; last night 210 s | Fixed wave count |
| Director | Spawn at 50 % of the team's kill rate, +5 %/night, +15 % per extra player; alive cap 6 solo, scaling with team | Spawn gap 0.6–1.8 s |
| Zombie health | 150, +30 per night | +40 |
| Lull | 100 s; one small line and the radio at 0:20 | — |
| Parts | 4, one each in lulls 2, 3, 5 and 6, one at a time for every team size; the part's building is open | — |
| Last night | Night 7: the Beacon comes to the house | Wave 5 |
| Tower / helicopter | Hill behind the house / the back yard | North edge / east end |
| Beacon | Sight fill 0.40 (Recruit 0.30); a catch throws you to the yard (part lost, −15 % points) | 0.55; instant death |
| Alleys | Behind both rows; Beacon sight in an alley ×0.5 | One road only |
| Dog | Bites at the windows (~25/s); lifts a solo player once a night; trail to the part; leads you home | — |
| Solo | 3 self-revives | 1 |
| Doors | Part building open; gun-only doors 500 / 750 / 1,000 | 750–1,500 |

### What a match looks like with these rules
| Team | Escape | Match length | Late home | Beacon catches per lull | How it's lost |
|---|---|---|---|---|---|
| Solo 18 yo | 42 % (Recruit 69 %) | 23 min | 0 % | 0.05 | Overwhelmed at night |
| Solo 6 yo | 11 % (Recruit 36 %) | 25 min | 11 % | 0.07 | Night, then late home |
| 18 yo + 6 yo | 96 % | 25 min | 7 % | 0.09 | Late home |
| 4 × 18 yo | 100 % (too easy, #12) | 23 min | 0 % | 0.24 | — |
| 2 × 18 yo + 2 × 6 yo | 99 % | 25 min | 8 % | 0.17 | Late home |

Nights run 90, 105, 120, 135, 150 and 165 s, then 210 s for the last night.

### How the fixes stacked up (the 18 + 6 year old duo, then 4 × 18 year olds)
| Version | Duo escape | Duo match | 4 × 18 yo escape | 4 × 18 yo match |
|---|---|---|---|---|
| A. Plan as written | 0 % | 5 min | 18 % | 7 min |
| B. Start downstairs | 1 % | 4 min | 22 % | 6 min |
| D. Cheaper doors, part free, ammo in town | 1 % | 4 min | 31 % | 5 min |
| E. Tower and helicopter behind the house | 3 % | 5 min | 60 % | 6 min |
| H. Caught = sent home | 12 % | 6 min | 98 % | 6 min |
| Timed nights + director | 94 % | 25 min | 99 % | 13 min |
| + one part per lull | 91 % | 25 min | 100 % | 23 min |
| + alleys, dog, team pressure (**final**) | 96 % | 25 min | 100 % | 23 min |

### Where the guns come from (duo, final rules)
Everyone has a better gun than the pistol after night 1. The **Shotgun** (house wall, 750) is bought by nearly every player, the **M4** (Police, 1,500) by about half the players, the **Sniper** (Apartments, 1,250) by about a third. Every price is reachable with the points you have at that time; no gun needs saving across more than 2 nights.

### The map, as the simulation sees it
- **One trip** (house → building → tower → house) is 440–800 studs: 23–42 s for an 18 year old, 34–61 s for a 6 year old. The Shop and the Hardware Store are the far ones, so they're best for gun stops, not parts on Recruit.
- **The Beacon** spends its time on the road, between the Neighbour House and the Barn. That's why the back alleys matter. See `last-light/sim/town_heat.svg`.

---

## 3. The restructured match (what a player meets)

| Time | What happens | New thing they learn (no reading) |
|---|---|---|
| 0:00 | Downstairs, pistol, the dog | Shoot at the windows |
| Night 1 (1:30) | Walkers | A window glows amber when it's being torn: hold to fix |
| Lull 1 (1:40) | **No part.** Follow the dog to the Shop for ammo, back before the ring empties | Going out and coming home; the radio and the dog call you home at 0:20 |
| Night 2 | Runners | — |
| Lull 2 | **Part 1**; its building is open | Carry it to the tower behind the house; the tower lights up |
| Night 3 | — | The kitchen wall gun glows once you can afford it |
| Lull 3 | Part 2; the Beacon's lamp comes close | Duck into the alley or a glowing dumpster; the dog lies flat |
| Night 4 | Zombie dogs | — |
| Lull 4 | **No part**: a free raid for guns and ammo | Doors cost points (the price shows only when you're close) |
| Lulls 5–6 | Parts 3 and 4 | — |
| Night 7 | The last night: the Beacon comes for the house, and the helicopter lands in the yard | GRAB |
| After | Class pick, the truck route, Nightmare (one line each) | — |

---

## 4. The HUD: what was simulated for phone and PC

13 moments in a match where you must know something (a window breaking, ammo low, the lull started, where the part is, time to go home, the Beacon close, where to hide, and so on). Each HUD option tells them through different channels (text, icon, a glow in the world, sound, the radio voice, the dog, a meter), and each has a cost to a phone-playing 6 year old and a PC-playing 18 year old.

| HUD option | On screen all the time | Told in text | 18 yo PC misses | 6 yo phone misses |
|---|---|---|---|---|
| U1 Today's HUD (text buttons, Notice lines) | 7 | 8 of 13 | 4.8 % | 38 % |
| U2 Typical Roblox (objective list, timers, prices, minimap) | 11 | 13 of 13 | 9.4 % | 64 % |
| U3 No HUD at all (world, dog, voice only) | 1 | 0 | 10.1 % | 13 % |
| **U4 Quiet hybrid ← pick** | 7 | 0 (one rare line) | **1.5 %** | **5 %** |

**The quiet hybrid (mockups in `last-light/sim/hud_mockups.svg`):**
- **On screen, always:** the heart-monitor health (built), the ammo number, the points number, the hotbar as 3 gun icons (built), and two new pieces at the top centre:
  - a **ring**: blue during the night (the night number in the middle, filling until dawn), amber in the lull (it drains; the seconds are shown in the middle);
  - a **Seen eye**: the existing Detect meter drawn as an eye.
  - A part icon lights next to the ring while you carry a part.
- **Phone buttons are icons, not words:** fire (crosshair, built), aim, reload, jump, roll. **A hand button appears only next to something** (hide, buy, grab, fix).
- **Everything else is in the world:**
  - the amber glow on a breaking window, an affordable wall gun, the tower, the helicopter;
  - a blue glow on a hide spot once you're being seen;
  - the dog's paw trail to the part;
  - a red edge pulse when you're hurt;
  - the radio voice at the start of a lull and at 0:20 ("Get back to the house!").
- **Text:** one small line on the existing Notice label, at most once a lull, and always spoken by the radio too. Prices only when you stand at the thing. No minimap, objective list or wave text.
- **PC** gets the same pieces, smaller, with key hints ([E]) at buyables. **Gamepad** gets button glyphs.

The weakest points left, for both players: noticing **ammo low** (fix: a click-empty sound plus the ammo number flashing) and **health low** (fix: heartbeat audio plus the red edge).

---

## 5. Fastest build order (each step playtestable on its own)

| Step | Days | What | Art needed |
|---|---|---|---|
| 1 | 3 | **MatchServer**: timed nights, director, lull cycle (doors open and bar), start downstairs, a catch throws you to the yard, solo 3 revives; `GameConfig.Nights` and `.Director` | None |
| 2 | 2 | **Parts and tower**: 4 placeholder parts, marker spots in buildings, a tower on the hill behind the house, the helicopter landing in the yard (reuse EvacPath) | Placeholder tower |
| 3 | 2 | **HUD U4**: the ring and the eye on the existing HUD, icon buttons, the hand button, glows, the radio voice (placeholder TTS or recorded) | Icons |
| — | — | **Playtest 1** (owner + 1 kid + 1 teen): check the sim's numbers | |
| 4 | 2 | **Back alleys** (fences, lanes, Toolbox props stripped and retextured) | Light |
| 5 | 4 | **Dog** (Blender base mesh, rig, 8 animations), trail, bites, lifts you, leads you home | Dog |
| 6 | 3 | **Runners + zombie dogs**; the Beacon hears gunfire; the last night at the house | Zombie dog skin |
| — | — | **Playtest 2**, then re-tune the sim | |
| 7 | 8 | 4 new buildings from the modular kit (Police, Hardware, Clinic, Army Checkpoint) + interiors | Kit |
| 8 | 3 | Classes, Scrip, store (Starter Pack, dog breeds, revive token), analytics funnel | Icons |

Steps 1–3 (7 days) are the new game with placeholder art. Everything after makes it better or keeps players longer.

---

## 6. Still open (honestly)
- **Squad difficulty** (#12) needs special enemies and real squad playtests; the model can't settle it.
- **Skill numbers** (aim, speed, hiding) are estimates. Playtest 1 sets them.
- **The HUD sim** scores how each channel lands, not how good it looks; the mockups need the owner's eye.
- **Spending** isn't in this sim. The earlier session sim (`sim_plans.py`) covers it; the dog and the replay layer still drive it.
