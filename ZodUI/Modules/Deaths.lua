local ADDON, ns = ...
local T = ns.T

-- Deaths: when and where you died, and at what level. Before the spirit healer brings you back it says what that
-- costs and how far your corpse is. On a Hardcore realm it keeps the deaths the game announces, with a notice.

local M = ns:NewModule("deaths", {
    title = "Deaths",
    desc = "Keeps a list of your deaths: when, where and at what level. Says what the spirit healer costs and how far "
        .. "your corpse is, and on Hardcore keeps the deaths the game announces.",
    defaults = { enabled = true, healer = true, hardcore = true },
    options = {
        { type = "check", key = "healer", label = "Before the spirit healer: what it costs and how far your corpse is" },
        { type = "check", key = "hardcore", label = "Hardcore: a notice when someone dies (only on Hardcore)" },
    },
})

local KEEP = 200
local HC_KEEP = 100

local function List()
    ns.chardb.deaths = ns.chardb.deaths or {}
    return ns.chardb.deaths
end

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Yards from you to your corpse, when both are on the map you stand on.
function M.CorpseYards()
    if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and C_Map and C_Map.GetMapWorldSize) then return nil end
    local x, y, map = ns.Coords()
    if not x then return nil end
    local pos = C_DeathInfo.GetCorpseMapPosition(map)
    if not pos or not pos.GetXY then return nil end
    local cx, cy = pos:GetXY()
    cx, cy = Plain(cx), Plain(cy)
    if type(cx) ~= "number" or type(cy) ~= "number" or (cx == 0 and cy == 0) then return nil end
    local w, h = C_Map.GetMapWorldSize(map)
    w, h = Plain(w), Plain(h)
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
    local dx, dy = (cx - x / 100) * w, (cy - y / 100) * h
    return math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
end

-- The spirit healer's question: what it costs, and whether walking back is quicker.
M:On("CONFIRM_XP_LOSS", function(self)
    if not self.db.healer then return end
    local level = ns.Level() or 0
    local cost = level > 10 and "resurrection sickness (less health, mana and stats for up to 10 minutes) and 25% durability on your gear"
        or "25% durability on your gear (no sickness up to level 10)"
    local yards = M.CorpseYards()
    ns.Alert("The spirit healer costs " .. cost .. "."
        .. (yards and (" Your corpse is " .. yards .. " yards away" .. (yards <= 200 and ": walking back is free." or ".")) or ""))
end)

-- Hardcore: the game names everyone who dies; kept for all characters.
local function HardcoreList()
    ns.db.hardcoreDeaths = ns.db.hardcoreDeaths or {}
    return ns.db.hardcoreDeaths
end

M:On("HARDCORE_DEATHS", function(self, _, name)
    if not (C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive()) then return end
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return end
    name = name:gsub("[%c|]", ""):sub(1, 48)
    local list = HardcoreList()
    table.insert(list, 1, { name = name, at = time() })
    while #list > HC_KEEP do table.remove(list) end
    if self.db.hardcore then ns.Alert("Hardcore: " .. name .. " has died.") end
    ns.Refresh()
end)

local function HardcoreToday()
    local n, from = 0, ns.Today()
    for _, d in ipairs(ns.db.hardcoreDeaths or {}) do
        if date("%Y-%m-%d", d.at) == from then n = n + 1 end
    end
    return n
end
M.HardcoreToday = HardcoreToday

M:On("PLAYER_DEAD", function()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local list = List()
    table.insert(list, 1, { at = time(), level = ns.Level(), zone = zone, sub = sub ~= zone and sub or nil })
    while #list > KEEP do table.remove(list) end
    ns.Refresh()
end)

-- /zod deaths hardcore: the last deaths the game announced.
function M:Slash(arg)
    if (arg or ""):lower() ~= "hardcore" then
        ns.Print("use /zod deaths to open the page, or /zod deaths hardcore.")
        return
    end
    local list = HardcoreList()
    if #list == 0 then ns.Print("no Hardcore deaths kept. They are only announced on Hardcore realms.") return end
    ns.Print("the last Hardcore deaths:")
    for i = 1, math.min(#list, 15) do print("  |cff999999" .. ns.When(list[i].at) .. "|r  " .. list[i].name) end
end

local function Where(d)
    return (d.sub and d.sub ~= "") and (d.sub .. ", " .. d.zone) or d.zone
end

function M:Card()
    local list = List()
    if #list == 0 then return nil end
    local today, from = 0, ns.Today()
    for _, d in ipairs(list) do
        if date("%Y-%m-%d", d.at) == from then today = today + 1 end
    end
    local lines = {
        { "Today", today },
        { "In all", #list },
        { "Last", Where(list[1]) },
    }
    local hc = HardcoreToday()
    if hc > 0 then lines[4] = { "Hardcore today", hc .. (hc == 1 and " death" or " deaths") } end
    return { title = "Deaths", lines = lines, button = { "All", function() ns.Show("deaths") end } }
end

ns.AddPage({
    key = "deaths", title = "Deaths", order = 16, group = "This character", module = "deaths",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Deaths module is off. Switch it on under Settings.")
        page.sum = T.Text(f, "GameFontHighlightSmall", T.DIM)
        page.sum:SetPoint("TOPLEFT", 0, -4)
        page.list = T.Table(f, { { "When", 160 }, { "Level", 60, "RIGHT" }, { "Where", w - 240 } }, w, ns.PAGE_H - 26)
        page.list:SetPoint("TOPLEFT", 0, -26)
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.sum:SetShown(on)
        page.list:SetShown(on)
        if not on then return end
        local list, rows, zones = List(), {}, {}
        for _, d in ipairs(list) do
            rows[#rows + 1] = { ns.WhenCell(d.at), d.level or "?", Where(d) }
            zones[d.zone] = (zones[d.zone] or 0) + 1
        end
        local worst, most
        for zone, n in pairs(zones) do
            if not most or n > most then worst, most = zone, n end
        end
        page.sum:SetText(#list == 0 and "No deaths yet. Long may it last."
            or (#list .. (#list == 1 and " death" or " deaths") .. (worst and (", most in " .. worst .. " (" .. most .. ")") or "") .. ".")
            .. (#HardcoreList() > 0 and ("  Hardcore: " .. HardcoreToday() .. " today, last " .. HardcoreList()[1].name .. " (/zod deaths hardcore).") or ""))
        page.list:SetRows(rows, "Deaths from now on are listed here.")
    end,
})
