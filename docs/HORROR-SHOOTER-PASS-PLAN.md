# Last Light: the big pass (plan, 31 Oct 2026)

What the owner asked for, what I found in the place, and how I'll build it. Nothing here is built yet.

## What's actually wrong (found in the code)

| Problem | Cause |
|---|---|
| Your friend looks like a normal avatar with no gun | The gun only exists on your own screen (`GunClient` viewmodel). Nothing is put on the character, and no pose or animation plays on the body. Other players only get a tracer that starts from your head (`GunClient` line 1122). |
| Zombies attack you inside a dumpster | `MobAI.nearestPlayer` never checks the `Hiding` or `Inside` attributes. Only the Beacon reads them. |
| The mobile Jump button does nothing | Roblox's own control script writes `Humanoid.Jump` every frame from its (hidden) jump button, so our one-frame `humanoid.Jump = true` is wiped before physics sees it. |
| Fall damage shows zombie claw marks | `FallDamage` hurts through `PlayerHealth.Damage`, which always fires `PlayerHit`, and the client always draws claws for it. |
| Jumping out of a window skips the game | Zombies only come from the house windows and the waves only matter inside. Outside there's nothing until breakout, because the Beacon sleeps until then. |
| Only one match per server | `MenuServer`: the first player to press PLAY picks the mode and everyone else joins that run. There's no solo, no team choice and no invites. |

## 1. Teammates you can see (the most serious one)

How shooters on Roblox do it, and what I'll build:

- **The gun on the body.** When you equip a gun, the server welds a third-person copy of it to your right hand. Because the server does it, everyone sees it, and it switches when you switch.
- **The pose.** A new client script, `TeamPose`, poses every *other* player each frame on top of their walk animation: both hands on the gun, rifles at the shoulder, the pistol held out, aimed up and down with where they're looking.
  - Where they're looking is sent about 15 times a second on an unreliable remote (`Look`). It's smoothed on the other end, so it doesn't jitter.
  - The states it shows come from attributes that mostly exist already: aiming, sprinting (gun lowered), reloading (hand to the magazine), firing (kick), downed (pistol only, on the ground), bandaging and hiding.
- **Shots come out of their gun.** Tracers and muzzle flashes start at the muzzle of their world gun, not their head.
- **Your own body** gets the same pose in any third-person moment (cutscenes, the ladder climb, the dumpster camera).

Procedural posing is better here than uploaded animations: it follows aim pitch exactly, needs no publishing, and covers every gun.

## 2. The roll is removed (owner, 31 Oct)

The roll is removed: the C, Left Ctrl and gamepad B binds, the touch Roll button, and the `Rolling` / `RollUntil` reads in `GunClient` and `BeaconServer`. Gamepad B stays as revive only.

- On a phone you hide by tapping the Hide prompt next to the spot. The prompt's tap area gets bigger, and it shows from a little farther away, so a tap close to the spot is enough.

## 2b. Shots must land instantly (owner, 31 Oct)

**Why it feels late:** every reaction after a hit is done on the server.

- **Kills:** a kill waits for your shot to reach the server, then for a 0.06 s freeze, and only then does the server turn the body into a ragdoll and throw it. The throw then travels back to your screen, where Roblox smooths it out over another tenth of a second or so.
- **The result:** on a normal connection the body moves about 0.25–0.4 s after you fire. Shotgun knockback on a zombie that's still alive has the same delay.

**The fix** (client-side prediction, the way Call of Duty and Left 4 Dead hide lag):

- **Kills show on your screen the same frame you shoot.**
  - Your client works out the damage with the same numbers as the server (`GameConfig`), against the zombie's health, which is copied to every player.
  - If your shot kills it, your screen ragdolls and throws the body at once.
  - Bodies become client-side. The server hides the dead zombie, and each screen throws its own copy: the shooter's at once, everyone else's when the server says so.
  - If the server disagrees (very rare, say two players finished the same zombie), the body is still dead, just thrown from the other player's shot.
- **Knockback on living zombies shows at once:** your client snaps the zombie's body back (a pose kick on its joints) on the same frame. The server push follows and lines up with it.
- **No more freeze on the server:** the 0.06 s freeze moves to your screen only (a hit-stop), where it reads as weight instead of lag.

**Bullets from the gun:**

- **Your tracers** start at the gun's Muzzle attachment, but the position is read before the viewmodel has moved that frame. So when you turn or move, the tracer starts where the gun *was*. Some Toolbox guns also have their Muzzle in the wrong place (the same import problem as the sideways AimPoints).
  - **Fix:** fire after the viewmodel is placed for that frame, and check and move each gun's Muzzle by screenshot (Pistol, Shotgun, AK, Sniper).
- **Teammates' tracers** start from their head: fixed by section 1 (they'll come from the world gun's muzzle).

**Shotgun spread you can see:** the pellets already spread on your side, but each pellet's tracer and hit is too small to read. Fixes:

