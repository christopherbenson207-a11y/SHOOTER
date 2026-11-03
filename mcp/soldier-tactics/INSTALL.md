# SoldierTactics: install guide (campaign place, through Studio MCP)

This folder upgrades the WAR soldiers in **Operation Last Light** (placeId 78870312741411) with the
squad behaviour you approved in the browser sandbox (`prototypes/war-ai/index.html`). It is written
for two readers: you, and an AI assistant connected to Roblox Studio through MCP (the Roblox Studio
MCP server and its code-running tool). Section 9 is a prompt you can paste to the assistant.

## 1. What it does

Your soldiers already find cover, peek, fire bursts, suppress, flank, fall back when hurt and man
mounted guns. SoldierTactics keeps all of that and adds the following.

- **Fireteams advance in two halves.** One half moves while the other half stays in cover and fires,
  then they swap. The whole fireteam moves up, not one soldier at a time.
- **Attackers never fall back to cover behind them.** With nothing ahead, a soldier stays put and
  fights.
- **Defenders stop bobbing forward and back.** Flanking only happens during an attack or a push, so
  defenders are not pulled out of their posts and dragged back.
- **Squads push when they have the advantage.** A fireteam counts every friendly soldier within 90
  studs. When those outnumber the enemies it knows of, or most of those enemies are wounded, pinned,
  reloading or caught moving in the open, it attacks their position and follows them. A push lasts at
  least 12 seconds. A failing push goes back to its old orders and waits 35 seconds before another. A
  push that clears the ground holds it.
- **Grenades.** Most soldiers carry hand grenades that reach about 30 metres. The first rifleman of
  each fireteam carries rifle grenades that reach about 55 metres and burst on impact. A soldier
  throws only at an enemy dug in behind cover, a crew on a mounted gun, or enemies bunched together.
  He never throws near his own side, checks the arc with rays, and stands up for a short wind-up.
  Damage goes through your existing `WarDamage.Blast`.
- **Soldiers dodge grenades.** A soldier who sees one land, or whose side has called it, runs to
  cover outside the blast if he can reach it in time, and otherwise runs straight away from it.
- **High ground.** Marksmen and machine gunners take posts you tag `HighGround`, such as upper
  windows and roofs, when the post covers the fight.
- **Harder to spot.** A still soldier crouched in cover cannot be seen beyond 140 studs unless he
  fires or moves.

## 2. What it does not change

It edits no existing script. It is a new ModuleScript and a small Script that switches it on. It
hooks into five functions of your current `Soldier` module at runtime: Spawn, ChooseCover,
TakeCover, SetOrder and Sees. If your Studio version has renamed or removed any of them, that part
switches itself off and prints a warning. Everything else keeps working.

Do **not** use `rojo serve` to install this. The places are ahead of the repo, and serving would
overwrite newer scripts.

## 3. Files

| File | Goes to | Type |
|---|---|---|
| `SoldierTactics.luau` | `ServerStorage.Modules.SoldierTactics` | ModuleScript |
| `SoldierTacticsBoot.server.luau` | `ServerScriptService.SoldierTacticsBoot` | Script |

Install it in the **campaign place only**. The lobby's `Soldier` module is the older brain, and the
module refuses to install there.

## 4. Before you start

1. Open the campaign place in Studio, in Edit mode, not Play.
2. Connect your assistant to Studio through MCP.
3. Save a copy of the place first with File > Save to File As.

## 5. Install, step by step

Each step is Luau to run in Studio through the MCP code tool, or in Studio's Command Bar.

### Step 1: check the soldier brain is there

```lua
local m = game.ServerStorage:FindFirstChild("Modules")
local function has(name) return m and m:FindFirstChild(name) ~= nil end
print("Soldier", has("Soldier"), "CoverMap", has("CoverMap"), "WarDamage", has("WarDamage"))
local src = m and m:FindFirstChild("Soldier") and m.Soldier.Source or ""
for _, f in { "Spawn", "ChooseCover", "TakeCover", "SetOrder", "Sees", "All", "FromModel" } do
	print(f, src:find("function Soldier[:.]" .. f .. "%(") ~= nil)
end
```

