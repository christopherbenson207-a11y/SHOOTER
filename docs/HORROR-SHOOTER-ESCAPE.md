# Last Light: the escape (spec, 31 Oct 2026)

The owner's idea: once you've held the house, a helicopter comes for you and the Beacon tries to stop you getting on it. You escape, and that unlocks the other modes. This file fills in everything the idea didn't say, and every number here lives in `GameConfig` so it can be tuned.

## The whole match, start to finish

1. **Menu.** PLAY starts the chosen mode. Before your first escape only **Defend** is open. **Nightmare** and **Endless** show as locked, with one small line: "ESCAPE ONCE TO UNLOCK".
2. **The house (waves 1–3).** You spawn upstairs.
   - Guns lie on random spots on both floors, and the sleeping zombies stand in random downstairs rooms, so every run is different.
   - Kills spill glowing amber shards. You walk over them to collect the points.
   - Points buy debris, guns, bandages and the crate.
3. **Break out (from wave 3).** Hold E (or tap the prompt) on the front or back door. The doors blow open, and then:
   - **Reveal** (`Breakout.RevealTime`, 5 s): the camera leaves your eyes and finds the Beacon down the street. It stands up, its lamps flare, and it smashes into a house. You can't move and nothing can hurt you; zombies don't spawn yet.
   - Then you're back in first person, with a red flare burning at the **landing zone** (`Map.Extraction.Zone`). The top-centre HUD reads `HELI 45` and counts down, and a Guide line points the way.
4. **The town.** Zombies keep coming, and the Beacon roams the streets. It walks up and down the streets, scanning with two lamps that move on their own. It never passes through buildings: it steers round them, walks up to one and smashes it from outside (walls and roofs fly off, then lie as rubble). If its Seen meter fills, it runs at you, grabs you and lifts you to its lamps before the dark. Hide spots and rolls work as before.
5. **The pickup** (`Breakout.Evac`).
   - **Inbound (10 s before):** you hear rotors, then the helicopter comes in low over the rooftops with its searchlight on the zone. The HUD says `HELI INBOUND`.
   - **Hover (9 s):** it hangs about 44 studs over the zone and drops a rope ladder. The Beacon has heard it: it stops whatever it was doing, and **both lamps go to the zone**, sweeping it. It walks, then runs, toward the zone from the far side of town. If it was far away, it comes over the rooftops.
   - **It pulls away (10 s):** once the hover ends (or the Beacon gets within reach), the pilot doesn't wait. The helicopter crawls off down the road at a running pace, climbing a little, with the ladder swinging. You have to chase the ladder.
   - **The grab:** when the ladder's foot is within reach, a big **GRAB** button appears at the bottom centre (tap on a phone; E, Space or a click on PC; X on a gamepad). Press it and your character leaps onto the ladder. A third-person shot shows you climbing up with the helicopter moving, the Beacon's lamps below, and then you sit in the open door. Nothing can hurt you once you've grabbed.
   - **Everyone's aboard:** the helicopter leaves at once.
   - **Leaving:** it climbs away over the town. Anyone still on the ground is **left behind**: the Beacon takes them.
6. **The escape cutscene** (everyone watches):
   - Shot 1, from the door looking down: the Beacon has reached the road below. It **reaches up** at the helicopter, screaming, with its lamps blazing into the cabin.
   - Shot 2, wide and side-on: the helicopter climbs over the rooftops while the Beacon chases along the street below and falls behind.
   - Then a fade to black.
7. **After.**
   - **Escaped:** one line, "YOU ESCAPED", plus escape points. The first time, a second line comes after it: "NIGHTMARE AND ENDLESS UNLOCKED". Then the one-time uniform pick if you've never had it, then the menu.
   - **Left behind:** the normal "YOU FELL" screen.
   - The unlock is saved per player (`Profile.Escaped`).
   - If nobody grabbed the ladder, the run ends as lost: "THE HELICOPTER LEFT".

## Modes (unlocked by escaping once)

| Mode | What changes |
|---|---|
| Defend | The normal run. |
| Nightmare | Zombies have ×1.5 health and come in ×1.3 numbers, runners from wave 2, and the breakout opens from wave 5. The Beacon's Seen meter fills ×1.4 as fast, and its lenses take ×1.5 to break. |
| Endless | No breakout and no helicopter. The doors open at wave 5, waves never stop, and the end screen shows the wave you reached. |

- **One match per server:** the server runs one match at a time. The first player to press PLAY while the server is waiting picks the mode. Anyone joining mid-run joins that mode, and the menu's PLAY tag shows the mode actually running.

## Rules carried from the owner

- No damage numbers. No big overlay text: one small line at a time, using the existing Notice label.
- The Beacon never lasers you; its lamps are eyes.
- Mobile parity: GRAB is a big tap target. Phones get the same `Seen.Touch` slowdown as before.
- No gore on screen in cutscenes. Being taken is the black-out, as before.

## Where it lives

- `ReplicatedStorage.Shared.EvacPath`: one shared timeline. The helicopter's CFrame and the ladder's foot are worked out from server time, so every client and the server agree with no streaming of parts.
- `ServerScriptService.MatchServer`:
  - the reveal, the flare and the countdown;
  - `Remotes.Evac` "Grab" (validated against EvacPath), the climb (the server moves the character up the ladder so teammates see it), the ride, early departure, and left-behind;
  - the modes.
- `StarterPlayerScripts.EvacClient`: draws the helicopter and ladder, plays the rotor sound, shows the GRAB button, and runs the reveal and climb cameras.
- `StarterPlayerScripts.RescueClient`: the escape cutscene, which now uses the live helicopter.
- `ServerScriptService.BeaconServer`: roaming, smashing buildings (they are rebuilt each match), the reveal smash, the evac hunt and the reach.
- `Shared.BeaconRig`: the new "Reach" pose.
- `Profile` (Escaped) and `MenuServer`/`MenuClient` (locked modes).
