local ADDON, ns = ...
local T = ns.T

-- Session & XP: what this play session has earned, how fast, and how long each
-- level took. A session carries over a /reload or a quick relog (under ten
-- minutes away); anything longer starts a new one.

local M = ns:NewModule("session", {
    title = "Session & XP",
    desc = "Counts the XP, quests and deaths of this play session, works out XP per hour and the time left to the next level, and keeps a log of how long every level took.",
    defaults = { enabled = true, announce = true, screenshot = false },
    options = {
        { type = "check", key = "announce", label = "Say in chat how long a level took when you reach the next" },
        { type = "check", key = "screenshot", label = "Take a screenshot when you level up" },
        { type = "button", label = "This session's numbers", text = "Start over", click = function(m) m:Reset() end },
    },
})

local RESUME = 600 -- seconds away after which a new session starts
local S, lastXP, lastMax, lastTick

local function Fresh()
    return { start = time(), last = time(), xp = 0, gains = 0, quests = 0, questXP = 0, deaths = 0, levels = 0, kills = 0, money = GetMoney() }
end

function M:Reset()
    S = Fresh()
    ns.chardb.session = S
    ns.Refresh()
end

function M:OnEnable()
    local cdb = ns.chardb
    cdb.levels = cdb.levels or {}
    cdb.played = cdb.played or 0
    S = cdb.session
    if not S or time() - (S.last or 0) > RESUME then
        S = Fresh()
        cdb.session = S
    end
    S.kills = S.kills or 0
    S.money = S.money or GetMoney() -- a session from before this version
    lastXP, lastMax = UnitXP("player") or 0, UnitXPMax("player") or 0
    lastTick = time()
end

-- XP to the next level, by level (the classic table). Used only to guess how
-- long the levels ahead take, so a server that differs only makes the guess off.
local XP_TO_LEVEL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700,
    19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800, 67100,
    71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900,
    160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }
local TOP = #XP_TO_LEVEL + 1
M.XP_TO_LEVEL = XP_TO_LEVEL -- the Leveling coach reads it too

-- XP still needed for the top level, or nil at the top.
function M:XPToTop()
    local level = ns.Level() or 1
    if level >= TOP then return nil end
    local left = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    for l = level + 1, TOP - 1 do left = left + XP_TO_LEVEL[l] end
    return left, TOP
end

local BEST_AFTER = 900 -- a session counts for the best XP per hour once it is this long

-- Gold per hour this session (copper; negative when more was spent than earned).
function M:GoldRate()
    local elapsed = math.max(60, time() - S.start)
    return (GetMoney() - (S.money or GetMoney())) / elapsed * 3600
end

-- Seconds logged in on this character since ZodUI was installed.
local function Tick()
    local now = time()
    local gap = now - (lastTick or now)
    if gap > 0 and gap < 120 then ns.chardb.played = (ns.chardb.played or 0) + gap end
    lastTick = now
    S.last = now
    local long = now - S.start
    if long >= BEST_AFTER and S.xp > 0 then
        local rate = S.xp / long * 3600
        if rate > (ns.chardb.bestRate or 0) then ns.chardb.bestRate = rate end
    end
end

ns.Every(10, Tick, M)
M:On("PLAYER_LOGOUT", Tick)

M:On("PLAYER_XP_UPDATE", function()
    local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    local delta = cur - lastXP
    if delta < 0 then delta = delta + lastMax end -- the bar wrapped: a level was gained
    if delta > 0 then
        S.xp = S.xp + delta
        S.gains = S.gains + 1
    end
    lastXP, lastMax = cur, max
    ns.Refresh()
end)

M:On("PLAYER_LEVEL_UP", function(self, _, level)
    Tick()
    local cdb = ns.chardb
    local prev = cdb.levels[level - 1]
    local entry = { at = time(), played = cdb.played }
    if prev and prev.played then entry.took = cdb.played - prev.played end
    cdb.levels[level] = entry
    S.levels = S.levels + 1
    if self.db.announce then
        if entry.took then
            ns.Print("level " .. level .. ". Level " .. (level - 1) .. " took " .. ns.Duration(entry.took) .. " of play.")
        else
            ns.Print("level " .. level .. ". From here on ZodUI times every level.")
        end
    end
    if self.db.screenshot and Screenshot then ns.After(1.5, Screenshot) end
    ns.Refresh()
end)

