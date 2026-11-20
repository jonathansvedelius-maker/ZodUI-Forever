// Merges quest recordings into Recorded.lua: this machine's (every account under the game's WTF folder) and any
// friends sent, put in UndeadRoute/recordings/ (their WTF\Account\<account>\SavedVariables\UndeadRoute.lua, any name).
//   node tools/record.js [<WoW folder>]     default: C:\Games\World of Warcraft\_forever_
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const addon = path.join(__dirname, "..");
const wow = process.argv[2] || "C:\\Games\\World of Warcraft\\_forever_";
const files = [];
const accounts = path.join(wow, "WTF", "Account");
if (fs.existsSync(accounts)) {
    for (const account of fs.readdirSync(accounts)) {
        const f = path.join(accounts, account, "SavedVariables", "UndeadRoute.lua");
        if (fs.existsSync(f)) files.push(f);
    }
}
const friends = path.join(addon, "recordings");
if (fs.existsSync(friends)) {
    for (const f of fs.readdirSync(friends)) if (f.endsWith(".lua")) files.push(path.join(friends, f));
}
if (files.length === 0) {
    console.log("No recordings found: play with Undead Route 1.22 or later, log out (the game writes the file then), and run this again.");
    process.exit(1);
}
console.log("Recordings:\n  " + files.join("\n  "));
const out = execFileSync(process.execPath, [path.join(__dirname, "lua.js"), path.join(__dirname, "record.lua"),
    path.join(addon, "Recorded.lua"), path.join(addon, "Generated.lua"), ...files], { encoding: "utf8" });
process.stdout.write(out);
if (out.includes("ERROR")) process.exit(1);