- each pellet gets a short, bright tracer;
- each pellet that hits a zombie throws its own green puff, and the zombie jerks back from the whole spread;
- each pellet that hits a wall leaves its own mark, so the spread pattern stays on the wall;
- at close range the burst throws the body visibly harder.

## 3. Solo or team, joining matches, inviting friends

**How it works:** the current place stays one place, but it runs in two kinds of servers.

- **Lobby servers** (normal public servers) show the menu over the town road with the Beacon walking. No match runs there.
- **Match servers** are private ("reserved") servers made just for one match, with at most 4 players. The game knows which kind it is when it starts.

**The menu:** PLAY opens two choices.

- **SOLO.** It makes a new match server and sends you there alone. Nobody else can join.
- **TEAM.** It shows two options.
  - **JOIN A MATCH**: drops you into a team match that's already running and has a free slot. If there isn't one, it makes a new open match, and others fill your free slots as they come.
  - **PLAY WITH FRIENDS**: makes a new match for your friends only and opens Roblox's invite screen. You go in right away; there's a 20 s wait before wave 1 so friends can arrive.
- **Inside a team match**, the settings button also has **INVITE** and **LEAVE**.

**The details, so there are no loopholes:**

- **Finding open matches:** each match server lists itself every 10 s in a shared list (MemoryStore), with its mode, wave, player count, team members and whether it's open. An entry that isn't updated expires in 30 s, so dead servers vanish.
- **When you can join:** you can join until the doors break out. After that the match is closed, because joining in the middle of the escape is pointless.
  - A late joiner waits for the next break between waves (or spawns at once if one is on).
  - They get the pistol and catch-up points (500 + 250 for each wave already played).
- **Two players racing for the last slot:** whoever arrives second is sent back to the lobby with one small line, "MATCH FULL". Then quick-join tries again.
- **Invites:** the invite carries the match's code (Roblox's invite "launch data"). Your friend lands in a lobby server, which reads the code and sends them straight on into your match if it's still open. If it's closed, they stay in the menu with one small line.
- **Following a friend:** Roblox's "Join" button can't follow anyone into a private server. Instead the lobby checks the open-match list for your friends and shows a **JOIN [name]** row in the Team page.
- **Teleports that fail:** they're retried 3 times, then you go back to the menu. The loading screen between servers is our own dark screen.
- **Saves:** your profile is saved before every teleport, and loading waits for that save, so unlocks and the uniform are never lost or doubled.
- **After a match:** you stay with your team. **PLAY AGAIN** restarts in the same match server, and the menu's SOLO or TEAM sends you to a new one. An empty match server shuts itself down.
- **Studio:** Roblox doesn't allow teleports in Studio, so in Studio the match runs in the same server as today. The real test needs a published version.
- **You'll need to set Max Players to 4** in Game Settings. It's a one-time setting; I can't change it from a script.

## 3c. Owner decisions (31 Oct, after the plan)

- **Solo and Team are both fully open**, including joining strangers, from the first run. The lock in 3b below is dropped.
- **Crouch and slide replace the roll.** Ctrl (gamepad B, the touch Crouch button):
  - standing still or walking: crouch (toggle; lower camera, slower, quieter for the Beacon);
  - sprinting: a slide that ends in a crouch.
  - Teammates see both through `TeamPose`. The body pose is procedural, so no animation needs publishing.

## 3b. The first run is the recruitment story, so is it solo only? (superseded by 3c)

**My answer: no, but strangers come later.**

- **Why not solo only:** your own playtest was you and a friend. The main way Roblox games grow is a friend inviting a friend. If a new player can't play with the friend who brought them, they leave, and that's the most valuable player you'll ever get.
  - The big co-op horror hits (Doors, Pressure, Evade) all let friends in from the first run.
- **The rule:**
  - **Before your first escape (the recruitment story):** you can play SOLO, or TEAM with friends you invite or whose match you join. **JOIN A MATCH (strangers) stays locked** with one small line: "ESCAPE ONCE TO UNLOCK".
  - **Why lock strangers:** a stranger's match might be at wave 6 when a new player drops in, which ruins the story for them. And veterans don't get a confused newbie dropped into their run.
- **The story still plays for everyone in a team:** the reveal, the helicopter and the uniform pick are already shown per player, and the uniform pick only appears for players who haven't picked. A veteran playing with a new friend just sees the story again, short.
- **SOLO is the default choice** for anyone who hasn't escaped yet.

## 4. Leaving the house must not save you

Your idea, checked against how Call of Duty Zombies and Left 4 Dead handle it. I'm keeping it, with three changes so it holds up:

1. **The Beacon is out from wave 1.** It roams the town from the start, and the reveal moves to the start of the match: a 4 s look at it through the upstairs window as it walks the far street. Everyone learns the threat on day one, and anyone who jumps out runs into it.
   - Its lamps still can't see indoors. The house itself is protected, and it can't smash the defend house before the breakout, or a reckless player could get the whole team killed.
