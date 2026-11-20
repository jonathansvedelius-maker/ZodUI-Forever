// Draws Undead Route's art: the icon, Media/Icon.svg and Media/Icon.tga, and the arrow to the next step,
// Media/Arrow.svg and Media/Arrow.tga (pointing up; the game turns it).
// The icon: Media/Icon.svg (the source, to look at or edit) and Media/Icon.tga (64 x 64,
// 32-bit, what the game shows). WoW reads no SVG, so the same shapes are drawn here pixel by pixel with soft
// edges (distance to each shape, 4 x 4 samples a pixel). Run: node tools/icon.js
const fs = require("fs");
const path = require("path");

const S = 64; // the TGA's size; the SVG uses the same units
const C = S / 2;
// A winding road from the bottom left to the top right, ending at a map pin.
const ROAD = [[14, 50], [22, 46], [26, 38], [22, 30], [26, 22], [36, 20], [42, 26]];
const PIN = { x: 44, y: 18, r: 7.5, tip: [44, 31] };
const COLORS = {
    disc: [45, 33, 37], // WoW Forever's warm dark
    ring: [145, 110, 51], // bronze
    road: [255, 209, 0], // the game's yellow
    pin: [214, 64, 48], // red
    dot: [45, 33, 37],
};

// --- the SVG
const pts = ROAD.map(([x, y]) => `${x},${y}`).join(" ");
const hex = (c) => "#" + c.map((v) => v.toString(16).padStart(2, "0")).join("");
const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}" width="${S}" height="${S}">
  <circle cx="${C}" cy="${C}" r="29" fill="${hex(COLORS.disc)}" stroke="${hex(COLORS.ring)}" stroke-width="4"/>
  <polyline points="${pts}" fill="none" stroke="${hex(COLORS.road)}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="6 3.5"/>
  <path d="M${PIN.tip[0]},${PIN.tip[1]} L${PIN.x - PIN.r * 0.8},${PIN.y + 3} A${PIN.r},${PIN.r} 0 1 1 ${PIN.x + PIN.r * 0.8},${PIN.y + 3} Z" fill="${hex(COLORS.pin)}"/>
  <circle cx="${PIN.x}" cy="${PIN.y}" r="2.8" fill="${hex(COLORS.dot)}"/>
