# Last Light

Co-op horror shooter on Roblox. One game, two places, one repo.

| Place | placeId | Rojo project | Port |
|---|---|---|---|
| Lobby (menu, store, zombies) | 79455872202749 | `lobby.project.json` | 34872 |
| Campaign (Operation Last Light) | 78870312741411 | `campaign.project.json` | 34873 |
| Endless reference (standalone, see docs/ENDLESS-REFERENCE.md) | new place, not made yet | `endless.project.json` | 34874 |

## Layout

```
src/common/    scripts identical in both places (edit once, both get it)
src/lobby/     lobby-only scripts, or the lobby's version of a script that differs
src/campaign/  campaign-only scripts, or the campaign's version
src/endless/   the Endless reference place: standalone, shares nothing with src/common
tools/         split.py, syncback.py, dump.luau, endless_house.py (checks and draws the Endless house)
docs/          design docs and the handoff (start with docs/HORROR-SHOOTER-HANDOFF.md)
```

Each folder mirrors the Studio tree: `src/common/ServerStorage/Modules/Tank.luau` is
`ServerStorage.Modules.Tank`. `.luau` = ModuleScript, `.server.luau` = Script,
`.client.luau` = LocalScript, `Name.meta.json` = the script is disabled.

A script path lives in `common` OR in a place folder, never both. After adding, deleting or
moving a script file (for example copying a common script into both `lobby` and `campaign`
so they can differ), regenerate both project files:

```bash
python tools/split.py --projects-only
```

Rojo only manages scripts. Maps, models, UI, sounds and everything else stay in the places
(every project node has `$ignoreUnknownInstances`), so connecting Rojo never deletes them.

## Files -> Studio

```bash
rojo serve lobby.project.json
rojo serve campaign.project.json
rojo serve endless.project.json
```

In each Studio, open the Rojo plugin, connect to its port (34872 lobby, 34873 campaign, 34874 endless).

## Studio -> files (sync back)

1. `python tools/syncback.py`
2. In each place's Command Bar run `tools/dump.luau` with `PLACE` set to `"lobby"` or `"campaign"`.
3. When both dumps are in, src/ and both project files are rebuilt. Review `git diff`, commit, push.

Always dump both places: split.py needs both to decide what is common. The Endless reference place
dumps on its own (`PLACE = "endless"`) and only rewrites src/endless.