2. **Zombies are in the streets every wave.** Part of each wave spawns in town and walks to the house. Anyone outside is the nearest target, and outside zombies notice you from farther away (no walls).
   - Zombies don't smash other houses. The Beacon already does, and 20 zombies tearing buildings apart would kill the frame rate on phones.
   - Hiding spots work from wave 1, not only after the breakout.
3. **Every zombie must die before you can leave.** The breakout becomes the **final wave**: a fixed number of town zombies (count on the HUD). The helicopter only comes in once that count hits 0, and nothing spawns after that. Then the Beacon hunts you to the ladder, as now.
   - A dumpster camper can't win this way. While they hide nothing dies, so the helicopter never comes.
   - Endless mode is unchanged.

## 5. Hiding vs zombies (your new message)

- **Inside a dumpster:** zombies can't see, target or hit you. The ones chasing you lose you, search where you were for about 4 s, then wander off.
  - **Stalling:** you can stay in for 40 s at most. Then you climb out on your own, and you have to wait 20 s before you can climb back in. Without this, a solo player could hide forever and the wave would never end.
- **Hiding behind a car (open ground):** the Beacon can't spot you, but a zombie within 10 studs that can see you notices you. Firing from cover gives you away to zombies for 2 s, the same as with the Beacon.

## 6. Settings button

A small gear at the top right of the menu and during a match, flat dark with amber like the rest, with labels only and no explainer text. Settings are saved to your profile.

- **Look sensitivity** and **aim sensitivity**.
- **Gyroscope** (only on devices that have one): on or off; when it works (always, or only while aiming); sensitivity; invert up/down.
- **Volume**: master and effects.
- **Camera shake**: full or reduced.
- In a team match: **INVITE** and **LEAVE MATCH**.

## 7. A good, accurate gyroscope

How the best gyro aiming works (Jibb Smart's GyroWiki, used by Fortnite, Splatoon and Steam Input), applied here:

- **It works like a mouse, not a joystick.** Each frame the phone's rotation since the last frame (from `UserInputService:GetDeviceRotation`) turns the camera by the same angle times the sensitivity. At 1.0, turning the phone 10° turns the view 10°. That's what "accurate" means here.
- **Axes:** "local space" is the right choice for a phone (player space is meant for controllers). Tilting the phone up looks up, and turning it looks sideways. Holding the phone in landscape left or right is detected and the axes are flipped to match, so neither way comes out backwards.
- **No drift:** while the phone is very still, the leftover sensor drift is measured and subtracted. No "hold still" screen is needed.
- **No shake:** very small movements (hand tremor, under about 2° per second) are softened smoothly. Real movements get no smoothing at all, so there's no lag.
- **Pauses:** the gyro pauses in menus, cutscenes, while dead, and when the app loses focus. It restarts cleanly, so the view never jumps.
- **With touch:** it adds to the touch-drag look, through the same pitch limit.
- **Testing:** Studio has no gyroscope, so a debug attribute feeds fake rotation for testing there. The real feel check is on your phone.

## 8. Smaller fixes and feel

- **Mobile Jump:** pressing the button now makes the character really jump (a state change on the ground, held while the finger is down), and it still leaves a dumpster or hiding spot.
- **Fall damage gets its own effect** instead of claws: a hard downward camera thump, a short grey pulse at the screen edges, and a dull thud and grunt.
- **Feel moments** (no damage numbers, no new panels):
  - **Headshot:** a sharper crack and a tiny 50 ms camera hitch.
  - **Headshot kill:** the head pops with a deeper crunch.
  - **Shotgun double kill:** a heavier crunch.
  - **The last zombie of a wave:** the sound dips briefly, then a low sting plays.
- **Ammo text:** one small, soft plain-text line under the crosshair, with no frame, that fades in and out (authored in `StarterGui.HUD`).
  - "reload" when the magazine is empty but you have spare ammo.
  - "out of ammo" when you have nothing left.

## Build order

1. **Shots land instantly** (prediction, client-side bodies, muzzle fix, readable shotgun spread) and **remove the roll**.
2. **The quick fixes:** dumpster and zombies, mobile Jump, the fall damage effect, the ammo text, the feel moments.
3. **Teammates you can see** (the gun on the body, `TeamPose`, the `Look` remote, tracers from the muzzle).
4. **The settings button and the gyroscope.**
5. **The open-town threat** (the Beacon from wave 1, street zombies, the breakout as the final wave, the helicopter only after a full clear).
6. **Solo, team, joining and invites** (the lobby and match server split, the open-match list, invites, PLAY AGAIN, strangers locked until the first escape).

Every step is backed up first in `ServerStorage._Backups` (suffix `_2026-11-01_before<Step>`) and tested in Studio Play.

## What can and can't be checked

- **In Studio:** everything in steps 1–4, and step 5's menu flow (in-place fallback). For the teammate pose, I'll drive a dummy player with the same attributes so I can screenshot it.
- **Needs a published version and two real players** (you and your friend): the real teleports, invites, quick join, and how a teammate looks across the network.
- **Needs your phone:** the gyroscope feel and the Jump button.
