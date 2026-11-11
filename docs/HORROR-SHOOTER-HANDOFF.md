# Last Light: handoff (29 Oct 2026, latest pass 1 Nov night at the top: the campaign place, CAMPAIGN in the menu, the store)

## 11 Nov 2026: GunSystem Medkit, healing feel, fire mode switch (Multiplayer, campaign, Zombies)
- **Owner's ask:** "build the medkit and add the features u just mentioned", then: keep the hybrid, he sends the bugs
  he finds, and whatever GunSystem has that ours lacks gets brought over.
- **Built** (`tools/gunfix/patch_medkit_firemode.luau`, marker `GUNFIX 11 Nov`, backups
  `ServerStorage._ScriptBackup_GunFix_11Nov`):
  - *Medkit* on the bandage job (`Modules.Bandages`): `Remotes.Bandage:FireServer("Medkit")`, 3.3 s, +60, closes every
    wound. Carried as the player attribute `Medkits` (`GameConfig.Bandages.Medkit`: Start 1 per life in campaign and
    Zombies, 0 in Multiplayer; Max 2). It has no hotbar slot: the Bandage key uses it by itself when you are missing 50
    health or more, or have no bandage. The bandage tile shows it as "x1 +1". `Bandages.GiveMedkit(player, n)` is the
    hook for a pickup or shop entry; none exists yet.
  - *Healing feel:* green motes round the healer for everyone (`HumanoidRootPart.HealGlow`), walking capped at
    `HealWalkSpeed` 7 while a gun Tool is out (`GunBridge.WalkSpeed`).
  - *Fire mode:* N (`Controls` action `FireMode`) switches an automatic between single shots and automatic.
- **Tested:** campaign Play: medkit started on the Bandage key at 37 health, motes on, 3.3 s, medkit used, bandage
  kept, no server errors. Not tested: the slow walk (the server cannot see client walk speed), the fire mode key,
  Multiplayer and Zombies after this patch.
- **Not built, and why:** suppression already exists (`CombatShock`, 7 Nov). AKM and AKS-74U would be new catalogue
  guns (stats, unlocks, lobby art). RPG-7, M1014, revolver, Thompson need their clips re-uploaded to the group. Kill
  feed and compass need authored art. Anything that needs GunSystem's own files needs `GunSystem.rbxl` open again.

## 9 Nov 2026: GunSystem repair pass (Multiplayer, campaign, Zombies; lobby Controls only)
- **Owner's ask:** "i tried migrating gunsystem into my shooter game the other places. but i made many errors and
  possibly left out a lot": how guns are held, animations, third and first person, right-click scoping, where guns
  are kept on the player; then the left/right lean, the GunSystem healing mechanic, and "other things we can
  incorporate?".
- **What the migration is:** `GunSystem.rbxl` is Spearhead (SPH) v1.2.1, an R6 Tool-based gun kit. It sits beside the
  place's own `GunClient`/`GunServer` as a hybrid: while a firearm Tool is equipped, `SPH_Character.CharacterClient`
  owns the viewmodel, camera, recoil and clips; `GunServer` stays the authority on damage and ammo. The seam is four
  scripts: `SPH_Assets.Modules.GunBridge` (GameConfig numbers into SPH), `GunNameMap` (Tool name to `GameConfig.Guns`
  key), `FireReporter` (builds the `Remotes.Fire` report), `ServerScriptService.ToolGrant` (one Tool per carried gun).
  **None of the SPH scripts are in this repo yet**; the patches of this pass are in `tools/gunfix/`.
- **Faults found and fixed** (same patch in all three places, backups in `ServerStorage._ScriptBackup_GunFix_9Nov`):
  - *Hands off the gun in third person.* The R6 clips drive two one-piece arm proxies; the R15 arms were welded to
    them stiff and straight, and the copied elbow and wrist offsets were wrong, so the right hand sat 0.85 studs from
    the grip. `SPH_Server` now gives each arm an `IKControl` (`Humanoid.SPH_ArmLeft/Right`, target `HandTarget` on the
    proxy, pole `UpperTorso.SPH_Pole*`), switched on while a gun is held. Right hand error after: 0.01 to 0.03 studs.
    The left hand of a long gun stops about 0.8 studs short of the handguard: these blocky arms reach 1.77 studs and
    the clip asks for 2.45.
  - *Stowed guns never showed.* Every gun holsters on a part called "Torso", which R15 does not have. `HolsterMount`
    puts long guns across the back (muzzle up over the left shoulder) and sidearms on the right thigh; stowed models
    are massless, non-colliding and take the player's camo.
  - *Aim dropped when you fired.* SPH's aim is a plain hold, and the owner's mouse reports right-button-up the instant
    left goes down (see 29 Oct). The old GunClient rule is ported: a release that lands within 0.05 s of a shot, or a
    tap shorter than 0.2 s, latches the aim until the next press; sprint lowers a latched aim. Touch aim uses it too.
  - *Sights came up at a fixed speed.* They now rise in the gun's own `AimTime` from GameConfig, frame-rate
    independent, so the scope overlay (`GunFeelScoped`, at `Scope.At` of AimTime) appears when the sights are up.
  - *Third person (V) put the camera on the character's back near a wall.* The shoulder offset and the distance are
    now checked against walls separately; the choice is kept across respawns in the player attribute `GunFeelThird`.
    The controller R3 binding of the view toggle is gone (it swallowed FRONTLINE's killstreak button).
  - *Lean was switched off.* It is back for R15: hold Q or E (`Controls` actions `LeanLeft`, `LeanRight`; E gives way to
    a use prompt and to getting up). The view shifts 0.95 studs and rolls 15 degrees, stopped by walls; the body tips at
    the waist through `GunBridge.SetLean`, and other players see it (`repLean`). **Tactical gear moved from Q/T to T.**
  - *Two hold poses blended after a fast gun swap* (the start gun and the Endless gun): one idle pose at a time, and
    an equip that was overtaken by another now stops instead of writing the old gun's ammo folder over the new one.
  - *Asset errors every spawn.* The four crouch and prone clips are R6 clips owned by another account and were loaded
    on every character; they are no longer loaded while the SPH stances are off. Three AWP handling sounds that the
    experience may not load now use the AK's; four unused sounds that can never load are deleted. Campaign Play after
    the pass: no failed animation or sound loads.
  - A fractional pellet spread (a choke attachment) could make `math.random` throw on every shotgun shot: rounded.
- **Tested in Play:** Multiplayer (hip, ADS, tap-to-latch aim, firing while latched, lean, reload, swap AK and
  pistol, holsters, third-person camera, a frozen copy of the character photographed from four sides) and campaign
  (spawn, IK, holster, bindings, logs). No script errors in either. Zombies has the same patch (its CharacterClient was
  byte-identical to Multiplayer's before it) but was not played after patching.
- **Not checked:** the sniper scope overlay after the AimTime change, two real players seeing each other, a phone, a
  controller. The lobby's CONTROLS screen gains two rows (Lean left, Lean right); not looked at.
- **Left as it is:** the first-person arms are SPH's block arms; the R6 walk/idle/run clip loader
  (`AnimationsConfig`) cannot work on R15; SPH's own crouch, prone, drops, ragdolls, glass and footsteps stay off
  because the place has its own.
- **Repo:** `src/common` and `src/duel` `Shared/Controls.luau` carry the lean edit. Everything else of the gun system
  still needs a full dump from the Command Bar (`tools/dump.luau`) once the lobby crate edits of the other session are
  committed.

## 7 Nov 2026: FRONTLINE phase 1, weather, shell shock and battle ambience in every combat place
- **Owner's ask:** "Yes, start phase 1" (`docs/FRONTLINE-OPEN-WORLD-PLAN.md` section 7: one weather system with seven
  presets, suppression and shell shock, battle ambience), then "some of the pass is across all places so do just
  that it should be across all places."
- **Built** (one copy of each file in `src/campaign` and `src/duel`, identical):
  - `Shared.Weather`: three preset sets picked by PlaceId (workspace `WeatherSet` overrides). Valley (campaign):
    Clear Morning, Overcast, Snowfall, Blizzard, Freezing Fog, Golden Dusk, Night Battle, with a 40% chance of a
    shift partway through a match (Overcast to Snowfall, Golden Dusk to Night Battle, ...). Desert (Multiplayer):
    High Noon, Hazy Heat, Blue Dawn, Golden Dusk, Dust Storm. Manor (Zombies): Still Night, Mist, Snow, Freezing Fog,
    which change only the air, so the manor's own night lighting stays.
  - `WeatherServer` only writes workspace attributes (Weather, WeatherFrom, WeatherStart, WeatherBlend, WeatherSight).
    In Studio, workspace `StudioWeather = "<preset>"` forces one (`StudioWeatherBlend` seconds, default 0).
  - `WeatherClient` blends each screen from the server clock and writes only the values the two presets change (the
    Zombies room flicker keeps its Ambient). Snow, blizzard, ice motes and dust come from a box that follows the
    camera, scaled by GraphicsTier and touch, and stop under a roof. `Fall.Glow` lets night snow light itself.
  - `CombatShock`: enemy near misses (ShotFx, EmplacementFx) blur, grey and sway the view. A blast (SoundKit blast
    cues tag their sound "Blast"; also Gear Fx blasts and Emplacement shells) shakes it, and a close one rings the
    ears (Intro/Tinnitus) and muffles the SFX, Mobs, Ambience and Beacon groups for up to 3 s. Lighting post effects
    only, no new UI. Camera bob setting scales the shake.
  - `BattleAmbience` (campaign and Multiplayer): far artillery flashes with late thumps, tracer bursts, bomber
    passes, a smoke column behind the objective, and at night illumination flares that light the ground and go out
    when the weather changes.
  - `SoundKit` (common and duel) tags blast sounds. `Soldier` (campaign and duel) caps bot sight at WeatherSight.
    The old campaign `Snowfall` and `SnowFx` scripts are deleted (WeatherClient replaces them).
- **In Studio:** campaign has all of it (backups in `ServerStorage._Backups`, `*_2026-11-07_beforeWeather`).
  Multiplayer: all of it, including BattleAmbience and the Soldier sight cap (not played yet). Zombies (not in git): Weather, WeatherServer, WeatherClient, CombatShock, the
  SoundKit edit and a new `Assets.Sounds.Intro.Tinnitus`, logged in `last-light/blender/zombies-place/PATCHES.md`.
  Lobby: only the SoundKit edit, so Studio matches `src/common`; no weather there, its menu lighting stays. Every
  script was checksum-matched against the repo. Backups of edited scripts: `ServerStorage._ScriptBackup_Weather_7Nov`
  (Multiplayer, Zombies, lobby).
- **Tested** in campaign Play: every Valley preset from the same spot, near misses and a blast 9 studs away (blur,
  muffle of -26 dB, ringing, back to normal in about 2 s), the flare fading out on a weather change, Low graphics with
  shadows off, and a greyscale pass of Night Battle at Low. No script errors. Zombies Play: the Manor set rolls, Snow
  applies, the shock effects are created.
- **Not done or not checked:** Clear Morning still looks grey because the place's painted overcast skybox stays (it
  needs a clear-sky Sky per preset, an art job). The Desert presets were not looked at in Play. Zombies snow could not
  be judged, because that Studio ran at about 5 fps during the test, which slows particles. No phone test and no
  multiplayer test.
- **Owner must save** the campaign, Multiplayer, Zombies and lobby places.
- Studio tip: when `start_stop_play` hangs on "Start play hasn't finished yet", end the session from the Server
  datamodel with `StudioTestService:EndTest()`; `ExecutePlayModeAsync` (spawned) starts one from Edit.

## 7 Nov 2026: gyro aim rebuilt (repo only, not on a phone yet)
- **Owner's ask:** "mobile gyro is so bad and wrong", research GitHub, top places and the Toolbox for the best
  gyro script and apply it in all places. Nothing usable exists (no Roblox gyro aim on GitHub or in the Toolbox,
  no top shooter with documented gyro aim), so `Shared.GyroAim` ports GyroWiki's player-space method and adds a
  self-check that works out each phone's rotation convention from gravity (48 candidates). Full write-up, tests
  and phone checklist: `docs/GYRO-AIM.md`.
- **Built:** `Shared.GyroAim` + TouchControls wiring in campaign and duel (repo). Simulation `tools/gyro_sim.py`:
  every convention within 15% (old code: 5%). `tools/install_gyro.luau` installs it in a place by command bar.
- **Not done:** Studio was not connected in that session, so no place in Studio has it yet: Rojo-sync campaign and
  duel or run `tools/install_gyro.luau` there, and run it in the Zombies place (not in git). Not played on a phone.
  `tools/gyro_luau_check.luau` (real module, stand-in types) not run yet.

## 7 Nov 2026: crouch, prone and the FRONTLINE open-world plan
- **Owner's ask:** the war games on Roblox are ahead of us ("our map in campaign is very weak and the gameplay"); watch
  Galifran's top 10 war games video frame by frame and plan the overhaul; then "Frontline needs to be changed completely
  to a huge map, replayable mode, fun open world", and the basics: hold crouch to lie flat holding the gun like a soldier,
  move while crouched or prone, press crouch again to stand, no sprint while crouched.
- **Plan:** `docs/FRONTLINE-OPEN-WORLD-PLAN.md` (the video's lessons per game, our state, the decision: Conquest on one
  huge map "Varsk Valley", 20 v 20 with bots, 7 named points, a moving front per match; art direction grounded
  semi-real Cold War; seven weather and time-of-day presets on one WeatherService; systems and build order, phase 0 to
  6; engine facts from the vault). `FRONTLINE-MAP-PLAN.md` is marked superseded. Nothing of phases 1 to 6 is built.
- **Stances (built, campaign and duel, repo and Studio, commit 5c850ea):** `Shared.CrouchPose` now has the prone pose
  (measured per avatar, body 0.1 stud off the floor, head at the camera, chest-held gun turned ahead) and `Crawl()`
  run by every client. `Evade.client` is one file for both places: tap crouches, hold 0.35 s lies down, a press from
  crouch or prone stands, jump stands; touch holds work (TouchControls passes the touch). `EvadeServer` takes
  `"Stance"` and poses everyone; going down stands the body. `GunClient`: no sprint while crouched or prone,
  ProneSpeed 4.5. Numbers in `GameConfig.Evade` (ProneHold, ProneSpeed, ProneTime, Pose.Prone).
- **Tested** in Studio Play with keyboard input (duel and a live campaign FRONTLINE match): tap, hold from standing and
  from crouch, stand by tap and by jump, sprint blocked low and working standing, AK and pistol (pack guns) and the
  sniper (chest-held) point ahead. **Not tested:** a phone touch hold, a gamepad hold, other players seeing the pose
  over the network, prone on steep slopes (the body may clip or bump), going down while prone. Backups of the old
  scripts: `ServerStorage._ScriptBackup_Stances_7Nov` in both places (delete once the owner is happy).
- **Owner must save** the campaign and Multiplayer places. The Zombies place has no prone yet (not in git).
- Another session's gyro-aim and offer work was uncommitted in TouchControls, the project files and lobby files at the
  time; only the crouch hunk of TouchControls went into 5c850ea.

## 7 Nov 2026: every store product is live, and HOME shows one offer picked from the player's data
- **Owner's ask:** "create all products needed", then "blend the monetization ways into the game like ... 2x exp boost for
  players who need level ups to obtain a class ... take data from datastore to help us better advertise our products ...
  predict sections they will need a product and wire a small tab for the purchase".
- **Products:** all 27 developer products and 4 passes exist in Creator Hub (universe 10773529574), on sale at the
  catalogue price with icons. Ids: `docs/product-ids.json`. Patched into Catalogue and GameConfig.Store in the lobby,
  campaign and duel (repo and Studio) with `tools/set_product_ids.py` / `tools/set_product_ids.luau`.
  The Zombies place (121963671263674, not in git) was patched in Studio too (25 catalogue + 4 GameConfig ids).
- **Offer engine:** `src/lobby/ServerStorage/Modules/Offers.luau`. Right after a match (fresh LastAar, once per match) it
  checks six rules in order and picks at most one: Starter Pack (real 48 h window, won match), 2X XP 30/60 min when a
  class, gun, gear or operator is 1-2 levels away and within ~4 matches of XP, 5 revive tokens after a lost match with
  no tokens, premium Night Pass once 4+ premium rewards are already earned, the gem pack that covers an item they tried
  to buy (Store `Want`, or a failed `Buy`) or the cheapest store operator they lack once they have half of it, Double
  Gems after a won match (line says what that match would have paid). Guard rails: store open + 2 matches, one offer per
  visit (two for payers), 10 min apart, per-rule cooldown that doubles each time the player hides it (max 7 days),
  permanent items only after a win. Profile field `data.Offers` (Seen/Want/AarAt/Bought).
- **Analytics (the "what do players need" data):** AnalyticsService custom events, visible in Creator Hub > Analytics >
  Custom events: `PlayerNeed` (every need found, shown or not; fields: need, match result, level band), `OfferShown`,
  `OfferHidden`, `OfferBought` (bought within 20 min of the offer), `WantItem` (item, gems short).
- **Strip:** `MenuPages/Offer.luau` (overlay, HOME only, under DEPLOY), art `horror-shooter/menu/art/screens/Offer.py`
  (Wide + Phone uploaded, `UiArt/Offer_*`). Product art, name, one line, BUY with the live price, "<" tucks it to a ">"
  tab at the screen edge. Text shrinks to fit by measuring (TextScaled breaks under the menu UIScale).
- **Tested:** rules checked in Studio with fake profiles (all six rules, the per-visit cap, hide back-off, stale and
  too-early matches). Play test in the lobby (phone layout): strip showed "2X XP 30 MIN / MARKSMAN CLASS UNLOCKS AT
  LEVEL 18 / R$ 49" under DEPLOY. **Not tested:** the "<" / ">" buttons and BUY from the strip (no clicks were possible),
  the Wide layout in Play, a real purchase. The owner must save the lobby, campaign, Multiplayer and Zombies places.

## 7 Nov 2026: gun feel pass, first / third person (V), per-gun muzzle flash
- **Owner's ask:** "improve the gun feel to absolute perfection. as well as add a pov where ppl can switch first person
  n third person", then "gun vfx at the tip needs to change get better vfx for guns n differ accross the board".
- **New shared modules** (campaign, duel, and Zombies place 121963671263674 in Studio; same text in all three):
  - `Shared.ViewMode`: the over-the-shoulder view. The camera stays LockFirstPerson. A RenderStep at Camera+2 moves the
    finished camera right 1.75 / up 0.4 / back 6 (aim 1.35 / 0.28 / 3.2, sprint back 6.6), with a spherecast against walls
    that pulls in at once and eases back out. The body fades in and the viewmodel hides. In third person a shot goes from
    the head to whatever the crosshair ray hits, so GunServer's origin check still passes. A scoped gun aims in first
    person. V (Controls action `View`, `Requires = "ViewMode"`) or the Settings row "Camera view" (option `View`,
    First/Third, saved) switches it. Your own world gun is posed and tilts with your look (`TiltGun`).
  - `ServerScriptService.ViewModeServer`: `Remotes.ViewMode` (boolean, 12 a second max) sets the player attribute
    `ThirdPerson`. A player in third person plays their own body's recoil and pack clips (these replicate), so other
    clients skip their local copy (WorldGunArms, or in Zombies GunClient TPAnim/PackArmsFx; `PackArms.Stop` added).
  - `Shared.GunFeel`: a learnable recoil pattern (noise-based sideways wander, a harder first shot, camera roll). Part of
    each shot's climb is held while firing and settles after the burst, minus what the player pulled down. Gun weight:
    strafe lean, a lift on jumps, a thump on landing, a kick going in and out of aim. A mechanical tick plays in the last
    third of the magazine.
  - `Shared.MuzzleFx`: one flash style per gun family. Pop (pistol), Rifle (AK), Burst (shotgun), Brake (sniper, side
    jets), Heavy (MG), Suppressed (silencer); a flash cap gives a smaller one. Each flash is a front sprite, a hot core, a
    beam jet, embers, a smoke puff, and a heat wisp after sustained fire. Pieces are pooled per gun tip. Other players'
    and soldiers' shots show the flash too (ShotFx handler). Textures come from `horror-shooter/vfx/make_flash2.py`.
- **Edited:** GunClient (campaign, duel, Zombies), WorldGunArms (campaign, duel), GameConfig + Controls (all four
  places), Settings rows `View` (LayoutOrder 115) and `Bind_View` (1021) in all four places' StarterGui.Settings.
- **Tested in the campaign Studio (MCP Play, script checks, no screenshots: computer use was busy):**
  - V switches both ways and the ThirdPerson attribute follows.
  - The camera sits at the right offset, and the body shows (25 of 28 parts) with the viewmodel hidden.
  - A wall 3 studs behind stops the camera about half a stud off its face, and the camera eases back out after.
  - Third-person shots leave from the head and land exactly on the crosshair ray.
  - 9 AK shots climb about 4.8° with sideways wander and roll, and settle back in about 1 second.
  - The first-person flash jet and light fire on every shot.
  - No console errors.
- **Not tested:**
  - The look of the flashes and the feel (no screenshots).
  - The sniper's forced first person, other guns' flash styles, and the low-ammo tick sound.
  - Two-player replication of ThirdPerson.
  - The Multiplayer and Zombies places (installed and hash-checked, not played).
