local ADDON, ns = ...

-- Loot rules: agree how a group rolls before the first boss, and see who breaks it.
--   * /zod rules says the rules in your group's chat: Need only on what you will wear now,
--     and for Bind on Equip items the rule you pick here (everyone Greed, by default).
--   * While the rules stand, a Need on a Bind on Equip item against them is told to you
--     (from Loot rolls' picks) and kept.
--   * Grouping again with someone who broke them before tells you when that was.
-- Players ask for this on the WoW Forever forums: Need on BoE epics is the loot argument there.

local M = ns:NewModule("lootrules", {
    title = "Loot rules",
    desc = "/zod rules says your group's loot rules in its chat; a Need on a Bind on Equip item against them is told to you and kept, and grouping with that player again reminds you.",
    defaults = { enabled = true, boe = "greed", remind = true },
    options = {
        { type = "cycle", key = "boe", label = "Bind on Equip items", choices = { { "greed", "Everyone Greed" },
            { "wear", "Need only to wear it now" } } },
        { type = "check", key = "remind", label = "Remind me when I group with someone who broke them before" },
    },
})

local KEEP = 100
local agreed -- the rule said to this group, until it breaks up
local seen = {}

local function Log()
    ns.db.lootBreaks = ns.db.lootBreaks or {}
    return ns.db.lootBreaks
end

local function Short(name)
    return type(name) == "string" and (name:match("^[^%-]+") or name) or "?"
end

function M:Text()
    local boe = self.db.boe == "greed" and "Bind on Equip items: Greed for everyone, no Need."
        or "Bind on Equip items: Need only if you will wear it now."
    return "Loot rules: Need only on what you will wear now. " .. boe .. " Thanks!"
end

function M:Say()
    if not (IsInGroup and IsInGroup()) then ns.Print("you are not in a group. The rules would be: " .. self:Text()) return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    send(self:Text(), (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
    agreed = self.db.boe
    return true
end

local function BoE(link)
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not get then return false end
    local bind = select(14, get(link))
    return bind == 2
end

-- A pick seen by Loot rolls.
function M:Pick(link, name, choice, mine)
    local rolls = ns.modules.rolls
    if mine or not agreed or not rolls or choice ~= rolls.NEED or agreed ~= "greed" then return end
    if not BoE(link) then return end
    local log = Log()
    table.insert(log, 1, { at = time(), name = Short(name), link = link })
    while #log > KEEP do table.remove(log) end
    ns.Alert(Short(name) .. " rolled Need on " .. link .. ", a Bind on Equip item, against the rules.")
end

local function Watch()
    local rolls = ns.modules.rolls
    if rolls and rolls.watchers and not M.watching then
        M.watching = true
        table.insert(rolls.watchers, function(...) if M.enabled then M:Pick(...) end end)
    end
end
function M:OnEnable() Watch() end

-- Who in the group broke the rules before: name -> the last time.
function M:Known()
    local out = {}
    if not (IsInGroup and IsInGroup()) or not GetNumGroupMembers then return out end
    local unit = (IsInRaid and IsInRaid()) and "raid" or "party"
    local last = {}
    for _, e in ipairs(Log()) do last[e.name] = last[e.name] or e end
    for i = 1, GetNumGroupMembers() do
        local name = UnitName and UnitName(unit .. i)
        if type(name) == "string" and not (issecretvalue and issecretvalue(name)) and last[name] then out[name] = last[name] end
    end
    return out
end

M:On("GROUP_ROSTER_UPDATE", function(self)
    if not (IsInGroup and IsInGroup()) then
        agreed, seen = nil, {}
        return
    end
    if not self.db.remind then return end
    for name, e in pairs(self:Known()) do
        if not seen[name] then
            seen[name] = true
            ns.Alert(name .. " rolled Need on " .. e.link .. " against the rules, " .. ns.When(e.at, true) .. ".")
        end
    end
end)

function M.Forget() agreed, seen = nil, {} end

function M:Slash(arg)
    local word = (arg or ""):lower():match("^%s*(%S*)")
    if word == "log" then
        local log = Log()
        if #log == 0 then ns.Print("no one broke the loot rules yet.") return end
        ns.Print("Need on Bind on Equip against the rules:")
        for i = 1, math.min(10, #log) do print("  " .. ns.When(log[i].at) .. "  " .. log[i].name .. "  " .. log[i].link) end
        return
    end
    self:Say()
end

-- /zod rules, shorter than /zod lootrules.
ns.pluginCommands = ns.pluginCommands or {}
ns.pluginCommands.rules = function(rest)
    if M.enabled then M:Slash(rest) else ns.Print("Loot rules is off. /zod lootrules on switches it on.") end
end
