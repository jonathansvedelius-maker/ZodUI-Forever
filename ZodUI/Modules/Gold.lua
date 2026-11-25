local ADDON, ns = ...
local T = ns.T

-- Gold: what every character holds, and what was earned and spent per day.

local M = ns:NewModule("gold", {
    title = "Gold",
    desc = "Remembers how much gold each of your characters holds and keeps a day-by-day ledger of what you earned and spent.",
    defaults = { enabled = true, keepDays = 60, milestone = 1000000 },
    options = {
        { type = "cycle", key = "milestone", label = "A notice when your gold passes", choices = { { 0, "Never" }, { 100000, "Every 10 gold" },
            { 1000000, "Every 100 gold" }, { 10000000, "Every 1,000 gold" } } },
        { type = "step", key = "keepDays", label = "Days of history to keep", min = 14, max = 365, step = 7,
            format = function(v) return v .. " days" end },
        { type = "button", label = "The day-by-day ledger", text = "Clear", confirm = "Sure? Click again", click = function()
            if ns.db.gold then ns.db.gold.days = {} end
            ns.Print("the day-by-day gold ledger is cleared.")
        end },
    },
})

local last
local session = { earned = 0, spent = 0, from = {} }
local showFrom = false

-- Where money comes from: the window that is open when it changes, or a quest just handed in.
local SOURCES = { { "loot", "Looted" }, { "quests", "Quests" }, { "merchant", "Merchants (sales, buys, repairs)" }, { "mail", "Mail" },
    { "trainer", "Trainers" }, { "taxi", "Flights" }, { "auction", "Auction house" }, { "other", "Other" } }
