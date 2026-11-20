local ADDON, ns = ...
local T = ns.T

-- Raid planner: what is coming, who is free, and who came.
--   Upcoming   your and your guild's calendar events for the next two weeks, with your answer, and a notice
--              a while before each one starts
--   Lockouts   for every dungeon or raid one of your characters is saved to: who is saved and who is free
--              (from what Characters keeps)
--   Group      who to ask along: the people you ran dungeons with (Dungeon runs) who are online now in your
--              guild or friends list, most runs together first; /zod raids invite asks the first few
--   History    your raids (Dungeon runs), who came to each and how often, and the loot rolls won during them (Rolls)
-- It only reads the other modules' data; the calendar is read, never changed.

local M = ns:NewModule("raids", {
    title = "Raid planner",
    desc = "Your calendar's events with a notice before each, who of your characters is saved or free for each "
        .. "dungeon and raid, who to ask along from the people you ran with, and who came to your raids.",
    defaults = { enabled = true, remind = 15 },
    options = {
        { type = "step", key = "remind", label = "Notice before a calendar event", min = 0, max = 60, step = 5,
            format = function(v) return v == 0 and "off" or (v .. " min") end },
        { type = "note", text = "/zod raids opens it. /zod raids group lists who to ask along (add a dungeon's name "
            .. "to narrow it), /zod raids invite 4 asks the first four, /zod raids attendance shows who came.", lines = 3 },
    },
})

local DAYS = 14             -- days of calendar shown
local SHOW_TYPES = { PLAYER = true, GUILD_EVENT = true, GUILD_ANNOUNCEMENT = true, COMMUNITY_EVENT = true }
local STATUS = { [0] = "Invited", [1] = "Available", [2] = "Declined", [3] = "Confirmed", [4] = "Out", [5] = "Standby",
    [6] = "Signed up", [7] = "Not signed up", [8] = "Tentative" }
local SKIP_REMIND = { Declined = true, Out = true }
local WEEKDAY = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local INVITE_MOST = 39
local GROUP_SHOW = 10

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Clean(s, most)
    return (tostring(s or ""):gsub("[%c|]", ""):sub(1, most or 60))
end

---------------------------------------------------------------------------
-- Upcoming: the calendar
---------------------------------------------------------------------------

local function CalendarNow()
    local get = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
    local t = get and get()
    if type(t) ~= "table" or not t.year then return nil end
    return t
end

-- "Thu 20:00"
local function When(s)
    local wd = (ns.CivilDay(s.year, s.month, s.monthDay) + 4) % 7 + 1 -- 1970-01-01 was a Thursday
    return string.format("%s %02d:%02d", WEEKDAY[wd], s.hour or 0, s.minute or 0)
end
M.When = When

local function Until(mins)
    if mins <= 0 then return "now" end
    return "in " .. ns.Duration(mins * 60)
end

-- Events from an hour ago to DAYS ahead, soonest first: { id, title, mins, start, status, kind }.
function M:Events(days)
    local cal, now = C_Calendar, CalendarNow()
    if not (now and cal and cal.GetNumDayEvents and cal.GetDayEvent) then return {} end
    local out, seen = {}, {}
    local today, nowMin = ns.CivilDay(now.year, now.month, now.monthDay), (now.hour or 0) * 60 + (now.minute or 0)
    local offset, day = 0, now.monthDay
    local info = cal.GetMonthInfo and cal.GetMonthInfo(0)
    local length = type(info) == "table" and info.numDays or 31
    for _ = 1, days or DAYS do
        for i = 1, cal.GetNumDayEvents(offset, day) or 0 do
            local e = cal.GetDayEvent(offset, day, i)
            local s = type(e) == "table" and e.startTime
            local title = e and Plain(e.title)
            if s and s.year and type(title) == "string" and SHOW_TYPES[e.calendarType] and not seen[e.eventID or title] then
                seen[e.eventID or title] = true -- an event over several days shows once
                local mins = (ns.CivilDay(s.year, s.month, s.monthDay) - today) * 1440 + (s.hour or 0) * 60 + (s.minute or 0) - nowMin
                if mins > -60 then
                    out[#out + 1] = { id = e.eventID or title, title = Clean(title), mins = mins, start = s,
                        status = STATUS[Plain(e.inviteStatus)], kind = e.calendarType }
                end
            end
        end
        day = day + 1
        if day > length then
            offset, day = offset + 1, 1
            info = cal.GetMonthInfo and cal.GetMonthInfo(offset)
            length = type(info) == "table" and info.numDays or 31
        end
    end
    table.sort(out, function(a, b) return a.mins < b.mins end)
    return out
