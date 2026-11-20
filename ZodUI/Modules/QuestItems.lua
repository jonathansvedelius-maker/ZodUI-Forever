local ADDON, ns = ...

-- Quest items: the items a quest still asks for are never sold by Vendor, and their
-- tooltip says which quest wants them. Two sources:
--   * the quest log: every item objective of a quest in it, done or not (a finished
--     objective still has to be handed in);
--   * Undead Route, when it is installed: the items its class quests ask for before
--     you have the quest, such as Whitestone Oak Lumber for A Moon-Kissed Blade.
-- Items are matched by name, the only thing both sources give.

local M = ns:NewModule("questitems", {
    title = "Quest items",
    desc = "Vendor never sells an item a quest in your log still asks for, or one Undead Route's class quests will need; its tooltip says which quest wants it.",
    defaults = { enabled = true, keep = true, tooltip = true, route = true },
    options = {
        { type = "check", key = "keep", label = "Vendor never sells them, even from the always-sell list" },
        { type = "check", key = "tooltip", label = "Say in the tooltip which quest wants the item" },
        { type = "check", key = "route", label = "Count the items Undead Route's class quests will ask for" },
    },
})

local cache -- lower-case name -> list of { quest, have, need, later }

-- "Linen Cloth: 3/10", or "3/10 Linen Cloth" in some languages.
function M.ParseObjective(text)
    if type(text) ~= "string" then return nil end
    local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
    if not name then have, need, name = text:match("^(%d+)%s*/%s*(%d+)%s+(.+)$") end
    if not name or name == "" then return nil end
    return name, tonumber(have), tonumber(need)
end

local function Add(map, name, entry)
    local key = name:lower()
    map[key] = map[key] or {}
    for _, e in ipairs(map[key]) do
        if e.quest == entry.quest then return end
    end
    table.insert(map[key], entry)
end

function M:Build()
    local map = {}
    local log = C_QuestLog
    if log and log.GetNumQuestLogEntries and log.GetInfo and log.GetQuestObjectives then
        local n = log.GetNumQuestLogEntries() or 0
        for i = 1, n do
            local info = log.GetInfo(i)
            if info and not info.isHeader and info.questID then
                for _, o in ipairs(log.GetQuestObjectives(info.questID) or {}) do
                    if o.type == "item" then
                        local name, have, need = M.ParseObjective(o.text)
                        if name then
                            Add(map, name, { quest = info.title or ("Quest " .. info.questID),
                                have = tonumber(o.numFulfilled) or have, need = tonumber(o.numRequired) or need })
                        end
                    end
                end
            end
        end
    end
    if self.db.route and type(UndeadRoute) == "table" and type(UndeadRoute.NeededItems) == "function" then
        local ok, list = pcall(UndeadRoute.NeededItems)
        if ok and type(list) == "table" then
            for _, item in ipairs(list) do
                if type(item) == "table" and type(item.name) == "string" and type(item.quest) == "string" then
                    Add(map, item.name, { quest = item.quest, later = true })
                end
            end
        end
    end
    cache = map
    return map
end

-- The quests that want an item, by its name; nil when none does.
function M:For(name)
    if not self.enabled or type(name) ~= "string" then return nil end
    local list = (cache or self:Build())[name:lower()]
    return list and #list > 0 and list or nil
end

local function ItemName(id)
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    local name = get and id and get(id)
    return type(name) == "string" and name or nil
end

-- Whether Vendor must leave this item alone.
function M:Keeps(id, name)
    if not (self.enabled and self.db.keep) then return nil end
    return self:For(name or ItemName(id))
end

function M:ItemTooltip(tip, id)
    if not self.db.tooltip then return end
    local list = self:For(ItemName(id))
    if not list then return end
    for _, e in ipairs(list) do
        local count = (e.have and e.need) and string.format(" (%d/%d)", e.have, e.need) or ""
        tip:AddLine((e.later and "Needed later for " or "Needed for ") .. e.quest .. count, 1, 0.82, 0)
    end
end

-- The log changes in bursts; the list is built again when it is next asked for.
local function Stale() cache = nil end
M:On("QUEST_LOG_UPDATE", Stale)
M:On("QUEST_ACCEPTED", Stale)
M:On("QUEST_TURNED_IN", Stale)

function M:OnEnable() cache = nil end
function M:OnOption() cache = nil end

