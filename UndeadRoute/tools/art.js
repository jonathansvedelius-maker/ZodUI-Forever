// Draws the few textures of the guide window (Media/Guide) that the QuestRouteUI texture pack has no file for:
// the pills, the tip icon and the Alliance's pennant. The rest of Media/Guide is that pack's. See tools/GUIDE-ART.md.
// The shapes are signed distance functions, sampled 4 x 4 a pixel for soft edges. Run: node tools/art.js
const fs = require("fs");
const path = require("path");

const OUT = path.join(__dirname, "..", "Media", "Guide");
const SS = 4; // samples a side per pixel

// --- shapes: each takes a point and gives the distance to its edge, below 0 inside
const circle = (cx, cy, r) => (x, y) => Math.hypot(x - cx, y - cy) - r;
const box = (cx, cy, hw, hh, r = 0) => (x, y) => {
    const qx = Math.abs(x - cx) - hw + r, qy = Math.abs(y - cy) - hh + r;
    return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
};
const seg = (ax, ay, bx, by, r) => (x, y) => {
    const dx = bx - ax, dy = by - ay;
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)));
    return Math.hypot(x - (ax + t * dx), y - (ay + t * dy)) - r;
};
const poly = (pts) => (x, y) => {
    let d = Infinity, inside = false;
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        const [ax, ay] = pts[j], [bx, by] = pts[i];
        d = Math.min(d, seg(ax, ay, bx, by, 0)(x, y));
        if ((ay > y) !== (by > y) && x < ((bx - ax) * (y - ay)) / (by - ay) + ax) inside = !inside;
    }
    return inside ? -d : d;
};
const polyline = (pts, r) => (x, y) => {
    let d = Infinity;
    for (let i = 1; i < pts.length; i++) d = Math.min(d, seg(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], r)(x, y));
    return d;
};
const union = (...fs) => (x, y) => Math.min(...fs.map((f) => f(x, y)));
const cut = (a, b) => (x, y) => Math.max(a(x, y), -b(x, y));
const ring = (f, w) => (x, y) => Math.abs(f(x, y)) - w / 2;
const grow = (f, by) => (x, y) => f(x, y) - by;
const rotate = (f, cx, cy, deg) => {
    const a = (-deg * Math.PI) / 180, c = Math.cos(a), s = Math.sin(a);
    return (x, y) => f(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c);
};
const arc = (cx, cy, r, from, to, w, n = 40) => {
    const pts = [];
    for (let i = 0; i <= n; i++) {
        const a = ((from + ((to - from) * i) / n) * Math.PI) / 180;
        pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
    }
    return polyline(pts, w / 2);
};

// --- colours: [r, g, b, a] in 0-255, a in 0-1, or a function of (x, y) giving one
const vgrad = (top, bottom, y0, y1) => (x, y) => {
    const t = Math.max(0, Math.min(1, (y - y0) / (y1 - y0)));
    return top.map((v, i) => v + (bottom[i] - v) * t);
};

// Layers, painted in order: { shape, color } fills; { glow, color, width } a soft halo outside the shape.
function draw(w, h, layers) {
    const px = new Float32Array(w * h * 4);
    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
            let r = 0, g = 0, b = 0, a = 0;
            for (const L of layers) {
                let cover = 0;
                if (L.glow) {
                    const d = L.glow(x + 0.5, y + 0.5);
                    cover = d <= 0 ? (L.inside ? 1 : 0) : Math.pow(Math.max(0, 1 - d / L.width), 2);
                } else {
                    for (let sy = 0; sy < SS; sy++) {
                        for (let sx = 0; sx < SS; sx++) {
                            if (L.shape(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS) <= 0) cover++;
                        }
                    }
                    cover /= SS * SS;
                }
                if (cover <= 0) continue;
                const c = typeof L.color === "function" ? L.color(x + 0.5, y + 0.5) : L.color;
                const ca = (c[3] === undefined ? 1 : c[3]) * cover;
                const na = ca + a * (1 - ca);
                if (na > 0) {
                    r = (c[0] * ca + r * a * (1 - ca)) / na;
                    g = (c[1] * ca + g * a * (1 - ca)) / na;
                    b = (c[2] * ca + b * a * (1 - ca)) / na;
                }
                a = na;
            }
            const i = (y * w + x) * 4;
            px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a;
        }
    }
    return { w, h, px };
}

// 32-bit TGA, top-left origin (descriptor 0x28), BGRA.
function tga(name, img) {
    const head = Buffer.alloc(18);
    head[2] = 2;
    head.writeUInt16LE(img.w, 12);
    head.writeUInt16LE(img.h, 14);
    head[16] = 32;
    head[17] = 0x28;
    const body = Buffer.alloc(img.w * img.h * 4);
    for (let i = 0; i < img.w * img.h; i++) {
        const k = i * 4, clamp = (v) => Math.max(0, Math.min(255, Math.round(v)));
        body[k] = clamp(img.px[k + 2]);
        body[k + 1] = clamp(img.px[k + 1]);
        body[k + 2] = clamp(img.px[k]);
        body[k + 3] = clamp(img.px[k + 3] * 255);
    }
    fs.writeFileSync(path.join(OUT, name + ".tga"), Buffer.concat([head, body]));
}

// --- the palette
const GOLD_HI = [255, 226, 140], GOLD_LO = [150, 104, 38];
const WHITE = [255, 255, 255];
const goldV = (y0, y1) => vgrad(GOLD_HI, GOLD_LO, y0, y1);

const art = {};

// A pill: 32 x 16, round ends, sliced 3 ways (8-pixel ends). Filled white for tinting.
art.Pill = () => draw(32, 16, [{ shape: box(16, 8, 15.5, 7.5, 7.5), color: WHITE }]);
// The same, outlined.
art.PillLine = () => draw(32, 16, [
    { shape: box(16, 8, 15.5, 7.5, 7.5), color: [0, 0, 0, 0.45] },
    { shape: ring(box(16, 8, 15, 7, 7), 1.2), color: WHITE },
]);

// The Alliance's pennant: 64 x 128 (the Horde has the pack's banner_horde). The addon's icon is laid on it by the code.
art.Banner = () => {
    const P = [[6, 2], [58, 2], [58, 112], [32, 98], [6, 112]];
    const outer = poly(P), inner = grow(outer, -3);
    return draw(64, 128, [
        { glow: outer, width: 5, color: [0, 0, 0, 0.6] },
        { shape: outer, color: goldV(0, 112) },
        { shape: inner, color: vgrad([196, 40, 30], [110, 16, 14], 0, 110) },
        { shape: ring(grow(outer, -6), 1), color: [255, 180, 120, 0.25] },
    ]);
};

const outline = (shape, w = 1.6) => ({ shape: grow(shape, w), color: [0, 0, 0, 0.85] });

// A tip: an "i" in a blue disc, 32 x 32 (the pack has no icon for a tip).
art.Tip = () => {
    const disc = circle(16, 16, 11);
    const letter = union(circle(16, 10.5, 1.9), seg(16, 15, 16, 22, 1.6));
    return draw(32, 32, [outline(disc, 1), { shape: disc, color: [70, 130, 200] }, { shape: letter, color: WHITE }]);
};

fs.mkdirSync(OUT, { recursive: true });
for (const [name, make] of Object.entries(art)) {
    tga(name, make());
    console.log("Media/Guide/" + name + ".tga");
}
