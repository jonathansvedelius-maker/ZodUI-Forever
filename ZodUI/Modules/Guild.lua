local ADDON, ns = ...
local T = ns.T

-- Guild network: what ZodUI in your guild tells each other (over Core\Bus.lua).
--   Rares: when you see a rare or a world boss, the guild hears where; when a guild member sees one in your zone you
--     get a notice, and /zod guild way sets a waypoint to it. A rare already told about is not told again for a while.
--   Quests: /zod guild quest <quest> asks who else has it and how far they are; taking a group quest asks by itself.
--   Who runs ZodUI: each login says hello with the version; /zod guild asks everyone and lists them.
-- What is shared: the version, rares you see with where you stood, and, when asked, a quest's progress and your
-- level and zone. Recipes are Crafters' (Modules\Crafters.lua), which asks over the same network.

local M = ns:NewModule("guild", {
    title = "Guild network",
    desc = "ZodUI in your guild talks to each other: rares and world bosses someone sees, who else has a quest and "
        .. "how far they are, who knows a recipe (with Guild crafters), and who runs ZodUI.",
    defaults = { enabled = true, rares = true, rareNotice = true, answer = true, groupAsk = true },
    options = {
        { type = "check", key = "rares", label = "Tell the guild when you see a rare or a world boss" },
        { type = "check", key = "rareNotice", label = "A notice when a guild member sees one in your zone" },
        { type = "check", key = "answer", label = "Answer when a guild member asks who has a quest or knows a recipe" },
        { type = "check", key = "groupAsk", label = "When you take a group quest, ask who in the guild has it too" },
        { type = "note", text = "/zod guild lists who runs ZodUI. /zod guild rares, /zod guild way 2, /zod guild quest "
            .. "and a shift-clicked quest. Only guild members with ZodUI hear any of it.", lines = 3 },
    },
})

local Bus = ns.Bus
local RARE = { rare = true, rareelite = true, worldboss = true }
local RARE_QUIET = 300   -- seconds before the same rare is told about again
local RARES_KEEP = 50
local WAIT = 4           -- seconds to gather answers to a question
local ANSWERS_MOST = 20
local SHOW_MOST = 12
local NAME_MOST = 48

local members = {}       -- short name -> { version, at }, this session
local told               -- the newer version already mentioned
local pending = {}       -- question id -> { quest, title, answers, auto, from }

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Num(s, lo, hi)
    local n = s ~= nil and tonumber(s) or nil -- tonumber(nil) is an error in the game's Lua
    if not n or n ~= n or n < lo or n > hi then return nil end
    return n
end

