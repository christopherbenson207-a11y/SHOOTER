"""Gyro aim simulation (run: python tools/gyro_sim.py).

Checks Shared.GyroAim's maths without a phone. A simulated player holds a phone in landscape and
turns, tilts and twists it with hand tremor. The phone reports its rotation CFrame in one of the 48
ways a device might (the 24 ways its axes can sit against the gravity sensor's, times device-to-world
or world-to-device), against an arbitrary reference frame, with readings out of step with frames.
Each algorithm turns the readings into camera yaw and pitch, and the result is compared with what
the player meant. "old" is the 3 Nov code (HEAD before the GyroAim module), "new" is GyroAim.luau
ported line for line. Keep the two in step: a change to GyroAim.luau's constants or logic goes here
too.
"""

from __future__ import annotations

import itertools
import math
import sys

import numpy as np

RNG = np.random.default_rng(7)


# ---- rotation helpers (CFrame rotation = 3x3 matrix, columns are the X/Y/Z vectors) ----------

def rot(axis, angle):
    axis = np.asarray(axis, float)
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s = math.cos(angle), math.sin(angle)
    C = 1 - c
    return np.array([
        [c + x * x * C, x * y * C - z * s, x * z * C + y * s],
        [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
        [z * x * C - y * s, z * y * C + x * s, c + z * z * C],
    ])


def to_axis_angle(R):
    cos = max(-1.0, min(1.0, (np.trace(R) - 1) / 2))
    angle = math.acos(cos)
    v = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]])
    n = np.linalg.norm(v)
    if n < 1e-12:
        return np.array([0.0, 1.0, 0.0]), 0.0
    return v / n, angle


def unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 0 else v


X, Y, Z = np.eye(3)


def proper_axis_maps():
    """The 24 rotations that map axes onto axes (signed permutations with determinant +1)."""
    out = []
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((1, -1), repeat=3):
            M = np.zeros((3, 3))
            for col, (row, sign) in enumerate(zip(perm, signs)):
                M[row, col] = sign
            if abs(np.linalg.det(M) - 1) < 1e-9:
                out.append(M)
    return out


MAPS = proper_axis_maps()
assert len(MAPS) == 24
MAPS_STACK = np.stack(MAPS)
IDENTITY_INDEX = next(i for i, M in enumerate(MAPS) if np.allclose(M, np.eye(3)))

# ---- the new algorithm (mirror of Shared.GyroAim) ---------------------------------------------

SCREEN_OUT = Y
MAX_STEP = math.radians(45)
STALE = 0.25
RELAX = 1.41

CHECK_RATE = 0.03
CHECK_WARMUP = 30
CHECK_RATIO = 3
CHECK_FLOOR = 0.0003
CHECK_HOLD = 15
UP_STEADY = 0.01

EDGE_RATE = 0.05
EDGE_MIN = 0.1
EDGE_ANY = 0.02

WINDOW = 1 / 30
HISTORY = 8
TIGHTEN = math.radians(3)
SMOOTH_HIGH = math.radians(8)
SMOOTH_LOW = SMOOTH_HIGH / 2
SMOOTH_TIME = 0.125

# Candidate k: map index k // 2, inverse if k is odd. Candidate 0 (identity, forward) is the
# documented guess and the default.
CANDIDATES = [(m, inv) for m in range(24) for inv in (False, True)]
DEFAULT = CANDIDATES.index((IDENTITY_INDEX, False))

# A phone held in landscape keeps its long edge (Z) level, and then a convention and the same one
# turned half round that edge look exactly as steady against gravity: its "twin". Twins agree on
# pitch and disagree on the sign of yaw. Only twisting the phone tells them apart.
FLIP_LONG_EDGE = np.diag([-1.0, -1.0, 1.0])
TWIN = []
for m, inv in CANDIDATES:
    target = MAPS[m] @ FLIP_LONG_EDGE
    tm = next(i for i, M in enumerate(MAPS) if np.allclose(M, target))
    TWIN.append(CANDIDATES.index((tm, inv)))


