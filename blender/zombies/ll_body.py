"""Creature description -> 15 R15 body part meshes (numpy only, no bpy).

A creature is six groups of SDF layers (Head, Torso, LeftArm, RightArm, LeftLeg, RightLeg), plus layers
attached to one part only (a helmet on the Head, a skirt on the LowerTorso). Each group is one solid,
cut flush into its R15 parts by planes at the waist, elbows, wrists, knees and ankles. A child part
reaches a little way up into its parent, shrunk just under the parent's surface, so a bent joint does
not open a hole and nothing z-fights at rest. Every part comes out closed (Roblox wants capped,
watertight limbs).
"""
import numpy as np
from ll_sdf import BIG, CULL, v3, smin, smax, smoothstep, sample_grid, surface_nets, laplacian, project

R15_PARTS = [
    "LowerTorso", "UpperTorso", "Head",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
]

# part -> (bone parent, joint key in J)
R15_BONES = {
    "LowerTorso": ("HumanoidRootNode", "root"),
    "UpperTorso": ("LowerTorso", "waist"),
    "Head": ("UpperTorso", "neck"),
    "LeftUpperArm": ("UpperTorso", "shoulder_L"),
    "LeftLowerArm": ("LeftUpperArm", "elbow_L"),
    "LeftHand": ("LeftLowerArm", "wrist_L"),
    "RightUpperArm": ("UpperTorso", "shoulder_R"),
    "RightLowerArm": ("RightUpperArm", "elbow_R"),
    "RightHand": ("RightLowerArm", "wrist_R"),
    "LeftUpperLeg": ("LowerTorso", "hip_L"),
    "LeftLowerLeg": ("LeftUpperLeg", "knee_L"),
    "LeftFoot": ("LeftLowerLeg", "ankle_L"),
    "RightUpperLeg": ("LowerTorso", "hip_R"),
    "RightLowerLeg": ("RightUpperLeg", "knee_R"),
    "RightFoot": ("RightLowerLeg", "ankle_R"),
}

GROUP_OF = {
    "LowerTorso": "Torso", "UpperTorso": "Torso", "Head": "Head",
    "LeftUpperArm": "LeftArm", "LeftLowerArm": "LeftArm", "LeftHand": "LeftArm",
    "RightUpperArm": "RightArm", "RightLowerArm": "RightArm", "RightHand": "RightArm",
    "LeftUpperLeg": "LeftLeg", "LeftLowerLeg": "LeftLeg", "LeftFoot": "LeftLeg",
    "RightUpperLeg": "RightLeg", "RightLowerLeg": "RightLeg", "RightFoot": "RightLeg",
}

# limb part suffix -> (joint plane at its top, joint plane at its bottom)
_LIMB_CUTS = {"UpperArm": (None, "elbow_"), "LowerArm": ("elbow_", "wrist_"), "Hand": ("wrist_", None),
              "UpperLeg": (None, "knee_"), "LowerLeg": ("knee_", "ankle_"), "Foot": ("ankle_", None)}


def srgb(c):
    """sRGB 0-255 (or 0-1) -> linear 0-1."""
    c = v3(c)
    if c.max() > 1.0:
        c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


class Layer:
    """low: True = in both the game mesh and the bake source; False = bake source only (thin cloth,
    small detail: it ends up in the textures); "only" = game mesh only (a simple stand-in)."""

    def __init__(self, node, mat, op="add", k=0.0, part=None, prio=0.0, low=True):
        self.node, self.mat, self.op, self.k, self.part, self.prio = node, mat, op, float(k), part, float(prio)
        self.low = low


def _pick(layers, low):
    if low:
        return [L for L in layers if L.low]
    return [L for L in layers if L.low != "only"]


class Mat:
    """Surface look. kind picks the colour pattern; rough/metal are 0-1; glow 0-1 (emissive mask)."""

    def __init__(self, color, kind="plain", color2=None, rough=0.8, metal=0.0, glow=0.0, var=0.12,
                 disp=0.0, disp_freq=30.0, extra=None):
        self.color = srgb(color)
        self.color2 = srgb(color2) if color2 is not None else self.color * 0.6
        self.kind, self.rough, self.metal, self.glow, self.var = kind, rough, metal, glow, var
        self.disp, self.disp_freq = disp, disp_freq
        self.extra = extra or {}


