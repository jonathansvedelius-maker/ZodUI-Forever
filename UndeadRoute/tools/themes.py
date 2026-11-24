# Makes the guide's themes (Media/Guide/<Theme>/) from the Ornate style of the QuestRouteUI v2 texture pack.
# Each theme gets the same file names as the default art in Media/Guide, so the guide only swaps the folder.
#
# The pack's whole textures (rows, buttons) are cut into nine-slices here rather than taking the pack's own
# nine-slice files, whose corners are mostly empty. On the way, bits of neighbouring art at the edge of a file are
# cropped off and the white fringe its background removal left is cleared. What the pack has no file for is made
# from what it has (a done row from the plain row tinted green, the header from the panel's fill) or copied from
# the default art (the progress bars, the chevron).
#
# Run (Python 3 with Pillow and numpy):
#   python tools/themes.py <folder holding QuestRouteUI/Textures/Themes> [Theme ...]
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "..", "Media", "Guide")
THEMES = ["HordeEmber", "AllianceSteel", "EmeraldWilds", "ArcaneNight"]
PIECES = ["top_left", "top", "top_right", "left", "center", "right", "bottom_left", "bottom", "bottom_right"]
ICONS = ["icon_quest_pickup", "icon_kill_target", "icon_turn_in", "icon_quest_complete", "icon_timer", "icon_travel",
         "icon_map_pin", "icon_waypoint", "icon_settings", "icon_pin", "icon_route", "icon_map_scroll", "icon_quest_log"]
COPIED = ["progress_empty", "progress_filled", "chevron_down"]


def load(path):
    return Image.open(path).convert("RGBA")


def write_tga(im, path):
    """32-bit uncompressed TGA, top-left origin (descriptor 0x28), as tools/art.js writes them."""
    w, h = im.size
    assert w & (w - 1) == 0 and h & (h - 1) == 0, "not a power of two: %s %dx%d" % (path, w, h)
    head = bytearray(18)
    head[2] = 2
    head[12:14] = w.to_bytes(2, "little")
    head[14:16] = h.to_bytes(2, "little")
    head[16], head[17] = 32, 0x28
    r, g, b, a = im.split()
    with open(path, "wb") as f:
        f.write(bytes(head) + Image.merge("RGBA", (b, g, r, a)).tobytes())


def longest_run(flags):
    best, start = (0, 0), None
    for i, on in enumerate(list(flags) + [False]):
        if on and start is None:
            start = i
        elif not on and start is not None:
            if i - start > best[1] - best[0]:
                best = (start, i)
            start = None
    return best


def crop_main(im):
    """The file's main piece of art: the longest unbroken run of columns and of rows that hold any, so slivers of
    neighbouring art across a gap are left out. A column or row counts when an eighth of it is solid: the gaps are
    2 or 3 pixels wide, with a stray solid pixel or a faint glow across them now and then."""
    a = np.asarray(im)[:, :, 3] > 200
    x0, x1 = longest_run(a.mean(axis=0) > 0.12)
    y0, y1 = longest_run(a[:, x0:x1].mean(axis=1) > 0.12)
    return im.crop((x0, y0, x1, y1))


def defringe(im, rim=5):
    """Clears the white halo along the art's outer edge: pale, grey pixels within `rim` of the see-through."""
    px = np.asarray(im).astype(np.float32)
    alpha = Image.fromarray(px[:, :, 3].astype(np.uint8))
    inner = np.asarray(alpha.filter(ImageFilter.MinFilter(rim * 2 + 1))) > 0
    rgb = px[:, :, :3] / 255
    hi, lo = rgb.max(axis=2), rgb.min(axis=2)
    sat = np.where(hi > 0, (hi - lo) / np.maximum(hi, 1e-6), 0)
    pale = (hi > 0.62) & (sat < 0.22) & (px[:, :, 3] > 0) & ~inner
    px[pale, 3] = 0
    return Image.fromarray(px.astype(np.uint8), "RGBA")


def tint(im, r, g, b, light=1.0):
    px = np.asarray(im).astype(np.float32)
    px[:, :, 0] *= r * light
    px[:, :, 1] *= g * light
    px[:, :, 2] *= b * light
    return Image.fromarray(np.clip(px, 0, 255).astype(np.uint8), "RGBA")


