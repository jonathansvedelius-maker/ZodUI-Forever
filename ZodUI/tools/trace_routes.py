"""Traces the Dungeon guide's route lines along the corridors of each dungeon map.

    node tools/dumpguides.js > guides.json
    python -I tools/trace_routes.py guides.json "<WoW>/Interface/AddOns/ForeverDungeonJournal/Media" <check-dir>

The map art is ForeverDungeonJournal's copy of each dungeon map (Media/Maps/<Name><n>.blp, the client's
tiles put together, and Media/*Map.tga for the maps it made itself): the same pictures the guide shows,
so their fractions are the guide's. For every leg between two steps on one floor it finds the cheapest
way over the floor's pixels, kept to the middle of the corridors, and simplifies it to a few bends.

The floor's colour is learned from the pixels around the boss pins, which stand on the floor. A leg
whose way runs over too much non-floor is not used (the line stays straight) and is reported. Bends a
step already has in GuideData.lua are kept as points the way must pass, except the ones listed in
GUESSED below. The result is written between the "traced" markers at the end of Modules/GuideData.lua,
and a picture of each floor with its lines is saved in <check-dir> to look over by eye.

Needs Pillow, numpy, scipy and scikit-image."""
import json, os, re, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from skimage.graph import route_through_array

GUESSED = {("sfk", 5), ("smlib", 2), ("smlib", 3)}  # bends placed by eye, not to be kept
# Open ground (a desert, a city's streets, an island): no corridors to keep to, and the walls the tool
# finds there are the terrain's pattern. Their lines stay straight.
OPEN = {"zf", "excav", "kroldok", "ruins", "drowned"}
SCALE = 0.5            # work on half-size maps: plenty for a 501-px window
MAX_OFF = 0.06         # share of a way that may run off the floor
OUT_MARK = ("-- traced:begin", "-- traced:end")

