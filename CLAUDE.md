# Last Light: notes for Claude

Read README.md for the layout. Design docs and the running handoff are in docs/;
the top section of docs/HORROR-SHOOTER-HANDOFF.md is the latest state.

## How this repo connects to the game
- Two places, one game: lobby 79455872202749, campaign 78870312741411 (same universe).
  A third, standalone place is the Endless reference (src/endless, endless.project.json,
  docs/ENDLESS-REFERENCE.md): it shares nothing with src/common and builds its own map.
- Rojo manages scripts only. Maps, models, UI and sounds live in the places, not here.
  A script may read instances (tags, attributes, models under Workspace/ServerStorage) you cannot see from here;
  check the docs before assuming something is missing.
- src/common is shared by both places. A change there ships to both. If a change should only reach one place,
  move the file into both place folders first, then run `python tools/split.py --projects-only`.
- A cloud session cannot reach Studio. Edit files, run `rojo build lobby.project.json -o /tmp/l.rbxlx` and
  `rojo build campaign.project.json -o /tmp/c.rbxlx` to check both still build, commit and push.
  The owner pulls and syncs into Studio with `rojo serve`. Say clearly that nothing was playtested.
- Never hand-edit `*.project.json` beyond what split.py would write; regenerate instead.

## Owner rules (keep)
- Write to the owner in plain, full sentences.
- Mob blood is green. Less gore on faces. Limb tearing stays.
- No damage numbers over mobs, ever.
- PC gets no aim assist; mobile gets assist. Detect input with PreferredInput.
- Core loops come from proven hits, not invented twists.
- UI is authored PNG art in ImageLabels; never build screens out of script-made frames and labels.
- Never write to live DataStores from tests.
