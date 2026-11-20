local ADDON, ns = ...
local T = ns.T

-- Loot: what you picked up this session and what a merchant would pay for it.
-- Like the session it carries over a /reload or a quick relog.

local M = ns:NewModule("loot", {
    title = "Loot log",
    desc = "Lists the items you looted this session, how many, and what they are worth at a merchant.",
    defaults = { enabled = true, minQuality = 0, alert = 3 },
    options = {
        { type = "cycle", key = "alert", label = "A notice when you loot", choices = { { 0, "Never" }, { 2, "Green and better" },
            { 3, "Blue and better" }, { 4, "Purple and better" } } },
        { type = "cycle", key = "minQuality", label = "List", choices = { { 0, "Everything" }, { 1, "White and better" },
            { 2, "Green and better" }, { 3, "Blue and better" } } },
        { type = "button", label = "This session's loot", text = "Clear", click = function(m) m:Reset() end },
    },
})

local RESUME = 600
local QUALITY_HEX = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }
local HEX_QUALITY = {}
for q, hex in pairs(QUALITY_HEX) do HEX_QUALITY[hex] = q end
local FINDS = 50 -- green and better items kept across sessions
local log
local patterns
local showFinds = false

-- "You receive loot: %s." becomes a pattern that captures the link, and the count where there is one.
local function Pattern(format)
    local p = format:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2") -- set aside before the escaping below
    p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end

