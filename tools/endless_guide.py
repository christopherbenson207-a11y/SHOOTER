"""Write docs/ENDLESS-MCP-BUILD.md: the Endless reference place as one Markdown file a local
Claude session can build in Studio with MCP (no Rojo). It holds the setup, the instance tree,
a play-test checklist and the full source of every script, read from src/endless so it is always
the code in the repo.

Usage: python tools/endless_guide.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src", "endless")
OUT = os.path.join(ROOT, "docs", "ENDLESS-MCP-BUILD.md")

CLASS = {".server.luau": "Script", ".client.luau": "LocalScript", ".luau": "ModuleScript"}

# Build order: folders, then modules (shared first), then the scripts that require them.
ORDER = [
    "ReplicatedStorage/Endless/Config",
    "ReplicatedStorage/Endless/Net",
    "ReplicatedStorage/Endless/Sfx",
    "ReplicatedStorage/Endless/Weapons",
    "ReplicatedStorage/Endless/GunModel",
    "ServerStorage/Endless/Util",
    "ServerStorage/Endless/HouseLayout",
    "ServerStorage/Endless/HouseBuilder",
    "ServerStorage/Endless/Economy",
    "ServerStorage/Endless/Survivors",
    "ServerStorage/Endless/Arsenal",
    "ServerStorage/Endless/Windows",
    "ServerStorage/Endless/Horde",
    "ServerStorage/Endless/Doors",
    "ServerStorage/Endless/Randomizer",
    "ServerStorage/Endless/WallBuys",
    "ServerStorage/Endless/Perks",
    "ServerStorage/Endless/Choices",
    "ServerStorage/Endless/Relics",
    "ServerStorage/Endless/Altar",
    "ServerStorage/Endless/PowerUps",
    "ServerStorage/Endless/Director",
    "StarterPlayer/StarterCharacterScripts/Health",
    "StarterPlayer/StarterPlayerScripts/EndlessFx",
    "StarterPlayer/StarterPlayerScripts/EndlessHud",
    "StarterPlayer/StarterPlayerScripts/EndlessClient",
    "ServerScriptService/EndlessServer",
]

WHAT = {
    "Config": "Every number: rounds, zombies, players, points, guns, perks, altar, relics, power-ups, the house.",
    "Net": "Makes and finds the three RemoteEvents (Weapon, Fx, Hud) in ReplicatedStorage.Endless.Remotes.",
    "Sfx": "Plays sound cues from ReplicatedStorage.Assets.Sounds (the lobby's folder); silent without it.",
    "Weapons": "A gun's numbers for one player: base stats plus altar boosts, perks and relics.",
    "GunModel": "Builds every gun's look from parts (no assets).",
    "Util": "Signal, Maid (cleanup), ProximityPrompt maker, shuffle, weighted pick.",
    "HouseLayout": "The map as data: four levels of ASCII plans, doors, arches, windows, hatches, stairs, spots.",
    "HouseBuilder": "Builds the house from HouseLayout out of parts, every run, and returns the House table.",
    "Economy": "Points (player attribute Points), Double Pay and Scavenger multipliers, run stats.",
    "Survivors": "Player lives: spawning, regen, going down, revives, bleed-out, self-revive.",
    "Arsenal": "Guns as Tools, slots, ammo, the server's checks on every shot, the knife.",
    "Windows": "Boarded windows: zombies tear boards off, players hold Repair to nail them back.",
    "Horde": "The zombies: R6 rig from blocks, rising, windows, hunting, the swipe, limbs, ragdoll.",
    "Doors": "Doors and stair gates bought with points; opening one opens its zones.",
    "Randomizer": "The weapon randomizer (mystery box): spin, take, the skull that moves it.",
    "WallBuys": "Chalk guns on the walls: buy the gun, or its ammo.",
    "Perks": "The five perk machines and the power switch.",
    "Choices": "Pick-one sigils on the floor (relics and altar boosts).",
    "Relics": "The relic draft after every round and what each relic does.",
    "Altar": "Gun ascension: pay, the gun is taken, pick one of three boosts, it comes back stronger.",
    "PowerUps": "Drops: Resupply, Reaper, Double Pay, Purge, Hammer and Nails.",
    "Director": "The rounds: how many zombies, how tough, how fast, from where; intermissions.",
    "Health": "Empty on purpose: replaces Roblox's default health regen script.",
    "EndlessFx": "Client: zombie poses, green blood, power-up spin, lamp flicker, prompt wording, spectating.",
    "EndlessHud": "Client: drives the lobby's authored HUD by name (builds no UI).",
    "EndlessClient": "Client: first-person guns, PC/gamepad/touch input, recoil, aim assist on touch and gamepad.",
    "EndlessServer": "Boot (lighting, collision groups, remotes) and the run loop; wires the systems together.",
}

HEADER = """# Endless reference: build it in Studio with MCP

