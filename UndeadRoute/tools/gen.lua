-- Builds UndeadRoute/Generated.lua, the TESTS' copy of the quest lists, from the quest data of addons installed
-- on this machine. The game builds the same lists at login (Build.lua, ns.BuildQuests, the same code), so
-- Generated.lua is never shipped: it is not in the .toc and git ignores it. It adds ForeverLevelingBiS's reward items,
-- which the game takes from the quest recorder instead. Run: node tools/lua.js tools/gen.lua <AddOns folder> Generated.lua
-- Sources:
--   ForeverDB                    every quest: class and race limits, giver, prerequisites, hand-in, objectives (needed)
--   ForeverLevelingBiS           quest reward items and their quality                                           (optional)
--   ForeverDungeonJournal        objectives and required items of class quest chains                            (optional)
-- Quests of both factions and every race and class are kept, each tagged with who may take it
-- (side, race and class masks); Route.lua keeps this character's at login.
local root, out = arg[1], arg[2]

-- ForeverDB's files, in its .toc's order, fill _G.ForeverDB.
local toc = assert(readfile(root .. "/ForeverDB/ForeverDB.toc"), "ForeverDB is not installed in " .. root)
for file in toc:gmatch("[^\r\n]+") do
    if file:match("^[%w_]+%.lua$") then assert(load(assert(readfile(root .. "/ForeverDB/" .. file)), file))() end
end
print("ForeverDB " .. tostring(ForeverDB.meta and ForeverDB.meta.build))

local flb = { language = {}, Quests = {}, Items = {} }
for _, f in ipairs({ "Quests.lua", "Items.lua", "Tables.lua", "Zones.lua" }) do
    local text = readfile(root .. "/ForeverLevelingBiS/Data/" .. f)
    if text then assert(load(text))("x", flb) else print("ForeverLevelingBiS: no " .. f .. ", left out") end
end