class Creature:
    def __init__(self, name, height):
        self.name = name
        self.height = float(height)
        self.S = self.height / 5.4  # detail scale relative to a 5.4 stud zombie
        self.J = {}
        self.glayers = {g: [] for g in ("Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg")}
        self.attached = {p: [] for p in R15_PARTS}
        self.palette = {}
        self.wounds = []  # (center, radius) green ichor stains
        self.eye_points = []  # world centres of the eyes (for the notes)
        self.eye_color = (255, 255, 255)
        self.tri_budget = 6000
        self.tri_weight = {}  # part -> multiplier on its share
        self.h = None  # base voxel size of the bake source
        self.h_fine = None  # head and hands
        self.seed = 1
        self.notes = ""
        self.ground = 0.0
        self.reach = 0.2 * self.S  # how far a child part reaches into its parent across a joint cut
        self.color_fx = []  # extra colour passes f(creature, part, V, N, mats, col, rough, metal, glow)
        self.crack = None  # dict(scale, depth, width, seed, seam, ...) -> cracked-plate hide on crack materials
        self.ao_strength = 0.6
        self.uses_metal = False

    # ---- building helpers
    def gadd(self, group, node, mat, k=0.0, prio=0.0, low=True):
        self.glayers[group].append(Layer(node, mat, "add", k, None, prio, low))

    def gsub(self, group, node, mat, k=0.0, prio=0.0, low=True):
        self.glayers[group].append(Layer(node, mat, "sub", k, None, prio, low))

    def attach(self, part, node, mat, op="add", k=0.0, prio=0.0, low=True):
        self.attached[part].append(Layer(node, mat, op, k, part, prio, low))

    # ---- evaluation
    def _fold(self, layers, P, blo, bhi, acc=None):
        for L in layers:
            if blo is not None and L.node.far(blo, bhi, L.k + CULL):
                continue
            d = L.node.eval(P, blo, bhi)
            if acc is None:
                acc = d if L.op == "add" else np.full(len(P), BIG)
                if L.op != "add":
                    continue
            elif L.op == "add":
                acc = smin(acc, d, L.k)
            elif L.op == "sub":
                acc = smax(acc, -d, L.k)
            else:
                acc = smax(acc, d, L.k)
        if acc is None:
            acc = np.full(len(P), BIG)
        return acc

    def setup_partition(self):
        J = self.J
        self.m = self.reach
        self.shrink = 0.018 * self.S
        up, dn = v3((0, 0, 1.0)), v3((0, 0, -1.0))
        self.planes = {"waist": (v3(J["waist"]), up)}
        for s in ("L", "R"):
            for key in ("elbow_", "wrist_", "knee_", "ankle_"):
                self.planes[key + s] = (v3(J[key + s]), dn)

    def group_full(self, group, P, blo=None, bhi=None, low=False):
        return self._fold(_pick(self.glayers[group], low), P, blo, bhi)

    def cells(self, P, part):
        """(c_own, c_ext): negative inside the part's own slab / its slab reaching into the parent."""
        none = np.full(len(P), -BIG)

        def ps(key):
            p0, n = self.planes[key]
            return (P - p0) @ n

        if part == "Head":
            return none, none
        if part == "LowerTorso":
            sw = ps("waist")
            return sw, sw
        if part == "UpperTorso":
            sw = ps("waist")
            return -sw, -(sw + self.m)
        side = "L" if part.startswith("Left") else "R"
        top, bot = next(v for k, v in _LIMB_CUTS.items() if part.endswith(k))
        own, ext = [none], [none]
        if top:
            s = ps(top + side)
            own.append(-s)
            ext.append(-(s + self.m))
        if bot:
            s = ps(bot + side)
            own.append(s)
            ext.append(s)
        return np.max(np.stack(own, 0), 0), np.max(np.stack(ext, 0), 0)

    def part_sdf(self, part, low=False):
        att = _pick(self.attached[part], low)
        w = self.m * 0.5
        grp = GROUP_OF[part]

        def f(P, blo=None, bhi=None):
            full = self.group_full(grp, P, blo, bhi, low)
            c_own, c_ext = self.cells(P, part)
            d = np.maximum(full + self.shrink * smoothstep(0.0, w, c_own), c_ext)
            if att:
                d = self._fold(att, P, blo, bhi, acc=d)
            return d

        return f

    # ---- meshing
    def bounds(self):
        los, his = [], []
        for L in [L for g in self.glayers.values() for L in g] + [L for p in R15_PARTS for L in self.attached[p]]:
            if L.op == "add" and L.node.lo is not None:
                los.append(L.node.lo)
                his.append(L.node.hi)
        return np.min(los, 0) - 0.1, np.max(his, 0) + 0.1

    def coarse_part_boxes(self, hc):
        lo, hi = self.bounds()
        n = np.ceil((hi - lo) / hc).astype(int) + 1
        xs = [lo[a] + hc * np.arange(n[a]) for a in range(3)]
        gx, gy, gz = np.meshgrid(*xs, indexing="ij")
        P = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], 1)
        boxes = {}
        sdfs = {p: self.part_sdf(p) for p in R15_PARTS}
        vals = {p: np.empty(len(P), dtype=np.float32) for p in R15_PARTS}
        step = 60000  # chunks keep memory down
        for i in range(0, len(P), step):
            Q = P[i:i + step]
            blo, bhi = Q.min(0), Q.max(0)
            for p in R15_PARTS:
                vals[p][i:i + step] = sdfs[p](Q, blo, bhi)
        for p in R15_PARTS:
            inside = vals[p] < hc * 0.75
            if not inside.any():
                raise RuntimeError(f"{self.name}: part {p} came out empty")
            q = P[inside]
            boxes[p] = (q.min(0) - 3 * hc, q.max(0) + 3 * hc)
        return boxes

    def mesh_parts(self, preview=False, log=print, low=False):
        """Returns {part: (V, Q)} quads projected onto the part surface: the high-res bake source, or
        with low=True the clean game-mesh base (coarser, thin cloth and small details left out)."""
        self.setup_partition()
        h = self.h or 0.012 * self.S
        hf = self.h_fine or h * 0.62
        if preview:
            h, hf = h * 1.8, hf * 1.8
        if low:
            h, hf = self.S * 0.022, self.S * 0.016
        if getattr(self, "_boxes", None) is None:
            self._boxes = self.coarse_part_boxes(max(h * 4, 0.04 * self.S) if not low else 0.05 * self.S)
        boxes = self._boxes
        out = {}
        for p in R15_PARTS:
            hp = hf if (p == "Head" or p.endswith("Hand")) else h
            fn = self.part_sdf(p, low=low)
            lo, hi = boxes[p]
            F, origin = sample_grid(fn, lo, hi, hp, block=20)
            V, Q = surface_nets(F, origin, hp)
            V = laplacian(V, Q, 1, 0.5)
            blo, bhi = V.min(0) - 0.1, V.max(0) + 0.1
            V = project(V, lambda X: fn(X, blo, bhi), hp, steps=2)
            out[p] = (V, Q)
            log(f"  {p:14s} grid {F.shape} verts {len(V):7d}")
        return out

    # ---- surface look
    def material_ids(self, part, V):
        """Index into self.mat_names for each vertex: the layer whose surface is nearest."""
        layers = _pick(self.glayers[GROUP_OF[part]], False) + _pick(self.attached[part], False)
        best = np.full(len(V), np.inf)
        idx = np.zeros(len(V), dtype=np.int64)
        names = self.mat_names
        for L in layers:
            if L.node.lo is not None:
                lo, hi = L.node.lo - 0.05, L.node.hi + 0.05
                near = np.all((V >= lo) & (V <= hi), 1)
                if not near.any():
                    continue
            else:
                near = np.ones(len(V), bool)
            d = np.abs(L.node.eval(V[near])) - L.prio
            cur = best[near]
            better = d < cur
            sel = np.nonzero(near)[0][better]
            best[sel] = d[better]
            idx[sel] = names.index(L.mat)
        return idx

    def prepare_materials(self):
        self.mat_names = list(self.palette.keys())
