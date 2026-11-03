"""Blocky R15 kit (Roblox block-body proportions) with horror dressing.

Each group (Head, Torso, arms, legs) is one solid block plus its dressing, cut flush at the joint
heights into the 15 R15 parts. Children reach a little into their parent (just under its skin), so a
bent elbow or knee doesn't open a hole. Origin = Root joint at the centre of the LowerTorso, the
creature faces -Y, +X is its left.
"""
import numpy as np
from ll_sdf import v3, norm, Sphere, Ellipsoid, RoundCone, Box, Ring, Fn, Union, Subtract, Intersect, Offset, \
    Displace, chain, Noise, euler

X, Y, Z = v3((1, 0, 0)), v3((0, 1, 0)), v3((0, 0, 1))


def lerp(a, b, t):
    return v3(a) + (v3(b) - v3(a)) * t


def rbox(lo, hi, rad=0.0, R=None):
    lo, hi = v3(lo), v3(hi)
    return Box((lo + hi) * 0.5, (hi - lo) * 0.5, R, rad)


class Dims:
    pass


def block_skeleton(cr, torso_w=2.0, torso_d=1.0, ut_h=1.6, lt_h=0.4, head=(1.2, 1.2, 1.2), neck=0.0,
                   head_fwd=0.0, head_drop=0.0, arm_w=1.0, arm_d=1.0, arm_len=2.0, arm_split=(0.47, 0.38),
                   arm_gap=0.0, arm_drop=0.0, leg_w=1.0, leg_d=1.0, leg_len=2.0, leg_split=(0.475, 0.375),
                   leg_gap=0.0, toe=0.0, reach=0.2):
    D = Dims()
    D.torso_w, D.torso_d, D.ut_h, D.lt_h = torso_w, torso_d, ut_h, lt_h
    D.head, D.neck, D.head_fwd = v3(head), neck, head_fwd
    D.arm_w, D.arm_d, D.arm_len, D.leg_w, D.leg_d, D.leg_len = arm_w, arm_d, arm_len, leg_w, leg_d, leg_len
    J = {}
    J["root"] = v3((0, 0, 0))
    J["waist"] = v3((0, 0, lt_h / 2))
    zt = lt_h / 2 + ut_h
    D.zt = zt
    J["neck"] = v3((0, 0, zt - head_drop))
    hb = zt + neck - head_drop
    D.hb = hb
    J["headbase"] = v3((0, -head_fwd, hb))
    J["headtop"] = v3((0, -head_fwd, hb + head[2]))
    D.arm = {}
    D.leg = {}
    for s, sx in (("L", 1.0), ("R", -1.0)):
        x_in = torso_w / 2 + arm_gap
        xc = x_in + arm_w / 2
        top = zt - arm_drop
        J["shoulder_" + s] = v3((sx * (x_in + arm_w * 0.22), 0, top - min(arm_w, arm_len * 0.3) * 0.5))
        el = top - arm_len * arm_split[0]
        wr = el - arm_len * arm_split[1]
        J["elbow_" + s] = v3((sx * xc, 0, el))
        J["wrist_" + s] = v3((sx * xc, 0, wr))
        J["handtip_" + s] = v3((sx * xc, 0, top - arm_len))
        D.arm[s] = dict(x0=sx * x_in, x1=sx * (x_in + arm_w), xc=sx * xc, top=top, bot=top - arm_len, el=el, wr=wr,
                        lo=v3((min(sx * x_in, sx * (x_in + arm_w)), -arm_d / 2, top - arm_len)),
                        hi=v3((max(sx * x_in, sx * (x_in + arm_w)), arm_d / 2, top)))
        xl = leg_gap / 2 + leg_w / 2
        hz = -lt_h / 2
        kn = hz - leg_len * leg_split[0]
        an = kn - leg_len * leg_split[1]
        g = hz - leg_len
        J["hip_" + s] = v3((sx * xl, 0, hz))
        J["knee_" + s] = v3((sx * xl, 0, kn))
        J["ankle_" + s] = v3((sx * xl, 0, an))
        J["toe_" + s] = v3((sx * xl, -leg_d / 2 - toe, g))
        J["heel_" + s] = v3((sx * xl, leg_d / 2, g))
        D.leg[s] = dict(xc=sx * xl, top=hz, kn=kn, an=an, bot=g,
                        lo=v3((sx * xl - leg_w / 2, -leg_d / 2, g)), hi=v3((sx * xl + leg_w / 2, leg_d / 2, hz)))
    cr.ground = -lt_h / 2 - leg_len
    cr.J = J
    cr.reach = reach
    cr.D = D
    return D


