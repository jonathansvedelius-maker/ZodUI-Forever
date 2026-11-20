-- Merges quest recordings (the account-wide SavedVariables file UndeadRoute.lua of each player) into Recorded.lua,
-- Undead Route's own quest data, and says how much of the generated data the recordings now cover.
--   node tools/record.js            (finds yours under the game's WTF folder, and friends' in recordings/)
--   node tools/lua.js tools/record.lua <Recorded.lua> <Generated.lua> <file> [<file> ...]
local out, genPath = arg[1], arg[2]
assert(out and genPath and arg[3], "usage: record.lua <Recorded.lua> <Generated.lua> <UndeadRoute.lua> [...]")

-- Places from several players: averaged when on the same map as the first, else the first kept.
local function AddPlace(sum, p)
    if type(p) ~= "table" or not p[1] then return sum end
    if not sum then return { p[1], p[2], p[3], p[4], n = 1 } end
    if sum[1] ~= p[1] then return sum end
    sum[2], sum[3], sum.n = sum[2] + p[2], sum[3] + p[3], sum.n + 1
    sum[4] = sum[4] or p[4]
    return sum
end
local function Place(sum)
    if not sum then return end
    local r = function(v) return math.floor(v / sum.n * 10 + 0.5) / 10 end
    return { sum[1], r(sum[2]), r(sum[3]), sum[4] }
end

local merged, files, quests = {}, 0, 0
local places = {} -- id -> { pick = sum, turnin = sum }
for i = 3, #arg do
    UndeadRouteRecordDB = nil
    local text = readfile(arg[i])
    local fn = load(text, "@" .. arg[i], "t", setmetatable({}, { __index = _G, __newindex = function(_, k, v)
        if k == "UndeadRouteRecordDB" then UndeadRouteRecordDB = v end -- other saved tables are ignored
    end }))
    local ok = fn and pcall(fn)
    local store = ok and type(UndeadRouteRecordDB) == "table" and UndeadRouteRecordDB.quests
    if type(store) ~= "table" then
        print("skipped (no recordings in it): " .. arg[i])
    else
        files = files + 1
        for id, q in pairs(store) do
            id = tonumber(id)
            if id and type(q) == "table" then
                quests = quests + 1
                local m = merged[id]
                if not m then
                    m = { seen = 0, sides = {}, races = {}, classes = {} }
                    merged[id] = m
                    places[id] = {}
                end
                m.seen = m.seen + (tonumber(q.seen) or 0)
                m.done = (m.done or 0) + (tonumber(q.done) or 0)
                if m.done == 0 then m.done = nil end
                if type(q.name) == "string" then m.name = m.name or q.name end
                if type(q.lv) == "number" then m.lv = math.max(m.lv or 0, q.lv) end
                if type(q.req) == "number" then m.req = math.min(m.req or 99, q.req) end
                if type(q.giver) == "string" then m.giver, m.item = m.giver or q.giver, nil
                elseif q.item and not m.giver then m.item = true end
                if type(q.ender) == "string" then m.ender = m.ender or q.ender end
                if type(q.xp) == "number" then m.xp = math.max(m.xp or 0, q.xp) end
                if type(q.rewards) == "table" and #q.rewards > #(m.rewards or {}) then m.rewards = q.rewards end
                if type(q.obj) == "table" and not m.obj then m.obj = q.obj end
                for _, k in ipairs({ "sides", "races", "classes" }) do
                    for key in pairs(type(q[k]) == "table" and q[k] or {}) do m[k][key] = true end
                end
                places[id].pick = AddPlace(places[id].pick, q.pick)
                places[id].turnin = AddPlace(places[id].turnin, q.turnin)
                local s = q.spot
                if type(s) == "table" and s[1] and (s[4] or 0) > 0 then
                    if not m.spot then m.spot = { s[1], 0, 0, 0 } end
                    if m.spot[1] == s[1] then
                        m.spot[2], m.spot[3], m.spot[4] = m.spot[2] + s[2], m.spot[3] + s[3], m.spot[4] + s[4]
                    end
                end
            end
        end
    end
