"""Build the Last Light zombies as Roblox R15 FBX files.

Run with Blender (numpy is bundled):
    blender -b -P blender/zombies/build_zombies.py -- Walker Runner          # some
    blender -b -P blender/zombies/build_zombies.py -- all                    # all seven
    blender -b -P blender/zombies/build_zombies.py -- Walker --preview       # quick look, no bake/export

Writes blender/zombies/out/<Name>/<Name>.fbx (+ textures, .blend) and renders in blender/zombies/renders/.
"""
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np
import bpy

import creatures
import ll_blender as LB
from ll_body import R15_PARTS, srgb
from ll_look import colorize, displace, crack_fields
from ll_sdf import vertex_normals

OUT = os.path.join(HERE, "out")
RENDERS = os.path.join(HERE, "renders")


def log(*a):
    print(*a, flush=True)


VIEW_TURN = {"front": 0.0, "threequarter": -38.0, "side": -90.0, "back": 180.0}


def front_camera(cr, lens=55, aspect=0.75):
    """Camera stays in front (lights stay put); the model turns on a turntable for each view."""
    lo, hi = cr.bounds()
    top = max(hi[2], cr.ground + cr.height)
    H = top - cr.ground
    W = max(hi[0] - lo[0], hi[1] - lo[1])
    frame = max(H * 1.12, W * 1.1 / aspect)
    zc = cr.ground + H * 0.5
    d = frame * 0.5 / math.tan(math.atan(18.0 / lens))
    return LB.add_camera("cam", (0, -d, zc + H * 0.05), (0, 0, zc), lens=lens)


def turntable(objs):
    tt = bpy.data.objects.new("Turntable", None)
    LB.link(tt)
    for o in objs:
        o.parent = tt
    return tt


def turn(tt, view):
    tt.rotation_euler = (0, 0, math.radians(VIEW_TURN[view]))
    bpy.context.view_layer.update()


def compose(paths, out_path):
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        imgs.append(LB.img_to_np(im)[:, :, :3])
        bpy.data.images.remove(im)
    sheet = np.concatenate(imgs, 1)
    LB.save_png(sheet, out_path, False)
    for p in paths:
        os.remove(p)


def make_highres(cr, preview):
    t0 = time.time()
    parts = cr.mesh_parts(preview=preview, log=log)
    log(f"  meshed in {time.time() - t0:.1f}s")
    highs, bases = {}, {}
    for p, (V, Q) in parts.items():
        N = vertex_normals(V, Q)
        mids = cr.material_ids(p, V)
        cf = crack_fields(cr, V)
        Vd = displace(cr, p, V, N, mids, cf)
        Nd = vertex_normals(Vd, Q)
        col, rough, metal, glow = colorize(cr, p, Vd, Nd, mids, cf)
        hob = LB.np_mesh(p + "_hi", Vd, Q)
        LB.set_point_color(hob.data, "Col", col)
        LB.set_point_float(hob.data, "Rough", rough)
        LB.set_point_float(hob.data, "Metal", metal)
        LB.set_point_float(hob.data, "Glow", glow)
        hob["r15_part"] = p
        highs[p] = hob
        bases[p] = (V, Q)
    log(f"  coloured in {time.time() - t0:.1f}s")
    return highs, bases


def preview(cr):
    highs, _ = make_highres(cr, True)
    m = LB.preview_material()
    for ob in highs.values():
        ob.data.materials.append(m)
    LB.setup_stage(cr.height, floor_z=cr.ground)
    os.makedirs(RENDERS, exist_ok=True)
    tt = turntable(list(highs.values()))
    front_camera(cr)
    shots = []
    for name in VIEW_TURN:
        turn(tt, name)
        p = os.path.join(RENDERS, f"_{cr.name}_{name}.png")
        LB.render(p, res=(480, 640), samples=12)
        shots.append(p)
    compose(shots, os.path.join(RENDERS, f"{cr.name}_preview.jpg"))
    log("  preview written")


def full(cr):
    out_dir = os.path.join(OUT, cr.name)
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(RENDERS, exist_ok=True)
    highs, _ = make_highres(cr, False)
    # game mesh: from the clean base (no thin cloth or small details), flat faces merged, capped by area share
    t0 = time.time()
    bases = cr.mesh_parts(low=True, log=lambda *a: None)
    log(f"  game base meshed in {time.time() - t0:.1f}s")
    areas = {}
    for p, (V, Q) in bases.items():
        a = np.linalg.norm(np.cross(V[Q[:, 1]] - V[Q[:, 0]], V[Q[:, 3]] - V[Q[:, 0]]), axis=1).sum()
        w = {"Head": 1.7}.get(p, 1.0)
        if p.endswith("Hand"):
            w = 2.0
        if p.endswith("Foot"):
            w = 0.8
        areas[p] = a * w * cr.tri_weight.get(p, 1.0)
    tot = sum(areas.values())
    lows = {}
    t0 = time.time()
    for p, (V, Q) in bases.items():
        target = max(int(cr.tri_budget * areas[p] / tot), 120)
        tmp = LB.np_mesh(p + "_tmp", V, Q)
        hp = cr.S * (0.016 if (p == "Head" or p.endswith("Hand")) else 0.022)  # the game-base grid size
        me = LB.game_mesh(tmp, target, voxel=hp * 0.9)
        bpy.data.objects.remove(tmp)
        me.name = p + "_Geo"
        ob = bpy.data.objects.new(p + "_Geo", me)
        LB.link(ob)
        ob["r15_part"] = p
        lows[p] = ob
    ntri = sum(LB.tri_count(o.data) for o in lows.values())
    log(f"  game mesh {ntri} tris in {time.time() - t0:.1f}s")
    LB.uv_atlas(list(lows.values()), {"Head": 1.45, "LeftHand": 1.15, "RightHand": 1.15})
    t0 = time.time()
    paths = LB.bake_maps(cr, lows, highs, 2048, out_dir, log=log)  # also deletes the high-res parts
    log(f"  baked in {time.time() - t0:.1f}s")
    glow_rgb = tuple(float(c) for c in srgb(cr.eye_color))
    gm = LB.game_material(cr.name + "_Skin", paths)
    for ob in lows.values():
        ob.data.materials.clear()
        ob.data.materials.append(gm)
        for prop in ("visible_camera", "visible_diffuse", "visible_glossy", "visible_transmission",
                     "visible_volume_scatter", "visible_shadow"):
            setattr(ob, prop, True)
    arm = LB.build_rig(cr)
    LB.bind(arm, lows)
    fbx = os.path.join(out_dir, cr.name + ".fbx")
    LB.export_fbx(fbx, arm, lows)
    log(f"  exported {fbx} ({os.path.getsize(fbx) / 1e6:.2f} MB)")
    # keep a clean .blend of the game model
    blend = os.path.join(out_dir, cr.name + ".blend")  # textures stay beside it, linked relatively
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True, copy=True, relative_remap=True)
    write_info(cr, lows, arm, out_dir, ntri)
    render_set(cr, lows, arm, paths, glow_rgb)


