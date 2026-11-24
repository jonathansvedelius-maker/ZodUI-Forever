// Serves the browser preview: the addon's Lua files (read fresh on every request, so
// F5 shows your latest edit), the game's own fonts, and the Lua VM for the browser.
//   node preview/server.js        then open http://localhost:8377
// It shows the addon it lives in. ADDON_DIR points it at another addon, PORT at another port:
//   ADDON_DIR=../ZodUI PORT=8378 node preview/server.js
// Such an addon can bring tools/preview-env.lua (game functions the preview lacks) and name
// the command that opens it in its .toc: ## X-Preview-Start: /zod
const http = require("http");
const fs = require("fs");
const path = require("path");

const ownDir = path.resolve(__dirname, "..", "..");
const addonDir = process.env.ADDON_DIR ? path.resolve(process.env.ADDON_DIR) : ownDir;
const gameDir = path.resolve(ownDir, "..", "..", "..");
const port = Number(process.env.PORT) || 8377;

const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
    ".lua": "text/plain; charset=utf-8", ".json": "application/json; charset=utf-8", ".ttf": "font/ttf" };

// The .toc decides which files load and in what order, as in the game.
function toc() {
    const name = fs.readdirSync(addonDir).find((f) => f.toLowerCase().endsWith(".toc"));
    const info = { addon: path.basename(name, path.extname(name)), files: [], title: "", version: "", saved: [], start: "" };
    for (const raw of fs.readFileSync(path.join(addonDir, name), "utf8").split(/\r?\n/)) {
        const line = raw.trim();
        const meta = line.match(/^##\s*([\w-]+)\s*:\s*(.*)$/);
        if (meta) {
            if (meta[1] === "Title") info.title = meta[2].replace(/\|c[0-9a-fA-F]{8}|\|r/g, "");
            if (meta[1] === "X-Preview-Start") info.start = meta[2];
            if (/^SavedVariables(PerCharacter)?$/.test(meta[1])) {
                info.saved.push(...meta[2].split(",").map((s) => s.trim()).filter(Boolean));
            }
            if (meta[1] === "Version") info.version = meta[2];
        } else if (line && !line.startsWith("#")) {
            info.files.push(line.replace(/\\/g, "/"));
        }
    }
    // The tests' local quest list (Generated.lua, never shipped) stands in for what Build.lua makes at login from
    // the quest addons, which the browser has not got: loaded right after Build.lua, as tools/harness.lua does.
    const build = info.files.indexOf("Build.lua");
    if (build >= 0 && fs.existsSync(path.join(addonDir, "Generated.lua"))) info.files.splice(build + 1, 0, "Generated.lua");
    return info;
}

// The game's textures are TGA, which no browser shows: an uncompressed 24/32-bit one is handed out as a PNG.
const zlib = require("zlib");
const CRC = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
});
function crc32(buf) {
    let c = 0xffffffff;
    for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
    const len = Buffer.alloc(4), crc = Buffer.alloc(4), td = Buffer.concat([Buffer.from(type), data]);
    len.writeUInt32BE(data.length);
    crc.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, crc]);
}
function tgaToPng(tga) {
    const idLen = tga[0], type = tga[2], w = tga.readUInt16LE(12), h = tga.readUInt16LE(14), bpp = tga[16], desc = tga[17];
    if (type !== 2 || (bpp !== 32 && bpp !== 24)) throw new Error("only uncompressed 24/32-bit TGA is shown");
    const top = (desc & 0x20) !== 0, step = bpp / 8, start = 18 + idLen;
    const raw = Buffer.alloc((w * 4 + 1) * h);
    for (let y = 0; y < h; y++) {
        const sy = top ? y : h - 1 - y;
        raw[y * (w * 4 + 1)] = 0;
        for (let x = 0; x < w; x++) {
            const s = start + (sy * w + x) * step, d = y * (w * 4 + 1) + 1 + x * 4;
            raw[d] = tga[s + 2]; raw[d + 1] = tga[s + 1]; raw[d + 2] = tga[s]; raw[d + 3] = step === 4 ? tga[s + 3] : 255;
        }
    }
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
    ihdr[8] = 8; ihdr[9] = 6;
    return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr),
        chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

function send(res, status, body, type) {
    res.writeHead(status, { "Content-Type": type || "text/plain; charset=utf-8", "Cache-Control": "no-store" });
    res.end(body);
}

function file(res, full) {
    fs.readFile(full, (err, data) => {
        if (err) return send(res, 404, "Not found: " + path.basename(full));
        send(res, 200, data, TYPES[path.extname(full).toLowerCase()]);
    });
}

http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split("?")[0]);
    try {
        if (url === "/") return file(res, path.join(__dirname, "index.html"));
        if (url === "/wow.lua") return file(res, path.join(__dirname, "wow.lua"));
        if (url === "/fengari-web.js") return file(res, path.join(path.dirname(require.resolve("fengari-web/package.json")), "dist", "fengari-web.js"));
        if (url === "/toc") return send(res, 200, JSON.stringify(toc()), TYPES[".json"]);
        if (url === "/env.lua") {
            const env = path.join(addonDir, "tools", "preview-env.lua");
            return send(res, 200, fs.existsSync(env) ? fs.readFileSync(env) : "");
        }
        if (url.startsWith("/addon/")) {
            const rel = url.slice(7);
            if (!toc().files.includes(rel)) return send(res, 404, "Not in the .toc: " + rel);
            return file(res, path.join(addonDir, rel));
        }
        // A texture of the addon's Media folder, by its path without extension: /media/Guide/Frame
        if (url.startsWith("/media/")) {
            const rel = url.slice(7).replace(/\.(tga|png)$/i, "");
            const media = path.join(addonDir, "Media");
            const full = path.resolve(media, rel + ".tga");
            if (!full.startsWith(media + path.sep) || !fs.existsSync(full)) return send(res, 404, "No texture: " + rel);
            return send(res, 200, tgaToPng(fs.readFileSync(full)), "image/png");
        }
        if (url.startsWith("/fonts/")) {
            const name = path.basename(url);
            if (!/^[\w.-]+\.ttf$/i.test(name)) return send(res, 404, "Not a font");
            return file(res, path.join(gameDir, "Fonts", name));
        }
        send(res, 404, "Not found");
    } catch (e) {
        send(res, 500, String(e && e.stack || e));
    }
}).listen(port, "127.0.0.1", () => {
    console.log(toc().title + " preview: http://localhost:" + port);
});
