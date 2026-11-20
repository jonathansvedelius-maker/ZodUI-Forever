// Runs ZodUI outside the game: loads the files the .toc lists into a Lua VM with a
// stubbed WoW API (stub.lua) and drives them through test.lua.
//   node tools/run.js
// The Lua VM (fengari) is borrowed from Undead Route's tools when it is not installed here.
const fs = require("fs");
const path = require("path");

let fengari;
try {
    fengari = require("fengari");
} catch (e) {
    fengari = require(path.join(__dirname, "..", "..", "UndeadRoute", "tools", "node_modules", "fengari"));
}
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const addonDir = path.resolve(__dirname, "..");
const tocName = fs.readdirSync(addonDir).find((f) => f.toLowerCase().endsWith(".toc"));
const files = fs.readFileSync(path.join(addonDir, tocName), "utf8").split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"))
    .map((line) => line.replace(/\\/g, "/"));

// Syntax the game's Lua 5.1 does not have but this VM (5.3) would accept.
let bad = 0;
for (const file of files) {
    const lines = fs.readFileSync(path.join(addonDir, file), "utf8").split(/\r?\n/);
    lines.forEach((line, i) => {
        const code = line.replace(/--.*$/, "").replace(/"(?:[^"\\]|\\.)*"/g, '""');
        if (/\/\/|<<|>>|\bgoto\b|[^=~<>]&[^&]|::\w+::/.test(code)) {
            console.log(`Lua 5.3 syntax in ${file}:${i + 1}: ${line.trim()}`);
            bad++;
        }
    });
}
if (bad) process.exit(1);

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function run(code, name) {
    if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring("@" + name)) !== lua.LUA_OK
        || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        console.log("ERROR in " + name + ": " + to_jsstring(lua.lua_tostring(L, -1)));
        process.exit(1);
    }
}

const quote = (file) => "[==========[" + fs.readFileSync(path.join(addonDir, file), "utf8") + "]==========]";
run("ADDON_FILES = {\n" + files.map((f) => `  { "${f}", ${quote(f)} },`).join("\n") + "\n}", "files");
run(fs.readFileSync(path.join(__dirname, "stub.lua"), "utf8"), "stub.lua");
const script = process.argv.includes("--bench") ? "bench.lua" : "test.lua";
run(fs.readFileSync(path.join(__dirname, script), "utf8"), script);
