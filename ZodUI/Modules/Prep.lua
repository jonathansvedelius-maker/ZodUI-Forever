local ADDON, ns = ...

-- Dungeon prep: walking into a dungeon (or /zod prep) lists your quests for it, and, with
-- others in your group who run ZodUI, which of those they have too and which of theirs you
-- lack, so quests can be shared before the first pull. /zod prep share offers yours to the
-- group. A quest belongs to a dungeon when your quest log files it under the dungeon's name.

local M = ns:NewModule("prep", {
    title = "Dungeon prep",
    desc = "Entering a dungeon lists your quests for it, and with others in your group who run ZodUI, which they have too and which of theirs you lack. /zod prep share offers yours to the group.",
    defaults = { enabled = true, auto = true },
    options = {
        { type = "check", key = "auto", label = "Show it when I enter a dungeon" },
        { type = "note", text = "Telling your group your quests needs the Guild network module on; only quest numbers travel.", lines = 1 },
    },
})

local Bus = ns.Bus
local MOST = 12
local WAIT = 3
local theirs = {} -- short name -> { dungeon = key, ids = { [id] = true } }
local lastShown

local function Num(s)
    local n = s ~= nil and tonumber(s) or nil
    if not n or n ~= n or n < 1 or n > 10000000 then return nil end
    return math.floor(n)
end

-- The dungeon you are in, or the one named: an entry of ns.Ads.DUNGEONS.
function M.Dungeon(name)
    if not name and GetInstanceInfo then
        local iname, kind = GetInstanceInfo()
        if kind == "party" or kind == "raid" then name = iname end
    end
    if type(name) ~= "string" then return nil end
    local lower = name:lower()
    for _, d in ipairs(ns.Ads.DUNGEONS) do
        if d.name:lower() == lower or d.name:lower():gsub("^the ", "") == lower:gsub("^the ", "") then return d end
        for _, w in ipairs(d.words) do
            if w == lower then return d end
        end
    end
    -- Scarlet Monastery's wings are their own instances.
    if lower:find("scarlet", 1, true) then return M.Dungeon("Scarlet Monastery") end
    return nil
end

-- Your quests filed under the dungeon in your log: list of { id, title, done }.
function M.Mine(d)
    local out = {}
    local log = C_QuestLog
    if not (d and log and log.GetNumQuestLogEntries and log.GetInfo) then return out end
    local under = false
    for i = 1, log.GetNumQuestLogEntries() or 0 do
        local info = log.GetInfo(i)
        if info then
            if info.isHeader then
                local title = (info.title or ""):lower()
                under = title == d.name:lower() or title == d.name:lower():gsub("^the ", "")
                    or (d.key == "sm" and title:find("scarlet", 1, true) ~= nil)
            elseif under and info.questID then
                out[#out + 1] = { id = info.questID, title = info.title or ("Quest " .. info.questID),
                    done = log.IsComplete and log.IsComplete(info.questID) or false }
            end
        end
    end
    return out
end

local function Tell(d, mine)
    if not (Bus and Bus.Send and Bus.PartyOn and Bus.PartyOn()) then return end
    local fields = { d.key }
    for i = 1, math.min(#mine, MOST) do fields[#fields + 1] = mine[i].id end
    Bus.Send("D", fields, "PARTY")
end

-- The lines to say: your quests, who shares them, and what others have that you lack.
function M:Lines(d)
    local mine = M.Mine(d)
    local have, lines = {}, {}
    for _, q in ipairs(mine) do have[q.id] = q end
    if #mine == 0 then
        lines[#lines + 1] = "You have no quests for " .. d.name .. " in your log."
    else
        local names = {}
        for _, q in ipairs(mine) do
            local with = {}
            for who, t in pairs(theirs) do
                if t.dungeon == d.key and t.ids[q.id] then with[#with + 1] = who end
            end
            table.sort(with)
            names[#names + 1] = q.title .. (q.done and " (done)" or "") .. (#with > 0 and (" |cff999999with " .. table.concat(with, ", ") .. "|r") or "")
        end
        lines[#lines + 1] = "Your quests for " .. d.name .. ": " .. table.concat(names, "; ") .. "."
    end
    local lack = {}
    for who, t in pairs(theirs) do
        if t.dungeon == d.key then
            local n = 0
            for id in pairs(t.ids) do
                if not have[id] then n = n + 1 end
            end
            if n > 0 then lack[#lack + 1] = who .. " has " .. n .. (n == 1 and " quest" or " quests") .. " you lack" end
        end
    end
    table.sort(lack)
    if #lack > 0 then lines[#lines + 1] = table.concat(lack, "; ") .. ": ask them to share." end
    return lines, mine
end

function M:Show(d)
    d = d or M.Dungeon()
    if not d then
        ns.Print("you are not in a dungeon. /zod prep <dungeon> looks at one, for example /zod prep sfk.")
        return
    end
    local lines, mine = self:Lines(d)
    for i, line in ipairs(lines) do
        if i == 1 then ns.Print(line) else print("  " .. line) end
    end
    return lines, mine
end

function M:Share(d)
    d = d or M.Dungeon()
    if not d then ns.Print("you are not in a dungeon.") return 0 end
    local n = 0
    for _, q in ipairs(M.Mine(d)) do
        local log = C_QuestLog
        local pushable = log and log.IsPushableQuest and log.IsPushableQuest(q.id)
        if pushable and log.SetSelectedQuest and QuestLogPushQuest and IsInGroup and IsInGroup() then
            log.SetSelectedQuest(q.id)
            QuestLogPushQuest()
            n = n + 1
        end
    end
    ns.Print(n > 0 and ("offered " .. n .. (n == 1 and " quest" or " quests") .. " to your group.") or "no quest of yours here can be shared.")
    return n
end

local function Entered(self)
    if not self.db.auto then return end
    local d = M.Dungeon()
    if not d or lastShown == d.key then return end
    lastShown = d.key
    Tell(d, M.Mine(d))
    ns.After(WAIT, function() if self.enabled then self:Show(d) end end)
end

M:On("PLAYER_ENTERING_WORLD", Entered)
M:On("ZONE_CHANGED_NEW_AREA", function(self)
    if not M.Dungeon() then lastShown = nil end
    Entered(self)
end)

if Bus then
    Bus.Listen("D", function(name, f, channel, full)
        if channel ~= "PARTY" and channel ~= "RAID" then return end
        local d
        for _, x in ipairs(ns.Ads.DUNGEONS) do
            if x.key == f[1] then d = x end
        end
        if not d then return end
        local ids = {}
        for i = 2, math.min(#f, MOST + 1) do
            local id = Num(f[i])
            if id then ids[id] = true end
        end
        local known = theirs[name]
        theirs[name] = { dungeon = d.key, ids = ids }
        -- Someone new: tell them yours, once.
        if not known and M.Dungeon() == d then Tell(d, M.Mine(d)) end
    end, M)
end

M:On("GROUP_ROSTER_UPDATE", function()
    if not (IsInGroup and IsInGroup()) then theirs = {} end
end)

function M.Forget() theirs, lastShown = {}, nil end

function M:Slash(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = word:lower()
    if word == "share" then
        self:Share(rest ~= "" and M.Dungeon(rest) or nil)
        return
    end
    local named = (word ~= "" and M.Dungeon(((word .. " " .. rest):gsub("%s+$", "")))) or nil
    if word ~= "" and not named then ns.Print("no dungeon called '" .. word .. "'. Try sfk, bfd, wc or a full name.") return end
    if named and Bus and Bus.PartyOn and Bus.PartyOn() then Tell(named, M.Mine(named)) end
    self:Show(named)
end
