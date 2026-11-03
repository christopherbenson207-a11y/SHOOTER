"""Check the Endless house layout and draw it.

Reads src/endless/ServerStorage/Endless/HouseLayout.luau (a plain Luau table), checks that the
builder can make a playable house from it, and draws every level to docs/endless/house.png.

Usage: python tools/endless_house.py            (check and draw)
       python tools/endless_house.py --check    (check only; exit code 1 on problems)

The rules checked here are the ones ServerStorage.Endless.HouseBuilder relies on. Pillow is only
needed for the drawing.
"""
import os
import re
import sys
from collections import defaultdict, deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYOUT = os.path.join(ROOT, "src", "endless", "ServerStorage", "Endless", "HouseLayout.luau")
OUT_DIR = os.path.join(ROOT, "docs", "endless")

DIRS = {"N": (0, -1), "S": (0, 1), "W": (-1, 0), "E": (1, 0)}
OPPOSITE = {"N": "S", "S": "N", "W": "E", "E": "W"}
SPOT_KINDS = {"Box", "Perk", "Wall", "Altar", "Power"}
# How many of each spot kind a run needs (Config: one box, five perks, one altar, one switch).
SPOT_NEEDS = {"Box": 2, "Perk": 5, "Altar": 1, "Power": 1, "Wall": 1}


# Luau table literal -> Python ------------------------------------------------------------------

TOKEN = re.compile(
    r"""\s+|--\[\[.*?\]\]|--[^\n]*|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|-?\d+(?:\.\d+)?|[A-Za-z_]\w*|[{}\[\]=,;]""",
    re.S,
)


def tokenize(text):
    pos, out = 0, []
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise SyntaxError(f"layout: can't read {text[pos:pos + 30]!r}")
        tok = m.group(0)
        pos = m.end()
        if tok.isspace() or tok.startswith("--"):
            continue
        out.append(tok)
    return out


def parse(text):
    toks = tokenize(text)
    i = 0

    def peek():
        return toks[i] if i < len(toks) else None

    def take(expected=None):
        nonlocal i
        tok = toks[i]
        if expected and tok != expected:
            raise SyntaxError(f"layout: expected {expected!r}, got {tok!r}")
        i += 1
        return tok

    def value():
        tok = peek()
        if tok == "{":
            return table()
        take()
        if tok[0] in "\"'":
            return bytes(tok[1:-1], "utf-8").decode("unicode_escape")
        if tok in ("true", "false"):
            return tok == "true"
        if tok == "nil":
            return None
        if re.fullmatch(r"-?\d+(\.\d+)?", tok):
            return float(tok) if "." in tok else int(tok)
        raise SyntaxError(f"layout: unexpected {tok!r}")

    def table():
        take("{")
        result, n = {}, 0
        while peek() != "}":
            if peek() == "[":
                take("[")
                key = value()
                take("]")
                take("=")
                result[key] = value()
            elif re.fullmatch(r"[A-Za-z_]\w*", peek() or "") and i + 1 < len(toks) and toks[i + 1] == "=":
                key = take()
                take("=")
                result[key] = value()
            else:
                n += 1
                result[n] = value()
            if peek() in (",", ";"):
                take()
        take("}")
        if result and all(isinstance(k, int) for k in result) and sorted(result) == list(range(1, len(result) + 1)):
            return [result[k] for k in range(1, len(result) + 1)]
        return result

    if peek() == "return":
        take()
    return value()


# The model -------------------------------------------------------------------------------------


