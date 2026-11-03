"""Blender side: meshes, game mesh, UV atlas, Cycles bake, R15 armature, FBX export, renders."""
import math
import os
import numpy as np
import bpy

from ll_body import R15_PARTS, R15_BONES
from ll_sdf import vertex_normals


# --------------------------------------------------------------------------- scene
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "NONE"
    sc.unit_settings.scale_length = 1.0
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    sc.view_settings.view_transform = "Standard"
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    return sc


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def np_mesh(name, V, F, smooth=True):
    me = bpy.data.meshes.new(name)
    nv, nf, k = len(V), len(F), F.shape[1]
    me.vertices.add(nv)
    me.vertices.foreach_set("co", V.astype(np.float32).ravel())
    me.loops.add(nf * k)
    me.loops.foreach_set("vertex_index", F.astype(np.int32).ravel())
    me.polygons.add(nf)
    me.polygons.foreach_set("loop_start", (np.arange(nf) * k).astype(np.int32))
    me.update(calc_edges=True)
    me.validate(clean_customdata=False)
    if smooth:
        me.shade_smooth()
    ob = bpy.data.objects.new(name, me)
    link(ob)
    return ob


def set_point_color(me, name, rgb):
    a = me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    rgba = np.concatenate([rgb, np.ones((len(rgb), 1))], 1).astype(np.float32)
    a.data.foreach_set("color", rgba.ravel())


def set_point_float(me, name, vals):
    a = me.attributes.new(name, "FLOAT", "POINT")
    a.data.foreach_set("value", vals.astype(np.float32))


def tri_count(me):
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def select_only(objs, active=None):
    bpy.context.view_layer.update()
    for o in list(bpy.context.view_layer.objects):
        if o is not None:
            o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


