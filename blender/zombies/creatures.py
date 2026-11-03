"""The seven Last Light mobs, blocky (Roblox block-body style) with horror dressing.

Owner rules kept on every one: green ichor only (no red), no teeth or drool on faces (a plain dark
mouth slot), dull skin for the dark night, eyes that can glow, and 15 separate R15 parts so limbs
still tear off.
"""
import numpy as np
from ll_sdf import (v3, norm, Sphere, Ellipsoid, RoundCone, Capsule, Box, Ring, Cylinder, Fn, Union,
                    Subtract, Intersect, Offset, Displace, chain, Noise, euler, smoothstep)
from ll_body import Creature, Mat
from ll_blocky import (X, Y, Z, lerp, rbox, block_skeleton, torso_box, head_box, arm_box, leg_box, lumps, spike,
                       spikes_along, chain_links, rivets, jagged_below, shell, tear, block_face, apply_items, claws)


def below(z0, amp=0.0, noise=None, freq=1.0):
    """Region inside where z < a (ragged) line. .plain = the straight line at its highest reach."""
    if noise is None or amp <= 0:
        n = Fn(lambda P: P[:, 2] - z0)
        n.plain = n
        return n
    n = Fn(lambda P: P[:, 2] - z0 - amp * noise.fbm(P * freq, 3))
    n.plain = Fn(lambda P: P[:, 2] - (z0 + amp))
    return n


def above(z0, amp=0.0, noise=None, freq=1.0, teeth=0.0, period=0.25):
    """Region inside where z > a ragged (optionally saw-toothed) hem. .plain = straight, at its lowest reach."""
    n = jagged_below(z0, amp, noise if noise is not None else Noise(0), freq, teeth, period)
    lo = z0 - amp - teeth
    n.plain = Fn(lambda P: lo - P[:, 2])
    return n


def both(a, b):
    n = Intersect(a, b)
    n.plain = Intersect(getattr(a, "plain", a), getattr(b, "plain", b))
    return n


def band(z0, z1, amp=0.0, noise=None, freq=1.0, teeth=0.0):
    return both(above(z0, amp, noise, freq, teeth), below(z1, amp * 0.5, noise, freq))


def wear(cr, group, base, t, region, mat, prio=0.004, holes=(), part=None):
    """A garment: the torn version goes to the bake source only; a plain shell reaching its lowest
    hem goes to the game mesh, so the game surface always sits on or just over the cloth."""
    torn = shell(base, t, region, holes=holes)
    plain = shell(base, t, getattr(region, "plain", region))
    if part:
        cr.attach(part, torn, mat, prio=prio, low=False)
        cr.attach(part, plain, mat, prio=prio, low="only")
    else:
        cr.gadd(group, torn, mat, prio=prio, low=False)
        cr.gadd(group, plain, mat, prio=prio, low="only")


def skin(color, color2, seam=None, **kw):
    ex = {"crack": True}
    ex.update(kw.pop("extra", {}))
    return Mat(color, "skin", color2, rough=kw.pop("rough", 0.82), disp=kw.pop("disp", 0.004),
               disp_freq=kw.pop("disp_freq", 30), extra=ex, **kw)


# =========================================================================== WALKER
def walker():
    cr = Creature("Walker", 5.2)
    cr.seed = 11
    cr.tri_budget = 3600
    cr.tri_weight = {"LeftHand": 0.45, "RightHand": 0.45}
    cr.eye_color = (205, 255, 140)
    cr.notes = "The basic horde zombie. Classic block proportions (2x2x1 torso, 1x1x2 limbs, 1.2 head)."
    D = block_skeleton(cr, head=(1.2, 1.2, 1.2), head_fwd=0.04)
    cr.crack = dict(scale=0.42, depth=0.022, width=0.085, seed=4, seam=(20, 28, 12), patch_lo=0.2)
    nz = Noise(cr.seed)
    T = torso_box(D, 0.08)
    cr.gadd("Torso", T, "skin")
    # untucked plaid shirt, torn hem, a rip at the belly and the back (texture only: low=False)
    wear(cr, "Torso", T, 0.056, above(-0.12, 0.05, nz, 3.0, teeth=0.1, period=0.3), "shirt", 0.003,
         holes=[tear(nz, (0.45, -0.5, 0.55), (0.32, 0.2, 0.3)), tear(nz, (-0.5, 0.52, 1.25), (0.3, 0.2, 0.25))])
    wear(cr, "Torso", T, 0.05, below(0.05, 0.02, nz, 4.0), "jeans", 0.004)
    # head: cracked block, sunken eyes, a plain dark mouth slot, a matted hair slab
    Hb, hc = head_box(D, 0.17)
    cr.gadd("Head", Hb, "skin_head")
    neck = rbox((-0.3, -0.3, D.zt - 0.25), (0.3, 0.3, D.hb + 0.1), 0.05)
    cr.gadd("Head", neck, "skin_head", k=0.02)
    apply_items(cr, "Head", block_face(cr, D, eye_w=0.24, eye_h=0.15, eye_sep=0.24, eye_z=0.55, eye_r=0.07,
                                       mouth_w=0.48, mouth_h=0.08, mouth_z=0.25, jag=0.012))
    top = D.hb + D.head[2]
    hair = Intersect(Displace(Offset(Hb, 0.05), lambda P: nz.ridged(P * v3((9, 9, 3)), 2) - 0.5, 0.03),
                     Subtract(above(top - 0.3, 0.12, nz, 4.0, teeth=0.12, period=0.18),
                              tear(nz, (0.3, 0.1, top), (0.28, 0.3, 0.2))), 0.01)
    cr.gadd("Head", hair, "hair", prio=0.003, low=False)
    cr.gadd("Head", Intersect(Offset(Hb, 0.04), above(top - 0.2)), "hair", low="only")
    for s in "LR":
        a = D.arm[s]
        A = arm_box(D, s, 0.08)
        g = "LeftArm" if s == "L" else "RightArm"
        cr.gadd(g, A, "skin")
        cut = a["el"] + (0.25 if s == "L" else -0.3)  # left sleeve torn short, right one longer
        wear(cr, g, A, 0.045, above(cut, 0.06, nz, 4.0, teeth=0.08, period=0.22), "shirt", 0.003)
        claws(cr, D, s, n=4, length=0.16, r0=0.05, spread=0.32, curl=0.2, seed=1 if s == "L" else 2)
        lg = D.leg[s]
        L = leg_box(D, s, 0.07)
        gl = "LeftLeg" if s == "L" else "RightLeg"
        cr.gadd(gl, L, "skin")
        holes = [tear(nz, (lg["xc"], -0.5, lg["kn"] + 0.05), (0.3, 0.2, 0.25))] if s == "R" else []
        wear(cr, gl, L, 0.05, both(above(lg["bot"] + 0.55, 0.05, nz, 4.0, teeth=0.08), below(lg["top"] + 0.2)), "jeans", 0.004,
             holes=holes)
        cr.gadd(gl, shell(L, 0.06, below(lg["bot"] + 0.34)), "shoe", prio=0.005)
        cr.gadd(gl, rbox((lg["xc"] - 0.5, -0.62, lg["bot"]), (lg["xc"] + 0.5, 0.0, lg["bot"] + 0.3), 0.1), "shoe", k=0.03, prio=0.005)
        cr.gadd(gl, rbox((lg["xc"] - 0.53, -0.64, lg["bot"]), (lg["xc"] + 0.53, 0.56, lg["bot"] + 0.07), 0.03), "sole", prio=0.006)
    # a fleshy growth bursting from the right shoulder (the reference's lumpy shoulders)
    ra = D.arm["R"]
    cr.attach("RightUpperArm", Union([
        lumps((ra["xc"] - 0.05, -0.05, ra["top"] + 0.03), 0.27, 9, 0.26, seed=3, flat=0.6),
        lumps((ra["x1"] - 0.02, 0.0, ra["top"] - 0.4), 0.21, 7, 0.2, seed=4, flat=0.55, normal=-X)], 0.08),
        "growth", k=0.05)
    cr.wounds += [(v3((0.45, -0.52, 0.55)), 0.32), (v3((-0.5, 0.55, 1.25)), 0.25), (v3((-1.45, -0.5, 0.95)), 0.2)]

    cr.palette = {
        "skin": skin((112, 124, 92), (78, 90, 62), extra={"vein": (60, 66, 72), "vein_amt": 0.45, "spot": (92, 84, 70)}),
        "skin_head": skin((120, 130, 100), (84, 94, 68), extra={"spot": (98, 90, 74)}),
        "socket": Mat((20, 22, 18), "plain", (14, 15, 12), rough=0.9),
        "eye": Mat((215, 245, 150), "eye", rough=0.25, glow=1.0),
        "mouth": Mat((12, 12, 10), "plain", (8, 8, 7), rough=0.9),
        "nail": Mat((66, 60, 46), "plain", (44, 40, 32), rough=0.5),
        "hair": Mat((30, 28, 24), "hair", (46, 42, 36), rough=0.85, disp=0.008, disp_freq=26),
        "shirt": Mat((56, 70, 86), "plaid", (80, 88, 92), rough=0.9, disp=0.004, disp_freq=20,
                     extra={"bands": [(32, 40, 52), (112, 104, 86)], "period": 0.42, "box": True}),
        "jeans": Mat((40, 50, 66), "denim", (72, 84, 100), rough=0.88, disp=0.004, disp_freq=22),
        "shoe": Mat((44, 36, 30), "leather", (30, 25, 21), rough=0.7, disp=0.003, disp_freq=18),
        "sole": Mat((22, 20, 18), "plain", (16, 15, 14), rough=0.85),
        "growth": Mat((88, 102, 60), "skin", (60, 74, 42), rough=0.6, disp=0.01, disp_freq=16,
                      extra={"vein": (50, 60, 40), "vein_amt": 0.5}),
    }
    return cr


