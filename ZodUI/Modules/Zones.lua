local ADDON, ns = ...
local T = ns.T

-- Zones: how long you spent in each zone, when you first came there and at
-- what level, and how many levels you gained there.

local M = ns:NewModule("zones", {
    title = "Zones",
    desc = "Times how long you spend in each zone, remembers when you first came there and at what level, and counts the levels you gained there.",
    defaults = { enabled = true, first = true },
    options = {
        { type = "check", key = "first", label = "Say in chat when you enter a zone for the first time" },
    },
})

local TICK = 10
local current

local function Data()
    ns.chardb.zones = ns.chardb.zones or {}
    return ns.chardb.zones
end

local function Zone()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    return zone ~= "" and zone or nil
end

local function Enter()
    local zone = Zone()
    if not zone then return end
    local data = Data()
    if not data[zone] then
        data[zone] = { time = 0, first = time(), level = ns.Level(), levels = 0 }
        if M.db.first and current then ns.Print("first time in " .. zone .. ".") end -- not at login
    end
    current = zone
end

function M:OnEnable()
    current = nil
    Enter()
    current = Zone()
end

M:On("ZONE_CHANGED_NEW_AREA", Enter)
M:On("PLAYER_ENTERING_WORLD", Enter)

M:On("PLAYER_LEVEL_UP", function()
    local entry = current and Data()[current]
    if entry then entry.levels = entry.levels + 1 end
end)

ns.Every(TICK, function()
    local entry = current and Data()[current]
    if entry then entry.time = entry.time + TICK end
end, M)

function M:Find(part, add, has)
    for zone, e in pairs(Data()) do
        if has(zone) then add("Zone", zone, ns.Duration(e.time) .. " spent there", "zones") end
    end
end

ns.AddPage({
    key = "zones", title = "Zones", order = 18, group = "This character", module = "zones",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Zones module is off. Switch it on under Settings.")
        page.sum = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.sum:SetPoint("TOPLEFT", 0, -4)
        page.list = T.Table(f, { { "Zone", w - 420 }, { "Time there", 110, "RIGHT" }, { "Levels gained", 100, "RIGHT" },
            { "First came", 110, "RIGHT" }, { "At level", 80, "RIGHT" } }, w, ns.PAGE_H - 26)
        page.list:SetPoint("TOPLEFT", 0, -26)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.sum:SetShown(on)
        page.list:SetShown(on)
        if not on then return end
        local rows, total = {}, 0
        for zone, e in pairs(Data()) do
            total = total + e.time
            rows[#rows + 1] = { zone == current and T.Paint(zone, T.GREEN) or zone, { ns.Duration(e.time), e.time }, e.levels > 0 and ("+" .. e.levels) or "-",
                ns.WhenCell(e.first, true), e.level or "?", t = e.time, name = zone }
        end
        table.sort(rows, function(a, b)
            if a.t ~= b.t then return a.t > b.t end
            return a.name < b.name
        end)
        page.sum:SetText(#rows .. (#rows == 1 and " zone, " or " zones, ") .. ns.Duration(total) .. " timed. Green is where you are.")
        page.list:SetRows(rows, "Zones are timed from now on.")
    end,
})
