local ADDON, ns = ...
local T = ns.T

-- Story: the character's life as a timeline, day by day, from what the other modules already keep (first visits
-- from Zones, deaths from Deaths, dungeon runs and who came along from Dungeon runs, good finds from Loot, quests
-- from Quests done, time played from History). Story itself keeps only what nothing else does: each level reached
-- and each standing gained with a faction. /zod story export gives it as plain text to copy and share.
-- It reads the others' saved data, so a module that is off simply adds nothing; nothing here changes their data.

local M = ns:NewModule("story", {
    title = "Story",
    desc = "Your character's story, day by day: levels, first visits, dungeons and who came along, deaths, good finds "
        .. "and new standings. /zod story export gives it as text to share.",
    defaults = { enabled = true, finds = 3 },
    options = {
        { type = "note", text = "Built from what Zones, Deaths, Dungeon runs, Loot and Quests done keep; levels and "
            .. "standings are kept from now on. /zod story export 7 gives the last 7 days as text.", lines = 3 },
    },
})

local KEEP = 300          -- levels and standings kept
local EXPORT_DAYS = 30    -- days in an export unless asked
local QUALITY_HEX = { [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }

local reactions = {}      -- factionID -> reaction, this session

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Data()
    local d = ns.chardb.story
    if not d then
        d = { levels = {}, standings = {} }
        ns.chardb.story = d
    end
    return d
end

local function Push(list, entry)
    list[#list + 1] = entry
    while #list > KEEP do table.remove(list, 1) end
end

local function Zone()
    local z = GetRealZoneText and GetRealZoneText() or ""
    return z ~= "" and z or nil
end

M:On("PLAYER_LEVEL_UP", function(_, _, level)
    level = tonumber(Plain(level))
    if not level then return end
    Push(Data().levels, { at = time(), level = level, zone = Zone() })
    ns.Refresh()
end)

local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local function Standing(reaction)
    return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or STANDING[reaction] or tostring(reaction)
end

local function ScanFactions(record)
    if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then return end
    for i = 1, C_Reputation.GetNumFactions() or 0 do
        local f = C_Reputation.GetFactionDataByIndex(i)
        local id, reaction, name = f and Plain(f.factionID), f and Plain(f.reaction), f and Plain(f.name)
        if id and type(reaction) == "number" and not f.isHeader then
            local was = reactions[id]
            if record and was and reaction > was and type(name) == "string" then
                Push(Data().standings, { at = time(), name = name, reaction = reaction })
            end
            reactions[id] = reaction
        end
    end
end

M:On("UPDATE_FACTION", function() ScanFactions(true) end)

function M:OnEnable()
    Data()
    ScanFactions(false) -- what you have at login is not news
end

---------------------------------------------------------------------------
-- The timeline
---------------------------------------------------------------------------

local function Where(zone, sub)
    return (sub and sub ~= "" and sub ~= zone) and (sub .. ", " .. (zone or "")) or (zone or "somewhere")
end

-- Every event, oldest first: { at, text, plain }. `plain` is the same without colour codes, for the export.
function M:Events()
    local out = {}
    local function Add(at, text, plain)
        if type(at) == "number" then out[#out + 1] = { at = at, text = text, plain = plain or text } end
    end
    local c = ns.chardb
    for _, l in ipairs(Data().levels) do
        Add(l.at, "Reached level " .. l.level .. (l.zone and (" in " .. l.zone) or "") .. ".")
    end
    for _, s in ipairs(Data().standings) do
        Add(s.at, "Became " .. Standing(s.reaction) .. " with " .. s.name .. ".")
    end
    for zone, z in pairs(c.zones or {}) do
        Add(z.first, "First came to " .. zone .. (z.level and (" at level " .. z.level) or "") .. ".")
    end
    for _, d in ipairs(c.deaths or {}) do
        Add(d.at, "Died in " .. Where(d.zone, d.sub) .. (d.level and (" at level " .. d.level) or "") .. ".")
    end
    for _, r in ipairs(c.runs and c.runs.list or {}) do
        local bits = { ns.Duration(r.took or 0) }
        if r.deaths and r.deaths > 0 then bits[#bits + 1] = r.deaths .. (r.deaths == 1 and " death" or " deaths") end
        local with = r.with and #r.with > 0 and (", with " .. table.concat(r.with, ", ")) or ""
        Add(r.at, "Ran " .. r.name .. " (" .. table.concat(bits, ", ") .. ")" .. with .. ".")
    end
    local least = self.db.finds or 3
    for _, f in ipairs(c.finds or {}) do
        if (f.q or 0) >= least and f.name then
            local hex = QUALITY_HEX[f.q] or "ffffffff"
            local where = f.where and f.where ~= "" and (" in " .. f.where) or ""
            Add(f.at, "Found |c" .. hex .. "[" .. f.name .. "]|r" .. where .. ".", "Found [" .. f.name .. "]" .. where .. ".")
        end
    end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
end

local function CivilDay(key)
    local y, m, d = key:match("(%d+)-(%d+)-(%d+)")
    return ns.CivilDay(tonumber(y), tonumber(m), tonumber(d))
end
M.CivilDay = CivilDay

-- The events by day, newest day first: { key, at, number, events, quests, played }.
function M:Days()
    local days, byKey = {}, {}
    local events = self:Events()
    local function Day(at)
        local key = date("%Y-%m-%d", at)
        local d = byKey[key]
        if not d then
            d = { key = key, at = at, events = {}, quests = 0 }
            byKey[key] = d
            days[#days + 1] = d
        end
        return d
    end
    for _, e in ipairs(events) do table.insert(Day(e.at).events, e) end
    for _, q in ipairs(ns.chardb.questsDone or {}) do
        if type(q.at) == "number" then Day(q.at).quests = Day(q.at).quests + 1 end
    end
    local history = ns.chardb.history and ns.chardb.history.days or {}
    table.sort(days, function(a, b) return a.key < b.key end)
    local first = days[1] and CivilDay(days[1].key)
    for _, d in ipairs(days) do
        d.number = CivilDay(d.key) - first + 1 -- by calendar date, not by the hour of the first event
        d.played = history[d.key] and history[d.key].played or nil
    end
    local newest = {}
    for i = #days, 1, -1 do newest[#newest + 1] = days[i] end
    return newest
end

local function Heading(d)
    local bits = {}
    local lo, hi
    for _, e in ipairs(d.events) do
        local lvl = e.plain:match("^Reached level (%d+)")
        if lvl then
            lvl = tonumber(lvl)
            lo, hi = lo and math.min(lo, lvl) or lvl, hi and math.max(hi, lvl) or lvl
        end
    end
    if lo then bits[#bits + 1] = lo == hi and ("level " .. lo) or ("levels " .. lo .. " to " .. hi) end
    if d.quests > 0 then bits[#bits + 1] = d.quests .. (d.quests == 1 and " quest" or " quests") end
    if d.played and d.played >= 60 then bits[#bits + 1] = ns.Duration(d.played) .. " played" end
    return "Day " .. d.number .. ", " .. date("%A %d %B %Y", d.at) .. (#bits > 0 and (": " .. table.concat(bits, ", ")) or "")
end
M.Heading = Heading

-- The story as plain text, the last `days` days (oldest first, as a story is read).
function M:Text(days)
    days = math.max(1, math.min(tonumber(days) or EXPORT_DAYS, 3650))
    local list = self:Days()
    local who = (ns.MyName() or "?") .. ", level " .. (ns.Level() or "?")
    local lines = { who .. ": a story kept by ZodUI." }
    for i = math.min(#list, days), 1, -1 do
        local d = list[i]
        lines[#lines + 1] = ""
        lines[#lines + 1] = Heading(d)
        for _, e in ipairs(d.events) do lines[#lines + 1] = "  " .. date("%H:%M", e.at) .. "  " .. e.plain end
        if #d.events == 0 then lines[#lines + 1] = "  A quiet day." end
    end
    if #list == 0 then lines[#lines + 1] = "Nothing yet: the story starts now." end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- The copy box
---------------------------------------------------------------------------

local box

local function Box()
    if box then return box end
    local f = CreateFrame("Frame", "ZodUIStoryBox", UIParent, "BackdropTemplate")
    f:SetSize(620, 420)
    f:SetFrameStrata("DIALOG")
    T.Window(f, T.WINDOW, 0.98, T.GOLD)
    f:EnableMouse(true)
    T.Movable(f, ns.MoverStore("storybox"), f) -- dragged anywhere on it, and kept there
    T.Place(f, ns.MoverStore("storybox"), "CENTER", 0, 40)
    f:Hide()
    tinsert(UISpecialFrames, "ZodUIStoryBox")
    f.title = T.Text(f, "GameFontNormal", T.GOLD)
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.hint = T.Text(f, "GameFontHighlightSmall", T.DIM)
    f.hint:SetPoint("TOPLEFT", 14, -32)
    f.hint:SetText("Press Ctrl+C to copy, then paste it where you want to share it.")
    local holder = T.Panel(f, T.SURFACE)
    holder:SetPoint("TOPLEFT", 14, -54)
    holder:SetSize(592, 318)
    local scroll, child = T.Scroll(holder)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetSize(580, 306)
    child:SetWidth(570)
    local e = CreateFrame("EditBox", nil, child)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetWidth(570)
    e:SetPoint("TOPLEFT", 0, 0)
    e:SetScript("OnEscapePressed", function() f:Hide() end)
    f.edit, f.child, f.scroll = e, child, scroll
    f.close = T.Button(f, "Close", 90, function() f:Hide() end)
    f.close:SetPoint("BOTTOMRIGHT", -14, 12)
    box = f
    return f
end

function M:Export(days)
    local f = Box()
    local text = self:Text(days)
    local _, n = text:gsub("\n", "")
    f.edit:SetText(text)
    local h = math.max(300, (n + 1) * 14)
    f.edit:SetHeight(h)
    f.child:SetHeight(h) -- the scroll's content: without it a long story does not scroll
    f.scroll:SetVerticalScroll(0)
    if f.scroll.Sync then f.scroll:Sync() end
    f.title:SetText("The story of " .. (ns.MyName() or "you"))
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
    return text
end

---------------------------------------------------------------------------

function M:Slash(arg)
    local verb, rest = arg:match("^(%S*)%s*(.-)$")
    verb = verb:lower()
    if verb == "" then ns.Show("story") return end
    if verb == "export" then
        self:Export(tonumber(rest))
        return
    end
    ns.Print("use /zod story, or /zod story export (and a number of days).")
end

function M:Card()
    local days = self:Days()
    local d = days[1]
    if not d then return nil end
    local last -- the newest event, also when the newest day has only quests done in it
    for _, day in ipairs(days) do
        if day.events[1] then last = day.events[#day.events] break end
    end
    -- Today's number by the calendar, also after a quiet day; the last event says when it was.
    local oldest = days[#days]
    local today = CivilDay(ns.Today()) - CivilDay(oldest.key) + 1
    return { title = "Story", lines = {
        { "Today is", "Day " .. today },
        { last and ((last.at and (ns.When(last.at) .. ": ") or "") .. last.text) or "A quiet day", "" }, -- the event takes the line
    }, button = { "Read", function() ns.Show("story") end } }
end

function M:Find(part, add, has)
    for _, e in ipairs(self:Events()) do
        if has(e.plain) then add("Story", e.plain, ns.When(e.at, true), "story") end
    end
end

ns.AddPage({
    key = "story", title = "Story", order = 19, group = "This character", module = "story",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Story module is off. Switch it on under Settings.")
        page.sum = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.sum:SetPoint("TOPLEFT", 0, -4)
        page.export = T.Button(f, "Export as text", 120, function() M:Export() end)
        page.export:SetPoint("TOPRIGHT", 0, 0)
        page.list = T.Table(f, { { "When", 70 }, { "What", w - 70 } }, w, ns.PAGE_H - 30, nil, true) -- the diary's order
        page.list:SetPoint("TOPLEFT", 0, -30)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.sum:SetShown(on)
        page.export:SetShown(on)
        page.list:SetShown(on)
        if not on then return end
        local days, rows, n = M:Days(), {}, 0
        for _, d in ipairs(days) do
            rows[#rows + 1] = { T.Paint(date("%d %b", d.at), T.GOLD), T.Paint(Heading(d), T.GOLD) }
            for i = #d.events, 1, -1 do
                local e = d.events[i]
                rows[#rows + 1] = { date("%H:%M", e.at), e.text }
                n = n + 1
            end
        end
        page.sum:SetText(#days == 0 and "Your story starts now." or (#days .. (#days == 1 and " day, " or " days, ") .. n .. " moments. Newest first."))
        page.list:SetRows(rows, "Levels, first visits, dungeons, deaths and good finds show up here as they happen.")
    end,
})
