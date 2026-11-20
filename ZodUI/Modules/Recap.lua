local ADDON, ns = ...

-- Recap: your week in numbers, and a plan when you come back.
--   * Each new week, at the first login, last week's numbers: time played, XP, levels,
--     quests, dungeons, gold, deaths and the best things found. /zod recap guild says
--     it in guild chat.
--   * At logout it keeps where you stopped. At the next login (after an hour or more
--     away) it says where that was and what is waiting: quests to hand in, the route's
--     next step, the coach's next level, your open to-dos.
-- It counts nothing of its own: the numbers are History's, Dungeons', Loot's and Quests done's.

local M = ns:NewModule("recap", {
    title = "Recap",
    desc = "Each new week, last week in numbers; and when you come back, where you stopped and what is waiting. /zod recap shows both.",
    defaults = { enabled = true, week = true, plan = true },
    options = {
        { type = "check", key = "week", label = "Last week's numbers at the first login of a week" },
        { type = "check", key = "plan", label = "Where you stopped and what is waiting, when you come back after an hour" },
    },
})

local DAY = 86400
local AWAY = 3600

local function Data()
    ns.chardb.recap = ns.chardb.recap or {}
    return ns.chardb.recap
end

-- Midnight of the Monday of the week `now` is in.
function M.WeekStart(now)
    now = now or time()
    local t = date("*t", now)
    return now - ((t.wday + 5) % 7) * DAY - (t.hour * 3600 + t.min * 60 + t.sec)
end

