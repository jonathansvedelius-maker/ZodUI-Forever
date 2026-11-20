local ADDON, ns = ...

-- Guild leaderboard: this week's numbers of everyone in your guild who runs ZodUI, side by
-- side: levels, quests, dungeons and purple finds. /zod top asks the guild over the guild
-- network (Core\Bus.lua) and lists what comes back a few seconds later. Each answers with
-- Recap's numbers for this week; nothing is sent unasked.

local M = ns:NewModule("leaderboard", {
    title = "Guild leaderboard",
    desc = "This week's levels, quests, dungeons and purple finds of everyone in your guild who runs ZodUI, side by side. /zod top asks. Needs the Guild network and Recap modules.",
    defaults = { enabled = true, answer = true },
    options = {
        { type = "check", key = "answer", label = "Tell my week when someone in the guild asks" },
    },
})

local Bus = ns.Bus
local WAIT = 4
local GAP = 60
local MOST = 40
local asked, answers, askedAt = nil, nil, nil

local function Num(s, lo, hi)
    local n = s ~= nil and tonumber(s) or nil
    if not n or n ~= n or n < lo or n > hi then return nil end
    return math.floor(n)
end

-- This week, as the fields that travel: level, levels, quests, runs, purple finds, played seconds.
function M:Mine()
    local recap = ns.modules.recap
    if not (recap and recap.Stats and recap.WeekStart) then return nil end
    local monday = recap.WeekStart()
    local s = recap:Stats(monday, monday + 7 * 86400)
    local purple = 0
    for _, f in ipairs(ns.chardb.finds or {}) do
        if type(f.at) == "number" and f.at >= monday and (f.q or 0) >= 4 then purple = purple + 1 end
    end
    return { level = UnitLevel and ns.Level() or 1, levels = s.levels, quests = s.quests, runs = s.runs, purple = purple,
        played = math.floor(s.played) }
end

local CATS = {
    { "levels", "Levels" }, { "quests", "Quests" }, { "runs", "Dungeons" }, { "purple", "Purple finds" },
}

function M:Lines(list)
    local out = {}
    for _, cat in ipairs(CATS) do
        table.sort(list, function(a, b)
            if a[cat[1]] ~= b[cat[1]] then return a[cat[1]] > b[cat[1]] end
            return a.name < b.name
        end)
        local parts = {}
        for i = 1, math.min(3, #list) do
            if list[i][cat[1]] > 0 then parts[#parts + 1] = i .. ". " .. list[i].name .. " " .. list[i][cat[1]] end
        end
        if #parts > 0 then out[#out + 1] = cat[2] .. ": " .. table.concat(parts, "  ") end
    end
    return out
end

function M:Finish()
    local list = answers or {}
    asked, answers = nil, nil
    local mine = self:Mine()
    if mine then
        mine.name = UnitName and ns.MyName() or "you"
        list[#list + 1] = mine
    end
    local lines = self:Lines(list)
    if #lines == 0 then
        ns.Print("no numbers this week yet from you or your guild.")
        return lines
    end
    ns.Print("this week in your guild (" .. #list .. (#list == 1 and " player" or " players") .. " with ZodUI):")
    for _, line in ipairs(lines) do print("  " .. line) end
    return lines
end

function M:Ask()
    if not (Bus and Bus.On and Bus.On()) then
        ns.Print("the Guild network module is off, or you are not in a guild.")
        return false
    end
    if askedAt and GetTime() - askedAt < GAP then
        ns.Print("asked a moment ago; ask again in a minute.")
        return false
    end
    askedAt = GetTime()
    asked, answers = tostring(math.random(100000, 999999)), {}
    Bus.Send("W", { asked })
    ns.Print("asking your guild for this week's numbers...")
    ns.After(WAIT, function() self:Finish() end)
    return true
end

if Bus then
    Bus.Listen("W", function(name, f, channel, full)
        if channel ~= "GUILD" or not (M.enabled and M.db.answer) then return end
        if not (f[1] or ""):match("^%d+$") then return end
        local mine = M:Mine()
        if not mine then return end
        Bus.Send("w", { f[1], mine.level, mine.levels, mine.quests, mine.runs, mine.purple, mine.played }, full)
    end)

    Bus.Listen("w", function(name, f, channel)
        if channel ~= "WHISPER" or not asked or f[1] ~= asked or #answers >= MOST then return end
        for _, a in ipairs(answers) do
            if a.name == name then return end
        end
        local level, levels, quests = Num(f[2], 1, 100), Num(f[3], 0, 60), Num(f[4], 0, 5000)
        local runs, purple, played = Num(f[5], 0, 1000), Num(f[6], 0, 1000), Num(f[7], 0, 7 * 86400)
        if not (level and levels and quests and runs and purple and played) then return end
        answers[#answers + 1] = { name = tostring(name):gsub("%-.*$", ""), level = level, levels = levels, quests = quests,
            runs = runs, purple = purple, played = played }
    end)
end

function M:Slash()
    self:Ask()
end

-- /zod top, shorter than /zod leaderboard.
ns.pluginCommands = ns.pluginCommands or {}
ns.pluginCommands.top = function() if M.enabled then M:Ask() else ns.Print("Guild leaderboard is off. /zod leaderboard on switches it on.") end end
