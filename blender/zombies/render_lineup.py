"""Render all built zombies side by side (from their saved .blend files), labelled with their heights.

    blender -b -P blender/zombies/render_lineup.py
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy

import creatures
import ll_blender as LB

ORDER = ["Grabber", "Walker", "Runner", "Bloater", "Brute", "Widow", "Goliath"]


def append_model(name, x):
    path = os.path.join(HERE, "out", name, name + ".blend")
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = [n for n in src.objects]
    objs = [o for o in dst.objects if o is not None]
    arm = [o for o in objs if o.type == "ARMATURE"][0]
    for o in objs:
        if o.type in ("MESH", "ARMATURE"):
            bpy.context.scene.collection.objects.link(o)
    cr = creatures.REGISTRY[name]()
    arm.location = (x, 0, -cr.ground)  # stand on z = 0
    meshes = [o for o in objs if o.type == "MESH"]
    return cr, arm, meshes


def label(text, x, size):
    cu = bpy.data.curves.new("lbl_" + text, "FONT")
    cu.body = text
    cu.align_x = "CENTER"
    cu.size = size
    ob = bpy.data.objects.new("lbl_" + text, cu)
    ob.location = (x, -4.8, 0.05)
    ob.rotation_euler = (math.radians(80), 0, 0)  # standing up, facing the camera
    m = bpy.data.materials.new("lblmat")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Emission Color"].default_value = (0.9, 0.85, 0.7, 1)
    b.inputs["Emission Strength"].default_value = 1.5
    cu.materials.append(m)
    LB.link(ob)


def main():
    LB.reset_scene()
    names = [n for n in ORDER if os.path.exists(os.path.join(HERE, "out", n, n + ".blend"))]
    x = 2.5  # margin so the first label stays in frame
    placed = []
    widths = {"Grabber": 3.2, "Walker": 4.4, "Runner": 4.0, "Bloater": 5.4, "Brute": 8.0, "Widow": 4.6, "Goliath": 11.0}
    for n in names:
        w = widths.get(n, 5.0)
        x += w / 2
        cr, arm, meshes = append_model(n, x)
        placed.append((n, x, cr))
        x += w / 2 + 0.6
    total = x + 2.0
    for n, px, cr in placed:
        import json
        info = json.load(open(os.path.join(HERE, "out", n, n + "_info.json")))
        label(f"{n}  {info['height_studs']:.1f}", px, 0.75)
        # glow the eyes (and sacs, embers) the way Neon parts would read at night
        d = os.path.join(HERE, "out", n)
        paths = {k: os.path.join(d, f"{n}_{k}.png") for k in ("ALB", "RGH", "NOR", "MTL")}
        paths["GLW"] = os.path.join(d, f"{n}_GLOW.png")
        paths = {k: v for k, v in paths.items() if os.path.exists(v)}
        from ll_body import srgb
        pm = LB.game_material(n + "_Lineup", paths, glow_color=tuple(float(c) for c in srgb(cr.eye_color)), preview_glow=8.0)
        for o in bpy.context.scene.objects:
            if o.type == "MESH" and o.data.materials and o.data.materials[0].name.startswith(n + "_Skin"):
                o.data.materials[0] = pm
    sc = bpy.context.scene
    w = sc.world
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.018, 0.02, 0.024, 1)
    cx = total / 2
    for name, loc, rot, size, energy, color in [
        ("Key", (cx - 6, -16, 14), (55, 0, -20), total * 0.5, 9000, (1.0, 0.94, 0.86)),
        ("Fill", (cx + 10, -14, 6), (70, 0, 35), total * 0.6, 3000, (0.75, 0.84, 1.0)),
        ("RimL", (cx - total * 0.3, 12, 12), (-55, 0, 180), total * 0.4, 7000, (0.82, 0.9, 1.0)),
        ("RimR", (cx + total * 0.3, 12, 12), (-55, 0, 180), total * 0.4, 7000, (0.82, 0.9, 1.0)),
    ]:
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy, ld.size, ld.color = energy, size, color
        lo = bpy.data.objects.new(name, ld)
        lo.location = loc
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        LB.link(lo)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(cx, 0, 0))
    fl = bpy.context.active_object
    fl.scale = (total + 200, 300, 1)
    fm = bpy.data.materials.new("FloorMat")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.032, 0.035, 1)
    fl.data.materials.append(fm)
    cam_d = total * 1.42
    LB.add_camera("cam", (total / 2, -cam_d, 6.5), (total / 2, 0, 4.6), lens=50)
    LB.render(os.path.join(HERE, "renders", "Lineup.jpg"), res=(2400, 1000), samples=48)


if __name__ == "__main__":
    main()