local WINDOWS = { { "LOOT_OPENED", "LOOT_CLOSED", "loot" }, { "MERCHANT_SHOW", "MERCHANT_CLOSED", "merchant" },
    { "MAIL_SHOW", "MAIL_CLOSED", "mail" }, { "TRAINER_SHOW", "TRAINER_CLOSED", "trainer" }, { "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "taxi" },
    { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "auction" } }
local LINGER = 1 -- seconds: the money of a last sale or loot can land just after the window closes
local open, lastQuest, lastOther = {}, nil, nil

for _, w in ipairs(WINDOWS) do
    M:On(w[1], function() open[w[3]] = (open[w[3]] or 0) + 1 end)
    M:On(w[2], function()
        ns.After(LINGER, function() open[w[3]] = math.max(0, (open[w[3]] or 0) - 1) end)
    end)
end

-- An open window wins; a quest handed in just now only explains money coming in.
local function Source(delta)
    for _, w in ipairs(WINDOWS) do
        if (open[w[3]] or 0) > 0 then return w[3] end
    end
    if delta > 0 and lastQuest and GetTime() - lastQuest < 2 then return "quests" end
    return "other"
end

local function Book(from, key, amount)
    from[key] = (from[key] or 0) + amount
end

local function Day(key)
    local days = ns.db.gold.days
    days[key] = days[key] or { earned = 0, spent = 0 }
    return days[key]
end

function M:OnEnable()
    ns.db.gold = ns.db.gold or {}
    ns.db.gold.days = ns.db.gold.days or {}
    local cutoff = ns.Today(self.db.keepDays)
    for key in pairs(ns.db.gold.days) do
        if key < cutoff then ns.db.gold.days[key] = nil end
    end
    last = GetMoney()
    ns.char.money = last
end

M:On("PLAYER_MONEY", function()
    local now = GetMoney()
    local delta = now - (last or now)
    last = now
    ns.char.money = now
    if delta == 0 then return end
    local day = Day(ns.Today())
    day.from = day.from or {}
    local source = Source(delta)
    Book(day.from, source, delta)
    Book(session.from, source, delta)
    lastOther = source == "other" and { delta = delta, at = GetTime(), day = day.from } or nil
    if delta > 0 then
        day.earned = day.earned + delta
        session.earned = session.earned + delta
        local step = M.db.milestone or 0
        if step > 0 and math.floor(now / step) > math.floor((now - delta) / step) then
            ns.Alert("You passed " .. ns.Money(math.floor(now / step) * step, true) .. ".")
        end
    else
        day.spent = day.spent - delta
        session.spent = session.spent - delta
    end
    ns.Refresh()
end)

local function Signed(copper)
    if copper == 0 then return ns.Money(0) end
    return (copper > 0 and "|cff59d973+|r" or "") .. ns.Money(copper)
end

function M:Total()
    local total = 0
    for _, char in pairs(ns.db.chars) do total = total + (char.money or 0) end
    return total
end

-- A quest's money can arrive just before the quest says it was handed in: move it over.
M:On("QUEST_TURNED_IN", function(_, _, _, _, money)
    lastQuest = GetTime()
    money = tonumber(money) or 0
    if money > 0 and lastOther and lastOther.delta == money and GetTime() - lastOther.at < 2 then
        Book(lastOther.day, "other", -money)
        Book(lastOther.day, "quests", money)
        Book(session.from, "other", -money)
        Book(session.from, "quests", money)
        lastOther = nil
        ns.Refresh()
    end
end)

-- Earned minus spent this session, in copper.
function M:Session()
    return session.earned - session.spent
end

function M:Card()
    local today = ns.db.gold.days[ns.Today()] or { earned = 0, spent = 0 }
    return {
        title = "Gold",
        lines = {
            { "This character", ns.Money(GetMoney()) },
            { "All characters", ns.Money(self:Total(), true) },
            { "This session", Signed(session.earned - session.spent) },
            { "Today", Signed(today.earned - today.spent) },
        },
        button = { "Ledger", function() ns.Show("gold") end },
    }
end

ns.AddPage({
    key = "gold", title = "Gold", order = 20, group = "This character", module = "gold",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Gold module is off. Switch it on under Settings.")
        page.total = T.Text(f, "GameFontNormalLarge")
        page.total:SetPoint("TOPLEFT", 0, -2)
        page.sub = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.sub:SetPoint("TOPLEFT", 0, -28)
        page.week = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.week:SetPoint("TOPRIGHT", 0, -6)
        page.week:SetJustifyH("RIGHT")
        page.chars = T.Table(f, { { "Character", 220 }, { "Level", 60 }, { "Realm", w - 480 }, { "Gold", 190, "RIGHT" } }, w, 180)
        page.chars:SetPoint("TOPLEFT", 0, -52)
        page.days = T.Table(f, { { "Day", w - 580 }, { "Earned", 190, "RIGHT" }, { "Spent", 190, "RIGHT" }, { "Net", 190, "RIGHT" } },
            w, ns.PAGE_H - 262)
        page.days:SetPoint("TOPLEFT", 0, -262)
        page.from = T.Table(f, { { "Where", w - 580 }, { "Today", 190, "RIGHT" }, { "This session", 190, "RIGHT" }, { "Last 7 days", 190, "RIGHT" } },
            w, ns.PAGE_H - 262)
        page.from:SetPoint("TOPLEFT", 0, -262)
        page.mode = T.Button(f, "Where it came from", 160, function()
            showFrom = not showFrom
            page:Refresh()
        end)
        page.mode:SetSize(160, 20)
        page.mode:SetPoint("TOPRIGHT", 0, -238)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.total:SetShown(on)
        page.sub:SetShown(on)
        page.week:SetShown(on)
        page.chars:SetShown(on)
        page.days:SetShown(on and not showFrom)
        page.from:SetShown(on and showFrom)
        page.mode:SetShown(on)
        if not on then return end
        page.mode.label:SetText(showFrom and "Day by day" or "Where it came from")
        if showFrom then
            local today = ns.db.gold.days[ns.Today()] or {}
            local week, from7 = {}, ns.Today(6)
            for key, d in pairs(ns.db.gold.days) do
                if key >= from7 then
                    for k, v in pairs(d.from or {}) do week[k] = (week[k] or 0) + v end
                end
            end
            local rows = {}
            for _, s in ipairs(SOURCES) do
                local a, b, c = (today.from or {})[s[1]] or 0, session.from[s[1]] or 0, week[s[1]] or 0
                if a ~= 0 or b ~= 0 or c ~= 0 then
                    rows[#rows + 1] = { s[2], a ~= 0 and Signed(a) or "-", b ~= 0 and Signed(b) or "-", c ~= 0 and Signed(c) or "-" }
                end
            end
            page.from:SetRows(rows, "Where your gold comes from and goes is sorted here from now on.")
        end

        -- Counts to a new total from the last one (the first is set at once; the same one again changes nothing).
        ns.Motion.CountTo(page.total, M:Total(), function(v) return "|cffffd100All characters:|r  " .. ns.Money(v) end)
        local week, played, bestKey, best = 0, 0, nil, nil
        local from = ns.Today(6)
        for key, d in pairs(ns.db.gold.days) do
            local net = d.earned - d.spent
            if key >= from then week, played = week + net, played + 1 end
            if net > 0 and (not best or net > best) then bestKey, best = key, net end
        end
        page.sub:SetText("This session: " .. Signed(session.earned - session.spent) .. "   |cff999999earned|r " .. ns.Money(session.earned)
            .. "   |cff999999spent|r " .. ns.Money(session.spent))
        page.week:SetText("|cff999999Last 7 days|r " .. Signed(week) .. (played > 0 and ("  |cff999999a day|r " .. Signed(math.floor(week / played))) or "")
            .. (best and ("\n|cff999999Best day|r " .. ns.When(ns.DayTime(bestKey), true) .. "  " .. Signed(best)) or ""))

        local rows = {}
        for _, char in pairs(ns.db.chars) do
            rows[#rows + 1] = { "|c" .. ns.ClassHex(char.class) .. (char.name or "?") .. "|r", char.level or "?", char.realm or "",
                ns.Money(char.money or 0), money = char.money or 0 }
        end
        table.sort(rows, function(a, b) return a.money > b.money end)
        page.chars:SetRows(rows)

        local days = {}
        for key, d in pairs(ns.db.gold.days) do
            days[#days + 1] = { ns.WhenCell(ns.DayTime(key), true), ns.Money(d.earned), ns.Money(d.spent), Signed(d.earned - d.spent), key = key }
        end
        table.sort(days, function(a, b) return a.key > b.key end)
        page.days:SetRows(days, "Gold you earn and spend from now on is listed here, one line per day.")
    end,
})
