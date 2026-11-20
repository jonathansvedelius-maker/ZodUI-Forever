local ADDON, ns = ...

-- Vendor: sells grey items and repairs when a merchant window opens.
-- Holding Shift while opening the merchant skips both.

local M = ns:NewModule("vendor", {
    title = "Vendor",
    desc = "Sells your grey items and repairs your gear when you open a merchant, from the guild bank when your guild lets you. Hold Shift while you open the merchant to skip it that once.",
    defaults = { enabled = true, sellJunk = true, repair = true, guildRepair = true, report = true, sell = {}, keep = {} },
    -- Both sell grey items and repair at a merchant; next to them this module starts off (asked once
    -- more on setups from before 0.28.0), so nothing is sold twice. Switching it on again keeps it on.
    conflicts = { "NaowhForever_QoL", "EllesmereUIQoL" },
    recheck = 1,
    options = {
        { type = "check", key = "sellJunk", label = "Sell grey items" },
        { type = "check", key = "repair", label = "Repair all gear" },
        { type = "check", key = "guildRepair", label = "Let the guild bank pay for the repair when it may" },
        { type = "check", key = "report", label = "Say in chat what was sold and what the repair cost" },
        { type = "note", text = "/zod vendor sell <item> sells an item of any colour too; /zod vendor keep <item> never sells a grey one. /zod vendor list shows both.", lines = 2 },
    },
})

local BATCH = 6 -- items per step: a merchant drops sales that arrive all at once
local open, queue, sold, earned, allGrey
local kept = {} -- names a quest wants, left unsold at this merchant

local function SellPrice(link)
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not (get and link) then return 0 end
    return select(11, get(link)) or 0
end

local function Junk()
    local list = {}
    if not (C_Container and C_Container.GetContainerItemInfo) then return list end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            local wanted = info and ((info.quality == 0 and not M.db.keep[id]) or M.db.sell[id])
            local quests = wanted and ns.modules.questitems
            if quests then
                local get = C_Item and C_Item.GetItemInfo or GetItemInfo
                local name = info.itemName or (get and get(id))
                if quests:Keeps(id, name) then
                    wanted = false
                    kept[name or ("item " .. id)] = true
                end
            end
            if wanted and not info.hasNoValue and not info.isLocked then
                local price = SellPrice(info.hyperlink)
                if price > 0 then
                    list[#list + 1] = { bag = bag, slot = slot, value = price * (info.stackCount or 1), grey = info.quality == 0 }
                end
            end
        end
    end
    return list
end

local repairAfter -- a repair waiting for the junk to be sold
local Repair -- below

local function SellStep()
    if not (open and queue) then return end
    for _ = 1, BATCH do
        local item = table.remove(queue)
        if not item then break end
        C_Container.UseContainerItem(item.bag, item.slot)
        sold, earned = sold + 1, earned + item.value
        if not item.grey then allGrey = false end
    end
    if #queue > 0 then
        ns.After(0.25, SellStep)
    else
        queue = nil
        if repairAfter then -- the junk's gold is in: now the repair can use it
            repairAfter = false
            ns.After(0.5, function() if open then Repair() end end)
        end
        if M.db.report and sold > 0 then
            ns.Print("sold " .. sold .. (allGrey and " grey item" or " item") .. (sold == 1 and "" or "s") .. " for " .. ns.Money(earned) .. ".")
        end
    end
end

-- Whether the guild bank may and can pay `cost`. A withdraw limit of -1 means no limit.
local function GuildPays(cost)
    if not (IsInGuild and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()) then return false end
    local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
    if type(limit) == "number" and limit >= 0 and limit < cost then return false end
    local bank = GetGuildBankMoney and GetGuildBankMoney()
    if type(bank) == "number" and bank > 0 and bank < cost then return false end
    return true
end

function Repair() -- the local declared above SellStep
    if not (CanMerchantRepair and CanMerchantRepair() and GetRepairAllCost and RepairAllItems) then return end
    local cost, needed = GetRepairAllCost()
    if not needed or not cost or cost <= 0 then return end
    if M.db.guildRepair and GuildPays(cost) then
        RepairAllItems(true)
        if M.db.report then ns.Print("the guild bank repaired your gear for " .. ns.Money(cost) .. ".") end
        return
    end
    if GetMoney() < cost then
        ns.Print("not enough gold to repair: it costs " .. ns.Money(cost) .. ".")
        return
    end
    RepairAllItems()
    if M.db.report then ns.Print("repaired for " .. ns.Money(cost) .. ".") end
end

M:On("MERCHANT_SHOW", function(self)
    open = true
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    -- Sell the junk first, then repair: the grey items may pay for what the repair would have been short of.
    repairAfter = self.db.repair and self.db.sellJunk
    if self.db.repair and not self.db.sellJunk then Repair() end
    if self.db.sellJunk then
        kept = {}
        queue, sold, earned, allGrey = Junk(), 0, 0, true
        local names = {}
        for name in pairs(kept) do names[#names + 1] = name end
        if self.db.report and #names > 0 then
            table.sort(names)
            ns.Print("kept " .. table.concat(names, ", ") .. ": a quest needs " .. (#names == 1 and "it." or "them."))
        end
        SellStep()
    end
end)

M:On("MERCHANT_CLOSED", function()
    open, queue = false, nil
end)

local function Named(list)
    local names = {}
    for id in pairs(list) do
        local known = ns.db.itemNames and ns.db.itemNames[id]
        names[#names + 1] = known and known.name or ("item " .. id)
    end
    table.sort(names)
    return #names > 0 and table.concat(names, ", ") or "nothing"
end

-- /zod vendor sell <item>, keep <item>, forget <item>, list
function M:Slash(arg)
    local word, rest = arg:match("^(%S*)%s*(.-)$")
    word = word:lower()
    if word == "" then
        ns.Show("settings", "vendor")
    elseif word == "list" then
        ns.Print("always sold: " .. Named(self.db.sell) .. ". Never sold: " .. Named(self.db.keep) .. ".")
    elseif (word == "sell" or word == "keep" or word == "forget") and rest ~= "" then
        if not ns.ResolveItem then return end
        local id, name = ns.ResolveItem(rest) -- "a and f()" would keep only f's first value
        if not id then
            ns.Print(name or "that item is not known.")
            return
        end
        self.db.sell[id], self.db.keep[id] = nil, nil
        if word == "sell" then
            self.db.sell[id] = true
            ns.Print(name .. " is sold at every merchant from now on.")
        elseif word == "keep" then
            self.db.keep[id] = true
            ns.Print(name .. " is never sold.")
        else
            ns.Print(name .. " is back to the usual rule: sold when it is grey.")
        end
    else
        ns.Print("use /zod vendor sell <item>, /zod vendor keep <item>, /zod vendor forget <item> or /zod vendor list.")
    end
end