def to_world(cf, k):
    m, inv = CANDIDATES[k]
    base = cf.T if inv else cf
    return base @ MAPS[m]


class NewGyro:
    def __init__(self):
        self.last = None
        self.last_time = 0.0
        self.pending = np.zeros(2)
        self.choice = DEFAULT
        self.verdict = DEFAULT
        self.votes = 0
        self.samples = 0
        self.means = np.zeros((len(CANDIDATES), 3))
        self.up = None  # world up in the chosen candidate's reference frame
        self.edge = np.zeros(3)
        self.angles = []
        self.steps = []
        self.smoothed = np.zeros(2)

    def check(self, cf, up_in_phone):
        rate = 1.0 if self.samples == 0 else CHECK_RATE
        # Same as to_world(cf, k) @ up_in_phone for every k, done all at once for speed.
        mapped = MAPS_STACK @ up_in_phone  # (24, 3)
        w = np.empty((len(CANDIDATES), 3))
        w[0::2] = mapped @ cf.T
        w[1::2] = mapped @ cf
        self.means = self.means + (w - self.means) * rate
        self.samples += 1
        if self.samples < CHECK_WARMUP:
            return
        misses = 1 - np.linalg.norm(self.means, axis=1)
        best = int(np.argmin(misses))
        twin = TWIN[best]
        rival = min((k for k in range(len(CANDIDATES)) if k != best and k != twin), key=lambda k: misses[k])
        verdict = self.choice
        if misses[best] * CHECK_RATIO + CHECK_FLOOR < misses[rival]:
            verdict = best
            if not (misses[best] * CHECK_RATIO + CHECK_FLOOR < misses[twin]):
                # No twist yet to tell the twins apart: take the one whose world up lies along +Y
                # or +Z of the sensor's frame (Roblox's own and the phones' sensor frames are
                # gravity-aligned with up positive).
                def score(k):
                    mean = self.means[k]
                    return max(mean[1], mean[2])
                verdict = best if score(best) >= score(twin) else twin
        if verdict == self.choice:
            self.votes = 0
        elif verdict == self.verdict:
            self.votes += 1
        else:
            self.verdict = verdict
            self.votes = 1
        if verdict != self.choice and self.votes >= CHECK_HOLD:
            self.choice = verdict
            self.votes = 0
            self.edge = np.zeros(3)
            self.up = None
        if misses[self.choice] < UP_STEADY:
            self.up = unit(self.means[self.choice])

    def reset(self):
        self.last = None
        self.pending = np.zeros(2)
        self.angles.clear()
        self.steps.clear()
        self.smoothed = np.zeros(2)

    def reading(self, cf, gravity, active, now):
        if gravity is not None and np.linalg.norm(gravity) > 1e-3:
            self.check(cf, -unit(gravity))
        if not active:
            if self.last is not None:
                self.reset()
            return
        last, last_time = self.last, self.last_time
        self.last, self.last_time = cf, now
        if last is None or now - last_time > STALE:
            return
        world = to_world(cf, self.choice)
        delta = to_world(last, self.choice).T @ world
        axis, angle = to_axis_angle(delta)
        if angle != angle or angle < 1e-7 or angle > MAX_STEP:
            return
        turn = axis * angle
        if self.up is not None:
            up = world.T @ self.up
        elif gravity is not None and np.linalg.norm(gravity) > 1e-3:
            up = -unit(gravity)
        else:
            up = world.T @ Y

        side = np.cross(up, SCREEN_OUT)
        level = np.linalg.norm(side)
        learned = np.linalg.norm(self.edge) > 0.5
        if level > EDGE_MIN or (not learned and level > EDGE_ANY):
            u = side / level
            if not learned or u @ self.edge < -0.5:
                self.edge = u
            else:
                self.edge = unit(self.edge + (u - self.edge) * EDGE_RATE)
        edge = self.edge
        if np.linalg.norm(edge) < 0.5:
            return

        pitch = turn @ edge
        rest = turn - edge * pitch
        up_rest = up - edge * (up @ edge)
        world_yaw = rest @ up_rest
        yaw = math.copysign(min(abs(world_yaw) * RELAX, np.linalg.norm(rest)), world_yaw)
        self.pending = self.pending + np.array([yaw, pitch])

    def step(self, dt):
        if dt <= 0:
            return np.zeros(2)
        self.angles.append(self.pending)
        self.steps.append(dt)
        self.pending = np.zeros(2)
        if len(self.angles) > HISTORY:
            self.angles.pop(0)
            self.steps.pop(0)
        total, span = np.zeros(2), 0.0
        for a, s in zip(reversed(self.angles), reversed(self.steps)):
            total = total + a
            span += s
            if span >= WINDOW:
                break
        rate = total / span
        speed = np.linalg.norm(rate)
        if speed < TIGHTEN:
            rate = rate * (speed / TIGHTEN)
        direct = min(1.0, max(0.0, (speed - SMOOTH_LOW) / (SMOOTH_HIGH - SMOOTH_LOW)))
        self.smoothed = self.smoothed + (rate * (1 - direct) - self.smoothed) * (1 - math.exp(-dt / SMOOTH_TIME))
        turn = (rate * direct + self.smoothed) * dt
        if np.linalg.norm(turn) < 1e-8:
            return np.zeros(2)
        return turn