# --------------------------------------------------------------------------- game mesh
def drop_crumbs(me, min_faces=40):
    """Delete tiny loose pieces (slivers a coarse grid leaves at thin tips); decimation can't merge them away."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    seen = set()
    small = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, island = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            island.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        if len(island) < min_faces:
            small += island
    if small:
        bmesh.ops.delete(bm, geom=small, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.to_mesh(me)
    bm.free()
    return len(small)


def _planar(ob, planar_deg):
    m1 = ob.modifiers.new("planar", "DECIMATE")
    m1.decimate_type = "DISSOLVE"
    m1.angle_limit = math.radians(planar_deg)
    m1.use_dissolve_boundaries = False
    m2 = ob.modifiers.new("tri", "TRIANGULATE")
    m2.quad_method = "BEAUTY"
    m2.ngon_method = "BEAUTY"
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.remove(m1)
    ob.modifiers.remove(m2)
    return me


def non_manifold(me):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    n = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    return n


def voxel_remesh(ob, size):
    """Re-surface ob through OpenVDB: always closed and manifold (thin tips under `size` melt away)."""
    mod = ob.modifiers.new("vox", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = size
    mod.adaptivity = 0.0
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.remove(mod)
    old = ob.data
    ob.data = me
    bpy.data.meshes.remove(old)


def game_mesh(ob, cap, planar_deg=1.2, sharp_deg=38.0, voxel=None):
    """Clean game mesh from a dense base: drop loose crumbs, re-surface it if it came out non-manifold
    (collapse decimation can throw away whole walls of a non-manifold mesh), merge flat block faces
    and triangulate. If that is still over `cap`, collapse the dense base itself, then merge again."""
    drop_crumbs(ob.data)
    if voxel and non_manifold(ob.data):
        voxel_remesh(ob, voxel)
        drop_crumbs(ob.data)
    me = _planar(ob, planar_deg)
    if tri_count(me) > cap:
        bpy.data.meshes.remove(me)
        dense = decimate_to(ob, cap)
        tmp = bpy.data.objects.new("tmp_dec", dense)
        link(tmp)
        me = _planar(tmp, planar_deg)
        bpy.data.objects.remove(tmp)
        bpy.data.meshes.remove(dense)
    me.shade_smooth()
    try:
        me.set_sharp_from_angle(angle=math.radians(sharp_deg))
    except Exception:
        pass
    return me


def decimate_to(ob, target):
    """Returns a new triangulated mesh near `target` triangles (does not touch ob). It never pushes the
    collapse ratio far below its first guess: when a mesh can't shrink (non-manifold tips), chasing the
    target makes the decimator eat whole flat walls instead. A few extra triangles are the better deal."""

    def run(r):
        mod = ob.modifiers.new("dec", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = r
        mod.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        ob.modifiers.remove(mod)
        return me

    have = tri_count(ob.data)
    ratio = min(1.0, target / max(have, 1))
    floor = ratio * 0.7
    me = run(ratio)
    for _ in range(2):
        got = tri_count(me)
        if abs(got - target) < 0.06 * target or ratio >= 1.0:
            break
        nr = min(1.0, max(floor, ratio * target / max(got, 1)))
        if abs(nr - ratio) < 1e-6:
            break
        bpy.data.meshes.remove(me)
        ratio = nr
        me = run(ratio)
    return me


def uv_atlas(objs, scales):
    """Smart-project every part, even out texel density, enlarge some parts, pack into one atlas."""
    select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(58), island_margin=0.0, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    for ob in objs:
        s = scales.get(ob["r15_part"], 1.0)
        if s != 1.0:
            uv = ob.data.uv_layers.active.data
            arr = np.empty(len(uv) * 2, dtype=np.float32)
            uv.foreach_get("uv", arr)
            arr = arr.reshape(-1, 2)
            c = arr.mean(0)
            arr = (arr - c) * s + c
            uv.foreach_set("uv", arr.ravel())
    select_only(objs, objs[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(udim_source="CLOSEST_UDIM", rotate=True, scale=True, margin_method="FRACTION",
                            margin=0.0085, shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")


# --------------------------------------------------------------------------- materials
def hi_material():
    m = bpy.data.materials.new("HiBake")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "Col"
    nt.links.new(at.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m, at, em, nt


def preview_material(name="Preview"):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "Col"
    nt.links.new(at.outputs["Color"], bsdf.inputs["Base Color"])
    ar = nt.nodes.new("ShaderNodeAttribute")
    ar.attribute_name = "Rough"
    nt.links.new(ar.outputs["Fac"], bsdf.inputs["Roughness"])
    am = nt.nodes.new("ShaderNodeAttribute")
    am.attribute_name = "Metal"
    nt.links.new(am.outputs["Fac"], bsdf.inputs["Metallic"])
    ag = nt.nodes.new("ShaderNodeAttribute")
    ag.attribute_name = "Glow"
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 6.0
    nt.links.new(ag.outputs["Fac"], mul.inputs[0])
    nt.links.new(at.outputs["Color"], bsdf.inputs["Emission Color"])
    nt.links.new(mul.outputs[0], bsdf.inputs["Emission Strength"])
    return m


def game_material(name, paths, glow_color=None, preview_glow=0.0):
    """Principled BSDF the Roblox importer reads: base colour, roughness, normal (+metal)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]

    def img_node(path, noncolor):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(path, check_existing=True)
        if noncolor:
            n.image.colorspace_settings.name = "Non-Color"
        return n

    alb = img_node(paths["ALB"], False)
    nt.links.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
    rgh = img_node(paths["RGH"], True)
    nt.links.new(rgh.outputs["Color"], bsdf.inputs["Roughness"])
    if "MTL" in paths:
        mtl = img_node(paths["MTL"], True)
        nt.links.new(mtl.outputs["Color"], bsdf.inputs["Metallic"])
    else:
        bsdf.inputs["Metallic"].default_value = 0.0
    nor = img_node(paths["NOR"], True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nor.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if preview_glow > 0 and "GLW" in paths:
        glw = img_node(paths["GLW"], True)
        mix = nt.nodes.new("ShaderNodeMath")
        mix.operation = "MULTIPLY"
        mix.inputs[1].default_value = preview_glow
        nt.links.new(glw.outputs["Color"], mix.inputs[0])
        bsdf.inputs["Emission Color"].default_value = (*glow_color, 1.0)
        nt.links.new(mix.outputs[0], bsdf.inputs["Emission Strength"])
    return m


# --------------------------------------------------------------------------- bake
def new_image(name, size, noncolor):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=True)
    if noncolor:
        img.colorspace_settings.name = "Non-Color"
    img.generated_color = (0, 0, 0, 1)
    return img


def img_to_np(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)


def save_png(arr, path, srgb_encode):
    """arr HxWx3 (linear if srgb_encode) -> 8-bit PNG."""
    h, w = arr.shape[:2]
    a = np.clip(arr, 0, 1)
    if srgb_encode:
        a = np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1 / 2.4) - 0.055)
    rgba = np.concatenate([a, np.ones((h, w, 1))], 2).astype(np.float32)
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if srgb_encode else "Non-Color"
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = path
    img.file_format = "JPEG" if path.lower().endswith(".jpg") else "PNG"
    img.save()
    bpy.data.images.remove(img)