</svg>
`;

// --- the pixels
function segDist(px, py, ax, ay, bx, by) {
    const dx = bx - ax, dy = by - ay;
    const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)));
    return { d: Math.hypot(px - (ax + t * dx), py - (ay + t * dy)), t };
}
// Distance along the road of each corner, for the dashes.
const along = [0];
for (let i = 1; i < ROAD.length; i++) along[i] = along[i - 1] + Math.hypot(ROAD[i][0] - ROAD[i - 1][0], ROAD[i][1] - ROAD[i - 1][1]);
function onRoad(x, y) {
    let best = Infinity, at = 0;
    for (let i = 1; i < ROAD.length; i++) {
        const { d, t } = segDist(x, y, ROAD[i - 1][0], ROAD[i - 1][1], ROAD[i][0], ROAD[i][1]);
        if (d < best) { best = d; at = along[i - 1] + t * (along[i] - along[i - 1]); }
    }
    return best <= 2.25 && (at % 9.5) < 6; // 6 on, 3.5 off
}
function inPin(x, y) {
    if (Math.hypot(x - PIN.x, y - PIN.y) <= PIN.r) return true;
    // The point under the head: a triangle from the head's sides to the tip.
    const [tx, ty] = PIN.tip;
    if (y < PIN.y || y > ty) return false;
    const half = PIN.r * 0.8 * (ty - y) / (ty - PIN.y - 3);
    return Math.abs(x - PIN.x) <= half;
}
function colorAt(x, y) {
    const r = Math.hypot(x - C, y - C);
    if (r > 31) return null;
    if (Math.hypot(x - PIN.x, y - PIN.y) <= 2.8) return COLORS.dot;
    if (inPin(x, y)) return COLORS.pin;
    if (onRoad(x, y)) return COLORS.road;
    if (r > 27) return COLORS.ring;
    return COLORS.disc;
}

const N = 4;
const px = Buffer.alloc(S * S * 4);
for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
        let r = 0, g = 0, b = 0, a = 0;
        for (let sy = 0; sy < N; sy++) {
            for (let sx = 0; sx < N; sx++) {
                const c = colorAt(x + (sx + 0.5) / N, y + (sy + 0.5) / N);
                if (c) { r += c[0]; g += c[1]; b += c[2]; a++; }
            }
        }
        // TGA rows go bottom up, BGRA.
        const o = ((S - 1 - y) * S + x) * 4;
        px[o] = a ? Math.round(b / a) : 0;
        px[o + 1] = a ? Math.round(g / a) : 0;
        px[o + 2] = a ? Math.round(r / a) : 0;
        px[o + 3] = Math.round(255 * a / (N * N));
    }
}
const head = Buffer.alloc(18);
head[2] = 2; // uncompressed true colour
head.writeUInt16LE(S, 12);
head.writeUInt16LE(S, 14);
head[16] = 32;
head[17] = 8; // 8 bits of alpha, bottom-left origin

const media = path.join(__dirname, "..", "Media");
fs.mkdirSync(media, { recursive: true });
fs.writeFileSync(path.join(media, "Icon.svg"), svg);
fs.writeFileSync(path.join(media, "Icon.tga"), Buffer.concat([head, px]));
console.log("wrote Media/Icon.svg and Media/Icon.tga (" + S + " x " + S + ")");

// --- the arrow: a gold arrowhead pointing up, with a dark edge so it reads on snow and on grass alike.
const HEAD = [[32, 5], [56, 55], [32, 42], [8, 55]];
function inPoly(x, y, poly) {
    let inside = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        const [xi, yi] = poly[i], [xj, yj] = poly[j];
        if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
}
function edgeDist(x, y, poly) {
    let best = Infinity;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        best = Math.min(best, segDist(x, y, poly[j][0], poly[j][1], poly[i][0], poly[i][1]).d);
    }
    return best;
}
const GOLD = [255, 209, 0], DEEP = [214, 150, 0], EDGE = [40, 26, 10];
function arrowAt(x, y) {
    const inside = inPoly(x, y, HEAD), d = edgeDist(x, y, HEAD);
    if (!inside && d > 1.6) return null;
    if (d <= 1.6) return EDGE;
    return x < 32 ? GOLD : DEEP; // two faces, lit from the left
}
const ap = Buffer.alloc(S * S * 4);
for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
        let r = 0, g = 0, b = 0, a = 0;
        for (let sy = 0; sy < N; sy++) for (let sx = 0; sx < N; sx++) {
            const c = arrowAt(x + (sx + 0.5) / N, y + (sy + 0.5) / N);
            if (c) { r += c[0]; g += c[1]; b += c[2]; a++; }
        }
        const o = ((S - 1 - y) * S + x) * 4;
        ap[o] = a ? Math.round(b / a) : 0; ap[o + 1] = a ? Math.round(g / a) : 0; ap[o + 2] = a ? Math.round(r / a) : 0;
        ap[o + 3] = Math.round(255 * a / (N * N));
    }
}
const hp = HEAD.map(([x, y]) => x + "," + y).join(" ");
fs.writeFileSync(path.join(media, "Arrow.svg"), `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}" width="${S}" height="${S}">
  <polygon points="${hp}" fill="${hex(GOLD)}" stroke="${hex(EDGE)}" stroke-width="3" stroke-linejoin="round"/>
  <polygon points="32,5 56,55 32,42" fill="${hex(DEEP)}"/>
</svg>
`);
fs.writeFileSync(path.join(media, "Arrow.tga"), Buffer.concat([head, ap]));
console.log("wrote Media/Arrow.svg and Media/Arrow.tga (" + S + " x " + S + ")");
