local ADDON, ns = ...

-- The quest recorder: Undead Route's own quest data, seen as you play, so the route need not rest on other
-- addons' data. For each quest it keeps what the game shows: its name and level, who gives it and where you
-- stood, the reward items and XP, the objectives and where they moved on, and who takes it in and where.
-- It is kept for the whole account (UndeadRouteRecordDB), every character adding to it.
--
-- Nothing about you is kept: no character or account names, only side, race and class ids, to tell who
-- can take a quest. tools/record.lua merges these files (yours, and any friends send) into Recorded.lua.
--
-- At load, the shipped Recorded.lua and then this account's own recordings are laid over the generated
-- quests: a recorded place, giver, hand-in or reward replaces the generated one, and a quest the generated
-- data lacks is added to its zone. Route.lua builds the route from the result at login.

local VERSION = 1
local rec -- UndeadRouteRecordDB.quests
local sessionCount = 0

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return Plain(a), Plain(b), Plain(c), Plain(d), Plain(e), Plain(f) end
end

local function Round(v) return math.floor(v * 10 + 0.5) / 10 end

-- Where you stand, in map units (0-100) of the zone's map; nil inside an instance or where the game will not say.
local function Here()
    local map = C_Map and Call(C_Map.GetBestMapForUnit, "player")
    if type(map) ~= "number" then return end
    local pos = Call(C_Map.GetPlayerMapPosition, map, "player")
    if not (pos and pos.GetXY) then return end
    local x, y = Call(pos.GetXY, pos)
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return end
    local info = Call(C_Map.GetMapInfo, map)
    local zone = info and Plain(info.name)
    return { map, Round(x * 100), Round(y * 100), type(zone) == "string" and zone or nil }
end

local function Entry(id)
    local q = rec[id]
    if not q then
        q = { seen = 0 }
        rec[id] = q
    end
    return q
end

-- Who this character is, for who may take a quest: side ("A"/"H"), race id, class id.
local function Who()
    local faction = Call(UnitFactionGroup, "player")
    local _, _, raceId = Call(UnitRace, "player")
    local _, _, classId = Call(UnitClass, "player")
    return (faction == "Alliance" and "A") or (faction == "Horde" and "H") or nil, raceId, classId
end

local function Mark(set, key)
    if key ~= nil then set[key] = true end
end

local function NpcName()
    for _, unit in ipairs({ "questnpc", "npc" }) do
        if Call(UnitExists, unit) then
            local name = Call(UnitName, unit)
            if type(name) == "string" then return name end
        end
    end
end

