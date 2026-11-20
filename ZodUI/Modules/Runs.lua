local ADDON, ns = ...
local T = ns.T

-- Dungeon runs: times every dungeon and raid visit and keeps what it gave.
-- Leaving does not end a run at once: walking back in within five minutes
-- (a corpse run, a reload, a trip to the vendor) continues it.

local M = ns:NewModule("runs", {
    title = "Dungeon runs",
    desc = "Times every dungeon and raid visit and keeps what it gave: XP, gold and deaths. Walking back in within five minutes continues the same run. Remembers who you ran with.",
    defaults = { enabled = true, report = true, limit = true, best = true, companions = true },
    options = {
        { type = "check", key = "report", label = "Say in chat what a run gave when it ends" },
        { type = "check", key = "limit", label = "Warn when you near the game's limit of 5 dungeons an hour" },
        { type = "check", key = "best", label = "Say your fastest run when you walk into a dungeon" },
        { type = "check", key = "companions", label = "Remind me who I ran with (tooltips, invites, whispers)" },
        { type = "note", text = "/zod runs with Bob says when you last ran together; /zod runs note Bob good tank keeps a note.", lines = 2 },
    },
})

local RESUME = 300 -- seconds outside before a run counts as over
local SHORTEST = 60 -- a visit shorter than this is not a run
local KEEP = 200
local lastXP, lastMax, lastMoney
local byDungeon = false -- the page lists every run, or one line per dungeon
local HOUR, LIMIT = 3600, 5

-- When each new run started in the last hour, for all characters: the limit is per account.
local function Entries()
    ns.db.entries = ns.db.entries or {}
    local list, now = ns.db.entries, time()
    for i = #list, 1, -1 do
        if now - list[i] >= HOUR then table.remove(list, i) end
    end
    return list
end

