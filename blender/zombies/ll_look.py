"""Per-vertex colour, roughness, metal, glow and fine displacement for the high-res parts."""
import numpy as np
from ll_sdf import Noise, smoothstep, v3, worley
from ll_body import srgb

ICHOR = srgb((30, 42, 12))
ICHOR_WET = srgb((50, 74, 18))
DIRT = srgb((58, 52, 40))


def _mix(a, b, t):
    t = np.clip(t, 0.0, 1.0)[:, None]
    return a * (1.0 - t) + b * t


def crack_fields(cr, V):
    """Cracked-plate hide (the reference look): seam mask, a plate id, and the plate rim."""
    if not cr.crack:
        return None
    c = cr.crack
    nz = Noise(cr.seed * 13 + 7)
    P = V / c["scale"]
    P = P + 0.25 * np.stack([nz(P * 0.7), nz(P * 0.7 + 17.0), nz(P * 0.7 + 31.0)], 1)  # wobbly seams
    f1, f2, idv = worley(P, c.get("seed", 3))
    gap = f2 - f1
    w = c.get("width", 0.07)
    # seams fade in and out along their length so the net reads as torn hide, not paving
    patch = c.get("patch_lo", 0.2) + (1.0 - c.get("patch_lo", 0.2)) * smoothstep(-0.3, 0.4, nz.fbm(V / c["scale"] * 0.4 + 5.0, 3))
    wv = w * (0.7 + 0.6 * smoothstep(-0.5, 0.5, nz(P * 1.7 + 9.0)))
    mask = (1.0 - smoothstep(0.0, wv, gap)) * patch
    rim = smoothstep(wv, wv * 2.2, gap) * (1.0 - smoothstep(wv * 2.2, wv * 4.5, gap)) * patch
    dome = smoothstep(0.0, 0.4, gap) * patch
    # a second, finer crack net inside the plates
    f1b, f2b, _ = worley(P * 2.4, c.get("seed", 3) + 5)
    fine = (1.0 - smoothstep(0.0, w * 0.7, f2b - f1b)) * 0.38 * smoothstep(0.0, 1.0, patch - 0.2)
    return {"mask": mask, "id": idv, "rim": rim, "fine": fine, "dome": dome}


def displace(cr, part, V, N, mids, cf=None):
    """Fine surface detail along the normals (only for the normal-map source)."""
    S = cr.S
    nz = Noise(cr.seed * 7 + 3)
    nz2 = Noise(cr.seed * 7 + 4)
    off = np.zeros(len(V))
    for i, name in enumerate(cr.mat_names):
        m = cr.palette[name]
        sel = mids == i
        if sel.any() and cf is not None and m.extra.get("crack"):
            dep = cr.crack["depth"]
            off[sel] += (-dep * np.maximum(cf["mask"][sel], cf["fine"][sel] * 0.6)
                         + (cf["id"][sel] - 0.5) * dep * 0.2 + cf["dome"][sel] * dep * 0.25)
        if not sel.any() or m.disp <= 0:
            continue
        P = V[sel] / S
        f = m.disp_freq
        k = m.kind
        if k in ("skin", "sac"):
            d = 0.55 * nz.fbm(P * f, 3) + 0.45 * (nz2.ridged(P * f * 0.45, 2) - 0.6)
        elif k in ("cloth", "plaid", "denim", "stripes", "canvas"):
            d = 0.6 * nz.fbm(P * v3((f, f, f * 3.0)), 3) + 0.4 * nz2(P * f * 3.0)
        elif k == "hair":
            d = nz2.ridged(P * v3((f, f, f * 0.25)), 2) - 0.5
        elif k in ("metal", "rubber"):
            d = nz.fbm(P * f * 0.35, 2) + 0.25 * nz2(P * f * 2.0)
        elif k == "leather":
            d = 0.7 * (nz2.ridged(P * f, 2) - 0.6) + 0.3 * nz(P * f * 2)
        elif k in ("concrete", "bone"):
            d = nz.fbm(P * f, 4)
        else:
            d = nz.fbm(P * f, 2)
        off[sel] += d * m.disp * S
    return V + N * off[:, None]