local function CleanText(s, most)
    s = tostring(s or ""):gsub("[%c|~]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return s:sub(1, most)
end

local function PlayerLink(name)
    return "|Hplayer:" .. name .. "|h[" .. name .. "]|h"
end

local function Ago(at)
    return ns.Ago(time() - at)
end

local function MapName(map)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    local name = type(info) == "table" and Plain(info.name)
    return type(name) == "string" and name ~= "" and name or ("map " .. map)
end

local function HereMap()
    local map = C_Map and C_Map.GetBestMapForUnit and Plain(C_Map.GetBestMapForUnit("player"))
    return type(map) == "number" and map or nil
end

---------------------------------------------------------------------------
-- Who runs ZodUI
---------------------------------------------------------------------------

-- "0.31.2" > "0.31.0"
local function Newer(a, b)
    local x, y = {}, {}
    for n in tostring(a):gmatch("%d+") do x[#x + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do y[#y + 1] = tonumber(n) end
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end
M.Newer = Newer

local function Heard(name, version)
    local v = type(version) == "string" and version:match("^%d+%.%d+%.?%d*$") and version or nil
    members[name] = { version = v or (members[name] and members[name].version) or "?", at = time() }
    if v and Newer(v, ns.version) and (not told or Newer(v, told)) then
        told = v
        ns.Print("a newer ZodUI (" .. v .. ") runs in your guild; you have " .. ns.version .. ".")
    end
end

local pinged = -1000 -- GetTime() of your last /zod guild: hellos whispered back are taken for a while after
Bus.Listen("H", function(name, f, channel)
    if channel == "WHISPER" and (GetTime() - pinged) > 30 then return end
    Heard(name, f[1])
end, M)
-- Someone asked who runs ZodUI: answer them alone.
Bus.Listen("P", function(name, f, channel, full)
    if channel ~= "GUILD" then return end
    Heard(name)
    Bus.Send("H", { ns.version }, full)
end, M)

function M:Members()
    local list = {}
    for name, m in pairs(members) do list[#list + 1] = { name = name, version = m.version, at = m.at } end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

---------------------------------------------------------------------------
-- Rares
---------------------------------------------------------------------------

local function Rares()
    ns.db.rares = ns.db.rares or {}
    return ns.db.rares
end

local function Recent(npc)
    for _, r in ipairs(Rares()) do
        if time() - r.at >= RARE_QUIET then return nil end
        if r.npc == npc then return r end
    end
end

local function Keep(r)
    local list = Rares()
    table.insert(list, 1, r)
    while #list > RARES_KEEP do table.remove(list) end
    ns.Refresh()
end

-- A rare in front of you: told once to the guild.
function M:Scan(unit)
    if not self.db.rares or not Bus.On() then return end
    if Plain(UnitIsPlayer(unit)) then return end
    local class = UnitClassification and Plain(UnitClassification(unit))
    if not RARE[class] then return end
    local guid = Plain(UnitGUID(unit))
    local npc = type(guid) == "string" and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
    local name = Plain(UnitName(unit))
    if not npc or type(name) ~= "string" or name == "" then return end
    local x, y, map = ns.Coords()
    if not x then return end -- not in instances
    local dead = (UnitIsDead and Plain(UnitIsDead(unit))) and true or false
    local last = Recent(npc)
    if last and last.dead == dead then return end
    local r = { npc = npc, name = CleanText(name, NAME_MOST), map = map, x = math.floor(x * 10 + 0.5), y = math.floor(y * 10 + 0.5),
        dead = dead, at = time(), by = ns.MyName(), class = class }
    Keep(r)
    Bus.Send("R", { r.npc, r.name, r.map, r.x, r.y, dead and 1 or 0, class })
end

M:On("PLAYER_TARGET_CHANGED", function(self) self:Scan("target") end)
M:On("UPDATE_MOUSEOVER_UNIT", function(self) self:Scan("mouseover") end)

Bus.Listen("R", function(name, f, channel)
    if channel ~= "GUILD" then return end
    Heard(name)
    local npc, map = Num(f[1], 1, 10000000), Num(f[3], 1, 100000)
    local x, y = Num(f[4], 0, 1000), Num(f[5], 0, 1000)
    local rname = CleanText(f[2], NAME_MOST)
    local dead = f[6] == "1"
    local class = RARE[f[7]] and f[7] or "rare"
    if not (npc and map and x and y) or rname == "" then return end
    local last = Recent(npc)
    if last and last.dead == dead then return end
    Keep({ npc = npc, name = rname, map = map, x = x, y = y, dead = dead, at = time(), by = name, class = class })
    if M.db.rareNotice and map == HereMap() then
        local what = class == "worldboss" and "World boss" or "Rare"
        if dead then
            ns.Print(rname .. " was killed (" .. name .. " saw it).")
        else
            ns.Alert(what .. ": " .. rname .. ", " .. name .. " saw it near " .. string.format("%.1f, %.1f", x / 10, y / 10) .. ". /zod guild way")
        end
    end
end, M)

-- A waypoint to the n-th rare in the list.
function M:Way(n)
    local r = Rares()[n or 1]
    if not r then return false, "no rares kept yet. Guild members with ZodUI tell you the ones they see." end
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return false, "this client cannot set waypoints."
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(r.map) then
        return false, "a waypoint cannot be set on " .. MapName(r.map) .. "."
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(r.map, r.x / 1000, r.y / 1000))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    return true, "waypoint to " .. r.name .. " in " .. MapName(r.map) .. string.format(" (%.1f, %.1f).", r.x / 10, r.y / 10)
end

---------------------------------------------------------------------------
-- Who else has a quest
---------------------------------------------------------------------------

local function QuestTitle(id)
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and Plain(C_QuestLog.GetTitleForQuestID(id))
    return type(title) == "string" and title ~= "" and title or ("quest " .. id)
end

-- How far you are with a quest in your log: "done", "3/8", or nil when it is not in your log.
local function Progress(id)
    local log = C_QuestLog
    if not (log and log.GetLogIndexForQuestID and log.GetLogIndexForQuestID(id)) then return nil end
    if log.IsComplete and log.IsComplete(id) then return "done" end
    local have, need = 0, 0
    for _, o in ipairs(log.GetQuestObjectives and log.GetQuestObjectives(id) or {}) do
        have = have + (tonumber(Plain(o.numFulfilled)) or 0)
        need = need + (tonumber(Plain(o.numRequired)) or 0)
    end
    return have .. "/" .. need
end

-- From what was typed: a quest link, a quest id, or part of a title in your log. Returns id, or nil and why.
function M.ParseQuest(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local id = tonumber(arg:match("|Hquest:(%d+)") or arg:match("^(%d+)$") or "")
    if id then return id end
    if arg == "" then return nil, "shift-click a quest into the command, or type part of its name." end
    local want = arg:lower()
    local log = C_QuestLog
    for i = 1, log and log.GetNumQuestLogEntries and log.GetNumQuestLogEntries() or 0 do
        local q = log.GetInfo(i)
        local title = q and Plain(q.title)
        if q and not q.isHeader and type(title) == "string" and title:lower():find(want, 1, true) then return q.questID end
    end
    return nil, "no quest in your log is called '" .. arg .. "'."
end

local function Finish(id)
    local p = pending[id]
    pending[id] = nil
    if not p then return end
    if #p.answers == 0 then
        if not p.auto then ns.Print("no one in your guild with ZodUI has " .. p.title .. ".") end
        return
    end
    table.sort(p.answers, function(a, b) return a.name < b.name end)
    local shown = {}
    for i = 1, math.min(#p.answers, SHOW_MOST) do
        local a = p.answers[i]
        shown[i] = PlayerLink(a.name) .. " |cff999999(" .. a.level .. ", " .. a.zone .. ": " .. a.progress .. ")|r"
    end
    ns.Print(p.title .. ": " .. (p.auto and "others in your guild have it too: " or "")
        .. table.concat(shown, ", ") .. (#p.answers > SHOW_MOST and (" and " .. (#p.answers - SHOW_MOST) .. " more") or "") .. ".")
end

function M:AskQuest(quest, auto)
    if not Bus.On() then return false, "the guild network needs a guild." end
    for _, p in pairs(pending) do
        if p.quest == quest then return false, "already asking about " .. p.title .. "." end
    end
    local id = Bus.NewID()
    pending[id] = { quest = quest, title = QuestTitle(quest), answers = {}, auto = auto, from = {} }
    Bus.Send("Q", { id, quest })
    ns.After(WAIT, function() Finish(id) end)
    return true, pending[id].title
end

Bus.Listen("Q", function(name, f, channel, full)
    if channel ~= "GUILD" or not M.db.answer then return end
    Heard(name)
    local quest = Num(f[2], 1, 10000000)
    if not quest or not (f[1] or ""):match("^%d+$") then return end
    local progress = Progress(quest)
    if not progress then return end
    Bus.Send("q", { f[1], quest, ns.Level() or 0, progress, GetRealZoneText and GetRealZoneText() or "" }, full)
end, M)

Bus.Listen("q", function(name, f, channel)
    if channel ~= "WHISPER" then return end
    local p = pending[f[1]]
    if not p or Num(f[2], 1, 10000000) ~= p.quest or p.from[name] or #p.answers >= ANSWERS_MOST then return end
    local level = Num(f[3], 1, 100)
    local progress = (f[4] == "done" or (f[4] or ""):match("^%d+/%d+$")) and f[4] or nil
    if not (level and progress) then return end
    p.from[name] = true
    p.answers[#p.answers + 1] = { name = name, level = level, progress = progress, zone = CleanText(f[5], 40) }
end, M)

-- Taking a group quest asks who else has it.
M:On("QUEST_ACCEPTED", function(self, _, quest)
    quest = Plain(quest)
    if not self.db.groupAsk or type(quest) ~= "number" then return end
    local size = C_QuestLog and C_QuestLog.GetSuggestedGroupSize and Plain(C_QuestLog.GetSuggestedGroupSize(quest))
    if type(size) == "number" and size > 1 then self:AskQuest(quest, true) end
end)

---------------------------------------------------------------------------

M:On("PLAYER_ENTERING_WORLD", function(self, _, login, reload)
    if (login or reload) and not self.said then
        self.said = true
        ns.After(15, function() Bus.Send("H", { ns.version }) end)
    end
end)

function M:Slash(arg)
    local verb, rest = arg:match("^(%S*)%s*(.-)$")
    verb = verb:lower()
    if not (IsInGuild and IsInGuild()) then ns.Print("you are not in a guild.") return end
    if verb == "" or verb == "who" then
        pinged = GetTime()
        Bus.Send("P", {})
        local list = self:Members()
        ns.Print("asking who in your guild runs ZodUI" .. (#list > 0 and ("; heard so far: " .. #list) or "") .. ". /zod guild list in a moment shows them.")
        return
    end
    if verb == "list" then
        local list = self:Members()
        if #list == 0 then ns.Print("no one in your guild with ZodUI heard from yet. /zod guild asks.") return end
        local shown = {}
        for i, m in ipairs(list) do shown[i] = PlayerLink(m.name) .. " |cff999999" .. m.version .. "|r" end
        ns.Print(#list .. " in your guild run ZodUI: " .. table.concat(shown, ", ") .. ".")
        return
    end
    if verb == "rares" then
        local list = Rares()
        if #list == 0 then ns.Print("no rares kept yet. Guild members with ZodUI tell you the ones they see.") return end
        ns.Print("rares the guild saw (/zod guild way <number> sets a waypoint):")
        for i = 1, math.min(#list, 10) do
            local r = list[i]
            print(string.format("  %d. %s%s  |cff999999%s (%.1f, %.1f), %s, %s|r", i, r.name, r.dead and " (killed)" or "",
                MapName(r.map), r.x / 10, r.y / 10, r.by or "?", Ago(r.at)))
        end
        return
    end
    if verb == "way" then
        local _, said = self:Way(tonumber(rest) or 1)
        ns.Print(said)
        return
    end
    if verb == "quest" then
        local quest, why = M.ParseQuest(rest)
        if not quest then ns.Print(why) return end
        local ok, said = self:AskQuest(quest, false)
        ns.Print(ok and ("asking your guild who has " .. said .. "...") or said)
        return
    end
    ns.Print("use /zod guild, /zod guild list, rares, way <number> or quest <quest>.")
end

function M:Card()
    local list, n = Rares(), 0
    for _ in pairs(members) do n = n + 1 end
    if n == 0 and #list == 0 then return nil end
    local lines = { { "ZodUI in guild", n } }
    if list[1] then lines[2] = { "Last rare", list[1].name .. "  |cff999999" .. Ago(list[1].at) .. "|r" } end
    return { title = "Guild network", lines = lines }
end

function M:Find(part, add, has)
    for i, r in ipairs(Rares()) do
        if has(r.name) then add("Rare", r.name, MapName(r.map) .. ", " .. Ago(r.at) .. " (/zod guild way " .. i .. ")", "settings", "guild") end
    end
end