-- The numbers of [from, to): what History, Dungeons, Quests done and Loot kept.
function M:Stats(from, to)
    local s = { played = 0, xp = 0, quests = 0, levels = 0, gold = 0, deaths = 0, runs = 0, finds = {} }
    local days = ns.chardb.history and ns.chardb.history.days or {}
    for at = from + DAY / 2, to - 1, DAY do
        local day = days[date("%Y-%m-%d", at)]
        if day then
            for _, k in ipairs({ "played", "xp", "quests", "levels", "gold", "deaths" }) do s[k] = s[k] + (tonumber(day[k]) or 0) end
        end
    end
    local runs = ns.chardb.runs and ns.chardb.runs.list or {}
    for _, run in ipairs(runs) do
        if type(run.at) == "number" and run.at >= from and run.at < to then s.runs = s.runs + 1 end
    end
    for _, f in ipairs(ns.chardb.finds or {}) do
        if type(f.at) == "number" and f.at >= from and f.at < to and (f.q or 0) >= 4 and f.name then
            s.finds[#s.finds + 1] = f.name
        end
    end
    return s
end

function M:Text(s, head)
    if s.played <= 0 and s.xp <= 0 and s.quests <= 0 and s.runs <= 0 then return nil end
    local parts = { ns.Duration(s.played) .. " played" }
    if s.xp > 0 then parts[#parts + 1] = ns.Comma(s.xp) .. " XP" end
    if s.levels > 0 then parts[#parts + 1] = "+" .. s.levels .. (s.levels == 1 and " level" or " levels") end
    if s.quests > 0 then parts[#parts + 1] = s.quests .. (s.quests == 1 and " quest" or " quests") end
    if s.runs > 0 then parts[#parts + 1] = s.runs .. (s.runs == 1 and " dungeon" or " dungeons") end
    if s.gold ~= 0 then parts[#parts + 1] = (s.gold > 0 and "+" or "") .. ns.PlainMoney(s.gold) end
    if s.deaths > 0 then parts[#parts + 1] = s.deaths .. (s.deaths == 1 and " death" or " deaths") end
    local text = head .. ": " .. table.concat(parts, ", ") .. "."
    if #s.finds > 0 then
        local shown = {}
        for i = 1, math.min(3, #s.finds) do shown[i] = s.finds[i] end
        text = text .. " Best finds: " .. table.concat(shown, ", ") .. (#s.finds > 3 and (" and " .. (#s.finds - 3) .. " more") or "") .. "."
    end
    return text
end

function M:LastWeek()
    local monday = M.WeekStart()
    return self:Text(self:Stats(monday - 7 * DAY, monday), "Last week")
end

function M:ThisWeek()
    local monday = M.WeekStart()
    return self:Text(self:Stats(monday, monday + 7 * DAY), "This week")
end

-- What waits now: a list of lines. Live, so it is right even when another addon moved on.
function M:Waiting()
    local lines = {}
    local stop = Data().stop
    if stop and stop.zone and stop.zone ~= "" then
        lines[#lines + 1] = "You stopped in " .. stop.zone .. (stop.sub and stop.sub ~= "" and stop.sub ~= stop.zone and (", " .. stop.sub) or "")
            .. (stop.at and (", " .. ns.Duration(math.max(0, time() - stop.at)) .. " ago") or "") .. "."
    end
    local route = type(UndeadRoute) == "table" and type(UndeadRoute.Status) == "function" and select(2, pcall(UndeadRoute.Status))
    if type(route) == "table" then
        if (tonumber(route.ready) or 0) > 0 then
            lines[#lines + 1] = route.ready .. (route.ready == 1 and " quest is" or " quests are") .. " ready to hand in."
        end
        if type(route.next) == "string" then lines[#lines + 1] = "Next on the route: " .. route.next .. "." end
    end
    local coach = ns.modules.coach
    if coach and coach.enabled and coach.Forecasts then
        local ok, list = pcall(coach.Forecasts, coach)
        local first = ok and type(list) == "table" and list[1]
        if first then lines[#lines + 1] = first[1] .. " in " .. first[2]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "." end
    end
    local open = 0
    for _, note in ipairs(ns.chardb.notes or {}) do
        if not note.done then open = open + 1 end
    end
    for _, note in ipairs(ns.db.notes or {}) do
        if not note.done then open = open + 1 end
    end
    if open > 0 then lines[#lines + 1] = open .. (open == 1 and " to-do is" or " to-dos are") .. " open." end
    return lines
end

M:On("PLAYER_LOGOUT", function()
    local data = Data()
    data.stop = { at = time(), zone = GetRealZoneText and GetRealZoneText() or "", sub = GetSubZoneText and GetSubZoneText() or "",
        level = UnitLevel and ns.Level() or nil }
end)

function M:OnEnable()
    if self.started then return end
    self.started = true
    local data = Data()
    local stop = data.stop
    ns.After(9, function() -- after the welcome line
        if not self.enabled then return end
        local monday = M.WeekStart()
        if self.db.week and data.week ~= monday then
            data.week = monday
            local text = self:LastWeek()
            if text then ns.Alert(text) end
        end
        if self.db.plan and stop and stop.at and time() - stop.at >= AWAY then
            local lines = self:Waiting()
            if #lines > 0 then
                ns.Print("since last time:")
                for _, line in ipairs(lines) do print("  " .. line) end
            end
        end
    end)
end

-- The week's numbers move slowly, and the open window asks every second: worked out every CARD_EVERY seconds.
local CARD_EVERY = 15
local cardAt, cardWas

function M:Card()
    local now = GetTime()
    if cardAt and now - cardAt < CARD_EVERY then return cardWas end
    cardAt = now
    local s = self:Stats(M.WeekStart(), M.WeekStart() + 7 * DAY)
    cardWas = s.played > 0 and { title = "This week", lines = {
        { "Played", ns.Duration(s.played) },
        { "XP", ns.Comma(s.xp) .. (s.levels > 0 and ("  +" .. s.levels .. " lv") or "") },
        { "Quests, dungeons", s.quests .. ", " .. s.runs },
    } } or nil
    return cardWas
end

function M:Slash(arg)
    local word = (arg or ""):lower():match("^%s*(%S*)")
    if word == "guild" then
        local text = self:LastWeek() or self:ThisWeek()
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        if not text then ns.Print("nothing played yet to tell.") return end
        if not (IsInGuild and IsInGuild() and send) then ns.Print("you are not in a guild. " .. text) return end
        send(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), "GUILD")
        return
    end
    if word == "plan" then
        local lines = self:Waiting()
        ns.Print(#lines > 0 and "waiting:" or "nothing waiting.")
        for _, line in ipairs(lines) do print("  " .. line) end
        return
    end
    ns.Print(self:ThisWeek() or "nothing played this week yet.")
    ns.Print(self:LastWeek() or "nothing played last week.")
    if word == "" then
        for _, line in ipairs(self:Waiting()) do print("  " .. line) end
    end
end