class OldGyro:
    """The 3 Nov code: local turn assuming device-to-world, split by raw gravity, no filtering."""

    def __init__(self):
        self.last = None
        self.delta = np.zeros(2)

    def reading(self, cf, gravity, active, now):
        if not active:
            self.last = None
            return
        if self.last is not None:
            axis, angle = to_axis_angle(self.last.T @ cf)
            if 1e-5 < angle < math.radians(30):
                turn = axis * angle
                up = -unit(gravity)
                side = np.cross(up, SCREEN_OUT)
                pitch = turn @ unit(side) if np.linalg.norm(side) > 0.15 else 0.0
                self.delta = self.delta + np.array([turn @ up, pitch])
        self.last = cf

    def step(self, dt):
        d, self.delta = self.delta, np.zeros(2)
        return d


# ---- the simulated player and phone ------------------------------------------------------------

def base_pose(landscape):
    """Device-to-world (gravity axes: X left edge, Y out of the screen, Z top edge) for a phone held
    upright in landscape in front of a player looking along -Z, screen toward them."""
    y = np.array([0.0, 0.0, 1.0])
    z = np.array([-1.0, 0.0, 0.0]) if landscape == "A" else np.array([1.0, 0.0, 0.0])
    x = np.cross(y, z)
    return np.column_stack([x, y, z])


class Phone:
    """Reports readings the way one device convention would."""

    def __init__(self, k, ref):
        self.k = k
        self.ref = ref  # the sensor's reference world, from ours
        m, inv = CANDIDATES[k]
        self.M = MAPS[m]
        self.inv = inv
        self.grav = None

    def report(self, D, dt):
        # D: device-to-world in gravity axes. Reported device axes: v_rep = M v_grav, so the
        # rotation in reported axes is ref @ D @ M^T.
        cf = self.ref @ D @ self.M.T
        if self.inv:
            cf = cf.T
        self.t = getattr(self, "t", 0.0) + dt
        t = self.t
        # Raw accelerometers also feel the hands moving the phone (about 0.3 m/s^2 here).
        hands = 0.3 * np.array([math.sin(t * 5.3), math.sin(t * 4.1 + 1), math.sin(t * 6.7 + 2)])
        g = D.T @ (np.array([0.0, -9.81, 0.0]) - hands)
        # The gravity sensor lags a little and is noisy.
        self.grav = g if self.grav is None else self.grav + (g - self.grav) * (1 - math.exp(-dt / 0.04))
        noisy = self.grav + RNG.normal(0, 0.08, 3)
        return cf, noisy


def tremor_rot(t, amp):
    a = amp * np.array([math.sin(t * 9.1) + 0.5 * math.sin(t * 23.7), math.sin(t * 11.3 + 1) + 0.5 * math.sin(t * 19.1), math.sin(t * 7.7 + 2)])
    n = np.linalg.norm(a)
    return rot(a / n, n) if n > 1e-12 else np.eye(3)