- Owner must **save all four places** in Studio.

## 6 Nov 2026 (night): the store becomes one scrolling shop with boosters and purchase effects
- **Owner's ask** (with a military-shooter store screenshot): "Make the shop like this. It should have boosts and
  actually buy able stuff. With nice effects. All. Ui have to be authored".
- **Art:** `horror-shooter/menu/art/screens/Store.py` (layout) + `screens/store_feed.py` (cards, booster canisters,
  info panels, pass banners, effects). Wide and Phone built in the lobby Studio; all 227 store images load. Backups of
  the old page are in `ServerStorage._Backup_2026-11-06_beforeStoreFeed`; old manifests in `out/feedtest/*.before.json`.
- **Page:** FEATURED, GEMS and PASSES are one scrolling `Feed` (hero, 4 gem packs, 2X XP and 2X GEMS booster rows with
  a live time-left counter, 6 pass banners). The tabs jump to their header, and the underline follows the scroll. Every card
  pops on hover (UIScale, white corner brackets, a light sweep). A granted purchase bursts out of its card (rays,
  flash, sparks: the hidden `Fx` images), with the LevelUp sound. OPERATORS and COSMETICS keep the old grid.
- **Boosters:** six dev products in `Shared.Catalogue` (XpBoost30/60/120, GemBoost30/60/120: 30, 75 and 165 minutes;
  49/79/129 R$). StoreServer grants call `Profile.AddTimed`, which stacks on the time left and saves `data.Timed.{Xp,Gems}`
  (the os.time() each runs until), published as `BoostXpUntil` / `BoostGemsUntil`. 2X XP doubles account XP in
  `Progression.Add` (lobby + Zombies; pass XP unchanged). 2X GEMS is a x2 in `Profile.Multiplier` (lobby, Zombies; the
  x4 cap still applies) and in `Profile.Earn` (campaign, duel).
- **Not on sale yet:** every product and pass id is still 0, so cards show the catalogue price and a click answers
  NotForSale (Error sound). The Open Cloud key lacks `developer-product:write` / `game-pass:write`, so the owner must
  create the products (or grant those scopes) and put the ids in `Catalogue.Products`.
- **Tested:** lobby Play (Phone layout: the viewport was short). Store opens, hover pop and brackets, GEMS/PASSES tab
  jumps, underline follows the scroll, a booster timer counted down from a test attribute, no script errors. Not
  tested: a real purchase and its burst (no product ids), Wide in Play, and the Zombies/campaign/duel changes in Play.
  The campaign Profile edit was made in edit mode, but the place was in Play when I went to compile-check it, so that
  copy is unchecked (the identical duel copy compiles).
- Studio places changed and unsaved: lobby, campaign, Multiplayer (duel), Zombies. The owner must save all four.

## 5 Nov 2026 (night): kid-friendly menu, GEMS, and one end card for every place
- **Owner's asks:** the main menu was "overwhelming", so cut the text and clutter, keep the store visible and the squad
  side by side, new kid-friendly colours, SCRIP becomes GEMS, a clickable gems wallet with a + beside it, LOADOUT renamed
  GUNS, and the end-of-match screens in the other places restyled to match the lobby. Plan: `horror-shooter/menu/SIMPLIFY-PLAN.md`.
- **Lobby** (Studio, synced here): navy and yellow palette (art recoloured by `horror-shooter/menu/art/recolour.py`,
  583 images and 290 texts remapped), Home rebuilt with less on it, TopBar tabs HOME / GUNS / STORE / PASS, wallet
  frame with + going to Store's GEMS section, Store tabs Featured / Operators / Cosmetics / Gems / Passes. The b973494
  attachments scripts were installed in the lobby Studio, the Gunsmith and Picker art is built and uploaded, and the
  Gunsmith page opens from the Picker's ATTACHMENTS button. Play-tested: Home, GUNS, Store and Gunsmith with no script errors.
- **End card:** `Shared.EndCard` (master copy `horror-shooter/menu/art/endcard/EndCard.luau`, art from
  `screens/EndCard.py`), PNG pieces plus live words: result banner, up to 3 stars, a stats line, PLAY AGAIN / SWITCH MODE /
  LOBBY, one note line.
  - Zombies place (not in this repo): EscapeHud's end screen uses it.
  - Campaign: FRONTLINE's end shows it with the kills and the next-match clock. LOBBY goes through the new
    `FrontLobby` script (Remotes.ToLobby, save then teleport). HUD.GameOver uses the new palette.
  - Duel: HUD.DuelEnd was replaced by the card (PLAY AGAIN is the rematch vote). The new HUD.DuelBar score bar and
    HUD.DuelKit round banner are art from `screens/DuelBar.py`. MatchHud hides the wave block and points there.
- **GEMS:** the word changed in player-facing text in all four places (code names such as `Scrip` stay).
- **Campaign Studio caught up (6 Nov evening):** the b973494 attachments hooks (GunServer, GunClient, Hotbar, Profile,
  Shared.Attachments) were installed in the campaign Studio by MCP, hunk by hunk on top of what Studio had. Every one
  now hashes equal to this repo, all compile, and `Attachments.Config` gives the right numbers in edit mode. Lobby
  and Multiplayer were checked the same way and already matched. Pre-install copies of the four scripts are in
  campaign `ServerStorage._ScriptBackups_6Nov_Attach` (disabled). Not play-tested; the owner must save the place.
  Zombies (121963671263674) was not open, so it was not re-checked.

## 6 Nov 2026: scopes, attachments and gun weight in every place
- **Owner's ask:** scopes and attachments from Toolbox, recoloured, camos on them, ways to get them, in the lobby,
  campaign, zombies and Multiplayer; then "some guns should be heavy and cause speed loss".
- **One module:** `src/common/ReplicatedStorage/Shared/Attachments.luau` (lobby and campaign through Rojo; zombies has a
  pasted copy; the Multiplayer session is porting it into `src/duel`). 13 items in 5 slots (Optic: Kobra, Red Dot, Holographic, ACOG 3x, Mini Dot,
  Recon 8x; Muzzle: Suppressor, Flash Hider, Choke; Under: Vertical Grip; Laser; Mag: Extended, Fast). Per-gun
  allowed lists and unlock ladders (weapon level of that gun), mods applied on top of the gun config and cached per
  pick set, short pros/cons lines for the menu, mount points per gun and view, and `Dress` which fits the models on
  world guns, viewmodels and the menu stage. Parts tagged Body take the gun's camo.
- **Models:** `ReplicatedStorage.Assets.Attachments`, built by `tools/attachments/install_attachments.luau` from
  six Toolbox packs (scripts, textures and decals stripped, repainted). Flash Hider and Choke are built from parts by
  `build_muzzle_devices.luau`; `patch_library_5nov.luau` fixed libraries installed before the Mini Dot and Recon 8x
  ring fixes. Installed in all four places (campaign on 6 Nov, staging folder removed).
- **Gun weight:** `A.GunWeight` (Pistol 0.9 kg up to M60 10.5 kg) plus each attachment's weight gives `MoveSpeed`
  and `SprintMult` (walk 1.0 to 0.7, sprint loses more). GunClient applies it to WalkSpeed in campaign and zombies.
  Lobby shows it on the Gunsmith page (kg and LIGHT / MEDIUM / HEAVY).
