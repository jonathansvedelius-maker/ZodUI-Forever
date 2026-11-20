local ADDON, ns = ...
local T = ns.T

-- History: a diary with one line per day played: time, XP, quests, levels,
-- gold and deaths, and a chart of the XP of the last two weeks.

local M = ns:NewModule("history", {
    title = "History",
    desc = "Keeps a diary of this character with one line per day played: time, XP, quests, levels, gold and deaths, and charts the XP of the last two weeks.",
    defaults = { enabled = true },
})

local KEEP = 120 -- days
local BARS = 14
local TICK = 10
local lastXP, lastMax, lastMoney
local chartMode = "xp" -- or "played"

local function Data()
    local data = ns.chardb.history
    if not data then
        data = { days = {} }
        ns.chardb.history = data
    end
    return data
end

local function Day()
    local days, key = Data().days, ns.Today()
    local day = days[key]
    if not day then
        day = { xp = 0, quests = 0, deaths = 0, levels = 0, gold = 0, played = 0 }
        days[key] = day
    end
    return day
end

local function Keys()
    local keys = {}
    for key in pairs(Data().days) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return a > b end) -- newest first; the keys are yyyy-mm-dd
    return keys
end

function M:OnEnable()
    lastXP, lastMax, lastMoney = UnitXP("player") or 0, UnitXPMax("player") or 0, GetMoney()
    local days, keys = Data().days, Keys()
    for i = KEEP + 1, #keys do days[keys[i]] = nil end
end

M:On("PLAYER_XP_UPDATE", function()
    local xp, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    local gain = xp - (lastXP or xp)
    if gain < 0 then gain = (lastMax or 0) - (lastXP or 0) + xp end -- a level-up
    lastXP, lastMax = xp, max
    if gain > 0 then
        local day = Day()
        day.xp = day.xp + gain
    end
end)

M:On("PLAYER_MONEY", function()
    local money = GetMoney()
    if lastMoney then
        local day = Day()
        day.gold = day.gold + money - lastMoney
    end
    lastMoney = money
end)

M:On("QUEST_TURNED_IN", function()
    local day = Day()
    day.quests = day.quests + 1
end)

M:On("PLAYER_DEAD", function()
    local day = Day()
    day.deaths = day.deaths + 1
end)

M:On("PLAYER_LEVEL_UP", function()
    local day = Day()
    day.levels = day.levels + 1
end)

ns.Every(TICK, function()
    local day = Day()
    day.played = day.played + TICK
end, M)

local function Signed(copper)
    if copper == 0 then return "-" end
    return (copper > 0 and "|cff59d973+|r" or "") .. ns.Money(copper, true)
end

