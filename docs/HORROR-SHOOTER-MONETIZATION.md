# Last Light: the monetization plan (1 Nov 2026, night)

The owner's ask: "very strong monetization that even when the game is 30 to 40 CCU we can make a lotta robux. Not
monetization spam but a well planned one." This is the plan, backed by a simulation
(`last-light/sim/store_sim.py`, results in `store_results.json`) built on the same 30-day player model as the
master plan's money model (`money_sim.py`, `mode_sim.py`).

**Where it stands:** nothing has been created on Roblox yet (creating items needs the owner signed in to Creator Hub
in the browser pane). The code already handles 1 game pass (VIP) and 6 developer products (Starter Pack, Revive, the
four classes), with every id still 0, so no row shows yet.

## 1. What the simulation says

Every catalogue gets the same players (the installs a day that give the launch set 35 CCU). "Floor" scales spending
so 3 % of all installs ever pay, which is realistic for Roblox; the model's own rate is about 9 %, so read it as the
ceiling. The creator keeps 70 % after Roblox's fee.

| Catalogue | Robux per install | Pay at all | Day-7 retention | CCU from that traffic | Creator's Robux a month (floor to model) |
|---|---|---|---|---|---|
| Today's code (VIP, starter pack, 4 classes) | 9 | 5.4 % | 5 % | 34 | 34k to 104k |
| **Launch set, no new art** (section 3) | **23** | 9.2 % | 5 % | 35 | **86k to 261k** |
| Launch + dog breeds, camos, Night Pass | 26 | 9.0 % | 6 % | 37 | 98k to 299k |
| The same, pushed hard (pop-ups every death, shop after every match) | 29 | 11.8 % | **2 %** | **28** | 109k to 331k at first, then less (below) |
| Launch + cosmetics + a **social hub lobby** | **55** | 10.8 % | **10 %** | **54** | **209k to 637k** |

- **Spam loses.** It earns 11 % more per player but cuts day-7 retention by two thirds and playtime by a quarter.
  Roblox recommends games on engagement, so its traffic shrinks. With that feedback it lands at about 23 CCU and 88k
  a month on the floor, against 38 CCU and 103k for the honest version.
- **The hub is the biggest lever.** Seeing other players' dogs and camos every visit, and squading up with them, more
  than doubles spending per player and adds about half again as many concurrent players from the same traffic. It's
  the master plan's "show it on other players before selling it" rule, measured.
- **Rewarded ads** (watch an ad to get up instead of paying) add only about 70 Robux a day at 35 CCU, because Roblox
  shows ads only to players 13 and over. They're worth having because they cost nothing and annoy nobody.

## 2. The rules, so it never feels like spam

1. **Sell at the moment of want, never in a fight.** The only in-match offers are on the death screen and the squad
   wipe screen, once per match each.
2. **One button per moment.** No stacked offers, no second chance pop-up.
3. **One pop-up, ever:** the Starter Pack, once, after the first escape or the third death, on a real 48-hour timer.
4. **Show it on others first.** Cosmetics sell when a teammate has one (flashlight colours at night, dogs, camos),
   later in the hub.
5. **Anything with a stat is also earnable with Scrip.** Robux buys time, looks and rescues. If PvP ever comes, paid
   stats stay out of it.
6. **No paid random items at launch.** Direct purchases only: no loot boxes, so no odds tables and nothing that reads
   as gambling.
7. **Every row says exactly what you get and what it costs.**

## 3. The launch catalogue: 3 game passes + 14 developer products

Built in code for both places (rows stay hidden until each id is set). Share is each item's part of the launch set's
Robux in the sim.

