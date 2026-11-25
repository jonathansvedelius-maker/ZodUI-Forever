// Loads the addon in a Lua VM with a stubbed WoW API and drives it.
// harness.lua (an Undead Paladin, the window and the reminders) and races.lua (every race and
// faction) each run in a Lua state of their own.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const dir = process.argv[2];
const quote = (file) => () => "[==========[" + fs.readFileSync(path.join(dir, file), "utf8") + "]==========]";

for (const script of ["harness.lua", "races.lua"]) {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    const code = fs.readFileSync(path.join(__dirname, script), "utf8")
        .replace("@DATA@", quote("Data.lua"))
        .replace("@GEN@", quote("Generated.lua"))
        .replace("@BUILD@", quote("Build.lua"))
        .replace("@REC@", quote("Recorded.lua"))
        .replace("@RECORDER@", quote("Recorder.lua"))
        .replace("@MOTION@", quote("Motion.lua"))
        .replace("@ROUTE@", quote("Route.lua"))
        .replace("@WINDOW@", quote("Window.lua"))
        .replace("@GUIDE@", quote("Guide.lua"))
        .replace("@CORE@", quote("Core.lua"));
    if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(script)) !== lua.LUA_OK
        || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
        console.log("ERROR in " + script + ": " + to_jsstring(lua.lua_tostring(L, -1)));
        process.exit(1);
    }
}