- **Getting them:** lobby Gunsmith page (`MenuPages/Gunsmith.luau`, opened by the Picker's ATTACHMENTS button) saves
  picks through Store "Attach" (weapon-level locks checked on the server; saved in Profile `Attach`). Zombies Endless
  has a Gunsmith station on the foyer table (1250 points, a random attachment on your current gun for the run only,
  `RunAttach`).
- **Menu art still to run:** `horror-shooter/menu/art/screens/Gunsmith.py` (new page) and the ATTACHMENTS button in
  `Picker.py`, plus the 13 icons in `horror-shooter/menu/art/renders/out/Attach` (made by `make_attach_icons.py`).
  Until they are built and uploaded, the Gunsmith page has no frame and the Picker shows no ATTACHMENTS button.
- **Owner to do:** save all four places (lobby, campaign and Multiplayer scripts now match this repo; menu art for
  Gunsmith and Picker is built, see the 5 Nov night section). **Only the lobby Gunsmith was playtested.**

## 5 Nov 2026 (late): MULTIPLAYER is a 1v1 duel in its own place; FRONTLINE, Defend and Nightmare retired
- **Owner's calls:** a new Multiplayer place (placeId 75051098491738, same universe) holds the game's multiplayer, with a
  1v1 as the first mode; the lobby gets a MULTIPLAYER card; the campaign/FRONTLINE, Defend and Nightmare are retired.
  "I want the game high quality now."
- **Lobby** (pushed into the lobby Studio, verified byte for byte against the repo; **owner must save and publish**):
  the mode id is `Duel`, shown as MULTIPLAYER (chips MULTIPLAYER / 1 V 1 / FIRST TO 5, art borrowed from FRONTLINE via
  `ART_OF` in `MenuPages/TopBar/Common`). `GameConfig.Menu.Modes` is now Outbreak and Endless; `C.Modes()` puts Duel
  first. MenuServer teleports a party of at most 2 to a **public** server of the duel place
  (`GameConfig.War.Campaign.DuelPlaceId`, `ShouldReserveServer = false`); 3-4 get DeployFailed "TooMany" (Play page
  notice); "Campaign" is answered "Locked"; Duel in Studio fails "Studio" (no teleports there). The zombies place still
  contains Defend/Nightmare code internally; only the menu hides them.
- **Duel place** (`src/duel`, standalone project `duel.project.json`, serve port 34875; split.py STANDALONE and syncback
  ALLOWED know it; dump.luau takes PLACE = "duel"): a copy of the campaign scripts minus the war/PvE servers and clients
  (33 scripts removed from the place), plus:
  - `Shared.Duel`: every number (first to 5, 90 s rounds, 3 s countdown, 15 s rematch window, out-of-bounds 3 s grace
    then 20/s, Scrip pay 150 win / 50 loss / +15 a round / 100 forfeit, points).
  - `ServerScriptService.DuelServer`: waits for two InMatch players, slots them Ally/Enemy so the FRONTLINE gun rules
    make each the other's target, loads both fresh at their ends each round (ends swap every round), round on a death
    or on the clock (healthier wins, level = draw), forfeit on leave, REMATCH (both = now) / LOBBY (teleport back with
    Profile.SaveNow + Reclaim on failure), a third player is sent to another duel server.
  - `MatchHud` duel lines (round + clock, score vs opponent by name, out-of-bounds countdown).
  - `DuelClient`: HUD.DuelEnd panel (VICTORY/DEFEAT, score, authored REMATCH/LOBBY PNG buttons from
    `horror-shooter/menu/art/duel_buttons.py`; R / pad X rematch, pad Y lobby, pad gets the selection, phones scale),
    cue sounds and countdown ticks.
- **Map:** the desert container yard from the owner's 5 BuiltByBit references, modelled in Blender
  (`last-light/blender/duel-yard`: FBX, `IMPORT-ME.md`, `place_yard.luau`, renders in `shots/`). The owner imported
  the FBX and `place_yard.luau` placed it (half turn detected and corrected): `Map.Meshes.Static` 28 meshes,
  `Map.Meshes.Props` 128 props cloned from 26 prototypes kept hidden in `Map.Meshes._Protos` (y -400, so a rerun can
  rebuild), about 121k triangles. All visible meshes are non-colliding and non-query; play runs on `Map.Collision`
  (144 invisible boxes). Also `Map.Spawns` A1-A3 / B1-B3 and `Map.Bounds.PlayBox`. Checked in edit-view captures:
  the whole yard is in place and spawn A faces its container screen. `Lighting.Technology` still has to be set to
  Future by hand (scripts can't).
- **Weapon rounds** (owner: "keep the mode fresh"): round 1 of every match is each player's own lobby loadout
  (Kit.Resolve primary + secondary); from round 2 both players get the same random kit from `Shared.Duel.Kits`
  (RIFLES AK+Pistol, SHOTGUNS Shotgun+Pistol, SNIPERS Sniper, PISTOLS Pistol, KNIVES Knife, AXES Axe; weighted, never
  the same kit twice in a row; a kit is only drawn when all its weapons are in GameConfig.Guns). DuelServer sets the
  player attribute `DuelKit` before each load and workspace `DuelKit` to the kit name; the duel's `Inventory` builds the
  life from it (no bandages: `Duel.Bandages = 0`); the round notice reads "ROUND 3 · SNIPERS". Picker checked over
  200 draws (no repeats).
- **Melee** (5 Nov late): GameConfig.Guns.Axe (the zombies place's axe, viewmodel, world gun and sounds copied over)
  and a new Knife (part-built model in `Assets.PackGuns.Knife` and `Assets.ViewModels.Knife`, pack Slash1/Equip/Idle
  clips for other players). Axe 55 a hit, 2 body hits; knife 34 a hit, 3 body hits, silent, kills outright from behind.
  Melee hits on players go through the lag-compensated player-hit path (`Validation.Pvp.Melee`). A life spawns holding
  its first carried weapon. Random kits are pure: `Kit.Resolve` gives no frags, flares or field item when `DuelKit` is
  set; round 1 keeps the player's own gear.
- **Attachments and gun weight** ported from the campaign into the duel copies of GunClient, GunServer, Hotbar,
  Profile and Shared.Attachments.
- **Spawns** (no spawn camping): `Map.Spawns` A1-A7 spread over end A's third of the yard (B1-B7 = the same spots
  turned half round). DuelServer `pickSpawns` draws a fresh pair each round: never a player's last pad at that end,
  never a pair with eye-height line of sight against `Map.Collision` (0 of 49 pairs see each other today).
- **Map pass 2** (`last-light/blender/duel-yard`): decluttered (18 props cut), recoloured to the refs, B side made exact
  copies of A, weathering decals and an invented ORVALE LINES logo/billboard (62 decals), paler hazy sky. Tyre walls,
  tarp cubes, billboards, helicopter and water tower are in `out/DuelYard_Additions.fbx`: **the owner imports it, then
  pastes `place_yard.luau`** (IMPORT-ME.md).
- **Lighting:** `Lighting.Technology` is gone from Studio; LightingStyle = Realistic with PrioritizeLightingQuality is
  the old Future. Set in the Multiplayer place.
- **Missing folder fixed:** the duel copy had lost the empty `workspace.Fx` folder; CombatFx (and with it the gun
  client) waited on it forever. Recreated.
- **HUD:** the menu session ("Main menu overhaul plan") is restyling HUD, MatchHud and DuelClient to the lobby look;
  sync its files into src/duel when it reports.
- **Netcode pass** (lag compensation, hitboxes, movement, touch and controller leniency): `HitHistory` (60 Hz, 1 s of
  every player's parts), each shot carries its server time, GunServer rewinds the target to what the shooter saw (capped
  at ping + 0.1 s + slack, 0.25 s max), only R15 body parts are hitboxes (gear and held guns pass through), PvP damage
  zones per gun, touch players get tighter tolerances only after 5 s of stable touch input, controller/touch aim assist
  scaled down against players (PC none), jump cooldown 0.45 s, air spread, slide 32 speed with 1.2 s cooldown, a real
  crouch pose other players see (`Shared.CrouchPose`), flinch cut to 30%. Numbers in `GameConfig.Validation.Pvp`,
  `GameConfig.Pvp`, `GameConfig.Movement`, `GameConfig.Evade`.
- **Tested:** solo Play in the duel place: the server boots, WaveState DuelWait, the player spawns at end A with
  full health. **Not tested:** a real two-player match, the end screen, the lobby teleport (needs the published game).
- **Server size:** the duel place's max players was set to 2 through Open Cloud (was 50).
- **Tested (solo Play, 5 Nov late):** spawn on a spread pad, own loadout in round 1, Knife / Axe / Sniper kits load
  with the right weapon and viewmodel, knife kit has no gear, no script errors.
- **Owner to do:** import `DuelYard_Additions.fbx` and paste `place_yard.luau`; save the Multiplayer and lobby places;
  publish both; play a 1v1 with a second account (melee hits, backstabs, spawn pairs, lag compensation).

## 6 Nov 2026 (later): FRONTLINE is the multiplayer mode; the map cut to four sectors
- **Lobby:** FRONTLINE is the first PLAY card and the default pick, labelled MULTIPLAYER (chips "MULTIPLAYER",
  "12 V 12", "4 SECTORS"). Its chapter tabs and mission tiles are hidden, and the loading screen says MULTIPLAYER · 12 V 12.
  The internal id stays "Campaign" so saves, teleports and MenuServer need no change (`Common.Multiplayer(id)`).
  Tested in lobby Play. The live game shows CAMPAIGN until the lobby is published.
- **Map cut** (plan and log: `docs/FRONTLINE-MAP-PLAN.md`): four sectors (Road, Depot, Plaza, Yards), new spawn groups
  `Map.War.FL_<Sector>_Attack` and `FL_<Sector>_Rear` so every walk to a flag is 80 to 100 studs, play boxes with a
  RETURN TO THE FIGHT countdown and then 20 damage a second (`Front.Bounds`, `FrontServer.boundsTick`), new end
  walls at z 300 and z -185, 59 lone props and 5 floor pines deleted. Tested solo in Play. The map edits live in the
  place: **the owner must save and publish the campaign place.**
- **Building cut (later):** unused buildings deleted by a clear rule (see the map plan), about 1,000 parts; the map is
  about 2,900 parts now. Street lamps lost with the houses were put back. Still only in Studio until the owner saves.
- **Next:** the landmark and colour pass per sector, and re-laying the Road field's short wall pieces into clear lines.

## 6 Nov 2026: FRONTLINE built (passes 1, 2, 3 and 5); the campaign place now plays a 12 v 12 push
Plan: `horror-shooter/war/FRONTLINE-PLAN.md`. Every number is in `Shared.Front` (campaign).
- **The match (`FrontServer`, `FrontBattle`):** HOUND attacks, the Lamplighters defend, three sectors in a row from
  the Road, Depot, Plaza, Yards and Basin. Each side has 12 bodies, players first and bots for the rest. Players
  respawn on waves. Attackers have tickets per sector, refunded and given more time when they take one. Sides swap
  every match. The old story campaign is off: `WarServer` only runs if workspace `PlayCampaign` is set.
- **The flag:** a pole with a neon ring of the capture radius, built at each sector under `Map.WarDressing`. The
  cloth rises and falls with progress, and the ring takes the contest colour.
- **PvP:** players can shoot players and bots of the other side (`GunServer`, `GunClient`). Kill credit uses
  `LastHitBy` and `LastHitAt`. There are no down states in FRONTLINE (`PlayerHealth.Rules.NoDown`).
- **Killstreaks (`FrontStreaks`, `FrontClient`):** SPOTTER at 3 kills, MORTARS at 5 and ARMOUR at 8, in one life.
  One key calls the best ready one: Controls "Streak", default 5 on keyboard and the right stick on a pad. Z was the
  first pick, but saved binds put Bandage there. The plates `HUD.Gear.Streak` and `TouchControls.Streak` are clones of
  the authored Field plate. They use the Mark, ReconFlare and Charge gear icons as stand-ins until streak icons exist.
- **Teammates:** other players on your side get an outline in the side colour and keep their name tags. Foes lose theirs.
- **The Front (pass 5, `FrontWeek` + lobby `FrontBoard`):** a universe-wide count of sectors taken this week (store
  `FrontWeek_v1`, Studio uses `FrontWeek_Studio_v1`). At 2,500, players that week get SIGNAL CAMO. The lobby card shows
  the count.
- **Lobby:** the Campaign card is now FRONTLINE with the chips "12 V 12", "5 SECTORS" and "BOTS FILL IN". It teleports
  to public servers (`ShouldReserveServer = false`) so squads meet other players.
- **Tested in Studio Play (solo with bots):** a full match ran, sides swapped, the flag built and painted, and
  SPOTTER, MORTARS (credited a kill) and ARMOUR (a tank drove to the flag) all worked. There were no script errors.
  **Not tested:** two or more real players, PvP kill credit between players, and the weekly reward grant. Pass 4
  (balance) needs a live test.
- **Known:** bots fight over the flag but rarely capture it alone. That is intended, since bot weight is capped. The
  map is too big and too cluttered for this mode (owner, 6 Nov). A map plan is next.
- **Tooling:** `tools/split.py --projects-only` rewrites the `$className` of the StarterCharacterScripts and
  StarterPlayerScripts folders to Folder. Fix both by hand after each run.
- **Owner to do:** set the campaign Max Players to 24, rename the place FRONTLINE, make mode-card art and streak
  icons, upload the 194 SFX and run `install_sfx.luau`, publish both places, and run a 2+ player test.

## 5 Nov 2026 (evening): campaign tank, mission flow after the tank, sniper scope, Outbreak as the tutorial
- **Campaign tank model:** `ServerStorage.TankVisual` (in the place) is a stripped, recoloured low-poly Toolbox tank
  (asset 3405685477) split into `Hull` and `Turret` models. `Tank.build()` still makes the physics box, turret ring, hinge
  and hit surfaces, hides them, and welds the visual on (turret pieces to the ring, so it turns and is thrown with it).
  The Lamplighter lamp stays visible. The muzzle moves to the visual's barrel tip.
- **The tank explodes:** `Tank:Wreck` now does a big fireball with two follow-up bursts, a shell-landing shake, the
  turret thrown high, up to 16 loose pieces and 14 pieces of burning shrapnel flung out (they fade after 7 to 10 s), the
  hull kicked up, and a bigger fire.
- **After the tank (the mission looked stuck):** the plaza fight still had about 20 enemies left, arriving one at a
  time from far behind the plaza, and the objective flipped back to ADVANCE TO THE PLAZA. Now the tank's
  `OnDestroyed` calls `Battle.EnemyRush`: at most 4 more of the reserve come straight at the squad, the rest never
  come, the ones on the field push, and a radio line says they are breaking. `guideFight` shows HOLD HERE · MORE ARE
  COMING when nobody is on the field, and moves the marker to the nearest enemy when the fight has moved away.
  Checked in Play (start step 3): after the wreck, 20 left became 9, all close by; when they died the objective moved
  to FIND THE BLOOD IN THE CLINIC. The yards tank (M3_Mid) uses the same code.
- **Sniper scope (campaign and Zombies `GunClient`):** while scoped the shot uses only the gun's aimed spread, shake
  is scaled by the zoom, the scoped kick is 0.45x and the FOV punch 0.25x, and the authored Scope frame moves at runtime
  into its own full-screen `ScopeView` gui so the reticle sits on the true screen centre on notched phones.
- **Heli (both places, by a helper):** a stripped olive Huey as `ReplicatedStorage.Assets.EvacHeli`, and a GRAB LADDER
  ProximityPrompt (hold E / ButtonX) instead of the amber GRAB button. The campaign builds the heli in the War state too.
- **Outbreak is the tutorial mode (lobby):** a TUTORIAL tag on its card, the line "THE TUTORIAL. FIX THE TOWER, FIND
  GUNS, GET TO THE HELICOPTER", and Nightmare and Endless show FINISH THE TUTORIAL while locked. The Zombies place has
  the same line. Outbreak already brings every enemy type, softer and later than Nightmare.
- **Zombies place (not in this repo):** tower siege in HOLD THE HILL (lose if it breaks), guns scattered round town with
  a hidden pistol in the safehouse instead of the gun shop, dog stacking fixed. See `last-light/blender/zombies-place/PATCHES.md`.
- **Not playtested:** the tank and heli seen on screen (screenshots of Play come back dark), the scope while scoped, the
  tower siege, the gun scatter, the dogs, the ladder prompt. All of it needs a save from Studio.

## 5 Nov 2026 (afternoon): squad fixes, teammate weapon animations, ready system, robber hostiles
- **Teammate weapon animations (live):** group-owned (964368511) ids in `GameConfig.Squad.Anims`, in the campaign and the Zombies place:
  Hold 107820513716617, FireRifle 139900330275537, FirePistol 128428459175128, AxeSwing 85930423035296.
  They key the WorldGun's `GunRoot.GunJoint` (and UpperTorso for the axe). Your own character plays Hold (it replicates);
  someone else's recoil plays only on the watching client when their `ShotFx` arrives, so no network per shot.
  Sources: `horror-shooter/squad-art/anims/make_tp_anims.py` and the .rbxmx files next to it.
- **Floating guns fixed:** player avatars use AnimationConstraints, not Motor6Ds; the arm IK (campaign `WorldGunArms`, Zombies `GunClient`) now reads both.
- **Corpses fall:** `MobReactions` tips bodies that land sitting up and ragdolls deaths that skipped a hit; campaign `SoldierView` does the same before freezing.
- **Campaign hostiles** (`ReplicatedStorage.WarRigs` HostileA/B, HeavyA): no uniform; dark street clothes and a balaclava, so they never read as your squad.
- **Lobby:** READY for teammates, DEPLOY for the leader (tells the leader who isn't ready), names on squad plates, wider squad spacing, phone tab bar with framed, labelled tabs.
- **Not tested with two real players.** The Zombies place is not in this repo; its scripts were changed in the place only.
- **Sync note:** Studio's assistant can no longer POST to `tools/syncback.py` (HTTP allowlist). Running `tools/dump.luau` from the Studio command bar still works.

## 5 Nov 2026: lag pass across all three places (ROBLOX-OPTIMIZATION.md in the parent folder)
- **Campaign:** soldier legs animate again (tracks load once the body is in the world). Past 45 studs, SoldierView draws each rifle mesh (about 45k triangles a rifle) as a plain block. The new `DetailLod` client script hides tagged MG-nest rounds and bolts by distance. In the place only: ClientAnimatorThrottling Enabled, PhysicsSteppingMethod Adaptive, Box collision on non-colliding meshes, Precise to Automatic, CastShadow off on small parts.
- **Zombies and lobby (in the place only):** ClientAnimatorThrottling Enabled; Precise to Automatic (zombies 60, lobby 285); small or decorative meshes moved off Default collision (zombies 172 to Hull; lobby 94 Box and 10 Hull). Old values are kept in the `RF_Before` and `CF_Before` attributes.
- **Not done:** PhysicsSteppingMethod Adaptive in Zombies and the lobby; set it in Properties. Studio's command bar in the Zombies window holds an unrun line; clear it.
- **Measuring:** this laptop was overloaded (Blender, three Studios, Defender), so Studio frame times were unreliable. Judge the published game on a clean machine. All of these changes need a save or publish from Studio.

## 4 Nov 2026 (night): controller support, key rebinding, lobby pad navigation, grenades in the campaign
- **Controls** (`Shared.Controls`, common): one table of actions with keyboard and controller defaults, saved per player in
  the `Binds` option. Settings has a CONTROLS section (`Bind_<Action>` rows built by `tools/build_controls_rows.luau`):
  pick a chip, press the new key; a key another action holds swaps over. HUD key labels follow the binds
  (`Controls.Changed`). A touch-only phone gets no CONTROLS rows (rows key off KeyboardEnabled / GamepadEnabled).
  Deliberate shared inputs: B crouches or revives while downed, X reloads or holds to interact, E interacts or revives.
  The emplacement get-off key is Use / Crouch now (was F).
- **Aim assist** (`Shared.AimAssist`): controller and touch only, never mouse. PreferredInput (Shared.Platform) picks the
  layout, so a PC player on a controller gets the controller layout and assist. Settings: AIM ASSIST Standard/Precision/Off,
  CONTROLLER LOOK SPEED.
- **Lobby pad navigation** (`Shared.Menu.Pad`, lobby): focus moves with the stick and D-pad, A presses, B goes back, LB/RB
  switch tabs; a right-stick pointer (Kit/Pointer and Kit/PointerHover PNGs) soft-snaps to buttons and hands focus over
  when it hides. Panels tagged `PadModal` hold focus (Settings). The Loadout turntable owns the right stick on that page;
  LT/RT turn models everywhere. Studio-only test hook: `PlayerGui.MenuPointer.PadTest` BindableFunction.
- **Campaign gear** (ported from the Zombies place, same items, numbers, art and slots): `GearServer`, `GearClient`,
  `Shared.Gear`, `Shared.UiArt` (+Kit/Renders/Atlas), `Modules.Kit`, `Remotes.Gear`, `ReplicatedStorage.Assets.Gear`
  (13 models), `StarterGui.HUD.Gear` plates (at {0.5,126},{1,-34}: the same 3 px off the three-slot hotbar as in Zombies)
  and the Lethal/Tactical/Field touch buttons. The kit is the player's selected lobby loadout (`Rules.Default` = Frag +
  Flare when there is none; no first-match pistol run here). Targets are anything hostile to the thrower's side
  (`WarDamage`): soldiers take hits through `MobReactions.Hit` like bullets, vehicles through `WarDamage.Apply`; squadmates
  are never hurt. Blasts are heard (`Soldier.Noise`), flashbangs suppress soldiers, smoke blinds them (`Soldier:Sees`
  checks `workspace.GearSmoke`), no gear while manning a gun. GunClient stows the gun while a throw is held (`GearReady`).
- **Tested in Play (campaign):** kit Frag/Flare/Smoke from the loadout, HUD plates with icons, counts and G/Q/X labels,
  touch buttons on touch (plates hidden), a frag took a soldier from 130 to 46 and the count dropped, a smoke cloud took
  soldiers seeing me from 12 to 0, no gear errors in the console. Not tested: flashbang and molotov on soldiers, two players.
- **Backups (campaign):** `_Backups.*_2026-11-04_beforeGear` (Soldier, GunClient, HUD, TouchControls),
  `*_2026-11-04_beforeControls`; lobby `*_beforePadNav`.

## 2 Nov 2026 (evening): story mode, tanks, NPC machine gunners (installed in campaign, tested in the copy only)
- **Story** (`Modules.WarStory`, steps in `WarServer`): Captain HALE lies on a stretcher by the crash and is carried up the valley.
  Depot cleared -> FIND MORPHINE FOR HALE (med case at a `MedSpot`-tagged part with attribute `Group`, else a random post; prompt
  "Take", then "Give" on HALE). Plaza taken + its tank destroyed -> FIND BLOOD IN THE CLINIC -> STAY WITH HALE -> he dies (blanket).
  Yards: no more reinforcements. LZ hold: HOUND bots fall one by one with "<NAME> IS DOWN!", last-stand line, "It's just you now"
  when the bird lands. Retry after a wipe refills the squad (`Battle.Refill`).
- **Tanks** (`Modules.Tank`, new): one collider hull, physics drive on PathfindingService paths, servo turret, main gun (shell
  barrage) + coax. Spawns at the plaza and yards (`<group>_Tank` lane if the map has one, else from `<group>_Rear`). Killed by a
  satchel on its back deck (prompt, 4 s fuse). Player bullets do not hurt it yet.
- **NPC gunners** (`Soldier:Gunner`): Support/Rifleman soldiers man a free gun of their side within 45 studs of their post area,
  switch to a target inside the gun's arc, and get off the gun for a close foe outside it. The two enemy MGs were moved from the
  farm (nobody held that ground) to the road defenders' line at (-25,220) and (20,220), crossfire up the road
  (`EnemyMG_RoadWest/East`, both places). Verified firing in the copy (heat rises, guns track the squad).
- **Studio only:** workspace attribute `WarStartStep` (1 Road .. 6 LZ) starts the war at a later step in Studio.
- **Backups:** `_Backups.WarServer_2026-11-02_beforeStory`, `Battle_2026-11-02_beforeStory`, `Soldier_2026-11-02_beforeGunner`,
  `GunClient_2026-11-02_beforeEmplacement` (campaign).
- **Crash intro (installed in the campaign 2 Nov evening, NOT play-tested; opening shot fixed, client hash now 112916859):** `horror-shooter/war/intro/CrashIntro.lua` (ServerStorage.Modules,
  hash 764628056) and `CrashIntroClient.client.lua` (StarterPlayerScripts, hash 80316894), RemoteEvent `Remotes.CrashIntro`, sounds folder
  `ReplicatedStorage.Assets.Sounds.Intro` (EngineDrone 9112812185, Flak 9114362114, Artillery 9113169432, AlarmBell 9113084891, MetalCreak
  9116550501, Tinnitus 112638428800232, Roar 9118747824; Tank needs Artillery and EngineDrone). It sets player attribute `InCutscene`
  (GunClient already hides for it). WarServer already calls it if the module exists. Opening shot A1 now sits 8 studs above the snow rim at the south
  edge (it was inside the rim); the crash-site shot has a clear line to the falling plane. The campaign lighting is overcast day, so the
  'night flight' plays in grey light unless night is set. The crash wreck is a UH-1 helicopter while the story says transport plane.
- **Open:** both-side player slots, player guns vs tanks, MG damage (12 a round at 900 RPM) may be harsh on players,
  map asks (clinic MedSpots, tank lanes, M3_LZ_Rear, asset 188608071 not approved, 203785492 wrong type), not play-tested by a person.

## 2 Nov 2026 (afternoon): War v2, light soldiers (installed in campaign, tested in the copy only)
- **Why:** the owner said the game was extremely laggy. Each soldier was a full physics R15 (63-121 parts), about 2,900 simulated parts for 24 soldiers.
- **What changed** (contracts in `horror-shooter/war/WAR-V2-CONTRACTS.md`):
  - `Modules.Soldier` v2: a soldier is two invisible anchored parts (HumanoidRootPart hitbox, Head) and a Humanoid with no state machine. One Heartbeat loop walks them all and writes CFrames at 20 Hz. Roles per fireteam (Leader, Rifleman, Support, Assault, Marksman): holders hang back, assault pushes and flanks. Spread scaled by 0.65 (they shoot well). Fights players of either side (player attribute `Side`).
  - `StarterPlayerScripts.SoldierView` (new, replaces SoldierPose): draws each soldier from `ReplicatedStorage.WarRigs` (trimmed SoldierRigs, 26-28 parts, nothing collides), walk/idle anims, kneel, waist aim, fall and fade, distance LOD (hidden past 380 studs).
  - `Modules.WarDamage` (new): one damage API for emplacements, shells and vehicles.
  - `MobReactions.Hit`: light bodies get blood and voice only (no limb/stagger/knockback).
  - `GunClient`: right-click fix (no gun swap from scroll while aiming or zero scroll; aim latch can't stick), far gunfire culled past 500 studs. `PromptLook`: prompts only take clicks on touch.
- **Measured in the test copy** (PC at 94% CPU with 4 Studios): server physics step 19-56 ms -> 0.5 ms, heartbeat 20.5 ms -> 1.2 ms, server soldier parts about 2,000 -> 46, drawn soldier parts about 2,900 -> 622. Bots took the road and fought into the depot with no errors. Shots in `horror-shooter/war/shots/`.
- **Backups:** `ServerStorage._Backups.*_2026-11-02_beforeV2` in both the copy and the campaign; v1 files on disk in `horror-shooter/war/_v1/`.
- **Install trick:** `python -m http.server 8765 --bind 127.0.0.1` in `horror-shooter/war`, then in Studio flip `HttpService.HttpEnabled` on, `GetAsync` the file, `UpdateSourceAsync`, flip it back.
- **In progress (helpers, test copy only):** plane-crash intro (`war/intro/`, CrashIntro + CrashIntroClient) and mounted MGs + artillery (`war/emplacements/`). Then: NPCs man the MGs, tanks, both-side player slots, the story (commander hurt, find medicine, he dies, squad wiped, escape alone).

## 2 Nov 2026: menu revamp (lobby place), design finished, build stopped early by the usage limit
- **Goal (owner):** a strong menu where players choose classes, guns and gear; modes as cards; a good store with good
  monetization; authored PNG GUI; Toolbox models. The Modern Warfare reference is `horror-shooter/MW-REFERENCE.md`.
- **Docs, all in `horror-shooter/menu/`:**
  - `MENU-PLAN.md` is the design. Section 9 (9.1-9.11) holds the final decisions after two critique runs and overrides
    the older sections.
  - `CONTRACTS.md` holds the interfaces, stream ownership and Studio rules. The campaign session owns WarServer,
    Modules.Soldier, SoldierPose, WarClient and GameConfig.War in both places, and nobody else edits them.
  - `CURRENT-STATE.md` describes what exists today. `CRITIQUE.md` holds the critiques.
  - `notes/<STREAM>.md` is each build stream's log.
- **Built so far (lobby Studio only; nothing in the campaign place changed):**
  - CORE: `Shared.Menu.Router`, `Ui`, `UiSound`, `Shared.UiArt`, stub `Modules.Progression` and `Modules.Kit`,
    `ServerStorage.Events.StartMatch` and `MatchEnded`, empty `StarterGui.Menu.Wide/Phone/Templates` containers
    (hidden), `StarterPlayerScripts.MenuPages` (empty). The art pipeline is `art/layerkit.py`. CORE is tested in Edit.
  - MODELS: nine third-person world guns in `ServerStorage.ArtStaging.WorldGuns` (AK, Shotgun, Sniper, Pistol, MP5,
    M4, HandCannon, SR25, M60). They are stripped of scripts, retextured, have a grip, muzzle and left-hand attachment,
    and tag their camo parts `Body`. Notes are in `notes/MODELS.md`. Four stripped raw grenade and flare models wait in
    `ArtStaging._Inbox`.
  - DATA: `Shared.Progression` written (requires cleanly); `Shared.Catalogue` not yet. Item ids are `<Kind>/<Id>`.
  - CHROME: `art/components.py` (the design system) written. No art sheets have been rendered or uploaded yet.
- **The game still runs the old menu and old systems**: Profile v1, the old StoreServer and MenuServer. The new pieces
  are unused until the front end is wired, so nothing is broken.
- **Removed:** a hidden Toolbox `LightConfig` script inside `Workspace."Dead Police".Head.Handle.Mesh`.
- **NEXT:** resume the build workflow.
  - The script is `.claude/projects/C--Users-PC-Documents-snailvs-snail/d6902f54-.../workflows/scripts/last-light-menu-build-wf_65af5c72-2f5.js`.
  - No stream finished, so every stream re-runs. Each stream reads its own notes and skips what is already built.
  - Order: DATA, MODELS and CHROME, then GUNS, MATCH and RENDERS, then SCREENS A-C, FRONT A-C and INTEGRATION.
  - Show the owner the art sheets before wiring.
  - Then run the PLAYTEST.md play test, then mirror to the campaign place after messaging the campaign session.
- **Owner actions:**
  - Create the products and passes from MENU-PLAN 4.9 in Creator Hub, or sign in to Roblox in the browser pane.
  - Turn on private servers.
  - Set the campaign place's Max Players to 12.
  - Ctrl+S, then publish both places together once Profile v2 lands.

## 2 Nov 2026: 12-v-12 battle AI in the campaign place (installed, NOT play-tested)
- What it does: HOUND has 12 slots (callsigns REYES to VOSS). Each slot is a bot until a player takes it. A player who joins replaces a bot, and a player who leaves hands the slot back to a bot. HOUND fights up to 12 Lamplighters at once, with a reserve for each step. Soldiers use cover found by a ray survey. They kneel behind half cover, peek and fire, suppress, leapfrog, flank, fall back when hurt and heal out of the fight.
- Installed in campaign Studio (Edit mode, hash-verified):
  - ServerStorage.Modules.Battle (new)
  - ServerStorage.Modules.CoverMap (new)
  - ServerStorage.Modules.Soldier (new brain)
  - ServerScriptService.WarServer (its steps call Battle)
  - StarterPlayerScripts.SoldierPose (the kneel)
  - GameConfig.War.Battle (all tuning)
- Backups: ServerStorage._Backups/*_2026-11-02_beforeBattle.
- Local copies are in horror-shooter/war/battle/. The design is in horror-shooter/war/BATTLE-PLAN.md.
- Cover survey (Edit mode, 147 spots in 3.2 s): M1_Road 0, M3_LZ 0, M3_Road 1, Start 4, M2_Hold 6, M2_Plaza 7, M1_Depot 12, M2_Road 42, M3_Mid 41. The map session was asked for 8-12 half-cover and 3-5 full-cover pieces per fight area. Without cover, soldiers fight in the open.
- NEXT: run a short Play test (ask the map session first, because Play blocks their Edit work). Check that:
  - the bots take the road and the depot on their own;
  - joining and leaving swaps a bot and a player;
  - a wipe restarts the step;
  - the kneel looks right;
  - the output has no "Soldier ...: err" lines;
  - 24 soldiers run smoothly.
  Then tune damage and pool sizes.
- A code review of the battle files was cut short by the usage limit and wrote nothing. Run a fresh review of war/battle/ before trusting the brain.
- Owner: Ctrl+S and publish both places, set the campaign's Max Players to 12, and rename the campaign place "Operation Last Light".


## 1 Nov night (newest): Operation Last Light is its own place, the lobby has CAMPAIGN, and the store works

The owner asked for a full game: "build the map, model, be a full game dev add monetization. make the entire game,
with its modes!" and "retexture and rebuild the war mp so its unrecognizable". Design notes for the campaign are in
HORROR-SHOOTER-WAR.md (its top section is the as-built state). Local mirrors of the new scripts are in
`horror-shooter/war/` (WarServer.server.lua, GameConfig_War.lua, store/).

### The campaign place: Operation Last Light

- **Place:** placeId 78870312741411 in the same universe (the Studio window titled "Bazooka_1244's Place:
  11022026_1"; rename it to "Operation Last Light" in Creator Hub). The lobby is 79455872202749.
- **Map:** `Map.Battlefield` is the war map, cleaned up (28 leaves and 113 roof crates removed, bark darkened), under
  snow (`StarterPlayerScripts.SnowFx`) and Atmosphere Density 0.33, Haze 1.6.
- **Dressing (`Map.WarDressing`):**
  - RelayMast in the plaza. The cabinet's Lamp1-4 are red, and turn green once someone patches in.
  - LZPad with a concrete Deck (ring and H) and its CallStation.
  - DownedBird (burning), sandbags, cars, wrecks, SupplyCrates (ammo), 8 street lamps and 5 fire barrels.
  - Prop templates are in `ServerStorage.WarProps`.
- **Spots (`Map.War` parts):** Start, Checkpoint1-3, M1_Road, M1_Depot (spot 4 has Kind Heavy), M2_Plaza, M2_Hold,
  M2_Road, M3_Mid, M3_LZ and M3_Road.
- **ServerScriptService.WarServer runs six steps over three missions:**
  - HOT DROP: the road, then the depot.
  - SIGNAL: take the plaza, patch into the mast (hold E 3 s), then hold the mast for 90 s of transmitting.
  - LAST LIGHT: the yards, clear the LZ, call the bird (hold E 1.5 s at the CallStation), hold the pad for 45 s,
    then GRAB the ladder.
  - A wipe restarts the step from its checkpoint.
  - The end: the Rescue cutscene and the Scrip, then `TeleportAsync` back to the lobby. In Studio the teleport fails,
    so the run starts over.
- **Kit:** this place's `GameConfig.Inventory.Start` and `Loadout` order put the AK first, so every life starts with
  the AK in hand, plus the Pistol and a Bandage.
  - Trap: a server-side GunsApi "Equip" does not move GunClient, which picks `Loadout[1]` on every spawn. That is why
    the kit lives in config.
- **Turned off in this place:** MatchServer, BeaconServer, PartsServer and DogServer, and the client BeaconAudio and
  BeaconClient (there is no Beacon here).
  - Empty `workspace.Dogs` and `workspace.Zombies` folders keep the shared client scripts from waiting forever.
- **Soldier rigs** (Toolbox, retextured) are in `ServerStorage.SoldierRigs`. Their tiny chest Border mesh (archived
  asset 4785764674) was removed.
- **Tested in Play (solo, flow forced from the server):**
  - The whole run to the bird, including the call, the hold, the GRAB and the rescue.
  - Scrip went 850 → 1400, then the Studio restart.
  - A missed bird loops back to CALL THE BIRD.
  - Kit verified: the AK in hand on both sides, 30/180.
- **Test trap:** a ProximityPrompt only shows when it's in the camera's view. A test character teleported next to the
  CallStation saw nothing until the camera was turned to it (`camera.CFrame = CFrame.lookAt(...)`).

### The lobby menu (main place)

- **The list now reads:** CAMPAIGN (tag OPERATION LAST LIGHT), ZOMBIES (the Play button with its text renamed, mode
  tag DEFEND), MODES, SHOP, SETTINGS.
  - Rows are 0.165 tall so five fit.
  - `placeTag(button, tagName)` places any tag after its word.
- **CAMPAIGN:** a fade to black, then MenuServer "Campaign" calls `TeleportAsync` to
  `GameConfig.War.Campaign.PlaceId`. That's public matchmaking, so joiners take NPC slots.
  - If the teleport fails, the menu gets "CampaignFailed" and fades back. In Studio it always fails ("Request Context
    Failure").
- **The main place's GameConfig.War** now has the Campaign table too (a copy of the campaign place's).
- **Backups:** `_2026-11-01_beforeCampaign` (GameConfig, MenuClient, MenuServer).

### Monetization (both places)

- **Classes are what Scrip buys.** `ReplicatedStorage.Shared.Classes.Perk(player, key)` reads the player attribute
  Class. Hooks:
  - BeaconServer: footsteps heard (Noise) and the Seen meter (SeenFill).
  - PlayerHealth and PlayerHealthClient: SelfReviveTime.
  - FallDamage: FallDamage.
  - GunClient: the recoil kick (Recoil).
  - MatchServer: board repair points (RepairPoints).
  - The perk lines were shortened to fit one line after the class name.
- **Scrip comes in from:**
  - `Profile.Earn(player, amount)`, which adds `Scrip.VipBonus` (+20%) for VIP. Used by the Outbreak bank, the
    campaign's mission pay and completion, and the new match payout.
  - The match payout, `payScrip` in MatchServer, for Defend, Nightmare and Endless at match end: PerNight (or
    PerWave) × nights survived, plus 2.5% of the points earned, plus Escape for those aboard.
  - Points now keeps a `PointsEarned` attribute per match.
- **ServerScriptService.StoreServer:**
  - `ProcessReceipt`: the starter pack (+1000 Scrip, once), class products, and revive tokens (counted only). Each is
    granted once (Profile receipts) and `SaveNow` runs before it says granted.
  - The VIP pass is checked on join and on `PromptGamePassPurchaseFinished`.
  - It counts in-match deaths.
  - `Remotes.Store` "Class" (pick, or buy for 2500 Scrip; refused in a match) and "Offer" (the starter pack, once,
    after the first escape or the 3rd death).
- **StarterPlayerScripts.VipTag:** a gold [VIP] before VIP names in chat.
- **Menu, SHOP page:**
  - STARTER PACK, VIP and CLASSES rows with amber tags, and the Scrip balance after the title.
  - A Robux row shows only once its id is set. The bought pack leaves the list.
- **Menu, CLASSES page** (cloned from MODES):
  - Each class has the pick mark and one line: the perk once owned, the price plus the perk before.
  - Buying with Scrip takes a second click ("CLICK AGAIN TO BUY", amber).
  - When short: "NEED 2,500 SCRIP", or the Robux prompt if the class has a product.
  - After a match the menu opens on the SHOP once when the starter pack is due.
- **Tested in Play:**
  - Bought Hunter for 2,500 Scrip through the real UI: the balance went 3,900 → 1,400, Class Hunter, perks 0.7 and
    0.8.
  - "NEED 2,500 SCRIP" shows on Firefighter.
  - A ZOMBIES match starts clean.
  - A forced game over paid 100 Scrip for 4,000 points earned.
  - The Studio save (`LastLightProfile_Studio_v1`) was put back as it was afterwards.
- **Owner to do: create the products, then paste their ids into `GameConfig.Store` in BOTH places:**
  - Starter Pack: developer product, 99 Robux.
  - VIP: game pass, 299 Robux.
  - Hunter, Firefighter, Marksman and Demolition class: developer products, 199 Robux each.
  - Rows stay hidden while an id is 0. Leave Revive at 0: tokens are counted but nothing uses them yet.
- **Backups:**
  - `_2026-11-01_beforeMonetize`: GameConfig, Profile, Points, PlayerHealth, PlayerHealthClient, FallDamage, GunClient,
    BeaconServer, MatchServer and WarServer.
  - `_2026-11-01_beforeShop`: MenuClient.

### Not done

- Set the campaign place's Max Players to 4 and its name in Creator Hub.
- Revive tokens can't be used while downed yet.
- The campaign place's own StarterGui.Menu is the old copy. It's never shown there: the Campaign attribute deploys
  straight in.
- Both places log "rbxassetid://203785492 failed: Asset type does not match" a few times. It isn't in any property or
  script I could read, and it's harmless.
- Not tested: two players in the campaign (slot takeover), a live teleport, and real Robux purchases.
- **Save and publish both places** (Ctrl+S, then File > Publish to Roblox in each window).

## 1 Nov: the death cam, so you see your dog howl over you

The owner said yes to a short death cam. If you die with the police dog at your side, you get about 3.5 s of the body
seen from outside, with the dog sitting beside it howling, before the screen goes black and YOU FELL comes up.
Backups: `ServerStorage._Backups` suffix `_2026-11-01_beforeDeathCam` (PlayerHealthClient, MatchHud, DogServer,
GameConfig).

- **When it plays:** every real death is a devour (the screen has already sunk to black), so the shot opens by lifting
  that black.
  - It plays only when the police dog's `Partner` attribute (DogServer, the UserId of the player at its heel) is
    yours.
  - It never plays after the Beacon takes you (`Taken` / `Grabbed`); that keeps its own grab camera.
  - Anyone else who dies gets the old fade.
- **PlayerHealthClient, section "The death cam":**
  - A Scriptable camera at RenderStep Camera+25 frames the body (UpperTorso) and the dog side by side, from the side
    with more room. The room check is a raycast that ignores the body, the dogs and the zombies; it pulls in at a
    wall, never closer than 1.5 studs.
  - The camera creeps in slowly. The FOV is 50, and 70 is put back at the end.
  - The red hurt edges fade out; the colour stays drained (it reads like a memory).
  - The first-person hide is turned off on your own body (`LocalTransparencyModifier = 0`) for the shot; without that,
    the body was a ghost.
  - Player attributes `DeathCam` and `Cutscene` are up while it runs.
  - It ends early on a respawn (black at once, then the usual lift), when the body is removed (to the menu; the
    camera is left to MenuClient) and in the Rescue.
- **Numbers:** `GameConfig.Player.DeathCam` (Time 3.5, Fade 1.2, Follow, Distance 11, PushIn, Height 2.5, Fov 50).
- **MatchHud.gameOver:** on a loss it waits while `DeathCam` is set, then shows YOU FELL only if `WaveState` is still
  GameOver. YOU FELL fades in together with the final black (one fade), about 3.8 s after the death, and is fully up
  by about 5 s. GameOverTime (9 s) is unchanged, so YOU FELL shows about 4.5 s before the restart.
- **DogServer:**
  - If the dog is more than `GameConfig.Dog.HowlReach` (12) studs from the body when its player dies, it's put beside
    the body at once (`toBody`, under the devour's black). In the first test it was 23 studs off and never made it
    in time.
  - If it still hasn't arrived when its 3 s run ends, the same thing happens.
- **Tested in Play** (solo, the real path: down, devour, death), three runs:
  - The dog howls beside the body for the whole shot, including when it was moved 25 studs away just before the death.
  - The black lifts, the shot holds, then black and YOU FELL.
  - A death in the pre-wave lull respawns cleanly back to first person.
  - Console: only the old warnings.
- **Test trap:** firing `Remotes.Menu "Play"` from a script skips MenuClient.enterGame, so the menu camera
  (`MenuCamera`, FOV 60) keeps the camera. To test, unbind `MenuCamera`, disable the Menu gui and set Custom.
  `require` from execute_luau gets its own copy of the PlayerHealth module, so trigger damage from a temporary
  in-game Script.
- Not verified with two players: a respawn mid-shot, and a Rescue during a shot. Both are handled in code.

## 1 Nov: the dogs are in the game, the police dog howls when its player dies

The owner imported Dog.fbx and ZombieDog.fbx (and a second Hill and RadioCabinet by mistake: same files as the ones
already in the map, deleted). Backups: `ServerStorage._Backups` suffix `_2026-11-01_beforeDogImport` (DogServer,
DogClient) and `_2026-11-01_beforeHowl` (GameConfig, DogRig, DogServer).

- **Templates:** `ServerStorage.Dogs.Dog` and `.ZombieDog`. Import 3D's AnimationController and InitialPoses (100
  CFrameValues, editor only) stripped. Body and Gear wear a `SurfaceAppearance` (ColorMap = the baked texture): with
  SmoothPlastic the coat shone like a plastic toy, matte reads as fur and nylon. Face (eyes and nose) dark glossy
  (20,15,13, Reflectance 0.12), Metal = Metal (200,204,210), MarkerLight a dark lens (28,52,86).
- **DogServer `visibleBox`:** Import 3D hangs the bones off an invisible 2x2x1 `RootPart` round the paws; counting it
  in the bounding box stood the dog a stud off the floor. The box now counts only parts you can see. Measured in
  Play: paws 0.00 studs off the ground.
- **DogClient:** the marker light part itself flashes too (Neon blue on the flash, the dark lens between).
- **Checked in Edit with DogRig on clones:** stand, walk, trot, run, sit, flat, bite and the zombie dog all skin and
  pose properly; the walk at phase 0.5 matches `out_dog/renders/pose_walk50_side.png` (same legs forward, same hind
  leg lifted), so the Roblox import keeps the Blender joint axes.
- **Tested in Play (Defend):** the police dog spawns 6 studs behind, sits after 4 s, follows, breaks off to bite
  zombies at the windows (points credited to the player). Zombie dogs (forced night 3 for the test, reset after):
  a pack of 3 came 28 s later from a town spawn 156 studs off, path-found to the player, two were killed by the
  police dog; the next pack path-found round the trees. No script errors.
- **The howl (owner: "make the dog howl when u die"):** `DogServer.noticeDeath` sees the player it was following
  die (Humanoid.Health 0; leaving alive, as in an escape, does not count) before anything decides the match is
  empty, so the dog isn't removed first. It runs to 2.5 studs from the body, sits facing it with `Pose = "Howl"`
  (DogRig and `blender/dog_pose.py`: the sit, muzzle to the sky, mouth round, ears back) and howls every
  `Dog.HowlGap` 3.8 s for `Dog.HowlTime` 8 s, then follows the next living player (or goes, if nobody is left).
  Sound: `Assets.Sounds.Dog.Howl.Howl1` = Pro Sound Effects "Wolf Howl Single CU" 9120790529 (3.5 s, Pitch
  1.02-1.12 to sit above a wolf). Tested in Play: at the body in 0.4 s, howls at 0.7 s and 4.5 s. Solo, the
  death blackout and YOU FELL cover the screen, so you hear it rather than see it; squadmates see it.
- **Zombie dog eyes (not done in Studio yet):** a Roblox MeshPart takes one colour, and the zombie dog's glowing
  green eyes and dark nose were one mesh (Face), so in the template both are dark for now. `build_dog.py` now
  splits the ghoul's face into `Eyes` and `Nose` (`split_by_material`); `out_dog/ZombieDog.fbx` is rebuilt (body
  unchanged, paws on the ground; old file in `out_dog/prev/`). **Owner re-imports ZombieDog.fbx**, then: replace
  `ServerStorage.Dogs.ZombieDog` with it, strip AnimationController/InitialPoses, Body SurfaceAppearance, `Eyes`
  Neon (200,255,106), `Nose` dark (18,14,12).
- Also seen: someone (the owner) played in the same Play session mid-test; the test guard and forced night were
  removed straight away.

## 1 Nov: Outbreak playtested in Studio Play, fixes, tower lamp glow

Owner: "You test it in Play". Three Play runs (menu clicks via user_mouse_input on `LocalPlayer.PlayerGui.Menu...` paths, prompts via `InputHoldBegin` from the Client datamodel). Note for testing: a ProximityPrompt only shows when it is on screen, so turn the camera to it (RenderStepped lookAt) before holding.

**Works in Play:** the menu Outbreak pick and drop, the HUD clock and one-line text (RADIO · HARDWARE STORE, HOLD THE RADIO n, GRAB THE LADDER), the crate refill (reserve 5 to 60), Hold contract (60 s at the post, pays 150 Carried), banking at a post (Scrip 0 to 150), Hunt contract (5 targets about 150 studs out, killing them pays), the Beacon wake, birds opening all 3 pad prompts, calling the bird to the roof pad (it hovers over the roof, ladder down to roof level), the respawn after 12 s.

**Fixed:**
- The hot drop killed you before the menu fade cleared (zombies awake at 31-44 studs, landing on the same insertion on respawn = spawn camp). Now the drop zombies spawn asleep and `wake` after `Outbreak.HotDrop.Delay` (5 s; a shot or walking within 26 studs wakes them sooner); measured: still for 4 s, contact at about 9 s. Every Outbreak landing gets `PlayerHealth.Protect(LandGrace = 4)`. Coming back mid-run you land on the insertion with the fewest awake zombies within 60 studs (`outbreakDrop`), tested: respawned 160 studs from the drop pack.
- A failed run (last bird gone) restarted Outbreak straight away under a black screen (the Defend replay loop). Now an Outbreak game over sends everyone to the menu (`sendToMenu` after `gameOver()` in the main loop).
- Back at the menu the screen stayed grey (PlayerHealthClient kept grading from the destroyed body). `update` now clears HurtColor, the hurt frame and the heartbeat when the character is gone.

**Owner request mid-test:** "the battery needs to be highlighted when its its turn to be activated, same with the other things". WorldGlow `LampGlow`: while a part is out (`PartOut`, lying in town or carried) its lamp on the radio cabinet (Lamp1..4 in `Parts.Order`: Battery, Fuel, Cable, Dish) glows solid amber and pulses, through walls. Checked in Play: Lamp1 amber against three red lamps.

**Escape tested (same day, owner: "Test the escape"):** Main Street pad: call, the bird over the pad, GRAB shows at once, grab accepted, the bird leaves 1.2 s later, Scrip banked (+EscapePay 100), "Unlocked" (card: NIGHTMARE AND ENDLESS UNLOCKED), the rescue cinematic, then the menu. Two more fixes:
- After an escape the first-person pistol floated over the menu (the body is removed alive, so GunClient never hid it). GunClient `update` now also hides the gun when `rootPart.Parent` is nil. Backup `GunClient_2026-11-01_beforeEscapeGunFix`.
- Pressing PLAY again after any trip back to the menu (escape or lost run) left a black screen and no HUD: MenuClient `enterGame` waited for a Humanoid on the old destroyed body (`player.Character` still points at it). It now waits for a character that is in Workspace. Backup `MenuClient_2026-11-01_beforeReplayFix`. Checked: menu, PLAY, HUD and gun back.
- Design note, not changed: in Outbreak the Beacon hunts whoever called the bird from the call until the bird leaves, the same as Defend's breakout. Standing in the open at the pad it catches you right as the bird arrives (BeaconCaughtAt blocks the grab, then you're taken). Real players have to stay out of sight until the bird is overhead. My test character could only escape with the Beacon told to ignore it (character attribute Aboard).
- Testing tips: a ProximityPrompt only shows when on screen and when no nearer prompt on the same key (a zombie's ammo drop) is closer; the bird stays only Hover 9 + Crawl 11 s, so grab from the same script as the call.

**Not tested:** the hilltop pad in Outbreak, two players. Spawn view: you land looking over the wreck (minor). Backups: `MatchServer/GameConfig_2026-11-01_beforePlaytestFix`, `PlayerHealthClient_2026-11-01_beforeMenuGradeFix`, `WorldGlow_2026-11-01_beforeLampGlow`.

Maps (owner asked): all modes share this town. A second map gets its own place in this universe when it is built (shared scripts as Packages then), not before.

## 1 Nov (latest): Outbreak first playable, Defend strays and the Shop part (wired, NOT playtested)

Owner: "Wire them up" (the map overlay below). Everything was checked in Edit only (loadstring syntax checks, a scan for undefined calls, a define-before-use check). Nothing has run in Play yet. Backups in `ServerStorage._Backups` with the suffix `_2026-11-01_beforeOutbreak` (MatchServer, GameConfig, MatchHud, WorldGlow, RadioVoice, EvadeServer, EvacClient, RescueClient, BeaconServer, PartsServer, and the menu list as `MenuModesList_...`).

**Defend (master plan step 1 pieces):**
- **Strays**: each lull puts `GameConfig.Nights.Strays` (3, +1 per extra player) sleeping walkers on `Map.StraySpawns`, nearest the line from the house to that lull's part (`PartAt`) and at least 40 studs from every player. They wake like the house sleepers (someone within InsideWakeRange, a shot within 70, a hit). Any still asleep at dusk are removed (`clearSleepingStrays` in playNight). Lull spawning now caps on awake zombies only, so strays don't block it. Strays never run (`addZombie(spot, walker)`).
- **Shop part on a first match**: at run start MatchServer sets player attribute `FirstMatch` if Profile `Matches` is 0, then counts the match. PartsServer's `pickSpot` gives the match's first part the spot with attribute FirstMatch (`PartSpots.Shop`) when anyone in the match has FirstMatch. Note: nobody has a Matches count yet, so the owner's next Defend run also counts as a first match.

**Outbreak (new mode, menu MODES > OUTBREAK, not locked):** MatchServer sections "Outbreak: the map" and "Outbreak: the run"; numbers in `GameConfig.Outbreak`. One squad per server for now (no hub, no 12-player squads yet).
- Drop: a random `Insertion` per run; players spawn on its InsertPoint facing town. HotDrop zombies (4 +1 per extra player) spawn awake on its 3 Spawns. The SupplyCrate prompt "Take ammo" refills all your guns (GunsApi GiveAmmo), once per CrateRefill (60 s) per player per crate; too soon flashes the points red ("Broke").
- Streets: Strays (9) asleep at StraySpawns at least 60 studs from everyone, topped up 2 at a time every 20 s. Hunting town zombies (5 +2 per extra player, +3 after 10:00) spawn out of sight via the breakout spawn rule. Zombies toughen every 4 minutes (Wave).
- Contracts: from 0:20 the radio post nearest the squad (not the last one) offers a contract: amber lamp, glow through walls (WorldGlow), prompt "Take contract". They alternate Hold (stay within 22 studs for 60 s while zombies come for it; the timer only runs while someone is there) and Hunt (a pack of 5 tougher sleepers 60-150 studs away, glowing red through walls). Limit 180 s. Pay is 150 Scrip onto every player's carried total (player `Carried`).
- Banking: any radio's prompt reads "Bank" while anyone carries Scrip. It banks your carried Scrip into Profile Scrip; player `Banked` counts it for this run. The nearest radio glows green while you carry. Dying loses carried Scrip; the dead come back on the insertion after 12 s.
- The Beacon wakes at 7:00 (Breakout attribute + reveal time, a radio line, a one-line notice). It looks for players in Outbreak and goes for a called helicopter's pad.
- Helicopter: from 12:00 every landing pad (hilltop = Map.Extraction, Pad2 Main Street, Pad3 roof) has "Call helicopter" (hold 1.5 s). The call lights that pad's flares (the hilltop uses the old red flare) and blinks its strobe, and flies the existing EvacPath to that pad (workspace `EvacZone`; EvacClient, RescueClient, BeaconServer and MatchHud now read it). GRAB the ladder as in the breakout. Whoever is aboard gets carried Scrip + EscapePay (100) banked, the first escape unlocks Nightmare/Endless, the escape cutscene plays for them only, then the menu. Everyone else plays on; the next call opens 45 s after the bird has gone.
- End: at 20:00, once no bird is out, anyone left loses carried Scrip and is taken; the game-over screen reads THE LAST BIRD IS GONE / BANKED n SCRIP.
- HUD (existing labels only): the top-left block shows the time left. The line under it shows the contract (HOLD THE RADIO 42 / GET TO THE RADIO / HUNT · 3 LEFT), the helicopter (HELI 23 · 80M / GRAB THE LADDER), BANK 150 SCRIP, RADIO · GAS STATION, or CALL THE BIRD AT A PAD. Notices: CONTRACT DONE +150, BANKED n SCRIP, CARRIED SCRIP LOST, THE BEACON IS AWAKE, BIRDS ARE FLYING. The radio voice (TTS) says each beat (RadioVoice cue "Radio").
- Hiding (EvadeServer) works in Outbreak. Radio posts are ModelStreamingMode Persistent so their glow shows from anywhere.
- Studio testing: workspace attribute `DebugTimeScale` (say 0.2) shortens the whole run (Beacon at 1:24, birds at 2:24, end at 4:00).

**Next:** the owner playtests Outbreak solo (DebugTimeScale 0.2) and one Defend run (strays, Shop part). Things to watch: the helicopter path to the roof pad (hover 95 studs up, the ladder must reach the roof), the hunt pack's spawn spots, and whether the Beacon's reveal at 7:00 reads without the breakout camera. Later: squads, drop-in limit at 10:00, Fetch/Lure/Rescue contracts, the hub (master plan steps 2 and 3).

## 1 Nov (later): map overlay for Defend and Outbreak (geometry and markers only, no scripts)

Owner: "start building. should we do a new place?" Decision: no new place. This place (79455872202749) stays the start place and holds every mode's map; the hub is a separate place in the same universe later (master plan build step 2, the owner creates it). This pass builds the map pieces HORROR-SHOOTER-MASTER-PLAN.md asks for. Nothing is wired yet: every light added here except the supply crates' is disabled, and no script reads the new tags.

Built (all in Workspace.Map):
- **Apartments fire escape** `Town.Buildings.Apartments.FireEscape` (east face, x 130.75 to 139.4, z 198 to 218): decks at every floor (y 0.05, 9.7, 18.0, 26.3, 34.6, 42.9, 51.18), flights between them. Walking uses invisible collidable "Ramp" parts (attr Walk); the visible "Tread" parts have CanCollide and CanQuery off. A bridge deck at y 51.18 reaches the roof. `FireEscape.RoofRail` runs round the roof edge with a gap where the bridge lands (z 209.8 to 218.2).
- **8 radio contract posts** `Outbreak.RadioPosts.RadioPost_<Building>` (tag RadioPost, attrs PostId, Building, Reserve): olive military crate with a radio, handset, mast and guy wires, a lamp (PointLight "Lamp", disabled) and a "Use" part with Attachment "PromptPoint". FuelStop (-142,236), Shop (-168,290), Clinic (35,284), Police (165,284), Hardware (180,230), Apartments (92,236); reserves AbandonedHouse (-48,236), NeighbourHouse (-70,276). South-row posts face the road (+Z).
- **Landing pads** (tag LandingPad, attrs PadId, Risk): `Map.Extraction` is pad 1, Risk Easy (only the tag and attrs were added). `Outbreak.Pads.Pad2_MainStreet` (-122, 0.25, 257), Risk Fast, unpainted, on the road. `Outbreak.Pads.Pad3_ApartmentsRoof` (112, 51.18, 210), Risk Hard, painted H and ring. Each has an invisible "Zone" cylinder (44 across), 4 FlarePots with "Flare" parts (tag PadFlare, PointLight FlareLight disabled), and a strobe tripod (PointLight StrobeLight disabled).
- **3 insertion points** `Outbreak.Insertions.Insert_West/East/South` (tag Insertion, attrs InsertId W/E/S, Side): a wreck cloned from Town.Props.Cars, sandbags cloned from ArmyCheckpoint.Sandbags1, and a "SupplyCrate" (tag SupplyCrate, attr InsertId) made of two olive crates with ammo cans and an always-on warm PointLight "CrateLight". "InsertPoint" is a 2x0.2x2 invisible marker (tag InsertPoint) facing into town, and "Spawns" holds 3 markers (tag InsertZombieSpawn) 30 to 40 studs ahead. West sits just inside the west roadblock (-194,257), East inside the east roadblock (194,257), South on the hill by the south barrier (-95,130).
- **16 stray spawns** `Map.StraySpawns.Stray1..16` (tag StraySpawn, attr Street Main/South/North): eight on the main street pavements, three on the south lane, five on the north lane, all at least 40 studs from the Defend house and checked clear of props.
- **Shop part spot** `Map.PartSpots.Shop` (-181, 0.82, 327), attr FirstMatch = true (unwired; the plan wants the first match's part here). It is in the normal random pool now. `GameConfig.Radio.Spots.Shop = "the shop"` was added so the radio voice can say it (backup `ServerStorage._Backups.GameConfig_2026-11-01_beforeShopSpot`).
- Moved one DeadTree in Town.Props.Trees (near 150, 208) +10 X to clear the fire escape. Deleted the temporary `_PropStaging` (8 rejected Toolbox candidates).

Not done / next: scripts for posts (contracts), pads (flares, strobe, call-in), insertions (drop players, crate refill), strays (lull spawns), FirstMatch. Then Outbreak's server loop (master plan section 4). Not playtested. Noticed, left alone: the grey jeep in Lot_FuelStop ("МАШИНА ИЗ СТАЛКЕР") is untextured flat grey and should be retextured.

## 1 Nov (late night): an isolated desert town, and store groundwork

Owner: "too many trees on the map itll nuke perfornce make it an isolated desert town", then "remember uis should be authored pngs not scripted slop", then "stop achiving just hard deleted unneeded stuff". Screenshots: `horror-shooter/screens/2026-11-01-desert/`.

- **The desert** (generator `horror-shooter/studio/map_desert_terrain.luau`, replaces `map_ends_terrain.luau`; one chunk row per call):
  - Terrain x -1304..1304, z -1052..1556. Sand (176,148,108) with low dunes by the wall, flat-topped sandstone mesas (156,110,78) from about 420 studs out, and a ring of cliffs near the edge, so the horizon is always mesas. No parts: every landmark is terrain.
  - The road runs flat out to x ±910, where a 9-stud sand drift buries its end.
  - No Ground material: its texture shows as dark holes at night whatever colour it gets.
  - Fixed on the way: Roblox puts the terrain surface at the top voxel's centre plus occupancy × 4. The old generator ignored that, so its land sat 2 studs high and covered the road.
- **Trees:** the forest outside (277 dead trees, 554 parts) is gone. 16 of the 21 dead trees in `Alleys.Beyond` are gone; 5 stay, spread along the strip.
- **The town's grass is desert now:** `Town.Ground.Grass`, `Town.Ground.Hill` and `Alleys.Beyond.GrassNorth` are Sand in the terrain's colour. The small grass bits (parking-lot lines, shop plants, the wall vine) are dry dirt. Each carries a `WasGrass` attribute with its old material and colour.
- **Haze:** the night Atmosphere is a little dustier: Color (50,50,60), Decay (30,27,30). The old values are in its `BeforeDesert` attribute. EditLight only stores Density, so this survives Bright/Restore.
- **Performance:** parts in Workspace went from 6,981 to 6,397. The terrain is mostly flat sand with no grass, so there's far less of it to draw than the hills had.
- **`ServerStorage._Archive` is deleted** (owner's OK): 12 folders, 3,477 parts of leftovers, including an imported Blender house, a police car, the old junk, and today's forest, trees and doors. Nothing referenced it. From now on, unneeded things are destroyed, not archived.
- **Store (plan step 9): groundwork only.**
  - `GameConfig.Scrip`, `.Classes`, `.Store` (every id 0) and `.Analytics` are in. Backup: `GameConfig_2026-11-01_beforeStore`.
  - `Profile` now keeps Scrip, Owned, Class, Flags, the Matches/Deaths/Tokens counters and Receipts, and has `SaveNow`. Backup: `Profile_2026-11-01_beforeStore`.
  - `Profile` also got safer. Several scripts asking at once share one load. A session whose save couldn't be read never saves, so a DataStore hiccup can't wipe a save. Saves coalesce, and BindToClose waits for saves still running.
  - **Not built yet:** StoreServer, the Analytics module, `Shared.Classes`, the perk hooks, the Scrip pay-out at match end, every store screen, and the revive token.
  - I first built a CLASS page, shop rows and a token row from script. They're removed, because UI must be authored PNG art. Menu and HUD match their backups exactly.
  - **Next:** design the store screens as PNGs (class cards, the Starter Pack and VIP offers, the token button), show them to the owner, then wire them.
  - Hook points found for the perks: BeaconServer hearing radius (lines 1124 to 1128) and Seen fill (line 1335); PlayerHealth self-revive (line 328) plus PlayerHealthClient's fill bar (line 386); FallDamage line 30; GunClient recoil (line 979); MatchServer repair points (line 684). Pay Scrip in MatchServer's main loop right after `running = false` (nights or waves survived, a share of points earned, the escape).
  - Revive-token rule worked out: offer it only while down with the bleed-out running and no self-revive left. In solo, the devour starts 0.8 s after nobody is standing, so there's no time for a purchase there.
- **Checked:** Edit-mode screenshots at night from the air, along the road to the drift, and from the helicopter's eye. Raycasts show the road on top of the sand.
- **Not checked:** a play test after the desert, and phone performance.

## 1 Nov (night): new buildings and the map's ends (plan steps 6 to 8)

Owner asked: "make the map better and declutter it... add ends to the map and remove the baseplate... the helicopter doesnt see the base plate or weird stuff". Screenshots: `horror-shooter/screens/2026-11-01-map/` (0 = before).

- **Buildings** (`Map.Town.Buildings`, Toolbox, scripts stripped, retextured to our palette, attribute `Source`):
  - PoliceStation (x 167..225, z 291..369, turned 180°, entry from the east). Its road side is a blank wall (a first pass).
  - Clinic, the octagon pharmacy (x -24..44, z 291..359, front doors archived). Product textures still show real brands; swap those.
  - HardwareStore (x 172..218, z 187..213; the asset came tilted 40°, re-levelled).
  - ArmyCheckpoint (sandbags at x 224 by the east roadblock). The tent is unplaced in `ServerStorage._TownStaging`.
  - New `Map.PartSpots` at each one, all reachable by pathfinding.
  - Trees and doors they replaced are in `ServerStorage._Archive` (`Trees_` / `Doors_2026-11-01_newBuildings`).
- **Baseplate and junk gone:** the Baseplate, a half-built store interior west of the map (about 40 shelves, freezers, lights, floor) and loose trash are in `ServerStorage._Archive["WorkspaceJunk_2026-11-01_mapEnds"]`. No script used the Baseplate. The SpawnLocation stays but is invisible (its decal showed from the air).
- **Land around the town:** Terrain from x -1304..1304, z -1052..1556.
  - Low by the town, rising to hills about 115 tall, with a high rim at the outer edge so the horizon is always hills, and a valley where the road runs out.
  - Grass, LeafyGrass, Ground, Mud and Rock, coloured close to the part grass.
  - Generator: `horror-shooter/studio/map_ends_terrain.luau`. Run one chunk row per call; Studio drops replies to longer calls.
- **The ends:** `Map.Town.Boundary.QuarantineWall`, 332 concrete T-wall sections (x ±236, z -6 and z 384), crossing the road behind both roadblocks.
  - `Boundary.Invisible` holds 4 invisible walls on the same line, 66 tall (rooftop jumps), CanQuery false. They're low enough that the helicopter's climb-out never meets them.
  - The north backyard fence was trimmed where it ran past the side walls.
- **Outside:** `Map.Surroundings.Forest` has 277 dead trees (the town's tree mesh, scaled 0.85 to 1.7, no shadows beyond 50 studs).
  - `Map.Surroundings.Road` extends the main road to x ±910, with lane dashes to ±630.
- **Declutter:**
  - 36 town trees archived (`_Archive["Trees_2026-11-01_mapEnds"]`): 29 along the old edges where the wall now is, 7 growing through buildings.
  - The Alleys.Beyond trees were moved off the north wall.
  - The dumpster and its hide spot that the police station landed on moved to (161, 367). All 13 dumpster hide spots are kept.
- **Helicopter and lineup:**
  - The escape shots (RescueClient, eye at about (-133, 46, 76), looking north-west and up) now see hills and forest.
  - The attire lineup used to stand on the baseplate. `ReplicatedStorage.Assets.AttireLineup` moved to z -6000 with its own dark `Stage` part.
  - RescueClient `LINEUP` constant updated; backup `RescueClient_2026-11-01_beforeMapEnds`.
- **Checked:** night and day screenshots from the ground, the hill, the helicopter's camera and the lineup camera. A play test reached the menu with no new errors.
- **Not checked:** a full match out to the escape cutscene; how the terrain and 277 trees run on a phone.

## 1 Nov (latest): the full game plan, no build

**START with `HORROR-SHOOTER-MASTER-PLAN.md`.** It audits today's build (16 weaknesses with fixes), rebuilds Defend to 5 nights / 75 s lulls / zombies in 5 s, adds the safehouse hub with squad pads, Outbreak (12-player extraction, hot drop, contracts, shared exfil), Operations (L4D push, update 1), the HUD decision, 16 launch guns, 8 classes, enemies, meta, money, ads and the 2k CCU path. Sims: `last-light/sim/match_play_sim.py` (every mode played by teen / 6yo / impatient 10yo, 12-variant sweep), `mode_sim.py`, `money_sim.py`. `HORROR-SHOOTER-MODES-2K.md` holds the chart research. Nothing in Studio changed.

## 1 Nov (late): mode plan for 2k CCU, no build

`HORROR-SHOOTER-MODES-2K.md` is the plan: hub with squad pads (16 players) → reserved match servers; new **Outbreak** mode (open-town extraction, 12 players in 3 squads, contracts, Beacon wakes at 7 min, shared helicopter exfil, drop-in); **Operations** (L4D-style 4-player push) as the second update; Horde Arena dropped, Convoy Rush deferred to a contract. Backed by `last-light/sim/mode_sim.py` (10 mode mixes, 30-day cohorts) and the 31 Oct zombie chart. Nothing in Studio changed.

## 1 Nov (latest): the police dog, zombie dogs and runners (plan step 4 and 5)

Backups: `ServerStorage._Backups` suffix `_2026-11-01_beforeDog` (GameConfig, MatchServer, SquadVoiceClient).

- **Blender dogs** (`horror-shooter/blender/build_dog.py`, renders via `render_dog.py`, notes in `blender/IMPORT-ME.md`):
  - `out_dog/Dog.fbx`: German Shepherd, about 10k tris body, coat baked from a 190k-tri mesh, black POLICE vest with a
    grab handle, blue marker light, collar with a badge tag. 16-bone rig. Renders in `out_dog/renders/`.
  - `out_dog/ZombieDog.fbx`: the gaunt dead version, same rig, glowing green eyes, dark nose. Renders in `out_dog/renders_zombie/`.
  - Fixed this pass: the vest/collar shell threw big black shards (solidify even-offset spikes on cut slivers): now
    `dissolve_degenerate` after the cuts and even offset off. Gear points under the skin are lifted out (26 left, in
    the shoulder creases under the vest, invisible).
  - **Not imported yet: the owner imports both FBX files** (Home > Import 3D, leave where they land). DogServer also
    picks up a model named Dog / ZombieDog lying loose in Workspace and moves it into `ServerStorage.Dogs` at runtime,
    but move them there in Edit so they don't stand in the map.
- **`ReplicatedStorage.Shared.DogRig`**: poses the bones from speed (walk/trot/run blend) and a Pose name (Sit, Lie, Flat,
  Sniff, Bark, Whimper, Bite). Same numbers as `blender/dog_pose.py`.
- **`ServerScriptService.DogServer`** (numbers `GameConfig.Dog`, `GameConfig.ZombieDogs`):
  - One police dog per match (`workspace.Dogs.PoliceDog`) once anyone is in it. Invisible HumanoidRootPart + Humanoid
    added at runtime, collision group `Dogs` (walks through players, not walls). Follows its player at heel, runs
    to catch up, path-finds round walls, is brought back behind them when 90 studs off or stuck 3 s.
  - Chases any Enemy within 22 studs of its player and bites (25 every 0.9 s through `MobReactions.Hit`, GunName "Dog",
    credited to the player, no bullet wounds). Lies flat while they hide, sits when they stand still 4 s, whimpers
    while they're down, barks at the Beacon within 60 studs (never while they hide). Can't die.
  - Zombie dogs: from night 3 while a night runs, a pack of 3 to 5 every 55 to 90 s from a town spawn 70+ studs from
    everyone (max 8 alive). In `workspace.Zombies`, tag Enemy, Kind Dog ("Dogs" callout), 70 HP, speed 21, bite 10.
    They die on their side and fade.
- **`StarterPlayerScripts.DogClient`**: runs DogRig on every dog in `workspace.Dogs` and `workspace.Zombies`, a bite
  lunge on `BiteAt`, and a blue double flash on the MarkerLight part.
- **SquadVoiceClient**: "GoodDog" when the police dog kills (its `KillAt`).
- **Runners** (MatchServer `addZombie`): Kind "Runner" (the "Runners" callout fires now) and orange, brighter eyes
  (`GameConfig.Runner`).
- **Dog sounds** moved to `ReplicatedStorage.Assets.Sounds.Dog` (Bark, Growl, Whine, Yowl, Pant) for SoundKit.
- **Tested in Play with a stand-in box model**: the dog spawns behind the player, follows at heel, sits after 4 s,
  chases and bites a TestZombie to death in about 5 s, no script errors.
- **Not tested**: the real imported model (bone posing, hip height 1.3, facing), zombie dog packs (needs night 3),
  the Beacon bark, hiding, downed whimper.


## 31 Oct (latest): HUD U4 "quiet hybrid" and a settings menu, build step 3 of HORROR-SHOOTER-SIM-REPORT.md

Backups: `ServerStorage._Backups` suffix `_2026-10-31_beforeHudU4` (GameConfig, Profile, GunClient, TouchControls script, Gore, CombatFx, MatchHud, HudScale, BeaconClient, MenuClient, PartsServer, HUD, Menu) plus `TouchControlsGui_2026-10-31_beforeHudU4`.

- **Night ring** (`HUD.Clock`, drawn by MatchHud): top centre. During a night it is blue, fills clockwise and shows the night number; the last night is red. During a lull it is amber, drains and shows the time left (m:ss), and it beats during the last ReturnWarn seconds. It swells when a new night starts. The old Match text hides while the ring shows. The Seen eye (`HUD.Detect`) sits under it at y 74. BeaconClient's shiver keeps the authored Y.
- **Part icon**: while carrying a part (`CarryingPart` on the character), a small amber box to the right of the ring shows the part in a ViewportFrame. `TowerParts` moved from ServerStorage to `ReplicatedStorage.Assets.TowerParts` so the client can clone them (PartsServer updated).
- **World glows** (`StarterPlayerScripts.WorldGlow`): a window that gets torn glows amber for `Hud.WindowGlow` seconds; the radio cabinet glows while you carry a part (`Workspace.Fx.TowerGlow`); when the Beacon is seeing you, the 3 nearest `HideSpot`s within 45 studs glow blue (on their `Cover` prop).
- **Prompt buttons** (`StarterPlayerScripts.PromptLook`): every ProximityPrompt is drawn as one round button with a hold ring next to the thing. Touch shows the hand icon (tap it), PC/gamepad show the key. Action text under it.
- **Radio voice** (`StarterPlayerScripts.RadioVoice`): AudioTextToSpeech through high/low-pass and distortion, so it sounds like a handheld radio. Lines live in `GameConfig.Radio.Lines` (lull, part out with the place name, return, part in with parts left, tower done, last night). Max 2 queued, only in a match.
- **Touch buttons**: Aim, Reload, Jump and Crouch show icons instead of words. Icons uploaded: gear `rbxassetid://78749640810501`, hand `rbxassetid://135680222520165` (`GameConfig.Hud.Icons`).
- **Settings** (gear in the top bar next to the Roblox buttons, P key, or SETTINGS in the main menu):
  - Options in `GameConfig.Settings`: look sensitivity, aim sensitivity, invert Y (touch only), gyro aim (Off / Aiming / Always, phones with a gyroscope only), gyro sensitivity, button size (touch only), field of view 60–90, camera bob, and Blood and gore.
  - Gore off: no blood, no splats, no torn faces, chunks or strands; hits still puff.
  - Saved per player: `ReplicatedStorage.Shared.Options` on the client, `ServerScriptService.SettingsServer` checks and clamps every value and saves through `Profile.SetSettings` (at most once per 2 s, flushed when leaving).
  - Limits: Roblox doesn't let a game write its own camera settings, so invert Y on PC/gamepad and gamepad sensitivity are left to Roblox's own menu.
  - Touch look now runs through our own `LookPad` (right half of the screen) so sensitivity, invert and gyro apply.
- **Tested in Play:** no script errors. Settings open from the menu and the gear; sliders, the gore switch, RESET and BACK work; the server saved the settings. Blue night ring, amber lull ring (0:57 draining), part icon beside the ring and the cabinet glow all checked with screenshots.
- **Not tested:** the radio voice by ear (no errors), window and hiding-spot glows, prompt buttons on screen, gore-off in a fight, touch look / button size (needs ForceTouch), and gyro (needs a real phone; the axis mapping is a guess).
- A console line `rbxassetid://203785492 failed: Asset type does not match` shows in Play. It's not in any script or property in Edit, so it's probably a Toolbox leftover created at runtime. Not chased.

## 31 Oct: parts and the radio tower, build step 2 of HORROR-SHOOTER-SIM-REPORT.md

Backups: `ServerStorage._Backups` suffix `_2026-10-31_beforeParts` (MatchServer, BeaconServer, GameConfig, MatchHud, EvacPath, Extraction). Turn parts off: `GameConfig.Parts.Enabled = false` (the last night goes back to night 7).

- **Imported and placed (owner imported both FBX files):**
  - **Hill:** `Map.Town.Ground.Hill`, at (0, 5.3, 75) turned 180°. Grass, (58,64,44), PreciseConvexDecomposition. FBX imports arrive turned 180° about Y, and the cabinet did too.
    - Raycast probes match the design: 13.6 under the tower and the pad, shoulders 10.8 / 8.2, flat at the road's end.
    - Setting the collision fidelity takes long enough to time out the MCP call, but it still applies.
  - **Cabinet:** `Map.RadioTower.RadioCabinet` (a nested model). Plinth bottom on `CabinetSpot`, door facing the house. Concrete plinth; CorrodedMetal body, hood and louvres; Neon lamps (LampOff red).
  - **Cleanup:** `Map._HillStandIn` deleted.
  - **Trees:** 8 DeadTrees raised onto the slope. The 3 in the tower and pad area were moved to the back slope. Backup: `_Backups` `Trees_2026-10-31_beforeHill`.
  - **Checked:**
    - In Edit, a copy of each part placed in its slot: battery on the left ledge, fuel can on the right, spool beside the plinth, dish on the hood.
    - In Play, a player walks from the yard up the front slope to the cabinet at full speed (16 studs/s, ~3.5 s), then across to the pad.
- **Hill** (`horror-shooter/blender/build_hill.py`, headless Blender, checks pass, 15.6k tris):
  - One closed heightfield mesh 480 × 170, flat top at y 13.6 centred (-8, 94).
  - Front slope reaches the ground at z≈156, the yard spawn is at 160, and the steepest slope is 30°.
  - Low shoulders either side. Past the grass edge (z 90) it covers the grey baseplate.
  - `out/relief.png` is the top-down check. Roblox materials on MeshParts tile in world studs whatever the UVs (tested), so Grass matches the ground.
- **Radio cabinet** (`build_cabinet.py`): plinth 9 × 4.4, steel cabinet, four socket rings with lamps (Lamp1..4 = Battery, Fuel, Cable, Dish), louvres and a conduit. All checks pass; close-ups reviewed (`out/cab_closeup_sheet.png`).
- **Tower**: Toolbox 12223934389 (single mesh, 96 tall), retextured (texture stripped, CorrodedMetal, rust grey). It's at `Map.RadioTower.Tower`, feet on the plateau at (22, 94). `TopLight` on top blinks red once the tower is complete.
- **Parts** (`ServerStorage.TowerParts`, Toolbox, all retextured so they don't look stock; pivots at the bottom centre):
  - Battery: 945971321, charcoal with brass terminals.
  - Fuel: 11184951576 jerry can, corroded olive.
  - Cable: 174738022 spool, black rubber and dark wood.
  - Dish: 11535442, weathered grey.
- **PartsServer** (new Script, `--!strict`, numbers in `GameConfig.Parts`):
  - **When parts come out:** one in each of lulls 2, 3, 5 and 6, plus any lull after 6 while parts are missing. Never two out at once.
  - **Where:** on a random unused spot in `Map.PartSpots` (Apartments, AbandonedHouse, NeighbourHouse, FuelStop forecourt), with an amber light and outline and a "Pick up" prompt.
  - **Carrying:** the part is welded on the back (`CarryOffset`). Reaching `InstallPoint` (within 9 studs) puts it in its slot and turns its lamp green.
  - **Losing it:** a Beacon catch (`ServerStorage.DropPart`, fired by BeaconServer `throwToYard`), death or leaving puts the part back on its spot. A part carried home at night stays carried.
  - **Attributes:** workspace TowerNeed, TowerParts, PartOut, PartAt; character CarryingPart.
  - **Cues:** `PartOut`, `PartIn`, `TowerDone` (for the step 3 HUD; nothing shows them yet).
- **MatchServer**: the last night is the night after TowerParts ≥ TowerNeed (falls back to `Nights.LastNight` without parts). So a part still out when its lull passes pushes the last night back.
- **Helicopter**: `Map.Extraction.Zone` moved to the hilltop pad (-32, 14.3, 94). The plan said the yard, but the yard would put the hover (zone + 44) below the 56-stud house roof. EvacPath is unchanged: in from the west, crawl off north-west, clear of the tower and the house.
- **Beacon**:
  - Parts tagged `BeaconNoGo` count as footprints. `Map.BeaconNoGo` has two boxes over the hill, so it never wades into the slope.
  - Its sleeping spot moved from the hilltop to (-55, 1, 166), left of the yard. The building nearest it is still the abandoned house.
  - It can't climb to the pad, so the pickup is safer from it than the old roadblock was.
- **Side road** now ends at the hill's foot (z 154..246).
- **Studio testing**: the player attribute `DebugPickUp` picks the part up from anywhere (Studio only).
- **Tested in Play** (solo, DebugTimeScale 0.1, auto-player):
  - A full run: battery, fuel, cable and dish came out in lulls 2/3/5/6 and were installed. Night 7 was the last, the breakout and helicopter followed, and the top light blinks.
  - A part carried through a later lull blocks the next one (correct).
  - The drop event and death both put the part back on its spot.
  - Game over resets the tower.
- **Not tested**: a full match on the real hill, the lamps turning green in Play, the prompt by hand, multiplayer, real-speed feel, the helicopter's look over the hilltop.

## 31 Oct (late night): nights and lulls, build step 1 of HORROR-SHOOTER-SIM-REPORT.md

Backups: `ServerStorage._Backups` suffix `_2026-10-31_beforeNights` (MatchServer, BeaconServer, GameConfig, PlayerHealth, BeaconClient, MatchHud, EvadeServer). Switch back to waves: `GameConfig.Nights.Enabled = false`.

- **The loop** (`MatchServer`, numbers in `GameConfig.Nights` and `GameConfig.Director`): start downstairs at the new invisible part `Map.DefendHouse.NightStart` with the sleepers upstairs. After 15 s come 7 timed nights, from 90 s growing 15 s a night (the last one is 210 s), with a 100 s lull after each of the first six. The Endless mode keeps the old waves.
- **Night**: the doors are barred and zombies come through the windows. The director sends them at a share of what the team can kill: each standing player's best carried gun (`Director.Dps`) divided by zombie health, × 0.5, rising 0.05 a night and 0.15 per extra player. At most 6 are alive solo, more with more players and later nights. Health grows 30 a night instead of 40. Spawning stops 8 s before dawn, and the night then waits up to 15 s for the last zombies. `ZombiesLeft` only reaches 0 at dawn, so the wave-clear sting plays once. A player shut outside holds E on a ground-floor door ("Get in", only visible from outside) to be let in.
- **Lull**: WaveState `Intermission`. The doors open quietly, dead players respawn, and up to 3 town zombies roam (+1 per extra player). The Beacon wakes at the first lull and smashes the building next door as its reveal. 20 s before the night the one line "GET BACK TO THE HOUSE" shows (cue `Return`). There's no radio voice yet; that's step 3.
- **Last night**: `workspace.BeaconHome` makes the Beacon pace the road in front of the house. 45 s before the end the helicopter is called (`callEvac`: no door and no reveal), and from there it's the old breakout and GRAB at the old landing zone. Moving the landing zone to the yard is step 2.
- **Beacon catch** (`BeaconServer.throwToYard`): in nights a catch costs 15 % of your points and drops you at `Map.Yard` (10, 160, behind the back door), alive. `BeaconClient` lifts the blackout. A player who is downed when caught is still taken. The lamps now look during nights and lulls. `Seen.Fill` is 0.40 (was 0.55).
- **Solo**: 3 self-revives (`SelfRevivesStart` on the player; `PlayerHealth` gives every new life that many).
- **HUD** (`MatchHud`, text only until step 3): NIGHT n / LAST NIGHT, "DAWN m:ss" during a night, "DUSK m:ss" during a lull; the game-over screen counts nights.
- **Studio testing**: the workspace attribute `DebugTimeScale` (for example 0.1) shortens every night and lull, Studio only. `execute_luau` loads its own copy of modules, so changing GameConfig or PlayerHealth from it doesn't reach the running game; use attributes or instance properties instead.
- **Tested in Play** (solo, time-scaled): the full run of 7 nights and 6 lulls, then the helicopter; the spawn rate on night 1 (about 5 s apart with the pistol); doors barring and opening; the Beacon waking at lull 1; three catches (−15 % each, dropped in the yard alive); the last-night Beacon walk (first try, it dithered at the edge of the house's footprint; its goal moved to the middle of the road); the evac call; the game over and the next run starting. **Not tested**: the "Get in" prompt (test tools can't press prompts), GRAB on the last night, two or more players, and how it plays at real speed.

## 31 Oct (night): dumpster hiding, indoor sight, floating house, touch Roll fix

Backups: `ServerStorage._Backups` suffix `_2026-10-31_beforeDumpsterHide` (EvadeServer, GunClient, Evade, Flashlight) and `TouchLight_2026-10-31_removed`.

- **Dumpsters**: hiding in a dumpster now puts you inside it. `EvadeServer` anchors you low in the dumpster and sets the character attribute `Inside`; every client hides that body. The new `StarterPlayerScripts.HideWatch` lifts your camera behind the dumpster and keeps it turned toward the Beacon; drag (mouse, touch or right stick) to look around, and it drifts back after 1.5 s. While inside, there's no gun and no crosshair, and you can't shoot (`GunClient` treats `Inside` like a cutscene). Jump, roll or the Leave prompt puts you back where you climbed in. Cars still use the old crouch-behind hiding. Tested in Play: in, watch camera, out, and first person is clean afterwards. The first version reset your own body to visible on the way out, which broke first person; `HideWatch` now restores each part's own LocalTransparencyModifier.
- **Indoors**: `BeaconServer` `indoors()` checks for a roof overhead (a raycast up against the town buildings and the house). Indoors, the lamps can't see you at all, even next to a window, and footsteps carry 30 %. A smashed-off roof stops counting.
- **Floating house**: `Map.DefendHouse` had been moved by (−10.8, +25.2, −14.0) at some point after the z-fight backup (it was not a script). It's moved back exactly; floors are at Y 2.5 again and spawns are correct. A stray 100-stud brick mesh hanging at Y 444 inside `Town.Buildings` is archived as `ServerStorage._Archive.FloatingBrickShell_2026-10-31`; it also blocked part of the Beacon's street map.
- **Touch**: the Light button is removed. Both Light and Roll had been calling `ContextActionService:CallFunction`, which game scripts aren't allowed to use, so neither worked on phones. Roll now fires `Evade.TouchRoll` (a BindableEvent).
- **Studio testing**: setting the player attribute `DebugHide` hides you in the nearest spot (Studio only). Prompt presses sent from the test tools don't reach the server.

## 31 Oct (late): fall damage, gem pickups, CoD-style touch buttons, z-fighting

Backups: `ServerStorage._Backups` suffix `_2026-10-31_beforeCodTouch` (TouchControls gui and script, GlowDrops, GameConfig, the removed FireLeft) and `DefendHouse_2026-10-31_beforeZFight`.

- **Fall damage**: `StarterCharacterScripts.FallWatch` measures each fall (peak to landing; teleports over 30 studs a frame, anchoring, Grabbed and Cutscene don't count) and fires `Remotes.Fall`. `ServerScriptService.FallDamage` hurts through `PlayerHealth.Damage`: `GameConfig.Match.FallDamage` = Safe 14 studs, 4 per stud past it. Tested: a 22-stud drop cost 25 health.
- **Kill drops**: shards are now spinning, bobbing amber gems hovering 1.4 studs up. Magnet 20 studs (was 9), pull 70, and once a gem locks on to someone it follows them until collected. Tested: gems spilled 15 studs away flew in.
- **Touch**: the left FIRE button is gone. All buttons are smoky dark circles with thin white rims (Call of Duty Mobile look); FIRE shows a white crosshair icon instead of text. Roblox's own Roll/Light touch buttons are off at the source (`Evade` and `Flashlight` bind with createTouchButton false), so they no longer show on the menu.
- **PC HUD**: `HudScale` moves any top-corner block that sits under Roblox's top-bar buttons down by `GuiService.TopbarInset.Height`.
- **Guide**: the stairs never glow now; only the exit doors.
- **Z-fighting**: 144 flush overlapping face pairs in DefendHouse (axis-aligned blocks) fixed by pushing the smaller part's face out 0.015–0.04 studs; a rescan finds 0. 94 rotated parts (stairs and the like) were not checked.
- **Studio note**: mouse clicks into the Play window were unreliable this pass; the test started the match with `Remotes.Menu:FireServer("Play", "Defend")` from the client.

## 31 Oct: mobile fix, aim fix, glow drops, helicopter escape, modes, Beacon pass 2

The full escape design lives in `HORROR-SHOOTER-ESCAPE.md`. Backups are in `ServerStorage._Backups`, with the suffixes `_2026-10-31_beforeMobileFix` and `_2026-10-31_beforeBeaconPass2`.

- **Mobile**:
  - `TouchControls` now shows whenever touch is enabled and the last input was a touch (Platform.IsTouch alone missed the owner's device).
  - Roblox's jump button is hidden every frame. The buttons have text labels: FIRE, AIM, RELOAD, JUMP, ROLL, LIGHT.
  - `HudScale` scales the HUD down per screen on touch only, with Wave and the zombie count at the top centre. PC keeps the authored layout.
- **Aim**: the viewmodel aligns to the AimPoint position only. The Shotgun's and Sniper's AimPoints face sideways and the AK's backwards, which broke right-click aiming.
- **Kills**: kills spill glowing amber shards (`ServerStorage.Modules.GlowDrops`, `GameConfig.Match.Glow`). Walking near them pulls them in and pays the points.
- **Random spawns**: each match puts the guns on random spots on both floors and the sleeping zombies in random downstairs rooms (`MatchServer` floorSpots, shuffleGuns).
- **Escape**: the police car and radio stand are archived (`ServerStorage._Archive`). A helicopter comes instead.
  - It runs on one shared timeline: `Shared.EvacPath`, `MatchServer` pickup section, `EvacClient`, `RescueClient`.
  - It hovers 44 studs up and drops a 40-stud rope ladder, then crawls off and climbs away to 300+ studs.
  - A GRAB button appears when the ladder is in reach. Grabbing starts the climb shot and the ride.
  - Escaping once unlocks Nightmare and Endless (`Profile.Escaped`, `GameConfig.Modes`, Menu Modes page).
- **The Beacon** (`BeaconServer`, `BeaconClient`, `Shared.BeaconRig`, `BeaconAudio`):
  - **Reveal**: a 5 s cutscene when the doors blow. You're frozen and safe while it tears into the building nearest the house. The camera picks a clear angle by raycast.
  - **Streets only**: it walks the streets and steers around every building footprint (`footprints`, `moveToward`); it never passes through. It walks up to buildings and smashes them from outside, and they're rebuilt each match.
  - **The pickup**: it runs for the landing zone when the helicopter comes, then chases the helicopter and reaches up at it.
  - **Grab**: when it catches you, it bends down, grabs you, and lifts you to its lamps. Teammates see it, and your camera looks up at it. Then the dark closes in. Config: `Caught.Grab`, `Caught.GrabReach`.
  - **Lamps**: the client now draws the lamps, smoothed, with a bright core, a soft halo, and a shadowed spotlight pool the size of what the lamp can see. The server only moves the aim point (`LensXTip`) and sets the lens attributes `LampOn`, `LampColor` and `LampPower`.
  - **Sound**: every Beacon sound plays through `SoundService.Beacon`. Indoors, `BeaconAudio` silences the scan loop and muffles the rest. The scan loop (`Assets.Sounds.Beacon.Siren`) is now the ProSoundEffects servo whir 9119664185 at 0.8 speed; the old siren is archived.
- **Night**: outside is brighter. The saved night values (Lighting `Night_*` attributes, which LightingGuard restores) went to moonlight 2.2, outdoor ambient (118, 128, 155), exposure +0.6 and atmosphere density 0.26. The old values are kept in the Lighting attribute `NightBefore1031`.
- **Guide**: once the doors can be broken, only the doors glow, not the stairs. Its last step is the red flare.
- **Studio testing**: setting `workspace.DebugBreakout = true` in a running match breaks out at once (Studio only).
- **To clean up**: `BeaconServer` `moveToward` still sets a `DebugMove` attribute every frame; delete those two lines. The old `buildHeli` and `placeHeli` in `RescueClient` are unused.
- **Not verified**:
  - The full ladder grab and climb at the new height, by hand.
  - The new scan sound, by ear.
  - Mobile on a real phone.

## Mobile controls (30 Oct, late). Checked in Studio with ForceTouch, not yet on a real phone.

- **Layout**: `StarterGui.TouchControls` holds the buttons; the `TouchControls` LocalScript in StarterPlayerScripts runs them.
  - Right thumb: a big amber Fire button. Around it are Aim (toggle), Reload, Jump, Roll and Light.
  - Left thumb: Roblox's thumbstick, with a small amber Fire above it. Pushing the stick nearly all the way forward sprints (read from `Humanoid.MoveDirection`).
  - The icons are drawn from UI frames, with no text.
- **Fire follows the gun**, set by `GameConfig.Guns.<gun>.TouchFire`:
  - `Hip` (Pistol, Shotgun) fires from the hip.
  - `AimFire` (AK) raises the sights and fires while held.
  - `AimRelease` (Sniper) aims while held and fires on release.
  - Dragging a held Fire button also turns the view.
- **GunClient hook**: GunClient has a `TouchInput` BindableEvent that takes Fire, Aim, Reload, Swap and Sprint.
- **Show and hide**:
  - The controls appear only while the last input was touch, and only during play (not in the menu, a cutscene, or while dead).
  - While they're up, HUD Health and Ammo move to the top corners.
  - Roblox's jump button and the Roll and Flashlight action buttons are hidden.
  - Buttons shrink on screens shorter than 480 px.
- **Testing on PC**: set the player attribute `ForceTouch = true` on the client.
- **Backups**: `ServerStorage._Backups.GunClient_2026-10-30_beforeTouch` and `GameConfig_2026-10-30_beforeTouch`.
- **Not done**:
  - The mobile aim assist (`GameConfig.AimAssist` has numbers but no code yet).
  - A check on a real phone, including whether the new PlayerModule's jump button really hides.

## 30 Oct pass (Beacon vision, evac, attire, fixes). Not playtested in a full match.

The owner's first playtester scored the game **3/10 for fun**. The top suspect is confusion: the owner got stuck upstairs and couldn't find the way. This pass adds route guidance; the next pass should go after pacing and feedback (see the end of this section).

- **Beacon** (`BeaconServer`, `BeaconClient`, `GameConfig.Beacon`):
  - The lamps are its eyes and never deal damage. Standing in a beam fills a Seen meter (`HUD.Detect`, top of the screen).
  - A full meter means a chase, the screen goes black, and you're taken (`PlayerHealth.Take`).
  - Vent windows (steam, lens highlights) are the only time its lenses take damage.
  - Hiding fills the meter at 0; firing from cover shows you briefly.
- **Hide and roll** (`EvadeServer`, `StarterPlayerScripts.Evade`, `GameConfig.Evade`):
  - Hide is E at cars, dumpsters and the police car (Map.HideSpots); Space or jump leaves.
  - Roll is C, LeftCtrl, gamepad B or a touch button.
- **Guide** (`StarterPlayerScripts.Guide`), all amber highlights through walls:
  - the stairs while you're upstairs (house `Stairs` model);
  - the cheapest debris you can afford;
  - the exit doors once the breakout is ready (from wave 3);
  - during the breakout, one hiding spot at a time toward the roadblock.
- **House** scaled 1.2× (backup `ServerStorage._Backups.house_2026-10-30_beforeScale`, also `ZombieSpawns_..._beforeScale`).
  - The ZombieSpawns House and Inside spots were moved to match.
  - The "abandoned house" in Town.Buildings moved 8 studs to −X to keep a gap.
- **Evac** (`MatchServer.rescue`, `StarterPlayerScripts.RescueClient`, `GameConfig.Rescue`): a local helicopter `ReplicatedStorage.Assets.EvacHeli` flies a three-shot cutscene.
  - The model is Toolbox 8771460530. Scripts, logos and a blocked texture were stripped, and it was repainted olive.
  - It has a searchlight, nav lights, a tail strobe and a looped rotor sound (placeholder, Toolbox 18630771616).
- **Attire** (`StarterGui.Attire.Pick`, RescueClient, `Profile`, `Remotes.Attire`): the owner's call is no word list.
  - The only text is "YOU ARE A SOLDIER NOW." / "PICK YOUR ATTIRE." plus a WEAR button.
  - Tap or click a uniform in the Workspace.MilitaryRigs lineup and it gets an amber Highlight; a gamepad uses the D-pad or shoulders.
  - The SWAT rig is hidden locally and Ghillie slides into its spot.
  - WEAR saves the pick, and you wear it from the next spawn.
  - **It is a one-time screen.** MatchServer sends "Attire" only to players with no saved uniform; everyone else goes straight to the menu after the helicopter. If AttireTime runs out, the first uniform is saved.
  - **The lineup is not in the world.** It lives in `ReplicatedStorage.Assets.AttireLineup` (built for a stage at z −800, off the map). RescueClient clones it only while the pick is open.
  - **Workspace tidy (30 Oct):**
    - The play house is now `Workspace.Map.DefendHouse`.
    - `building` → `Map.Town.Buildings.Apartments`; the spare house copy → `Map.Town.Buildings.NeighbourHouse`, with its Debris and WaveDoor tags removed.
    - Moved to `ServerStorage._Archive`: the floating "Puerta" sky structure (43 pieces), the stray Brick_Struct_238, and the off-map Blender house (`BlenderHouse_import`).
    - Deleted the empty mockup folders in Map.
    - Workspace now holds only Map, Beacon, Fx, SpawnLocation and Baseplate.
  - **The menu is a separate screen.** RescueClient turns off `Menu` and its camera for the cutscene and the pick, and MenuClient brings the menu back only on Remotes.Menu "Show".
- **Per-player difficulty**: the `PerPlayer` blocks in `GameConfig.Match`, `.Breakout` and `.Beacon`.
- **Fixes**:
  - **Hotbar:** a full hotbar now lets a gun or bandage pickup replace the gun in your hands, which drops with its ammo (`InteractServer.dropHeld`).
  - **Windows:** one hold re-boards a whole window. The hold takes `Repair.HoldTime + PerBoard × torn boards`.
- **Backups**: `ServerStorage._Backups.*_2026-10-30_beforeVision`.
- **Next, for fun:**
  1. Playtest the full loop with 2 players.
  2. Ask the tester for their 3 worst moments.
  3. Shorten the dead time at the start (wave 1 sooner, zombies at the windows in seconds).
  4. Add stronger hit and kill feedback, plus a reason to come back (unlocks).


A complete picture of the horror shooter for whoever picks it up next: what the game is, the owner's rules, where it takes place (still open), what is built and where, how the systems talk to each other, how to test, and what is left.

**Read these first, in this order:**
1. This file.
2. `HORROR-SHOOTER-BRIEF.md`: the game design (core loop, platforms, style, checklist in section 8).
3. `HORROR-SHOOTER-FEEL.md`: the shooting and gore spec plus a log of every pass (sections 10–13 describe what was built).

---

## 1. The game in one paragraph

**Last Light** (working title) is a co-op PvE horror shooter for Roblox, 1–4 players, PC and phone. The core loop is round-based co-op zombie survival, the proven Call of Duty Zombies loop plus Left 4 Dead's downed/revive. You earn points by shooting, spend them on doors, wall guns, a mystery crate, perks and an upgrade bench, and rounds get harder until everyone is down. The owner wants one building under siege that gets ripped apart over time, and a heavy, punchy, gory-but-not-red shooting feel. The current place is a test range with zombies, four guns and the full gore system. The match loop (rounds, points, buying) is not built yet, and the setting is still open (section 3: haunted mall recommended, Backrooms as a secret level).

- **Place:** placeId `79455872202749`, universe `10773529574` (still named "Untitled Game").
- **Studio:** edited through the Roblox Studio MCP. Studio instance id at the time of writing: `9cda169c-ca17-4257-b2d6-12fb0402ec86` (it changes; list the open Studios to get the current one).
- **Owner's Studio avatar in tests:** `Bazooka_1244`.

---

## 2. Owner rules (do not break these)

**Design**
- **No gimmick core loops.** The core must come from a proven hit; name the hit when you add a mechanic. The owner rejected "monsters weak in light" as a gimmick that "will destroy the game".
- **Make design decisions yourself**, then build and report. The owner does not want to be asked every choice.
- **PC gets no aim assist.** Mobile gets assist (slowdown, gentle magnetism, optional auto-fire). Gamepad gets moderate assist. Numbers are already in `GameConfig.AimAssist`. Detect the platform properly (`Shared.Platform`, `PreferredInput`) and switch live.

**Feel and gore**
- **Feel bar:** the EgorV "How to make gunfire punchy" 7-step method (feel doc section 7). Every gun feels different, with its own fire rate, tracer speed, recoil and reload.
- **Mob blood is green**, never red, so the game stays out of the realistic-blood maturity rating. This covers blood, splats, pools, drops and particles.
- **Limb tearing stays.** Shot limbs loosen, then tear off. Zombies stagger, flash white on hit, and squash.
- **Less gore on faces:** no teeth, red gums or drool on zombie faces. Mobs must fit a dark night (dull skin; the glowing eyes carry the read). The test zombie has a red right eye and a green left eye.
- **No damage counters.** Damage numbers over mobs were built and the owner rejected them ("no damage counters pls"). They are fully removed; don't add them back. The brief also says no floating point numbers for the match points; points tick up quietly in a corner.
- **Details must be intricate.** It's a test game, but every pass is done slowly and properly.

**Assets and UI**
- **Toolbox first** for models and props. Strip every script from Toolbox inserts (some hide fake payload scripts), then change what's needed.
- **UI is authored in StarterGui**, not built by scripts at runtime. UI style: flat and dark with an amber accent, quiet. No helper or explainer text on screen.

**Process**
- **Work in Studio Edit mode** and back up before big changes. Backups go in `ServerStorage._Backups` named `<Name>_<date>_<reason>`.
- **The owner may be playing the same Play session** you are testing in. Studio Play is one shared session, so check before you start or stop Play. Undo every visual test hack (hidden viewmodel, moved camera) right after the screenshot. If they are playing, don't stop Play; ask.
- **Remind the owner to press Ctrl+S** after changes; nothing saves on its own.
- **Speak in plain full sentences** to the owner. Short "caveman" shorthand is hard for them to follow.

---

## 3. Setting: where the game takes place (open decision)

**Not decided yet. The owner must pick before any map work starts.** The test range is a placeholder.

### 3.1 How we got here

| When | Setting | Source |
|---|---|---|
| 28 Oct, brief v2 | **Pinecrest Camp**: an abandoned summer camp in a pine forest at night (cabins → mess hall → lake dock → floodlight tower) | `HORROR-SHOOTER-BRIEF.md` section 4 |
| 28 Oct, later | **One building under siege** that zombies rip apart over time; players hold their ground and repair | Owner direction, feel doc sections 1 and 9 |
| 29 Oct | Owner asked: **"Backrooms or a haunted mall?"** | Owner message, unanswered until this handoff |

The brief still says Pinecrest Camp. Update `HORROR-SHOOTER-BRIEF.md` section 4 once the owner picks.

### 3.2 The two options

**The Backrooms.**
- **What it is:** the internet horror story (2019 onward, made famous by Kane Pixels' videos) about "no-clipping" out of reality into an endless maze of empty office rooms. The rooms have yellow wallpaper, damp carpet and humming fluorescent lights. The first area is called Level 0, and deeper levels have their own looks.
- **On Roblox:** a proven horror theme, with several big Backrooms games (Apeirophobia is the best known).
- **The fear:** being lost and alone, hunted by an "entity" you can't fight.

**A haunted mall.**
- **What it is:** a closed-down shopping mall at night with the power out.
- **Spaces:** an atrium, shop rows with roll-down shutters, a food court, stopped escalators, an upper floor with a department store, service corridors, a loading dock, a security office and a parking garage.
- **Proven for zombies:** the mall is one of the oldest zombie settings, from Dawn of the Dead (1978) to Capcom's Dead Rising.

### 3.3 How each fits our game

| What our game needs | Haunted mall | Backrooms |
|---|---|---|
| **Round-based zombies loop** (buyable doors, wall guns, mystery crate, perks, upgrade bench) | Every piece has a natural home: shutters are doors, shops hold wall guns, kiosks hold the crate, vending machines are perks | No natural home: every room looks the same, so there's nothing to buy open and no landmarks to put things at |
| **"One building under siege"** (owner's direction) | It *is* one big building: glass storefronts smash, shutters bend, zombies pour in through broken skylights and vents | Endless and has no outside, so nothing is "under siege" |
| **Holding your ground in co-op** | Clear choke points: escalators, shop doorways, the food court balcony | The Backrooms fear is being alone and lost, which fights co-op shooting |
| **Zombies as the enemy** | Classic fit (Dawn of the Dead, Dead Rising) | Backrooms fans expect "entities" you can't fight, not zombie hordes |
| **Dark night look** (owner rule) | Power cut: emergency lights, flashlights, moonlight through skylights. Matches the brief's "power is out at the start" | Level 0 is bright yellow and evenly lit; going dark breaks the recognisable look |
| **Readable map, no clutter** (owner rule) | Landmarks everywhere (fountain, escalators, food court); clutter must be controlled | Very readable but samey; players get lost (by design) |
| **Breakable building** (pass D) | Lots to break: glass, shelves, mannequins, kiosks, ceiling tiles | Little to break: walls and carpet |
| **Ad thumbnail** | "Zombies in a dark mall" reads instantly | Instantly recognisable to Roblox horror players |
| **Build effort** | Bigger: needs many store assets (Toolbox first) | Cheap: a few repeating room pieces |

### 3.4 Recommendation: haunted mall as the main map, the Backrooms as a secret level

The mall carries the core loop; the Backrooms work best as a surprise inside it.

**Mall layout in unlock order** (mirrors the brief's camp areas):

1. **Main entrance and atrium.**
   - The spawn, with a dead fountain in the middle.
   - The first barricades are the smashed glass entrance doors and windows.
   - You start with the pistol.
2. **Ground-floor shop row.**
   - Roll-down shutters are the buyable doors.
   - Wall guns sit inside themed shops: the shotgun in sporting goods, the AK in an army-surplus or pawn shop, the sniper in a hunting store.
3. **Food court.**
   - The mystery crate sits at a kiosk and moves between kiosks.
   - Perks are vending machines.
   - The open floor is the **round 5 boss arena**.
4. **Upper floor, reached by stopped escalators.**
   - The escalators are natural choke points.
   - The department store has mannequins, a good home for the **stalker** (the brief's Left 4 Dead Witch-style enemy that can't be killed early). Mannequins are only its look; the mechanic stays the proven one.
5. **Back of house.**
   - Service corridors, the loading dock, and the security office.
   - The security office holds the **generator**: restoring power turns on the lights, perks and the **upgrade bench**. The bench could sit in an electronics repair shop.
6. **Parking garage.** A later area, or the place where special rounds come from.

**The horror layer, set in the mall:**
- The power is out at the start. Emergency exit signs and flashlights are the only light.
- **Dread round starts:** the mall PA crackles with a broken announcement, the lights flicker, and the music on the speakers warps.
- **Zombie entry points** to break through in pass D: glass storefronts, shutters, skylights, air vents and ceiling tiles.

**How to use the Backrooms:**
- A **hidden easter-egg level**, like CoD Zombies' secret quests. A cracked wall in the service corridor "no-clips" the squad into a short Level 0.
- The rules there are different: no horde, one entity hunting you, find the exit. Getting out gives a reward (a special gun or perk) and returns you to the mall.
- This uses the Backrooms' recognisability without making it carry the whole loop.
- **Or**, if the ad test shows Backrooms pull more players, make it a second map or mode after launch.

### 3.5 Cheap way to settle it with data

The brief already plans an ad test with 2 creatives (section 7). The owner's rule is to pick ideas from proven data. Make one thumbnail and short ad for the **mall** and one for the **Backrooms** before building the full map, and build the one that gets clicked more. The shooting, gore and zombies are the same in both, so nothing built so far is wasted either way.

### 3.6 Other locations considered

- **Pinecrest Camp** (the brief's original): great night mood, but it's spread out outdoors, so it fights "one building under siege". Keep it as a later map.
- **Abandoned hospital:** a strong single building, but overused in Roblox horror.
- **Subway station:** good choke points, but too linear for buying open areas.
- **School:** fits one building, but zombies in a school is a sensitive theme for ads. Avoid it.

### 3.7 What the owner needs to decide

1. Mall (recommended) or Backrooms as the main map, or the thumbnail ad test first.
2. If mall: approve the zone list in 3.4, then start the map following the map rules (Toolbox first, readable at night, no clutter, rounded where it fits).

---

## 4. What is built (and where)

### 4.1 Scripts

| Script | Lines | What it does |
|---|---|---|
| `ReplicatedStorage.Shared.GameConfig` | ~706 | Every number: `Debug`, `TestRange`, `Loadout`, `AimAssist`, `Camera`, `Movement`, `SwitchLowerTime`, `Validation`, `Mobs`, `Guns`, `ViewArms` |
| `ReplicatedStorage.Shared.Platform` | 129 | Input mode detection (`PreferredInput` + fallbacks), `Changed` event, `DebugInputMode` attribute override |
| `ReplicatedStorage.Shared.Spring` | 42 | Damped spring used for recoil, sway, shake, FOV |
| `ReplicatedStorage.Shared.SoundKit` | 103 | Plays sound cues like `"Guns/AK/Crack"` (a Sound or a folder of variants, never the same variant twice, pitch from the folder's `Pitch` NumberRange). `PlayLayers` plays Crack/Body/Tail together. Missing cues are silent |
| `ServerScriptService.GunServer` | 399 | Per-player loadout and ammo, fire validation, pellets, penetration, reloads (mag and shell-by-shell), gun switching, hit grouping per mob, calls `MobReactions` |
| `ServerScriptService.InputModeServer` | 18 | Stores each player's input mode as the `InputMode` attribute |
| `ServerScriptService.CharacterSetup` | 30 | Puts players in the `Characters` collision group |
| `ServerScriptService.TestRangeServer` | 119 | Spawns test zombies at `Workspace.TestRange.DummySpots`; walkers head for the nearest player |
| `ServerStorage.Modules.MobReactions` | 742 | Server side of every hit: limb health, wound → loosen (ball socket) → tear, stagger, knockback and knock-down, head pop, shotgun splat (burst), kill freeze, ragdoll and body throw, corpse fade |
| `StarterPlayerScripts.GunClient` | ~1400 | First-person controller: loadout and switching, viewmodel and arms, recoil/sway/bob/sprint/aim, all fire modes, pellets, penetration ray, reload and cycle animations, scope, HUD, hitmarkers |
| `StarterPlayerScripts.CombatFx` | 570 | World effects: tracers, whiz, muzzle light, casings and dropped mags that stay, bullet holes, splats, simulated blood drops and pools, hit flash, squash |
| `StarterPlayerScripts.Gore` | 707 | Client gore: wounds, torn faces, strands, spurts, chunks, head pop and torso burst effects, exit spray |
| `StarterPlayerScripts.MobImpact` | 173 | Client-side instant hit kick on mob joints (kicks accumulate per joint) |
| `StarterPlayerScripts.Dents` | 318 | EditableMesh dents on shot parts (pool of ~6; only works on meshes we own, skipped on the Toolbox zombie) |
| `StarterPlayerScripts.ViewArms` | 177 | First-person arms copied from the player's own avatar (shirt and skin). Straight arms from a shoulder point to each grip; a gun can set its own `LeftShoulder` |

### 4.2 Assets and world

- **`ReplicatedStorage.Assets.ViewModels`:** `Pistol`, `Shotgun` (Ithaca 37), `AK` (ACS AK-47), `Sniper` (Kar98k with scope). All from the Toolbox with scripts stripped.
  - Each viewmodel has a root part of size 0.1 as `PrimaryPart`. The gun points down -Z, +Y is up and +X is the gun's right.
  - Attachments on the root: `RightGrip`, `LeftGrip`, `AimPoint`, `Muzzle`, `Eject`, plus `ShellPort`, `BoltAxis` and `BoltHandle` where needed.
  - A `Flash` part with a PointLight is the muzzle flash.
  - Moving pieces carry a `VmGroup` attribute: `Mag`, `Slide`, `Pump`, `Bolt` or `Shell`.
- **`ReplicatedStorage.Assets.Sounds`:** `Guns/{Pistol,Shotgun,AK,Sniper}`, `Common/{Hit,HitHead,Kill,KillCrunch,ImpactFlesh,ImpactWorld,Casing,MagDrop,Whiz}`, `Mobs/TestZombie`. **All placeholders**; several look ripped from other games and must be replaced before release.
- **`ReplicatedStorage.Assets.Fx`:** particle templates: Spark, Dust, HitPuff, Ember, Blood, Gore, Smoke, Spurt, Drip.
- **`ReplicatedStorage.Remotes`:** Fire, Reload, HitConfirm, AmmoSync, ShotFx, SetInputMode, MobFx, Equip. `ServerStorage.Events.EnemyHit` is a server BindableEvent fired with the damage dealt (for future points).
- **`ServerStorage.TestZombie`:** Toolbox R15 "Zombie" by Rzepert with its scripts stripped except `Animate` (Roblox zombie walk and idle). It has the `Enemy` tag and `MobType=TestZombie`, 150 HP, and limb groups Head, LeftArm, RightArm, LeftLeg, RightLeg.
- **`StarterGui.HUD`:**
  - `Crosshair` (lines that spread with accuracy).
  - `Hitmarker` (white, amber on a head hit, red on a kill).
  - `Ammo` (gun name, mag, reserve, mag bar).
  - `Scope` (round lens, German post reticle with a lit red tip, `Blackout` fade).
- **Workspace:** `Baseplate`, `SpawnLocation`, `Fx` (client effects folder), `TestRange` (walls, crates, dummy spots). The lighting is **night** (ClockTime 0.5; pass E), with street lamps in `TestRange.Lights`.
- **Collision groups:** `Default`, `Characters`, `Debris`. Debris (gibs, casings, mags, ragdoll parts) doesn't collide with Characters or with itself.

### 4.3 The four guns (all in `GameConfig.Guns`)

Zombie: 150 HP. Limb health: head 120 (kills), arms 80, legs 90.

| Gun | Mode | Damage | Head × | Falloff | Mag / reserve | Kills a zombie in |
|---|---|---|---|---|---|---|
| Pistol | Semi | 34 | 2.5 | – | 12 | 5 body or 2 head shots; arm tears on the 3rd hit |
| Shotgun | Pump, 80 RPM | 10 pellets × 17 | 1.5 | full to 10 studs, down to 30% by 32 | 6 / 36, shell by shell | 1 shot up close; 4 pellets tear a limb |
| AK | Auto, 600 RPM | 28 | 2.2 (62) | full to 40 studs, down to 65% by 120 | 30 / 180 | 6 body (~0.5 s) or 2 head; arm tears on the 3rd bullet |
| Sniper | Bolt, 50 RPM | 175 | 3 (525) | none | 5 / 30 | 1 shot; any limb hit tears; head pops; passes through 3 zombies at 100/75/56% |

How each one feels:
- **Shotgun:**
  - Big kick, shake and FOV punch. The blast shoves the shooter backwards (`PlayerPush` 20 over 0.14 s).
  - Pellets on one zombie add into one heavy shove that knocks it down. Dead zombies fly far as ragdolls.
  - A point-blank kill (8 studs or less, at least half the pellets hit) **splats**: the torso bursts, spare limbs tear off, the head pops, and gore covers the floor and walls.
  - It pumps after every shot and the red shell flies out. It reloads one shell at a time; clicking during the reload loads the shell in hand, then fires.
- **AK:**
  - Climbing recoil that drifts right; bloom grows while the trigger is held.
  - Small shove and short ragdoll throw; exit spray on every hit.
  - The tactical reload drops the real curved mag on the floor. The empty reload also racks the charging handle.
- **Sniper:**
  - Scope at 14° FOV with lower sensitivity. The viewmodel hides when scoped.
  - Holding Shift while scoped steadies the sway for 4 s; once that runs out the sway is worse until your breath recovers.
  - Bolt cycle after each shot: the right hand leaves the grip and works the bolt, and the case flies out.
  - Reload: the bolt opens, three rounds are pressed in, then the bolt closes.

**Controls (PC):**
- Left mouse fires (hold for the AK). Right mouse aims: hold it, or tap to toggle.
- **R** reloads. **Shift** sprints, or holds the breath when scoped.
- Keys **1–4** or the **scroll wheel** switch guns.
- Gamepad: R2 fire, L2 aim, X reload, Y next gun, L3 sprint.

**Gun config layout:** each gun has `ViewModel`, `DisplayName`, `FireMode`, `RPM`, `Damage`, `HeadMultiplier`, `Falloff`, `Range`, `MagSize`, `Reserve`, `Spread`, `Recoil`, the aim fields (`AimTime`, `AimFov`, `AimSensitivity`, `AimDistance`), the hold fields (`HipOffset`, `HipAngles`, `LeftShoulder`), `MoveSpeed`, `EquipTime`, `Feel` (all 7 punch steps as numbers), `ReloadAnim` (keyframed tracks with sound/mag/kick/eject events) and, where needed:
- `Pellets` and `PelletSpread` (shotgun).
- `ShellReload` (shotgun).
- `Cycle` (pump or bolt animation).
- `Penetration` and `Scope` (sniper).

The comment block above `GameConfig.Guns` explains each field.

### 4.4 How a shot flows (client → server → everyone)

1. **Client (`GunClient.fire`):**
   - Raycasts each pellet. Penetrating rounds continue through mobs, at most one hit per mob per ray.
   - Plays the shot, tracer, hit kick, wound and blood, hitmarker and recoil on the same frame.
   - Sends `Remotes.Fire:FireServer(origin, gunName, shots)`, where `shots[i] = { Dir, End, Hits = { {Part, Pos}, ... } }`.
2. **Server (`GunServer`):**
   - Checks that the gun is the current one, the fire rate, ammo and pellet count, and the cone (every pellet within `PelletSpread + Spread.Max + Validation.ConeSlack` of the mean).
   - Then checks each hit (range, line of sight) and applies falloff and penetration damage.
   - Groups the hits per zombie and calls `MobReactions.Hit(model, hits, ctx)` once per zombie, with `ctx.Share` = the share of pellets that hit it.
3. **Server → shooter:** `HitConfirm(enemy, isHead, killed, severed)`, which plays the kill marker, crunch and shake.
4. **Server → other players:** `ShotFx(shooter, ends, gunName)` draws tracers and sounds for teammates.
5. **Server → all:** `MobFx(kind, ...)` drives client gore. The kinds:
   - `Hit` (with Parts and Positions arrays)
   - `Loosen`
   - `Sever`
   - `Pop` (head pop)
   - `Burst` (shotgun splat)
   - `Kill`

Other remotes:
- `Reload:FireServer()` starts a reload, and `Reload:FireServer("Stop")` ends a shell reload early.
- `Equip:FireServer(gunName)` switches guns.
- `AmmoSync(gunName, mag, reserve)` keeps the client's ammo honest.

### 4.5 Test and debug aids

- **`GameConfig.Debug.InfiniteReserve = true`.** Turn it off before the ad test.
- **Player attributes** (set on the LocalPlayer from the client):
  - `DebugReloadT` (0–1) freezes an animation frame for screenshots. `DebugAnim` names the track (Tactical, Empty, Cycle, Start, Shell, End, EndEmpty), and `DebugReloadEmpty` picks the empty reload.
  - `DebugHipOffset` and `DebugHipAngles` (Vector3) override the gun's hip pose live.
  - `DebugLeftShoulder` (Vector3) overrides the left shoulder point.
- **Studio MCP quirks found so far:**
  - **Screenshots in Play:** `screen_capture` returned only the HUD on a flat dark background, even though the game rendered fine. Use an OS-level screenshot of the Studio window instead (the computer-use zoom tool worked).
  - **Config changes from `execute_luau` don't reach running game scripts**, because the require cache is separate. Tune live with the player attributes above, or edit in Edit mode and restart Play.
  - **Script rewrites:** to replace a whole script, use `ScriptEditorService:UpdateSourceAsync`. A Lua long string `[==[` already drops its first newline, so don't also trim the first character; that cut the leading `-` off two scripts once.
  - **`execute_luau` takes `datamodel_type`** (Edit, Client or Server). In Play only Client and Server exist, so edits made in Play are lost when Play stops.
  - **Studio disconnects sometimes.** List the Studios again and retry.
  - **Toolbox decals:** a decal's asset id is not its image id; resolve it with `InsertService:LoadAsset(decalId)`.

### 4.6 Backups (`ServerStorage._Backups`)

`Pistol_Placeholder_2026-10-28`, `MobReactions_2026-10-28_beforeTear`, `GunClient_2026-10-29_beforeAimLatch`, `MobReactions_2026-10-29_socketAxes`, `TestDummy_R6Block_2026-10-29`, and the pre-guns set `{GameConfig, GunServer, MobReactions, GunClient, Gore, CombatFx, HUD}_2026-10-29_beforeGuns`. Before pass B: `{GameConfig, GunServer, TestRangeServer, MobReactions, GunClient, HUD}_2026-10-29_beforeHealth`. Before pass C: `{TestRangeServer, MobAttack, MobPose, GameConfig}_2026-10-29_beforeNav`. Before world damage: `{GunServer, GunClient, CombatFx, GameConfig}_2026-10-29_beforeWorldDamage`. Before pass E: `{GameConfig, WorldDamage, GunServer, GunClient}_2026-10-29_beforeNight` and `Lighting_2026-10-29_beforeNight` (a folder: the old Lighting children, with the properties as attributes). Before doors and pickups: `{GameConfig, GunServer, MobAI}_2026-10-29_beforeDoorsPickups`. Before bandages and the hotbar: `{GameConfig, GunServer, InteractServer, PlayerHealth, GunClient, ViewArms, Pickups, HUD}_2026-10-29_beforeBandages`. Before the inventory: `{GameConfig, GunServer, InteractServer, Bandages, GunClient, Hotbar, Pickups, HUD}_2026-10-29_beforeInventory`, `Pickups_2026-10-29_beforeShrink`. Before the bandage fix (feel doc sec 20, trauma): `{Bandages, PlayerHealth, BandageView, Hotbar, PlayerHealthClient, GameConfig, HUD}_2026-10-29_beforeBandageFix`.

---

## 5. Done in the last session (29 Oct)

- Added the **shotgun, AK and sniper**: models, attachments, sounds, config, server, client, gore, scope.
- **Server:**
  - Multi-gun loadout with ammo per gun and the `Equip` remote.
  - Pellet and penetration fire protocol, and shell reloads that a shot can interrupt.
  - Hits grouped per mob.
- **MobReactions:**
  - Ragdoll on death (Motor6Ds become ball sockets), knock-down and lift on heavy hits.
  - Shotgun splat (burst plus extra limbs), head pop, `EnemyHit` with the damage dealt.
- **Gore:**
  - Exit spray out the back of hits, head pop and torso burst effects, splatter on nearby walls.
  - Scaled-down impact per pellet.
- **GunClient rewrite:**
  - Switching with keys 1–4, the scroll wheel and gamepad Y; fire modes Semi, Auto, Pump and Bolt.
  - Pump and bolt cycle animations, shell reload phases.
  - Scope with sway and hold-breath, player push.
  - Per-gun move speed, and a crosshair that includes the pellet cone.
- **HUD:** gun name label and the scope overlay.
- **Arms:** long guns sit lower right and turned, and the left arm comes up from below the screen (`LeftShoulder` per gun).
- **Dropped mags** are now copies of the real mag model, not boxes.
- **Damage numbers:** built, then **removed at the owner's request**.
- **Tested in Play with screenshots:**
  - All four guns switch.
  - The shotgun point-blank splat works.
  - The AK fires full auto with blood and stagger.
  - The sniper's scoped headshot pops the head, then the bolt cycles.
  - The AK mag drop lands on the floor as the real model.
  - No script errors.
- **Cleanup and docs:** deleted `workspace._GunStaging`; updated feel doc section 13 and ticked the brief's checklist.

---

## 6. What is left

### 6.1 Right away
1. **Owner's feel pass on the three new guns.** Wait for the owner's notes. Recoil, push, knockback, splat range and throw strength are all single numbers in each gun's `Feel` block.
2. **Ctrl+S.** Make sure the owner has saved the place.
3. **Setting decision (pending with the owner).** See section 3: a haunted mall as the main map (recommended) with the Backrooms as a secret level, or a thumbnail ad test of both first.

### 6.2 Small cleanups
- `ServerStorage._ToolboxStaging` still holds unused pistols (CZ75, DeagleViewmodel, CleanPistol). Delete them or keep them for later wall guns.
- `ServerStorage._DevTools` (`_ArmsPreviewHarness`, `_ArmsPreviewRig`) is a dev-only arms preview. Delete it before release.
- `Workspace.TestRange`, `TestRangeServer` and `ServerStorage.TestZombie` are test-only. Replace them when real mobs and the map exist.
- The output repeats `ContentId: rbxassetid://203785492 failed due to: Asset type does not match requested type`. No script or property in the place references that id; it may come from the avatar or an engine default. It's harmless, but worth one more look.
- `GameConfig.Debug.InfiniteReserve` must be `false` before the ad test.
- `GameConfig.Loadout` gives every player all four guns at spawn, **for testing**. In the real loop you start with the pistol and buy the others (wall guns and the mystery crate).

### 6.3 Feel-phase passes still to do (feel doc section 9, in this order)

| Pass | What | Status |
|---|---|---|
| A | Toolbox pistol with a proper two-hand hold; Toolbox zombie whose shot parts come off | **Done** (the pistol was earlier; the zombie is the Toolbox R15) |
| B | Player HP and a horror-style HP bar, zombie attacks with hit feedback, downed state, the "devour" finish (zombies pile on and cover you, nothing gory shown), self-revive, zombies retarget your friends | **Done 29 Oct** (feel doc section 14); teammate revive and the touch key not yet tested with real players |
| C | Zombie navigation: pathfind to the player, act "dumb" when blocked (bump, mill, claw), then vault fences and smash wood after a delay | **Done 29 Oct** (feel doc section 15): `MobAI` + `Barricades`, test fence/wall/barricade at z=-16 in the range |
| D | Breakable building with physics, like Jujutsu Shenanigans: walls, boards and furniture break into chunks; zombies tear the building; players repair | **Started 29 Oct:** shooting the world by material, with Siege-style holes in doors and crates, glass shatter and shootable barricade boards (feel doc section 16, `WorldDamage`). Repair (`Barricades.Repair` / `WorldDamage.Restore` exist, no player action yet) and zombie-torn walls still to do |
| E | Atmosphere: night lighting, flickering bulbs, flashlight, ambience, fear stingers, "holding your ground" pacing | Started 29 Oct: night lighting, street lamps (two faulty), flashlight (F), wind, bulb buzz and fear stings. See feel doc sec 17. Faulty lamps tested after the streaming fix. Doors (E, zombies shove them) and pickups (ammo, zombie drops, highlights) were added; see feel doc sec 18. Bandages (carried, slot 5, wraps on the wounded limb) and the hotbar replaced medkits; see feel doc sec 19. "Holding your ground" pacing is not done |
| F | Round 5 boss: very deadly; beating it needs upgrades, teamwork or skill | Not started |

### 6.4 Day 2: mobile and gamepad (owner: important, "not some slop shrug-off")
- Touch controls and a thumb layout, with mobile aim assist (slowdown, gentle magnetism, optional auto-fire) using `GameConfig.AimAssist`.
- Gamepad moderate assist and button prompts.
- Test each HUD on its own device.

### 6.5 Match loop (brief section 2 and checklist section 8)
- Rounds that scale, with a special round every 5th; points per hit, kill, headshot and barricade repair (shown quietly, no floating numbers).
- Barricades, buyable doors, wall guns, a mystery crate that moves, 4 perks and an upgrade bench.
- Walker, runner, grabber and brute.
- Downed and revive, with one solo self-revive; game over screen with the round reached and one-tap Play Again.
- **Horror layer:**
  - Power out at the start; a generator turns on lights, perks and the bench.
  - Director pacing and a stalker.
  - A sound tell per monster, and dread round starts.
- Meta and money: cash from the round reached, weapon mastery and skins, skin crate and revive token.

### 6.6 Ship
- **Replace all placeholder audio** with owned or licensed sounds (some current ones look ripped from other games). Music must be from the APM library.
- A separate Studio DataStore from live, and analytics events tagged with platform.
- Performance on a low-end phone with 4 players and a full round.
- Icon, thumbnail, title and description; 2 ad creatives; the owner playtests on PC and phone, then the ad test, then read the numbers.

---

## 7. Known risks

- **Dents only work on meshes we own.** Toolbox meshes won't dent unless re-uploaded under our account. A published game may need the Mesh/Image APIs enabled in Game Settings.
- **Gore effect cost.** Splats, pools, casings and mags stay in the world up to caps (`CombatFx` `LIMITS`; drops are capped at 180). Check the frame rate on phones with 4 players once the match loop exists.
- **Arms are straight** (no elbow bend). It reads well with the current shoulder points; if the owner wants bent elbows, `ViewArms.poseArm` is where a two-bone solve would go.
- **Fire validation is loose by design** for feel (`Validation.ConeSlack = 3`). Tighten it if exploiting becomes an issue.

---

## 8. Late 29 Oct: menu, test range, military rigs

- **Join menu** (Belief-lobby style): `ServerScriptService.MenuServer` (CharacterAutoLoads off, spawns on Play, respawns while `InMatch`), `StarterPlayerScripts.MenuClient`, authored `StarterGui.Menu` (stencil logo image 104032996532207, Oswald words PLAY / MODES / SHOP, one mode: Defend), 3D room `ReplicatedStorage.MenuScene`, config `GameConfig.Menu`. Owner wants the menu background reworked heavily (a military safehouse rebuild is planned; staging props in `ServerStorage._MenuStaging`).
- **Respawn camera guard:** MenuClient sets the camera back to Custom on every spawn after the menu (backup `MenuClient_2026-10-29_beforeCamGuard`).
- **"Upside down" was the Studio MCP, not the game:** execute_luau restores the camera type it saw at call start, so a Client call made while the menu was open stuck the owner's camera in Scriptable. Don't run Client execute_luau with the menu open; if you must change the camera live, use `task.delay`.
- **Test range:** walkers wait `TestRange.WalkerDelay` (6 s) after the first spawn, and static zombies only wake after that too.
- **Military rigs:** `Workspace.MilitaryRigs`, 5 anchored R15 rigs at z=30 facing spawn, built from HumanoidDescription Shirt/Pants (the method from the owner's dummy-clothing video), each with a warm SpotLight in `MilitaryRigs.Lights`:
  - Woodland 9958476757 / 9958477344
  - Desert 10934858481 / 10934862919
  - Arctic 5188807105 / 5188810938
  - SWAT 1455700999 / 1455701482
  - Ghillie 16593023062 / 16593040882
  They have Humanoids, so guns treat them as targets (dents, limb tears) in Play.

---

## 9. Night 29 Oct: Blender house imported, the Beacon on the map

**House (`Workspace.LastLightHouse`)**

The first FBX import failed because Roblox uploads every mesh as its own asset, and 1,637 meshes timed out. The fix splits the house in two:

- **The FBX** (`last-light/blender/out/LastLightHouse.fbx`) holds only the shaped pieces, merged by material and storey into 16 MeshParts (about 9.6k triangles).
- **The 1,287 plain boxes** (walls, floors, studs, stairs, doors, window boards, porch) are real Parts:
  - built by `last-light/blender/build_house_parts.luau` from the data in `ServerStorage.HouseData` (`Head` JSON plus `Chunk1..4`);
  - lined up with the imported mesh `Char_G_1`;
  - WorldDamage can cut them.
- **Import 3D turns this FBX half a turn about Y** but leaves the MeshPart Orientation at 0. The builder applies the same half turn; this was checked with the furnace mesh.
- **Skin and tags:** `apply_house_skin.luau` set the `LL_*` variants on all 1,303 parts and tagged 16 `Door_*` models `HouseDoor`. Door and board pieces are tagged `Breakable`.
- **Placement is not final.** The owner dropped it on the baseplate at about (68, 0, -105), outside the town (the town grass covers x ±240, z 90..390).
  - The model's base is the **basement floor**, so the basement currently sits above ground and the ground floor is 13 studs up.
  - When it moves onto the map, sink it about 11 studs (the ground floor sits 2 studs above grade) and cut a basement hole in the town Grass part.
  - The mockup houses (`Map.house` ×2) are still there.
- **Not done yet:** the crouch mechanic (Jam and Sag doors need it), picking the best `LL_*` variant per family, a Play test.

**The Beacon (`Workspace.Beacon`, wave 5)**

- The FBX was imported by the owner; in Studio it's 36 studs tall with 35 bones, an AnimationController and RootPart (anchored, invisible).
- Backup of the raw import: `ServerStorage._Backups.Beacon_2026-10-29_import`.
- Textures:

  | Part | Material | Variant | Colour |
  |---|---|---|---|
  | Body | Wood | `LL_Bark` (new: dead grey-brown bark) | 92,80,70 |
  | Head (lamps, bar) | CorrodedMetal | `LL_Metal` | 132,108,88 |
  | Cables | Rubber | none | near black |
  | LensL, LensR | Neon | none | warm white |

  - Each lens has a SpotLight (Front, 38°, range 60, shadows) and a small PointLight glow.
  - `LL_Rust` was also generated, but its texture is bright red paint that reads like blood, so it's unused. Don't put it on the Beacon.
- **Stands at (-10, 0, 112)** at the back edge of the town, on the Grass, facing the houses (+Z). The import faced -Z, so it was turned 180°. It has tag `Beacon` and attribute `Wave = 5`.
- Meshes have CanCollide off; it is a static display for now.
- **Next:**
  - a slow-lurch walk clip;
  - searchlight AI (both lamps sweep using the `LampL`/`LampR` bones, turn red on sight, the player hides to break line of sight);
  - a menu background version walking in the wilderness.

## 29 Oct late: breakout, Beacon boss, menu on the road (NOT fully playtested)

**Proven loop:** CoD Zombies (Nacht der Untoten) waves in the house, then a Left 4 Dead style finale: break out, run to the roadblock, call the evac, hold out.

- **Gun torch:** every ViewModel has `TorchBody`/`TorchMount`/`TorchLens` under the barrel and a `TorchPoint` attachment on Root. `Flashlight` puts the light at `TorchPoint`; the lens glows when on. F toggles. Backup `ViewModels_2026-10-29_beforeTorch`.
- **Breakout (MatchServer + GameConfig.Breakout):** after wave 4 is cleared (`BreakoutReady`), hold E on the front or back door ("Break out"). Doors fly open, `Breakout` = true, town zombies spawn without end (MaxAlive 16, 60-170 studs from players). The objective is `Map.Extraction` at the east road end (Roblox police car from the Toolbox, scripts stripped, red/blue flasher, radio `CallPrompt`, `Zone` radius 22). Call → 40 s `EvacAt` countdown; anyone alive in the zone at 0 wins for all ("YOU MADE IT OUT", +1500). Nobody in the zone → call again. If nobody breaks out, doors burst at wave 8 (`OpenAtWave`).
- **Beacon (BeaconServer + GameConfig.Beacon):** wakes on `Breakout`, walks toward noise (walk 30, sprint 95, gunshot 160 studs; hiding spots cut footsteps to 30%). **Two lamps act independently:** each sweeps its own arc and locks on by itself (red beam, 1.1 s charge, 40 damage); the other keeps searching. It stands still while either lamp holds a lock. Hiding: parts tagged `HideSpot` in `Map.HideSpots` (wrecked cars, 7 Toolbox dumpsters in `Town.Props.Dumpsters`, the police car). Weak points: `LensL`/`LensR`, 360 HP each, via GunServer's new `Events.WorldShot` (`Events.Gunshot` feeds hearing). Both out → it topples, +2000 for everyone. The `Indestructible` attribute keeps WorldDamage off it.
- **Client:** `Shared.BeaconRig` poses bones procedurally (legs and arms on local X). `BeaconClient` walks it and drives the red screen edge `HUD.BeaconWarn` while you are locked (`LockL`/`LockR`). `MatchHud` shows GET OUT / ROADBLOCK nM / HOLD OUT / EVAC IN n, plus notices.
- **Sounds:** `Assets.Sounds.Beacon` (Siren, Charge, Blast, Step, Collapse, Alarm), from the Toolbox.
- **Menu:** no room and no avatar any more. The camera sits on the town road (`Menu.RoadCamera`); a local `ReplicatedStorage.MenuBeacon` weaves up the street right to the camera and back (`Menu.BeaconRoute`), with independent lamps and a cold rim light. MenuClient streams the road in with RequestStreamAroundAsync. Words were restyled: bigger, outlined, amber mode chip, row wash + bar on hover. The old `MenuScene` is in `ServerStorage._Parked`.
- **Lighting:** a little brighter (Brightness 1.5, ExposureCompensation 0.3, ambients up, atmosphere 0.32). Backup `Lighting_2026-10-29_beforeBrighter`.
- **Editing light:** run `require(game.ServerStorage._DevTools.EditLight)()` in the command bar to toggle daylight on and off. `LightingGuard` restores the night on every run.
- **Tested in Play:** menu (screenshots), breakout trigger, Beacon waking and walking, town spawns, HUD distance. **Not yet tested:** lamp lock-on, damage, lens kills, collapse, the evac countdown and the win screen, hiding spots.

## 29 Oct late, part 2: upstairs start, zombies already inside

- **Spawn:** `PlayerStart` is now upstairs in the front bedroom at (-16, 19, 206). The old ground-floor spot is backed up as `_Backups.PlayerStart_2026-10-29_groundFloor`.
- **Stairs:** `Debris_Stairs` has moved to `ServerStorage._Parked`, so the stairs are open.
- **Sniper:** the sniper on the bedroom table now costs 1000.
- **Zombies inside:** at run start `InsideAtStart` (3) zombies stand downstairs at random points from `Map.ZombieSpawns.Inside` (5 points in the living room and hall).
  - They wake when a player on their floor comes within `InsideWakeRange` (26), when one is hurt, or when a shot goes off within 70 studs.
  - The stuck-zombie check skips them while they sleep.
  - They count toward wave 1.
- **First wave:** `FirstWaveDelay` is 22 s, so there is time to come down and clear the house first.
- **MatchServer:** the shared zombie setup is now `addZombie(spot)`; `spawnZombie` and `spawnSleepers` both use it. Backup `MatchServer_2026-10-29_beforeSleepers`.
- **Tested in Play:** spawning upstairs, 3 zombies sitting downstairs, and the zombies waking when the player enters the living room (before the range was raised to 26).
