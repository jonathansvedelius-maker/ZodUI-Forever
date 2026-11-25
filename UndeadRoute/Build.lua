local _, ns = ...

-- The quest lists, built at login from the quest data of addons the player has installed, so none of their
-- data ships with Undead Route:
--   ForeverDB                    every quest: class and race limits, giver, prerequisites, hand-in, objectives'
--                                spots (loaded on demand; ns.FromForeverDB turns it into the tables below)
--   ForeverDungeonJournal        objectives and required items of class quest chains, dungeon rewards (optional)
-- Quests of both factions and every race and class are kept, each tagged with who may take it (side, race
-- and class masks); Route.lua keeps this character's at login. Reward items: ForeverDungeonJournal's, else
-- ForeverDB's, with the quest recorder's laid over them.
--
-- ns.BuildQuests(src, stages) is the builder itself; tools/gen.lua runs the same one on the files, for the tests.
-- It makes:
-- ns.Dungeons: every dungeon below 60 with quests.
--   quest: id, name, lv, where (pickup), map / x / y (pickup pin), inside (starts in the dungeon),
--   pre (has a prerequisite chain), side ("A" / "H" when limited), class / race (bit masks, when limited), rewards
-- ns.ClassQuests[classId]: each class's quests for every race and side, prerequisites first.
--   quest: id, name, lv, req (level needed), giver, zone, map / x / y, needs (quest ids), turnin { map, x, y, zone },
--   side, race (bit mask), class (when other classes share it), objective, items { name, source }, rewards,
--   dungeon, classic (an old level 60 set turn-in)
-- ns.ZoneQuests[mapId]: the quests of each zone on any route, both factions, by level, prerequisites first.
--   quest: id, name, lv, req, giver, zone / map / x / y (pickup), item (starts from an item), side, race / class,
--   needs (quest ids; a list inside means any one of them), closed (quests that close it), turnin, rewards,
--   spot { x, y } (middle of its objectives in the zone), part (its number among the zone's quests of the same
--   name; { A = n, H = m } when the sides count differently)
-- ns.NeedLimit[questId]: who may take a prerequisite not everyone can; for anyone else it does not count.

local CLASS_NAMES = { [1] = "Warrior", [2] = "Paladin", [3] = "Hunter", [4] = "Rogue", [5] = "Priest",
    [7] = "Shaman", [8] = "Mage", [9] = "Warlock", [11] = "Druid" }
ns.CLASS_NAMES = CLASS_NAMES

local function bit(mask, n) -- is bit n (1 = lowest) set?
    return mask and mask > 0 and math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

-- The side ("A" / "H") a quest is limited to, if any. D.Quests side: 1 Alliance, 2 Horde, 3 both.
local function Side(q)
    return (q[4] == 1 and "A") or (q[4] == 2 and "H") or nil
end

