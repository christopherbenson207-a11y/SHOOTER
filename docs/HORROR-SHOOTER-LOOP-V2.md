# Last Light: core loop v2 (31 Oct 2026, revised after chart research)

The owner's verdict on the current build: satisfying but weak, too short, and a lot of it doesn't tally. This file says why, what the zombie games that are winning right now do, and the new match structure. It replaces "The whole match" in `HORROR-SHOOTER-ESCAPE.md`. Shooting, gore, the Beacon, the house, the town and the helicopter all stay; what changes is how they connect.

## 1. Why it feels weak

**It's two games glued at the front door.** Waves 1–3 are Call of Duty Zombies (shoot, points, buy). After the breakout it's a stealth game (hide from the Beacon, run to a flare). The skills, the economy and the goal all switch once, and neither half lasts long enough to build up.

**The match is about 8–10 minutes, and most of it is one room.** The town, the best-looking part of the map, is something you run across once.

**Points stop mattering** after the breakout.

**The story doesn't line up:**
- You get a soldier uniform *after* you escape, so the game never says who you are.
- The helicopter shows up without you doing anything to call it.
- Free guns on the floor make wall guns and the crate pointless.
- Zombies and the Beacon never touch each other's game.

**The only reason to replay is the unlock**, and that's gone after one escape.

## 2. What the zombie hits are doing (live chart, 31 Oct 2026)

Zombie games on Roblox ranked by live players (rblxdb, 31 Oct 2026):

| Game | Live players | How it plays |
|---|---|---|
| Dead Rails | ~26,000 | A run with an end: ride a train 80 km through zombie country to a final bridge. Stop at towns to loot, get back on the train before night. Classes. Bonds are the currency kept between runs. |
| Survive the Apocalypse | ~11,500 | **Day:** go out, gather, build and reinforce a base. **Night:** zombie waves, harder each night. 11 classes bought with the kept currency. |
| Zombie Rush Survival | ~10,000 (peak 16.6k, launched May 2026) | Wave survival; little detail published. |
| Survive Zombie Arena | ~6,700 | Wave arena. |
| HUSH [Zombie Extraction] | ~3,700 | Co-op, go out, loot, extract before a 20–25 min timer. **Zombies hunt by sound: guns are loud, sneaking is quiet**, and shooting is the emergency option. |
| Project Lazarus / Zombie Uprising (pure CoD Zombies) | ~600–3,400 | Rounds, points, doors, wall guns. Well liked, but small now. |

The biggest survival hit overall, **99 Nights in the Forest** (peak 14.2 million concurrent), runs on the same split: **in the day you go out and explore; at night you defend the camp**, and the nights get harder until night 99.

**What this says:**
1. **The winners alternate going out and holding a base**, in a steady rhythm (day/night, stop/ride). Nobody sticks one half on the end of the other, the way we do now.
2. **The run has a destination and an end** (Dead Rails' bridge, 99 Nights' night 99), so it feels finished, not cut off.
3. **Classes** are in both of the top two, and they're what the kept currency buys.
4. **Pure CoD-style rounds are a smaller market now**. Our shooting feel is a strength, but the round loop alone isn't what's charting.
5. **HUSH already proves our Beacon idea**: a hunter that tracks noise, so going loud is a choice.

## 3. The new loop: hold the house by night, raid the town in the lull

Borrowed from Survive the Apocalypse and 99 Nights (go out, come back, defend), with Dead Rails' destination ending and HUSH's noise rule. Every piece already built has a job in it.

### Who you are (fixes the uniform)
Your squad was flown in to find survivors, and the Beacon brought the helicopter down. Before your first match you pick your **class**, which is also your uniform (the attire lineup moves here). Starting classes:
- **Rifleman**: starts with the AK instead of the pistol.
- **Medic**: bandages heal more and revives are faster; starts with 3 bandages.
- **Engineer**: boards windows and doors faster, and repaired boards are stronger.
- **Scout**: quieter footsteps and a slower Seen meter outside.

More classes are bought with the kept currency (see section 5).

### The match: about 6 nights, about 20–25 minutes

**Opening (under 30 s).** A short cutscene: the helicopter goes down near the house, the Beacon's lamps sweep over it, and you crawl into the house. The house radio crackles: "GET THE TOWER UP. WE'LL SEND ANOTHER BIRD." (One line, the Notice label.) Then straight into Night 1.

**Night (a wave, about 2 minutes).** The doors are barred and the zombies come at the windows. This is the shooting game that already feels good: hold, board up, earn points, revive. The Beacon stays out on the edge of town; you see its lamps through the windows.

**Lull (between waves, about 90–120 s, with a countdown).** The doors unbar and **you go out into the town**:
- **The town is the Beacon's.** Its lamps, the Seen meter, hide spots and rolls all work as they do now. **Shooting outside is loud**, and the Beacon turns toward gunfire (the HUSH rule). A few zombies stray in the streets, so you choose: shoot or sneak past.
- **Things to bring back:**
  - **Tower parts** (one or two per lull, in random buildings): Battery, Antenna, Cable, Fuel.
  - **Supplies**: boards, ammo, bandages, the occasional better gun.
  - **Points** from stray kills. Shops and the crate are in town buildings, so points buy things here too.
