local ADDON, ns = ...

-- Skill-ups: how many points each skill gained today, on a Home card.

local M = ns:NewModule("skills", {
    title = "Skill-ups",
    desc = "Counts the points your professions and weapon skills gain each day and shows today's on Home.",
    defaults = { enabled = true },
})

local pattern

-- "Your skill in %s has increased to %d." as a pattern capturing both.
local function Pattern()
    local format = _G.SKILL_RANK_UP
    if type(format) ~= "string" then return "^Your skill in (.+) has increased to (%d+)%.$" end
    local p = format:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    return "^" .. p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)") .. "$"
end

local function Day()
    local day = ns.chardb.skillDay
    if not day or day.day ~= ns.Today() then
        day = { day = ns.Today(), by = {} }
        ns.chardb.skillDay = day
    end
    return day
end

function M:OnEnable()
    pattern = pattern or Pattern()
end

M:On("CHAT_MSG_SKILL", function(_, _, msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    local name, rank = msg:match(pattern)
    if not name then return end
    local entry = Day().by[name] or { gained = 0 }
    Day().by[name] = entry
    entry.gained, entry.rank = entry.gained + 1, tonumber(rank)
    ns.Refresh()
end)

function M:Card()
    local list = {}
    for name, e in pairs(Day().by) do list[#list + 1] = { name, e } end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a[2].gained > b[2].gained end)
    local lines = {}
    for i = 1, math.min(4, #list) do
        lines[i] = { list[i][1], "+" .. list[i][2].gained .. "  |cff999999" .. (list[i][2].rank or "") .. "|r" }
    end
    return { title = "Skill-ups today", lines = lines }
end