def run(algo_cls, k, ref, landscape, tilt, motion, seconds, warm, active_from=0.0, tremor=math.radians(0.15)):
    """motion(t) -> (yaw, pitch, roll) of the player's intent in radians. Returns per-frame arrays of
    (intended yaw, intended pitch, camera yaw, camera pitch)."""
    algo = algo_cls()
    phone = Phone(k, ref)
    D0 = base_pose(landscape)
    sensor_t = 0.0
    frame_t = 0.0
    cam = np.zeros(2)
    rows = []
    total = warm + seconds

    def pose(t):
        if t < warm:
            # Natural handling while the round starts: look around, tilt, small twists. It fades
            # out over the last second so the measured part starts from rest.
            f = smooth01(warm - t)
            yaw = f * (0.5 * math.sin(t * 1.3) + 0.2 * math.sin(t * 2.9))
            pitch = f * 0.25 * math.sin(t * 1.7 + 0.4)
            roll = f * 0.08 * math.sin(t * 2.3)
            extra = f * 0.1 * math.sin(t * 0.7)
        else:
            yaw, pitch, roll = motion(t - warm)
            extra = 0.0
        return yaw, pitch, roll, extra

    def device(t):
        yaw, pitch, roll, extra = pose(t)
        return rot(Y, yaw) @ rot(X, pitch - tilt + extra) @ rot(Z, roll) @ tremor_rot(t, tremor) @ D0

    start_intent = None
    start_cam = None
    while frame_t < total:
        dt = 1 / 60 * (1 + RNG.uniform(-0.25, 0.6))
        frame_t += dt
        while sensor_t + 1 / 60 <= frame_t:
            sdt = 1 / 60 * (1 + RNG.uniform(-0.3, 0.3))
            sensor_t += sdt
            D = device(sensor_t)
            cf, g = phone.report(D, sdt)
            algo.reading(cf, g, sensor_t >= active_from, sensor_t)
        turn = algo.step(dt)
        cam = cam + turn
        if frame_t >= warm:
            yaw, pitch, roll, _ = pose(frame_t)
            if start_intent is None:
                start_intent = np.array([yaw, pitch])
                start_cam = cam.copy()
            rows.append((yaw - start_intent[0], pitch - start_intent[1], cam[0] - start_cam[0], cam[1] - start_cam[1]))
    return np.array(rows)


# ---- scenarios -------------------------------------------------------------------------------