-- QuestUpdates.lua is a run of "-- BEGIN name ... -- END name" blocks, each a do-block. Each block is
-- loaded on its own, so one that needs the game (frames, events) loses only itself. Only FDJ's
-- fields are made up on the fly; any other missing global is an error, which skips that block.
local FDJ = setmetatable({}, { __index = function(t, k) local v = {} rawset(t, k, v) return v end }) -- one level deep only
local fdjText = readfile(root .. "/ForeverDungeonJournal/Data/QuestUpdates.lua") or ""
if fdjText == "" then print("ForeverDungeonJournal: not installed, left out") end
local env = setmetatable({ FDJ = FDJ, ForeverDungeonJournal = FDJ }, { __index = _G })
local fdjOk, fdjBad, pos = 0, {}, 1
local head = fdjText:find("\n%-%- BEGIN ") or #fdjText
local chunks = { { "header", fdjText:sub(1, head) } }
for name, body in fdjText:gmatch("\n%-%- BEGIN ([%w_]+)\n(.-)\n%-%- END ") do chunks[#chunks + 1] = { name, body } end
for _, chunk in ipairs(chunks) do
    local fn = load(chunk[1] == "header" and chunk[2] or ("local ADDON_NAME, FDJ = ...\n" .. chunk[2]), chunk[1], "t", env)
    local done = fn and pcall(fn, "x", FDJ)
    if done then fdjOk = fdjOk + 1 else fdjBad[#fdjBad + 1] = chunk[1] end
end
print(string.format("ForeverDungeonJournal details: %d blocks loaded, %d skipped (%s)", fdjOk, #fdjBad, table.concat(fdjBad, ", ")))
local Details = rawget(FDJ, "QUEST_PREREQ_DETAILS") or {}

-- Reward items of a quest worth showing: green and better, as { id, name, quality }.
local function Rewards(id)
    local q, list = flb.Quests[id], {}
    local r = q and q.rewards or {}
    for _, group in ipairs({ r.choices or {}, r.items or {} }) do
        for _, item in ipairs(group) do
            local it = flb.Items[item]
            if it and (it.quality or 0) >= 2 then list[#list + 1] = { item, it.name, it.quality } end
        end
    end
    return list
end

-- The route's stages (Data.lua), for which maps to keep, and the builder (Build.lua) itself.
local addon = out:gsub("[^/\\]*$", "")
local ns = {}
assert(load(readfile(addon .. "Data.lua"), "Data.lua"))("x", ns)
assert(load(readfile(addon .. "Build.lua"), "Build.lua"))("x", ns)
if not next(flb.Quests) then Rewards = ns.ForeverDBRewards(ForeverDB) print("rewards: ForeverDB's") end
local t0 = os.clock()
local J, D, Spots, own = ns.FromForeverDB(ForeverDB, ns.Stages)
for id, det in pairs(Details) do own[id] = det end -- ForeverDungeonJournal's win where it has a quest
Details = own
print(string.format("ForeverDB read in %.1f s", os.clock() - t0))
local dungeons, classQuests, zoneQuests, needLimit, log, mapOrder = ns.BuildQuests({
    J = J, D = D, Spots = Spots, Details = Details, Rewards = Rewards, chains = flb.QuestChains,
}, ns.Stages)
for _, line in ipairs(log) do print(line) end
local mapName = {}
for _, z in ipairs(D.Zones) do mapName[z.map] = z.name end
local empty = {}
for _, map in ipairs(mapOrder) do if not zoneQuests[map] or #zoneQuests[map] == 0 then empty[#empty + 1] = map end end
assert(#empty == 0, "route maps with no quests: " .. table.concat(empty, ", "))

---------------------------------------------------------------------------
-- Serialising
---------------------------------------------------------------------------
local function ser(v)
    local t = type(v)
    if t == "string" then return (string.format("%q", v):gsub("\\\n", "\\n")) end
    if t == "number" and v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%.0f", v) end
    if t ~= "table" then return tostring(v) end
    local parts, n = {}, #v
    for i = 1, n do parts[#parts + 1] = ser(v[i]) end
    local keys = {}
    for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        parts[#parts + 1] = (type(k) == "string" and k or ("[" .. ser(k) .. "]")) .. " = " .. ser(v[k])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local lines = {
    "local _, ns = ...",
    "",
    "-- GENERATED on " .. os.date("%Y-%m-%d") .. " by tools/gen.lua for the TESTS, from the quest data of addons installed on",
    "-- this machine. Never shipped (not in the .toc, ignored by git): the game builds the same lists at login (Build.lua).",
    "ns.Dungeons = {",
}
for _, d in ipairs(dungeons) do
    lines[#lines + 1] = string.format("    { name = %q, min = %d, max = %d, quests = {", d.name, d.min, d.max)
    for _, q in ipairs(d.quests) do lines[#lines + 1] = "        " .. ser(q) .. "," end
    lines[#lines + 1] = "    } },"
end
lines[#lines + 1] = "}"
lines[#lines + 1] = ""
lines[#lines + 1] = "ns.ClassQuests = {"
local classOrder = {}
for cid in pairs(classQuests) do classOrder[#classOrder + 1] = cid end
table.sort(classOrder)
for _, cid in ipairs(classOrder) do
    lines[#lines + 1] = "    [" .. cid .. "] = { -- " .. ns.CLASS_NAMES[cid]
    for _, q in ipairs(classQuests[cid]) do lines[#lines + 1] = "        " .. ser(q) .. "," end
    lines[#lines + 1] = "    },"
end
lines[#lines + 1] = "}"
lines[#lines + 1] = ""
lines[#lines + 1] = "ns.ZoneQuests = {"
for _, map in ipairs(mapOrder) do
    if zoneQuests[map] then
        lines[#lines + 1] = "    [" .. map .. "] = { -- " .. mapName[map]
        for _, q in ipairs(zoneQuests[map]) do lines[#lines + 1] = "        " .. ser(q) .. "," end
        lines[#lines + 1] = "    },"
    end
end
lines[#lines + 1] = "}"
lines[#lines + 1] = ""
lines[#lines + 1] = "ns.NeedLimit = " .. ser(needLimit)
lines[#lines + 1] = ""
writefile(out, table.concat(lines, "\n"))
print("wrote " .. out)