def down2(a):
    return 0.25 * (a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2])


def bake_maps(cr, lows, highs, size, out_dir, log=print):
    """Bake every map in one call each: a joined copy of the 15 game parts (same UV atlas) is the
    target and the joined high-res parts are the source. Consumes (deletes) the high-res objects."""
    sc = bpy.context.scene
    hm, attr, em, _ = hi_material()
    copies = []
    for p in R15_PARTS:
        c = lows[p].copy()
        c.data = lows[p].data.copy()
        link(c)
        copies.append(c)
    select_only(copies, copies[0])
    bpy.ops.object.join()
    low_all = bpy.context.view_layer.objects.active
    hl = [highs[p] for p in R15_PARTS]
    select_only(hl, hl[0])
    bpy.ops.object.join()
    high_all = bpy.context.view_layer.objects.active
    high_all.data.materials.clear()
    high_all.data.materials.append(hm)
    for o in lows.values():
        o.hide_render = True
    for prop in ("visible_camera", "visible_diffuse", "visible_glossy", "visible_transmission",
                 "visible_volume_scatter", "visible_shadow"):
        setattr(low_all, prop, False)
    bm = bpy.data.materials.new("LowBake")
    bm.use_nodes = True
    node = bm.node_tree.nodes.new("ShaderNodeTexImage")
    bm.node_tree.nodes.active = node
    low_all.data.materials.clear()
    low_all.data.materials.append(bm)
    S = cr.S
    ext = 0.07 * S
    ray = 0.17 * S
    passes = [("NOR", "NORMAL", None), ("COL", "EMIT", "Col"), ("RGH", "EMIT", "Rough"),
              ("MTL", "EMIT", "Metal"), ("GLW", "EMIT", "Glow"), ("AO", "AO", None)]
    sc.world.light_settings.distance = 0.3 * S
    results = {}
    for key, btype, att in passes:
        if key == "MTL" and not cr.uses_metal:
            continue
        img = new_image("bake_" + key, size, key != "COL")
        node.image = img
        if att:
            attr.attribute_name = att
            attr_out = "Color" if att == "Col" else "Fac"
            nt = hm.node_tree
            for l in list(nt.links):
                if l.to_node == em and l.to_socket.name == "Color":
                    nt.links.remove(l)
            nt.links.new(attr.outputs[attr_out], em.inputs["Color"])
        sc.cycles.samples = 48 if btype == "AO" else 1
        select_only([high_all, low_all], low_all)
        bpy.ops.object.bake(type=btype, use_selected_to_active=True, cage_extrusion=ext, max_ray_distance=ray,
                            margin=8, margin_type="EXTEND", use_clear=True, target="IMAGE_TEXTURES",
                            normal_space="TANGENT")
        results[key] = img_to_np(img)[:, :, :3].copy()
        node.image = None
        bpy.data.images.remove(img)
        log(f"  baked {key}")
    for o in lows.values():
        o.hide_render = False
    for ob in (low_all, high_all):
        me = ob.data
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(me)
    bpy.context.view_layer.update()
    # compose 1024 maps
    paths = {}
    col = results["COL"]
    ao = results["AO"][:, :, :1]
    aoc = np.clip(ao, 0, 1) ** 0.8
    alb = col * (1.0 - cr.ao_strength * (1.0 - aoc))
    alb = down2(alb)
    paths["ALB"] = os.path.join(out_dir, f"{cr.name}_ALB.png")
    save_png(alb, paths["ALB"], True)
    nor = results["NOR"] * 2.0 - 1.0
    nor = down2(nor)
    nor = nor / np.maximum(np.linalg.norm(nor, axis=2, keepdims=True), 1e-6)
    empty = np.abs(down2(results["NOR"])).sum(2) < 1e-6
    nor[empty] = (0, 0, 1)
    paths["NOR"] = os.path.join(out_dir, f"{cr.name}_NOR.png")
    save_png(nor * 0.5 + 0.5, paths["NOR"], False)
    rg = down2(results["RGH"])
    paths["RGH"] = os.path.join(out_dir, f"{cr.name}_RGH.png")
    save_png(rg, paths["RGH"], False)
    if "MTL" in results:
        paths["MTL"] = os.path.join(out_dir, f"{cr.name}_MTL.png")
        save_png(down2(results["MTL"]), paths["MTL"], False)
    paths["GLW"] = os.path.join(out_dir, f"{cr.name}_GLOW.png")
    save_png(down2(results["GLW"]), paths["GLW"], False)
    return paths