- **Get back before the night starts.** When the countdown ends the doors bar again. If you're still outside, the Beacon hunts you for real and the zombies are out, so you have to fight your way to a window and climb in. That's the tension the hits run on.

**The tower.** It stands on the hill behind the house. Each part you bring back gets fitted there and the tower lights up a bit more. That's the visible progress bar for the whole match, with no menu needed.

**The last night.** Once all four parts are fitted, the radio calls the helicopter. **The Beacon hears it** and comes straight for the house. The last night is the biggest zombie wave plus the Beacon tearing the house from outside (smashing from outside already works). Shooting its lens vents staggers it. Then comes the ladder and GRAB finale, which already exists.

**Or stay.** At the helicopter anyone can stay behind, and the nights keep coming. The end screen shows the night reached. Endless mode is this from the start.

### Why this tallies
- **Inside is zombies, outside is the Beacon**, and you switch every 2–3 minutes, so neither half wears out.
- **Points and supplies matter all match**, because what you bring back in the lull is what you hold the night with.
- **The helicopter comes because you fixed the tower**, and the Beacon comes because it heard it.
- **The uniform is your class**, chosen before you play.
- **Every match is different**: random part spots, random gun spots, and the Beacon roaming differently.

## 4. Numbers to start with (all go in `GameConfig.Nights`)

| Thing | Start value |
|---|---|
| Nights to fit all parts | 4 parts over about 5 nights, so night 6 is the last |
| Night length | Wave size, not time; about 2 min at night 1 |
| Lull length | 120 s on night 1, down to 90 s by night 5 |
| Parts out per lull | 1 (2 with 3+ players) |
| Shot noise outside | Each shot adds to the Seen meter if the Beacon is within 120 studs |
| Late back | Doors bar; climb in through any window that isn't boarded (yours to leave open, or not) |

## 4b. Replayability and story: what the big zombie games do on every platform

Research 31 Oct 2026 (Steam live counts, mobile revenue charts, the current Call of Duty).

| Game (platform) | Size now | What makes people replay it |
|---|---|---|
| DayZ, Project Zomboid, 7 Days to Die (Steam) | 15k–52k live each, the top 3 on Steam | Open sandbox: no story, every run tells its own. Too big for us to copy, but it shows **random runs beat a fixed script**. |
| Left 4 Dead 2 (Steam, 2009) | ~25k live, still top 4 | **The AI Director** moves enemies, items and crescendos every run, so the same short campaign (4–5 hours total) still gets played 15 years on. **The story is split into campaigns**, each a few chapters with safe rooms between them, and each ends in a rescue finale. |
| Call of Duty Black Ops 7 Zombies (console/PC) | The biggest paid zombie mode | **Every map is its own chapter with a main quest** (the story). A **super quest** opens only after you finish every map's quest. **Directed mode** walks you through the quest; **Cursed mode** and high rounds are for experts. |
| Killing Floor 2 / World War Z / Back 4 Blood (Steam) | Killing Floor 2 still top 10 | **Classes that level up** with play. Killing Floor has a trader between waves and a boss at the end. Back 4 Blood adds a **card deck** that changes each run. |
| Into the Dead: Our Darkest Days (Steam, 2025) | New hit | Shelter by night, scavenge by day, and **several different Escape Plans** to get out of the city, so each run can end a different way. |
| Last War / State of Survival (mobile) | $0.5–1.7 bn a year | Base building and heroes. The lesson for us is the ads: **over half of Last War's ads show one simple, readable mini game** that really is in the first minutes of play. |

### Our answer: split the story into chapters, and make each chapter replayable

**Split the story** the way Left 4 Dead and Call of Duty do: each **chapter is a map and a full match** (about 20–25 minutes) with its own way out. Finishing one unlocks the next and moves the story on. Nobody has to replay a cutscene they've seen, and each chapter stands alone as something to replay.

- **Chapter 1, "The Town"** (what we have): the house, the town, the tower, the helicopter. The helicopter gets you out of the town, but the Beacon has followed...
- **Chapter 2, "The Dam"**, **Chapter 3, "The Hospital"** and so on later: the same night and lull loop, a new base, a new way out and a new hunter. Each new chapter is an update (the Dead Rails and Call of Duty way to keep a game fresh).
- **The story is told in pieces you find**: radio messages and notes hidden in town buildings during the lull (Call of Duty and Left 4 Dead do this). Finding them all across every chapter opens a **final chapter** (the super quest idea).