-- The patterns, and beside them how the item came: "loot", "pushed" (a quest reward, a mail) or "created" (made).
local kinds
local function Patterns()
    local list = {}
    kinds = {}
    for _, name in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
        "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_CREATED_SELF" }) do
        local format = _G[name]
        if type(format) == "string" then
            list[#list + 1] = Pattern(format)
            kinds[#list] = name:find("PUSHED", 1, true) and "pushed" or (name:find("CREATED", 1, true) and "created" or "loot")
        end
    end
    if #list == 0 then
        list = { "^You receive loot: (.+)x(%d+)%.$", "^You receive item: (.+)x(%d+)%.$", "^You receive loot: (.+)%.$",
            "^You receive item: (.+)%.$" }
        kinds = { "loot", "pushed", "loot", "pushed" }
    end
    return list
end


-- One loot line read: link, item id, quality (from the link's colour, nil when unknown), count and how it came;
-- nil for a line that is not your own loot. Loot shout (Modules\Shout.lua) reads loot with it too.
function M.Parse(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return nil end
    patterns = patterns or Patterns()
    for i, pattern in ipairs(patterns) do
        local link, count = msg:match(pattern)
        if link then
            if count and count:find("|H", 1, true) then link, count = count, link end -- a language that puts the count first
            local id = tonumber(link:match("|Hitem:(%d+)"))
            if not id then return nil end
            local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
            return link, id, hex and HEX_QUALITY[hex:lower()], tonumber(count) or 1, kinds[i] or "loot"
        end
    end
end

function M:Reset()
    log = { last = time(), start = time(), items = {} }
    ns.chardb.loot = log
    ns.Refresh()
end

function M:OnEnable()
    patterns = patterns or Patterns()
    log = ns.chardb.loot
    if not log or time() - (log.last or 0) > RESUME then self:Reset() end
    log.start = log.start or time()
    ns.chardb.finds = ns.chardb.finds or {}
end

ns.Every(10, function()
    if log then log.last = time() end
end, M)

M:On("CHAT_MSG_LOOT", function(_, _, msg)
    -- The link's colour tells the quality before the game has the item's details.
    local link, id, quality, count = M.Parse(msg)
    if not link then return end
    local entry = log.items[id]
    if not entry then
        entry = { name = link:match("|h%[(.-)%]|h") or ("Item " .. id), count = 0 }
        log.items[id] = entry
    end
    entry.count = entry.count + count
    log.last = time()
    if quality then
        if quality >= 2 then
            local finds = ns.chardb.finds
            table.insert(finds, 1, { at = time(), id = id, name = entry.name, q = quality,
                where = GetRealZoneText and GetRealZoneText() or "" })
            while #finds > FINDS do table.remove(finds) end
        end
        local at = M.db.alert or 0
        if at > 0 and quality >= at then ns.Alert("Loot: |c" .. QUALITY_HEX[quality] .. entry.name .. "|r") end
    end
    ns.Refresh()
end)

-- Quality and merchant price, filled in when the game knows the item.
local function Info(id, entry)
    if entry.quality and entry.price then return end
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not get then return end
    local _, _, quality, _, _, _, _, _, _, _, price = get(id)
    if quality then entry.quality, entry.price = quality, price or 0 end
end

-- Rows for the table, best first, and the totals.
function M:Summary(minQuality)
    local rows, pieces, value, best = {}, 0, 0, nil
    for id, entry in pairs(log and log.items or {}) do
        Info(id, entry)
        local quality, price = entry.quality or 1, entry.price or 0
        pieces = pieces + entry.count
        value = value + price * entry.count
        if not best or quality > (best.quality or 1) then best = entry end
        if quality >= (minQuality or 0) then
            rows[#rows + 1] = { "|c" .. (QUALITY_HEX[quality] or "ffffffff") .. entry.name .. "|r", entry.count,
                price > 0 and ns.Money(price) or "-", price > 0 and ns.Money(price * entry.count) or "-",
                quality = quality, value = price * entry.count, name = entry.name, id = id }
        end
    end
    table.sort(rows, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.value ~= b.value then return a.value > b.value end
        return a.name < b.name
    end)
    return rows, pieces, value, best
end

function M:Card()
    local _, pieces, value, best = self:Summary()
    return {
        title = "Loot this session",
        lines = {
            { "Items", pieces },
            { "Worth at a merchant", ns.Money(value) },
            { "Best", best and ("|c" .. (QUALITY_HEX[best.quality or 1] or "ffffffff") .. best.name .. "|r") or "-" },
        },
        button = { "List", function() ns.Show("loot") end },
    }
end

ns.AddPage({
    key = "loot", title = "Loot", order = 15, group = "This character", module = "loot",
    Build = function(page, f)
        local w = ns.PAGE_W
        page.off = T.Text(f, "GameFontHighlightSmall", T.MUTED)
        page.off:SetPoint("TOPLEFT", 0, -4)
        page.off:SetText("The Loot log module is off. Switch it on under Settings.")
        page.total = T.Text(f, "GameFontNormal")
        page.total:SetPoint("TOPLEFT", 0, -4)
        page.list = T.Table(f, { { "Item", w - 380 }, { "Count", 70, "RIGHT" }, { "Each", 150, "RIGHT" }, { "Worth", 150, "RIGHT" } },
            w, ns.PAGE_H - 62)
        page.list:SetPoint("TOPLEFT", 0, -28)
        page.list.itemOf = function(d) return d.name end -- Alt-click: Codex Forever
        page.list.linkOf = function(d) return d.id and ("item:" .. d.id) end -- its tooltip, and shift-click links it
        page.search = T.Edit(f, 180, 24)
        page.search.clearOnEscape = true
        page.search:SetPoint("TOPLEFT", w - 180, 0)
        page.search.edit:SetMaxLetters(30)
        page.search.hint = T.Text(page.search, "GameFontHighlightSmall", T.MUTED)
        page.search.hint:SetPoint("LEFT", 8, 0)
        page.search.hint:SetText("Filter by name")
        page.search.edit:SetScript("OnTextChanged", function(self)
            local text = (self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            page.search.hint:SetShown(text == "")
            if text ~= page.filter then
                page.filter = text
                page:Refresh()
            end
        end)
        page.filter = ""
        page.clear = T.Button(f, "Clear the list", 140, function() M:Reset() end)
        page.clear:SetPoint("BOTTOMLEFT", 0, 0)
        page.clear.confirm = "Sure? Click again"
        showFinds = M.db.showFinds or false -- kept across /reload
        page.mode = T.Button(f, "Best finds", 120, function()
            showFinds = not showFinds
            M.db.showFinds = showFinds or nil
            page:Refresh()
        end)
        page.mode:SetPoint("BOTTOMLEFT", 146, 0) -- placed in Refresh: beside Clear, or first when Clear is hidden
        page.finds = T.Table(f, { { "Item", w - 330 }, { "When", 140 }, { "Where", 190 } }, w, ns.PAGE_H - 62)
        page.finds:SetPoint("TOPLEFT", 0, -28)
        page.finds.itemOf = function(d) return d.name end
        page.finds.linkOf = function(d) return d.id and ("item:" .. d.id) end
    end,
    Refresh = function(page)
        local on = M.enabled
        page.off:SetShown(not on)
        page.total:SetShown(on)
        page.list:SetShown(on)
        page.clear:SetShown(on)
        page.search:SetShown(on and not showFinds)
        page.mode:SetShown(on)
        page.finds:SetShown(on and showFinds)
        page.list:SetShown(on and not showFinds)
        page.clear:SetShown(on and not showFinds)
        page.mode:ClearAllPoints()
        page.mode:SetPoint("BOTTOMLEFT", showFinds and 0 or 146, 0)
        if not on then return end
        page.mode.label:SetText(showFinds and "This session" or "Best finds")
        page.mode.tip = showFinds and "Now: the best finds of every session. Click for this session's loot." or "Now: this session's loot. Click for the best finds of every session."
        if showFinds then
            local rows = {}
            for _, find in ipairs(ns.chardb.finds or {}) do
                rows[#rows + 1] = { "|c" .. (QUALITY_HEX[find.q] or "ffffffff") .. find.name .. "|r", ns.WhenCell(find.at), find.where or "",
                    data = { name = find.name, id = find.id } }
            end
            page.total:SetText("|cffffffffBest finds:|r green and better, newest first" .. ns.Codex.Hint())
            page.finds:SetRows(rows, "Green and better items you loot from now on are kept here.")
            return
        end
        local rows, pieces, value = M:Summary(M.db.minQuality)
        local filter = page.filter
        if filter ~= "" then
            local kept = {}
            for _, row in ipairs(rows) do
                if row.name:lower():find(filter, 1, true) then kept[#kept + 1] = row end
            end
            rows = kept
        end
        for _, row in ipairs(rows) do row.data = row.data or { name = row.name, id = row.id } end
        local long = time() - (log and log.start or time())
        page.total:SetText("|cffffffff" .. pieces .. " item" .. (pieces == 1 and "" or "s") .. " this session, worth|r " .. ns.Money(value)
            .. " |cffffffffat a merchant|r" .. ((long >= 600 and value > 0) and ("|cff999999, " .. "|r" .. ns.Money(value / long * 3600, true)
            .. " |cffffffffan hour|r") or "") .. ns.Codex.Hint())
        page.list:SetRows(rows, filter ~= "" and "Nothing looted matches." or pieces == 0 and "What you loot from now on is listed here."
            or "Nothing of that quality yet. Settings > Loot log changes what is listed.")
    end,
})