end

function M:OnEnable()
    if C_Calendar and C_Calendar.OpenCalendar then C_Calendar.OpenCalendar() end -- asks the server for the events
    if RequestRaidInfo then RequestRaidInfo() end -- and the lockouts, for Characters
end

M:On("CALENDAR_UPDATE_EVENT_LIST", function() ns.Refresh() end)

-- A notice a while before each event you did not decline; once per event and start.
ns.Every(30, function(self)
    local before = self.db.remind or 0
    if before <= 0 then return end
    ns.chardb.raidsReminded = ns.chardb.raidsReminded or {}
    local said = ns.chardb.raidsReminded
    for _, e in ipairs(self:Events(1)) do
        local key = tostring(e.id) .. "@" .. When(e.start)
        if e.mins > 0 and e.mins <= before and not said[key] and not SKIP_REMIND[e.status] then
            said[key] = time()
            ns.Alert(e.title .. " starts in " .. e.mins .. (e.mins == 1 and " minute" or " minutes")
                .. (e.status and (" (you: " .. e.status .. ")") or "") .. ".")
        end
    end
    for key, at in pairs(said) do
        if time() - at > 3 * 86400 then said[key] = nil end
    end
end, M)

---------------------------------------------------------------------------
-- Lockouts: who is saved, who is free
---------------------------------------------------------------------------