All of these should print `true`. If Soldier or CoverMap is missing, stop: this is not the campaign
place. If one of the functions prints `false`, install anyway. The part that needs it switches off,
and the Output says which.

### Step 2: back up

```lua
local backups = game.ServerStorage:FindFirstChild("_Backups") or Instance.new("Folder", game.ServerStorage)
backups.Name = "_Backups"
local stamp = os.date("%Y-%m-%d")
for _, name in { "Soldier", "Battle", "CoverMap" } do
	local s = game.ServerStorage.Modules:FindFirstChild(name)
	if s then
		local c = s:Clone()
		c.Name = name .. "_" .. stamp .. "_beforeTactics"
		c.Parent = backups
	end
end
print("backed up")
```

### Step 3: create the module

The module is about 36 KB. Send it in parts of about 300 lines so each call stays small. The source
contains no `]==]`, so a `[==[ ... ]==]` string holds it safely.

First call, which creates the module and puts in part 1:

```lua
local mods = game.ServerStorage.Modules
local old = mods:FindFirstChild("SoldierTactics")
if old then old:Destroy() end
local m = Instance.new("ModuleScript")
m.Name = "SoldierTactics"
m.Source = [==[
-- paste lines 1 to 300 of SoldierTactics.luau here
]==]
m.Parent = mods
print(#m.Source)
```

Each later call appends the next part:

```lua
local m = game.ServerStorage.Modules.SoldierTactics
m.Source = m.Source .. [==[
-- paste the next 300 lines here
]==]
print(#m.Source)
```

Check that the final printed length is close to the file's size, 36,160 bytes. A long bracket drops
one leading newline, so expect a few bytes fewer. If setting `Source` is refused,
`game:GetService("ScriptEditorService"):UpdateSourceAsync(m, function() return text end)` does the
same job.

To check it compiles:

```lua
local ok, err = pcall(require, game.ServerStorage.Modules.SoldierTactics)
print(ok, err)
```

It should print `true` and a table. In Edit mode `Install()` is not called, so nothing runs.

### Step 4: create the switch

```lua
local s = Instance.new("Script")
s.Name = "SoldierTacticsBoot"
s.Source = [==[
-- paste all of SoldierTacticsBoot.server.luau here
]==]
s.Parent = game.ServerScriptService
print("boot script added")
```

### Step 5 (optional): tag high-ground posts

A post is a small invisible part placed where a soldier should stand, such as just inside an upper
window or on a roof edge. Turn it so its front face points out over the ground it covers, and give
it the tag `HighGround`. The soldier must be able to walk there. Stairs work. Ladders and jumps do
not, because soldiers cannot jump. This snippet adds one post at a position facing a direction:

```lua
local function post(pos, facing, name)
	local p = Instance.new("Part")
	p.Name = name or "HighGroundPost"
	p.Size = Vector3.new(1, 0.2, 1)
	p.Transparency, p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = 1, true, false, false, false
	p.CFrame = CFrame.lookAt(pos, pos + Vector3.new(facing.X, 0, facing.Z))
	game:GetService("CollectionService"):AddTag(p, "HighGround")
	local folder = workspace:FindFirstChild("HighGroundPosts") or Instance.new("Folder", workspace)
	folder.Name = "HighGroundPosts"
	p.Parent = folder
end
-- Example: the TOWN lookout tower, facing south over the plaza. Use your real positions.
-- post(Vector3.new(0, 131, 40), Vector3.new(0, 0, -1), "TownLookout")
```

Good places on the valley map are the TOWN lookout tower, the depot's upper floor and windows over
the plaza. Two to four posts per fight area is plenty. With no posts tagged, everything else still
works.

### Step 6: save

Press Ctrl+S. Publish when you're happy with it.

## 6. Test it

1. Press Play and deploy. The Output should show one line:
   `SoldierTactics: installed (Bounds, Dodge, Flanks, Grenades, HighGround, NoBack, Pressure, Spotting); N high-ground posts tagged "HighGround"`.
2. To see decisions as they happen, select Workspace in the server view and add the boolean
   attribute `TacticsDebug` set to true. Lines starting `[Tactics]` show bounds, pushes, grenades,
   dodges and high ground.
