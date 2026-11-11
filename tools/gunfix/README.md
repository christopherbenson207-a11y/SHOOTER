# GunSystem repair pass, 9 Nov 2026

Patch scripts for the GunSystem (Spearhead) migration in the Multiplayer, campaign and Zombies places. All of them
have already been run in the four Studio places on 9 Nov 2026; they are kept here as the record of what changed,
because the migrated gun system itself is not in this repo yet (no `SPH_*` script is tracked).

Each script is pasted into `execute_luau` (Edit) or the Command Bar. They check every anchor and compile the result
before writing anything, skip a script that already carries the `GUNFIX` marker, and keep the old source in
`ServerStorage._ScriptBackup_GunFix_9Nov`.

| File | What it patches |
|---|---|
| `patch_server.luau` | `ServerScriptService.SPH_Server`: R15 arms follow the gun by IK, stowed guns on the back and thigh, lean value clamp |
| `patch_client.luau` | `SPH_Character.CharacterClient`, `SPH_Assets.Modules.GunBridge`, `SPH_Player.PlayerClient`, `SPH_Assets.GameConfig`, `Shared.Controls` |
| `fix_sounds.luau` | swaps three AWP sounds that cannot load, removes four unused sounds that cannot load |

The lobby got only the `Shared.Controls` part (the four edits of job 5 in `patch_client.luau`).

Details and test results: `docs/HORROR-SHOOTER-HANDOFF.md`, section "9 Nov 2026: GunSystem repair pass".
