# Last Light: the house (defend-a-house waves)

Owner direction, 29 Oct night: the game is "defend a house" in waves. The map is a small town with the house as the start point, and **at wave 5 the players get to go outside**.

## Where the design comes from

- **Call of Duty Zombies, Nacht der Untoten (the proven loop):** a closed start room with boarded windows that zombies tear open and players re-board, plus paid debris that opens more rooms. Upstairs gives a second floor of windows to hold.
- **Left 4 Dead safe houses and the RE7 Baker house (the look):** a worn two-storey American farmhouse with siding, a porch, dark wood inside, and lamps that barely hold the night back.
- **Kept from our own rules:** the night setting fixed with lights, not daylight; bulky, readable shapes; no clutter props; round edges where they fit.

## Layout (Workspace.Map.House, front faces +Z to the street)

Footprint is 48 x 32 studs (x -24..24, z 180..212, offset by the map origin). Each floor is 12 studs tall, and there is a porch at the front (z 212..220).

Ground floor:

| Room | Area | Opens | Windows (boarded, Breakable) |
|---|---|---|---|
| Living room (START) | front left, 28 x 20 | start | 2 front, 1 side |
| Hall + front door | front middle, 8 x 20 | start; front door boarded until **wave 5** | none |
| Kitchen | front right, 12 x 20 | debris 750 | 1 front, 1 side |
| Dining | back left, 28 x 12 | debris 750 | 1 back, 1 side |
| Mudroom + back door | back right | from kitchen; back door opens **wave 5** | 1 back |

Upstairs (stairs in the hall, behind debris 1000): a landing, master bedroom with a balcony door onto the porch roof (looks over the street), a second bedroom and a bathroom. Upstairs windows are glass, so zombies climb in only once the boards below are gone (later pass).

## Wave 5: going outside

The front and back doors (`Door` models with `OpenAtWave = 5`) burst open. The street, yards and neighbour lots then become the play space: wall guns, the mystery crate's second spot and the power generator live outside.

## Town (next pass, after the owner approves the house)

- One street in front (z 230..250) with sidewalks and street lamps (the existing `Lamp` tag; some faulty).
- 3 to 4 neighbour lots: a burnt house, a corner store, a garage with a car.
- Fences that zombies vault (`Vaultable`), and a dead end blocked by a crashed truck.
- Built Toolbox-first for props, with scripts stripped.

## Status (29 Oct night)

**House** (`Workspace.Map.House`, origin (0,0,200), scaled 1.3x after the owner asked for a bigger inside; backup `ServerStorage._Backups.House_2026-10-29_v1`):
- Wrecked look: grimy siding, torn planks with bare studs, a roof hole with rafters, smashed upstairs glass, a sagging balcony with a collapsed corner, a broken porch post and missing balusters.
- Ground windows hold `Breakable` boards; upstairs windows are glass or nailed planks.
- `WaveDoors` (front and back, tag `WaveDoor`, `OpenAtWave = 5`), and `Interior.Debris` (tag `Debris`, `Cost` 750/750/1000). These are attributes only; no script uses them yet.
- `Interior.Lights` (tag `Lamp`, two `Faulty`), and `Interior.PlayerStart`.
- The interior has no furniture yet (Toolbox furniture is wanted). The owner said "we might need to model a better house"; this one is a mockup.

**Town** (`Workspace.Map.Town`): main street along X at z≈257 (x −220..220) with sidewalks, curbs and potholes, plus a side street at x≈−95.
- **Buildings:** Toolbox lots renamed `Lot_*` and fully restyled to our palette, with textures, decals, PBR skins and signs stripped so they don't read as Toolbox assets. Three of them hid the fake "Runtime/ScreenBuilder" script payload, which was stripped. Lots: FuelStop, Market, Diner, Duplex, Townhouse, BurntHouse, Farmhouse.
- **Props:** 10 street lamps (some dead, some flickering), 7 wrecked cars, about 98 dead trees (yards plus a tree line at the edge), and concrete barriers with car pile-ups closing both street ends and the side street.
- **Edges:** invisible `Boundary` walls.

**All ages (owner, 29 Oct):** the map has no blood, bodies, gore or text graffiti, and Toolbox decals are always stripped. Gameplay still has green mob blood and limb tearing, which may raise the maturity rating; check the Roblox questionnaire before publishing.

**Next:** furniture (Toolbox, restyled), fences and yards (`Vaultable`), the wave loop with the wave-5 door opening, zombie spawn points round the town edge, and possibly a better house model.

## Blender house v1 (29 Oct, late)

Owner direction: **SWAT rescue** in the house and the town, so the house has storeys, rooms, and broken doors you pass under. It must look attacked and hand-built, with no AI-slop geometry and real texturing.

- **Model:** `last-light/blender/build_house.py` plus `house_detail.py`, run headless with Blender 5.1.
  - Output: `out/LastLightHouse.fbx` (1,637 pieces, 66k tris) and the renders in `out/renders` (including floor-plan cutaways).
  - Import steps: `last-light/blender/IMPORT-ME.md`.
- **Storeys:**
  - basement with a furnace room, storage and a panic room;
  - ground floor;
  - upper floor;
  - attic.
  - Stairs: the main hall stair, the basement stair in the mudroom, and the attic stair in the upper storage room.
- **Doors** are paneled leaves split into pieces.
  - Jam: bottom smashed out, crouch through.
  - Sag: header collapsed, crouch under.
  - Off: torn off. The rest are intact.
  - **There's no crouch in the game yet**, and these doors need one.
- **Wreck:** breaches with studs and burnt siding, a collapsed upper corner, a roof hole with rafters, ragged torn shingles, boarded ground windows, glass shards, a porch with a snapped post, a broken balcony rail and a hanging gutter.
- **Build quality:** every box is bevelled, UVs are box-projected (8 studs per tile), siding and shingle courses are on global grids, and the clip check is clean apart from faces that only touch.
- **Texturing:** 10 generated MaterialVariants in MaterialService: LL_Siding, Trim, Shingle, Brick, Stone, Wood, Floor, Plaster, Char and Metal, with 4 options each (`LL_X`, `LL_X1..3`). `apply_house_skin.luau` applies them by each part's name prefix after import.
- **Next:**
  1. The owner imports the FBX.
  2. Run the skin script and pick the best variant of each material.
  3. Cut the grass for the basement.
  4. Add crouch.
  5. Swap the mockup `Workspace.Map.House` for this model.