This file is everything a local Claude session needs to build the Endless reference place in Roblox
Studio through MCP, without Rojo: what it is, how to set the place up, every script with its exact
place in the Explorer, its type and its full code, and what to check when you press Play.
It is generated from `src/endless/` by `python tools/endless_guide.py`, so the code below is exactly
the code in the repo. The design write-up is `docs/ENDLESS-REFERENCE.md`; a browser version you can
play straight away is `docs/endless/endless-test.html`.

**Nothing in Studio has been playtested yet.** The scripts were written in a cloud session with no
Studio. They passed a layout checker, a syntax and name checker and three code reviews (about twenty
bugs found and fixed), but the first Play in Studio is the real test.

## What it is

A standalone place that plays an Endless mode from start to finish, as reference code for building
Endless into the zombie mode. It follows the owner's brief: the Mortuus video (roguelike Call of Duty
Zombies) with a weapon randomizer, in a huge house. Everything is built by the scripts (the house,
the zombies and the guns are plain parts), so it runs in an empty place.

- **Rounds** use Call of Duty's numbers (6, 8, 13, 18, 24 zombies for the first five rounds alone;
  health 150, +100 a round to round 9, then x1.1). Brutes from round 8, crawlers from round 12, runners
  from round 4. At most 24 zombies up at once.
- **Zombies** rise in the yard outside a boarded window, tear the boards off and climb in (upper windows:
  they climb the wall first), or claw up through a floor hatch. Only rooms the squad has opened send
  zombies. They lose arms and legs to gunfire (heads never), and their blood is green.
- **Points:** 10 a hit, 50 a kill, 100 a headshot kill, 130 a knife kill, 10 a board nailed back.
- **Spending:** doors and stair gates (750 to 1500, prices move each run), chalk guns on the walls (buy
  again for ammo), the weapon randomizer (950: a random gun you don't carry; after four spins the skull
  can move it), five perk machines behind a power switch in the cellar, and the gun ascension altar
  (pick one of three boosts, up to eight times a gun).
- **Relics** after every round (three on the floor, take one), **power-ups** from kills, **going down**
  and being revived, and a new draw of the box, perks, wall guns, altar, switch and prices every run.

## Set the place up (once)

1. Make a new place in the Last Light universe (Creator Hub, or Studio: File > New > Baseplate, then
   File > Publish to Roblox As, Last Light, new place). Any empty place works for a test.