3. For a running total, run this in the server Command Bar during Play:
   `require(game.ServerStorage.Modules.SoldierTactics).Report()`.
4. What to look for:
   - On the road, HOUND's fireteams move up half at a time, while the other half fires.
   - Bots no longer run back to cover they have already passed.
   - Lamplighters on their posts stay there, until they have the numbers or you are pinned. Then a
     group pushes at you together.
   - Someone throws a grenade when you sit still behind cover for several seconds.
   - Soldiers near a grenade that lands scatter before it goes off.
   - With posts tagged, a marksman climbs to one.

Nothing here has run in Roblox yet. The behaviour was tested in the browser sandbox, and the module
was checked for structure but not compiled. Watch the Output for `SoldierTactics:` warnings on the
first Play.

## 7. Tuning and switching parts off

Every number is in `SoldierTactics.TUNING` at the top of the module. The ones you are most likely to
change:

| Setting | Default | What it does |
|---|---|---|
| `BoundTimeout` | 8 | Seconds before the halves swap even if someone has not moved |
| `PressMargin` | 1 each side | Friendly soldiers needed beyond the enemies known before a push |
| `PressMin`, `PressCooldown` | 12, 35 | Shortest push, and wait after a failed push |
| `HandGrenades` | 1 to 2 by role | Grenades each role carries |
| `RifleGrenades` | 3 | Rifle grenades for the first rifleman of each fireteam |
| `Grenade.Max`, `Grenade.RifleMax` | 110, 200 | Throw and launch range in studs |
| `Grenade.Damage`, `Grenade.Radius` | 120, 14 | Blast at the centre and its reach |
| `SpotCrouch` | 140 | How far a still, crouched soldier in cover can be seen |

To switch a part off without editing the module, change the line in `SoldierTacticsBoot`:

```lua
require(tactics).Install({ Features = { Grenades = false, Pressure = false } })
```

The part names are Bounds, NoBack, Flanks, Pressure, Grenades, Dodge, HighGround and Spotting.

## 8. Remove it

Delete `ServerScriptService.SoldierTacticsBoot`. The module does nothing unless it is installed, so
it can stay or go. The backups from step 2 are in `ServerStorage._Backups`, but they are only needed
if something else was changed.

## 9. Prompt for your MCP assistant

Paste this to the assistant together with the three files:

> You are connected to my Roblox Studio through MCP, with the campaign place open in Edit mode.
> Install SoldierTactics by following INSTALL.md exactly. Run step 1 and show me the output. If
> Soldier or CoverMap is missing, stop and tell me. Then do step 2 (backups), step 3 (create
> `ServerStorage.Modules.SoldierTactics` from SoldierTactics.luau, sent in parts of about 300 lines,
> and check the final length and that `require` succeeds), and step 4 (create
> `ServerScriptService.SoldierTacticsBoot` from SoldierTacticsBoot.server.luau). Do not change or
> delete any other script, do not run `rojo serve`, and do not press Play. When done, list what you
> created and remind me to press Ctrl+S. If I ask for high-ground posts, look at the map, propose
> positions at upper windows and roofs that overlook the fight areas, and add them with the step 5
> snippet only after I agree.

## 10. If something goes wrong

| Output says | Meaning and fix |
|---|---|
| `ServerStorage.Modules.Soldier not found` | Wrong place, or the module is elsewhere. Install in the campaign place. |
| `this Soldier module is not the WAR v2 brain` | The place has the old soldier brain, such as the lobby's. Use the campaign place. |
| `Soldier.X not found; the parts that need it are off` | Your newer Soldier renamed X. Everything else still runs. Send me the current Soldier source and I will adapt the hook. |
| `no WarDamage module; grenades are off` | Grenades need `ServerStorage.Modules.WarDamage`. |
| `SoldierTactics: <error>` repeating | A field the module expects is different in your version. Disable the boot script and send me the line. |

The soldier view does not yet play a throwing animation. A thrower stands up for the wind-up, and
the model's `Throwing` attribute is true for those 0.9 seconds if you want `SoldierView` to animate
it.
