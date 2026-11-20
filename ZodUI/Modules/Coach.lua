local ADDON, ns = ...
local T = ns.T

-- Leveling coach: how fast you level and when you get where you are going. Undead Route says where to be (its
-- stage and next step); the coach says how long that takes at your pace:
--   pace       XP per played hour over the last days (History), and this session's (Session & XP)
--   forecasts  the next level, the end of the route's stage, your level goal (Goals) and 60, in played time
--              and in days at the time you usually play a day
--   zones      XP per hour in each zone you levelled in, kept here, so the best ones show
--   rested     how much rested XP you have, and when each of your characters is full (from Characters)
-- Without Undead Route there is no stage, the rest works the same. Nothing here changes another module's data.

local M = ns:NewModule("coach", {
    title = "Leveling coach",
    desc = "How fast you level and when you get there: XP per hour, the next level, the end of Undead Route's stage, "
        .. "your level goal and 60. Your best zones by XP per hour, and when your characters are fully rested.",
    defaults = { enabled = true, days = 7 },
    options = {
        { type = "note", text = "/zod coach opens it; Home has its card. Pace is XP per played hour over the last "
            .. "days that had play, so a short session does not swing it.", lines = 3 },
    },
})

local TICK = 10
local TOP = 60
local REST_RATE = 0.05 / (8 * 3600)  -- of a level's XP a second while resting (5% per 8 hours)
local REST_CAP = 1.5                   -- rested XP stops at one and a half levels
local OUTSIDE = 0.25                   -- the rate away from an inn or city
local ZONE_MIN = 600                   -- seconds in a zone before its pace counts

local function Data()
    local d = ns.chardb.coach
    if not d then
        d = { zones = {} }
        ns.chardb.coach = d
    end
    return d
end

local function Zone()
    local z = GetRealZoneText and GetRealZoneText() or ""
    return z ~= "" and z or nil
end

local lastXP, lastMax

function M:OnEnable()
    Data()
    lastXP, lastMax = UnitXP("player") or 0, UnitXPMax("player") or 0
end

M:On("PLAYER_XP_UPDATE", function()
    local xp, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    local gain = xp - (lastXP or xp)
    if gain < 0 then gain = (lastMax or 0) - (lastXP or 0) + xp end -- a level-up
    lastXP, lastMax = xp, max
    local zone = Zone()
    if gain > 0 and zone then
        local z = Data().zones[zone] or { xp = 0, time = 0 }
        z.xp = z.xp + gain
        Data().zones[zone] = z
    end
end)

-- Time counts in a zone while you level there: not at the top level, not while away.
ns.Every(TICK, function()
    local level = ns.Level() or 0
    if level >= TOP or ns.IsAway() then return end
    local zone = Zone()
    if not zone then return end
    local z = Data().zones[zone] or { xp = 0, time = 0 }
    z.time = z.time + TICK
    Data().zones[zone] = z
end, M)

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------

