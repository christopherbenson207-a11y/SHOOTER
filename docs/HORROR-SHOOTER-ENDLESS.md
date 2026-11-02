# Last Light: Endless mode (1 Nov 2026)

The owner's reference: BaronVonGames, "This game is like Roguelike COD Zombies But BETTER"
(https://youtu.be/tDO-QSw2YrY), which is **Mortuus** by Hamuno (Steam demo, 14 Oct 2026). Its loop:
survive the round, spend your points, **pick one upgrade from a draft after every round**, perk
machines, a Gun Ascension altar, doors and a mystery box, a **new map every run** ("you learn the
game, not the map"), special enemies later (Juggernaut, Lope, Skitter), a hidden ritual boss.

We take the concept, not the game: our house, our zombies, our names.

## What Endless is now

Endless is the Defend house with Call of Duty Zombies rounds and a roguelike twist. No nights, no
breakout, no helicopter: rounds until everyone falls. Unlocked by escaping once (unchanged).

1. **Rounds.** Wave n sends Count(n) zombies through the windows; the doors burst open at a round
   drawn fresh each run (`Endless.OpenAtWave`, 6 to 10). Zombie dog packs come from round
   `ZombieDogs.FromNight` (already wired in DogServer). Dead players come back at the next
   intermission, as in Defend. When nobody is left the run ends on the round reached.
2. **The relics (the upgrade draft).** When a round is cleared, three relics appear on floor sigils
   on the floor the squad is standing on: a candle on a glowing ring, each a different colour.
   Everyone sees the same three. Hold E on one and it is yours for the run; your sigils then go
   dark for you (RelicClient), the others still see theirs. They vanish when the next round
   starts, so the pick is made in the intermission (`Endless.Intermission` 18 s instead of 12).
   One HUD line when they appear: CHOOSE A RELIC.
3. **The relic pool** (`GameConfig.Endless.Relics`; stacks, lasts the run, read as player
   attributes by the systems that already exist):
   | Relic | Effect | Where it lands |
   |---|---|---|
   | Iron Rounds | +15 % gun damage | GunServer.checkHit, `RelicDamage` |
   | Headhunter | +50 % headshot bonus | GunServer.checkHit, `RelicHead` |
   | Thick Skin | +25 max health, now and every life | PlayerHealth, `RelicHealth` |
   | Lead Belly | 15 % less damage taken (cap 60 %) | PlayerHealth.Damage, `RelicArmor` |
   | Fast Mend | health comes back 30 % sooner (cap 75 %) | PlayerHealth.step, `RelicRegen` |
   | Scavenger | +30 % points | Points.Add, `RelicPoints` |
   | Second Wind | +1 self-revive this life and the next | character SelfRevives, `SelfRevivesStart` |
4. **Learn the game, not the house.** Every Endless run: the guns lie on new spots (already),
   the sleepers stand on new spots (already), the debris costs are drawn from
   `Endless.DebrisCost` (500 to 1000, in 50s), the doors open at a different round, the sigils
   land on new spots.
5. **Twists.** From round 4, a round has a 35 % chance of one twist, called out on the one HUD
   line as it starts: RUNNERS (every zombie runs), THICK HIDE (+40 % health, hits pay double),
   SWARM (twice as many, half the health). `Endless.Twists`.
6. **Best round** is saved on the profile (`Profile.Count` style: `EndlessBest`), for a board later.

## Code

- `ServerStorage.Modules.Relics` (new): the pool, `Offer(floors)`, `Clear()`, `Reset(player)`,
  `Apply(player, name)`. Builds the sigils (parts, no UI) in `workspace.Relics`.
- `StarterPlayerScripts.RelicClient` (new): hides the sigils for a player who has picked this round.
- `MatchServer`: Endless branch of the run loop (relics after each round, the longer intermission,
  the twists), per-run door round and debris costs, `Relics.Reset` at run start and end.
- `GunServer`, `PlayerHealth`, `Points`: read the relic attributes.
- `GameConfig.Endless`, `GameConfig.Modes.Endless.Relics = true`.

Backups: `ServerStorage._Backups.*_2026-11-01_beforeEndless`.

## Not done (next)

- A Gun Ascension altar (feed a gun points, pick how it grows) and perk machines as world objects.
- Special enemies of our own for late rounds (a crawler on the ceiling, a charger) need Blender.
- A best-round board in the hub.