end
for id, m in pairs(merged) do
    m.pick, m.turnin = Place(places[id].pick), Place(places[id].turnin)
    if m.spot then -- kept as an average with a weight of 1: smaller, and the same to Recorder.lua
        local n = m.spot[4]
        m.spot = { m.spot[1], math.floor(m.spot[2] / n * 10 + 0.5) / 10, math.floor(m.spot[3] / n * 10 + 0.5) / 10, 1 }
    end
end

---------------------------------------------------------------------------
-- Writing it, keys in order so a new recording changes only its own lines
---------------------------------------------------------------------------
local function ser(v)
    local t = type(v)
    if t == "string" then return (string.format("%q", v):gsub("\\\n", "\\n")) end
    if t == "number" then
        if v == math.floor(v) then return string.format("%d", v) end
        return (string.format("%.1f", v):gsub("%.0$", ""))
    end
    if t ~= "table" then return tostring(v) end
    local parts, n = {}, #v
    for i = 1, n do parts[#parts + 1] = ser(v[i]) end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    for _, k in ipairs(keys) do
        local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. ser(k) .. "]")
        parts[#parts + 1] = key .. " = " .. ser(v[k])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local ids = {}
for id in pairs(merged) do ids[#ids + 1] = id end
table.sort(ids)
local lines = {
    "local _, ns = ...",
    "",
    "-- Undead Route's own quest data, recorded in the game by Recorder.lua and merged by tools/record.lua",
    "-- (" .. files .. " recording file" .. (files == 1 and "" or "s") .. ", " .. #ids .. " quests). Recorder.lua lays it over Generated.lua.",
    "-- quest: name, lv, req (lowest level seen taking it), giver or item, pick / turnin { map, x, y, zone }, ender,",
    "--   spot { map, x, y, 1 } (where its objectives moved on), rewards { itemId, name, quality }, xp, obj (objective texts),",
    "--   sides / races / classes (who has taken it), seen / done (how often)",
    "ns.Recorded = {",
}
for _, id in ipairs(ids) do lines[#lines + 1] = "    [" .. id .. "] = " .. ser(merged[id]) .. "," end
lines[#lines + 1] = "}"
writefile(out, table.concat(lines, "\n") .. "\n")
print(string.format("%d file(s), %d recordings, %d quests -> %s", files, quests, #ids, out))

---------------------------------------------------------------------------
-- How much of the generated data is now covered
---------------------------------------------------------------------------
local ns = {}
assert(load(readfile(genPath), "@Generated.lua"))("UndeadRoute", ns)
local total, withPick, withTurnin, full = 0, 0, 0, 0
local zones = {}
for map, list in pairs(ns.ZoneQuests or {}) do
    local z = { map = map, n = #list, full = 0 }
    for _, q in ipairs(list) do
        z.name = z.name or q.zone
        total = total + 1
        local m = merged[q.id]
        if m and m.pick then withPick = withPick + 1 end
        if m and m.turnin then withTurnin = withTurnin + 1 end
        if m and m.pick and m.turnin then full = full + 1 z.full = z.full + 1 end
    end
    zones[#zones + 1] = z
end
local new = 0
local known = {}
for _, list in pairs(ns.ZoneQuests or {}) do for _, q in ipairs(list) do known[q.id] = true end end
for _, list in pairs(ns.ClassQuests or {}) do for _, q in ipairs(list) do known[q.id] = true end end
for _, d in ipairs(ns.Dungeons or {}) do for _, q in ipairs(d.quests) do known[q.id] = true end end
for _, id in ipairs(ids) do if not known[id] then new = new + 1 end end
print(string.format("zone quests: %d generated, %d with a recorded giver's place, %d with a recorded hand-in, %d with both (%.0f%%)",
    total, withPick, withTurnin, full, total > 0 and 100 * full / total or 0))
print(string.format("%d recorded quests the generated data does not have", new))
table.sort(zones, function(a, b) return a.full / math.max(1, a.n) > b.full / math.max(1, b.n) end)
for i = 1, math.min(12, #zones) do
    local z = zones[i]
    if z.full == 0 then break end
    print(string.format("  %-28s %3d of %3d recorded", z.name or tostring(z.map), z.full, z.n))
end