def torso_box(D, rad):
    return rbox((-D.torso_w / 2, -D.torso_d / 2, -D.lt_h / 2), (D.torso_w / 2, D.torso_d / 2, D.zt), rad)


def head_box(D, rad):
    h = D.head
    c = v3((0, -D.head_fwd, D.hb + h[2] / 2))
    return Box(c, h / 2, None, rad), c


def arm_box(D, s, rad):
    a = D.arm[s]
    return rbox(a["lo"], a["hi"], rad)


def leg_box(D, s, rad):
    a = D.leg[s]
    return rbox(a["lo"], a["hi"], rad)


# --------------------------------------------------------------------------- dressing
def lumps(center, size, count, spread, seed=0, flat=0.7, normal=Z):
    """A cluster of fleshy growths around center, squashed along normal."""
    rng = np.random.default_rng(seed)
    n = norm(normal)
    t1 = norm(np.cross(n, X if abs(n @ X) < 0.9 else Y))
    t2 = np.cross(n, t1)
    R = np.stack([t1, t2, n], 1)
    kids = []
    for i in range(count):
        o = v3(center) + t1 * rng.normal(0, spread) + t2 * rng.normal(0, spread) + n * rng.normal(0, spread * 0.25)
        r = size * rng.uniform(0.55, 1.15)
        kids.append(Ellipsoid(o, v3((r, r * rng.uniform(0.8, 1.2), r * flat)), R))
    return Union(kids, size * 0.35)


def spike(base, tip, r0, r1=None):
    return RoundCone(base, tip, r0, r1 if r1 is not None else r0 * 0.12)


def spikes_along(points, dirs, lens, r0, seed=0, jitter=0.15):
    rng = np.random.default_rng(seed)
    out = []
    for p, d, L in zip(points, dirs, lens):
        dd = norm(v3(d) + rng.normal(0, jitter, 3))
        out.append(spike(p, v3(p) + dd * L, r0 * rng.uniform(0.8, 1.2)))
    return Union(out)


def chain_links(points, link_r, wire_r):
    """Chain links between consecutive points (alternating 90 degree turns)."""
    links = []
    for i in range(len(points) - 1):
        a, b = v3(points[i]), v3(points[i + 1])
        c = (a + b) * 0.5
        d = norm(b - a)
        up = X if abs(d @ X) < 0.8 else Y
        side = norm(np.cross(d, up))
        if i % 2:
            side = norm(np.cross(d, side))
        n = np.cross(d, side)
        R = np.stack([d, side, n], 1)  # ring in the d-side plane
        L = np.linalg.norm(b - a)
        links.append(Ring(c, L * 0.62, link_r, wire_r, R))
    return Union(links)


def rivets(points, r):
    return Union([Sphere(p, r) for p in points])


def jagged_below(z0, amp, noise, freq, teeth=0.0, period=0.25):
    """Region inside where z > a ragged line around z0 (hem). teeth adds a saw edge."""
    def f(P):
        e = z0 + amp * noise.fbm(P * freq, 3)
        if teeth > 0:
            ang = np.arctan2(P[:, 1], P[:, 0])
            u = (P[:, 0] + P[:, 1]) / period
            e = e - teeth * np.abs((u % 1.0) - 0.5) * 2.0
        return e - P[:, 2]
    return Fn(f)


def shell(base, t, region, holes=(), hole_k=0.02, fold=None, fold_amp=0.0):
    n = Offset(base, t)
    if fold is not None:
        n = Displace(n, fold, fold_amp)
    reg = region
    for h in holes:
        reg = Subtract(reg, h, hole_k)
    return Intersect(n, reg, 0.006)


def tear(noise, c, r, amp=0.45, freq=7.0):
    c = v3(c)
    rr = v3(r) if np.ndim(r) else v3((r, r, r))

    def f(P):
        q = (P - c) / rr
        return (np.sqrt((q * q).sum(1)) - 1.0) * rr.min() + amp * rr.min() * noise.fbm(P * freq, 3)

    return Fn(f, c - rr * 1.6, c + rr * 1.6)