2. Recommended: set `Workspace.StreamingEnabled` to false (new places have it on).
3. Optional: set `Lighting.Technology` to Future (lamps throw shadows).
4. Optional but strongly recommended: copy these two from the lobby place into this place:
   - `StarterGui.HUD` (the authored HUD: round, points, ammo). Without it there is no HUD.
   - `ReplicatedStorage.Assets.Sounds` (the zombie mode's sounds). Without it the place is silent.
5. The Baseplate and SpawnLocation can stay: the server deletes them when it starts.

## How to build it with MCP

Give the local session this file and ask it to build every script below. For each script:

1. Make any missing folders on the way (both `Endless` folders are plain `Folder`s).
2. Create an instance of the listed class (ModuleScript, Script or LocalScript) with the listed Name
   at the listed path.
3. Set its `Source` to the code block, exactly as written (for long sources, the MCP tool that edits
   script source, or `ScriptEditorService:UpdateSourceAsync`, both work).

Build in the order of the table (modules before the scripts that require them). `Health` is meant to
be empty apart from its comment. Nothing else is needed: no models, no assets, no Rojo.

A Luau snippet for the folders (run it in the Command Bar or with the MCP run-code tool):

```lua
local function folder(parent, name)
	local f = parent:FindFirstChild(name) or Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
folder(game:GetService("ReplicatedStorage"), "Endless")
folder(game:GetService("ServerStorage"), "Endless")
```

## The scripts

| # | Explorer path | Class | What it does |
|---|---|---|---|
"""

CHECKLIST = """
## What to check when you press Play (solo)

Studio test switches (workspace attributes, read when a run starts): `EndlessStartRound` (number),
`EndlessStartPoints` (number), `EndlessPower` (bool), `EndlessGod` (bool), `EndlessOpenAll` (bool).

1. The Output shows no red errors. The baseplate is gone and Blackwood Manor stands with a walled yard.
2. You spawn in the foyer, first person, with the Service Pistol, 8/80 ammo and 500 points.
3. 15 seconds later round 1 starts (HUD: ROUND 1, zombies left). About six zombies rise outside the
   foyer windows, tear the boards off one by one and climb in. Shoot them: each hit pays 10, a kill 50.
4. Hold E at a torn window: the boards go back and pay 10 each.
5. Doors show "Open Door (price)". Buy the living room door (about 750): it swings open and zombies now
   also come through the living room windows.
6. Wall guns: the Carbine and Bolt Rifle chalk drawings in the foyer sell the gun; buying again sells ammo.
7. Find the chest with the pale beam (the weapon randomizer, 950): guns flick past, one settles, hold E
   to take it. You never get a gun you already carry.
8. Go down to the cellar (pantry gate) and turn on the power: the lamps change from dim red to warm, the
   perk machines light up and the altar rune glows.
9. Buy a perk (Bulwark Brew: health 250). Go down: every perk is lost.
10. At the altar, hold a gun and pay: it is taken, three candles rise; take one and the gun comes back
    with a star on the HUD and a tint.
11. After each round three relic candles stand in your room: take one; HUD line names it.
12. Kills sometimes drop a glowing power-up: walk over it (RESUPPLY, REAPER, DOUBLE PAY, PURGE, HAMMER AND NAILS).
13. Let the zombies get you: you go down (grey screen). Alone with no Lazarus Draught or Second Wind,
    the run ends: the end screen shows the round reached, and 12 seconds later a new run starts in a
    freshly built house (the box, perks and prices have moved).

If something goes wrong, the useful things to report back are the first red error in the Output and
which step it was.
"""


def main():
    rows, sections = [], []
    files = {}
    for dirpath, _, names in os.walk(SRC):
        for fn in names:
            for suffix, cls in CLASS.items():
                if fn.endswith(suffix):
                    rel = os.path.relpath(os.path.join(dirpath, fn[: -len(suffix)]), SRC).replace(os.sep, "/")
                    files[rel] = (os.path.join(dirpath, fn), cls)
                    break
    missing = [p for p in files if p not in ORDER]
    if missing:
        raise SystemExit(f"add these to ORDER in tools/endless_guide.py: {missing}")
    total = 0
    for i, rel in enumerate(ORDER, 1):
        path, cls = files[rel]
        name = rel.split("/")[-1]
        explorer = rel.replace("/", ".")
        rows.append(f"| {i} | `{explorer}` | {cls} | {WHAT.get(name, '')} |")
        with open(path, encoding="utf-8") as f:
            src = f.read().rstrip("\n")
        total += src.count("\n") + 1
        sections.append(f"### {i}. `{explorer}` ({cls})\n\n{WHAT.get(name, '')}\n\n```lua\n{src}\n```\n")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER)
        f.write("\n".join(rows) + "\n")
        f.write(CHECKLIST)
        f.write(f"\n## Full source ({len(ORDER)} scripts, {total} lines)\n\n")
        f.write("\n".join(sections))
    print(f"wrote {os.path.relpath(OUT, ROOT)}: {len(ORDER)} scripts, {total} lines of code")


if __name__ == "__main__":
    main()
