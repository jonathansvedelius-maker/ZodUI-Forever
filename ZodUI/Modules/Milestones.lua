local ADDON, ns = ...
local T = ns.T

-- Milestones: small achievements of your own, read from what the other modules keep:
-- levels, quests handed in, dungeons, finds, gold, zones, a companion you keep running
-- with, levels without dying. Each is said once, when it is reached; the ones already
-- reached when the module first runs are marked quietly.

local M = ns:NewModule("milestones", {
    title = "Milestones",
    desc = "Small achievements of your own from what ZodUI keeps: levels, quests, dungeons, finds, gold, zones and more. Each is said once, when you reach it.",
    defaults = { enabled = true, guild = false },
    options = {
        { type = "check", key = "guild", label = "Also say a new milestone in guild chat" },
    },
})

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function Finds(q)
    local n = 0
    for _, f in ipairs(ns.chardb.finds or {}) do
        if (f.q or 0) >= q then n = n + 1 end
    end
    return n
end

local function BestAlly()
    local best = 0
    for _, a in pairs(ns.db.allies or {}) do best = math.max(best, tonumber(a.n) or 0) end
    return best
end

local function LevelsAlive()
    local level = UnitLevel and ns.Level() or 1
    local last = 1
    for _, d in ipairs(ns.chardb.deaths or {}) do
        if d.level then last = math.max(last, d.level) end
    end
    return level - last
end

-- { key, name, what, value(), goal }
M.LIST = {}
local function Add(key, name, what, value, goal)
    M.LIST[#M.LIST + 1] = { key = key, name = name, what = what, value = value, goal = goal }
end
for _, lv in ipairs({ 10, 20, 30, 40, 50, 60 }) do
    Add("level" .. lv, "Level " .. lv, "Reach level " .. lv, function() return UnitLevel and ns.Level() or 1 end, lv)
end
for _, n in ipairs({ 50, 100, 250, 500 }) do
    Add("quests" .. n, n .. " quests", "Hand in " .. n .. " quests", function() return #(ns.chardb.questsDone or {}) end, n)
end
Add("run1", "First dungeon", "Finish a dungeon", function() return #(ns.chardb.runs and ns.chardb.runs.list or {}) end, 1)
for _, n in ipairs({ 10, 25, 50 }) do
    Add("runs" .. n, n .. " dungeons", "Finish " .. n .. " dungeons", function() return #(ns.chardb.runs and ns.chardb.runs.list or {}) end, n)
end
Add("blue", "Something blue", "Find a blue item", function() return Finds(3) end, 1)
Add("purple", "Something purple", "Find a purple item", function() return Finds(4) end, 1)
Add("purple5", "Purple rain", "Find five purple items", function() return Finds(4) end, 5)
for _, g in ipairs({ 10, 100, 1000 }) do
    Add("gold" .. g, g .. " gold", "Hold " .. g .. " gold", function() return math.floor((GetMoney and GetMoney() or 0) / 10000) end, g)
end
for _, n in ipairs({ 10, 25 }) do
    Add("zones" .. n, n .. " zones", "Spend time in " .. n .. " zones", function() return Count(ns.chardb.zones) end, n)
end
Add("ally10", "Old friends", "Run ten dungeons with the same person", BestAlly, 10)
Add("alive10", "Careful", "Ten levels without dying", LevelsAlive, 10)
Add("alive20", "Very careful", "Twenty levels without dying", LevelsAlive, 20)

local function Done()
    ns.chardb.milestones = ns.chardb.milestones or {}
    return ns.chardb.milestones
end

-- Marks the ones reached; says them unless `quiet`. Returns how many were new.
function M:Check(quiet)
    local done, new = Done(), 0
    for _, m in ipairs(M.LIST) do
        if not done[m.key] then
            local ok, v = pcall(m.value)
            if ok and type(v) == "number" and v >= m.goal then
                done[m.key] = time()
                new = new + 1
                if not quiet then
                    ns.Alert("Milestone: " .. m.name .. ". " .. m.what .. ".")
                    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
                    if self.db.guild and IsInGuild and IsInGuild() and send then send("Milestone: " .. m.name .. "!", "GUILD") end
                end
            end
        end
    end
    if new > 0 then ns.Refresh() end
    return new
end

function M:OnEnable()
    local first = ns.chardb.milestones == nil
    ns.After(12, function() if self.enabled then self:Check(first) end end)
end

-- One check two seconds after a burst of events (loot, money, XP come many at a time), not one per event.
local waiting
local function Soon(self)
    if waiting then return end
    waiting = true
    ns.After(2, function()
        waiting = false
        if self.enabled then self:Check() end
    end)
end
for _, event in ipairs({ "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "PLAYER_MONEY", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_LOOT" }) do
    M:On(event, Soon)
end

function M:Card()
    local done = Done()
    local n, last, at = 0, nil, 0
    for _, m in ipairs(M.LIST) do
        if done[m.key] then
            n = n + 1
            if done[m.key] >= at then last, at = m, done[m.key] end
        end
    end
    if n == 0 then return nil end
    return { title = "Milestones", lines = { { "Reached", n .. " of " .. #M.LIST }, { "Latest", last.name } } }
end

ns.AddPage({
    key = "milestones", title = "Milestones", order = 19.7, group = "This character", module = "milestones",
    Build = function(page, f)
        page.head = T.Text(f, "GameFontNormalLarge", T.GOLD)
        page.head:SetPoint("TOPLEFT", 0, -2)
        page.list = T.Table(f, { { "Milestone", 180 }, { "What", ns.PAGE_W - 180 - 220 }, { "", 220, "RIGHT" } }, ns.PAGE_W, ns.PAGE_H - 34)
        page.list:SetPoint("TOPLEFT", 0, -34)
    end,
    Refresh = function(page)
        local done, rows, n = Done(), {}, 0
        for _, m in ipairs(M.LIST) do
            local state
            if done[m.key] then
                n = n + 1
                state = "|cff40d040" .. ns.When(done[m.key], true) .. "|r"
            else
                local ok, v = pcall(m.value)
                state = "|cff999999" .. ns.Comma(ok and type(v) == "number" and math.max(0, v) or 0) .. " / " .. ns.Comma(m.goal) .. "|r"
            end
            rows[#rows + 1] = { (done[m.key] and "" or "|cff999999") .. m.name .. (done[m.key] and "" or "|r"), m.what, state }
        end
        page.head:SetText(n .. " of " .. #M.LIST .. " milestones reached")
        page.list:SetRows(rows)
    end,
})