# --------------------------------------------------------------------------- shared dressing
def groove(base, z0, z1, depth):
    """A shallow horizontal groove round a block (ribs, wrinkles); use with gsub."""
    return Subtract(Intersect(Offset(base, 0.05), band(z0, z1)), Offset(base, -depth), 0.0)


def surface_points(node, center, n, seed, zr=(-1.0, 1.0), front_bias=0.0):
    rng = np.random.default_rng(seed)
    pts = []
    from ll_sdf import norm as _n
    while len(pts) < n:
        d = rng.normal(0, 1, 3)
        d[1] -= front_bias
        d = _n(d)
        if not (zr[0] <= d[2] <= zr[1]):
            continue
        o = v3(center)
        lo, hi = 0.0, 6.0
        for _ in range(36):
            mid = (lo + hi) * 0.5
            if node.eval((o + d * mid)[None, :])[0] < 0:
                lo = mid
            else:
                hi = mid
        pts.append((o + d * lo, d))
    return pts


def chain_loop(lo, hi, z, out=0.05, link=0.2, wire=0.03, tilt=0.0):
    """Chain links wrapped round a block (lo/hi are the block's x,y extents)."""
    x0, y0 = lo[0] - out, lo[1] - out
    x1, y1 = hi[0] + out, hi[1] + out
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)]
    pts = []
    for i in range(4):
        a, b = v3((*corners[i], 0)), v3((*corners[i + 1], 0))
        L = np.linalg.norm(b - a)
        k = max(int(L / link), 1)
        for j in range(k):
            p = a + (b - a) * (j / k)
            pts.append(v3((p[0], p[1], z + tilt * (len(pts) % 7) / 7.0)))
    pts.append(pts[0])
    return chain_links(pts, link * 0.5, wire)


def hanging_chain(top, n, link=0.2, wire=0.03, sway=(0.0, -0.02)):
    pts = [v3(top) + v3((sway[0] * i, sway[1] * i, -link * 0.9 * i)) for i in range(n + 1)]
    return chain_links(pts, link * 0.5, wire)


def bone_spikes(base_pts, dirs, lens, r0, seed):
    return spikes_along(base_pts, dirs, lens, r0, seed=seed, jitter=0.12)


def boot_block(cr, gl, lg, D, h=0.4, toe=0.14, t=0.06, mat="boot", sole="sole", cap=None):
    xc, bot = lg["xc"], lg["bot"]
    w, d = D.leg_w / 2, D.leg_d / 2
    L = leg_box(D, "L" if gl.startswith("Left") else "R", 0.07)
    up = Union([shell(L, t, below(bot + h)), rbox((xc - w - t * 0.6, -d - toe, bot), (xc + w + t * 0.6, 0.0, bot + h * 0.72), 0.1 * cr.S)], 0.03)
    cr.gadd(gl, up, mat, prio=0.005)
    cr.gadd(gl, rbox((xc - w - t, -d - toe - 0.03, bot), (xc + w + t, d + t, bot + 0.075 * cr.S), 0.03), sole, prio=0.006)
    if cap:
        cr.gadd(gl, rbox((xc - w - t * 0.7, -d - toe - 0.015, bot + 0.05), (xc + w + t * 0.7, -d + 0.05, bot + h * 0.62), 0.06),
                cap, k=0.01, prio=0.007)