class House:
    def __init__(self, data):
        self.data = data
        self.w, self.d = data["Width"], data["Depth"]
        self.levels = data["Levels"]
        self.rooms = data["Rooms"]
        self.problems = []

    def fail(self, msg):
        self.problems.append(msg)

    def room(self, level, x, z):
        rows = self.levels.get(level)
        if rows is None or not (0 <= x < self.w and 0 <= z < self.d):
            return None
        c = rows[z][x]
        return None if c == "." else c

    @staticmethod
    def boundary(level, x, z, side):
        dx, dz = DIRS[side]
        if side in ("W", "N"):
            return (level, x + dx, z + dz, OPPOSITE[side])
        return (level, x, z, side)

    def check(self):
        d = self.data
        for level, rows in self.levels.items():
            if len(rows) != self.d or any(len(r) != self.w for r in rows):
                self.fail(f"level {level}: every plan needs {self.d} rows of {self.w} cells")
                return
        # Rooms: defined, on one level, in one piece.
        cells = defaultdict(list)
        for level, rows in self.levels.items():
            for z, row in enumerate(rows):
                for x, c in enumerate(row):
                    if c != ".":
                        cells[c].append((level, x, z))
        for c, list_ in cells.items():
            if c not in self.rooms:
                self.fail(f"room {c!r} is in a plan but not in Rooms")
            if len({lv for lv, _, _ in list_}) > 1:
                self.fail(f"room {c!r} is on more than one level")
            seen, todo = {list_[0]}, [list_[0]]
            while todo:
                lv, x, z = todo.pop()
                for dx, dz in DIRS.values():
                    n = (lv, x + dx, z + dz)
                    if n in set(list_) and n not in seen:
                        seen.add(n)
                        todo.append(n)
            if len(seen) != len(list_):
                self.fail(f"room {c!r} is in more than one piece")
        for c in self.rooms:
            if c not in cells:
                self.fail(f"room {c!r} is in Rooms but on no plan")
        self.cells = cells
        self.room_level = {c: l[0][0] for c, l in cells.items()}

        # Stairs.
        self.ramp, self.hole, self.approach, self.landing = {}, {}, {}, {}
        self.gates = {}
        joins = []  # rooms joined without a door
        gated = []  # (roomA, roomB, cost, where)
        for s in d.get("Stairs", []):
            lv, (x, z), rise, n = s["Level"], s["At"], s["Rise"], s["Length"]
            dx, dz = DIRS[rise]
            ramp = [(x + dx * k, z + dz * k) for k in range(n)]
            low_room = {self.room(lv, a, b) for a, b in ramp}
            high_room = {self.room(lv + 1, a, b) for a, b in ramp}
            app = (x - dx, z - dz)
            land = (x + dx * n, z + dz * n)
            if len(low_room) != 1 or None in low_room:
                self.fail(f"stair at {lv} {x},{z}: its ramp cells must all be one room")
                continue
            if len(high_room) != 1 or None in high_room:
                self.fail(f"stair at {lv} {x},{z}: the cells above the ramp must all be one room")
                continue
            r0, r1 = low_room.pop(), high_room.pop()
            if self.room(lv, *app) != r0:
                self.fail(f"stair at {lv} {x},{z}: the cell before its foot must be {r0}")
            if self.room(lv + 1, *land) != r1:
                self.fail(f"stair at {lv} {x},{z}: the cell past its top must be {r1}")
            for a, b in ramp:
                self.ramp[(lv, a, b)] = s
                self.hole[(lv + 1, a, b)] = s
            self.approach[(lv, *app)] = s
            self.landing[(lv + 1, *land)] = s
            gate = s.get("Gate")
            if gate == "Bottom":
                key = self.boundary(lv, x, z, OPPOSITE[rise])
            elif gate == "Top":
                key = self.boundary(lv + 1, *ramp[-1], rise)
            else:
                key = None
            if key:
                self.gates[key] = s
                gated.append((r0, r1, s.get("Cost", 0), f"stair {lv} {x},{z}"))
            else:
                joins.append((r0, r1))

        # Openings.
        self.openings = {}

        def place(kind, o):
            lv, (x, z), side = o["Level"], o["At"], o["Side"]
            here, there = self.room(lv, x, z), self.room(lv, x + DIRS[side][0], z + DIRS[side][1])
            where = f"{kind} at {lv} {x},{z} {side}"
            if here is None:
                self.fail(f"{where}: no room in that cell")
                return None
            key = self.boundary(lv, x, z, side)
            if key in self.openings or key in self.gates:
                self.fail(f"{where}: that wall already has an opening")
                return None
            for cell in ((lv, x, z), (lv, x + DIRS[side][0], z + DIRS[side][1])):
                if cell in self.ramp or cell in self.hole:
                    self.fail(f"{where}: opens onto a stair")
            if kind in ("Door", "Arch"):
                if there is None or there == here:
                    self.fail(f"{where}: must be between two different rooms")
                    return None
            else:
                if there is not None:
                    self.fail(f"{where}: windows go in outside walls")
                    return None
                if lv < 0:
                    self.fail(f"{where}: no windows below ground (use a hatch)")
                ox, oz = x + DIRS[side][0], z + DIRS[side][1]
                for below in range(0, lv):
                    if self.room(below, ox, oz) is not None:
                        self.fail(f"{where}: zombies climb to this window, so level {below} must be open ground under it")
            self.openings[key] = (kind, o, here, there)
            return here, there

        for o in d.get("Doors", []):
            r = place("Door", o)
            if r:
                gated.append((r[0], r[1], o.get("Cost", 0), f"door {o['Level']} {o['At']}"))
        for o in d.get("Arches", []):
            r = place("Arch", o)
            if r:
                joins.append(r)
        for o in d.get("Windows", []):
            place("Window", o)

        for h in d.get("Hatches", []):
            cell = (h["Level"], *h["At"])
            if self.room(*cell) is None:
                self.fail(f"hatch at {cell}: no room in that cell")
            if cell in self.ramp or cell in self.hole or cell in self.approach or cell in self.landing:
                self.fail(f"hatch at {cell}: too close to a stair")

        spots_at = set()
        counts = defaultdict(int)
        for s in d.get("Spots", []):
            lv, (x, z), side = s["Level"], s["At"], s["Side"]
            where = f"{s['Kind']} spot at {lv} {x},{z} {side}"
            counts[s["Kind"]] += 1
            if s["Kind"] not in SPOT_KINDS:
                self.fail(f"{where}: unknown kind")
            here = self.room(lv, x, z)
            there = self.room(lv, x + DIRS[side][0], z + DIRS[side][1])
            if here is None:
                self.fail(f"{where}: no room in that cell")
            elif there == here:
                self.fail(f"{where}: there is no wall on that side")
            key = self.boundary(lv, x, z, side)
            if key in self.openings or key in self.gates:
                self.fail(f"{where}: that wall has an opening")
            if (lv, x, z) in self.ramp or (lv, x, z) in self.hole:
                self.fail(f"{where}: on a stair")
            if (lv, x, z, side) in spots_at:
                self.fail(f"{where}: two spots in one place")
            spots_at.add((lv, x, z, side))
        for kind, need in SPOT_NEEDS.items():
            if counts[kind] < need:
                self.fail(f"Spots: a run needs at least {need} {kind} spots, the layout has {counts[kind]}")

        # Zones: rooms joined by arches and open stairs; doors and gated stairs join zones.
        parent = {c: c for c in self.rooms}

        def find(c):
            while parent[c] != c:
                parent[c] = parent[parent[c]]
                c = parent[c]
            return c

        for a, b in joins:
            parent[find(a)] = find(b)
        self.zone = {c: find(c) for c in self.rooms if c in self.cells}
        starts = [c for c, r in self.rooms.items() if r.get("Start")]
        if len(starts) != 1:
            self.fail("exactly one room needs Start = true")
            return
        links = defaultdict(set)
        for a, b, _, _ in gated:
            if a in self.zone and b in self.zone:
                za, zb = self.zone[a], self.zone[b]
                if za == zb:
                    self.fail(f"a door joins {a} and {b}, which are already one zone")
                links[za].add(zb)
                links[zb].add(za)
        start = self.zone[starts[0]]
        seen, todo = {start}, deque([start])
        while todo:
            z = todo.popleft()
            for n in links[z]:
                if n not in seen:
                    seen.add(n)
                    todo.append(n)
        for c, z in self.zone.items():
            if z not in seen:
                self.fail(f"room {c} ({self.rooms[c]['Name']}) can never be reached from the start")
        entries = defaultdict(int)
        for kind, o, here, _ in self.openings.values():
            if kind == "Window":
                entries[self.zone[here]] += 1
        for h in d.get("Hatches", []):
            r = self.room(h["Level"], *h["At"])
            if r:
                entries[self.zone[r]] += 1
        if entries[start] == 0:
            self.fail("the start zone needs a window or a hatch, or no zombie can reach the players")
        self.entries = entries
        self.start = start