def smooth01(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def turn_body(t):  # 60 degrees left over 1 s, hold, back
    a = math.radians(60) * (smooth01(t) - smooth01(t - 1.5))
    return a, 0.0, 0.0


def tilt_up(t):  # top toward you 20 degrees and back
    a = math.radians(20) * (smooth01(t) - smooth01(t - 1.5))
    return 0.0, a, 0.0


def circles(t):  # starts from rest at the centre
    return math.radians(25) * math.sin(t * 2.2), math.radians(12) * (1 - math.cos(t * 2.2)), 0.0


def still(t):
    return 0.0, 0.0, 0.0


def slow_pan(t):  # 8 degrees per second
    return math.radians(8) * t, 0.0, 0.0


def score(rows, name):
    want_yaw, want_pitch, yaw, pitch = rows.T
    peak = max(np.max(np.abs(want_yaw)), np.max(np.abs(want_pitch)), 1e-9)
    err = np.sqrt(np.mean((yaw - want_yaw) ** 2 + (pitch - want_pitch) ** 2))
    return err / peak  # error as a share of the motion


def random_ref():
    """The sensor's reference world, from ours: gravity-aligned, up along +Y or +Z, any heading."""
    heading = rot(Y, RNG.uniform(0, 2 * math.pi))
    return (rot(X, math.pi / 2) if RNG.random() < 0.5 else np.eye(3)) @ heading


def main():
    landscapes = ("A", "B")
    tilts = (math.radians(25), math.radians(55))
    report = {"old": [], "new": []}
    worst = {"old": (0, None), "new": (0, None)}
    decided = []
    for k in range(len(CANDIDATES)):
        ref = random_ref()
        for landscape, tilt in (("A", tilts[0]), ("B", tilts[1])):
            for motion in (turn_body, tilt_up) if k % 2 else (circles, turn_body):
                    for name, cls in (("old", OldGyro), ("new", NewGyro)):
                        rows = run(cls, k, ref, landscape, tilt, motion, 3.0, warm=6.0)
                        s = score(rows, motion.__name__)
                        report[name].append(s)
                        if s > worst[name][0]:
                            worst[name] = (s, (k, landscape, round(math.degrees(tilt)), motion.__name__))
    for name in ("old", "new"):
        arr = np.array(report[name])
        good = np.mean(arr < 0.15)
        print(f"{name}: median error {np.median(arr):.1%}, runs within 15%: {good:.0%}, worst {worst[name][0]:.0%} at {worst[name][1]}")

    # The documented convention only (what the 3 Nov code assumed).
    for name, cls in (("old", OldGyro), ("new", NewGyro)):
        errs = []
        for landscape in landscapes:
            for tilt in tilts:
                for motion in (turn_body, tilt_up, circles):
                    errs.append(score(run(cls, DEFAULT, np.eye(3), landscape, tilt, motion, 3.0, warm=4.0), ""))
        print(f"{name} on the documented convention: median {np.median(errs):.1%}, worst {max(errs):.1%}")

    # How long the self-check takes to lock on, from the first reading, during natural handling.
    times = []
    for k in RNG.choice(len(CANDIDATES), 24, replace=False):
        g = NewGyro()
        phone = Phone(int(k), random_ref())
        D0 = base_pose("A")
        t = 0.0
        locked = None
        while t < 20:
            t += 1 / 60
            D = rot(Y, 0.5 * math.sin(t * 1.3)) @ rot(X, 0.25 * math.sin(t * 1.7) - 0.5) @ tremor_rot(t, math.radians(0.15)) @ D0
            cf, grav = phone.report(D, 1 / 60)
            g.reading(cf, grav, True, t)
            if g.choice == k and locked is None:
                locked = t
            elif g.choice != k:
                locked = None
        times.append(locked if locked is not None else float("inf"))
    times = np.array(times)
    print(f"self-check: locked on {np.mean(np.isfinite(times)):.0%} of conventions, median {np.median(times[np.isfinite(times)]):.1f} s, slowest {np.max(times[np.isfinite(times)]):.1f} s")

    # Holding still: how much the crosshair moves (degrees, standard deviation over 3 s).
    for name, cls in (("old", OldGyro), ("new", NewGyro)):
        rows = run(cls, DEFAULT, np.eye(3), "A", math.radians(35), still, 3.0, warm=4.0, tremor=math.radians(0.3))
        wobble = math.degrees(np.std(rows[:, 2]) + np.std(rows[:, 3]))
        print(f"{name} holding still with hand tremor: crosshair wobble {wobble:.3f} degrees")

    # Slow pan: smoothness (frame-to-frame variation of the turn rate, degrees per second).
    for name, cls in (("old", OldGyro), ("new", NewGyro)):
        rows = run(cls, DEFAULT, np.eye(3), "A", math.radians(35), slow_pan, 3.0, warm=4.0, tremor=math.radians(0.05))
        per_frame = np.diff(rows[:, 2])
        print(f"{name} slow pan: turn per frame varies by {math.degrees(np.std(per_frame)) * 60:.2f} deg/s (pan is 8 deg/s), ends at {math.degrees(rows[-1, 2]):.1f} of {math.degrees(rows[-1, 0]):.1f} degrees")

    # Twisting the phone like a steering wheel counts toward yaw in player space.
    def twist(t):
        return 0.0, 0.0, math.radians(20) * smooth01(t)
    rows = run(NewGyro, DEFAULT, np.eye(3), "A", math.radians(35), twist, 2.0, warm=4.0)
    print(f"new, 20 degree twist to the left: yaw {math.degrees(rows[-1, 2]):.1f}, pitch {math.degrees(rows[-1, 3]):.1f} degrees")
    return 0


if __name__ == "__main__":
    sys.exit(main())