-- XP per played hour over the last `days` days that had play, and how long you play on such a day.
function M:Pace()
    local days = ns.chardb.history and ns.chardb.history.days or {}
    local keys = {}
    for key, d in pairs(days) do
        if (d.played or 0) >= 300 then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return a > b end)
    local xp, played, n = 0, 0, 0
    for i = 1, math.min(#keys, self.db.days or 7) do
        local d = days[keys[i]]
        xp, played, n = xp + (d.xp or 0), played + (d.played or 0), n + 1
    end
    if played < 600 or xp <= 0 then return nil end
    return xp / played * 3600, played / n
end

-- XP from here to the start of `level`: what is left of this level, then each level between from the classic
-- table Session & XP keeps (nil when a level is missing from it).
function M:XPTo(level)
    local now = ns.Level() or 1
    if level <= now then return 0 end
    local left = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    local table_ = ns.modules.session and ns.modules.session.XP_TO_LEVEL or {}
    for l = now + 1, math.min(level, TOP) - 1 do
        if not table_[l] then return nil end
        left = left + table_[l]
    end
    return left
end

-- Where Undead Route wants you, or nil: { stage, min, max, kind }.
function M.Route()
    local route = UndeadRoute
    if type(route) ~= "table" or not route.Status then return nil end
    local ok, s = pcall(route.Status)
    if not ok or type(s) ~= "table" then return nil end
    local min, max = tonumber(s.min), tonumber(s.max)
    if not (min and max) then -- an older route: read "20-25"
        local a, b = tostring(s.range or ""):match("^(%d+)%D+(%d+)$")
        min, max = tonumber(a), tonumber(b)
    end
    if not (min and max) or s.kind == "city" or s.kind == "class" then return nil end
    return { stage = tostring(s.stage), min = min, max = max, kind = s.kind }
end

local function Played(sec)
    return sec and ns.Duration(sec) or "?"
end

-- A forecast line: label, the XP to go, and the pace.
local function Forecast(label, xp, perHour, perDay)
    if not xp or xp <= 0 then return nil end
    if not perHour then return { label, ns.Comma(xp) .. " XP" } end
    local sec = xp / perHour * 3600
    local days = perDay and perDay > 0 and math.ceil(sec / perDay) or nil
    return { label, Played(sec) .. " played" .. (days and days > 1 and ("  |cff999999about " .. days .. " days|r") or "") }
end

function M:Forecasts()
    local perHour, perDay = self:Pace()
    if not perHour then
        local session = ns.modules.session
        if session and session.enabled and session.Rate then
            local rate = session:Rate()
            if rate and rate > 0 then perHour = rate end
        end
    end
    local level, out = ns.Level() or 1, {}
    if level >= TOP then return out, perHour, perDay end
    out[#out + 1] = Forecast("Level " .. (level + 1), self:XPTo(level + 1), perHour, perDay)
    local route = self.Route()
    if route and route.max > level and route.max < TOP then
        out[#out + 1] = Forecast(route.stage .. " done (" .. route.max .. ")", self:XPTo(route.max), perHour, perDay)
    end
    local goal = tonumber(ns.chardb.levelGoal)
    if goal and goal > level + 1 and goal < TOP then out[#out + 1] = Forecast("Your goal, " .. goal, self:XPTo(goal), perHour, perDay) end
    out[#out + 1] = Forecast("Level " .. TOP, self:XPTo(TOP), perHour, perDay)
    return out, perHour, perDay
end

-- Advice about the route's stage: under it, in it or past it.
function M:RouteAdvice()
    local route = self.Route()
    if not route then return nil end
    local level = ns.Level() or 1
    if level < route.min then
        return "You are " .. (route.min - level) .. (route.min - level == 1 and " level" or " levels") .. " under " .. route.stage
            .. " (" .. route.min .. "-" .. route.max .. "). Finish what is green and yellow where you are first."
    elseif level >= route.max then
        return "You are past " .. route.stage .. " (" .. route.min .. "-" .. route.max .. "). Undead Route has the next stage: /route."
    end
    return "On pace for " .. route.stage .. " (" .. route.min .. "-" .. route.max .. ")."
end

-- Your zones by XP per hour, best first.
function M:Zones()
    local list = {}
    for name, z in pairs(Data().zones) do
        if z.time >= ZONE_MIN and z.xp > 0 then list[#list + 1] = { name = name, perHour = z.xp / z.time * 3600, time = z.time } end
    end
    table.sort(list, function(a, b) return a.perHour > b.perHour end)
    return list
end

-- Rested XP of every character you have, worked out to now, and when each is full.
function M:Rested()
    local out, now = {}, time()
    for key, c in pairs(ns.db.chars or {}) do
        local max, level = tonumber(c.xpMax), tonumber(c.level)
        if max and max > 0 and level and level < TOP then
            local mine = c.name == ns.MyName()
            local rested = mine and (GetXPExhaustion and GetXPExhaustion() or 0) or (tonumber(c.rested) or 0)
            local resting = mine and (IsResting and IsResting()) or c.resting
            local rate = REST_RATE * max * (resting and 1 or OUTSIDE)
            if not mine and c.seen then rested = rested + rate * math.max(0, now - c.seen) end
            local cap = REST_CAP * max
            rested = math.min(cap, rested)
            out[#out + 1] = { name = c.name or key, level = level, rested = rested, levels = rested / max,
                full = rested >= cap and 0 or (cap - rested) / rate, resting = resting and true or false, mine = mine }
        end
    end
    table.sort(out, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        return a.levels > b.levels
    end)
    return out
end

---------------------------------------------------------------------------

function M:Slash(arg)
    if (arg or "") == "" then ns.Show("coach") return end
    ns.Print("use /zod coach.")
end

function M:Card()
    if (ns.Level() or TOP) >= TOP then return nil end
    local list = self:Forecasts()
    if #list == 0 then return nil end
    local lines = {}
    for i = 1, math.min(3, #list) do lines[i] = list[i] end
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    local max = UnitXPMax("player") or 0
    if rested > 0 and max > 0 then lines[#lines + 1] = { "Rested", math.floor(rested / max * 100 + 0.5) .. "% of a level" } end
    return { title = "Leveling coach", lines = lines, button = { "More", function() ns.Show("coach") end } }
end

ns.AddPage({
    key = "coach", title = "Leveling coach", order = 19.5, group = "This character", module = "coach",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Leveling coach is off. Switch it on under Settings.")
        page.sum = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.sum:SetPoint("TOPLEFT", 0, -4)
        page.sum:SetWidth(w)
        page.route = T.Text(f, "GameFontHighlightSmall", T.GOLD)
        page.route:SetPoint("TOPLEFT", 0, -22)
        page.route:SetWidth(w)
        local half = math.floor((w - 12) / 2)
        local h = math.floor((ns.PAGE_H - 52) / 2) - 6
        page.when = T.Table(f, { { "When you get there", half - 190 }, { "At your pace", 190 } }, half, h)
        page.when:SetPoint("TOPLEFT", 0, -44)
        page.zones = T.Table(f, { { "Best zones", half - 170 }, { "XP per hour", 90, "RIGHT" }, { "Time", 80, "RIGHT" } }, half, h)
        page.zones:SetPoint("TOPLEFT", half + 12, -44)
        page.rest = T.Table(f, { { "Rested", w - 360 }, { "Level", 50, "RIGHT" }, { "Now", 120, "RIGHT" }, { "Full in", 190, "RIGHT" } }, w, h)
        page.rest:SetPoint("TOPLEFT", 0, -44 - h - 12)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        for _, k in ipairs({ "sum", "route", "when", "zones", "rest" }) do page[k]:SetShown(on) end
        if not on then return end
        local list, perHour, perDay = M:Forecasts()
        page.sum:SetText(perHour and ("Your pace: " .. ns.Comma(perHour) .. " XP per played hour"
            .. (perDay and (", about " .. ns.Duration(perDay) .. " played on a day you play") or "") .. ".")
            or "No pace yet: play a while and it shows here.")
        page.route:SetText(M:RouteAdvice() or (UndeadRoute and "" or "With Undead Route installed, the end of its stage is forecast too."))
        page.when:SetRows(list, (ns.Level() or 0) >= TOP and "Level " .. TOP .. ": nothing left to level." or "Play a while first.")
        local zones = {}
        for _, z in ipairs(M:Zones()) do zones[#zones + 1] = { z.name, ns.Comma(z.perHour), ns.Duration(z.time) } end
        page.zones:SetRows(zones, "Zones show here after 10 minutes of levelling in them.")
        local rest = {}
        for _, c in ipairs(M:Rested()) do
            rest[#rest + 1] = { c.name .. (c.resting and "  |cff999999resting|r" or ""), c.level,
                math.floor(c.levels * 100 + 0.5) .. "%", c.full <= 0 and T.Paint("full", T.GREEN) or ns.Duration(c.full) }
        end
        page.rest:SetRows(rest, "Your characters below " .. TOP .. " show here.")
    end,
})