# =========================================================================== RUNNER
def runner():
    cr = Creature("Runner", 5.8)
    cr.seed = 21
    cr.tri_budget = 4200
    cr.eye_color = (255, 120, 60)
    cr.notes = "Fast and thin. Long limbs, torn hoodie, joggers, sneakers. Orange eyes like GameConfig.Runner."
    D = block_skeleton(cr, torso_w=1.45, torso_d=0.74, ut_h=1.7, lt_h=0.35, head=(1.0, 0.98, 1.1), neck=0.1,
                       head_fwd=0.16, arm_w=0.6, arm_d=0.62, arm_len=2.35, arm_gap=0.02, leg_w=0.66, leg_d=0.68,
                       leg_len=2.55, leg_gap=0.08, reach=0.15)
    cr.crack = dict(scale=0.36, depth=0.018, width=0.075, seed=7, seam=(24, 30, 22), patch_lo=0.15)
    nz = Noise(cr.seed)
    T = torso_box(D, 0.07)
    cr.gadd("Torso", T, "skin")
    ht = 0.065
    fy = -D.torso_d / 2
    wear(cr, "Torso", T, ht, above(-0.06, 0.05, nz, 3.0, teeth=0.06), "hoodie", 0.003, holes=[tear(nz, (-0.4, fy, 0.95), (0.18, 0.15, 0.22))])
    cr.gadd("Torso", rbox((-0.52, fy - ht - 0.035, 0.12), (0.52, fy, 0.62), 0.05), "hoodie", k=0.01, prio=0.004, low=False)
    cr.gadd("Torso", rbox((-0.025, fy - ht - 0.014, 0.64), (0.025, fy, D.zt + 0.02), 0.01), "metal", k=0.004, low=False)
    wear(cr, "Torso", T, 0.06, below(0.1, 0.02, nz, 4.0), "joggers", 0.004)
    # hood bunched behind the neck, drawstrings at the front (rigid on the UpperTorso)
    zt = D.zt
    cr.attach("UpperTorso", Displace(rbox((-0.55, 0.22, zt - 0.22), (0.55, 0.66, zt + 0.36), 0.17),
                                     lambda P: nz.fbm(P * 6.0, 2), 0.03), "hoodie", k=0.03)
    for sx in (1, -1):
        a = v3((sx * 0.16, fy - ht - 0.02, zt - 0.06))
        b = v3((sx * 0.19, fy - ht - 0.05, zt - 0.62))
        cr.attach("UpperTorso", Union([Capsule(a, b, 0.022), Cylinder(b, b - v3((0, 0, 0.09)), 0.03, 0.008)]), "cord", k=0.005, low=False)
    Hb, hc = head_box(D, 0.15)
    cr.gadd("Head", Hb, "skin_head")
    cr.gadd("Head", rbox((-0.24, -0.24, zt - 0.25), (0.24, 0.24, D.hb + 0.1), 0.05), "skin_head", k=0.02)
    apply_items(cr, "Head", block_face(cr, D, eye_w=0.26, eye_h=0.12, eye_sep=0.23, eye_z=0.56, eye_r=0.06, eye_tilt=20,
                                       mouth_w=0.34, mouth_h=0.17, mouth_z=0.23, jag=0.035, brow=0.05))
    top = D.hb + D.head[2]
    cr.gadd("Head", Intersect(Offset(Hb, 0.028), above(top - 0.2, 0.06, nz, 5.0, teeth=0.05, period=0.12), 0.01), "hair", prio=0.003, low=False)
    for s in "LR":
        g = "LeftArm" if s == "L" else "RightArm"
        a = D.arm[s]
        A = arm_box(D, s, 0.06)
        cr.gadd(g, A, "skin")
        cut = a["el"] - 0.42 if s == "L" else a["el"] + 0.12
        wear(cr, g, A, 0.06, above(cut, 0.05, nz, 4.0, teeth=0.07, period=0.2), "hoodie", 0.003)
        if s == "R":  # athletic tape round the wrist
            wear(cr, g, A, 0.03, band(a["wr"] - 0.12, a["wr"] + 0.22, 0.03, nz, 6.0), "tape", 0.004)
        claws(cr, D, s, n=4, length=0.13, r0=0.045, spread=0.32, curl=0.15, seed=7 + (s == "L"))
        gl = "LeftLeg" if s == "L" else "RightLeg"
        lg = D.leg[s]
        L = leg_box(D, s, 0.06)
        cr.gadd(gl, L, "skin")
        wear(cr, gl, L, 0.055, both(above(lg["bot"] + 0.42, 0.03, nz, 4.0), below(lg["top"] + 0.2)), "joggers", 0.004)
        cr.gadd(gl, shell(L, 0.072, band(lg["bot"] + 0.34, lg["bot"] + 0.5)), "cuff", prio=0.005)
        xc, bot, w = lg["xc"], lg["bot"], D.leg_w / 2
        cr.gadd(gl, shell(L, 0.05, below(bot + 0.3)), "shoe", prio=0.006)
        cr.gadd(gl, rbox((xc - w - 0.03, -w - 0.16, bot), (xc + w + 0.03, 0.0, bot + 0.26), 0.1), "shoe", k=0.03, prio=0.006)
        cr.gadd(gl, rbox((xc - w - 0.06, -w - 0.2, bot), (xc + w + 0.06, w + 0.06, bot + 0.1), 0.04), "sole", prio=0.007)
        for i, zz in enumerate((0.2, 0.25)):
            cr.gadd(gl, Capsule(v3((xc - 0.17, -w - 0.06 - 0.06 * i, bot + zz)), v3((xc + 0.17, -w - 0.06 - 0.06 * i, bot + zz)), 0.022),
                    "cord", k=0.004, low=False)
    cr.wounds += [(v3((-0.4, -0.45, 0.95)), 0.22), (v3((-1.2, -0.4, 0.5)), 0.15)]

    def stripes(cr_, part, V, N, mids, col, rough, metal, glow):
        j = cr_.mat_names.index("joggers")
        sel = (mids == j) & (np.abs(N[:, 0]) > 0.6) & (np.sign(N[:, 0]) == np.sign(V[:, 0])) & (np.abs(V[:, 1]) < 0.075)
        col[sel] = col[sel] * 0.25 + np.array([0.55, 0.55, 0.52]) * 0.75
        return col, rough, metal, glow

    cr.color_fx.append(stripes)
    cr.palette = {
        "skin": skin((118, 126, 116), (84, 92, 86), extra={"vein": (66, 72, 88), "vein_amt": 0.55, "spot": (96, 90, 96)}),
        "skin_head": skin((124, 132, 122), (88, 96, 90), extra={"spot": (100, 94, 100)}),
        "socket": Mat((18, 18, 20), "plain", (12, 12, 14), rough=0.9),
        "eye": Mat((255, 150, 80), "eye", rough=0.25, glow=1.0),
        "mouth": Mat((12, 11, 12), "plain", (8, 8, 9), rough=0.9),
        "nail": Mat((60, 58, 54), "plain", (40, 38, 36), rough=0.5),
        "hair": Mat((26, 24, 24), "hair", (40, 38, 36), rough=0.85, disp=0.006, disp_freq=30),
        "hoodie": Mat((62, 64, 68), "cloth", (44, 46, 50), rough=0.92, disp=0.005, disp_freq=18),
        "joggers": Mat((30, 31, 34), "cloth", (22, 22, 25), rough=0.9, disp=0.004, disp_freq=20),
        "cuff": Mat((26, 27, 30), "cloth", (20, 20, 22), rough=0.9, disp=0.006, disp_freq=40),
        "cord": Mat((150, 146, 136), "plain", (110, 106, 98), rough=0.7),
        "metal": Mat((120, 122, 126), "metal", (70, 60, 50), rough=0.35, metal=0.8),
        "tape": Mat((150, 144, 126), "cloth", (110, 104, 90), rough=0.85),
        "shoe": Mat((70, 74, 80), "cloth", (50, 52, 56), rough=0.7),
        "sole": Mat((168, 166, 158), "plain", (130, 128, 122), rough=0.6),
    }
    cr.uses_metal = True
    return cr


