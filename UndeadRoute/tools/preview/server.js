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
    return info;
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