| # | Item | Type | Robux | What you get | Sold where | Share |
|---|---|---|---|---|---|---|
| 1 | VIP | Pass | 299 | +20 % Scrip, gold [VIP] in chat, gold name, the gold flashlight beam | SHOP | 5 % |
| 2 | Double Scrip | Pass | 399 | ×2 Scrip from every match and mission (stacks with VIP) | SHOP; the payout screen shows "×2 WITH DOUBLE SCRIP" | 15 % |
| 3 | Flashlight Colours | Pass | 149 | Six beam colours your squad sees at night | SHOP, and a teammate's coloured beam | 3 % |
| 4 | Starter Pack | Product, once | 99 | 2,500 Scrip (a class's worth) and 3 revives | The one pop-up (after the first escape or third death), then 48 h in the SHOP | 18 % |
| 5-8 | Hunter, Firefighter, Marksman, Demolition | Product, once each | 199 each | The class (also 2,500 Scrip) | CLASSES page | 22 % |
| 9 | All Classes | Product, once | 599 | All four (saves 197) | CLASSES page | 12 % |
| 10 | Revive | Product | 25 | Get up where you fell, once per match | Death screen, only when no teammate can reach you; 13+ can watch an ad instead | 4 % |
| 11 | Revives ×5 | Product | 99 | Five revives to keep | SHOP, after your first revive | 4 % |
| 12 | Squad Revive | Product | 99 | When the whole squad (2+) is down from night 3, everyone gets up; once per match | The squad-wipe screen | 2 % |
| 13 | Squad Boost | Product | 79 | ×2 Scrip for everyone in your next match; the HUD line names you | SHOP and the payout screen | 2 % |
| 14-17 | Scrip 1,000 / 2,750 / 6,000 / 13,000 | Product | 99 / 249 / 499 / 999 | +0 / +10 / +20 / +30 % bonus | SHOP; "NEED 600 SCRIP" offers the smallest pack that covers it | 13 % |

Multipliers stack (VIP ×1.2, Double Scrip ×2, Premium ×1.1, Squad Boost ×2) but are capped at **×4** so Scrip keeps
its value.

## 4. Free levers (no item to buy)

- **Roblox Premium:** +10 % Scrip for Premium members, and a SHOP row that opens Roblox's Premium prompt. Premium
  members' playtime earns Premium Payouts.
- **Group reward:** 500 Scrip once for joining the group (needs the group id).
- **Daily streak:** 7 days (100, 150, 200, a revive, 300, 400, 750 Scrip). The sim counts it as part of the launch
  set's retention.
- **Rewarded ads:** watch to get up, for players 13 and over, when Roblox has an ad to show.
- **Private servers:** 100 Robux a month, set by the owner in Creator Hub (Monetization, Private Servers).
- **Subscriptions** (monthly, real money) are available to this game. Worth adding once the Night Pass exists, as
  "Last Light+": daily Scrip, the season's premium track, a monthly cosmetic.

## 5. Next, with art: cosmetics and the season (+14 % Robux, better retention)

- **Dog breeds:** 6 looks for the police dog (Husky, Doberman, Malinois, Rottweiler, Golden, a white "Ghost"). 149
  Robux or 6,000 Scrip each.
- **Gun camos:** direct purchases, 149 Robux or 3,000 Scrip each, by gun.
- **Night Pass:** a 6-week season, 30 tiers, free and premium tracks, 399 Robux; tier skips 49 each.

## 6. After that: the social hub lobby (the biggest single lever)

The master plan's hub (squad pads, the kennel, the armoury wall, boards). In the sim it doubles Robux per player and
adds about half again as many concurrent players.

## 7. The economy

- **Earning:** about 400 Scrip for a full Defend match and 900 for a campaign run (`GameConfig.Scrip`,
  `GameConfig.War.Campaign.Reward`), so roughly 1,500 to 2,500 Scrip an hour.
- **Spending:** a class costs 2,500 Scrip (2 to 3 hours of play). Later, breeds cost 6,000 and camos 3,000, which
  gives a long grind that Robux shortens.
- **The exchange rate:** Scrip packs give about 10 Scrip per Robux. Direct purchases (a class for 199) are always the
  better deal for one item, and packs are for "I'm a little short".

## 8. Build order

1. **Code, both places:** `GameConfig.Store` v2 with every item above, StoreServer grants and multipliers, death-screen
   and squad-wipe buttons, flashlight colours, Premium bonus, group reward, daily streak, rewarded ads, SHOP pages
   (authored rows cloned in Edit).
2. **Owner signs in** to Roblox in the browser pane. Then I create the 17 items at the prices above and paste the ids
   into both places.
3. **Owner sets** private servers to 100 Robux a month (or says I may) and gives the group id.
4. **After launch:** read the first week's analytics (conversion per item, retention) and replace the sim's guesses.

## 9. What the simulation can't know

The appeal of each item, how many players can spend Robux and the value of an ad view are design assumptions. The
model is for comparing catalogues. The 3 % floor is the safer planning number until real data arrives.