-- { name, saved = { { who, reset } }, free = { names } } for every instance a character is saved to. Free are the
-- characters not saved to it at no lower a level than the lowest one saved (a guess at who can go).
function M:Lockouts()
    local chars, byName, list = ns.db.chars or {}, {}, {}
    for key, c in pairs(chars) do
        for _, s in ipairs(c.saved or {}) do
            if type(s.reset) == "number" and s.reset > time() and s.name then
                local e = byName[s.name]
                if not e then
                    e = { name = s.name, saved = {}, free = {}, low = 999 }
                    byName[s.name] = e
                    list[#list + 1] = e
                end
                e.saved[#e.saved + 1] = { who = c.name or key, reset = s.reset }
                e.low = math.min(e.low, tonumber(c.level) or 999)
            end
        end
    end
    for _, e in ipairs(list) do
        local savedWho = {}
        for _, s in ipairs(e.saved) do savedWho[s.who] = true end
        for key, c in pairs(chars) do
            local who = c.name or key
            if not savedWho[who] and (tonumber(c.level) or 0) >= e.low then e.free[#e.free + 1] = who end
        end
        table.sort(e.saved, function(a, b) return a.who < b.who end)
        table.sort(e.free)
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

---------------------------------------------------------------------------
-- Group: who to ask along
---------------------------------------------------------------------------

local function Short(name)
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    return Ambiguate and Ambiguate(name, "none") or name:match("^[^-]+")
end

-- Everyone online in your guild or friends list: short name -> { from, level, class }.
local function Online()
    local out = {}
    for i = 1, GetNumGuildMembers and GetNumGuildMembers() or 0 do
        local name, _, _, level, class, _, _, _, online = GetGuildRosterInfo(i)
        local short = Short(name)
        if short and Plain(online) then out[short] = { from = "guild", level = Plain(level), class = Plain(class) } end
    end
    local fl = C_FriendList
    for i = 1, fl and fl.GetNumFriends and fl.GetNumFriends() or 0 do
        local f = fl.GetFriendInfoByIndex(i)
        local short = f and Short(f.name)
        if short and Plain(f.connected) and not out[short] then out[short] = { from = "friend", level = Plain(f.level), class = Plain(f.className) } end
    end
    return out
end

-- The people you ran with who are online now and not in your group, most runs together first; `filter` keeps
-- the ones whose last dungeon together has it in its name.
function M:Candidates(filter)
    filter = filter and filter ~= "" and filter:lower() or nil
    local online, list = Online(), {}
    for name, a in pairs(ns.db.allies or {}) do
        local o = online[name]
        local inGroup = UnitInParty and UnitInParty(name) or (UnitInRaid and ns.Plain(UnitInRaid(name)))
        if o and a.dungeon and not inGroup and (not filter or a.dungeon:lower():find(filter, 1, true)) then
            list[#list + 1] = { name = name, n = a.n or 1, dungeon = a.dungeon, note = a.note, level = o.level, class = o.class, from = o.from }
        end
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    return list
end

function M:Invite(count, filter)
    local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
    if not invite then return 0 end
    local n = 0
    for _, c in ipairs(self:Candidates(filter)) do
        if n >= math.min(count, INVITE_MOST) then break end
        invite(c.name)
        n = n + 1
    end
    return n
end

---------------------------------------------------------------------------
-- History: your raids, who came, what was won
---------------------------------------------------------------------------

-- Your raids, newest first: { name, at, took, with, loot = { "Item (Winner)" } }, and how many each person came to.
function M:History()
    local raids, seen = {}, {}
    for _, r in ipairs(ns.chardb.runs and ns.chardb.runs.list or {}) do
        if r.kind == "raid" and r.at then
            local stop, loot = r.at + (r.took or 0), {}
            for _, roll in ipairs(ns.db.rolls or {}) do
                if roll.at and roll.at >= r.at and roll.at <= stop and roll.winner and roll.winner ~= "" then
                    loot[#loot + 1] = Clean(roll.name, 40) .. " (" .. Clean(roll.winner, 24) .. ")"
                end
            end
            raids[#raids + 1] = { name = r.name, at = r.at, took = r.took or 0, with = r.with or {}, loot = loot }
            for _, who in ipairs(r.with or {}) do seen[who] = (seen[who] or 0) + 1 end
        end
    end
    local attendance = {}
    for who, n in pairs(seen) do attendance[#attendance + 1] = { name = who, n = n } end
    table.sort(attendance, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    return raids, attendance
end

---------------------------------------------------------------------------

local function PlayerLink(name)
    return "|Hplayer:" .. name .. "|h[" .. name .. "]|h"
end

function M:Slash(arg)
    local verb, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    verb = verb:lower()
    if verb == "" then ns.Show("raids") return end
    if verb == "group" then
        local list = self:Candidates(rest)
        if #list == 0 then
            ns.Print("no one you ran with is online in your guild or friends list" .. (rest ~= "" and (" for " .. rest) or "") .. ".")
            return
        end
        ns.Print("online now, who you ran with most (/zod raids invite " .. math.min(4, #list) .. " asks the first ones):")
        for i = 1, math.min(#list, GROUP_SHOW) do
            local c = list[i]
            print(string.format("  %d. %s  |cff999999%s%s, %d %s together, last %s%s|r", i, PlayerLink(c.name), c.level and (c.level .. " ") or "",
                c.class or "", c.n, c.n == 1 and "run" or "runs", c.dungeon, c.note and (". " .. c.note) or ""))
        end
        return
    end
    if verb == "invite" then
        local count, filter = rest:match("^(%d+)%s*(.-)$")
        count = tonumber(count)
        if not count or count < 1 then ns.Print("use /zod raids invite 4, or /zod raids invite 4 deadmines.") return end
        local n = self:Invite(count, filter)
        ns.Print(n == 0 and "no one you ran with is online to ask." or ("asked " .. n .. (n == 1 and " player" or " players") .. " to your group."))
        return
    end
    if verb == "attendance" then
        local raids, attendance = self:History()
        if #raids == 0 then ns.Print("no raids kept yet. Dungeon runs keeps them as you go.") return end
        local parts = {}
        for i = 1, math.min(#attendance, 20) do parts[i] = attendance[i].name .. " " .. attendance[i].n .. "/" .. #raids end
        ns.Print("who came to your " .. #raids .. (#raids == 1 and " raid: " or " raids: ") .. table.concat(parts, ", ") .. ".")
        return
    end
    ns.Print("use /zod raids, or /zod raids group, invite 4 or attendance.")
end

function M:Card()
    local events, lines = self:Events(), {}
    if events[1] then
        local e = events[1]
        lines[#lines + 1] = { e.title, When(e.start) .. "  |cff999999" .. Until(e.mins) .. "|r" }
        if e.status then lines[#lines + 1] = { "You", e.status } end
    end
    local saved = 0
    for _, l in ipairs(self:Lockouts()) do saved = saved + #l.saved end
    if saved > 0 then lines[#lines + 1] = { "Lockouts", saved .. " this week" } end
    if #lines == 0 then return nil end
    return { title = "Raid planner", lines = lines, button = { "Plan", function() ns.Show("raids") end } }
end

ns.AddPage({
    key = "raids", title = "Raid planner", order = 43, group = "Planning", module = "raids",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Raid planner is off. Switch it on under Settings.")
        page.sum = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.sum:SetPoint("TOPLEFT", 0, -4)
        page.sum:SetWidth(w)
        local h = math.floor((ns.PAGE_H - 30) / 3) - 8
        page.events = T.Table(f, { { "When", 150 }, { "Upcoming", w - 280 }, { "You", 130 } }, w, h)
        page.events:SetPoint("TOPLEFT", 0, -26)
        page.locks = T.Table(f, { { "Lockout", 200 }, { "Saved", w - 400 }, { "Free", 200 } }, w, h)
        page.locks:SetPoint("TOPLEFT", 0, -26 - (h + 8))
        page.raids = T.Table(f, { { "When", 110 }, { "Raid", 170 }, { "Who came", w - 520 }, { "Loot won", 240 } }, w, h)
        page.raids:SetPoint("TOPLEFT", 0, -26 - 2 * (h + 8))
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        for _, k in ipairs({ "sum", "events", "locks", "raids" }) do page[k]:SetShown(on) end
        if not on then return end
        local rows = {}
        for _, e in ipairs(M:Events()) do
            rows[#rows + 1] = { When(e.start) .. "  |cff999999" .. Until(e.mins) .. "|r", e.title, e.status or "" }
        end
        page.events:SetRows(rows, "No calendar events in the next two weeks.")
        rows = {}
        for _, l in ipairs(M:Lockouts()) do
            local saved = {}
            for i, s in ipairs(l.saved) do saved[i] = s.who .. " |cff999999" .. ns.Duration(s.reset - time()) .. "|r" end
            rows[#rows + 1] = { l.name, table.concat(saved, ", "), #l.free > 0 and T.Paint(table.concat(l.free, ", "), T.GREEN) or "-" }
        end
        page.locks:SetRows(rows, "None of your characters is saved anywhere this week.")
        local raids, attendance = M:History()
        rows = {}
        for _, r in ipairs(raids) do
            rows[#rows + 1] = { ns.WhenCell(r.at, true), r.name, #r.with .. ": " .. table.concat(r.with, ", "),
                #r.loot > 0 and table.concat(r.loot, ", ") or "-" }
        end
        page.raids:SetRows(rows, "Your raids show here, with who came and what was won.")
        local online = #M:Candidates()
        page.sum:SetText(online .. (online == 1 and " person" or " people") .. " you ran with " .. (online == 1 and "is" or "are") .. " online (/zod raids group)."
            .. (attendance[1] and ("  Came most: " .. attendance[1].name .. ", " .. attendance[1].n .. " of " .. #raids .. " raids.") or ""))
    end,
})