-- src: J (dungeons), D (quests, zones, prerequisites, filters), Spots (hand-ins and objective camps), all three as
-- ns.FromForeverDB makes them,
-- Details (ForeverDungeonJournal's QUEST_PREREQ_DETAILS, may be empty), Rewards (function(id) -> list, optional),
-- chains (lists of { id } steps, optional). stages: every route stage (Data.lua), for which maps to keep.
-- Returns dungeons, classQuests, zoneQuests, needLimit, and a log: lines saying what was built.
function ns.BuildQuests(src, stages)
    local J, D, Spots, Details = src.J, src.D, src.Spots or {}, src.Details or {}
    local Rewards = src.Rewards or function() return {} end
    local log = {}
    local function say(...) log[#log + 1] = string.format(...) end

    local mapName = {}
    for _, z in ipairs(D.Zones) do mapName[z.map] = z.name end

    -------------------------------------------------------------------------
    -- Dungeons
    -------------------------------------------------------------------------
    local dungeons, nq = {}, 0
    for _, d in ipairs(J and J.QuestData or {}) do
        if d.levels[1] < 60 then
            local quests = {}
            for _, q in ipairs(d.quests) do
                local id, name, lv, side, flag, where, map, x, y = q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8], q[9]
                local info = D.Quests[id]
                local e = { id = id, name = name, lv = lv, where = where, map = map, x = x, y = y }
                if side == "H" or side == "A" then e.side = side end
                -- flag is whether the quest can be shared, or "pre" (it has prerequisites).
                -- A quest with no pickup spot on a zone map starts inside the dungeon or from a drop.
                if not map then e.inside = true end
                if flag == "pre" then e.pre = true end
                if info and info[5] and info[5] > 0 then e.race = info[5] end
                if info and info[6] and info[6] > 0 then e.class = info[6] end
                local rew = Rewards(id)
                if #rew > 0 then e.rewards = rew end
                quests[#quests + 1] = e
                nq = nq + 1
            end
            if #quests > 0 then
                dungeons[#dungeons + 1] = { name = d.name, min = d.levels[1], max = d.levels[2], quests = quests }
            end
        end
    end
    say("%d dungeons, %d quests (both factions)", #dungeons, nq)

    -------------------------------------------------------------------------
    -- Class quests: every class, for every race and both factions, prerequisites first
    -------------------------------------------------------------------------
    local classOrder = {}
    for cid in pairs(CLASS_NAMES) do classOrder[#classOrder + 1] = cid end
    table.sort(classOrder)

    -- Chain steps the prerequisite table leaves out: each step needs the one before it.
    local chainNeeds = { [95140] = 95126 }
    for _, chain in pairs(src.chains or {}) do
        for step = 2, #chain do
            local id, prev = chain[step] and chain[step][1], chain[step - 1] and chain[step - 1][1]
            local q, qp = id and D.Quests[id], prev and D.Quests[prev]
            if q and qp and q[6] > 0 and qp[6] > 0 then chainNeeds[id] = prev end
        end
    end

    -- A class quest is one only one or two classes can take. A wider mask ("every class but the Warlock")
    -- marks a zone quest with a class twin: it stays in the zone lists, with its class mask.
    -- Worked out once for each mask: there are a few dozen masks and thousands of quests.
    local only = {}
    local function ClassOnly(mask)
        local v = only[mask]
        if v == nil then
            local n = 0
            for _, cid in ipairs(classOrder) do if bit(mask, cid) then n = n + 1 end end
            v = mask > 0 and n <= 2
            only[mask] = v
        end
        return v
    end

    -- Each class's quests, from one pass over every quest (one pass per class was most of the build's time).
    local idsOf, inSetOf = {}, {}
    for _, cid in ipairs(classOrder) do idsOf[cid], inSetOf[cid] = {}, {} end
    for id, q in pairs(D.Quests) do
        -- { name, level, reqLevel, side, raceMask, classMask, map, x, y, giver }
        local mask = q[6]
        if ClassOnly(mask) then
            for _, cid in ipairs(classOrder) do
                if bit(mask, cid) then
                    local ids = idsOf[cid]
                    ids[#ids + 1] = id
                    inSetOf[cid][id] = true
                end
            end
        end
    end

    local classQuests = {}
    for _, cid in ipairs(classOrder) do
        local ids, inSet = idsOf[cid], inSetOf[cid]
        table.sort(ids, function(a, b)
            local qa, qb = D.Quests[a], D.Quests[b]
            if qa[3] ~= qb[3] then return qa[3] < qb[3] end
            if qa[2] ~= qb[2] then return qa[2] < qb[2] end
            return a < b
        end)
        local placed, order = {}, {}
        local function place(id)
            if placed[id] then return end
            placed[id] = true
            for _, pre in ipairs(D.Requires[id] or {}) do
                if type(pre) == "number" and inSet[pre] then place(pre) end
            end
            if chainNeeds[id] and inSet[chainNeeds[id]] then place(chainNeeds[id]) end
            order[#order + 1] = id
        end
        for _, id in ipairs(ids) do place(id) end
        local list = {}
        for _, id in ipairs(order) do
            local q, det, spot = D.Quests[id], rawget(Details, id), Spots[id]
            local e = { id = id, name = q[1], lv = q[2], req = q[3], giver = q[10], map = q[7], x = q[8], y = q[9],
                zone = mapName[q[7]], side = Side(q) }
            if q[5] > 0 then e.race = q[5] end
            if q[6] ~= 2 ^ (cid - 1) then e.class = q[6] end -- shared with other classes
            if D.Dungeon[id] then e.dungeon = true end
            if D.Repeatable[id] then e.repeatable = true end
            local needs = {}
            for _, pre in ipairs(D.Requires[id] or {}) do needs[#needs + 1] = pre end
            if #needs == 0 and chainNeeds[id] and inSet[chainNeeds[id]] then needs[1] = chainNeeds[id] end
            if #needs > 0 then e.needs = needs end
            if id < 20000 and q[3] >= 60 then e.classic = true end -- an old level 60 set turn-in
            if spot and spot[1] and spot[1][1] then e.turnin = { spot[1][1], spot[1][2], spot[1][3], mapName[spot[1][1]] } end
            if type(det) == "table" then
                if type(rawget(det, "objective")) == "string" then e.objective = det.objective end
                local items = rawget(det, "requiredItems")
                if type(items) == "table" then
                    e.items = {}
                    for _, it in ipairs(items) do e.items[#e.items + 1] = { it[2], it[4] } end
                end
            end
            local rew = Rewards(id)
            if #rew > 0 then e.rewards = rew end
            list[#list + 1] = e
        end
        classQuests[cid] = list
        say("  class %-8s %3d quests", CLASS_NAMES[cid], #list)
    end

    -------------------------------------------------------------------------
    -- Zone quests: the quests of every map a route stage names (stage.maps in Data.lua), both factions
    -------------------------------------------------------------------------
    local wanted, mapOrder = {}, {}
    for _, stage in ipairs(stages) do -- every faction's and race's stages
        for _, map in ipairs(stage.maps or {}) do
            if not wanted[map] then wanted[map] = true mapOrder[#mapOrder + 1] = map end
        end
    end

    -- What closes a quest, as the source addon works it out: the other quests of its
    -- exclusive group, the quest a breadcrumb leads to, any quest that needs it, and ClosedBy.
    local closers = {}
    local function AddCloser(id, other)
        if not D.Quests[other] then return end
        closers[id] = closers[id] or {}
        for _, have in ipairs(closers[id]) do if have == other then return end end
        table.insert(closers[id], other)
    end
    local groupOf = {}
    for _, group in ipairs(D.Exclusive or {}) do
        for _, id in ipairs(group) do
            groupOf[id] = group
            for _, other in ipairs(group) do if other ~= id then AddCloser(id, other) end end
        end
    end
    for id, target in pairs(D.Breadcrumb or {}) do
        AddCloser(id, target)
        for _, other in ipairs(groupOf[target] or {}) do if other ~= target then AddCloser(id, other) end end
    end
    for id, elements in pairs(D.Requires) do
        for _, element in ipairs(elements) do
            if type(element) == "table" then
                for _, before in ipairs(element) do AddCloser(before, id) end
            else
                AddCloser(element, id)
            end
        end
    end
    for id, others in pairs(D.ClosedBy or {}) do for _, other in ipairs(others) do AddCloser(id, other) end end
    for id, other in pairs(D.Until or {}) do AddCloser(id, other) end

    -- Prerequisites: a number must be done; a list means any one of them. A prerequisite only some
    -- characters can take goes in needLimit, so it is left out for everyone else.
    local needLimit = {}
    local function Needs(id)
        local list = {}
        for _, element in ipairs(D.Requires[id] or {}) do
            if type(element) == "table" then
                if #element == 1 then list[#list + 1] = element[1] elseif #element > 1 then list[#list + 1] = element end
            else
                list[#list + 1] = element
            end
        end
        for _, element in ipairs(list) do
            for _, other in ipairs(type(element) == "table" and element or { element }) do
                local q = D.Quests[other]
                if q and (q[6] > 0 or q[5] > 0 or Side(q)) then
                    needLimit[other] = { side = Side(q), race = q[5] > 0 and q[5] or nil, class = q[6] > 0 and q[6] or nil }
                end
            end
        end
        return list
    end

    local none = {}
    local zoneQuests, nz = {}, 0
    for _, zone in ipairs(D.Zones) do
        if wanted[zone.map] then
            local ids, inZone = {}, {}
            for _, id in ipairs(zone.quests) do
                local q = D.Quests[id]
                if q and not ClassOnly(q[6]) and not (D.Repeatable or none)[id] and not (D.Dungeon or none)[id]
                    and not (D.Battleground or none)[id] and not (D.Elsewhere or none)[id] and not (D.Profession or none)[id]
                    and not (D.Recipe or none)[id] and not (D.SkillRank or none)[id] and not (D.MinReputation or none)[id]
                    and not (D.MaxReputation or none)[id] and not (D.MaxLevel or none)[id] and q[2] >= 1
                    and not q[1]:find("^A Donation of ") then
                    ids[#ids + 1] = id
                    inZone[id] = true
                end
            end
            table.sort(ids, function(a, b)
                local qa, qb = D.Quests[a], D.Quests[b]
                if qa[2] ~= qb[2] then return qa[2] < qb[2] end
                local ga, gb = qa[10] or "", qb[10] or ""
                if ga ~= gb then return ga < gb end
                return a < b
            end)
            local seen, ordered = {}, {}
            local function put(id)
                if seen[id] then return end
                seen[id] = true
                for _, element in ipairs(D.Requires[id] or {}) do
                    for _, pre in ipairs(type(element) == "table" and element or { element }) do
                        if inZone[pre] then put(pre) end
                    end
                end
                ordered[#ordered + 1] = id
            end
            for _, id in ipairs(ids) do put(id) end
            local list = {}
            for _, id in ipairs(ordered) do
                local q, spot = D.Quests[id], Spots[id]
                local e = { id = id, name = q[1], lv = q[2], req = q[3], giver = q[10], map = q[7], x = q[8], y = q[9],
                    zone = mapName[q[7]], side = Side(q) }
                if q[5] > 0 then e.race = q[5] end
                if q[6] > 0 then e.class = q[6] end
                if q[11] then e.item = true end
                local needs = Needs(id)
                if #needs > 0 then e.needs = needs end
                if closers[id] then e.closed = closers[id] end
                if spot and spot[1] and spot[1][1] then e.turnin = { spot[1][1], spot[1][2], spot[1][3], mapName[spot[1][1]] } end
                -- Where the work is: the middle of the objective camps in this zone, and the camps themselves when
                -- there are more than one (the route walks to the nearest, and joins quests that share one).
                local sx, sy, sn, camps = 0, 0, 0, {}
                for _, camp in ipairs(spot and spot[2] or {}) do
                    if camp[1] == zone.map then
                        sx, sy, sn = sx + camp[2], sy + camp[3], sn + 1
                        camps[sn] = { camp[2], camp[3] }
                    end
                end
                if sn > 0 then e.spot = { math.floor(sx / sn * 10 + 0.5) / 10, math.floor(sy / sn * 10 + 0.5) / 10 } end
                if sn > 1 then e.camps = camps end
                local rew = Rewards(id)
                if #rew > 0 then e.rewards = rew end
                list[#list + 1] = e
            end
            -- Chain steps often share one name: number them in order, among the quests each side sees.
            -- A quest both sides see whose number differs by side gets part = { A = n, H = m }.
            local parts = {}
            for _, side in ipairs({ "A", "H" }) do
                local count, nth = {}, {}
                for _, e in ipairs(list) do
                    if e.side == nil or e.side == side then count[e.name] = (count[e.name] or 0) + 1 end
                end
                for _, e in ipairs(list) do
                    if (e.side == nil or e.side == side) and count[e.name] > 1 then
                        nth[e.name] = (nth[e.name] or 0) + 1
                        parts[e] = parts[e] or {}
                        parts[e][side] = nth[e.name]
                    end
                end
            end
            for _, e in ipairs(list) do
                local p = parts[e]
                if p then
                    if e.side then e.part = p[e.side]
                    elseif p.A and p.A == p.H then e.part = p.A
                    else e.part = p end
                end
            end
            zoneQuests[zone.map] = list
            nz = nz + #list
        end
    end
    local missing = 0
    for _, map in ipairs(mapOrder) do if not zoneQuests[map] then missing = missing + 1 end end
    say("%d zone quests on %d maps (%d route maps without data)", nz, #mapOrder - missing, missing)
    return dungeons, classQuests, zoneQuests, needLimit, log, mapOrder
end

---------------------------------------------------------------------------
-- ForeverDB -> the tables BuildQuests reads (D, Spots). ForeverDB's quest details (qx) are QuestieDB's:
-- 1 race mask, 2 class mask, 3 preQuestSingle (any one), 4 preQuestGroup (all), 5 exclusiveTo, 6 breadcrumbFor,
-- 8 creature, 9 object, 10 item objectives, 11 zoneOrSort, 13 specialFlags, 14 requiredSkill, 16 / 22 objective
-- spots, 19 requiredMinRep, 23 extra objective targets. Positions: spm (map spots, 0-1000) or spw (world yards).
---------------------------------------------------------------------------

-- Negative zoneOrSort: QuestieDB's quest sorts. A class's sort stands in for a missing class mask.
local SORT_CLASS = { [-81] = 1, [-141] = 2, [-261] = 3, [-162] = 4, [-262] = 5, [-82] = 7, [-161] = 8, [-61] = 9, [-263] = 11 }
local SORT_PROFESSION = { [-24] = true, [-101] = true, [-121] = true, [-181] = true, [-182] = true, [-201] = true,
    [-264] = true, [-304] = true, [-324] = true, [-666] = true } -- -666: WoW Forever's Camping
local SORT_ELSEWHERE = { [-1] = true, [-22] = true, [-284] = true, [-344] = true, [-364] = true, [-365] = true,
    [-366] = true, [-367] = true, [-368] = true, [-369] = true, [-641] = true, [-676] = true } -- holidays, events, legendaries
local CLASSIC_A, CLASSIC_H = { 1, 3, 4, 7 }, { 2, 5, 6, 8 } -- race ids; the Skyborne are bits 33 (A) and 34 (H)
-- ForeverDB's dungeon names that the route spells otherwise, and its dungeon areas that are not five-player dungeons.
local DUNGEON_ALIAS = { ["The Temple of Atal'Hakkar"] = "Sunken Temple", ["Deadmines"] = "The Deadmines",
    ["Stormwind Stockade"] = "The Stockade" }
local NOT_DUNGEONS = { ["Alterac Valley"] = true, ["Arathi Basin"] = true, ["Warsong Gulch"] = true, ["Deeprun Tram"] = true,
    ["Molten Core"] = true, ["Onyxia's Lair"] = true, ["Blackwing Lair"] = true, ["Zul'Gurub"] = true,
    ["Ruins of Ahn'Qiraj"] = true, ["Temple of Ahn'Qiraj"] = true, ["Ahn'Qiraj Temple"] = true, ["Naxxramas"] = true }

-- { side (1 A, 2 H, 3 both), race mask (0 when the side alone says who) } from a QuestieDB race mask.
local function RaceSide(mask)
    if not mask or mask <= 0 then return 3, 0 end
    local function all(list) for _, r in ipairs(list) do if not bit(mask, r) then return false end end return true end
    local function any(list) for _, r in ipairs(list) do if bit(mask, r) then return true end end return false end
    local a, h = any(CLASSIC_A) or bit(mask, 33), any(CLASSIC_H) or bit(mask, 34)
    local side = (a and not h and 1) or (h and not a and 2) or 3
    local whole = (not a or (all(CLASSIC_A) and bit(mask, 33))) and (not h or (all(CLASSIC_H) and bit(mask, 34)))
    return side, whole and 0 or mask
end

-- Is world point (x, y) inside any of the loops (even-odd, so holes count)?
local function Inside(loops, x, y)
    local inside = false
    for _, loop in ipairs(loops) do
        local n = #loop
        local jx, jy = loop[n - 1], loop[n]
        for i = 1, n - 1, 2 do
            local ix, iy = loop[i], loop[i + 1]
            if (iy > y) ~= (jy > y) and x < (jx - ix) * (y - iy) / (jy - iy) + ix then inside = not inside end
            jx, jy = ix, iy
        end
    end
    return inside
end

function ns.FromForeverDB(F, stages)
    local none = {}
    local quest, qx, qg, qe = F.quest or none, F.qx or none, F.qg or none, F.qe or none
    local npc, obj, spm, spw = F.npc or none, F.obj or none, F.spm or none, F.spw or none
    local umap, umaa, area, zbord = F.umap or none, F.umaa or none, F.area or none, F.zbord or none

    -- Map placement: every zone map's world rectangle, a zone area's map, and the zone outlines by continent.
    local rect, areaMap = {}, {} -- rect[uiMap] = { cont, minX, minY, maxX, maxY }
    for _, r in pairs(umaa) do
        local m, info = r[1], umap[r[1]]
        if info and info[3] == 3 and not rect[m] then
            rect[m] = { r[2], r[8], r[9], r[11], r[12] }
            if r[3] and r[3] > 0 and (not areaMap[r[3]] or m < areaMap[r[3]]) then areaMap[r[3]] = m end
        end
    end
    local outlines = {} -- outlines[cont] = { { ui, minX, minY, maxX, maxY, loops }, ... }
    for _, z in pairs(zbord) do
        if z.ui and z.w and rect[z.ui] then
            local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
            for _, loop in ipairs(z.w) do
                for i = 1, #loop - 1, 2 do
                    x0, x1 = math.min(x0, loop[i]), math.max(x1, loop[i])
                    y0, y1 = math.min(y0, loop[i + 1]), math.max(y1, loop[i + 1])
                end
            end
            outlines[z.c] = outlines[z.c] or {}
            table.insert(outlines[z.c], { z.ui, x0, y0, x1, y1, z.w })
        end
    end
    local function ZoneOfArea(a) -- a sub-zone's zone map
        for _ = 1, 8 do
            if not a or a <= 0 then return nil end
            if areaMap[a] then return areaMap[a] end
            a = area[a] and area[a][3]
        end
    end
    local function In(m, cont, x, y)
        local r = rect[m]
        return r and r[1] == cont and x >= r[2] and x <= r[4] and y >= r[3] and y <= r[5]
    end
    local function Pct(m, x, y)
        local r = rect[m]
        return math.floor((r[5] - y) / (r[5] - r[3]) * 1000 + 0.5) / 10, math.floor((r[4] - x) / (r[4] - r[2]) * 1000 + 0.5) / 10
    end
    -- World point -> uiMap, x, y (0-100). hint: the quest's zone map, taken when the point is inside its rectangle.
    local function Place(cont, x, y, hint)
        local m = hint and In(hint, cont, x, y) and hint
        if not m then
            for _, o in ipairs(outlines[cont] or none) do
                if x >= o[2] and x <= o[4] and y >= o[3] and y <= o[5] and Inside(o[6], x, y) then m = o[1] break end
            end
        end
        if not m then -- no outline (Ironforge, the Undercity): the smallest map around it
            local best
            for id, r in pairs(rect) do
                if In(id, cont, x, y) then
                    local size = (r[4] - r[2]) * (r[5] - r[3])
                    if not best or size < best or (size == best and id < m) then m, best = id, size end
                end
            end
        end
        if m then return m, Pct(m, x, y) end
    end
    -- Every spot of an npc / object key ("c123", "o45"): { { map, x, y }, ... }; one = the first only.
    local function SpotsOf(key, hint, one)
        local list = {}
        for m, pts in pairs(spm[key] or none) do
            for i = 1, #pts - 1, 2 do
                list[#list + 1] = { m, pts[i] / 10, pts[i + 1] / 10 }
                if one then return list end
            end
        end
        for _, group in ipairs(spw[key] or none) do
            for i = 2, #group - 1, 2 do
                local m, px, py = Place(group[1], group[i], group[i + 1], hint)
                if m then
                    list[#list + 1] = { m, px, py }
                    if one then return list end
                end
            end
        end
        return list
    end
    local function NameOf(key)
        local kind, n = key:sub(1, 1), tonumber(key:sub(2))
        local e = (kind == "c" and npc[n]) or (kind == "o" and obj[n])
        return e and e[1]
    end

    local itemStart = {}
    for _, qid in pairs(F.start or none) do itemStart[qid] = true end
    local inDungeon = {}
    for a in pairs(F.dng or none) do inDungeon[a] = true end

    local D = { Quests = {}, Zones = {}, Requires = {}, Exclusive = {}, Breadcrumb = {}, Repeatable = {}, Dungeon = {},
        Battleground = {}, Elsewhere = {}, Profession = {}, SkillRank = {}, MinReputation = {} }
    local zoneOf = {}
    for id, q in pairs(quest) do
        local x = qx[id] or none
        local side, race = RaceSide(x[1])
        local sort = x[11] or 0
        local class = x[2] or 0
        if class <= 0 and SORT_CLASS[sort] then class = 2 ^ (SORT_CLASS[sort] - 1) end
        local hint = sort > 0 and ZoneOfArea(sort) or nil
        local giverKey = (qg[id] or none)[1]
        local at = giverKey and SpotsOf(giverKey, hint, true)[1]
        local map = at and at[1] or hint
        D.Quests[id] = { q[1] or "?", q[2] or 0, q[3] or 0, side, race, class, map, at and at[2], at and at[3],
            giverKey and NameOf(giverKey), itemStart[id] or nil }
        if map then
            zoneOf[map] = zoneOf[map] or {}
            table.insert(zoneOf[map], id)
        end
        local needs = {}
        for _, pre in ipairs(x[4] or none) do needs[#needs + 1] = pre end
        local single = x[3] or none
        if #single == 1 then needs[#needs + 1] = single[1] elseif #single > 1 then needs[#needs + 1] = single end
        if #needs > 0 then D.Requires[id] = needs end
        if x[5] and #x[5] > 0 then
            local group = { id }
            for _, other in ipairs(x[5]) do group[#group + 1] = other end
            D.Exclusive[#D.Exclusive + 1] = group
        end
        if type(x[6]) == "number" and x[6] > 0 then D.Breadcrumb[id] = x[6] end
        if bit(x[13], 1) then D.Repeatable[id] = true end
        if inDungeon[sort] or (giverKey and (F.ind or none)[giverKey]) then D.Dungeon[id] = true end
        if sort == -25 then D.Battleground[id] = true end
        if SORT_ELSEWHERE[sort] then D.Elsewhere[id] = true end
        if SORT_PROFESSION[sort] then D.Profession[id] = true end
        if x[14] then D.SkillRank[id] = true end
        if x[19] then D.MinReputation[id] = true end
    end
    -- A loop of prerequisites (the data has one in Riverglades) would leave every quest in it waiting on another:
    -- each loop loses the link whose prerequisite is the most levels above the quest that needs it.
    while true do
        local color, path, cut = {}, {}, nil -- color: 1 on the path, 2 done
        local function Visit(id)
            color[id] = 1
            path[#path + 1] = id
            for _, pre in ipairs(D.Requires[id] or none) do
                if type(pre) == "number" and D.Quests[pre] then
                    if color[pre] == 1 then -- a loop: from pre along the path back to pre
                        local worst, gap
                        local start
                        for i = #path, 1, -1 do if path[i] == pre then start = i break end end
                        for i = start, #path do
                            local q, p = path[i], path[i + 1] or pre
                            local g = D.Quests[p][2] - D.Quests[q][2]
                            if not gap or g > gap or (g == gap and p > worst[2]) then worst, gap = { q, p }, g end
                        end
                        cut = worst
                        return true
                    elseif not color[pre] and Visit(pre) then
                        return true
                    end
                end
            end
            path[#path] = nil
            color[id] = 2
        end
        for id in pairs(D.Requires) do
            if not color[id] and Visit(id) then break end
        end
        if not cut then break end
        local list = D.Requires[cut[1]]
        for i = #list, 1, -1 do if list[i] == cut[2] then table.remove(list, i) end end
    end

    local maps = {}
    for m in pairs(zoneOf) do maps[#maps + 1] = m end
    table.sort(maps)
    for _, m in ipairs(maps) do
        table.sort(zoneOf[m])
        D.Zones[#D.Zones + 1] = { map = m, name = umap[m] and umap[m][1] or tostring(m), quests = zoneOf[m] }
    end

    -- Hand-ins for every quest a list can show (route maps and class quests); objective camps for the route maps.
    local wanted = {}
    for _, stage in ipairs(stages or none) do for _, m in ipairs(stage.maps or none) do wanted[m] = true end end
    local Spots = {}
    for id, q in pairs(D.Quests) do
        local onRoute = q[7] and wanted[q[7]]
        if onRoute or (q[6] > 0 and q[2] > 0) then
            local x = qx[id] or none
            local hint = (x[11] or 0) > 0 and ZoneOfArea(x[11]) or nil
            local enderKey = (qe[id] or none)[1]
            local turnin = enderKey and SpotsOf(enderKey, hint, true)[1] or nil
            local camps = {}
            if onRoute then
                -- Where players made progress (recorded), else the spots of what the objectives name.
                local pts = {}
                local function addMapPts(byMap)
                    for m, list in pairs(byMap or none) do
                        for i = 1, #list - 1, 2 do pts[#pts + 1] = { m, list[i] / 10, list[i + 1] / 10 } end
                    end
                end
                addMapPts((F.qsp or none)[id])
                if #pts == 0 then
                    local keys = {}
                    for _, c in ipairs(x[8] or none) do keys[#keys + 1] = "c" .. (type(c) == "table" and c[1] or c) end
                    for _, o in ipairs(x[9] or none) do keys[#keys + 1] = "o" .. (type(o) == "table" and o[1] or o) end
                    for _, k in ipairs(x[23] or none) do keys[#keys + 1] = k end
                    for _, it in ipairs(x[10] or none) do
                        local item = type(it) == "table" and it[1] or it
                        for _, src in ipairs({ { F.drop, "c" }, { F.odrop, "o" } }) do
                            local list = (src[1] or none)[item] or none
                            for i = 1, math.min(#list, 6) - 1, 2 do keys[#keys + 1] = src[2] .. list[i] end -- the best 3 sources
                        end
                    end
                    for _, k in ipairs(keys) do
                        for _, p in ipairs(SpotsOf(k, hint)) do pts[#pts + 1] = p end
                    end
                    addMapPts(x[16])
                    addMapPts(x[22])
                end
                -- Grouped into 10% squares; the three fullest are the camps, each at the middle of its points.
                local cells, order = {}, {}
                for _, p in ipairs(pts) do
                    local key = p[1] .. ":" .. math.floor(p[2] / 10) .. ":" .. math.floor(p[3] / 10)
                    local c = cells[key]
                    if not c then c = { p[1], 0, 0, 0 } cells[key] = c order[#order + 1] = c end
                    c[2], c[3], c[4] = c[2] + p[2], c[3] + p[3], c[4] + 1
                end
                table.sort(order, function(a, b) return a[4] > b[4] end)
                for i = 1, math.min(3, #order) do
                    local c = order[i]
                    camps[i] = { c[1], math.floor(c[2] / c[4] * 10 + 0.5) / 10, math.floor(c[3] / c[4] * 10 + 0.5) / 10 }
                end
            end
            if turnin or #camps > 0 then Spots[id] = { turnin or {}, camps } end
        end
    end

    -- Dungeons: a quest of a dungeon area (its zoneOrSort, or a giver who lives inside), or one with an objective
    -- found only inside dungeons (its mobs or objects live there, or all that drop its item do). A quest can be in
    -- several. Grouped by the dungeon's name; the level range runs from the lowest level needed to the highest quest level.
    local dng, ind = F.dng or none, F.ind or none
    local function NameOfArea(a)
        local name = dng[a] and dng[a][1]
        name = name and (DUNGEON_ALIAS[name] or name)
        if name and not NOT_DUNGEONS[name] then return name end
    end
    -- An instance map (where a mob inside stands, in spw) -> the dungeon's name, from the travel data's entrances.
    local entrances = type(F.spf) == "table" and F.spf.Entrances or none
    local function NameOfInstance(m)
        local e = entrances[m]
        local name = e and e.name
        name = name and (DUNGEON_ALIAS[name] or name)
        if name and not NOT_DUNGEONS[name] then return name end
    end
    local function DungeonsOfKey(key) -- the dungeons an npc / object lives in, or nil when it is found outside too
        local found = {}
        for _, a in ipairs(ind[key] or none) do if NameOfArea(a) then found[NameOfArea(a)] = true end end
        if next(found) then return found end
        local groups = spw[key]
        if not groups or #groups == 0 then return nil end
        for _, g in ipairs(groups) do
            local name = NameOfInstance(g[1])
            if not name then return nil end
            found[name] = true
        end
        return found
    end
    local function OnlyInside(keys, into) -- every key lives in a dungeon: their dungeons, into the set
        if #keys == 0 then return end
        local found = {}
        for _, k in ipairs(keys) do
            local names = DungeonsOfKey(k)
            if not names then return end
            for name in pairs(names) do found[name] = true end
        end
        for name in pairs(found) do into[name] = true end
    end
    local dungeonsOf = {}
    for id, q in pairs(D.Quests) do
        local x, set = qx[id] or none, {}
        if x[11] and NameOfArea(x[11]) then set[NameOfArea(x[11])] = true end
        local giverKey = (qg[id] or none)[1]
        for _, a in ipairs(giverKey and ind[giverKey] or none) do if NameOfArea(a) then set[NameOfArea(a)] = true end end
        for _, c in ipairs(x[8] or none) do OnlyInside({ "c" .. (type(c) == "table" and c[1] or c) }, set) end
        for _, o in ipairs(x[9] or none) do OnlyInside({ "o" .. (type(o) == "table" and o[1] or o) }, set) end
        for _, it in ipairs(x[10] or none) do
            local item, keys = type(it) == "table" and it[1] or it, {}
            for _, src in ipairs({ { F.drop, "c" }, { F.odrop, "o" } }) do
                local list = (src[1] or none)[item] or none
                for i = 1, #list - 1, 2 do keys[#keys + 1] = src[2] .. list[i] end
            end
            OnlyInside(keys, set)
        end
        if next(set) and q[2] > 0 then
            dungeonsOf[id] = set
            D.Dungeon[id] = true
        end
    end
    local byName, order = {}, {}
    for id, set in pairs(dungeonsOf) do
        local q = D.Quests[id]
        local giverKey = (qg[id] or none)[1]
        local map, x, y = q[7], q[8], q[9]
        if (giverKey and ind[giverKey]) or not x then map, x, y = nil, nil, nil end -- picked up inside, or not known
        local zone = map and umap[map] and umap[map][1]
        local where = zone and q[10] and (zone .. " - " .. q[10]) or zone or q[10]
        for name in pairs(set) do
            local d = byName[name]
            if not d then d = { name = name, levels = { 99, 0 }, quests = {} } byName[name] = d order[#order + 1] = d end
            d.quests[#d.quests + 1] = { id, q[1], q[2], q[4] == 1 and "A" or q[4] == 2 and "H" or nil,
                D.Requires[id] and "pre" or nil, where, map, x, y }
        end
    end
    -- The range: from the lowest level needed to the highest quest level, of the quests within 10 levels of the
    -- dungeon's middle one (a stray level 1 quest in Blackrock Depths would open it at level 1), and only levels
    -- needed within 10 of it too.
    for _, d in ipairs(order) do
        local lv = {}
        for _, e in ipairs(d.quests) do lv[#lv + 1] = e[3] end
        table.sort(lv)
        local mid = lv[math.ceil(#lv / 2)]
        for _, e in ipairs(d.quests) do
            if math.abs(e[3] - mid) <= 10 then
                local req = D.Quests[e[1]][3]
                if req < mid - 10 then req = e[3] end -- some say "level 1 needed" for a level 60 quest
                d.levels[1] = math.min(d.levels[1], req)
                d.levels[2] = math.max(d.levels[2], e[3])
            end
        end
    end
    table.sort(order, function(a, b) return a.levels[1] < b.levels[1] or (a.levels[1] == b.levels[1] and a.name < b.name) end)
    for _, d in ipairs(order) do table.sort(d.quests, function(a, b) return a[3] < b[3] or (a[3] == b[3] and a[1] < b[1]) end) end

    -- The items class quests need, with where each comes from (the dungeon when it drops
    -- inside one): ForeverDungeonJournal's QUEST_PREREQ_DETAILS shape, { requiredItems = { { id, name, _, source } } }.
    local Details = {}
    for id, q in pairs(D.Quests) do
        local x = qx[id] or none
        if q[6] > 0 and x[10] then
            local items = {}
            for _, it in ipairs(x[10]) do
                local itemId = type(it) == "table" and it[1] or it
                local e = (F.item or none)[itemId]
                if e and e[1] then
                    local where
                    for _, src in ipairs({ { F.drop, "c" }, { F.odrop, "o" } }) do
                        local list = (src[1] or none)[itemId] or none
                        if not where and list[1] then
                            local key = src[2] .. list[1]
                            local inside = DungeonsOfKey(key)
                            local place = inside and next(inside)
                            if not place then
                                local at = SpotsOf(key, nil, true)[1]
                                place = at and umap[at[1]] and umap[at[1]][1]
                            end
                            local who = NameOf(key)
                            where = who and place and (who .. ", " .. place) or who or place
                        end
                    end
                    items[#items + 1] = { itemId, e[1], nil, where or "" }
                end
            end
            if #items > 0 then Details[id] = { requiredItems = items } end
        end
    end
    return { QuestData = order }, D, Spots, Details
end

---------------------------------------------------------------------------
-- In the game: from the installed addons, at load
---------------------------------------------------------------------------

-- The addons the quest lists come from: needed (the route has no quests without them) and optional.
ns.QUEST_SOURCES = {
    { "ForeverDB", "ForeverDB", true },
    { "ForeverDungeonJournal", "ForeverDungeonJournal", false },
}

-- The reward items of dungeon quests, from ForeverDungeonJournal's dungeon list (FDJ.DB[name].quests[].rewardItems):
-- function(id) -> { { itemId, name, quality }, ... }, green and better. Other quests' come from ForeverDB, and the
-- quest recorder's are laid over both.
function ns.JournalRewards(FDJ)
    local byId = {}
    local db = type(FDJ) == "table" and rawget(FDJ, "DB")
    for _, d in pairs(type(db) == "table" and db or {}) do
        for _, q in ipairs(type(d) == "table" and type(d.quests) == "table" and d.quests or {}) do
            if type(q) == "table" and type(q.id) == "number" and type(q.rewardItems) == "table" then
                local list = {}
                for _, it in ipairs(q.rewardItems) do
                    if type(it) == "table" and type(it[1]) == "number" and (tonumber(it[3]) or 0) >= 2 then
                        list[#list + 1] = { it[1], it[2], it[3] }
                    end
                end
                if #list > 0 then byId[q.id] = list end
            end
        end
    end
    local none = {}
    return function(id) return byId[id] or none end
end

-- The reward items of every quest, from ForeverDB (qrw[id] = { money, xp, { choices }, { items } }, item[id][2] its
-- quality): the same shape as JournalRewards, green and better.
function ns.ForeverDBRewards(F)
    local qrw, item, none = type(F) == "table" and F.qrw or {}, type(F) == "table" and F.item or {}, {}
    return function(id)
        local r = qrw[id]
        if not r then return none end
        local list = {}
        for _, group in ipairs({ r[3] or none, r[4] or none }) do
            for _, it in ipairs(group) do
                local e = item[it]
                if e and (e[2] or 0) >= 2 then list[#list + 1] = { it, e[1], e[2] } end
            end
        end
        return list
    end
end

local function Loaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function Load(name)
    if Loaded(name) then return true end
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if not load then return false end
    local ok, done = pcall(load, name)
    return ok and done and true or false
end

-- Builds ns.Dungeons, ns.ClassQuests, ns.ZoneQuests and ns.NeedLimit unless they are already there (the tests'
-- Generated.lua). Returns how: "built", "given", or nil and what is missing.
function ns.LoadQuests()
    if ns.ZoneQuests then
        ns.questSource = "given"
        return "given"
    end
    -- ForeverDB loads on demand: asked for here.
    Load("ForeverDB")
    local F = _G.ForeverDB
    local missing = {}
    local have = type(F) == "table" and type(F.quest) == "table" and type(F.qx) == "table" and type(F.qg) == "table"
        and type(F.npc) == "table" and type(F.umaa) == "table"
    if not have then missing[#missing + 1] = "ForeverDB" end
    if have then
        local FDJ = _G.ForeverDungeonJournal_NS
        local details = type(FDJ) == "table" and rawget(FDJ, "QUEST_PREREQ_DETAILS")
        local stages = ns.AllStages or ns.Stages
        local ok, dungeons, classQuests, zoneQuests, needLimit = pcall(function()
            local J, D, Spots, own_details = ns.FromForeverDB(F, stages)
            if type(details) == "table" then -- ForeverDungeonJournal's, where it has a quest
                for id, det in pairs(details) do own_details[id] = det end
            end
            details = own_details
            local journal, own = ns.JournalRewards(FDJ), ns.ForeverDBRewards(F)
            local function Rewards(id) -- ForeverDungeonJournal's when it has them, else ForeverDB's
                local list = journal(id)
                if #list > 0 then return list end
                return own(id)
            end
            return ns.BuildQuests({ J = J, D = D, Spots = Spots, Details = type(details) == "table" and details or {},
                Rewards = Rewards }, stages)
        end)
        if ok then
            ns.Dungeons, ns.ClassQuests, ns.ZoneQuests, ns.NeedLimit = dungeons, classQuests, zoneQuests, needLimit
            ns.questSource, ns.questMissing = "built", missing
            return "built"
        end
        missing[#missing + 1] = "(their data did not read: " .. tostring(dungeons) .. ")"
    end
    ns.Dungeons, ns.ClassQuests, ns.ZoneQuests, ns.NeedLimit = {}, {}, {}, {}
    ns.questSource, ns.questMissing = nil, missing
    return nil, missing
end