-- The reward items on the quest window now: { { itemId, name, quality }, ... }, green and better.
local function Rewards()
    local list = {}
    for _, kind in ipairs({ "choice", "reward" }) do
        local n = Call(kind == "choice" and GetNumQuestChoices or GetNumQuestRewards) or 0
        for i = 1, n do
            local name, _, _, quality, _, itemId = Call(GetQuestItemInfo, kind, i)
            if type(itemId) ~= "number" then
                local link = Call(GetQuestItemLink, kind, i)
                itemId = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
            end
            if type(itemId) == "number" and type(quality) == "number" and quality >= 2 then
                list[#list + 1] = { itemId, type(name) == "string" and name or nil, quality }
            end
        end
    end
    return list
end

-- The objectives of a quest in your log: { text, ... }, and how far along each is.
local function Objectives(id)
    local list = C_QuestLog and Call(C_QuestLog.GetQuestObjectives, id)
    if type(list) ~= "table" then return end
    local texts, done = {}, {}
    for i, o in ipairs(list) do
        texts[i] = type(Plain(o.text)) == "string" and o.text or ""
        done[i] = tonumber(Plain(o.numFulfilled)) or 0
    end
    return texts, done
end

---------------------------------------------------------------------------
-- What the game shows, as it happens
---------------------------------------------------------------------------

local detail -- the quest window you are reading: id, giver, place, rewards, XP
local progress = {} -- quest id -> how far along each objective was, to see it move

local R = {}
ns.Recorder = R

-- The quest window opened (from an NPC, an object or an item): kept until you accept it.
function R.Detail()
    local id = Call(GetQuestID)
    if type(id) ~= "number" or id == 0 then return end
    local giver = NpcName()
    detail = {
        id = id, name = Call(GetTitleText), giver = giver, item = not giver or nil, at = Here(),
        rewards = Rewards(), xp = Call(GetRewardXP),
    }
end

function R.Accepted(id)
    id = tonumber(id)
    if not (rec and id) then return end
    local q = Entry(id)
    local d = detail and detail.id == id and detail or nil
    detail = nil
    q.seen = q.seen + 1
    q.name = (d and type(d.name) == "string" and d.name) or (C_QuestLog and Call(C_QuestLog.GetTitleForQuestID, id)) or q.name
    local level = C_QuestLog and Call(C_QuestLog.GetQuestDifficultyLevel, id)
    if type(level) ~= "number" and C_QuestLog then -- else the log's own line for it
        local index = Call(C_QuestLog.GetLogIndexForQuestID, id)
        local info = index and Call(C_QuestLog.GetInfo, index)
        level = info and Plain(info.level)
    end
    if type(level) == "number" and level > 0 then q.lv = level end
    local me = Call(UnitLevel, "player")
    if type(me) == "number" then q.req = math.min(q.req or me, me) end -- the lowest level seen taking it
    if d then
        if d.giver then q.giver, q.item = d.giver, nil elseif not q.giver then q.item = true end
        if d.at then q.pick = d.at end
        if #d.rewards > 0 then q.rewards = d.rewards end
        if type(d.xp) == "number" and d.xp > 0 then q.xp = d.xp end
    elseif not q.pick then
        q.pick, q.auto = Here(), true -- taken without a window (shared, or an area quest)
    end
    local s, race, class = Who()
    q.sides, q.races, q.classes = q.sides or {}, q.races or {}, q.classes or {}
    Mark(q.sides, s) Mark(q.races, race) Mark(q.classes, class)
    q.obj = Objectives(id) or q.obj
    local _, done = Objectives(id)
    progress[id] = done
    sessionCount = sessionCount + 1
end

-- An objective moved on: where you stood counts towards where that quest's work is.
function R.LogUpdate()
    if not rec then return end
    local at
    for id, before in pairs(progress) do
        local _, now = Objectives(id)
        if now then
            for i, n in ipairs(now) do
                if n > (before[i] or 0) then
                    at = at or Here() or false
                    if at then
                        local q = Entry(id)
                        local spot = q.spot
                        if not spot then spot = { at[1], 0, 0, 0 } q.spot = spot end
                        if spot[1] ~= at[1] then
                            -- Another map (a cave, the next zone): counted apart in q.spotAlt, so one kill there
                            -- does not throw away what was seen here. It takes over once more of the work is there.
                            local alt = q.spotAlt
                            if not alt or alt[1] ~= at[1] then alt = { at[1], 0, 0, 0 } q.spotAlt = alt end
                            spot = alt
                        end
                        spot[2], spot[3], spot[4] = spot[2] + at[2], spot[3] + at[3], spot[4] + 1
                        if q.spotAlt and q.spotAlt[4] > q.spot[4] then q.spot, q.spotAlt = q.spotAlt, q.spot end
                    end
                end
            end
            progress[id] = now
        end
    end
end

-- The reward window: you stand at whoever takes the quest in.
local completing
function R.Complete()
    local id = Call(GetQuestID)
    if type(id) ~= "number" or id == 0 then return end
    completing = { id = id, ender = NpcName(), at = Here(), rewards = Rewards() }
end

function R.TurnedIn(id, xp)
    id = tonumber(id)
    if not (rec and id) then return end
    local q = Entry(id)
    local c = completing and completing.id == id and completing or nil
    completing = nil
    progress[id] = nil
    if c then
        if c.at then q.turnin = c.at end
        if c.ender then q.ender = c.ender end
        if #c.rewards > 0 and not q.rewards then q.rewards = c.rewards end
    end
    xp = tonumber(Plain(xp))
    if xp and xp > 0 then q.xpDone = xp end
    q.done = (q.done or 0) + 1
end

-- Out of your log (abandoned, or handed in): its objectives are not followed any more.
function R.Removed(id)
    id = tonumber(Plain(id))
    if id then progress[id] = nil end
end

-- The quests already in your log at login are followed too, so their objectives count.
function R.Watch()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    local n = Call(C_QuestLog.GetNumQuestLogEntries) or 0
    for i = 1, n do
        local info = Call(C_QuestLog.GetInfo, i)
        local id = info and Plain(info.questID)
        if type(id) == "number" and id > 0 and not Plain(info.isHeader) then
            local _, done = Objectives(id)
            progress[id] = done
        end
    end
end

-- How much is recorded: quests, of them with a giver's place, and with a hand-in place.
function R.Counts()
    local all, picked, handed = 0, 0, 0
    for _, q in pairs(rec or {}) do
        all = all + 1
        if q.pick then picked = picked + 1 end
        if q.turnin then handed = handed + 1 end
    end
    return all, picked, handed, sessionCount
end

---------------------------------------------------------------------------
-- Laying recorded quests over the generated ones
---------------------------------------------------------------------------

local function SpotOf(q)
    local s = q.spot
    if s and s[4] and s[4] > 0 then return s[1], Round(s[2] / s[4]), Round(s[3] / s[4]) end
end

-- One recorded quest over a generated one: what was seen replaces what was said.
local function Lay(g, q, zoneMap)
    if q.name then g.name = q.name end
    if q.giver then g.giver = q.giver g.item = nil elseif q.item and not g.giver then g.item = true end
    if q.pick then g.map, g.x, g.y, g.zone = q.pick[1], q.pick[2], q.pick[3], q.pick[4] or g.zone end
    if q.turnin then
        g.turnin = { q.turnin[1], q.turnin[2], q.turnin[3], q.turnin[4] or (g.turnin and g.turnin[4]) or g.zone }
    end
    local map, x, y = SpotOf(q)
    if map and (not zoneMap or map == zoneMap) then g.spot = { x, y } end
    if q.rewards and #q.rewards > 0 then g.rewards = q.rewards end
    g.rec = true
end

local function SideOf(q)
    local a, h = q.sides and q.sides.A, q.sides and q.sides.H
    if a and not h then return "A" end
    if h and not a then return "H" end
end

-- Lays `recorded` (quest id -> recording) over ns.ZoneQuests, ns.ClassQuests and ns.Dungeons; returns how many
-- generated quests it changed and how many it added.
function R.Apply(recorded)
    if type(recorded) ~= "table" then return 0, 0 end
    local known, changed, added = {}, 0, 0
    local function over(list, zoneMap)
        for _, g in ipairs(list or {}) do
            known[g.id] = true
            local q = recorded[g.id]
            if type(q) == "table" then
                Lay(g, q, zoneMap)
                changed = changed + 1
            end
        end
    end
    ns.ZoneQuests = ns.ZoneQuests or {}
    for map, list in pairs(ns.ZoneQuests) do over(list, map) end
    for _, list in pairs(ns.ClassQuests or {}) do over(list) end
    for _, d in pairs(ns.Dungeons or {}) do over(d.quests) end
    -- Quests only the recordings know: added to the zone they were taken in, for the side that took them.
    -- Only one seen taken from someone, at a known level, with a place: enough to route by.
    for id, q in pairs(recorded) do
        if type(id) == "number" and not known[id] and type(q) == "table" and q.pick and q.name and q.lv and q.req
            and (q.giver or q.item) then
            local map = q.pick[1]
            local g = { id = id, lv = q.lv, req = math.min(q.req, q.lv), side = SideOf(q) }
            Lay(g, q, map)
            ns.ZoneQuests[map] = ns.ZoneQuests[map] or {}
            table.insert(ns.ZoneQuests[map], g)
            known[id] = true
            added = added + 1
        end
    end
    return changed, added
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_REMOVED")

local logTimer = false
frame:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        UndeadRouteRecordDB = type(UndeadRouteRecordDB) == "table" and UndeadRouteRecordDB or {}
        local store = UndeadRouteRecordDB
        store.v = VERSION
        store.quests = type(store.quests) == "table" and store.quests or {}
        rec = store.quests
        -- The quest lists, from the installed quest-data addons (Build.lua); then, before Route.lua builds the
        -- route at login, the shipped recordings and this account's own laid over them.
        ns.LoadQuests()
        R.Apply(ns.Recorded)
        if store.off ~= true then R.Apply(rec) end
        return
    end
    if event == "PLAYER_LOGIN" and not ns.questSource then
        -- Without the quest-data addons there is no quest list: say which are missing, once a login.
        print("|cffff5959Undead Route:|r no quest list: it is read from addons that are not installed or not on: "
            .. table.concat(ns.questMissing or {}, ", ") .. ". The steps still name the zones and hubs. /route data says more.")
    end
    if not rec or UndeadRouteRecordDB.off == true then return end
    if event == "PLAYER_LOGIN" then
        R.Watch()
    elseif event == "QUEST_DETAIL" then
        R.Detail()
    elseif event == "QUEST_ACCEPTED" then
        -- (questId) on this client; an older one passed (logIndex, questId).
        R.Accepted(a2 and tonumber(a2) or a1)
    elseif event == "QUEST_COMPLETE" then
        R.Complete()
    elseif event == "QUEST_TURNED_IN" then
        R.TurnedIn(a1, a2)
    elseif event == "QUEST_REMOVED" then
        R.Removed(a1)
    elseif event == "QUEST_LOG_UPDATE" and not logTimer then
        -- It fires in bursts: look once, a moment later.
        if C_Timer and C_Timer.After then
            logTimer = true
            C_Timer.After(0.3, function() logTimer = false R.LogUpdate() end)
        else
            R.LogUpdate()
        end
    end
end)