# =========================================================================== GRABBER
def grabber():
    cr = Creature("Grabber", 3.6)
    cr.seed = 31
    cr.tri_budget = 4000
    cr.eye_color = (150, 230, 255)
    cr.notes = "Small and quick. Big head, short legs, arms to the ground with hooked claws: it pounces and pins."
    D = block_skeleton(cr, torso_w=1.05, torso_d=0.62, ut_h=1.0, lt_h=0.3, head=(1.25, 1.1, 1.15), head_fwd=0.2,
                       arm_w=0.42, arm_d=0.44, arm_len=2.1, arm_split=(0.45, 0.42), arm_gap=0.03,
                       leg_w=0.46, leg_d=0.48, leg_len=1.15, leg_gap=0.1, toe=0.06, reach=0.1)
    cr.crack = dict(scale=0.28, depth=0.014, width=0.07, seed=8, seam=(22, 28, 14), patch_lo=0.15)
    nz = Noise(cr.seed)
    T = torso_box(D, 0.06)
    cr.gadd("Torso", T, "skin")
    for z in (0.55, 0.72, 0.89, 1.04):  # starved ribs
        cr.gsub("Torso", groove(T, z - 0.018, z + 0.018, 0.035), "skin", k=0.02, low=False)
    fy, by = -D.torso_d / 2, D.torso_d / 2
    for i, z in enumerate(np.linspace(0.3, 1.05, 4)):
        cr.attach("UpperTorso" if z > D.lt_h / 2 else "LowerTorso",
                  spike(v3((0, by - 0.02, z)), v3((0, by + 0.2 - 0.02 * i, z + 0.1)), 0.06), "bone", k=0.02)
    # rag loincloth flaps (rigid on the LowerTorso)
    lt0 = -D.lt_h / 2
    for yy, sgn in ((fy, -1), (by, 1)):
        flap = Intersect(rbox((-0.42, yy - 0.02 * sgn - 0.045, lt0 - 0.6), (0.42, yy - 0.02 * sgn + 0.045, lt0 + 0.25), 0.02),
                         above(lt0 - 0.36, 0.06, nz, 5.0, teeth=0.2, period=0.17), 0.005)
        cr.attach("LowerTorso", flap, "rag", k=0.01)
    wear(cr, "Torso", T, 0.035, below(D.lt_h / 2 + 0.05, 0.03, nz, 5.0), "rag", 0.003)
    Hb, hc = head_box(D, 0.2)
    cr.gadd("Head", Hb, "skin_head")
    cr.gadd("Head", rbox((-0.22, -0.22, D.zt - 0.2), (0.22, 0.22, D.hb + 0.1), 0.05), "skin_head", k=0.02)
    apply_items(cr, "Head", block_face(cr, D, eye_w=0.3, eye_h=0.13, eye_sep=0.25, eye_z=0.55, eye_r=0.065, eye_tilt=24,
                                       eye_depth=0.12, mouth_w=0.66, mouth_h=0.09, mouth_z=0.2, jag=0.04, brow=0.075))
    top = D.hb + D.head[2]
    for sx in (1, -1):  # pointed ears
        cr.gadd("Head", spike(v3((sx * 0.6, 0.02 - D.head_fwd, D.hb + 0.66)), v3((sx * 0.98, 0.1 - D.head_fwd, D.hb + 0.98)), 0.13, 0.02),
                "skin_head", k=0.04)
    cr.gadd("Head", lumps(v3((0.05, -D.head_fwd + 0.1, top)), 0.14, 7, 0.22, seed=5, flat=0.5), "skin_head", k=0.05)
    for s in "LR":
        g = "LeftArm" if s == "L" else "RightArm"
        cr.gadd(g, arm_box(D, s, 0.05), "skin")
        cr.gadd(g, Ellipsoid(v3((D.arm[s]["xc"], D.arm_d / 2, D.arm[s]["el"])), v3((0.13, 0.08, 0.12))), "skin", k=0.05)  # bony elbow
        claws(cr, D, s, n=3, length=0.48, r0=0.075, spread=0.33, curl=0.55, seed=11 + (s == "L"))
        gl = "LeftLeg" if s == "L" else "RightLeg"
        lg = D.leg[s]
        cr.gadd(gl, leg_box(D, s, 0.05), "skin")
        cr.gadd(gl, Ellipsoid(v3((lg["xc"], -D.leg_d / 2, lg["kn"] - 0.04)), v3((0.15, 0.06, 0.12))), "skin", k=0.05)  # kneecap
        foot = "LeftFoot" if s == "L" else "RightFoot"
        tc = [spike(v3((lg["xc"] + o, -D.leg_d / 2 - 0.02, lg["bot"] + 0.07)), v3((lg["xc"] + o * 1.2, -D.leg_d / 2 - 0.24, lg["bot"] + 0.01)), 0.055)
              for o in (-0.18, 0.0, 0.18)]
        cr.attach(foot, Union(tc), "nail", k=0.02)
    cr.wounds += [(v3((0.3, -0.4, 0.4)), 0.18), (v3((-0.85, -0.3, 0.2)), 0.14)]
    cr.palette = {
        "skin": skin((126, 132, 112), (88, 94, 76), extra={"vein": (74, 78, 86), "vein_amt": 0.5, "spot": (104, 96, 90)}),
        "skin_head": skin((134, 140, 120), (94, 100, 82), extra={"spot": (108, 100, 94)}),
        "socket": Mat((12, 14, 16), "plain", (8, 9, 10), rough=0.9),
        "eye": Mat((175, 240, 255), "eye", rough=0.25, glow=1.0),
        "mouth": Mat((10, 10, 10), "plain", (6, 6, 6), rough=0.9),
        "nail": Mat((48, 44, 40), "plain", (30, 28, 26), rough=0.4),
        "bone": Mat((196, 188, 166), "bone", (150, 142, 122), rough=0.6, disp=0.006, disp_freq=20),
        "rag": Mat((74, 62, 48), "cloth", (52, 44, 34), rough=0.95, disp=0.006, disp_freq=18),
    }
    return cr