def write_info(cr, lows, arm, out_dir, ntri):
    import json
    head = lows["Head"]
    V = np.array([v.co[:] for v in head.data.vertices])
    hc = (V.min(0) + V.max(0)) * 0.5
    allv = np.concatenate([np.array([v.co[:] for v in o.data.vertices]) for o in lows.values()])
    lo, hi = allv.min(0), allv.max(0)

    def to_roblox(d):  # Blender (x left, y back, z up) -> Roblox part space (X right, Y up, Z back)
        return [round(float(-d[0]), 3), round(float(d[2]), 3), round(float(d[1]), 3)]

    info = {
        "name": cr.name,
        "height_studs": round(float(hi[2] - lo[2]), 2),
        "width_studs": round(float(hi[0] - lo[0]), 2),
        "triangles": ntri,
        "triangles_per_part": {p: LB.tri_count(o.data) for p, o in lows.items()},
        "root_joint_above_ground_studs": round(-cr.ground, 3),
        "eye_color_rgb": list(cr.eye_color),
        "eye_offsets_from_Head_center_roblox_xyz": [to_roblox(e - hc) for e in cr.eye_points[:2]],
        "notes": cr.notes,
    }
    with open(os.path.join(out_dir, cr.name + "_info.json"), "w") as f:
        json.dump(info, f, indent=1)


def render_set(cr, lows, arm, paths, glow_rgb):
    # preview look: same maps, plus the glow mask lit up the way Neon eyes would read at night
    pm = LB.game_material(cr.name + "_Preview", paths, glow_color=glow_rgb, preview_glow=8.0)
    for ob in lows.values():
        ob.data.materials.clear()
        ob.data.materials.append(pm)
    LB.setup_stage(cr.height, floor_z=cr.ground)
    tt = turntable([arm])
    front_camera(cr)
    turn(tt, "threequarter")
    LB.render(os.path.join(RENDERS, f"{cr.name}.jpg"), res=(900, 1200), samples=40)
    shots = []
    for name in ("front", "side", "back"):
        turn(tt, name)
        p = os.path.join(RENDERS, f"_{cr.name}_{name}.png")
        LB.render(p, res=(600, 800), samples=24)
        shots.append(p)
    compose(shots, os.path.join(RENDERS, f"{cr.name}_turnaround.jpg"))
    # pose test: zombie reach, a step, a head turn, a bent waist
    pose_test(cr, arm)
    turn(tt, "threequarter")
    LB.render(os.path.join(RENDERS, f"{cr.name}_posetest.jpg"), res=(700, 930), samples=24)


def pose_test(cr, arm):
    from mathutils import Euler
    pb = arm.pose.bones
    rot = {
        "LeftUpperArm": (80, 0, -8), "RightUpperArm": (62, 0, 10),
        "LeftLowerArm": (25, 0, 0), "RightLowerArm": (40, 0, 0),
        "LeftUpperLeg": (32, 0, 0), "LeftLowerLeg": (-45, 0, 0), "RightUpperLeg": (-15, 0, 0),
        "Head": (-10, 0, -22), "UpperTorso": (-14, 0, 8), "LeftHand": (0, 0, 20),
    }
    for name, (rx, ry, rz) in rot.items():
        b = pb[name]
        b.rotation_mode = "XYZ"
        # bone local axes: x = world x, y = world up, z = world -y (bones point up, roll 0)
        b.rotation_euler = Euler((math.radians(-rx), math.radians(rz), math.radians(-ry)), "XYZ")
    bpy.context.view_layer.update()


def main(argv):
    names = [a for a in argv if not a.startswith("--")]
    prev = "--preview" in argv
    if not names or names == ["all"]:
        names = list(creatures.REGISTRY)
    for n in names:
        t0 = time.time()
        log(f"== {n} {'(preview)' if prev else ''}")
        LB.reset_scene()
        cr = creatures.REGISTRY[n]()
        cr.prepare_materials()
        if prev:
            preview(cr)
        else:
            full(cr)
        log(f"== {n} done in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(argv)