guides = json.load(open(sys.argv[1], encoding="utf-8"))
media = sys.argv[2]
check_dir = sys.argv[3]
os.makedirs(check_dir, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
data_path = os.path.join(here, "..", "Modules", "GuideData.lua")


def art(floor):
    """The floor's map as an RGB array covering exactly the guide's 0..1 square, or None."""
    if floor.get("texture"):
        name = floor["texture"].split("\\")[-1]
        for p in (os.path.join(media, name + ".tga"), os.path.join(media, "Maps", name + ".tga"), os.path.join(media, "Maps", name + ".blp")):
            if os.path.exists(p):
                im = Image.open(p).convert("RGB")
                w, h = im.size
                return np.asarray(im.crop((0, 0, round(w * floor.get("texRight", 1)), round(h * floor.get("texBottom", 1)))))
    if floor.get("tiles"):
        name = floor["tiles"].split("\\")[-1].rstrip("_")
        p = os.path.join(media, "Maps", name + ".blp")
        if os.path.exists(p):
            return np.asarray(Image.open(p).convert("RGB").crop((0, 0, 1002, 668)))
    return None


def floor_mask(img, spots):
    """(inside, wall): the map's walls are its sharpest edges; what reaches the picture's border without
    crossing one is the parchment around the dungeon, and the rest, inside the walls, is the dungeon's
    floor: light rooms, dark caves, water. Edges inside are doors and room borders, crossed at a cost."""
    lum = img.astype(float) @ [0.3, 0.59, 0.11]
    g = ndimage.gaussian_filter(lum, 1.0)
    grad = np.hypot(ndimage.sobel(g, 0), ndimage.sobel(g, 1))
    wall = ndimage.binary_dilation(grad > np.percentile(grad, 88), iterations=1)
    labels, n = ndimage.label(~wall)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    inside = ~wall & ~np.isin(labels, list(border))
    sizes = ndimage.sum(inside, labels, range(n + 1))
    inside &= sizes[labels] >= 30                       # specks in the parchment's pattern
    return inside, wall


def rdp(pts, eps):
    if len(pts) < 3: return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    L = max(1e-9, ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5)
    d = [abs((y2 - y1) * x - (x2 - x1) * y + x2 * y1 - y2 * x1) / L for x, y in pts[1:-1]]
    i = int(np.argmax(d)) + 1
    if d[i - 1] <= eps: return [pts[0], pts[-1]]
    return rdp(pts[:i + 1], eps)[:-1] + rdp(pts[i:], eps)


def snap(mask, dist, px, py, r):
    h, w = mask.shape
    ys, xs = np.mgrid[max(0, py - r):min(h, py + r + 1), max(0, px - r):min(w, px + r + 1)]
    ok = mask[ys, xs]
    if not ok.any(): return px, py
    score = dist[ys, xs] * 2 - np.hypot(xs - px, ys - py)
    score[~ok] = -1e9
    j = np.unravel_index(np.argmax(score), score.shape)
    return int(xs[j]), int(ys[j])


traced, report = {}, []
for key in sorted(guides):
    if key in OPEN: continue
    g = guides[key]
    steps, floors = g["steps"], g["floors"]
    pictures = {}
    for fi, fl in enumerate(floors, start=1):
        img = art(fl)
        if img is None: continue
        small = np.asarray(Image.fromarray(img).resize((round(img.shape[1] * SCALE), round(img.shape[0] * SCALE)), Image.LANCZOS))
        spots = [(s["x"], s["y"]) for s in steps if s.get("x") is not None and s.get("floor") == fi]
        inside, wall = floor_mask(small, spots)
        dist = ndimage.distance_transform_edt(inside)
        cost = np.where(inside, 1.0 + 6.0 / (dist + 1.0), np.where(wall, 30.0, 400.0))
        mask = inside | wall      # the way may cross a door's edge, never the parchment outside
        pictures[fi] = (small, mask, dist, cost)

    lines = {}
    for i, s in enumerate(steps, start=1):
        if i == 1 or s.get("x") is None: continue
        prev = next((steps[j - 1] for j in range(i - 1, 0, -1) if steps[j - 1].get("x") is not None), None)
        if not prev: continue
        pts = [(prev["floor"], prev["x"], prev["y"])]
        if (key, i) not in GUESSED:
            pts += [tuple(p) for p in s.get("via") or []]
        pts.append((s["floor"], s["x"], s["y"]))
        out, ok = [], True
        for (fa, xa, ya), (fb, xb, yb) in zip(pts, pts[1:]):
            if fa != fb or fa not in pictures:
                out.append((fb, xb, yb))
                continue
            small, mask, dist, cost = pictures[fa]
            h, w = mask.shape
            a = snap(mask, dist, int(xa * w), int(ya * h), 10)
            b = snap(mask, dist, int(xb * w), int(yb * h), 10)
            route, _ = route_through_array(cost, (a[1], a[0]), (b[1], b[0]), fully_connected=True, geometric=True)
            off = sum(1 for y, x in route if not mask[y, x]) / max(1, len(route))
            if off > MAX_OFF:
                ok = False
                report.append("%s step %d (%s): %.0f%% of the way off the floor, left straight" % (key, i, s["title"], off * 100))
                break
            simple = rdp([(x, y) for y, x in route], 2.5)
            for x, y in simple[1:-1]:
                out.append((fa, round(x / w, 3), round(y / h, 3)))
            out.append((fb, xb, yb))
            lines.setdefault(fa, []).append([(x, y) for x, y in simple])
        if ok:
            bends = [p for p in out[:-1]]
            traced.setdefault(key, {})[i] = bends

    for fi, (small, mask, dist, cost) in pictures.items():
        shade = small.copy()
        shade[~mask] = shade[~mask] // 3                     # what the way may not cross shows dark
        pic = Image.fromarray(shade).convert("RGB")
        dr = ImageDraw.Draw(pic)
        for line in lines.get(fi, []):
            dr.line(line, fill=(0, 220, 0), width=3)
        h, w = mask.shape
        for i, s in enumerate(steps, start=1):
            if s.get("x") is not None and s.get("floor") == fi:
                x, y = s["x"] * w, s["y"] * h
                dr.rectangle((x - 7, y - 7, x + 7, y + 7), fill=(160, 20, 20))
                dr.text((x - 4, y - 6), str(i), fill=(255, 255, 255))
        pic.save(os.path.join(check_dir, "%s_%d.png" % (key, fi)))


def lua_points(pts):
    return "{ " + ", ".join("{ %d, %s, %s }" % (f, ("%.3f" % x).rstrip("0").rstrip("."), ("%.3f" % y).rstrip("0").rstrip(".")) for f, x, y in pts) + " }"

body = [OUT_MARK[0],
        "-- Bends along the corridors, made by tools/trace_routes.py from ForeverDungeonJournal's map art.",
        "-- They stand in for a step's `via` (your own drawn bends still win). Do not edit by hand: run the tool.",
        "ns.GUIDE_TRACED = {"]
for key in sorted(traced):
    body.append("    %s = {" % key)
    for i in sorted(traced[key]):
        body.append("        [%d] = %s," % (i, lua_points(traced[key][i])))
    body.append("    },")
body += ["}", OUT_MARK[1]]

src = open(data_path, encoding="utf-8").read()
if OUT_MARK[0] in src:
    src = src[:src.index(OUT_MARK[0])] + "\n".join(body) + src[src.index(OUT_MARK[1]) + len(OUT_MARK[1]):]
else:
    src = src.rstrip("\n") + "\n\n" + "\n".join(body) + "\n"
open(data_path, "w", encoding="utf-8", newline="").write(src)

print("traced %d legs in %d guides" % (sum(len(v) for v in traced.values()), len(traced)))
for line in report: print(line)