# --------------------------------------------------------------------------- rig + export
BONE_ORDER = ["Root", "HumanoidRootNode"] + R15_PARTS


def build_rig(cr):
    arm = bpy.data.armatures.new(cr.name + "_Rig")
    ob = bpy.data.objects.new(cr.name, arm)
    link(ob)
    select_only([ob], ob)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    L = 0.22 * cr.S
    heads = {"Root": np.zeros(3), "HumanoidRootNode": np.zeros(3)}
    parents = {"Root": None, "HumanoidRootNode": "Root"}
    for p in R15_PARTS:
        parents[p] = R15_BONES[p][0]
        heads[p] = cr.J[R15_BONES[p][1]]
    for name in BONE_ORDER:
        b = eb.new(name)
        b.head = tuple(heads[name])
        b.tail = tuple(heads[name] + np.array([0.0, 0.0, L]))
        b.roll = 0.0
        b.use_connect = False
        b.use_deform = name not in ("Root", "HumanoidRootNode")
        if parents[name]:
            b.parent = eb[parents[name]]
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def bind(arm_ob, lows):
    for p, ob in lows.items():
        ob.parent = arm_ob
        vg = ob.vertex_groups.new(name=p)
        vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm_ob


def export_fbx(path, arm_ob, lows):
    select_only([arm_ob] + list(lows.values()), arm_ob)
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, object_types={"ARMATURE", "MESH"},
        apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
        use_space_transform=True, bake_space_transform=False, use_mesh_modifiers=True,
        mesh_smooth_type="FACE", use_tspace=False, add_leaf_bones=False, primary_bone_axis="Y",
        secondary_bone_axis="X", armature_nodetype="NULL", bake_anim=False, path_mode="COPY",
        embed_textures=True, use_custom_props=False)


# --------------------------------------------------------------------------- render
def setup_stage(height, dark=True, floor_z=0.0):
    sc = bpy.context.scene
    w = sc.world
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.018, 0.02, 0.024, 1) if dark else (0.3, 0.3, 0.32, 1)
    bg.inputs[1].default_value = 1.0
    for name, loc, rot, size, energy, color in [
        ("Key", (-0.9, -1.2, 0.95), (55, 0, -35), 0.6, 520, (1.0, 0.94, 0.86)),
        ("Fill", (1.4, -0.9, 0.5), (70, 0, 55), 1.0, 140, (0.75, 0.84, 1.0)),
        ("Rim", (0.6, 1.4, 1.1), (-55, 0, 155), 0.5, 650, (0.82, 0.9, 1.0)),
        ("Rim2", (-1.2, 1.1, 0.8), (-60, 0, -140), 0.5, 300, (1.0, 0.95, 0.9)),
    ]:
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy * (height / 5.4) ** 2
        ld.size = size * height
        ld.color = color
        lo = bpy.data.objects.new(name, ld)
        lo.location = (loc[0] * height, loc[1] * height, loc[2] * height + floor_z)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        link(lo)
    bpy.ops.mesh.primitive_circle_add(vertices=64, radius=height * 3.0, fill_type="NGON", location=(0, 0, floor_z))
    fl = bpy.context.active_object
    fl.name = "Floor"
    m = bpy.data.materials.new("FloorMat")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.03, 0.032, 0.035, 1) if dark else (0.2, 0.2, 0.2, 1)
    b.inputs["Roughness"].default_value = 0.9
    fl.data.materials.append(m)
    return fl


def add_camera(name, loc, target, lens=55.0, ortho=None):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.clip_end = 500
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    co = bpy.data.objects.new(name, cd)
    co.location = loc
    link(co)
    d = np.array(target) - np.array(loc)
    rot = np.array(d)
    co.rotation_mode = "QUATERNION"
    from mathutils import Vector
    co.rotation_quaternion = Vector(rot).to_track_quat("-Z", "Y")
    bpy.context.scene.camera = co
    return co


def render(path, res=(900, 1200), samples=48):
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.cycles.samples = samples
    sc.render.film_transparent = False
    sc.render.filepath = path
    sc.render.image_settings.file_format = "JPEG" if path.lower().endswith(".jpg") else "PNG"
    if path.lower().endswith(".jpg"):
        sc.render.image_settings.quality = 90
    bpy.ops.render.render(write_still=True)