# Drawing ---------------------------------------------------------------------------------------

def draw(house):
    from PIL import Image, ImageDraw, ImageFont

    px = 44
    pad = 30
    levels = sorted(house.levels)
    w, h = house.w * px + pad * 2, house.d * px + pad * 2 + 24
    img = Image.new("RGB", (w * 2, h * ((len(levels) + 1) // 2)), (24, 24, 28))
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 11)
        bold = ImageFont.truetype("DejaVuSans-Bold.ttf", 15)
    except OSError:
        font = bold = ImageFont.load_default()

    def colour(c):
        hsh = sum(ord(ch) * 97 for ch in c) * 2654435761 % 360
        import colorsys
        r, g, b = colorsys.hls_to_rgb(hsh / 360, 0.42, 0.35)
        return int(r * 255), int(g * 255), int(b * 255)

    names = {"Box": "BOX", "Perk": "PERK", "Wall": "GUN", "Altar": "ALTAR", "Power": "POWER"}
    for i, lv in enumerate(levels):
        ox, oy = (i % 2) * w + pad, (i // 2) * h + pad + 20
        d = ImageDraw.Draw(img)
        title = {-1: "CELLAR", 0: "GROUND FLOOR", 1: "UPPER FLOOR", 2: "ATTIC"}.get(lv, f"LEVEL {lv}")
        d.text((ox, oy - 26), f"{title}  (level {lv})", fill=(235, 230, 220), font=bold)

        def cell_box(x, z):
            return ox + x * px, oy + z * px, ox + (x + 1) * px, oy + (z + 1) * px

        for z in range(house.d):
            for x in range(house.w):
                r = house.room(lv, x, z)
                box = cell_box(x, z)
                if r is None:
                    d.rectangle(box, outline=(34, 34, 40))
                    continue
                fill = colour(r)
                if (lv, x, z) in house.hole:
                    fill = (18, 18, 20)
                d.rectangle(box, fill=fill, outline=tuple(min(255, v + 18) for v in fill))
                if (lv, x, z) in house.ramp:
                    s = house.ramp[(lv, x, z)]
                    dx, dz = DIRS[s["Rise"]]
                    cx, cz = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
                    d.line((cx - dx * 14, cz - dz * 14, cx + dx * 14, cz + dz * 14), fill=(250, 250, 250), width=3)
                    d.polygon([(cx + dx * 16, cz + dz * 16), (cx + dx * 6 - dz * 7, cz + dz * 6 + dx * 7),
                               (cx + dx * 6 + dz * 7, cz + dz * 6 - dx * 7)], fill=(250, 250, 250))
        # Room labels.
        for c, list_ in house.cells.items():
            if house.room_level[c] != lv:
                continue
            xs = [x for _, x, _ in list_]
            zs = [z for _, _, z in list_]
            cx = ox + (min(xs) + max(xs) + 1) / 2 * px
            cz = oy + (min(zs) + max(zs) + 1) / 2 * px
            label = f"{c}  {house.rooms[c]['Name']}"
            tw = d.textlength(label, font=font)
            d.text((cx - tw / 2, cz - 6), label, fill=(250, 248, 240), font=font)
        # Walls and openings.
        for z in range(-1, house.d + 1):
            for x in range(-1, house.w + 1):
                for side in ("E", "S"):
                    a = house.room(lv, x, z)
                    nx, nz = x + DIRS[side][0], z + DIRS[side][1]
                    b = house.room(lv, nx, nz)
                    if a == b or (a is None and b is None):
                        continue
                    key = (lv, x, z, side)
                    if side == "E":
                        line = (ox + (x + 1) * px, oy + z * px, ox + (x + 1) * px, oy + (z + 1) * px)
                    else:
                        line = (ox + x * px, oy + (z + 1) * px, ox + (x + 1) * px, oy + (z + 1) * px)
                    opening = house.openings.get(key)
                    if opening is None:
                        d.line(line, fill=(10, 10, 10), width=4)
                        continue
                    kind, o, _, _ = opening
                    if kind == "Window":
                        d.line(line, fill=(90, 170, 255), width=6)
                    elif kind == "Door":
                        d.line(line, fill=(10, 10, 10), width=4)
                        mx, my = (line[0] + line[2]) / 2, (line[1] + line[3]) / 2
                        if side == "E":
                            d.line((mx, my - 13, mx, my + 13), fill=(255, 150, 40), width=6)
                        else:
                            d.line((mx - 13, my, mx + 13, my), fill=(255, 150, 40), width=6)
                        d.text((mx + 4, my + 2), str(o.get("Cost", "")), fill=(255, 200, 120), font=font)
                    else:
                        d.line(line, fill=(10, 10, 10), width=4)
                        mx, my = (line[0] + line[2]) / 2, (line[1] + line[3]) / 2
                        if side == "E":
                            d.line((mx, my - 15, mx, my + 15), fill=colour(a or b), width=6)
                        else:
                            d.line((mx - 15, my, mx + 15, my), fill=colour(a or b), width=6)
        # Railings round stair holes, and gates.
        for (l, x, z), s in house.hole.items():
            if l != lv:
                continue
            for side, (dx, dz) in DIRS.items():
                n = (l, x + dx, z + dz)
                if n in house.hole or house.room(*n) != house.room(l, x, z):
                    continue
                if n in house.landing and house.landing[n] is s:
                    continue
                box = cell_box(x, z)
                line = {"N": (box[0], box[1], box[2], box[1]), "S": (box[0], box[3], box[2], box[3]),
                        "W": (box[0], box[1], box[0], box[3]), "E": (box[2], box[1], box[2], box[3])}[side]
                d.line(line, fill=(200, 200, 200), width=2)
        for (l, x, z, side), s in house.gates.items():
            if l != lv:
                continue
            box = cell_box(x, z)
            line = {"E": (box[2], box[1] + 6, box[2], box[3] - 6), "S": (box[0] + 6, box[3], box[2] - 6, box[3])}[side]
            d.line(line, fill=(255, 150, 40), width=6)
            d.text((line[0] + 4, line[1] + 2), f"{s.get('Cost', '')}", fill=(255, 200, 120), font=font)
        # Hatches.
        for hch in house.data.get("Hatches", []):
            if hch["Level"] != lv:
                continue
            box = cell_box(*hch["At"])
            d.ellipse((box[0] + 12, box[1] + 12, box[2] - 12, box[3] - 12), fill=(150, 60, 200), outline=(230, 200, 255))
        # Spots.
        for s in house.data.get("Spots", []):
            if s["Level"] != lv:
                continue
            box = cell_box(*s["At"])
            cx, cz = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
            dx, dz = DIRS[s["Side"]]
            sx, sz = cx + dx * 13, cz + dz * 13
            label = names[s["Kind"]] if s["Kind"] != "Wall" or "Weapon" not in s else s["Weapon"].upper()
            tw = d.textlength(label, font=font)
            d.rectangle((sx - tw / 2 - 2, sz - 7, sx + tw / 2 + 2, sz + 7), fill=(245, 225, 120))
            d.text((sx - tw / 2, sz - 7), label, fill=(30, 25, 10), font=font)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "house.png")
    img.save(path)
    return path


def main():
    with open(LAYOUT, encoding="utf-8") as f:
        house = House(parse(f.read()))
    house.check()
    zones = defaultdict(list)
    for c, z in getattr(house, "zone", {}).items():
        zones[z].append(c)
    for z, rooms in sorted(zones.items()):
        names = ", ".join(house.rooms[c]["Name"] for c in sorted(rooms))
        start = "  (start)" if z == getattr(house, "start", None) else ""
        print(f"zone {z}: {names}; {house.entries.get(z, 0)} zombie entries{start}")
    if house.problems:
        print(f"\n{len(house.problems)} problem(s):")
        for p in house.problems:
            print("  -", p)
    else:
        print("\nlayout OK")
    if "--check" not in sys.argv:
        print("drew", os.path.relpath(draw(house), ROOT))
    sys.exit(1 if house.problems else 0)


if __name__ == "__main__":
    main()
