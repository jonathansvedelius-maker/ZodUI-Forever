local ADDON, ns = ...
local T = ns.T

-- Items: what every character carries and has in the bank, in one searchable
-- list. Bags are read as they change; the bank can only be read while its
-- window is open, so its numbers are from the last visit.

local M = ns:NewModule("items", {
    title = "Items",
    desc = "Remembers what each character carries and has in the bank, so you can search all of them at once. The bank is read when you open it.",
    defaults = { enabled = true },
})

local QUALITY_HEX = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }
local MAX_ROWS = 300
local dirty, bankOpen
local filter = ""
local mineOnly, byCount = false, false

local function CarriedBags()
    local list = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do list[#list + 1] = bag end
    return list
end

-- The bank is tabs on this client; the numbered bank bags are the older layout.
local function BankBags()
    local list = {}
    local index = Enum and Enum.BagIndex
    if index and index.CharacterBankTab_1 then
        for i = 0, 5 do list[#list + 1] = index.CharacterBankTab_1 + i end
    else
        list[1] = BANK_CONTAINER or -1
        for i = 1, NUM_BANKBAGSLOTS or 7 do list[#list + 1] = (NUM_BAG_SLOTS or 4) + i end
    end
    return list
end

local function Remember(info)
    local names = ns.db.itemNames
    local known = names[info.itemID]
    if known and known.name then return end
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    local name, _, quality
    if get and info.hyperlink then name, _, quality = get(info.hyperlink) end
    name = name or (type(info.hyperlink) == "string" and info.hyperlink:match("%[(.-)%]"))
    if name then names[info.itemID] = { name = name, q = quality or info.quality or 1 } end
end

-- Counts what is in `bags` and writes it to this character's record as `field`
-- ("bags" or "bank"), leaving the other field alone.
local function Count(bags, field)
    local seen = {}
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                seen[info.itemID] = (seen[info.itemID] or 0) + (info.stackCount or 1)
                Remember(info)
            end
        end
    end
    local items = ns.char.items
    for id, rec in pairs(items) do
        rec[field] = seen[id]
        seen[id] = nil
        if not rec.bags and not rec.bank then items[id] = nil end
    end
    for id, n in pairs(seen) do items[id] = { [field] = n } end
end

local function Scan()
    if not dirty then return end
    dirty = false
    Count(CarriedBags(), "bags")
    if bankOpen then Count(BankBags(), "bank") end
    ns.Refresh()
end

function M:OnEnable()
    if not (C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerNumSlots) then
        self.unsupported = true
        return
    end
    ns.db.itemNames = ns.db.itemNames or {}
    ns.char.items = ns.char.items or {}
    dirty = true
end

M:On("BAG_UPDATE_DELAYED", function() dirty = true end)
M:On("PLAYERBANKSLOTS_CHANGED", function() dirty = true end)
M:On("BANKFRAME_OPENED", function() bankOpen, dirty = true, true end)
M:On("BANKFRAME_CLOSED", function() bankOpen = false end)

ns.Every(1, function()
    if not M.unsupported then Scan() end
end, M)

-- What the other characters have of an item: { { name, class, bags, bank } ... }, most first.
function M:Others(id)
    local list = {}
    for key, char in pairs(ns.db.chars) do
        local rec = key ~= ns.charKey and char.items and char.items[id]
        if rec then
            list[#list + 1] = { name = char.name or key, class = char.class, bags = rec.bags or 0, bank = rec.bank or 0 }
        end
    end
    table.sort(list, function(a, b)
        local x, y = a.bags + a.bank, b.bags + b.bank
        if x ~= y then return x > y end
        return a.name < b.name
    end)
    return list
end

-- "12" or "12 (5 in the bank)".
function M.CountText(bags, bank)
    local text = tostring(bags + bank)
    if bank > 0 then text = text .. " |cff999999(" .. bank .. " in the bank)|r" end
    return text
end

-- Every known item with who has it, filtered by a part of its name.
local function Rows(part)
    local byId, chars = {}, 0
    for key, char in pairs(ns.db.chars) do
        if char.items and next(char.items) and (not mineOnly or key == ns.charKey) then
            chars = chars + 1
            for id, rec in pairs(char.items) do
                local entry = byId[id]
                if not entry then
                    entry = { id = id, total = 0, who = {} }
                    byId[id] = entry
                end
                local bags, bank = rec.bags or 0, rec.bank or 0
                entry.total = entry.total + bags + bank
                entry.who[#entry.who + 1] = { name = char.name or key, class = char.class, bags = bags, bank = bank,
                    me = key == ns.charKey }
            end
        end
    end
    local rows, kinds = {}, 0
    for id, entry in pairs(byId) do
        kinds = kinds + 1
        local known = ns.db.itemNames[id]
        local name = known and known.name or ("Item " .. id)
        if part == "" or name:lower():find(part, 1, true) then
            table.sort(entry.who, function(a, b)
                if a.me ~= b.me then return a.me end
                return a.name < b.name
            end)
            local where = {}
            for _, w in ipairs(entry.who) do
                where[#where + 1] = "|c" .. ns.ClassHex(w.class) .. w.name .. "|r " .. M.CountText(w.bags, w.bank)
            end
            rows[#rows + 1] = { "|c" .. (QUALITY_HEX[known and known.q or 1] or "ffffffff") .. name .. "|r", ns.Comma(entry.total),
                table.concat(where, ",  "), sort = name:lower(), total = entry.total, data = { name = name, id = id } }
        end
    end
    table.sort(rows, function(a, b)
        if byCount and a.total ~= b.total then return a.total > b.total end
        return a.sort < b.sort
    end)
    return rows, kinds, chars
end

function M:Find(part, add, has)
    if self.unsupported then return end
    local totals = {}
    for _, char in pairs(ns.db.chars) do
        for id, rec in pairs(char.items or {}) do totals[id] = (totals[id] or 0) + (rec.bags or 0) + (rec.bank or 0) end
    end
    local found = {}
    for id, total in pairs(totals) do
        local known = ns.db.itemNames[id]
        if known and has(known.name) then found[#found + 1] = { known.name, total } end
    end
    table.sort(found, function(a, b) return a[1] < b[1] end)
    for _, item in ipairs(found) do add("Item", item[1], ns.Comma(item[2]) .. " across your characters", "items", item[1]) end
end

ns.AddPage({
    key = "items", title = "Items", order = 32, group = "All characters", module = "items",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Items module is off. Switch it on under Settings.")
        page.search = T.Edit(f, 240, 24)
        page.search.clearOnEscape = true
        page.search:SetPoint("TOPLEFT", 0, 0)
        page.search.edit:SetMaxLetters(40)
        page.search.edit:SetScript("OnTextChanged", function(self)
            local text = (self:GetText() or ""):lower()
            if text ~= filter then
                filter = text
                page:Refresh()
            end
        end)
        page.hint = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.hint:SetPoint("LEFT", page.search, "RIGHT", 10, 0)
        -- Up to two lines in the room before the buttons on the right.
        page.hint:SetPoint("RIGHT", page.search, "RIGHT", 10 + (ns.PAGE_W - 240 - 120 - 6 - 100 - 10 - 10), 0)
        page.hint:SetHeight(24)
        page.hint:SetJustifyV("MIDDLE")
        mineOnly, byCount = M.db.mineOnly or false, M.db.byCount or false -- kept across /reload
        page.mine = T.Button(f, "This character", 120, function()
            mineOnly = not mineOnly
            M.db.mineOnly = mineOnly or nil
            page:Refresh()
        end)
        page.mine:SetPoint("TOPRIGHT", 0, 0)
        page.sortBy = T.Button(f, "Most first", 100, function()
            byCount = not byCount
            M.db.byCount = byCount or nil
            page:Refresh()
        end)
        page.sortBy:SetPoint("RIGHT", page.mine, "LEFT", -6, 0)
        page.list = T.Table(f, { { "Item", 230 }, { "Total", 60, "RIGHT" }, { "Who has it", w - 310 } }, w, ns.PAGE_H - 34)
        page.list:SetPoint("TOPLEFT", 0, -34)
        page.list.itemOf = function(d) return d.name end -- Alt-click: Codex Forever
        page.list.linkOf = function(d) return "item:" .. d.id end -- its tooltip, and shift-click links it
    end,
    Refresh = function(page, arg)
        if arg then -- opened from the search with an item's name
            filter = arg:lower()
            page.search.edit:SetText(arg)
        end
        local on = M.enabled and not M.unsupported
        page.off:SetShown(not on)
        page.search:SetShown(on)
        page.hint:SetShown(on)
        page.list:SetShown(on)
        page.mine:SetShown(on)
        page.sortBy:SetShown(on)
        if not on then return end
        page.mine.label:SetText(mineOnly and "All characters" or "This character")
        page.sortBy.label:SetText(byCount and "A to Z" or "Most first")
        page.mine.tip = mineOnly and "Now: only what this character has. Click for every character." or "Now: every character. Click for only this one."
        page.sortBy.tip = byCount and "Now: the most first. Click for A to Z." or "Now: A to Z. Click for the most first."
        local rows, kinds, chars = Rows(filter)
        local found = #rows
        for i = #rows, MAX_ROWS + 1, -1 do rows[i] = nil end
        if filter == "" then
            page.hint:SetText("Type part of a name to search. " .. ns.Comma(kinds) .. " different item" .. (kinds == 1 and "" or "s")
                .. " on " .. chars .. " character" .. (chars == 1 and "" or "s") .. ".")
        elseif found > MAX_ROWS then
            page.hint:SetText(ns.Comma(found) .. " match. The first " .. MAX_ROWS .. " are shown.")
        else
            page.hint:SetText(found .. (found == 1 and " item matches." or " items match."))
        end
        page.list:SetRows(rows, filter == "" and "Nothing counted yet. Bags are read as they change, the bank when you open it."
            or "No character has an item with that in its name.")
    end,
})