local function Entered(name)
    local list = Entries()
    list[#list + 1] = time()
    local n = #list
    if M.db.limit and n >= LIMIT - 1 then
        if n == LIMIT - 1 then
            ns.Alert(n .. "th dungeon this hour. The game lets you enter " .. LIMIT .. ".")
        else
            ns.Alert(n .. "th dungeon this hour: that is the limit. The oldest frees up in " .. ns.Duration(list[1] + HOUR - time()) .. ".")
        end
    end
    if M.db.best then
        local best, runs = nil, 0
        for _, r in ipairs(ns.chardb.runs and ns.chardb.runs.list or {}) do
            if r.name == name then
                runs = runs + 1
                if not best or r.took < best then best = r.took end
            end
        end
        if best then ns.Print(name .. ": your fastest run here took " .. ns.Duration(best) .. " (" .. runs .. (runs == 1 and " run)." or " runs).")) end
    end
end

local function Data()
    local data = ns.chardb.runs
    if not data then
        data = { list = {} }
        ns.chardb.runs = data
    end
    return data
end

-- The dungeon or raid the character stands in, or nil.
local function Where()
    if not IsInInstance then return nil end
    local inside, kind = IsInInstance()
    if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
    local name = GetInstanceInfo and GetInstanceInfo()
    return name or (GetRealZoneText and GetRealZoneText()) or "Dungeon", kind
end

local function Inside()
    local run = ns.chardb and ns.chardb.runs and ns.chardb.runs.current
    return run and not run.left and run or nil
end

local function PerHour(xp, took)
    if took < SHORTEST or xp <= 0 then return nil end
    return xp / took * 3600
end

---------------------------------------------------------------------------
-- Dungeon companions: who was in the group, remembered for all characters
---------------------------------------------------------------------------

local ALLIES_MOST = 1000
local WITH_MOST = 40

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- [name] = { n = runs together, dungeon, at, char, guid, note }
local function Allies()
    ns.db.allies = ns.db.allies or {}
    return ns.db.allies
end

local function Short(name)
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    return Ambiguate and Ambiguate(name, "none") or name
end

-- "bob" -> "Bob"
local function CleanName(s)
    s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" or s:find("[%s%c|]") then return nil end
    local name, realm = s:match("^([^-]+)(.*)$")
    if name:find("^%a+$") then name = name:sub(1, 1):upper() .. name:sub(2):lower() end
    return name .. realm
end

local function UnitFullName(unit)
    local name, realm = UnitName(unit)
    name, realm = Plain(name), Plain(realm)
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    return (type(realm) == "string" and realm ~= "") and (name .. "-" .. realm) or name
end

-- Adds who is in the group now to the run.
local function AddGroup(run)
    run.with = run.with or {}
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    local me = ns.MyName()
    local n = 0
    for _ in pairs(run.with) do n = n + 1 end
    for _, unit in ipairs(units) do
        local name = UnitFullName(unit)
        if name and name ~= me and run.with[name] == nil and n < WITH_MOST then
            run.with[name] = Plain(UnitGUID and UnitGUID(unit)) or false
            n = n + 1
        end
    end
end

local function Remember(run)
    local allies = Allies()
    for name, guid in pairs(run.with or {}) do
        local a = allies[name] or {}
        allies[name] = a
        a.n, a.dungeon, a.at = (a.n or 0) + 1, run.name, run.start
        a.char = ns.char and ns.char.name or a.char
        if guid then a.guid = guid end
    end
    local count, oldest, oldestAt = 0, nil, nil
    for name, a in pairs(allies) do
        count = count + 1
        if not a.note and (not oldestAt or (a.at or 0) < oldestAt) then oldest, oldestAt = name, a.at or 0 end
    end
    if count > ALLIES_MOST and oldest then allies[oldest] = nil end
end

-- "Deadmines, 3d ago (2 runs together)", or nil for someone you never ran with.
function M:Companion(name)
    local a = name and Allies()[name]
    if not a or not a.dungeon then return nil, a end
    local ago = time() - (a.at or time())
    local when = ns.Ago(ago)
    return a.dungeon .. ", " .. when .. ((a.n or 1) > 1 and (" (" .. a.n .. " runs together)") or ""), a
end

local function Said(name)
    local text, a = M:Companion(name)
    local note = a and a.note
    if not text and not note then return nil end
    return (text and ("you ran " .. text) or "") .. (note and ((text and ". " or "") .. "Note: " .. note) or "")
end

function M:UnitTooltip(tip)
    if not self.db.companions or not (UnitIsPlayer and Plain(UnitIsPlayer("mouseover"))) then return end
    local name = UnitFullName("mouseover")
    local text, a = self:Companion(name)
    if text then tip:AddDoubleLine("Ran with you", text, 0.6, 0.6, 0.6, 1, 1, 1) end
    if a and a.note then tip:AddLine("Note: " .. a.note, 1, 0.82, 0, true) end
end

local told = {} -- whispers: said once per person per session

M:On("PARTY_INVITE_REQUEST", function(self, _, name)
    if not self.db.companions then return end
    local short = Short(name)
    local said = short and Said(short)
    if said then ns.Print(short .. " invites you: " .. said .. ".") end
end)

M:On("CHAT_MSG_WHISPER", function(self, _, _, sender)
    if not self.db.companions then return end
    local short = Short(sender)
    if not short or told[short] then return end
    local said = Said(short)
    if said then
        told[short] = true
        ns.Print(short .. ": " .. said .. ".")
    end
end)

M:On("GROUP_ROSTER_UPDATE", function()
    local run = ns.chardb and ns.chardb.runs and ns.chardb.runs.current
    if run and not run.left then AddGroup(run) end
end)

-- A note on someone, kept in ZodUI and, where the game has Recent Allies, in its own note too.
function M:SetNote(name, note)
    note = (note or ""):gsub("[%c|]", ""):sub(1, 120)
    local allies = Allies()
    local a = allies[name] or {}
    allies[name] = a
    a.note = note ~= "" and note or nil
    if not a.note and not a.dungeon then allies[name] = nil end
    local RA = C_RecentAllies
    if a.guid and RA and RA.IsSystemEnabled and RA.IsSystemEnabled() and RA.SetRecentAllyNote
        and (not RA.CanSetRecentAllyNote or RA.CanSetRecentAllyNote(a.guid)) then
        pcall(RA.SetRecentAllyNote, a.guid, note)
    end
end

-- /zod runs with Bob, /zod runs note Bob good tank
function M:Slash(arg)
    local verb, who, rest = arg:match("^(%S*)%s*(%S*)%s*(.-)$")
    verb = verb:lower()
    local name = CleanName(who)
    if (verb == "with" or verb == "note") and not name then
        ns.Print("use /zod runs with Bob, or /zod runs note Bob good tank.")
        return
    end
    if verb == "with" then
        ns.Print(name .. ": " .. (Said(name) or "you have not run a dungeon together yet") .. ".")
    elseif verb == "note" then
        self:SetNote(name, rest)
        ns.Print(rest ~= "" and ("note on " .. name .. " kept.") or ("note on " .. name .. " removed."))
    else
        ns.Print("use /zod runs to open the page, /zod runs with Bob, or /zod runs note Bob good tank.")
    end
end

local function Finish(run)
    local data = Data()
    data.current = nil
    local took = (run.left or run.last or run.start) - run.start
    if took < SHORTEST then return end
    Remember(run)
    local with = {}
    for name in pairs(run.with or {}) do with[#with + 1] = name end
    table.sort(with)
    table.insert(data.list, 1, { name = run.name, kind = run.kind, at = run.start, took = took, xp = run.xp, gold = run.gold,
        deaths = run.deaths, level = run.level, with = #with > 0 and with or nil })
    while #data.list > KEEP do table.remove(data.list) end
    if M.db.report then
        local parts = { ns.Duration(took) }
        if run.xp > 0 then parts[#parts + 1] = ns.Comma(run.xp) .. " XP" end
        if run.gold ~= 0 then parts[#parts + 1] = ns.Money(run.gold, true) end
        if run.deaths > 0 then parts[#parts + 1] = run.deaths .. (run.deaths == 1 and " death" or " deaths") end
        ns.Print(run.name .. ": " .. table.concat(parts, ", ") .. ".")
    end
end

local function Check()
    local data, now = Data(), time()
    local run = data.current
    local name, kind = Where()
    if name then
        if run and (run.name ~= name or now - (run.left or run.last or now) > RESUME) then
            Finish(run)
            run = nil
        end
        if not run then
            run = { name = name, kind = kind, start = now, xp = 0, gold = 0, deaths = 0, level = ns.Level() }
            data.current = run
            Entered(name)
        end
        run.left, run.last = nil, now
        AddGroup(run)
    elseif run then
        -- Outside. A run last seen long ago (a logout inside) ended when it was last seen.
        if not run.left then run.left = (now - (run.last or now) > 60) and run.last or now end
        if now - run.left > RESUME then Finish(run) end
    end
    ns.Refresh()
end

function M:OnEnable()
    lastXP, lastMax, lastMoney = UnitXP("player") or 0, UnitXPMax("player") or 0, GetMoney()
    Check()
end

M:On("PLAYER_ENTERING_WORLD", Check)
M:On("ZONE_CHANGED_NEW_AREA", Check)
ns.Every(10, Check, M)

M:On("PLAYER_XP_UPDATE", function()
    local xp, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    local gain = xp - (lastXP or xp)
    if gain < 0 then gain = (lastMax or 0) - (lastXP or 0) + xp end -- a level-up: the rest of the old level, then the new one
    lastXP, lastMax = xp, max
    local run = Inside()
    if run and gain > 0 then run.xp = run.xp + gain end
end)

M:On("PLAYER_MONEY", function()
    local money = GetMoney()
    local run = Inside()
    if run and lastMoney then run.gold = run.gold + money - lastMoney end
    lastMoney = money
end)

M:On("PLAYER_DEAD", function()
    local run = Inside()
    if run then run.deaths = run.deaths + 1 end
end)

-- One result per dungeon, with how often and the fastest visit.
function M:Find(part, add, has)
    local seen, names = {}, {}
    for _, run in ipairs(Data().list) do
        if has(run.name) then
            local s = seen[run.name]
            if not s then
                s = { n = 0, best = run.took }
                seen[run.name] = s
                names[#names + 1] = run.name
            end
            s.n = s.n + 1
            if run.took < s.best then s.best = run.took end
        end
    end
    for _, name in ipairs(names) do
        local s = seen[name]
        add("Dungeon", name, s.n == 1 and ("1 run, " .. ns.Duration(s.best)) or (s.n .. " runs, fastest " .. ns.Duration(s.best)), "runs")
    end
end

function M:Hints(add)
    local n = #Entries()
    if n >= LIMIT - 1 then add(n .. " of " .. LIMIT .. " dungeons entered this hour", 55, "runs") end
end

function M:Card()
    local run = Inside()
    if not run then return nil end -- the card is only there during a run
    local took = time() - run.start
    local rate = PerHour(run.xp, took)
    return {
        title = "Dungeon run",
        lines = {
            { run.name, ns.Duration(took) },
            { "XP", ns.Comma(run.xp) .. (rate and ("  |cff999999" .. ns.Comma(rate) .. "/h|r") or "") },
            { "Gold", ns.Money(run.gold, true) },
        },
        button = { "All", function() ns.Show("runs") end },
    }
end

local function Row(run, took, when)
    local rate = PerHour(run.xp or 0, took)
    return { run.name, run.level or "", when, ns.Duration(took), (run.xp or 0) > 0 and ns.Comma(run.xp) or "-",
        rate and ns.Comma(rate) or "-", (run.gold or 0) ~= 0 and ns.Money(run.gold, true) or "-",
        (run.deaths or 0) > 0 and run.deaths or "" }
end

ns.AddPage({
    key = "runs", title = "Dungeons", order = 17, group = "This character", module = "runs",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Dungeon runs module is off. Switch it on under Settings.")
        page.summary = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.summary:SetPoint("TOPLEFT", 0, -4)
        page.list = T.Table(f, { { "Dungeon", w - 540 }, { "Lvl", 40 }, { "When", 110 }, { "Time", 70, "RIGHT" }, { "XP", 80, "RIGHT" },
            { "XP/hour", 80, "RIGHT" }, { "Gold", 90, "RIGHT" }, { "Deaths", 50, "RIGHT" } }, w, ns.PAGE_H - 56)
        page.list.onClick = function(run)
            page.list.selected = run
            page:Refresh()
        end
        page.remove = T.Button(f, "Remove this run", 150, function()
            local list, chosen = Data().list, page.list.selected
            for i = #list, 1, -1 do
                if list[i] == chosen then table.remove(list, i) end
            end
            page.list.selected = nil
            page:Refresh()
        end)
        page.remove:SetPoint("BOTTOMLEFT", 0, 0)
        page.list:SetPoint("TOPLEFT", 0, -26)
        page.each = T.Table(f, { { "Dungeon", w - 500 }, { "Runs", 60, "RIGHT" }, { "Fastest", 80, "RIGHT" }, { "Average", 80, "RIGHT" },
            { "XP a run", 90, "RIGHT" }, { "Deaths", 60, "RIGHT" }, { "Last", 130, "RIGHT" } }, w, ns.PAGE_H - 26)
        page.each:SetPoint("TOPLEFT", 0, -26)
        byDungeon = M.db.byDungeon or false -- kept across /reload
        page.mode = T.Button(f, "By dungeon", 110, function()
            byDungeon = not byDungeon
            M.db.byDungeon = byDungeon or nil
            page:Refresh()
        end)
        page.mode:SetPoint("TOPLEFT", w - 110, 0)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.summary:SetShown(on)
        page.list:SetShown(on and not byDungeon)
        page.remove:SetShown(on and not byDungeon and page.list.selected ~= nil)
        page.each:SetShown(on and byDungeon)
        page.mode:SetShown(on)
        if not on then return end
        page.mode.label:SetText(byDungeon and "Every run" or "By dungeon")
        page.mode.tip = byDungeon and "Now: one line per dungeon. Click for every run." or "Now: every run. Click for one line per dungeon."
        local data, now = Data(), time()
        if byDungeon then
            local seen, each = {}, {}
            for _, r in ipairs(data.list) do
                local s = seen[r.name]
                if not s then
                    s = { name = r.name, n = 0, took = 0, xp = 0, deaths = 0, best = r.took, last = r.at }
                    seen[r.name] = s
                    each[#each + 1] = s
                end
                s.n, s.took, s.xp, s.deaths = s.n + 1, s.took + r.took, s.xp + (r.xp or 0), s.deaths + (r.deaths or 0)
                if r.took < s.best then s.best = r.took end
                if r.at > s.last then s.last = r.at end
            end
            table.sort(each, function(a, b)
                if a.n ~= b.n then return a.n > b.n end
                return a.name < b.name
            end)
            local lines = {}
            for i, s in ipairs(each) do
                lines[i] = { s.name, s.n, ns.Duration(s.best), ns.Duration(s.took / s.n), s.xp > 0 and ns.Comma(s.xp / s.n) or "-",
                    s.deaths > 0 and s.deaths or "", ns.WhenCell(s.last) }
            end
            page.each:SetRows(lines, "No runs yet on this character.")
        end
        local rows = {}
        local run = data.current
        if run then
            rows[1] = Row(run, (run.left or now) - run.start, run.left and "|cff999999left|r" or T.Paint("now", T.GREEN))
        end
        local total, xp = 0, 0
        local fastest, count = {}, {}
        for _, r in ipairs(data.list) do
            count[r.name] = (count[r.name] or 0) + 1
            if not fastest[r.name] or r.took < fastest[r.name].took then fastest[r.name] = r end
        end
        for _, r in ipairs(data.list) do
            local row = Row(r, r.took, ns.WhenCell(r.at))
            if fastest[r.name] == r and count[r.name] > 1 then row[4] = T.Paint(row[4], T.GOLD) end -- the fastest of several
            row.data = r
            rows[#rows + 1] = row
            total, xp = total + r.took, xp + (r.xp or 0)
        end
        local n = #data.list
        local hour = #Entries()
        local entered = hour > 0 and ("  Entered this hour: " .. hour .. " of " .. LIMIT .. ".") or ""
        if n == 0 then
            page.summary:SetText("A run is logged when you leave a dungeon or raid." .. entered)
        else
            local rate = PerHour(xp, total)
            page.summary:SetText(n .. (n == 1 and " run, " or " runs, ") .. ns.Duration(total) .. " inside"
                .. (rate and (", " .. ns.Comma(rate) .. " XP an hour on average") or "") .. "." .. entered)
        end
        page.list:SetRows(rows, "No runs yet on this character.")
    end,
})
