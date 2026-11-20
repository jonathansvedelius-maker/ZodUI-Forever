local ADDON, ns = ...
local T = ns.T

-- Kills: every creature that gave you XP, counted by name, and today's kills.

local M = ns:NewModule("kills", {
    title = "Kills",
    desc = "Counts the creatures that gave you XP, by name, with how many today and in all.",
    defaults = { enabled = true },
})

local pattern

-- "%s dies, you gain %d experience." as a pattern that captures the name.
local function Pattern()
    local format = _G.COMBATLOG_XPGAIN_FIRSTPERSON
    if type(format) ~= "string" then return "^(.+) dies, you gain" end
    local p = format:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    return "^" .. p:gsub("\1", "(.+)"):gsub("\2", "%%d+")
end

local function Data()
    local data = ns.chardb.kills
    if not data then
        data = { by = {}, day = ns.Today(), today = 0, total = 0 }
        ns.chardb.kills = data
    end
    if data.day ~= ns.Today() then data.day, data.today = ns.Today(), 0 end
    return data
end

function M:OnEnable()
    pattern = pattern or Pattern()
end

M:On("CHAT_MSG_COMBAT_XP_GAIN", function(_, _, msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    local name = msg:match(pattern)
    if not name then return end
    local data = Data()
    local entry = data.by[name] or { n = 0 }
    data.by[name] = entry
    entry.n, entry.last = entry.n + 1, time()
    if entry.day ~= data.day then entry.day, entry.today = data.day, 0 end
    entry.today = entry.today + 1
    data.today, data.total = data.today + 1, data.total + 1
    ns.Refresh()
end)

function M:Card()
    local data = Data()
    if data.total == 0 then return nil end
    local most, top
    for name, e in pairs(data.by) do
        if e.day == data.day and (not most or e.today > most) then most, top = e.today, name end
    end
    return {
        title = "Kills",
        lines = {
            { "Today", ns.Comma(data.today) },
            { "Most today", top and (top .. "  |cff999999" .. most .. "|r") or "-" },
            { "In all", ns.Comma(data.total) },
        },
        button = { "All", function() ns.Show("kills") end },
    }
end

function M:Find(part, add, has)
    for name, e in pairs(Data().by) do
        if has(name) then add("Kills", name, ns.Comma(e.n) .. " killed", "kills") end
    end
end

ns.AddPage({
    key = "kills", title = "Kills", order = 14, group = "This character", module = "kills",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Kills module is off. Switch it on under Settings.")
        page.sum = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.sum:SetPoint("TOPLEFT", 0, -4)
        page.list = T.Table(f, { { "Creature", w - 330 }, { "Today", 80, "RIGHT" }, { "In all", 90, "RIGHT" }, { "Last", 140, "RIGHT" } },
            w, ns.PAGE_H - 26)
        page.list:SetPoint("TOPLEFT", 0, -26)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.sum:SetShown(on)
        page.list:SetShown(on)
        if not on then return end
        local data = Data()
        local rows = {}
        for name, e in pairs(data.by) do
            rows[#rows + 1] = { name, e.day == data.day and e.today or "-", ns.Comma(e.n), ns.WhenCell(e.last), n = e.n }
        end
        table.sort(rows, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a[1] < b[1]
        end)
        page.sum:SetText(ns.Comma(data.today) .. " today, " .. ns.Comma(data.total) .. " in all, " .. #rows .. " kinds of creature.")
        page.list:SetRows(rows, "Creatures that give you XP from now on are counted here.")
    end,
})