# =========================================================================== BRUTE
def brute():
    cr = Creature("Brute", 7.65)
    cr.seed = 41
    cr.tri_budget = 6500
    cr.eye_color = (255, 110, 40)
    cr.uses_metal = True
    cr.notes = "Big and slow. Welded iron mask (armoured head), huge forearms, chains, bone spikes. Breaks windows."
    D = block_skeleton(cr, torso_w=3.4, torso_d=1.9, ut_h=3.0, lt_h=0.55, head=(1.45, 1.4, 1.4), head_fwd=0.28,
                       head_drop=0.3, arm_w=1.6, arm_d=1.7, arm_len=3.9, arm_split=(0.4, 0.43), arm_gap=0.03,
                       leg_w=1.45, leg_d=1.5, leg_len=3.0, leg_gap=0.25, toe=0.1, reach=0.3)
    cr.crack = dict(scale=0.6, depth=0.034, width=0.085, seed=12, seam=(16, 24, 10), patch_lo=0.25)
    nz = Noise(cr.seed)
    T = torso_box(D, 0.16)
    fy = -D.torso_d / 2
    zt = D.zt
    TP = Union([T, rbox((-1.45, fy - 0.12, zt - 1.25), (-0.05, fy + 0.3, zt - 0.2), 0.2),
                rbox((0.05, fy - 0.12, zt - 1.25), (1.45, fy + 0.3, zt - 0.2), 0.2)], 0.12)
    cr.gadd("Torso", TP, "skin")
    # chest harness: two straps in an X lying on the chest, an iron ring where they cross
    xc = v3((0, 0, zt - 1.35))
    for sgn in (1, -1):
        nrm = v3((np.sin(np.radians(sgn * 38)), 0, np.cos(np.radians(sgn * 38))))
        strap = Fn(lambda P, nrm=nrm: np.maximum(np.abs((P - xc) @ nrm) - 0.13, P[:, 1]))
        cr.gadd("Torso", shell(TP, 0.045, strap), "strap", prio=0.004, low=False)
    ring_c = surface_points(TP, v3((0, 0, zt - 1.35)), 1, seed=0, zr=(-0.01, 0.01), front_bias=50.0)[0][0]
    cr.gadd("Torso", Ring(ring_c + v3((0, -0.03, 0)), 0.17, 0.17, 0.04, np.array([[1, 0, 0], [0, 0, 1], [0, 1, 0]])),
            "metal", k=0.005, low=False)
    wear(cr, "Torso", T, 0.07, below(0.12, 0.02, nz, 3.0), "pants", 0.004)
    cr.gadd("Torso", shell(T, 0.11, band(-0.2, 0.18)), "strap", prio=0.006)
    cr.gadd("Torso", rbox((-0.3, fy - 0.2, -0.24), (0.3, fy, 0.22), 0.04), "metal", k=0.01, prio=0.007)
    # head: an iron plate welded over the face, slit eyes, riveted, strapped on
    Hb, hc = head_box(D, 0.18)
    cr.gadd("Head", Hb, "skin_head")
    cr.gadd("Head", rbox((-0.5, -0.5, zt - 0.5), (0.5, 0.5, D.hb + 0.2), 0.1), "skin_head", k=0.03)
    hy = -D.head_fwd - D.head[1] / 2
    hb = D.hb
    mask = rbox((-0.66, hy - 0.11, hb + 0.08), (0.66, hy + 0.14, hb + 1.22), 0.05)
    cr.gadd("Head", Displace(mask, lambda P: nz.fbm(P * 3.0, 2), 0.02), "iron", k=0.01, prio=0.005)
    cr.gadd("Head", shell(Hb, 0.06, band(hb + 0.8, hb + 1.0)), "strap", prio=0.006)
    slits, eyes = [], []
    for sx in (1, -1):
        c = v3((sx * 0.3, hy - 0.1, hb + 0.82))
        slits.append(Box(c, v3((0.2, 0.3, 0.05)), euler(0, sx * -10, 0), rad=0.02))
        e = v3((sx * 0.3, hy + 0.12, hb + 0.82))
        eyes.append(Ellipsoid(e, v3((0.15, 0.06, 0.05))))
        cr.eye_points.append(e)
    cr.gsub("Head", Union(slits), "socket", k=0.01)
    cr.gadd("Head", Union(eyes), "eye", k=0.005)
    vents = [rbox((-0.36, hy - 0.2, hb + 0.3 + 0.12 * i), (0.36, hy + 0.05, hb + 0.35 + 0.12 * i), 0.015) for i in range(3)]
    cr.gsub("Head", Union(vents), "socket", k=0.008)
    rv = [v3((x, hy - 0.11, z)) for x in (-0.56, 0.56) for z in np.linspace(hb + 0.2, hb + 1.1, 4)]
    rv += [v3((x, hy - 0.11, hb + 1.13)) for x in np.linspace(-0.4, 0.4, 4)]
    cr.gadd("Head", rivets(rv, 0.045), "iron", k=0.01, low=False)
    for s in "LR":
        sx = 1 if s == "L" else -1
        g = "LeftArm" if s == "L" else "RightArm"
        a = D.arm[s]
        A = arm_box(D, s, 0.14)
        fore = rbox((min(a["x0"], a["x1"]) - 0.16, -D.arm_d / 2 - 0.18, a["wr"] - 0.05), (max(a["x0"], a["x1"]) + 0.16, D.arm_d / 2 + 0.16, a["el"] - 0.1), 0.2)
        fist = rbox((min(a["x0"], a["x1"]) - 0.2, -D.arm_d / 2 - 0.22, a["bot"]), (max(a["x0"], a["x1"]) + 0.2, D.arm_d / 2 + 0.2, a["wr"] + 0.02), 0.18)
        cr.gadd(g, Union([A, fore, fist], 0.12), "skin")
        # knuckles
        kn = [Sphere(v3((a["xc"] + sx * 0.0 + o, -D.arm_d / 2 - 0.16, a["bot"] + 0.22)), 0.17) for o in (-0.5, -0.17, 0.17, 0.5)]
        cr.gadd(g, Union(kn), "skin", k=0.05)
        # shoulder growth with bone spikes
        sh = v3((a["xc"], -0.05, a["top"] + 0.05))
        cr.attach(("Left" if s == "L" else "Right") + "UpperArm", lumps(sh, 0.36, 10, 0.42, seed=20 + sx, flat=0.6), "growth", k=0.08)
        sp_b = [sh + v3((sx * 0.25, 0.1, 0.15)), sh + v3((-sx * 0.15, 0.35, 0.12)), sh + v3((sx * 0.45, -0.25, 0.0)), sh + v3((0, -0.2, 0.2))]
        sp_d = [(sx * 0.5, 0.2, 1), (0, 0.6, 1), (sx * 1, -0.2, 0.4), (sx * 0.1, -0.3, 1)]
        cr.attach(("Left" if s == "L" else "Right") + "UpperArm", bone_spikes(sp_b, sp_d, [0.75, 0.6, 0.55, 0.5], 0.12, 30 + sx),
                  "bone", k=0.04)
        gl = "LeftLeg" if s == "L" else "RightLeg"
        lg = D.leg[s]
        L = leg_box(D, s, 0.12)
        cr.gadd(gl, L, "skin")
        holes = [tear(nz, (lg["xc"], -D.leg_d / 2, lg["kn"]), (0.45, 0.2, 0.35))] if s == "L" else []
        wear(cr, gl, L, 0.07, both(above(lg["bot"] + 0.75, 0.08, nz, 3.0, teeth=0.12, period=0.3), below(lg["top"] + 0.3)), "pants", 0.004,
             holes=holes)
        boot_block(cr, gl, lg, D, h=0.7, toe=0.2, t=0.08, cap="iron")
    # chains wrapped round the left forearm, a broken length hanging off it
    la = D.arm["L"]
    lo = v3((min(la["x0"], la["x1"]) - 0.16, -D.arm_d / 2 - 0.18, 0))
    hi = v3((max(la["x0"], la["x1"]) + 0.16, D.arm_d / 2 + 0.16, 0))
    cr.attach("LeftLowerArm", Union([chain_loop(lo, hi, la["el"] - 0.55, out=0.04, link=0.24, wire=0.045, tilt=0.12),
                                     chain_loop(lo, hi, la["el"] - 0.95, out=0.04, link=0.24, wire=0.045, tilt=-0.1)]),
              "iron", k=0.01, low=False)
    fore_box = rbox((lo[0], lo[1], la["wr"]), (hi[0], hi[1], la["el"] - 0.1), 0.2)
    for zc in (la["el"] - 0.55, la["el"] - 0.95):  # plain bands stand in for the links on the game mesh
        cr.attach("LeftLowerArm", shell(fore_box, 0.1, band(zc - 0.09, zc + 0.12)), "iron", low="only")
    cr.attach("LeftLowerArm", hanging_chain(v3((hi[0] + 0.05, 0.1, la["el"] - 1.0)), 4, link=0.24, wire=0.045), "iron", k=0.01)
    cr.wounds += [(v3((1.0, fy - 0.1, 2.0)), 0.3), (v3((-2.3, -0.9, 0.8)), 0.25)]
    cr.palette = {
        "skin": skin((86, 98, 64), (58, 68, 42), extra={"vein": (46, 52, 40), "vein_amt": 0.55, "spot": (78, 70, 56)}),
        "skin_head": skin((90, 102, 68), (62, 72, 46), extra={"spot": (80, 72, 58)}),
        "growth": Mat((96, 104, 62), "skin", (66, 74, 42), rough=0.6, disp=0.012, disp_freq=12,
                      extra={"vein": (50, 58, 36), "vein_amt": 0.5}),
        "bone": Mat((200, 190, 162), "bone", (150, 140, 116), rough=0.6, disp=0.008, disp_freq=14),
        "iron": Mat((96, 92, 86), "metal", (92, 58, 36), rough=0.45, metal=0.85, disp=0.006, disp_freq=10, extra={"rust_lo": -0.4}),
        "metal": Mat((110, 108, 102), "metal", (90, 60, 40), rough=0.4, metal=0.85),
        "strap": Mat((60, 44, 32), "leather", (40, 30, 22), rough=0.7, disp=0.004, disp_freq=16),
        "socket": Mat((10, 10, 9), "plain", (6, 6, 6), rough=0.9),
        "eye": Mat((255, 130, 60), "eye", rough=0.25, glow=1.0),
        "pants": Mat((70, 64, 46), "canvas", (50, 46, 34), rough=0.9, disp=0.005, disp_freq=14),
        "boot": Mat((46, 38, 30), "leather", (30, 25, 20), rough=0.7, disp=0.004, disp_freq=12),
        "sole": Mat((22, 20, 18), "plain", (16, 15, 14), rough=0.85),
    }
    return cr


