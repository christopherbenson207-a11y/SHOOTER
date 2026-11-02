# The Beacon: wave 5 monster (29 Oct)

Owner brief: a wave 5 monster, scary but **not gore, for kids**, "something like Siren Head". It has laser vision, and players **hide so they don't get caught**. Rigged nicely. It is also the **menu background**: an entity walking in the wilderness. Detailed, but the age rating stays low.

## Design (our own creature, not Siren Head)

We copy no existing character. The Beacon keeps the archetype (a very tall, gaunt figure with a machine for a head) and gives it its own identity, tied to the game's title, *Last Light*.

- **Height 34 studs.** It looks over the house eaves and peers into the upper windows.
- **Body:** an emaciated humanoid shape with a tiny torso, legs half its height, arms to the knee and long thin fingers.
  - The skin is dark weathered **bark**: cracked, grey-brown, like a dead tree.
  - No flesh, ribs, teeth, eyes or blood. The scare comes from the proportions and the slow movement.
- **Head:** a rusted **searchlight drum** on a crooked neck, mounted in a yoke, with cooling fins on the drum.
  - The face is a **caged lens**: a grille over the glass.
  - Three old power cables hang from the drum and run into its back.
- **Laser vision:** the lens is a Neon part that holds a SpotLight plus a beam.
  - Searching: warm white, sweeping.
  - When it sees you: the lens turns red, the beam locks on and a sting plays.
  - Players break line of sight to hide (inside rooms, behind cover, under the porch).
- **Movement:** a slow, long-legged lurch. Arms hang and sway, the head turns ahead of the body, and the light sweeps.

## Rig

The armature uses the same joints the body was built on:

- Root
- Spine, Chest, Neck, Head
- Shoulder, UpperArm, LowerArm and Hand (L/R)
- 3 fingers × 2 bones per hand (L/R)
- Thigh, Shin, Foot and Toe (L/R)

Weights:

- Each vertex is weighted to its nearest bone, blended with that bone's parent or child at the joints, with at most 4 influences.
- The head parts are 100% Head; the lens has its own Neon mesh.

Export: an FBX with the armature, giving skinned MeshParts plus Bones in Roblox. Animation runs through an AnimationController, using a walk clip authored in Blender.

## Files

- `last-light/blender/build_beacon.py` builds `out_beacon/Beacon.fbx` plus the renders.

## Twin lights (29 Oct, owner's pick)

The owner wanted two heads, like the reference. We kept it original:

- There are **two searchlight drums**, not horn speakers.
- They sit on a tilted crossbar on top of a tall pole neck:
  - the left lamp hangs under the bar;
  - the right lamp sits on top of the bar.
- Each lamp has its own bone (`LampL`/`LampR`) at the yoke joint, so the two beams can sweep separately.
- Height is now about 35 studs.

The FBX was re-exported and round-trip checked: 36 bones and 5 skinned meshes. The pose test (`renders/7_pose_34.png`) bends cleanly.

## In Studio (29 Oct night)

The Beacon is in `Workspace.Beacon`, standing at (-10, 0, 112) on the town Grass and facing the houses.

- **Textures:**
  - Body: Wood with `LL_Bark`.
  - Head: CorrodedMetal with `LL_Metal`, tinted rust brown.
  - Cables: black Rubber.
  - Lenses: Neon, each with a SpotLight and a PointLight.
- **Rejected texture:** `LL_Rust` was generated but looks like red paint, which reads as blood, so it's unused.
- **Backup:** `ServerStorage._Backups.Beacon_2026-10-29_import`.
- **Full notes:** section 9 of `HORROR-SHOOTER-HANDOFF.md`.

## Status (29 Oct, v1 single lamp)

v1 is modelled and rigged by `blender/build_beacon.py`, and exported to `blender/out_beacon/Beacon.fbx`. The renders are in `out_beacon/renders`, and the import steps are in `blender/IMPORT-BEACON.md`.

- **Height:** 30 studs. The posture is hunched, the head juts forward and the shoulders are shrugged.
- **Body:** knobbly joints with thin limbs between them, 3 long fingers and 3 splayed toes per side.
- **Rig and weights:** a pose test showed clean bends at the knee, arm, fingers and neck.

Next:

- a bark/rust texture in Studio (a MaterialVariant on the skinned MeshParts, box UVs at 4 studs);
- a walk clip (slow lurch);
- the searchlight AI (sweep, spot, red lock, hide);
- the menu scene, walking in the wilderness.
