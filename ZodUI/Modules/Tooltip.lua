local ADDON, ns = ...

-- Tooltips: adds what the game leaves out: how many of an item you own, whether
-- Vendor will sell it, its item level and your goal for it. Item and spell ids
-- are NaowhForever_QoL's (Global Copy).

local M = ns:NewModule("tooltip", {
    title = "Tooltips",
    desc = "Adds to item tooltips how many you and your other characters have, the item level, your goal for it and whether the Vendor module will sell it; shows whom a player or creature is targeting.",
    defaults = { enabled = true, count = true, alts = true, junk = true, ilvl = true, target = true, goal = true },
    options = {
        { type = "check", key = "count", label = "How many you own (bags and bank)" },
        { type = "check", key = "alts", label = "How many your other characters have (needs the Items module)" },
        { type = "check", key = "junk", label = "Mark grey items the Vendor module will sell" },
        { type = "check", key = "ilvl", label = "The item level of gear" },
        { type = "check", key = "goal", label = "Your goal for the item (needs the Goals module)" },
        { type = "check", key = "target", label = "Whom a player or creature is targeting" },
        { type = "note", text = "NaowhForever_QoL can count items in tooltips too. Next to it the two count lines start unticked, so nothing is said twice.", lines = 2 },
    },
})

local hooked

local function Ours(tip)
    return tip == GameTooltip or tip == ItemRefTooltip
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function Item(tip, data)
    if not M.enabled or not Ours(tip) or not data then return end
    local id = data.id
    if not id or Secret(id) then return end
    if M.db.count then
        local count = C_Item and C_Item.GetItemCount or GetItemCount
        if count then
            local carried, all = count(id) or 0, count(id, true) or 0
            if all > 0 then
                local text = carried .. (all > carried and (" |cff999999(+" .. (all - carried) .. " in the bank)|r") or "")
                tip:AddDoubleLine("You have", text, 0.6, 0.6, 0.6, 1, 1, 1)
            end
        end
    end
    if M.db.alts then
        local items = ns.modules.items
        if items and items.enabled and not items.unsupported then
            for _, other in ipairs(items:Others(id)) do
                tip:AddDoubleLine("|c" .. ns.ClassHex(other.class) .. other.name .. "|r", items.CountText(other.bags, other.bank),
                    1, 1, 1, 1, 1, 1)
            end
        end
    end
    if M.db.junk then
        local vendor = ns.modules.vendor
        local get = C_Item and C_Item.GetItemInfo or GetItemInfo
        if vendor and vendor.enabled and vendor.db.sellJunk and get then
            local _, _, quality, _, _, _, _, _, _, _, price = get(id)
            local quests = ns.modules.questitems
            if quality == 0 and (price or 0) > 0 and not (quests and quests:Keeps(id)) then
                tip:AddLine("ZodUI sells this at the next merchant.", 0.6, 0.6, 0.6)
            end
        end
    end
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if M.db.ilvl and get then
        local _, _, _, level, _, _, _, _, equip = get(id)
        if level and level > 0 and type(equip) == "string" and equip ~= "" then
            tip:AddDoubleLine("Item level", tostring(level), 0.6, 0.6, 0.6, 1, 1, 1)
        end
    end
    if M.db.goal then
        local goals = ns.modules.goals
        local count = C_Item and C_Item.GetItemCount or GetItemCount
        if goals and goals.enabled and count then
            for _, goal in ipairs(ns.chardb.goals or {}) do
                if goal.id == id then
                    local have = count(id, goals.db.bank and true or false) or 0
                    tip:AddDoubleLine("Goal", ns.Comma(have) .. " / " .. ns.Comma(goal.want), 0.6, 0.6, 0.6, 1, 0.82, 0)
                end
            end
        end
    end
    -- Lines from other modules: M:ItemTooltip(tip, itemID) on any module that is on.
    for _, m in ipairs(ns.order) do
        if m ~= M and m.enabled and m.ItemTooltip then
            m.tipLabel = m.tipLabel or (m.key .. " tooltip")
            ns.Run(m.tipLabel, m.ItemTooltip, m, tip, id)
        end
    end
end

-- A player's or creature's tooltip: whom it is targeting.
local function Targeting(tip)
    local name = UnitName and UnitName("mouseovertarget")
    if Secret(name) or not name then return end
    local me = UnitIsUnit and UnitIsUnit("mouseovertarget", "player")
    if Secret(me) then return end
    tip:AddDoubleLine("Targeting", me and "|cffff6060You|r" or name, 0.6, 0.6, 0.6, 1, 1, 1)
end

local function Unit(tip, data)
    if not M.enabled or tip ~= GameTooltip or not data then return end
    if M.db.target then Targeting(tip) end
    -- Lines from other modules: M:UnitTooltip(tip) on any module that is on (the unit is "mouseover").
    for _, m in ipairs(ns.order) do
        if m ~= M and m.enabled and m.UnitTooltip then
            m.tipLabel = m.tipLabel or (m.key .. " tooltip")
            ns.Run(m.tipLabel, m.UnitTooltip, m, tip)
        end
    end
end

function M:OnEnable()
    if self.db.naowh == nil then -- decided once, so ticking them again sticks
        self.db.naowh = ns.AddOnLoaded("NaowhForever_QoL") and true or false
        if self.db.naowh then self.db.count, self.db.alts = false, false end
    end
    if hooked then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.Timed("tooltip item", Item))
        if Enum.TooltipDataType.Unit then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ns.Timed("tooltip unit", Unit)) end
    else
        self.unsupported = true
    end
end
