local ADDON, ns = ...
local T = ns.T

-- Quest log: every quest you hand in, with when, where, at what level, and
-- the XP and gold it gave.

local M = ns:NewModule("questlog", {
    title = "Quests done",
    desc = "Keeps a list of the quests you hand in: when, where, at what level, and the XP and gold each gave.",
    defaults = { enabled = true },
})

local KEEP = 500

local function List()
    ns.chardb.questsDone = ns.chardb.questsDone or {}
    return ns.chardb.questsDone
end

local function Title(id)
    local get = C_QuestLog and C_QuestLog.GetTitleForQuestID
    local title = get and id and get(id)
    return (type(title) == "string" and title ~= "") and title or ("Quest " .. tostring(id or "?"))
end

M:On("QUEST_TURNED_IN", function(_, _, id, xp, money)
    local list = List()
    table.insert(list, 1, { at = time(), id = id, name = Title(id), xp = tonumber(xp) or 0, money = tonumber(money) or 0,
        level = ns.Level(), zone = GetRealZoneText and GetRealZoneText() or "" })
    while #list > KEEP do table.remove(list) end
    ns.Refresh()
end)

local function Today()
    local n, xp, from = 0, 0, ns.Today()
    for _, q in ipairs(List()) do
        if date("%Y-%m-%d", q.at) ~= from then break end
        n, xp = n + 1, xp + q.xp
    end
    return n, xp
end

function M:Card()
    local list = List()
    if #list == 0 then return nil end
    local n, xp = Today()
    return {
        title = "Quests done",
        lines = {
            { "Today", n .. (xp > 0 and ("  |cff999999" .. ns.Comma(xp) .. " XP|r") or "") },
            { "In all", #list },
            { "Last", list[1].name },
        },
        button = { "All", function() ns.Show("questlog") end },
    }
end

function M:Find(part, add, has)
    for _, q in ipairs(List()) do
        if has(q.name) then add("Quest", q.name, "done " .. ns.When(q.at, true), "questlog") end
    end
end

ns.AddPage({
    key = "questlog", title = "Quests done", order = 13, group = "This character", module = "questlog",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Quests done module is off. Switch it on under Settings.")
        page.sum = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.sum:SetPoint("TOPLEFT", 0, -4)
        page.list = T.Table(f, { { "Quest", w - 480 }, { "When", 110 }, { "Lvl", 40, "RIGHT" }, { "XP", 80, "RIGHT" },
            { "Gold", 90, "RIGHT" }, { "Where", 140 } }, w, ns.PAGE_H - 26)
        page.list:SetPoint("TOPLEFT", 0, -26)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.sum:SetShown(on)
        page.list:SetShown(on)
        if not on then return end
        local rows, xp = {}, 0
        for _, q in ipairs(List()) do
            xp = xp + q.xp
            rows[#rows + 1] = { q.name, ns.WhenCell(q.at), q.level or "?", q.xp > 0 and ns.Comma(q.xp) or "-",
                q.money > 0 and ns.Money(q.money, true) or "-", q.zone or "" }
        end
        local n, today = Today()
        page.sum:SetText(#rows .. (#rows == 1 and " quest, " or " quests, ") .. ns.Comma(xp) .. " XP in all. Today: " .. n
            .. (today > 0 and (", " .. ns.Comma(today) .. " XP") or "") .. ".")
        page.list:SetRows(rows, "Quests you hand in from now on are listed here.")
    end,
})