# =========================================================================== BLOATER
def bloater():
    cr = Creature("Bloater", 5.75)
    cr.seed = 51
    cr.tri_budget = 6500
    cr.eye_color = (210, 255, 90)
    cr.notes = "Big and wide. A swollen barrel of a body covered in glowing green sacs; made to pop into a cloud."
    D = block_skeleton(cr, torso_w=3.0, torso_d=2.3, ut_h=2.6, lt_h=0.6, head=(1.0, 1.0, 1.0), head_fwd=0.15,
                       head_drop=0.25, arm_w=0.85, arm_d=0.85, arm_len=2.1, arm_gap=0.0, arm_drop=0.35,
                       leg_w=1.05, leg_d=1.05, leg_len=1.75, leg_gap=0.35, reach=0.2)
    cr.crack = dict(scale=0.45, depth=0.02, width=0.085, seed=14, seam=(34, 46, 14), patch_lo=0.15)
    nz = Noise(cr.seed)
    zt = D.zt
    T = Union([torso_box(D, 0.55), Ellipsoid(v3((0, -0.75, 0.75)), v3((1.3, 0.7, 1.05)))], 0.35)
    cr.gadd("Torso", T, "skin")
    wear(cr, "Torso", T, 0.05, both(above(1.25, 0.12, nz, 2.5, teeth=0.1), below(zt + 0.2)), "tanktop", 0.003,
         holes=[tear(nz, (0.6, -1.3, 1.6), (0.35, 0.3, 0.3)), tear(nz, (-0.8, 1.1, 2.0), (0.4, 0.3, 0.3))])
    wear(cr, "Torso", T, 0.06, below(0.2, 0.04, nz, 3.0), "shorts", 0.004)
    sacs = []
    rng = np.random.default_rng(17)
    for (p, d) in surface_points(T, v3((0, -0.2, 0.9)), 30, seed=5, zr=(-0.6, 0.8), front_bias=0.25):
        r = rng.uniform(0.1, 0.27)
        sacs.append(Sphere(p + d * r * 0.05, r))
        if rng.uniform() < 0.35:  # a few grow in clusters
            sacs.append(Sphere(p + d * 0.02 + v3(rng.normal(0, 0.16, 3)), r * 0.6))
    cr.gadd("Torso", Union(sacs, 0.04), "sac", k=0.05, prio=0.006)
    Hb, hc = head_box(D, 0.24)
    cr.gadd("Head", Hb, "skin_head")
    cr.gadd("Head", rbox((-0.42, -0.42, zt - 0.5), (0.42, 0.42, D.hb + 0.15), 0.12), "skin_head", k=0.05)
    apply_items(cr, "Head", block_face(cr, D, eye_w=0.2, eye_h=0.12, eye_sep=0.22, eye_z=0.56, eye_r=0.06, eye_tilt=6,
                                       mouth_w=0.26, mouth_h=0.12, mouth_z=0.22, jag=0.02, brow=0.05))
    cr.gadd("Head", Union([Sphere(v3((0.28, -0.62, D.hb + 0.82)), 0.11), Sphere(v3((-0.3, -0.5, D.hb + 0.98)), 0.08)]), "sac", k=0.02)
    for s in "LR":
        g = "LeftArm" if s == "L" else "RightArm"
        a = D.arm[s]
        A = arm_box(D, s, 0.16)
        cr.gadd(g, A, "skin")
        asacs = [Sphere(v3((a["x1"] * 0.98, -0.1 + 0.2 * i, a["top"] - 0.4 - 0.55 * i)), 0.13 + 0.03 * i) for i in range(3)]
        cr.gadd(g, Union(asacs), "sac", k=0.03, prio=0.006)
        claws(cr, D, s, n=3, length=0.12, r0=0.06, spread=0.3, curl=0.15, seed=51 + (s == "L"))
        gl = "LeftLeg" if s == "L" else "RightLeg"
        lg = D.leg[s]
        L = leg_box(D, s, 0.16)
        cr.gadd(gl, L, "skin")
        wear(cr, gl, L, 0.06, both(above(lg["kn"] + 0.15, 0.06, nz, 4.0, teeth=0.1), below(lg["top"] + 0.2)), "shorts", 0.004)
        tz = [Sphere(v3((lg["xc"] + o, -D.leg_d / 2 - 0.02, lg["bot"] + 0.09)), 0.1) for o in (-0.32, -0.1, 0.12, 0.32)]
        cr.gadd(gl, Union(tz), "skin", k=0.04)
    cr.wounds += [(v3((0.6, -1.35, 1.6)), 0.35), (v3((-0.8, 1.15, 2.0)), 0.35)]
    cr.palette = {
        "skin": skin((130, 138, 86), (98, 106, 62), extra={"vein": (56, 76, 34), "vein_amt": 0.65}),
        "skin_head": skin((136, 142, 92), (102, 108, 66)),
        "sac": Mat((185, 255, 95), "sac", (52, 86, 26), rough=0.25, glow=0.85, disp=0.004, disp_freq=24),
        "socket": Mat((18, 20, 10), "plain", (12, 13, 8), rough=0.9),
        "eye": Mat((220, 255, 110), "eye", rough=0.25, glow=1.0),
        "mouth": Mat((14, 16, 8), "plain", (10, 11, 6), rough=0.9),
        "nail": Mat((70, 66, 44), "plain", (50, 46, 30), rough=0.5),
        "tanktop": Mat((140, 136, 118), "cloth", (104, 100, 84), rough=0.92, disp=0.005, disp_freq=18),
        "shorts": Mat((72, 58, 42), "cloth", (52, 42, 30), rough=0.9, disp=0.005, disp_freq=16),
    }
    return cr