def nine(im, out, base, cut, corner=32, edge=128, middle=64):
    """Cuts `im` into nine files `base`_<piece>: corners `cut` pixels of the source, written `corner` big."""
    w, h = im.size
    xs, ys = [0, cut, w - cut, w], [0, cut, h - cut, h]
    sizes = {0: corner, 1: edge, 2: corner}
    vsizes = {0: corner, 1: middle, 2: corner}
    for n, piece in enumerate(PIECES):
        cx, cy = n % 3, n // 3
        part = im.crop((xs[cx], ys[cy], xs[cx + 1], ys[cy + 1]))
        write_tga(part.resize((sizes[cx], vsizes[cy]), Image.LANCZOS), os.path.join(out, "%s_%s.tga" % (base, piece)))


def fit(im, size):
    """`im` in the middle of a see-through square `size` a side, its longer side filling it."""
    w, h = im.size
    k = size / max(w, h)
    small = im.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(small, ((size - small.width) // 2, (size - small.height) // 2))
    return canvas


def switch(im):
    """A switch laid out as the default art's: 128 x 64, the switch itself in x 0.03-0.97 and y 0.2-0.8, the part
    the guide shows (Guide.lua's SetTexCoord)."""
    canvas = Image.new("RGBA", (128, 64), (0, 0, 0, 0))
    x0, x1, y0, y1 = round(0.03 * 128), round(0.97 * 128), round(0.2 * 64), round(0.8 * 64)
    canvas.alpha_composite(im.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0))
    return canvas


def make(root, theme):
    src = os.path.join(root, "QuestRouteUI", "Textures", "Themes", theme)
    core, states, slices = (os.path.join(src, "Ornate", d) for d in ("Core", "States", "NineSlice"))
    out = os.path.join(MEDIA, theme)
    os.makedirs(out, exist_ok=True)

    def whole(folder, name):
        return defringe(crop_main(load(os.path.join(folder, name + ".png"))))

    # Rows and buttons: cut from the whole textures, their chamfered corners kept.
    row = whole(core, "row_normal")
    for base, im in [("row_normal", row), ("row_active", whole(core, "row_active")),
                     ("row_complete", tint(row, 0.72, 1.12, 0.70)), ("row_upcoming", whole(core, "row_disabled")),
                     ("row_hover", whole(states, "row_hover")), ("button_normal", whole(core, "button_normal")),
                     ("button_hover", whole(core, "button_hover"))]:
        nine(im, out, base, round(min(im.size) * 0.22), corner=16)
    # The window's frame: the pack's own nine-slice (it is drawn over the window, so its middle is left empty);
    # its middle becomes the window's fill.
    for piece in PIECES:
        im = load(os.path.join(slices, "frame_%s.png" % piece))
        if piece == "center":
            write_tga(im.resize((256, 256), Image.LANCZOS), os.path.join(out, "panel_fill.tga"))
            fill = im
            im = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
        write_tga(im, os.path.join(out, "frame_ornate_%s.tga" % piece))
    write_tga(tint(fill, 1, 1, 1, 0.72).resize((512, 128), Image.LANCZOS), os.path.join(out, "header_backdrop.tga"))
    write_tga(tint(fill, 1, 1, 1, 0.62).resize((512, 64), Image.LANCZOS), os.path.join(out, "footer_backdrop.tga"))
    top = crop_main(load(os.path.join(slices, "frame_top.png")))
    write_tga(top.resize((256, 8), Image.LANCZOS), os.path.join(out, "divider_gold.tga"))
    # The step's ring: the level ring, plain for the step you are on, dimmed for the others, green once done.
    ring = fit(whole(core, "level_ring"), 64)
    write_tga(ring, os.path.join(out, "step_ring_current.tga"))
    write_tga(tint(ring, 1, 1, 1, 0.7), os.path.join(out, "step_ring_idle.tga"))
    write_tga(tint(ring, 0.6, 1.1, 0.6), os.path.join(out, "step_ring_done.tga"))
    write_tga(switch(whole(core, "toggle_on")), os.path.join(out, "toggle_on.tga"))
    write_tga(switch(whole(states, "toggle_off")), os.path.join(out, "toggle_off.tga"))
    # The theme's emblem, where the default art has the Horde's banner.
    write_tga(fit(whole(core, "quest_badge"), 128), os.path.join(out, "emblem.tga"))
    for name in ICONS:
        write_tga(fit(load(os.path.join(src, "SharedIcons", name + ".png")), 64), os.path.join(out, name + ".tga"))
    for name in COPIED:
        with open(os.path.join(MEDIA, name + ".tga"), "rb") as f, open(os.path.join(out, name + ".tga"), "wb") as g:
            g.write(f.read())
    print("Media/Guide/%s: %d files" % (theme, len(os.listdir(out))))


if __name__ == "__main__":
    for t in sys.argv[2:] or THEMES:
        make(sys.argv[1], t)