ns.AddPage({
    key = "history", title = "History", order = 12, group = "This character", module = "history",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The History module is off. Switch it on under Settings.")

        local chart = T.Panel(f, T.PANEL)
        chart:SetSize(w, 150)
        chart:SetPoint("TOPLEFT", 0, 0)
        page.chart = chart
        chart.title = T.Text(chart, "GameFontHighlightSmall", T.GOLD)
        chart.title:SetPoint("TOPLEFT", 10, -8)
        chart.title:SetText("XP a day, the last two weeks")
        chartMode = M.db.chartMode or "xp" -- kept across /reload
        chart.mode = T.Button(chart, "Show play time", 120, function()
            chartMode = chartMode == "xp" and "played" or "xp"
            M.db.chartMode = chartMode ~= "xp" and chartMode or nil
            page:Refresh()
        end)
        chart.mode:SetSize(120, 20)
        chart.mode:SetPoint("TOPRIGHT", -6, -5)
        chart.top = T.Text(chart, "GameFontHighlightSmall", T.MUTED)
        chart.top:SetPoint("TOPRIGHT", chart.mode, "TOPLEFT", -10, -3)
        chart.streak = T.Text(chart, "GameFontHighlightSmall", T.DIM)
        chart.streak:SetPoint("LEFT", chart.title, "RIGHT", 16, 0)
        chart.bars, chart.labels = {}, {}
        local slot = (w - 20) / BARS
        chart.slot = slot
        for i = 1, BARS do
            local bar = chart:CreateTexture(nil, "ARTWORK")
            bar:SetTexture(T.WHITE)
            bar:SetVertexColor(T.GOLD[1], T.GOLD[2], T.GOLD[3], 0.85)
            bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 10 + (i - 1) * slot + 5, 24)
            bar:SetSize(slot - 10, 1)
            chart.bars[i] = bar
            local label = T.Text(chart, "GameFontHighlightSmall", T.MUTED)
            label:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 10 + (i - 1) * slot, 7)
            label:SetWidth(slot)
            label:SetJustifyH("CENTER")
            chart.labels[i] = label
            local hit = CreateFrame("Button", nil, chart) -- the day's slot: its date and value on hover
            hit:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 10 + (i - 1) * slot, 4)
            hit:SetSize(slot, 124)
            hit:SetScript("OnEnter", function(self) if self.tip then T.ShowTip(self, self.tipTitle, self.tip) end end)
            hit:SetScript("OnLeave", T.HideTip)
            chart.hits = chart.hits or {}
            chart.hits[i] = hit
        end

        page.list = T.Table(f, { { "Day", w - 560 }, { "Played", 80, "RIGHT" }, { "XP", 90, "RIGHT" }, { "XP/hour", 90, "RIGHT" },
            { "Quests", 60, "RIGHT" }, { "Levels", 60, "RIGHT" }, { "Gold", 100, "RIGHT" }, { "Deaths", 60, "RIGHT" } }, w, ns.PAGE_H - 160)
        page.list:SetPoint("TOPLEFT", 0, -160)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.chart:SetShown(on)
        page.list:SetShown(on)
        if not on then return end

        local days, chart = Data().days, page.chart
        local field = chartMode
        chart.mode.label:SetText(field == "xp" and "Show play time" or "Show XP")
        chart.title:SetText(field == "xp" and "XP a day, the last two weeks" or "Play time a day, the last two weeks")
        local most = 0
        for i = 1, BARS do
            local day = days[ns.Today(BARS - i)]
            if day and day[field] > most then most = day[field] end
        end
        for i = 1, BARS do
            local key = ns.Today(BARS - i)
            local day = days[key]
            local bar = chart.bars[i]
            if day and day[field] > 0 and most > 0 then
                bar:SetSize(chart.slot - 10, math.max(2, 96 * day[field] / most))
                bar:Show()
            else
                bar:Hide()
            end
            chart.labels[i]:SetText(key:sub(9, 10))
            local hit = chart.hits and chart.hits[i]
            if hit then
                local v = day and day[field] or 0
                hit.tipTitle = ns.When(ns.DayTime(key), true)
                hit.tip = field == "xp" and (ns.Comma(v) .. " XP") or ((v > 0 and ns.Duration(v) or "nothing") .. " played")
            end
        end
        local streak = M:Streak()
        chart.streak:SetText(streak > 1 and (streak .. " days in a row") or "")
        if field == "xp" then
            chart.top:SetText(most > 0 and ("best day " .. ns.Comma(most) .. " XP") or "no XP in these days")
        else
            chart.top:SetText(most > 0 and ("longest day " .. ns.Duration(most)) or "no play time in these days")
        end

        local rows, today = {}, ns.Today()
        -- The last 7 and 30 days added up, above the days themselves.
        for _, span in ipairs({ 7, 30 }) do
            local from = ns.Today(span - 1)
            local sum = { xp = 0, quests = 0, deaths = 0, levels = 0, gold = 0, played = 0 }
            for key, day in pairs(days) do
                if key >= from then
                    for k in pairs(sum) do sum[k] = sum[k] + (day[k] or 0) end
                end
            end
            local rate = sum.played >= 600 and sum.xp > 0 and sum.xp / sum.played * 3600
            rows[#rows + 1] = { T.Paint("Last " .. span .. " days", T.GOLD), sum.played >= 60 and ns.Duration(sum.played) or "-",
                sum.xp > 0 and ns.Comma(sum.xp) or "-", rate and ns.Comma(rate) or "-", sum.quests > 0 and sum.quests or "-",
                sum.levels > 0 and ("+" .. sum.levels) or "-", Signed(sum.gold), sum.deaths > 0 and sum.deaths or "-" }
        end
        for _, key in ipairs(Keys()) do
            local day = days[key]
            local rate = day.played >= 600 and day.xp > 0 and day.xp / day.played * 3600
            rows[#rows + 1] = { key == today and T.Paint("Today", T.GREEN) or key, day.played >= 60 and ns.Duration(day.played) or "-",
                day.xp > 0 and ns.Comma(day.xp) or "-", rate and ns.Comma(rate) or "-", day.quests > 0 and day.quests or "-",
                day.levels > 0 and ("+" .. day.levels) or "-", Signed(day.gold), day.deaths > 0 and day.deaths or "-" }
        end
        page.list:SetRows(rows, "Nothing yet. A day shows up here once you have played on it.")
    end,
})

-- Days in a row with play, up to today (or yesterday, when today has none yet).
function M:Streak()
    local days, n, offset = Data().days, 0, 0
    local function Played(key) return days[key] and days[key].played >= 60 end
    if not Played(ns.Today()) then offset = 1 end
    while Played(ns.Today(offset + n)) do n = n + 1 end
    return n
end

-- Today's numbers: played, xp, quests, levels, gold (copper), deaths.
function M:Today()
    return Data().days[ns.Today()] or { xp = 0, quests = 0, deaths = 0, levels = 0, gold = 0, played = 0 }
end

function M:Card()
    local day = self:Today()
    if day.played < 60 and day.xp == 0 then return nil end
    local streak = self:Streak()
    return {
        title = "Today",
        lines = {
            { "Played", ns.Duration(day.played) },
            { "XP / quests", ns.Comma(day.xp) .. " / " .. day.quests },
            { "Gold", Signed(day.gold) },
            { "Days in a row", streak > 0 and streak or "-" },
        },
        button = { "History", function() ns.Show("history") end },
    }
end
