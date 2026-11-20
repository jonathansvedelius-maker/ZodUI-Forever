local ADDON, ns = ...

-- Loot shout: says your fine loot in guild chat, with its link. Purple and better by default; a blue or
-- green item that is an upgrade for you too: Forever Leveling BiS says so when it is installed (its public
-- ForeverLevelingBiS_API, GetGain), else ZodUI weighs it against what you wear (CoreWeights.lua).
-- Quest rewards count; made items never do.
-- It is careful with the guild's chat: at most one line every GAP seconds and HOUR_MOST an hour, the same item
-- once in a while, nothing in combat or the chat lockdown (it waits, up to WAIT_MOST), and nothing outside a guild.

local M = ns:NewModule("shout", {
    title = "Loot shout",
    desc = "Says your fine loot in guild chat: purple and better, and blue or green items that are an upgrade for "
        .. "you. At most one line a minute.",
    needs = { "ForeverLevelingBiS", "NaowhForever_BiS" },
    defaults = { enabled = true, quality = 4, upgrades = false, quests = true }, -- upgrades: many lines in guild chat, so yours to switch on
    options = {
        { type = "cycle", key = "quality", label = "Say in guild chat", choices = { { 0, "Never" }, { 3, "Blue and better" },
            { 4, "Purple and better" }, { 5, "Orange only" } } },
        { type = "check", key = "upgrades", label = "Also a green or blue item that is an upgrade for you" },
        { type = "check", key = "quests", label = "Quest rewards count too" },
        { type = "note", text = "/zod shout test shows in your own chat what would be said, without saying it.", lines = 2 },
    },
})

local GAP = 60          -- seconds between two lines
local HOUR_MOST = 6     -- lines an hour
local SAME_ITEM = 1800  -- the same item is said again only after this
local SETTLE = 1.5      -- seconds to let the game load the item before asking whether it is an upgrade
local WAIT_MOST = 300   -- a line held back by combat is dropped after this

local LINES = {
    "Look what just dropped for me: %s!",
    "%s is mine!",
    "Got %s!",
}

local sent = {}         -- times of the lines said, the last hour
local said = {}         -- item id -> when it was said
local waiting           -- { text, at } held back by combat or the lockdown

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- What you wear now, as Hand-me-downs weighs a character: class, level and gear by slot.
local function Me()
    local _, class = UnitClass("player")
    local gear = {}
    for slot = 1, 18 do gear[slot] = GetInventoryItemLink and GetInventoryItemLink("player", slot) or nil end
    return { class = class, level = Plain(UnitLevel("player")) or 1, gear = gear, mine = true }
end

-- Whether the item is an upgrade for you: Forever Leveling BiS's word when it is installed, else the stat weights
-- (NaowhForever's or ZodUI's own) against what you wear in that slot.
function M.Upgrade(link)
    local api = ForeverLevelingBiS_API
    if type(api) == "table" then
        if api.GetGain then
            local ok, gain = pcall(api.GetGain, link)
            if ok and type(gain) == "number" then return gain > 0 end
        end
        if api.IsUpgrade then
            local ok, yes = pcall(api.IsUpgrade, link)
            if ok and type(yes) == "boolean" then return yes end
        end
    end
    local H = ns.modules.handouts
    if not (H and H.GainAt and UnitClass) then return false end
    local ok, pct = pcall(H.GainAt, Me(), link, 1)
    return ok and pct ~= nil
end

-- The line to say for an item, or nil when it is not worth saying.
function M:Line(link, id, quality, kind)
    local least = self.db.quality or 4
    if least <= 0 or not quality or kind == "created" or (kind == "pushed" and not self.db.quests) then return nil end
    local upgrade = quality >= 2 and self.db.upgrades and self.Upgrade(link)
    if quality < least and not (upgrade and quality >= 2) then return nil end
    local text = string.format(LINES[id % #LINES + 1], link)
    if upgrade then text = text .. " An upgrade for me, too." end
    return text
end

local function Held()
    if InCombatLockdown and InCombatLockdown() then return true end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and Plain(C_ChatInfo.InChatMessagingLockdown()) then return true end
    return false
end

-- Whether a line may go out now, by the limits.
local function Allowed()
    local now = time()
    for i = #sent, 1, -1 do
        if now - sent[i] >= 3600 then table.remove(sent, i) end
    end
    if #sent >= HOUR_MOST then return false end
    return not sent[#sent] or now - sent[#sent] >= GAP
end

local function Say(text)
    if not (IsInGuild and IsInGuild()) then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    if Held() then
        waiting = { text = text, at = time() }
        return false
    end
    if not Allowed() then return false end
    send(text, "GUILD")
    sent[#sent + 1] = time()
    return true
end

function M:Looted(link, id, quality, kind)
    local last = said[id]
    if last and time() - last < SAME_ITEM then return end
    ns.After(SETTLE, function()
        if not self.enabled then return end
        local text = self:Line(link, id, quality, kind)
        if not text then return end
        said[id] = time()
        Say(text)
    end)
end

M:On("CHAT_MSG_LOOT", function(self, _, msg)
    local loot = ns.modules.loot
    if not (loot and loot.Parse) then return end
    local link, id, quality, _, kind = loot.Parse(msg)
    if link and quality and quality >= 2 then self:Looted(link, id, quality, kind) end
end)

-- A line held back by combat goes out after it, if it is not old.
ns.Every(2, function()
    if not waiting or Held() then return end
    local w = waiting
    waiting = nil
    if time() - w.at <= WAIT_MOST then Say(w.text) end
end, M)

function M:Slash(arg)
    local verb, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    if verb:lower() == "test" then
        local link = rest ~= "" and rest or "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"
        local id = tonumber(link:match("|Hitem:(%d+)")) or 0
        local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
        local quality = ({ ffa335ee = 4, ff0070dd = 3, ff1eff00 = 2, ffff8000 = 5 })[hex and hex:lower() or ""] or 4
        local text = self:Line(link, id, quality, "loot")
        ns.Print(text and ("in guild chat this would say: " .. text) or "that item would not be said with these settings.")
        return
    end
    ns.Print("use /zod shout test, or /zod shout test and a shift-clicked item.")
end

-- For tests: forget what was said.
function M.Forget()
    sent, said, waiting = {}, {}, nil
end
