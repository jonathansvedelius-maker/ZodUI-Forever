// Runs a Lua script in fengari with the remaining arguments in the global `arg`.
const fs = require("fs");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_newtable(L);
process.argv.slice(3).forEach((a, i) => {
    lua.lua_pushstring(L, to_luastring(a));
    lua.lua_rawseti(L, -2, i + 1);
});
lua.lua_setglobal(L, to_luastring("arg"));
lua.lua_pushcfunction(L, (S) => {
    lua.lua_pushstring(S, fs.readFileSync(to_jsstring(lua.lua_tostring(S, 1))));
    return 1;
});
lua.lua_setglobal(L, to_luastring("readfile"));
lua.lua_pushcfunction(L, (S) => {
    fs.writeFileSync(to_jsstring(lua.lua_tostring(S, 1)), Buffer.from(lua.lua_tostring(S, 2)));
    return 0;
});
lua.lua_setglobal(L, to_luastring("writefile"));
const code = fs.readFileSync(process.argv[2]);
if (lauxlib.luaL_loadbuffer(L, code, null, to_luastring("@" + process.argv[2])) !== lua.LUA_OK
    || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.log("ERROR: " + to_jsstring(lua.lua_tostring(L, -1)));
    process.exit(1);
}
