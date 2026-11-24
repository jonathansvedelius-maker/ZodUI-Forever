local _, ns = ...

-- The quest lists, built at login from the quest data of addons the player has installed, so none of their
-- data ships with Undead Route:
--   NaowhForever_DungeonJournal  every dungeon quest (id, level, side, where to pick it up)
--   NaowhForever_DiscoveryData   every quest (class and race limits, giver, prerequisites)    (loaded on demand)
--   NaowhForever_JourneysData    where each quest is handed in, and its objectives' camps     (loaded on demand)
--   ForeverDungeonJournal        objectives and required items of class quest chains          (optional)
-- Quests of both factions and every race and class are kept, each tagged with who may take it (side, race
-- and class masks); Route.lua keeps this character's at login. Reward items come from the quest recorder.
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

-- src: J (NaowhForever.Journal), D (NaowhForever.CompletoQuestData), Spots (NaowhForever.JourneyQuestSpots),
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
-- In the game: from the installed addons, at load
---------------------------------------------------------------------------

-- The addons the quest lists come from: needed (the route has no quests without them) and optional.
ns.QUEST_SOURCES = {
    { "NaowhForever", "NaowhForever", true },
    { "NaowhForever_DungeonJournal", "NaowhForever Dungeon Journal", true },
    { "NaowhForever_DiscoveryData", "NaowhForever Discovery (its data)", true },
    { "NaowhForever_JourneysData", "NaowhForever Journeys (its data)", true },
    { "ForeverDungeonJournal", "ForeverDungeonJournal", false },
}

-- The reward items of dungeon quests, from ForeverDungeonJournal's dungeon list (FDJ.DB[name].quests[].rewardItems):
-- function(id) -> { { itemId, name, quality }, ... }, green and better. Zone quests' rewards come from the recorder.
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
    -- The two data packs load on demand: asked for here, as Naowh's own modules would.
    Load("NaowhForever_DiscoveryData")
    Load("NaowhForever_JourneysData")
    local N = _G.NaowhForever
    local D = type(N) == "table" and N.CompletoQuestData
    local missing = {}
    if not (type(D) == "table" and D.Quests and D.Zones and D.Requires) then missing[#missing + 1] = "NaowhForever Discovery" end
    if not (type(N) == "table" and type(N.Journal) == "table" and N.Journal.QuestData) then missing[#missing + 1] = "NaowhForever Dungeon Journal" end
    if not (type(N) == "table" and type(N.JourneyQuestSpots) == "table") then missing[#missing + 1] = "NaowhForever Journeys" end
    if D and D.Quests and D.Zones and D.Requires then
        local FDJ = _G.ForeverDungeonJournal_NS
        local details = type(FDJ) == "table" and rawget(FDJ, "QUEST_PREREQ_DETAILS")
        local ok, dungeons, classQuests, zoneQuests, needLimit = pcall(ns.BuildQuests, {
            J = N.Journal, D = D, Spots = N.JourneyQuestSpots, Details = type(details) == "table" and details or {},
            Rewards = ns.JournalRewards(FDJ),
        }, ns.AllStages or ns.Stages)
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