-- /route data: where the quest list comes from, and which addons it needs.
function R.Data(print)
    local count = 0
    for _, list in pairs(ns.ZoneQuests or {}) do count = count + #list end
    print(string.format("quest list: %s, %d zone quests. It is read at login from these addons:",
        ns.questSource == "built" and "read from your addons" or ns.questSource == "given" and "built in" or "none", count))
    for _, s in ipairs(ns.QUEST_SOURCES or {}) do
        local on = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(s[1])) or (IsAddOnLoaded and IsAddOnLoaded(s[1]))
        print(string.format("  %s%s|r%s%s", on and "|cff59d973" or "|cffff5959", on and "on " or "missing ", s[2],
            s[3] and "" or " (optional: class quest objectives)"))
    end
    local all = R.Counts()
    print(string.format("  and %d quests you recorded yourself (/route record).", all))
end

-- /route record: what is recorded; /route record off|on pauses or resumes it.
function R.Slash(arg, print)
    local store = UndeadRouteRecordDB
    if not store then return end
    if arg == "off" then
        store.off = true
        print("quest recorder paused. /route record on starts it again.")
    elseif arg == "on" then
        store.off = nil
        print("quest recorder on.")
    else
        local all, picked, handed, now = R.Counts()
        print(string.format("quest recorder %s: %d quests (%d with the giver's place, %d with the hand-in), %d this session. "
            .. "The file is WTF\\Account\\<account>\\SavedVariables\\UndeadRoute.lua; it holds no names, only side, race and class.",
            store.off and "paused" or "on", all, picked, handed, now))
    end
end