-- "A Kobold dies, you gain 45 experience." Quest XP says no "dies".
M:On("CHAT_MSG_COMBAT_XP_GAIN", function(_, _, msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    if msg:find(" dies", 1, true) then
        S.kills = S.kills + 1
        S.killXP = (S.killXP or 0) + (tonumber(msg:match("(%d+) experience")) or 0)
        ns.Refresh()
    end
end)

M:On("PLAYER_DEAD", function()
    S.deaths = S.deaths + 1
    ns.Refresh()
end)

M:On("QUEST_TURNED_IN", function(_, _, _, xp)
    S.quests = S.quests + 1
    S.questXP = S.questXP + (tonumber(xp) or 0)
    ns.Refresh()
end)

-- XP per hour, and the seconds to the next level at that rate (nil while nothing was earned).
function M:Rate()
    local elapsed = math.max(60, time() - S.start)
    local perHour = S.xp / elapsed * 3600
    local max = UnitXPMax("player") or 0
    local left = max - (UnitXP("player") or 0)
    local eta = (perHour > 0 and max > 0) and (left / perHour * 3600) or nil
    return perHour, eta, left
end

function M:Card()
    local perHour, eta = self:Rate()
    return {
        title = "Session",
        lines = {
            { "XP per hour", perHour > 0 and ns.Comma(perHour) or "-" },
            { "Next level in", eta and ns.Duration(eta) or "-" },
            { "Played", ns.Duration(time() - S.start) },
            { "Quests / deaths", S.quests .. " / " .. S.deaths },
        },
        button = { "Details", function() ns.Show("session") end },
    }
end

ns.AddPage({
    key = "session", title = "Session", order = 10, group = "This character", module = "session",
    Build = function(page, f)
        local half = (ns.PAGE_W - 10) / 2
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Session & XP module is off. Switch it on under Settings.")
        page.stats = T.Table(f, { { "This session", half - 100 }, { "", 90, "RIGHT" } }, half, ns.PAGE_H - 34)
        page.stats:SetPoint("TOPLEFT", 0, 0)
        page.levels = T.Table(f, { { "Level", 60 }, { "Reached", half - 190 }, { "Play time", 120, "RIGHT" } }, half, ns.PAGE_H - 34)
        page.levels:SetPoint("TOPLEFT", half + 10, 0)
        page.reset = T.Button(f, "Start a new session", 160, function() M:Reset() end)
        page.reset:SetPoint("BOTTOMLEFT", 0, 0)
        page.reset.confirm = "Sure? Click again"
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.stats:SetShown(on)
        page.levels:SetShown(on)
        page.reset:SetShown(on)
        if not on then return end

        local perHour, eta, left = M:Rate()
        local avg = S.gains > 0 and S.xp / S.gains or 0
        local rows = {
            { "Time played", ns.Duration(time() - S.start) },
            { "XP earned", ns.Comma(S.xp) },
            { "XP per hour", perHour > 0 and ns.Comma(perHour) or "-" },
            { "Time to next level", eta and ns.Duration(eta) or "-" },
            { "XP to next level", left > 0 and ns.Comma(left) or "-" },
            { "Kills or hand-ins to next level", (avg > 0 and left > 0) and ("about " .. math.ceil(left / avg)) or "-" },
            { "Quests handed in", S.quests },
            { "XP from quests", ns.Comma(S.questXP) },
            { "Levels gained", S.levels },
            { "Deaths", S.deaths },
            { "Played on this character", ns.Duration(ns.chardb.played or 0) },
        }
        local rested = GetXPExhaustion and GetXPExhaustion() or 0
        local gold = M:GoldRate()
        local best = ns.chardb.bestRate
        local level = ns.Level() or 0
        local last = ns.chardb.levels and ns.chardb.levels[level]
        local sum, n = 0, 0
        for _, e in pairs(ns.chardb.levels or {}) do
            if e.took then sum, n = sum + e.took, n + 1 end
        end
        table.insert(rows, 4, { "Gold per hour", gold ~= 0 and ((gold > 0 and "+" or "") .. ns.Money(gold, true)) or "-" })
        table.insert(rows, 5, { "Best XP per hour", best and ns.Comma(best) or "-" })
        table.insert(rows, 8, { "Rested XP left", rested > 0 and ns.Comma(rested) or "-" })
        table.insert(rows, 10, { "Kills that gave XP", S.kills })
        local kill = S.killXP or 0
        table.insert(rows, 9, { "XP from kills", ns.Comma(kill) })
        table.insert(rows, 11, { "Other XP (exploring and such)", ns.Comma(math.max(0, S.xp - kill - S.questXP)) })
        local toTop, top = M:XPToTop()
        local pace = (perHour > 0 and perHour) or best
        if toTop then
            rows[#rows + 1] = { "Level " .. top .. " in", pace and pace > 0 and ("about " .. ns.Duration(toTop / pace * 3600)) or "-" }
        end
        rows[#rows + 1] = { "Last level took", last and last.took and ns.Duration(last.took) or "-" }
        rows[#rows + 1] = { "A level on average", n > 0 and ns.Duration(sum / n) or "-" }
        page.stats:SetRows(rows)

        local log = {}
        for level, e in pairs(ns.chardb.levels or {}) do
            log[#log + 1] = { level, ns.WhenCell(e.at), e.took and ns.Duration(e.took) or "-" }
        end
        table.sort(log, function(a, b) return a[1] > b[1] end)
        page.levels:SetRows(log, "Each level you reach from now on is listed here with the play time it took.")
    end,
})
