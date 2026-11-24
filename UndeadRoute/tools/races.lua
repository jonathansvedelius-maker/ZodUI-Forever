-- Every race and both factions: logs a character of each race in (a fresh load of the addon each
-- time) and checks the route it gets, its class quests and the faction filters. Run by run.js
-- after harness.lua, in a Lua state of its own.
local DATA = assert(load(@DATA@, "Data.lua"))
local GEN = assert(load(@GEN@, "Generated.lua"))
-- The addon's own three files, in the .toc's order.
local ROUTE, WINDOW, WIRING = assert(load(@ROUTE@, "Route.lua")), assert(load(@WINDOW@, "Window.lua")), assert(load(@CORE@, "Core.lua"))
local GUIDE = assert(load(@GUIDE@, "Guide.lua"))
local function CORE(...) ROUTE(...) WINDOW(...) GUIDE(...) WIRING(...) end

local say = function(s) io.write(s .. "\n") end
local function plain(s) return ((s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- The stubbed game: every widget method exists and does nothing, except what the addon reads back.
local frames
local function Widget()
    local w = { scripts = {}, shown = true }
    return setmetatable(w, { __index = function(_, k)
        if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
        if k == "SetText" then return function(self, t) self.text = t end end
        if k == "GetFont" then return function(self) return "Font", rawget(self, "fsize") or 10, "" end end
        if k == "SetFont" then return function(self, _, size) self.fsize = size end end
        if k == "GetStringHeight" then return function() return 12 end end
        if k == "GetHeight" then return function(self) return self.h or 100 end end
        if k == "SetHeight" then return function(self, h) self.h = h end end
        if k == "GetVerticalScroll" then return function() return 0 end end
        if k == "Show" then return function(self) self.shown = true end end
        if k == "Hide" then return function(self) self.shown = false end end
        if k == "SetShown" then return function(self, s) self.shown = s and true or false end end
        if k == "IsShown" then return function(self) return self.shown end end
        if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
        if k == "CreateFontString" or k == "CreateTexture" then return function() return Widget() end end
        return function() end
    end })
end
function CreateFrame(kind, name)
    local f = Widget()
    f.kind = kind
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
UIParent, GameTooltip, UISpecialFrames, tinsert = Widget(), Widget(), {}, table.insert
SlashCmdList = {}
C_Timer = { After = function(_, fn) fn() end }
UIErrorsFrame = { AddMessage = function() end }
print = function() end
local done = {}
C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return done[id] or false end,
    IsOnQuest = function() return false end,
    IsComplete = function() return false end,
}
C_Map = { GetBestMapForUnit = function() return 0 end }
function GetBindLocation() return "" end

local CLASSES = { WARRIOR = { "Warrior", 1 }, PALADIN = { "Paladin", 2 }, HUNTER = { "Hunter", 3 }, ROGUE = { "Rogue", 4 },
    PRIEST = { "Priest", 5 }, SHAMAN = { "Shaman", 7 }, MAGE = { "Mage", 8 }, WARLOCK = { "Warlock", 9 }, DRUID = { "Druid", 11 } }

-- Logs in a character and returns the addon's ns and the event frame.
local level, zone = 1, ""
local function Login(c)
    frames, done = {}, {}
    level, zone = c.level or 1, c.zone
    UndeadRouteDB, UndeadRouteFrame, UndeadRouteTracker, UndeadRoute = nil, nil, nil, nil
    function UnitLevel() return level end
    function UnitClass() return CLASSES[c.class][1], c.class, CLASSES[c.class][2] end
    function UnitRace() return c.raceName, c.raceFile, c.race end
    function UnitFactionGroup() return c.faction, c.faction end
    function GetRealZoneText() return zone end
    local ns = {}
    DATA("UndeadRoute", ns) GEN("UndeadRoute", ns) CORE("UndeadRoute", ns)
    local events
    for _, f in ipairs(frames) do if f.scripts.OnEvent then events = f end end
    events.scripts.OnEvent(events, "ADDON_LOADED", "UndeadRoute")
    events.scripts.OnEvent(events, "PLAYER_LOGIN")
    return ns, function(e, a) events.scripts.OnEvent(events, e, a) end
end

local function Keys(ns)
    local keys = {}
    for _, s in ipairs(ns.Stages) do keys[s.key] = s end
    return keys
end

-- QuestAllowed: side, race (with the Skyborne rule) and class masks.
do
    local ns = {}
    DATA("UndeadRoute", ns) GEN("UndeadRoute", ns)
    frames = {}
    function UnitLevel() return 1 end
    CORE("UndeadRoute", ns)
    local A = ns.QuestAllowed
    assert(A({ side = "H" }, "H", 5) and not A({ side = "H" }, "A", 1), "side limit")
    assert(A({ race = 16 }, "H", 5) and not A({ race = 16 }, "H", 2), "race bit 5 is the Undead")
    assert(A({ race = 2 ^ 32 }, "A", 95) and not A({ race = 2 ^ 32 }, "H", 96), "Skyborne own bits")
    assert(A({ race = 77 }, "A", 95), "an Alliance-wide Classic mask lets the High Order Skyborne in")
    assert(not A({ race = 8 }, "A", 95), "a Night Elf quest is not the Skyborne's")
    assert(A({ race = 178 }, "H", 96) and not A({ race = 178 }, "A", 95), "a Horde-wide mask is the Windshaper's only")
    assert(A({ class = 2 }, "H", 5, 2) and not A({ class = 2 }, "H", 5, 1), "class mask")
    assert(A({ class = 1247 }, "H", 2, 1) and not A({ class = 1247 }, "H", 2, 9), "every class but the Warlock")
    say("QuestAllowed: side, race, Skyborne and class masks OK")
end

-- SelectRoute: the stages each faction and race gets, straight from Data.lua.
do
    local ns = {}
    DATA("UndeadRoute", ns)
    frames = {}
    CORE("UndeadRoute", ns)
    local all = ns.Stages
    local function keys(faction, race)
        local k = {}
        for _, s in ipairs(ns.SelectRoute(all, faction, race)) do k[s.key] = s end
        return k
    end
    local undead, orc, human, nelf = keys("Horde", 5), keys("Horde", 2), keys("Alliance", 1), keys("Alliance", 4)
    assert(undead.deathknell and not undead["valley-of-trials"] and not undead.northshire, "Undead start")
    assert(orc["valley-of-trials"] and not orc.deathknell and orc["barrens-north"] and not orc["silverpine-north"], "Orc start")
    assert(human.northshire and human.westfall.kind == "zone" and not human.undercity and human.stormwind, "Human start")
    assert(nelf.westfall.kind == "alt" and nelf.ashenvale.kind == "zone" and human.ashenvale.kind == "alt", "altRaces")
    assert(human.riverglades.hub == "Alliance quest hubs" and undead.riverglades.hub == "Rog'mar", "faction override")
    assert(human.blackmaw.x == nil and undead.blackmaw.x == 22, "false clears a field")
    assert(not human.riverglades.Alliance and not human.riverglades.Horde, "override tables left on a stage")
    assert(human.arathi.hub == "Refuge Pointe" and undead.arathi.hub == "Hammerfall", "one key, two factions")
    -- The selection copies: adding steps for one character leaves Data.lua's list as it was.
    local before = #all[1].tasks
    table.insert(ns.SelectRoute(all, "Horde", 5)[1].tasks, { t = "x" })
    assert(#all[1].tasks == before, "SelectRoute shares the step lists with Data.lua")
    say("SelectRoute: start zones, alt branches, faction overrides OK")
end

-- Every race: a fresh login at level 1 in its start zone, then the route from 1 to 60.
local RACES = {
    { race = 1, raceFile = "Human", raceName = "Human", faction = "Alliance", class = "MAGE", start = "northshire", zone = "Elwynn Forest" },
    { race = 3, raceFile = "Dwarf", raceName = "Dwarf", faction = "Alliance", class = "HUNTER", start = "coldridge", zone = "Dun Morogh" },
    { race = 4, raceFile = "NightElf", raceName = "Night Elf", faction = "Alliance", class = "DRUID", start = "shadowglen", zone = "Teldrassil" },
    { race = 7, raceFile = "Gnome", raceName = "Gnome", faction = "Alliance", class = "WARLOCK", start = "coldridge", zone = "Dun Morogh" },
    { race = 95, raceFile = "Skyborne", raceName = "High Order Skyborne", faction = "Alliance", class = "ROGUE", start = "zephras-start", zone = "Zephras Isle" },
    { race = 2, raceFile = "Orc", raceName = "Orc", faction = "Horde", class = "WARRIOR", start = "valley-of-trials", zone = "Durotar" },
    { race = 5, raceFile = "Scourge", raceName = "Undead", faction = "Horde", class = "PALADIN", start = "deathknell", zone = "Tirisfal Glades" },
    { race = 6, raceFile = "Tauren", raceName = "Tauren", faction = "Horde", class = "SHAMAN", start = "camp-narache", zone = "Mulgore" },
    { race = 8, raceFile = "Troll", raceName = "Troll", faction = "Horde", class = "PRIEST", start = "valley-of-trials", zone = "Durotar" },
    { race = 96, raceFile = "Skyborne", raceName = "Windshaper Skyborne", faction = "Horde", class = "SHAMAN", start = "zephras-start", zone = "Zephras Isle" },
}
local CITIES = { Horde = { "undercity", "orgrimmar", "thunder-bluff" }, Alliance = { "stormwind", "ironforge", "darnassus" } }
for _, c in ipairs(RACES) do
    local ns, fire = Login(c)
    local keys = Keys(ns)
    local sideCode = c.faction == "Alliance" and "A" or "H"
    local other = c.faction == "Alliance" and "Horde" or "Alliance"
    -- The start zone is the recommendation at level 1.
    local status = UndeadRoute.Status()
    local startStage = keys[c.start]
    assert(startStage and startStage.kind == "zone", c.raceName .. ": no start stage " .. c.start)
    assert(status.stage == c.zone and status.hub == startStage.hub,
        c.raceName .. ": starts in " .. status.stage .. ", " .. status.hub .. ", not " .. c.zone)
    -- Capitals follow the faction.
    for _, key in ipairs(CITIES[c.faction]) do assert(keys[key] and keys[key].kind == "city", c.raceName .. ": no " .. key) end
    for _, key in ipairs(CITIES[other]) do assert(not keys[key], c.raceName .. ": has the other side's " .. key) end
    -- Every quest on the list is one this character may take; zone stages all have quests.
    local quests, perStage = 0, {}
    for _, s in ipairs(ns.Stages) do
        local n = 0
        for _, t in ipairs(s.tasks) do
            if t.id then
                n = n + 1
                assert(ns.QuestAllowed(t.quest, sideCode, c.race, CLASSES[c.class][2]),
                    c.raceName .. ": " .. t.quest.name .. " (" .. t.id .. ") on " .. s.key .. " is not theirs")
            end
        end
        if s.kind == "zone" or s.kind == "city" then assert(n > 0, c.raceName .. ": no quests on " .. s.key) end
        if s.kind == "dungeon" and s.ally then
            assert(s.note and s.note:find(other, 1, true), c.raceName .. ": " .. s.key .. " is in no enemy land")
        end
        quests = quests + n
        perStage[s.key] = n
    end
    -- Class quests: the stage is named and keyed after the class, and holds only quests this race and side can take.
    if c.faction == "Alliance" then
        assert(keys["d:Ruins of Lordaeron"] and keys["d:Ruins of Lordaeron"].ally, c.raceName .. ": Ruins of Lordaeron not marked Horde land")
        assert(keys["d:The Deadmines"] and keys["d:The Deadmines"].route, c.raceName .. ": the Deadmines not on the route")
    else
        assert(keys["d:Ragefire Chasm"] and keys["d:Ragefire Chasm"].route == nil and not keys["d:Ragefire Chasm"].ally,
            c.raceName .. ": Ragefire Chasm is not Horde-side")
        assert(not keys["d:The Deadmines"] or keys["d:The Deadmines"].ally, c.raceName .. ": the Deadmines not marked Alliance land")
        assert(not keys["d:The Stockade"], c.raceName .. ": an Alliance-only dungeon listed")
    end
    local class = keys[c.class:lower()]
    local className = CLASSES[c.class][1]
    assert(class and class.kind == "class" and class.zone == className .. " class quests",
        c.raceName .. ": no " .. className .. " class stage")
    assert(#class.tasks > 0, c.raceName .. " " .. className .. ": no class quests")
    -- The route from 1 to 60: where it sends you at each level.
    local path, last = {}, nil
    for lv = 1, 60 do
        level = lv
        fire("PLAYER_LEVEL_UP", lv)
        local s = UndeadRoute.Status()
        local where = s.stage .. " (" .. s.hub .. ")"
        if where ~= last then path[#path + 1] = lv .. " " .. where last = where end
    end
    assert(last:find("^Mount Hyjal"), c.raceName .. ": the route does not reach Mount Hyjal at 60")
    say(string.format("%-20s %-8s %-8s %3d stages, %4d quests, %3d %s class quests", c.raceName, c.faction, className,
        #ns.Stages, quests, #class.tasks, className))
    say("    " .. table.concat(path, " > ", 1, math.min(#path, 7)) .. (#path > 7 and " > ..." or ""))
end

-- The class lines name the class in its color: an Orc Warrior with a Warrior quest open.
do
    local c = RACES[6]
    local ns, fire = Login({ race = 2, raceFile = "Orc", raceName = "Orc", faction = "Horde", class = "WARRIOR",
        zone = "Durotar", level = 10 })
    local class = Keys(ns).warrior
    local open
    for _, t in ipairs(class.tasks) do
        if not open and (t.req or 1) <= 10 and not t.quest.needs and not t.quest.classic then open = t end
    end
    assert(open, "no open Warrior quest at 10 for an Orc")
    fire("QUEST_LOG_UPDATE")
    local body = UndeadRouteTracker.body.text or ""
    assert(body:find("|cffc69b6dWarrior:|r", 1, true), "tracker has no Warrior line: " .. plain(body))
    assert(not plain(body):find("Paladin", 1, true), "tracker still says Paladin")
    SlashCmdList["UNDEADROUTE"]("")
    assert(plain(UndeadRouteFrame.sub.text) == "Horde 1-60, WoW Forever", "window subtitle: " .. plain(UndeadRouteFrame.sub.text))
    say("class line: " .. plain(body):match("Warrior:[^\n]*"))
    -- A Human Mage: Alliance subtitle, Mage class stage, no Horde quests among the Mage quests.
    local ns2 = Login({ race = 1, raceFile = "Human", raceName = "Human", faction = "Alliance", class = "MAGE",
        zone = "Elwynn Forest", level = 10 })
    SlashCmdList["UNDEADROUTE"]("")
    assert(plain(UndeadRouteFrame.sub.text) == "Alliance 1-60, WoW Forever", "Alliance subtitle")
    for _, t in ipairs(Keys(ns2).mage.tasks) do assert(t.quest.side ~= "H", "Horde Mage quest for a Human") end
    say("Human Mage: " .. #Keys(ns2).mage.tasks .. " Mage quests, none Horde-only")
end
say("RACES OK")