# =========================================================================== GOLIATH (boss)
def goliath():
    cr = Creature("Goliath", 10.65)
    cr.seed = 61
    cr.tri_budget = 11000
    cr.eye_color = (255, 170, 60)
    cr.uses_metal = True
    cr.notes = "Boss. A towering charred hulk whose cracks glow like embers, bone spikes, iron collar and broken shackles."
    D = block_skeleton(cr, torso_w=4.4, torso_d=2.6, ut_h=4.2, lt_h=0.8, head=(1.9, 1.8, 1.8), head_fwd=0.35,
                       head_drop=0.35, arm_w=2.1, arm_d=2.2, arm_len=5.0, arm_split=(0.42, 0.42), arm_gap=0.05,
                       leg_w=2.0, leg_d=2.1, leg_len=4.2, leg_gap=0.3, toe=0.15, reach=0.4)
    cr.crack = dict(scale=0.9, depth=0.06, width=0.08, seed=9, seam=(255, 138, 38), glow=1.0, wet=0.0, patch_lo=0.35)
    nz = Noise(cr.seed)
    zt = D.zt
    fy, by = -D.torso_d / 2, D.torso_d / 2
    T = torso_box(D, 0.22)
    pecs = [rbox((sx * 0.08 if sx > 0 else -2.0, fy - 0.16, zt - 1.7), (2.0 if sx > 0 else -0.08, fy + 0.4, zt - 0.3), 0.3) for sx in (1, -1)]
    cr.gadd("Torso", Union([T] + pecs, 0.15), "skin")
    # iron collar with a broken chain at the front
    cr.gadd("Torso", shell(T, 0.16, band(zt - 0.55, zt + 0.1)), "iron", prio=0.006)
    rv = [v3((x, fy - 0.17, zt - 0.25)) for x in np.linspace(-1.9, 1.9, 7)]
    cr.gadd("Torso", rivets(rv, 0.07), "iron", k=0.01, low=False)
    cr.attach("UpperTorso", hanging_chain(v3((0.5, fy - 0.25, zt - 0.5)), 4, link=0.32, wire=0.06), "iron", k=0.01)
    # spine of bone spikes
    sb = [v3((0, by + 0.0, z)) for z in np.linspace(1.6, zt - 0.4, 5)]
    cr.attach("UpperTorso", bone_spikes(sb, [(0, 1, 0.6)] * 5, [0.9, 1.1, 1.2, 1.0, 0.8], 0.2, 7), "bone", k=0.06)
    # leather straps hanging from the waist
    lt0 = -D.lt_h / 2
    for yy, sgn in ((fy, -1), (by, 1)):
        flap = Intersect(rbox((-1.3, yy + sgn * 0.1 - 0.1, lt0 - 1.9), (1.3, yy + sgn * 0.1 + 0.1, lt0 + 0.5), 0.04),
                         above(lt0 - 1.15, 0.12, nz, 2.0, teeth=0.6, period=0.42), 0.006)
        cr.attach("LowerTorso", flap, "strap", k=0.015)
    cr.gadd("Torso", shell(T, 0.12, band(-0.45, 0.25)), "strap", prio=0.006)
    Hb, hc = head_box(D, 0.24)
    cr.gadd("Head", Hb, "skin_head")
    cr.gadd("Head", rbox((-0.7, -0.7, zt - 0.6), (0.7, 0.7, D.hb + 0.3), 0.15), "skin_head", k=0.05)
    apply_items(cr, "Head", block_face(cr, D, eye_w=0.2, eye_h=0.12, eye_sep=0.23, eye_z=0.6, eye_r=0.06, eye_tilt=18,
                                       eye_depth=0.14, mouth_w=0.6, mouth_h=0.12, mouth_z=0.24, mouth_depth=0.12, jag=0.04, brow=0.12))
    top = D.hb + D.head[2]
    cr.gadd("Head", lumps(v3((0, -D.head_fwd + 0.15, top - 0.02)), 0.3, 9, 0.4, seed=8, flat=0.55), "skin_head", k=0.08)
    cb = [v3((x, -D.head_fwd + 0.2 + 0.1 * abs(x), top + 0.12)) for x in (-0.6, -0.2, 0.2, 0.6)]
    cr.gadd("Head", bone_spikes(cb, [(x * 0.6, 0.3, 1) for x in (-0.6, -0.2, 0.2, 0.6)], [0.55, 0.7, 0.7, 0.55], 0.12, 9), "bone", k=0.04)
    for s in "LR":
        sx = 1 if s == "L" else -1
        side = "Left" if s == "L" else "Right"
        g = side + "Arm"
        a = D.arm[s]
        xa, xb = min(a["x0"], a["x1"]), max(a["x0"], a["x1"])
        A = arm_box(D, s, 0.2)
        fist = rbox((xa - 0.15, -D.arm_d / 2 - 0.15, a["bot"]), (xb + 0.15, D.arm_d / 2 + 0.15, a["wr"] + 0.02), 0.22)
        cr.gadd(g, Union([A, fist], 0.12), "skin")
        cr.gadd(g, shell(A, 0.14, band(a["wr"] + 0.08, a["wr"] + 0.7)), "iron", prio=0.006)
        cr.attach(side + "LowerArm", hanging_chain(v3((a["xc"] + sx * 0.4, -D.arm_d / 2 - 0.2, a["wr"] + 0.2)), 3, link=0.32, wire=0.06),
                  "iron", k=0.01)
        sh = v3((a["xc"], 0.0, a["top"] + 0.05))
        cr.attach(side + "UpperArm", lumps(sh, 0.5, 12, 0.6, seed=40 + sx, flat=0.6), "skin", k=0.12)
        spb = [sh + v3((sx * 0.4, 0.2, 0.2)), sh + v3((-sx * 0.2, 0.5, 0.2)), sh + v3((sx * 0.7, -0.3, 0.0)),
               sh + v3((0, -0.4, 0.25)), sh + v3((sx * 0.1, 0.1, 0.35))]
        spd = [(sx * 0.6, 0.3, 1), (0, 0.7, 1), (sx * 1, -0.2, 0.5), (sx * 0.2, -0.5, 1), (0, 0, 1)]
        cr.attach(side + "UpperArm", bone_spikes(spb, spd, [1.2, 1.0, 0.9, 0.9, 1.4], 0.2, 50 + sx), "bone", k=0.05)
        fb = [v3((a["xc"] + sx * 0.3 * (i - 1), D.arm_d / 2, a["el"] - 0.5 - 0.6 * i)) for i in range(3)]
        cr.attach(side + "LowerArm", bone_spikes(fb, [(0, 1, -0.5)] * 3, [0.8, 0.95, 0.7], 0.16, 60 + sx), "bone", k=0.04)
        claws(cr, D, s, n=4, length=0.35, r0=0.13, spread=0.32, curl=0.25, mat="bone", seed=70 + (s == "L"))
        gl = side + "Leg"
        lg = D.leg[s]
        cr.gadd(gl, leg_box(D, s, 0.2), "skin")
        kb = [v3((lg["xc"] + o, -D.leg_d / 2, lg["kn"] + 0.1)) for o in (-0.4, 0.4)]
        cr.attach(side + "UpperLeg", bone_spikes(kb, [(0, -1, 0.3)] * 2, [0.6, 0.5], 0.14, 80 + sx), "bone", k=0.04)
        tc = [spike(v3((lg["xc"] + o, -D.leg_d / 2 - 0.05, lg["bot"] + 0.15)), v3((lg["xc"] + o * 1.15, -D.leg_d / 2 - 0.5, lg["bot"] + 0.02)), 0.13)
              for o in (-0.6, 0.0, 0.6)]
        cr.attach(side + "Foot", Union(tc), "bone", k=0.03)
    cr.palette = {
        "skin": skin((48, 42, 40), (30, 27, 26), rough=0.7, extra={"vein": (90, 50, 26), "vein_amt": 0.35}),
        "skin_head": skin((52, 45, 42), (32, 28, 27), rough=0.7),
        "bone": Mat((206, 196, 170), "bone", (150, 140, 116), rough=0.6, disp=0.01, disp_freq=10),
        "iron": Mat((84, 80, 76), "metal", (88, 52, 30), rough=0.45, metal=0.85, disp=0.008, disp_freq=8, extra={"rust_lo": -0.3}),
        "strap": Mat((54, 40, 30), "leather", (34, 26, 20), rough=0.7, disp=0.005, disp_freq=10),
        "socket": Mat((12, 6, 4), "plain", (8, 4, 3), rough=0.9),
        "eye": Mat((255, 190, 90), "eye", rough=0.25, glow=1.0),
        "mouth": Mat((255, 120, 30), "eye", rough=0.4, glow=0.9),
        "nail": Mat((206, 196, 170), "bone", (150, 140, 116), rough=0.6),
    }
    return cr