def block_face(cr, D, eye_w=0.2, eye_h=0.16, eye_sep=0.25, eye_z=0.56, eye_depth=0.1, eye_r=0.075,
               mouth_w=0.46, mouth_h=0.07, mouth_z=0.27, mouth_depth=0.08, brow=0.06, jag=0.03, seed=3,
               eye_shape="round", eye_tilt=12.0):
    """Sunken glowing eyes, a brow ridge and a ragged dark mouth slot (no teeth: owner rule)."""
    h = D.head
    fz = D.hb
    fy = -D.head_fwd - h[1] / 2  # front face plane
    nz = Noise(cr.seed + seed)
    items = []
    socks, eyes = [], []
    for sx in (1, -1):
        c = v3((sx * eye_sep * h[0], fy, fz + eye_z * h[2]))
        R = euler(0, sx * -eye_tilt, 0)  # slanted, angry sockets
        socks.append(Box(c + v3((0, eye_depth * 0.3, 0)), v3((eye_w * h[0] / 2, eye_depth, eye_h * h[2] / 2)), R,
                         rad=min(eye_w * h[0], eye_h * h[2]) * 0.35))
        e = c + v3((0, eye_depth * 0.85, 0))
        if eye_shape == "round":
            eyes.append(Sphere(e, eye_r * h[0]))
        else:
            eyes.append(Box(e, v3((eye_w * h[0] * 0.32, eye_r * h[0], eye_h * h[2] * 0.3)), R, rad=0.02))
        cr.eye_points.append(e - v3((0, eye_r * h[0] * 0.6, 0)))
    items.append(("sub", Union(socks), "socket", 0.02))
    items.append(("add", Union(eyes), "eye", 0.005))
    if brow > 0:
        bz = fz + (eye_z + eye_h * 0.62) * h[2]
        br = Union([Box(v3((sx * eye_sep * h[0] * 0.85, fy + 0.01, bz)), v3((h[0] * 0.24, brow, brow * 0.9)),
                        euler(0, sx * -eye_tilt * 1.4, 0), rad=brow * 0.6) for sx in (1, -1)], 0.04)
        items.append(("add", br, "skin_head", 0.03))
    mz = fz + mouth_z * h[2]
    mc = v3((0, fy, mz))
    half = v3((mouth_w * h[0] / 2, mouth_depth, mouth_h * h[2] / 2))

    def mouth(P):
        q = np.abs(P - mc) - half
        d = np.sqrt((np.maximum(q, 0) ** 2).sum(1)) + np.minimum(q.max(1), 0)
        return d - jag * h[2] * (0.5 + 0.5 * nz.fbm(P * v3((14, 14, 6)) / h[0], 2))

    items.append(("sub", Fn(mouth, mc - half - 0.1, mc + half + 0.1), "mouth", 0.012))
    return items


def apply_items(cr, group, items):
    for op, node, mat, k in items:
        if op == "add":
            cr.gadd(group, node, mat, k)
        else:
            cr.gsub(group, node, mat, k)


def claws(cr, D, s, n=3, length=0.35, r0=0.07, spread=0.28, curl=0.25, mat="nail", seed=0):
    """Claws hanging from the bottom of a block hand (attached to the Hand part)."""
    a = D.arm[s]
    sx = 1.0 if s == "L" else -1.0
    rng = np.random.default_rng(seed)
    out = []
    for i in range(n):
        t = (i - (n - 1) / 2) / max(n - 1, 1)
        base = v3((a["xc"] + rng.normal(0, 0.02), -D.arm_d * 0.5 * spread * 2 * t - D.arm_d * 0.12, a["bot"] + 0.06))
        tip = base + v3((sx * rng.normal(0, 0.03), -curl * length, -length))
        mid = lerp(base, tip, 0.55) + v3((0, -curl * length * 0.35, 0))
        out.append(chain([base, mid, tip], [r0, r0 * 0.6, r0 * 0.12]))
    cr.attach(("Left" if s == "L" else "Right") + "Hand", Union(out), mat, k=0.02)