def colorize(cr, part, V, N, mids, cf=None):
    """Returns rgb (linear), rough, metal, glow per vertex."""
    S = cr.S
    n = len(V)
    col = np.zeros((n, 3))
    rough = np.zeros(n)
    metal = np.zeros(n)
    glow = np.zeros(n)
    nz = Noise(cr.seed * 11 + 1)
    nz2 = Noise(cr.seed * 11 + 2)
    nz3 = Noise(cr.seed * 11 + 5)
    P = V / S
    big = nz.fbm(P * 2.2, 3)
    mid = nz2.fbm(P * 7.0, 3)
    fine = nz3(P * 38.0)
    for i, name in enumerate(cr.mat_names):
        m = cr.palette[name]
        sel = mids == i
        if not sel.any():
            continue
        b, m2, f2 = big[sel], mid[sel], fine[sel]
        Q = P[sel]
        base = np.repeat(m.color[None, :], sel.sum(), 0)
        k = m.kind
        if k == "skin":
            c = _mix(base, m.color2, smoothstep(-0.25, 0.45, b) * 0.85)
            c = c * (1.0 + m.var * m2 + 0.05 * f2)[:, None]
            vein = m.extra.get("vein")
            if vein is not None:
                vr = nz3.ridged(Q * v3((5.0, 5.0, 2.2)), 3)
                c = _mix(c, srgb(vein), smoothstep(0.86, 0.97, vr) * m.extra.get("vein_amt", 0.55))
            spot = m.extra.get("spot")
            if spot is not None:
                c = _mix(c, srgb(spot), smoothstep(0.35, 0.6, nz.fbm(Q * 4.5 + 7.0, 3)) * 0.6)
            r = m.rough + 0.08 * m2
        elif k in ("cloth", "canvas"):
            c = _mix(base, m.color2, smoothstep(-0.2, 0.6, b) * 0.7)
            c = c * (1.0 + m.var * m2 + 0.07 * f2)[:, None]
            r = m.rough + 0.05 * m2
        elif k == "plaid":
            bands = [srgb(x) for x in m.extra["bands"]]
            per = m.extra.get("period", 0.34) * S
            if m.extra.get("box"):
                Ns = N[sel]
                side = np.abs(Ns[:, 0]) > np.abs(Ns[:, 1])
                topf = np.abs(Ns[:, 2]) > 0.75
                u = np.where(side, V[sel, 1], V[sel, 0]) / per
                w = np.where(topf, V[sel, 1], V[sel, 2]) / per
            else:
                # vertical lines from the angle round the body axis, horizontal from height
                ang = np.arctan2(V[sel, 1] - m.extra.get("cy", 0.0), V[sel, 0])
                u = ang * m.extra.get("radius", 0.55) * S / per
                w = V[sel, 2] / per
            def band(x, width):
                fx = np.abs((x % 1.0) - 0.5) * 2.0
                return smoothstep(1.0 - width, 1.0 - width + 0.06, fx)
            c = base.copy()
            c = _mix(c, bands[0], np.maximum(band(u, 0.28), band(w, 0.28)) * 0.85)
            c = _mix(c, bands[1], band(u + 0.5, 0.1) * 0.9)
            c = _mix(c, bands[1], band(w + 0.5, 0.1) * 0.9)
            c = _mix(c, m.color2, smoothstep(0.0, 0.8, b) * 0.45)
            c = c * (1.0 + m.var * m2 + 0.08 * f2)[:, None]
            r = m.rough + 0.05 * m2
        elif k == "denim":
            tw = nz3(Q * v3((90.0, 90.0, 90.0)) + Q[:, [2, 0, 1]] * 60.0)
            c = base * (1.0 + 0.08 * tw)[:, None]
            c = _mix(c, m.color2, smoothstep(0.1, 0.7, b + 0.4 * m2) * 0.65)
            c = c * (1.0 + m.var * m2)[:, None]
            r = m.rough + 0.05 * m2
        elif k == "stripes":
            c = _mix(base, m.color2, smoothstep(0.0, 0.7, b) * 0.5)
            c = c * (1.0 + m.var * m2 + 0.06 * f2)[:, None]
            r = m.rough + 0.05 * m2
        elif k == "leather":
            cr_ = nz3.ridged(Q * 14.0, 2)
            c = _mix(base, m.color2, smoothstep(0.2, 0.75, b) * 0.6)
            c = c * (1.0 - 0.25 * smoothstep(0.82, 0.95, cr_))[:, None]
            c = c * (1.0 + m.var * m2)[:, None]
            r = m.rough - 0.1 * smoothstep(0.0, 0.6, m2)
        elif k == "metal":
            rust = smoothstep(m.extra.get("rust_lo", -0.1), 0.45, b + 0.5 * m2)
            c = _mix(base, m.color2, rust)
            scr = nz3.ridged(Q * v3((60.0, 8.0, 60.0)), 1)
            c = c * (1.0 + 0.25 * smoothstep(0.93, 0.99, scr) * (1 - rust))[:, None]
            c = c * (1.0 + m.var * f2)[:, None]
            r = m.rough + 0.45 * rust
            metal[sel] = m.metal * (1.0 - rust)
        elif k == "hair":
            st = nz3(Q * v3((55.0, 55.0, 6.0)))
            c = base * (1.0 + 0.35 * st)[:, None]
            c = _mix(c, m.color2, smoothstep(0.0, 0.7, b) * 0.5)
            r = m.rough + 0.1 * st
        elif k == "eye":
            c = base * (1.0 + 0.1 * f2)[:, None]
            r = np.full(sel.sum(), m.rough)
        elif k == "sac":
            core = smoothstep(-0.3, 0.5, m2 + 0.3 * f2)
            c = _mix(m.color2, base, core)
            r = np.full(sel.sum(), m.rough)
        elif k in ("concrete", "bone"):
            sp = smoothstep(0.5, 0.9, nz3(Q * 30.0))
            c = _mix(base, m.color2, smoothstep(-0.2, 0.6, b) * 0.7)
            c = c * (1.0 - 0.3 * sp + m.var * m2)[:, None]
            r = m.rough + 0.05 * m2
        else:  # plain, dark, nail, rubber, mouth
            c = _mix(base, m.color2, smoothstep(-0.1, 0.7, b) * 0.5)
            c = c * (1.0 + m.var * m2)[:, None]
            r = m.rough + 0.04 * m2
        g = np.full(sel.sum(), m.glow)
        if cf is not None and m.extra.get("crack"):
            mk, pid, rim, cfine = cf["mask"][sel], cf["id"][sel], cf["rim"][sel], cf["fine"][sel]
            c = c * (0.92 + 0.16 * pid)[:, None] * (1.0 + 0.08 * rim)[:, None]
            seam = srgb(cr.crack.get("seam", (22, 30, 14)))
            c = _mix(c, seam, np.maximum(mk, cfine * 0.6) * 0.88)
            r = r - cr.crack.get("wet", 0.3) * mk  # ichor in the cracks catches the light
            gl = cr.crack.get("glow", 0.0)
            if gl > 0:
                g = np.maximum(g, mk * gl)
        col[sel] = c
        rough[sel] = r
        glow[sel] = g
    # dirt and grime: heavier toward the ground, never on eyes or glowing bits
    soil = np.array([cr.palette[nm].glow < 0.5 and cr.palette[nm].kind not in ("metal", "eye")
                     for nm in cr.mat_names])[mids] & (glow < 0.5)
    zg = V[:, 2] - cr.ground
    dirt = smoothstep(1.3 * S, 0.0, zg) * 0.55 + smoothstep(0.35, 0.8, nz.fbm(P * 1.3 + 11.0, 3)) * 0.25
    dirt = dirt * soil
    col = _mix(col, DIRT * (0.8 + 0.4 * mid[:, None]), dirt * 0.7)
    rough = rough + dirt * 0.1
    # green ichor round wounds (owner rule: mob blood is green, never red)
    for (c0, rad) in cr.wounds:
        d = np.linalg.norm(V - v3(c0), axis=1) + nz2(P * 9.0) * rad * 0.35
        st = smoothstep(rad, rad * 0.25, d) * soil
        drip = smoothstep(rad * 0.45, 0.0, np.linalg.norm((V - v3(c0))[:, :2], axis=1) + nz3(P * 14.0) * rad * 0.2)
        drip *= smoothstep(-rad * 3.0, -rad * 0.5, V[:, 2] - c0[2]) * (V[:, 2] < c0[2]) * soil
        a = np.maximum(st, drip * 0.8)
        col = _mix(col, _mix(ICHOR, ICHOR_WET, smoothstep(0.4, 1.0, st)), a * 0.9)
        rough = rough * (1.0 - 0.45 * a)
    for fx in cr.color_fx:
        col, rough, metal, glow = fx(cr, part, V, N, mids, col, rough, metal, glow)
    return np.clip(col, 0.0, 1.0), np.clip(rough, 0.05, 1.0), np.clip(metal, 0.0, 1.0), np.clip(glow, 0.0, 1.0)
