"""Signed distance shapes, noise and a surface-nets mesher in plain numpy.

Everything is in studs (1 Blender unit = 1 stud). Negative distance = inside.
Only numpy is used, so this runs inside Blender's own Python.
"""
import numpy as np

BIG = 1.0e3
CULL = 0.02


def v3(x):
    return np.asarray(x, dtype=np.float64)


def norm(x):
    x = v3(x)
    return x / np.linalg.norm(x)


def _len(a):
    return np.sqrt(np.einsum("ij,ij->i", a, a))


def smin(a, b, k):
    if k <= 0.0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def euler(rx=0.0, ry=0.0, rz=0.0):
    """Rotation matrix (degrees), applied X then Y then Z (world axes)."""
    a, b, c = np.radians([rx, ry, rz])
    Rx = np.array([[1, 0, 0], [0, np.cos(a), -np.sin(a)], [0, np.sin(a), np.cos(a)]])
    Ry = np.array([[np.cos(b), 0, np.sin(b)], [0, 1, 0], [-np.sin(b), 0, np.cos(b)]])
    Rz = np.array([[np.cos(c), -np.sin(c), 0], [np.sin(c), np.cos(c), 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


# --------------------------------------------------------------------------- nodes
class Node:
    lo = None
    hi = None

    def far(self, blo, bhi, gap):
        if self.lo is None:
            return False
        d = np.maximum(0.0, np.maximum(self.lo - bhi, blo - self.hi))
        return float((d * d).sum()) > gap * gap

    def eval(self, P, blo=None, bhi=None):
        raise NotImplementedError

    def __call__(self, P):
        return self.eval(P)


class Sphere(Node):
    def __init__(s, c, r):
        s.c, s.r = v3(c), float(r)
        s.lo, s.hi = s.c - s.r, s.c + s.r

    def eval(s, P, blo=None, bhi=None):
        return _len(P - s.c) - s.r


class Ellipsoid(Node):
    def __init__(s, c, r, R=None):
        s.c, s.r = v3(c), v3(r)
        s.R = np.eye(3) if R is None else np.asarray(R, dtype=np.float64)
        ext = np.sqrt(((s.R * s.r[None, :]) ** 2).sum(1))
        s.lo, s.hi = s.c - ext, s.c + ext

    def eval(s, P, blo=None, bhi=None):
        q = (P - s.c) @ s.R
        k0 = _len(q / s.r)
        k1 = _len(q / (s.r * s.r))
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


class RoundCone(Node):
    """Capsule between a and b whose radius goes from ra to rb (iq's sdRoundCone)."""

    def __init__(s, a, b, ra, rb=None):
        rb = ra if rb is None else rb
        s.a, s.b, s.ra, s.rb = v3(a), v3(b), float(ra), float(rb)
        ba = s.b - s.a
        s.ba = ba
        s.l2 = max(float(ba @ ba), 1e-9)
        s.rr = s.ra - s.rb
        s.a2 = s.l2 - s.rr * s.rr
        if s.a2 <= 1e-9:  # one end swallows the other: shrink the difference
            s.rr = np.sign(s.rr) * np.sqrt(s.l2) * 0.95
            s.rb = s.ra - s.rr
            s.a2 = s.l2 - s.rr * s.rr
        s.il2 = 1.0 / s.l2
        r = max(s.ra, s.rb)
        s.lo, s.hi = np.minimum(s.a, s.b) - r, np.maximum(s.a, s.b) + r

    def eval(s, P, blo=None, bhi=None):
        pa = P - s.a
        y = pa @ s.ba
        z = y - s.l2
        xv = pa * s.l2 - np.outer(y, s.ba)
        x2 = np.einsum("ij,ij->i", xv, xv)
        y2 = y * y * s.l2
        z2 = z * z * s.l2
        k = np.sign(s.rr) * s.rr * s.rr * x2
        d1 = np.sqrt(x2 + z2) * s.il2 - s.rb
        d2 = np.sqrt(x2 + y2) * s.il2 - s.ra
        d3 = (np.sqrt(np.maximum(x2 * s.a2 * s.il2, 0.0)) + y * s.rr) * s.il2 - s.ra
        return np.where(np.sign(z) * s.a2 * z2 > k, d1, np.where(np.sign(y) * s.a2 * y2 < k, d2, d3))


def Capsule(a, b, r):
    return RoundCone(a, b, r, r)


class Box(Node):
    def __init__(s, c, half, R=None, rad=0.0):
        s.c, s.h = v3(c), v3(half)
        s.R = np.eye(3) if R is None else np.asarray(R, dtype=np.float64)
        s.rad = float(min(rad, s.h.min() * 0.999))
        ext = np.abs(s.R) @ s.h
        s.lo, s.hi = s.c - ext, s.c + ext

    def eval(s, P, blo=None, bhi=None):
        q = np.abs((P - s.c) @ s.R) - (s.h - s.rad)
        return _len(np.maximum(q, 0.0)) + np.minimum(q.max(1), 0.0) - s.rad


class Ring(Node):
    """Elliptic torus: ring with semi-axes a (local x) and b (local y), tube radius r (local frame R)."""

    def __init__(s, c, a, b, r, R=None, rz=None):
        s.c, s.a, s.b, s.r = v3(c), float(a), float(b), float(r)
        s.rz = s.r if rz is None else float(rz)  # tube half-height (flattened bands)
        s.R = np.eye(3) if R is None else np.asarray(R, dtype=np.float64)
        e = v3((s.a + s.r, s.b + s.r, max(s.r, s.rz)))
        ext = np.abs(s.R) @ e
        s.lo, s.hi = s.c - ext, s.c + ext

    def eval(s, P, blo=None, bhi=None):
        q = (P - s.c) @ s.R
        k = np.sqrt((q[:, 0] / s.a) ** 2 + (q[:, 1] / s.b) ** 2)
        g = np.sqrt((q[:, 0] / (s.a * s.a)) ** 2 + (q[:, 1] / (s.b * s.b)) ** 2) / np.maximum(k, 1e-9)
        de = (k - 1.0) / np.maximum(g, 1e-9)
        dz = q[:, 2] * (s.r / s.rz)
        return np.sqrt(de * de + dz * dz) - s.r


class Cylinder(Node):
    """Capped cylinder from a to b, radius r, edges rounded by rad."""

    def __init__(s, a, b, r, rad=0.0):
        s.a0, s.b0 = v3(a), v3(b)
        axis = norm(s.b0 - s.a0)
        s.rad = float(rad)
        s.a, s.b = s.a0 + axis * s.rad, s.b0 - axis * s.rad
        s.r = float(r) - s.rad
        R = float(r)
        s.lo, s.hi = np.minimum(s.a0, s.b0) - R, np.maximum(s.a0, s.b0) + R

    def eval(s, P, blo=None, bhi=None):
        ba = s.b - s.a
        pa = P - s.a
        baba = float(ba @ ba)
        paba = pa @ ba
        x = _len(pa * baba - np.outer(paba, ba)) - s.r * baba
        y = np.abs(paba - baba * 0.5) - baba * 0.5
        x2 = x * x
        y2 = y * y * baba
        inside = np.maximum(x, y) < 0.0
        d = np.where(inside, -np.minimum(x2, y2), np.where(x > 0, x2, 0.0) + np.where(y > 0, y2, 0.0))
        return np.sign(d) * np.sqrt(np.abs(d)) / baba - s.rad


class Plane(Node):
    """Half space: inside where (p - p0) . n < 0. Unbounded (never culled)."""

    def __init__(s, p0, n):
        s.p0, s.n = v3(p0), norm(n)

    def far(self, blo, bhi, gap):
        return False

    def eval(s, P, blo=None, bhi=None):
        return (P - s.p0) @ s.n


class Fn(Node):
    """Wrap a python function f(P)->d with a given bounding box (lo, hi) or None (unbounded)."""

    def __init__(s, f, lo=None, hi=None):
        s.f = f
        s.lo = None if lo is None else v3(lo)
        s.hi = None if hi is None else v3(hi)

    def eval(s, P, blo=None, bhi=None):
        return s.f(P)


class Union(Node):
    def __init__(s, kids, k=0.0):
        s.kids = [c for c in kids if c is not None]
        s.k = float(k)
        bounded = [c for c in s.kids if c.lo is not None]
        if len(bounded) == len(s.kids) and bounded:
            s.lo = np.min([c.lo for c in bounded], 0) - s.k
            s.hi = np.max([c.hi for c in bounded], 0) + s.k
        else:
            s.lo = s.hi = None

    def eval(s, P, blo=None, bhi=None):
        d = None
        for c in s.kids:
            if blo is not None and c.far(blo, bhi, s.k + CULL):
                continue
            dc = c.eval(P, blo, bhi)
            d = dc if d is None else smin(d, dc, s.k)
        if d is None:
            return np.full(len(P), BIG)
        return d


class Subtract(Node):
    def __init__(s, a, b, k=0.0):
        s.a, s.b, s.k = a, b, float(k)
        s.lo, s.hi = a.lo, a.hi

    def eval(s, P, blo=None, bhi=None):
        if blo is not None and s.a.far(blo, bhi, CULL):
            return np.full(len(P), BIG)
        da = s.a.eval(P, blo, bhi)
        if blo is not None and s.b.far(blo, bhi, s.k + CULL):
            return da
        return smax(da, -s.b.eval(P, blo, bhi), s.k)


class Intersect(Node):
    def __init__(s, a, b, k=0.0):
        s.a, s.b, s.k = a, b, float(k)
        boxes = [c for c in (a, b) if c.lo is not None]
        if boxes:
            s.lo = np.max([c.lo for c in boxes], 0)
            s.hi = np.min([c.hi for c in boxes], 0)
        else:
            s.lo = s.hi = None

    def eval(s, P, blo=None, bhi=None):
        if blo is not None and (s.a.far(blo, bhi, CULL) or s.b.far(blo, bhi, CULL)):
            return np.full(len(P), BIG)
        return smax(s.a.eval(P, blo, bhi), s.b.eval(P, blo, bhi), s.k)


class Offset(Node):
    def __init__(s, a, t):
        s.a, s.t = a, float(t)
        if a.lo is not None:
            s.lo, s.hi = a.lo - max(s.t, 0.0), a.hi + max(s.t, 0.0)

    def eval(s, P, blo=None, bhi=None):
        if blo is not None and s.far(blo, bhi, CULL):
            return np.full(len(P), BIG)
        return s.a.eval(P, blo, bhi) - s.t


class Displace(Node):
    """d - amp * f(P) with |f| <= 1."""

    def __init__(s, a, f, amp):
        s.a, s.f, s.amp = a, f, float(amp)
        if a.lo is not None:
            s.lo, s.hi = a.lo - abs(s.amp), a.hi + abs(s.amp)

    def eval(s, P, blo=None, bhi=None):
        if blo is not None and s.far(blo, bhi, CULL):
            return np.full(len(P), BIG)
        return s.a.eval(P, blo, bhi) - s.amp * s.f(P)


def chain(points, radii, k=0.0):
    """Tube through points with per-point radii (union of round cones)."""
    pts = [v3(p) for p in points]
    segs = [RoundCone(pts[i], pts[i + 1], radii[i], radii[i + 1]) for i in range(len(pts) - 1)]
    return segs[0] if len(segs) == 1 else Union(segs, k)


# --------------------------------------------------------------------------- noise
class Noise:
    """3D gradient (Perlin) noise, roughly in [-1, 1]."""

    G = np.array(
        [[1, 1, 0], [-1, 1, 0], [1, -1, 0], [-1, -1, 0], [1, 0, 1], [-1, 0, 1], [1, 0, -1], [-1, 0, -1],
         [0, 1, 1], [0, -1, 1], [0, 1, -1], [0, -1, -1]], dtype=np.float64)

    def __init__(self, seed=0):
        p = np.random.default_rng(seed).permutation(256)
        self.perm = np.concatenate([p, p, p]).astype(np.int64)
        self.offset = np.random.default_rng(seed + 1).uniform(0, 100, 3)

    def __call__(self, P):
        P = P + self.offset
        Pi = np.floor(P)
        f = P - Pi
        i = Pi.astype(np.int64) & 255
        u = f * f * f * (f * (f * 6 - 15) + 10)
        perm = self.perm
        out = 0.0
        res = []
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    h = perm[perm[perm[i[:, 0] + dx] + i[:, 1] + dy] + i[:, 2] + dz] % 12
                    g = self.G[h]
                    res.append(((f[:, 0] - dx) * g[:, 0] + (f[:, 1] - dy) * g[:, 1] + (f[:, 2] - dz) * g[:, 2]))
        n000, n001, n010, n011, n100, n101, n110, n111 = res
        x00 = n000 + u[:, 0] * (n100 - n000)
        x01 = n001 + u[:, 0] * (n101 - n001)
        x10 = n010 + u[:, 0] * (n110 - n010)
        x11 = n011 + u[:, 0] * (n111 - n011)
        y0 = x00 + u[:, 1] * (x10 - x00)
        y1 = x01 + u[:, 1] * (x11 - x01)
        return (y0 + u[:, 2] * (y1 - y0)) * 1.1

    def fbm(self, P, octaves=4, lac=2.0, gain=0.5):
        a, f, s, n = 1.0, 1.0, 0.0, 0.0
        for _ in range(octaves):
            s = s + a * self(P * f)
            n += a
            a *= gain
            f *= lac
        return s / n

    def ridged(self, P, octaves=3):
        a, f, s, n = 1.0, 1.0, 0.0, 0.0
        for _ in range(octaves):
            s = s + a * (1.0 - np.abs(self(P * f)))
            n += a
            a *= 0.5
            f *= 2.0
        return s / n


def _hash3(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 1274126177 + seed * 144665 + 1013904223) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = (h ^ (h >> 16)) & 0xFFFFFFFF
    return h


def worley(P, seed=0):
    """Cellular noise on a unit jittered grid: (F1, F2, cell id 0..1). Cracks live where F2-F1 is small."""
    Pi = np.floor(P).astype(np.int64)
    Pf = P - Pi
    n = len(P)
    f1 = np.full(n, 9.0)
    f2 = np.full(n, 9.0)
    idv = np.zeros(n)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                cx, cy, cz = Pi[:, 0] + dx, Pi[:, 1] + dy, Pi[:, 2] + dz
                h = _hash3(cx, cy, cz, seed)
                jx = (h & 1023) / 1023.0
                jy = ((h >> 10) & 1023) / 1023.0
                jz = ((h >> 20) & 1023) / 1023.0
                fx = dx + 0.1 + 0.8 * jx - Pf[:, 0]
                fy = dy + 0.1 + 0.8 * jy - Pf[:, 1]
                fz = dz + 0.1 + 0.8 * jz - Pf[:, 2]
                d = np.sqrt(fx * fx + fy * fy + fz * fz)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                idv = np.where(closer, ((h >> 7) & 4095) / 4095.0, idv)
                f1 = np.where(closer, d, f1)
    return f1, f2, idv


# --------------------------------------------------------------------------- meshing
_CORNERS = [(i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
_EDGES = [(a, b) for a in range(8) for b in range(a + 1, 8)
          if sum(abs(_CORNERS[a][t] - _CORNERS[b][t]) for t in range(3)) == 1]


def sample_grid(fn, lo, hi, h, block=40):
    """Evaluate fn(P, blo, bhi) on a grid; blocks far from the surface are filled without evaluating."""
    lo = v3(lo)
    n = np.maximum(np.ceil((v3(hi) - lo) / h).astype(int) + 1, 2)
    F = np.empty(tuple(n), dtype=np.float32)
    xs = [lo[a] + h * np.arange(n[a]) for a in range(3)]
    for i0 in range(0, n[0], block):
        for j0 in range(0, n[1], block):
            for k0 in range(0, n[2], block):
                i1, j1, k1 = min(i0 + block, n[0]), min(j0 + block, n[1]), min(k0 + block, n[2])
                blo = v3((xs[0][i0], xs[1][j0], xs[2][k0]))
                bhi = v3((xs[0][i1 - 1], xs[1][j1 - 1], xs[2][k1 - 1]))
                c = (blo + bhi) * 0.5
                half = float(np.linalg.norm(bhi - blo)) * 0.5
                dc = float(fn(c[None, :], blo, bhi)[0])
                if abs(dc) > 2.0 * half + 4 * h:
                    F[i0:i1, j0:j1, k0:k1] = dc
                    continue
                gx, gy, gz = np.meshgrid(xs[0][i0:i1], xs[1][j0:j1], xs[2][k0:k1], indexing="ij")
                P = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], 1)
                F[i0:i1, j0:j1, k0:k1] = fn(P, blo, bhi).reshape(gx.shape)
    return F, lo


def surface_nets(F, origin, h):
    """Naive surface nets. Returns (verts (N,3), quads (M,4)) with outward winding."""
    F = F.copy()
    F[0, :, :] = F[-1, :, :] = F[:, 0, :] = F[:, -1, :] = F[:, :, 0] = F[:, :, -1] = BIG
    s = F < 0
    nx, ny, nz = F.shape
    cnt = np.zeros((nx - 1, ny - 1, nz - 1), dtype=np.uint8)
    for (i, j, k) in _CORNERS:
        cnt += s[i:nx - 1 + i, j:ny - 1 + j, k:nz - 1 + k]
    active = (cnt > 0) & (cnt < 8)
    ai, aj, ak = np.nonzero(active)
    nv = len(ai)
    vidx = np.full((nx - 1, ny - 1, nz - 1), -1, dtype=np.int64)
    vidx[ai, aj, ak] = np.arange(nv)
    acc = np.zeros((nv, 3))
    num = np.zeros(nv)
    for (ca, cb) in _EDGES:
        oa, ob = np.array(_CORNERS[ca]), np.array(_CORNERS[cb])
        fa = F[ai + oa[0], aj + oa[1], ak + oa[2]].astype(np.float64)
        fb = F[ai + ob[0], aj + ob[1], ak + ob[2]].astype(np.float64)
        m = (fa < 0) != (fb < 0)
        t = fa[m] / (fa[m] - fb[m])
        acc[m] += oa[None, :] + t[:, None] * (ob - oa)[None, :]
        num[m] += 1
    V = (np.stack([ai, aj, ak], 1) + acc / np.maximum(num, 1)[:, None]) * h + origin

    quads = []
    # x edges
    e = s[:-1, 1:-1, 1:-1] != s[1:, 1:-1, 1:-1]
    i, j, k = np.nonzero(e)
    j, k = j + 1, k + 1
    q = np.stack([vidx[i, j - 1, k - 1], vidx[i, j, k - 1], vidx[i, j, k], vidx[i, j - 1, k]], 1)
    flip = ~s[i, j, k]
    q[flip] = q[flip][:, ::-1]
    quads.append(q)
    # y edges
    e = s[1:-1, :-1, 1:-1] != s[1:-1, 1:, 1:-1]
    i, j, k = np.nonzero(e)
    i, k = i + 1, k + 1
    q = np.stack([vidx[i - 1, j, k - 1], vidx[i - 1, j, k], vidx[i, j, k], vidx[i, j, k - 1]], 1)
    flip = ~s[i, j, k]
    q[flip] = q[flip][:, ::-1]
    quads.append(q)
    # z edges
    e = s[1:-1, 1:-1, :-1] != s[1:-1, 1:-1, 1:]
    i, j, k = np.nonzero(e)
    i, j = i + 1, j + 1
    q = np.stack([vidx[i - 1, j - 1, k], vidx[i, j - 1, k], vidx[i, j, k], vidx[i - 1, j, k]], 1)
    flip = ~s[i, j, k]
    q[flip] = q[flip][:, ::-1]
    quads.append(q)
    Q = np.concatenate(quads, 0)
    return V, Q


def vertex_normals(V, Q):
    """Area weighted vertex normals for a quad (or tri) mesh."""
    if Q.shape[1] == 4:
        n = np.cross(V[Q[:, 2]] - V[Q[:, 0]], V[Q[:, 3]] - V[Q[:, 1]])
    else:
        n = np.cross(V[Q[:, 1]] - V[Q[:, 0]], V[Q[:, 2]] - V[Q[:, 0]])
    N = np.zeros_like(V)
    for c in range(Q.shape[1]):
        np.add.at(N, Q[:, c], n)
    return N / np.maximum(np.linalg.norm(N, axis=1), 1e-12)[:, None]


def laplacian(V, Q, iters=1, lam=0.5):
    """Umbrella smoothing over the quad edges."""
    E = np.concatenate([Q[:, [0, 1]], Q[:, [1, 2]], Q[:, [2, 3]], Q[:, [3, 0]]], 0)
    for _ in range(iters):
        S = np.zeros_like(V)
        c = np.zeros(len(V))
        np.add.at(S, E[:, 0], V[E[:, 1]])
        np.add.at(S, E[:, 1], V[E[:, 0]])
        np.add.at(c, E[:, 0], 1)
        np.add.at(c, E[:, 1], 1)
        avg = S / np.maximum(c, 1)[:, None]
        V = V + lam * (avg - V)
    return V


def project(V, fn, h, steps=2):
    """Move vertices onto fn's zero set with Newton steps (finite-difference gradient)."""
    e = h * 0.5
    for _ in range(steps):
        d = fn(V)
        g = np.stack([(fn(V + v3(o) * e) - fn(V - v3(o) * e)) / (2 * e)
                      for o in ((1, 0, 0), (0, 1, 0), (0, 0, 1))], 1)
        gl2 = np.maximum((g * g).sum(1), 1e-6)
        step = (d / gl2)[:, None] * g
        # never move more than a voxel (keeps sharp creases from collapsing)
        sl = np.linalg.norm(step, axis=1)
        step *= np.minimum(1.0, h / np.maximum(sl, 1e-12))[:, None]
        V = V - step
    return V
