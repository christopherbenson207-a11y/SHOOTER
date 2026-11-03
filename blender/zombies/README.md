# Last Light zombies (Blender, Roblox R15)

Seven blocky R15 mobs, five zombie types and two bosses, modelled in Blender by script.
They follow the Roblox block-body look (square head, block torso, block limbs) with the horror
in the surface: cracked hide, torn clothes, growths, bone spikes and glowing eyes.

The owner rules are kept on every model. Blood and ichor are green, never red. Faces have no teeth,
gums or drool; every mouth is a plain dark slot. Skin is dull so the glowing eyes carry the read at
night. Every model has 15 separate R15 parts, so limb tearing still works.

| Mob | Role | Height (studs, with hair and spikes) | Triangles | Eye glow |
|---|---|---|---|---|
| Walker | Zombie, medium: the basic horde zombie | 5.3 | 3,590 | RGB 205, 255, 140 |
| Runner | Zombie, fast: thin, long limbs | 5.8 | 4,178 | RGB 255, 120, 60 |
| Grabber | Zombie, small: big head, claws to the ground; pounces and pins | 3.7 | 4,064 | RGB 150, 230, 255 |
| Brute | Zombie, big: iron mask, huge forearms, chains; breaks windows | 7.7 | 6,478 | RGB 255, 110, 40 |
| Bloater | Zombie, big and wide: glowing green sacs, made to pop | 5.8 | 6,472 | RGB 210, 255, 90 |
| Goliath | Boss: towering hulk, cracks glowing like embers, bone spikes | 11.4 | 10,964 | RGB 255, 170, 60 |
| Widow | Boss: very tall stalker, hair over the face, claws a stud long | 10.2 | 9,714 | RGB 190, 225, 255 |

Renders: `renders/<Name>.jpg` (three-quarter view), `<Name>_turnaround.jpg` (front, side, back),
`<Name>_posetest.jpg` (the rig bent: arms reaching, a step, head turned), and `Lineup.jpg` (all seven
side by side, labelled with their heights in studs). The renders light the glow mask the way Neon eyes would look at night.

## Files for each mob (`out/<Name>/`)

- `<Name>.fbx` is the file to import. It holds the 15 meshes, the R15 armature and the textures.
- `<Name>_ALB.png`, `_NOR.png`, `_RGH.png` (and `_MTL.png` where there is metal) are the same textures
  as loose files: colour, normal, roughness, metalness. Use them if Studio does not pick the textures up.
- `<Name>_GLOW.png` is a mask of what should glow: the eyes, the Bloater's sacs, the Goliath's cracks
  and mouth. If your Studio has emissive maps on SurfaceAppearance, this is the mask for that.
- `<Name>.blend` is the game model in Blender (meshes, armature, material), with the textures linked
  from the same folder.
- `<Name>_info.json` has the height, triangle counts per part, the root joint height, the eye colour
  and the eye offsets from the Head part's centre (in Roblox part space, studs).

## Rig

- Meshes are named `Head_Geo`, `UpperTorso_Geo`, `LowerTorso_Geo`, `LeftUpperArm_Geo` and so on, the
  names Roblox's character spec asks for.
- Bones follow the R15 tree: `Root` > `HumanoidRootNode` > `LowerTorso` > `UpperTorso` > `Head`, arms
  and legs. `Root` and `LowerTorso` sit at the origin.
- Every mesh is weighted 100% to its own bone (a rigid R15, no skinning), so a part can come off
  without dragging its neighbours.
- Every bone is axis-aligned in the file (no rotation of its own), like Roblox's own R15 rigs, so
  stock R15 animations (the zombie walk the TestZombie uses) turn the joints the right way.
- Child parts reach a little way inside their parent, just under its surface, so a bent elbow or
  knee does not open a hole and nothing z-fights at rest.
- The model faces +Z in the file and stands up in +Y, as the character spec asks. One Blender unit is
  one stud, exported with "FBX Units Scale".

## Importing (Studio 3D Importer)

- The importer should pick Rig Type R15 by itself. Leave Scale Unit at Stud.
- If it offers a joint or constraint type, pick Motor6D. MobReactions, Gore, MobImpact and MobPose
  look for Motor6D joints.
- If a model ever comes in facing backwards, set World Forward to Back.
- The bosses are taller than the avatar limit (10 studs). That limit is for Marketplace bodies; it
  does not matter for NPCs, so ignore any warning about it.

To use one as a mob, set it up like `ServerStorage.TestZombie`:

- a `MobType` attribute and the `Enemy` tag;
- a `Limb` attribute on each part (Head; LeftArm on LeftUpperArm, LeftLowerArm and LeftHand; and so on);
- the Animate script;
- two Neon parts named `Eye` with a PointLight named `Glow`, welded to the Head at the offsets in the
  info file (the eyes are already painted bright in the texture);
- a `GameConfig.Mobs` entry for each new MobType.

## Rebuilding

The models come from code, so changes are edits and a rebuild. Run with Blender (it bundles numpy):

```bash
blender -b -P blender/zombies/build_zombies.py -- all
```

```bash
blender -b -P blender/zombies/build_zombies.py -- Walker --preview
```

```bash
blender -b -P blender/zombies/verify_fbx.py
```

```bash
blender -b -P blender/zombies/render_lineup.py
```

- `creatures.py` describes the seven mobs (proportions, clothes, dressing, colours).
- `ll_blocky.py` is the block-body kit; `ll_sdf.py` the shapes, noise and mesher; `ll_body.py` cuts the
  body into the 15 parts; `ll_look.py` paints and roughens the surface; `ll_blender.py` does the game
  mesh, UV atlas, bake, armature, FBX and renders.
- Thin cloth and small details live only in the bake source (`low=False`), so the game mesh stays
  clean blocks and the detail is in the textures. A full build takes about five minutes a mob;
  `--preview` skips the bake and export and writes a quick four-view `renders/<Name>_preview.jpg`.

## Checked, and not checked

- Each FBX was imported back into Blender: 15 `_Geo` meshes, the R15 bone tree, every vertex 100% on
  its own bone, every bone axis-aligned in the file, textures embedded, and every part watertight
  (no open or non-manifold edges) (`verify_fbx.py`).
- Each rig was posed in Blender (arms reaching, a step, the head turned) and rendered: the parts turn on
  their joints, and elbows and knees stay closed.
- The Widow's gown rides on her LowerTorso like any rigid Roblox skirt, so a leg swinging far forward
  pokes through it.
- Nothing was imported into Roblox Studio or play-tested; this session has no Studio.
