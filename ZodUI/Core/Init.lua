local ADDON, ns = ...

-- ZodUI: a suite of small modules behind one window.
--   Core\Init.lua     the module registry, events, timers, saved data and /zod
--   Core\Theme.lua    the palette and every widget the pages are built from
--   Core\Window.lua   the window: Home, the module pages, Settings
--   Core\Minimap.lua  the minimap button
--   Modules\*.lua     one file per module; each registers itself with ns:NewModule
-- A module that fails never takes the others with it: every handler runs
-- guarded, and what went wrong is kept for /zod errors.

ZodUI = ns
ns.version = "0.64.0"
ns.modules = {} -- by key
ns.order = {} -- in load order, which is the order Settings lists them
ns.errors = {}

local errorCount = {}

function ns.Print(msg)
    print("|cffffd100ZodUI:|r " .. tostring(msg))
end

-- Runs fn(...) and survives it failing. The first failure of a kind is said in chat.
function ns.Guard(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local key = where .. ": " .. tostring(err)
        if not errorCount[key] then
            errorCount[key] = 0
            ns.errors[#ns.errors + 1] = key
            if #ns.errors <= 3 then
                ns.Print("|cffff6060" .. where .. " failed.|r /zod errors shows what went wrong.")
            end
        end
        errorCount[key] = errorCount[key] + 1
    end
    return ok
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------

function ns.Comma(n)
    local s = string.format("%d", math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""):gsub("^%-,", "-"))
end

-- 12g 34s 56c with the coin colours, leaving out a unit that is 0 (25s, not 25s 0c; 0c only for nothing at all);
-- `short` keeps the two largest units.
function ns.Money(copper, short)
    local sign = copper < 0 and "-" or ""
    local c = math.floor(math.abs(copper) + 0.5)
    local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = ns.Comma(g) .. "|cffffd100g|r" end
    if s > 0 then parts[#parts + 1] = s .. "|cffc7c7cfs|r" end
    if k > 0 and not (short and g > 0) then parts[#parts + 1] = k .. "|cffeda55fc|r" end
    if #parts == 0 then parts[1] = "0|cffeda55fc|r" end
    return sign .. table.concat(parts, " ")
end

function ns.Duration(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    if sec < 60 then return sec .. "s" end
    if sec < 3600 then return math.floor(sec / 60) .. "m" end
    local big, small
    if sec < 86400 then
        big, small = math.floor(sec / 3600) .. "h", math.floor(sec % 3600 / 60)
        return small > 0 and (big .. " " .. small .. "m") or big
    end
    big, small = math.floor(sec / 86400) .. "d", math.floor(sec % 86400 / 3600)
    return small > 0 and (big .. " " .. small .. "h") or big
end

-- How long ago, the same way on every page: "just now", "5m ago", "3h 10m ago", "2d 4h ago".
function ns.Ago(seconds)
    seconds = math.max(0, seconds or 0)
    if seconds < 60 then return "just now" end
    return ns.Duration(seconds) .. " ago"
end

-- A moment in the past, the same way on every page: "today 14:30", "yesterday 14:30", "12 Nov 14:30" this
-- year, "12 Nov 2024" before. noTime leaves the clock out ("today", "12 Nov").
function ns.When(at, noTime)
    if not at then return "-" end
    local day = date("%Y-%m-%d", at)
    local clock = noTime and "" or (" " .. date("%H:%M", at))
    if day == date("%Y-%m-%d") then return "today" .. clock end
    if day == date("%Y-%m-%d", time() - 86400) then return "yesterday" .. clock end
    if date("%Y", at) == date("%Y") then return date("%d %b", at) .. clock end
    return date("%d %b %Y", at)
end

-- "2026-11-19" (a day's key, ns.Today) -> noon of that day, for ns.When.
function ns.DayTime(key)
    local y, m, d = tostring(key or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return nil end
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

-- ns.When for a table cell: it shows the words and sorts by the moment itself.
function ns.WhenCell(at, noTime)
    return { ns.When(at, noTime), at or 0 }
end

function ns.Today(offsetDays)
    return date("%Y-%m-%d", time() - (offsetDays or 0) * 86400)
end

-- A calendar date -> days since 1970-01-01, by the calendar alone (no time zone, no daylight saving).
-- Story numbers its days with it, the Raid planner counts down to calendar events.
function ns.CivilDay(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local CLASS_HEX = {
    WARRIOR = "ffc79c6e", PALADIN = "fff58cba", HUNTER = "ffabd473", ROGUE = "fffff569", PRIEST = "ffffffff",
    SHAMAN = "ff0070de", MAGE = "ff69ccf0", WARLOCK = "ff9482c9", DRUID = "ffff7d0a",
}

function ns.ClassHex(classFile)
    local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    return c and c.colorStr or CLASS_HEX[classFile or ""] or "ffffffff"
end

-- The player's position on the map they stand on, 0-100, or nil where the game gives none (instances).
function ns.Coords()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end
    return x * 100, y * 100, map
end

-- /zod where: where you stand, in chat, or said to your group or guild. Returns the text.
function ns.Where(to)
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local x, y = ns.Coords()
    local text = zone .. ((sub ~= "" and sub ~= zone) and (", " .. sub) or "") .. (x and string.format(" (%.1f, %.1f)", x, y) or "")
    local channel
    if to == "party" or to == "group" or to == "p" then
        channel = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY") or nil
        if not channel then
            ns.Print("you are not in a group. You are in " .. text .. ".")
            return
        end
    elseif to == "guild" or to == "g" then
        channel = (IsInGuild and IsInGuild()) and "GUILD" or nil
        if not channel then
            ns.Print("you are not in a guild. You are in " .. text .. ".")
            return
        end
    elseif to == "text" then
        return text
    elseif to ~= nil and to ~= "" then
        ns.Print("use /zod where, /zod where party or /zod where guild.")
        return
    end
    if channel then
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        if send then send(text, channel) end
    else
        ns.Print("you are in " .. text .. ".")
    end
    return text
end

function ns.BagSlots()
    local free, total = 0, 0
    if not (C_Container and C_Container.GetContainerNumSlots) then return free, total end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        total = total + (C_Container.GetContainerNumSlots(bag) or 0)
        free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
    end
    return free, total
end

-- The most worn piece of equipped gear, as a fraction; nil when nothing worn has durability.
function ns.Durability()
    if not GetInventoryItemDurability then return end
    local lowest
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local f = cur / max
            if not lowest or f < lowest then lowest = f end
        end
    end
    return lowest
end

function ns.AddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) and true or false end
    if IsAddOnLoaded then return IsAddOnLoaded(name) and true or false end
    return false
end

-- The other addons parts of ZodUI need, and what for. A module names the ones it needs (info.needs), and its
-- settings say whether each is installed; General lists them all. Without one, only that part does nothing.
ns.NEEDS = {
    ForeverLevelingBiS = { name = "Forever Leveling BiS",
        what = "its stat weights: Hand-me-downs needs them for everything, Loot shout for the upgrades" },
    ForeverDungeonJournal = { name = "ForeverDungeonJournal",
        what = "its map pictures: the Dungeon guide shows them for Forever's dungeons and the ones the game has no map for" },
    CodexForever = { name = "Codex Forever",
        what = "Alt-click on an item opens it there, and the search ends with a Codex line" },
}
ns.NEEDS_ORDER = { "ForeverLevelingBiS", "ForeverDungeonJournal", "CodexForever" }

-- One line about a needed addon: its name, whether it is on, and what it is for.
function ns.NeedText(addon)
    local need = ns.NEEDS[addon]
    if not need then return "" end
    local on = ns.AddOnLoaded(addon)
    return (on and "|cff59d973Installed:|r " or "|cffff5959Needs|r ") .. "|cffffffff" .. need.name .. "|r, for " .. need.what .. "."
end

-- The last notices, newest first, for /zod notices.
ns.noticeLog = {}
local LOG_MOST = 30

-- Reads a notice aloud with the game's text to speech (voice, speed and volume from Options > Accessibility).
-- The same text twice within SPEAK_GAP seconds is read once.
local SPEAK_GAP = 2
local lastSpoken, lastSpokenAt
function ns.Speak(msg)
    local general = ns.db and ns.db.general
    local VC = C_VoiceChat
    if not (general and general.speak and VC and VC.SpeakText) then return end
    local text = tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
    text = text:gsub("%[", ""):gsub("%]", "")
    local now = GetTime and GetTime() or 0
    if text == lastSpoken and lastSpokenAt and now - lastSpokenAt < SPEAK_GAP then return end
    lastSpoken, lastSpokenAt = text, now
    local TTS = C_TTSSettings
    local voice = TTS and TTS.GetVoiceOptionID and TTS.GetVoiceOptionID(0) or 0
    local rate = TTS and TTS.GetSpeechRate and TTS.GetSpeechRate() or 0
    local volume = TTS and TTS.GetSpeechVolume and TTS.GetSpeechVolume() or 100
    pcall(VC.SpeakText, voice, text, rate, volume, false)
end

-- A message in the middle of the screen and in chat.
-- opts (optional): { click = function, hint = text }: clicking the notice runs click, and hovering it shows hint.
function ns.Alert(msg, opts)
    table.insert(ns.noticeLog, 1, { time(), msg })
    if #ns.noticeLog > LOG_MOST then table.remove(ns.noticeLog) end
    if ns.db and ns.db.general.toasts and ns.Toast then
        ns.Guard("notice", ns.Toast, msg, opts)
    elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1, 0.82, 0)
    end
    ns.Guard("speak", ns.Speak, msg)
    ns.Print(msg)
end

---------------------------------------------------------------------------
-- Events and timers
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}
local timers = {}

-- The profiler (/zod perf): nil, or label -> { ms, calls, slowest } while it runs. Each handler, timer and
-- hook runs through ns.Run, which times it only while the profiler is on.
local prof
local Now = debugprofilestop

local function Record(label, start, ...)
    local ms = Now() - start
    local p = prof and prof[label]
    if prof and not p then
        p = { 0, 0, 0 }
        prof[label] = p
    end
    if p then
        p[1], p[2] = p[1] + ms, p[2] + 1
        if ms > p[3] then p[3] = ms end
    end
    return ...
end

-- Runs fn(...) as ns.Guard does, timed under `label` while profiling.
function ns.Run(label, fn, ...)
    if not prof or not Now then return ns.Guard(label, fn, ...) end
    return Record(label, Now(), ns.Guard(label, fn, ...))
end

-- fn wrapped to be timed under `label` while profiling, its results passed on (for hooks and chat filters).
function ns.Timed(label, fn)
    return function(...)
        if not prof or not Now then return fn(...) end
        return Record(label, Now(), fn(...))
    end
end

function ns.ProfileStart() prof = {} end
function ns.ProfileStop() local p = prof prof = nil return p end
function ns.Profiling() return prof end

-- fn(mod, event, ...) runs while `mod` is enabled; without a module it always runs.
function ns.On(event, fn, mod)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event) -- an event this client lacks must not stop the file
    end
    table.insert(handlers[event], { fn = fn, mod = mod, label = (mod and mod.key or "core") .. " " .. event })
end

-- The timers are looked at only when the soonest is due, not every frame: `waited` is the time since they were
-- last looked at, `due` how long until the soonest one. A timer added in between counts from now.
local waited, due = 0, 0

local function Add(t)
    t.left = t.left + waited
    if t.left < due then due = t.left end
    timers[#timers + 1] = t
end

function ns.Every(interval, fn, mod)
    Add({ interval = interval, left = interval, fn = fn, mod = mod, every = true,
        label = (mod and mod.key or "core") .. " timer" })
end

function ns.After(delay, fn)
    Add({ left = delay, fn = fn, label = "after" })
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local h = list[i]
        if not h.mod or h.mod.enabled then ns.Run(h.label, h.fn, h.mod, event, ...) end
    end
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + elapsed
    if waited < due then return end
    local step = waited
    waited = 0
    for i = #timers, 1, -1 do
        local t = timers[i]
        t.left = t.left - step
        if t.left <= 0 then
            if t.every then
                t.left = t.interval
                if not t.mod or t.mod.enabled then ns.Run(t.label, t.fn, t.mod) end
            else
                table.remove(timers, i)
                ns.Run(t.label, t.fn)
            end
        end
    end
    local soonest = math.huge
    for i = 1, #timers do
        if timers[i].left < soonest then soonest = timers[i].left end
    end
    due = soonest
end)

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------

local Module = {}
Module.__index = Module
local Attach, Start -- below: a module's saved settings, and switching it on at login

-- Set by Core\Window.lua: a module arrived after the window was built.
function ns.ModuleAdded() end

-- info: title, desc, defaults (settings; `enabled` is whether it starts on),
-- conflicts (addons that already do this: the module then starts off), recheck (see Start),
-- options (see Core\Window.lua), OnEnable, OnDisable, OnOption, Card.
function ns:NewModule(key, info)
    local m = setmetatable(info, Module)
    m.key = key
    m.enabled = false
    m.defaults = m.defaults or {}
    ns.modules[key] = m
    ns.order[#ns.order + 1] = m
    -- A plugin addon loads after ZodUI's saved data, and one loaded on demand after login.
    if ns.db then Attach(m) end
    if ns.ready then
        local held = Start(m, {}, {})
        if #held > 0 then ns.Print(m.title .. " starts switched off because " .. m.db.conflict .. " already does that.") end
        ns.Guard("late module", ns.ModuleAdded, m)
    end
    return m
end

function Module:On(event, fn)
    ns.On(event, fn, self)
end

function Module:Print(msg)
    ns.Print(msg)
end

function Module:Enable()
    if self.enabled then return end
    self.enabled = true
    self.db.enabled = true
    if self.OnEnable then ns.Guard(self.key .. " enable", self.OnEnable, self) end
    ns.Refresh()
end

function Module:Disable()
    if not self.enabled then return end
    self.enabled = false
    self.db.enabled = false
    if self.OnDisable then ns.Guard(self.key .. " disable", self.OnDisable, self) end
    ns.Refresh()
end

function ns.Refresh() end -- replaced by Core\Window.lua

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

local function Fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and Fill({}, v) or v
        elseif type(v) == "table" and type(dst[k]) == "table" then
            Fill(dst[k], v)
        end
    end
    return dst
end

local GENERAL = { font = 1, minimap = true, minimapAngle = 215, welcome = true, accent = "gold", look = "game", scale = 100, combatClose = true,
    toasts = true, greet = true, hideOff = true, remember = true, alpha = 100, toastHold = 5, toastSound = false, nextUp = true, speak = false }

local function LoadData()
    ZodUIDB = ZodUIDB or {}
    ZodUICharDB = ZodUICharDB or {}
    local db = ZodUIDB
    db.modules = db.modules or {}
    db.chars = db.chars or {}
    db.general = Fill(db.general or {}, GENERAL)
    db.window = db.window or {}
    ns.db, ns.chardb = db, ZodUICharDB
    for _, m in ipairs(ns.order) do Attach(m) end
end

-- The module's saved settings, with the defaults filled in.
function Attach(m)
    local saved = ns.db.modules[m.key] or {}
    ns.db.modules[m.key] = saved
    for k, v in pairs(m.defaults) do
        if k ~= "enabled" and saved[k] == nil then
            saved[k] = type(v) == "table" and Fill({}, v) or v
        end
    end
    m.db = saved
end

-- Switches the module on if it should be. The first time it is seen it starts
-- off when another addon already does its job; held and because collect that.
function Start(m, held, because)
    -- recheck (a number): a module that gained conflicts looks at them once more on a setup that already
    -- has it on; raising the number asks again. A module switched back on afterwards stays on.
    local first = m.db.enabled == nil
    local again = not first and m.recheck ~= nil and m.db.recheck ~= m.recheck
    if m.recheck then m.db.recheck = m.recheck end
    if first or again then
        local on = (first and m.defaults.enabled ~= false) or (again and m.db.enabled)
        for _, other in ipairs(m.conflicts or {}) do
            if ns.AddOnLoaded(other) then
                if on then
                    held[#held + 1] = m.title
                    if not because[other] then
                        because[other] = true
                        because[#because + 1] = other
                    end
                end
                on = false
                m.db.conflict = other
            end
        end
        m.db.enabled = on
    end
    if m.db.enabled then
        m.enabled = true
        if m.OnEnable then ns.Guard(m.key .. " enable", m.OnEnable, m) end
    end
    return held
end

local function Login()
    local name, realm = ns.MyName(), GetRealmName and GetRealmName() or "?"
    ns.charKey = (name or "?") .. "-" .. (realm or "?")
    local char = ns.db.chars[ns.charKey] or {}
    ns.db.chars[ns.charKey] = char
    local className, classFile = ns.MyClass()
    char.name, char.realm, char.class, char.className = name, realm, classFile, className
    char.race = ns.Plain(UnitRace("player"))
    if ns.T and ns.T.ApplyAccent then ns.T.ApplyAccent(ns.db.general.accent, classFile) end -- before any frame is built
    if ns.T and ns.T.ApplyLook then ns.T.ApplyLook(ns.db.general.look) end
    char.level = ns.Level()
    local away = char.seen and (time() - char.seen) -- how long this character was logged out
    char.seen = time()
    ns.char = char

    local held, because = {}, {}
    for _, m in ipairs(ns.order) do Start(m, held, because) end
    ns.ready = true
    if ns.db.general.welcome then
        ns.Print("v" .. ns.version .. " loaded. |cffffd100/zod|r opens it.")
    end
    local general = ns.db.general
    -- Said in chat, and a few seconds later as a notice too: in the login noise a chat line is easily missed.
    local later
    if not general.seenSetup then -- the first login ever
        general.seenSetup = true
        ns.Print("New here? |cffffd100/zod setup|r picks which modules run.")
        later = "New here? /zod setup picks which modules run."
    elseif general.lastVersion and general.lastVersion ~= ns.version then
        ns.Print("updated to v" .. ns.version .. ". |cffffd100/zod news|r says what is new.")
        later = "ZodUI is updated to v" .. ns.version .. ". What's new in the window says what changed."
        general.newsUnseen = true -- the window's What's new button is marked until opened
    end
    if later and general.toasts and ns.Toast then ns.After(8, function() ns.Guard("notice", ns.Toast, later) end) end
    general.lastVersion = ns.version
    if general.greet and away and away > 3600 then
        ns.After(6, function() -- once the login noise has passed
            local parts = { "away " .. ns.Duration(away) }
            local max = UnitXPMax("player") or 0
            local rested = GetXPExhaustion and GetXPExhaustion() or 0
            if max > 0 and rested > 0 then parts[#parts + 1] = "rested " .. math.floor(rested / max * 100) .. "%" end
            ns.Alert("Welcome back, " .. (char.name or "") .. ": " .. table.concat(parts, ", ") .. ".")
        end)
    end
    if #held > 0 then -- said once, the first time: a module that is silently off looks broken
        ns.Print(table.concat(held, ", ") .. (#held == 1 and " starts" or " start") .. " switched off because "
            .. table.concat(because, " and ") .. (#because == 1 and " already does that." or " already do that.")
            .. " |cffffd100/zod settings|r switches them on.")
    end
end

ns.On("ADDON_LOADED", function(_, _, name)
    if name == ADDON then LoadData() end
end)

ns.On("PLAYER_LOGIN", function()
    if not ns.db then LoadData() end
    Login()
end)

---------------------------------------------------------------------------
-- /zod
---------------------------------------------------------------------------

-- Every command, for /zod commands and the search: { command, what it does }.
ns.COMMANDS = {
    { "/zod", "Open or close the window" },
    { "/zod help", "The most used commands in chat" },
    { "/zod commands", "Every command as buttons" },
    { "/zod settings", "Open Settings" },
    { "/zod <page>", "Open a page: session, history, loot, runs, gold, rep, alts, items, notes, remind, goals..." },
    { "/zod rem, /zod his ...", "A page from the first three letters of its name" },
    { "/zod <module> on | off", "Switch a module, for example /zod databar on" },
    { "/zod modules", "The modules and whether they are on" },
    { "/zod setup", "Every module's switch on one page" },
    { "/zod find <text>", "Search pages, settings and what the modules hold" },
    { "/zod report", "Today in chat; /zod report party or guild says it there" },
    { "/zod played", "Time played on all characters" },
    { "/zod remind 20 <what>", "A reminder in 20 minutes; also 21:30, every 30, login, list, clear, snooze" },
    { "/zod goals 60 <item>", "Add a goal; also level 30 and gold 100" },
    { "/zod rolls test", "Two sample loot rolls; /zod rolls clear forgets the kept ones" },
    { "/zod vendor sell | keep <item>", "Items Vendor always sells, or never sells; forget, list" },
    { "/zod chat watch <word>", "Watch for a word; unwatch, whispers, mentions" },
    { "/zod loans lend Bob 5g", "Write down a loan; also borrow, list, paid, ok, no and forget with its number" },
    { "/zod crafters <recipe>", "Who in your guild knows a shift-clicked recipe; also 18445 tailoring, list, test" },
    { "/zod guild", "Who in your guild runs ZodUI; /zod guild list shows them" },
    { "/zod guild rares", "Rares and world bosses the guild saw; /zod guild way 2 sets a waypoint to one" },
    { "/zod guild quest <quest>", "Who in your guild has a shift-clicked quest, and how far they are" },
    { "/zod runs with Bob", "When you last ran a dungeon with someone; /zod runs note Bob good tank keeps a note" },
    { "/zod pet", "Your hunter pets: the one out and the stable's, with level, loyalty and diet" },
    { "/zod deaths hardcore", "The last deaths a Hardcore realm announced" },
    { "/zod recap", "This week and last week in numbers, and what waits; /zod recap guild says last week there" },
    { "/zod handouts", "Hand-me-downs in your bags, and whom each is for" },
    { "/zod top", "This week's levels, quests, dungeons and purple finds of your guild's ZodUI players" },
    { "/zod prep", "Your quests for the dungeon you are in, and who in your group has which; /zod prep share offers yours" },
    { "/zod travel", "Your hearthstone, where the route sends you, and portals offered in chat now; /zod travel uc for one city" },
    { "/zod rules", "Say the loot rules in your group's chat; /zod rules log: who broke them" },
    { "/zod heal", "Put on your healing set in this group; /zod healer set <name> names it, /zod healer solo puts your gear back" },
    { "/zod guide", "A dungeon's map with the route drawn on, step by step; /zod guide sfk, brd, dmw...; /zod guide draw, /zod guide export" },
    { "/zod lfg", "Group listings from every layer; /zod lfg sfk tank heal lists your group (or you) for 15 minutes, /zod lfg stop takes it down" },
    { "/zod board", "The Chat board; /zod board crusader: who offered it in the last two weeks" },
    { "/zod groups test", "A sample Group match notice; the roles you play are under Settings" },
    { "/zod shout test", "What Loot shout would say in guild chat, shown only to you" },
    { "/zod raids", "Calendar events, lockouts and your raids; also group, invite 4 and attendance" },
    { "/zod coach", "Your leveling pace and when you get there; with Undead Route, the end of its stage too" },
    { "/zod story", "Your character's story, day by day; /zod story export 7 gives the last 7 days as text" },
    { "/zod where", "Where you stand; party or guild says it there" },
    { "/zod unlock, /zod lock", "Move the notices, the info bar, the loot rolls and the away box" },
    { "/zod export, /zod import", "Your settings as text" },
    { "/zod news", "What each version added" },
    { "/zod notices", "The last notices again" },
    { "/zod test", "A sample notice" },
    { "/zod version", "The version and how many modules are on" },
    { "/zod errors", "What failed since login; /zod errors clear" },
    { "/zod perf", "Measure what ZodUI itself costs while you play: /zod perf start, /zod perf, /zod perf stop" },
    { "/zod safe", "Every module off, to find a problem; /zod safe off brings them back" },
    { "/zod reload", "Reload the interface" },
    { "/zod reset", "Put the windows back where they started" },
}

-- The client can hand back a value as "secret": any test, compare or string call on it from addon code errors.
-- Plain gives nil for one. The readers below fall back to the last plain value seen, so your own name, level
-- and class never come back secret or missing once ZodUI has read them once.
function ns.Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local kept = {}
local function Kept(key, v)
    if not (issecretvalue and issecretvalue(v)) and v ~= nil then kept[key] = v end
    return kept[key]
end

function ns.Level() return Kept("level", UnitLevel and UnitLevel("player")) or 1 end
function ns.MyName() return Kept("name", UnitName and UnitName("player")) end
function ns.MyClass() -- the class name and its file tag ("WARLOCK")
    if not UnitClass then return nil, nil end
    local name, file = UnitClass("player")
    return Kept("className", name), Kept("class", file)
end

-- Whether you are flagged away. The client can hand back a secret boolean, which a plain test errors on;
-- that counts as not away.
function ns.IsAway()
    if not UnitIsAFK then return false end
    local away = UnitIsAFK("player")
    if issecretvalue and issecretvalue(away) then return false end
    return away and true or false
end

-- Copper as plain text for chat, which takes no colour codes: 3g 20s 5c.
function ns.PlainMoney(copper)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(math.floor(copper + 0.5))
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return sign .. table.concat(parts, " ")
end

-- Today as one line: from History, Kills and Deaths when they are on.
local function Report()
    local history = ns.modules.history
    if not (history and history.enabled and history.Today) then return nil end
    local day = history:Today()
    local parts = { ns.Duration(day.played) .. " played", ns.Comma(day.xp) .. " XP" }
    if day.quests > 0 then parts[#parts + 1] = day.quests .. (day.quests == 1 and " quest" or " quests") end
    if day.levels > 0 then parts[#parts + 1] = "+" .. day.levels .. (day.levels == 1 and " level" or " levels") end
    if day.gold ~= 0 then parts[#parts + 1] = (day.gold > 0 and "+" or "") .. ns.PlainMoney(day.gold) end
    local kills = ns.modules.kills
    local k = kills and kills.enabled and ns.chardb.kills
    if k and k.day == ns.Today() and k.today > 0 then parts[#parts + 1] = k.today .. (k.today == 1 and " kill" or " kills") end
    if day.deaths > 0 then parts[#parts + 1] = day.deaths .. (day.deaths == 1 and " death" or " deaths") end
    return "Today: " .. table.concat(parts, ", ") .. "."
end

local function Help()
    ns.Print("commands:")
    print("  |cffffd100/zod|r  open or close the window")
    print("  |cffffd100/zod settings|r  open Settings; |cffffd100/zod session|r, |cffffd100loot|r, |cffffd100gold|r, |cffffd100alts|r, |cffffd100rep|r, |cffffd100notes|r open that page")
    print("  |cffffd100/zod <module> on|off|r  switch a module, for example /zod databar on")
    print("  |cffffd100/zod modules|r  list the modules and whether they are on")
    print("  |cffffd100/zod remind 20 check the auction|r  a reminder in 20 minutes")
    print("  |cffffd100/zod where|r  where you stand; |cffffd100/zod where party|r or |cffffd100guild|r says it there")
    print("  |cffffd100/zod export|r, |cffffd100/zod import|r  copy your settings as text, or take over someone's")
    print("  |cffffd100/zod find linen|r  look through pages, settings, items, to-dos, reminders, goals and characters")
    print("  |cffffd100/zod unlock|r, |cffffd100/zod lock|r  drag the notices, the info bar and the loot rolls where you want them")
    print("  |cffffd100/zod setup|r  every module's switch on one page; |cffffd100/zod news|r  what each version added")
    print("  |cffffd100/zod test|r  show a sample notice; |cffffd100/zod notices|r  the last ones again")
    print("  |cffffd100/zod version|r  the version and how many modules are on")
    print("  |cffffd100/zod errors|r  what failed since login")
    print("  |cffffd100/zod reset|r  put the windows back where they started")
    print("  |cffffd100/zod commands|r  every command as buttons")
end

SLASH_ZODUI1 = "/zod"
SLASH_ZODUI2 = "/zodui"
SlashCmdList["ZODUI"] = function(msg)
    local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = raw:lower()
    local a, b = msg:match("^(%S*)%s*(.-)$")
    if a == "" then
        ns.Toggle()
    elseif a == "help" or a == "?" then
        Help()
    elseif a == "errors" then
        if b == "clear" then
            for i = #ns.errors, 1, -1 do
                errorCount[ns.errors[i]] = nil
                ns.errors[i] = nil
            end
            ns.Print("errors forgotten.")
        elseif #ns.errors == 0 then
            ns.Print("no errors since login.")
        else
            ns.Print(#ns.errors .. " kind(s) of error since login:")
            for _, key in ipairs(ns.errors) do print("  " .. errorCount[key] .. "x  " .. key) end
        end
    elseif a == "modules" then
        ns.Print("modules:")
        for _, m in ipairs(ns.order) do
            print("  " .. (m.enabled and "|cff40d040on |r " or "|cff999999off|r ") .. m.key .. "  |cff999999" .. m.title .. "|r")
        end
    elseif a == "reset" then
        -- Emptied in place: the frames hold on to these tables to save into.
        for k in pairs(ns.db.window) do ns.db.window[k] = nil end
        for _, m in ipairs(ns.order) do
            if m.db.pos then
                for k in pairs(m.db.pos) do m.db.pos[k] = nil end
            end
            if m.enabled and m.OnOption then ns.Guard(m.key .. " option", m.OnOption, m, "pos") end
        end
        if ns.ResetWindow then ns.ResetWindow() end
        if ns.ResetMovers then ns.ResetMovers() end
        ns.Print("windows are back where they started.")
    elseif a == "export" or a == "import" then
        if ns.ShareBox then ns.Guard("share box", ns.ShareBox, a) end
    elseif a == "find" or a == "search" then
        ns.Search(b)
    elseif a == "report" then
        local text = Report()
        if not text then
            ns.Print("the History module is off. /zod history on switches it on.")
        elseif b == "party" or b == "group" or b == "guild" then
            local channel = b == "guild" and ((IsInGuild and IsInGuild()) and "GUILD" or nil)
                or ((IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY" or nil))
            local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
            if channel and send then
                send(text, channel)
            else
                ns.Print("you are not in " .. (b == "guild" and "a guild" or "a group") .. ". " .. text)
            end
        else
            ns.Print(text)
        end
    elseif a == "played" then
        local list, total = {}, 0
        for _, char in pairs(ns.db.chars) do
            if char.playedTotal then
                list[#list + 1] = char
                total = total + char.playedTotal
            end
        end
        if #list == 0 then
            ns.Print("no character has said its time played yet. Type /played on each.")
        else
            table.sort(list, function(x, y) return x.playedTotal > y.playedTotal end)
            ns.Print("played on all characters: " .. ns.Duration(total) .. ".")
            for _, char in ipairs(list) do
                print("  |c" .. ns.ClassHex(char.class) .. (char.name or "?") .. "|r  " .. ns.Duration(char.playedTotal))
            end
        end
    elseif a == "reload" then
        if ReloadUI then ReloadUI() end
    elseif a == "commands" then
        ns.Show("commands")
    elseif a == "safe" then
        local general = ns.db.general
        if b == "off" then
            local back = general.safe or {}
            general.safe = nil
            for _, key in ipairs(back) do
                if ns.modules[key] then ns.modules[key]:Enable() end
            end
            ns.Print(#back == 0 and "safe mode was not on." or (#back .. " modules are on again."))
        elseif general.safe then
            ns.Print("safe mode is already on. /zod safe off brings the modules back.")
        else
            local was = {}
            for _, m in ipairs(ns.order) do
                if m.enabled then
                    was[#was + 1] = m.key
                    m:Disable()
                end
            end
            general.safe = was
            ns.Print("safe mode: " .. #was .. " modules are off. If the problem is gone, switch them on one by one; /zod safe off brings them all back.")
        end
    elseif a == "version" then
        local on = 0
        for _, m in ipairs(ns.order) do
            if m.enabled then on = on + 1 end
        end
        ns.Print("v" .. ns.version .. ", " .. on .. " of " .. #ns.order .. " modules on.")
    elseif a == "notices" then
        if #ns.noticeLog == 0 then
            ns.Print("no notices since login.")
        else
            ns.Print("the last notices:")
            for i = math.min(10, #ns.noticeLog), 1, -1 do
                local entry = ns.noticeLog[i]
                print("  |cff999999" .. date("%H:%M", entry[1]) .. "|r  " .. entry[2])
            end
        end
    elseif a == "where" then
        ns.Guard("where command", ns.Where, b)
    elseif a == "unlock" or a == "move" then
        ns.Unlock()
    elseif a == "lock" then
        ns.Lock()
    elseif a == "test" then
        ns.Alert("This is what a ZodUI notice looks like.")
    elseif ns.pluginCommands and ns.pluginCommands[a] then
        ns.Guard(a .. " command", ns.pluginCommands[a], (raw:match("^%S*%s*(.-)$")))
    elseif b == "" and ns.pages and ns.pages[a] then
        ns.Show(a)
    elseif ns.modules[a] and ns.modules[a].Slash and b ~= "on" and b ~= "off" then
        -- A module with a command of its own; it gets what was typed, capitals and all.
        local m = ns.modules[a]
        if m.enabled then
            ns.Guard(a .. " command", m.Slash, m, (raw:match("^%S*%s*(.-)$")))
        else
            ns.Print(m.title .. " is off. /zod " .. a .. " on switches it on.")
        end
    elseif ns.modules[a] then
        local m = ns.modules[a]
        if b == "on" then
            m:Enable()
        elseif b == "off" then
            m:Disable()
        elseif b ~= "" then
            ns.Print("use /zod " .. a .. " on or /zod " .. a .. " off.")
            return
        else
            ns.Show("settings", a)
            return
        end
        ns.Print(m.title .. " is " .. (m.enabled and "on." or "off."))
    elseif b == "" and #a >= 3 and ns.PageFor and ns.PageFor(a) then
        ns.Show(ns.PageFor(a)) -- the first letters of a page: /zod rem
    else
        ns.Print("unknown command '" .. a .. "'.")
        Help()
    end
end

function ZodUI_OnCompartmentClick()
    ns.Toggle()
end

-- The key binding (Bindings.xml): Options > Keybindings > ZodUI.
BINDING_NAME_ZODUI_TOGGLE = "Open or close ZodUI"
function ZodUI_Toggle()
    ns.Toggle()
end

-- More key bindings (Options > Keybindings > ZodUI).
BINDING_NAME_ZODUI_FIND = "Search ZodUI"
BINDING_NAME_ZODUI_NOTES = "Open the to-do list"
BINDING_NAME_ZODUI_UNLOCK = "Move ZodUI's frames (unlock or lock)"
function ZodUI_Find()
    ns.Search("")
end
function ZodUI_Open(key)
    ns.Show(key)
end
BINDING_NAME_ZODUI_GUIDE = "Dungeon guide: show or hide"
BINDING_NAME_ZODUI_GUIDE_NEXT = "Dungeon guide: next step"
BINDING_NAME_ZODUI_GUIDE_BACK = "Dungeon guide: step back"
function ZodUI_Guide(verb) -- as /zod guide, /zod guide next, /zod guide back
    local guide = ns.modules.guide
    if not (guide and guide.enabled) then
        ns.Print("the Dungeon guide module is off. Switch it on under Settings.")
        return
    end
    if guide.Slash then ns.Guard("guide key", guide.Slash, guide, verb) end
end
function ZodUI_Unlock()
    if ns.IsUnlocked() then ns.Lock() else ns.Unlock() end
end
