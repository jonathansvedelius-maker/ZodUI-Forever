// Prints the Dungeon guide routes (Modules\GuideData.lua) as JSON, for tools/trace_routes.py.
//   node tools/dumpguides.js > guides.json
const fs = require("fs");
const path = require("path");

let fengari;
try {
    fengari = require("fengari");
} catch (e) {
    fengari = require(path.join(__dirname, "..", "..", "UndeadRoute", "tools", "node_modules", "fengari"));
}
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const data = fs.readFileSync(path.join(__dirname, "..", "Modules", "GuideData.lua"), "utf8");
const code = `
local ns = {}
local chunk = assert(load(${JSON.stringify("return function(...) " + "\n" + data + "\nend")}))()
chunk("ZodUI", ns)
local function enc(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v):gsub("\\\\\\n", "\\\\n") end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t ~= "table" then return "null" end
    if #v > 0 or next(v) == nil then
        local parts = {}
        for i = 1, #v do parts[i] = enc(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = string.format("%q", k) .. ":" .. enc(v[k] ~= nil and v[k] or v[tonumber(k)]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
OUT = enc(ns.GUIDES)
`;
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.error(to_jsstring(lua.lua_tostring(L, -1)));
    process.exit(1);
}
lua.lua_getglobal(L, to_luastring("OUT"));
const out = JSON.parse(to_jsstring(lua.lua_tostring(L, -1)));
process.stdout.write(JSON.stringify(out, null, 1));