# =========================================================================== WIDOW (boss)
def widow():
    cr = Creature("Widow", 10.1)
    cr.seed = 71
    cr.tri_budget = 10000
    cr.eye_color = (190, 225, 255)
    cr.notes = "Boss. Impossibly tall and thin, hair hanging over the face, tattered black dress, claws a stud long."
    D = block_skeleton(cr, torso_w=1.7, torso_d=0.85, ut_h=2.3, lt_h=0.5, head=(1.2, 1.15, 1.35), neck=0.35,
                       head_fwd=0.15, arm_w=0.55, arm_d=0.55, arm_len=4.0, arm_split=(0.44, 0.44), arm_gap=0.04,
                       leg_w=0.62, leg_d=0.62, leg_len=5.6, leg_gap=0.3, reach=0.2)
    cr.crack = dict(scale=0.5, depth=0.018, width=0.09, seed=15, seam=(40, 44, 52), patch_lo=0.1)
    nz = Noise(cr.seed)
    zt = D.zt
    fy = -D.torso_d / 2
    T = torso_box(D, 0.08)
    cr.gadd("Torso", T, "skin")
    wear(cr, "Torso", T, 0.06, above(-0.3, 0.03, nz, 3.0), "dress", 0.003)
    cr.gadd("Torso", shell(T, 0.08, band(0.9, 1.15)), "lace", prio=0.004)
    # flared tattered skirt, rigid on the LowerTorso, long strips at the hem
    lt0 = -D.lt_h / 2
    # one solid flared bell with long strips at the hem (solid meshes and decimates cleanly; the legs move inside it)
    def bell(P):
        t = np.clip((lt0 + 0.5 - P[:, 2]) / 3.4, 0.0, 1.0)  # 0 at the waist, 1 at the hem
        fl = smoothstep(0.7, 1.0, t)  # narrow past the hands and claws, then flares below the knees
        hx = 0.88 + 0.65 * fl
        hy = 0.53 + 0.5 * fl
        q = np.stack([np.abs(P[:, 0]) - hx + 0.25, np.abs(P[:, 1]) - hy + 0.25], 1)
        d2 = np.sqrt((np.maximum(q, 0) ** 2).sum(1)) + np.minimum(q.max(1), 0) - 0.25
        return np.maximum(d2, np.maximum(P[:, 2] - (lt0 + 0.5), (lt0 - 3.6) - P[:, 2]))
    bell_n = Fn(bell, (-1.8, -1.2, lt0 - 3.7), (1.8, 1.2, lt0 + 0.6))
    hem = above(lt0 - 2.55, 0.25, nz, 1.5, teeth=0.95, period=0.3)
    skirt = Intersect(bell_n, hem, 0.01)
    cr.attach("LowerTorso", Displace(skirt, lambda P: nz.fbm(P * v3((4, 4, 1.2)), 3), 0.035), "dress", k=0.02, low=False)
    # the game mesh gets fewer, wider strips with clean edges; the torn detail is baked onto them
    wave = Fn(lambda P: (lt0 - 2.75 - 0.45 * (0.5 + 0.5 * np.sin(2 * np.pi * (P[:, 0] + P[:, 1]) / 0.6))) - P[:, 2])
    cr.attach("LowerTorso", Intersect(bell_n, wave, 0.02), "dress", low="only")
    # thin neck and a head behind a curtain of hair
    Hb, hc = head_box(D, 0.16)
    cr.gadd("Head", Hb, "skin_head")
    cr.gadd("Head", rbox((-0.17, -0.17 - D.head_fwd * 0.5, zt - 0.3), (0.17, 0.17 - D.head_fwd * 0.5, D.hb + 0.15), 0.06), "skin_head", k=0.03)
    apply_items(cr, "Head", block_face(cr, D, eye_w=0.2, eye_h=0.1, eye_sep=0.2, eye_z=0.55, eye_r=0.055, eye_tilt=-6,
                                       mouth_w=0.4, mouth_h=0.2, mouth_z=0.22, jag=0.04, brow=0.0))
    hb, top = D.hb, D.hb + D.head[2]
    hy = -D.head_fwd - D.head[1] / 2
    face_open = rbox((-0.8, hy - 0.3, hb - 0.2), (0.8, hy + 0.18, top - 0.16), 0.02)  # keep the face clear
    cr.gadd("Head", Intersect(Offset(Hb, 0.06), Subtract(above(hb + 0.5, 0.05, nz, 4.0), face_open), 0.01), "hair", prio=0.004)
    rng = np.random.default_rng(3)
    strands = []
    for i, x in enumerate(np.linspace(-0.56, 0.56, 11)):
        gap = min(abs(x - 0.24), abs(x + 0.24)) < 0.07  # let the eyes show through
        if gap:
            continue
        L = rng.uniform(1.6, 2.6)
        y0 = hy - 0.07
        pts = [v3((x, y0, top - 0.05))]
        for j in range(1, 5):
            pts.append(v3((x + rng.normal(0, 0.03), y0 - 0.03 * j - 0.06 * max(0, j - 2), top - 0.05 - L * j / 4)))
        strands.append(chain(pts, [0.07, 0.075, 0.07, 0.06, 0.025]))
    by_ = -D.head_fwd + D.head[1] / 2
    for i, x in enumerate(np.linspace(-0.6, 0.6, 9)):
        L = rng.uniform(2.6, 3.4)
        pts = [v3((x, by_ + 0.06, top - 0.1))] + [v3((x * (1.0 + 0.1 * j) + rng.normal(0, 0.03), by_ + 0.08 + 0.02 * j, top - 0.1 - L * j / 4))
                                                  for j in range(1, 5)]
        strands.append(chain(pts, [0.09, 0.09, 0.085, 0.07, 0.03]))
    for sx in (1, -1):
        for j in range(3):
            x = sx * (0.62 + 0.02 * j)
            pts = [v3((x, -0.3 + 0.3 * j - D.head_fwd, top - 0.15))] + [v3((x + sx * 0.03 * k, -0.3 + 0.3 * j - D.head_fwd + rng.normal(0, 0.03),
                                                                             top - 0.15 - 0.6 * k)) for k in range(1, 5)]
            strands.append(chain(pts, [0.08, 0.08, 0.075, 0.06, 0.025]))
    cr.attach("Head", Union(strands, 0.03), "hair", k=0.04, prio=0.004)
    for s in "LR":
        side = "Left" if s == "L" else "Right"
        a = D.arm[s]
        A = arm_box(D, s, 0.06)
        cr.gadd(side + "Arm", A, "skin")
        wear(cr, side + "Arm", A, 0.06, above(a["el"] - 0.5, 0.12, nz, 3.0, teeth=0.18, period=0.18), "dress", 0.003)
        claws(cr, D, s, n=4, length=1.0, r0=0.075, spread=0.4, curl=0.35, mat="claw", seed=90 + (s == "L"))
        lg = D.leg[s]
        cr.gadd(side + "Leg", leg_box(D, s, 0.06), "skin")
        cr.gadd(side + "Leg", Sphere(v3((lg["xc"], -0.16, lg["kn"])), 0.22), "skin", k=0.05)
        tc = [spike(v3((lg["xc"] + o, -D.leg_d / 2 - 0.02, lg["bot"] + 0.06)), v3((lg["xc"] + o * 1.3, -D.leg_d / 2 - 0.32, lg["bot"] + 0.01)), 0.05)
              for o in (-0.2, 0.0, 0.2)]
        cr.attach(side + "Foot", Union(tc), "nail", k=0.02)
    cr.palette = {
        "skin": skin((150, 156, 164), (112, 118, 128), extra={"vein": (90, 96, 120), "vein_amt": 0.55}),
        "skin_head": skin((156, 162, 170), (116, 122, 132)),
        "hair": Mat((9, 9, 11), "hair", (18, 18, 21), rough=0.55, disp=0.008, disp_freq=26),
        "dress": Mat((26, 24, 28), "cloth", (40, 36, 42), rough=0.85, disp=0.006, disp_freq=14),
        "lace": Mat((46, 44, 50), "cloth", (30, 28, 34), rough=0.7, disp=0.01, disp_freq=40),
        "socket": Mat((8, 8, 12), "plain", (5, 5, 8), rough=0.9),
        "eye": Mat((205, 232, 255), "eye", rough=0.25, glow=1.0),
        "mouth": Mat((8, 8, 10), "plain", (5, 5, 6), rough=0.9),
        "nail": Mat((30, 28, 30), "plain", (18, 17, 19), rough=0.35),
        "claw": Mat((120, 116, 108), "bone", (64, 60, 56), rough=0.4, disp=0.004, disp_freq=20),
    }
    return cr


REGISTRY = {"Walker": walker, "Runner": runner, "Grabber": grabber, "Brute": brute, "Bloater": bloater,
            "Goliath": goliath, "Widow": widow}