**Make each chapter replayable**, with 5 things taken from the hits above:
1. **A director** (Left 4 Dead): each match randomises the part spots, the supply spots, which buildings are open, which streets are blocked, the Beacon's route, and one **night event** (fog, a power cut, a runner pack, a horde from one side). Random gun and zombie spots already exist, so this extends them.
2. **More than one way out** (Into the Dead, Call of Duty quests). Chapter 1 gets a second escape: **the helicopter** (fix the tower) or **the roadblock** (fuel and a battery for the army truck, then drive out with the Beacon chasing). Each needs different parts, so a run can go either way, and doing both is a badge.
3. **Classes that level up** (Killing Floor, World War Z). Each class levels with play and unlocks small perks and looks. This is the long grind.
4. **Curses** (Back 4 Blood cards, Call of Duty Cursed mode): before the match, turn on harder rules (no Guide glow, faster Beacon, one life, pistol only) for more Scrip. This replaces Nightmare as the expert path.
5. **The scores**: best night survived in Endless, fastest escape, escapes per class, all on leaderboards (solo and squad).

## 5. Between matches (the reason to come back)

1. **Kept currency** (call it Scrip) from nights survived, parts fitted and escaping. Escaping pays most.
2. **Classes**: 4 to start with, more bought with Scrip. This is the main thing to buy (proven by both top charting games).
3. **Weapon mastery**: kills level each gun and unlock camos.
4. **Nightmare and Endless** unlock on the first escape (already built).
5. **Best night and fastest escape** leaderboards.
6. **Later:** new towns, each with a different way out (a boat, a train) and a different hunter.

Monetisation stays as the brief says: skins and one revive token, never pay to win. Classes can also be sold for Robux, but always earnable too.

## 6. What changes in the build

| Area | Change |
|---|---|
| `MatchServer` | Night and lull cycle replaces "breakout at wave 3": doors bar and unbar, lull countdown, parts spawn per lull, tower fitting, the last night, the stay option. |
| Doors | The house doors bar at night and open in the lull (no more one-time blow-open). |
| Beacon | Already roams; new: turns toward outdoor gunfire, and walks to the house on the last night. |
| Town | Parts and supply spawns in buildings; a few stray zombies in the streets during the lull. |
| Tower | New model on the hill with four sockets that light up. |
| Guns | Floor guns in the house cut to one random pick; better guns come from town or the crate. |
| Classes | The attire lineup becomes the class pick at first join; class perks in `GameConfig.Classes`. |
| HUD | Uses existing spots: the Wave label becomes "NIGHT 3" / "LULL 0:45", and one small line shows "PARTS 2/4". No new overlays. |
| Opening | Helicopter crash cutscene on the existing EvacPath and RescueClient pieces. |

## 7. Build order

1. **Night and lull cycle + doors that bar and unbar + countdown.** This alone fixes "two games glued".
2. **Tower and parts** (placeholder part models). Then playtest the whole loop end to end.
3. **Beacon hears gunfire, last night at the house.**
4. **Classes from the attire lineup** + Scrip.
5. **Opening cutscene**, mastery, leaderboards.

6. **Director randomising** (night events, blocked streets, open buildings).
7. **Second escape** (the roadblock and the army truck).
8. **Curses**, then **story pieces** (radio messages and notes).
9. **Chapter 2** as the first big update.

Steps 1–3 fix "too short" and "doesn't tally". Steps 4–8 make it replayable. Step 9 grows it.

## Sources (31 Oct 2026)
- rblxdb live zombie ranking: https://rblxdb.com/best-roblox-games/zombie
- Survive the Apocalypse loop: https://rowatcher.com/games/9098570654/survive-the-apocalypse and https://www.player.one/roblox-survive-apocalypse-codes-march-2026-can-you-outrun-zombies-your-friends-162448
- Dead Rails loop: https://www.sportskeeda.com/roblox-news/how-play-dead-rails and https://www.pocketgamer.com/roblox/how-to-beat-dead-rails
- HUSH loop: https://allthings.how/hush-zombie-extraction-on-roblox-the-quarantined-town-looter-explained/
- 99 Nights: https://devforum.roblox.com/t/creator-spotlight-the-story-behind-99-nights-in-the-forest/4036940 and https://www.exitlag.com/blog/99-nights-in-the-forest-roblox/
- Zombie Rush Survival stats: https://rotrends.com/game/10138624079
- Pure CoD-style ratings and players: https://robloxden.com/best-games/genres/survival
- Steam live zombie counts: https://coilr.org/most-played/zombie and https://wan.gg/charts/tags/1659/zombies
- Mobile zombie revenue: https://www.blog.udonis.co/mobile-marketing/mobile-games/top-grossing-mobile-games
- Last War ads: https://naavik.co/digest/how-last-war-is-winning-the-4x-game/ and https://appgrowing.net/blog/en/how-survival-ads-turn-immediate-danger-into-a-base-building-payoff/
- Black Ops 7 Zombies modes and quests: https://www.gameswelt.de/sonstiges-aus-der-welt-der-spiele/kampagne/black-ops-7-zombies-maps-every-main-quest-its-rewards-and-how-hard-it-is-335155 and https://deltiasgaming.com/?p=355204
- Left 4 Dead director: https://gamespot.com/articles/what-made-left-4-dead-special-according-to-the-devs-making-games-like-it/1100-6503996/
- Into the Dead: Our Darkest Days: https://faq.pikpok.com/hc/en-nz/articles/45293877816089-Into-the-Dead-Our-Darkest-Days-FAQ
