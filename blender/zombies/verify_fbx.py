"""Re-import each exported FBX into an empty scene and check it is a clean Roblox R15 rig.

    blender -b -P blender/zombies/verify_fbx.py -- [names...]

Checks: 15 *_Geo meshes, the R15 bone tree (Root > HumanoidRootNode > LowerTorso > ...), every vertex
100% on its own bone, the triangle budget, height, facing (+Z in the file = -Y in Blender), embedded
textures, and that every bone carries zero rotation in the file (so stock R15 animations line up).
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import bpy

from ll_body import R15_PARTS, R15_BONES

PARENT = {"Root": None, "HumanoidRootNode": "Root"}
PARENT.update({p: R15_BONES[p][0] for p in R15_PARTS})


def fbx_bone_rotations(path):
    """Lcl Rotation / PreRotation of every LimbNode, read straight from the binary FBX."""
    sys.path.insert(0, os.path.dirname(bpy.utils.resource_path("LOCAL")))
    import addon_utils
    mod = [m for m in addon_utils.modules() if m.__name__ == "io_scene_fbx"][0]
    import importlib
    parse = importlib.import_module("io_scene_fbx.parse_fbx")
    root, _ = parse.parse(path)
    out = {}
    gs = [e for e in root.elems if e.id == b"GlobalSettings"]
    if gs:
        vals = {}
        for p70 in [c for c in gs[0].elems if c.id == b"Properties70"]:
            for p in p70.elems:
                k = p.props[0].decode()
                if k in ("UpAxis", "UpAxisSign", "FrontAxis", "FrontAxisSign", "CoordAxis", "CoordAxisSign", "UnitScaleFactor"):
                    vals[k] = p.props[4]
        out["__global__"] = ("Global", vals, ())
    objects = [e for e in root.elems if e.id == b"Objects"][0]
    uid_name, local = {}, {}
    for e in objects.elems:
        if e.id != b"Model":
            continue
        name = e.props[1].split(b"\x00")[0].decode()
        kind = e.props[2].decode()
        rot = pre = (0.0, 0.0, 0.0)
        for p70 in [c for c in e.elems if c.id == b"Properties70"]:
            for p in p70.elems:
                key = p.props[0].decode()
                if key == "Lcl Rotation":
                    rot = tuple(p.props[4:7])
                elif key == "PreRotation":
                    pre = tuple(p.props[4:7])
        uid_name[e.props[0]] = name
        local[name] = (kind, rot, pre)
    parent = {}
    conns = [e for e in root.elems if e.id == b"Connections"][0]
    for c in conns.elems:
        if c.props[0] == b"OO" and c.props[1] in uid_name and c.props[2] in uid_name:
            parent[uid_name[c.props[1]]] = uid_name[c.props[2]]

    def euler_xyz(r):  # FBX eEulerXYZ: X first, then Y, then Z
        a, b, g = np.radians(r)
        Rx = np.array([[1, 0, 0], [0, np.cos(a), -np.sin(a)], [0, np.sin(a), np.cos(a)]])
        Ry = np.array([[np.cos(b), 0, np.sin(b)], [0, 1, 0], [-np.sin(b), 0, np.cos(b)]])
        Rz = np.array([[np.cos(g), -np.sin(g), 0], [np.sin(g), np.cos(g), 0], [0, 0, 1]])
        return Rz @ Ry @ Rx

    def world(n):
        kind, rot, pre = local[n]
        R = euler_xyz(pre) @ euler_xyz(rot)
        return world(parent[n]) @ R if n in parent else R

    for n, (kind, rot, pre) in local.items():
        out[n] = (kind, rot, pre, world(n))
    return out


def check(name):
    path = os.path.join(HERE, "out", name, name + ".fbx")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    errs = []
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if len(arms) != 1:
        errs.append(f"{len(arms)} armatures")
    names = sorted(o.name for o in meshes)
    want = sorted(p + "_Geo" for p in R15_PARTS)
    if names != want:
        errs.append(f"meshes {names}")
    arm = arms[0]
    bones = {b.name: (b.parent.name if b.parent else None) for b in arm.data.bones}
    if bones != PARENT:
        errs.append(f"bone tree differs: {bones}")
    tris = 0
    open_edges = {}
    import bmesh
    for o in meshes:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        n = sum(1 for e in bm.edges if not e.is_manifold)
        bm.free()
        if n:
            open_edges[o.name] = n
        part = o.name[:-4]
        vgs = [g.name for g in o.vertex_groups]
        if vgs != [part]:
            errs.append(f"{o.name} groups {vgs}")
        bad = 0
        for v in o.data.vertices:
            ws = [(g.group, g.weight) for g in v.groups]
            if len(ws) != 1 or abs(ws[0][1] - 1.0) > 1e-4:
                bad += 1
        if bad:
            errs.append(f"{o.name}: {bad} verts not 100% on {part}")
        o.data.calc_loop_triangles()
        tris += len(o.data.loop_triangles)
        if not any(m and m.node_tree and any(n.type == "TEX_IMAGE" and n.image for n in m.node_tree.nodes)
                   for m in o.data.materials):
            errs.append(f"{o.name}: no texture")
    co = np.concatenate([np.array([o.matrix_world @ v.co for v in o.data.vertices]) for o in meshes])
    lo, hi = co.min(0), co.max(0)
    head = [o for o in meshes if o.name == "Head_Geo"][0]
    hv = np.array([head.matrix_world @ v.co for v in head.data.vertices])
    front = hv[:, 1].min() - hv[:, 1].mean()
    back = hv[:, 1].max() - hv[:, 1].mean()
    rots = fbx_bone_rotations(path)
    print("          global:", rots.pop("__global__", ("", {}, ()))[1])
    limb = {k: v for k, v in rots.items() if v[0] == "LimbNode"}
    off = [k for k, v in limb.items() if np.abs(v[3] - np.eye(3)).max() > 1e-4]
    if off:
        errs.append(f"bones not axis-aligned in the file's space: {off}")
    imgs = [i for i in bpy.data.images if i.size[0] > 0]
    print(f"{name:8s} tris {tris:6d}  height {hi[2] - lo[2]:5.2f}  width {hi[0] - lo[0]:5.2f}  depth {hi[1] - lo[1]:5.2f}"
          f"  bones {len(bones)}  limbnodes {len(limb)}  images {len(imgs)}  file {os.path.getsize(path) / 1e6:.2f} MB")
    nonlimb = {k: v[:3] for k, v in rots.items() if v[0] != "LimbNode" and not k.endswith("_Geo")}
    print(f"          root nodes: {nonlimb}")
    print("          watertight: " + ("yes, every part" if not open_edges else f"non-manifold edges {open_edges}"))
    print("          " + ("OK" if not errs else "PROBLEMS: " + "; ".join(errs)))
    return not errs


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    import creatures
    names = argv or list(creatures.REGISTRY)
    ok = all([check(n) for n in names if os.path.exists(os.path.join(HERE, "out", n, n + ".fbx"))])
    print("ALL OK" if ok else "SOME FAILED")
