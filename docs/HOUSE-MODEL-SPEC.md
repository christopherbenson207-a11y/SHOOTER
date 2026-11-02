# Last Light house: Blender model spec (29 Oct night)

Owner: "build the house very intricately. everything on point, purposeful, spacing, doors breakable." This replaces the part-built mockup at `Workspace.Map.House`.

Built by `last-light/blender/build_house.py` (headless Blender 5.1 with the shared `fix-my-scooter/blender/lib.py`).

## Conventions

- **Units and axes:** 1 Blender unit = 1 stud. Z is up and the front is −Y, which becomes Roblox +Z (the street side) after the Y-up FBX export. The house is centred on X = 0, Y = 0, with the ground at Z = 0.
- **Names:** every object is named `<Material>_<Where>_<What>`, for example `Siding_G_Front_3` or `Trim_Win_LivingFront1_Head`. After import, a Studio script colours and materials each part by its first word: Siding, Trim, Core, Plaster, Floor, Stone, Shingle, Wood, Glass, Brick and Metal.
- **Breakables:** these are separate objects under a named empty, so scripts can knock pieces off one by one:
  - `Door_<id>`: stiles, rails and panels.
  - `Boards_<window>`: separate planks.
- **Collision:** walls, floors and stairs collide as simple boxes. Siding, trim and shingles get CanCollide off after import.

## Grid and heights

| Element | Studs |
|---|---|
| Footprint | 64 × 44 (X −32..32, Y −22..22) |
| Stone plinth | Z 0..2; ground floor top Z 2 |
| Floor-to-floor | 13 (ground Z 2..15, upper Z 15..28), ceilings 12 |
| Walls | exterior core 0.8, interior 0.6, lap siding 0.35 proud |
| Doors | 5.5 × 9 (sill at floor); cased opening 8 wide |
| Windows | 5.5 × 7, sill 3 above floor (ground Z 5..12, upper Z 18..25) |
| Stairs | 5.2 wide, 17 risers of 0.765, tread 1.1 |
| Roof | gable along X, pitch 0.6, eave and rake overhang 1.5, ridge Z ≈ 41.2 |
| Porch | full width, 8 deep (Y −30..−22), deck at Z 2, 3 steps at X 0; balcony on its roof |

A Roblox character is about 5 studs tall, so doors are just under twice that and halls are at least 8 wide. That keeps it roomy for fights with zombies and the camera.

## Rooms

Ground floor:

- **Hall** (X −6..6, full depth): front door at X 0, back door at X 0, and the stairs along the X 6 side, rising toward the back.
- **Living room (start)** (X −32..−6, Y −22..2):
  - 2 front windows (X −25, −13) and a side window (Y −15).
  - Fireplace and chimney on the X −32 wall (Y −4).
  - An 8-wide cased opening to the hall at Y −12.
- **Dining** (X −32..−6, Y 2..22): back windows at X −25 and −13, a side window at Y 12, and a door to the hall at Y 12 (debris 750).
- **Kitchen** (X 6..32, Y −22..4): front windows at X 13 and 25, a side window at Y −9, and a door to the hall at Y −14 (debris 750).
- **Mudroom** (X 6..32, Y 4..22): a door to the kitchen at X 19, a back window at X 25, and a side door at Y 13 (opens at wave 5).

Upper floor:

- **Landing:** the stairwell hole X 0.4..5.7, Y −14..4.7, with a rail.
- **Master bedroom** (front left): a balcony door at X −13, windows at X −25 and side Y −15.
- **Bedroom 2** (back left): windows at X −25 and −13, side Y 12.
- **Bedroom 3** (front right): windows at X 13 and 25, side Y −9.
- **Bath** (X 6..18, Y 10..22): a small window.
- **Storage** (X 18..32, Y 10..22): windows on the back and side.

## Detail list (each one has a job)

- **Lap siding:** a real board profile with a thick bottom edge that throws shadow lines.
- **Trim:** corner boards, a band board between storeys, and a frieze under the eaves, so the wall reads in two storeys and doesn't look like a box.
- **Window casings:** head cap, side casings, sill and apron. Ground windows are boarded (breakable planks).
- **Doors:** paneled leaves made of separate stiles, rails and panels, which break piece by piece; doors also get casings.
- **Stone plinth and water-table board:** they ground the house so it doesn't float.
- **Roof:** shingle courses, fascia, rake boards, ridge cap and soffits. The gables are board-and-batten with louvred vents. There is a brick chimney.
- **Porch:** turned posts, balusters, a rail, a lattice skirt, grooved deck boards and steps with stringers.
- **Stairs:** treads, risers, stringers, a turned newel and balusters, and a handrail.

## Stages

1. Shell: plinth, wall cores with openings, floors, siding, trim and roof. Renders, then the owner looks.
2. Windows, doors (breakable), porch, balcony and stairs.
3. Wreck pass (the owner wants it wrecked): missing siding boards, a roof hole, broken balusters, smashed glass, sagging rails. Kept all-ages: no blood or bodies.
4. Interior detail: baseboards, fireplace, built-ins. Toolbox furniture is placed in Studio and restyled.
5. Export FBX, write `IMPORT-ME.md`, then a Studio colour and collision script after the owner imports.
